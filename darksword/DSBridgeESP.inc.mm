// DSBridgeESP.inc.mm — shared-page kernel memory reader + AOV hosted overlay.
// Included by DSBridge.mm.
//
// Hạ tầng dùng chung (Fl0rkFF style): vm region cache, shared-page cache qua
// vmmapremotepage, read/write helpers, Mach-O main-image identity. Reader AOV
// nằm ở DSBridgeLienQuan.inc.mm; file này giữ hosted overlay và render loop.

#import "KGVNHeroIcons/Herolib.h"

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
    LienQuan = 1,
    PUBG = 2,
};

static NSString * const kDSActiveGameKey = @"DSActiveGame";

static inline int ds_active_game(void) {
    id val = [NSUserDefaults.standardUserDefaults objectForKey:kDSActiveGameKey];
    if (!val) return 1; // Default to PUBG Mobile (1) in DarkPubg
    return (int)[val integerValue];
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

// Entry points implemented in DSBridgeLienQuan.inc.mm (included after this
// file); the menu below only drives them.
static bool ds_lq_camera_zoom_enabled(void);
static float ds_lq_camera_zoom_value(void);
static void ds_lq_camera_zoom_set(bool enabled, float value);
static void ds_lq_auto_smite_set(bool enabled);
static void ds_lq_auto_smite_objectives_only_set(bool enabled);
// Defined with the AOV overlay pool below; used by the ESP menu switch.
static void ds_hosted_lq_hide_all(void);

static NSString * const kDSHostedCamZoomEnabledKey = @"lq_camxa_enabled";
static NSString * const kDSHostedCamZoomValueKey = @"lq_camxa_value";
static NSString * const kDSHostedAutoSmiteEnabledKey = @"lq_auto_smite_enabled";
static NSString * const kDSHostedAutoSmiteObjectivesOnlyKey =
    @"lq_auto_smite_objectives_only";
static NSString * const kDSHostedMenuAnchorXKey = @"lq_menu_anchor_x";
static NSString * const kDSHostedMenuAnchorYKey = @"lq_menu_anchor_y";
static NSString * const kDSHostedMenuPanelXKey = @"lq_menu_panel_x";
static NSString * const kDSHostedMenuPanelYKey = @"lq_menu_panel_y";
static NSString * const kDSHostedMinimapOffsetXKey = @"lq_minimap_offset_x";
static NSString * const kDSHostedMinimapOffsetYKey = @"lq_minimap_offset_y";
static NSString * const kDSHostedEspEnabledKey = @"lq_esp_enabled";
static const double kDSHostedMenuLevel = 10000020.0;
static const float kDSHostedCamZoomMin = 1.0f;
static const float kDSHostedCamZoomMax = 10.0f;
static const float kDSHostedMinimapOffsetMin = -200.0f;
static const float kDSHostedMinimapOffsetMax = 200.0f;
static const CGFloat kDSHostedMenuButtonSize = 18.0;
static const CGFloat kDSHostedMenuSymbolSize = 8.0;
enum : NSInteger {
    kDSHostedMinimapXMinusTag = 1,
    kDSHostedMinimapXPlusTag,
    kDSHostedMinimapYMinusTag,
    kDSHostedMinimapYPlusTag,
};
static std::atomic<float> g_hostedMinimapOffsetX(0.0f);
static std::atomic<float> g_hostedMinimapOffsetY(0.0f);

static void ds_hosted_minimap_load_offsets(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        float x = (float)[defaults doubleForKey:kDSHostedMinimapOffsetXKey];
        float y = (float)[defaults doubleForKey:kDSHostedMinimapOffsetYKey];
        if (!isfinite(x)) x = 0.0f;
        if (!isfinite(y)) y = 0.0f;
        g_hostedMinimapOffsetX.store(
            fminf(fmaxf(x, kDSHostedMinimapOffsetMin),
                  kDSHostedMinimapOffsetMax),
            std::memory_order_release);
        g_hostedMinimapOffsetY.store(
            fminf(fmaxf(y, kDSHostedMinimapOffsetMin),
                  kDSHostedMinimapOffsetMax),
            std::memory_order_release);
    });
}

static CGPoint ds_hosted_minimap_offset(void) {
    ds_hosted_minimap_load_offsets();
    return CGPointMake(
        g_hostedMinimapOffsetX.load(std::memory_order_acquire),
        g_hostedMinimapOffsetY.load(std::memory_order_acquire));
}

static void ds_hosted_minimap_set_offset(CGPoint offset) {
    ds_hosted_minimap_load_offsets();
    float x = isfinite(offset.x) ? (float)offset.x : 0.0f;
    float y = isfinite(offset.y) ? (float)offset.y : 0.0f;
    x = fminf(fmaxf(x, kDSHostedMinimapOffsetMin),
              kDSHostedMinimapOffsetMax);
    y = fminf(fmaxf(y, kDSHostedMinimapOffsetMin),
              kDSHostedMinimapOffsetMax);
    g_hostedMinimapOffsetX.store(x, std::memory_order_release);
    g_hostedMinimapOffsetY.store(y, std::memory_order_release);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:x forKey:kDSHostedMinimapOffsetXKey];
    [defaults setDouble:y forKey:kDSHostedMinimapOffsetYKey];
}

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
    // Load the persisted value first so an explicit write below is not
    // overwritten by the one-time defaults read.
    (void)ds_hosted_esp_enabled();
    g_hostedEspEnabled.store(enabled, std::memory_order_release);
    [NSUserDefaults.standardUserDefaults setBool:enabled
                                          forKey:kDSHostedEspEnabledKey];
    if (enabled) return;
    void (^hideEsp)(void) = ^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        ds_hosted_lq_hide_all();
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

@class DSESPMenuViewController;

// Interactive sibling of DSESPHostedWindow: touchable, still system/secure so
// SpringBoard can host it above the game.
@interface DSESPMenuWindow : UIWindow
@end

