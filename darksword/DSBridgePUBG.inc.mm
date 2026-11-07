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

// Process names
static const char kDSPUBGTargetProcessName[] = "ShadowTrackerExtra";
static const char kDSPUBGTargetProcessShortName[] = "ShadowTrackerExt";
static const char kDSPUBGTargetProcessAltName[] = "PUBG MOBILE";

// Offsets dumped from DUMP/ folder (ShadowTrackerExtra UE4)
// Base address is Mach-O 64-bit main image (__TEXT unslid 0x100000000)
// UEPointers from DUMP/Offsets.hpp & DUMP/Logs.txt:
//   GEngine: unslid 0x10A8AA8A0 -> RVA 0x0A8AA8A0
//   Names:   unslid 0x10D492AC0 -> RVA 0x0D492AC0
//   GUObject:unslid 0x10A692D18 -> RVA 0x0A692D18
static const uint64_t kDSPUBGEngineRva = 0x0A8AA8A0ULL;

// Class Member Offsets from DUMP/SDK/Engine.hpp & DUMP/SDK.txt
static const uint64_t kDSPUBGEngineGameViewportOffset        = 0x810ULL; // UEngine.GameViewport (UGameViewportClient*)
static const uint64_t kDSPUBGEngineGameInstanceOffset        = 0xE20ULL; // UGameEngine.GameInstance (UGameInstance*)
static const uint64_t kDSPUBGViewportWorldOffset             = 0x78ULL;  // UGameViewportClient.World (UWorld*)
static const uint64_t kDSPUBGWorldPersistentLevelOffset       = 0x30ULL;  // UWorld.PersistentLevel (ULevel*)
static const uint64_t kDSPUBGLevelActorClusterOffset         = 0xE0ULL;  // ULevel.ActorCluster (ULevelActorContainer*)
static const uint64_t kDSPUBGActorClusterActorsOffset        = 0x28ULL;  // ULevelActorContainer.Actors (TArray<AActor*>)
static const uint64_t kDSPUBGLevelDirectActorsFallbackOffset = 0x98ULL;  // Fallback direct Actors in ULevel

// LocalPlayer & Camera Chain
static const uint64_t kDSPUBGGameInstanceLocalPlayersOffset  = 0x48ULL;  // UGameInstance.LocalPlayers (TArray<ULocalPlayer*>)
static const uint64_t kDSPUBGLocalPlayerControllerOffset     = 0x30ULL;  // UPlayer.PlayerController (APlayerController*)
static const uint64_t kDSPUBGPlayerControllerPawnOffset      = 0x528ULL; // APlayerController.AcknowledgedPawn (APawn*)
static const uint64_t kDSPUBGPlayerControllerCameraMgrOffset = 0x548ULL; // APlayerController.PlayerCameraManager (APlayerCameraManager*)

// Camera Cache POV (APlayerCameraManager.CameraCache at 0x520, POV at +0x10)
static const uint64_t kDSPUBGCameraPOVLocationOffset         = 0x530ULL; // FVector (float X, Y, Z)
static const uint64_t kDSPUBGCameraPOVRotationOffset         = 0x548ULL; // FRotator (float Pitch, Yaw, Roll)
static const uint64_t kDSPUBGCameraPOVFOVOffset              = 0x554ULL; // float FOV

// Actor & Component Offsets
static const uint64_t kDSPUBGActorRootComponentOffset        = 0x208ULL; // AActor.RootComponent (USceneComponent*)
static const uint64_t kDSPUBGSceneCompRelativeLocOffset      = 0x1E4ULL; // USceneComponent.RelativeLocation (FVector)
static const uint64_t kDSPUBGCharacterPlayerNameOffset       = 0x960ULL; // UAECharacter.PlayerName (FString)
static const uint64_t kDSPUBGCharacterPlayerKeyOffset        = 0x980ULL; // UAECharacter.PlayerKey (uint32_t)
static const uint64_t kDSPUBGCharacterTeamIDOffset           = 0x998ULL; // UAECharacter.TeamID (int32_t)
static const uint64_t kDSPUBGCharacterIsAIOffset             = 0xA40ULL; // UAECharacter.bIsAI (bool)
static const uint64_t kDSPUBGCharacterHealthOffset           = 0xE60ULL; // STExtraCharacter.Health (float)
static const uint64_t kDSPUBGCharacterHealthMaxOffset        = 0xE64ULL; // STExtraCharacter.HealthMax (float)
static const uint64_t kDSPUBGCharacterDeadOffset             = 0xE7CULL; // STExtraCharacter.bDead (uint8_t)

