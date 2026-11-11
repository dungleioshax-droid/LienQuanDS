// DSBridgeESP.inc.mm — shared-page kernel memory reader + AOV hosted overlay.
// Included by DSBridge.mm.
//
// Hạ tầng dùng chung (Fl0rkFF style): vm region cache, shared-page cache qua
// vmmapremotepage, read/write helpers, Mach-O main-image identity. Reader AOV
// nằm ở DSBridgeLienQuan.inc.mm; file này giữ hosted overlay và render loop.

static BOOL ds_debug_user_address(uint64_t address) {
    return address >= 0x100000000ULL && address < 0x300000000000ULL;
}

typedef struct {
    uint64_t start;
    uint64_t end;
    uint64_t entryAddress;
} DSDebugVMRegion;

enum class DSDebugShmemOwner : uint8_t {
    None = 0,
    PUBG = 1,
};

static inline int ds_active_game(void) {
    return 1; // Pure PUBG Mobile
}

// Mapper ownership is confined to ds_bridge_queue. Only the epoch is read by
// the display thread, so publications can reject spans from an old target.
static DSDebugShmemOwner g_debugShmemOwner = DSDebugShmemOwner::None;
static pid_t g_debugShmemPid = 0;
static uint64_t g_debugShmemOwnerVmMap = 0;
static std::atomic<uint64_t> g_debugShmemEpoch(1);

static bool ds_debug_shmem_target_matches(DSDebugShmemOwner owner, pid_t pid,
                                          uint64_t vmMap) {
    return owner != DSDebugShmemOwner::None &&
           g_debugShmemOwner == owner && g_debugShmemPid == pid && pid > 0 &&
           g_debugShmemOwnerVmMap == vmMap && vmMap != 0;
}

static uint64_t ds_debug_shmem_epoch(void) {
    return g_debugShmemEpoch.load(std::memory_order_acquire);
}
static std::vector<DSDebugVMRegion> g_debugVMRegions;
static uint64_t g_debugVMRegionsMap = 0;
static pid_t g_debugVMRegionsPid = 0;
static CFAbsoluteTime g_debugVMRegionsBuiltAt = 0;
static CFAbsoluteTime g_debugVMRegionsLastForcedAt = 0;
static uint32_t g_debugVMRegionEntryCount = 0;
// The vector above is swapped in from a background rebuild queue; every access
// goes through this lock. Generation rejects rebuild results that were started
// before a flush/reset (their entries belong to a dead topology).
static os_unfair_lock g_debugVMRegionsLock = OS_UNFAIR_LOCK_INIT;
static uint64_t g_debugVMRegionsGeneration = 0;
static BOOL g_debugVMRegionsRebuildQueued = NO;

static void ds_debug_vm_regions_reset(void) {
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    g_debugVMRegions.clear();
    g_debugVMRegionsMap = 0;
    g_debugVMRegionsPid = 0;
    g_debugVMRegionsBuiltAt = 0;
    g_debugVMRegionsLastForcedAt = 0;
    g_debugVMRegionEntryCount = 0;
    g_debugVMRegionsGeneration++;
    os_unfair_lock_unlock(&g_debugVMRegionsLock);
}

// Walk the target vm_map entry list into a fresh vector. Runs WITHOUT the
// regions lock so a background queue can absorb the multi-millisecond
// kernel-read burst while the ESP reader keeps using the last good index.
// ds_kread* is mutex-serialized per primitive call, so the reader only ever
// waits one call, never the whole walk.
static BOOL ds_debug_vm_regions_walk(uint64_t vmMap,
                                     std::vector<DSDebugVMRegion> *out,
                                     uint32_t *outEntryCount) {
    if (!vmMap || !off_vm_map_hdr || !off_vm_map_header_links_next ||
        !off_vm_map_header_nentries || !off_vm_map_entry_links_next) {
        return NO;
    }
    std::vector<DSDebugVMRegion> regions;
    uint32_t nentries = 0;
    @try {
        uint64_t header = vmMap + off_vm_map_hdr;
        nentries = ds_kread32(header + off_vm_map_header_nentries);
        uint64_t entry = ds_kreadptr(header + off_vm_map_header_links_next);
        // Long-running game sessions can exceed 9,000 entries after loading
        // gameplay assets. Keep enough headroom to cover the active heap.
        uint32_t limit = MIN(nentries, (uint32_t)16384);
        regions.reserve(limit);
        for (uint32_t index = 0; ds_isvalid(entry) && index < limit; index++) {
            uint64_t range[2] = {0, 0};
            ds_kreadbuf(entry + 0x10, range, sizeof(range));
            if (range[1] > range[0] && ds_debug_user_address(range[0]) &&
                ds_debug_user_address(range[1] - 1)) {
                regions.push_back({range[0], range[1], entry});
            }
            uint64_t next = ds_kreadptr(entry + off_vm_map_entry_links_next);
            if (!ds_isvalid(next) || next == entry) break;
            entry = next;
        }
    } @catch (__unused NSException *exception) {
        return NO;
    }
    if (regions.empty()) return NO;
    out->swap(regions);
    if (outEntryCount) *outEntryCount = nentries;
    return YES;
}

// Synchronous build — attach path only (once per target lifetime), where a
// one-time stall is acceptable and the reader has nothing to show yet anyway.
static BOOL ds_debug_vm_regions_rebuild(uint64_t vmMap, pid_t pid, BOOL forced) {
    (void)forced;
    std::vector<DSDebugVMRegion> regions;
    uint32_t nentries = 0;
    if (!ds_debug_vm_regions_walk(vmMap, &regions, &nentries)) return NO;
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    g_debugVMRegions.swap(regions);
    g_debugVMRegionsMap = vmMap;
    g_debugVMRegionsPid = pid;
    g_debugVMRegionsBuiltAt = CFAbsoluteTimeGetCurrent();
    g_debugVMRegionEntryCount = nentries;
    g_debugVMRegionsGeneration++;
    os_unfair_lock_unlock(&g_debugVMRegionsLock);
    return YES;
}

static dispatch_queue_t ds_debug_regions_queue(void) {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.darkspeed.aov.vmregions",
                                      DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// Hot-path policy: NEVER walk the target vm_map on the reader queue. A large
// map walk can freeze the serial reader for tens-to-hundreds of milliseconds
// when the game maps a fresh region mid-match. A miss fails the current read
// and refreshes the index asynchronously here.
static void ds_debug_vm_regions_request_async(uint64_t vmMap, pid_t pid) {
    if (!vmMap || !pid) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    if (g_debugVMRegionsRebuildQueued ||
        now - g_debugVMRegionsLastForcedAt < 1.0) {
        os_unfair_lock_unlock(&g_debugVMRegionsLock);
        return;
    }
    g_debugVMRegionsRebuildQueued = YES;
    g_debugVMRegionsLastForcedAt = now;
    uint64_t generation = g_debugVMRegionsGeneration;
    os_unfair_lock_unlock(&g_debugVMRegionsLock);

    dispatch_async(ds_debug_regions_queue(), ^{
        std::vector<DSDebugVMRegion> regions;
        uint32_t nentries = 0;
        BOOL ok = ds_debug_vm_regions_walk(vmMap, &regions, &nentries);
        os_unfair_lock_lock(&g_debugVMRegionsLock);
        g_debugVMRegionsRebuildQueued = NO;
        if (ok && generation == g_debugVMRegionsGeneration) {
            g_debugVMRegions.swap(regions);
            g_debugVMRegionsMap = vmMap;
            g_debugVMRegionsPid = pid;
            g_debugVMRegionsBuiltAt = CFAbsoluteTimeGetCurrent();
            g_debugVMRegionEntryCount = nentries;
            g_debugVMRegionsGeneration++;
        }
        os_unfair_lock_unlock(&g_debugVMRegionsLock);
    });
}

// The vm_map walk preserves address order. Binary search keeps a page miss
// from scanning thousands of regions while holding the shared lock.
static int ds_debug_vm_region_index_locked(uint64_t address, uint64_t endAddress) {
    size_t low = 0;
    size_t high = g_debugVMRegions.size();
    while (low < high) {
        size_t mid = low + (high - low) / 2;
        if (g_debugVMRegions[mid].end <= address) low = mid + 1;
        else high = mid;
    }
    if (low >= g_debugVMRegions.size()) return -1;
    const DSDebugVMRegion &region = g_debugVMRegions[low];
    return address >= region.start && endAddress < region.end ? (int)low : -1;
}

static BOOL ds_debug_vm_regions_contains(uint64_t address, uint64_t endAddress) {
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    BOOL found = ds_debug_vm_region_index_locked(address, endAddress) >= 0;
    os_unfair_lock_unlock(&g_debugVMRegionsLock);
    return found;
}

static uint64_t ds_debug_vm_region_entry(uint64_t address, uint64_t endAddress) {
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    int index = ds_debug_vm_region_index_locked(address, endAddress);
    uint64_t entryAddress = index >= 0 ? g_debugVMRegions[(size_t)index].entryAddress : 0;
    os_unfair_lock_unlock(&g_debugVMRegionsLock);
    return entryAddress;
}

static BOOL ds_debug_address_mapped(uint64_t vmMap, uint64_t address, size_t length) {
    if (!vmMap || length == 0 || !ds_debug_user_address(address)) return NO;
    uint64_t endAddress = address + (uint64_t)length - 1ULL;
    if (endAddress < address || !ds_debug_user_address(endAddress)) return NO;
    if (!off_vm_map_hdr || !off_vm_map_header_links_next ||
        !off_vm_map_header_nentries || !off_vm_map_entry_links_next) {
        return YES;
    }

    // Index lookup only. Any miss (stale target or genuinely new region) defers
    // to a background rebuild and fails this frame — the reader must never eat
    // a vm_map walk mid-match.
    BOOL stale;
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    stale = g_debugVMRegionsMap != vmMap ||
            g_debugVMRegionsPid != g_debugShmemPid;
    os_unfair_lock_unlock(&g_debugVMRegionsLock);
    if (stale) {
        ds_debug_vm_regions_request_async(vmMap, g_debugShmemPid);
        return NO;
    }
    if (ds_debug_vm_regions_contains(address, endAddress)) return YES;
    ds_debug_vm_regions_request_async(vmMap, g_debugShmemPid);
    return NO;
}

static void ds_debug_release_shmem(struct vmshmem shmem) {
    // Intentionally leak everything: deallocating the named entry makes the
    // kernel tear down a vm_map_entry we crafted to point at the target's
    // vm_object. If the target already died, that teardown dereferences a
    // freed object → kernel panic (this was the quit-game panic). The leaked
    // port + pinned object cost a few KB each and vanish on reboot.
    (void)shmem;
}

// Release path for when the target process is VERIFIED alive: the crafted
// vm_map_entry teardown then references a live vm_object, which is exactly
// the normal named-entry teardown path — safe. Use this to keep the pinned
// page/port footprint from growing forever across matches and toggles.
static void ds_debug_release_shmem_live(struct vmshmem shmem) {
    if (shmem.localAddress) {
        mach_vm_deallocate(mach_task_self_, shmem.localAddress, PAGE_SIZE);
    }
    if (shmem.port) {
        mach_port_deallocate(mach_task_self_, (mach_port_t)shmem.port);
    }
}

// Kernel proc address of the cached AOV target, set by the attach path.
// Lets the alive check read one word instead of walking the whole allproc
// list (hundreds of KRW round trips) on every flush.
static uint64_t g_debugShmemProc = 0;

// Userspace liveness probe with NO kernel reads. This gate is mandatory
// before any kread of a cached proc address: a cached proc points into the
// proc_task zone, and after the target exits zalloc GC can return the whole
// page to the VM under memory pressure. Reading it then faults inside the
// ICMPv6 copy path -> kernel data abort (panic log: "Zone: proc_task,
// use-after-free"). kill(pid, 0) never dereferences our cached pointer.
static BOOL ds_pid_alive_userspace(pid_t pid) {
    if (pid <= 0) return NO;
    return (kill(pid, 0) == 0 || errno == EPERM) ? YES : NO;
}

// True only when the cached target still resolves to a live proc. The pid
// must be alive in userspace first; only then is one kread of p_pid at the
// cached proc address allowed. A reused slot yields a mismatched pid. Falls
// back to the full walk only when no proc address is cached.
static BOOL ds_debug_target_alive(void) {
    pid_t pid = g_debugShmemPid;
    if (!pid || !ds_is_ready()) return NO;
    if (!ds_pid_alive_userspace(pid)) return NO;
    if (ds_isvalid(g_debugShmemProc) && off_proc_p_pid) {
        return ds_kread32(g_debugShmemProc + off_proc_p_pid) == (uint32_t)pid ? YES : NO;
    }
    uint64_t proc = procbypid(pid);
    return ds_isvalid(proc) ? YES : NO;
}

// Called before any live-release unmap so the reader can drop pins pointing
// into the cache (clears the camera source under its own lock, which is also
// the lock held while memcpy'ing it -> race-free).
static void (*g_debugPreUnmapHook)(void) = NULL;
static void ds_debug_set_pre_unmap_hook(void (*hook)(void)) {
    g_debugPreUnmapHook = hook;
}

// Fl0rkFF-style shared-page cache. vmmapremotepage() performs kernel WRITES
// (vm_object refcount++, crafted zone element) on every call; hundreds of
// those per second while the target mutates its vm_map corrupt kernel zone
// memory and panic the device a few minutes later. Map each page at most once
// per target topology generation; per-tick reads then become plain local
// memcpy. Keep enough mappings for a complete match working set so active
// pages do not churn through repeated evict+remap cycles.
#define DS_DEBUG_SHMEM_SLOTS 2048
static struct {
    uint64_t vmMap;
    uint64_t pageAddress;
    struct vmshmem shmem;
    uint64_t tick;
    uint32_t pinCount;
} g_debugShmemCache[DS_DEBUG_SHMEM_SLOTS];
static uint64_t g_debugShmemTick = 0;
static int g_debugShmemCount = 0;
static std::unordered_map<uint64_t, int> g_debugShmemIndex;

static void ds_debug_shmem_flush_ex(BOOL targetAlive) {
    // Clear every published span even when the dead target's mappings must be
    // leaked. A leaked local address is still the wrong process generation.
    if (g_debugPreUnmapHook) g_debugPreUnmapHook();
    for (int index = 0; index < DS_DEBUG_SHMEM_SLOTS; index++) {
        if (g_debugShmemCache[index].shmem.used) {
            if (targetAlive) {
                ds_debug_release_shmem_live(g_debugShmemCache[index].shmem);
            } else {
                ds_debug_release_shmem(g_debugShmemCache[index].shmem);
            }
        }
        g_debugShmemCache[index].vmMap = 0;
        g_debugShmemCache[index].pageAddress = 0;
        g_debugShmemCache[index].shmem = (struct vmshmem){0};
        g_debugShmemCache[index].tick = 0;
        g_debugShmemCache[index].pinCount = 0;
    }
    g_debugShmemTick = 0;
    g_debugShmemOwner = DSDebugShmemOwner::None;
    g_debugShmemPid = 0;
    g_debugShmemOwnerVmMap = 0;
    g_debugShmemProc = 0;
    g_debugShmemCount = 0;
    g_debugShmemIndex.clear();
    ds_debug_vm_regions_reset();
    g_debugShmemEpoch.fetch_add(1, std::memory_order_acq_rel);
}

// Claiming a different backend/process invalidates every mapping and live span
// from the previous owner. Callers rebuild the VM-region index after a claim.
static bool ds_debug_shmem_claim_target(DSDebugShmemOwner owner, pid_t pid,
                                        uint64_t proc, uint64_t vmMap) {
    if (owner == DSDebugShmemOwner::None || pid <= 0 ||
        !ds_isvalid(proc) || !ds_isvalid(vmMap)) {
        return false;
    }
    if (ds_debug_shmem_target_matches(owner, pid, vmMap)) {
        g_debugShmemProc = proc;
        return true;
    }

    BOOL previousTargetAlive = ds_debug_target_alive();
    ds_debug_shmem_flush_ex(previousTargetAlive);
    g_debugShmemOwner = owner;
    g_debugShmemPid = pid;
    g_debugShmemOwnerVmMap = vmMap;
    g_debugShmemProc = proc;
    return true;
}

static void ds_debug_shmem_release_owner(DSDebugShmemOwner owner,
                                         BOOL targetAlive) {
    if (owner == DSDebugShmemOwner::None || g_debugShmemOwner != owner) return;
    ds_debug_shmem_flush_ex(targetAlive);
}

// UE replaces large parts of its heap while moving between lobby/map worlds.
// The process and vm_map survive, but a user virtual page can now refer to a
// different vm_object. Cached shared mappings are tied to the old object, so
// forget them at a known topology boundary while keeping the current target.
// The target is alive here (same pid, verified this tick), so flush WITH
// release — this is what bounds the pin/leak footprint across matches.
static void ds_debug_shmem_invalidate_target_pages(void) {
    DSDebugShmemOwner targetOwner = g_debugShmemOwner;
    pid_t targetPid = g_debugShmemPid;
    uint64_t targetVmMap = g_debugShmemOwnerVmMap;
    uint64_t targetProc = g_debugShmemProc;
    BOOL alive = ds_debug_target_alive();
    ds_debug_shmem_flush_ex(alive);
    g_debugShmemOwner = targetOwner;
    g_debugShmemPid = targetPid;
    g_debugShmemOwnerVmMap = targetVmMap;
    g_debugShmemProc = targetProc;
}

static uint64_t ds_debug_map_page(uint64_t vmMap, uint64_t pageAddress) {
    if (!ds_isvalid(vmMap) || !ds_debug_user_address(pageAddress)) return 0;
    if (g_debugShmemOwner == DSDebugShmemOwner::None ||
        g_debugShmemOwnerVmMap != vmMap || !g_debugShmemPid) return 0;

    if (g_debugShmemIndex.bucket_count() < DS_DEBUG_SHMEM_SLOTS) {
        g_debugShmemIndex.reserve(DS_DEBUG_SHMEM_SLOTS);
    }
    g_debugShmemTick++;
    auto cached = g_debugShmemIndex.find(pageAddress);
    if (cached != g_debugShmemIndex.end()) {
        int index = cached->second;
        if (index >= 0 && index < g_debugShmemCount &&
            g_debugShmemCache[index].shmem.used &&
            g_debugShmemCache[index].vmMap == vmMap &&
            g_debugShmemCache[index].pageAddress == pageAddress) {
            g_debugShmemCache[index].tick = g_debugShmemTick;
            return g_debugShmemCache[index].shmem.localAddress;
        }
        g_debugShmemIndex.erase(cached);
    }

    // One-time per page: the mapping check plus the vm_object craft. The walk
    // and the kernel writes must not race a dying target — the reader proves
    // the pid at the start of every tick; never map without a live target.
    if (!g_debugShmemPid) return 0;
    if (!ds_debug_address_mapped(vmMap, pageAddress, PAGE_SIZE)) return 0;
    uint64_t entryAddress = ds_debug_vm_region_entry(
        pageAddress, pageAddress + (uint64_t)PAGE_SIZE - 1ULL);
    if (!entryAddress) return 0;

    int slot = -1;
    BOOL appendedSlot = NO;
    if (g_debugShmemCount < DS_DEBUG_SHMEM_SLOTS) {
        slot = g_debugShmemCount++;
        appendedSlot = YES;
    } else {
        uint64_t oldestTick = UINT64_MAX;
        for (int index = 0; index < g_debugShmemCount; index++) {
            if (!g_debugShmemCache[index].shmem.used) {
                slot = index;
                break;
            }
            // Never evict a page with a live display-thread lease.
            if (g_debugShmemCache[index].pinCount != 0) continue;
            if (g_debugShmemCache[index].tick <= oldestTick) {
                oldestTick = g_debugShmemCache[index].tick;
                slot = index;
            }
        }
    }
    if (slot < 0) return 0;

    // Use the entry captured by the region-index pass. Calling the legacy
    // vmmapremotepage() here would walk up to 9,000 kernel entries again for
    // every newly observed pawn/mesh/bone page.
    struct vmshmem shmem = vmmapremotepagefromentry(entryAddress, pageAddress);
    if (!shmem.used || !shmem.localAddress) {
        // The target may have mutated its vm_map after the index was built.
        // Refresh the index in the background rather than re-walking it here
        // on the reader queue; this page maps on a later frame once it lands.
        ds_debug_vm_regions_request_async(vmMap, g_debugShmemPid);
    }
    if (!shmem.used || !shmem.localAddress) {
        if (appendedSlot) g_debugShmemCount--;
        ds_debug_release_shmem(shmem);
        return 0;
    }
    if (g_debugShmemCache[slot].shmem.used) {
        auto indexed = g_debugShmemIndex.find(g_debugShmemCache[slot].pageAddress);
        if (indexed != g_debugShmemIndex.end() && indexed->second == slot) {
            g_debugShmemIndex.erase(indexed);
        }
        // Mid-match churn: the target is alive (attach validated this tick),
        // so actually release the mapping instead of leaking it. Without this,
        // every eviction past 1024 pages pins another vm_object + wired page
        // forever, and the footprint only stops growing at a jetsam/panic.
        ds_debug_release_shmem_live(g_debugShmemCache[slot].shmem);
    }
    g_debugShmemCache[slot].vmMap = vmMap;
    g_debugShmemCache[slot].pageAddress = pageAddress;
    g_debugShmemCache[slot].shmem = shmem;
    g_debugShmemCache[slot].tick = g_debugShmemTick;
    g_debugShmemCache[slot].pinCount = 0;
    g_debugShmemIndex[pageAddress] = slot;
    return shmem.localAddress;
}

// Acquire/release a long-lived page lease for a source published to another
// thread. All calls are bridge-queue confined; a stale-epoch release is a no-op
// because its slot was already cleared by the owner transition.
static uint64_t ds_debug_map_page_pinned(DSDebugShmemOwner owner,
                                         uint64_t vmMap,
                                         uint64_t pageAddress,
                                         uint64_t *epochOut) {
    if (owner == DSDebugShmemOwner::None || g_debugShmemOwner != owner ||
        g_debugShmemOwnerVmMap != vmMap) return 0;
    uint64_t localAddress = ds_debug_map_page(vmMap, pageAddress);
    if (!localAddress) return 0;
    auto cached = g_debugShmemIndex.find(pageAddress);
    if (cached == g_debugShmemIndex.end()) return 0;
    int index = cached->second;
    if (index < 0 || index >= g_debugShmemCount ||
        !g_debugShmemCache[index].shmem.used ||
        g_debugShmemCache[index].vmMap != vmMap ||
        g_debugShmemCache[index].pageAddress != pageAddress ||
        g_debugShmemCache[index].shmem.localAddress != localAddress ||
        g_debugShmemCache[index].pinCount == UINT32_MAX) {
        return 0;
    }
    g_debugShmemCache[index].pinCount++;
    if (epochOut) *epochOut = ds_debug_shmem_epoch();
    return localAddress;
}

static void ds_debug_unpin_page(DSDebugShmemOwner owner, uint64_t vmMap,
                                uint64_t epoch, uint64_t pageAddress) {
    if (owner == DSDebugShmemOwner::None || g_debugShmemOwner != owner ||
        g_debugShmemOwnerVmMap != vmMap ||
        epoch != ds_debug_shmem_epoch()) return;
    auto cached = g_debugShmemIndex.find(pageAddress);
    if (cached == g_debugShmemIndex.end()) return;
    int index = cached->second;
    if (index < 0 || index >= g_debugShmemCount ||
        !g_debugShmemCache[index].shmem.used ||
        g_debugShmemCache[index].vmMap != vmMap ||
        g_debugShmemCache[index].pageAddress != pageAddress ||
        g_debugShmemCache[index].pinCount == 0) return;
    g_debugShmemCache[index].pinCount--;
}

static BOOL ds_debug_read_bytes(uint64_t vmMap, uint64_t address, void *buffer, size_t length) {
    if (!vmMap || !address || !buffer || length == 0) return NO;

    @try {
    uint8_t *dst = (uint8_t *)buffer;
    uint64_t current = address;
    size_t remaining = length;
    const uint64_t pageSize = (uint64_t)PAGE_SIZE;
    const uint64_t pageMask = pageSize - 1ULL;

    while (remaining > 0) {
        if (!ds_debug_user_address(current)) return NO;

        uint64_t pageAddress = current & ~pageMask;
        uint64_t pageOffset = current & pageMask;
        size_t copySize = (size_t)MIN((uint64_t)remaining, pageSize - pageOffset);

        // Cached page mapping: no per-read vm_map walk, no kernel writes.
        uint64_t localPage = ds_debug_map_page(vmMap, pageAddress);
        if (!localPage) return NO;

        memcpy(dst, (const void *)(uintptr_t)(localPage + pageOffset), copySize);

        dst += copySize;
        current += copySize;
        remaining -= copySize;
    }

    return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

// Write counterpart of ds_debug_read_bytes. The shared-page mapping is created
// with VM_PROT_ALL, so RW heap pages of the target are writable straight
// through the local alias. Bridge-queue callers only; a read-only or unmapped
// page just fails the copy (or, for a genuinely RO object, must be caught by
// the caller's read-back verify).
static BOOL ds_debug_write_bytes(uint64_t vmMap, uint64_t address, const void *buffer, size_t length) {
    if (!vmMap || !address || !buffer || length == 0) return NO;

    @try {
    const uint8_t *src = (const uint8_t *)buffer;
    uint64_t current = address;
    size_t remaining = length;
    const uint64_t pageSize = (uint64_t)PAGE_SIZE;
    const uint64_t pageMask = pageSize - 1ULL;

    while (remaining > 0) {
        if (!ds_debug_user_address(current)) return NO;

        uint64_t pageAddress = current & ~pageMask;
        uint64_t pageOffset = current & pageMask;
        size_t copySize = (size_t)MIN((uint64_t)remaining, pageSize - pageOffset);

        uint64_t localPage = ds_debug_map_page(vmMap, pageAddress);
        if (!localPage) return NO;

        memcpy((void *)(uintptr_t)(localPage + pageOffset), src, copySize);

        src += copySize;
        current += copySize;
        remaining -= copySize;
    }

    return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

typedef struct {
    uint64_t address;
    void *buffer;
    size_t length;
    BOOL success;
} DSDebugReadRange;

// DarkSword scatter equivalent for the hot mesh/bone path. Resolve every
// target page first, then copy all ranges from the pinned local mappings. This
// keeps page-creation work out of the middle of a logical frame snapshot. The
// Reader ranges are <= one page and therefore span at most two target pages.
static BOOL ds_debug_read_list(uint64_t vmMap, DSDebugReadRange *ranges, size_t count) {
    if (!vmMap || !ranges || count == 0 || count > 128) return NO;
    struct PinnedRange {
        uint64_t first;
        uint64_t second;
        uint64_t firstPage;
        uint64_t secondPage;
        uint64_t epoch;
        size_t firstLength;
        size_t length;
    };
    // The reader batches are capped at 128 ranges. Keep this scratch storage
    // on the stack so the display-rate path never touches the heap allocator.
    PinnedRange pinned[128] = {};
    const uint64_t pageSize = (uint64_t)PAGE_SIZE;
    const uint64_t pageMask = pageSize - 1ULL;
    DSDebugShmemOwner owner = g_debugShmemOwner;
    BOOL allOK = YES;

    for (size_t i = 0; i < count; i++) {
        ranges[i].success = NO;
        uint64_t address = ranges[i].address;
        size_t length = ranges[i].length;
        if (!address || !ranges[i].buffer || length == 0 || length > PAGE_SIZE) {
            allOK = NO;
            continue;
        }
        uint64_t end = address + (uint64_t)length - 1ULL;
        if (end < address || !ds_debug_user_address(address) || !ds_debug_user_address(end)) {
            allOK = NO;
            continue;
        }
        uint64_t firstPage = address & ~pageMask;
        uint64_t lastPage = end & ~pageMask;
        uint64_t mapperEpoch = 0;
        uint64_t firstLocal = ds_debug_map_page_pinned(
            owner, vmMap, firstPage, &mapperEpoch);
        if (!firstLocal) {
            allOK = NO;
            continue;
        }
        size_t firstLength = MIN(length, (size_t)(pageSize - (address & pageMask)));
        uint64_t secondLocal = 0;
        if (lastPage != firstPage) {
            uint64_t secondEpoch = 0;
            secondLocal = ds_debug_map_page_pinned(
                owner, vmMap, lastPage, &secondEpoch);
            if (!secondLocal) {
                ds_debug_unpin_page(owner, vmMap, mapperEpoch, firstPage);
                allOK = NO;
                continue;
            }
            if (secondEpoch != mapperEpoch) {
                ds_debug_unpin_page(owner, vmMap, secondEpoch, lastPage);
                ds_debug_unpin_page(owner, vmMap, mapperEpoch, firstPage);
                allOK = NO;
                continue;
            }
        }
        pinned[i] = {firstLocal + (address & pageMask), secondLocal,
                     firstPage, lastPage != firstPage ? lastPage : 0,
                     mapperEpoch, firstLength, length};
    }

    std::atomic_thread_fence(std::memory_order_acquire);
    for (size_t i = 0; i < count; i++) {
        const PinnedRange &pin = pinned[i];
        if (!pin.first || pin.length == 0) continue;
        memcpy(ranges[i].buffer, (const void *)(uintptr_t)pin.first, pin.firstLength);
        size_t remaining = pin.length - pin.firstLength;
        if (remaining) {
            memcpy((uint8_t *)ranges[i].buffer + pin.firstLength,
                   (const void *)(uintptr_t)pin.second, remaining);
        }
        ranges[i].success = YES;
        ds_debug_unpin_page(owner, vmMap, pin.epoch, pin.firstPage);
        if (pin.secondPage) {
            ds_debug_unpin_page(owner, vmMap, pin.epoch, pin.secondPage);
        }
    }
    return allOK;
}

#pragma mark - Floating camera menu (hosted in SpringBoard, DarkSpeed pattern)

static void ds_hosted_pubg_hide_all(void);

static NSString * const kDSHostedMenuAnchorXKey = @"pubg_menu_anchor_x";
static NSString * const kDSHostedMenuAnchorYKey = @"pubg_menu_anchor_y";
static NSString * const kDSHostedMenuPanelXKey = @"pubg_menu_panel_x";
static NSString * const kDSHostedMenuPanelYKey = @"pubg_menu_panel_y";
static NSString * const kDSHostedEspEnabledKey = @"pubg_esp_enabled";
static const double kDSHostedMenuLevel = 10000020.0;
static const CGFloat kDSHostedMenuButtonSize = 42.0;
static const CGFloat kDSHostedMenuSymbolSize = 16.0;

// ESP defaults to on (the overlay always rendered before the switch existed).
static std::atomic<bool> g_hostedEspEnabled(true);
static dispatch_once_t g_hostedEspDefaultsOnce;

static bool ds_hosted_esp_enabled(void) {
    dispatch_once(&g_hostedEspDefaultsOnce, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id stored = [defaults objectForKey:kDSHostedEspEnabledKey];
        if (stored) {
            g_hostedEspEnabled.store([defaults boolForKey:kDSHostedEspEnabledKey],
                                     std::memory_order_release);
        }
    });
    return g_hostedEspEnabled.load(std::memory_order_acquire);
}

static void ds_hosted_esp_set_enabled(bool enabled) {
    (void)ds_hosted_esp_enabled();
    g_hostedEspEnabled.store(enabled, std::memory_order_release);
    [NSUserDefaults.standardUserDefaults setBool:enabled
                                          forKey:kDSHostedEspEnabledKey];
    if (enabled) return;
    void (^hideEsp)(void) = ^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        ds_hosted_pubg_hide_all();
        [CATransaction commit];
    };
    if (NSThread.isMainThread) {
        hideEsp();
    } else {
        dispatch_async(dispatch_get_main_queue(), hideEsp);
    }
}

static UIImage *ds_hosted_menu_toggle_image(void) {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIImage *symbol = [UIImage systemImageNamed:@"slider.horizontal.3"];
        if (symbol) {
            image = [symbol imageByApplyingSymbolConfiguration:
                [UIImageSymbolConfiguration
                    configurationWithPointSize:kDSHostedMenuSymbolSize
                                         weight:UIImageSymbolWeightSemibold]];
        }
    });
    return image;
}

static UIButton *ds_hosted_minimap_step_button(NSString *symbolName,
                                                NSInteger tag,
                                                NSString *accessibilityLabel) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = tag;
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = accessibilityLabel;
    UIImage *image = [UIImage systemImageNamed:symbolName];
    if (image) {
        image = [image imageByApplyingSymbolConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:12.0
                                                             weight:UIImageSymbolWeightSemibold]];
        [button setImage:image forState:UIControlStateNormal];
    } else {
        [button setTitle:[symbolName isEqualToString:@"plus"] ? @"+" : @"-"
                forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    }
    return button;
}