@implementation DSESPMenuWindow
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
- (BOOL)keepContextInBackground { return YES; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
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

@interface DSESPMenuViewController : UIViewController
- (void)dsSetExpanded:(BOOL)expanded;
- (void)dsApplyOrientation;
- (BOOL)dsShouldAcceptHitView:(UIView *)hitView;
@end

@implementation DSESPMenuViewController {
    UIView *_contentView;
    UIView *_panelView;
    UIButton *_toggleButton;
    UIButton *_closeButton;
    UILabel *_titleLabel;
    UILabel *_espLabel;
    UISwitch *_espSwitch;
    UILabel *_enableLabel;
    UISwitch *_enableSwitch;
    UILabel *_autoSmiteLabel;
    UISwitch *_autoSmiteSwitch;
    UILabel *_autoSmiteObjectivesOnlyLabel;
    UISwitch *_autoSmiteObjectivesOnlySwitch;
    UILabel *_zoomLabel;
    UISlider *_zoomSlider;
    UILabel *_zoomValueLabel;
    UILabel *_minimapXLabel;
    UIButton *_minimapXMinusButton;
    UISlider *_minimapXSlider;
    UIButton *_minimapXPlusButton;
    UILabel *_minimapXValueLabel;
    UILabel *_minimapYLabel;
    UIButton *_minimapYMinusButton;
    UISlider *_minimapYSlider;
    UIButton *_minimapYPlusButton;
    UILabel *_minimapYValueLabel;
    UIButton *_resetButton;
    // Modern UI Containers
    UIView *_masterCard;
    UIView *_pubgCards[8];
    UIView *_scanCard;
    // PUBG ESP controls
    UILabel *_pubgBoxLabel;
    UISwitch *_pubgBoxSwitch;
    UILabel *_pubgSkeletonLabel;
    UISwitch *_pubgSkeletonSwitch;
    UILabel *_pubgLineLabel;
    UISwitch *_pubgLineSwitch;
    UILabel *_pubgArrowLabel;
    UISwitch *_pubgArrowSwitch;
    UILabel *_pubgHealthLabel;
    UISwitch *_pubgHealthSwitch;
    UILabel *_pubgNameLabel;
    UISwitch *_pubgNameSwitch;
    UILabel *_pubgDistLabel;
    UISwitch *_pubgDistSwitch;
    UILabel *_pubgBotLabel;
    UISwitch *_pubgBotSwitch;
    UILabel *_pubgVehicleLabel;
    UISwitch *_pubgVehicleSwitch;
    UILabel *_pubgVehicleHpLabel;
    UISwitch *_pubgVehicleHpSwitch;
    UILabel *_pubgVehicleFuelLabel;
    UISwitch *_pubgVehicleFuelSwitch;
    int _pubgCurrentTab;
    UIView *_pubgTabBar;
    UIButton *_pubgTabButtonPlayer;
    UIButton *_pubgTabButtonItems;
    UIButton *_pubgTabButtonSettings;
    UIView *_pubgItemCards[8];
    UILabel *_pubgWeaponLabel;
    UISwitch *_pubgWeaponSwitch;
    UILabel *_pubgArmorLabel;
    UISwitch *_pubgArmorSwitch;
    UILabel *_pubgBagLabel;
    UISwitch *_pubgBagSwitch;
    UILabel *_pubgScopeLabel;
    UISwitch *_pubgScopeSwitch;
    UILabel *_pubgCrateLabel;
    UISwitch *_pubgCrateSwitch;
    UIView *_pubgItemScanCard;
    UILabel *_pubgItemScanLabel;
    UILabel *_pubgItemScanValueLabel;
    UISlider *_pubgItemScanSlider;
    UIView *_pubgSettingLangCard;
    UILabel *_pubgSettingLangLabel;
    UISegmentedControl *_pubgLangSegment;
    UIView *_pubgSettingThicknessCard;
    UILabel *_pubgSettingThicknessLabel;
    UILabel *_pubgSettingThicknessValueLabel;
    UISlider *_pubgSettingThicknessSlider;
    UIView *_pubgSettingInfoCard;
    UILabel *_pubgSettingInfoLabel;
    UILabel *_pubgSettingInfoDescLabel;
    CGPoint _buttonAnchorUnit;
    CGPoint _panelAnchorUnit;
    CGPoint _dragStartAnchor;
    BOOL _hasButtonAnchor;
    BOOL _hasPanelAnchor;
    BOOL _hasAppliedOrientation;
    int _appliedOrientation;
    CGRect _appliedWindowBounds;
}

- (void)loadView {
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.opaque = NO;
    self.view.backgroundColor = UIColor.clearColor;

    _contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    _contentView.opaque = NO;
    _contentView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_contentView];

    _panelView = [[UIView alloc] initWithFrame:CGRectZero];
    _panelView.backgroundColor = [UIColor colorWithRed:12/255.0 green:15/255.0 blue:24/255.0 alpha:0.96];
    _panelView.layer.cornerRadius = 16.0;
    _panelView.layer.borderWidth = 1.2;
    _panelView.layer.borderColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.35].CGColor;
    _panelView.layer.shadowColor = UIColor.blackColor.CGColor;
    _panelView.layer.shadowRadius = 18.0;
    _panelView.layer.shadowOffset = CGSizeMake(0, 6);
    _panelView.layer.shadowOpacity = 0.75;
    _panelView.layer.masksToBounds = NO;
    [_contentView addSubview:_panelView];

    _masterCard = [[UIView alloc] initWithFrame:CGRectZero];
    _masterCard.backgroundColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.08];
    _masterCard.layer.cornerRadius = 9.0;
    _masterCard.layer.borderWidth = 0.9;
    _masterCard.layer.borderColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.25].CGColor;
    [_panelView addSubview:_masterCard];

    for (int ci = 0; ci < 8; ci++) {
        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
        card.layer.cornerRadius = 8.0;
        card.layer.borderWidth = 0.8;
        card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
        [_panelView addSubview:card];
        _pubgCards[ci] = card;
    }

    for (int ci = 0; ci < 8; ci++) {
        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
        card.layer.cornerRadius = 8.0;
        card.layer.borderWidth = 0.8;
        card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
        card.hidden = YES;
        [_panelView addSubview:card];
        _pubgItemCards[ci] = card;
    }

    _pubgTabBar = [[UIView alloc] initWithFrame:CGRectZero];
    _pubgTabBar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
    _pubgTabBar.layer.cornerRadius = 8.0;
    _pubgTabBar.layer.borderWidth = 0.8;
    _pubgTabBar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    _pubgTabBar.hidden = YES;
    [_panelView addSubview:_pubgTabBar];

    _pubgTabButtonPlayer = [UIButton buttonWithType:UIButtonTypeCustom];
    [_pubgTabButtonPlayer setTitle:@"👤 ESP Địch" forState:UIControlStateNormal];
    _pubgTabButtonPlayer.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    _pubgTabButtonPlayer.layer.cornerRadius = 6.0;
    [_pubgTabButtonPlayer addTarget:self action:@selector(dsPubgTabTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_pubgTabBar addSubview:_pubgTabButtonPlayer];

    _pubgTabButtonItems = [UIButton buttonWithType:UIButtonTypeCustom];
    [_pubgTabButtonItems setTitle:@"📦 Vật Phẩm" forState:UIControlStateNormal];
    _pubgTabButtonItems.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    _pubgTabButtonItems.layer.cornerRadius = 6.0;
    [_pubgTabButtonItems addTarget:self action:@selector(dsPubgTabTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_pubgTabBar addSubview:_pubgTabButtonItems];

    _pubgTabButtonSettings = [UIButton buttonWithType:UIButtonTypeCustom];
    [_pubgTabButtonSettings setTitle:@"⚙️ Cài Đặt" forState:UIControlStateNormal];
    _pubgTabButtonSettings.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    _pubgTabButtonSettings.layer.cornerRadius = 6.0;
    [_pubgTabButtonSettings addTarget:self action:@selector(dsPubgTabTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_pubgTabBar addSubview:_pubgTabButtonSettings];

    _scanCard = [[UIView alloc] initWithFrame:CGRectZero];
    _scanCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
    _scanCard.layer.cornerRadius = 9.0;
    _scanCard.layer.borderWidth = 0.8;
    _scanCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
    [_panelView addSubview:_scanCard];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = @"DARKPUBG";
    _titleLabel.textColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
    _titleLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightHeavy];
    _titleLabel.userInteractionEnabled = YES;
    UIPanGestureRecognizer *titlePan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dsMenuPanelPanned:)];
    [_titleLabel addGestureRecognizer:titlePan];
    [_panelView addSubview:_titleLabel];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeButton.tintColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    _closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    _closeButton.layer.cornerRadius = 13.0;
    _closeButton.layer.masksToBounds = YES;
    UIImage *closeImage = [UIImage systemImageNamed:@"xmark"];
    if (closeImage) {
        closeImage = [closeImage imageByApplyingSymbolConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:11.0
                                                             weight:UIImageSymbolWeightBold]];
        [_closeButton setImage:closeImage forState:UIControlStateNormal];
    } else {
        [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [_closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    }
    [_closeButton addTarget:self action:@selector(dsCloseTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    [_panelView addSubview:_closeButton];

    _espLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLabel.text = @"ESP";
    _espLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    _espLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [_panelView addSubview:_espLabel];

    _espSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espSwitch.onTintColor = [UIColor colorWithRed:26/255.0 green:188/255.0 blue:156/255.0 alpha:1.0];
    _espSwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    _espSwitch.on = ds_hosted_esp_enabled();
    [_espSwitch addTarget:self action:@selector(dsEspSwitchChanged:)
         forControlEvents:UIControlEventValueChanged];
    [_panelView addSubview:_espSwitch];

    _enableLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _enableLabel.text = @"Cam Xa";
    _enableLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    _enableLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [_panelView addSubview:_enableLabel];

    _enableSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _enableSwitch.onTintColor = [UIColor colorWithRed:26/255.0 green:188/255.0 blue:156/255.0 alpha:1.0];
    _enableSwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [_enableSwitch addTarget:self action:@selector(dsEnableSwitchChanged:)
            forControlEvents:UIControlEventValueChanged];
    [_panelView addSubview:_enableSwitch];

    _autoSmiteLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoSmiteLabel.text = @"Auto TT";
    _autoSmiteLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    _autoSmiteLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [_panelView addSubview:_autoSmiteLabel];

    _autoSmiteSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoSmiteSwitch.onTintColor = [UIColor colorWithRed:26/255.0 green:188/255.0 blue:156/255.0 alpha:1.0];
    _autoSmiteSwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [_autoSmiteSwitch addTarget:self action:@selector(dsAutoSmiteSwitchChanged:)
                 forControlEvents:UIControlEventValueChanged];
    [_panelView addSubview:_autoSmiteSwitch];

    _autoSmiteObjectivesOnlyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoSmiteObjectivesOnlyLabel.text = @"Chỉ Rồng/Tà";
    _autoSmiteObjectivesOnlyLabel.textColor =
        [UIColor colorWithWhite:1.0 alpha:0.86];
    _autoSmiteObjectivesOnlyLabel.font =
        [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [_panelView addSubview:_autoSmiteObjectivesOnlyLabel];

    _autoSmiteObjectivesOnlySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoSmiteObjectivesOnlySwitch.onTintColor =
        [UIColor colorWithRed:26/255.0 green:188/255.0 blue:156/255.0 alpha:1.0];
    _autoSmiteObjectivesOnlySwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [_autoSmiteObjectivesOnlySwitch
        addTarget:self
           action:@selector(dsAutoSmiteObjectivesOnlySwitchChanged:)
 forControlEvents:UIControlEventValueChanged];
    [_panelView addSubview:_autoSmiteObjectivesOnlySwitch];

    _zoomLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _zoomLabel.text = @"Zoom";
    _zoomLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    _zoomLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [_panelView addSubview:_zoomLabel];

    _zoomSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _zoomSlider.minimumValue = kDSHostedCamZoomMin;
    _zoomSlider.maximumValue = kDSHostedCamZoomMax;
    _zoomSlider.continuous = YES;
    _zoomSlider.minimumTrackTintColor = [UIColor colorWithRed:26/255.0 green:188/255.0 blue:156/255.0 alpha:1.0];
    _zoomSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    [_zoomSlider addTarget:self action:@selector(dsZoomSliderChanged:)
          forControlEvents:UIControlEventValueChanged];
    [_panelView addSubview:_zoomSlider];

    _zoomValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _zoomValueLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    _zoomValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    _zoomValueLabel.textAlignment = NSTextAlignmentRight;
    [_panelView addSubview:_zoomValueLabel];

    _minimapXLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _minimapXLabel.text = @"Map X";
    _minimapXLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    _minimapXLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [_panelView addSubview:_minimapXLabel];

    _minimapXMinusButton = ds_hosted_minimap_step_button(
        @"minus", kDSHostedMinimapXMinusTag, @"Decrease minimap X");
    [_minimapXMinusButton addTarget:self
                             action:@selector(dsMinimapStepTapped:)
                   forControlEvents:UIControlEventTouchUpInside];
    [_panelView addSubview:_minimapXMinusButton];

    _minimapXSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _minimapXSlider.minimumValue = kDSHostedMinimapOffsetMin;
    _minimapXSlider.maximumValue = kDSHostedMinimapOffsetMax;
    _minimapXSlider.continuous = YES;
    _minimapXSlider.minimumTrackTintColor = [UIColor colorWithRed:26/255.0 green:188/255.0 blue:156/255.0 alpha:1.0];
    _minimapXSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    [_minimapXSlider addTarget:self action:@selector(dsMinimapOffsetChanged:)
               forControlEvents:UIControlEventValueChanged];
    [_panelView addSubview:_minimapXSlider];

    _minimapXPlusButton = ds_hosted_minimap_step_button(
        @"plus", kDSHostedMinimapXPlusTag, @"Increase minimap X");
    [_minimapXPlusButton addTarget:self
                            action:@selector(dsMinimapStepTapped:)
                  forControlEvents:UIControlEventTouchUpInside];
    [_panelView addSubview:_minimapXPlusButton];

    _minimapXValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _minimapXValueLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    _minimapXValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    _minimapXValueLabel.textAlignment = NSTextAlignmentRight;
    [_panelView addSubview:_minimapXValueLabel];

    _minimapYLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _minimapYLabel.text = @"Map Y";
    _minimapYLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
    _minimapYLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [_panelView addSubview:_minimapYLabel];

    _minimapYMinusButton = ds_hosted_minimap_step_button(
        @"minus", kDSHostedMinimapYMinusTag, @"Decrease minimap Y");
    [_minimapYMinusButton addTarget:self
                             action:@selector(dsMinimapStepTapped:)
                   forControlEvents:UIControlEventTouchUpInside];
    [_panelView addSubview:_minimapYMinusButton];

    _minimapYSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _minimapYSlider.minimumValue = kDSHostedMinimapOffsetMin;
    _minimapYSlider.maximumValue = kDSHostedMinimapOffsetMax;
    _minimapYSlider.continuous = YES;
    _minimapYSlider.minimumTrackTintColor = [UIColor colorWithRed:26/255.0 green:188/255.0 blue:156/255.0 alpha:1.0];
    _minimapYSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    [_minimapYSlider addTarget:self action:@selector(dsMinimapOffsetChanged:)
               forControlEvents:UIControlEventValueChanged];
    [_panelView addSubview:_minimapYSlider];

    _minimapYPlusButton = ds_hosted_minimap_step_button(
        @"plus", kDSHostedMinimapYPlusTag, @"Increase minimap Y");
    [_minimapYPlusButton addTarget:self
                            action:@selector(dsMinimapStepTapped:)
                  forControlEvents:UIControlEventTouchUpInside];
    [_panelView addSubview:_minimapYPlusButton];

    _minimapYValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _minimapYValueLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    _minimapYValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    _minimapYValueLabel.textAlignment = NSTextAlignmentRight;
    [_panelView addSubview:_minimapYValueLabel];

    _resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    [_resetButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _resetButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    _resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    _resetButton.layer.cornerRadius = 8.0;
    _resetButton.layer.masksToBounds = YES;
    [_resetButton addTarget:self action:@selector(dsResetTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_panelView addSubview:_resetButton];

    auto pubgCreateSwitch = ^(SEL sel) {
        UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 51.0, 31.0)];
        s.onTintColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
        s.transform = CGAffineTransformMakeScale(0.70, 0.70);
        [s addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
        [_panelView addSubview:s];
        return s;
    };
    auto pubgCreateLabel = ^(NSString *text) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.text = text;
        l.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        l.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
        [_panelView addSubview:l];
        return l;
    };

    _pubgBoxLabel = pubgCreateLabel(@"Box Góc 2D");
    _pubgBoxSwitch = pubgCreateSwitch(@selector(dsPubgBoxChanged:));
    _pubgSkeletonLabel = pubgCreateLabel(@"Xương");
    _pubgSkeletonSwitch = pubgCreateSwitch(@selector(dsPubgSkeletonChanged:));

    _pubgLineLabel = pubgCreateLabel(@"Tia Line");
    _pubgLineSwitch = pubgCreateSwitch(@selector(dsPubgLineChanged:));

    _pubgHealthLabel = pubgCreateLabel(@"Thanh Máu");
    _pubgHealthSwitch = pubgCreateSwitch(@selector(dsPubgHealthChanged:));
    _pubgNameLabel = pubgCreateLabel(@"Tên Địch");
    _pubgNameSwitch = pubgCreateSwitch(@selector(dsPubgNameChanged:));

    _pubgDistLabel = pubgCreateLabel(@"Khoảng Cách");
    _pubgDistSwitch = pubgCreateSwitch(@selector(dsPubgDistChanged:));
    _pubgBotLabel = pubgCreateLabel(@"Hiện Bot AI");
    _pubgBotSwitch = pubgCreateSwitch(@selector(dsPubgBotChanged:));
    _pubgArrowLabel = pubgCreateLabel(@"Mũi Tên");
    _pubgArrowSwitch = pubgCreateSwitch(@selector(dsPubgArrowChanged:));

    _pubgVehicleLabel = pubgCreateLabel(@"Hiện Xe");
    _pubgVehicleSwitch = pubgCreateSwitch(@selector(dsPubgVehicleChanged:));
    _pubgVehicleHpLabel = pubgCreateLabel(@"Máu Xe");
    _pubgVehicleHpSwitch = pubgCreateSwitch(@selector(dsPubgVehicleHpChanged:));
    _pubgVehicleFuelLabel = pubgCreateLabel(@"Xăng Xe");
    _pubgVehicleFuelSwitch = pubgCreateSwitch(@selector(dsPubgVehicleFuelChanged:));
    _pubgWeaponLabel = pubgCreateLabel(@"Hiện Súng");
    _pubgWeaponSwitch = pubgCreateSwitch(@selector(dsPubgWeaponChanged:));
    _pubgArmorLabel = pubgCreateLabel(@"Giáp & Mũ");
    _pubgArmorSwitch = pubgCreateSwitch(@selector(dsPubgArmorChanged:));
    _pubgBagLabel = pubgCreateLabel(@"Hiện Balo");
    _pubgBagSwitch = pubgCreateSwitch(@selector(dsPubgBagChanged:));
    _pubgScopeLabel = pubgCreateLabel(@"Ống Ngắm");
    _pubgScopeSwitch = pubgCreateSwitch(@selector(dsPubgScopeChanged:));
    _pubgCrateLabel = pubgCreateLabel(@"Hòm & Thính");
    _pubgCrateSwitch = pubgCreateSwitch(@selector(dsPubgCrateChanged:));

    _pubgItemScanCard = [[UIView alloc] initWithFrame:CGRectZero];
    _pubgItemScanCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
    _pubgItemScanCard.layer.cornerRadius = 9.0;
    _pubgItemScanCard.layer.borderWidth = 0.8;
    _pubgItemScanCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
    _pubgItemScanCard.hidden = YES;
    [_panelView addSubview:_pubgItemScanCard];

    _pubgItemScanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgItemScanLabel.text = @"Khoảng cách vật phẩm";
    _pubgItemScanLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    _pubgItemScanLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    _pubgItemScanLabel.hidden = YES;
    [_panelView addSubview:_pubgItemScanLabel];

    _pubgItemScanValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgItemScanValueLabel.textColor = [UIColor colorWithRed:255/255.0 green:215/255.0 blue:0/255.0 alpha:1.0];
    _pubgItemScanValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightBold];
    _pubgItemScanValueLabel.textAlignment = NSTextAlignmentRight;
    _pubgItemScanValueLabel.text = @"150m";
    _pubgItemScanValueLabel.hidden = YES;
    [_panelView addSubview:_pubgItemScanValueLabel];

    _pubgItemScanSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _pubgItemScanSlider.minimumValue = 50.0f;
    _pubgItemScanSlider.maximumValue = 300.0f;
    _pubgItemScanSlider.value = g_pubgItemMaxDistance;
    _pubgItemScanSlider.continuous = YES;
    _pubgItemScanSlider.minimumTrackTintColor = [UIColor colorWithRed:255/255.0 green:215/255.0 blue:0/255.0 alpha:1.0];
    _pubgItemScanSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    [_pubgItemScanSlider addTarget:self action:@selector(dsPubgItemScanSliderChanged:) forControlEvents:UIControlEventValueChanged];
    _pubgItemScanSlider.hidden = YES;
    [_panelView addSubview:_pubgItemScanSlider];

    // Tab 2: Settings Controls (Cài đặt ngôn ngữ và độ dày nét vẽ địch)
    _pubgSettingLangCard = [[UIView alloc] initWithFrame:CGRectZero];
    _pubgSettingLangCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
    _pubgSettingLangCard.layer.cornerRadius = 9.0;
    _pubgSettingLangCard.layer.borderWidth = 0.8;
    _pubgSettingLangCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
    _pubgSettingLangCard.hidden = YES;
    [_panelView addSubview:_pubgSettingLangCard];

    _pubgSettingLangLabel = pubgCreateLabel(@"Ngôn ngữ giao diện");
    _pubgSettingLangLabel.hidden = YES;

    _pubgLangSegment = [[UISegmentedControl alloc] initWithItems:@[@"Tiếng Việt", @"English"]];
    _pubgLangSegment.selectedSegmentIndex = g_pubgLanguage;
    _pubgLangSegment.hidden = YES;
    [_pubgLangSegment addTarget:self action:@selector(dsPubgLangChanged:) forControlEvents:UIControlEventValueChanged];
    _pubgLangSegment.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    if (@available(iOS 13.0, *)) {
        _pubgLangSegment.selectedSegmentTintColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.35];
    }
    [_pubgLangSegment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.95 alpha:1.0],
        NSFontAttributeName: [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold]
    } forState:UIControlStateSelected];
    [_pubgLangSegment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:0.6 alpha:1.0],
        NSFontAttributeName: [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium]
    } forState:UIControlStateNormal];
    [_panelView addSubview:_pubgLangSegment];

    _pubgSettingThicknessCard = [[UIView alloc] initWithFrame:CGRectZero];
    _pubgSettingThicknessCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
    _pubgSettingThicknessCard.layer.cornerRadius = 9.0;
    _pubgSettingThicknessCard.layer.borderWidth = 0.8;
    _pubgSettingThicknessCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
    _pubgSettingThicknessCard.hidden = YES;
    [_panelView addSubview:_pubgSettingThicknessCard];

    _pubgSettingThicknessLabel = pubgCreateLabel(@"Độ dày nét vẽ địch");
    _pubgSettingThicknessLabel.hidden = YES;

    _pubgSettingThicknessValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgSettingThicknessValueLabel.textColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
    _pubgSettingThicknessValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightBold];
    _pubgSettingThicknessValueLabel.textAlignment = NSTextAlignmentRight;
    _pubgSettingThicknessValueLabel.text = [NSString stringWithFormat:@"%.1f px", g_pubgEspThickness];
    _pubgSettingThicknessValueLabel.hidden = YES;
    [_panelView addSubview:_pubgSettingThicknessValueLabel];

    _pubgSettingThicknessSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _pubgSettingThicknessSlider.minimumValue = 0.8f;
    _pubgSettingThicknessSlider.maximumValue = 3.5f;
    _pubgSettingThicknessSlider.value = g_pubgEspThickness;
    _pubgSettingThicknessSlider.continuous = YES;
    _pubgSettingThicknessSlider.minimumTrackTintColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
    _pubgSettingThicknessSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    [_pubgSettingThicknessSlider addTarget:self action:@selector(dsPubgThicknessChanged:) forControlEvents:UIControlEventValueChanged];
    _pubgSettingThicknessSlider.hidden = YES;
    [_panelView addSubview:_pubgSettingThicknessSlider];

    _pubgSettingInfoCard = [[UIView alloc] initWithFrame:CGRectZero];
    _pubgSettingInfoCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.045];
    _pubgSettingInfoCard.layer.cornerRadius = 9.0;
    _pubgSettingInfoCard.layer.borderWidth = 0.8;
    _pubgSettingInfoCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.09].CGColor;
    _pubgSettingInfoCard.hidden = YES;
    [_panelView addSubview:_pubgSettingInfoCard];

    _pubgSettingInfoLabel = pubgCreateLabel(@"Hệ thống & Tối ưu");
    _pubgSettingInfoLabel.textColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
    _pubgSettingInfoLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
    _pubgSettingInfoLabel.hidden = YES;

    _pubgSettingInfoDescLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pubgSettingInfoDescLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    _pubgSettingInfoDescLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    _pubgSettingInfoDescLabel.numberOfLines = 2;
    _pubgSettingInfoDescLabel.text = @"• Tần số quét: 60/120 FPS mượt mà\n• Độ trễ: Zero-Lag Interactive QoS";
    _pubgSettingInfoDescLabel.hidden = YES;
    [_panelView addSubview:_pubgSettingInfoDescLabel];

    _toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _toggleButton.backgroundColor = [UIColor colorWithRed:12/255.0 green:15/255.0 blue:24/255.0 alpha:0.92];
    _toggleButton.tintColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
    _toggleButton.layer.cornerRadius = kDSHostedMenuButtonSize * 0.5;
    _toggleButton.layer.borderWidth = 1.4;
    _toggleButton.layer.borderColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.8].CGColor;
    _toggleButton.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.5].CGColor;
    _toggleButton.layer.shadowRadius = 8.0;
    _toggleButton.layer.shadowOpacity = 0.8;
    _toggleButton.layer.shadowOffset = CGSizeZero;
    _toggleButton.layer.masksToBounds = NO;
    UIImage *image = ds_hosted_menu_toggle_image();
    if (image) {
        [_toggleButton setImage:image forState:UIControlStateNormal];
    } else {
        [_toggleButton setTitle:@"⚡" forState:UIControlStateNormal];
        [_toggleButton setTitleColor:[UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
        _toggleButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    }
    [_toggleButton addTarget:self action:@selector(dsToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dsMenuButtonPanned:)];
    [_toggleButton addGestureRecognizer:menuPan];
    [_contentView addSubview:_toggleButton];

    // Seed controls from persisted state so the first render uses the saved
    // camera zoom and minimap correction.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"lq_camxa_straight"];
    _enableSwitch.on = [defaults boolForKey:kDSHostedCamZoomEnabledKey];
    _autoSmiteSwitch.on = [defaults boolForKey:kDSHostedAutoSmiteEnabledKey];
    _autoSmiteObjectivesOnlySwitch.on =
        [defaults boolForKey:kDSHostedAutoSmiteObjectivesOnlyKey];
    id storedZoom = [defaults objectForKey:kDSHostedCamZoomValueKey];
    id storedAnchorX = [defaults objectForKey:kDSHostedMenuAnchorXKey];
    id storedAnchorY = [defaults objectForKey:kDSHostedMenuAnchorYKey];
    if (storedAnchorX && storedAnchorY) {
        CGFloat x = (CGFloat)[storedAnchorX doubleValue];
        CGFloat y = (CGFloat)[storedAnchorY doubleValue];
        if (isfinite(x) && isfinite(y) && x >= 0.0 && x <= 1.0 &&
            y >= 0.0 && y <= 1.0) {
            _buttonAnchorUnit = CGPointMake(x, y);
            _hasButtonAnchor = YES;
        }
    }
    id storedPanelX = [defaults objectForKey:kDSHostedMenuPanelXKey];
    id storedPanelY = [defaults objectForKey:kDSHostedMenuPanelYKey];
    if (storedPanelX && storedPanelY) {
        CGFloat x = (CGFloat)[storedPanelX doubleValue];
        CGFloat y = (CGFloat)[storedPanelY doubleValue];
        if (isfinite(x) && isfinite(y) && x >= 0.0 && x <= 1.0 &&
            y >= 0.0 && y <= 1.0) {
            _panelAnchorUnit = CGPointMake(x, y);
            _hasPanelAnchor = YES;
        }
    }
    if (ds_active_game() == 1) {
        _titleLabel.text = @"DARKPUBG";
        _zoomLabel.text = @"Khoảng cách hiện địch";
        _zoomSlider.minimumValue = 50.0f;
        _zoomSlider.maximumValue = 500.0f;
        _zoomSlider.value = g_dspubgMaxDistance;
        if ([defaults objectForKey:@"pubg_box"] != nil) g_pubgEspBox = [defaults boolForKey:@"pubg_box"];
        _pubgBoxSwitch.on = g_pubgEspBox;
        if ([defaults objectForKey:@"pubg_skeleton"] != nil) g_pubgEspSkeleton = [defaults boolForKey:@"pubg_skeleton"];
        _pubgSkeletonSwitch.on = g_pubgEspSkeleton;
        if ([defaults objectForKey:@"pubg_line"] != nil) g_pubgEspLine = [defaults boolForKey:@"pubg_line"];
        _pubgLineSwitch.on = g_pubgEspLine;
        if ([defaults objectForKey:@"pubg_health"] != nil) g_pubgEspHealth = [defaults boolForKey:@"pubg_health"];
        _pubgHealthSwitch.on = g_pubgEspHealth;
        if ([defaults objectForKey:@"pubg_name"] != nil) g_pubgEspName = [defaults boolForKey:@"pubg_name"];
        _pubgNameSwitch.on = g_pubgEspName;
        if ([defaults objectForKey:@"pubg_dist"] != nil) g_pubgEspDist = [defaults boolForKey:@"pubg_dist"];
        _pubgDistSwitch.on = g_pubgEspDist;
        if ([defaults objectForKey:@"pubg_bot"] != nil) g_pubgEspBot = [defaults boolForKey:@"pubg_bot"];
        _pubgBotSwitch.on = g_pubgEspBot;
        if ([defaults objectForKey:@"pubg_arrow"] != nil) g_pubgEspArrow = [defaults boolForKey:@"pubg_arrow"];
        _pubgArrowSwitch.on = g_pubgEspArrow;
        if ([defaults objectForKey:@"pubg_vehicle"] != nil) g_pubgEspVehicle = [defaults boolForKey:@"pubg_vehicle"];
        _pubgVehicleSwitch.on = g_pubgEspVehicle;
        if ([defaults objectForKey:@"pubg_vehicle_hp"] != nil) g_pubgEspVehicleHp = [defaults boolForKey:@"pubg_vehicle_hp"];
        _pubgVehicleHpSwitch.on = g_pubgEspVehicleHp;
        if ([defaults objectForKey:@"pubg_vehicle_fuel"] != nil) g_pubgEspVehicleFuel = [defaults boolForKey:@"pubg_vehicle_fuel"];
        _pubgVehicleFuelSwitch.on = g_pubgEspVehicleFuel;
        if ([defaults objectForKey:@"pubg_weapon"] != nil) g_pubgEspWeapon = [defaults boolForKey:@"pubg_weapon"];
        _pubgWeaponSwitch.on = g_pubgEspWeapon;
        if ([defaults objectForKey:@"pubg_armor"] != nil) g_pubgEspArmor = [defaults boolForKey:@"pubg_armor"];
        _pubgArmorSwitch.on = g_pubgEspArmor;
        if ([defaults objectForKey:@"pubg_bag"] != nil) g_pubgEspBag = [defaults boolForKey:@"pubg_bag"];
        _pubgBagSwitch.on = g_pubgEspBag;
        if ([defaults objectForKey:@"pubg_scope"] != nil) g_pubgEspScope = [defaults boolForKey:@"pubg_scope"];
        _pubgScopeSwitch.on = g_pubgEspScope;
        if ([defaults objectForKey:@"pubg_crate"] != nil) g_pubgEspCrate = [defaults boolForKey:@"pubg_crate"];
        _pubgCrateSwitch.on = g_pubgEspCrate;
        if ([defaults objectForKey:@"pubg_item_dist"] != nil) g_pubgItemMaxDistance = [defaults floatForKey:@"pubg_item_dist"];
        _pubgItemScanSlider.value = g_pubgItemMaxDistance;
        _pubgItemScanValueLabel.text = [NSString stringWithFormat:@"%.0fm", g_pubgItemMaxDistance];

        if ([defaults objectForKey:@"pubg_lang"] != nil) g_pubgLanguage = (int)[defaults integerForKey:@"pubg_lang"];
        _pubgLangSegment.selectedSegmentIndex = g_pubgLanguage;
        if ([defaults objectForKey:@"pubg_thickness"] != nil) {
            g_pubgEspThickness = [defaults floatForKey:@"pubg_thickness"];
            if (g_pubgEspThickness < 0.8f) g_pubgEspThickness = 0.8f;
            if (g_pubgEspThickness > 3.5f) g_pubgEspThickness = 3.5f;
        }
        _pubgSettingThicknessSlider.value = g_pubgEspThickness;
        _pubgSettingThicknessValueLabel.text = [NSString stringWithFormat:@"%.1f px", g_pubgEspThickness];
        [self dsUpdatePubgLanguage];
    } else {
        _titleLabel.text = @"LQ Tools";
        _zoomLabel.text = @"Zoom";
        _zoomSlider.minimumValue = kDSHostedCamZoomMin;
        _zoomSlider.maximumValue = kDSHostedCamZoomMax;
        float initialZoom = storedZoom ? (float)[storedZoom doubleValue] : 1.0f;
        if (!isfinite(initialZoom)) initialZoom = 1.0f;
        _zoomSlider.value = fminf(fmaxf(initialZoom, kDSHostedCamZoomMin),
                                  kDSHostedCamZoomMax);
        ds_lq_camera_zoom_set(_enableSwitch.on, _zoomSlider.value);
        ds_lq_auto_smite_set(_autoSmiteSwitch.on);
        ds_lq_auto_smite_objectives_only_set(
            _autoSmiteObjectivesOnlySwitch.on);
        CGPoint minimapOffset = ds_hosted_minimap_offset();
        _minimapXSlider.value = (float)minimapOffset.x;
        _minimapYSlider.value = (float)minimapOffset.y;
    }

    [self dsSetExpanded:g_hostedMenuExpanded];
    [self dsUpdateValueLabel];
    [self dsApplyOrientation];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self dsApplyOrientation];
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)dsSetExpanded:(BOOL)expanded {
    BOOL desiredPanelHidden = !expanded;
    BOOL changed = g_hostedMenuExpanded != expanded ||
                   _panelView.hidden != desiredPanelHidden;
    g_hostedMenuExpanded = expanded;
    if (!changed) return;
    _panelView.hidden = desiredPanelHidden;
    [self dsLayoutMenu];
}

