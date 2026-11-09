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

static DSPUBGProjectedItem g_dspubgItems[kDSPUBGMaxItems] = {};
static int g_dspubgItemCount = 0;
static uint64_t g_dspubgItemEpoch = 1;

static DSPUBGProjectedGrenade g_dspubgGrenades[kDSPUBGMaxGrenades] = {};
static int g_dspubgGrenadeCount = 0;
static uint64_t g_dspubgGrenadeEpoch = 1;
static uint64_t g_dspubgLocalPawn = 0;

static uint64_t g_dspubgGNames = 0;
static uint32_t g_dspubgFNameEntryOffset = 0x0C;
static bool g_dspubgGNamesIsChunkArray = true;

// Fast Actor Classification Cache: Caches scenery, pawn, and item classification
// to eliminate repetitive GNames lookups and memory reads for thousands of level actors.
struct DSPUBGActorCacheEntry {
    uint64_t actor;
    bool isScenery;
    bool isPawn;
    DSPUBGItemCategory itemCat;
    char itemName[36];
};
static const size_t kDSPUBGActorCacheSize = 4096;
static DSPUBGActorCacheEntry g_dspubgActorCache[kDSPUBGActorCacheSize] = {};

static inline uint32_t ds_pubg_actor_cache_hash(uint64_t actor) {
    return (uint32_t)((actor >> 4) ^ (actor >> 13)) & (uint32_t)(kDSPUBGActorCacheSize - 1);
}

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

struct DSPUBGGrenadeHistory {
    uint64_t actor;
    DSPUBGGrenadeType type;
    DSPUBGVector trail[16];
    int trailCount;
    uint64_t lastSeenTick;
    DSPUBGVector throwerPos;
    bool hasThrowerPos;
};
static DSPUBGGrenadeHistory s_grenadeHistories[16] = {};
static uint64_t s_grenadeTickCounter = 0;

static inline bool ds_pubg_valid(uint64_t address) {
    uint64_t clean = address & 0x0000FFFFFFFFFFFFULL;
    return clean >= 0x100000000ULL && clean < 0x300000000000ULL;
}

static uint64_t ds_pubg_read_ptr(uint64_t address) {
    uint64_t value = 0;
    if (!ds_pubg_valid(address) || (address & 0x7ULL) != 0 || !g_dspubgVmMap) return 0;
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
    if (!g_dspubgVmMap || !ds_pubg_valid(address) || (address & 0x3ULL) != 0) return 0;
    ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value));
    return value;
}

static int32_t ds_pubg_read_i32(uint64_t address) {
    int32_t value = 0;
    if (!g_dspubgVmMap || !ds_pubg_valid(address) || (address & 0x3ULL) != 0) return 0;
    ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value));
    return value;
}

static float ds_pubg_read_f32(uint64_t address) {
    float value = 0.0f;
    if (!g_dspubgVmMap || !ds_pubg_valid(address) || (address & 0x3ULL) != 0) return 0.0f;
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

struct ScanRange {
    uint64_t start;
    uint64_t size;
    int priority; // 0 = high (__bss, __common), 1 = medium (__data), 2 = other
};

static bool ds_pubg_get_data_ranges(uint64_t vmMap, uint64_t base, std::vector<ScanRange> &outRanges) {
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
                    outRanges.push_back({sAddr, sec.size, prio});
                }
            }
        }
        cursor += cmd->cmdsize;
    }

    std::sort(outRanges.begin(), outRanges.end(), [](const ScanRange &a, const ScanRange &b) {
        return a.priority < b.priority;
    });

    return !outRanges.empty();
}

static bool ds_pubg_is_valid_gnames(uint64_t vmMap, uint64_t candidate, uint32_t *outNameOffset) {
    if (!candidate || !ds_pubg_valid(candidate)) return false;
    uint64_t chunk0 = 0;
    if (!ds_debug_read_bytes(vmMap, candidate, &chunk0, sizeof(chunk0))) return false;
    chunk0 &= 0x0000FFFFFFFFFFFFULL;
    if (!chunk0 || !ds_pubg_valid(chunk0)) return false;

    uint64_t entry0 = 0;
    if (!ds_debug_read_bytes(vmMap, chunk0, &entry0, sizeof(entry0))) return false;
    entry0 &= 0x0000FFFFFFFFFFFFULL;
    if (!entry0 || !ds_pubg_valid(entry0)) return false;

    static const uint32_t kOffsets[] = { 0x0C, 0x10, 0x0E, 0x14 };
    for (uint32_t off : kOffsets) {
        char buf[16] = {0};
        if (ds_debug_read_bytes(vmMap, entry0 + off, buf, sizeof(buf) - 1)) {
            if (strcmp(buf, "None") == 0) {
                uint64_t entry1 = 0;
                if (ds_debug_read_bytes(vmMap, chunk0 + 8, &entry1, sizeof(entry1))) {
                    entry1 &= 0x0000FFFFFFFFFFFFULL;
                    char buf1[32] = {0};
                    if (entry1 && ds_pubg_valid(entry1) && ds_debug_read_bytes(vmMap, entry1 + off, buf1, sizeof(buf1) - 1)) {
                        if (strstr(buf1, "Byte") || strstr(buf1, "Int") || strstr(buf1, "Property") || strstr(buf1, "Bool")) {
                            if (outNameOffset) *outNameOffset = off;
                            return true;
                        }
                    }
                }
                if (outNameOffset) *outNameOffset = off;
                return true;
            }
        }
    }
    return false;
}

static void ds_pubg_try_known_gnames(uint64_t vmMap, uint64_t base) {
    if (g_dspubgGNames) return;
    static const uint64_t kKnownGNamesRVAs[] = {
        0x0D492AC0ULL, // v3.4 Global / VN / 64-bit Mach-O
        0x0D481AC0ULL,
        0x0D490AC0ULL,
        0x0D4A0AC0ULL
    };
    for (uint64_t rva : kKnownGNamesRVAs) {
        uint64_t val = 0;
        if (ds_debug_read_bytes(vmMap, base + rva, &val, sizeof(val))) {
            val &= 0x0000FFFFFFFFFFFFULL;
            uint32_t nameOff = 0x0C;
            if (val && ds_pubg_valid(val) && ds_pubg_is_valid_gnames(vmMap, val, &nameOff)) {
                g_dspubgGNames = val;
                g_dspubgFNameEntryOffset = nameOff;
                g_dspubgGNamesIsChunkArray = true;
                return;
            }
            if (ds_pubg_is_valid_gnames(vmMap, base + rva, &nameOff)) {
                g_dspubgGNames = base + rva;
                g_dspubgFNameEntryOffset = nameOff;
                g_dspubgGNamesIsChunkArray = false;
                return;
            }
        }
    }
}

static void ds_pubg_scan_for_gnames(uint64_t vmMap, const std::vector<ScanRange> &scanRanges) {
    if (g_dspubgGNames) return;
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
                uint32_t nameOff = 0x10;

                // Check 1: ptrAddr holds pointer to chunk array (GNames as uint64_t*)
                if (ds_pubg_is_valid_gnames(vmMap, val, &nameOff)) {
                    g_dspubgGNames = val;
                    g_dspubgFNameEntryOffset = nameOff;
                    g_dspubgGNamesIsChunkArray = true;
                    return;
                }

                // Check 2: ptrAddr is directly the chunk array (GNames as uint64_t[])
                if (ds_pubg_is_valid_gnames(vmMap, ptrAddr, &nameOff)) {
                    g_dspubgGNames = ptrAddr;
                    g_dspubgFNameEntryOffset = nameOff;
                    g_dspubgGNamesIsChunkArray = false;
                    return;
                }
            }
        }
    }
}

static bool ds_pubg_get_name_by_id(uint32_t id, char *outBuf, size_t outCap) {
    if (!outBuf || outCap < 2) return false;
    outBuf[0] = '\0';
    if (!g_dspubgGNames || id == 0 || id > 500000) return false;

    uint32_t chunkIdx = id / 16384;
    uint32_t inChunkIdx = id % 16384;

    uint64_t chunk = 0;
    if (g_dspubgGNamesIsChunkArray) {
        chunk = ds_pubg_read_ptr(g_dspubgGNames + (chunkIdx * 8ULL));
    } else {
        chunk = g_dspubgGNames;
    }
    if (!chunk || !ds_pubg_valid(chunk)) return false;

    uint64_t entry = ds_pubg_read_ptr(chunk + (inChunkIdx * 8ULL));
    if (!entry || !ds_pubg_valid(entry)) return false;

    char raw[64] = {0};
    if (!ds_debug_read_bytes(g_dspubgVmMap, entry + g_dspubgFNameEntryOffset, raw, sizeof(raw) - 1)) {
        return false;
    }
    raw[sizeof(raw) - 1] = '\0';

    if (raw[0] == '\0') return false;
    for (size_t i = 0; i < sizeof(raw) && raw[i] != '\0'; i++) {
        unsigned char c = (unsigned char)raw[i];
        if (c < 32 || c > 126) {
            raw[i] = '\0';
            break;
        }
    }
    if (strlen(raw) < 2) return false;

    strncpy(outBuf, raw, outCap - 1);
    outBuf[outCap - 1] = '\0';
    return true;
}

static bool ds_pubg_get_actor_name(uint64_t actor, char *outBuf, size_t outCap) {
    if (!actor || !outBuf || outCap < 2) return false;
    outBuf[0] = '\0';

    // 1. Try ClassPrivate at 0x10ULL -> FName at +0x18ULL
    uint64_t classPrivate = ds_pubg_read_ptr(actor + 0x10ULL);
    if (classPrivate && ds_pubg_valid(classPrivate)) {
        uint32_t classFId = ds_pubg_read_u32(classPrivate + 0x18ULL);
        if (classFId > 0 && classFId < 500000 && ds_pubg_get_name_by_id(classFId, outBuf, outCap)) {
            if (strlen(outBuf) > 1) return true;
        }
        uint32_t classFId2 = ds_pubg_read_u32(classPrivate + 0x20ULL);
        if (classFId2 > 0 && classFId2 < 500000 && ds_pubg_get_name_by_id(classFId2, outBuf, outCap)) {
            if (strlen(outBuf) > 1) return true;
        }
    }

    // 2. Try actor's own FName at 0x18ULL
    uint32_t actorFId = ds_pubg_read_u32(actor + 0x18ULL);
    if (actorFId > 0 && actorFId < 500000 && ds_pubg_get_name_by_id(actorFId, outBuf, outCap)) {
        if (strlen(outBuf) > 1) return true;
    }
    uint32_t actorFId2 = ds_pubg_read_u32(actor + 0x20ULL);
    if (actorFId2 > 0 && actorFId2 < 500000 && ds_pubg_get_name_by_id(actorFId2, outBuf, outCap)) {
        if (strlen(outBuf) > 1) return true;
    }

    return false;
}

