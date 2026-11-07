//
//  DSBridgePUBG.inc.mm
//  DarkPubg
//
//  PUBG Mobile (ShadowTrackerExtra) Unreal Engine 4 memory reader + ESP projector.
//  Included by DSBridge.mm.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/loader.h>
#include <cmath>
#include <vector>
#include <algorithm>
#include <atomic>
#include <os/lock.h>

// UEPointers from DUMP/Offsets.hpp & DUMP/Logs.txt (ShadowTrackerExtra UE4)
// Base address is Mach-O 64-bit main image (__TEXT)
// Primary default GEngine RVA (v3.4 Global)
static const uint64_t kDSPUBGEngineRvaDefault = 0x0A8AA8A0ULL;

// Class Member Offsets from DUMP/SDK/Engine.hpp & DUMP/SDK.txt
static const uint64_t kDSPUBGEngineGameViewportOffset        = 0x810ULL;  // UEngine.GameViewport (UGameViewportClient*)
static const uint64_t kDSPUBGEngineGameInstanceOffset        = 0xE20ULL;  // UGameEngine.GameInstance (UGameInstance*)
static const uint64_t kDSPUBGViewportWorldOffset             = 0x78ULL;   // UGameViewportClient.World (UWorld*)
static const uint64_t kDSPUBGWorldPersistentLevelOffset       = 0x30ULL;   // UWorld.PersistentLevel (ULevel*)
static const uint64_t kDSPUBGWorldOwningGameInstanceOffset   = 0x470ULL;  // UWorld.OwningGameInstance (UGameInstance*)
static const uint64_t kDSPUBGWorldGameStateOffset            = 0x428ULL;  // UWorld.GameState (AGameStateBase*)
static const uint64_t kDSPUBGWorldAuthorityGameModeOffset    = 0x420ULL;  // UWorld.AuthorityGameMode (AGameModeBase*)
static const uint64_t kDSPUBGGameModeGameStateOffset         = 0x508ULL;  // AGameModeBase.GameState (AGameStateBase*)

// Fast player list via GameState.PlayerArray
static const uint64_t kDSPUBGGameStatePlayerArrayOffset      = 0x4C8ULL;  // AGameStateBase.PlayerArray (TArray<APlayerState*>)
static const uint64_t kDSPUBGPlayerStatePawnPrivateOffset    = 0x528ULL;  // APlayerState.PawnPrivate (APawn*)
static const uint64_t kDSPUBGPlayerStateIsABotOffset         = 0x4DCULL;  // byte bitfield: bit 2 is bIsABot
static const uint64_t kDSPUBGPlayerStatePlayerNameOffset     = 0x4B8ULL;  // APlayerState.PlayerName (FString)

// LocalPlayer & Camera Chain
static const uint64_t kDSPUBGGameInstanceLocalPlayersOffset  = 0x48ULL;   // UGameInstance.LocalPlayers (TArray<ULocalPlayer*>)
static const uint64_t kDSPUBGLocalPlayerControllerOffset     = 0x30ULL;   // UPlayer.PlayerController (APlayerController*)
static const uint64_t kDSPUBGPlayerControllerPawnOffset      = 0x528ULL;  // APlayerController.AcknowledgedPawn (APawn*)
static const uint64_t kDSPUBGPlayerControllerCameraMgrOffset = 0x548ULL;  // APlayerController.PlayerCameraManager (APlayerCameraManager*)

// Camera ViewTarget POV (PlayerCameraManager.ViewTarget at 0x10A0, POV at +0x10)
static const uint64_t kDSPUBGCameraViewTargetOffset          = 0x10A0ULL; // FTViewTarget
static const uint64_t kDSPUBGViewTargetPOVOffset             = 0x10ULL;   // FMinimalViewInfo
static const uint64_t kDSPUBGPOVLocationOffset               = 0x0ULL;    // FVector (float X, Y, Z)
static const uint64_t kDSPUBGPOVRotationOffset               = 0x18ULL;   // FRotator (float Pitch, Yaw, Roll)
static const uint64_t kDSPUBGPOVFOVOffset                    = 0x24ULL;   // float FOV
static const uint64_t kDSPUBGPOVAspectOffset                 = 0x34ULL;   // float Aspect

// Actor & Component Offsets
static const uint64_t kDSPUBGActorRootComponentOffset        = 0x208ULL;  // AActor.RootComponent (USceneComponent*)
static const uint64_t kDSPUBGSceneCompRelativeLocOffset      = 0x1E4ULL;  // USceneComponent.RelativeLocation (FVector)
static const uint64_t kDSPUBGSceneCompAttachedParentOffset   = 0x188ULL;  // USceneComponent.AttachedParent (USceneComponent*)
static const uint64_t kDSPUBGCharacterMeshOffset             = 0x510ULL;  // ASTExtraBaseCharacter.Mesh (USkeletalMeshComponent*)
static const uint64_t kDSPUBGCharacterMovementOffset         = 0x518ULL;  // ACharacter.CharacterMovement (UCharacterMovementComponent*)
static const uint64_t kDSPUBGCharacterCapsuleOffset          = 0x520ULL;  // ACharacter.CapsuleComponent (UCapsuleComponent*)
static const uint64_t kDSPUBGMeshBoxExtentZOffset            = 0xBA0ULL;  // Mesh.Bounds.BoxExtent.Z
static const uint64_t kDSPUBGCharacterPlayerNameOffset       = 0x960ULL;  // UAECharacter.PlayerName (FString)
static const uint64_t kDSPUBGCharacterPlayerKeyOffset        = 0x980ULL;  // UAECharacter.PlayerKey (uint32_t)
static const uint64_t kDSPUBGCharacterTeamIDOffset           = 0x998ULL;  // UAECharacter.TeamID (int32_t)
static const uint64_t kDSPUBGCharacterIsAIOffset             = 0xA40ULL;  // UAECharacter.bIsAI (bool)
static const uint64_t kDSPUBGCharacterHealthOffset           = 0xE60ULL;  // STExtraCharacter.Health (float)
static const uint64_t kDSPUBGCharacterHealthMaxOffset        = 0xE64ULL;  // STExtraCharacter.HealthMax (float)
static const uint64_t kDSPUBGCharacterDeadOffset             = 0xE7CULL;  // STExtraCharacter.bDead (uint8_t)
static const uint64_t kDSPUBGCharacterVehicleOffset          = 0xEB0ULL;  // ASTExtraCharacter.CurrentVehicle (ASTExtraVehicleBase*)

// Runtime target state
static uint64_t g_dspubgProc = 0;
static uint32_t g_dspubgPid = 0;
static uint64_t g_dspubgVmMap = 0;
static uint64_t g_dspubgBase = 0;
static uint64_t g_dspubgEngineRva = 0;
static uint64_t g_dspubgWorldRva = 0;
static uint64_t g_dspubgCachedWorld = 0;
static uint64_t g_dspubgEngineViewportOffset = kDSPUBGEngineGameViewportOffset;
static CFAbsoluteTime g_dspubgNextAttach = 0;
static CFAbsoluteTime g_dspubgNextScan = 0;
static std::atomic<bool> g_dspubgTargetActive(false);

// Live diagnostic statistics
static int g_dspubgLastActorsCount = 0;
static int g_dspubgLastEnemyCount = 0;
static int g_dspubgLastBotCount = 0;
static int g_dspubgLastVehicleCount = 0;
static char g_dspubgStatusBuf[128] = "PUBG: Waiting for game process...";

// Snapshot storage
static os_unfair_lock g_dspubgSnapshotLock = OS_UNFAIR_LOCK_INIT;
static DSPUBGProjectedPlayer g_dspubgPlayers[kDSPUBGMaxPlayers] = {};
static int g_dspubgPlayerCount = 0;
static uint64_t g_dspubgEpoch = 1;