// Interactive sibling of DSESPHostedWindow: touchable, still system/secure so
// SpringBoard can host it above the game.
@interface DSESPMenuWindow : UIWindow
@end

@interface DSESPMenuViewController : UIViewController
- (void)dsSetExpanded:(BOOL)expanded;
- (void)dsApplyOrientation;
- (BOOL)dsShouldAcceptHitView:(UIView *)hitView;
- (UIButton *)toggleButton;
- (void)dsUpdatePubgLanguage;
@end

static UIWindow *g_hostedMenuWindow = nil;
static DSESPMenuViewController *g_hostedMenuViewController = nil;
static uint64_t g_hostedMenuRemoteController = 0;
static unsigned g_hostedMenuContextId = 0;
static BOOL g_hostedMenuExpanded = NO;
static int g_hostedMenuLastOrientation = 0;
static CFAbsoluteTime g_hostedMenuLastSetupTryAt = 0;
static CFAbsoluteTime g_hostedMenuLastRegisterTryAt = 0;

static CGRect ds_hosted_menu_frame(void) {
    // Full screen; hit testing inside the view controller decides what is
    // touchable, everything else falls through to the game.
    return UIScreen.mainScreen.bounds;
}

static void ds_hosted_menu_set_expanded(BOOL expanded);

@implementation DSESPMenuWindow
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
- (BOOL)keepContextInBackground { return YES; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!g_hostedMenuExpanded && g_hostedMenuViewController) {
        UIButton *btn = [g_hostedMenuViewController toggleButton];
        if (btn && !btn.hidden) {
            CGPoint ptInBtn = [self convertPoint:point toView:btn];
            CGRect expandHitRect = CGRectInset(btn.bounds, -12.0, -12.0);
            if (CGRectContainsPoint(expandHitRect, ptInBtn)) {
                return btn;
            }
        }
    }
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit || hit == self || hit == self.rootViewController.view) return nil;
    SEL acceptSel = NSSelectorFromString(@"dsShouldAcceptHitView:");
    if ([self.rootViewController respondsToSelector:acceptSel]) {
        BOOL accepted = ((BOOL (*)(id, SEL, UIView *))objc_msgSend)(self.rootViewController,
                                                                    acceptSel, hit);
        if (!accepted) return nil;
    }
    return hit;
}
@end

@implementation DSESPMenuViewController {
    UIView *_contentView;
    UIView *_panelView;
    UIView *_headerView;
    UILabel *_watermarkLabel;
    UILabel *_resizeHandleLabel;
    UIButton *_toggleButton;
    UIButton *_collapseButton;
    UIButton *_closeButton;
    UILabel *_titleLabel;

    // Tab Bar
    int _pubgCurrentTab;
    UIView *_pubgTabBar;
    UIButton *_pubgTabButtonPlayer;
    UIButton *_pubgTabButtonItems;
    UIButton *_pubgTabButtonVehicles;
    UIButton *_pubgTabButtonSettings;
    UIView *_tabDividers[3];

    // Scroll View & Content Containers
    UIScrollView *_scrollView;
    UIView *_tabContentViewPlayer;
    UIView *_tabContentViewItems;
    UIView *_tabContentViewVehicles;
    UIView *_tabContentViewSettings;

    // Tab 0: Player ESP Controls
    UIView *_rowMasterEsp;
    UILabel *_espLabel;
    UISwitch *_espSwitch;

    UIView *_rowBox;
    UILabel *_pubgBoxLabel;
    UISwitch *_pubgBoxSwitch;

    UIView *_rowSkeleton;
    UILabel *_pubgSkeletonLabel;
    UISwitch *_pubgSkeletonSwitch;

    UIView *_rowLine;
    UILabel *_pubgLineLabel;
    UISwitch *_pubgLineSwitch;

    UIView *_rowHealth;
    UILabel *_pubgHealthLabel;
    UISwitch *_pubgHealthSwitch;

    UIView *_rowName;
    UILabel *_pubgNameLabel;
    UISwitch *_pubgNameSwitch;

    UIView *_rowDist;
    UILabel *_pubgDistLabel;
    UISwitch *_pubgDistSwitch;

    UIView *_rowBot;
    UILabel *_pubgBotLabel;
    UISwitch *_pubgBotSwitch;

    UIView *_rowArrow;
    UILabel *_pubgArrowLabel;
    UISwitch *_pubgArrowSwitch;

    UIView *_rowGrenade;
    UILabel *_pubgGrenadeLabel;
    UISwitch *_pubgGrenadeSwitch;

    UIView *_rowZoom;
    UILabel *_zoomLabel;
    UISlider *_zoomSlider;
    UILabel *_zoomValueLabel;

    // Tab 1: Item ESP Controls
    UIView *_rowWeapon;
    UILabel *_pubgWeaponLabel;
    UISwitch *_pubgWeaponSwitch;

    UIView *_rowArmor;
    UILabel *_pubgArmorLabel;
    UISwitch *_pubgArmorSwitch;

    UIView *_rowBag;
    UILabel *_pubgBagLabel;
    UISwitch *_pubgBagSwitch;

    UIView *_rowScope;
    UILabel *_pubgScopeLabel;
    UISwitch *_pubgScopeSwitch;

    UIView *_rowCrate;
    UILabel *_pubgCrateLabel;
    UISwitch *_pubgCrateSwitch;

    UIView *_rowItemScan;
    UILabel *_pubgItemScanLabel;
    UILabel *_pubgItemScanValueLabel;
    UISlider *_pubgItemScanSlider;

    // Tab 2: Vehicle ESP Controls
    UIView *_rowVehicle;
    UILabel *_pubgVehicleLabel;
    UISwitch *_pubgVehicleSwitch;

    UIView *_rowVehicleHp;
    UILabel *_pubgVehicleHpLabel;
    UISwitch *_pubgVehicleHpSwitch;

    UIView *_rowVehicleFuel;
    UILabel *_pubgVehicleFuelLabel;
    UISwitch *_pubgVehicleFuelSwitch;

    // Tab 3: Settings Controls
    UIView *_rowLang;
    UILabel *_pubgSettingLangLabel;
    UISegmentedControl *_pubgLangSegment;

    UIView *_rowThickness;
    UILabel *_pubgSettingThicknessLabel;
    UILabel *_pubgSettingThicknessValueLabel;
    UISlider *_pubgSettingThicknessSlider;

    UIView *_rowInfo;
    UILabel *_pubgSettingInfoLabel;
    UILabel *_pubgSettingInfoDescLabel;

    UIButton *_resetButton;

    // Anchors & Orientation
    CGPoint _buttonAnchorUnit;
    CGPoint _panelAnchorUnit;
    CGPoint _dragStartAnchor;
    BOOL _hasButtonAnchor;
    BOOL _hasPanelAnchor;
    BOOL _hasAppliedOrientation;
    int _appliedOrientation;
    CGRect _appliedWindowBounds;
}

static UIView *ds_create_pill_row(CGFloat y, CGFloat width, CGFloat height) {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, height)];
    row.backgroundColor = [UIColor colorWithRed:248/255.0 green:249/255.0 blue:252/255.0 alpha:1.0];
    row.layer.cornerRadius = 10.0;
    row.layer.borderWidth = 0.6;
    row.layer.borderColor = [UIColor colorWithRed:235/255.0 green:238/255.0 blue:246/255.0 alpha:1.0].CGColor;
    row.clipsToBounds = YES;
    row.userInteractionEnabled = YES;
    return row;
}

static UILabel *ds_create_row_label(UIView *parent, NSString *text, CGFloat width, CGFloat height) {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(12.0, 0, width - 64.0, height)];
    lbl.text = text;
    lbl.textColor = [UIColor colorWithRed:31/255.0 green:41/255.0 blue:55/255.0 alpha:1.0];
    lbl.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    lbl.userInteractionEnabled = NO;
    [parent addSubview:lbl];
    return lbl;
}

static UISwitch *ds_create_row_switch(UIView *parent, id target, SEL action, BOOL isOn, CGFloat width, CGFloat height) {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.onTintColor = [UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:1.0];
    sw.thumbTintColor = [UIColor whiteColor];
    sw.transform = CGAffineTransformMakeScale(0.72, 0.72);
    sw.center = CGPointMake(width - 28.0, height * 0.5);
    sw.on = isOn;
    [sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sw];
    return sw;
}

static void ds_setup_slider_row(UIView *parent, UILabel *tLbl, UILabel *vLbl, UISlider *sl,
                                NSString *title, float minVal, float maxVal, float curVal,
                                id target, SEL action, CGFloat width) {
    tLbl.frame = CGRectMake(12.0, 6.0, width - 85.0, 18.0);
    tLbl.text = title;
    tLbl.textColor = [UIColor colorWithRed:31/255.0 green:41/255.0 blue:55/255.0 alpha:1.0];
    tLbl.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    tLbl.userInteractionEnabled = NO;
    [parent addSubview:tLbl];

    vLbl.frame = CGRectMake(width - 75.0, 6.0, 65.0, 18.0);
    vLbl.textColor = [UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:1.0];
    vLbl.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightBold];
    vLbl.textAlignment = NSTextAlignmentRight;
    vLbl.userInteractionEnabled = NO;
    [parent addSubview:vLbl];

    sl.frame = CGRectMake(10.0, 26.0, width - 20.0, 24.0);
    sl.minimumValue = minVal;
    sl.maximumValue = maxVal;
    sl.value = curVal;
    sl.continuous = YES;
    sl.minimumTrackTintColor = [UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:1.0];
    sl.maximumTrackTintColor = [UIColor colorWithRed:226/255.0 green:232/255.0 blue:240/255.0 alpha:1.0];
    [sl addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sl];
}

