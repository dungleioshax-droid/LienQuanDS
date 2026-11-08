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
static uint32_t g_dspubgLastBoneOff = 0;
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
    g_dspubgLastBoneOff = 0;
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
    if (isnan(world.X) || isinf(world.X) ||
        isnan(world.Y) || isinf(world.Y) ||
        isnan(world.Z) || isinf(world.Z)) return false;

    float dx = world.X - b.lx;
    float dy = world.Y - b.ly;
    float dz = world.Z - b.lz;

    float tx = dx * b.m10 + dy * b.m11 + dz * b.m12;
    float ty = dx * b.m20 + dy * b.m21 + dz * b.m22;
    float tz = dx * b.m00 + dy * b.m01 + dz * b.m02;

    if (isnan(tz) || isinf(tz) || tz < 10.0f) return false; // Behind or too close

    float distSq = dx * dx + dy * dy + dz * dz;
    if (isnan(distSq) || isinf(distSq) || distSq < 0.0f) return false;
    float distM = sqrtf(distSq) / 100.0f;

    float projX = b.cx + tx * b.k / tz;
    float projY = b.cy - ty * b.k / tz;
    if (isnan(projX) || isinf(projX) || isnan(projY) || isinf(projY)) return false;

    outX = projX;
    outY = projY;
    outDist = distM;
    return true;
}

// Standard UE4 humanoid rigs (head 6, neck 5, pelvis 1):
// Map D: Training Dummy rig (< 58 bones)
// Map G: Player & Bot rig (67 bones - ShadowTrackerExtra)
static const int kESPBoneMapD[15] = {
    6, 5, 1,          // Head, Neck, Pelvis
    12, 13, 14,       // UprR, LwrR, HandR
    8, 9, 10,         // UprL, LwrL, HandL
    19, 20, 21,       // ThighR, CalfR, FootR
    15, 16, 17        // ThighL, CalfL, FootL
};

static const int kESPBoneMapG[15] = {
    6, 5, 1,          // Head, Neck, Pelvis
    13, 15, 16,       // UprR, LwrR, HandR
    34, 36, 37,       // UprL, LwrL, HandL
    57, 58, 59,       // ThighR, CalfR, FootR (verified: 57=thigh_r, 58=calf_r, 59=foot_r)
    53, 54, 55        // ThighL, CalfL, FootL (verified: 53=thigh_l, 54=calf_l, 55=foot_l)
};

static bool ds_pubg_read_c2w(uint64_t meshComp, const DSPUBGVector &rootLoc, float halfH, uint8_t *outC2W) {
    if (!meshComp || !ds_pubg_valid(meshComp) || !outC2W) return false;
    // In UE4 64-bit arm64, USceneComponent RelativeScale3D is at 0x1FC (ends at 0x208).
    // FTransform is alignas(16), so ComponentToWorld is located at 0x210 (with 8B alignment padding at 0x208).
    // On packed/unaligned layouts, test 0x210, 0x208, 0x200, 0x220, 0x218.
    static const uint32_t kCandidates[] = { 0x210, 0x208, 0x200, 0x220, 0x218 };
    static uint32_t s_cachedC2WOff = 0;

    auto testCandidate = [&](uint32_t off) -> bool {
        uint8_t buf[48];
        if (!ds_pubg_read(meshComp + (uint64_t)off, buf, sizeof(buf))) return false;

        float qx = 0, qy = 0, qz = 0, qw = 1.0f;
        memcpy(&qx, buf + 0x0, 4);
        memcpy(&qy, buf + 0x4, 4);
        memcpy(&qz, buf + 0x8, 4);
        memcpy(&qw, buf + 0xC, 4);
        float qlen2 = qx * qx + qy * qy + qz * qz + qw * qw;
        if (isnan(qlen2) || isinf(qlen2) || qlen2 < 0.6f || qlen2 > 1.5f) return false;

        float tx = 0, ty = 0, tz = 0;
        memcpy(&tx, buf + 0x10, 4);
        memcpy(&ty, buf + 0x14, 4);
        memcpy(&tz, buf + 0x18, 4);
        if (isnan(tx) || isinf(tx) || isnan(ty) || isinf(ty) || isnan(tz) || isinf(tz)) return false;

        float dX = tx - rootLoc.X;
        float dY = ty - rootLoc.Y;
        if (dX * dX + dY * dY > (300.0f * 300.0f)) return false;

        float expectedZ = rootLoc.Z - halfH;
        if (fabsf(tz - expectedZ) > 250.0f && fabsf(tz - rootLoc.Z) > 250.0f) return false;

        float sx = 1.0f, sy = 1.0f, sz = 1.0f;
        memcpy(&sx, buf + 0x20, 4);
        memcpy(&sy, buf + 0x24, 4);
        memcpy(&sz, buf + 0x28, 4);
        if (isnan(sx) || isinf(sx) || sx < 0.2f || sx > 5.0f ||
            isnan(sy) || isinf(sy) || sy < 0.2f || sy > 5.0f ||
            isnan(sz) || isinf(sz) || sz < 0.2f || sz > 5.0f) return false;

        memcpy(outC2W, buf, 48);
        return true;
    };

    if (s_cachedC2WOff != 0 && testCandidate(s_cachedC2WOff)) {
        return true;
    }

    for (uint32_t off : kCandidates) {
        if (off == s_cachedC2WOff) continue;
        if (testCandidate(off)) {
            s_cachedC2WOff = off;
            return true;
        }
    }

    if (!ds_pubg_read(meshComp + 0x210ULL, outC2W, 48)) {
        ds_pubg_read(meshComp + 0x208ULL, outC2W, 48);
    }
    return false;
}