// Vector and Rotator types for projection
struct DSPUBGVector {
    float X, Y, Z;
};

struct DSPUBGRotator {
    float Pitch, Yaw, Roll;
};

struct DSPUBGCamBasis {
    float m00, m01, m02;
    float m10, m11, m12;
    float m20, m21, m22;
    float lx, ly, lz;
    float k;
    float cx, cy;
};

static inline bool ds_pubg_valid(uint64_t address) {
    uint64_t clean = address & 0x0000FFFFFFFFFFFFULL;
    return clean >= 0x100000000ULL && clean < 0x300000000000ULL;
}

static uint64_t ds_pubg_read_ptr(uint64_t address) {
    uint64_t value = 0;
    if (!ds_pubg_valid(address) || !g_dspubgVmMap) return 0;
    if (!ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value))) return 0;
    value &= 0x0000FFFFFFFFFFFFULL;
    return (ds_pubg_valid(value) && (value & 0x7ULL) == 0) ? value : 0;
}

static bool ds_pubg_read(uint64_t address, void *buffer, size_t length) {
    if (!g_dspubgVmMap || !ds_pubg_valid(address) || !buffer || !length)
        return false;
    return ds_debug_read_bytes(g_dspubgVmMap, address, buffer, length);
}

static uint32_t ds_pubg_read_u32(uint64_t address) {
    uint32_t value = 0;
    if (!g_dspubgVmMap || !ds_pubg_valid(address)) return 0;
    ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value));
    return value;
}

static int32_t ds_pubg_read_i32(uint64_t address) {
    int32_t value = 0;
    if (!g_dspubgVmMap || !ds_pubg_valid(address)) return 0;
    ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value));
    return value;
}

static float ds_pubg_read_f32(uint64_t address) {
    float value = 0.0f;
    if (!g_dspubgVmMap || !ds_pubg_valid(address)) return 0.0f;
    ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value));
    return value;
}

static uint8_t ds_pubg_read_u8(uint64_t address) {
    uint8_t value = 0;
    if (!g_dspubgVmMap || !ds_pubg_valid(address)) return 0;
    ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value));
    return value;
}

static int ds_pubg_ucs2_to_utf8(const uint8_t *src, int srcChars, char *out, int outCap) {
    if (!src || srcChars <= 0 || !out || outCap <= 1) return 0;
    int o = 0;
    for (int i = 0; i < srcChars && o + 4 < outCap; i++) {
        uint16_t u = (uint16_t)src[i * 2] | ((uint16_t)src[i * 2 + 1] << 8);
        if (u == 0) break;
        if (u < 0x80) {
            out[o++] = (char)u;
        } else if (u < 0x800) {
            out[o++] = (char)(0xC0 | (u >> 6));
            out[o++] = (char)(0x80 | (u & 0x3F));
        } else {
            out[o++] = (char)(0xE0 | (u >> 12));
            out[o++] = (char)(0x80 | ((u >> 6) & 0x3F));
            out[o++] = (char)(0x80 | (u & 0x3F));
        }
    }
    out[o] = '\0';
    return o;
}

static bool ds_pubg_read_fstring_nick(uint64_t fstr, char *out, int outCap) {
    if (!fstr || !ds_pubg_valid(fstr) || !out || outCap <= 1) return false;
    uint64_t dataPtr = ds_pubg_read_ptr(fstr);
    uint32_t num = ds_pubg_read_u32(fstr + 8);
    if (!dataPtr || !ds_pubg_valid(dataPtr) || num < 2 || num > 32) return false;
    uint8_t raw[64] = {0};
    uint64_t want = (uint64_t)num * 2;
    if (want > sizeof(raw)) want = sizeof(raw);
    if (!ds_pubg_read(dataPtr, raw, (size_t)want)) return false;
    int n = ds_pubg_ucs2_to_utf8(raw, (int)(want / 2), out, outCap);
    return n >= 2;
}

// Check whether candidate pointer points to a valid Unreal Engine UWorld.
// In UE4: World.PersistentLevel (+0x30) -> Level.OwningWorld (+0xC0) == World.
static bool ds_pubg_is_valid_world(uint64_t vmMap, uint64_t world) {
    if (!ds_pubg_valid(world) || (world & 0x7ULL) != 0) return false;
    uint64_t level = 0;
    if (!ds_debug_read_bytes(vmMap, world + kDSPUBGWorldPersistentLevelOffset, &level, sizeof(level))) return false;
    level &= 0x0000FFFFFFFFFFFFULL;
    if (!ds_pubg_valid(level) || (level & 0x7ULL) != 0) return false;
    uint64_t owningWorld = 0;
    if (!ds_debug_read_bytes(vmMap, level + 0xC0ULL, &owningWorld, sizeof(owningWorld))) return false;
    owningWorld &= 0x0000FFFFFFFFFFFFULL;
    return (owningWorld == world);
}

// Check whether candidate pointer points to a valid Unreal Engine UEngine.
// In UE4: Engine.GameViewport (+0x810, +0x808, etc.) -> Viewport.World (+0x78) == UWorld.
static bool ds_pubg_is_valid_engine(uint64_t vmMap, uint64_t gengine, uint64_t *outVpOff, uint64_t *outWorld) {
    if (!ds_pubg_valid(gengine) || (gengine & 0x7ULL) != 0) return false;
    static const uint64_t vpOffsets[] = { 0x810, 0x808, 0x800, 0x818, 0x820, 0x780 };
    for (uint64_t vpOff : vpOffsets) {
        uint64_t vp = 0;
        if (!ds_debug_read_bytes(vmMap, gengine + vpOff, &vp, sizeof(vp))) continue;
        vp &= 0x0000FFFFFFFFFFFFULL;
        if (!ds_pubg_valid(vp) || (vp & 0x7ULL) != 0) continue;

        static const uint64_t wOffsets[] = { 0x78, 0x80, 0x70 };
        for (uint64_t wOff : wOffsets) {
            uint64_t world = 0;
            if (!ds_debug_read_bytes(vmMap, vp + wOff, &world, sizeof(world))) continue;
            world &= 0x0000FFFFFFFFFFFFULL;
            if (ds_pubg_is_valid_world(vmMap, world)) {
                if (outVpOff) *outVpOff = vpOff;
                if (outWorld) *outWorld = world;
                return true;
            }
        }
    }
    return false;
}