- (void)loadView {
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.opaque = NO;
    self.view.backgroundColor = UIColor.clearColor;

    _contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    _contentView.opaque = NO;
    _contentView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_contentView];

    // 1. Floating Action Button (Circle with royal blue bg, neon green ring, bold white DS)
    _toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _toggleButton.backgroundColor = [UIColor colorWithRed:36/255.0 green:48/255.0 blue:185/255.0 alpha:0.95];
    _toggleButton.tintColor = [UIColor whiteColor];
    _toggleButton.layer.cornerRadius = kDSHostedMenuButtonSize * 0.5;
    _toggleButton.layer.borderWidth = 2.2;
    _toggleButton.layer.borderColor = [UIColor colorWithRed:0/255.0 green:230/255.0 blue:118/255.0 alpha:1.0].CGColor;
    _toggleButton.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:230/255.0 blue:118/255.0 alpha:0.6].CGColor;
    _toggleButton.layer.shadowRadius = 8.0;
    _toggleButton.layer.shadowOpacity = 0.85;
    _toggleButton.layer.shadowOffset = CGSizeZero;
    _toggleButton.layer.masksToBounds = NO;
    [_toggleButton setTitle:@"DS" forState:UIControlStateNormal];
    [_toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _toggleButton.titleLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightHeavy];
    [_toggleButton addTarget:self action:@selector(dsToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dsMenuButtonPanned:)];
    [_toggleButton addGestureRecognizer:menuPan];
    [_contentView addSubview:_toggleButton];

    // 2. Menu Window Card (Crisp white rounded card with soft drop shadow)
    _panelView = [[UIView alloc] initWithFrame:CGRectZero];
    _panelView.backgroundColor = [UIColor whiteColor];
    _panelView.layer.cornerRadius = 16.0;
    _panelView.layer.borderWidth = 0.8;
    _panelView.layer.borderColor = [UIColor colorWithRed:226/255.0 green:232/255.0 blue:240/255.0 alpha:1.0].CGColor;
    _panelView.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.18].CGColor;
    _panelView.layer.shadowRadius = 18.0;
    _panelView.layer.shadowOffset = CGSizeMake(0, 6);
    _panelView.layer.shadowOpacity = 1.0;
    _panelView.layer.masksToBounds = NO;
    [_contentView addSubview:_panelView];

    // 3. Watermark Label (Subtle translucent "sudo" centered behind rows)
    _watermarkLabel = [[UILabel alloc] initWithFrame:CGRectMake(10.0, 100.0, 290.0, 110.0)];
    _watermarkLabel.text = @"sudo";
    _watermarkLabel.font = [UIFont systemFontOfSize:54.0 weight:UIFontWeightHeavy];
    _watermarkLabel.textColor = [UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:0.06];
    _watermarkLabel.textAlignment = NSTextAlignmentCenter;
    _watermarkLabel.userInteractionEnabled = NO;
    [_panelView addSubview:_watermarkLabel];

    // 4. Resize Handle Indicator in bottom-right corner
    _resizeHandleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _resizeHandleLabel.text = @"↘";
    _resizeHandleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    _resizeHandleLabel.textColor = [UIColor colorWithRed:160/255.0 green:170/255.0 blue:185/255.0 alpha:0.7];
    _resizeHandleLabel.textAlignment = NSTextAlignmentCenter;
    _resizeHandleLabel.userInteractionEnabled = NO;
    [_panelView addSubview:_resizeHandleLabel];

    // 5. Header View (Draggable top bar with title and action buttons)
    _headerView = [[UIView alloc] initWithFrame:CGRectZero];
    _headerView.backgroundColor = [UIColor clearColor];
    _headerView.userInteractionEnabled = YES;
    UIPanGestureRecognizer *headerPan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dsMenuPanelPanned:)];
    [_headerView addGestureRecognizer:headerPan];
    [_panelView addSubview:_headerView];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = @"DS · DARKPUBG";
    _titleLabel.textColor = [UIColor colorWithRed:17/255.0 green:24/255.0 blue:39/255.0 alpha:1.0];
    _titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
    [_headerView addSubview:_titleLabel];

    _collapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_collapseButton setTitle:@"⌃" forState:UIControlStateNormal];
    [_collapseButton setTitleColor:[UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:1.0] forState:UIControlStateNormal];
    _collapseButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    [_collapseButton addTarget:self action:@selector(dsToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_collapseButton];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [_closeButton setTitleColor:[UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:1.0] forState:UIControlStateNormal];
    _closeButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    [_closeButton addTarget:self action:@selector(dsCloseTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_closeButton];

    // 6. Tab Bar (Capsule container with 4 tabs separated by dividers)
    _pubgTabBar = [[UIView alloc] initWithFrame:CGRectZero];
    _pubgTabBar.backgroundColor = [UIColor colorWithRed:241/255.0 green:242/255.0 blue:246/255.0 alpha:1.0];
    _pubgTabBar.layer.cornerRadius = 8.0;
    _pubgTabBar.clipsToBounds = YES;
    [_panelView addSubview:_pubgTabBar];

    auto createTabBtn = ^(NSString *title) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        [b addTarget:self action:@selector(dsPubgTabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self->_pubgTabBar addSubview:b];
        return b;
    };
    _pubgTabButtonPlayer = createTabBtn(@"ESP");
    _pubgTabButtonItems = createTabBtn(@"Vật Phẩm");
    _pubgTabButtonVehicles = createTabBtn(@"Xe");
    _pubgTabButtonSettings = createTabBtn(@"Cài Đặt");

    for (int di = 0; di < 3; di++) {
        UIView *div = [[UIView alloc] initWithFrame:CGRectZero];
        div.backgroundColor = [UIColor colorWithRed:226/255.0 green:232/255.0 blue:240/255.0 alpha:1.0];
        [_pubgTabBar addSubview:div];
        _tabDividers[di] = div;
    }

    // 7. Scroll View & Containers for each tab
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.backgroundColor = [UIColor clearColor];
    _scrollView.showsVerticalScrollIndicator = YES;
    _scrollView.alwaysBounceVertical = YES;
    [_panelView addSubview:_scrollView];

    CGFloat rowW = 286.0;
    _tabContentViewPlayer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowW, 514.0)];
    _tabContentViewItems = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowW, 284.0)];
    _tabContentViewVehicles = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowW, 132.0)];
    _tabContentViewSettings = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rowW, 230.0)];

    [_scrollView addSubview:_tabContentViewPlayer];
    [_scrollView addSubview:_tabContentViewItems];
    [_scrollView addSubview:_tabContentViewVehicles];
    [_scrollView addSubview:_tabContentViewSettings];

    // Seed controls from persisted state
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:@"pubg_box"] != nil) g_pubgEspBox = [defaults boolForKey:@"pubg_box"];
    if ([defaults objectForKey:@"pubg_skeleton"] != nil) g_pubgEspSkeleton = [defaults boolForKey:@"pubg_skeleton"];
    if ([defaults objectForKey:@"pubg_line"] != nil) g_pubgEspLine = [defaults boolForKey:@"pubg_line"];
    if ([defaults objectForKey:@"pubg_health"] != nil) g_pubgEspHealth = [defaults boolForKey:@"pubg_health"];
    if ([defaults objectForKey:@"pubg_name"] != nil) g_pubgEspName = [defaults boolForKey:@"pubg_name"];
    if ([defaults objectForKey:@"pubg_dist"] != nil) g_pubgEspDist = [defaults boolForKey:@"pubg_dist"];
    if ([defaults objectForKey:@"pubg_bot"] != nil) g_pubgEspBot = [defaults boolForKey:@"pubg_bot"];
    if ([defaults objectForKey:@"pubg_arrow"] != nil) g_pubgEspArrow = [defaults boolForKey:@"pubg_arrow"];
    if ([defaults objectForKey:@"pubg_grenade"] != nil) g_pubgEspGrenade = [defaults boolForKey:@"pubg_grenade"];
    if ([defaults objectForKey:@"pubg_vehicle"] != nil) g_pubgEspVehicle = [defaults boolForKey:@"pubg_vehicle"];
    if ([defaults objectForKey:@"pubg_vehicle_hp"] != nil) g_pubgEspVehicleHp = [defaults boolForKey:@"pubg_vehicle_hp"];
    if ([defaults objectForKey:@"pubg_vehicle_fuel"] != nil) g_pubgEspVehicleFuel = [defaults boolForKey:@"pubg_vehicle_fuel"];
    if ([defaults objectForKey:@"pubg_weapon"] != nil) g_pubgEspWeapon = [defaults boolForKey:@"pubg_weapon"];
    if ([defaults objectForKey:@"pubg_armor"] != nil) g_pubgEspArmor = [defaults boolForKey:@"pubg_armor"];
    if ([defaults objectForKey:@"pubg_bag"] != nil) g_pubgEspBag = [defaults boolForKey:@"pubg_bag"];
    if ([defaults objectForKey:@"pubg_scope"] != nil) g_pubgEspScope = [defaults boolForKey:@"pubg_scope"];
    if ([defaults objectForKey:@"pubg_crate"] != nil) g_pubgEspCrate = [defaults boolForKey:@"pubg_crate"];
    if ([defaults objectForKey:@"pubg_item_dist"] != nil) g_pubgItemMaxDistance = [defaults floatForKey:@"pubg_item_dist"];
    if ([defaults objectForKey:@"pubg_lang"] != nil) g_pubgLanguage = (int)[defaults integerForKey:@"pubg_lang"];
    if ([defaults objectForKey:@"pubg_thickness"] != nil) {
        g_pubgEspThickness = [defaults floatForKey:@"pubg_thickness"];
        if (g_pubgEspThickness < 0.8f) g_pubgEspThickness = 0.8f;
        if (g_pubgEspThickness > 3.5f) g_pubgEspThickness = 3.5f;
    }

    // --- Tab 0: Player ESP Controls ---
    CGFloat y0 = 0;
    _rowMasterEsp = ds_create_pill_row(y0, rowW, 40.0);
    _espLabel = ds_create_row_label(_rowMasterEsp, @"Bật ESP Master", rowW, 40.0);
    _espSwitch = ds_create_row_switch(_rowMasterEsp, self, @selector(dsEspSwitchChanged:), ds_hosted_esp_enabled(), rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowMasterEsp];

    y0 += 46.0;
    _rowBox = ds_create_pill_row(y0, rowW, 40.0);
    _pubgBoxLabel = ds_create_row_label(_rowBox, @"Khung 2D (Box)", rowW, 40.0);
    _pubgBoxSwitch = ds_create_row_switch(_rowBox, self, @selector(dsPubgBoxChanged:), g_pubgEspBox, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowBox];

    y0 += 46.0;
    _rowSkeleton = ds_create_pill_row(y0, rowW, 40.0);
    _pubgSkeletonLabel = ds_create_row_label(_rowSkeleton, @"Khung Xương (Skeleton)", rowW, 40.0);
    _pubgSkeletonSwitch = ds_create_row_switch(_rowSkeleton, self, @selector(dsPubgSkeletonChanged:), g_pubgEspSkeleton, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowSkeleton];

    y0 += 46.0;
    _rowLine = ds_create_pill_row(y0, rowW, 40.0);
    _pubgLineLabel = ds_create_row_label(_rowLine, @"Đường Kẻ (Line)", rowW, 40.0);
    _pubgLineSwitch = ds_create_row_switch(_rowLine, self, @selector(dsPubgLineChanged:), g_pubgEspLine, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowLine];

    y0 += 46.0;
    _rowHealth = ds_create_pill_row(y0, rowW, 40.0);
    _pubgHealthLabel = ds_create_row_label(_rowHealth, @"Thanh Máu (Health)", rowW, 40.0);
    _pubgHealthSwitch = ds_create_row_switch(_rowHealth, self, @selector(dsPubgHealthChanged:), g_pubgEspHealth, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowHealth];

    y0 += 46.0;
    _rowName = ds_create_pill_row(y0, rowW, 40.0);
    _pubgNameLabel = ds_create_row_label(_rowName, @"Tên Địch (Name)", rowW, 40.0);
    _pubgNameSwitch = ds_create_row_switch(_rowName, self, @selector(dsPubgNameChanged:), g_pubgEspName, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowName];

    y0 += 46.0;
    _rowDist = ds_create_pill_row(y0, rowW, 40.0);
    _pubgDistLabel = ds_create_row_label(_rowDist, @"Khoảng Cách (Distance)", rowW, 40.0);
    _pubgDistSwitch = ds_create_row_switch(_rowDist, self, @selector(dsPubgDistChanged:), g_pubgEspDist, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowDist];

    y0 += 46.0;
    _rowBot = ds_create_pill_row(y0, rowW, 40.0);
    _pubgBotLabel = ds_create_row_label(_rowBot, @"Hiện Bot AI", rowW, 40.0);
    _pubgBotSwitch = ds_create_row_switch(_rowBot, self, @selector(dsPubgBotChanged:), g_pubgEspBot, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowBot];

    y0 += 46.0;
    _rowArrow = ds_create_pill_row(y0, rowW, 40.0);
    _pubgArrowLabel = ds_create_row_label(_rowArrow, @"Cảnh Báo 360 (Radar)", rowW, 40.0);
    _pubgArrowSwitch = ds_create_row_switch(_rowArrow, self, @selector(dsPubgArrowChanged:), g_pubgEspArrow, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowArrow];

    y0 += 46.0;
    _rowGrenade = ds_create_pill_row(y0, rowW, 40.0);
    _pubgGrenadeLabel = ds_create_row_label(_rowGrenade, @"Cảnh Báo Lựu Đạn", rowW, 40.0);
    _pubgGrenadeSwitch = ds_create_row_switch(_rowGrenade, self, @selector(dsPubgGrenadeChanged:), g_pubgEspGrenade, rowW, 40.0);
    [_tabContentViewPlayer addSubview:_rowGrenade];

    y0 += 46.0;
    _rowZoom = ds_create_pill_row(y0, rowW, 54.0);
    _zoomLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _zoomValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _zoomSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    ds_setup_slider_row(_rowZoom, _zoomLabel, _zoomValueLabel, _zoomSlider,
                        @"Khoảng cách hiện địch", 50.0f, 500.0f, g_dspubgMaxDistance,
                        self, @selector(dsZoomSliderChanged:), rowW);
    [_tabContentViewPlayer addSubview:_rowZoom];

    // --- Tab 1: Item ESP Controls ---
    CGFloat y1 = 0;
    _rowWeapon = ds_create_pill_row(y1, rowW, 40.0);
    _pubgWeaponLabel = ds_create_row_label(_rowWeapon, @"Hiện Súng & Vũ Khí", rowW, 40.0);
    _pubgWeaponSwitch = ds_create_row_switch(_rowWeapon, self, @selector(dsPubgWeaponChanged:), g_pubgEspWeapon, rowW, 40.0);
    [_tabContentViewItems addSubview:_rowWeapon];

    y1 += 46.0;
    _rowArmor = ds_create_pill_row(y1, rowW, 40.0);
    _pubgArmorLabel = ds_create_row_label(_rowArmor, @"Giáp & Mũ Bảo Hiểm", rowW, 40.0);
    _pubgArmorSwitch = ds_create_row_switch(_rowArmor, self, @selector(dsPubgArmorChanged:), g_pubgEspArmor, rowW, 40.0);
    [_tabContentViewItems addSubview:_rowArmor];

    y1 += 46.0;
    _rowBag = ds_create_pill_row(y1, rowW, 40.0);
    _pubgBagLabel = ds_create_row_label(_rowBag, @"Balo & Túi Đồ", rowW, 40.0);
    _pubgBagSwitch = ds_create_row_switch(_rowBag, self, @selector(dsPubgBagChanged:), g_pubgEspBag, rowW, 40.0);
    [_tabContentViewItems addSubview:_rowBag];

    y1 += 46.0;
    _rowScope = ds_create_pill_row(y1, rowW, 40.0);
    _pubgScopeLabel = ds_create_row_label(_rowScope, @"Ống Ngắm (Scopes)", rowW, 40.0);
    _pubgScopeSwitch = ds_create_row_switch(_rowScope, self, @selector(dsPubgScopeChanged:), g_pubgEspScope, rowW, 40.0);
    [_tabContentViewItems addSubview:_rowScope];

    y1 += 46.0;
    _rowCrate = ds_create_pill_row(y1, rowW, 40.0);
    _pubgCrateLabel = ds_create_row_label(_rowCrate, @"Thùng Thính & Hòm Xác", rowW, 40.0);
    _pubgCrateSwitch = ds_create_row_switch(_rowCrate, self, @selector(dsPubgCrateChanged:), g_pubgEspCrate, rowW, 40.0);
    [_tabContentViewItems addSubview:_rowCrate];

    y1 += 46.0;
    _rowItemScan = ds_create_pill_row(y1, rowW, 54.0);
    _pubgItemScanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgItemScanValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgItemScanSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    ds_setup_slider_row(_rowItemScan, _pubgItemScanLabel, _pubgItemScanValueLabel, _pubgItemScanSlider,
                        @"Khoảng cách vật phẩm", 50.0f, 300.0f, g_pubgItemMaxDistance,
                        self, @selector(dsPubgItemScanSliderChanged:), rowW);

    // --- Tab 2: Vehicle ESP Controls ---
    CGFloat y2 = 0;
    _rowVehicle = ds_create_pill_row(y2, rowW, 40.0);
    _pubgVehicleLabel = ds_create_row_label(_rowVehicle, @"Hiện Phương Tiện (Xe)", rowW, 40.0);
    _pubgVehicleSwitch = ds_create_row_switch(_rowVehicle, self, @selector(dsPubgVehicleChanged:), g_pubgEspVehicle, rowW, 40.0);
    [_tabContentViewVehicles addSubview:_rowVehicle];

    y2 += 46.0;
    _rowVehicleHp = ds_create_pill_row(y2, rowW, 40.0);
    _pubgVehicleHpLabel = ds_create_row_label(_rowVehicleHp, @"Hiện Máu Xe", rowW, 40.0);
    _pubgVehicleHpSwitch = ds_create_row_switch(_rowVehicleHp, self, @selector(dsPubgVehicleHpChanged:), g_pubgEspVehicleHp, rowW, 40.0);
    [_tabContentViewVehicles addSubview:_rowVehicleHp];

    y2 += 46.0;
    _rowVehicleFuel = ds_create_pill_row(y2, rowW, 40.0);
    _pubgVehicleFuelLabel = ds_create_row_label(_rowVehicleFuel, @"Hiện Bình Xăng Xe", rowW, 40.0);
    _pubgVehicleFuelSwitch = ds_create_row_switch(_rowVehicleFuel, self, @selector(dsPubgVehicleFuelChanged:), g_pubgEspVehicleFuel, rowW, 40.0);
    [_tabContentViewVehicles addSubview:_rowVehicleFuel];

    // --- Tab 3: Settings Controls ---
    CGFloat y3 = 0;
    _rowLang = ds_create_pill_row(y3, rowW, 62.0);
    _pubgSettingLangLabel = [[UILabel alloc] initWithFrame:CGRectMake(12.0, 6.0, rowW - 24.0, 18.0)];
    _pubgSettingLangLabel.text = @"Ngôn ngữ giao diện";
    _pubgSettingLangLabel.textColor = [UIColor colorWithRed:31/255.0 green:41/255.0 blue:55/255.0 alpha:1.0];
    _pubgSettingLangLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    _pubgSettingLangLabel.userInteractionEnabled = NO;
    [_rowLang addSubview:_pubgSettingLangLabel];

    _pubgLangSegment = [[UISegmentedControl alloc] initWithItems:@[@"Tiếng Việt", @"English"]];
    _pubgLangSegment.frame = CGRectMake(10.0, 28.0, rowW - 20.0, 26.0);
    _pubgLangSegment.selectedSegmentIndex = g_pubgLanguage;
    [_pubgLangSegment addTarget:self action:@selector(dsPubgLangChanged:) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        _pubgLangSegment.selectedSegmentTintColor = [UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:0.18];
    }
    [_pubgLangSegment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:1.0],
        NSFontAttributeName: [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold]
    } forState:UIControlStateSelected];
    [_pubgLangSegment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithRed:100/255.0 green:116/255.0 blue:139/255.0 alpha:1.0],
        NSFontAttributeName: [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]
    } forState:UIControlStateNormal];
    [_rowLang addSubview:_pubgLangSegment];
    [_tabContentViewSettings addSubview:_rowLang];

    y3 += 68.0;
    _rowThickness = ds_create_pill_row(y3, rowW, 54.0);
    _pubgSettingThicknessLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgSettingThicknessValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgSettingThicknessSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    ds_setup_slider_row(_rowThickness, _pubgSettingThicknessLabel, _pubgSettingThicknessValueLabel, _pubgSettingThicknessSlider,
                        @"Độ dày nét vẽ địch", 0.8f, 3.5f, g_pubgEspThickness,
                        self, @selector(dsPubgThicknessChanged:), rowW);
    [_tabContentViewSettings addSubview:_rowThickness];

    y3 += 60.0;
    _rowInfo = ds_create_pill_row(y3, rowW, 56.0);
    _pubgSettingInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(12.0, 6.0, rowW - 24.0, 16.0)];
    _pubgSettingInfoLabel.text = @"Hệ thống & Tối ưu";
    _pubgSettingInfoLabel.textColor = [UIColor colorWithRed:79/255.0 green:70/255.0 blue:229/255.0 alpha:1.0];
    _pubgSettingInfoLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    _pubgSettingInfoLabel.userInteractionEnabled = NO;
    [_rowInfo addSubview:_pubgSettingInfoLabel];

    _pubgSettingInfoDescLabel = [[UILabel alloc] initWithFrame:CGRectMake(12.0, 24.0, rowW - 24.0, 26.0)];
    _pubgSettingInfoDescLabel.textColor = [UIColor colorWithRed:100/255.0 green:116/255.0 blue:139/255.0 alpha:1.0];
    _pubgSettingInfoDescLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    _pubgSettingInfoDescLabel.numberOfLines = 2;
    _pubgSettingInfoDescLabel.text = @"• Tần số quét: 60/120 FPS Zero-Lag\n• Trạng thái: Direct Memory QoS Active";
    _pubgSettingInfoDescLabel.userInteractionEnabled = NO;
    [_rowInfo addSubview:_pubgSettingInfoDescLabel];
    [_tabContentViewSettings addSubview:_rowInfo];

    y3 += 62.0;
    _resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _resetButton.frame = CGRectMake(0, y3, rowW, 40.0);
    [_resetButton setTitle:@"Khôi phục cài đặt gốc" forState:UIControlStateNormal];
    [_resetButton setTitleColor:[UIColor colorWithRed:220/255.0 green:38/255.0 blue:38/255.0 alpha:1.0] forState:UIControlStateNormal];
    _resetButton.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    _resetButton.backgroundColor = [UIColor colorWithRed:254/255.0 green:226/255.0 blue:226/255.0 alpha:0.8];
    _resetButton.layer.cornerRadius = 10.0;
    _resetButton.layer.borderWidth = 0.8;
    _resetButton.layer.borderColor = [UIColor colorWithRed:252/255.0 green:165/255.0 blue:165/255.0 alpha:0.5].CGColor;
    [_resetButton addTarget:self action:@selector(dsResetTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_tabContentViewSettings addSubview:_resetButton];

    // Persisted anchors
    id storedAnchorX = [defaults objectForKey:kDSHostedMenuAnchorXKey];
    id storedAnchorY = [defaults objectForKey:kDSHostedMenuAnchorYKey];
    if (storedAnchorX && storedAnchorY) {
        CGFloat x = (CGFloat)[storedAnchorX doubleValue];
        CGFloat y = (CGFloat)[storedAnchorY doubleValue];
        if (isfinite(x) && isfinite(y) && x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0) {
            _buttonAnchorUnit = CGPointMake(x, y);
            _hasButtonAnchor = YES;
        }
    }
    id storedPanelX = [defaults objectForKey:kDSHostedMenuPanelXKey];
    id storedPanelY = [defaults objectForKey:kDSHostedMenuPanelYKey];
    if (storedPanelX && storedPanelY) {
        CGFloat x = (CGFloat)[storedPanelX doubleValue];
        CGFloat y = (CGFloat)[storedPanelY doubleValue];
        if (isfinite(x) && isfinite(y) && x >= 0.0 && x <= 1.0 && y >= 0.0 && y <= 1.0) {
            _panelAnchorUnit = CGPointMake(x, y);
            _hasPanelAnchor = YES;
        }
    }

    [self dsUpdatePubgLanguage];
    [self dsUpdateValueLabel];
    [self dsSetExpanded:g_hostedMenuExpanded];
    [self dsApplyOrientation];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self dsApplyOrientation];
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)dsSetExpanded:(BOOL)expanded {
    BOOL desiredPanelHidden = !expanded;
    BOOL changed = g_hostedMenuExpanded != expanded || _panelView.hidden != desiredPanelHidden;
    g_hostedMenuExpanded = expanded;
    if (!changed) return;
    _panelView.hidden = desiredPanelHidden;
    [self dsLayoutMenu];
}

- (void)dsUpdateTabSelection {
    UIButton *buttons[4] = { _pubgTabButtonPlayer, _pubgTabButtonItems, _pubgTabButtonVehicles, _pubgTabButtonSettings };
    UIView *views[4] = { _tabContentViewPlayer, _tabContentViewItems, _tabContentViewVehicles, _tabContentViewSettings };
    CGFloat heights[4] = { 514.0, 284.0, 132.0, 230.0 };

    for (int i = 0; i < 4; i++) {
        UIButton *b = buttons[i];
        if (i == _pubgCurrentTab) {
            b.backgroundColor = [UIColor whiteColor];
            b.layer.cornerRadius = 6.0;
            b.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.10].CGColor;
            b.layer.shadowRadius = 2.5;
            b.layer.shadowOffset = CGSizeMake(0, 1);
            b.layer.shadowOpacity = 1.0;
            [b setTitleColor:[UIColor colorWithRed:17/255.0 green:24/255.0 blue:39/255.0 alpha:1.0] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
            views[i].hidden = NO;
        } else {
            b.backgroundColor = [UIColor clearColor];
            b.layer.shadowOpacity = 0.0;
            [b setTitleColor:[UIColor colorWithRed:100/255.0 green:116/255.0 blue:139/255.0 alpha:1.0] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
            views[i].hidden = YES;
        }
    }
    _scrollView.contentSize = CGSizeMake(286.0, heights[_pubgCurrentTab] + 10.0);
    [_scrollView setContentOffset:CGPointZero animated:NO];
}

- (void)dsPubgTabTapped:(UIButton *)sender {
    if (sender == _pubgTabButtonPlayer) _pubgCurrentTab = 0;
    else if (sender == _pubgTabButtonItems) _pubgCurrentTab = 1;
    else if (sender == _pubgTabButtonVehicles) _pubgCurrentTab = 2;
    else if (sender == _pubgTabButtonSettings) _pubgCurrentTab = 3;
    [self dsUpdateTabSelection];
}

- (void)dsLayoutMenu {
    CGRect bounds = _contentView.bounds;
    CGFloat boundsW = CGRectGetWidth(bounds);
    CGFloat panelW = 310.0;
    CGFloat panelH = 345.0;
    CGFloat boundsH = CGRectGetHeight(bounds);
    CGFloat defaultPanelY = MIN((CGFloat)82.0, MAX((CGFloat)10.0, boundsH - panelH - 10.0));
    CGPoint buttonAnchor = _hasButtonAnchor
        ? CGPointMake(_buttonAnchorUnit.x * boundsW, _buttonAnchorUnit.y * boundsH)
        : CGPointMake(14.0 + kDSHostedMenuButtonSize * 0.5, defaultPanelY + 46.0 + kDSHostedMenuButtonSize * 0.5);
    CGFloat buttonHalf = kDSHostedMenuButtonSize * 0.5;
    buttonAnchor.x = MIN(MAX(buttonAnchor.x, buttonHalf + 4.0), boundsW - buttonHalf - 4.0);
    buttonAnchor.y = MIN(MAX(buttonAnchor.y, buttonHalf + 4.0), boundsH - buttonHalf - 4.0);
    _buttonAnchorUnit = CGPointMake(buttonAnchor.x / MAX(boundsW, 1.0), buttonAnchor.y / MAX(boundsH, 1.0));
    _toggleButton.bounds = CGRectMake(0, 0, kDSHostedMenuButtonSize, kDSHostedMenuButtonSize);
    _toggleButton.center = buttonAnchor;
    if (!g_hostedMenuExpanded) {
        _panelView.frame = CGRectZero;
        return;
    }

    CGPoint panelAnchor = _hasPanelAnchor
        ? CGPointMake(_panelAnchorUnit.x * boundsW, _panelAnchorUnit.y * boundsH)
        : CGPointMake(14.0 + panelW * 0.5, defaultPanelY + panelH * 0.5);
    panelAnchor.x = MIN(MAX(panelAnchor.x, panelW * 0.5 + 10.0), boundsW - panelW * 0.5 - 10.0);
    panelAnchor.y = MIN(MAX(panelAnchor.y, panelH * 0.5 + 10.0), boundsH - panelH * 0.5 - 10.0);
    _panelAnchorUnit = CGPointMake(panelAnchor.x / MAX(boundsW, 1.0), panelAnchor.y / MAX(boundsH, 1.0));
    CGFloat panelX = panelAnchor.x - panelW * 0.5;
    CGFloat panelY = panelAnchor.y - panelH * 0.5;
    _panelView.frame = CGRectMake(panelX, panelY, panelW, panelH);
    _headerView.frame = CGRectMake(0, 0, panelW, 38.0);
    _titleLabel.frame = CGRectMake(14.0, 9.0, panelW - 90.0, 22.0);
    _collapseButton.frame = CGRectMake(panelW - 64.0, 7.0, 26.0, 26.0);
    _closeButton.frame = CGRectMake(panelW - 34.0, 7.0, 26.0, 26.0);
    _pubgTabBar.frame = CGRectMake(12.0, 38.0, panelW - 24.0, 32.0);

    CGFloat tabTotalW = panelW - 24.0;
    CGFloat tabW = floorf(tabTotalW / 4.0);
    _pubgTabButtonPlayer.frame = CGRectMake(0, 0, tabW, 32.0);
    _pubgTabButtonItems.frame = CGRectMake(tabW, 0, tabW, 32.0);
    _pubgTabButtonVehicles.frame = CGRectMake(tabW * 2, 0, tabW, 32.0);
    _pubgTabButtonSettings.frame = CGRectMake(tabW * 3, 0, tabTotalW - tabW * 3, 32.0);

    _tabDividers[0].frame = CGRectMake(tabW, 8.0, 1.0, 16.0);
    _tabDividers[1].frame = CGRectMake(tabW * 2, 8.0, 1.0, 16.0);
    _tabDividers[2].frame = CGRectMake(tabW * 3, 8.0, 1.0, 16.0);

    _watermarkLabel.frame = CGRectMake(10.0, 100.0, panelW - 20.0, 110.0);
    _resizeHandleLabel.frame = CGRectMake(panelW - 20.0, panelH - 20.0, 16.0, 16.0);
    _scrollView.frame = CGRectMake(12.0, 76.0, panelW - 24.0, panelH - 84.0);

    [self dsUpdateTabSelection];
}

- (void)dsToggleTapped:(UIButton *)sender {
    (void)sender;
    ds_hosted_menu_set_expanded(!g_hostedMenuExpanded);
}

- (void)dsCloseTapped:(UIButton *)sender {
    (void)sender;
    ds_hosted_menu_set_expanded(NO);
}

- (void)dsMenuButtonPanned:(UIPanGestureRecognizer *)gesture {
    CGRect bounds = _contentView.bounds;
    CGFloat boundsW = CGRectGetWidth(bounds);
    CGFloat boundsH = CGRectGetHeight(bounds);
    if (boundsW <= 0.0 || boundsH <= 0.0) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragStartAnchor = CGPointMake(_buttonAnchorUnit.x * boundsW, _buttonAnchorUnit.y * boundsH);
    }
    CGPoint translation = [gesture translationInView:_contentView];
    CGFloat distance = hypot(translation.x, translation.y);
    CGPoint anchor = CGPointMake(_dragStartAnchor.x + translation.x, _dragStartAnchor.y + translation.y);
    CGFloat half = kDSHostedMenuButtonSize * 0.5;
    anchor.x = MIN(MAX(anchor.x, half + 4.0), boundsW - half - 4.0);
    anchor.y = MIN(MAX(anchor.y, half + 4.0), boundsH - half - 4.0);
    _buttonAnchorUnit = CGPointMake(anchor.x / boundsW, anchor.y / boundsH);
    _hasButtonAnchor = YES;
    [self dsLayoutMenu];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setDouble:_buttonAnchorUnit.x forKey:kDSHostedMenuAnchorXKey];
        [defaults setDouble:_buttonAnchorUnit.y forKey:kDSHostedMenuAnchorYKey];
    }
}