static void ds_pubg_bone_world_from_local(const uint8_t *c2w,
                                          const DSPUBGVector &rootLoc,
                                          float halfH,
                                          const DSPUBGRotator &actorRot,
                                          const DSPUBGVector *local,
                                          DSPUBGVector *out) {
    float qx = 0, qy = 0, qz = 0, qw = 1.0f;
    float tx = 0, ty = 0, tz = 0;
    float sx = 1.0f, sy = 1.0f, sz = 1.0f;
    if (c2w) {
        memcpy(&qx, c2w + 0x0, 4);
        memcpy(&qy, c2w + 0x4, 4);
        memcpy(&qz, c2w + 0x8, 4);
        memcpy(&qw, c2w + 0xC, 4);
        memcpy(&tx, c2w + 0x10, 4);
        memcpy(&ty, c2w + 0x14, 4);
        memcpy(&tz, c2w + 0x18, 4);
        memcpy(&sx, c2w + 0x20, 4);
        memcpy(&sy, c2w + 0x24, 4);
        memcpy(&sz, c2w + 0x28, 4);
    }

    if (isnan(sx) || isinf(sx) || sx < 0.01f || sx > 100.0f) sx = 1.0f;
    if (isnan(sy) || isinf(sy) || sy < 0.01f || sy > 100.0f) sy = 1.0f;
    if (isnan(sz) || isinf(sz) || sz < 0.01f || sz > 100.0f) sz = 1.0f;

    // Translation validation & anchoring:
    // In UE4 ACharacter, USkeletalMeshComponent origin is placed at the character feet:
    // (rootLoc.Z - halfH). Bone Z=0 is feet, Z≈85 is Pelvis, Z≈165 is Head.
    float meshOriginZ = rootLoc.Z - halfH;
    float dX = tx - rootLoc.X;
    float dY = ty - rootLoc.Y;
    float distSq = dX * dX + dY * dY;
    if (isnan(tx) || isinf(tx) || isnan(ty) || isinf(ty) || isnan(tz) || isinf(tz) ||
        (fabsf(tx) < 1.0f && fabsf(ty) < 1.0f) || distSq > (500.0f * 500.0f)) {
        tx = rootLoc.X;
        ty = rootLoc.Y;
        tz = meshOriginZ;
    } else {
        // If c2w translation Z is floating at waist (rootLoc.Z) rather than ground level (meshOriginZ),
        // adjust it down to meshOriginZ so bones don't float above enemy
        if (fabsf(tz - rootLoc.Z) < 30.0f && fabsf(tz - meshOriginZ) > 30.0f) {
            tz = meshOriginZ;
        }
    }

    // Rotation quaternion validation & fallback:
    float qlen2 = qx * qx + qy * qy + qz * qz + qw * qw;
    bool quatValid = (!isnan(qlen2) && !isinf(qlen2) && qlen2 >= 0.5f && qlen2 <= 2.0f);
    if (quatValid) {
        float qlen = sqrtf(qlen2);
        qx /= qlen; qy /= qlen; qz /= qlen; qw /= qlen;
    } else if (!isnan(actorRot.Yaw) && !isinf(actorRot.Yaw)) {
        // In UE4 Character, Mesh is attached with RelativeRotation(0, -90, 0),
        // so Mesh Yaw = ActorYaw - 90
        const float kPi = 3.141592653589793f;
        float radYaw = ((actorRot.Yaw - 90.0f) * kPi / 180.0f) * 0.5f;
        qx = 0.0f;
        qy = 0.0f;
        qz = sinf(radYaw);
        qw = cosf(radYaw);
    } else {
        qx = 0.0f; qy = 0.0f; qz = 0.0f; qw = 1.0f;
    }

    float vx = local->X * sx, vy = local->Y * sy, vz = local->Z * sz;
    float cx = qy * vz - qz * vy;
    float cy = qz * vx - qx * vz;
    float cz = qx * vy - qy * vx;
    float ux = 2.0f * (cx + qw * vx);
    float uy = 2.0f * (cy + qw * vy);
    float uz = 2.0f * (cz + qw * vz);

    out->X = vx + (qy * uz - qz * uy) + tx;
    out->Y = vy + (qz * ux - qx * uz) + ty;
    out->Z = vz + (qx * uy - qy * ux) + tz;
}

// Dynamically locates live ComponentSpaceTransforms TArray<FTransform> on USkeletalMeshComponent.
// Tests verified double buffer offsets (0xA30/0xA40), eval-context (0xE18/0xE28), cached (0xCE0/0xCD0),
// and bone-space (0xC98).
static bool ds_pubg_find_bone_array(uint64_t meshComp, uint64_t *outData, uint32_t *outCount, uint32_t *outOffset) {
    if (!meshComp || !ds_pubg_valid(meshComp)) return false;

    auto testOffset = [&](uint32_t off) -> bool {
        uint8_t hdr[16] = {0};
        if (!ds_pubg_read(meshComp + (uint64_t)off, hdr, sizeof(hdr))) return false;
        uint64_t d = 0;
        uint32_t c = 0, maxc = 0;
        memcpy(&d, hdr, 8);
        memcpy(&c, hdr + 8, 4);
        memcpy(&maxc, hdr + 12, 4);
        d &= 0x0000FFFFFFFFFFFFULL;
        if (!ds_pubg_valid(d) || (d & 0x7ULL) != 0) return false;
        if (c < 20 || c > 800 || maxc < c || maxc > 2000) return false;
        if (outData) *outData = d;
        if (outCount) *outCount = c;
        if (outOffset) *outOffset = off;
        return true;
    };

    // 1. Double buffer ComponentSpaceTransformsArray[2] (0xA30 / 0xA40)
    // Check CurrentRead index (0xA74 / 0xA78) per-mesh to ensure live pose (crouching/aiming) is never stale
    int32_t rd = ds_pubg_read_i32(meshComp + 0xA74ULL);
    if (rd != 0 && rd != 1) rd = ds_pubg_read_i32(meshComp + 0xA78ULL);
    uint32_t first = (rd == 1) ? 0xA40 : 0xA30;
    uint32_t second = (rd == 1) ? 0xA30 : 0xA40;

    if (testOffset(first)) return true;
    if (testOffset(second)) return true;

    // 2. Live transforms eval-context (0xE18 / 0xE28)
    if (testOffset(0xE18)) return true;
    if (testOffset(0xE28)) return true;

    // 3. CachedComponentSpaceTransforms (0xCE0)
    if (testOffset(0xCE0)) return true;

    return false;
}

