//
//  DSBridgePUBG.inc.mm
//  DarkPubg
//
//  PUBG Mobile (ShadowTrackerExtra) Unreal Engine 4 memory reader + ESP projector.
//  Included by DSBridge.mm.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <cmath>
#include <vector>
#include <atomic>
#include <os/lock.h>

// UEPointers from DUMP/Offsets.hpp & DUMP/Logs.txt (ShadowTrackerExtra UE4)
// Base address is Mach-O 64-bit main image (__TEXT)
// GEngine: unslid 0x10A8AA8A0 -> RVA 0x0A8AA8A0
static const uint64_t kDSPUBGEngineRva = 0x0A8AA8A0ULL;

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
static const uint64_t kDSPUBGMeshBoxExtentZOffset            = 0xBA0ULL;  // Mesh.Bounds.BoxExtent.Z
static const uint64_t kDSPUBGCharacterPlayerNameOffset       = 0x960ULL;  // UAECharacter.PlayerName (FString)
static const uint64_t kDSPUBGCharacterPlayerKeyOffset        = 0x980ULL;  // UAECharacter.PlayerKey (uint32_t)
static const uint64_t kDSPUBGCharacterTeamIDOffset           = 0x998ULL;  // UAECharacter.TeamID (int32_t)
static const uint64_t kDSPUBGCharacterHealthOffset           = 0xE60ULL;  // STExtraCharacter.Health (float)
static const uint64_t kDSPUBGCharacterHealthMaxOffset        = 0xE64ULL;  // STExtraCharacter.HealthMax (float)
static const uint64_t kDSPUBGCharacterDeadOffset             = 0xE7CULL;  // STExtraCharacter.bDead (uint8_t)

// Runtime target state
static uint64_t g_dspubgProc = 0;
static uint32_t g_dspubgPid = 0;
static uint64_t g_dspubgVmMap = 0;
static uint64_t g_dspubgBase = 0;
static uint64_t g_dspubgCachedWorld = 0;
static CFAbsoluteTime g_dspubgNextAttach = 0;
static std::atomic<bool> g_dspubgTargetActive(false);

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
    return address >= 0x100000000ULL && address < 0x300000000000ULL;
}