- (void)dsMenuPanelPanned:(UIPanGestureRecognizer *)gesture {
    CGRect bounds = _contentView.bounds;
    CGFloat boundsW = CGRectGetWidth(bounds);
    CGFloat boundsH = CGRectGetHeight(bounds);
    if (boundsW <= 0.0 || boundsH <= 0.0) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragStartAnchor = CGPointMake(_panelAnchorUnit.x * boundsW, _panelAnchorUnit.y * boundsH);
    }
    CGPoint translation = [gesture translationInView:_contentView];
    CGFloat panelW = CGRectGetWidth(_panelView.bounds);
    CGFloat panelH = CGRectGetHeight(_panelView.bounds);
    CGPoint anchor = CGPointMake(_dragStartAnchor.x + translation.x, _dragStartAnchor.y + translation.y);
    anchor.x = MIN(MAX(anchor.x, panelW * 0.5 + 10.0), boundsW - panelW * 0.5 - 10.0);
    anchor.y = MIN(MAX(anchor.y, panelH * 0.5 + 10.0), boundsH - panelH * 0.5 - 10.0);
    _panelAnchorUnit = CGPointMake(anchor.x / boundsW, anchor.y / boundsH);
    _hasPanelAnchor = YES;
    [self dsLayoutMenu];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setDouble:_panelAnchorUnit.x forKey:kDSHostedMenuPanelXKey];
        [defaults setDouble:_panelAnchorUnit.y forKey:kDSHostedMenuPanelYKey];
    }
}

- (void)dsApplyOrientation {
    if (!_contentView) return;
    CGRect windowBounds = self.view.bounds;
    int orientation = (int)ds_active_orientation();
    if (_hasAppliedOrientation && _appliedOrientation == orientation &&
        CGRectEqualToRect(_appliedWindowBounds, windowBounds)) return;
    _hasAppliedOrientation = YES;
    _appliedOrientation = orientation;
    _appliedWindowBounds = windowBounds;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _contentView.center = CGPointMake(CGRectGetWidth(windowBounds) * 0.5, CGRectGetHeight(windowBounds) * 0.5);
    if (UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)orientation)) {
        _contentView.bounds = CGRectMake(0, 0, CGRectGetHeight(windowBounds), CGRectGetWidth(windowBounds));
        double angle = (orientation == UIInterfaceOrientationLandscapeLeft) ? -M_PI_2 : M_PI_2;
        _contentView.transform = CGAffineTransformMakeRotation(angle);
    } else {
        _contentView.bounds = windowBounds;
        _contentView.transform = CGAffineTransformIdentity;
    }
    [CATransaction commit];
    [self dsLayoutMenu];
}

- (BOOL)dsShouldAcceptHitView:(UIView *)hitView {
    if (!hitView || hitView == self.view || hitView == _contentView) return NO;
    for (UIView *view = hitView; view; view = view.superview) {
        if (view == _toggleButton) return YES;
        if (view == _panelView) return g_hostedMenuExpanded;
    }
    return NO;
}

- (UIButton *)toggleButton {
    return _toggleButton;
}

- (void)dsEspSwitchChanged:(UISwitch *)sender {
    ds_hosted_esp_set_enabled(sender.on);
}

- (void)dsPubgBoxChanged:(UISwitch *)sender {
    g_pubgEspBox = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_box"];
}

- (void)dsPubgSkeletonChanged:(UISwitch *)sender {
    g_pubgEspSkeleton = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_skeleton"];
}

- (void)dsPubgLineChanged:(UISwitch *)sender {
    g_pubgEspLine = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_line"];
}

- (void)dsPubgHealthChanged:(UISwitch *)sender {
    g_pubgEspHealth = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_health"];
}

- (void)dsPubgNameChanged:(UISwitch *)sender {
    g_pubgEspName = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_name"];
}

- (void)dsPubgDistChanged:(UISwitch *)sender {
    g_pubgEspDist = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_dist"];
}

- (void)dsPubgBotChanged:(UISwitch *)sender {
    g_pubgEspBot = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_bot"];
}

- (void)dsPubgArrowChanged:(UISwitch *)sender {
    g_pubgEspArrow = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_arrow"];
}

- (void)dsPubgGrenadeChanged:(UISwitch *)sender {
    g_pubgEspGrenade = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_grenade"];
}

- (void)dsZoomSliderChanged:(UISlider *)sender {
    g_dspubgMaxDistance = sender.value;
    [self dsUpdateValueLabel];
    [NSUserDefaults.standardUserDefaults setFloat:sender.value forKey:@"pubg_zoom_dist"];
}

- (void)dsPubgWeaponChanged:(UISwitch *)sender {
    g_pubgEspWeapon = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_weapon"];
}

- (void)dsPubgArmorChanged:(UISwitch *)sender {
    g_pubgEspArmor = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_armor"];
}

- (void)dsPubgBagChanged:(UISwitch *)sender {
    g_pubgEspBag = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_bag"];
}

- (void)dsPubgScopeChanged:(UISwitch *)sender {
    g_pubgEspScope = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_scope"];
}

- (void)dsPubgCrateChanged:(UISwitch *)sender {
    g_pubgEspCrate = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_crate"];
}

- (void)dsPubgItemScanSliderChanged:(UISlider *)sender {
    g_pubgItemMaxDistance = sender.value;
    _pubgItemScanValueLabel.text = [NSString stringWithFormat:@"%.0fm", sender.value];
    [NSUserDefaults.standardUserDefaults setFloat:sender.value forKey:@"pubg_item_dist"];
}

- (void)dsPubgVehicleChanged:(UISwitch *)sender {
    g_pubgEspVehicle = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_vehicle"];
}

- (void)dsPubgVehicleHpChanged:(UISwitch *)sender {
    g_pubgEspVehicleHp = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_vehicle_hp"];
}

- (void)dsPubgVehicleFuelChanged:(UISwitch *)sender {
    g_pubgEspVehicleFuel = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"pubg_vehicle_fuel"];
}

- (void)dsPubgLangChanged:(UISegmentedControl *)sender {
    g_pubgLanguage = (int)sender.selectedSegmentIndex;
    [NSUserDefaults.standardUserDefaults setInteger:g_pubgLanguage forKey:@"pubg_lang"];
    [self dsUpdatePubgLanguage];
}

- (void)dsPubgThicknessChanged:(UISlider *)sender {
    g_pubgEspThickness = sender.value;
    _pubgSettingThicknessValueLabel.text = [NSString stringWithFormat:@"%.1f px", sender.value];
    [NSUserDefaults.standardUserDefaults setFloat:sender.value forKey:@"pubg_thickness"];
}

- (void)dsResetTapped:(UIButton *)sender {
    (void)sender;
    [_espSwitch setOn:YES animated:YES];
    ds_hosted_esp_set_enabled(true);
    [_pubgBoxSwitch setOn:YES animated:YES];
    [_pubgSkeletonSwitch setOn:YES animated:YES];
    [_pubgLineSwitch setOn:YES animated:YES];
    [_pubgHealthSwitch setOn:YES animated:YES];
    [_pubgNameSwitch setOn:YES animated:YES];
    [_pubgDistSwitch setOn:YES animated:YES];
    [_pubgBotSwitch setOn:YES animated:YES];
    [_pubgArrowSwitch setOn:YES animated:YES];
    [_pubgGrenadeSwitch setOn:YES animated:YES];
    [_zoomSlider setValue:400.0f animated:YES];
    g_pubgEspBox = YES;
    g_pubgEspSkeleton = YES;
    g_pubgEspLine = YES;
    g_pubgEspHealth = YES;
    g_pubgEspName = YES;
    g_pubgEspDist = YES;
    g_pubgEspBot = YES;
    g_pubgEspArrow = YES;
    g_pubgEspGrenade = YES;
    g_dspubgMaxDistance = 400.0f;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:@"pubg_box"];
    [defaults setBool:YES forKey:@"pubg_skeleton"];
    [defaults setBool:YES forKey:@"pubg_line"];
    [defaults setBool:YES forKey:@"pubg_health"];
    [defaults setBool:YES forKey:@"pubg_name"];
    [defaults setBool:YES forKey:@"pubg_dist"];
    [defaults setBool:YES forKey:@"pubg_bot"];
    [defaults setBool:YES forKey:@"pubg_arrow"];
    [defaults setBool:YES forKey:@"pubg_grenade"];
    [defaults setFloat:400.0f forKey:@"pubg_zoom_dist"];

    [_pubgVehicleSwitch setOn:YES animated:YES];
    [_pubgVehicleHpSwitch setOn:YES animated:YES];
    [_pubgVehicleFuelSwitch setOn:YES animated:YES];
    [_pubgWeaponSwitch setOn:YES animated:YES];
    [_pubgArmorSwitch setOn:YES animated:YES];
    [_pubgBagSwitch setOn:YES animated:YES];
    [_pubgScopeSwitch setOn:YES animated:YES];
    [_pubgCrateSwitch setOn:YES animated:YES];
    [_pubgItemScanSlider setValue:150.0f animated:YES];
    _pubgItemScanValueLabel.text = @"150m";

    g_pubgEspVehicle = YES;
    g_pubgEspVehicleHp = YES;
    g_pubgEspVehicleFuel = YES;
    g_pubgEspWeapon = YES;
    g_pubgEspArmor = YES;
    g_pubgEspBag = YES;
    g_pubgEspScope = YES;
    g_pubgEspCrate = YES;
    g_pubgItemMaxDistance = 150.0f;

    [defaults setBool:YES forKey:@"pubg_vehicle"];
    [defaults setBool:YES forKey:@"pubg_vehicle_hp"];
    [defaults setBool:YES forKey:@"pubg_vehicle_fuel"];
    [defaults setBool:YES forKey:@"pubg_weapon"];
    [defaults setBool:YES forKey:@"pubg_armor"];
    [defaults setBool:YES forKey:@"pubg_bag"];
    [defaults setBool:YES forKey:@"pubg_scope"];
    [defaults setBool:YES forKey:@"pubg_crate"];
    [defaults setFloat:150.0f forKey:@"pubg_item_dist"];

    g_pubgLanguage = 0;
    g_pubgEspThickness = 1.5f;
    [defaults setInteger:0 forKey:@"pubg_lang"];
    [defaults setFloat:1.5f forKey:@"pubg_thickness"];
    _pubgLangSegment.selectedSegmentIndex = 0;
    [_pubgSettingThicknessSlider setValue:1.5f animated:YES];
    _pubgSettingThicknessValueLabel.text = @"1.5 px";
    [self dsUpdatePubgLanguage];
    [self dsUpdateValueLabel];
}

- (void)dsUpdatePubgLanguage {
    if (g_pubgLanguage == 1) {
        _titleLabel.text = @"DS · DARKPUBG";
        [_pubgTabButtonPlayer setTitle:@"ESP" forState:UIControlStateNormal];
        [_pubgTabButtonItems setTitle:@"Items" forState:UIControlStateNormal];
        [_pubgTabButtonVehicles setTitle:@"Vehicles" forState:UIControlStateNormal];
        [_pubgTabButtonSettings setTitle:@"Settings" forState:UIControlStateNormal];

        _espLabel.text = @"Master ESP";
        _pubgBoxLabel.text = @"2D Box";
        _pubgSkeletonLabel.text = @"Skeleton";
        _pubgLineLabel.text = @"Snapline";
        _pubgHealthLabel.text = @"Health Bar";
        _pubgNameLabel.text = @"Player Name";
        _pubgDistLabel.text = @"Distance";
        _pubgBotLabel.text = @"Bot ESP";
        _pubgArrowLabel.text = @"360 Radar Warning";
        _pubgGrenadeLabel.text = @"Grenade Warning";
        _zoomLabel.text = @"Enemy Scan Distance";

        _pubgWeaponLabel.text = @"Weapons & Ammo";
        _pubgArmorLabel.text = @"Armor & Helmet";
        _pubgBagLabel.text = @"Backpacks";
        _pubgScopeLabel.text = @"Scopes";
        _pubgCrateLabel.text = @"Airdrops & Crates";
        _pubgItemScanLabel.text = @"Item Scan Distance";

        _pubgVehicleLabel.text = @"Vehicles";
        _pubgVehicleHpLabel.text = @"Vehicle HP";
        _pubgVehicleFuelLabel.text = @"Vehicle Fuel";

        _pubgSettingLangLabel.text = @"UI Language";
        _pubgSettingThicknessLabel.text = @"ESP Line Thickness";
        _pubgSettingInfoLabel.text = @"System & Performance";
        _pubgSettingInfoDescLabel.text = @"• Refresh Rate: 60/120 FPS Zero-Lag\n• Status: Direct Memory QoS Active";
        [_resetButton setTitle:@"Reset to Defaults" forState:UIControlStateNormal];
    } else {
        _titleLabel.text = @"DS · DARKPUBG";
        [_pubgTabButtonPlayer setTitle:@"ESP" forState:UIControlStateNormal];
        [_pubgTabButtonItems setTitle:@"Vật Phẩm" forState:UIControlStateNormal];
        [_pubgTabButtonVehicles setTitle:@"Xe" forState:UIControlStateNormal];
        [_pubgTabButtonSettings setTitle:@"Cài Đặt" forState:UIControlStateNormal];

        _espLabel.text = @"Bật ESP Master";
        _pubgBoxLabel.text = @"Khung 2D (Box)";
        _pubgSkeletonLabel.text = @"Khung Xương (Skeleton)";
        _pubgLineLabel.text = @"Đường Kẻ (Line)";
        _pubgHealthLabel.text = @"Thanh Máu (Health)";
        _pubgNameLabel.text = @"Tên Địch (Name)";
        _pubgDistLabel.text = @"Khoảng Cách (Distance)";
        _pubgBotLabel.text = @"Hiện Bot AI";
        _pubgArrowLabel.text = @"Cảnh Báo 360 (Radar)";
        _pubgGrenadeLabel.text = @"Cảnh Báo Lựu Đạn";
        _zoomLabel.text = @"Khoảng cách hiện địch";

        _pubgWeaponLabel.text = @"Hiện Súng & Vũ Khí";
        _pubgArmorLabel.text = @"Giáp & Mũ Bảo Hiểm";
        _pubgBagLabel.text = @"Balo & Túi Đồ";
        _pubgScopeLabel.text = @"Ống Ngắm (Scopes)";
        _pubgCrateLabel.text = @"Thùng Thính & Hòm Xác";
        _pubgItemScanLabel.text = @"Khoảng cách vật phẩm";

        _pubgVehicleLabel.text = @"Hiện Phương Tiện (Xe)";
        _pubgVehicleHpLabel.text = @"Hiện Máu Xe";
        _pubgVehicleFuelLabel.text = @"Hiện Bình Xăng Xe";

        _pubgSettingLangLabel.text = @"Ngôn ngữ giao diện";
        _pubgSettingThicknessLabel.text = @"Độ dày nét vẽ địch";
        _pubgSettingInfoLabel.text = @"Hệ thống & Tối ưu";
        _pubgSettingInfoDescLabel.text = @"• Tần số quét: 60/120 FPS Zero-Lag\n• Trạng thái: Direct Memory QoS Active";
        [_resetButton setTitle:@"Khôi phục cài đặt gốc" forState:UIControlStateNormal];
    }
}

- (void)dsUpdateValueLabel {
    _zoomValueLabel.text = [NSString stringWithFormat:@"%.0fm", _zoomSlider.value];
}

@end

static void ds_hosted_menu_set_expanded(BOOL expanded) {
    g_hostedMenuExpanded = expanded;
    if (!g_hostedMenuWindow) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect windowFrame = ds_hosted_menu_frame();
    if (!CGRectEqualToRect(g_hostedMenuWindow.frame, windowFrame))
        g_hostedMenuWindow.frame = windowFrame;
    UIView *rootView = g_hostedMenuWindow.rootViewController.view;
    if (!CGRectEqualToRect(rootView.frame, g_hostedMenuWindow.bounds))
        rootView.frame = g_hostedMenuWindow.bounds;
    [g_hostedMenuViewController dsSetExpanded:expanded];
    [g_hostedMenuViewController dsApplyOrientation];
    [CATransaction commit];
}

static void ds_hosted_menu_register(unsigned contextId) {
    RemoteCall *process = g_springBoard;
    if (!process || !process.trojanMem || !contextId) return;
    if (g_hostedMenuRemoteController) return;
    uint64_t hostClass = ds_remote_class(process, "SBSAccessibilityWindowHostingController");
    if (!hostClass) return;
    uint64_t host = remote_msg(process, hostClass, ds_remote_sel(process, "alloc"), 0, 0, 0, 0);
    if (!host || !ds_remote_invoke_noarg_on_main(process, host, "init")) return;
    uint32_t cid = contextId;
    double level = kDSHostedMenuLevel;
    DSRemoteArgument args[2] = {
        { &cid, sizeof(cid) },
        { &level, sizeof(level) },
    };
    if (ds_remote_invoke_on_main(process, host,
                                 ds_remote_sel(process, "registerWindowWithContextID:atLevel:"),
                                 args, 2)) {
        g_hostedMenuRemoteController = host;
    }
}



// Main thread, all local UIKit. Returns the window's render-server context id.
static unsigned ds_hosted_menu_setup_on_main(void) {
    if (g_hostedMenuWindow) {
        g_hostedMenuWindow.hidden = NO;
        return g_hostedMenuContextId;
    }

    DSESPMenuWindow *window = [[DSESPMenuWindow alloc] initWithFrame:ds_hosted_menu_frame()];
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = kDSHostedMenuLevel;
    if (@available(iOS 13.0, *)) {
        window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    DSESPMenuViewController *rootVC = [[DSESPMenuViewController alloc] init];
    window.rootViewController = rootVC;
    window.hidden = NO;
    [window makeKeyAndVisible];

    unsigned contextId = ((unsigned (*)(id, SEL))objc_msgSend)(window, NSSelectorFromString(@"_contextId"));
    if (!contextId) {
        window.hidden = YES;
        return 0;
    }

    g_hostedMenuWindow = window;
    g_hostedMenuViewController = rootVC;
    g_hostedMenuContextId = contextId;
    ds_hosted_menu_set_expanded(g_hostedMenuExpanded);



    return contextId;
}

static void ds_hosted_menu_ensure(void) {
    if (g_hostedMenuWindow) {
        if (g_hostedMenuContextId && !g_hostedMenuRemoteController) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (now - g_hostedMenuLastRegisterTryAt >= 2.0) {
                g_hostedMenuLastRegisterTryAt = now;
                ds_hosted_menu_register(g_hostedMenuContextId);
            }
        }
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - g_hostedMenuLastSetupTryAt < 2.0) return;
    g_hostedMenuLastSetupTryAt = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        unsigned contextId = ds_hosted_menu_setup_on_main();
        if (contextId) {
            dispatch_async(ds_bridge_queue(), ^{
                ds_hosted_menu_register(contextId);
            });
        }
    });
}

#pragma mark - Mach-O main image identity

static BOOL ds_debug_macho_main_identity(uint64_t vmMap, uint64_t base) {
    struct mach_header_64 header = {};
    if (!ds_debug_read_bytes(vmMap, base, &header, sizeof(header)) ||
        header.magic != MH_MAGIC_64 || header.ncmds == 0 ||
        header.ncmds > 1024 || header.sizeofcmds == 0 ||
        header.sizeofcmds > (64U * 1024U)) {
        return NO;
    }

    std::vector<uint8_t> commands(header.sizeofcmds);
    if (!ds_debug_read_bytes(vmMap, base + sizeof(header),
                             commands.data(), commands.size())) {
        return NO;
    }

    size_t cursor = 0;
    for (uint32_t index = 0; index < header.ncmds; index++) {
        if (cursor + sizeof(struct load_command) > commands.size()) return NO;
        const struct load_command *command =
            (const struct load_command *)(commands.data() + cursor);
        if (command->cmdsize < sizeof(struct load_command) ||
            cursor + command->cmdsize > commands.size()) {
            return NO;
        }
        cursor += command->cmdsize;
    }
    return header.filetype == MH_EXECUTE;
}

static uint64_t ds_debug_find_main_image_base(uint64_t vmMap) {
    // Snapshot region starts under the lock; the identity probes below read
    // target memory and would deadlock on the (non-recursive) regions lock.
    std::vector<uint64_t> starts;
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    for (const DSDebugVMRegion &region : g_debugVMRegions) {
        starts.push_back(region.start);
    }
    os_unfair_lock_unlock(&g_debugVMRegionsLock);
    for (uint64_t start : starts) {
        if (ds_debug_macho_main_identity(vmMap, start)) return start;
    }
    return 0;
}

#pragma mark - Hosted overlay window (registration performed inside SpringBoard)

// The window must be a real UIWindow with these overrides
// (sources/HUDMainWindow.mm — TrollSpeed's proven pattern).
@interface DSESPHostedWindow : UIWindow
@end

@implementation DSESPHostedWindow
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return YES; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
// Keep the render-server context alive when our app backgrounds.
- (BOOL)keepContextInBackground { return YES; }
@end

@interface DSESPHostedViewController : UIViewController
@end

@implementation DSESPHostedViewController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.userInteractionEnabled = NO;
    self.view.opaque = NO;
    self.view.backgroundColor = UIColor.clearColor;
}
- (BOOL)prefersStatusBarHidden { return YES; }
@end

typedef struct {
    uint64_t generation;
    BOOL pubgRenderSourceReady;
} DSHostedRenderSnapshot;

static os_unfair_lock g_hostedSnapshotLock = OS_UNFAIR_LOCK_INIT;
static DSHostedRenderSnapshot g_hostedSnapshots[2] = {};
static int g_hostedPublishedSnapshot = -1;
static uint64_t g_hostedSnapshotGeneration = 0;
static uint64_t g_hostedConsumedGeneration = 0;
static BOOL g_hostedFallbackApplyQueued = NO;
static uint64_t g_hostedFallbackToken = 0;
static std::atomic<double> g_hostedLastDisplayLinkTick(0.0);
static std::atomic<uint32_t> g_hostedMaximumFrameRate(60);
static std::atomic<uint64_t> g_hostedDisplayPulse(0);
// Accessed only by ds_bridge_queue. UINT64_MAX permits the initial setup tick
// before CADisplayLink has delivered its first pulse.
static uint64_t g_hostedConsumedDisplayPulse = UINT64_MAX;
static std::atomic<bool> g_hostedLayerReady(false);
static CADisplayLink *g_hostedDisplayLink = nil;
static CGFloat g_hostedPortraitNotchHeight = 0.0;