static DSPUBGItemCategory ds_pubg_classify_item(const char *name, char *outDisplay, size_t outCap) {
    if (!name || !outDisplay || outCap < 4) return DSPUBGItemCategoryNone;
    outDisplay[0] = '\0';

    // 0. Fast reject non-item actors (bullets, effects, cameras, players)
    if (strcasestr(name, "Bullet") || strcasestr(name, "Proj") || strcasestr(name, "Shell") ||
        strcasestr(name, "Cartridge") || strcasestr(name, "Trace") || strcasestr(name, "Particle") ||
        strcasestr(name, "Emitter") || strcasestr(name, "Effect") || strcasestr(name, "Decal") ||
        strcasestr(name, "Camera") || strcasestr(name, "Controller") || strcasestr(name, "Player") ||
        strcasestr(name, "Character") || strcasestr(name, "Volume") || strcasestr(name, "Trigger") ||
        strcasestr(name, "Light") || strcasestr(name, "Audio") || strcasestr(name, "Sound") ||
        strcasestr(name, "Landscape") || strcasestr(name, "WorldSettings") || strcasestr(name, "GameMode") ||
        strcasestr(name, "Grenade") || strcasestr(name, "Smoke") || strcasestr(name, "Flash") ||
        strcasestr(name, "Explo") || strcasestr(name, "Fire") || strcasestr(name, "Flame")) {
        return DSPUBGItemCategoryNone;
    }

    // 1. Vehicles
    bool isNonVehicle = (strcasestr(name, "Wrapper") != nullptr) ||
                        (strcasestr(name, "PickUp") != nullptr && strcasestr(name, "VH_") == nullptr) ||
                        (strcasestr(name, "Pickup") != nullptr && strcasestr(name, "VH_") == nullptr) ||
                        (strcasestr(name, "WheelComponent") != nullptr) ||
                        (strcasestr(name, "VehicleWheel") != nullptr) ||
                        (strcasestr(name, "SeatComponent") != nullptr) ||
                        (strcasestr(name, "Spawner") != nullptr) ||
                        (strcasestr(name, "Audio") != nullptr) ||
                        (strcasestr(name, "Sound") != nullptr) ||
                        (strcasestr(name, "Decal") != nullptr) ||
                        (strcasestr(name, "Weapon") != nullptr) ||
                        (strcasestr(name, "UI") != nullptr);
    if (!isNonVehicle) {
        if (strcasestr(name, "Jeep") || strcasestr(name, "UAZ")) {
            snprintf(outDisplay, outCap, "Xe UAZ");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Sedan") || strcasestr(name, "Dacia")) {
            snprintf(outDisplay, outCap, "Xe Dacia");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Buggy")) {
            snprintf(outDisplay, outCap, "Xe Buggy");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "VH_PickUp") || strcasestr(name, "VH_Pickup") || (strcasestr(name, "Truck") && !strcasestr(name, "Monster")) || strcasestr(name, "Rony")) {
            snprintf(outDisplay, outCap, "Xe Bán Tải");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Motorcycle") || strcasestr(name, "Motorbike") || strcasestr(name, "VH_Motor") || strcasestr(name, "Bike")) {
            snprintf(outDisplay, outCap, "Xe Máy");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Scooter")) {
            snprintf(outDisplay, outCap, "Xe Scooter");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "TukTuk")) {
            snprintf(outDisplay, outCap, "Xe TukTuk");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "MiniBus") || strcasestr(name, "Bus_")) {
            snprintf(outDisplay, outCap, "Xe MiniBus");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "PG117") || strcasestr(name, "Boat") || strcasestr(name, "Cano")) {
            snprintf(outDisplay, outCap, "Thuyền Cano");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "AquaRail") || strcasestr(name, "JetSki")) {
            snprintf(outDisplay, outCap, "Moto Nước");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "BRDM")) {
            snprintf(outDisplay, outCap, "Xe BRDM");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "CoupeRB") || strcasestr(name, "Coupe")) {
            snprintf(outDisplay, outCap, "Xe Coupe RB");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "MonsterTruck") || strcasestr(name, "BigFoot")) {
            snprintf(outDisplay, outCap, "Xe Quái Thú");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Mirado")) {
            snprintf(outDisplay, outCap, "Xe Mirado");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Lada")) {
            snprintf(outDisplay, outCap, "Xe Lada Niva");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Snowmobile") || strcasestr(name, "Snowbike")) {
            snprintf(outDisplay, outCap, "Xe Tuyết");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Bicycle")) {
            snprintf(outDisplay, outCap, "Xe Đạp");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Tank")) {
            snprintf(outDisplay, outCap, "Xe Tăng");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Helicopter") || strcasestr(name, "DirectFly")) {
            snprintf(outDisplay, outCap, "Trực Thăng");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Lamborghini")) {
            snprintf(outDisplay, outCap, "Xe Lamborghini");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "Tesla") || strcasestr(name, "ModelY")) {
            snprintf(outDisplay, outCap, "Xe Model Y");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "UTV")) {
            snprintf(outDisplay, outCap, "Xe UTV");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "ATV")) {
            snprintf(outDisplay, outCap, "Xe ATV");
            return DSPUBGItemCategoryVehicle;
        }
        if (strcasestr(name, "VH_") || strcasestr(name, "WheeledVehicle") || strcasestr(name, "Vehicle_")) {
            snprintf(outDisplay, outCap, "Xe Ô Tô");
            return DSPUBGItemCategoryVehicle;
        }
    }

    // 2. Scopes
    if (strcasestr(name, "8X")) {
        snprintf(outDisplay, outCap, "Scope 8x");
        return DSPUBGItemCategoryScope;
    }
    if (strcasestr(name, "6X")) {
        snprintf(outDisplay, outCap, "Scope 6x");
        return DSPUBGItemCategoryScope;
    }
    if (strcasestr(name, "4X")) {
        snprintf(outDisplay, outCap, "Scope 4x");
        return DSPUBGItemCategoryScope;
    }
    if (strcasestr(name, "3X")) {
        snprintf(outDisplay, outCap, "Scope 3x");
        return DSPUBGItemCategoryScope;
    }
    if (strcasestr(name, "2X")) {
        snprintf(outDisplay, outCap, "Scope 2x");
        return DSPUBGItemCategoryScope;
    }
    if (strcasestr(name, "RedDot") || strcasestr(name, "HD")) {
        snprintf(outDisplay, outCap, "Red Dot");
        return DSPUBGItemCategoryScope;
    }
    if (strcasestr(name, "Holo") || strcasestr(name, "MZJ_QX")) {
        snprintf(outDisplay, outCap, "Holo");
        return DSPUBGItemCategoryScope;
    }

    // 3. Armor & Helmets
    if (strcasestr(name, "Armor_Lv3") || strcasestr(name, "Armor3")) {
        snprintf(outDisplay, outCap, "Giáp 3");
        return DSPUBGItemCategoryArmor;
    }
    if (strcasestr(name, "Armor_Lv2") || strcasestr(name, "Armor2")) {
        snprintf(outDisplay, outCap, "Giáp 2");
        return DSPUBGItemCategoryArmor;
    }
    if (strcasestr(name, "Armor_Lv1") || strcasestr(name, "Armor1")) {
        snprintf(outDisplay, outCap, "Giáp 1");
        return DSPUBGItemCategoryArmor;
    }
    if (strcasestr(name, "Head_Lv3") || strcasestr(name, "Helmet_Lv3") || strcasestr(name, "Head3")) {
        snprintf(outDisplay, outCap, "Mũ 3");
        return DSPUBGItemCategoryArmor;
    }
    if (strcasestr(name, "Head_Lv2") || strcasestr(name, "Helmet_Lv2") || strcasestr(name, "Head2")) {
        snprintf(outDisplay, outCap, "Mũ 2");
        return DSPUBGItemCategoryArmor;
    }
    if (strcasestr(name, "Head_Lv1") || strcasestr(name, "Helmet_Lv1") || strcasestr(name, "Head1")) {
        snprintf(outDisplay, outCap, "Mũ 1");
        return DSPUBGItemCategoryArmor;
    }

    // 4. Backpacks
    if (strcasestr(name, "Bag_Lv3") || strcasestr(name, "Bag3")) {
        snprintf(outDisplay, outCap, "Balo 3");
        return DSPUBGItemCategoryBag;
    }
    if (strcasestr(name, "Bag_Lv2") || strcasestr(name, "Bag2")) {
        snprintf(outDisplay, outCap, "Balo 2");
        return DSPUBGItemCategoryBag;
    }
    if (strcasestr(name, "Bag_Lv1") || strcasestr(name, "Bag1")) {
        snprintf(outDisplay, outCap, "Balo 1");
        return DSPUBGItemCategoryBag;
    }

    // 5. Weapons
    if (strcasestr(name, "Flare")) {
        snprintf(outDisplay, outCap, "Flare Gun");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "AWM")) {
        snprintf(outDisplay, outCap, "AWM");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "M416")) {
        snprintf(outDisplay, outCap, "M416");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "AKM")) {
        snprintf(outDisplay, outCap, "AKM");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "M24")) {
        snprintf(outDisplay, outCap, "M24");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Kar98")) {
        snprintf(outDisplay, outCap, "Kar98k");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Groza")) {
        snprintf(outDisplay, outCap, "Groza");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "AUG")) {
        snprintf(outDisplay, outCap, "AUG");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "M762")) {
        snprintf(outDisplay, outCap, "M762");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Mk14")) {
        snprintf(outDisplay, outCap, "Mk14");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "SLR")) {
        snprintf(outDisplay, outCap, "SLR");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "SKS")) {
        snprintf(outDisplay, outCap, "SKS");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Mini14")) {
        snprintf(outDisplay, outCap, "Mini14");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "AMR")) {
        snprintf(outDisplay, outCap, "Lynx AMR");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "MG3")) {
        snprintf(outDisplay, outCap, "MG3");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "M249")) {
        snprintf(outDisplay, outCap, "M249");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "DP28") || strcasestr(name, "DP-28")) {
        snprintf(outDisplay, outCap, "DP-28");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "P90")) {
        snprintf(outDisplay, outCap, "P90");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Vector")) {
        snprintf(outDisplay, outCap, "Vector");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "UMP")) {
        snprintf(outDisplay, outCap, "UMP45");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "DBS")) {
        snprintf(outDisplay, outCap, "DBS");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "SCAR")) {
        snprintf(outDisplay, outCap, "SCAR-L");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "M16A4") || strcasestr(name, "M16")) {
        snprintf(outDisplay, outCap, "M16A4");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "QBZ")) {
        snprintf(outDisplay, outCap, "QBZ");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "G36")) {
        snprintf(outDisplay, outCap, "G36C");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "ACE32")) {
        snprintf(outDisplay, outCap, "ACE32");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Honey")) {
        snprintf(outDisplay, outCap, "Honey Badger");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "FAMAS")) {
        snprintf(outDisplay, outCap, "FAMAS");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Mosin")) {
        snprintf(outDisplay, outCap, "Mosin");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Mk12")) {
        snprintf(outDisplay, outCap, "Mk12");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "QBU")) {
        snprintf(outDisplay, outCap, "QBU");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "VSS")) {
        snprintf(outDisplay, outCap, "VSS");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "S12K")) {
        snprintf(outDisplay, outCap, "S12K");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "S686")) {
        snprintf(outDisplay, outCap, "S686");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "S1897")) {
        snprintf(outDisplay, outCap, "S1897");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "UZI") || strcasestr(name, "MicroUZI")) {
        snprintf(outDisplay, outCap, "Micro UZI");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Bizon") || strcasestr(name, "PP19")) {
        snprintf(outDisplay, outCap, "PP-19 Bizon");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "MP5K") || strcasestr(name, "MP5")) {
        snprintf(outDisplay, outCap, "MP5K");
        return DSPUBGItemCategoryWeapon;
    }
    if (strcasestr(name, "Pan")) {
        snprintf(outDisplay, outCap, "Chảo");
        return DSPUBGItemCategoryWeapon;
    }

    // 6. Crates & AirDrops & Tokens
    if (strcasestr(name, "AirDrop")) {
        snprintf(outDisplay, outCap, (g_pubgLanguage == 1) ? "AirDrop" : "HÒM THÍNH");
        return DSPUBGItemCategoryCrate;
    }
    if (strcasestr(name, "DeadBox") || strcasestr(name, "PlayerDeadInventoryBox") || strcasestr(name, "TombBox")) {
        snprintf(outDisplay, outCap, (g_pubgLanguage == 1) ? "DeadBox" : "Hòm Xác");
        return DSPUBGItemCategoryCrate;
    }
    if (strcasestr(name, "PickUpListWrapper")) {
        snprintf(outDisplay, outCap, (g_pubgLanguage == 1) ? "DropLoot" : "Đồ Rơi");
        return DSPUBGItemCategoryCrate;
    }
    if (strcasestr(name, "Token") || strcasestr(name, "ShopToken") || strcasestr(name, "GoldToken")) {
        snprintf(outDisplay, outCap, (g_pubgLanguage == 1) ? "TokenShop" : "Xu Shop");
        return DSPUBGItemCategoryCrate;
    }
    if (strcasestr(name, "GasCan") || strcasestr(name, "JerryCan") || strcasestr(name, "FuelCan")) {
        snprintf(outDisplay, outCap, (g_pubgLanguage == 1) ? "Gascan" : "Bình Xăng");
        return DSPUBGItemCategoryCrate;
    }

    return DSPUBGItemCategoryNone;
}

static bool ds_pubg_classify_grenade(const char *name, DSPUBGGrenadeType *outType, char *outDisplay, size_t outCap, float *outRadius) {
    if (!name || !outType || !outDisplay || outCap < 8) return false;

    // Filter out pickup wrappers, weapons in hand, emitters, explosions, scenery
    if (strcasestr(name, "PickUp") || strcasestr(name, "Wrapper") || strcasestr(name, "Weapon") ||
        strcasestr(name, "Particle") || strcasestr(name, "Emitter") || strcasestr(name, "Effect") ||
        strcasestr(name, "Explosion") || strcasestr(name, "Decal") || strcasestr(name, "Sound") ||
        strcasestr(name, "Audio") || strcasestr(name, "Camera") || strcasestr(name, "Character") ||
        strcasestr(name, "Pawn") || strcasestr(name, "Player")) {
        return false;
    }

    bool isEn = (g_pubgLanguage == 1);

    // 1. Frag Grenade (Lựu đạn nổ)
    if (strcasestr(name, "Shoulei") || strcasestr(name, "Frag") || strcasestr(name, "ProjFrag") ||
        strcasestr(name, "ProjGrenade_Shoulei") || strcasestr(name, "BP_Grenade_Shoulei")) {
        *outType = DSPUBGGrenadeTypeFrag;
        snprintf(outDisplay, outCap, isEn ? "FRAG GRENADE" : "LỰU ĐẠN NỔ");
        if (outRadius) *outRadius = 9.0f; // 9 meters damage radius
        return true;
    }

    // 2. Molotov / Burn Grenade (Bom lửa)
    if (strcasestr(name, "Burn") || strcasestr(name, "Molotov") || strcasestr(name, "Fire") ||
        strcasestr(name, "ProjBurn") || strcasestr(name, "BP_Molotov")) {
        *outType = DSPUBGGrenadeTypeBurn;
        snprintf(outDisplay, outCap, isEn ? "MOLOTOV" : "BOM LỬA");
        if (outRadius) *outRadius = 4.5f; // 4.5 meters burn radius
        return true;
    }

    // 3. Smoke Grenade (Bom khói)
    if (strcasestr(name, "Smoke") || strcasestr(name, "ProjSmoke") || strcasestr(name, "BP_Grenade_Smoke")) {
        *outType = DSPUBGGrenadeTypeSmoke;
        snprintf(outDisplay, outCap, isEn ? "SMOKE" : "BOM KHÓI");
        if (outRadius) *outRadius = 6.0f; // 6 meters smoke radius
        return true;
    }

    // 4. Stun Grenade (Bom choáng)
    if (strcasestr(name, "Stun") || strcasestr(name, "Flash") || strcasestr(name, "ProjStun") || strcasestr(name, "BP_Grenade_Stun")) {
        *outType = DSPUBGGrenadeTypeStun;
        snprintf(outDisplay, outCap, isEn ? "STUN" : "BOM CHOÁNG");
        if (outRadius) *outRadius = 8.0f; // 8 meters flash radius
        return true;
    }

    // 5. Generic Projectile Grenade
    if (strcasestr(name, "ProjGrenade") || (strcasestr(name, "Grenade") && strcasestr(name, "Proj"))) {
        *outType = DSPUBGGrenadeTypeFrag;
        snprintf(outDisplay, outCap, isEn ? "GRENADE" : "LỰU ĐẠN");
        if (outRadius) *outRadius = 9.0f;
        return true;
    }

    return false;
}