// Automatically scans __DATA sections of the main Mach-O image to discover GEngine or GWorld dynamically.
// This allows DarkPubg to work across different PUBG Mobile versions (Global, VN, KR, TW, updates)
// without breaking on static RVA changes.
static bool ds_pubg_scan_for_engine_and_world(uint64_t vmMap, uint64_t base) {
    if (!vmMap || !base) return false;

    // 1. Check currently configured RVA
    if (g_dspubgEngineRva) {
        uint64_t ge = 0;
        if (ds_debug_read_bytes(vmMap, base + g_dspubgEngineRva, &ge, sizeof(ge))) {
            ge &= 0x0000FFFFFFFFFFFFULL;
            uint64_t vpOff = 0, world = 0;
            if (ds_pubg_is_valid_engine(vmMap, ge, &vpOff, &world)) {
                g_dspubgEngineViewportOffset = vpOff;
                g_dspubgCachedWorld = world;
                return true;
            }
        }
    }

    // 2. Check known common RVAs across PUBG Mobile versions
    static const uint64_t kKnownRVAs[] = {
        0x0A8AA8A0ULL, // v3.4 Global
        0x0A8A98A0ULL,
        0x0A8B08A0ULL,
        0x0A88B8A0ULL,
        0x0A8B88A0ULL,
        0x0A9008A0ULL,
        0x0A7AA8A0ULL,
        0x0A692D18ULL,
        0x0A692D28ULL
    };
    for (uint64_t rva : kKnownRVAs) {
        uint64_t ge = 0;
        if (ds_debug_read_bytes(vmMap, base + rva, &ge, sizeof(ge))) {
            ge &= 0x0000FFFFFFFFFFFFULL;
            uint64_t vpOff = 0, world = 0;
            if (ds_pubg_is_valid_engine(vmMap, ge, &vpOff, &world)) {
                g_dspubgEngineRva = rva;
                g_dspubgEngineViewportOffset = vpOff;
                g_dspubgCachedWorld = world;
                return true;
            }
        }
    }

    // 3. Parse Mach-O load commands to scan __DATA sections (__bss, __common, __data)
    struct mach_header_64 header = {};
    if (!ds_debug_read_bytes(vmMap, base, &header, sizeof(header)) ||
        header.magic != MH_MAGIC_64 || header.ncmds == 0 || header.ncmds > 1024 ||
        header.sizeofcmds == 0 || header.sizeofcmds > (64U * 1024U)) {
        return false;
    }

    std::vector<uint8_t> commands(header.sizeofcmds);
    if (!ds_debug_read_bytes(vmMap, base + sizeof(header), commands.data(), commands.size())) {
        return false;
    }

    uint64_t slide = 0;
    bool slideFound = false;
    size_t cursor = 0;
    for (uint32_t i = 0; i < header.ncmds; i++) {
        if (cursor + sizeof(struct load_command) > commands.size()) break;
        const struct load_command *cmd = (const struct load_command *)(commands.data() + cursor);
        if (cmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cmd;
            if (strncmp(seg->segname, "__TEXT", 6) == 0) {
                slide = base - seg->vmaddr;
                slideFound = true;
                break;
            }
        }
        cursor += cmd->cmdsize;
    }
    if (!slideFound) return false;

    struct ScanRange {
        uint64_t start;
        uint64_t size;
        int priority; // 0 = high (__bss, __common), 1 = medium (__data), 2 = other
    };
    std::vector<ScanRange> scanRanges;

    cursor = 0;
    for (uint32_t i = 0; i < header.ncmds; i++) {
        if (cursor + sizeof(struct load_command) > commands.size()) break;
        const struct load_command *cmd = (const struct load_command *)(commands.data() + cursor);
        if (cmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cmd;
            if (strncmp(seg->segname, "__DATA", 6) == 0) {
                const struct section_64 *sections = (const struct section_64 *)(commands.data() + cursor + sizeof(struct segment_command_64));
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    const struct section_64 &sec = sections[s];
                    if (sec.size < 8) continue;
                    uint64_t sAddr = sec.addr + slide;
                    int prio = 2;
                    if (strcmp(sec.sectname, "__bss") == 0 || strcmp(sec.sectname, "__common") == 0) {
                        prio = 0;
                    } else if (strcmp(sec.sectname, "__data") == 0) {
                        prio = 1;
                    }
                    scanRanges.push_back({sAddr, sec.size, prio});
                }
            }
        }
        cursor += cmd->cmdsize;
    }

    std::sort(scanRanges.begin(), scanRanges.end(), [](const ScanRange &a, const ScanRange &b) {
        return a.priority < b.priority;
    });

    const size_t kChunkSize = 32768;
    std::vector<uint8_t> chunk(kChunkSize);

    for (const auto &range : scanRanges) {
        uint64_t limitSize = range.size > (16ULL * 1024ULL * 1024ULL) ? (16ULL * 1024ULL * 1024ULL) : range.size;
        for (uint64_t offset = 0; offset < limitSize; offset += kChunkSize) {
            size_t toRead = (size_t)std::min((uint64_t)kChunkSize, limitSize - offset);
            uint64_t chunkAddr = range.start + offset;
            if (!ds_debug_read_bytes(vmMap, chunkAddr, chunk.data(), toRead)) continue;

            size_t ptrCount = toRead / 8;
            const uint64_t *ptrs = (const uint64_t *)chunk.data();
            for (size_t p = 0; p < ptrCount; p++) {
                uint64_t val = ptrs[p] & 0x0000FFFFFFFFFFFFULL;
                if (!val || (val & 0x7ULL) != 0 || !ds_pubg_valid(val)) continue;

                uint64_t ptrAddr = chunkAddr + p * 8;

                // Check 1: Is val GWorld directly?
                if (ds_pubg_is_valid_world(vmMap, val)) {
                    g_dspubgWorldRva = ptrAddr - base;
                    g_dspubgCachedWorld = val;
                    return true;
                }

                // Check 2: Is val GEngine?
                uint64_t vpOff = 0, world = 0;
                if (ds_pubg_is_valid_engine(vmMap, val, &vpOff, &world)) {
                    g_dspubgEngineRva = ptrAddr - base;
                    g_dspubgEngineViewportOffset = vpOff;
                    g_dspubgCachedWorld = world;
                    return true;
                }
            }
        }
    }
    return false;
}

static void ds_pubg_reset_state(void) {
    g_dspubgProc = 0;
    g_dspubgPid = 0;
    g_dspubgVmMap = 0;
    g_dspubgBase = 0;
    g_dspubgEngineRva = 0;
    g_dspubgWorldRva = 0;
    g_dspubgCachedWorld = 0;
    g_dspubgLastActorsCount = 0;
    g_dspubgLastEnemyCount = 0;
    g_dspubgLastBotCount = 0;
    g_dspubgNextScan = 0;
    g_dspubgTargetActive.store(false, std::memory_order_release);
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    g_dspubgPlayerCount = 0;
    memset(g_dspubgPlayers, 0, sizeof(g_dspubgPlayers));
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}

// Find PUBG Mobile process. In iOS XNU, p_comm is 16 bytes max (15 chars + \0),
// so "ShadowTrackerExtra" (18 chars) truncates to "ShadowTrackerEx".
static uint64_t ds_pubg_find_proc(pid_t *outPid) {
    if (outPid) *outPid = 0;
    if (!ds_is_ready()) return 0;

    // 1. Prefix match via procbyname (15 chars)
    uint64_t proc = procbyname("ShadowTrackerEx");
    if (!proc) proc = procbyname("ShadowTrackerExtra");
    if (!proc) proc = procbyname("ShadowTracker");
    if (!proc) proc = procbyname("PUBG MOBILE");
    if (!proc) proc = procbyname("PUBGMOBILE");
    if (!proc) proc = procbyname("pubgmobile");
    if (!proc) proc = procbyname("PUBGM");
    if (!proc) proc = procbyname("pubg");

    if (proc) {
        if (outPid) {
            pid_t pid = (pid_t)(off_proc_p_pid ? ds_kread32(proc + off_proc_p_pid) : 0);
            if (pid <= 0) pid = (pid_t)ds_kread32(proc + 0x60);
            if (pid <= 0) pid = (pid_t)ds_kread32(proc + 0x28);
            *outPid = pid;
        }
        return proc;
    }

    // 2. Full proclist search with case-insensitive substring
    int count = 0;
    proc_entry_t *list = proclist("", &count);
    if (list && count > 0) {
        for (int i = 0; i < count; i++) {
            const char *name = list[i].name;
            if (!name || !name[0]) continue;
            if (strcasestr(name, "Shadow") != NULL || strcasestr(name, "PUBG") != NULL) {
                uint64_t p = list[i].kaddr;
                if (p && ds_isvalid(p)) {
                    pid_t pid = off_proc_p_pid ? (pid_t)ds_kread32(p + off_proc_p_pid) : (pid_t)list[i].pid;
                    if (pid <= 0) pid = (pid_t)list[i].pid;
                    if (pid > 0) {
                        if (outPid) *outPid = pid;
                        proc = p;
                        break;
                    }
                }
            }
        }
        free_proclist(list);
    }
    return proc;
}