static void ds_hosted_consume_render_snapshot(bool fallback,
                                              double timestamp,
                                              double targetTimestamp,
                                              double startedAt);
static void ds_hosted_overlay_frame(void);

static void ds_hosted_configure_display_link(CADisplayLink *displayLink) {
    if (!displayLink) return;
    NSInteger maximum = MAX((NSInteger)UIScreen.mainScreen.maximumFramesPerSecond,
                            (NSInteger)60);
    g_hostedMaximumFrameRate.store((uint32_t)maximum,
                                   std::memory_order_release);
    displayLink.preferredFramesPerSecond = maximum;
    if (@available(iOS 15.0, *)) {
        displayLink.preferredFrameRateRange =
            CAFrameRateRangeMake(60.0, (float)maximum, (float)maximum);
    }
}

@interface DSHostedDisplayLinkDriver : NSObject
- (void)displayLinkDidFire:(CADisplayLink *)displayLink;
@end

@implementation DSHostedDisplayLinkDriver
- (void)displayLinkDidFire:(CADisplayLink *)displayLink {
    double startedAt = CACurrentMediaTime();
    g_hostedDisplayPulse.fetch_add(1, std::memory_order_release);
    g_hostedLastDisplayLinkTick.store(startedAt, std::memory_order_relaxed);
    ds_hosted_consume_render_snapshot(false, displayLink.timestamp,
                                      displayLink.targetTimestamp, startedAt);
    g_hostedLastDisplayLinkTick.store(CACurrentMediaTime(),
                                      std::memory_order_relaxed);

    // Phase-locked frame trigger: Immediately dispatch next memory sample & projection
    // so the next snapshot is ready with zero frame latency when the display link fires next!
    static std::atomic<bool> s_pubgFramePending(false);
    if (!s_pubgFramePending.exchange(true, std::memory_order_acq_rel)) {
        dispatch_async(ds_bridge_queue(), ^{
            s_pubgFramePending.store(false, std::memory_order_release);
            ds_hosted_overlay_frame();
        });
    }
}
@end

static DSHostedDisplayLinkDriver *g_hostedDisplayLinkDriver = nil;

static void ds_hosted_apply_orientation(UIInterfaceOrientation orientation) {
    if (!g_hostedLayer || (int)orientation == g_hostedLastOrientation) return;
    g_hostedLastOrientation = (int)orientation;
    CGRect windowBounds = g_hostedWindow.bounds;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        g_hostedLayer.bounds = CGRectMake(0, 0, windowBounds.size.height,
                                          windowBounds.size.width);
        g_hostedLayer.position = CGPointMake(windowBounds.size.width * 0.5,
                                             windowBounds.size.height * 0.5);
        double angle = orientation == UIInterfaceOrientationLandscapeLeft
            ? -M_PI_2 : M_PI_2;
        g_hostedLayer.affineTransform = CGAffineTransformMakeRotation(angle);
    } else {
        g_hostedLayer.bounds = windowBounds;
        g_hostedLayer.position = CGPointMake(windowBounds.size.width * 0.5,
                                             windowBounds.size.height * 0.5);
        g_hostedLayer.affineTransform = CGAffineTransformIdentity;
    }
    if (g_hostedMenuViewController &&
        (int)orientation != g_hostedMenuLastOrientation) {
        g_hostedMenuLastOrientation = (int)orientation;
        [g_hostedMenuViewController dsApplyOrientation];
    }
}

#pragma mark - PUBG ESP render

static CAShapeLayer *g_hostedPUBGBoxLayers[kDSPUBGMaxPlayers] = {};
static CAShapeLayer *g_hostedPUBGSkeletonLayers[kDSPUBGMaxPlayers] = {};
static CAShapeLayer *g_hostedPUBGLineLayers[kDSPUBGMaxPlayers] = {};
static CAShapeLayer *g_hostedPUBGAIMarkLayers[kDSPUBGMaxPlayers] = {};
static CATextLayer *g_hostedPUBGInfoLabels[kDSPUBGMaxPlayers] = {};
static CALayer *g_hostedPUBGHealthBgLayers[kDSPUBGMaxPlayers] = {};
static CALayer *g_hostedPUBGHealthBarLayers[kDSPUBGMaxPlayers] = {};
static CATextLayer *g_hostedPUBGWeaponLabels[kDSPUBGMaxPlayers] = {};
static CAShapeLayer *g_hostedPUBGArrowLayers[kDSPUBGMaxPlayers] = {};
static CATextLayer *g_hostedPUBGArrowTextLayers[kDSPUBGMaxPlayers] = {};
static CATextLayer *g_hostedPUBGItemLabels[kDSPUBGMaxItems] = {};
static CAShapeLayer *g_hostedPUBGGrenadeTrajLayers[kDSPUBGMaxGrenades] = {};
static CAShapeLayer *g_hostedPUBGGrenadeCircleLayers[kDSPUBGMaxGrenades] = {};
static CAShapeLayer *g_hostedPUBGGrenadeCircleMidLayers[kDSPUBGMaxGrenades] = {};
static CAShapeLayer *g_hostedPUBGGrenadeCircleInnerLayers[kDSPUBGMaxGrenades] = {};
static CAShapeLayer *g_hostedPUBGGrenadeBoxLayers[kDSPUBGMaxGrenades] = {};
static CATextLayer *g_hostedPUBGGrenadeLabels[kDSPUBGMaxGrenades] = {};
static CAShapeLayer *g_hostedPUBGGrenadeDropLineLayers[kDSPUBGMaxGrenades] = {};
static CALayer *g_hostedPUBGGrenadeMarkerLayers[kDSPUBGMaxGrenades] = {};
static CALayer *g_hostedPUBGGrenadeFragLayers[kDSPUBGMaxGrenades] = {};
static CALayer *g_hostedPUBGGrenadeSmokeLayers[kDSPUBGMaxGrenades] = {};
static CALayer *g_hostedPUBGGrenadeBurnLayers[kDSPUBGMaxGrenades] = {};
static CALayer *g_hostedPUBGGrenadeStunLayers[kDSPUBGMaxGrenades] = {};
static CALayer *g_hostedPUBGGrenadeMarkerBgLayers[kDSPUBGMaxGrenades] = {};
static CALayer *g_hostedPUBGGrenadeMarkerFillLayers[kDSPUBGMaxGrenades] = {};
static CATextLayer *g_hostedPUBGGrenadeDangerBanner = nil;
static CAShapeLayer *g_hostedPUBGTopCountBgLayer = nil;
static CATextLayer *g_hostedPUBGTopCountLabel = nil;

static void ds_hosted_pubg_hide_all(void) {
    for (int i = 0; i < kDSPUBGMaxPlayers; i++) {
        if (g_hostedPUBGBoxLayers[i] && !g_hostedPUBGBoxLayers[i].hidden) g_hostedPUBGBoxLayers[i].hidden = YES;
        if (g_hostedPUBGSkeletonLayers[i] && !g_hostedPUBGSkeletonLayers[i].hidden) g_hostedPUBGSkeletonLayers[i].hidden = YES;
        if (g_hostedPUBGLineLayers[i] && !g_hostedPUBGLineLayers[i].hidden) g_hostedPUBGLineLayers[i].hidden = YES;
        if (g_hostedPUBGAIMarkLayers[i] && !g_hostedPUBGAIMarkLayers[i].hidden) g_hostedPUBGAIMarkLayers[i].hidden = YES;
        if (g_hostedPUBGInfoLabels[i] && !g_hostedPUBGInfoLabels[i].hidden) g_hostedPUBGInfoLabels[i].hidden = YES;
        if (g_hostedPUBGHealthBgLayers[i] && !g_hostedPUBGHealthBgLayers[i].hidden) g_hostedPUBGHealthBgLayers[i].hidden = YES;
        if (g_hostedPUBGHealthBarLayers[i] && !g_hostedPUBGHealthBarLayers[i].hidden) g_hostedPUBGHealthBarLayers[i].hidden = YES;
        if (g_hostedPUBGWeaponLabels[i] && !g_hostedPUBGWeaponLabels[i].hidden) g_hostedPUBGWeaponLabels[i].hidden = YES;
        if (g_hostedPUBGArrowLayers[i] && !g_hostedPUBGArrowLayers[i].hidden) g_hostedPUBGArrowLayers[i].hidden = YES;
        if (g_hostedPUBGArrowTextLayers[i] && !g_hostedPUBGArrowTextLayers[i].hidden) g_hostedPUBGArrowTextLayers[i].hidden = YES;
    }
    for (int i = 0; i < kDSPUBGMaxItems; i++) {
        if (g_hostedPUBGItemLabels[i] && !g_hostedPUBGItemLabels[i].hidden) g_hostedPUBGItemLabels[i].hidden = YES;
    }
    for (int i = 0; i < kDSPUBGMaxGrenades; i++) {
        if (g_hostedPUBGGrenadeTrajLayers[i] && !g_hostedPUBGGrenadeTrajLayers[i].hidden) g_hostedPUBGGrenadeTrajLayers[i].hidden = YES;
        if (g_hostedPUBGGrenadeCircleLayers[i] && !g_hostedPUBGGrenadeCircleLayers[i].hidden) g_hostedPUBGGrenadeCircleLayers[i].hidden = YES;
        if (g_hostedPUBGGrenadeCircleMidLayers[i] && !g_hostedPUBGGrenadeCircleMidLayers[i].hidden) g_hostedPUBGGrenadeCircleMidLayers[i].hidden = YES;
        if (g_hostedPUBGGrenadeCircleInnerLayers[i] && !g_hostedPUBGGrenadeCircleInnerLayers[i].hidden) g_hostedPUBGGrenadeCircleInnerLayers[i].hidden = YES;
        if (g_hostedPUBGGrenadeBoxLayers[i] && !g_hostedPUBGGrenadeBoxLayers[i].hidden) g_hostedPUBGGrenadeBoxLayers[i].hidden = YES;
        if (g_hostedPUBGGrenadeLabels[i] && !g_hostedPUBGGrenadeLabels[i].hidden) g_hostedPUBGGrenadeLabels[i].hidden = YES;
        if (g_hostedPUBGGrenadeDropLineLayers[i] && !g_hostedPUBGGrenadeDropLineLayers[i].hidden) g_hostedPUBGGrenadeDropLineLayers[i].hidden = YES;
        if (g_hostedPUBGGrenadeMarkerLayers[i] && !g_hostedPUBGGrenadeMarkerLayers[i].hidden) g_hostedPUBGGrenadeMarkerLayers[i].hidden = YES;
    }
    if (g_hostedPUBGGrenadeDangerBanner && !g_hostedPUBGGrenadeDangerBanner.hidden) g_hostedPUBGGrenadeDangerBanner.hidden = YES;
    if (g_hostedPUBGTopCountBgLayer && !g_hostedPUBGTopCountBgLayer.hidden) g_hostedPUBGTopCountBgLayer.hidden = YES;
    if (g_hostedPUBGTopCountLabel && !g_hostedPUBGTopCountLabel.hidden) g_hostedPUBGTopCountLabel.hidden = YES;
}

static CGColorRef ds_pubg_cgcolor_from_rgba(uint32_t rgba) {
    static struct CachedColor {
        uint32_t rgba;
        CGColorRef color;
    } s_colorCache[24] = {};
    static int s_colorCount = 0;

    for (int i = 0; i < s_colorCount; i++) {
        if (s_colorCache[i].rgba == rgba) {
            return s_colorCache[i].color;
        }
    }

    CGFloat r = ((rgba >> 24) & 0xFF) / 255.0;
    CGFloat g = ((rgba >> 16) & 0xFF) / 255.0;
    CGFloat b = ((rgba >> 8) & 0xFF) / 255.0;
    CGFloat a = (rgba & 0xFF) / 255.0;
    CGColorRef newColor = [UIColor colorWithRed:r green:g blue:b alpha:a].CGColor;
    if (s_colorCount < 24) {
        s_colorCache[s_colorCount].rgba = rgba;
        s_colorCache[s_colorCount].color = CGColorRetain(newColor);
        s_colorCount++;
        return newColor;
    }
    return newColor;
}