static DSPUBGItemCategory ds_pubg_classify_item_id(int itemId, char *outDisplay, size_t outCap) {
    if (itemId <= 0 || !outDisplay || outCap < 4) return DSPUBGItemCategoryNone;
    outDisplay[0] = '\0';
    bool isEn = (g_pubgLanguage == 1);

    switch (itemId) {
        // --- Assault Rifles (AR) ---
        case 101001: snprintf(outDisplay, outCap, "AKM"); return DSPUBGItemCategoryWeapon;
        case 101002: snprintf(outDisplay, outCap, "M16A4"); return DSPUBGItemCategoryWeapon;
        case 101003: snprintf(outDisplay, outCap, isEn ? "SCARL" : "SCAR-L"); return DSPUBGItemCategoryWeapon;
        case 101004: snprintf(outDisplay, outCap, "M416"); return DSPUBGItemCategoryWeapon;
        case 101005: snprintf(outDisplay, outCap, "Groza"); return DSPUBGItemCategoryWeapon;
        case 101006: snprintf(outDisplay, outCap, "AUG"); return DSPUBGItemCategoryWeapon;
        case 101007: snprintf(outDisplay, outCap, "QBZ"); return DSPUBGItemCategoryWeapon;
        case 101008: snprintf(outDisplay, outCap, "M762"); return DSPUBGItemCategoryWeapon;
        case 101009: snprintf(outDisplay, outCap, "Mk47"); return DSPUBGItemCategoryWeapon;
        case 101010: snprintf(outDisplay, outCap, "G36C"); return DSPUBGItemCategoryWeapon;
        case 101011: snprintf(outDisplay, outCap, "HoneyBadger"); return DSPUBGItemCategoryWeapon;
        case 101012: snprintf(outDisplay, outCap, "ACE32"); return DSPUBGItemCategoryWeapon;

        // --- Submachine Guns (SMG) ---
        case 102001: snprintf(outDisplay, outCap, "UZI"); return DSPUBGItemCategoryWeapon;
        case 102002: snprintf(outDisplay, outCap, "UMP45"); return DSPUBGItemCategoryWeapon;
        case 102003: snprintf(outDisplay, outCap, "Vector"); return DSPUBGItemCategoryWeapon;
        case 102004: snprintf(outDisplay, outCap, "Tommy Gun"); return DSPUBGItemCategoryWeapon;
        case 102005: snprintf(outDisplay, outCap, isEn ? "Bizon" : "PP-19 Bizon"); return DSPUBGItemCategoryWeapon;
        case 102007: snprintf(outDisplay, outCap, "MP5K"); return DSPUBGItemCategoryWeapon;
        case 102008: snprintf(outDisplay, outCap, "P90"); return DSPUBGItemCategoryWeapon;

        // --- Sniper Rifles (SR) & DMR ---
        case 103001: snprintf(outDisplay, outCap, "Kar98k"); return DSPUBGItemCategoryWeapon;
        case 103002: snprintf(outDisplay, outCap, "M24"); return DSPUBGItemCategoryWeapon;
        case 103003: snprintf(outDisplay, outCap, "AWM"); return DSPUBGItemCategoryWeapon;
        case 103004: snprintf(outDisplay, outCap, "SKS"); return DSPUBGItemCategoryWeapon;
        case 103005: snprintf(outDisplay, outCap, "VSS"); return DSPUBGItemCategoryWeapon;
        case 103006: snprintf(outDisplay, outCap, "Mini14"); return DSPUBGItemCategoryWeapon;
        case 103007: snprintf(outDisplay, outCap, "Mk14"); return DSPUBGItemCategoryWeapon;
        case 103008: snprintf(outDisplay, outCap, "Win94"); return DSPUBGItemCategoryWeapon;
        case 103009: snprintf(outDisplay, outCap, "SLR"); return DSPUBGItemCategoryWeapon;
        case 103010: snprintf(outDisplay, outCap, "QBU"); return DSPUBGItemCategoryWeapon;
        case 103011: snprintf(outDisplay, outCap, "Mosin"); return DSPUBGItemCategoryWeapon;
        case 103012: snprintf(outDisplay, outCap, "Lynx AMR"); return DSPUBGItemCategoryWeapon;
        case 103013: snprintf(outDisplay, outCap, "AMR"); return DSPUBGItemCategoryWeapon;

        // --- Shotguns (SG) ---
        case 104001: snprintf(outDisplay, outCap, "S686"); return DSPUBGItemCategoryWeapon;
        case 104002: snprintf(outDisplay, outCap, "S1897"); return DSPUBGItemCategoryWeapon;
        case 104003: snprintf(outDisplay, outCap, "S12K"); return DSPUBGItemCategoryWeapon;
        case 104004: snprintf(outDisplay, outCap, "DBS"); return DSPUBGItemCategoryWeapon;
        case 104005: snprintf(outDisplay, outCap, "M1014"); return DSPUBGItemCategoryWeapon;

        // --- Light Machine Guns (LMG) ---
        case 105001: snprintf(outDisplay, outCap, "M249"); return DSPUBGItemCategoryWeapon;
        case 105002: snprintf(outDisplay, outCap, "DP-28"); return DSPUBGItemCategoryWeapon;
        case 105003: snprintf(outDisplay, outCap, "MG3"); return DSPUBGItemCategoryWeapon;

        // --- Pistols & Special ---
        case 106001: snprintf(outDisplay, outCap, "P92"); return DSPUBGItemCategoryWeapon;
        case 106002: snprintf(outDisplay, outCap, "P1911"); return DSPUBGItemCategoryWeapon;
        case 106003: snprintf(outDisplay, outCap, "R1895"); return DSPUBGItemCategoryWeapon;
        case 106004: snprintf(outDisplay, outCap, "P18C"); return DSPUBGItemCategoryWeapon;
        case 106005: snprintf(outDisplay, outCap, "R45"); return DSPUBGItemCategoryWeapon;
        case 106006: snprintf(outDisplay, outCap, "Sawed-Off"); return DSPUBGItemCategoryWeapon;
        case 106007: snprintf(outDisplay, outCap, "Flare Gun"); return DSPUBGItemCategoryWeapon;
        case 106008: snprintf(outDisplay, outCap, "Skorpion"); return DSPUBGItemCategoryWeapon;
        case 106010: snprintf(outDisplay, outCap, "Deagle"); return DSPUBGItemCategoryWeapon;
        case 107001: snprintf(outDisplay, outCap, isEn ? "Crossbow" : "Nỏ"); return DSPUBGItemCategoryWeapon;
        case 108001: snprintf(outDisplay, outCap, isEn ? "Pan" : "Chảo"); return DSPUBGItemCategoryWeapon;

        // --- Scopes & Sights ---
        case 201001: snprintf(outDisplay, outCap, "RedDot"); return DSPUBGItemCategoryScope;
        case 201002: snprintf(outDisplay, outCap, "Holo"); return DSPUBGItemCategoryScope;
        case 201003: snprintf(outDisplay, outCap, isEn ? "Scope2x" : "Scope 2x"); return DSPUBGItemCategoryScope;
        case 201004: snprintf(outDisplay, outCap, isEn ? "Scope4x" : "Scope 4x"); return DSPUBGItemCategoryScope;
        case 201005: snprintf(outDisplay, outCap, isEn ? "Scope8x" : "Scope 8x"); return DSPUBGItemCategoryScope;
        case 201009: snprintf(outDisplay, outCap, isEn ? "Scope3x" : "Scope 3x"); return DSPUBGItemCategoryScope;
        case 201010: snprintf(outDisplay, outCap, isEn ? "Scope6x" : "Scope 6x"); return DSPUBGItemCategoryScope;
        case 201011: snprintf(outDisplay, outCap, "Canted Sight"); return DSPUBGItemCategoryScope;
        case 201012: snprintf(outDisplay, outCap, isEn ? "Scope15x" : "Scope 15x"); return DSPUBGItemCategoryScope;

        // --- Armor & Helmets ---
        case 501001: case 501004: snprintf(outDisplay, outCap, isEn ? "ArmorLv1" : "Giáp 1"); return DSPUBGItemCategoryArmor;
        case 501002: case 501005: snprintf(outDisplay, outCap, isEn ? "ArmorLv2" : "Giáp 2"); return DSPUBGItemCategoryArmor;
        case 501003: case 501006: snprintf(outDisplay, outCap, isEn ? "ArmorLv3" : "Giáp 3"); return DSPUBGItemCategoryArmor;

        case 502001: snprintf(outDisplay, outCap, isEn ? "HelmetLv1" : "Mũ 1"); return DSPUBGItemCategoryArmor;
        case 502002: snprintf(outDisplay, outCap, isEn ? "HelmetLv2" : "Mũ 2"); return DSPUBGItemCategoryArmor;
        case 502003: snprintf(outDisplay, outCap, isEn ? "HelmetLv3" : "Mũ 3"); return DSPUBGItemCategoryArmor;

        // --- Backpacks ---
        case 503001: snprintf(outDisplay, outCap, isEn ? "BagLv1" : "Balo 1"); return DSPUBGItemCategoryBag;
        case 503002: snprintf(outDisplay, outCap, isEn ? "BagLv2" : "Balo 2"); return DSPUBGItemCategoryBag;
        case 503003: snprintf(outDisplay, outCap, isEn ? "BagLv3" : "Balo 3"); return DSPUBGItemCategoryBag;

        // --- Medical / Boosters ---
        case 601001: snprintf(outDisplay, outCap, isEn ? "Bandage" : "Băng Gạc"); return DSPUBGItemCategoryCrate;
        case 601002: snprintf(outDisplay, outCap, isEn ? "FirstaidKit" : "First Aid"); return DSPUBGItemCategoryCrate;
        case 601003: snprintf(outDisplay, outCap, isEn ? "MedKit" : "Med Kit"); return DSPUBGItemCategoryCrate;
        case 601004: snprintf(outDisplay, outCap, isEn ? "EnergyDrink" : "Nước Tăng Lực"); return DSPUBGItemCategoryCrate;
        case 601005: snprintf(outDisplay, outCap, isEn ? "Painkiller" : "Giảm Đau"); return DSPUBGItemCategoryCrate;
        case 601006: snprintf(outDisplay, outCap, "Adrenaline"); return DSPUBGItemCategoryCrate;

        // --- Throwables ---
        case 602001: snprintf(outDisplay, outCap, isEn ? "Grenade" : "Lựu Đạn"); return DSPUBGItemCategoryWeapon;
        case 602002: snprintf(outDisplay, outCap, isEn ? "Smoke" : "Bom Khói"); return DSPUBGItemCategoryWeapon;
        case 602003: snprintf(outDisplay, outCap, isEn ? "Molotof" : "Bom Xăng"); return DSPUBGItemCategoryWeapon;
        case 602004: snprintf(outDisplay, outCap, isEn ? "Flash" : "Choáng"); return DSPUBGItemCategoryWeapon;

        // --- Ammo ---
        case 301001: snprintf(outDisplay, outCap, isEn ? "9mm" : "Đạn 9mm"); return DSPUBGItemCategoryCrate;
        case 302001: snprintf(outDisplay, outCap, isEn ? "7.62mm" : "Đạn 7.62"); return DSPUBGItemCategoryCrate;
        case 303001: snprintf(outDisplay, outCap, isEn ? "5.56mm" : "Đạn 5.56"); return DSPUBGItemCategoryCrate;
        case 304001: snprintf(outDisplay, outCap, isEn ? "12Guage" : "Đạn 12G"); return DSPUBGItemCategoryCrate;
        case 305001: snprintf(outDisplay, outCap, isEn ? ".300 Mag" : "Đạn .300"); return DSPUBGItemCategoryCrate;
        case 306001: snprintf(outDisplay, outCap, isEn ? "FlareAmmo" : "Đạn Flare"); return DSPUBGItemCategoryWeapon;
        case 307001: snprintf(outDisplay, outCap, isEn ? "45ACP" : "Đạn .45"); return DSPUBGItemCategoryCrate;
        case 308001: snprintf(outDisplay, outCap, isEn ? "5.7mm" : "Đạn 5.7"); return DSPUBGItemCategoryCrate;

        // --- Shop Tokens & Event Currency ---
        case 603001: case 603002: case 603003: case 603004:
            snprintf(outDisplay, outCap, isEn ? "TokenShop" : "Xu Shop"); return DSPUBGItemCategoryCrate;

        default:
            break;
    }

    if (itemId >= 101000 && itemId < 109000) {
        snprintf(outDisplay, outCap, isEn ? "Gun #%d" : "Súng (#%d)", itemId % 1000);
        return DSPUBGItemCategoryWeapon;
    }
    if (itemId >= 201000 && itemId < 202000) {
        snprintf(outDisplay, outCap, isEn ? "Scope #%d" : "Scope (#%d)", itemId % 1000);
        return DSPUBGItemCategoryScope;
    }
    if (itemId >= 501000 && itemId < 502000) {
        snprintf(outDisplay, outCap, isEn ? "Armor #%d" : "Giáp (#%d)", itemId % 10);
        return DSPUBGItemCategoryArmor;
    }
    if (itemId >= 502000 && itemId < 503000) {
        snprintf(outDisplay, outCap, isEn ? "Helmet #%d" : "Mũ (#%d)", itemId % 10);
        return DSPUBGItemCategoryArmor;
    }
    if (itemId >= 503000 && itemId < 504000) {
        snprintf(outDisplay, outCap, isEn ? "Bag #%d" : "Balo (#%d)", itemId % 10);
        return DSPUBGItemCategoryBag;
    }

    return DSPUBGItemCategoryNone;
}