// Locate main executable base image.
static uint64_t ds_pubg_find_base(uint64_t vmMap) {
    if (!vmMap) return 0;

    std::vector<uint64_t> starts;
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    for (const DSDebugVMRegion &region : g_debugVMRegions) {
        starts.push_back(region.start);
    }
    os_unfair_lock_unlock(&g_debugVMRegionsLock);

    uint64_t firstMacho = 0;
    for (uint64_t start : starts) {
        if (ds_debug_macho_main_identity(vmMap, start)) {
            firstMacho = start;
            break;
        }
    }
    if (!firstMacho) {
        firstMacho = ds_debug_find_main_image_base(vmMap);
    }
    return firstMacho;
}

static bool ds_pubg_attach(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (g_dspubgTargetActive.load(std::memory_order_acquire) && g_dspubgBase && g_dspubgVmMap) {
        return true;
    }
    if (now < g_dspubgNextAttach) return false;

    pid_t targetPid = 0;
    uint64_t proc = ds_pubg_find_proc(&targetPid);

    if (!ds_isvalid(proc) || targetPid <= 0) {
        g_dspubgTargetActive.store(false, std::memory_order_release);
        g_dspubgProc = g_dspubgVmMap = g_dspubgBase = 0;
        g_dspubgPid = 0;
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    uint64_t task = proc_task(proc);
    uint64_t vmMap = ds_isvalid(task) ? task_get_vm_map(task) : 0;
    if (!ds_isvalid(vmMap)) {
        g_dspubgTargetActive.store(false, std::memory_order_release);
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    bool identityChanged = (g_dspubgProc != proc || g_dspubgPid != (uint32_t)targetPid || g_dspubgVmMap != vmMap);
    if (identityChanged) {
        g_dspubgBase = 0;
        g_dspubgEngineRva = 0;
        g_dspubgWorldRva = 0;
        g_dspubgCachedWorld = 0;
    }
    g_dspubgProc = proc;
    g_dspubgPid = (uint32_t)targetPid;
    g_dspubgVmMap = vmMap;

    if (!ds_debug_shmem_claim_target(DSDebugShmemOwner::PUBG, targetPid, proc, vmMap)) {
        g_dspubgTargetActive.store(false, std::memory_order_release);
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    if (!g_dspubgBase || identityChanged) {
        ds_debug_vm_regions_rebuild(vmMap, targetPid, YES);
        g_dspubgBase = ds_pubg_find_base(vmMap);
        if (g_dspubgBase) {
            ds_pubg_scan_for_engine_and_world(vmMap, g_dspubgBase);
        }
    }

    if (!g_dspubgBase) {
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    g_dspubgTargetActive.store(true, std::memory_order_release);
    g_dspubgNextAttach = now + 1.5;
    return true;
}

// Build Camera Basis for World-to-Screen projection (DarkPubg proven algorithm)
static bool ds_pubg_cam_basis_build(DSPUBGVector camLoc, DSPUBGRotator camRot, float fov,
                                    float screenW, float screenH, DSPUBGCamBasis &b) {
    if (screenW <= 0.0f || screenH <= 0.0f || fov < 10.0f || fov > 170.0f) return false;
    const float kPi = 3.141592653589793f;
    float radPitch = camRot.Pitch * kPi / 180.0f;
    float radYaw   = camRot.Yaw   * kPi / 180.0f;
    float radRoll  = camRot.Roll  * kPi / 180.0f;

    float SP = sinf(radPitch), CP = cosf(radPitch);
    float SY = sinf(radYaw),   CY = cosf(radYaw);
    float SR = sinf(radRoll),  CR = cosf(radRoll);

    float tanHalf = tanf(fov * kPi / 360.0f);
    if (tanHalf <= 0.01f || tanHalf > 10.0f) return false;

    b.m00 = CP * CY;
    b.m01 = CP * SY;
    b.m02 = SP;

    b.m10 = SR * SP * CY - CR * SY;
    b.m11 = SR * SP * SY + CR * CY;
    b.m12 = -SR * CP;

    b.m20 = -(CR * SP * CY + SR * SY);
    b.m21 = CY * SR - CR * SP * SY;
    b.m22 = CR * CP;

    b.lx = camLoc.X;
    b.ly = camLoc.Y;
    b.lz = camLoc.Z;

    b.cx = screenW * 0.5f;
    b.cy = screenH * 0.5f;
    b.k  = b.cx / tanHalf;

    return true;
}

static bool ds_pubg_cam_basis_project(const DSPUBGCamBasis &b, DSPUBGVector world,
                                      float &outX, float &outY, float &outDist) {
    float dx = world.X - b.lx;
    float dy = world.Y - b.ly;
    float dz = world.Z - b.lz;

    float tx = dx * b.m10 + dy * b.m11 + dz * b.m12;
    float ty = dx * b.m20 + dy * b.m21 + dz * b.m22;
    float tz = dx * b.m00 + dy * b.m01 + dz * b.m02;

    if (tz < 10.0f) return false; // Behind or too close

    float distM = sqrtf(dx * dx + dy * dy + dz * dz) / 100.0f;
    outX = b.cx + tx * b.k / tz;
    outY = b.cy - ty * b.k / tz;
    outDist = distM;
    return true;
}

static bool ds_pubg_has_render_source(void) {
    return g_dspubgTargetActive.load(std::memory_order_acquire);
}

static int ds_pubg_copy_projected_players(DSPUBGProjectedPlayer out[kDSPUBGMaxPlayers], uint64_t *epochOut) {
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    int count = g_dspubgPlayerCount;
    if (count > 0 && out) {
        memcpy(out, g_dspubgPlayers, count * sizeof(DSPUBGProjectedPlayer));
    }
    if (epochOut) *epochOut = g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
    return count;
}

static void ds_pubg_overlay_reset(void) {
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    g_dspubgPlayerCount = 0;
    memset(g_dspubgPlayers, 0, sizeof(g_dspubgPlayers));
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}

// Convert ESTExtraVehicleType enum to readable name
static const char* ds_pubg_vehicle_name(uint8_t type) {
    switch (type) {
        case 1: case 2: return "Motorbike";
        case 3: case 4: return "Moto Cart";
        case 5: case 6: case 7: case 8: return "Dacia";
        case 9: case 10: case 11: return "UAZ";
        case 12: case 13: case 14: return "Buggy";
        case 15: return "Boat";
        case 16: return "Aquarail";
        case 17: case 18: case 19: return "Minibus";
        case 20: case 21: case 22: case 23: case 24:
        case 25: case 26: case 27: case 28: case 29: return "Pickup";
        case 30: case 31: case 32: return "Buggy";
        case 33: case 34: case 35: case 36:
        case 37: case 38: return "Mirado";
        case 39: case 40: return "Mirado";
        case 41: return "UAZ";
        case 42: case 43: return "Rony";
        case 44: case 45: return "Scooter";
        case 46: case 47: return "Tukshai";
        case 48: case 49: return "BRDM-2";
        case 50: case 51: return "Monster Truck";
        case 52: case 53: return "Coupe RB";
        default: return "Vehicle";
    }
}

// Live informative diagnostic HUD string
static const char* ds_pubg_get_debug_status(void) {
    if (!g_dspubgTargetActive.load(std::memory_order_acquire)) {
        return "PUBG: Waiting for game process...";
    }
    if (!g_dspubgBase) {
        return "PUBG: Attached (Resolving Base...)";
    }
    if (!g_dspubgCachedWorld && !g_dspubgEngineRva && !g_dspubgWorldRva) {
        return "PUBG: Scanning Engine & World...";
    }
    if (!g_dspubgCachedWorld) {
        return "PUBG: Attached (Waiting for Match)";
    }
    if (g_dspubgLastEnemyCount > 0 || g_dspubgLastBotCount > 0 || g_dspubgLastVehicleCount > 0) {
        snprintf(g_dspubgStatusBuf, sizeof(g_dspubgStatusBuf),
                 "PUBG: %d Enemies | %d Bots | %d Cars",
                 g_dspubgLastEnemyCount, g_dspubgLastBotCount, g_dspubgLastVehicleCount);
        return g_dspubgStatusBuf;
    }
    if (g_dspubgLastActorsCount > 0) {
        snprintf(g_dspubgStatusBuf, sizeof(g_dspubgStatusBuf),
                 "PUBG: In Match (0 Enemies | %d Actors)", g_dspubgLastActorsCount);
    } else {
        snprintf(g_dspubgStatusBuf, sizeof(g_dspubgStatusBuf),
                 "PUBG: In Match (Waiting for Spawns)");
    }
    return g_dspubgStatusBuf;
}

static void ds_pubg_tick(void) {
    if (!ds_pubg_attach()) {
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    // 1. Resolve World pointer
    uint64_t world = 0;
    if (g_dspubgEngineRva) {
        uint64_t gengine = ds_pubg_read_ptr(g_dspubgBase + g_dspubgEngineRva);
        if (gengine) {
            uint64_t vp = ds_pubg_read_ptr(gengine + g_dspubgEngineViewportOffset);
            if (vp) {
                world = ds_pubg_read_ptr(vp + kDSPUBGViewportWorldOffset);
                if (!world) world = ds_pubg_read_ptr(vp + 0x80ULL);
            }
        }
    }

    if (!world && g_dspubgWorldRva) {
        world = ds_pubg_read_ptr(g_dspubgBase + g_dspubgWorldRva);
    }

    if (!world && g_dspubgCachedWorld) {
        if (ds_pubg_is_valid_world(g_dspubgVmMap, g_dspubgCachedWorld)) {
            world = g_dspubgCachedWorld;
        }
    }

    // Dynamic scan fallback if world is lost or unlocated
    if (!world) {
        if (now >= g_dspubgNextScan) {
            g_dspubgNextScan = now + 1.5;
            if (ds_pubg_scan_for_engine_and_world(g_dspubgVmMap, g_dspubgBase)) {
                world = g_dspubgCachedWorld;
            }
        }
    } else {
        g_dspubgCachedWorld = world;
    }

    if (!world) {
        g_dspubgLastActorsCount = 0;
        g_dspubgLastEnemyCount = 0;
        g_dspubgLastBotCount = 0;
        g_dspubgLastVehicleCount = 0;
        return;
    }

    // 2. Resolve LocalPlayer, PlayerController, CameraManager
    uint64_t gameInstance = 0;
    if (g_dspubgEngineRva) {
        uint64_t ge = ds_pubg_read_ptr(g_dspubgBase + g_dspubgEngineRva);
        if (ge) gameInstance = ds_pubg_read_ptr(ge + kDSPUBGEngineGameInstanceOffset);
    }
    if (!gameInstance) {
        gameInstance = ds_pubg_read_ptr(world + kDSPUBGWorldOwningGameInstanceOffset);
        if (!gameInstance) gameInstance = ds_pubg_read_ptr(world + 0x240ULL);
    }

    uint64_t localPlayer = 0;
    if (gameInstance) {
        uint64_t lpArray = ds_pubg_read_ptr(gameInstance + kDSPUBGGameInstanceLocalPlayersOffset);
        if (lpArray) localPlayer = ds_pubg_read_ptr(lpArray);
        if (!localPlayer) {
            uint64_t lp38 = ds_pubg_read_ptr(gameInstance + 0x38ULL);
            if (lp38 && ds_pubg_valid(lp38)) localPlayer = ds_pubg_read_ptr(lp38);
        }
    }

    uint64_t playerController = 0;
    if (localPlayer) {
        playerController = ds_pubg_read_ptr(localPlayer + kDSPUBGLocalPlayerControllerOffset);
    }

    // Fallback: Find local PlayerController from GameState if LocalPlayers was empty or encrypted
    if (!playerController) {
        uint64_t gs = ds_pubg_read_ptr(world + kDSPUBGWorldGameStateOffset);
        if (gs) {
            uint64_t paData = ds_pubg_read_ptr(gs + kDSPUBGGameStatePlayerArrayOffset);
            uint32_t paCount = ds_pubg_read_u32(gs + kDSPUBGGameStatePlayerArrayOffset + 8);
            if (paData && paCount > 0) {
                if (paCount > 100) paCount = 100;
                for (uint32_t i = 0; i < paCount; i++) {
                    uint64_t ps = ds_pubg_read_ptr(paData + i * 8);
                    if (!ps) continue;
                    uint64_t owner = ds_pubg_read_ptr(ps + 0xF0ULL); // AActor.Owner
                    if (owner && ds_pubg_valid(owner)) {
                        uint64_t cam = ds_pubg_read_ptr(owner + kDSPUBGPlayerControllerCameraMgrOffset);
                        if (cam && ds_pubg_valid(cam)) {
                            playerController = owner;
                            break;
                        }
                    }
                }
            }
        }
    }

    uint64_t localPawn = playerController ? ds_pubg_read_ptr(playerController + kDSPUBGPlayerControllerPawnOffset) : 0;
    uint64_t cameraManager = playerController ? ds_pubg_read_ptr(playerController + kDSPUBGPlayerControllerCameraMgrOffset) : 0;

    DSPUBGVector camLoc = {};
    DSPUBGRotator camRot = {};
    float camFOV = 90.0f;
    float camAspect = 0.0f;

    if (cameraManager) {
        // ViewTarget.POV (0x10A0 + 0x10 = 0x10B0)
        uint64_t pov = cameraManager + kDSPUBGCameraViewTargetOffset + kDSPUBGViewTargetPOVOffset;
        ds_pubg_read(pov + kDSPUBGPOVLocationOffset, &camLoc, sizeof(camLoc));
        ds_pubg_read(pov + kDSPUBGPOVRotationOffset, &camRot, sizeof(camRot));
        ds_pubg_read(pov + kDSPUBGPOVFOVOffset, &camFOV, sizeof(camFOV));
        ds_pubg_read(pov + kDSPUBGPOVAspectOffset, &camAspect, sizeof(camAspect));

        // CameraCache.POV fallback (0x520 + 0x10 = 0x530)
        if (fabsf(camLoc.X) < 1.0f && fabsf(camLoc.Y) < 1.0f && fabsf(camLoc.Z) < 1.0f) {
            uint64_t cachePov = cameraManager + 0x520ULL + 0x10ULL;
            ds_pubg_read(cachePov + kDSPUBGPOVLocationOffset, &camLoc, sizeof(camLoc));
            ds_pubg_read(cachePov + kDSPUBGPOVRotationOffset, &camRot, sizeof(camRot));
            ds_pubg_read(cachePov + kDSPUBGPOVFOVOffset, &camFOV, sizeof(camFOV));
        }
    }

    // Tertiary camera fallback: If cameraManager was null or loc is 0, search PersistentLevel for any PlayerCameraManager
    uint64_t level = ds_pubg_read_ptr(world + kDSPUBGWorldPersistentLevelOffset);
    if ((!cameraManager || (fabsf(camLoc.X) < 1.0f && fabsf(camLoc.Y) < 1.0f && fabsf(camLoc.Z) < 1.0f)) && level) {
        uint64_t cluster = ds_pubg_read_ptr(level + 0xE0ULL);
        uint64_t aData = cluster ? ds_pubg_read_ptr(cluster + 0x28ULL) : ds_pubg_read_ptr(level + 0x98ULL);
        uint32_t aCount = cluster ? ds_pubg_read_u32(cluster + 0x30ULL) : ds_pubg_read_u32(level + 0xA0ULL);
        if (aData && aCount > 0) {
            if (aCount > 512) aCount = 512;
            std::vector<uint64_t> act(aCount, 0);
            if (ds_pubg_read(aData, act.data(), aCount * sizeof(uint64_t))) {
                for (uint32_t i = 0; i < aCount; i++) {
                    uint64_t a = act[i];
                    if (!a || !ds_pubg_valid(a)) continue;
                    float testFov = ds_pubg_read_f32(a + 0x530ULL + 0x24ULL);
                    if (testFov >= 50.0f && testFov <= 120.0f) {
                        DSPUBGVector testLoc = {};
                        ds_pubg_read(a + 0x530ULL, &testLoc, sizeof(testLoc));
                        if (fabsf(testLoc.X) > 10.0f || fabsf(testLoc.Y) > 10.0f) {
                            cameraManager = a;
                            camLoc = testLoc;
                            ds_pubg_read(a + 0x530ULL + 0x18ULL, &camRot, sizeof(camRot));
                            camFOV = testFov;
                            break;
                        }
                    }
                }
            }
        }
    }

    if (camFOV < 10.0f || camFOV > 170.0f) camFOV = 90.0f;

    int32_t localTeamId = -1;
    if (localPawn) {
        localTeamId = ds_pubg_read_i32(localPawn + kDSPUBGCharacterTeamIDOffset);
    }

    CGRect screenBounds = UIScreen.mainScreen.bounds;
    float screenW = (float)MAX(screenBounds.size.width, screenBounds.size.height);
    float screenH = (float)MIN(screenBounds.size.width, screenBounds.size.height);

    DSPUBGCamBasis basis = {};
    if (!ds_pubg_cam_basis_build(camLoc, camRot, camFOV, screenW, screenH, basis)) {
        return;
    }

    DSPUBGProjectedPlayer staging[kDSPUBGMaxPlayers] = {};
    int publishedCount = 0;
    int enemyCount = 0;
    int botCount = 0;
    int vehicleCount = 0;
    std::vector<uint64_t> seenPawns;

    auto processVehicle = [&](uint64_t veh, uint64_t vehCommon, uint8_t vehType) {
        if (!veh || !ds_pubg_valid(veh)) return;
        if (!g_pubgEspVehicle) return;
        if (veh == localPawn) return;
        if (localPawn) {
            uint64_t myVeh = ds_pubg_read_ptr(localPawn + kDSPUBGCharacterVehicleOffset);
            if (myVeh && veh == myVeh) return; // Skip vehicle we are currently inside
        }
        for (uint64_t seen : seenPawns) {
            if (seen == veh) return;
        }

        uint64_t rootComp = ds_pubg_read_ptr(veh + kDSPUBGActorRootComponentOffset);
        if (!rootComp) rootComp = ds_pubg_read_ptr(veh + 0x180ULL);
        if (!rootComp || !ds_pubg_valid(rootComp)) return;

        // Check bHidden in AActor (offset 0xE8)
        uint8_t aHidden = ds_pubg_read_u8(veh + 0xE8ULL);
        if (aHidden & 0x1) return;

        seenPawns.push_back(veh);

        DSPUBGVector rootLoc = {};
        if (!ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc))) return;
        if (isnan(rootLoc.X) || isinf(rootLoc.X) || (fabsf(rootLoc.X) < 1.0f && fabsf(rootLoc.Y) < 1.0f)) return;

        uint64_t parent = ds_pubg_read_ptr(rootComp + kDSPUBGSceneCompAttachedParentOffset);
        if (parent && ds_pubg_valid(parent)) {
            DSPUBGVector pLoc = {};
            if (ds_pubg_read(parent + kDSPUBGSceneCompRelativeLocOffset, &pLoc, sizeof(pLoc))) {
                rootLoc.X += pLoc.X;
                rootLoc.Y += pLoc.Y;
                rootLoc.Z += pLoc.Z;
            }
        }

        // Read HP and Fuel from UVehicleCommonComponent
        float hpMax = ds_pubg_read_f32(vehCommon + 0x350ULL);
        float hp = ds_pubg_read_f32(vehCommon + 0x354ULL);
        float fuelMax = ds_pubg_read_f32(vehCommon + 0x438ULL);
        float fuel = ds_pubg_read_f32(vehCommon + 0x43CULL);

        // Destroyed / exploded vehicle check:
        if (!isnan(hp) && !isnan(hpMax) && hpMax >= 50.0f && hp <= 0.0f) {
            return; // Destroyed/exploded vehicle -> skip
        }
        if (hpMax < 50.0f || hpMax > 20000.0f || isnan(hpMax) || isinf(hpMax)) {
            hpMax = 1000.0f;
        }
        if (isnan(hp) || isinf(hp) || hp <= 0.0f || hp > hpMax) {
            hp = hpMax;
        }

        float fuelPct = (fuelMax > 0.0f && fuel >= 0.0f) ? ((fuel / fuelMax) * 100.0f) : 100.0f;
        if (fuelPct > 100.0f) fuelPct = 100.0f;

        float vehH = 140.0f;
        float halfH = vehH * 0.5f;
        DSPUBGVector bot = rootLoc; bot.Z -= halfH;
        DSPUBGVector top = rootLoc; top.Z += halfH;

        float bx = 0, by = 0, bd = 0;
        float tx = 0, ty = 0, td = 0;
        bool okB = ds_pubg_cam_basis_project(basis, bot, bx, by, bd);
        bool okT = ds_pubg_cam_basis_project(basis, top, tx, ty, td);

        float sx = 0, sy = 0, dist = 0;
        if (!okB && !okT) {
            if (!ds_pubg_cam_basis_project(basis, rootLoc, sx, sy, dist)) return;
        } else {
            dist = okB ? bd : td;
        }

        if (dist > g_dspubgMaxDistance || dist < 0.5f) return;

        float topY = 0, bottomY = 0, boxH = 0, centerX = 0;
        if (okB && okT) {
            topY = fminf(ty, by);
            bottomY = fmaxf(ty, by);
            boxH = bottomY - topY;
            centerX = (tx + bx) * 0.5f;
        } else {
            float tz = dist * 100.0f;
            if (tz < 10.0f) tz = 10.0f;
            boxH = (vehH / tz) * basis.k;
            topY = sy - boxH * 0.5f;
            centerX = sx;
        }

        if (boxH < 6.0f) boxH = 6.0f;
        if (boxH > screenH * 2.0f) return;
        float boxW = boxH * 1.35f;
        float boxX = centerX - boxW * 0.5f;

        if (centerX + boxW * 0.5f < -60.0f || centerX - boxW * 0.5f > screenW + 60.0f ||
            topY > screenH + 60.0f || topY + boxH < -60.0f) {
            return;
        }

        DSPUBGProjectedPlayer p = {};
        p.screenX = boxX;
        p.screenY = topY;
        p.headX = centerX;
        p.headY = topY;
        p.boxWidth = boxW;
        p.boxHeight = boxH;
        p.distanceMeters = dist;
        p.health = hp;
        p.healthMax = hpMax;
        p.teamId = -1;
        p.isAI = false;
        p.isDead = false;
        p.isVisible = true;
        p.isVehicle = true;
        p.fuel = fuelPct;
        p.actorPtr = veh;
        strncpy(p.name, ds_pubg_vehicle_name(vehType), sizeof(p.name) - 1);

        if (publishedCount < kDSPUBGMaxPlayers) {
            staging[publishedCount++] = p;
            vehicleCount++;
        }
    };

    auto processPawn = [&](uint64_t pawn, uint64_t psHint, bool knownBot) {
        if (!pawn || pawn == localPawn || !ds_pubg_valid(pawn)) return;
        for (uint64_t seen : seenPawns) {
            if (seen == pawn) return;
        }

        // 1. Reject local player's own bullets, weapons, projectiles
        uint64_t owner = ds_pubg_read_ptr(pawn + 0x140ULL);
        uint64_t instigator = ds_pubg_read_ptr(pawn + 0x138ULL);
        if (localPawn && (owner == localPawn || instigator == localPawn)) {
            return;
        }

        // 2. Check bHidden in AActor (offset 0xE8)
        uint8_t aHidden = ds_pubg_read_u8(pawn + 0xE8ULL);
        if (aHidden & 0x1) return;

        // 3. Dead check - STExtraCharacter.bDead at 0xE7C
        uint8_t isDead = ds_pubg_read_u8(pawn + kDSPUBGCharacterDeadOffset) & 1;
        if (isDead) return;

        // 4. Must have valid RootComponent and Mesh
        uint64_t rootComp = ds_pubg_read_ptr(pawn + kDSPUBGActorRootComponentOffset);
        if (!rootComp) rootComp = ds_pubg_read_ptr(pawn + 0x180ULL);
        if (!rootComp || !ds_pubg_valid(rootComp)) return;

        uint64_t meshComp = ds_pubg_read_ptr(pawn + kDSPUBGCharacterMeshOffset);
        if (!meshComp || !ds_pubg_valid(meshComp)) return;

        // 5. Verification for actors discovered outside PlayerArray:
        // Must match UE4 ACharacter hierarchy (CapsuleComponent == RootComponent and valid CharacterMovement)
        uint64_t ps = psHint ? psHint : ds_pubg_read_ptr(pawn + 0x4D0ULL);
        if (!ps || !ds_pubg_valid(ps)) {
            uint64_t capsuleComp = ds_pubg_read_ptr(pawn + kDSPUBGCharacterCapsuleOffset);
            uint64_t moveComp = ds_pubg_read_ptr(pawn + kDSPUBGCharacterMovementOffset);
            if (capsuleComp != rootComp || !moveComp || !ds_pubg_valid(moveComp)) {
                return; // Discard bullets, weapon projectiles, loot items, level debris!
            }
        }

        // 6. Health check:
        // Real PUBG Mobile characters have HealthMax 50..500 (usually 100).
        // Props, crates, items DO NOT have HealthMax in this range!
        float health = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthOffset);
        float healthMax = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthMaxOffset);
        if (isnan(health) || isinf(health) || isnan(healthMax) || isinf(healthMax)) return;
        if (health <= 0.0f) return; // Discard dead or healthless objects!

        if (!psHint) {
            if (healthMax < 50.0f || healthMax > 500.0f) return;
            if (health > healthMax + 50.0f) return;
        } else {
            if (healthMax < 20.0f || healthMax > 500.0f) healthMax = 100.0f;
            if (health > healthMax) health = healthMax;
        }

        // 7. Team filter:
        int32_t teamId = ds_pubg_read_i32(pawn + kDSPUBGCharacterTeamIDOffset);
        if (teamId < 0 || teamId > 200000000) return;
        if (localTeamId > 0 && teamId == localTeamId) {
            return;
        }

        // 8. Human skeletal mesh extent check:
        float extZ = ds_pubg_read_f32(meshComp + kDSPUBGMeshBoxExtentZOffset);
        if (extZ < 25.0f || extZ > 170.0f) {
            if (!psHint) return; // Non-human extents discard!
        }

        seenPawns.push_back(pawn);

        DSPUBGVector rootLoc = {};
        if (!ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc))) {
            return;
        }
        if (isnan(rootLoc.X) || isinf(rootLoc.X) || (fabsf(rootLoc.X) < 1.0f && fabsf(rootLoc.Y) < 1.0f)) {
            return;
        }

        uint64_t parent = ds_pubg_read_ptr(rootComp + kDSPUBGSceneCompAttachedParentOffset);
        if (parent && ds_pubg_valid(parent)) {
            DSPUBGVector parentLoc = {};
            if (ds_pubg_read(parent + kDSPUBGSceneCompRelativeLocOffset, &parentLoc, sizeof(parentLoc))) {
                rootLoc.X += parentLoc.X;
                rootLoc.Y += parentLoc.Y;
                rootLoc.Z += parentLoc.Z;
            }
        }

        float actorH = 175.0f;
        if (extZ >= 30.0f && extZ <= 160.0f) {
            actorH = extZ * 2.0f;
        }

        DSPUBGVector pos = rootLoc;
        float halfH = actorH * 0.5f;
        DSPUBGVector bot = pos; bot.Z -= halfH;
        DSPUBGVector top = pos; top.Z += halfH;

        float bx = 0, by = 0, bd = 0;
        float tx = 0, ty = 0, td = 0;
        bool okB = ds_pubg_cam_basis_project(basis, bot, bx, by, bd);
        bool okT = ds_pubg_cam_basis_project(basis, top, tx, ty, td);

        float sx = 0, sy = 0, dist = 0;
        if (!okB && !okT) {
            if (!ds_pubg_cam_basis_project(basis, pos, sx, sy, dist)) return;
        } else {
            dist = okB ? bd : td;
        }

        if (dist > g_dspubgMaxDistance) return;

        float topY = 0, bottomY = 0, boxH = 0, centerX = 0;
        if (okB && okT) {
            topY = fminf(ty, by);
            bottomY = fmaxf(ty, by);
            boxH = bottomY - topY;
            centerX = (tx + bx) * 0.5f;
        } else {
            float tz = dist * 100.0f;
            if (tz < 10.0f) tz = 10.0f;
            boxH = (actorH / tz) * basis.k;
            topY = sy - boxH * 0.5f;
            centerX = sx;
        }

        if (boxH < 8.0f) boxH = 8.0f;
        if (boxH > screenH * 2.0f) return;
        float boxW = boxH * 0.5f;
        float boxX = centerX - boxW * 0.5f;

        if (centerX + boxW * 0.5f < -60.0f || centerX - boxW * 0.5f > screenW + 60.0f ||
            topY > screenH + 60.0f || topY + boxH < -60.0f) {
            return;
        }

        bool isAI = knownBot;
        if (!isAI && ps && ds_pubg_valid(ps)) {
            uint8_t botByte = ds_pubg_read_u8(ps + kDSPUBGPlayerStateIsABotOffset);
            isAI = (botByte & 0x4) != 0;
        }
        if (!isAI) {
            isAI = (ds_pubg_read_u8(pawn + kDSPUBGCharacterIsAIOffset) != 0); // UAECharacter.bIsAI
        }

        DSPUBGProjectedPlayer p = {};
        p.screenX = boxX;
        p.screenY = topY;
        p.headX = centerX;
        p.headY = topY + boxH * 0.08f;
        p.boxWidth = boxW;
        p.boxHeight = boxH;
        p.distanceMeters = dist;
        p.health = health;
        p.healthMax = healthMax;
        p.teamId = teamId;
        p.isAI = isAI;
        p.isDead = false;
        p.isVisible = true;
        p.isVehicle = false;
        p.actorPtr = pawn;
        p.playerKey = ds_pubg_read_u32(pawn + kDSPUBGCharacterPlayerKeyOffset);

        if (!ds_pubg_read_fstring_nick(pawn + kDSPUBGCharacterPlayerNameOffset, p.name, sizeof(p.name))) {
            if (ps && ds_pubg_valid(ps)) {
                ds_pubg_read_fstring_nick(ps + kDSPUBGPlayerStatePlayerNameOffset, p.name, sizeof(p.name));
            }
        }
        if (p.name[0] == '\0') {
            strncpy(p.name, isAI ? "Bot" : "Enemy", sizeof(p.name) - 1);
        }

        // Humanoid Skeleton (16 joints, 15 bone links)
        // Perfectly proportioned and aligned with the enemy character's box and head
        p.hasSkeleton = false;
        if (g_pubgEspSkeleton && !p.isVehicle) {
            // Spine / Center line
            p.skeleton[0] = { centerX, topY + boxH * 0.08f, true }; // Head (matches head dot)
            p.skeleton[1] = { centerX, topY + boxH * 0.18f, true }; // Neck
            p.skeleton[2] = { centerX, topY + boxH * 0.35f, true }; // Chest
            p.skeleton[3] = { centerX, topY + boxH * 0.53f, true }; // Pelvis / Waist

            // Left Arm
            p.skeleton[4] = { centerX - boxW * 0.32f, topY + boxH * 0.20f, true }; // L Shoulder
            p.skeleton[5] = { centerX - boxW * 0.44f, topY + boxH * 0.36f, true }; // L Elbow
            p.skeleton[6] = { centerX - boxW * 0.38f, topY + boxH * 0.50f, true }; // L Hand

            // Right Arm
            p.skeleton[7] = { centerX + boxW * 0.32f, topY + boxH * 0.20f, true }; // R Shoulder
            p.skeleton[8] = { centerX + boxW * 0.44f, topY + boxH * 0.36f, true }; // R Elbow
            p.skeleton[9] = { centerX + boxW * 0.38f, topY + boxH * 0.50f, true }; // R Hand

            // Left Leg
            p.skeleton[10] = { centerX - boxW * 0.18f, topY + boxH * 0.55f, true }; // L Hip
            p.skeleton[11] = { centerX - boxW * 0.22f, topY + boxH * 0.75f, true }; // L Knee
            p.skeleton[12] = { centerX - boxW * 0.24f, topY + boxH * 0.98f, true }; // L Foot

            // Right Leg
            p.skeleton[13] = { centerX + boxW * 0.18f, topY + boxH * 0.55f, true }; // R Hip
            p.skeleton[14] = { centerX + boxW * 0.22f, topY + boxH * 0.75f, true }; // R Knee
            p.skeleton[15] = { centerX + boxW * 0.24f, topY + boxH * 0.98f, true }; // R Foot

            p.hasSkeleton = true;
        }

        if (publishedCount < kDSPUBGMaxPlayers) {
            staging[publishedCount++] = p;
            if (isAI) botCount++; else enemyCount++;
        }
    };

    // Source 1: GameState.PlayerArray
    uint64_t gameState = ds_pubg_read_ptr(world + kDSPUBGWorldGameStateOffset);
    if (!gameState) {
        uint64_t gm = ds_pubg_read_ptr(world + kDSPUBGWorldAuthorityGameModeOffset);
        if (gm) gameState = ds_pubg_read_ptr(gm + kDSPUBGGameModeGameStateOffset);
    }
    if (gameState) {
        uint64_t playerArrayData = ds_pubg_read_ptr(gameState + kDSPUBGGameStatePlayerArrayOffset);
        uint32_t playerCount = ds_pubg_read_u32(gameState + kDSPUBGGameStatePlayerArrayOffset + 8);
        if (playerArrayData && playerCount > 0) {
            if (playerCount > 128) playerCount = 128;
            std::vector<uint64_t> playerStates(playerCount, 0);
            if (ds_pubg_read(playerArrayData, playerStates.data(), playerCount * sizeof(uint64_t))) {
                for (uint32_t i = 0; i < playerCount; i++) {
                    uint64_t ps = playerStates[i];
                    if (!ps || !ds_pubg_valid(ps)) continue;
                    uint64_t pawn = ds_pubg_read_ptr(ps + kDSPUBGPlayerStatePawnPrivateOffset);
                    uint8_t botByte = ds_pubg_read_u8(ps + kDSPUBGPlayerStateIsABotOffset);
                    bool isBot = (botByte & 0x4) != 0;
                    if (pawn) {
                        processPawn(pawn, ps, isBot);
                    }
                }
            }
        }
    }

    // Source 2: PersistentLevel.ActorCluster.Actors & PersistentLevel.Actors
    if (level) {
        uint64_t cluster = ds_pubg_read_ptr(level + 0xE0ULL);
        uint64_t actorsData = 0;
        uint32_t actorsCount = 0;
        if (cluster) {
            actorsData = ds_pubg_read_ptr(cluster + 0x28ULL);
            actorsCount = ds_pubg_read_u32(cluster + 0x30ULL);
        }
        if (!actorsData || actorsCount == 0) {
            actorsData = ds_pubg_read_ptr(level + 0x98ULL);
            actorsCount = ds_pubg_read_u32(level + 0xA0ULL);
        }
        if (!actorsData || actorsCount == 0) {
            actorsData = ds_pubg_read_ptr(level + 0xA0ULL);
            actorsCount = ds_pubg_read_u32(level + 0xA8ULL);
        }
        g_dspubgLastActorsCount = (int)actorsCount;

        if (actorsData && actorsCount > 0) {
            if (actorsCount > 4096) actorsCount = 4096;
            std::vector<uint64_t> levelActors(actorsCount, 0);
            if (ds_pubg_read(actorsData, levelActors.data(), actorsCount * sizeof(uint64_t))) {
                for (uint32_t i = 0; i < actorsCount; i++) {
                    uint64_t actor = levelActors[i];
                    if (!actor || actor == localPawn || !ds_pubg_valid(actor)) continue;

                    // 1. Vehicle detection via VehicleCommon (0xC08)
                    uint64_t vehCommon = ds_pubg_read_ptr(actor + 0xC08ULL);
                    if (vehCommon && ds_pubg_valid(vehCommon)) {
                        uint8_t vehType = ds_pubg_read_u8(actor + 0x70CULL);
                        processVehicle(actor, vehCommon, vehType);
                        continue;
                    }

                    // 2. Character detection: Must have valid PlayerState (0x4D0) OR
                    // match UE4 ACharacter hierarchy (CapsuleComponent == RootComponent, CharacterMovement, Mesh)
                    uint64_t ps = ds_pubg_read_ptr(actor + 0x4D0ULL);
                    uint64_t rootComp = ds_pubg_read_ptr(actor + kDSPUBGActorRootComponentOffset);
                    if (!rootComp) rootComp = ds_pubg_read_ptr(actor + 0x180ULL);
                    uint64_t capsuleComp = ds_pubg_read_ptr(actor + kDSPUBGCharacterCapsuleOffset);
                    uint64_t moveComp = ds_pubg_read_ptr(actor + kDSPUBGCharacterMovementOffset);
                    uint64_t meshComp = ds_pubg_read_ptr(actor + kDSPUBGCharacterMeshOffset);

                    bool isChar = false;
                    if (ps && ds_pubg_valid(ps)) {
                        isChar = true;
                    } else if (rootComp && capsuleComp == rootComp && ds_pubg_valid(moveComp) && ds_pubg_valid(meshComp)) {
                        isChar = true;
                    }

                    if (isChar) {
                        processPawn(actor, ps, false);
                    }
                }
            }
        }
    }

    g_dspubgLastEnemyCount = enemyCount;
    g_dspubgLastBotCount = botCount;
    g_dspubgLastVehicleCount = vehicleCount;

    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    memcpy(g_dspubgPlayers, staging, publishedCount * sizeof(DSPUBGProjectedPlayer));
    g_dspubgPlayerCount = publishedCount;
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}