static const char *ds_pubg_weapon_name_by_id(int32_t id) {
    switch (id) {
        // Assault Rifles
        case 101001: return "AKM";
        case 101002: return "M16A4";
        case 101003: return "SCAR-L";
        case 101004: return "M416";
        case 101005: return "Groza";
        case 101006: return "AUG";
        case 101007: return "QBZ";
        case 101008: return "M762";
        case 101009: return "Mk47";
        case 101010: return "G36C";
        case 101011: return "FAMAS";
        case 101012: return "ACE32";
        case 101013: return "HoneyBadger";

        // SMGs
        case 102001: return "UZI";
        case 102002: return "UMP45";
        case 102003: return "Vector";
        case 102004: return "Tommy";
        case 102005: return "Bizon";
        case 102007: return "P90";
        case 102008: return "MP5K";

        // Sniper & DMR
        case 103001: return "Kar98k";
        case 103002: return "M24";
        case 103003: return "AWM";
        case 103004: return "SKS";
        case 103005: return "VSS";
        case 103006: return "Mini14";
        case 103007: return "Mk14";
        case 103008: return "Win94";
        case 103009: return "SLR";
        case 103010: return "QBU";
        case 103011: return "Mosin";
        case 103012: return "AMR";
        case 103013: return "Lynx AMR";

        // Shotguns
        case 104001: return "S686";
        case 104002: return "S1897";
        case 104003: return "S12K";
        case 104004: return "DBS";
        case 104005: return "M1014";

        // LMGs
        case 105001: return "M249";
        case 105002: return "DP-28";
        case 105003: return "MG3";

        // Pistols
        case 106001: return "P92";
        case 106002: return "P1911";
        case 106003: return "R1895";
        case 106004: return "P18C";
        case 106005: return "R45";
        case 106006: return "SawedOff";
        case 106008: return "Skorpion";
        case 106010: return "Deagle";

        // Others / Melee
        case 107001: return "Crossbow";
        case 108001: return "Pan";
        case 108002: return "Crowbar";
        case 108003: return "Machete";
        case 108004: return "Sickle";

        // Throwables / Grenades
        case 601001: return "Frag Grenade";
        case 601002: return "Smoke Grenade";
        case 601003: return "Molotov";
        case 601004: return "Stun Grenade";
        case 601005: return "Grenade";
        case 602001: return "Smoke Grenade";
        case 602002: return "Frag Grenade";
        case 602003: return "Molotov";
        case 602004: return "Stun Grenade";
        default: return NULL;
    }
}

static int32_t ds_pubg_read_equipped_weapon_id(uint64_t pawn) {
    if (!pawn || !ds_pubg_valid(pawn)) return 0;

    auto isValidWeaponId = [](int32_t wid) -> bool {
        return (wid >= 101001 && wid <= 108999) || (wid >= 601001 && wid <= 603999);
    };

    auto extractWeaponIdFromActor = [&](uint64_t weapon) -> int32_t {
        if (!weapon || !ds_pubg_valid(weapon)) return 0;

        // 1. WeaponCfg.KeyID (0x798 on ASTExtraWeapon)
        int32_t wid = ds_pubg_read_i32(weapon + 0x798ULL);
        if (isValidWeaponId(wid)) return wid;

        // 2. OwnerClientCreateWeaponData.ID.TypeSpecificID (0x68C on ASTExtraWeapon: 0x670 + 0x18 + 0x4)
        wid = ds_pubg_read_i32(weapon + 0x68CULL);
        if (isValidWeaponId(wid)) return wid;

        // 3. WeaponEntityComp (0x868) -> WeaponId (0x1E0 on UWeaponEntity)
        uint64_t wepEntity = ds_pubg_read_ptr(weapon + 0x868ULL);
        if (wepEntity && ds_pubg_valid(wepEntity)) {
            wid = ds_pubg_read_i32(wepEntity + 0x1E0ULL);
            if (isValidWeaponId(wid)) return wid;
        }

        // 4. ShootID (0xCBC on ASTExtraShootWeapon)
        wid = ds_pubg_read_i32(weapon + 0xCBCULL);
        if (isValidWeaponId(wid)) return wid;

        // 5. Standard heuristic offsets on weapon
        static const uint64_t idOffsets[] = { 0x74ULL, 0x1E0ULL, 0x200ULL, 0x220ULL, 0x238ULL, 0x280ULL };
        for (uint64_t idOff : idOffsets) {
            wid = ds_pubg_read_i32(weapon + idOff);
            if (isValidWeaponId(wid)) return wid;
        }
        return 0;
    };

    // Step 1: Check WeaponManagerComponent on pawn
    // Offsets on ASTExtraBaseCharacter: 0x2628 (primary dump), 0x25B8, 0x15B8, 0x2600, 0x2618, 0x2620, 0x2630
    static const uint64_t wmOffsets[] = { 0x2628ULL, 0x25B8ULL, 0x15B8ULL, 0x2600ULL, 0x2618ULL, 0x2620ULL, 0x2630ULL };
    for (uint64_t wmOff : wmOffsets) {
        uint64_t wm = ds_pubg_read_ptr(pawn + wmOff);
        if (!wm || !ds_pubg_valid(wm)) continue;

        // Check active / held weapons:
        // CurrentWeaponReplicated (0x5E8), CurrentWeaponSimulate (0x5F8), TemporaryWeaponReplicated (0x5F0), CurrentShield (0x600, 0x608)
        static const uint64_t cwOffsets[] = { 0x5E8ULL, 0x5F8ULL, 0x5F0ULL, 0x600ULL, 0x608ULL };
        for (uint64_t cwOff : cwOffsets) {
            uint64_t w = ds_pubg_read_ptr(wm + cwOff);
            if (w && ds_pubg_valid(w)) {
                int32_t wid = extractWeaponIdFromActor(w);
                if (wid > 0) return wid;
            }
        }

        // If held weapon pointer was temporarily null during switch, check active socket:
        // CurUseWeaponLogicSocketRep: 1=Slot1, 2=Slot2, 3=SubSlot, 4=MeleeSlot
        uint8_t curSlot = ds_pubg_read_u8(wm + 0x320ULL);
        if (curSlot >= 1 && curSlot <= 4) {
            uint64_t slotOff = 0;
            if (curSlot == 1) slotOff = 0x4C8ULL;
            else if (curSlot == 2) slotOff = 0x500ULL;
            else if (curSlot == 3) slotOff = 0x538ULL;
            else if (curSlot == 4) slotOff = 0x570ULL;

            if (slotOff != 0) {
                // Check TargetWeapon at slot + 0x0
                uint64_t w = ds_pubg_read_ptr(wm + slotOff);
                if (w && ds_pubg_valid(w)) {
                    int32_t wid = extractWeaponIdFromActor(w);
                    if (wid > 0) return wid;
                }
                // Check ID.TypeSpecificID at slot + 0x1C (0x18 + 0x4)
                int32_t slotWid = ds_pubg_read_i32(wm + slotOff + 0x1CULL);
                if (isValidWeaponId(slotWid)) return slotWid;
            }
        } else if (curSlot == 0) {
            // curSlot == 0 (SWPS_None) explicitly means Unarmed (tay không)
            return 0;
        }
    }

    // Step 2: Check CurrentReloadWeapon on ASTExtraBaseCharacter (0x3220ULL)
    uint64_t reloadWep = ds_pubg_read_ptr(pawn + 0x3220ULL);
    if (reloadWep && ds_pubg_valid(reloadWep)) {
        int32_t wid = extractWeaponIdFromActor(reloadWep);
        if (wid > 0) return wid;
    }

    // Step 3: Check fallback direct weapon pointers on pawn
    static const uint64_t directWeaponOffsets[] = {
        0x2AF4ULL, 0x2A84ULL, 0x2B00ULL, 0x2A70ULL, 0x2B10ULL, 0x2AA0ULL, 0x21F0ULL, 0x1A00ULL
    };
    for (uint64_t off : directWeaponOffsets) {
        uint64_t w = ds_pubg_read_ptr(pawn + off);
        if (w && ds_pubg_valid(w)) {
            int32_t wid = extractWeaponIdFromActor(w);
            if (wid > 0) return wid;
        }
    }

    return 0;
}