static void ds_hosted_apply_pubg(void) {
    if (!g_hostedLayer) return;
    if (!ds_hosted_esp_enabled()) {
        ds_hosted_pubg_hide_all();
        return;
    }
    UIInterfaceOrientation orientation = ds_active_orientation();
    if (!UIInterfaceOrientationIsLandscape(orientation)) {
        if (ds_pubg_has_render_source()) {
            orientation = UIInterfaceOrientationLandscapeRight;
        } else {
            ds_hosted_pubg_hide_all();
            return;
        }
    }

    DSPUBGProjectedPlayer players[kDSPUBGMaxPlayers] = {};
    uint64_t epoch = 0;
    int count = ds_pubg_copy_projected_players(players, &epoch);
    if (count < 0) return;
    if (count > kDSPUBGMaxPlayers) count = kDSPUBGMaxPlayers;

    const CGFloat width = CGRectGetWidth(g_hostedLayer.bounds);
    const CGFloat height = CGRectGetHeight(g_hostedLayer.bounds);

    static UIFont *s_infoFont = nil;
    static UIFont *s_wFont = nil;
    static UIFont *s_itemTitleFont = nil;
    static UIFont *s_itemSubFont = nil;
    static UIFont *s_itemFont = nil;
    static UIFont *s_itemBigWeaponFont = nil;
    static NSMutableParagraphStyle *s_centerStyle = nil;
    static dispatch_once_t s_pubgFontOnce;
    dispatch_once(&s_pubgFontOnce, ^{
        s_infoFont = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
        s_wFont = [UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
        s_itemTitleFont = [UIFont systemFontOfSize:9.0 weight:UIFontWeightBold];
        s_itemSubFont = [UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
        s_itemFont = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
        s_itemBigWeaponFont = [UIFont systemFontOfSize:12.5 weight:UIFontWeightHeavy];
        s_centerStyle = [[NSMutableParagraphStyle alloc] init];
        s_centerStyle.alignment = NSTextAlignmentCenter;
        s_centerStyle.lineBreakMode = NSLineBreakByClipping;
        s_centerStyle.lineSpacing = -1.5;
    });

    int totalEnemies = 0;
    int totalBots = 0;
    ds_pubg_get_total_counts(&totalEnemies, &totalBots);

    int activeEnemyCount = 0;
    int activeBotCount = 0;

    for (int i = 0; i < count; i++) {
        const DSPUBGProjectedPlayer &p = players[i];
        CAShapeLayer *box = g_hostedPUBGBoxLayers[i];
        CAShapeLayer *skel = g_hostedPUBGSkeletonLayers[i];
        CAShapeLayer *line = g_hostedPUBGLineLayers[i];
        CAShapeLayer *aiMark = g_hostedPUBGAIMarkLayers[i];
        CATextLayer *info = g_hostedPUBGInfoLabels[i];
        CALayer *hpBg = g_hostedPUBGHealthBgLayers[i];
        CALayer *hpBar = g_hostedPUBGHealthBarLayers[i];
        CATextLayer *wLabel = g_hostedPUBGWeaponLabels[i];
        CAShapeLayer *arrow = g_hostedPUBGArrowLayers[i];
        CATextLayer *arrowText = g_hostedPUBGArrowTextLayers[i];
        if (!box || !line || !info || !hpBar) continue;

        BOOL ai = p.isAI;

        if (!p.isVisible || p.screenX < -150 || p.screenX > width + 150 ||
            p.screenY < -150 || p.screenY > height + 150) {
            box.hidden = YES;
            if (skel) skel.hidden = YES;
            line.hidden = YES;
            if (aiMark) aiMark.hidden = YES;
            info.hidden = YES;
            if (hpBg) hpBg.hidden = YES;
            hpBar.hidden = YES;
            if (wLabel) wLabel.hidden = YES;

            if (!g_pubgEspArrow || !arrow || !arrowText) {
                if (arrow) arrow.hidden = YES;
                if (arrowText) arrowText.hidden = YES;
                continue;
            }

            if (ai && !g_pubgEspBot) {
                arrow.hidden = YES;
                arrowText.hidden = YES;
                continue;
            }

            if (ai) activeBotCount++;
            else activeEnemyCount++;

            // 3D Direction Arrow around screen boundary
            float tx = p.camRelX;
            float ty = p.camRelY;
            float tz = p.camRelZ;

            float dirX = 0.0f;
            float dirY = 0.0f;
            if (tz > 0.1f) {
                dirX = tx;
                dirY = -ty; // Negative Y is UP in screen coords
            } else {
                float h = hypotf(tx, tz);
                if (h < 0.001f) h = 0.001f;
                dirX = tx / h;
                dirY = -tz / h; // When tz < 0, -tz > 0 (points DOWN/behind)
            }

            float dirLen = hypotf(dirX, dirY);
            if (dirLen < 0.001f) {
                dirX = 0.0f;
                dirY = 1.0f;
            } else {
                dirX /= dirLen;
                dirY /= dirLen;
            }

            // Screen boundary clamping with safe device margins
            const CGFloat padX = 38.0f;
            const CGFloat padY = 32.0f;
            CGFloat minX = padX;
            CGFloat maxX = width - padX;
            CGFloat minY = padY;
            CGFloat maxY = height - padY;
            CGFloat cx = width * 0.5f;
            CGFloat cy = height * 0.5f;

            CGFloat tx_bound = (dirX > 0.0001f) ? (maxX - cx) / dirX : ((dirX < -0.0001f) ? (minX - cx) / dirX : 1e9f);
            CGFloat ty_bound = (dirY > 0.0001f) ? (maxY - cy) / dirY : ((dirY < -0.0001f) ? (minY - cy) / dirY : 1e9f);
            CGFloat t = fminf(tx_bound, ty_bound);

            CGFloat arrowTipX = cx + t * dirX;
            CGFloat arrowTipY = cy + t * dirY;
            CGFloat angle = atan2f(dirY, dirX);

            CGFloat arrowLen = 14.0f;
            CGFloat arrowHalfW = 6.0f;
            CGFloat cosA = cosf(angle);
            CGFloat sinA = sinf(angle);

            CGFloat baseCX = arrowTipX - cosA * arrowLen;
            CGFloat baseCY = arrowTipY - sinA * arrowLen;
            CGFloat normX = -sinA;
            CGFloat normY = cosA;

            CGFloat p1X = baseCX + normX * arrowHalfW;
            CGFloat p1Y = baseCY + normY * arrowHalfW;
            CGFloat p2X = baseCX - normX * arrowHalfW;
            CGFloat p2Y = baseCY - normY * arrowHalfW;

            UIBezierPath *arrowPath = [UIBezierPath bezierPath];
            [arrowPath moveToPoint:CGPointMake(arrowTipX, arrowTipY)];
            [arrowPath addLineToPoint:CGPointMake(p1X, p1Y)];
            [arrowPath addLineToPoint:CGPointMake(p2X, p2Y)];
            [arrowPath closePath];

            arrow.path = arrowPath.CGPath;

            UIColor *arrowColor;
            if (ai) {
                arrowColor = [UIColor colorWithRed:0.0/255.0 green:170.0/255.0 blue:255.0/255.0 alpha:0.95];
            } else if (p.isKnocked) {
                arrowColor = [UIColor colorWithRed:255.0/255.0 green:149.0/255.0 blue:0.0/255.0 alpha:0.95];
            } else if (p.distanceMeters < 50.0f) {
                arrowColor = [UIColor colorWithRed:255.0/255.0 green:59.0/255.0 blue:48.0/255.0 alpha:0.95];
            } else {
                arrowColor = [UIColor colorWithRed:255.0/255.0 green:214.0/255.0 blue:10.0/255.0 alpha:0.95];
            }

            arrow.fillColor = arrowColor.CGColor;
            arrow.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
            arrow.lineWidth = 1.0;
            arrow.hidden = NO;

            // Distance text label placed inside the arrow (towards screen center)
            CGFloat textOffset = arrowLen + 11.0f;
            CGFloat textCX = arrowTipX - cosA * textOffset;
            CGFloat textCY = arrowTipY - sinA * textOffset;

            CGFloat lblW = 46.0f;
            CGFloat lblH = 14.0f;
            arrowText.frame = CGRectMake(textCX - lblW * 0.5f, textCY - lblH * 0.5f, lblW, lblH);
            arrowText.string = [NSString stringWithFormat:@"%.0fm", p.distanceMeters];
            arrowText.foregroundColor = arrowColor.CGColor;
            arrowText.hidden = NO;
            continue;
        }

        // On-screen player: hide arrow
        if (arrow) arrow.hidden = YES;
        if (arrowText) arrowText.hidden = YES;

        // Honor user filters
        if (ai && !g_pubgEspBot) {
            box.hidden = YES;
            if (skel) skel.hidden = YES;
            line.hidden = YES;
            if (aiMark) aiMark.hidden = YES;
            info.hidden = YES;
            if (hpBg) hpBg.hidden = YES;
            hpBar.hidden = YES;
            if (wLabel) wLabel.hidden = YES;
            continue;
        }

        if (ai) activeBotCount++;
        else activeEnemyCount++;

        CGFloat centerX = p.screenX + p.boxWidth * 0.5f;
        CGFloat topY = p.screenY;
        CGFloat bottomY = p.screenY + p.boxHeight;

        // 1. Bounding Box: Hộp 4 line 4 góc (Corner Box ESP)
        if (g_pubgEspBox) {
            CGFloat bx = p.screenX;
            CGFloat by = p.screenY;
            CGFloat bw = p.boxWidth;
            CGFloat bh = p.boxHeight;

            // Chiều dài mỗi đoạn line ở 4 góc (1/4 chiều rộng, 1/5 chiều cao)
            CGFloat lineW = bw * 0.25f;
            CGFloat lineH = bh * 0.20f;
            if (lineW < 4.0f) lineW = 4.0f;
            if (lineH < 4.0f) lineH = 4.0f;
            if (lineW > bw * 0.45f) lineW = bw * 0.45f;
            if (lineH > bh * 0.45f) lineH = bh * 0.45f;

            UIBezierPath *boxPath = [UIBezierPath bezierPath];

            // Góc trên - trái (Top-Left)
            [boxPath moveToPoint:CGPointMake(bx, by + lineH)];
            [boxPath addLineToPoint:CGPointMake(bx, by)];
            [boxPath addLineToPoint:CGPointMake(bx + lineW, by)];

            // Góc trên - phải (Top-Right)
            [boxPath moveToPoint:CGPointMake(bx + bw - lineW, by)];
            [boxPath addLineToPoint:CGPointMake(bx + bw, by)];
            [boxPath addLineToPoint:CGPointMake(bx + bw, by + lineH)];

            // Góc dưới - trái (Bottom-Left)
            [boxPath moveToPoint:CGPointMake(bx, by + bh - lineH)];
            [boxPath addLineToPoint:CGPointMake(bx, by + bh)];
            [boxPath addLineToPoint:CGPointMake(bx + lineW, by + bh)];

            // Góc dưới - phải (Bottom-Right)
            [boxPath moveToPoint:CGPointMake(bx + bw - lineW, by + bh)];
            [boxPath addLineToPoint:CGPointMake(bx + bw, by + bh)];
            [boxPath addLineToPoint:CGPointMake(bx + bw, by + bh - lineH)];

            box.path = boxPath.CGPath;
            box.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
            box.lineWidth = g_pubgEspThickness;
            box.lineCap = kCALineCapSquare;
            box.lineJoin = kCALineJoinMiter;
            box.hidden = NO;
        } else {
            box.hidden = YES;
        }

        // 2. Snapline: Màu trắng
        if (g_pubgEspLine) {
            UIBezierPath *linePath = [UIBezierPath bezierPath];
            [linePath moveToPoint:CGPointMake(width * 0.5f, 25.0f)];
            [linePath addLineToPoint:CGPointMake(centerX, topY)];
            line.path = linePath.CGPath;
            line.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
            line.lineWidth = g_pubgEspThickness;
            line.hidden = NO;
        } else {
            line.hidden = YES;
        }

        // 4. AI Mark: inverted blue triangle on top of box for AI only
        if (ai && aiMark) {
            CGFloat tx = centerX;
            CGFloat ty = topY - 5.0f;
            UIBezierPath *triPath = [UIBezierPath bezierPath];
            [triPath moveToPoint:CGPointMake(tx, ty - 9.0f)];
            [triPath addLineToPoint:CGPointMake(tx - 7.0f, ty)];
            [triPath addLineToPoint:CGPointMake(tx + 7.0f, ty)];
            [triPath closePath];
            aiMark.path = triPath.CGPath;
            aiMark.fillColor = [UIColor colorWithRed:0.0/255.0 green:170.0/255.0 blue:255.0/255.0 alpha:0.85].CGColor;
            aiMark.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
            aiMark.lineWidth = fmaxf(1.0f, g_pubgEspThickness * 0.8f);
            aiMark.hidden = NO;
        } else if (aiMark) {
            aiMark.hidden = YES;
        }

        // 5. Horizontal Health Bar (Máu ngang kiểu thanh nằm trên đầu)
        BOOL showHp = (g_pubgEspHealth && p.healthMax > 0 && p.health >= 0);
        // Fixed dimensions: Doesn't zoom with scope, doesn't shrink with distance
        CGFloat barW = 50.0f;
        CGFloat barH = 3.5f;
        CGFloat barX = centerX - barW * 0.5f;
        // Lowered slightly so it sits right above the head/box instead of floating too high
        CGFloat barY = topY - barH - 1.0f;
        if (showHp) {
            float hpRatio = p.health / p.healthMax;
            if (hpRatio < 0.0f) hpRatio = 0.0f;
            if (hpRatio > 1.0f) hpRatio = 1.0f;
            CGFloat fillW = barW * hpRatio;
            if (fillW < 1.0f && p.health > 0.0f) fillW = 1.0f;

            if (hpBg) {
                hpBg.frame = CGRectMake(barX - 0.5f, barY - 0.5f, barW + 1.0f, barH + 1.0f);
                hpBg.hidden = NO;
            }

            hpBar.frame = CGRectMake(barX, barY, fillW, barH);
            if (p.isKnocked) {
                // Bright safety orange for knocked down (gục ngã / bò)
                hpBar.backgroundColor = [UIColor colorWithRed:255.0/255.0 green:149.0/255.0 blue:0.0/255.0 alpha:1.0].CGColor;
            } else {
                hpBar.backgroundColor = (hpRatio >= 0.60f)
                    ? [UIColor colorWithRed:52.0/255.0 green:199.0/255.0 blue:89.0/255.0 alpha:1.0].CGColor
                    : ((hpRatio >= 0.30f)
                        ? [UIColor colorWithRed:255.0/255.0 green:204.0/255.0 blue:0.0/255.0 alpha:1.0].CGColor
                        : [UIColor colorWithRed:255.0/255.0 green:59.0/255.0 blue:48.0/255.0 alpha:1.0].CGColor);
            }
            hpBar.hidden = NO;
        } else {
            if (hpBg) hpBg.hidden = YES;
            hpBar.hidden = YES;
        }

        // Weapon ESP: Above health bar (or above head if health bar hidden)
        if (wLabel) {
            NSString *weaponText = nil;
            CGColorRef weaponColor = [UIColor colorWithRed:255.0/255.0 green:214.0/255.0 blue:10.0/255.0 alpha:1.0].CGColor;

            BOOL isEn = (g_pubgLanguage == 1);
            if (p.isKnocked) {
                if (p.weaponName[0] != '\0') {
                    weaponText = [NSString stringWithFormat:isEn ? @"⚠️ KNOCKED | %s" : @"⚠️ GỤC | %s", p.weaponName];
                    weaponColor = [UIColor colorWithRed:255.0/255.0 green:214.0/255.0 blue:10.0/255.0 alpha:1.0].CGColor;
                } else {
                    weaponText = isEn ? @"⚠️ KNOCKED | Fist" : @"⚠️ GỤC | Tay";
                    weaponColor = [UIColor colorWithRed:46.0/255.0 green:204.0/255.0 blue:113.0/255.0 alpha:1.0].CGColor;
                }
            } else if (p.weaponName[0] != '\0') {
                weaponText = [NSString stringWithUTF8String:p.weaponName];
                weaponColor = [UIColor colorWithRed:255.0/255.0 green:214.0/255.0 blue:10.0/255.0 alpha:1.0].CGColor;
            } else {
                weaponText = isEn ? @"Fist" : @"Tay";
                weaponColor = [UIColor colorWithRed:46.0/255.0 green:204.0/255.0 blue:113.0/255.0 alpha:1.0].CGColor;
            }

            if (weaponText) {
                CGFloat wLblW = 100.0f;
                CGFloat wLblH = 11.0f;
                CGFloat baseTop = showHp ? barY : topY;
                CGFloat wLblY = baseTop - wLblH - 1.0f;
                wLabel.frame = CGRectMake(centerX - wLblW * 0.5f, wLblY, wLblW, wLblH);
                NSAttributedString *attrW = [[NSAttributedString alloc] initWithString:weaponText attributes:@{
                    NSFontAttributeName: s_wFont,
                    NSForegroundColorAttributeName: [UIColor colorWithCGColor:weaponColor],
                    NSStrokeColorAttributeName: [UIColor blackColor],
                    NSStrokeWidthAttributeName: @(-1.4),
                    NSParagraphStyleAttributeName: s_centerStyle
                }];
                wLabel.string = attrW;
                wLabel.shadowOpacity = 0.0f;
                wLabel.hidden = NO;
            } else {
                wLabel.hidden = YES;
            }
        }

        // 6. Text label: below box at bottom center (tightly anchored right below enemy)
        // Tên: Bot = Xanh nước biển, Người = Vàng
        // Khoảng cách (và team): Trắng
        if (g_pubgEspName || g_pubgEspDist) {
            char teamStr[48] = {0};
            if (p.teamId >= 0 && p.teamId <= 200000000) {
                if (ai) {
                    snprintf(teamStr, sizeof(teamStr), "[Team %d - AI]", p.teamId);
                } else {
                    snprintf(teamStr, sizeof(teamStr), "[Team %d]", p.teamId);
                }
            } else if (ai) {
                snprintf(teamStr, sizeof(teamStr), "[AI]");
            }

            BOOL haveNick = (p.name[0] != '\0' && strncmp(p.name, "Unknown", 7) != 0);
            const char *displayName = haveNick ? p.name : (ai ? "Bot" : (g_pubgLanguage == 1 ? "Enemy" : "Địch"));

            // Màu Tên: Bot = Xanh nước biển, Người = Vàng
            UIColor *nameColor = ai
                ? [UIColor colorWithRed:0.0/255.0 green:170.0/255.0 blue:255.0/255.0 alpha:1.0]
                : [UIColor colorWithRed:255.0/255.0 green:214.0/255.0 blue:10.0/255.0 alpha:1.0];

            // Màu Khoảng cách và team = Trắng
            UIColor *whiteColor = [UIColor colorWithWhite:1.0 alpha:1.0];

            NSMutableAttributedString *attrText = [[NSMutableAttributedString alloc] init];

            if (g_pubgEspName) {
                NSString *nameStr = [NSString stringWithUTF8String:displayName];
                [attrText appendAttributedString:[[NSAttributedString alloc] initWithString:nameStr attributes:@{
                    NSFontAttributeName: s_infoFont,
                    NSForegroundColorAttributeName: nameColor,
                    NSStrokeColorAttributeName: [UIColor blackColor],
                    NSStrokeWidthAttributeName: @(-1.4),
                    NSParagraphStyleAttributeName: s_centerStyle
                }]];
            }

            if (teamStr[0] != '\0') {
                if (attrText.length > 0) {
                    [attrText appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{
                        NSFontAttributeName: s_infoFont,
                        NSParagraphStyleAttributeName: s_centerStyle
                    }]];
                }
                NSString *tStr = [NSString stringWithUTF8String:teamStr];
                [attrText appendAttributedString:[[NSAttributedString alloc] initWithString:tStr attributes:@{
                    NSFontAttributeName: s_infoFont,
                    NSForegroundColorAttributeName: whiteColor,
                    NSStrokeColorAttributeName: [UIColor blackColor],
                    NSStrokeWidthAttributeName: @(-1.4),
                    NSParagraphStyleAttributeName: s_centerStyle
                }]];
            }

            if (g_pubgEspDist) {
                if (attrText.length > 0) {
                    [attrText appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{
                        NSFontAttributeName: s_infoFont,
                        NSParagraphStyleAttributeName: s_centerStyle
                    }]];
                }
                NSString *distStr = [NSString stringWithFormat:@"%.0fm", p.distanceMeters];
                [attrText appendAttributedString:[[NSAttributedString alloc] initWithString:distStr attributes:@{
                    NSFontAttributeName: s_infoFont,
                    NSForegroundColorAttributeName: whiteColor,
                    NSStrokeColorAttributeName: [UIColor blackColor],
                    NSStrokeWidthAttributeName: @(-1.4),
                    NSParagraphStyleAttributeName: s_centerStyle
                }]];
            }

            CGFloat enemyBottom = bottomY;
            if (p.hasSkeleton) {
                CGFloat maxBoneY = -1.0f;
                for (int k = 0; k < 15; k++) {
                    if (p.skeleton[k].valid && p.skeleton[k].y > maxBoneY) {
                        maxBoneY = p.skeleton[k].y;
                    }
                }
                if (maxBoneY > 0.0f) {
                    enemyBottom = fminf(bottomY, maxBoneY + 1.5f);
                }
            }

            CGFloat labelH = 12.0f;
            if (g_pubgEspName && g_pubgEspDist) {
                labelH = (teamStr[0] != '\0') ? 32.0f : 22.0f;
            } else if (g_pubgEspName || g_pubgEspDist) {
                labelH = (teamStr[0] != '\0') ? 22.0f : 12.0f;
            }

            CGFloat labelW = 130.0f;
            info.frame = CGRectMake(centerX - labelW * 0.5f, enemyBottom + 1.0f, labelW, labelH);
            info.string = attrText;
            info.shadowOpacity = 0.0f;
            info.hidden = NO;
        } else {
            info.hidden = YES;
        }

        // 7. Skeleton ESP (Hiện xương kết nối các khớp)
        if (g_pubgEspSkeleton && p.hasSkeleton && skel) {
            @try {
                UIBezierPath *skelPath = [UIBezierPath bezierPath];
                static const int bonePairs[][2] = {
                    {0, 1},                     // Head <-> Neck
                    {1, 2},                     // Neck <-> Pelvis (Spine)
                    {1, 3}, {3, 4}, {4, 5},     // Neck <-> UprR <-> LwrR <-> HandR
                    {1, 6}, {6, 7}, {7, 8},     // Neck <-> UprL <-> LwrL <-> HandL
                    {2, 9}, {9, 10}, {10, 11},  // Pelvis <-> ThighR <-> CalfR <-> FootR
                    {2, 12}, {12, 13}, {13, 14} // Pelvis <-> ThighL <-> CalfL <-> FootL
                };
                const int boneCount = (int)(sizeof(bonePairs) / sizeof(bonePairs[0]));
                int drawnLines = 0;
                for (int b = 0; b < boneCount; b++) {
                    int u = bonePairs[b][0];
                    int v = bonePairs[b][1];
                    if (p.skeleton[u].valid && p.skeleton[v].valid) {
                        float ux = p.skeleton[u].x, uy = p.skeleton[u].y;
                        float vx = p.skeleton[v].x, vy = p.skeleton[v].y;
                        if (!isnan(ux) && !isinf(ux) && !isnan(uy) && !isinf(uy) &&
                            !isnan(vx) && !isinf(vx) && !isnan(vy) && !isinf(vy) &&
                            fabsf(ux) < 10000.0f && fabsf(uy) < 10000.0f &&
                            fabsf(vx) < 10000.0f && fabsf(vy) < 10000.0f) {
                            [skelPath moveToPoint:CGPointMake(ux, uy)];
                            [skelPath addLineToPoint:CGPointMake(vx, vy)];
                            drawnLines++;
                        }
                    }
                }

                // Head Circle (scaled with 3D perspective projection distance)
                if (p.skeleton[0].valid || p.skeleton[15].valid) {
                    float cx = p.skeleton[0].valid ? p.skeleton[0].x : p.skeleton[15].x;
                    float cy = p.skeleton[0].valid ? p.skeleton[0].y : p.skeleton[15].y;
                    if (!isnan(cx) && !isinf(cx) && !isnan(cy) && !isinf(cy) &&
                        fabsf(cx) < 10000.0f && fabsf(cy) < 10000.0f) {
                        float r = p.boxHeight / 18.0f;
                        if (p.skeleton[15].valid && p.skeleton[0].valid) {
                            float dx = p.skeleton[15].x - p.skeleton[0].x;
                            float dy = p.skeleton[15].y - p.skeleton[0].y;
                            float d = hypotf(dx, dy) * 1.1f;
                            if (d >= 0.6f && d <= 30.0f) {
                                r = d;
                            }
                        }
                        if (r < 0.6f) r = 0.6f;
                        if (r > 24.0f) r = 24.0f;

                        [skelPath moveToPoint:CGPointMake(cx + r, cy)];
                        [skelPath addArcWithCenter:CGPointMake(cx, cy)
                                            radius:r
                                        startAngle:0
                                          endAngle:2.0f * (float)M_PI
                                         clockwise:YES];
                        drawnLines++;
                    }
                }

                if (drawnLines > 0) {
                    skel.path = skelPath.CGPath;
                    skel.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
                    skel.lineWidth = g_pubgEspThickness;
                    skel.hidden = NO;
                } else {
                    skel.hidden = YES;
                }
            } @catch (NSException *ex) {
                skel.hidden = YES;
            }
        } else if (skel) {
            skel.hidden = YES;
        }
    }

    for (int i = count; i < kDSPUBGMaxPlayers; i++) {
        if (g_hostedPUBGBoxLayers[i]) g_hostedPUBGBoxLayers[i].hidden = YES;
        if (g_hostedPUBGSkeletonLayers[i]) g_hostedPUBGSkeletonLayers[i].hidden = YES;
        if (g_hostedPUBGLineLayers[i]) g_hostedPUBGLineLayers[i].hidden = YES;
        if (g_hostedPUBGAIMarkLayers[i]) g_hostedPUBGAIMarkLayers[i].hidden = YES;
        if (g_hostedPUBGInfoLabels[i]) g_hostedPUBGInfoLabels[i].hidden = YES;
        if (g_hostedPUBGHealthBgLayers[i]) g_hostedPUBGHealthBgLayers[i].hidden = YES;
        if (g_hostedPUBGHealthBarLayers[i]) g_hostedPUBGHealthBarLayers[i].hidden = YES;
        if (g_hostedPUBGWeaponLabels[i]) g_hostedPUBGWeaponLabels[i].hidden = YES;
        if (g_hostedPUBGArrowLayers[i]) g_hostedPUBGArrowLayers[i].hidden = YES;
        if (g_hostedPUBGArrowTextLayers[i]) g_hostedPUBGArrowTextLayers[i].hidden = YES;
    }

    if (g_hostedPUBGTopCountLabel) {
        if (g_hostedPUBGTopCountBgLayer) {
            g_hostedPUBGTopCountBgLayer.hidden = YES;
        }

        if (ds_pubg_has_render_source()) {
            int total = totalEnemies + totalBots;
            CGFloat lblW = 120.0f;
            CGFloat lblH = 30.0f;
            CGFloat lblX = (width - lblW) * 0.5f;
            CGFloat lblY = 12.0f;

            g_hostedPUBGTopCountLabel.frame = CGRectMake(lblX, lblY, lblW, lblH);
            g_hostedPUBGTopCountLabel.fontSize = 22.0f;
            g_hostedPUBGTopCountLabel.font = (__bridge CFTypeRef)[UIFont monospacedDigitSystemFontOfSize:22.0 weight:UIFontWeightHeavy];
            g_hostedPUBGTopCountLabel.foregroundColor = [UIColor colorWithRed:239.0/255.0 green:68.0/255.0 blue:68.0/255.0 alpha:1.0].CGColor;
            g_hostedPUBGTopCountLabel.backgroundColor = UIColor.clearColor.CGColor;
            g_hostedPUBGTopCountLabel.string = [NSString stringWithFormat:@"%d", total];
            g_hostedPUBGTopCountLabel.hidden = NO;
        } else {
            g_hostedPUBGTopCountLabel.hidden = YES;
        }
    }

    // Render Items / Loot ESP
    DSPUBGProjectedItem items[kDSPUBGMaxItems];
    uint64_t itemEpoch = 0;
    int itemCount = ds_pubg_copy_projected_items(items, &itemEpoch);

    // Anti-overlap vertical stacking for items at the same screen position (capped to 48 nearest items)
    int antiOverlapCount = (itemCount > 48) ? 48 : itemCount;
    CGPoint adjustedPositions[kDSPUBGMaxItems];
    for (int i = 0; i < itemCount; i++) {
        adjustedPositions[i] = CGPointMake(items[i].screenX, items[i].screenY);
    }

    for (int i = 0; i < antiOverlapCount; i++) {
        const DSPUBGProjectedItem &it = items[i];
        if (!it.isVisible) continue;
        for (int j = 0; j < i; j++) {
            if (!items[j].isVisible) continue;
            CGFloat dx = fabsf(adjustedPositions[i].x - adjustedPositions[j].x);
            CGFloat dy = fabsf(adjustedPositions[i].y - adjustedPositions[j].y);
            if (dx < 38.0f && dy < 11.5f) {
                adjustedPositions[i].y = adjustedPositions[j].y - 12.0f;
            }
        }
    }

    for (int i = 0; i < kDSPUBGMaxItems; i++) {
        CATextLayer *lbl = g_hostedPUBGItemLabels[i];
        if (!lbl) continue;

        if (i >= itemCount) {
            if (!lbl.hidden) lbl.hidden = YES;
            continue;
        }

        const DSPUBGProjectedItem &it = items[i];
        bool show = false;
        switch (it.category) {
            case DSPUBGItemCategoryVehicle: show = g_pubgEspVehicle; break;
            case DSPUBGItemCategoryWeapon:  show = (g_pubgEspWeapon || g_pubgEspCrate); break;
            case DSPUBGItemCategoryScope:   show = (g_pubgEspScope || g_pubgEspCrate); break;
            case DSPUBGItemCategoryArmor:   show = (g_pubgEspArmor || g_pubgEspCrate); break;
            case DSPUBGItemCategoryBag:     show = (g_pubgEspBag || g_pubgEspCrate); break;
            case DSPUBGItemCategoryCrate:   show = g_pubgEspCrate; break;
            default: break;
        }

        float maxDist = (it.category == DSPUBGItemCategoryVehicle) ? 450.0f :
                        ((it.category == DSPUBGItemCategoryCrate) ? (g_pubgItemMaxDistance * 2.0f) : g_pubgItemMaxDistance);
        if (!show || !it.isVisible || it.distanceMeters > maxDist) {
            if (!lbl.hidden) lbl.hidden = YES;
            continue;
        }

        NSString *nameStr = [NSString stringWithUTF8String:it.name];
        if (!nameStr || nameStr.length == 0) {
            nameStr = @"Vật Phẩm";
        }

        CGFloat posX = adjustedPositions[i].x;
        CGFloat posY = adjustedPositions[i].y;

        if (it.category == DSPUBGItemCategoryVehicle) {
            NSString *titleStr = nil;
            if ((g_pubgEspVehicleHp && it.hpMax > 0.0f) || (g_pubgEspVehicleFuel && it.fuelMax > 0.0f)) {
                float hpVal = it.hp;
                float fuelPct = (it.fuelMax > 0.0f) ? (it.fuel / it.fuelMax) * 100.0f : 0.0f;
                if (fuelPct < 0.0f) fuelPct = 0.0f;
                if (fuelPct > 100.0f) fuelPct = 100.0f;
                titleStr = [NSString stringWithFormat:@"%@ (%.0fm)\nHP: %.0f | Fuel: %.0f%%", nameStr, it.distanceMeters, hpVal, fuelPct];
                lbl.wrapped = YES;
                lbl.fontSize = 8.5;
            } else {
                titleStr = [NSString stringWithFormat:@"%@ (%.0fm)", nameStr, it.distanceMeters];
                lbl.wrapped = NO;
                lbl.fontSize = 9.0;
            }

            CGFloat strW = 150.0f;
            CGFloat strH = lbl.wrapped ? 26.0f : 14.0f;
            lbl.frame = CGRectMake(posX - strW * 0.5f, posY - strH * 0.5f, strW, strH);
            lbl.foregroundColor = ds_pubg_cgcolor_from_rgba(it.colorRGBA);
            lbl.shadowColor = [UIColor blackColor].CGColor;
            lbl.shadowOpacity = 1.0f;
            lbl.shadowRadius = 1.0f;
            lbl.shadowOffset = CGSizeZero;
            lbl.string = titleStr;
            if (lbl.hidden) lbl.hidden = NO;
        } else {
            NSString *itemText = [NSString stringWithFormat:@"%@ (%.0fm)", nameStr, it.distanceMeters];
            CGFloat strW = it.isPriority ? 120.0f : 110.0f;
            CGFloat strH = it.isPriority ? 16.0f : 13.0f;
            lbl.frame = CGRectMake(posX - strW * 0.5f, posY - strH * 0.5f, strW, strH);
            lbl.fontSize = it.isPriority ? 10.5 : 8.5;
            lbl.foregroundColor = ds_pubg_cgcolor_from_rgba(it.colorRGBA);
            lbl.shadowColor = [UIColor blackColor].CGColor;
            lbl.shadowOpacity = 1.0f;
            lbl.shadowRadius = 1.0f;
            lbl.shadowOffset = CGSizeZero;
            lbl.wrapped = NO;
            lbl.string = itemText;
            if (lbl.hidden) lbl.hidden = NO;
        }
    }

    // --- GRENADE WARNING RENDERING (Flight Line, Dynamic 3D Bomb Icon, Drop Line, Damage Circle) ---
    DSPUBGProjectedGrenade grenades[kDSPUBGMaxGrenades];
    uint64_t grenadeEpoch = 0;
    int grenadeCount = ds_pubg_copy_projected_grenades(grenades, &grenadeEpoch);

    for (int i = 0; i < kDSPUBGMaxGrenades; i++) {
        CAShapeLayer *trajLayer = g_hostedPUBGGrenadeTrajLayers[i];
        CAShapeLayer *circleOutLayer = g_hostedPUBGGrenadeCircleLayers[i];
        CAShapeLayer *circleMidLayer = g_hostedPUBGGrenadeCircleMidLayers[i];
        CAShapeLayer *circleInLayer = g_hostedPUBGGrenadeCircleInnerLayers[i];
        CAShapeLayer *boxLayer = g_hostedPUBGGrenadeBoxLayers[i];
        CATextLayer *badgeLbl = g_hostedPUBGGrenadeLabels[i];
        CAShapeLayer *dropLineLayer = g_hostedPUBGGrenadeDropLineLayers[i];
        CALayer *markerLayer = g_hostedPUBGGrenadeMarkerLayers[i];

        if (i >= grenadeCount || !g_pubgEspGrenade || !g_hostedEspEnabled) {
            if (trajLayer) trajLayer.hidden = YES;
            if (circleOutLayer) circleOutLayer.hidden = YES;
            if (circleMidLayer) circleMidLayer.hidden = YES;
            if (circleInLayer) circleInLayer.hidden = YES;
            if (boxLayer) boxLayer.hidden = YES;
            if (badgeLbl) badgeLbl.hidden = YES;
            if (dropLineLayer) dropLineLayer.hidden = YES;
            if (markerLayer) markerLayer.hidden = YES;
            continue;
        }

        const DSPUBGProjectedGrenade &g = grenades[i];

        bool hasCircleOnScreen = false;
        for (int k = 0; k < g.circlePointCount; k++) {
            if (g.circlePointsValid[k] || g.circlePointsMidValid[k] || g.circlePointsInnerValid[k]) {
                hasCircleOnScreen = true;
                break;
            }
        }

        if (!g.isVisible && g.trajCount == 0 && !hasCircleOnScreen && !g.hasBox) {
            if (trajLayer) trajLayer.hidden = YES;
            if (circleOutLayer) circleOutLayer.hidden = YES;
            if (circleMidLayer) circleMidLayer.hidden = YES;
            if (circleInLayer) circleInLayer.hidden = YES;
            if (boxLayer) boxLayer.hidden = YES;
            if (badgeLbl) badgeLbl.hidden = YES;
            if (dropLineLayer) dropLineLayer.hidden = YES;
            if (markerLayer) markerLayer.hidden = YES;
            continue;
        }

        // 1. Line bom ném ra (Đường bay & vệt quỹ đạo bay màu trắng mờ mượt mà phía sau quả bom)
        if (trajLayer) {
            if (g.trajCount >= 2) {
                UIBezierPath *linePath = [UIBezierPath bezierPath];
                [linePath moveToPoint:g.trajPoints[0]];
                for (int t = 1; t < g.trajCount; t++) {
                    [linePath addLineToPoint:g.trajPoints[t]];
                }
                trajLayer.path = linePath.CGPath;
                trajLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;
                trajLayer.lineWidth = 2.0f;
                trajLayer.lineCap = kCALineCapRound;
                trajLayer.lineJoin = kCALineJoinRound;
                trajLayer.hidden = NO;
            } else {
                trajLayer.hidden = YES;
            }
        }

        // Helper lambda to build smooth circle path matching Circle3D
        auto buildCirclePath = [&](const CGPoint *pts, const bool *validPts, int count) -> UIBezierPath * {
            UIBezierPath *p = [UIBezierPath bezierPath];
            int validSegments = 0;
            for (int k = 0; k < count; k++) {
                int next = (k + 1) % count;
                if (validPts[k] && validPts[next]) {
                    [p moveToPoint:pts[k]];
                    [p addLineToPoint:pts[next]];
                    validSegments++;
                }
            }
            return validSegments >= 3 ? p : nil;
        };

        // 2. 3D Damage Circle (Vòng tròn sát thương 3D màu vàng chanh sáng rõ nét như trong ảnh)
        if (circleOutLayer) {
            UIBezierPath *cp = buildCirclePath(g.circlePoints, g.circlePointsValid, g.circlePointCount);
            if (cp) {
                circleOutLayer.path = cp.CGPath;
                circleOutLayer.strokeColor = [UIColor colorWithRed:0.90f green:1.0f blue:0.10f alpha:1.0f].CGColor;
                circleOutLayer.lineWidth = 1.8f;
                circleOutLayer.lineCap = kCALineCapRound;
                circleOutLayer.lineJoin = kCALineJoinRound;
                circleOutLayer.hidden = NO;
            } else {
                circleOutLayer.hidden = YES;
            }
        }
        if (circleMidLayer) circleMidLayer.hidden = YES;
        if (circleInLayer) circleInLayer.hidden = YES;

        // 3. Altitude Drop Line to Ground (Đường line vàng thẳng đứng hạ từ quả bom xuống mặt đất)
        if (dropLineLayer) {
            if (g.hasDropLine && g.isVisible) {
                UIBezierPath *dp = [UIBezierPath bezierPath];
                [dp moveToPoint:CGPointMake(g.screenX, g.screenY + 12.0f)];
                [dp addLineToPoint:g.groundPoint];

                dropLineLayer.path = dp.CGPath;
                dropLineLayer.strokeColor = [UIColor colorWithRed:0.92f green:1.0f blue:0.12f alpha:1.0f].CGColor;
                dropLineLayer.lineWidth = 1.6f;
                dropLineLayer.hidden = NO;
            } else {
                dropLineLayer.hidden = YES;
            }
        }

        // 4. Distinct 3D Throwable Icons (Frag, Smoke, Burn, Stun)
        if (markerLayer) {
            if (g.isVisible) {
                markerLayer.position = CGPointMake(g.screenX, g.screenY);
                markerLayer.hidden = NO;

                CALayer *fragL = g_hostedPUBGGrenadeFragLayers[i];
                CALayer *smokeL = g_hostedPUBGGrenadeSmokeLayers[i];
                CALayer *burnL = g_hostedPUBGGrenadeBurnLayers[i];
                CALayer *stunL = g_hostedPUBGGrenadeStunLayers[i];

                if (g.type == DSPUBGGrenadeTypeSmoke) {
                    if (fragL) fragL.hidden = YES;
                    if (smokeL) smokeL.hidden = NO;
                    if (burnL) burnL.hidden = YES;
                    if (stunL) stunL.hidden = YES;
                } else if (g.type == DSPUBGGrenadeTypeBurn) {
                    if (fragL) fragL.hidden = YES;
                    if (smokeL) smokeL.hidden = YES;
                    if (burnL) burnL.hidden = NO;
                    if (stunL) stunL.hidden = YES;
                } else if (g.type == DSPUBGGrenadeTypeStun) {
                    if (fragL) fragL.hidden = YES;
                    if (smokeL) smokeL.hidden = YES;
                    if (burnL) burnL.hidden = YES;
                    if (stunL) stunL.hidden = NO;
                } else {
                    if (fragL) fragL.hidden = NO;
                    if (smokeL) smokeL.hidden = YES;
                    if (burnL) burnL.hidden = YES;
                    if (stunL) stunL.hidden = YES;

                    float total = (g.totalFuseSeconds > 0.1f) ? g.totalFuseSeconds : 5.0f;
                    float progress = 1.0f - (g.cookSeconds / total);
                    if (progress < 0.0f) progress = 0.0f;
                    if (progress > 1.0f) progress = 1.0f;

                    CALayer *redFill = g_hostedPUBGGrenadeMarkerFillLayers[i];
                    CALayer *bgYellow = g_hostedPUBGGrenadeMarkerBgLayers[i];
                    if (redFill) {
                        CGFloat redH = 22.0f * progress;
                        redFill.frame = CGRectMake(0, 22.0f - redH, 22.0f, redH);
                    }
                    if (bgYellow) {
                        CGFloat gVal = 0.95f - (0.87f * progress);
                        if (gVal < 0.08f) gVal = 0.08f;
                        if (gVal > 0.95f) gVal = 0.95f;
                        bgYellow.backgroundColor = [UIColor colorWithRed:1.0f green:gVal blue:0.05f alpha:1.0f].CGColor;
                    }
                }
            } else {
                markerLayer.hidden = YES;
            }
        }

        // 6. 3D Bounding Box around grenade (< 13m)
        if (boxLayer) {
            if (g.hasBox) {
                UIBezierPath *bp = [UIBezierPath bezierPath];
                [bp moveToPoint:g.boxCorners[0]];
                [bp addLineToPoint:g.boxCorners[1]];
                [bp addLineToPoint:g.boxCorners[2]];
                [bp addLineToPoint:g.boxCorners[3]];
                [bp closePath];
                [bp moveToPoint:g.boxCorners[4]];
                [bp addLineToPoint:g.boxCorners[5]];
                [bp addLineToPoint:g.boxCorners[6]];
                [bp addLineToPoint:g.boxCorners[7]];
                [bp closePath];
                [bp moveToPoint:g.boxCorners[0]]; [bp addLineToPoint:g.boxCorners[4]];
                [bp moveToPoint:g.boxCorners[1]]; [bp addLineToPoint:g.boxCorners[5]];
                [bp moveToPoint:g.boxCorners[2]]; [bp addLineToPoint:g.boxCorners[6]];
                [bp moveToPoint:g.boxCorners[3]]; [bp addLineToPoint:g.boxCorners[7]];

                boxLayer.path = bp.CGPath;
                boxLayer.strokeColor = [UIColor colorWithRed:1.0f green:0.2f blue:0.2f alpha:1.0f].CGColor;
                boxLayer.lineWidth = 1.3f;
                boxLayer.lineCap = kCALineCapRound;
                boxLayer.lineJoin = kCALineJoinRound;
                boxLayer.hidden = NO;
            } else {
                boxLayer.hidden = YES;
            }
        }

        // 7. Distance tag
        if (badgeLbl && g.isVisible) {
            NSString *titleStr = [NSString stringWithUTF8String:g.name];
            NSString *fullBadge = [NSString stringWithFormat:@"%@ [%.0fm]", titleStr, g.distanceMeters];

            NSAttributedString *badgeAttr = [[NSAttributedString alloc] initWithString:fullBadge attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy],
                NSForegroundColorAttributeName: [UIColor colorWithRed:1.0f green:0.2f blue:0.2f alpha:1.0f],
                NSStrokeColorAttributeName: [UIColor blackColor],
                NSStrokeWidthAttributeName: @(-2.2),
                NSParagraphStyleAttributeName: s_centerStyle
            }];

            CGFloat bw = 160.0f;
            CGFloat bh = 18.0f;
            badgeLbl.frame = CGRectMake(g.screenX - bw * 0.5f, g.screenY + 22.0f, bw, bh);
            badgeLbl.backgroundColor = UIColor.clearColor.CGColor;
            badgeLbl.string = badgeAttr;
            badgeLbl.hidden = NO;
        } else if (badgeLbl) {
            badgeLbl.hidden = YES;
        }
    }

    // Banner removed per user request: "không cần làm cái thông báo địch rút bom đâu xoá đi cho tôi"
    if (g_hostedPUBGGrenadeDangerBanner) {
        g_hostedPUBGGrenadeDangerBanner.hidden = YES;
    }
}