static uint64_t ds_pubg_read_ptr(uint64_t address) {
    uint64_t value = 0;
    if (!ds_pubg_valid(address) || !g_dspubgVmMap) return 0;
    if (!ds_debug_read_bytes(g_dspubgVmMap, address, &value, sizeof(value))) return 0;
    return ds_pubg_valid(value) && (value & 0x7ULL) == 0 ? value : 0;
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

static void ds_pubg_reset_state(void) {
    g_dspubgProc = 0;
    g_dspubgPid = 0;
    g_dspubgVmMap = 0;
    g_dspubgBase = 0;
    g_dspubgCachedWorld = 0;
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

// Locate main executable base image. Verifies GEngine RVA to ensure the correct binary.
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
            if (!firstMacho) firstMacho = start;
            // Verify GEngine pointer at base + kDSPUBGEngineRva
            uint64_t ge = 0;
            if (ds_debug_read_bytes(vmMap, start + kDSPUBGEngineRva, &ge, sizeof(ge))) {
                if (ds_pubg_valid(ge) && (ge & 0x7ULL) == 0) {
                    return start;
                }
            }
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

static void ds_pubg_tick(void) {
    if (!ds_pubg_attach()) {
        return;
    }

    uint64_t gengine = ds_pubg_read_ptr(g_dspubgBase + kDSPUBGEngineRva);
    if (!gengine) {
        return;
    }

    uint64_t viewport = ds_pubg_read_ptr(gengine + kDSPUBGEngineGameViewportOffset);
    uint64_t gameInstance = ds_pubg_read_ptr(gengine + kDSPUBGEngineGameInstanceOffset);

    uint64_t world = 0;
    if (viewport) {
        world = ds_pubg_read_ptr(viewport + kDSPUBGViewportWorldOffset);
        if (!gameInstance) {
            gameInstance = ds_pubg_read_ptr(viewport + 0x80ULL);
        }
    }

    // Fallback resolution for UWorld
    if (!world && gameInstance) {
        uint64_t lpArray = ds_pubg_read_ptr(gameInstance + kDSPUBGGameInstanceLocalPlayersOffset);
        uint64_t lp0 = lpArray ? ds_pubg_read_ptr(lpArray) : 0;
        uint64_t pc = lp0 ? ds_pubg_read_ptr(lp0 + kDSPUBGLocalPlayerControllerOffset) : 0;
        uint64_t pawn = pc ? ds_pubg_read_ptr(pc + kDSPUBGPlayerControllerPawnOffset) : 0;
        uint64_t outer = pawn ? ds_pubg_read_ptr(pawn + 0x20ULL) : 0;
        if (outer) world = ds_pubg_read_ptr(outer + 0xC0ULL);
    }

    if (!world) {
        world = g_dspubgCachedWorld;
    } else {
        g_dspubgCachedWorld = world;
    }

    if (!world) {
        return;
    }

    // Camera and local player resolution
    if (!gameInstance) {
        gameInstance = ds_pubg_read_ptr(world + kDSPUBGWorldOwningGameInstanceOffset);
    }

    uint64_t localPlayersArray = 0;
    int32_t localPlayerCount = 0;
    if (gameInstance) {
        localPlayersArray = ds_pubg_read_ptr(gameInstance + kDSPUBGGameInstanceLocalPlayersOffset);
        localPlayerCount = ds_pubg_read_i32(gameInstance + kDSPUBGGameInstanceLocalPlayersOffset + 8);
    }

    if (!localPlayersArray || localPlayerCount <= 0) {
        return;
    }

    uint64_t localPlayer = ds_pubg_read_ptr(localPlayersArray);
    if (!localPlayer) return;

    uint64_t playerController = ds_pubg_read_ptr(localPlayer + kDSPUBGLocalPlayerControllerOffset);
    if (!playerController) return;

    uint64_t localPawn = ds_pubg_read_ptr(playerController + kDSPUBGPlayerControllerPawnOffset);
    uint64_t cameraManager = ds_pubg_read_ptr(playerController + kDSPUBGPlayerControllerCameraMgrOffset);
    if (!cameraManager) return;

    // In this build of PUBG Mobile, camera is at PlayerCameraManager.ViewTarget.POV (0x10A0 + 0x10)
    uint64_t pov = cameraManager + kDSPUBGCameraViewTargetOffset + kDSPUBGViewTargetPOVOffset;
    DSPUBGVector camLoc = {};
    DSPUBGRotator camRot = {};
    float camFOV = 90.0f;
    float camAspect = 0.0f;

    ds_pubg_read(pov + kDSPUBGPOVLocationOffset, &camLoc, sizeof(camLoc));
    ds_pubg_read(pov + kDSPUBGPOVRotationOffset, &camRot, sizeof(camRot));
    ds_pubg_read(pov + kDSPUBGPOVFOVOffset, &camFOV, sizeof(camFOV));
    ds_pubg_read(pov + kDSPUBGPOVAspectOffset, &camAspect, sizeof(camAspect));

    // Fallback to CameraCache.POV (0x520 + 0x10 = 0x530)
    if (camLoc.X == 0.0f && camLoc.Y == 0.0f && camLoc.Z == 0.0f) {
        uint64_t cachePov = cameraManager + 0x520ULL + 0x10ULL;
        ds_pubg_read(cachePov + kDSPUBGPOVLocationOffset, &camLoc, sizeof(camLoc));
        ds_pubg_read(cachePov + kDSPUBGPOVRotationOffset, &camRot, sizeof(camRot));
        ds_pubg_read(cachePov + kDSPUBGPOVFOVOffset, &camFOV, sizeof(camFOV));
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

    // Source 1: Fast player list via UWorld.GameState -> PlayerArray
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
                for (uint32_t i = 0; i < playerCount && publishedCount < (uint32_t)kDSPUBGMaxPlayers; i++) {
                    uint64_t ps = playerStates[i];
                    if (!ps || !ds_pubg_valid(ps)) continue;

                    uint64_t pawn = ds_pubg_read_ptr(ps + kDSPUBGPlayerStatePawnPrivateOffset);
                    if (!pawn || pawn == localPawn || !ds_pubg_valid(pawn)) continue;

                    uint8_t botByte = ds_pubg_read_u8(ps + kDSPUBGPlayerStateIsABotOffset);
                    bool isAI = (botByte & 0x4) != 0;

                    int32_t teamId = ds_pubg_read_i32(pawn + kDSPUBGCharacterTeamIDOffset);
                    if (localTeamId > 0 && teamId == localTeamId) {
                        continue;
                    }

                    float health = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthOffset);
                    float healthMax = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthMaxOffset);
                    uint8_t isDead = ds_pubg_read_u8(pawn + kDSPUBGCharacterDeadOffset) & 1;

                    if (healthMax < 10.0f || healthMax > 500.0f || isDead || health <= 0.0f) {
                        continue;
                    }

                    uint64_t rootComp = ds_pubg_read_ptr(pawn + kDSPUBGActorRootComponentOffset);
                    if (!rootComp) continue;

                    DSPUBGVector rootLoc = {};
                    if (!ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc))) {
                        continue;
                    }
                    if (isnan(rootLoc.X) || isinf(rootLoc.X) || (fabsf(rootLoc.X) < 1.0f && fabsf(rootLoc.Y) < 1.0f)) {
                        continue;
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
                    uint64_t meshComp = ds_pubg_read_ptr(pawn + kDSPUBGCharacterMeshOffset);
                    if (meshComp && ds_pubg_valid(meshComp)) {
                        float extZ = ds_pubg_read_f32(meshComp + kDSPUBGMeshBoxExtentZOffset);
                        if (extZ > 30.0f && extZ < 200.0f) {
                            actorH = extZ * 2.0f;
                        }
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
                        if (!ds_pubg_cam_basis_project(basis, pos, sx, sy, dist)) continue;
                    } else {
                        dist = okB ? bd : td;
                    }

                    if (dist > g_dspubgMaxDistance) continue;

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
                    if (boxH > screenH * 2.0f) continue;
                    float boxW = boxH * 0.5f;
                    float boxX = centerX - boxW * 0.5f;

                    if (centerX + boxW * 0.5f < -60.0f || centerX - boxW * 0.5f > screenW + 60.0f ||
                        topY > screenH + 60.0f || topY + boxH < -60.0f) {
                        continue;
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
                    p.actorPtr = pawn;
                    p.playerKey = ds_pubg_read_u32(pawn + kDSPUBGCharacterPlayerKeyOffset);

                    if (!ds_pubg_read_fstring_nick(pawn + kDSPUBGCharacterPlayerNameOffset, p.name, sizeof(p.name))) {
                        ds_pubg_read_fstring_nick(ps + kDSPUBGPlayerStatePlayerNameOffset, p.name, sizeof(p.name));
                    }

                    staging[publishedCount++] = p;
                }
            }
        }
    }

    // Source 2: Fallback to UWorld.PersistentLevel.ActorCluster.Actors if GameState yielded no enemies
    if (publishedCount == 0 && world) {
        uint64_t level = ds_pubg_read_ptr(world + kDSPUBGWorldPersistentLevelOffset);
        if (level) {
            uint64_t cluster = ds_pubg_read_ptr(level + 0xE0ULL); // ActorCluster
            uint64_t actorsData = cluster ? ds_pubg_read_ptr(cluster + 0x28ULL) : ds_pubg_read_ptr(level + 0x98ULL);
            uint32_t actorsCount = cluster ? ds_pubg_read_u32(cluster + 0x30ULL) : ds_pubg_read_u32(level + 0xA0ULL);
            if (actorsData && actorsCount > 0) {
                if (actorsCount > 512) actorsCount = 512;
                std::vector<uint64_t> levelActors(actorsCount, 0);
                if (ds_pubg_read(actorsData, levelActors.data(), actorsCount * sizeof(uint64_t))) {
                    for (uint32_t i = 0; i < actorsCount && publishedCount < (uint32_t)kDSPUBGMaxPlayers; i++) {
                        uint64_t pawn = levelActors[i];
                        if (!pawn || pawn == localPawn || !ds_pubg_valid(pawn)) continue;

                        float health = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthOffset);
                        float healthMax = ds_pubg_read_f32(pawn + kDSPUBGCharacterHealthMaxOffset);
                        uint8_t isDead = ds_pubg_read_u8(pawn + kDSPUBGCharacterDeadOffset) & 1;

                        if (healthMax < 10.0f || healthMax > 500.0f || isDead || health <= 0.0f) {
                            continue;
                        }

                        int32_t teamId = ds_pubg_read_i32(pawn + kDSPUBGCharacterTeamIDOffset);
                        if (localTeamId > 0 && teamId == localTeamId) {
                            continue;
                        }

                        uint64_t rootComp = ds_pubg_read_ptr(pawn + kDSPUBGActorRootComponentOffset);
                        if (!rootComp) continue;

                        DSPUBGVector rootLoc = {};
                        if (!ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc))) {
                            continue;
                        }
                        if (isnan(rootLoc.X) || isinf(rootLoc.X) || (fabsf(rootLoc.X) < 1.0f && fabsf(rootLoc.Y) < 1.0f)) {
                            continue;
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
                        uint64_t meshComp = ds_pubg_read_ptr(pawn + kDSPUBGCharacterMeshOffset);
                        if (meshComp && ds_pubg_valid(meshComp)) {
                            float extZ = ds_pubg_read_f32(meshComp + kDSPUBGMeshBoxExtentZOffset);
                            if (extZ > 30.0f && extZ < 200.0f) {
                                actorH = extZ * 2.0f;
                            }
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
                            if (!ds_pubg_cam_basis_project(basis, pos, sx, sy, dist)) continue;
                        } else {
                            dist = okB ? bd : td;
                        }

                        if (dist > g_dspubgMaxDistance) continue;

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
                        if (boxH > screenH * 2.0f) continue;
                        float boxW = boxH * 0.5f;
                        float boxX = centerX - boxW * 0.5f;

                        if (centerX + boxW * 0.5f < -60.0f || centerX - boxW * 0.5f > screenW + 60.0f ||
                            topY > screenH + 60.0f || topY + boxH < -60.0f) {
                            continue;
                        }

                        uint64_t ps = ds_pubg_read_ptr(pawn + 0x4D0ULL); // APawn.PlayerState
                        bool isAI = false;
                        if (ps && ds_pubg_valid(ps)) {
                            uint8_t botByte = ds_pubg_read_u8(ps + kDSPUBGPlayerStateIsABotOffset);
                            isAI = (botByte & 0x4) != 0;
                        } else {
                            isAI = (ds_pubg_read_u8(pawn + 0xA40ULL) != 0); // UAECharacter.bIsAI
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
                        p.actorPtr = pawn;
                        p.playerKey = ds_pubg_read_u32(pawn + kDSPUBGCharacterPlayerKeyOffset);

                        if (!ds_pubg_read_fstring_nick(pawn + kDSPUBGCharacterPlayerNameOffset, p.name, sizeof(p.name))) {
                            if (ps && ds_pubg_valid(ps)) {
                                ds_pubg_read_fstring_nick(ps + kDSPUBGPlayerStatePlayerNameOffset, p.name, sizeof(p.name));
                            }
                        }

                        staging[publishedCount++] = p;
                    }
                }
            }
        }
    }

    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    memcpy(g_dspubgPlayers, staging, publishedCount * sizeof(DSPUBGProjectedPlayer));
    g_dspubgPlayerCount = publishedCount;
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}