- (void)dsLayoutMenu {
    CGRect bounds = _contentView.bounds;
    CGFloat boundsW = CGRectGetWidth(bounds);
    CGFloat panelW = (ds_active_game() == 1) ? 300.0 : MIN((CGFloat)312.0, MAX((CGFloat)260.0, boundsW - 28.0));
    CGFloat panelH = (ds_active_game() == 1) ? 328.0 : 311.0;
    CGFloat boundsH = CGRectGetHeight(bounds);
    CGFloat defaultPanelY = MIN((CGFloat)82.0,
        MAX((CGFloat)10.0, boundsH - panelH - 10.0));
    CGPoint buttonAnchor = _hasButtonAnchor
        ? CGPointMake(_buttonAnchorUnit.x * boundsW,
                      _buttonAnchorUnit.y * boundsH)
        : CGPointMake(14.0 + kDSHostedMenuButtonSize * 0.5,
                      defaultPanelY + 46.0 + kDSHostedMenuButtonSize * 0.5);
    CGFloat buttonHalf = kDSHostedMenuButtonSize * 0.5;
    buttonAnchor.x = MIN(MAX(buttonAnchor.x, buttonHalf + 4.0),
                         boundsW - buttonHalf - 4.0);
    buttonAnchor.y = MIN(MAX(buttonAnchor.y, buttonHalf + 4.0),
                         boundsH - buttonHalf - 4.0);
    _buttonAnchorUnit = CGPointMake(buttonAnchor.x / MAX(boundsW, 1.0),
                                    buttonAnchor.y / MAX(boundsH, 1.0));
    _toggleButton.bounds = CGRectMake(0, 0, kDSHostedMenuButtonSize,
                                       kDSHostedMenuButtonSize);
    _toggleButton.center = buttonAnchor;
    if (!g_hostedMenuExpanded) {
        _panelView.frame = CGRectZero;
        return;
    }

    CGPoint panelAnchor = _hasPanelAnchor
        ? CGPointMake(_panelAnchorUnit.x * boundsW, _panelAnchorUnit.y * boundsH)
        : CGPointMake(14.0 + panelW * 0.5, defaultPanelY + panelH * 0.5);
    panelAnchor.x = MIN(MAX(panelAnchor.x, panelW * 0.5 + 10.0),
                        boundsW - panelW * 0.5 - 10.0);
    panelAnchor.y = MIN(MAX(panelAnchor.y, panelH * 0.5 + 10.0),
                        boundsH - panelH * 0.5 - 10.0);
    _panelAnchorUnit = CGPointMake(panelAnchor.x / MAX(boundsW, 1.0),
                                   panelAnchor.y / MAX(boundsH, 1.0));
    CGFloat panelX = panelAnchor.x - panelW * 0.5;
    CGFloat panelY = panelAnchor.y - panelH * 0.5;
    _panelView.frame = CGRectMake(panelX, panelY, panelW, panelH);
    CGRect panelBounds = _panelView.bounds;
    _titleLabel.frame = CGRectMake(16.0, 9.0,
                                    CGRectGetWidth(panelBounds) - 60.0, 22.0);
    _closeButton.frame = CGRectMake(CGRectGetWidth(panelBounds) - 36.0, 8.0,
                                    26.0, 26.0);

    if (ds_active_game() == 1) {
        _titleLabel.text = @"DARKPUBG";
        _titleLabel.textColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
        _enableLabel.hidden = YES;
        _enableSwitch.hidden = YES;
        _autoSmiteLabel.hidden = YES;
        _autoSmiteSwitch.hidden = YES;
        _autoSmiteObjectivesOnlyLabel.hidden = YES;
        _autoSmiteObjectivesOnlySwitch.hidden = YES;
        _minimapXLabel.hidden = YES;
        _minimapXMinusButton.hidden = YES;
        _minimapXSlider.hidden = YES;
        _minimapXPlusButton.hidden = YES;
        _minimapXValueLabel.hidden = YES;
        _minimapYLabel.hidden = YES;
        _minimapYMinusButton.hidden = YES;
        _minimapYSlider.hidden = YES;
        _minimapYPlusButton.hidden = YES;
        _minimapYValueLabel.hidden = YES;
        CGFloat cardW = (panelW - 32.0) * 0.5;
        CGFloat cardH = 30.0;
        CGFloat col1X = 12.0;
        CGFloat col2X = 12.0 + cardW + 8.0;
        CGFloat switchRightPadding = 8.0 + (51.0 * 0.70 * 0.5);

        auto layoutCardSwitch = ^(UISwitch *s, CGFloat cardRightX, CGFloat cardCenterY) {
            s.bounds = CGRectMake(0, 0, 51.0, 31.0);
            s.center = CGPointMake(cardRightX - switchRightPadding, cardCenterY);
        };

        // Master ESP Card
        _masterCard.hidden = NO;
        _masterCard.frame = CGRectMake(12.0, 36.0, panelW - 24.0, 32.0);
        _espLabel.hidden = NO;
        _espLabel.text = (g_pubgLanguage == 1) ? @"Master ESP" : @"Bật ESP Master";
        _espLabel.textColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
        _espLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold];
        _espLabel.frame = CGRectMake(22.0, 42.0, 150.0, 20.0);
        _espSwitch.hidden = NO;
        _espSwitch.transform = CGAffineTransformMakeScale(0.70, 0.70);
        layoutCardSwitch(_espSwitch, panelW - 12.0, 36.0 + 16.0);

        // Tab Bar setup (3 tabs: ESP Địch, Vật Phẩm, Cài Đặt)
        _pubgTabBar.hidden = NO;
        CGFloat tabTotalW = panelW - 24.0;
        _pubgTabBar.frame = CGRectMake(12.0, 70.0, tabTotalW, 26.0);
        CGFloat tabGap = 4.0;
        CGFloat tabW = floorf((tabTotalW - tabGap * 2.0) / 3.0);
        _pubgTabButtonPlayer.frame = CGRectMake(0, 0, tabW, 26.0);
        _pubgTabButtonItems.frame = CGRectMake(tabW + tabGap, 0, tabW, 26.0);
        _pubgTabButtonSettings.frame = CGRectMake((tabW + tabGap) * 2.0, 0, tabTotalW - (tabW + tabGap) * 2.0, 26.0);

        auto resetTabBtn = ^(UIButton *b) {
            b.backgroundColor = [UIColor clearColor];
            b.layer.borderWidth = 0.0;
            [b setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateNormal];
        };
        auto setTabBtnActive = ^(UIButton *b, UIColor *bg, UIColor *border, UIColor *text) {
            b.backgroundColor = bg;
            b.layer.borderWidth = 1.0;
            b.layer.borderColor = border.CGColor;
            [b setTitleColor:text forState:UIControlStateNormal];
        };

        if (_pubgCurrentTab == 0) {
            setTabBtnActive(_pubgTabButtonPlayer,
                            [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.18],
                            [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.6],
                            [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0]);
            resetTabBtn(_pubgTabButtonItems);
            resetTabBtn(_pubgTabButtonSettings);

            // Hide Tab 1 (Items)
            for (int ci = 0; ci < 8; ci++) _pubgItemCards[ci].hidden = YES;
            _pubgVehicleLabel.hidden = YES; _pubgVehicleSwitch.hidden = YES;
            _pubgVehicleHpLabel.hidden = YES; _pubgVehicleHpSwitch.hidden = YES;
            _pubgVehicleFuelLabel.hidden = YES; _pubgVehicleFuelSwitch.hidden = YES;
            _pubgWeaponLabel.hidden = YES; _pubgWeaponSwitch.hidden = YES;
            _pubgArmorLabel.hidden = YES; _pubgArmorSwitch.hidden = YES;
            _pubgBagLabel.hidden = YES; _pubgBagSwitch.hidden = YES;
            _pubgScopeLabel.hidden = YES; _pubgScopeSwitch.hidden = YES;
            _pubgCrateLabel.hidden = YES; _pubgCrateSwitch.hidden = YES;
            _pubgItemScanCard.hidden = YES; _pubgItemScanLabel.hidden = YES;
            _pubgItemScanValueLabel.hidden = YES; _pubgItemScanSlider.hidden = YES;

            // Hide Tab 2 (Settings)
            _pubgSettingLangCard.hidden = YES; _pubgSettingLangLabel.hidden = YES; _pubgLangSegment.hidden = YES;
            _pubgSettingThicknessCard.hidden = YES; _pubgSettingThicknessLabel.hidden = YES;
            _pubgSettingThicknessValueLabel.hidden = YES; _pubgSettingThicknessSlider.hidden = YES;
            _pubgSettingInfoCard.hidden = YES; _pubgSettingInfoLabel.hidden = YES; _pubgSettingInfoDescLabel.hidden = YES;

            // Show & Layout Tab 0 (Player ESP)
            CGFloat cardH0 = 28.0;
            CGFloat y0 = 100.0;
            _pubgCards[0].frame = CGRectMake(col1X, y0, cardW, cardH0);
            _pubgCards[0].hidden = NO;
            _pubgBoxLabel.frame = CGRectMake(col1X + 8.0, y0 + 4.0, cardW - 48.0, 20.0);
            _pubgBoxLabel.hidden = NO;
            _pubgBoxSwitch.hidden = NO;
            layoutCardSwitch(_pubgBoxSwitch, col1X + cardW, y0 + cardH0 * 0.5);

            _pubgCards[1].frame = CGRectMake(col2X, y0, cardW, cardH0);
            _pubgCards[1].hidden = NO;
            _pubgSkeletonLabel.frame = CGRectMake(col2X + 8.0, y0 + 4.0, cardW - 48.0, 20.0);
            _pubgSkeletonLabel.hidden = NO;
            _pubgSkeletonSwitch.hidden = NO;
            layoutCardSwitch(_pubgSkeletonSwitch, col2X + cardW, y0 + cardH0 * 0.5);

            CGFloat y1 = 132.0;
            _pubgCards[2].frame = CGRectMake(col1X, y1, cardW, cardH0);
            _pubgCards[2].hidden = NO;
            _pubgLineLabel.frame = CGRectMake(col1X + 8.0, y1 + 4.0, cardW - 48.0, 20.0);
            _pubgLineLabel.hidden = NO;
            _pubgLineSwitch.hidden = NO;
            layoutCardSwitch(_pubgLineSwitch, col1X + cardW, y1 + cardH0 * 0.5);

            _pubgCards[3].frame = CGRectMake(col2X, y1, cardW, cardH0);
            _pubgCards[3].hidden = NO;
            _pubgHealthLabel.frame = CGRectMake(col2X + 8.0, y1 + 4.0, cardW - 48.0, 20.0);
            _pubgHealthLabel.hidden = NO;
            _pubgHealthSwitch.hidden = NO;
            layoutCardSwitch(_pubgHealthSwitch, col2X + cardW, y1 + cardH0 * 0.5);

            CGFloat y2 = 164.0;
            _pubgCards[4].frame = CGRectMake(col1X, y2, cardW, cardH0);
            _pubgCards[4].hidden = NO;
            _pubgNameLabel.frame = CGRectMake(col1X + 8.0, y2 + 4.0, cardW - 48.0, 20.0);
            _pubgNameLabel.hidden = NO;
            _pubgNameSwitch.hidden = NO;
            layoutCardSwitch(_pubgNameSwitch, col1X + cardW, y2 + cardH0 * 0.5);

            _pubgCards[5].frame = CGRectMake(col2X, y2, cardW, cardH0);
            _pubgCards[5].hidden = NO;
            _pubgDistLabel.frame = CGRectMake(col2X + 8.0, y2 + 4.0, cardW - 48.0, 20.0);
            _pubgDistLabel.hidden = NO;
            _pubgDistSwitch.hidden = NO;
            layoutCardSwitch(_pubgDistSwitch, col2X + cardW, y2 + cardH0 * 0.5);

            CGFloat y3 = 196.0;
            _pubgCards[6].frame = CGRectMake(col1X, y3, cardW, cardH0);
            _pubgCards[6].hidden = NO;
            _pubgBotLabel.frame = CGRectMake(col1X + 8.0, y3 + 4.0, cardW - 48.0, 20.0);
            _pubgBotLabel.hidden = NO;
            _pubgBotSwitch.hidden = NO;
            layoutCardSwitch(_pubgBotSwitch, col1X + cardW, y3 + cardH0 * 0.5);

            _pubgCards[7].frame = CGRectMake(col2X, y3, cardW, cardH0);
            _pubgCards[7].hidden = NO;
            _pubgArrowLabel.frame = CGRectMake(col2X + 8.0, y3 + 4.0, cardW - 48.0, 20.0);
            _pubgArrowLabel.hidden = NO;
            _pubgArrowSwitch.hidden = NO;
            layoutCardSwitch(_pubgArrowSwitch, col2X + cardW, y3 + cardH0 * 0.5);

            CGFloat y4 = 230.0;
            _scanCard.frame = CGRectMake(col1X, y4, panelW - 24.0, 48.0);
            _scanCard.hidden = NO;
            _zoomLabel.text = (g_pubgLanguage == 1) ? @"Enemy ESP Distance" : @"Khoảng cách hiện địch";
            _zoomLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
            _zoomLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
            _zoomLabel.hidden = NO;
            _zoomValueLabel.textColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
            _zoomValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightBold];
            _zoomValueLabel.hidden = NO;
            _zoomSlider.hidden = NO;
            _zoomSlider.minimumTrackTintColor = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0];
            _zoomLabel.frame = CGRectMake(col1X + 10.0, y4 + 3.0, 160.0, 18.0);
            _zoomValueLabel.frame = CGRectMake(panelW - 90.0, y4 + 3.0, 78.0, 18.0);
            _zoomSlider.frame = CGRectMake(col1X + 8.0, y4 + 21.0, panelW - 40.0, 22.0);
        } else if (_pubgCurrentTab == 1) {
            setTabBtnActive(_pubgTabButtonItems,
                            [UIColor colorWithRed:255/255.0 green:215/255.0 blue:0/255.0 alpha:0.18],
                            [UIColor colorWithRed:255/255.0 green:215/255.0 blue:0/255.0 alpha:0.6],
                            [UIColor colorWithRed:255/255.0 green:215/255.0 blue:0/255.0 alpha:1.0]);
            resetTabBtn(_pubgTabButtonPlayer);
            resetTabBtn(_pubgTabButtonSettings);

            // Hide Tab 0 (Player ESP)
            for (int ci = 0; ci < 8; ci++) _pubgCards[ci].hidden = YES;
            _pubgBoxLabel.hidden = YES; _pubgBoxSwitch.hidden = YES;
            _pubgSkeletonLabel.hidden = YES; _pubgSkeletonSwitch.hidden = YES;
            _pubgLineLabel.hidden = YES; _pubgLineSwitch.hidden = YES;
            _pubgHealthLabel.hidden = YES; _pubgHealthSwitch.hidden = YES;
            _pubgNameLabel.hidden = YES; _pubgNameSwitch.hidden = YES;
            _pubgDistLabel.hidden = YES; _pubgDistSwitch.hidden = YES;
            _pubgBotLabel.hidden = YES; _pubgBotSwitch.hidden = YES;
            _pubgArrowLabel.hidden = YES; _pubgArrowSwitch.hidden = YES;
            _scanCard.hidden = YES; _zoomLabel.hidden = YES; _zoomValueLabel.hidden = YES; _zoomSlider.hidden = YES;

            // Hide Tab 2 (Settings)
            _pubgSettingLangCard.hidden = YES; _pubgSettingLangLabel.hidden = YES; _pubgLangSegment.hidden = YES;
            _pubgSettingThicknessCard.hidden = YES; _pubgSettingThicknessLabel.hidden = YES;
            _pubgSettingThicknessValueLabel.hidden = YES; _pubgSettingThicknessSlider.hidden = YES;
            _pubgSettingInfoCard.hidden = YES; _pubgSettingInfoLabel.hidden = YES; _pubgSettingInfoDescLabel.hidden = YES;

            // Show & Layout Tab 1 (Items)
            CGFloat cardH1 = 28.0;
            CGFloat y0 = 100.0;
            _pubgItemCards[0].frame = CGRectMake(col1X, y0, cardW, cardH1);
            _pubgItemCards[0].hidden = NO;
            _pubgVehicleLabel.frame = CGRectMake(col1X + 8.0, y0 + 4.0, cardW - 48.0, 20.0);
            _pubgVehicleLabel.hidden = NO;
            _pubgVehicleSwitch.hidden = NO;
            layoutCardSwitch(_pubgVehicleSwitch, col1X + cardW, y0 + cardH1 * 0.5);

            _pubgItemCards[1].frame = CGRectMake(col2X, y0, cardW, cardH1);
            _pubgItemCards[1].hidden = NO;
            _pubgVehicleHpLabel.frame = CGRectMake(col2X + 8.0, y0 + 4.0, cardW - 48.0, 20.0);
            _pubgVehicleHpLabel.hidden = NO;
            _pubgVehicleHpSwitch.hidden = NO;
            layoutCardSwitch(_pubgVehicleHpSwitch, col2X + cardW, y0 + cardH1 * 0.5);

            CGFloat y1 = 132.0;
            _pubgItemCards[2].frame = CGRectMake(col1X, y1, cardW, cardH1);
            _pubgItemCards[2].hidden = NO;
            _pubgVehicleFuelLabel.frame = CGRectMake(col1X + 8.0, y1 + 4.0, cardW - 48.0, 20.0);
            _pubgVehicleFuelLabel.hidden = NO;
            _pubgVehicleFuelSwitch.hidden = NO;
            layoutCardSwitch(_pubgVehicleFuelSwitch, col1X + cardW, y1 + cardH1 * 0.5);

            _pubgItemCards[3].frame = CGRectMake(col2X, y1, cardW, cardH1);
            _pubgItemCards[3].hidden = NO;
            _pubgWeaponLabel.frame = CGRectMake(col2X + 8.0, y1 + 4.0, cardW - 48.0, 20.0);
            _pubgWeaponLabel.hidden = NO;
            _pubgWeaponSwitch.hidden = NO;
            layoutCardSwitch(_pubgWeaponSwitch, col2X + cardW, y1 + cardH1 * 0.5);

            CGFloat y2 = 164.0;
            _pubgItemCards[4].frame = CGRectMake(col1X, y2, cardW, cardH1);
            _pubgItemCards[4].hidden = NO;
            _pubgArmorLabel.frame = CGRectMake(col1X + 8.0, y2 + 4.0, cardW - 48.0, 20.0);
            _pubgArmorLabel.hidden = NO;
            _pubgArmorSwitch.hidden = NO;
            layoutCardSwitch(_pubgArmorSwitch, col1X + cardW, y2 + cardH1 * 0.5);

            _pubgItemCards[5].frame = CGRectMake(col2X, y2, cardW, cardH1);
            _pubgItemCards[5].hidden = NO;
            _pubgBagLabel.frame = CGRectMake(col2X + 8.0, y2 + 4.0, cardW - 48.0, 20.0);
            _pubgBagLabel.hidden = NO;
            _pubgBagSwitch.hidden = NO;
            layoutCardSwitch(_pubgBagSwitch, col2X + cardW, y2 + cardH1 * 0.5);

            CGFloat y3 = 196.0;
            _pubgItemCards[6].frame = CGRectMake(col1X, y3, cardW, cardH1);
            _pubgItemCards[6].hidden = NO;
            _pubgScopeLabel.frame = CGRectMake(col1X + 8.0, y3 + 4.0, cardW - 48.0, 20.0);
            _pubgScopeLabel.hidden = NO;
            _pubgScopeSwitch.hidden = NO;
            layoutCardSwitch(_pubgScopeSwitch, col1X + cardW, y3 + cardH1 * 0.5);

            _pubgItemCards[7].frame = CGRectMake(col2X, y3, cardW, cardH1);
            _pubgItemCards[7].hidden = NO;
            _pubgCrateLabel.frame = CGRectMake(col2X + 8.0, y3 + 4.0, cardW - 48.0, 20.0);
            _pubgCrateLabel.hidden = NO;
            _pubgCrateSwitch.hidden = NO;
            layoutCardSwitch(_pubgCrateSwitch, col2X + cardW, y3 + cardH1 * 0.5);

            CGFloat y4 = 230.0;
            _pubgItemScanCard.frame = CGRectMake(col1X, y4, panelW - 24.0, 48.0);
            _pubgItemScanCard.hidden = NO;
            _pubgItemScanLabel.frame = CGRectMake(col1X + 10.0, y4 + 3.0, 160.0, 18.0);
            _pubgItemScanLabel.hidden = NO;
            _pubgItemScanValueLabel.frame = CGRectMake(panelW - 90.0, y4 + 3.0, 78.0, 18.0);
            _pubgItemScanValueLabel.hidden = NO;
            _pubgItemScanSlider.frame = CGRectMake(col1X + 8.0, y4 + 21.0, panelW - 40.0, 22.0);
            _pubgItemScanSlider.hidden = NO;
        } else {
            // Tab 2: Settings (Cài Đặt)
            setTabBtnActive(_pubgTabButtonSettings,
                            [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.18],
                            [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.6],
                            [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:1.0]);
            resetTabBtn(_pubgTabButtonPlayer);
            resetTabBtn(_pubgTabButtonItems);

            // Hide Tab 0 (Player ESP)
            for (int ci = 0; ci < 8; ci++) _pubgCards[ci].hidden = YES;
            _pubgBoxLabel.hidden = YES; _pubgBoxSwitch.hidden = YES;
            _pubgSkeletonLabel.hidden = YES; _pubgSkeletonSwitch.hidden = YES;
            _pubgLineLabel.hidden = YES; _pubgLineSwitch.hidden = YES;
            _pubgHealthLabel.hidden = YES; _pubgHealthSwitch.hidden = YES;
            _pubgNameLabel.hidden = YES; _pubgNameSwitch.hidden = YES;
            _pubgDistLabel.hidden = YES; _pubgDistSwitch.hidden = YES;
            _pubgBotLabel.hidden = YES; _pubgBotSwitch.hidden = YES;
            _pubgArrowLabel.hidden = YES; _pubgArrowSwitch.hidden = YES;
            _scanCard.hidden = YES; _zoomLabel.hidden = YES; _zoomValueLabel.hidden = YES; _zoomSlider.hidden = YES;

            // Hide Tab 1 (Items)
            for (int ci = 0; ci < 8; ci++) _pubgItemCards[ci].hidden = YES;
            _pubgVehicleLabel.hidden = YES; _pubgVehicleSwitch.hidden = YES;
            _pubgVehicleHpLabel.hidden = YES; _pubgVehicleHpSwitch.hidden = YES;
            _pubgVehicleFuelLabel.hidden = YES; _pubgVehicleFuelSwitch.hidden = YES;
            _pubgWeaponLabel.hidden = YES; _pubgWeaponSwitch.hidden = YES;
            _pubgArmorLabel.hidden = YES; _pubgArmorSwitch.hidden = YES;
            _pubgBagLabel.hidden = YES; _pubgBagSwitch.hidden = YES;
            _pubgScopeLabel.hidden = YES; _pubgScopeSwitch.hidden = YES;
            _pubgCrateLabel.hidden = YES; _pubgCrateSwitch.hidden = YES;
            _pubgItemScanCard.hidden = YES; _pubgItemScanLabel.hidden = YES;
            _pubgItemScanValueLabel.hidden = YES; _pubgItemScanSlider.hidden = YES;

            // Show & Layout Tab 2 (Settings)
            CGFloat cardWFull = panelW - 24.0;
            CGFloat y0 = 100.0;
            _pubgSettingLangCard.frame = CGRectMake(col1X, y0, cardWFull, 52.0);
            _pubgSettingLangCard.hidden = NO;
            _pubgSettingLangLabel.frame = CGRectMake(col1X + 10.0, y0 + 3.0, cardWFull - 20.0, 18.0);
            _pubgSettingLangLabel.hidden = NO;
            _pubgLangSegment.frame = CGRectMake(col1X + 8.0, y0 + 22.0, cardWFull - 16.0, 24.0);
            _pubgLangSegment.hidden = NO;

            CGFloat y1 = 158.0;
            _pubgSettingThicknessCard.frame = CGRectMake(col1X, y1, cardWFull, 52.0);
            _pubgSettingThicknessCard.hidden = NO;
            _pubgSettingThicknessLabel.frame = CGRectMake(col1X + 10.0, y1 + 3.0, cardWFull - 90.0, 18.0);
            _pubgSettingThicknessLabel.hidden = NO;
            _pubgSettingThicknessValueLabel.frame = CGRectMake(col1X + cardWFull - 80.0, y1 + 3.0, 70.0, 18.0);
            _pubgSettingThicknessValueLabel.text = [NSString stringWithFormat:@"%.1f px", g_pubgEspThickness];
            _pubgSettingThicknessValueLabel.hidden = NO;
            _pubgSettingThicknessSlider.frame = CGRectMake(col1X + 8.0, y1 + 22.0, cardWFull - 16.0, 24.0);
            _pubgSettingThicknessSlider.hidden = NO;

            CGFloat y2 = 216.0;
            _pubgSettingInfoCard.frame = CGRectMake(col1X, y2, cardWFull, 62.0);
            _pubgSettingInfoCard.hidden = NO;
            _pubgSettingInfoLabel.frame = CGRectMake(col1X + 10.0, y2 + 5.0, cardWFull - 20.0, 18.0);
            _pubgSettingInfoLabel.hidden = NO;
            _pubgSettingInfoDescLabel.frame = CGRectMake(col1X + 10.0, y2 + 24.0, cardWFull - 20.0, 32.0);
            _pubgSettingInfoDescLabel.hidden = NO;
        }

        // Reset button
        _resetButton.hidden = NO;
        _resetButton.frame = CGRectMake(12.0, 286.0, panelW - 24.0, 26.0);
        [_panelView bringSubviewToFront:_resetButton];
    } else {
        _masterCard.hidden = YES;
        for (int ci = 0; ci < 8; ci++) _pubgCards[ci].hidden = YES;
        _scanCard.hidden = YES;
        _espLabel.text = @"ESP";
        _espLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.86];
        _espLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        _espLabel.frame = CGRectMake(14.0, 40.0, 90.0, 20.0);
        _espSwitch.frame = CGRectMake(CGRectGetWidth(panelBounds) - 62.0, 35.0, 51.0, 31.0);

        _pubgBoxLabel.hidden = YES;
        _pubgBoxSwitch.hidden = YES;
        _pubgSkeletonLabel.hidden = YES;
        _pubgSkeletonSwitch.hidden = YES;
        _pubgLineLabel.hidden = YES;
        _pubgLineSwitch.hidden = YES;
        _pubgHealthLabel.hidden = YES;
        _pubgHealthSwitch.hidden = YES;
        _pubgNameLabel.hidden = YES;
        _pubgNameSwitch.hidden = YES;
        _pubgDistLabel.hidden = YES;
        _pubgDistSwitch.hidden = YES;
        _pubgBotLabel.hidden = YES;
        _pubgBotSwitch.hidden = YES;
        _pubgArrowLabel.hidden = YES;
        _pubgArrowSwitch.hidden = YES;
        _pubgVehicleLabel.hidden = YES;
        _pubgVehicleSwitch.hidden = YES;
        _pubgVehicleHpLabel.hidden = YES;
        _pubgVehicleHpSwitch.hidden = YES;
        _pubgVehicleFuelLabel.hidden = YES;
        _pubgVehicleFuelSwitch.hidden = YES;
        _pubgTabBar.hidden = YES;
        for (int ci = 0; ci < 8; ci++) _pubgItemCards[ci].hidden = YES;
        _pubgWeaponLabel.hidden = YES; _pubgWeaponSwitch.hidden = YES;
        _pubgArmorLabel.hidden = YES; _pubgArmorSwitch.hidden = YES;
        _pubgBagLabel.hidden = YES; _pubgBagSwitch.hidden = YES;
        _pubgScopeLabel.hidden = YES; _pubgScopeSwitch.hidden = YES;
        _pubgCrateLabel.hidden = YES; _pubgCrateSwitch.hidden = YES;
        _pubgItemScanCard.hidden = YES; _pubgItemScanLabel.hidden = YES;
        _pubgItemScanValueLabel.hidden = YES; _pubgItemScanSlider.hidden = YES;
        _pubgSettingLangCard.hidden = YES; _pubgSettingLangLabel.hidden = YES; _pubgLangSegment.hidden = YES;
        _pubgSettingThicknessCard.hidden = YES; _pubgSettingThicknessLabel.hidden = YES;
        _pubgSettingThicknessValueLabel.hidden = YES; _pubgSettingThicknessSlider.hidden = YES;
        _pubgSettingInfoCard.hidden = YES; _pubgSettingInfoLabel.hidden = YES; _pubgSettingInfoDescLabel.hidden = YES;

        _titleLabel.text = @"LQ Tools";
        _enableLabel.hidden = NO;
        _enableSwitch.hidden = NO;
        _autoSmiteLabel.hidden = NO;
        _autoSmiteSwitch.hidden = NO;
        _autoSmiteObjectivesOnlyLabel.hidden = NO;
        _autoSmiteObjectivesOnlySwitch.hidden = NO;
        _minimapXLabel.hidden = NO;
        _minimapXMinusButton.hidden = NO;
        _minimapXSlider.hidden = NO;
        _minimapXPlusButton.hidden = NO;
        _minimapXValueLabel.hidden = NO;
        _minimapYLabel.hidden = NO;
        _minimapYMinusButton.hidden = NO;
        _minimapYSlider.hidden = NO;
        _minimapYPlusButton.hidden = NO;
        _minimapYValueLabel.hidden = NO;
        _resetButton.hidden = NO;

        _enableLabel.frame = CGRectMake(13.0, 73.0, 90.0, 20.0);
        _enableSwitch.frame = CGRectMake(CGRectGetWidth(panelBounds) - 62.0, 68.0, 51.0, 31.0);
        _autoSmiteLabel.frame = CGRectMake(13.0, 104.0, 90.0, 20.0);
        _autoSmiteSwitch.frame = CGRectMake(CGRectGetWidth(panelBounds) - 62.0, 99.0, 51.0, 31.0);
        _autoSmiteObjectivesOnlyLabel.frame = CGRectMake(13.0, 135.0, 110.0, 20.0);
        _autoSmiteObjectivesOnlySwitch.frame = CGRectMake(
            CGRectGetWidth(panelBounds) - 62.0, 130.0, 51.0, 31.0);
        _zoomLabel.text = @"Zoom";
        _zoomLabel.hidden = NO;
        _zoomValueLabel.hidden = NO;
        _zoomSlider.hidden = NO;
        _zoomLabel.frame = CGRectMake(13.0, 166.0, 52.0, 20.0);
        _zoomValueLabel.frame = CGRectMake(CGRectGetWidth(panelBounds) - 58.0, 166.0, 46.0, 20.0);
        _zoomSlider.frame = CGRectMake(66.0, 163.0, CGRectGetWidth(panelBounds) - 132.0, 26.0);
        CGFloat panelWidth = CGRectGetWidth(panelBounds);
        _minimapXLabel.frame = CGRectMake(13.0, 197.0, 42.0, 20.0);
        _minimapXMinusButton.frame = CGRectMake(57.0, 193.0, 28.0, 28.0);
        _minimapXSlider.frame = CGRectMake(89.0, 194.0, panelWidth - 168.0, 26.0);
        _minimapXPlusButton.frame = CGRectMake(panelWidth - 75.0, 193.0, 28.0, 28.0);
        _minimapXValueLabel.frame = CGRectMake(panelWidth - 44.0, 197.0, 34.0, 20.0);
        _minimapYLabel.frame = CGRectMake(13.0, 228.0, 42.0, 20.0);
        _minimapYMinusButton.frame = CGRectMake(57.0, 224.0, 28.0, 28.0);
        _minimapYSlider.frame = CGRectMake(89.0, 225.0, panelWidth - 168.0, 26.0);
        _minimapYPlusButton.frame = CGRectMake(panelWidth - 75.0, 224.0, 28.0, 28.0);
        _minimapYValueLabel.frame = CGRectMake(panelWidth - 44.0, 228.0, 34.0, 20.0);
        _resetButton.frame = CGRectMake(13.0, CGRectGetHeight(panelBounds) - 36.0,
                                        CGRectGetWidth(panelBounds) - 26.0, 27.0);
    }
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
        _dragStartAnchor = CGPointMake(_buttonAnchorUnit.x * boundsW,
                                       _buttonAnchorUnit.y * boundsH);
    }
    CGPoint translation = [gesture translationInView:_contentView];
    CGPoint anchor = CGPointMake(_dragStartAnchor.x + translation.x,
                                 _dragStartAnchor.y + translation.y);
    CGFloat half = kDSHostedMenuButtonSize * 0.5;
    anchor.x = MIN(MAX(anchor.x, half + 4.0), boundsW - half - 4.0);
    anchor.y = MIN(MAX(anchor.y, half + 4.0), boundsH - half - 4.0);
    _buttonAnchorUnit = CGPointMake(anchor.x / boundsW, anchor.y / boundsH);
    _hasButtonAnchor = YES;
    [self dsLayoutMenu];
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {
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
        _dragStartAnchor = CGPointMake(_panelAnchorUnit.x * boundsW,
                                       _panelAnchorUnit.y * boundsH);
    }
    CGPoint translation = [gesture translationInView:_contentView];
    CGFloat panelW = CGRectGetWidth(_panelView.bounds);
    CGFloat panelH = CGRectGetHeight(_panelView.bounds);
    CGPoint anchor = CGPointMake(_dragStartAnchor.x + translation.x,
                                 _dragStartAnchor.y + translation.y);
    anchor.x = MIN(MAX(anchor.x, panelW * 0.5 + 10.0),
                       boundsW - panelW * 0.5 - 10.0);
    anchor.y = MIN(MAX(anchor.y, panelH * 0.5 + 10.0),
                       boundsH - panelH * 0.5 - 10.0);
    _panelAnchorUnit = CGPointMake(anchor.x / boundsW, anchor.y / boundsH);
    _hasPanelAnchor = YES;
    [self dsLayoutMenu];
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {
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
    _contentView.center = CGPointMake(CGRectGetWidth(windowBounds) * 0.5,
                                      CGRectGetHeight(windowBounds) * 0.5);
    if (UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)orientation)) {
        _contentView.bounds = CGRectMake(0, 0, CGRectGetHeight(windowBounds),
                                         CGRectGetWidth(windowBounds));
        double angle = (orientation == UIInterfaceOrientationLandscapeLeft)
            ? -M_PI_2 : M_PI_2;
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

- (void)dsEspSwitchChanged:(UISwitch *)sender {
    ds_hosted_esp_set_enabled(sender.on);
}

- (void)dsEnableSwitchChanged:(UISwitch *)sender {
    ds_lq_camera_zoom_set(sender.on, _zoomSlider.value);
}

- (void)dsAutoSmiteSwitchChanged:(UISwitch *)sender {
    ds_lq_auto_smite_set(sender.on);
}

- (void)dsAutoSmiteObjectivesOnlySwitchChanged:(UISwitch *)sender {
    ds_lq_auto_smite_objectives_only_set(sender.on);
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
    _pubgItemScanValueLabel.text = [NSString stringWithFormat:@"%.0fm", g_pubgItemMaxDistance];
    [NSUserDefaults.standardUserDefaults setFloat:g_pubgItemMaxDistance forKey:@"pubg_item_dist"];
}

- (void)dsPubgTabTapped:(UIButton *)sender {
    if (sender == _pubgTabButtonItems) {
        _pubgCurrentTab = 1;
    } else if (sender == _pubgTabButtonSettings) {
        _pubgCurrentTab = 2;
    } else {
        _pubgCurrentTab = 0;
    }
    [self dsLayoutMenu];
}

- (void)dsPubgLangChanged:(UISegmentedControl *)sender {
    g_pubgLanguage = (int)sender.selectedSegmentIndex;
    [NSUserDefaults.standardUserDefaults setInteger:g_pubgLanguage forKey:@"pubg_lang"];
    [self dsUpdatePubgLanguage];
}

- (void)dsPubgThicknessChanged:(UISlider *)sender {
    g_pubgEspThickness = sender.value;
    _pubgSettingThicknessValueLabel.text = [NSString stringWithFormat:@"%.1f px", g_pubgEspThickness];
    [NSUserDefaults.standardUserDefaults setFloat:g_pubgEspThickness forKey:@"pubg_thickness"];
}

- (void)dsUpdatePubgLanguage {
    BOOL isEn = (g_pubgLanguage == 1);

    // Tab buttons
    [_pubgTabButtonPlayer setTitle:isEn ? @"👤 Enemy" : @"👤 ESP Địch" forState:UIControlStateNormal];
    [_pubgTabButtonItems setTitle:isEn ? @"📦 Items" : @"📦 Vật Phẩm" forState:UIControlStateNormal];
    [_pubgTabButtonSettings setTitle:isEn ? @"⚙️ Settings" : @"⚙️ Cài Đặt" forState:UIControlStateNormal];

    // Master ESP
    _espLabel.text = isEn ? @"Master ESP" : @"Bật ESP Master";

    // Tab 0: Enemy ESP
    _pubgBoxLabel.text = isEn ? @"Corner Box 2D" : @"Box Góc 2D";
    _pubgSkeletonLabel.text = isEn ? @"Skeleton" : @"Xương";
    _pubgLineLabel.text = isEn ? @"Snapline" : @"Tia Line";
    _pubgHealthLabel.text = isEn ? @"Health Bar" : @"Thanh Máu";
    _pubgNameLabel.text = isEn ? @"Player Name" : @"Tên Địch";
    _pubgDistLabel.text = isEn ? @"Distance" : @"Khoảng Cách";
    _pubgBotLabel.text = isEn ? @"Show Bots AI" : @"Hiện Bot AI";
    _pubgArrowLabel.text = isEn ? @"360° Arrow" : @"Mũi Tên";
    _zoomLabel.text = isEn ? @"Enemy ESP Distance" : @"Khoảng cách hiện địch";

    // Tab 1: Items
    _pubgVehicleLabel.text = isEn ? @"Vehicles" : @"Hiện Xe";
    _pubgVehicleHpLabel.text = isEn ? @"Vehicle HP" : @"Máu Xe";
    _pubgVehicleFuelLabel.text = isEn ? @"Vehicle Fuel" : @"Xăng Xe";
    _pubgWeaponLabel.text = isEn ? @"Weapons" : @"Hiện Súng";
    _pubgArmorLabel.text = isEn ? @"Armor & Helm" : @"Giáp & Mũ";
    _pubgBagLabel.text = isEn ? @"Backpacks" : @"Hiện Balo";
    _pubgScopeLabel.text = isEn ? @"Scopes" : @"Ống Ngắm";
    _pubgCrateLabel.text = isEn ? @"Crates & AirDrop" : @"Hòm & Thính";
    _pubgItemScanLabel.text = isEn ? @"Item ESP Distance" : @"Khoảng cách vật phẩm";

    // Tab 2: Settings
    _pubgSettingLangLabel.text = isEn ? @"Menu Language" : @"Ngôn ngữ giao diện";
    _pubgSettingThicknessLabel.text = isEn ? @"Enemy Line Thickness" : @"Độ dày nét vẽ địch";
    _pubgSettingInfoLabel.text = isEn ? @"System & Optimization" : @"Hệ thống & Tối ưu";
    _pubgSettingInfoDescLabel.text = isEn
        ? @"• Display: 60/120 FPS ProMotion\n• Latency: Zero-Lag Interactive QoS"
        : @"• Tần số quét: 60/120 FPS mượt mà\n• Độ trễ: Zero-Lag Interactive QoS";

    // Reset button
    [_resetButton setTitle:isEn ? @"Reset to Defaults" : @"Khôi phục cài đặt gốc" forState:UIControlStateNormal];
}

- (void)dsZoomSliderChanged:(UISlider *)sender {
    if (ds_active_game() == 1) {
        g_dspubgMaxDistance = sender.value;
        [self dsUpdateValueLabel];
        return;
    }
    // Moving the slider is an explicit request to use camera zoom. Keeping the
    // switch off here made every slider event restore the stock value.
    if (!_enableSwitch.on) {
        [_enableSwitch setOn:YES animated:YES];
    }
    ds_lq_camera_zoom_set(true, sender.value);
    [self dsUpdateValueLabel];
}

- (void)dsMinimapOffsetChanged:(UISlider *)sender {
    (void)sender;
    ds_hosted_minimap_set_offset(CGPointMake(_minimapXSlider.value,
                                             _minimapYSlider.value));
    [self dsUpdateValueLabel];
}

- (void)dsMinimapStepTapped:(UIButton *)sender {
    UISlider *slider = nil;
    float delta = 0.0f;
    switch (sender.tag) {
        case kDSHostedMinimapXMinusTag:
            slider = _minimapXSlider;
            delta = -1.0f;
            break;
        case kDSHostedMinimapXPlusTag:
            slider = _minimapXSlider;
            delta = 1.0f;
            break;
        case kDSHostedMinimapYMinusTag:
            slider = _minimapYSlider;
            delta = -1.0f;
            break;
        case kDSHostedMinimapYPlusTag:
            slider = _minimapYSlider;
            delta = 1.0f;
            break;
        default:
            return;
    }
    float value = fminf(fmaxf(slider.value + delta, slider.minimumValue),
                        slider.maximumValue);
    [slider setValue:value animated:NO];
    [self dsMinimapOffsetChanged:slider];
}

- (void)dsResetTapped:(UIButton *)sender {
    (void)sender;
    if (ds_active_game() == 1) {
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
        [_zoomSlider setValue:400.0f animated:YES];
        g_pubgEspBox = YES;
        g_pubgEspSkeleton = YES;
        g_pubgEspLine = YES;
        g_pubgEspHealth = YES;
        g_pubgEspName = YES;
        g_pubgEspDist = YES;
        g_pubgEspBot = YES;
        g_pubgEspArrow = YES;
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
        return;
    }
    [_espSwitch setOn:YES animated:YES];
    ds_hosted_esp_set_enabled(true);
    [_enableSwitch setOn:NO animated:YES];
    [_autoSmiteSwitch setOn:NO animated:YES];
    [_autoSmiteObjectivesOnlySwitch setOn:NO animated:YES];
    [_zoomSlider setValue:1.0f animated:YES];
    [_minimapXSlider setValue:0.0f animated:YES];
    [_minimapYSlider setValue:0.0f animated:YES];
    ds_lq_camera_zoom_set(false, 1.0f);
    ds_lq_auto_smite_set(false);
    ds_lq_auto_smite_objectives_only_set(false);
    ds_hosted_minimap_set_offset(CGPointZero);
    [self dsUpdateValueLabel];
}

- (void)dsUpdateValueLabel {
    if (ds_active_game() == 1) {
        _zoomValueLabel.text = [NSString stringWithFormat:@"%.0fm", _zoomSlider.value];
        return;
    }
    _zoomValueLabel.text = [NSString stringWithFormat:@"%.2f", _zoomSlider.value];
    _minimapXValueLabel.text = [NSString stringWithFormat:@"%+.0f",
                               _minimapXSlider.value];
    _minimapYValueLabel.text = [NSString stringWithFormat:@"%+.0f",
                               _minimapYSlider.value];
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
    BOOL lqRenderSourceReady;
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

// Persistent AOV layer pool. Each frame only changes position, contents and
// visibility inside a disabled-actions transaction.
static UIImageView *g_hostedLQHeroViews[5] = {};
static UIImageView *g_hostedLQMinimapViews[5] = {};
static UIImageView *g_hostedLQStatusHeroViews[5] = {};
static CATextLayer *g_hostedLQHealthLabels[5] = {};
static CAShapeLayer *g_hostedLQUltimateDiamonds[5] = {};
static CATextLayer *g_hostedLQUltimateLabels[5] = {};
static CATextLayer *g_hostedLQTalentLabels[5] = {};
static CALayer *g_hostedLQMonsterViews[kDSLQMaxMonsters] = {};
static CATextLayer *g_hostedLQMonsterHealthLabels[kDSLQMaxMonsters] = {};
static CALayer *g_hostedLQMonsterMinimapViews[kDSLQMaxMonsters] = {};
static uint64_t g_hostedLQMonsterActors[kDSLQMaxMonsters] = {};
static uint32_t g_hostedLQMonsterConfigIds[kDSLQMaxMonsters] = {};
static uint64_t g_hostedLQMonsterLastSeen[kDSLQMaxMonsters] = {};
static int32_t g_hostedLQMonsterLastHealth[kDSLQMaxMonsters] = {};
static CGPoint g_hostedLQMonsterLastWorldPositions[kDSLQMaxMonsters] = {};
static CGPoint g_hostedLQMonsterLastMapPositions[kDSLQMaxMonsters] = {};
static BOOL g_hostedLQMonsterHasWorldPosition[kDSLQMaxMonsters] = {};
static BOOL g_hostedLQMonsterHasMapPosition[kDSLQMaxMonsters] = {};
static const CGFloat kDSLQHeroIconSize = 32.5;

static CGFloat ds_hosted_lq_minimap_icon_size(CGFloat screenHeight) {
    CGFloat nativeScale = MAX(UIScreen.mainScreen.nativeScale, 1.0);
    return nativeScale == 2.0 && screenHeight < 500.0
        ? 14.0 : 42.0 / nativeScale;
}

static CGFloat ds_hosted_lq_minimap_center_x(CGFloat gameScreenX,
                                              CGFloat gameScreenWidth,
                                              const float viewport[4],
                                              CGFloat overlayWidth,
                                              CGFloat safeAreaInset,
                                              CGFloat fallbackCenterX,
                                              BOOL *usedRuntime) {
    // RefreshMinimapFinalPos stores WorldToScreenPoint. The game subsequently
    // sends that point through the same form camera's ScreenToWorldPoint, so
    // remove its pixelRect before mapping the viewport coordinate to UIKit.
    CGFloat centerX = gameScreenWidth > 0.0 && viewport[2] > 0.0
        ? ((gameScreenX / gameScreenWidth - viewport[0]) / viewport[2]) *
              overlayWidth + safeAreaInset * 0.5
        : NAN;
    BOOL valid = isfinite(centerX) && centerX > 0.0;
    if (usedRuntime) *usedRuntime = valid;
    return valid ? centerX : fallbackCenterX;
}

static CGFloat ds_hosted_lq_minimap_center_y(CGFloat mapHeight,
                                              int32_t roomType,
                                              CGFloat gameScreenY,
                                              CGFloat gameScreenHeight,
                                              const float viewport[4],
                                              CGFloat overlayHeight,
                                              BOOL *usedRuntime) {
    // mmFinalScreenPos.y is the game's actual minimap anchor. It includes
    // layout choices such as moving the shop to the right; only the fallback
    // differs by map type. The hosted overlay's axes are manually rotated, so
    // convert the form-camera viewport's bottom-origin Y to UIKit's top-origin.
    if (isfinite(gameScreenY) && gameScreenY > 0.0 &&
        viewport[3] > 0.0 && gameScreenHeight > 0.0 &&
        overlayHeight > 0.0) {
        CGFloat viewportY =
            (gameScreenY / gameScreenHeight - viewport[1]) / viewport[3];
        // RefreshMinimapFinalPos projects mmUGUIRoot's lower pivot. Marker
        // offsets, however, are relative to the map center.
        CGFloat centerY = (1.0 - viewportY) * overlayHeight -
                          mapHeight * 0.5;
        if (isfinite(centerY) && centerY >= 0.0) {
            if (usedRuntime) *usedRuntime = YES;
            return centerY;
        }
    }
    if (usedRuntime) *usedRuntime = NO;
    if (roomType == 3) return mapHeight * 0.75 + 18.0;
    return mapHeight * 0.5 + 1.0;
}

static CGFloat ds_hosted_lq_minimap_layout_y_correction(
    int32_t storePosMode,
    CGFloat mapHeight,
    CGFloat rawAnchorY,
    CGFloat nodeRatio,
    CGFloat screenToLayerY) {
    CGFloat anchorHalfHeight = fabs(rawAnchorY) *
                               nodeRatio * screenToLayerY;
    CGFloat correction = mapHeight * 0.5 - anchorHalfHeight;
    if (!isfinite(correction) || fabs(correction) >= mapHeight * 0.1) {
        correction = 0.0;
    }

    if (storePosMode == 0) {
        // The store-left layout clips the outer minimap root at the top.
        CGFloat layoutRemainder = mapHeight - fabs(rawAnchorY);
        if (isfinite(layoutRemainder) && layoutRemainder > 0.0 &&
            layoutRemainder < mapHeight * 0.5) {
            correction += layoutRemainder * 0.5;
        }
    } else if (storePosMode == 1) {
        // The right-store minimap's visible content pivot sits one point above
        // the outer root returned by RefreshMinimapFinalPos.
        correction += 1.0;
    }
    return correction;
}

typedef struct {
    BOOL valid;
    CGFloat scaleX;
    CGFloat scaleY;
    CGFloat mapWidth;
    CGFloat mapHeight;
    CGPoint baseCenter;
    CGPoint markerCenter;
} DSHostedLQMinimapLayout;

// Runtime minimap geometry is identical for every hero and monster in one
// projection frame. Build its screen transform once, then share it across both
// render passes. The manual offset moves only minimap markers; status/cooldown
// widgets keep using baseCenter and remain in their original screen position.
static DSHostedLQMinimapLayout ds_hosted_lq_minimap_layout(
    CGFloat gameScreenWidth,
    CGFloat gameScreenHeight,
    const float viewport[4],
    CGFloat mapWidthPixels,
    CGFloat mapHeightPixels,
    CGFloat gameCenterX,
    CGFloat gameCenterY,
    CGFloat rawAnchorY,
    int32_t storePosMode,
    int32_t roomType,
    CGFloat overlayWidth,
    CGFloat overlayHeight,
    CGFloat runtimeMinimapInset) {
    DSHostedLQMinimapLayout layout = {};
    if (!viewport || !isfinite(gameScreenWidth) ||
        !isfinite(gameScreenHeight) || !isfinite(mapWidthPixels) ||
        !isfinite(mapHeightPixels) || gameScreenWidth <= 0.0 ||
        gameScreenHeight <= 0.0 || viewport[2] <= 0.0f ||
        viewport[3] <= 0.0f || mapWidthPixels <= 0.0 ||
        mapHeightPixels <= 0.0 || overlayWidth <= 0.0 ||
        overlayHeight <= 0.0) {
        return layout;
    }

    layout.scaleX = overlayWidth / (gameScreenWidth * viewport[2]);
    layout.scaleY = overlayHeight / (gameScreenHeight * viewport[3]);
    layout.mapWidth = mapWidthPixels * layout.scaleX;
    layout.mapHeight = mapHeightPixels * layout.scaleY;
    if (!isfinite(layout.scaleX) || !isfinite(layout.scaleY) ||
        !isfinite(layout.mapWidth) || !isfinite(layout.mapHeight) ||
        layout.scaleX <= 0.0 || layout.scaleY <= 0.0 ||
        layout.mapWidth <= 0.0 || layout.mapHeight <= 0.0) {
        DSHostedLQMinimapLayout empty = {};
        return empty;
    }

    CGFloat fallbackCenterX = runtimeMinimapInset + layout.mapWidth * 0.5;
    layout.baseCenter.x = ds_hosted_lq_minimap_center_x(
        gameCenterX, gameScreenWidth, viewport, overlayWidth,
        runtimeMinimapInset, fallbackCenterX, nullptr);
    BOOL usedRuntimeCenterY = NO;
    layout.baseCenter.y = ds_hosted_lq_minimap_center_y(
        layout.mapHeight, roomType, gameCenterY, gameScreenHeight,
        viewport, overlayHeight, &usedRuntimeCenterY);
    if (usedRuntimeCenterY) {
        CGFloat nodeRatio = MIN(gameScreenWidth / 1136.0,
                                gameScreenHeight / 640.0);
        layout.baseCenter.y -= ds_hosted_lq_minimap_layout_y_correction(
            storePosMode, layout.mapHeight, rawAnchorY, nodeRatio,
            layout.scaleY);
    }

    CGPoint offset = ds_hosted_minimap_offset();
    layout.markerCenter = CGPointMake(layout.baseCenter.x + offset.x,
                                      layout.baseCenter.y + offset.y);
    layout.valid = isfinite(layout.baseCenter.x) &&
                   isfinite(layout.baseCenter.y) &&
                   isfinite(layout.markerCenter.x) &&
                   isfinite(layout.markerCenter.y);
    return layout;
}
static int32_t g_hostedLQLastHealth[5] = {};
static uint32_t g_hostedLQHeroConfigIds[5] = {};
static uint32_t g_hostedLQHeroRequestedConfigIds[5] = {};
static uint32_t g_hostedLQHeroPlayerIds[5] = {};
static uint64_t g_hostedLQHeroActors[5] = {};
static uint64_t g_hostedLQHeroLastSeen[5] = {};
static uint64_t g_hostedLQHeroLastImageAttempt[5] = {};
static CGPoint g_hostedLQHeroLastPositions[5] = {};
static BOOL g_hostedLQHeroHasPosition[5] = {};
static uint64_t g_hostedLQSlotEpoch = 0;
static uint64_t g_hostedLQRenderSequence = 0;

static os_unfair_lock g_hostedLQHeroImageCacheLock = OS_UNFAIR_LOCK_INIT;
static std::atomic_bool g_dslqAllHeroImagesPrewarmStarted(false);

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t width;
    uint32_t height;
    uint32_t bytesPerRow;
    uint64_t payloadSize;
} DSLQDecodedImageCacheHeader;

static const uint32_t kDSLQDecodedImageCacheMagic = 0x44535149U;
static const uint32_t kDSLQDecodedImageCacheVersion = 1U;

static NSString *ds_lq_decoded_image_cache_directory(void) {
    static NSString *directory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *base = paths.firstObject ?: NSTemporaryDirectory();
        directory = [[base stringByAppendingPathComponent:
            @"DarkSpeed/HeroImageCache"] copy];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    });
    return directory;
}