static void ds_hosted_consume_render_snapshot(bool fallback,
                                              double timestamp,
                                              double targetTimestamp,
                                              double startedAt) {
    (void)fallback;
    (void)timestamp;
    (void)targetTimestamp;
    (void)startedAt;
    if (!NSThread.isMainThread || !g_hostedLayer) return;
    DSHostedRenderSnapshot snapshot = {};
    BOOL shouldRender = NO;
    os_unfair_lock_lock(&g_hostedSnapshotLock);
    if (g_hostedPublishedSnapshot >= 0) {
        snapshot = g_hostedSnapshots[g_hostedPublishedSnapshot];
    }
    if (snapshot.generation &&
        snapshot.generation != g_hostedConsumedGeneration) {
        g_hostedConsumedGeneration = snapshot.generation;
        shouldRender = YES;
    }
    os_unfair_lock_unlock(&g_hostedSnapshotLock);
    if (!shouldRender) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIInterfaceOrientation renderOri = ds_active_orientation();
    if (!UIInterfaceOrientationIsLandscape(renderOri)) {
        if (ds_pubg_has_render_source()) {
            renderOri = UIInterfaceOrientationLandscapeRight;
        }
    }
    ds_hosted_apply_orientation(renderOri);
    ds_hosted_apply_pubg();
    [CATransaction commit];
    [CATransaction flush];
}

static void ds_hosted_publish_render_snapshot(const DSHostedRenderSnapshot &next) {
    BOOL queueFallback = NO;
    uint64_t fallbackToken = 0;
    double now = CACurrentMediaTime();
    os_unfair_lock_lock(&g_hostedSnapshotLock);
    int writeIndex = g_hostedPublishedSnapshot == 0 ? 1 : 0;
    g_hostedSnapshots[writeIndex] = next;
    g_hostedSnapshots[writeIndex].generation = ++g_hostedSnapshotGeneration;
    g_hostedPublishedSnapshot = writeIndex;
    if (now - g_hostedLastDisplayLinkTick.load(std::memory_order_relaxed) > 0.10 &&
        !g_hostedFallbackApplyQueued) {
        g_hostedFallbackApplyQueued = YES;
        fallbackToken = ++g_hostedFallbackToken;
        queueFallback = YES;
    }
    os_unfair_lock_unlock(&g_hostedSnapshotLock);
    if (queueFallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            double startedAt = CACurrentMediaTime();
            os_unfair_lock_lock(&g_hostedSnapshotLock);
            BOOL validToken = g_hostedFallbackApplyQueued &&
                              fallbackToken == g_hostedFallbackToken;
            BOOL displayLinkResumed =
                g_hostedLastDisplayLinkTick.load(std::memory_order_relaxed) > now;
            os_unfair_lock_unlock(&g_hostedSnapshotLock);
            if (validToken && !displayLinkResumed) {
                ds_hosted_consume_render_snapshot(true, 0.0, 0.0, startedAt);
            }
            os_unfair_lock_lock(&g_hostedSnapshotLock);
            if (fallbackToken == g_hostedFallbackToken) {
                g_hostedFallbackApplyQueued = NO;
            }
            os_unfair_lock_unlock(&g_hostedSnapshotLock);
        });
    }
}

// Registration executed INSIDE SpringBoard via the existing RemoteCall — the
// caller's audit token is then SpringBoard's own, so the accessibility-window
// entitlement check passes without any entitlement patching. One-time setup.
static void ds_hosted_overlay_register(unsigned contextId) {
    RemoteCall *process = g_springBoard;
    if (!process || !process.trojanMem || !contextId) return;
    if (g_hostedRemoteController) return;
    uint64_t hostClass = ds_remote_class(process, "SBSAccessibilityWindowHostingController");
    if (!hostClass) return;
    uint64_t host = remote_msg(process, hostClass, ds_remote_sel(process, "alloc"), 0, 0, 0, 0);
    if (!host || !ds_remote_invoke_noarg_on_main(process, host, "init")) return;
    uint32_t cid = contextId;  // signature "v@:Id": unsigned int + double
    double level = 10000010.0;
    DSRemoteArgument args[2] = {
        { &cid, sizeof(cid) },
        { &level, sizeof(level) },
    };
    if (ds_remote_invoke_on_main(process, host,
                                 ds_remote_sel(process, "registerWindowWithContextID:atLevel:"),
                                 args, 2)) {
        g_hostedRemoteController = host;  // keep the controller alive in SpringBoard
        g_hostedSBPid = (pid_t)process.pid;
    }
}

// Main thread, all local UIKit. Returns the window's render-server context id.
static void ds_hosted_overlay_start_display_link(void) {
    if (g_hostedDisplayLink) return;
    g_hostedDisplayLinkDriver = [[DSHostedDisplayLinkDriver alloc] init];
    g_hostedDisplayLink = [CADisplayLink displayLinkWithTarget:g_hostedDisplayLinkDriver
                                                      selector:@selector(displayLinkDidFire:)];
    ds_hosted_configure_display_link(g_hostedDisplayLink);
    [g_hostedDisplayLink addToRunLoop:NSRunLoop.mainRunLoop
                              forMode:NSRunLoopCommonModes];
}