static DSPUBGItemCategory ds_pubg_classify_vehicle_type(uint8_t vtype, char *outDisplay, size_t outCap) {
    if (vtype == 0 || !outDisplay || outCap < 4) return DSPUBGItemCategoryNone;
    outDisplay[0] = '\0';
    switch (vtype) {
        case 1: case 2: case 3: case 4:
            snprintf(outDisplay, outCap, "Xe Máy");
            return DSPUBGItemCategoryVehicle;
        case 5: case 6: case 7: case 8:
            snprintf(outDisplay, outCap, "Xe Dacia");
            return DSPUBGItemCategoryVehicle;
        case 9: case 10: case 11:
            snprintf(outDisplay, outCap, "Xe UAZ");
            return DSPUBGItemCategoryVehicle;
        case 12: case 13: case 14:
            snprintf(outDisplay, outCap, "Xe Buggy");
            return DSPUBGItemCategoryVehicle;
        case 15:
            snprintf(outDisplay, outCap, "Thuyền Cano");
            return DSPUBGItemCategoryVehicle;
        case 16:
            snprintf(outDisplay, outCap, "Moto Nước");
            return DSPUBGItemCategoryVehicle;
        case 17: case 18: case 19:
            snprintf(outDisplay, outCap, "Xe MiniBus");
            return DSPUBGItemCategoryVehicle;
        case 20: case 21: case 22: case 23: case 24: case 25: case 26: case 27: case 28:
            snprintf(outDisplay, outCap, "Xe Bán Tải");
            return DSPUBGItemCategoryVehicle;
        default:
            if (vtype > 0 && vtype <= 50) {
                snprintf(outDisplay, outCap, "Xe Ô Tô");
                return DSPUBGItemCategoryVehicle;
            }
            break;
    }
    return DSPUBGItemCategoryNone;
}

static DSPUBGItemCategory ds_pubg_classify_vehicle_shape(uint8_t shape, char *outDisplay, size_t outCap) {
    if (shape == 0 || !outDisplay || outCap < 4) return DSPUBGItemCategoryNone;
    outDisplay[0] = '\0';

    switch (shape) {
        case 1: case 2: case 28:
            snprintf(outDisplay, outCap, "Xe Máy");
            return DSPUBGItemCategoryVehicle;
        case 3: case 54:
            snprintf(outDisplay, outCap, "Xe Dacia");
            return DSPUBGItemCategoryVehicle;
        case 4:
            snprintf(outDisplay, outCap, "Xe MiniBus");
            return DSPUBGItemCategoryVehicle;
        case 5: case 6: case 55:
            snprintf(outDisplay, outCap, "Xe Bán Tải");
            return DSPUBGItemCategoryVehicle;
        case 7: case 56:
            snprintf(outDisplay, outCap, "Xe Buggy");
            return DSPUBGItemCategoryVehicle;
        case 8: case 9: case 10: case 13: case 33: case 57:
            snprintf(outDisplay, outCap, "Xe UAZ");
            return DSPUBGItemCategoryVehicle;
        case 11:
            snprintf(outDisplay, outCap, "Thuyền Cano");
            return DSPUBGItemCategoryVehicle;
        case 12:
            snprintf(outDisplay, outCap, "Moto Nước");
            return DSPUBGItemCategoryVehicle;
        case 14: case 15: case 52:
            snprintf(outDisplay, outCap, "Xe Mirado");
            return DSPUBGItemCategoryVehicle;
        case 16:
            snprintf(outDisplay, outCap, "Xe Bán Tải");
            return DSPUBGItemCategoryVehicle;
        case 17:
            snprintf(outDisplay, outCap, "Xe Scooter");
            return DSPUBGItemCategoryVehicle;
        case 18: case 20:
            snprintf(outDisplay, outCap, "Xe Tuyết");
            return DSPUBGItemCategoryVehicle;
        case 19:
            snprintf(outDisplay, outCap, "Xe TukTuk");
            return DSPUBGItemCategoryVehicle;
        case 23: case 58:
            snprintf(outDisplay, outCap, "Trực Thăng");
            return DSPUBGItemCategoryVehicle;
        case 24: case 88:
            snprintf(outDisplay, outCap, "Xe BRDM");
            return DSPUBGItemCategoryVehicle;
        case 25:
            snprintf(outDisplay, outCap, "Xe Lada Niva");
            return DSPUBGItemCategoryVehicle;
        case 27:
            snprintf(outDisplay, outCap, "Xe Loot Truck");
            return DSPUBGItemCategoryVehicle;
        case 29:
            snprintf(outDisplay, outCap, "Xe Model Y");
            return DSPUBGItemCategoryVehicle;
        case 30:
            snprintf(outDisplay, outCap, "Xe ATV");
            return DSPUBGItemCategoryVehicle;
        case 50: case 51:
            snprintf(outDisplay, outCap, "Xe Lamborghini");
            return DSPUBGItemCategoryVehicle;
        case 53:
            snprintf(outDisplay, outCap, "Xe Quái Thú");
            return DSPUBGItemCategoryVehicle;
        case 60:
            snprintf(outDisplay, outCap, "Tàu Bay Lượn");
            return DSPUBGItemCategoryVehicle;
        case 61:
            snprintf(outDisplay, outCap, "Xe Coupe RB");
            return DSPUBGItemCategoryVehicle;
        case 63: case 68: case 69: case 114:
            snprintf(outDisplay, outCap, "Xe Tăng");
            return DSPUBGItemCategoryVehicle;
        case 65: case 67:
            snprintf(outDisplay, outCap, "Xe Đạp");
            return DSPUBGItemCategoryVehicle;
        case 66:
            snprintf(outDisplay, outCap, "Xe UTV");
            return DSPUBGItemCategoryVehicle;
        case 70: case 71: case 72:
            snprintf(outDisplay, outCap, "Khủng Long");
            return DSPUBGItemCategoryVehicle;
        case 78: case 79: case 82:
            snprintf(outDisplay, outCap, "Robot Mecha");
            return DSPUBGItemCategoryVehicle;
        case 87: case 89: case 90:
            snprintf(outDisplay, outCap, "Chiến Mã");
            return DSPUBGItemCategoryVehicle;
        case 112:
            snprintf(outDisplay, outCap, "Xe Cảnh Sát");
            return DSPUBGItemCategoryVehicle;
        default:
            if (shape > 0 && shape <= 125) {
                snprintf(outDisplay, outCap, "Xe Ô Tô");
                return DSPUBGItemCategoryVehicle;
            }
            break;
    }
    return DSPUBGItemCategoryNone;
}