static NSString *ds_lq_decoded_image_cache_path(uint32_t heroId) {
    if (!heroId) return nil;
    return [ds_lq_decoded_image_cache_directory()
        stringByAppendingPathComponent:
            [NSString stringWithFormat:@"hero_%u.rgba", heroId]];
}

static UIImage *ds_lq_load_decoded_image_from_disk(uint32_t heroId) {
    NSString *path = ds_lq_decoded_image_cache_path(heroId);
    if (!path) return nil;
    NSData *file = [NSData dataWithContentsOfFile:path
                                          options:NSDataReadingMappedIfSafe
                                            error:nil];
    if (!file || file.length < sizeof(DSLQDecodedImageCacheHeader)) return nil;

    DSLQDecodedImageCacheHeader header = {};
    memcpy(&header, file.bytes, sizeof(header));
    if (header.magic != kDSLQDecodedImageCacheMagic ||
        header.version != kDSLQDecodedImageCacheVersion ||
        !header.width || !header.height ||
        header.width > 4096 || header.height > 4096 ||
        header.bytesPerRow < header.width * 4U ||
        header.payloadSize != (uint64_t)header.bytesPerRow * header.height ||
        header.payloadSize > SIZE_MAX ||
        file.length != sizeof(header) + (NSUInteger)header.payloadSize) {
        return nil;
    }

    NSData *payload = [file subdataWithRange:NSMakeRange(
        sizeof(header), (NSUInteger)header.payloadSize)];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(
        (__bridge CFDataRef)payload);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = provider && colorSpace
        ? CGImageCreate(header.width, header.height, 8, 32,
                        header.bytesPerRow, colorSpace,
                        kCGImageAlphaPremultipliedLast |
                            kCGBitmapByteOrder32Big,
                        provider, NULL, false, kCGRenderingIntentDefault)
        : NULL;
    if (provider) CGDataProviderRelease(provider);
    if (colorSpace) CGColorSpaceRelease(colorSpace);
    if (!cgImage) return nil;
    UIImage *image = [UIImage imageWithCGImage:cgImage scale:1.0
                                   orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return image;
}

static void ds_lq_store_decoded_image_to_disk(uint32_t heroId,
                                               size_t width,
                                               size_t height,
                                               size_t bytesPerRow,
                                               const void *pixels) {
    if (!heroId || !pixels || !width || !height ||
        width > UINT32_MAX || height > UINT32_MAX ||
        bytesPerRow < width * 4 || bytesPerRow > UINT32_MAX ||
        height > SIZE_MAX / bytesPerRow) return;
    size_t payloadSize = bytesPerRow * height;
    if (payloadSize > UINT64_MAX) return;
    DSLQDecodedImageCacheHeader header = {
        kDSLQDecodedImageCacheMagic,
        kDSLQDecodedImageCacheVersion,
        (uint32_t)width,
        (uint32_t)height,
        (uint32_t)bytesPerRow,
        (uint64_t)payloadSize
    };
    NSMutableData *file = [NSMutableData dataWithCapacity:
        sizeof(header) + payloadSize];
    [file appendBytes:&header length:sizeof(header)];
    [file appendBytes:pixels length:payloadSize];
    NSString *path = ds_lq_decoded_image_cache_path(heroId);
    if (path) [file writeToFile:path options:NSDataWritingAtomic error:nil];
}

static NSMutableDictionary<NSNumber *, UIImage *> *ds_lq_hero_image_cache(void) {
    static NSMutableDictionary<NSNumber *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionaryWithCapacity:160];
    });
    return cache;
}