static unsigned ds_hosted_overlay_setup_on_main(void) {
    if (g_hostedLayer) {
        // Paused earlier: window/context/layers survived — just relink frames.
        g_hostedWindow.hidden = NO;
        g_hostedLayerReady.store(true, std::memory_order_release);
        ds_hosted_overlay_start_display_link();
        return g_hostedContextId;
    }
    g_hostedSetupAttempts++;

    // Read the device cutout from the normal app scene before the secure,
    // status-bar-less hosted window becomes key. Keep this value immutable
    // for the lifetime of the overlay; minimap rendering only consumes it.
    g_hostedPortraitNotchHeight = 0.0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateUnattached)
            continue;
        for (UIWindow *candidate in windowScene.windows) {
            // In landscape the device cutout is reported on left/right,
            // not top. Keep the largest safe-area edge as the portrait
            // notch-equivalent used by the manually rotated overlay.
            UIEdgeInsets insets = candidate.safeAreaInsets;
            CGFloat cutout = MAX(MAX(insets.top, insets.bottom),
                                 MAX(insets.left, insets.right));
            g_hostedPortraitNotchHeight = MAX(
                g_hostedPortraitNotchHeight, cutout);
        }
    }

    // Scene-less window (TrollSpeed pattern): this app has no scene manifest,
    // so the window is not tied to any scene's lifecycle.
    CGRect sceneBounds = UIScreen.mainScreen.bounds;
    CGRect content = sceneBounds;
    if (CGRectGetWidth(content) < CGRectGetHeight(content)) {
        content = CGRectMake(0, 0, CGRectGetHeight(content), CGRectGetWidth(content));
    }
    g_hostedContentBounds = content;

    DSESPHostedWindow *window = [[DSESPHostedWindow alloc] initWithFrame:sceneBounds];
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = 10000010.0;
    DSESPHostedViewController *rootVC = [[DSESPHostedViewController alloc] init];
    window.rootViewController = rootVC;
    UIView *espView = [[UIView alloc] initWithFrame:content];
    espView.userInteractionEnabled = NO;
    espView.opaque = NO;
    espView.clipsToBounds = YES;
    espView.backgroundColor = UIColor.clearColor;
    [rootVC.view addSubview:espView];
    window.hidden = NO;
    [window makeKeyAndVisible];  // forces the render-server context to exist

    unsigned contextId = ((unsigned (*)(id, SEL))objc_msgSend)(window, NSSelectorFromString(@"_contextId"));
    if (!contextId) {
        window.hidden = YES;
        return 0;
    }

    g_hostedWindow = window;
    g_hostedESPView = espView;
    g_hostedLayer = espView.layer;
    g_hostedLayer.contents = nil;

    NSDictionary *noAnim = @{@"position": [NSNull null], @"hidden": [NSNull null],
                             @"string": [NSNull null], @"bounds": [NSNull null],
                             @"frame": [NSNull null], @"backgroundColor": [NSNull null],
                             @"path": [NSNull null], @"strokeColor": [NSNull null],
                             @"fillColor": [NSNull null], @"lineWidth": [NSNull null],
                             @"lineDashPhase": [NSNull null]};
    CGFloat scale = UIScreen.mainScreen.scale;

    // PUBG-only pool: bounding boxes, snaplines, info labels, and health bars
        {
            for (int i = 0; i < kDSPUBGMaxPlayers; i++) {
                CAShapeLayer *box = [CAShapeLayer layer];
                box.actions = noAnim;
                box.contentsScale = scale;
                box.fillColor = UIColor.clearColor.CGColor;
                box.lineWidth = 1.5;
                box.hidden = YES;
                [g_hostedLayer addSublayer:box];
                g_hostedPUBGBoxLayers[i] = box;

                CAShapeLayer *skel = [CAShapeLayer layer];
                skel.actions = noAnim;
                skel.contentsScale = scale;
                skel.fillColor = UIColor.clearColor.CGColor;
                skel.lineWidth = 1.2;
                skel.hidden = YES;
                [g_hostedLayer addSublayer:skel];
                g_hostedPUBGSkeletonLayers[i] = skel;

                CAShapeLayer *line = [CAShapeLayer layer];
                line.actions = noAnim;
                line.contentsScale = scale;
                line.lineWidth = 1.2;
                line.hidden = YES;
                [g_hostedLayer addSublayer:line];
                g_hostedPUBGLineLayers[i] = line;

                CAShapeLayer *aiMark = [CAShapeLayer layer];
                aiMark.actions = noAnim;
                aiMark.contentsScale = scale;
                aiMark.hidden = YES;
                [g_hostedLayer addSublayer:aiMark];
                g_hostedPUBGAIMarkLayers[i] = aiMark;

                CATextLayer *info = [CATextLayer layer];
                info.actions = noAnim;
                info.contentsScale = scale;
                info.alignmentMode = kCAAlignmentCenter;
                info.wrapped = YES;
                info.fontSize = 8.5;
                info.font = (__bridge CFTypeRef)[UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
                info.shadowColor = [UIColor blackColor].CGColor;
                info.shadowOpacity = 0.0f;
                info.shadowRadius = 0.0f;
                info.shadowOffset = CGSizeZero;
                info.hidden = YES;
                [g_hostedLayer addSublayer:info];
                g_hostedPUBGInfoLabels[i] = info;

                CALayer *hpBg = [CALayer layer];
                hpBg.actions = noAnim;
                hpBg.contentsScale = scale;
                hpBg.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65].CGColor;
                hpBg.cornerRadius = 1.5;
                hpBg.hidden = YES;
                [g_hostedLayer addSublayer:hpBg];
                g_hostedPUBGHealthBgLayers[i] = hpBg;

                CALayer *hpBar = [CALayer layer];
                hpBar.actions = noAnim;
                hpBar.contentsScale = scale;
                hpBar.cornerRadius = 1.5;
                hpBar.hidden = YES;
                [g_hostedLayer addSublayer:hpBar];
                g_hostedPUBGHealthBarLayers[i] = hpBar;

                CATextLayer *wLabel = [CATextLayer layer];
                wLabel.actions = noAnim;
                wLabel.contentsScale = scale;
                wLabel.alignmentMode = kCAAlignmentCenter;
                wLabel.fontSize = 8.0;
                wLabel.font = (__bridge CFTypeRef)[UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
                wLabel.shadowColor = [UIColor blackColor].CGColor;
                wLabel.shadowOpacity = 0.0f;
                wLabel.shadowRadius = 0.0f;
                wLabel.shadowOffset = CGSizeZero;
                wLabel.hidden = YES;
                [g_hostedLayer addSublayer:wLabel];
                g_hostedPUBGWeaponLabels[i] = wLabel;

                CAShapeLayer *arrow = [CAShapeLayer layer];
                arrow.actions = noAnim;
                arrow.contentsScale = scale;
                arrow.hidden = YES;
                [g_hostedLayer addSublayer:arrow];
                g_hostedPUBGArrowLayers[i] = arrow;

                CATextLayer *arrowText = [CATextLayer layer];
                arrowText.actions = noAnim;
                arrowText.contentsScale = scale;
                arrowText.alignmentMode = kCAAlignmentCenter;
                arrowText.fontSize = 8.5;
                arrowText.font = (__bridge CFTypeRef)[UIFont monospacedDigitSystemFontOfSize:8.5 weight:UIFontWeightHeavy];
                arrowText.shadowColor = [UIColor blackColor].CGColor;
                arrowText.shadowOpacity = 0.0f;
                arrowText.shadowRadius = 0.0f;
                arrowText.shadowOffset = CGSizeZero;
                arrowText.hidden = YES;
                [g_hostedLayer addSublayer:arrowText];
                g_hostedPUBGArrowTextLayers[i] = arrowText;
            }

            for (int i = 0; i < kDSPUBGMaxItems; i++) {
                CATextLayer *itemLbl = [CATextLayer layer];
                itemLbl.actions = noAnim;
                itemLbl.contentsScale = scale;
                itemLbl.alignmentMode = kCAAlignmentCenter;
                itemLbl.wrapped = NO;
                itemLbl.font = (__bridge CFTypeRef)[UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
                itemLbl.fontSize = 8.5;
                itemLbl.shadowColor = UIColor.blackColor.CGColor;
                itemLbl.shadowRadius = 1.0;
                itemLbl.shadowOpacity = 1.0;
                itemLbl.shadowOffset = CGSizeZero;
                itemLbl.hidden = YES;
                [g_hostedLayer addSublayer:itemLbl];
                g_hostedPUBGItemLabels[i] = itemLbl;
            }

            for (int i = 0; i < kDSPUBGMaxGrenades; i++) {
                CAShapeLayer *traj = [CAShapeLayer layer];
                traj.actions = noAnim;
                traj.contentsScale = scale;
                traj.fillColor = UIColor.clearColor.CGColor;
                traj.lineCap = kCALineCapRound;
                traj.lineJoin = kCALineJoinRound;
                traj.lineWidth = 2.0;
                traj.hidden = YES;
                [g_hostedLayer addSublayer:traj];
                g_hostedPUBGGrenadeTrajLayers[i] = traj;

                CAShapeLayer *circOut = [CAShapeLayer layer];
                circOut.actions = noAnim;
                circOut.contentsScale = scale;
                circOut.fillColor = UIColor.clearColor.CGColor;
                circOut.lineCap = kCALineCapRound;
                circOut.lineJoin = kCALineJoinRound;
                circOut.lineWidth = 1.8;
                circOut.hidden = YES;
                [g_hostedLayer addSublayer:circOut];
                g_hostedPUBGGrenadeCircleLayers[i] = circOut;

                CAShapeLayer *circMid = [CAShapeLayer layer];
                circMid.actions = noAnim;
                circMid.contentsScale = scale;
                circMid.fillColor = UIColor.clearColor.CGColor;
                circMid.hidden = YES;
                [g_hostedLayer addSublayer:circMid];
                g_hostedPUBGGrenadeCircleMidLayers[i] = circMid;

                CAShapeLayer *circIn = [CAShapeLayer layer];
                circIn.actions = noAnim;
                circIn.contentsScale = scale;
                circIn.fillColor = UIColor.clearColor.CGColor;
                circIn.hidden = YES;
                [g_hostedLayer addSublayer:circIn];
                g_hostedPUBGGrenadeCircleInnerLayers[i] = circIn;

                CAShapeLayer *dropLine = [CAShapeLayer layer];
                dropLine.actions = noAnim;
                dropLine.contentsScale = scale;
                dropLine.fillColor = UIColor.clearColor.CGColor;
                dropLine.lineCap = kCALineCapRound;
                dropLine.lineJoin = kCALineJoinRound;
                dropLine.lineWidth = 1.6;
                dropLine.hidden = YES;
                [g_hostedLayer addSublayer:dropLine];
                g_hostedPUBGGrenadeDropLineLayers[i] = dropLine;

                // Container for Distinct Throwable 3D Markers (32x32 pt)
                CALayer *markerContainer = [CALayer layer];
                markerContainer.actions = noAnim;
                markerContainer.contentsScale = scale;
                markerContainer.bounds = CGRectMake(0, 0, 32.0, 32.0);
                markerContainer.hidden = YES;

                // --- 1. FRAG GRENADE GROUP (Lựu Đạn: Circular bomb with dynamic yellow-to-red countdown) ---
                CALayer *fragGroup = [CALayer layer];
                fragGroup.actions = noAnim;
                fragGroup.contentsScale = scale;
                fragGroup.frame = CGRectMake(0, 0, 32.0, 32.0);

                CALayer *fusePin = [CALayer layer];
                fusePin.actions = noAnim;
                fusePin.contentsScale = scale;
                fusePin.frame = CGRectMake(20.5, 2.5, 5.0, 5.5);
                fusePin.cornerRadius = 1.0;
                fusePin.backgroundColor = [UIColor colorWithRed:0.85f green:1.0f blue:0.20f alpha:1.0f].CGColor;
                [fragGroup addSublayer:fusePin];

                CALayer *circleBody = [CALayer layer];
                circleBody.actions = noAnim;
                circleBody.contentsScale = scale;
                circleBody.frame = CGRectMake(5.0, 5.0, 22.0, 22.0);
                circleBody.cornerRadius = 11.0;
                circleBody.masksToBounds = YES;
                circleBody.backgroundColor = [UIColor colorWithRed:1.0f green:0.95f blue:0.05f alpha:1.0f].CGColor;
                [fragGroup addSublayer:circleBody];
                g_hostedPUBGGrenadeMarkerBgLayers[i] = circleBody;

                CALayer *redFill = [CALayer layer];
                redFill.actions = noAnim;
                redFill.contentsScale = scale;
                redFill.backgroundColor = [UIColor colorWithRed:0.95f green:0.08f blue:0.08f alpha:1.0f].CGColor;
                redFill.frame = CGRectMake(0, 22.0, 22.0, 0);
                [circleBody addSublayer:redFill];
                g_hostedPUBGGrenadeMarkerFillLayers[i] = redFill;

                CAShapeLayer *borderLayer = [CAShapeLayer layer];
                borderLayer.actions = noAnim;
                borderLayer.contentsScale = scale;
                UIBezierPath *bPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(5.0, 5.0, 22.0, 22.0)];
                borderLayer.path = bPath.CGPath;
                borderLayer.fillColor = UIColor.clearColor.CGColor;
                borderLayer.strokeColor = UIColor.whiteColor.CGColor;
                borderLayer.lineWidth = 1.6;
                [fragGroup addSublayer:borderLayer];

                CAShapeLayer *shineLayer = [CAShapeLayer layer];
                shineLayer.actions = noAnim;
                shineLayer.contentsScale = scale;
                UIBezierPath *sPath = [UIBezierPath bezierPath];
                [sPath addArcWithCenter:CGPointMake(16.0, 16.0) radius:8.5 startAngle:3.4 endAngle:4.3 clockwise:YES];
                shineLayer.path = sPath.CGPath;
                shineLayer.fillColor = UIColor.clearColor.CGColor;
                shineLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
                shineLayer.lineWidth = 1.8;
                shineLayer.lineCap = kCALineCapRound;
                [fragGroup addSublayer:shineLayer];
                [markerContainer addSublayer:fragGroup];
                g_hostedPUBGGrenadeFragLayers[i] = fragGroup;

                // --- 2. SMOKE GRENADE GROUP (Bom Khói: Canister with cyan/white band) ---
                CALayer *smokeGroup = [CALayer layer];
                smokeGroup.actions = noAnim;
                smokeGroup.contentsScale = scale;
                smokeGroup.frame = CGRectMake(0, 0, 32.0, 32.0);
                smokeGroup.hidden = YES;

                CALayer *smkCap = [CALayer layer];
                smkCap.actions = noAnim;
                smkCap.contentsScale = scale;
                smkCap.frame = CGRectMake(12.0, 3.5, 8.0, 4.0);
                smkCap.cornerRadius = 1.5;
                smkCap.backgroundColor = [UIColor colorWithWhite:0.88 alpha:1.0].CGColor;
                [smokeGroup addSublayer:smkCap];

                CALayer *smkBody = [CALayer layer];
                smkBody.actions = noAnim;
                smkBody.contentsScale = scale;
                smkBody.frame = CGRectMake(8.0, 7.0, 16.0, 21.0);
                smkBody.cornerRadius = 3.5;
                smkBody.masksToBounds = YES;
                smkBody.backgroundColor = [UIColor colorWithRed:0.22f green:0.28f blue:0.35f alpha:0.95f].CGColor;

                CALayer *smkStripe = [CALayer layer];
                smkStripe.actions = noAnim;
                smkStripe.contentsScale = scale;
                smkStripe.frame = CGRectMake(0, 7.0, 16.0, 6.5);
                smkStripe.backgroundColor = [UIColor colorWithRed:0.0f green:0.85f blue:0.90f alpha:1.0f].CGColor;
                [smkBody addSublayer:smkStripe];
                [smokeGroup addSublayer:smkBody];

                CAShapeLayer *smkBorder = [CAShapeLayer layer];
                smkBorder.actions = noAnim;
                smkBorder.contentsScale = scale;
                UIBezierPath *smkPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(8.0, 7.0, 16.0, 21.0) cornerRadius:3.5];
                smkBorder.path = smkPath.CGPath;
                smkBorder.fillColor = UIColor.clearColor.CGColor;
                smkBorder.strokeColor = UIColor.whiteColor.CGColor;
                smkBorder.lineWidth = 1.4;
                [smokeGroup addSublayer:smkBorder];

                CATextLayer *smkText = [CATextLayer layer];
                smkText.actions = noAnim;
                smkText.contentsScale = scale;
                smkText.alignmentMode = kCAAlignmentCenter;
                smkText.fontSize = 7.5;
                smkText.font = (__bridge CFTypeRef)[UIFont monospacedDigitSystemFontOfSize:7.5 weight:UIFontWeightHeavy];
                smkText.foregroundColor = UIColor.whiteColor.CGColor;
                smkText.frame = CGRectMake(7.0, 15.0, 18.0, 10.0);
                smkText.string = @"SMK";
                [smokeGroup addSublayer:smkText];
                [markerContainer addSublayer:smokeGroup];
                g_hostedPUBGGrenadeSmokeLayers[i] = smokeGroup;

                // --- 3. BURN / MOLOTOV GROUP (Bom Lửa: Glass bottle with bright fire flames) ---
                CALayer *burnGroup = [CALayer layer];
                burnGroup.actions = noAnim;
                burnGroup.contentsScale = scale;
                burnGroup.frame = CGRectMake(0, 0, 32.0, 32.0);
                burnGroup.hidden = YES;

                CAShapeLayer *flameLayer = [CAShapeLayer layer];
                flameLayer.actions = noAnim;
                flameLayer.contentsScale = scale;
                UIBezierPath *flamePath = [UIBezierPath bezierPath];
                [flamePath moveToPoint:CGPointMake(16.0, 2.0)];
                [flamePath addCurveToPoint:CGPointMake(20.5, 8.5) controlPoint1:CGPointMake(19.0, 4.0) controlPoint2:CGPointMake(21.0, 6.5)];
                [flamePath addCurveToPoint:CGPointMake(16.0, 10.0) controlPoint1:CGPointMake(20.0, 10.0) controlPoint2:CGPointMake(18.0, 10.0)];
                [flamePath addCurveToPoint:CGPointMake(11.5, 8.5) controlPoint1:CGPointMake(14.0, 10.0) controlPoint2:CGPointMake(12.0, 10.0)];
                [flamePath addCurveToPoint:CGPointMake(16.0, 2.0) controlPoint1:CGPointMake(11.0, 6.5) controlPoint2:CGPointMake(13.0, 4.0)];
                flameLayer.path = flamePath.CGPath;
                flameLayer.fillColor = [UIColor colorWithRed:1.0f green:0.45f blue:0.0f alpha:1.0f].CGColor;
                flameLayer.strokeColor = [UIColor colorWithRed:1.0f green:0.90f blue:0.10f alpha:1.0f].CGColor;
                flameLayer.lineWidth = 1.0;
                [burnGroup addSublayer:flameLayer];

                CALayer *bNeck = [CALayer layer];
                bNeck.actions = noAnim;
                bNeck.contentsScale = scale;
                bNeck.frame = CGRectMake(13.5, 9.5, 5.0, 5.0);
                bNeck.backgroundColor = [UIColor colorWithRed:0.50f green:0.25f blue:0.05f alpha:0.9f].CGColor;
                [burnGroup addSublayer:bNeck];

                CALayer *bBody = [CALayer layer];
                bBody.actions = noAnim;
                bBody.contentsScale = scale;
                bBody.frame = CGRectMake(9.0, 14.0, 14.0, 14.5);
                bBody.cornerRadius = 3.0;
                bBody.masksToBounds = YES;
                bBody.backgroundColor = [UIColor colorWithRed:0.40f green:0.18f blue:0.04f alpha:0.95f].CGColor;

                CALayer *bLiquid = [CALayer layer];
                bLiquid.actions = noAnim;
                bLiquid.contentsScale = scale;
                bLiquid.frame = CGRectMake(0, 5.0, 14.0, 9.5);
                bLiquid.backgroundColor = [UIColor colorWithRed:1.0f green:0.55f blue:0.0f alpha:0.95f].CGColor;
                [bBody addSublayer:bLiquid];
                [burnGroup addSublayer:bBody];

                CAShapeLayer *bBorder = [CAShapeLayer layer];
                bBorder.actions = noAnim;
                bBorder.contentsScale = scale;
                UIBezierPath *bBPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(9.0, 14.0, 14.0, 14.5) cornerRadius:3.0];
                bBorder.path = bBPath.CGPath;
                bBorder.fillColor = UIColor.clearColor.CGColor;
                bBorder.strokeColor = UIColor.whiteColor.CGColor;
                bBorder.lineWidth = 1.3;
                [burnGroup addSublayer:bBorder];
                [markerContainer addSublayer:burnGroup];
                g_hostedPUBGGrenadeBurnLayers[i] = burnGroup;

                // --- 4. STUN GRENADE GROUP (Bom Choáng: Silver-blue canister with flash icon) ---
                CALayer *stunGroup = [CALayer layer];
                stunGroup.actions = noAnim;
                stunGroup.contentsScale = scale;
                stunGroup.frame = CGRectMake(0, 0, 32.0, 32.0);
                stunGroup.hidden = YES;

                CALayer *stnCap = [CALayer layer];
                stnCap.actions = noAnim;
                stnCap.contentsScale = scale;
                stnCap.frame = CGRectMake(12.0, 3.5, 8.0, 4.0);
                stnCap.cornerRadius = 1.5;
                stnCap.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0].CGColor;
                [stunGroup addSublayer:stnCap];

                CALayer *stnBody = [CALayer layer];
                stnBody.actions = noAnim;
                stnBody.contentsScale = scale;
                stnBody.frame = CGRectMake(8.5, 7.0, 15.0, 21.0);
                stnBody.cornerRadius = 3.0;
                stnBody.masksToBounds = YES;
                stnBody.backgroundColor = [UIColor colorWithRed:0.30f green:0.38f blue:0.52f alpha:0.95f].CGColor;

                CALayer *stnStripe = [CALayer layer];
                stnStripe.actions = noAnim;
                stnStripe.contentsScale = scale;
                stnStripe.frame = CGRectMake(0, 6.0, 15.0, 8.0);
                stnStripe.backgroundColor = [UIColor colorWithRed:0.75f green:0.80f blue:0.90f alpha:1.0f].CGColor;
                [stnBody addSublayer:stnStripe];
                [stunGroup addSublayer:stnBody];

                CAShapeLayer *stnBorder = [CAShapeLayer layer];
                stnBorder.actions = noAnim;
                stnBorder.contentsScale = scale;
                UIBezierPath *stnPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(8.5, 7.0, 15.0, 21.0) cornerRadius:3.0];
                stnBorder.path = stnPath.CGPath;
                stnBorder.fillColor = UIColor.clearColor.CGColor;
                stnBorder.strokeColor = UIColor.whiteColor.CGColor;
                stnBorder.lineWidth = 1.4;
                [stunGroup addSublayer:stnBorder];

                CATextLayer *stnText = [CATextLayer layer];
                stnText.actions = noAnim;
                stnText.contentsScale = scale;
                stnText.alignmentMode = kCAAlignmentCenter;
                stnText.fontSize = 8.5;
                stnText.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:8.5];
                stnText.foregroundColor = [UIColor colorWithRed:1.0f green:0.85f blue:0.10f alpha:1.0f].CGColor;
                stnText.frame = CGRectMake(6.0, 14.5, 20.0, 11.0);
                stnText.string = @"⚡";
                [stunGroup addSublayer:stnText];
                [markerContainer addSublayer:stunGroup];
                g_hostedPUBGGrenadeStunLayers[i] = stunGroup;

                [g_hostedLayer addSublayer:markerContainer];
                g_hostedPUBGGrenadeMarkerLayers[i] = markerContainer;

                CAShapeLayer *box = [CAShapeLayer layer];
                box.actions = noAnim;
                box.contentsScale = scale;
                box.fillColor = UIColor.clearColor.CGColor;
                box.lineCap = kCALineCapRound;
                box.lineJoin = kCALineJoinRound;
                box.lineWidth = 1.3;
                box.hidden = YES;
                [g_hostedLayer addSublayer:box];
                g_hostedPUBGGrenadeBoxLayers[i] = box;

                CATextLayer *gLbl = [CATextLayer layer];
                gLbl.actions = noAnim;
                gLbl.contentsScale = scale;
                gLbl.alignmentMode = kCAAlignmentCenter;
                gLbl.wrapped = NO;
                gLbl.shadowColor = UIColor.blackColor.CGColor;
                gLbl.shadowRadius = 0.0;
                gLbl.shadowOpacity = 0.0;
                gLbl.hidden = YES;
                [g_hostedLayer addSublayer:gLbl];
                g_hostedPUBGGrenadeLabels[i] = gLbl;
            }

            CATextLayer *dangerBanner = [CATextLayer layer];
            dangerBanner.actions = noAnim;
            dangerBanner.contentsScale = scale;
            dangerBanner.alignmentMode = kCAAlignmentCenter;
            dangerBanner.wrapped = NO;
            dangerBanner.hidden = YES;
            [g_hostedLayer addSublayer:dangerBanner];
            g_hostedPUBGGrenadeDangerBanner = dangerBanner;

            CAShapeLayer *topBg = [CAShapeLayer layer];
            topBg.actions = noAnim;
            topBg.contentsScale = scale;
            topBg.fillColor = [UIColor colorWithRed:12/255.0 green:15/255.0 blue:24/255.0 alpha:0.88].CGColor;
            topBg.lineWidth = 1.2;
            topBg.hidden = YES;
            [g_hostedLayer addSublayer:topBg];
            g_hostedPUBGTopCountBgLayer = topBg;

            CATextLayer *topLabel = [CATextLayer layer];
            topLabel.actions = noAnim;
            topLabel.contentsScale = scale;
            topLabel.alignmentMode = kCAAlignmentCenter;
            topLabel.fontSize = 22.0;
            topLabel.font = (__bridge CFTypeRef)[UIFont monospacedDigitSystemFontOfSize:22.0 weight:UIFontWeightHeavy];
            topLabel.foregroundColor = [UIColor colorWithRed:239.0/255.0 green:68.0/255.0 blue:68.0/255.0 alpha:1.0].CGColor;
            topLabel.backgroundColor = UIColor.clearColor.CGColor;
            topLabel.shadowColor = UIColor.blackColor.CGColor;
            topLabel.shadowRadius = 0.0;
            topLabel.shadowOpacity = 0.0;
            topLabel.shadowOffset = CGSizeZero;
            topLabel.hidden = YES;
            [g_hostedLayer addSublayer:topLabel];
            g_hostedPUBGTopCountLabel = topLabel;
        }

    g_hostedLayerReady.store(true, std::memory_order_release);
    ds_hosted_overlay_start_display_link();
    g_hostedContextId = contextId;
    g_hostedLastOrientation = 0;  // force the first transform update
    return contextId;
}

static void ds_hosted_overlay_frame(void) {
    ds_hosted_menu_ensure();
    if (!g_hostedLayerReady.load(std::memory_order_acquire)) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - g_hostedLastSetupTryAt >= 2.0) {
            g_hostedLastSetupTryAt = now;
            dispatch_async(dispatch_get_main_queue(), ^{
                unsigned contextId = ds_hosted_overlay_setup_on_main();
                if (contextId) {
                    dispatch_async(ds_bridge_queue(), ^{
                        ds_hosted_overlay_register(contextId);
                    });
                }
            });
        }
        return;
    }

    DSHostedRenderSnapshot snapshot = {};
    ds_pubg_tick();
    snapshot.pubgRenderSourceReady = ds_pubg_has_render_source();
    g_hostedPushedFrames++;
    ds_hosted_publish_render_snapshot(snapshot);
}

static void ds_hosted_overlay_start(void) {
    if (g_hostedTimer) return;
    g_hostedLastSetupTryAt = 0;
    os_unfair_lock_lock(&g_hostedSnapshotLock);
    g_hostedSnapshots[0] = {};
    g_hostedSnapshots[1] = {};
    g_hostedPublishedSnapshot = -1;
    g_hostedSnapshotGeneration = 0;
    g_hostedConsumedGeneration = 0;
    g_hostedFallbackApplyQueued = NO;
    ++g_hostedFallbackToken;
    os_unfair_lock_unlock(&g_hostedSnapshotLock);
    g_hostedLastDisplayLinkTick.store(0.0, std::memory_order_relaxed);
    g_hostedDisplayPulse.store(0, std::memory_order_release);
    g_hostedConsumedDisplayPulse = UINT64_MAX;
    [NSUserDefaults.standardUserDefaults setInteger:1 forKey:@"active_game"];
    [NSUserDefaults.standardUserDefaults synchronize];
    ds_pubg_overlay_reset();
    dispatch_async(dispatch_get_main_queue(), ^{
        unsigned contextId = ds_hosted_overlay_setup_on_main();
        unsigned menuContextId = ds_hosted_menu_setup_on_main();
        if (g_hostedMenuWindow) {
            g_hostedMenuWindow.hidden = NO;
        }
        if (g_hostedMenuViewController) {
            [g_hostedMenuViewController dsApplyOrientation];
        }
        if (contextId || menuContextId) {
            dispatch_async(ds_bridge_queue(), ^{
                if (contextId) ds_hosted_overlay_register(contextId);
                if (menuContextId) ds_hosted_menu_register(menuContextId);
                if (g_hostedTimer) {
                    uint32_t maximumFrameRate = MAX(
                        g_hostedMaximumFrameRate.load(std::memory_order_acquire),
                        30u);
                    dispatch_source_set_timer(
                        g_hostedTimer, DISPATCH_TIME_NOW,
                        (uint64_t)(NSEC_PER_SEC / maximumFrameRate),
                        1 * NSEC_PER_MSEC);
                }
            });
        }
    });
    g_hostedTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                           ds_bridge_queue());
    uint32_t maximumFrameRate = MAX(
        g_hostedMaximumFrameRate.load(std::memory_order_acquire), 30u);
    dispatch_source_set_timer(g_hostedTimer, DISPATCH_TIME_NOW,
                              (uint64_t)(NSEC_PER_SEC / maximumFrameRate),
                              1 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(g_hostedTimer, ^{
        if (g_hostedLayerReady.load(std::memory_order_acquire)) {
            uint64_t pulse = g_hostedDisplayPulse.load(std::memory_order_acquire);
            if (pulse == g_hostedConsumedDisplayPulse) {
                // The display link can go silent while this process is
                // backgrounded (hosted SpringBoard context, audio keepalive).
                // Returning here starved ds_pubg_tick() after the first frame:
                // no ESP refresh, no camera zoom, no auto smite, and menu
                // switches appeared dead. Only skip while the display link is
                // actually driving frames; otherwise this timer reads and
                // publishes, and the publish fallback applies on main.
                double lastTick = g_hostedLastDisplayLinkTick.load(
                    std::memory_order_relaxed);
                if (lastTick > 0.0 &&
                    CACurrentMediaTime() - lastTick <= 0.10) {
                    return;
                }
            } else {
                g_hostedConsumedDisplayPulse = pulse;
            }
        }
        ds_hosted_overlay_frame();
    });
    dispatch_resume(g_hostedTimer);
}

// Pause rendering without dropping the local window/CAContext or the
// SpringBoard-side registration: the next enable is then fully local
// (one-shot channel design). Every ESP layer is hidden so the hosted window
// commits one transparent frame before the display link stops.
static void ds_hosted_overlay_pause(void) {
    if (g_hostedTimer) {
        dispatch_source_cancel(g_hostedTimer);
        g_hostedTimer = nil;
    }
    os_unfair_lock_lock(&g_hostedSnapshotLock);
    g_hostedSnapshots[0] = {};
    g_hostedSnapshots[1] = {};
    g_hostedPublishedSnapshot = -1;
    g_hostedSnapshotGeneration = 0;
    g_hostedConsumedGeneration = 0;
    g_hostedFallbackApplyQueued = NO;
    ++g_hostedFallbackToken;
    os_unfair_lock_unlock(&g_hostedSnapshotLock);
    g_hostedLastDisplayLinkTick.store(0.0, std::memory_order_relaxed);
    g_hostedDisplayPulse.store(0, std::memory_order_release);
    g_hostedConsumedDisplayPulse = UINT64_MAX;
    ds_pubg_overlay_reset();
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_hostedDisplayLink invalidate];
        g_hostedDisplayLink = nil;
        g_hostedDisplayLinkDriver = nil;
        ds_hosted_menu_set_expanded(NO);
        g_hostedMenuWindow.hidden = YES;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        ds_hosted_pubg_hide_all();
        [CATransaction commit];
    });
}

static void ds_hosted_overlay_stop(void) {
    if (g_hostedTimer) {
        dispatch_source_cancel(g_hostedTimer);
        g_hostedTimer = nil;
    }
    g_hostedRemoteController = 0;
    g_hostedMenuRemoteController = 0;
    g_hostedMenuLastSetupTryAt = 0;
    g_hostedMenuLastRegisterTryAt = 0;
    g_hostedMenuLastOrientation = 0;
    g_hostedSBPid = 0;
    g_hostedLayerReady.store(false, std::memory_order_release);
    os_unfair_lock_lock(&g_hostedSnapshotLock);
    g_hostedSnapshots[0] = {};
    g_hostedSnapshots[1] = {};
    g_hostedPublishedSnapshot = -1;
    g_hostedSnapshotGeneration = 0;
    g_hostedConsumedGeneration = 0;
    g_hostedFallbackApplyQueued = NO;
    ++g_hostedFallbackToken;
    os_unfair_lock_unlock(&g_hostedSnapshotLock);
    g_hostedLastDisplayLinkTick.store(0.0, std::memory_order_relaxed);
    g_hostedDisplayPulse.store(0, std::memory_order_release);
    g_hostedConsumedDisplayPulse = UINT64_MAX;
    ds_pubg_overlay_reset();
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_hostedDisplayLink invalidate];
        g_hostedDisplayLink = nil;
        g_hostedDisplayLinkDriver = nil;
        g_hostedWindow.hidden = YES;
        g_hostedWindow = nil;   // drops the window + its hosted context
        g_hostedESPView = nil;
        g_hostedLayer = nil;
        g_hostedMenuWindow.hidden = YES;
        g_hostedMenuWindow = nil;
        g_hostedMenuViewController = nil;
        g_hostedMenuContextId = 0;
        g_hostedMenuExpanded = NO;
        g_hostedPortraitNotchHeight = 0.0;
        g_hostedContentBounds = CGRectNull;
    });
}