static DSPUBGItemCategory ds_pubg_identify_item(uint64_t actor, char *outDisplay, size_t outCap) {
    if (!actor || !outDisplay || outCap < 4 || !ds_pubg_valid(actor)) return DSPUBGItemCategoryNone;
    outDisplay[0] = '\0';

    // 0. Check bHidden in AActor (offset 0xE8)
    uint8_t aHidden = ds_pubg_read_u8(actor + 0xE8ULL);
    if (aHidden & 0x1) return DSPUBGItemCategoryNone;

    // Optional: Get actor name via GNames if available
    char actorName[64] = {0};
    bool hasName = ds_pubg_get_actor_name(actor, actorName, sizeof(actorName));

    if (hasName) {
        // Fast reject scenery, props, systems, volumes, decals, bullets, character meshes
        if (strcasestr(actorName, "StaticMesh") || strcasestr(actorName, "InstancedFoliage") ||
            strcasestr(actorName, "Foliage") || strcasestr(actorName, "Landscape") ||
            strcasestr(actorName, "Building") || strcasestr(actorName, "House") ||
            strcasestr(actorName, "Tree") || strcasestr(actorName, "Rock") ||
            strcasestr(actorName, "Wall") || strcasestr(actorName, "Fence") ||
            strcasestr(actorName, "Door") || strcasestr(actorName, "Window") ||
            strcasestr(actorName, "Stairs") || strcasestr(actorName, "Floor") ||
            strcasestr(actorName, "Roof") || strcasestr(actorName, "Brush") ||
            strcasestr(actorName, "Volume") || strcasestr(actorName, "NavMesh") ||
            strcasestr(actorName, "Light") || strcasestr(actorName, "Audio") ||
            strcasestr(actorName, "Sound") || strcasestr(actorName, "Particle") ||
            strcasestr(actorName, "Emitter") || strcasestr(actorName, "Effect") ||
            strcasestr(actorName, "Decal") || strcasestr(actorName, "Camera") ||
            strcasestr(actorName, "Controller") || strcasestr(actorName, "Player") ||
            strcasestr(actorName, "Character") || strcasestr(actorName, "Pawn") ||
            strcasestr(actorName, "WorldSettings") || strcasestr(actorName, "GameMode") ||
            strcasestr(actorName, "GameState") || strcasestr(actorName, "Bullet") ||
            strcasestr(actorName, "Proj") || strcasestr(actorName, "Shell") ||
            strcasestr(actorName, "Cartridge") || strcasestr(actorName, "Trace") ||
            strcasestr(actorName, "Grenade") || strcasestr(actorName, "Smoke") ||
            strcasestr(actorName, "Flash") || strcasestr(actorName, "Explo") ||
            strcasestr(actorName, "Fire") || strcasestr(actorName, "Flame") ||
            strcasestr(actorName, "Trigger") || strcasestr(actorName, "Spawner") ||
            strcasestr(actorName, "Collision") || strcasestr(actorName, "Physics")) {
            return DSPUBGItemCategoryNone;
        }

        // 1. Vehicle check by name
        bool isVehicleActor = (strcasestr(actorName, "Vehicle") != nullptr) ||
                              (strcasestr(actorName, "VH_") != nullptr) ||
                              (strcasestr(actorName, "Jeep") != nullptr) ||
                              (strcasestr(actorName, "UAZ") != nullptr) ||
                              (strcasestr(actorName, "Dacia") != nullptr) ||
                              (strcasestr(actorName, "Sedan") != nullptr) ||
                              (strcasestr(actorName, "Buggy") != nullptr) ||
                              (strcasestr(actorName, "Motorcycle") != nullptr) ||
                              (strcasestr(actorName, "Motorbike") != nullptr) ||
                              (strcasestr(actorName, "Bike") != nullptr) ||
                              (strcasestr(actorName, "Scooter") != nullptr) ||
                              (strcasestr(actorName, "TukTuk") != nullptr) ||
                              (strcasestr(actorName, "MiniBus") != nullptr) ||
                              (strcasestr(actorName, "Bus_") != nullptr) ||
                              (strcasestr(actorName, "PG117") != nullptr) ||
                              (strcasestr(actorName, "Boat") != nullptr) ||
                              (strcasestr(actorName, "Cano") != nullptr) ||
                              (strcasestr(actorName, "AquaRail") != nullptr) ||
                              (strcasestr(actorName, "JetSki") != nullptr) ||
                              (strcasestr(actorName, "BRDM") != nullptr) ||
                              (strcasestr(actorName, "Coupe") != nullptr) ||
                              (strcasestr(actorName, "MonsterTruck") != nullptr) ||
                              (strcasestr(actorName, "BigFoot") != nullptr) ||
                              (strcasestr(actorName, "Mirado") != nullptr) ||
                              (strcasestr(actorName, "Lada") != nullptr) ||
                              (strcasestr(actorName, "Snowmobile") != nullptr) ||
                              (strcasestr(actorName, "Snowbike") != nullptr) ||
                              (strcasestr(actorName, "Bicycle") != nullptr) ||
                              (strcasestr(actorName, "Tank") != nullptr) ||
                              (strcasestr(actorName, "Helicopter") != nullptr) ||
                              (strcasestr(actorName, "DirectFly") != nullptr) ||
                              (strcasestr(actorName, "Lamborghini") != nullptr) ||
                              (strcasestr(actorName, "Tesla") != nullptr) ||
                              (strcasestr(actorName, "ModelY") != nullptr) ||
                              (strcasestr(actorName, "UTV") != nullptr) ||
                              (strcasestr(actorName, "ATV") != nullptr) ||
                              (strcasestr(actorName, "Rony") != nullptr);

        if (isVehicleActor) {
            if (strcasestr(actorName, "Jeep") || strcasestr(actorName, "UAZ")) {
                snprintf(outDisplay, outCap, "Xe UAZ");
            } else if (strcasestr(actorName, "Sedan") || strcasestr(actorName, "Dacia")) {
                snprintf(outDisplay, outCap, "Xe Dacia");
            } else if (strcasestr(actorName, "Buggy")) {
                snprintf(outDisplay, outCap, "Xe Buggy");
            } else if (strcasestr(actorName, "VH_PickUp") || strcasestr(actorName, "VH_Pickup") || (strcasestr(actorName, "Truck") && !strcasestr(actorName, "Monster")) || strcasestr(actorName, "Rony")) {
                snprintf(outDisplay, outCap, "Xe Bán Tải");
            } else if (strcasestr(actorName, "Motorcycle") || strcasestr(actorName, "Motorbike") || strcasestr(actorName, "VH_Motor") || strcasestr(actorName, "Bike")) {
                snprintf(outDisplay, outCap, "Xe Máy");
            } else if (strcasestr(actorName, "Scooter")) {
                snprintf(outDisplay, outCap, "Xe Scooter");
            } else if (strcasestr(actorName, "TukTuk")) {
                snprintf(outDisplay, outCap, "Xe TukTuk");
            } else if (strcasestr(actorName, "MiniBus") || strcasestr(actorName, "Bus_")) {
                snprintf(outDisplay, outCap, "Xe MiniBus");
            } else if (strcasestr(actorName, "PG117") || strcasestr(actorName, "Boat") || strcasestr(actorName, "Cano")) {
                snprintf(outDisplay, outCap, "Thuyền Cano");
            } else if (strcasestr(actorName, "AquaRail") || strcasestr(actorName, "JetSki")) {
                snprintf(outDisplay, outCap, "Moto Nước");
            } else if (strcasestr(actorName, "BRDM")) {
                snprintf(outDisplay, outCap, "Xe BRDM");
            } else if (strcasestr(actorName, "Coupe") || strcasestr(actorName, "CoupeRB")) {
                snprintf(outDisplay, outCap, "Xe Coupe RB");
            } else if (strcasestr(actorName, "Mirado")) {
                snprintf(outDisplay, outCap, "Xe Mirado");
            } else if (strcasestr(actorName, "MonsterTruck") || strcasestr(actorName, "BigFoot")) {
                snprintf(outDisplay, outCap, "Xe Quái Thú");
            } else if (strcasestr(actorName, "Lada")) {
                snprintf(outDisplay, outCap, "Xe Lada Niva");
            } else if (strcasestr(actorName, "Snowmobile") || strcasestr(actorName, "Snowbike")) {
                snprintf(outDisplay, outCap, "Xe Tuyết");
            } else if (strcasestr(actorName, "Bicycle")) {
                snprintf(outDisplay, outCap, "Xe Đạp");
            } else if (strcasestr(actorName, "Tank")) {
                snprintf(outDisplay, outCap, "Xe Tăng");
            } else if (strcasestr(actorName, "Helicopter") || strcasestr(actorName, "DirectFly")) {
                snprintf(outDisplay, outCap, "Trực Thăng");
            } else if (strcasestr(actorName, "Lamborghini")) {
                snprintf(outDisplay, outCap, "Xe Lamborghini");
            } else if (strcasestr(actorName, "Tesla") || strcasestr(actorName, "ModelY")) {
                snprintf(outDisplay, outCap, "Xe Model Y");
            } else if (strcasestr(actorName, "UTV")) {
                snprintf(outDisplay, outCap, "Xe UTV");
            } else if (strcasestr(actorName, "ATV")) {
                snprintf(outDisplay, outCap, "Xe ATV");
            } else {
                uint8_t shape = ds_pubg_read_u8(actor + 0x70DULL);
                if (shape > 0 && shape <= 125) {
                    DSPUBGItemCategory cat = ds_pubg_classify_vehicle_shape(shape, outDisplay, outCap);
                    if (cat != DSPUBGItemCategoryNone) return cat;
                }
                uint8_t vtype = ds_pubg_read_u8(actor + 0x70CULL);
                if (vtype > 0 && vtype <= 30) {
                    DSPUBGItemCategory cat = ds_pubg_classify_vehicle_type(vtype, outDisplay, outCap);
                    if (cat != DSPUBGItemCategoryNone) return cat;
                }
                snprintf(outDisplay, outCap, "Xe Ô Tô");
            }
            return DSPUBGItemCategoryVehicle;
        }

        // 2. AirDrop / DeathBox / Drop check by name
        if (strstr(actorName, "AirDrop")) {
            uint8_t isEmpty = ds_pubg_read_u8(actor + 0x729ULL) & 1;
            if (isEmpty) return DSPUBGItemCategoryNone;
            uint8_t isSuper = ds_pubg_read_u8(actor + 0x5C0ULL) & 1;
            snprintf(outDisplay, outCap, isSuper ? "THÍNH ĐỎ" : "HÒM THÍNH");
            return DSPUBGItemCategoryCrate;
        }
        if (strstr(actorName, "TombBox") || strstr(actorName, "DeadBox") || strstr(actorName, "PlayerDeadInventoryBox")) {
            snprintf(outDisplay, outCap, "Hòm Xác");
            return DSPUBGItemCategoryCrate;
        }
        if (strstr(actorName, "PickUpListWrapper")) {
            snprintf(outDisplay, outCap, "Đồ Rơi");
            return DSPUBGItemCategoryCrate;
        }

        // 3. Direct Item Name classification
        DSPUBGItemCategory strCat = ds_pubg_classify_item(actorName, outDisplay, outCap);
        if (strCat != DSPUBGItemCategoryNone) {
            return strCat;
        }

        // 4. Wrapper Actor check
        if (strstr(actorName, "Wrapper") || strstr(actorName, "PickUp") || strstr(actorName, "Pickup")) {
            uint8_t pickedUp = ds_pubg_read_u8(actor + 0x615ULL) & 1;
            if (pickedUp) return DSPUBGItemCategoryNone;

            int typeSpecificID = ds_pubg_read_i32(actor + 0x5FCULL);
            int itemId = ds_pubg_read_i32(actor + 0x758ULL);
            int targetId = (typeSpecificID >= 101001 && typeSpecificID <= 699999) ? typeSpecificID :
                           ((itemId >= 101001 && itemId <= 699999) ? itemId : 0);
            if (targetId > 0) {
                DSPUBGItemCategory idCat = ds_pubg_classify_item_id(targetId, outDisplay, outCap);
                if (idCat != DSPUBGItemCategoryNone) return idCat;
            }
        }

        // If actor has a name and none of the above matched, it is definitely not an item or vehicle!
        return DSPUBGItemCategoryNone;
    }

    // Name resolution failed (hasName == false) - Use strict multi-field memory checks
    // Check if it's already picked up
    uint8_t pickedUp = ds_pubg_read_u8(actor + 0x615ULL) & 1;
    if (pickedUp) return DSPUBGItemCategoryNone;

    // Check Ground Item ID at 0x5FC or 0x758
    int typeSpecificID = ds_pubg_read_i32(actor + 0x5FCULL);
    int itemId = ds_pubg_read_i32(actor + 0x758ULL);
    int targetId = (typeSpecificID >= 101001 && typeSpecificID <= 699999) ? typeSpecificID :
                   ((itemId >= 101001 && itemId <= 699999) ? itemId : 0);
    if (targetId > 0) {
        DSPUBGItemCategory idCat = ds_pubg_classify_item_id(targetId, outDisplay, outCap);
        if (idCat != DSPUBGItemCategoryNone) return idCat;
    }

    // Check AirDrop
    int airdropId = ds_pubg_read_i32(actor + 0x5B0ULL);
    if (airdropId > 0 && airdropId < 1000) {
        float dropSpd = ds_pubg_read_f32(actor + 0x56CULL);
        uint8_t aFlag = ds_pubg_read_u8(actor + 0x5C0ULL);
        if (!isnan(dropSpd) && dropSpd >= -3000.0f && dropSpd <= 3000.0f && aFlag <= 2) {
            uint8_t isEmpty = ds_pubg_read_u8(actor + 0x729ULL) & 1;
            if (!isEmpty) {
                snprintf(outDisplay, outCap, (aFlag & 1) ? "THÍNH ĐỎ" : "HÒM THÍNH");
                return DSPUBGItemCategoryCrate;
            }
        }
    }

    // Check DeathBox
    uint8_t boxType = ds_pubg_read_u8(actor + 0x641ULL);
    uint32_t tombOwner = ds_pubg_read_u32(actor + 0x660ULL);
    if (boxType > 0 && boxType < 10 && tombOwner > 0) {
        snprintf(outDisplay, outCap, "Hòm Xác");
        return DSPUBGItemCategoryCrate;
    }

    // Check Vehicle via strict pointer triad (Common + Seats + Damage)
    uint64_t vCommon = ds_pubg_read_ptr(actor + 0xC08ULL);
    uint64_t vSeats  = ds_pubg_read_ptr(actor + 0xBF0ULL);
    uint64_t vDamage = ds_pubg_read_ptr(actor + 0xC00ULL);
    if (vCommon && vSeats && vDamage) {
        float hpMax = ds_pubg_read_f32(vCommon + 0x350ULL);
        uint8_t shape = ds_pubg_read_u8(actor + 0x70DULL);
        uint8_t vtype = ds_pubg_read_u8(actor + 0x70CULL);
        if (!isnan(hpMax) && hpMax >= 500.0f && hpMax <= 10000.0f &&
            ((shape > 0 && shape <= 125) || (vtype > 0 && vtype <= 30))) {
            if (shape > 0 && shape <= 125) {
                DSPUBGItemCategory cat = ds_pubg_classify_vehicle_shape(shape, outDisplay, outCap);
                if (cat != DSPUBGItemCategoryNone) return cat;
            }
            if (vtype > 0 && vtype <= 30) {
                DSPUBGItemCategory cat = ds_pubg_classify_vehicle_type(vtype, outDisplay, outCap);
                if (cat != DSPUBGItemCategoryNone) return cat;
            }
            snprintf(outDisplay, outCap, "Xe Ô Tô");
            return DSPUBGItemCategoryVehicle;
        }
    }

    return DSPUBGItemCategoryNone;
}

struct CrateItemInfo {
    char name[36];
    DSPUBGItemCategory category;
    int priority;
};