static UIImage *ds_lq_hero_image(uint32_t heroId) {
    if (!heroId) return nil;
    NSMutableDictionary<NSNumber *, UIImage *> *cache = ds_lq_hero_image_cache();
    NSNumber *key = @(heroId);
    os_unfair_lock_lock(&g_hostedLQHeroImageCacheLock);
    UIImage *image = cache[key];
    os_unfair_lock_unlock(&g_hostedLQHeroImageCacheLock);
    return image;
}

static UIImage *ds_lq_decode_hero_image(uint32_t heroId) {
    if (!heroId) return nil;
    UIImage *cached = ds_lq_hero_image(heroId);
    if (cached) return cached;

    UIImage *diskCached = ds_lq_load_decoded_image_from_disk(heroId);
    if (diskCached) {
        NSMutableDictionary<NSNumber *, UIImage *> *cache =
            ds_lq_hero_image_cache();
        NSNumber *key = @(heroId);
        os_unfair_lock_lock(&g_hostedLQHeroImageCacheLock);
        UIImage *existing = cache[key];
        if (!existing) cache[key] = diskCached;
        os_unfair_lock_unlock(&g_hostedLQHeroImageCacheLock);
        return existing ?: diskCached;
    }

    UIImage *image = nil;
    for (size_t i = 0; i < sizeof(heroArray) / sizeof(heroArray[0]); i++) {
        if ((uint32_t)heroArray[i].heroid != heroId) continue;
        NSData *data = [NSData dataWithBytesNoCopy:heroArray[i].data
                                            length:heroArray[i].size
                                      freeWhenDone:NO];
        image = [UIImage imageWithData:data];
        break;
    }
    if (!image) return nil;

    // Force bitmap decode away from the display callback. CALayer uses the
    // CGImage pixels directly, so UIImage's logical scale is not relevant.
    CGImageRef source = image.CGImage;
    size_t width = source ? CGImageGetWidth(source) : 0;
    size_t height = source ? CGImageGetHeight(source) : 0;
    if (source && width && height && width <= SIZE_MAX / 4) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = colorSpace
            ? CGBitmapContextCreate(NULL, width, height, 8, width * 4,
                                    colorSpace,
                                    kCGImageAlphaPremultipliedLast |
                                        kCGBitmapByteOrder32Big)
            : NULL;
        if (context) {
            CGContextSetBlendMode(context, kCGBlendModeCopy);
            CGContextDrawImage(context, CGRectMake(0, 0, width, height),
                               source);
            ds_lq_store_decoded_image_to_disk(
                heroId, width, height, width * 4,
                CGBitmapContextGetData(context));
            CGImageRef decoded = CGBitmapContextCreateImage(context);
            if (decoded) {
                image = [UIImage imageWithCGImage:decoded];
                CGImageRelease(decoded);
            }
            CGContextRelease(context);
        }
        if (colorSpace) CGColorSpaceRelease(colorSpace);
    }

    NSMutableDictionary<NSNumber *, UIImage *> *cache = ds_lq_hero_image_cache();
    NSNumber *key = @(heroId);
    os_unfair_lock_lock(&g_hostedLQHeroImageCacheLock);
    UIImage *existing = cache[key];
    if (!existing) cache[key] = image;
    os_unfair_lock_unlock(&g_hostedLQHeroImageCacheLock);
    return existing ?: image;
}