// Runtime target state
static uint64_t g_dspubgProc = 0;
static uint32_t g_dspubgPid = 0;
static uint64_t g_dspubgVmMap = 0;
static uint64_t g_dspubgBase = 0;
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

static inline bool ds_pubg_valid(uint64_t address) {
    return address >= 0x100000000ULL && address < 0x1600000000ULL;
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

static void ds_pubg_reset_state(void) {
    g_dspubgProc = 0;
    g_dspubgPid = 0;
    g_dspubgVmMap = 0;
    g_dspubgBase = 0;
    g_dspubgTargetActive.store(false, std::memory_order_release);
    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    g_dspubgPlayerCount = 0;
    memset(g_dspubgPlayers, 0, sizeof(g_dspubgPlayers));
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}

static bool ds_pubg_attach(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (g_dspubgTargetActive.load(std::memory_order_acquire) && g_dspubgBase && g_dspubgVmMap) {
        return true;
    }
    if (now < g_dspubgNextAttach) return false;

    uint64_t proc = proc_find_by_name(kDSPUBGTargetProcessName);
    if (!ds_isvalid(proc)) proc = proc_find_by_name(kDSPUBGTargetProcessShortName);
    if (!ds_isvalid(proc)) proc = proc_find_by_name(kDSPUBGTargetProcessAltName);

    if (!ds_isvalid(proc)) {
        g_dspubgTargetActive.store(false, std::memory_order_release);
        g_dspubgProc = g_dspubgVmMap = g_dspubgBase = 0;
        g_dspubgPid = 0;
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    uint32_t pid = off_proc_p_pid ? ds_kread32(proc + off_proc_p_pid) : 0;
    uint64_t task = proc_task(proc);
    uint64_t vmMap = ds_isvalid(task) ? task_get_vm_map(task) : 0;
    if (!pid || !ds_isvalid(vmMap)) {
        g_dspubgTargetActive.store(false, std::memory_order_release);
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    bool identityChanged = (g_dspubgProc != proc || g_dspubgPid != pid || g_dspubgVmMap != vmMap);
    if (identityChanged) {
        g_dspubgBase = 0;
    }
    g_dspubgProc = proc;
    g_dspubgPid = pid;
    g_dspubgVmMap = vmMap;

    if (!ds_debug_shmem_claim_target(DSDebugShmemOwner::PUBG, (pid_t)pid, proc, vmMap)) {
        g_dspubgTargetActive.store(false, std::memory_order_release);
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    if (identityChanged) {
        ds_debug_vm_regions_rebuild(vmMap, (pid_t)pid, YES);
    }

    if (!g_dspubgBase) {
        g_dspubgBase = ds_debug_find_main_image_base(vmMap);
    }

    if (!g_dspubgBase) {
        g_dspubgNextAttach = now + 1.0;
        return false;
    }

    g_dspubgTargetActive.store(true, std::memory_order_release);
    g_dspubgNextAttach = now + 1.5;
    return true;
}

static void ds_pubg_get_axes(DSPUBGRotator R, DSPUBGVector &X, DSPUBGVector &Y, DSPUBGVector &Z) {
    float radPitch = R.Pitch * (float)M_PI / 180.0f;
    float radYaw   = R.Yaw * (float)M_PI / 180.0f;
    float radRoll  = R.Roll * (float)M_PI / 180.0f;

    float SP = sinf(radPitch);
    float CP = cosf(radPitch);
    float SY = sinf(radYaw);
    float CY = cosf(radYaw);
    float SR = sinf(radRoll);
    float CR = cosf(radRoll);

    X.X = CP * CY;
    X.Y = CP * SY;
    X.Z = SP;

    Y.X = SR * SP * CY - CR * SY;
    Y.Y = SR * SP * SY + CR * CY;
    Y.Z = -SR * CP;

    Z.X = -(CR * SP * CY + SR * SY);
    Z.Y = CY * SR - CR * SP * SY;
    Z.Z = CR * CP;
}

static bool ds_pubg_w2s(DSPUBGVector worldLoc, DSPUBGVector camLoc, DSPUBGRotator camRot, float fov, float screenW, float screenH, float &outX, float &outY, float &outDist) {
    DSPUBGVector axisX, axisY, axisZ;
    ds_pubg_get_axes(camRot, axisX, axisY, axisZ);

    DSPUBGVector delta;
    delta.X = worldLoc.X - camLoc.X;
    delta.Y = worldLoc.Y - camLoc.Y;
    delta.Z = worldLoc.Z - camLoc.Z;

    outDist = sqrtf(delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z) / 100.0f;

    float transX = delta.X * axisY.X + delta.Y * axisY.Y + delta.Z * axisY.Z;
    float transY = delta.X * axisZ.X + delta.Y * axisZ.Y + delta.Z * axisZ.Z;
    float transZ = delta.X * axisX.X + delta.Y * axisX.Y + delta.Z * axisX.Z;

    if (transZ < 1.0f) {
        return false;
    }

    float halfW = screenW * 0.5f;
    float halfH = screenH * 0.5f;
    float tanHalfFov = tanf((fov * (float)M_PI / 180.0f) * 0.5f);
    if (tanHalfFov <= 0.0001f) return false;

    float factor = halfW / tanHalfFov;
    outX = halfW + (transX * factor / transZ);
    outY = halfH - (transY * factor / transZ);

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
    if (!viewport && !gameInstance) {
        return;
    }

    uint64_t world = 0;
    if (viewport) {
        world = ds_pubg_read_ptr(viewport + kDSPUBGViewportWorldOffset);
        if (!gameInstance) {
            gameInstance = ds_pubg_read_ptr(viewport + 0x80ULL);
        }
    }

    if (!world) {
        return;
    }

    // Camera and local player
    uint64_t localPlayersArray = 0;
    int32_t localPlayerCount = 0;
    if (gameInstance) {
        localPlayersArray = ds_pubg_read_ptr(gameInstance + kDSPUBGGameInstanceLocalPlayersOffset);
        ds_pubg_read(gameInstance + kDSPUBGGameInstanceLocalPlayersOffset + 8, &localPlayerCount, sizeof(localPlayerCount));
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

    DSPUBGVector camLoc = {};
    DSPUBGRotator camRot = {};
    float camFOV = 90.0f;
    ds_pubg_read(cameraManager + kDSPUBGCameraPOVLocationOffset, &camLoc, sizeof(camLoc));
    ds_pubg_read(cameraManager + kDSPUBGCameraPOVRotationOffset, &camRot, sizeof(camRot));
    ds_pubg_read(cameraManager + kDSPUBGCameraPOVFOVOffset, &camFOV, sizeof(camFOV));
    if (camFOV < 10.0f || camFOV > 170.0f) camFOV = 90.0f;

    int32_t localTeamId = -1;
    if (localPawn) {
        ds_pubg_read(localPawn + kDSPUBGCharacterTeamIDOffset, &localTeamId, sizeof(localTeamId));
    }

    uint64_t persistentLevel = ds_pubg_read_ptr(world + kDSPUBGWorldPersistentLevelOffset);
    if (!persistentLevel) return;

    uint64_t actorsData = 0;
    int32_t actorCount = 0;

    uint64_t actorCluster = ds_pubg_read_ptr(persistentLevel + kDSPUBGLevelActorClusterOffset);
    if (actorCluster) {
        actorsData = ds_pubg_read_ptr(actorCluster + kDSPUBGActorClusterActorsOffset);
        ds_pubg_read(actorCluster + kDSPUBGActorClusterActorsOffset + 8, &actorCount, sizeof(actorCount));
    }

    if (!actorsData || actorCount <= 0 || actorCount > 4000) {
        actorsData = ds_pubg_read_ptr(persistentLevel + kDSPUBGLevelDirectActorsFallbackOffset);
        ds_pubg_read(persistentLevel + kDSPUBGLevelDirectActorsFallbackOffset + 8, &actorCount, sizeof(actorCount));
    }

    if (!actorsData || actorCount <= 0) return;

    int fetchCount = MIN(actorCount, 512);
    std::vector<uint64_t> actors(fetchCount, 0);
    if (!ds_pubg_read(actorsData, actors.data(), fetchCount * sizeof(uint64_t))) {
        return;
    }

    CGRect screenBounds = UIScreen.mainScreen.bounds;
    float screenW = (float)MAX(screenBounds.size.width, screenBounds.size.height);
    float screenH = (float)MIN(screenBounds.size.width, screenBounds.size.height);

    DSPUBGProjectedPlayer staging[kDSPUBGMaxPlayers] = {};
    int publishedCount = 0;

    for (int i = 0; i < fetchCount && publishedCount < kDSPUBGMaxPlayers; i++) {
        uint64_t actor = actors[i];
        if (!actor || actor == localPawn) continue;

        uint64_t rootComp = ds_pubg_read_ptr(actor + kDSPUBGActorRootComponentOffset);
        if (!rootComp) continue;

        float health = 0.0f;
        float healthMax = 0.0f;
        uint8_t isDead = 0;
        ds_pubg_read(actor + kDSPUBGCharacterHealthOffset, &health, sizeof(health));
        ds_pubg_read(actor + kDSPUBGCharacterHealthMaxOffset, &healthMax, sizeof(healthMax));
        ds_pubg_read(actor + kDSPUBGCharacterDeadOffset, &isDead, sizeof(isDead));

        if (healthMax < 10.0f || healthMax > 500.0f || isDead || health <= 0.0f) {
            continue;
        }

        int32_t teamId = 0;
        uint8_t isAI = 0;
        uint32_t playerKey = 0;
        ds_pubg_read(actor + kDSPUBGCharacterTeamIDOffset, &teamId, sizeof(teamId));
        ds_pubg_read(actor + kDSPUBGCharacterIsAIOffset, &isAI, sizeof(isAI));
        ds_pubg_read(actor + kDSPUBGCharacterPlayerKeyOffset, &playerKey, sizeof(playerKey));

        if (localTeamId > 0 && teamId == localTeamId) {
            continue;
        }

        DSPUBGVector rootLoc = {};
        ds_pubg_read(rootComp + kDSPUBGSceneCompRelativeLocOffset, &rootLoc, sizeof(rootLoc));
        if (isnan(rootLoc.X) || isinf(rootLoc.X) || (fabsf(rootLoc.X) < 1.0f && fabsf(rootLoc.Y) < 1.0f)) {
            continue;
        }

        float feetX = 0, feetY = 0, dist = 0;
        bool feetVisible = ds_pubg_w2s(rootLoc, camLoc, camRot, camFOV, screenW, screenH, feetX, feetY, dist);
        if (!feetVisible || dist > g_dspubgMaxDistance) continue;

        DSPUBGVector headLoc = rootLoc;
        headLoc.Z += 175.0f;
        float headX = 0, headY = 0, headDist = 0;
        ds_pubg_w2s(headLoc, camLoc, camRot, camFOV, screenW, screenH, headX, headY, headDist);

        float boxH = fabsf(feetY - headY);
        if (boxH < 4.0f) boxH = 4.0f;
        float boxW = boxH * 0.45f;
        float boxX = headX - boxW * 0.5f;
        float boxY = MIN(feetY, headY);

        DSPUBGProjectedPlayer p = {};
        p.screenX = boxX;
        p.screenY = boxY;
        p.headX = headX;
        p.headY = headY;
        p.boxWidth = boxW;
        p.boxHeight = boxH;
        p.distanceMeters = dist;
        p.health = health;
        p.healthMax = healthMax;
        p.teamId = teamId;
        p.isAI = (isAI != 0);
        p.isDead = false;
        p.isVisible = true;
        p.actorPtr = actor;
        p.playerKey = playerKey;

        staging[publishedCount++] = p;
    }

    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    memcpy(g_dspubgPlayers, staging, publishedCount * sizeof(DSPUBGProjectedPlayer));
    g_dspubgPlayerCount = publishedCount;
    ++g_dspubgEpoch;
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);
}