static std::vector<CrateItemInfo> ds_pubg_get_crate_items(uint64_t crateActor) {
    std::vector<CrateItemInfo> results;
    if (!crateActor || !ds_pubg_valid(crateActor)) return results;

    uint8_t isEmpty = ds_pubg_read_u8(crateActor + 0x729ULL) & 1;
    if (isEmpty) return results;

    std::vector<uint64_t> targets;
    targets.push_back(crateActor);

    // Look for attached wrappers or inventory components
    static const uint64_t kCompOffsets[] = {
        0x5B8ULL, 0x5C8ULL, 0x620ULL, 0x630ULL, 0x640ULL, 0x650ULL, 0x660ULL, 0x680ULL, 0x6F0ULL, 0x700ULL
    };
    for (uint64_t cOff : kCompOffsets) {
        uint64_t comp = ds_pubg_read_ptr(crateActor + cOff);
        if (comp && comp != crateActor && ds_pubg_valid(comp)) {
            targets.push_back(comp);
        }
    }

    auto addItem = [&](int itemId, int count) {
        if (itemId < 101001 || itemId > 699999) return;
        char dName[36] = {0};
        DSPUBGItemCategory cat = ds_pubg_classify_item_id(itemId, dName, sizeof(dName));
        if (cat == DSPUBGItemCategoryNone) return;

        int prio = 10;
        if (itemId == 101004 || itemId == 103003 || itemId == 101005 || itemId == 103007 ||
            itemId == 105003 || itemId == 103013 || itemId == 102008 || itemId == 101006 ||
            itemId == 106007 || itemId == 101008 || itemId == 103001 || itemId == 103002) {
            prio = 1; // M416, AWM, Groza, Mk14, MG3, AMR, P90, AUG, Flare Gun, M762, Kar98k, M24
        } else if (cat == DSPUBGItemCategoryWeapon) {
            prio = 2; // Other weapons
        } else if (itemId == 501003 || itemId == 501006 || itemId == 502003 || itemId == 503003) {
            prio = 3; // L3 Armor, Helmet, Bag
        } else if (itemId == 201005 || itemId == 201010 || itemId == 201012) {
            prio = 4; // Scope 8x, 6x, 15x
        } else if (itemId == 501002 || itemId == 501005 || itemId == 502002 || itemId == 503002) {
            prio = 5; // L2 Armor, Helmet, Bag
        } else if (itemId == 201004 || itemId == 201009) {
            prio = 6; // Scope 4x, 3x
        } else if (itemId == 601003 || itemId == 601006 || itemId == 601002) {
            prio = 7; // Med Kit, Adrenaline, First Aid
        } else if (itemId == 305001 || itemId == 303001 || itemId == 302001) {
            prio = 8; // Ammo
        }

        // Avoid exact duplicates in list
        for (const auto &ex : results) {
            if (strcmp(ex.name, dName) == 0) return;
        }

        CrateItemInfo info;
        strncpy(info.name, dName, sizeof(info.name) - 1);
        info.name[sizeof(info.name) - 1] = '\0';
        info.category = cat;
        info.priority = prio;
        results.push_back(info);
    };

    for (uint64_t target : targets) {
        if (!target || !ds_pubg_valid(target)) continue;

        for (uint64_t off = 0x580ULL; off <= 0x980ULL; off += 8ULL) {
            uint64_t dataPtr = ds_pubg_read_ptr(target + off);
            if (!dataPtr || !ds_pubg_valid(dataPtr)) continue;

            uint32_t count = ds_pubg_read_u32(target + off + 8ULL);
            if (count == 0 || count > 64) continue;
            uint32_t max = ds_pubg_read_u32(target + off + 12ULL);
            if (max < count || max > 128) continue;

            // Test if pointer array
            int validItemsPtr = 0;
            int testLimit = (count > 6) ? 6 : (int)count;
            for (int t = 0; t < testLimit; t++) {
                uint64_t obj = ds_pubg_read_ptr(dataPtr + t * 8ULL);
                if (obj && ds_pubg_valid(obj)) {
                    int id = ds_pubg_read_i32(obj + 0x5FCULL);
                    if (id < 101001 || id > 699999) id = ds_pubg_read_i32(obj + 0x758ULL);
                    if (id < 101001 || id > 699999) id = ds_pubg_read_i32(obj + 0x2F4ULL);
                    if (id < 101001 || id > 699999) id = ds_pubg_read_i32(obj + 0xCCULL);
                    if (id >= 101001 && id <= 699999) validItemsPtr++;
                }
            }

            if (validItemsPtr > 0) {
                for (uint32_t i = 0; i < count; i++) {
                    uint64_t obj = ds_pubg_read_ptr(dataPtr + i * 8ULL);
                    if (!obj || !ds_pubg_valid(obj)) continue;
                    int id = ds_pubg_read_i32(obj + 0x5FCULL);
                    if (id < 101001 || id > 699999) id = ds_pubg_read_i32(obj + 0x758ULL);
                    if (id < 101001 || id > 699999) id = ds_pubg_read_i32(obj + 0x2F4ULL);
                    if (id < 101001 || id > 699999) id = ds_pubg_read_i32(obj + 0xCCULL);
                    int qty = ds_pubg_read_i32(obj + 0x618ULL);
                    addItem(id, qty);
                }
                break;
            }

            // Test struct array
            static const int kStrides[] = { 48, 56, 64, 40, 32, 72, 80 };
            static const int kIdOffsets[] = { 4, 0, 8, 12, 16, 20 };
            int bestStride = 0, bestIdOff = 0, bestMatchCount = 0;

            for (int stride : kStrides) {
                for (int idOff : kIdOffsets) {
                    int matches = 0;
                    for (int t = 0; t < testLimit; t++) {
                        int id = ds_pubg_read_i32(dataPtr + t * stride + idOff);
                        if (id >= 101001 && id <= 699999) matches++;
                    }
                    if (matches > bestMatchCount) {
                        bestMatchCount = matches;
                        bestStride = stride;
                        bestIdOff = idOff;
                    }
                }
                if (bestMatchCount >= 2 || (count == 1 && bestMatchCount == 1)) break;
            }

            if (bestMatchCount > 0) {
                for (uint32_t i = 0; i < count; i++) {
                    uint64_t elem = dataPtr + i * bestStride;
                    int id = ds_pubg_read_i32(elem + bestIdOff);
                    int qty = ds_pubg_read_i32(elem + bestIdOff + 4);
                    addItem(id, qty);
                }
                break;
            }
        }
        if (!results.empty()) break;
    }

    if (!results.empty()) {
        std::sort(results.begin(), results.end(), [](const CrateItemInfo &a, const CrateItemInfo &b) {
            if (a.priority != b.priority) return a.priority < b.priority;
            return strcmp(a.name, b.name) < 0;
        });
        if (results.size() > 10) results.resize(10);
    }
    return results;
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
                if (!g_dspubgGNames) {
                    ds_pubg_try_known_gnames(vmMap, base);
                }
                if (!g_dspubgGNames) {
                    std::vector<ScanRange> ranges;
                    if (ds_pubg_get_data_ranges(vmMap, base, ranges)) ds_pubg_scan_for_gnames(vmMap, ranges);
                }
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
                if (!g_dspubgGNames) {
                    ds_pubg_try_known_gnames(vmMap, base);
                }
                if (!g_dspubgGNames) {
                    std::vector<ScanRange> ranges;
                    if (ds_pubg_get_data_ranges(vmMap, base, ranges)) ds_pubg_scan_for_gnames(vmMap, ranges);
                }
                return true;
            }
        }
    }

    // 3. Parse Mach-O load commands to scan __DATA sections (__bss, __common, __data)
    std::vector<ScanRange> scanRanges;
    if (!ds_pubg_get_data_ranges(vmMap, base, scanRanges)) return false;

    if (!g_dspubgGNames) {
        ds_pubg_try_known_gnames(vmMap, base);
        if (!g_dspubgGNames) {
            ds_pubg_scan_for_gnames(vmMap, scanRanges);
        }
    }

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
    g_dspubgGNames = 0;
    g_dspubgLastActorsCount = 0;
    g_dspubgLastEnemyCount = 0;
    g_dspubgLastBotCount = 0;
    g_dspubgLastBoneOff = 0;
    g_dspubgNextScan = 0;
    g_dspubgLocalPawn = 0;
    g_dspubgTargetActive.store(false, std::memory_order_release);
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    g_dspubgPlayerCount = 0;
    g_dspubgItemCount = 0;
    memset(g_dspubgPlayers, 0, sizeof(g_dspubgPlayers));
    memset(g_dspubgItems, 0, sizeof(g_dspubgItems));
    memset(g_dspubgActorCache, 0, sizeof(g_dspubgActorCache));
    ++g_dspubgEpoch;
    ++g_dspubgItemEpoch;
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
    // If c2w translation is valid, use it directly (exact UE4 mesh world transform).
    // Only fallback to rootLoc if c2w translation is uninitialized/corrupt.
    float meshOriginZ = rootLoc.Z - halfH;
    float dX = tx - rootLoc.X;
    float dY = ty - rootLoc.Y;
    float distSq = dX * dX + dY * dY;
    if (isnan(tx) || isinf(tx) || isnan(ty) || isinf(ty) || isnan(tz) || isinf(tz) ||
        (fabsf(tx) < 1.0f && fabsf(ty) < 1.0f) || distSq > (500.0f * 500.0f)) {
        tx = rootLoc.X;
        ty = rootLoc.Y;
        tz = meshOriginZ;
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

static int ds_pubg_copy_projected_items(DSPUBGProjectedItem out[kDSPUBGMaxItems], uint64_t *epochOut) {
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    int count = g_dspubgItemCount;
    if (count > kDSPUBGMaxItems) count = kDSPUBGMaxItems;
    if (count > 0 && out) {
        memcpy(out, g_dspubgItems, count * sizeof(DSPUBGProjectedItem));
    }
    if (epochOut) *epochOut = g_dspubgItemEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
    return count;
}

static int ds_pubg_copy_projected_grenades(DSPUBGProjectedGrenade out[kDSPUBGMaxGrenades], uint64_t *epochOut) {
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    int count = g_dspubgGrenadeCount;
    if (count > kDSPUBGMaxGrenades) count = kDSPUBGMaxGrenades;
    if (count > 0 && out) {
        memcpy(out, g_dspubgGrenades, count * sizeof(DSPUBGProjectedGrenade));
    }
    if (epochOut) *epochOut = g_dspubgGrenadeEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
    return count;
}

static void ds_pubg_overlay_reset(void) {
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    g_dspubgPlayerCount = 0;
    g_dspubgItemCount = 0;
    g_dspubgGrenadeCount = 0;
    g_dspubgTotalEnemies = 0;
    g_dspubgTotalBots = 0;
    memset(g_dspubgPlayers, 0, sizeof(g_dspubgPlayers));
    memset(g_dspubgItems, 0, sizeof(g_dspubgItems));
    memset(g_dspubgGrenades, 0, sizeof(g_dspubgGrenades));
    memset(g_dspubgActorCache, 0, sizeof(g_dspubgActorCache));
    ++g_dspubgEpoch;
    ++g_dspubgItemEpoch;
    ++g_dspubgGrenadeEpoch;
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
    g_dspubgLocalPawn = localPawn;
    uint64_t cameraManager = playerController ? ds_pubg_read_ptr(playerController + kDSPUBGPlayerControllerCameraMgrOffset) : 0;

    DSPUBGVector camLoc = {};
    DSPUBGRotator camRot = {};
    float camFOV = 90.0f;
    float camAspect = 0.0f;

    if (cameraManager) {
        // 1. Primary: CameraCache.POV (0x520 + 0x10 = 0x530)
        // CameraCache contains the post-update, post-modifier camera transform directly used
        // by the GPU render pass every frame. It tracks camera rotation with zero latency!
        uint64_t cachePov = cameraManager + 0x520ULL + 0x10ULL;
        DSPUBGVector cLoc = {};
        DSPUBGRotator cRot = {};
        float cFOV = 0.0f;
        if (ds_pubg_read(cachePov + kDSPUBGPOVLocationOffset, &cLoc, sizeof(cLoc)) &&
            ds_pubg_read(cachePov + kDSPUBGPOVRotationOffset, &cRot, sizeof(cRot)) &&
            ds_pubg_read(cachePov + kDSPUBGPOVFOVOffset, &cFOV, sizeof(cFOV)) &&
            !isnan(cLoc.X) && !isinf(cLoc.X) && (fabsf(cLoc.X) > 1.0f || fabsf(cLoc.Y) > 1.0f) &&
            !isnan(cRot.Pitch) && !isnan(cRot.Yaw) && cFOV >= 20.0f && cFOV <= 160.0f) {
            camLoc = cLoc;
            camRot = cRot;
            camFOV = cFOV;
        } else {
            // 2. Secondary fallback: ViewTarget.POV (0x10A0 + 0x10 = 0x10B0)
            uint64_t pov = cameraManager + kDSPUBGCameraViewTargetOffset + kDSPUBGViewTargetPOVOffset;
            ds_pubg_read(pov + kDSPUBGPOVLocationOffset, &camLoc, sizeof(camLoc));
            ds_pubg_read(pov + kDSPUBGPOVRotationOffset, &camRot, sizeof(camRot));
            ds_pubg_read(pov + kDSPUBGPOVFOVOffset, &camFOV, sizeof(camFOV));
            ds_pubg_read(pov + kDSPUBGPOVAspectOffset, &camAspect, sizeof(camAspect));
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

    auto processPawn = [&](uint64_t pawn, uint64_t psHint, bool knownBot) -> bool {
        if (!pawn || pawn == localPawn || !ds_pubg_valid(pawn)) return false;
        for (uint64_t seen : seenPawns) {
            if (seen == pawn) return false;
        }

        uint32_t cSlot = ds_pubg_actor_cache_hash(pawn);
        DSPUBGActorCacheEntry &cEntry = g_dspubgActorCache[cSlot];
        if (cEntry.actor == pawn) {
            if (cEntry.isScenery) {
                return false;
            }
        }

        // 0. Fast reject non-character actors by name
        char pawnName[64] = {0};
        bool hasPawnName = ds_pubg_get_actor_name(pawn, pawnName, sizeof(pawnName));
        if (hasPawnName) {
            bool isScenery = (strstr(pawnName, "StaticMesh") || strstr(pawnName, "Foliage") ||
                strstr(pawnName, "Landscape") || strstr(pawnName, "Building") ||
                strstr(pawnName, "House") || strstr(pawnName, "Tree") ||
                strstr(pawnName, "Rock") || strstr(pawnName, "Wall") ||
                strstr(pawnName, "Fence") || strstr(pawnName, "Door") ||
                strstr(pawnName, "Window") || strstr(pawnName, "Floor") ||
                strstr(pawnName, "Roof") || strstr(pawnName, "Brush"));
            if (isScenery) {
                cEntry.actor = pawn;
                cEntry.isScenery = true;
                cEntry.isPawn = false;
                cEntry.itemCat = DSPUBGItemCategoryNone;
                return false;
            }

            if (strstr(pawnName, "Bullet") || strstr(pawnName, "Proj") || strstr(pawnName, "Weapon") ||
                strstr(pawnName, "PickUp") || strstr(pawnName, "Vehicle") || strstr(pawnName, "VH_") ||
                strstr(pawnName, "Drop") || strstr(pawnName, "Tomb") || strstr(pawnName, "Box") ||
                strstr(pawnName, "Supply") || strstr(pawnName, "Particle") || strstr(pawnName, "Effect") ||
                strstr(pawnName, "Decal") || strstr(pawnName, "Camera") || strstr(pawnName, "Volume") ||
                strstr(pawnName, "Trigger") || strstr(pawnName, "AirDrop") || strstr(pawnName, "Item") ||
                strstr(pawnName, "Controller") || strstr(pawnName, "Light") || strstr(pawnName, "Audio") ||
                strstr(pawnName, "Sound") || strstr(pawnName, "Zone") || strstr(pawnName, "Fog") ||
                strstr(pawnName, "Shell") || strstr(pawnName, "Cartridge") || strstr(pawnName, "Trace") ||
                strstr(pawnName, "Grenade") || strstr(pawnName, "Smoke") || strstr(pawnName, "Explosion")) {
                return false;
            }
        }

        // 1. Reject local player's own bullets, weapons, projectiles
        uint64_t owner = ds_pubg_read_ptr(pawn + 0x140ULL);
        uint64_t instigator = ds_pubg_read_ptr(pawn + 0x138ULL);
        if (localPawn && (owner == localPawn || instigator == localPawn)) {
            return false;
        }

        // 2. Check bHidden in AActor (offset 0xE8)
        uint8_t aHidden = ds_pubg_read_u8(pawn + 0xE8ULL);
        if (aHidden & 0x1) return false;

        // 3. Dead check - STExtraCharacter.bDead at 0xE7C
        uint8_t isDead = ds_pubg_read_u8(pawn + kDSPUBGCharacterDeadOffset) & 1;
        if (isDead) return false;

        // 4. Must have valid RootComponent and Mesh (standard UE4 character)
        uint64_t rootComp = ds_pubg_read_ptr(pawn + kDSPUBGActorRootComponentOffset);
        if (!rootComp) rootComp = ds_pubg_read_ptr(pawn + 0x180ULL);
        if (!rootComp || !ds_pubg_valid(rootComp)) return false;

        uint64_t meshComp = ds_pubg_read_ptr(pawn + kDSPUBGCharacterMeshOffset);
        if (!meshComp) meshComp = ds_pubg_read_ptr(pawn + 0x320ULL);
        if (!meshComp || !ds_pubg_valid(meshComp)) return false;

        // 5. Strict Health validation (Reject all non-characters and dead bodies):
        float health = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthOffset);
        float healthMax = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthMaxOffset);
        if (isnan(health) || isinf(health) || isnan(healthMax) || isinf(healthMax)) return false;

        if (healthMax < 50.0f || healthMax > 2000.0f) return false;

        bool isKnocked = false;
        // Check multiple possible GroggyHealth offsets in STExtraCharacter: 0xE68, 0xE6C, 0xE70, 0xE74
        float gh = ds_pubg_read_f32(pawn + 0xE68ULL);
        if (isnan(gh) || isinf(gh) || gh <= 0.0f || gh > 200.0f) {
            gh = ds_pubg_read_f32(pawn + 0xE6CULL);
        }
        if (isnan(gh) || isinf(gh) || gh <= 0.0f || gh > 200.0f) {
            gh = ds_pubg_read_f32(pawn + 0xE70ULL);
        }
        if (isnan(gh) || isinf(gh) || gh <= 0.0f || gh > 200.0f) {
            gh = ds_pubg_read_f32(pawn + 0xE74ULL);
        }

        // If bDead (offset 0xE7C) is 0, but standard health <= 0, the player is knocked down (gục ngã)!
        if (health <= 0.0f) {
            isKnocked = true;
            if (!isnan(gh) && !isinf(gh) && gh > 0.0f && gh <= 200.0f) {
                health = gh;
            } else {
                health = 100.0f; // Default knocked health if groggy offset shifted
            }
        } else if (!isnan(gh) && !isinf(gh) && gh > 0.0f && gh <= 200.0f && gh < health) {
            // Some versions update groggy health before main health
            isKnocked = true;
            health = gh;
        }

        if (health <= 0.0f || health > healthMax + 50.0f) return false;

        // 6. Team filter:
        int32_t teamId = ds_pubg_read_i32(pawn + kDSPUBGCharacterTeamIDOffset);
        if (localTeamId > 0 && teamId == localTeamId) {
            return false;
        }
        if (teamId < 0 || teamId > 200000000) {
            teamId = -1;
        }

        seenPawns.push_back(pawn);

        DSPUBGVector rootLoc = {};
        if (!ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc))) {
            return false;
        }
        if (isnan(rootLoc.X) || isinf(rootLoc.X) || (fabsf(rootLoc.X) < 1.0f && fabsf(rootLoc.Y) < 1.0f)) {
            return false;
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
            return false;
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
            float actorH = 165.0f;
            if (isKnocked) {
                actorH = 45.0f;
            } else if (extZ >= 30.0f && extZ <= 95.0f) {
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

                    uint8_t boneBuf[68 * 48];
                    uint32_t needReadCount = (bCount > 68) ? 68 : bCount;
                    size_t readSize = (size_t)needReadCount * 48;
                    if (ds_pubg_read(boneData, boneBuf, readSize)) {
                        auto getBoneLocal = [&](int idx, DSPUBGVector &outV) -> bool {
                            if (idx < 0 || idx >= (int)needReadCount) return false;
                            const uint8_t *boneEntry = boneBuf + (size_t)idx * 48;
                            memcpy(&outV.X, boneEntry + 0x10, 4);
                            memcpy(&outV.Y, boneEntry + 0x14, 4);
                            memcpy(&outV.Z, boneEntry + 0x18, 4);
                            return (!isnan(outV.X) && !isinf(outV.X) && !isnan(outV.Y) && !isinf(outV.Y) && !isnan(outV.Z) && !isinf(outV.Z));
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

                            // Right Arm (stable UE4 humanoid rig: UpperArm=13, LowerArm=15, Hand=16):
                            bUprR = 13; bLwrR = 15; bHandR = 16;

                            // Left Arm (stable UE4 humanoid rig: UpperArm=34, LowerArm=36, Hand=37):
                            bUprL = 34; bLwrL = 36; bHandL = 37;

                            // Dynamic Armed vs Unarmed Leg Selection:
                            // Unarmed (tay không / gục ngã): Right={55, 56, 57}, Left={59, 60, 61}
                            // Armed (cầm súng):             Right={57, 58, 59}, Left={53, 54, 55}
                            bool isArmedPose = (p.weaponName[0] != '\0');
                            if (!isArmedPose && !p.isKnocked) {
                                DSPUBGVector pelvisLoc = {}, bone61Loc = {};
                                if (getBoneLocal(1, pelvisLoc) && getBoneLocal(61, bone61Loc)) {
                                    if (bone61Loc.Z >= pelvisLoc.Z - 35.0f) {
                                        isArmedPose = true;
                                    }
                                }
                            }

                            if (isArmedPose) {
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

                        uint8_t c2w[48] = {0};
                        ds_pubg_read_c2w(meshComp, rootLoc, halfH, c2w);

                        int okBones = 0;
                        for (int i = 0; i < 15; i++) {
                            int bi = jointIndices[i];
                            DSPUBGVector localTrans = {};
                            if (getBoneLocal(bi, localTrans)) {
                                DSPUBGVector world = {};
                                ds_pubg_bone_world_from_local(c2w, rootLoc, halfH, actorRot, &localTrans, &world);
                                float sx_proj = 0, sy_proj = 0, d_proj = 0;
                                if (ds_pubg_cam_basis_project(basis, world, sx_proj, sy_proj, d_proj)) {
                                    p.skeleton[i] = { sx_proj, sy_proj, true };
                                    okBones++;
                                }
                            }
                        }

                        // Project HeadTop for circle at vHead.Z += 7.0f (exact internal snippet logic)
                        DSPUBGVector headLocal = {};
                        if (getBoneLocal(bHead, headLocal)) {
                            DSPUBGVector headTopLocal = headLocal;
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

                            float minBoneY = 99999.0f, maxBoneY = -99999.0f;
                            for (int bi = 0; bi < 16; bi++) {
                                if (p.skeleton[bi].valid) {
                                    if (p.skeleton[bi].y < minBoneY) minBoneY = p.skeleton[bi].y;
                                    if (p.skeleton[bi].y > maxBoneY) maxBoneY = p.skeleton[bi].y;
                                }
                            }
                            if (okBones >= 6 && maxBoneY > minBoneY + 8.0f) {
                                float realTop = (p.skeleton[15].valid) ? (p.skeleton[15].y - 3.0f) : (minBoneY - 4.0f);
                                float realBot = maxBoneY + 1.5f;
                                topY = realTop;
                                boxH = realBot - realTop;
                                if (boxH < 8.0f) boxH = 8.0f;
                                boxW = boxH * 0.45f;
                                boxX = centerX - boxW * 0.5f;
                                p.screenX = boxX;
                                p.screenY = topY;
                                p.boxWidth = boxW;
                                p.boxHeight = boxH;
                            }
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
        cEntry.actor = pawn;
        cEntry.isScenery = false;
        cEntry.isPawn = true;
        cEntry.itemCat = DSPUBGItemCategoryNone;
        return true;
    };

    DSPUBGProjectedGrenade grenadeStaging[kDSPUBGMaxGrenades * 2];
    int grenadeStagingCount = 0;
    s_grenadeTickCounter++;

    auto processGrenade = [&](uint64_t actor) -> bool {
        if (grenadeStagingCount >= kDSPUBGMaxGrenades) return false;
        if (!g_pubgEspGrenade) return false;

        uint32_t cSlot = ds_pubg_actor_cache_hash(actor);
        DSPUBGActorCacheEntry &cEntry = g_dspubgActorCache[cSlot];
        if (cEntry.actor == actor && cEntry.isScenery) return false;

        char actorName[64] = {0};
        if (!ds_pubg_get_actor_name(actor, actorName, sizeof(actorName))) {
            return false;
        }

        DSPUBGGrenadeType gType = DSPUBGGrenadeTypeFrag;
        char gDisplayName[32] = {0};
        float dmgRadius = 9.0f;
        if (!ds_pubg_classify_grenade(actorName, &gType, gDisplayName, sizeof(gDisplayName), &dmgRadius)) {
            return false;
        }

        DSPUBGVector rootLoc = {};
        bool hasLoc = false;
        uint64_t rootComp = ds_pubg_read_ptr(actor + kDSPUBGActorRootComponentOffset);
        if (!rootComp || !ds_pubg_valid(rootComp)) {
            rootComp = ds_pubg_read_ptr(actor + 0x180ULL);
        }
        if (rootComp && ds_pubg_valid(rootComp)) {
            if (ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc))) {
                if (!isnan(rootLoc.X) && !isinf(rootLoc.X) &&
                    !isnan(rootLoc.Y) && !isinf(rootLoc.Y) &&
                    !isnan(rootLoc.Z) && !isinf(rootLoc.Z) &&
                    (rootLoc.X != 0.0f || rootLoc.Y != 0.0f || rootLoc.Z != 0.0f)) {
                    hasLoc = true;
                }
            }
        }
        if (!hasLoc) return false;

        float dx = (rootLoc.X - basis.lx) * 0.01f;
        float dy = (rootLoc.Y - basis.ly) * 0.01f;
        float dz = (rootLoc.Z - basis.lz) * 0.01f;
        float dist3D = sqrtf(dx * dx + dy * dy + dz * dz);
        if (dist3D > 150.0f) return true;

        float sx = 0, sy = 0, dist = 0;
        bool isVisible = ds_pubg_cam_basis_project(basis, rootLoc, sx, sy, dist);

        int histSlot = -1;
        for (int h = 0; h < 16; h++) {
            if (s_grenadeHistories[h].actor == actor) {
                histSlot = h;
                break;
            }
        }
        if (histSlot < 0) {
            for (int h = 0; h < 16; h++) {
                if (s_grenadeHistories[h].actor == 0 || (s_grenadeTickCounter - s_grenadeHistories[h].lastSeenTick) > 30) {
                    histSlot = h;
                    s_grenadeHistories[h].actor = actor;
                    s_grenadeHistories[h].type = gType;
                    s_grenadeHistories[h].trailCount = 0;
                    s_grenadeHistories[h].hasThrowerPos = false;
                    uint64_t inst = ds_pubg_read_ptr(actor + 0x138ULL);
                    if (!inst || !ds_pubg_valid(inst)) inst = ds_pubg_read_ptr(actor + 0x140ULL);
                    if (inst && ds_pubg_valid(inst)) {
                        uint64_t instRoot = ds_pubg_read_ptr(inst + kDSPUBGActorRootComponentOffset);
                        if (instRoot && ds_pubg_valid(instRoot)) {
                            DSPUBGVector instLoc = {};
                            if (ds_pubg_read(instRoot + kDSPUBGSceneCompRelativeLocOffset, &instLoc, sizeof(instLoc))) {
                                s_grenadeHistories[h].throwerPos = instLoc;
                                s_grenadeHistories[h].hasThrowerPos = true;
                                s_grenadeHistories[h].trail[0] = instLoc;
                                s_grenadeHistories[h].trailCount = 1;
                            }
                        }
                    }
                    break;
                }
            }
        }

        DSPUBGProjectedGrenade &pg = grenadeStaging[grenadeStagingCount++];
        pg.screenX = sx;
        pg.screenY = sy;
        pg.distanceMeters = dist3D;
        pg.isVisible = isVisible;
        pg.type = gType;
        strncpy(pg.name, gDisplayName, sizeof(pg.name) - 1);
        pg.name[sizeof(pg.name) - 1] = '\0';
        pg.damageRadiusMeters = dmgRadius;
        pg.isLocalInDanger = (dist3D <= dmgRadius);
        pg.hasStart = false;
        pg.startX = screenW * 0.5f;
        pg.startY = 25.0f;
        pg.trajCount = 0;
        pg.circlePointCount = kDSPUBGCirclePoints;

        if (histSlot >= 0) {
            DSPUBGGrenadeHistory &hist = s_grenadeHistories[histSlot];
            hist.lastSeenTick = s_grenadeTickCounter;

            if (hist.trailCount == 0) {
                hist.trail[0] = rootLoc;
                hist.trailCount = 1;
            } else {
                DSPUBGVector &lastPos = hist.trail[hist.trailCount - 1];
                float mdx = (rootLoc.X - lastPos.X) * 0.01f;
                float mdy = (rootLoc.Y - lastPos.Y) * 0.01f;
                float mdz = (rootLoc.Z - lastPos.Z) * 0.01f;
                float moveDist = sqrtf(mdx * mdx + mdy * mdy + mdz * mdz);
                if (moveDist > 0.3f) {
                    if (hist.trailCount < 16) {
                        hist.trail[hist.trailCount++] = rootLoc;
                    } else {
                        for (int k = 0; k < 15; k++) hist.trail[k] = hist.trail[k + 1];
                        hist.trail[15] = rootLoc;
                    }
                }
            }

            if (hist.hasThrowerPos) {
                float tsx = 0, tsy = 0, tdist = 0;
                if (ds_pubg_cam_basis_project(basis, hist.throwerPos, tsx, tsy, tdist)) {
                    pg.startX = tsx;
                    pg.startY = tsy;
                    pg.hasStart = true;
                }
            }

            int projectedTraj = 0;
            for (int t = 0; t < hist.trailCount && projectedTraj < 16; t++) {
                float psx = 0, psy = 0, pdist = 0;
                if (ds_pubg_cam_basis_project(basis, hist.trail[t], psx, psy, pdist)) {
                    pg.trajPoints[projectedTraj++] = CGPointMake(psx, psy);
                }
            }
            pg.trajCount = projectedTraj;
        }

        float radUnits = dmgRadius * 100.0f;
        for (int k = 0; k < kDSPUBGCirclePoints; k++) {
            float angle = (float)k * (2.0f * (float)M_PI / (float)kDSPUBGCirclePoints);
            DSPUBGVector cpt = {
                rootLoc.X + radUnits * cosf(angle),
                rootLoc.Y + radUnits * sinf(angle),
                rootLoc.Z
            };
            float csx = 0, csy = 0, cdist = 0;
            if (ds_pubg_cam_basis_project(basis, cpt, csx, csy, cdist)) {
                pg.circlePoints[k] = CGPointMake(csx, csy);
                pg.circlePointsValid[k] = true;
            } else {
                pg.circlePoints[k] = CGPointMake(-9999.0f, -9999.0f);
                pg.circlePointsValid[k] = false;
            }
        }

        return true;
    };

    DSPUBGProjectedItem itemStaging[kDSPUBGMaxItems * 2];
    int itemStagingCount = 0;

    auto processItemOrVehicle = [&](uint64_t actor) {
        if (itemStagingCount >= (kDSPUBGMaxItems * 2)) return;
        if (!g_pubgEspVehicle && !g_pubgEspWeapon && !g_pubgEspArmor &&
            !g_pubgEspBag && !g_pubgEspScope && !g_pubgEspCrate) {
            return;
        }

        uint32_t cSlot = ds_pubg_actor_cache_hash(actor);
        DSPUBGActorCacheEntry &cEntry = g_dspubgActorCache[cSlot];
        if (cEntry.actor == actor && cEntry.isScenery) {
            return;
        }

        if (localPawn) {
            uint64_t inst = ds_pubg_read_ptr(actor + 0x138ULL);
            uint64_t own = ds_pubg_read_ptr(actor + 0x140ULL);
            if (inst == localPawn || own == localPawn) {
                return;
            }
        }

        // 1. Fast RootComponent and Location check FIRST (filters out 95% of non-spatial/offscreen actors)
        DSPUBGVector rootLoc = {};
        bool hasLoc = false;
        uint64_t rootComp = ds_pubg_read_ptr(actor + kDSPUBGActorRootComponentOffset);
        if (!rootComp || !ds_pubg_valid(rootComp)) {
            rootComp = ds_pubg_read_ptr(actor + 0x180ULL);
        }
        if (rootComp && ds_pubg_valid(rootComp)) {
            if (ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc))) {
                if (!isnan(rootLoc.X) && !isinf(rootLoc.X) &&
                    !isnan(rootLoc.Y) && !isinf(rootLoc.Y) &&
                    !isnan(rootLoc.Z) && !isinf(rootLoc.Z) &&
                    (rootLoc.X != 0.0f || rootLoc.Y != 0.0f || rootLoc.Z != 0.0f)) {
                    hasLoc = true;
                }
            }
        }
        if (!hasLoc) {
            // AttachedRelLoc at 0x634 (APickUpWrapperActor) or 0x624 (APlayerTombBox)
            if (ds_pubg_read(actor + 0x634ULL, &rootLoc, sizeof(rootLoc)) &&
                !isnan(rootLoc.X) && !isinf(rootLoc.X) &&
                (rootLoc.X != 0.0f || rootLoc.Y != 0.0f || rootLoc.Z != 0.0f)) {
                hasLoc = true;
            } else if (ds_pubg_read(actor + 0x624ULL, &rootLoc, sizeof(rootLoc)) &&
                       !isnan(rootLoc.X) && !isinf(rootLoc.X) &&
                       (rootLoc.X != 0.0f || rootLoc.Y != 0.0f || rootLoc.Z != 0.0f)) {
                hasLoc = true;
            }
        }
        if (!hasLoc) return;

        // 2. Early Distance Check (skip actors across the 8x8 km map)
        float dx = (rootLoc.X - basis.lx) * 0.01f;
        float dy = (rootLoc.Y - basis.ly) * 0.01f;
        float dz = (rootLoc.Z - basis.lz) * 0.01f;
        float dist3D = sqrtf(dx * dx + dy * dy + dz * dz);
        if (dist3D < 1.0f || dist3D > 450.0f) return;

        // 3. Early Screen Projection & Frustum Culling (skip actors behind or off screen)
        float sx = 0, sy = 0, dist = 0;
        if (!ds_pubg_cam_basis_project(basis, rootLoc, sx, sy, dist)) {
            return;
        }
        if (sx < -80.0f || sx > (screenW + 80.0f) || sy < -80.0f || sy > (screenH + 80.0f)) {
            return;
        }

        // 4. Fast Cache-Accelerated Item / Vehicle Identification
        char displayName[36] = {0};
        DSPUBGItemCategory cat = DSPUBGItemCategoryNone;
        if (cEntry.actor == actor && cEntry.itemCat != DSPUBGItemCategoryNone) {
            cat = cEntry.itemCat;
            strncpy(displayName, cEntry.itemName, sizeof(displayName) - 1);
            if (cat != DSPUBGItemCategoryVehicle) {
                uint8_t pickedUp = ds_pubg_read_u8(actor + 0x615ULL) & 1;
                if (pickedUp) {
                    cEntry.actor = 0;
                    cEntry.isScenery = false;
                    cEntry.isPawn = false;
                    cEntry.itemCat = DSPUBGItemCategoryNone;
                    return;
                }
            }
        } else {
            cat = ds_pubg_identify_item(actor, displayName, sizeof(displayName));
            if (cat == DSPUBGItemCategoryNone) {
                // Non-item actors must not be cached as scenery
                return;
            }
            cEntry.actor = actor;
            cEntry.isScenery = false;
            cEntry.isPawn = false;
            cEntry.itemCat = cat;
            strncpy(cEntry.itemName, displayName, sizeof(cEntry.itemName) - 1);
            cEntry.itemName[sizeof(cEntry.itemName) - 1] = '\0';
        }

        if (cat == DSPUBGItemCategoryVehicle && !g_pubgEspVehicle) return;
        if (cat == DSPUBGItemCategoryWeapon && !g_pubgEspWeapon) return;
        if (cat == DSPUBGItemCategoryScope && !g_pubgEspScope) return;
        if (cat == DSPUBGItemCategoryArmor && !g_pubgEspArmor) return;
        if (cat == DSPUBGItemCategoryBag && !g_pubgEspBag) return;
        if (cat == DSPUBGItemCategoryCrate && !g_pubgEspCrate) return;

        float maxDist = (cat == DSPUBGItemCategoryVehicle) ? 450.0f :
                        ((cat == DSPUBGItemCategoryCrate) ? (g_pubgItemMaxDistance * 2.0f) : g_pubgItemMaxDistance);
        if (dist3D > maxDist) return;

        if (cat == DSPUBGItemCategoryCrate) {
            std::vector<CrateItemInfo> cItems = ds_pubg_get_crate_items(actor);
            if (!cItems.empty()) {
                for (const auto &ci : cItems) {
                    if (itemStagingCount >= (kDSPUBGMaxItems * 2 - 2)) break;
                    DSPUBGProjectedItem &pi = itemStaging[itemStagingCount++];
                    pi.screenX = sx;
                    pi.screenY = sy;
                    pi.distanceMeters = dist3D;
                    pi.category = ci.category;
                    pi.isVisible = true;
                    strncpy(pi.name, ci.name, sizeof(pi.name) - 1);
                    pi.name[sizeof(pi.name) - 1] = '\0';
                    pi.hp = 0.0f; pi.hpMax = 0.0f; pi.fuel = 0.0f; pi.fuelMax = 0.0f;
                }
                return;
            }
        }

        DSPUBGProjectedItem &pi = itemStaging[itemStagingCount++];
        pi.screenX = sx;
        pi.screenY = sy;
        pi.distanceMeters = dist3D;
        pi.category = cat;
        pi.isVisible = true;
        strncpy(pi.name, displayName, sizeof(pi.name) - 1);
        pi.name[sizeof(pi.name) - 1] = '\0';
        pi.hp = 0.0f;
        pi.hpMax = 0.0f;
        pi.fuel = 0.0f;
        pi.fuelMax = 0.0f;

        if (cat == DSPUBGItemCategoryVehicle) {
            uint64_t vCommon = ds_pubg_read_ptr(actor + 0xC08ULL);
            if (!vCommon || !ds_pubg_valid(vCommon)) {
                vCommon = ds_pubg_read_ptr(actor + 0x6F8ULL);
            }
            if (vCommon && ds_pubg_valid(vCommon)) {
                float hpMax = ds_pubg_read_f32(vCommon + 0x350ULL);
                float hp = ds_pubg_read_f32(vCommon + 0x354ULL);
                float fuelMax = ds_pubg_read_f32(vCommon + 0x438ULL);
                float fuel = ds_pubg_read_f32(vCommon + 0x43CULL);

                if (!isnan(hpMax) && !isinf(hpMax) && hpMax > 0.0f && hpMax <= 200000.0f) {
                    pi.hpMax = hpMax;
                    if (!isnan(hp) && !isinf(hp) && hp >= 0.0f) {
                        pi.hp = (hp > hpMax) ? hpMax : hp;
                    } else {
                        pi.hp = 0.0f;
                    }
                }
                if (!isnan(fuelMax) && !isinf(fuelMax) && fuelMax > 0.0f && fuelMax <= 200000.0f) {
                    pi.fuelMax = fuelMax;
                    if (!isnan(fuel) && !isinf(fuel) && fuel >= 0.0f) {
                        pi.fuel = (fuel > fuelMax) ? fuelMax : fuel;
                    } else {
                        pi.fuel = 0.0f;
                    }
                }
            }
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

    // Source 2: Levels Actors
    auto collectActorsFromLevel = [&](uint64_t lvl) {
        if (!lvl || !ds_pubg_valid(lvl)) return;
        uint64_t actorsData = 0;
        uint32_t actorsCount = 0;

        uint64_t arr = ds_pubg_decrypt_actors_array(lvl);
        if (arr && ds_pubg_valid(arr)) {
            ds_pubg_actors_array_at(arr, &actorsData, &actorsCount);
        }

        if (!actorsData || actorsCount == 0) {
            ds_pubg_actors_array_at(lvl + 0xA0ULL, &actorsData, &actorsCount);
        }
        if (!actorsData || actorsCount == 0) {
            uint64_t cluster = ds_pubg_read_ptr(lvl + 0xE0ULL);
            if (cluster && ds_pubg_valid(cluster)) {
                ds_pubg_actors_array_at(cluster + 0x28ULL, &actorsData, &actorsCount);
            }
        }

        if (actorsData && actorsCount > 0) {
            g_dspubgLastActorsCount = (int)actorsCount;
            if (actorsCount > 8192) actorsCount = 8192;
            static std::vector<uint64_t> s_levelActors;
            if (s_levelActors.size() < actorsCount) s_levelActors.resize(actorsCount);
            if (ds_pubg_read(actorsData, s_levelActors.data(), actorsCount * sizeof(uint64_t))) {
                for (uint32_t i = 0; i < actorsCount; i++) {
                    uint64_t actor = s_levelActors[i];
                    if (!actor || actor == localPawn || !ds_pubg_valid(actor)) continue;

                    uint32_t cSlot = ds_pubg_actor_cache_hash(actor);
                    if (g_dspubgActorCache[cSlot].actor == actor && g_dspubgActorCache[cSlot].isScenery) {
                        continue;
                    }

                    if (!processPawn(actor, 0, false)) {
                        if (!processGrenade(actor)) {
                            processItemOrVehicle(actor);
                        }
                    }
                }
            }
        }
    };

    if (level) {
        collectActorsFromLevel(level);
    }

    g_dspubgLastEnemyCount = enemyCount;
    g_dspubgLastBotCount = botCount;

    if (publishedCount > 1) {
        std::sort(staging, staging + publishedCount, [](const DSPUBGProjectedPlayer &a, const DSPUBGProjectedPlayer &b) {
            return a.distanceMeters < b.distanceMeters;
        });
    }

    if (itemStagingCount > 1) {
        std::sort(itemStaging, itemStaging + itemStagingCount, [](const DSPUBGProjectedItem &a, const DSPUBGProjectedItem &b) {
            return a.distanceMeters < b.distanceMeters;
        });
    }

    int copyItemCount = itemStagingCount > kDSPUBGMaxItems ? kDSPUBGMaxItems : itemStagingCount;
    int copyGrenadeCount = grenadeStagingCount > kDSPUBGMaxGrenades ? kDSPUBGMaxGrenades : grenadeStagingCount;

    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    memcpy(g_dspubgPlayers, staging, publishedCount * sizeof(DSPUBGProjectedPlayer));
    g_dspubgPlayerCount = publishedCount;
    g_dspubgTotalEnemies = total360EnemyCount;
    g_dspubgTotalBots = total360BotCount;
    ++g_dspubgEpoch;

    memcpy(g_dspubgItems, itemStaging, copyItemCount * sizeof(DSPUBGProjectedItem));
    g_dspubgItemCount = copyItemCount;
    ++g_dspubgItemEpoch;

    memcpy(g_dspubgGrenades, grenadeStaging, copyGrenadeCount * sizeof(DSPUBGProjectedGrenade));
    g_dspubgGrenadeCount = copyGrenadeCount;
    ++g_dspubgGrenadeEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}