typedef struct {
    int count;
    uint32_t heroIds[kDSLQMaxEnemies];
} DSLQHeroImagePrewarmRequest;

static dispatch_queue_t ds_lq_hero_image_prewarm_queue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.darkspeed.lq.hero-images",
                                      DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static void ds_lq_prewarm_hero_images(const uint32_t *heroIds, int count) {
    DSLQHeroImagePrewarmRequest request = {};
    request.count = MIN(MAX(count, 0), kDSLQMaxEnemies);
    for (int i = 0; i < request.count; i++) request.heroIds[i] = heroIds[i];
    dispatch_async(ds_lq_hero_image_prewarm_queue(), ^{
        @autoreleasepool {
            for (int i = 0; i < request.count; i++)
                (void)ds_lq_decode_hero_image(request.heroIds[i]);
        }
    });
}

static void ds_lq_prewarm_all_hero_images(void) {
    bool expected = false;
    if (!g_dslqAllHeroImagesPrewarmStarted.compare_exchange_strong(
            expected, true, std::memory_order_acq_rel)) return;
    dispatch_async(ds_lq_hero_image_prewarm_queue(), ^{
        @autoreleasepool {
            const size_t count = sizeof(heroArray) / sizeof(heroArray[0]);
            for (size_t i = 0; i < count; i++)
                (void)ds_lq_decode_hero_image((uint32_t)heroArray[i].heroid);
        }
    });
}

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

#pragma mark - AOV icon render

static void ds_hosted_lq_hide_all(void) {
    for (int i = 0; i < kDSLQMaxEnemies; i++) {
        UIImageView *view = g_hostedLQHeroViews[i];
        if (view && !view.hidden) view.hidden = YES;
        UIImageView *minimapView = g_hostedLQMinimapViews[i];
        if (minimapView && !minimapView.hidden) minimapView.hidden = YES;
        UIImageView *statusView = g_hostedLQStatusHeroViews[i];
        if (statusView && !statusView.hidden) statusView.hidden = YES;
        if (g_hostedLQHealthLabels[i])
            g_hostedLQHealthLabels[i].hidden = YES;
        if (g_hostedLQUltimateDiamonds[i])
            g_hostedLQUltimateDiamonds[i].hidden = YES;
        if (g_hostedLQUltimateLabels[i])
            g_hostedLQUltimateLabels[i].hidden = YES;
        if (g_hostedLQTalentLabels[i])
            g_hostedLQTalentLabels[i].hidden = YES;
    }
    for (int i = 0; i < kDSLQMaxMonsters; i++) {
        if (g_hostedLQMonsterViews[i])
            g_hostedLQMonsterViews[i].hidden = YES;
        if (g_hostedLQMonsterHealthLabels[i])
            g_hostedLQMonsterHealthLabels[i].hidden = YES;
        if (g_hostedLQMonsterMinimapViews[i])
            g_hostedLQMonsterMinimapViews[i].hidden = YES;
    }
}

static void ds_hosted_lq_reset_slots(BOOL clearContents) {
    ds_hosted_lq_hide_all();
    memset(g_hostedLQHeroConfigIds, 0, sizeof(g_hostedLQHeroConfigIds));
    memset(g_hostedLQHeroRequestedConfigIds, 0,
           sizeof(g_hostedLQHeroRequestedConfigIds));
    memset(g_hostedLQHeroPlayerIds, 0, sizeof(g_hostedLQHeroPlayerIds));
    memset(g_hostedLQHeroActors, 0, sizeof(g_hostedLQHeroActors));
    memset(g_hostedLQHeroLastSeen, 0, sizeof(g_hostedLQHeroLastSeen));
    memset(g_hostedLQHeroLastImageAttempt, 0,
           sizeof(g_hostedLQHeroLastImageAttempt));
    memset(g_hostedLQHeroLastPositions, 0,
           sizeof(g_hostedLQHeroLastPositions));
    memset(g_hostedLQHeroHasPosition, 0,
           sizeof(g_hostedLQHeroHasPosition));
    memset(g_hostedLQMonsterActors, 0, sizeof(g_hostedLQMonsterActors));
    memset(g_hostedLQMonsterConfigIds, 0,
           sizeof(g_hostedLQMonsterConfigIds));
    memset(g_hostedLQMonsterLastSeen, 0,
           sizeof(g_hostedLQMonsterLastSeen));
    memset(g_hostedLQMonsterLastWorldPositions, 0,
           sizeof(g_hostedLQMonsterLastWorldPositions));
    memset(g_hostedLQMonsterLastMapPositions, 0,
           sizeof(g_hostedLQMonsterLastMapPositions));
    memset(g_hostedLQMonsterHasWorldPosition, 0,
           sizeof(g_hostedLQMonsterHasWorldPosition));
    memset(g_hostedLQMonsterHasMapPosition, 0,
           sizeof(g_hostedLQMonsterHasMapPosition));
    for (int i = 0; i < kDSLQMaxEnemies; i++)
        g_hostedLQLastHealth[i] = INT32_MIN;
    for (int i = 0; i < kDSLQMaxMonsters; i++)
        g_hostedLQMonsterLastHealth[i] = INT32_MIN;
    g_hostedLQSlotEpoch = 0;
    g_hostedLQRenderSequence = 0;
    if (clearContents) {
        for (int i = 0; i < kDSLQMaxEnemies; i++) {
            if (g_hostedLQHeroViews[i]) g_hostedLQHeroViews[i].image = nil;
            if (g_hostedLQMinimapViews[i])
                g_hostedLQMinimapViews[i].image = nil;
            if (g_hostedLQStatusHeroViews[i])
                g_hostedLQStatusHeroViews[i].image = nil;
        }
    }
}

static int ds_hosted_lq_slot_for_identity(uint32_t playerId, uint64_t actor,
                                          const BOOL touched[5]) {
    if (playerId) {
        for (int i = 0; i < kDSLQMaxEnemies; i++) {
            if (!touched[i] && g_hostedLQHeroPlayerIds[i] == playerId) return i;
        }
    }
    if (actor) {
        for (int i = 0; i < kDSLQMaxEnemies; i++) {
            if (!touched[i] && g_hostedLQHeroActors[i] == actor) return i;
        }
    }
    for (int i = 0; i < kDSLQMaxEnemies; i++) {
        if (!touched[i] && g_hostedLQHeroPlayerIds[i] == 0 &&
            g_hostedLQHeroActors[i] == 0) return i;
    }
    int oldestSlot = -1;
    uint64_t oldestSeen = UINT64_MAX;
    for (int i = 0; i < kDSLQMaxEnemies; i++) {
        if (!touched[i] && g_hostedLQHeroLastSeen[i] < oldestSeen) {
            oldestSeen = g_hostedLQHeroLastSeen[i];
            oldestSlot = i;
        }
    }
    return oldestSlot;
}