static int g_dspubgTotalEnemies = 0;
static int g_dspubgTotalBots = 0;

static void ds_pubg_get_total_counts(int *outEnemies, int *outBots) {
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    if (outEnemies) *outEnemies = g_dspubgTotalEnemies;
    if (outBots) *outBots = g_dspubgTotalBots;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
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
    g_dspubgTotalEnemies = 0;
    g_dspubgTotalBots = 0;
    memset(g_dspubgPlayers, 0, sizeof(g_dspubgPlayers));
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}

// Ported from DarkPubg DecryptActorsArray (port logic of QBL __ZN...DecryptActorsArrayEyyi)
// Resolves ULevel Actors array: plain at 0xA0 or encrypted at 0x448
static uint64_t ds_pubg_decrypt_actors_array(uint64_t uLevel) {
    if (!ds_pubg_valid(uLevel)) return 0;

    // 1) Level + 0xA0: Plain TArray
    uint64_t vPlain = ds_pubg_read_ptr(uLevel + 0xA0ULL);
    if (vPlain > 0 && ds_pubg_valid(vPlain)) {
        return uLevel + 0xA0ULL;
    }

    // 2) Level + 0x448: Encrypted TArray (if already plain pointer)
    uint64_t vEnc = ds_pubg_read_ptr(uLevel + 0x448ULL);
    if (vEnc > 0 && ds_pubg_valid(vEnc)) {
        return uLevel + 0x448ULL;
    }

    // 3) Read 0x20 bytes (4 uint64_t) at 0x448 + 0x10
    uint64_t enc[4] = {0, 0, 0, 0};
    if (!ds_pubg_read(uLevel + 0x448ULL + 0x10ULL, enc, sizeof(enc))) {
        return 0;
    }

    // Branch 1: enc[0] table of 8 offsets + 8 scattered bytes
    if (enc[0] > 0) {
        if (!ds_pubg_valid(enc[0])) return 0;
        uint32_t vals[8] = {0};
        if (!ds_pubg_read(enc[0] + 0x80ULL, vals, sizeof(vals))) {
            return 0;
        }
        uint64_t r = 0;
        for (int i = 0; i < 8; i++) {
            uint64_t addr = enc[0] + (uint64_t)vals[i];
            if (addr < enc[0] || !ds_pubg_valid(addr)) {
                return 0;
            }
            uint8_t b = ds_pubg_read_u8(addr);
            r |= ((uint64_t)b) << (8 * i);
        }
        if (ds_pubg_valid(r)) return r;
        return 0;
    }

    // Branch 2: enc[1] subtract 4 per byte
    if (enc[1] > 0) {
        if (!ds_pubg_valid(enc[1])) return 0;
        uint64_t ea = ds_pubg_read_ptr(enc[1]);
        if (ea) {
            uint64_t r = 0;
            for (int i = 0; i < 8; i++) {
                uint8_t b = (uint8_t)(ea >> (8 * i));
                r |= ((uint64_t)(uint8_t)(b - 4)) << (8 * i);
            }
            if (ds_pubg_valid(r)) return r;
        }
        return 0;
    }

    // Branch 3: enc[2] ror 56 (rotate left 8)
    if (enc[2] > 0) {
        if (!ds_pubg_valid(enc[2])) return 0;
        uint64_t ea = ds_pubg_read_ptr(enc[2]);
        if (ea) {
            uint64_t r = (ea >> 56) | (ea << 8);
            if (ds_pubg_valid(r)) return r;
        }
        return 0;
    }

    // Branch 4: enc[3] XOR with 0xCDCD00
    if (enc[3] > 0) {
        if (!ds_pubg_valid(enc[3])) return 0;
        uint64_t ea = ds_pubg_read_ptr(enc[3]);
        if (ea) {
            uint64_t r = ea ^ 0xCDCD00ULL;
            if (ds_pubg_valid(r)) return r;
        }
        return 0;
    }

    return 0;
}

static bool ds_pubg_actors_array_at(uint64_t arr, uint64_t *outData, uint32_t *outCount) {
    if (!ds_pubg_valid(arr)) return false;
    uint64_t data = ds_pubg_read_ptr(arr + 0x0ULL);
    uint32_t count = ds_pubg_read_u32(arr + 0x8ULL);
    if (count > 20000) return false;
    if (count > 0 && !ds_pubg_valid(data)) return false;
    if (outData) *outData = data;
    if (outCount) *outCount = count;
    return true;
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
    if (g_dspubgLastEnemyCount > 0 || g_dspubgLastBotCount > 0) {
        if (g_dspubgLastBoneOff) {
            snprintf(g_dspubgStatusBuf, sizeof(g_dspubgStatusBuf),
                     "PUBG: %d Enemies | %d Bots [B:0x%X]",
                     g_dspubgLastEnemyCount, g_dspubgLastBotCount, g_dspubgLastBoneOff);
        } else {
            snprintf(g_dspubgStatusBuf, sizeof(g_dspubgStatusBuf),
                     "PUBG: %d Enemies | %d Bots",
                     g_dspubgLastEnemyCount, g_dspubgLastBotCount);
        }
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
    int total360EnemyCount = 0;
    int total360BotCount = 0;
    std::vector<uint64_t> seenPawns;

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

        // 4. Must have valid RootComponent and Mesh (standard UE4 character)
        uint64_t rootComp = ds_pubg_read_ptr(pawn + kDSPUBGActorRootComponentOffset);
        if (!rootComp) rootComp = ds_pubg_read_ptr(pawn + 0x180ULL);
        if (!rootComp || !ds_pubg_valid(rootComp)) return;

        uint64_t meshComp = ds_pubg_read_ptr(pawn + kDSPUBGCharacterMeshOffset);
        if (!meshComp || !ds_pubg_valid(meshComp)) return;

        // 5. Health check (same robust heuristic as DarkPubg):
        float health = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthOffset);
        float healthMax = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthMaxOffset);
        if (isnan(health) || isinf(health) || isnan(healthMax) || isinf(healthMax)) return;

        if (!psHint) {
            if (healthMax < 50.0f || healthMax > 2000.0f) return;
            if (health < 0.0f || health > healthMax + 50.0f) return;
        } else {
            if (healthMax < 20.0f || healthMax > 2000.0f) healthMax = 100.0f;
            if (health < 0.0f) health = 0.0f;
            if (health > healthMax) health = healthMax;
        }

        bool isKnocked = false;
        float groggyHealth = ds_pubg_read_f32(pawn + 0xE68ULL);
        if (!isnan(groggyHealth) && !isinf(groggyHealth) && groggyHealth > 0.0f && groggyHealth <= 100.0f && health <= 0.0f) {
            health = groggyHealth;
            isKnocked = true;
        }

        // 6. Team filter:
        int32_t teamId = ds_pubg_read_i32(pawn + kDSPUBGCharacterTeamIDOffset);
        if (teamId < 0 || teamId > 200000000) return;
        if (localTeamId > 0 && teamId == localTeamId) {
            return;
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

        DSPUBGRotator actorRot = {};
        if (!ds_pubg_read(rootComp + 0x1F0ULL, &actorRot, sizeof(actorRot)) ||
            isnan(actorRot.Yaw) || isinf(actorRot.Yaw) || (actorRot.Pitch == 0.0f && actorRot.Yaw == 0.0f && actorRot.Roll == 0.0f)) {
            ds_pubg_read(pawn + 0x134ULL, &actorRot, sizeof(actorRot));
        }

        // 3D Euclidean distance in meters from camera to actor:
        float dx = rootLoc.X - basis.lx;
        float dy = rootLoc.Y - basis.ly;
        float dz = rootLoc.Z - basis.lz;
        float dist3D = sqrtf(dx * dx + dy * dy + dz * dz) * 0.01f;
        if (isnan(dist3D) || isinf(dist3D) || dist3D > g_dspubgMaxDistance) {
            return;
        }

        uint64_t ps = psHint ? psHint : ds_pubg_read_ptr(pawn + 0x4D0ULL);
        bool isAI = knownBot;
        if (!isAI && ps && ds_pubg_valid(ps)) {
            uint8_t botByte = ds_pubg_read_u8(ps + kDSPUBGPlayerStateIsABotOffset);
            isAI = (botByte & 0x4) != 0;
        }
        if (!isAI) {
            isAI = (ds_pubg_read_u8(pawn + kDSPUBGCharacterIsAIOffset) != 0); // UAECharacter.bIsAI
        }

        // 360-Degree Radar Enemy & Bot Counter (independent of camera viewport)
        if (isAI) {
            total360BotCount++;
        } else {
            total360EnemyCount++;
        }

        // Camera-relative coordinates for 3D arrow indicator & projection:
        float camRelX = dx * basis.m10 + dy * basis.m11 + dz * basis.m12; // Camera Right
        float camRelY = dx * basis.m20 + dy * basis.m21 + dz * basis.m22; // Camera Up
        float camRelZ = dx * basis.m00 + dy * basis.m01 + dz * basis.m02; // Camera Forward

        DSPUBGProjectedPlayer p = {};
        p.distanceMeters = dist3D;
        p.health = health;
        p.healthMax = (healthMax >= 20.0f) ? healthMax : 100.0f;
        p.teamId = teamId;
        p.isAI = isAI;
        p.isDead = false;
        p.isKnocked = isKnocked;
        p.isVisible = false;
        p.isVehicle = false;
        p.actorPtr = pawn;
        p.playerKey = ds_pubg_read_u32(pawn + kDSPUBGCharacterPlayerKeyOffset);
        p.camRelX = camRelX;
        p.camRelY = camRelY;
        p.camRelZ = camRelZ;

        bool onScreen = false;
        float boxX = 0, boxY = 0, boxW = 0, boxH = 0, centerX = 0, topY = 0;
        float halfH = 87.5f;

        if (camRelZ > 10.0f) {
            float extZ = ds_pubg_read_f32(meshComp + kDSPUBGMeshBoxExtentZOffset);
            float actorH = 175.0f;
            if (extZ >= 30.0f && extZ <= 160.0f) {
                actorH = extZ * 2.0f;
            }

            DSPUBGVector pos = rootLoc;
            halfH = actorH * 0.5f;
            DSPUBGVector bot = pos; bot.Z -= halfH;
            DSPUBGVector top = pos; top.Z += halfH;

            float bx = 0, by = 0, bd = 0;
            float tx = 0, ty = 0, td = 0;
            bool okB = ds_pubg_cam_basis_project(basis, bot, bx, by, bd);
            bool okT = ds_pubg_cam_basis_project(basis, top, tx, ty, td);

            float sx = 0, sy = 0, dist = dist3D;
            bool hasProj = false;
            if (okB || okT) {
                hasProj = true;
                dist = okB ? bd : td;
            } else if (ds_pubg_cam_basis_project(basis, pos, sx, sy, dist)) {
                hasProj = true;
            }

            if (hasProj) {
                float bottomY = 0;
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
                    bottomY = topY + boxH;
                }

                if (boxH < 8.0f) boxH = 8.0f;
                if (boxH <= screenH * 2.0f) {
                    boxW = boxH * 0.5f;
                    boxX = centerX - boxW * 0.5f;
                    boxY = topY;

                    // Visible if inside screen bounds
                    if (centerX + boxW * 0.5f >= 0.0f && centerX - boxW * 0.5f <= screenW &&
                        topY + boxH >= 0.0f && topY <= screenH) {
                        onScreen = true;
                        p.screenX = boxX;
                        p.screenY = topY;
                        p.headX = centerX;
                        p.headY = topY + boxH * 0.08f;
                        p.boxWidth = boxW;
                        p.boxHeight = boxH;
                        p.distanceMeters = dist;
                        p.isVisible = true;
                    }
                }
            }
        }

        if (onScreen) {
            int32_t wid = ds_pubg_read_equipped_weapon_id(pawn);
            if (wid > 0) {
                const char *wName = ds_pubg_weapon_name_by_id(wid);
                if (wName) {
                    strncpy(p.weaponName, wName, sizeof(p.weaponName) - 1);
                } else {
                    snprintf(p.weaponName, sizeof(p.weaponName), "Gun %d", wid);
                }
            }

            if (!ds_pubg_read_fstring_nick(pawn + kDSPUBGCharacterPlayerNameOffset, p.name, sizeof(p.name))) {
                if (ps && ds_pubg_valid(ps)) {
                    ds_pubg_read_fstring_nick(ps + kDSPUBGPlayerStatePlayerNameOffset, p.name, sizeof(p.name));
                }
            }
            if (p.name[0] == '\0') {
                strncpy(p.name, isAI ? "Bot" : "Enemy", sizeof(p.name) - 1);
            }

            // Real Skeletal Bones (16 joints, 15 bone links)
            p.hasSkeleton = false;
        if (g_pubgEspSkeleton) {
            bool skeletonDone = false;
            uint64_t boneData = 0;
            if (meshComp && ds_pubg_valid(meshComp)) {
                uint32_t bCount = 0;
                uint32_t resolvedOff = 0;
                if (ds_pubg_find_bone_array(meshComp, &boneData, &bCount, &resolvedOff) && boneData && bCount >= 20) {
                    g_dspubgLastBoneOff = resolvedOff;

                    uint8_t boneBuf[256 * 48];
                    uint32_t needReadCount = (bCount > 256) ? 256 : bCount;
                    size_t readSize = (size_t)needReadCount * 48;
                    if (ds_pubg_read(boneData, boneBuf, readSize)) {
                        auto getBoneLocal = [&](int idx, DSPUBGVector &outV) -> bool {
                            if (idx < 0 || idx >= (int)needReadCount) return false;
                            const uint8_t *boneEntry = boneBuf + (size_t)idx * 48;
                            memcpy(&outV.X, boneEntry + 0x10, 4);
                            memcpy(&outV.Y, boneEntry + 0x14, 4);
                            memcpy(&outV.Z, boneEntry + 0x18, 4);
                            if (isnan(outV.X) || isinf(outV.X) || isnan(outV.Y) || isinf(outV.Y) || isnan(outV.Z) || isinf(outV.Z)) return false;
                            // Reject uninitialized zero bones which otherwise project to feet/root causing ghost lines
                            if (fabsf(outV.X) + fabsf(outV.Y) + fabsf(outV.Z) < 0.1f) return false;
                            if (fabsf(outV.X) > 400.0f || fabsf(outV.Y) > 400.0f || fabsf(outV.Z) > 400.0f) return false;
                            return true;
                        };

                        auto dist3D = [](const DSPUBGVector &a, const DSPUBGVector &b) -> float {
                            float dx = a.X - b.X, dy = a.Y - b.Y, dz = a.Z - b.Z;
                            return sqrtf(dx * dx + dy * dy + dz * dz);
                        };

                        int bHead = 6, bNeck = 5, bPelvis = 1;
                        int bUprR = -1, bLwrR = -1, bHandR = -1;
                        int bUprL = -1, bLwrL = -1, bHandL = -1;
                        int bThighR = -1, bCalfR = -1, bFootR = -1;
                        int bThighL = -1, bCalfL = -1, bFootL = -1;

                        if (needReadCount < 35) {
                            // Training dummy rig (< 35 bones, typically ~22)
                            bHead = 6; bNeck = 5; bPelvis = 1;
                            DSPUBGVector armA = {}, armB = {};
                            getBoneLocal(12, armA);
                            getBoneLocal(8, armB);
                            if (armA.Y >= armB.Y) {
                                bUprR = 12; bLwrR = 13; bHandR = 14;
                                bUprL = 8;  bLwrL = 9;  bHandL = 10;
                            } else {
                                bUprR = 8;  bLwrR = 9;  bHandR = 10;
                                bUprL = 12; bLwrL = 13; bHandL = 14;
                            }

                            DSPUBGVector legA = {}, legB = {};
                            getBoneLocal(19, legA);
                            getBoneLocal(15, legB);
                            if (legA.Y >= legB.Y) {
                                bThighR = 19; bCalfR = 20; bFootR = 21;
                                bThighL = 15; bCalfL = 16; bFootL = 17;
                            } else {
                                bThighR = 15; bCalfR = 16; bFootR = 17;
                                bThighL = 19; bCalfL = 20; bFootL = 21;
                            }
                        } else {
                            // Player & Bot rig (67 bones - ShadowTrackerExtra)
                            bHead = 6; bNeck = 5; bPelvis = 1;

                            // Right Arm Selection:
                            // Bone 14 is lowerarm_r (true elbow), 15 is lowerarm_twist_01_r
                            // Bone 12 is upperarm_r (true shoulder), 13 is upperarm_twist_01_r
                            // Bone 16 is hand_r
                            bHandR = 16;
                            DSPUBGVector vHandR = {};
                            bool hasHandR = getBoneLocal(16, vHandR);

                            bLwrR = 14;
                            DSPUBGVector vElbowR = {};
                            DSPUBGVector v14 = {}, v15 = {};
                            bool ok14 = getBoneLocal(14, v14);
                            bool ok15 = getBoneLocal(15, v15);
                            if (hasHandR) {
                                float d14 = ok14 ? dist3D(v14, vHandR) : 999.0f;
                                float d15 = ok15 ? dist3D(v15, vHandR) : 999.0f;
                                if (ok14 && d14 >= 15.0f && d14 <= 45.0f) {
                                    bLwrR = 14; vElbowR = v14;
                                } else if (ok15 && d15 >= 12.0f && d15 <= 45.0f) {
                                    bLwrR = 15; vElbowR = v15;
                                } else if (ok14) {
                                    bLwrR = 14; vElbowR = v14;
                                } else if (ok15) {
                                    bLwrR = 15; vElbowR = v15;
                                }
                            } else {
                                if (ok14) { bLwrR = 14; vElbowR = v14; }
                                else if (ok15) { bLwrR = 15; vElbowR = v15; }
                            }

                            bUprR = 12;
                            DSPUBGVector v12 = {}, v13 = {};
                            bool ok12 = getBoneLocal(12, v12);
                            bool ok13 = getBoneLocal(13, v13);
                            if (vElbowR.Z != 0.0f) {
                                float d12 = ok12 ? dist3D(v12, vElbowR) : 999.0f;
                                float d13 = ok13 ? dist3D(v13, vElbowR) : 999.0f;
                                if (ok12 && d12 >= 15.0f && d12 <= 55.0f) {
                                    bUprR = 12;
                                } else if (ok13 && d13 >= 12.0f && d13 <= 55.0f) {
                                    bUprR = 13;
                                } else if (ok12) {
                                    bUprR = 12;
                                } else if (ok13) {
                                    bUprR = 13;
                                }
                            } else {
                                if (ok12) bUprR = 12; else if (ok13) bUprR = 13;
                            }

                            // Left Arm Selection:
                            // Bone 35 is lowerarm_l (true elbow), 36 is lowerarm_twist_01_l
                            // Bone 33 is upperarm_l (true shoulder), 34 is upperarm_twist_01_l
                            // Bone 37 is hand_l
                            bHandL = 37;
                            DSPUBGVector vHandL = {};
                            bool hasHandL = getBoneLocal(37, vHandL);

                            bLwrL = 35;
                            DSPUBGVector vElbowL = {};
                            DSPUBGVector v35 = {}, v36 = {};
                            bool ok35 = getBoneLocal(35, v35);
                            bool ok36 = getBoneLocal(36, v36);
                            if (hasHandL) {
                                float d35 = ok35 ? dist3D(v35, vHandL) : 999.0f;
                                float d36 = ok36 ? dist3D(v36, vHandL) : 999.0f;
                                if (ok35 && d35 >= 15.0f && d35 <= 45.0f) {
                                    bLwrL = 35; vElbowL = v35;
                                } else if (ok36 && d36 >= 12.0f && d36 <= 45.0f) {
                                    bLwrL = 36; vElbowL = v36;
                                } else if (ok35) {
                                    bLwrL = 35; vElbowL = v35;
                                } else if (ok36) {
                                    bLwrL = 36; vElbowL = v36;
                                }
                            } else {
                                if (ok35) { bLwrL = 35; vElbowL = v35; }
                                else if (ok36) { bLwrL = 36; vElbowL = v36; }
                            }

                            bUprL = 33;
                            DSPUBGVector v33 = {}, v34 = {};
                            bool ok33 = getBoneLocal(33, v33);
                            bool ok34 = getBoneLocal(34, v34);
                            if (vElbowL.Z != 0.0f) {
                                float d33 = ok33 ? dist3D(v33, vElbowL) : 999.0f;
                                float d34 = ok34 ? dist3D(v34, vElbowL) : 999.0f;
                                if (ok33 && d33 >= 15.0f && d33 <= 55.0f) {
                                    bUprL = 33;
                                } else if (ok34 && d34 >= 12.0f && d34 <= 55.0f) {
                                    bUprL = 34;
                                } else if (ok33) {
                                    bUprL = 33;
                                } else if (ok34) {
                                    bUprL = 34;
                                }
                            } else {
                                if (ok33) bUprL = 33; else if (ok34) bUprL = 34;
                            }

                            // Dynamic Leg Selection with anatomical validation:
                            // Candidate 1: Right={55, 56, 57}, Left={59, 60, 61}
                            // Candidate 2: Right={57, 58, 59}, Left={53, 54, 55}
                            bThighR = 55; bCalfR = 56; bFootR = 57;
                            bThighL = 59; bCalfL = 60; bFootL = 61;

                            DSPUBGVector rT1 = {}, rC1 = {}, rF1 = {};
                            DSPUBGVector lT1 = {}, lC1 = {}, lF1 = {};
                            bool okR1 = getBoneLocal(55, rT1) && getBoneLocal(56, rC1) && getBoneLocal(57, rF1);
                            bool okL1 = getBoneLocal(59, lT1) && getBoneLocal(60, lC1) && getBoneLocal(61, lF1);

                            DSPUBGVector rT2 = {}, rC2 = {}, rF2 = {};
                            DSPUBGVector lT2 = {}, lC2 = {}, lF2 = {};
                            bool okR2 = getBoneLocal(57, rT2) && getBoneLocal(58, rC2) && getBoneLocal(59, rF2);
                            bool okL2 = getBoneLocal(53, lT2) && getBoneLocal(54, lC2) && getBoneLocal(55, lF2);

                            int score1 = 0, score2 = 0;
                            if (okR1) {
                                float dt = dist3D(rT1, rC1), dc = dist3D(rC1, rF1);
                                if (dt >= 20.0f && dt <= 75.0f && dc >= 20.0f && dc <= 75.0f) score1 += 2;
                            }
                            if (okL1) {
                                float dt = dist3D(lT1, lC1), dc = dist3D(lC1, lF1);
                                if (dt >= 20.0f && dt <= 75.0f && dc >= 20.0f && dc <= 75.0f) score1 += 2;
                            }
                            if (okR2) {
                                float dt = dist3D(rT2, rC2), dc = dist3D(rC2, rF2);
                                if (dt >= 20.0f && dt <= 75.0f && dc >= 20.0f && dc <= 75.0f) score2 += 2;
                            }
                            if (okL2) {
                                float dt = dist3D(lT2, lC2), dc = dist3D(lC2, lF2);
                                if (dt >= 20.0f && dt <= 75.0f && dc >= 20.0f && dc <= 75.0f) score2 += 2;
                            }

                            if (score2 > score1) {
                                bThighR = 57; bCalfR = 58; bFootR = 59;
                                bThighL = 53; bCalfL = 54; bFootL = 55;
                            } else {
                                bThighR = 55; bCalfR = 56; bFootR = 57;
                                bThighL = 59; bCalfL = 60; bFootL = 61;
                            }
                        }

                        const int jointIndices[15] = {
                            bHead, bNeck, bPelvis,
                            bUprR, bLwrR, bHandR,
                            bUprL, bLwrL, bHandL,
                            bThighR, bCalfR, bFootR,
                            bThighL, bCalfL, bFootL
                        };

                        DSPUBGVector locals[15] = {};
                        bool localsValid[15] = {};
                        for (int i = 0; i < 15; i++) {
                            localsValid[i] = getBoneLocal(jointIndices[i], locals[i]);
                        }

                        // Anatomical sanity checks before projecting:
                        // Invalidate joints if bone lengths exceed anatomical limits, preventing ghost lines
                        if (localsValid[1] && localsValid[3] && dist3D(locals[1], locals[3]) > 60.0f) localsValid[3] = false;
                        if (localsValid[3] && localsValid[4] && dist3D(locals[3], locals[4]) > 60.0f) localsValid[4] = false;
                        if (localsValid[4] && localsValid[5] && dist3D(locals[4], locals[5]) > 60.0f) localsValid[5] = false;

                        if (localsValid[1] && localsValid[6] && dist3D(locals[1], locals[6]) > 60.0f) localsValid[6] = false;
                        if (localsValid[6] && localsValid[7] && dist3D(locals[6], locals[7]) > 60.0f) localsValid[7] = false;
                        if (localsValid[7] && localsValid[8] && dist3D(locals[7], locals[8]) > 60.0f) localsValid[8] = false;

                        if (localsValid[2] && localsValid[9] && dist3D(locals[2], locals[9]) > 65.0f) localsValid[9] = false;
                        if (localsValid[9] && localsValid[10] && dist3D(locals[9], locals[10]) > 80.0f) localsValid[10] = false;
                        if (localsValid[10] && localsValid[11] && dist3D(locals[10], locals[11]) > 80.0f) localsValid[11] = false;

                        if (localsValid[2] && localsValid[12] && dist3D(locals[2], locals[12]) > 65.0f) localsValid[12] = false;
                        if (localsValid[12] && localsValid[13] && dist3D(locals[12], locals[13]) > 80.0f) localsValid[13] = false;
                        if (localsValid[13] && localsValid[14] && dist3D(locals[13], locals[14]) > 80.0f) localsValid[14] = false;

                        uint8_t c2w[48] = {0};
                        ds_pubg_read_c2w(meshComp, rootLoc, halfH, c2w);

                        int okBones = 0;
                        for (int i = 0; i < 15; i++) {
                            if (localsValid[i]) {
                                DSPUBGVector world = {};
                                ds_pubg_bone_world_from_local(c2w, rootLoc, halfH, actorRot, &locals[i], &world);
                                float sx_proj = 0, sy_proj = 0, d_proj = 0;
                                if (ds_pubg_cam_basis_project(basis, world, sx_proj, sy_proj, d_proj)) {
                                    p.skeleton[i] = { sx_proj, sy_proj, true };
                                    okBones++;
                                }
                            }
                        }

                        // Project HeadTop for circle at vHead.Z += 7.0f (exact internal snippet logic)
                        if (localsValid[0]) {
                            DSPUBGVector headTopLocal = locals[0];
                            headTopLocal.Z += 7.0f;
                            DSPUBGVector worldHeadTop = {};
                            ds_pubg_bone_world_from_local(c2w, rootLoc, halfH, actorRot, &headTopLocal, &worldHeadTop);
                            float sx_ht = 0, sy_ht = 0, d_ht = 0;
                            if (ds_pubg_cam_basis_project(basis, worldHeadTop, sx_ht, sy_ht, d_ht)) {
                                p.skeleton[15] = { sx_ht, sy_ht, true };
                            }
                        }

                        if (okBones >= 4) {
                            p.hasSkeleton = true;
                            if (p.skeleton[0].valid) {
                                p.headX = p.skeleton[0].x;
                                p.headY = p.skeleton[0].y;
                            }
                            skeletonDone = true;
                        }
                    }
                }
            }

            // Fallback: ONLY if the mesh had NO component-space transforms at all
            // (e.g. culled mesh or non-skeletal actor), use bounding box proportional skeleton.
            // NEVER fallback when real bone transforms were found, to avoid flickering!
            if (!skeletonDone && boneData == 0 && boxH >= 8.0f && !isnan(boxH) && !isnan(centerX) && !isnan(topY)) {
                p.skeleton[0]  = { centerX,                 topY + boxH * 0.12f, true }; // Head
                p.skeleton[1]  = { centerX,                 topY + boxH * 0.18f, true }; // Neck
                p.skeleton[2]  = { centerX,                 topY + boxH * 0.52f, true }; // Pelvis
                p.skeleton[3]  = { centerX + boxW * 0.22f,  topY + boxH * 0.24f, true }; // UprR
                p.skeleton[4]  = { centerX + boxW * 0.32f,  topY + boxH * 0.38f, true }; // LwrR
                p.skeleton[5]  = { centerX + boxW * 0.35f,  topY + boxH * 0.50f, true }; // HandR
                p.skeleton[6]  = { centerX - boxW * 0.22f,  topY + boxH * 0.24f, true }; // UprL
                p.skeleton[7]  = { centerX - boxW * 0.32f,  topY + boxH * 0.38f, true }; // LwrL
                p.skeleton[8]  = { centerX - boxW * 0.35f,  topY + boxH * 0.50f, true }; // HandL
                p.skeleton[9]  = { centerX + boxW * 0.16f,  topY + boxH * 0.56f, true }; // ThighR
                p.skeleton[10] = { centerX + boxW * 0.18f,  topY + boxH * 0.76f, true }; // CalfR
                p.skeleton[11] = { centerX + boxW * 0.20f,  topY + boxH * 0.96f, true }; // FootR
                p.skeleton[12] = { centerX - boxW * 0.16f,  topY + boxH * 0.56f, true }; // ThighL
                p.skeleton[13] = { centerX - boxW * 0.18f,  topY + boxH * 0.76f, true }; // CalfL
                p.skeleton[14] = { centerX - boxW * 0.20f,  topY + boxH * 0.96f, true }; // FootL
                p.skeleton[15] = { centerX,                 topY + boxH * 0.10f, true }; // HeadTop
                p.hasSkeleton = true;
            }
        }
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

    // Source 2: PersistentLevel.Actors (via DecryptActorsArray)
    if (level) {
        uint64_t actorsData = 0;
        uint32_t actorsCount = 0;

        uint64_t arr = ds_pubg_decrypt_actors_array(level);
        if (arr && ds_pubg_valid(arr)) {
            ds_pubg_actors_array_at(arr, &actorsData, &actorsCount);
        }

        if (!actorsData || actorsCount == 0) {
            // Fallback to direct 0xA0
            ds_pubg_actors_array_at(level + 0xA0ULL, &actorsData, &actorsCount);
        }

        if (!actorsData || actorsCount == 0) {
            // Fallback to cluster 0xE0
            uint64_t cluster = ds_pubg_read_ptr(level + 0xE0ULL);
            if (cluster && ds_pubg_valid(cluster)) {
                ds_pubg_actors_array_at(cluster + 0x28ULL, &actorsData, &actorsCount);
            }
        }

        g_dspubgLastActorsCount = (int)actorsCount;

        if (actorsData && actorsCount > 0) {
            if (actorsCount > 4096) actorsCount = 4096;
            std::vector<uint64_t> levelActors(actorsCount, 0);
            if (ds_pubg_read(actorsData, levelActors.data(), actorsCount * sizeof(uint64_t))) {
                for (uint32_t i = 0; i < actorsCount; i++) {
                    uint64_t actor = levelActors[i];
                    if (!actor || actor == localPawn || !ds_pubg_valid(actor)) continue;
                    uint64_t ps = ds_pubg_read_ptr(actor + 0x4D0ULL);
                    processPawn(actor, ps, false);
                }
            }
        }
    }

    g_dspubgLastEnemyCount = enemyCount;
    g_dspubgLastBotCount = botCount;

    if (publishedCount > 1) {
        std::sort(staging, staging + publishedCount, [](const DSPUBGProjectedPlayer &a, const DSPUBGProjectedPlayer &b) {
            return a.distanceMeters < b.distanceMeters;
        });
    }

    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    memcpy(g_dspubgPlayers, staging, publishedCount * sizeof(DSPUBGProjectedPlayer));
    g_dspubgPlayerCount = publishedCount;
    g_dspubgTotalEnemies = total360EnemyCount;
    g_dspubgTotalBots = total360BotCount;
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}