static int ds_hosted_lq_monster_slot_for_actor(
    uint64_t actor, const BOOL touched[kDSLQMaxMonsters]) {
    if (!actor) return -1;
    for (int i = 0; i < kDSLQMaxMonsters; i++) {
        if (!touched[i] && g_hostedLQMonsterActors[i] == actor) return i;
    }
    for (int i = 0; i < kDSLQMaxMonsters; i++) {
        if (!touched[i] && g_hostedLQMonsterActors[i] == 0) return i;
    }
    int oldestSlot = -1;
    uint64_t oldestSeen = UINT64_MAX;
    for (int i = 0; i < kDSLQMaxMonsters; i++) {
        if (!touched[i] && g_hostedLQMonsterLastSeen[i] < oldestSeen) {
            oldestSeen = g_hostedLQMonsterLastSeen[i];
            oldestSlot = i;
        }
    }
    return oldestSlot;
}

static BOOL ds_hosted_lq_monster_buff(uint32_t configId) {
    return configId == 7010 || configId == 7011 ||
           configId == 547010 || configId == 547011;
}

static BOOL ds_hosted_lq_monster_boss(uint32_t configId) {
    return configId == 49 || configId == 7012 || configId == 70093 ||
           configId == 123 ||
           configId == 124 || configId == 70092 || configId == 7024 ||
           configId == 7009;
}

static BOOL ds_hosted_lq_monster_minimap_large(uint32_t configId) {
    return configId == 7010 || configId == 7011 || configId == 7012 ||
           configId == 70093 || configId == 70092 || configId == 7024 ||
           configId == 7009 || configId == 547010 || configId == 547011;
}

static void ds_hosted_lq_apply_cooldowns(const DSLQProjectedHero &hero,
                                         int slot, CGPoint minimapCenter,
                                         CGFloat width, CGFloat height,
                                         BOOL hidden) {
    UIImageView *statusHero = g_hostedLQStatusHeroViews[slot];
    CAShapeLayer *diamond = g_hostedLQUltimateDiamonds[slot];
    CATextLayer *ultimate = g_hostedLQUltimateLabels[slot];
    CATextLayer *talent = g_hostedLQTalentLabels[slot];
    CGFloat nativeScale = MAX(UIScreen.mainScreen.scale, 1.0);
    CGFloat baseScale = nativeScale == 2.0 && height < 500.0
        ? 12.0 : 42.0 / nativeScale;
    CGFloat iconScale = 1.5 * baseScale;
    NSInteger heroIndex = slot + 1;
    CGPoint position = CGPointMake(
        minimapCenter.x + width / 8.0 +
            (heroIndex + 5) * iconScale + round(height / 60.0) * heroIndex,
        iconScale * 0.5 + 10.0);
    if (statusHero) {
        statusHero.frame = CGRectMake(position.x - iconScale * 0.5,
                                      position.y - iconScale * 0.5,
                                      iconScale, iconScale);
        statusHero.layer.cornerRadius = iconScale * 0.5;
        statusHero.hidden = hidden;
    }
    BOOL ultimateHidden = hidden || !hero.ultimateCooldownValid;
    if (diamond) {
        CGFloat diamondSize = (iconScale / 8.0) * 1.5;
        CGPoint center = CGPointMake(
            position.x, position.y - iconScale * 0.5 - 2.0);
        diamond.frame = CGRectMake(center.x - diamondSize - 2.0,
                                   center.y - diamondSize - 2.0,
                                   (diamondSize + 2.0) * 2.0,
                                   (diamondSize + 2.0) * 2.0);
        CGMutablePathRef path = CGPathCreateMutable();
        CGFloat cx = CGRectGetMidX(diamond.bounds);
        CGFloat cy = CGRectGetMidY(diamond.bounds);
        CGPathMoveToPoint(path, NULL, cx, cy - diamondSize);
        CGPathAddLineToPoint(path, NULL, cx + diamondSize, cy);
        CGPathAddLineToPoint(path, NULL, cx, cy + diamondSize);
        CGPathAddLineToPoint(path, NULL, cx - diamondSize, cy);
        CGPathCloseSubpath(path);
        diamond.path = path;
        CGPathRelease(path);
        diamond.lineWidth = 1.5;
        diamond.strokeColor = [UIColor colorWithRed:175/255.0
                                               green:238/255.0
                                                blue:238/255.0 alpha:1.0].CGColor;
        diamond.fillColor =
            [UIColor colorWithRed:0 green:200/255.0 blue:0 alpha:1.0].CGColor;
        diamond.hidden = ultimateHidden || hero.ultimateCooldown > 0;
        if (ultimate) {
            BOOL showNumber = !ultimateHidden &&
                hero.ultimateCooldown > 0;
            ultimate.string = showNumber
                ? [NSString stringWithFormat:@"%d", hero.ultimateCooldown]
                : @"";
            ultimate.frame = CGRectMake(center.x - 18.0, center.y - 7.0,
                                        36.0, 14.0);
            ultimate.hidden = !showNumber;
        }
    }
    if (talent) {
        BOOL showTalent = !hidden && hero.talentCooldownValid &&
                          hero.talentCooldown > 0;
        talent.string = showTalent
            ? [NSString stringWithFormat:@"%d", hero.talentCooldown] : @"";
        talent.frame = CGRectMake(position.x - 15.0,
                                  position.y + iconScale + 4.75,
                                  30.0, 14.0);
        talent.hidden = !showTalent;
    }
}

// The AOV batch retains every enemy identity and marks projection rejects as
// invisible. Binding by playerId keeps a hero on the same CALayer at screen
// edges instead of compacting all following heroes into different slots.
static void ds_hosted_apply_lq(void) {
    if (!g_hostedLayer) return;
    if (!ds_hosted_esp_enabled()) {
        // The switch only gates the overlay visuals; ds_lq_tick keeps running
        // so Auto TT and the camera helpers stay live while ESP is off.
        ds_hosted_lq_hide_all();
        return;
    }
    UIInterfaceOrientation orientation = ds_active_orientation();
    if (!UIInterfaceOrientationIsLandscape(orientation)) {
        ds_hosted_lq_hide_all();
        return;
    }
    DSLQProjectedHero heroes[5] = {};
    uint64_t epoch = 0;
    int count = ds_lq_copy_projected_heroes(heroes, &epoch);
    if (count < 0) return;
    if (count > kDSLQMaxEnemies) count = kDSLQMaxEnemies;
    if (epoch && epoch != g_hostedLQSlotEpoch) {
        ds_hosted_lq_reset_slots(YES);
        g_hostedLQSlotEpoch = epoch;
    }

    BOOL touched[5] = {};
    const CGFloat width = CGRectGetWidth(g_hostedLayer.bounds);
    const CGFloat height = CGRectGetHeight(g_hostedLayer.bounds);
    CGFloat notchHeight = g_hostedPortraitNotchHeight;
    if (notchHeight <= 0.0) {
        UIView *hostedRootView = g_hostedWindow.rootViewController.view;
        notchHeight = CGRectGetMinY(
            hostedRootView.safeAreaLayoutGuide.layoutFrame);
    }
    CGFloat landscapeLeftInset = notchHeight > 30.0 ? 41.0 : 0.0;
    CGFloat runtimeMinimapInset = notchHeight > 30.0 ? notchHeight : 0.0;
    DSHostedLQMinimapLayout minimapLayout = {};
    for (int i = 0; i < count && !minimapLayout.valid; i++) {
        const DSLQProjectedHero &sample = heroes[i];
        minimapLayout = ds_hosted_lq_minimap_layout(
            sample.minimapScreenWidthPx, sample.minimapScreenHeightPx,
            sample.minimapFormCameraViewport, sample.minimapWidthPx,
            sample.minimapHeightPx, sample.minimapCenterXPx,
            sample.minimapCenterYPx, sample.minimapAnchorYPx,
            sample.minimapStorePosMode, sample.minimapRoomType,
            width, height, runtimeMinimapInset);
    }
    ++g_hostedLQRenderSequence;
    for (int i = 0; i < count; i++) {
        const DSLQProjectedHero &hero = heroes[i];
        int slot = ds_hosted_lq_slot_for_identity(hero.playerId, hero.actor,
                                                   touched);
        if (slot < 0) continue;
        touched[slot] = YES;
        bool identityChanged =
            g_hostedLQHeroPlayerIds[slot] != hero.playerId ||
            g_hostedLQHeroActors[slot] != hero.actor;
        g_hostedLQHeroPlayerIds[slot] = hero.playerId;
        g_hostedLQHeroActors[slot] = hero.actor;
        g_hostedLQHeroLastSeen[slot] = g_hostedLQRenderSequence;
        if (identityChanged) g_hostedLQHeroHasPosition[slot] = NO;

        UIImageView *view = g_hostedLQHeroViews[slot];
        UIImageView *minimapView = g_hostedLQMinimapViews[slot];
        UIImageView *statusView = g_hostedLQStatusHeroViews[slot];
        if (!view) continue;
        if (g_hostedLQHeroRequestedConfigIds[slot] != hero.configId) {
            g_hostedLQHeroRequestedConfigIds[slot] = hero.configId;
            g_hostedLQHeroConfigIds[slot] = 0;
            g_hostedLQHeroLastImageAttempt[slot] = 0;
            view.image = nil;
            if (minimapView) minimapView.image = nil;
            if (statusView) statusView.image = nil;
        }
        // Image decode/prewarm is metadata work. Retry a missing cache entry
        // at a bounded cadence instead of taking the cache lock every display
        // callback while still allowing an asynchronous prewarm to complete.
        bool imageMissing = hero.configId != 0 &&
            (g_hostedLQHeroConfigIds[slot] != hero.configId ||
             view.image == nil);
        if (imageMissing &&
            (g_hostedLQHeroLastImageAttempt[slot] == 0 ||
             g_hostedLQRenderSequence -
                 g_hostedLQHeroLastImageAttempt[slot] >= 4)) {
            UIImage *image = ds_lq_hero_image(hero.configId);
            g_hostedLQHeroLastImageAttempt[slot] = g_hostedLQRenderSequence;
            if (image) {
                view.image = image;
                if (minimapView) minimapView.image = image;
                if (statusView) statusView.image = image;
                g_hostedLQHeroConfigIds[slot] = hero.configId;
            }
        }
        BOOL hidden = !hero.visible || view.image == nil;
        CGPoint heroPosition = g_hostedLQHeroLastPositions[slot];
        if (!hidden) {
            CGPoint position = CGPointMake(hero.u * width, hero.v * height);
            heroPosition = position;
            const CGFloat iconSize = kDSLQHeroIconSize;
            if (!g_hostedLQHeroHasPosition[slot] ||
                !CGPointEqualToPoint(g_hostedLQHeroLastPositions[slot],
                                     position)) {
                view.frame = CGRectMake(position.x - iconSize * 0.5,
                                        position.y - iconSize * 0.5,
                                        iconSize, iconSize);
                g_hostedLQHeroLastPositions[slot] = position;
                g_hostedLQHeroHasPosition[slot] = YES;
            }
            CATextLayer *healthLabel = g_hostedLQHealthLabels[slot];
            if (hero.hpSampleValid && healthLabel) {
                if (g_hostedLQLastHealth[slot] != hero.hp) {
                    healthLabel.string = [NSString stringWithFormat:@"%d",
                                                                  hero.hp];
                    g_hostedLQLastHealth[slot] = hero.hp;
                }
                healthLabel.frame = CGRectMake(
                    position.x - 36.0, position.y - iconSize * 0.5 - 20.0,
                    72.0, 18.0);
                healthLabel.hidden = NO;
            } else {
                if (healthLabel) healthLabel.hidden = YES;
            }
        } else {
            if (g_hostedLQHealthLabels[slot])
                g_hostedLQHealthLabels[slot].hidden = YES;
        }
        if (view.hidden != hidden) view.hidden = hidden;
        ds_hosted_lq_apply_cooldowns(
            hero, slot,
            CGPointMake(landscapeLeftInset,
                        minimapLayout.valid ? minimapLayout.baseCenter.y : 1.0),
            width, height, statusView == nil || statusView.image == nil);
        CGFloat minimapX = minimapLayout.markerCenter.x +
                           hero.minimapX * minimapLayout.scaleX;
        CGFloat minimapY = minimapLayout.markerCenter.y +
                           hero.minimapY * minimapLayout.scaleY;
        BOOL minimapHidden = !minimapLayout.valid || !hero.minimapValid ||
                             !minimapView ||
                             minimapView.image == nil ||
                             minimapX < 0.0 || minimapX > width ||
                             minimapY < 0.0 || minimapY > height;
        if (!minimapHidden) {
            CGFloat minimapIconSize =
                ds_hosted_lq_minimap_icon_size(height);
            minimapView.frame = CGRectMake(
                minimapX - minimapIconSize * 0.5,
                minimapY - minimapIconSize * 0.5,
                minimapIconSize, minimapIconSize);
            minimapView.layer.cornerRadius = minimapIconSize * 0.5;
        }
        if (minimapView && minimapView.hidden != minimapHidden)
            minimapView.hidden = minimapHidden;
    }
    for (int i = 0; i < kDSLQMaxEnemies; i++) {
        if (!touched[i] && g_hostedLQHeroViews[i] &&
            !g_hostedLQHeroViews[i].hidden) {
            g_hostedLQHeroViews[i].hidden = YES;
        }
        if (!touched[i] && g_hostedLQHealthLabels[i])
            g_hostedLQHealthLabels[i].hidden = YES;
        if (!touched[i] && g_hostedLQMinimapViews[i])
            g_hostedLQMinimapViews[i].hidden = YES;
        if (!touched[i] && g_hostedLQStatusHeroViews[i])
            g_hostedLQStatusHeroViews[i].hidden = YES;
        if (!touched[i] && g_hostedLQUltimateDiamonds[i])
            g_hostedLQUltimateDiamonds[i].hidden = YES;
        if (!touched[i] && g_hostedLQUltimateLabels[i])
            g_hostedLQUltimateLabels[i].hidden = YES;
        if (!touched[i] && g_hostedLQTalentLabels[i])
            g_hostedLQTalentLabels[i].hidden = YES;
    }

    DSLQProjectedMonster monsters[kDSLQMaxMonsters] = {};
    uint64_t monsterEpoch = 0;
    int monsterCount = ds_lq_copy_projected_monsters(monsters, &monsterEpoch);
    if (monsterCount >= 0) {
        monsterCount = MIN(monsterCount, kDSLQMaxMonsters);
        BOOL monsterTouched[kDSLQMaxMonsters] = {};
        for (int i = 0; i < monsterCount; i++) {
            const DSLQProjectedMonster *monster = &monsters[i];
            int slot = ds_hosted_lq_monster_slot_for_actor(
                monster->actor, monsterTouched);
            if (slot < 0) continue;
            monsterTouched[slot] = YES;
            BOOL identityChanged =
                g_hostedLQMonsterActors[slot] != monster->actor;
            BOOL configChanged =
                g_hostedLQMonsterConfigIds[slot] != monster->configId;
            if (identityChanged) {
                g_hostedLQMonsterHasWorldPosition[slot] = NO;
                g_hostedLQMonsterHasMapPosition[slot] = NO;
                g_hostedLQMonsterLastHealth[slot] = INT32_MIN;
            }
            g_hostedLQMonsterActors[slot] = monster->actor;
            g_hostedLQMonsterConfigIds[slot] = monster->configId;
            g_hostedLQMonsterLastSeen[slot] = g_hostedLQRenderSequence;

            CALayer *worldDot = g_hostedLQMonsterViews[slot];
            CATextLayer *worldHp = g_hostedLQMonsterHealthLabels[slot];
            CALayer *mapDot = g_hostedLQMonsterMinimapViews[slot];
            BOOL worldHidden = !monster || !monster->visible ||
                monster->u < 0.0f || monster->u > 1.0f ||
                monster->v < 0.0f || monster->v > 1.0f;
            if (worldDot) {
                if (!worldHidden) {
                    CGPoint point = CGPointMake(monster->u * width,
                                                monster->v * height);
                    CGFloat radius = ds_hosted_lq_monster_boss(monster->configId)
                        ? height / 100.0
                        : (ds_hosted_lq_monster_buff(monster->configId)
                           ? height / 150.0 : height / 200.0);
                    if (!g_hostedLQMonsterHasWorldPosition[slot] ||
                        configChanged ||
                        !CGPointEqualToPoint(
                            g_hostedLQMonsterLastWorldPositions[slot], point)) {
                        worldDot.frame = CGRectMake(
                            point.x - radius, point.y - radius,
                            radius * 2.0, radius * 2.0);
                        worldDot.cornerRadius = radius;
                        if (worldHp) {
                            worldHp.frame = CGRectMake(
                                point.x - 70.0, point.y - radius - 20.0,
                                140.0, 18.0);
                            worldHp.fontSize = ds_hosted_lq_monster_boss(
                                monster->configId) ? 15.0 : 12.0;
                            worldHp.foregroundColor =
                                (ds_hosted_lq_monster_buff(monster->configId)
                                     ? UIColor.whiteColor
                                     : UIColor.redColor).CGColor;
                        }
                        g_hostedLQMonsterLastWorldPositions[slot] = point;
                        g_hostedLQMonsterHasWorldPosition[slot] = YES;
                    }
                    if (worldHp) {
                        if (monster->hpSampleValid &&
                            g_hostedLQMonsterLastHealth[slot] != monster->hp) {
                            worldHp.string = [NSString stringWithFormat:@"%d",
                                                                   monster->hp];
                            g_hostedLQMonsterLastHealth[slot] = monster->hp;
                        }
                        BOOL hpHidden = !monster->hpSampleValid;
                        if (worldHp.hidden != hpHidden)
                            worldHp.hidden = hpHidden;
                    }
                } else if (worldHp) {
                    if (!worldHp.hidden) worldHp.hidden = YES;
                }
                if (worldDot.hidden != worldHidden)
                    worldDot.hidden = worldHidden;
            }

            CGFloat mapX = -1.0;
            CGFloat mapY = -1.0;
            if (monster && monster->minimapValid && minimapLayout.valid) {
                mapX = minimapLayout.markerCenter.x +
                       monster->minimapX * minimapLayout.scaleX;
                mapY = minimapLayout.markerCenter.y +
                       monster->minimapY * minimapLayout.scaleY;
            }
            BOOL mapHidden = !minimapLayout.valid || !monster ||
                !monster->minimapValid ||
                mapX < 0.0 || mapX > width || mapY < 0.0 || mapY > height;
            if (mapDot) {
                if (!mapHidden) {
                    CGFloat radius = ds_hosted_lq_monster_minimap_large(
                        monster->configId) ? height / 150.0
                                           : height / 300.0;
                    CGPoint point = CGPointMake(mapX, mapY);
                    if (!g_hostedLQMonsterHasMapPosition[slot] ||
                        configChanged ||
                        !CGPointEqualToPoint(
                            g_hostedLQMonsterLastMapPositions[slot], point)) {
                        mapDot.frame = CGRectMake(
                            mapX - radius, mapY - radius,
                            radius * 2.0, radius * 2.0);
                        mapDot.cornerRadius = radius;
                        g_hostedLQMonsterLastMapPositions[slot] = point;
                        g_hostedLQMonsterHasMapPosition[slot] = YES;
                    }
                }
                if (mapDot.hidden != mapHidden) mapDot.hidden = mapHidden;
            }
        }
        for (int slot = 0; slot < kDSLQMaxMonsters; slot++) {
            if (monsterTouched[slot]) continue;
            if (g_hostedLQMonsterViews[slot] &&
                !g_hostedLQMonsterViews[slot].hidden)
                g_hostedLQMonsterViews[slot].hidden = YES;
            if (g_hostedLQMonsterHealthLabels[slot] &&
                !g_hostedLQMonsterHealthLabels[slot].hidden)
                g_hostedLQMonsterHealthLabels[slot].hidden = YES;
            if (g_hostedLQMonsterMinimapViews[slot] &&
                !g_hostedLQMonsterMinimapViews[slot].hidden)
                g_hostedLQMonsterMinimapViews[slot].hidden = YES;
        }
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
    if (g_hostedPUBGTopCountBgLayer && !g_hostedPUBGTopCountBgLayer.hidden) g_hostedPUBGTopCountBgLayer.hidden = YES;
    if (g_hostedPUBGTopCountLabel && !g_hostedPUBGTopCountLabel.hidden) g_hostedPUBGTopCountLabel.hidden = YES;
}

static void ds_hosted_apply_pubg(void) {
    if (!g_hostedLayer) return;
    if (!ds_hosted_esp_enabled()) {
        ds_hosted_pubg_hide_all();
        return;
    }
    UIInterfaceOrientation orientation = ds_active_orientation();
    if (!UIInterfaceOrientationIsLandscape(orientation)) {
        ds_hosted_pubg_hide_all();
        return;
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
    static NSMutableParagraphStyle *s_centerStyle = nil;
    static dispatch_once_t s_pubgFontOnce;
    dispatch_once(&s_pubgFontOnce, ^{
        s_infoFont = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
        s_wFont = [UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
        s_itemTitleFont = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
        s_itemSubFont = [UIFont systemFontOfSize:7.5 weight:UIFontWeightBold];
        s_itemFont = [UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
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
            case DSPUBGItemCategoryWeapon:  show = g_pubgEspWeapon; break;
            case DSPUBGItemCategoryScope:   show = g_pubgEspScope; break;
            case DSPUBGItemCategoryArmor:   show = g_pubgEspArmor; break;
            case DSPUBGItemCategoryBag:     show = g_pubgEspBag; break;
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
        if (!nameStr) {
            nameStr = [NSString stringWithCString:it.name encoding:NSUTF8StringEncoding];
        }
        if (!nameStr) {
            nameStr = [NSString stringWithCString:it.name encoding:NSISOLatin1StringEncoding];
        }
        if (!nameStr || nameStr.length == 0) {
            nameStr = @"Vật Phẩm";
        }

        if (it.category == DSPUBGItemCategoryVehicle) {
            lbl.backgroundColor = UIColor.clearColor.CGColor;
            lbl.shadowOpacity = 0.0f;
            lbl.cornerRadius = 0.0f;
            lbl.wrapped = YES;

            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];

            NSString *titleStr = [NSString stringWithFormat:@"%@ [%.0fm]", nameStr, it.distanceMeters];
            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:titleStr
                attributes:@{
                    NSForegroundColorAttributeName: [UIColor whiteColor],
                    NSFontAttributeName: s_itemTitleFont,
                    NSStrokeColorAttributeName: [UIColor blackColor],
                    NSStrokeWidthAttributeName: @(-2.0),
                    NSParagraphStyleAttributeName: s_centerStyle
                }]];

            NSMutableArray<NSAttributedString *> *parts = [NSMutableArray array];
            if (g_pubgEspVehicleHp && it.hpMax > 0.0f) {
                float hpPct = (it.hp / it.hpMax) * 100.0f;
                if (hpPct < 0.0f) hpPct = 0.0f;
                if (hpPct > 100.0f) hpPct = 100.0f;
                NSString *hpStr = [NSString stringWithFormat:@"Máu: %.0f%%", hpPct];
                [parts addObject:[[NSAttributedString alloc] initWithString:hpStr
                    attributes:@{
                        NSForegroundColorAttributeName: [UIColor colorWithRed:50/255.0 green:220/255.0 blue:50/255.0 alpha:1.0],
                        NSFontAttributeName: s_itemSubFont,
                        NSStrokeColorAttributeName: [UIColor blackColor],
                        NSStrokeWidthAttributeName: @(-2.0)
                    }]];
            }

            if (g_pubgEspVehicleFuel && it.fuelMax > 0.0f) {
                float fuelPct = (it.fuel / it.fuelMax) * 100.0f;
                if (fuelPct < 0.0f) fuelPct = 0.0f;
                if (fuelPct > 100.0f) fuelPct = 100.0f;
                NSString *fuelStr = [NSString stringWithFormat:@"Xăng: %.0f%%", fuelPct];
                [parts addObject:[[NSAttributedString alloc] initWithString:fuelStr
                    attributes:@{
                        NSForegroundColorAttributeName: [UIColor colorWithRed:255/255.0 green:215/255.0 blue:0/255.0 alpha:1.0],
                        NSFontAttributeName: s_itemSubFont,
                        NSStrokeColorAttributeName: [UIColor blackColor],
                        NSStrokeWidthAttributeName: @(-2.0)
                    }]];
            }

            if (parts.count > 0) {
                [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                    attributes:@{NSFontAttributeName: s_itemTitleFont, NSParagraphStyleAttributeName: s_centerStyle}]];
                for (NSUInteger pi = 0; pi < parts.count; pi++) {
                    if (pi > 0) {
                        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "
                            attributes:@{NSFontAttributeName: s_itemSubFont}]];
                    }
                    [attr appendAttributedString:parts[pi]];
                }
            }

            CGFloat strW = (parts.count > 0) ? 140.0f : 120.0f;
            CGFloat strH = (parts.count > 0) ? 24.0f : 14.0f;
            lbl.frame = CGRectMake(it.screenX - strW * 0.5f, it.screenY - strH * 0.5f, strW, strH);
            lbl.string = attr;
            lbl.hidden = NO;
        } else {
            UIColor *color = [UIColor colorWithRed:255/255.0 green:215/255.0 blue:0/255.0 alpha:0.95]; // Gold default
            if (it.category == DSPUBGItemCategoryScope) {
                color = [UIColor colorWithRed:190/255.0 green:110/255.0 blue:255/255.0 alpha:0.95]; // Purple
            } else if (it.category == DSPUBGItemCategoryArmor) {
                color = [UIColor colorWithRed:0/255.0 green:229/255.0 blue:255/255.0 alpha:0.95]; // Cyan
            } else if (it.category == DSPUBGItemCategoryBag) {
                color = [UIColor colorWithRed:38/255.0 green:222/255.0 blue:129/255.0 alpha:0.95]; // Mint
            } else if (it.category == DSPUBGItemCategoryCrate) {
                color = [UIColor colorWithRed:255/255.0 green:75/255.0 blue:75/255.0 alpha:0.95]; // Red
            }

            NSString *str = [NSString stringWithFormat:@"%@ [%.0fm]", nameStr, it.distanceMeters];
            CGFloat strW = 100.0f;
            CGFloat strH = 14.0f;
            lbl.frame = CGRectMake(it.screenX - strW * 0.5f, it.screenY - strH * 0.5f, strW, strH);
            lbl.fontSize = 8.5f;
            lbl.font = (__bridge CFTypeRef)s_itemFont;
            lbl.foregroundColor = color.CGColor;
            lbl.backgroundColor = UIColor.clearColor.CGColor;
            lbl.shadowOpacity = 0.0f;
            lbl.cornerRadius = 0.0f;
            lbl.wrapped = NO;
            lbl.string = str;
            lbl.hidden = NO;
        }
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
    ds_hosted_apply_orientation(ds_active_orientation());
    if (ds_active_game() == 1) {
        ds_hosted_lq_hide_all();
        ds_hosted_apply_pubg();
    } else {
        ds_hosted_pubg_hide_all();
        ds_hosted_apply_lq();
    }
    [CATransaction commit];
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

    // AOV-only pool: five persistent hero icons and live-HP text layers.
    {
        NSDictionary *noAnim = @{@"position": [NSNull null], @"hidden": [NSNull null],
                                 @"string": [NSNull null], @"bounds": [NSNull null],
                                 @"frame": [NSNull null], @"backgroundColor": [NSNull null]};
        CGFloat scale = UIScreen.mainScreen.scale;
        CGFloat minimapIconSize = ds_hosted_lq_minimap_icon_size(
            MIN(CGRectGetWidth(content), CGRectGetHeight(content)));
        for (int i = 0; i < kDSLQMaxEnemies; i++) {
            UIImageView *minimapHero = [[UIImageView alloc]
                initWithFrame:CGRectMake(0, 0, minimapIconSize,
                                         minimapIconSize)];
            minimapHero.contentMode = UIViewContentModeScaleAspectFill;
            minimapHero.clipsToBounds = YES;
            minimapHero.layer.cornerRadius = minimapIconSize * 0.5;
            minimapHero.layer.masksToBounds = YES;
            minimapHero.layer.borderWidth = 1.0;
            minimapHero.layer.borderColor = UIColor.redColor.CGColor;
            minimapHero.layer.contentsScale = scale;
            minimapHero.hidden = YES;
            minimapHero.userInteractionEnabled = NO;
            minimapHero.layer.actions = noAnim;
            [g_hostedESPView addSubview:minimapHero];
            g_hostedLQMinimapViews[i] = minimapHero;

            CATextLayer *healthLabel = [CATextLayer layer];
            healthLabel.actions = noAnim;
            healthLabel.contentsScale = scale;
            healthLabel.alignmentMode = kCAAlignmentCenter;
            healthLabel.fontSize = 15.0;
            healthLabel.font = (__bridge CFTypeRef)
                [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
            healthLabel.foregroundColor = UIColor.redColor.CGColor;
            healthLabel.hidden = YES;
            [g_hostedLayer addSublayer:healthLabel];
            g_hostedLQHealthLabels[i] = healthLabel;

            UIImageView *hero = [[UIImageView alloc]
                initWithFrame:CGRectMake(0, 0, kDSLQHeroIconSize,
                                         kDSLQHeroIconSize)];
            hero.contentMode = UIViewContentModeScaleAspectFill;
            hero.clipsToBounds = YES;
            hero.layer.cornerRadius = kDSLQHeroIconSize * 0.5;
            hero.layer.masksToBounds = YES;
            hero.layer.borderWidth = 1.0;
            hero.layer.borderColor =
                [UIColor colorWithRed:1.0 green:0.10 blue:0.12 alpha:1.0].CGColor;
            hero.layer.contentsScale = scale;
            hero.hidden = YES;
            hero.userInteractionEnabled = NO;
            hero.layer.actions = noAnim;
            [g_hostedESPView addSubview:hero];
            g_hostedLQHeroViews[i] = hero;

            UIImageView *statusHero = [[UIImageView alloc]
                initWithFrame:CGRectZero];
            statusHero.contentMode = UIViewContentModeScaleAspectFill;
            statusHero.clipsToBounds = YES;
            statusHero.layer.masksToBounds = YES;
            statusHero.layer.borderWidth = 1.0;
            statusHero.layer.borderColor =
                [UIColor colorWithRed:139/255.0 green:0 blue:0 alpha:1.0].CGColor;
            statusHero.layer.contentsScale = scale;
            statusHero.hidden = YES;
            statusHero.userInteractionEnabled = NO;
            statusHero.layer.actions = noAnim;
            [g_hostedESPView addSubview:statusHero];
            g_hostedLQStatusHeroViews[i] = statusHero;

            CAShapeLayer *ultimateDiamond = [CAShapeLayer layer];
            ultimateDiamond.actions = noAnim;
            ultimateDiamond.contentsScale = scale;
            ultimateDiamond.hidden = YES;
            [g_hostedLayer addSublayer:ultimateDiamond];
            g_hostedLQUltimateDiamonds[i] = ultimateDiamond;

            CATextLayer *ultimateLabel = [CATextLayer layer];
            ultimateLabel.actions = noAnim;
            ultimateLabel.contentsScale = scale;
            ultimateLabel.alignmentMode = kCAAlignmentCenter;
            ultimateLabel.fontSize = 9.0;
            ultimateLabel.font = (__bridge CFTypeRef)
                [UIFont systemFontOfSize:9.0 weight:UIFontWeightBold];
            ultimateLabel.foregroundColor =
                [UIColor colorWithRed:0 green:200/255.0 blue:0 alpha:1.0].CGColor;
            ultimateLabel.hidden = YES;
            [g_hostedLayer addSublayer:ultimateLabel];
            g_hostedLQUltimateLabels[i] = ultimateLabel;

            CATextLayer *talentLabel = [CATextLayer layer];
            talentLabel.actions = noAnim;
            talentLabel.contentsScale = scale;
            talentLabel.alignmentMode = kCAAlignmentCenter;
            talentLabel.fontSize = 10.0;
            talentLabel.font = (__bridge CFTypeRef)
                [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
            talentLabel.foregroundColor = UIColor.whiteColor.CGColor;
            talentLabel.backgroundColor =
                [UIColor colorWithWhite:0 alpha:0.72].CGColor;
            talentLabel.cornerRadius = 7.0;
            talentLabel.hidden = YES;
            [g_hostedLayer addSublayer:talentLabel];
            g_hostedLQTalentLabels[i] = talentLabel;
        }

        for (int i = 0; i < kDSLQMaxMonsters; i++) {
            CALayer *worldDot = [CALayer layer];
            worldDot.actions = noAnim;
            worldDot.contentsScale = scale;
            worldDot.backgroundColor = UIColor.redColor.CGColor;
            worldDot.hidden = YES;
            [g_hostedLayer addSublayer:worldDot];
            g_hostedLQMonsterViews[i] = worldDot;

            CATextLayer *worldHp = [CATextLayer layer];
            worldHp.actions = noAnim;
            worldHp.contentsScale = scale;
            worldHp.alignmentMode = kCAAlignmentCenter;
            worldHp.fontSize = 12.0;
            worldHp.font = (__bridge CFTypeRef)
                [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
            worldHp.foregroundColor = UIColor.redColor.CGColor;
            worldHp.hidden = YES;
            [g_hostedLayer addSublayer:worldHp];
            g_hostedLQMonsterHealthLabels[i] = worldHp;

            CALayer *mapDot = [CALayer layer];
            mapDot.actions = noAnim;
            mapDot.contentsScale = scale;
            mapDot.backgroundColor = UIColor.redColor.CGColor;
            mapDot.hidden = YES;
            [g_hostedLayer addSublayer:mapDot];
            g_hostedLQMonsterMinimapViews[i] = mapDot;
        }

        ds_hosted_lq_reset_slots(YES);

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
                itemLbl.shadowColor = UIColor.blackColor.CGColor;
                itemLbl.shadowRadius = 0.0;
                itemLbl.shadowOpacity = 0.0;
                itemLbl.shadowOffset = CGSizeZero;
                itemLbl.hidden = YES;
                [g_hostedLayer addSublayer:itemLbl];
                g_hostedPUBGItemLabels[i] = itemLbl;
            }

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

    // FBSOrientationObserver follows the actual foreground application. While
    // Home is portrait, stop touching the suspended game's mapped pages; the
    // same reader state resumes when its landscape scene becomes active again.
    UIInterfaceOrientation activeOrientation = ds_active_orientation();
    if (UIInterfaceOrientationIsPortrait(activeOrientation)) {
        ds_hosted_publish_render_snapshot(snapshot);
        return;
    }

    if (ds_active_game() == 1) {
        ds_pubg_tick();
        snapshot.lqRenderSourceReady = ds_pubg_has_render_source();
    } else {
        ds_lq_tick();
        snapshot.lqRenderSourceReady = ds_lq_has_render_source();
    }

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
    [NSUserDefaults.standardUserDefaults setInteger:1 forKey:kDSActiveGameKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    if (ds_active_game() == 1) {
        ds_pubg_overlay_reset();
    } else {
        ds_lq_overlay_reset();
        ds_lq_prewarm_all_hero_images();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        unsigned contextId = ds_hosted_overlay_setup_on_main();
        unsigned menuContextId = ds_hosted_menu_setup_on_main();
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
                // Returning here starved ds_lq_tick() after the first frame:
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
    ds_lq_overlay_reset();
    ds_pubg_overlay_reset();
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_hostedDisplayLink invalidate];
        g_hostedDisplayLink = nil;
        g_hostedDisplayLinkDriver = nil;
        ds_hosted_menu_set_expanded(NO);
        g_hostedMenuWindow.hidden = YES;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        ds_hosted_lq_reset_slots(YES);
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
    ds_lq_overlay_reset();
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
        ds_hosted_lq_reset_slots(YES);
        for (int index = 0; index < kDSLQMaxEnemies; index++) {
            g_hostedLQHeroViews[index] = nil;
            g_hostedLQMinimapViews[index] = nil;
            g_hostedLQStatusHeroViews[index] = nil;
            g_hostedLQHealthLabels[index] = nil;
            g_hostedLQUltimateDiamonds[index] = nil;
            g_hostedLQUltimateLabels[index] = nil;
            g_hostedLQTalentLabels[index] = nil;
        }
        for (int index = 0; index < kDSLQMaxMonsters; index++) {
            g_hostedLQMonsterViews[index] = nil;
            g_hostedLQMonsterHealthLabels[index] = nil;
            g_hostedLQMonsterMinimapViews[index] = nil;
        }
        g_hostedContentBounds = CGRectNull;
    });
}
