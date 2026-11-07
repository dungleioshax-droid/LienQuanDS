// DSBridgeLienQuan.inc.mm
// Lien Quan (Unity IL2CPP) discovery layer.
//
// Reuses the shared-page read primitive and exposes the singleton/object chain
// used by the AOV snapshot reader.

#pragma mark - kgvn hardcoded metadata

extern "C" int proc_regionfilename(pid_t pid, uint64_t address,
                                    void *buffer, uint32_t buffersize);

static const char kDSLienQuanTargetProcessName[] = "kgvn";
static const uint64_t kDSLienQuanFrameworkEditorProxyTypeInfoRva = 0x0D0BBE00ULL;
static const uint64_t kDSLienQuanKyriosFrameworkTypeInfoRva = 0x0D0BB320ULL;
static const uint64_t kDSLienQuanLogicCoreMethodInfoRva = 0x0D10E9D0ULL;
static const uint64_t kDSLienQuanIl2CppStaticFieldsOffset = 0xB8ULL;
static const uint64_t kDSLienQuanIl2CppRGCTXDataOffset = 0xC0ULL;
static const uint64_t kDSLienQuanProxyInstanceOffset = 0x00ULL;
static const uint64_t kDSLienQuanFrameworkBattleLogicOffset = 0x68ULL;
static const uint64_t kDSLienQuanLogicCoreCurrentDeskOffset = 0x40ULL;
static const uint64_t kDSLienQuanLogicCoreInstancesOffset = 0x48ULL;
static const uint64_t kDSLienQuanDeskBattleLogicOffset = 0x38ULL;
static const uint64_t kDSLienQuanListViewContextOffset = 0x08ULL;
static const uint64_t kDSLienQuanKyriosPlayerCenterOffset = 0x48ULL;
static const uint64_t kDSLienQuanKyriosHostLogicOffset = 0x50ULL;
static const uint64_t kDSLienQuanHostPlayerIdOffset = 0x10ULL;
static const uint64_t kDSLienQuanPlayerCenterPlayersOffset = 0x20ULL;
static const uint64_t kDSLienQuanPlayerIdOffset = 0x08ULL;
static const uint64_t kDSLienQuanPlayerCampOffset = 0x30ULL;
static const uint64_t kDSLienQuanPlayerBattleRefOffset = 0x198ULL;
static const uint64_t kDSLienQuanKyriosActorManagerOffset = 0x28ULL;
static const uint64_t kDSLienQuanActorManagerHeroActorsOffset = 0x20ULL;
static const uint64_t kDSLienQuanRefWrapperObjectOffset = 0x10ULL;
static const uint64_t kDSLienQuanBattleDynamicModulesOffset = 0xA0ULL;
static const uint64_t kDSLienQuanBattleModulesOffset = 0xA8ULL;

static const uint64_t kDSLienQuanBattleGameActorMgrOffset = 0xF8ULL;
static const uint64_t kDSLienQuanBattleHostPlayerIdOffset = 0x88ULL;
static const uint64_t kDSLienQuanBattleHostPlayerOffset = 0x2C8ULL;
static const uint64_t kDSLienQuanLogicHostPlayerIdOffset = 0x10ULL;
static const uint64_t kDSLienQuanLogicHostActorOffset = 0x20ULL;
static const uint64_t kDSLienQuanGameActorMgrGameActorsOffset = 0x38ULL;
static const uint64_t kDSLienQuanGameActorMgrHeroActorsOffset = 0x48ULL;
static const uint64_t kDSLienQuanGameActorMgrMonsterActorsOffset = 0x70ULL;
static const uint64_t kDSLienQuanHeroListItemsOffset = 0x08ULL;
static const uint64_t kDSLienQuanHeroListSizeOffset = 0x10ULL;
static const uint64_t kDSLienQuanArrayDataOffset = 0x20ULL;
// HeroActors keeps 16-byte PoolObjHandle slots, but the valid LActorRoot
// pointer is at the start of each runtime slot in this build.
static const uint64_t kDSLienQuanHeroElementStride = 0x10ULL;
static const uint64_t kDSLienQuanHeroObjectOffset = 0x00ULL;
static const uint64_t kDSLienQuanPoolObjHandleStride = 0x10ULL;
static const uint64_t kDSLienQuanPoolObjHandleObjectOffset = 0x08ULL;
static const uint64_t kDSLienQuanActorRootObjectIdOffset = 0x28ULL;
static const uint64_t kDSLienQuanActorRootMetaOffset = 0x58ULL;
static const uint64_t kDSLienQuanActorRootLocationOffset = 0xE0ULL;
static const uint64_t kDSLienQuanActorRootForwardOffset = 0xECULL;
static const uint64_t kDSLienQuanActorRootControlOffset = 0x308ULL;
static const uint64_t kDSLienQuanActorRootValueComponentOffset = 0x338ULL;
static const uint64_t kDSLienQuanActorRootSkillControlOffset = 0x328ULL;
static const uint64_t kDSLienQuanActorRootGameObjectOffset = 0x410ULL;
static const uint64_t kDSLienQuanActorRootRecycledOffset = 0x420ULL;
static const uint64_t kDSLienQuanEngineGameObjectDestroyedOffset = 0x5DULL;
// dump.cs: LEngineGameObject.m_Transform @ 0x50, LEngineTransform.position
// @ 0x2C. The transform position is the VISUAL position updated with the
// model; LActorRoot._location is only the battle-logic position.
static const uint64_t kDSLienQuanEngineGameObjectTransformOffset = 0x50ULL;
static const uint64_t kDSLienQuanEngineTransformPositionOffset = 0x2CULL;
static const uint64_t kDSLienQuanCrypticHpOffset = 0x50ULL;
static const uint64_t kDSLienQuanSkillSlotArrayOffset = 0x88ULL;
static const uint64_t kDSLienQuanSkillSlotTypeOffset = 0x68ULL;
static const uint64_t kDSLienQuanSkillSlotCooldownOffset = 0xFCULL;
static const size_t kDSLienQuanSkillSlotCount = 16;
// SkillSlot+0x88 is the inline NucleusDrive.Share.SkillStateData value.
// currentSkillDamage is the first field in that struct.
static const uint64_t kDSLienQuanLogicSkillSlotSyncDataOffset = 0x88ULL;
static const uint64_t kDSLienQuanLogicSkillSlotSkillOffset = 0x120ULL;
static const uint64_t kDSLienQuanLogicSkillIdOffset = 0x20ULL;
static const uint64_t kDSLienQuanActorLinkerSkillControlOffset = 0x18ULL;
static const uint64_t kDSLienQuanVisualSkillSlotArrayOffset = 0x30ULL;
// View SkillSlot+0x18 is the same inline SkillStateData value.
static const uint64_t kDSLienQuanVisualSkillSlotInfoDataOffset = 0x18ULL;
static const uint64_t kDSLienQuanSkillStateDataDamageOffset = 0x00ULL;
static const uint64_t kDSLienQuanVisualSkillSlotTypeOffset = 0x80ULL;
static const uint64_t kDSLienQuanVisualSkillSlotSkillOffset = 0xB8ULL;
static const uint64_t kDSLienQuanVisualSkillIdOffset = 0x18ULL;
static const uint64_t kDSLienQuanMsgUseSkillTargetTypeInfoRva = 0x0D0BF620ULL;
static const uint64_t kDSLienQuanMsgUseSkillTargetPoolGetMethodInfoRva =
    0x0D0D9118ULL;
static const uint64_t kDSLienQuanObjectPoolRepositoryMethodInfoRva = 0x0D10ED70ULL;
static const uint64_t kDSLienQuanActorLinkerBuffControlOffset = 0x40ULL;
static const uint64_t kDSLienQuanSpawnedBuffListOffset = 0x30ULL;
static const uint64_t kDSLienQuanBuffSkillCfgDataOffset = 0x60ULL;
static const uint64_t kDSLienQuanBuffCfgSkillIdOffset = 0x08ULL;
// Assets.Scripts.GameLogic.BuffSkill.GetDuration reads this field directly.
static const uint64_t kDSLienQuanBuffSkillDurationOffset = 0x20ULL;
static const uint64_t kDSLienQuanBuffSkillInitStampOffset = 0x50ULL;
// dump.cs: NucleusDrive.Logic.LBattleLogic.<LogicFrameTick>k__BackingField
// @ 0x38 (ulong). 0x288 is <lSeasonGameplaySys> in this build.
static const uint64_t kDSLienQuanBattleLogicFrameTickOffset = 0x38ULL;
static const uint64_t kDSLienQuanManagedArrayLengthOffset = 0x10ULL;
static const uint64_t kDSLienQuanManagedArrayDataOffset = 0x18ULL;
static const uint64_t kDSLienQuanObjWrapperBehaviorOffset = 0x4CULL;
static const uint64_t kDSLienQuanActorLinkerObjectIdOffset = 0x148ULL;
static const uint64_t kDSLienQuanActorLinkerVisibleOffset = 0x1DDULL;
static const uint64_t kDSLienQuanIl2CppClassInstanceSizeOffset = 0xF8ULL;
static const uint64_t kDSLienQuanCameraSystemTypeInfoRva = 0x0D0B5AD8ULL;
static const uint64_t kDSLienQuanLBattleLogicTypeInfoRva = 0x0D0BB890ULL;
static const uint64_t kDSLienQuanBattleSingletonMethodInfoRva = 0x0D10D320ULL;
// dump.cs: LBattleLogic.<m_GameInfo>k__BackingField @ 0x18 (LGameBase);
// LGameBase.GameContext @ 0x28 is the LGameContextBase (a LSLevelContext),
// which carries iLevelID @ 0x0C and MapType @ 0x18. 0x30 is ActiveAstar.
static const uint64_t kDSLienQuanBattleLogicGameContextOffset = 0x18ULL;
static const uint64_t kDSLienQuanGameContextLevelContextOffset = 0x28ULL;
static const uint64_t kDSLienQuanLevelContextLevelIdOffset = 0x0CULL;
static const uint64_t kDSLienQuanLevelContextMapTypeOffset = 0x18ULL;
static const uint64_t kDSLienQuanActorRootTypeInfoRva = 0x0D0BB620ULL;
static const uint64_t kDSLienQuanIl2CppParentClassOffset = 0x58ULL;
static const uint64_t kDSLienQuanCameraSystemMainCameraOffset = 0x108ULL;
static const uint64_t kDSLienQuanCBattleSystemTypeInfoRva = 0x0D0AE488ULL;
static const uint64_t kDSLienQuanGameSettingsTypeInfoRva = 0x0D0B8E80ULL;
// MethodInfo passed by CUIManagerAdapter.SetFormCameraAdapter to
// Singleton<CUIManager>.GetInstance. Unlike the get_instance property slot,
// this entry is initialized on the path that installs m_formCamera.
static const uint64_t kDSLienQuanCUIManagerSingletonMethodInfoRva =
    0x0D10E368ULL;
static const uint64_t kDSLienQuanCBattleSingletonMethodInfoRva = 0x0D10D538ULL;
static const uint64_t kDSLienQuanCBattleTheMinimapSysOffset = 0x30ULL;
// dump.cs: CBattleSystem.world_UI_Factor_Small (Vector4, 0xC8).
// CvtWorld2UISM uses it as a 2x2 matrix over world X/Z.
static const uint64_t kDSLienQuanCBattleWorldUIFactorSmallOffset = 0xC8ULL;
static const uint64_t kDSLienQuanMinimapTransferOffset = 0x28ULL;
static const uint64_t kDSLienQuanMinimapOwnerFormOffset = 0x58ULL;
static const uint64_t kDSLienQuanMinimapMMSizeOffset = 0x08ULL;
// CUIManager.m_formCamera. UIForm.GetCamera resolves Canvas.worldCamera to this
// camera; reading it from the manager avoids invoking either managed getter.
static const uint64_t kDSLienQuanCUIManagerFormCameraOffset = 0x70ULL;
static const uint64_t kDSLienQuanScreenResolutionXOffset = 0x1F0ULL;
static const uint64_t kDSLienQuanStorePosModeOffset = 0x260ULL;
static const uint64_t kDSLienQuanConfigIntValueOffset = 0x14ULL;
static const uint64_t kDSLienQuanUnityObjectCachedPtrOffset = 0x08ULL;
static const uint64_t kDSLienQuanNativeCameraViewMatrixOffset = 0x80ULL;
static const uint64_t kDSLienQuanNativeCameraViewportOffset = 0x42CULL;
static const uint64_t kDSLienQuanCameraSystemMobaCameraOffset = 0x18ULL;
static const uint64_t kDSLienQuanMobaCameraAdditionZoomOffset = 0x94ULL;
static const uint64_t kDSLienQuanMobaCameraChangedOffset = 0xDCULL;
// CameraSystem values used only to convert the normalized slider delta into
// Moba_Camera zoom-distance units.
static const uint64_t kDSLienQuanCameraSystemZoomRateOffset = 0x3CULL;
static const uint64_t kDSLienQuanCameraSystemCurrentZoomOffset = 0x8CULL;

static uint64_t g_dslqProc = 0;
static uint32_t g_dslqPid = 0;
static uint64_t g_dslqVmMap = 0;
static uint64_t g_dslqBase = 0;
static dispatch_source_t g_dslqProcWatcher = nil;
static void ds_lq_watch_target_pid(uint32_t pid);
static CFAbsoluteTime g_dslqNextAttach = 0;
static CFAbsoluteTime g_dslqNextFallbackScan = 0;
static bool g_dslqRegionsReady = false;
static uint64_t g_dslqCachedBattle = 0;
static uint64_t g_dslqCachedManager = 0;
static uint64_t g_dslqCachedHeroList = 0;
static uint64_t g_dslqCachedHeroItems = 0;
static int g_dslqCachedHeroCount = -1;
static int g_dslqCachedRootCount = 0;
static uint64_t g_dslqCachedRootPtrs[10] = {};
static uint32_t g_dslqCachedRootConfigIds[10] = {};
static uint32_t g_dslqCachedRootPlayerIds[10] = {};
static int32_t g_dslqCachedRootCamps[10] = {};
static uint64_t g_dslqCachedListItemsOffset = 0;
static uint64_t g_dslqCachedListSizeOffset = 0;
static bool g_dslqCachedListLayoutKnown = false;
static bool g_dslqCachedListLayoutLoose = false;
static int g_dslqGraphMisses = 0;
static uint64_t g_dslqCachedFramework = 0;
static uint64_t g_dslqCachedActorManager = 0;
static uint64_t g_dslqCachedLogicCore = 0;
static uint64_t g_dslqCachedHostLogic = 0;
static uint32_t g_dslqCachedHostPlayerId = 0;
static uint32_t g_dslqCachedHostConfigId = 0;
static int g_dslqCachedHostCamp = 0;
static uint64_t g_dslqCachedHostBattle = 0;
static uint64_t g_dslqCachedHostActor = 0;
static uint64_t g_dslqCachedCameraSystem = 0;
static uint64_t g_dslqCachedManagedCamera = 0;
static uint64_t g_dslqCachedNativeCamera = 0;
static bool g_dslqCachedViewportValid = false;
static float g_dslqCachedViewport[4] = {};

// Camera zoom ("cam xa") — external port of myhack's zoomRateFromAge write.
// External has no managed-call path, so instead of hooking GetZoomRate the
// reader queue applies the resulting CameraSystem state externally. Driven by
// the floating
// menu in DSBridgeESP.inc.mm through these atomics (any thread) plus the
// bridge-queue-confined apply state below.
static std::atomic<bool> g_dslqCamZoomEnabled(false);
static std::atomic<float> g_dslqCamZoomValue(1.0f);
static bool g_dslqCamZoomLoadedDefaults = false;
static uint64_t g_dslqCamZoomScaleSystem = 0;
static float g_dslqCamZoomBaseScale = 1.0f;
static uint64_t g_dslqCamZoomExtraCamera = 0;
static float g_dslqCamZoomExtraWritten = NAN;
static float g_dslqCamZoomExtraContribution = 0.0f;
static std::atomic<bool> g_dslqAutoSmiteEnabled(false);
static std::atomic<bool> g_dslqAutoSmiteObjectivesOnly(false);
static bool g_dslqAutoSmiteLoadedDefaults = false;
static bool g_dslqAutoSmiteWasEnabled = false;
static uint64_t g_dslqAutoSmitePool = 0;
static int32_t g_dslqAutoSmiteClassId = 0;
static uint64_t g_dslqAutoSmiteTargetClass = 0;
static uint64_t g_dslqAutoSmiteHostActor = 0;
static uint32_t g_dslqAutoSmiteHostPlayerId = 0;
static CFAbsoluteTime g_dslqAutoSmiteLastEnqueue = 0;
// Duration comes from the live BuffSkill instance. The short fallback only
// coalesces the selection and final confirmation reads in one smite attempt.
static const CFTimeInterval kDSLQSmitePenaltyNegativeCache = 0.10;
static CFAbsoluteTime g_dslqSmiteCaesarPenaltyUntil = 0;
static CFAbsoluteTime g_dslqSmiteSlayerPenaltyUntil = 0;
static CFAbsoluteTime g_dslqSmitePenaltyNegativeUntil = 0;
static const uint32_t kDSLienQuanYueConfigId = 545;
static int g_dslqFallbackPhase = 0;
static uint64_t g_dslqModuleScanBattle = 0;
static int g_dslqModuleScanIndex = 0;
static int g_dslqDynamicModuleScanIndex = 0;
typedef struct {
    int32_t x;
    int32_t y;
    int32_t z;
} DSLienQuanVInt3;

typedef struct {
    DSLienQuanVInt3 location;
    DSLienQuanVInt3 forward;
} DSLQActorMotion;
static_assert(kDSLienQuanActorRootForwardOffset -
                  kDSLienQuanActorRootLocationOffset ==
              offsetof(DSLQActorMotion, forward),
              "LActorRoot motion fields are no longer contiguous");

typedef struct {
    int32_t decrypt;
    int32_t cryptic;
} DSLQLQCrypticInt32;

static int32_t ds_lq_cryptic_int32_value(const DSLQLQCrypticInt32 &value) {
    return (int32_t)((uint32_t)value.decrypt ^
                     (uint32_t)value.cryptic);
}

typedef struct {
    uint32_t configId;
    uint32_t playerId;
    uint64_t reserved08;
    int32_t actorType;
    int32_t actorCamp;
} DSLienQuanActorMeta;

typedef struct {
    bool valid;
    int32_t roomType;
    float mmPos[2];
    float mmSize[2];
    float mmAnchorPos[2];
    int32_t storePosMode;
    float screenSize[2];
    float formCameraViewport[4];
    float worldUIFactorSmall[4];
} DSLQMinimapGeometry;

typedef struct {
    bool valid;
    uint64_t mapperEpoch;
    uint64_t matchEpoch;
    uint64_t battle;
    float viewProjection[16];
    float viewport[4];
    bool viewportValid;
    DSLQMinimapGeometry minimap;
    int32_t hostCamp;
} DSLQProjectionFrameCache;

// Main-thread cache shared by the hero and monster projection passes in the
// same display callback. Hero fills it first; monster reuses it immediately.
static DSLQProjectionFrameCache g_dslqProjectionFrameCache = {};

// Minimap layout and conversion factors are immutable for one match. Confirm
// five matching runtime samples before locking them so partially initialized
// scene values can never become the match-wide geometry.
static DSLQMinimapGeometry g_dslqMinimapCandidate = {};
static DSLQMinimapGeometry g_dslqMinimapCache = {};
static uint8_t g_dslqMinimapStableSamples = 0;
static bool g_dslqMinimapCacheLocked = false;
static CFAbsoluteTime g_dslqMinimapCandidateSince = 0;
static int32_t g_dslqStorePosMode = -1;
static CFAbsoluteTime g_dslqNextStorePosRead = 0;

static std::atomic<bool> g_dslqTargetActive(false);
static std::atomic<uint32_t> g_dslqRecoveryFlags(0);
static std::atomic<uint32_t> g_dslqCameraSampleFailureStreak(0);
static std::atomic<uint32_t> g_dslqLocationSampleFailureStreak(0);
static std::atomic<uint32_t> g_dslqStaleSourceFailureStreak(0);
typedef struct {
    bool valid;
    uint64_t actor;
    uint32_t playerId;
    float x;
    float y;
    float z;
    uint64_t lastUse;
} DSLQLerpPosition;
static os_unfair_lock g_dslqLerpPositionLock = OS_UNFAIR_LOCK_INIT;
static DSLQLerpPosition g_dslqLerpPositions[5] = {};
static uint64_t g_dslqLerpEpoch = 0;
static uint64_t g_dslqLerpSequence = 0;
typedef struct {
    uint64_t remoteAddress;
    uint64_t localFirst;
    uint64_t localSecond;
    uint64_t vmMap;
    uint64_t mapperEpoch;
    uint64_t firstPage;
    uint64_t secondPage;
    uint32_t firstLength;
    uint32_t totalLength;
} DSLQPinnedSpan;

typedef struct {
    uint64_t actor;
    uint32_t configId;
    uint32_t playerId;
    DSLQPinnedSpan motion;
    DSLQPinnedSpan health;
    DSLQPinnedSpan behavior;
    DSLQPinnedSpan sight;
    DSLQPinnedSpan ultimateCooldown;
} DSLQEnemyReadSource;

typedef struct {
    uint64_t actor;
    uint32_t configId;
    int32_t actorCamp;
    DSLQPinnedSpan motion;
    DSLQPinnedSpan health;
    DSLQPinnedSpan recycled;
    DSLQPinnedSpan destroyed;
    // Visual transform position (gameObject.m_Transform.position). Empty when
    // the transform could not be resolved/pinned — the sampler falls back to
    // the logic _location in that case.
    DSLQPinnedSpan visualPos;
} DSLQMonsterReadEntry;

typedef struct {
    bool ready;
    pid_t pid;
    uint64_t vmMap;
    uint64_t mapperEpoch;
    uint64_t matchEpoch;
    uint64_t battle;
    int count;
    DSLQMonsterReadEntry monsters[kDSLQMaxMonsters];
} DSLQMonsterReadSource;

typedef struct {
    bool ready;
    pid_t pid;
    uint64_t vmMap;
    uint64_t mapperEpoch;
    uint64_t matchEpoch;
    uint64_t battle;
    uint64_t nativeCamera;
    DSLQPinnedSpan camera;
    float viewport[4];
    bool viewportValid;
    DSLQMinimapGeometry minimap;
    int32_t hostCamp;
    int enemyCount;
    DSLQEnemyReadSource enemies[5];
} DSLQLiveRenderSource;

static os_unfair_lock g_dslqLiveSourceLock = OS_UNFAIR_LOCK_INIT;
static DSLQLiveRenderSource g_dslqLiveSource = {};
static os_unfair_lock g_dslqMonsterLock = OS_UNFAIR_LOCK_INIT;
static DSLQMonsterReadSource g_dslqMonsterSource = {};
static uint64_t g_dslqMonsterBattle = 0;
typedef struct {
    uint64_t actor;
    uint32_t configId;
    int32_t hp;
    float world[3];
    float pendingWorld[3];
    uint8_t pendingSamples;
    bool hasHealth;
    bool hasMotion;
} DSLQMonsterFrameState;
static DSLQMonsterFrameState
    g_dslqMonsterFrameStates[kDSLQMaxMonsters] = {};
static CFAbsoluteTime g_dslqNextMonsterRosterRefresh = 0;
static uint64_t g_dslqMonsterRosterCandidateSignature = 0;
static uint8_t g_dslqMonsterRosterStablePasses = 0;
static uint8_t g_dslqMonsterEmptyStablePasses = 0;
static uint64_t g_dslqMonsterInstalledSignature = 0;
static uint64_t g_dslqMatchEpoch = 1;
static bool g_dslqRosterLocked = false;
static uint64_t g_dslqRosterCandidateSignature = 0;
static int g_dslqRosterStablePasses = 0;
static CFAbsoluteTime g_dslqRosterStableSince = 0;
static CFAbsoluteTime g_dslqNextRosterRefresh = 0;
static CFAbsoluteTime g_dslqNextDiscovery = 0;
static CFAbsoluteTime g_dslqNextCameraRepin = 0;
static CFAbsoluteTime g_dslqNextCameraIdentityCheck = 0;
static uint8_t g_dslqDiscoveryFailures = 0;
static uint8_t g_dslqCameraRepinFailures = 0;
static uint8_t g_dslqCameraIdentityMisses = 0;
static uint8_t g_dslqRosterIdentityMisses = 0;
static uint8_t g_dslqHostIdentityMisses = 0;
// Roster torn-read watchdog. A single torn read is transient while Unity
// mutates the managed array; only a sustained streak unlocks revalidation.
static uint8_t g_dslqRosterTornSamples = 0;
// Grace window start for an unlocked roster that momentarily resolves zero
// valid roots (GC storms). The publication must ride through it: resetting
// the cache here blanks the overlay for a whole rediscovery pass.
static CFAbsoluteTime g_dslqZeroRootsSince = 0;

enum : uint32_t {
    kDSLQRecoverCamera = 1u << 0,
    kDSLQRecoverLocations = 1u << 1,
    kDSLQRecoverStaleSource = 1u << 2,
};

static bool ds_lq_has_render_source(void) {
    uint64_t mapperEpoch = ds_debug_shmem_epoch();
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    bool ready = g_dslqLiveSource.ready &&
                 g_dslqLiveSource.mapperEpoch == mapperEpoch &&
                 g_dslqLiveSource.enemyCount > 0 &&
                 g_dslqLiveSource.camera.localFirst != 0;
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);
    return ready;
}

static void ds_lq_unpin_span(const DSLQPinnedSpan &span) {
    if (!span.vmMap || !span.mapperEpoch) return;
    if (span.firstPage) {
        ds_debug_unpin_page(DSDebugShmemOwner::LienQuan, span.vmMap,
                            span.mapperEpoch, span.firstPage);
    }
    if (span.secondPage) {
        ds_debug_unpin_page(DSDebugShmemOwner::LienQuan, span.vmMap,
                            span.mapperEpoch, span.secondPage);
    }
}

static void ds_lq_release_enemy_pins(const DSLQEnemyReadSource &enemy) {
    ds_lq_unpin_span(enemy.motion);
    ds_lq_unpin_span(enemy.health);
    ds_lq_unpin_span(enemy.behavior);
    ds_lq_unpin_span(enemy.sight);
    ds_lq_unpin_span(enemy.ultimateCooldown);
}

static void ds_lq_release_monster_pins(
    const DSLQMonsterReadSource &source) {
    int count = MIN(MAX(source.count, 0), kDSLQMaxMonsters);
    for (int i = 0; i < count; i++) {
        ds_lq_unpin_span(source.monsters[i].motion);
        ds_lq_unpin_span(source.monsters[i].health);
        ds_lq_unpin_span(source.monsters[i].recycled);
        ds_lq_unpin_span(source.monsters[i].destroyed);
        ds_lq_unpin_span(source.monsters[i].visualPos);
    }
}

static void ds_lq_clear_monsters(bool releasePins = true) {
    DSLQMonsterReadSource old = {};
    os_unfair_lock_lock(&g_dslqMonsterLock);
    old = g_dslqMonsterSource;
    g_dslqMonsterSource = {};
    memset(g_dslqMonsterFrameStates, 0,
           sizeof(g_dslqMonsterFrameStates));
    os_unfair_lock_unlock(&g_dslqMonsterLock);
    if (releasePins) ds_lq_release_monster_pins(old);
    g_dslqMonsterBattle = 0;
    g_dslqNextMonsterRosterRefresh = 0;
    g_dslqMonsterRosterCandidateSignature = 0;
    g_dslqMonsterRosterStablePasses = 0;
    g_dslqMonsterEmptyStablePasses = 0;
    g_dslqMonsterInstalledSignature = 0;
}

static void ds_lq_release_source_pins(const DSLQLiveRenderSource &source) {
    ds_lq_unpin_span(source.camera);
    int count = MIN(MAX(source.enemyCount, 0), kDSLQMaxEnemies);
    for (int i = 0; i < count; i++) {
        ds_lq_release_enemy_pins(source.enemies[i]);
    }
}

static bool ds_lq_pin_span(uint64_t remoteAddress, size_t length,
                           DSLQPinnedSpan *out) {
    if (out) *out = {};
    if (!out || !remoteAddress || !length || length > PAGE_SIZE ||
        !g_dslqPid || !g_dslqVmMap ||
        !ds_debug_shmem_target_matches(DSDebugShmemOwner::LienQuan,
                                       (pid_t)g_dslqPid, g_dslqVmMap)) {
        return false;
    }
    const uint64_t pageMask = (uint64_t)PAGE_SIZE - 1ULL;
    uint64_t page = remoteAddress & ~pageMask;
    uint32_t offset = (uint32_t)(remoteAddress & pageMask);
    uint32_t firstLength = (uint32_t)MIN(length,
                                         (size_t)PAGE_SIZE - offset);
    uint64_t mapperEpoch = 0;
    uint64_t localFirst = ds_debug_map_page_pinned(
        DSDebugShmemOwner::LienQuan, g_dslqVmMap, page, &mapperEpoch);
    if (!localFirst) return false;
    uint64_t localSecond = 0;
    uint64_t secondPage = 0;
    if (firstLength < length) {
        secondPage = page + PAGE_SIZE;
        uint64_t secondEpoch = 0;
        localSecond = ds_debug_map_page_pinned(
            DSDebugShmemOwner::LienQuan, g_dslqVmMap, secondPage,
            &secondEpoch);
        if (!localSecond || secondEpoch != mapperEpoch) {
            ds_debug_unpin_page(DSDebugShmemOwner::LienQuan, g_dslqVmMap,
                                mapperEpoch, page);
            if (localSecond) {
                ds_debug_unpin_page(DSDebugShmemOwner::LienQuan, g_dslqVmMap,
                                    secondEpoch, secondPage);
            }
            return false;
        }
    }
    *out = {
        remoteAddress, localFirst + offset, localSecond, g_dslqVmMap,
        mapperEpoch, page, secondPage, firstLength, (uint32_t)length
    };
    return true;
}

static bool ds_lq_copy_pinned_span(const DSLQPinnedSpan &source, void *out,
                                   size_t length) {
    if (!out || !source.localFirst || source.totalLength != length ||
        !source.firstLength || source.firstLength > length) return false;
    memcpy(out, (const void *)(uintptr_t)source.localFirst,
           source.firstLength);
    size_t remaining = length - source.firstLength;
    if (remaining) {
        if (!source.localSecond) return false;
        memcpy((uint8_t *)out + source.firstLength,
               (const void *)(uintptr_t)source.localSecond, remaining);
    }
    return true;
}

// Unity updates the view/projection block in place. A single memcpy can land
// between those writes and still look numerically valid, producing a one-frame
// projection near screen center. Accept only a complete block observed twice.
static bool ds_lq_copy_coherent_camera(const DSLQPinnedSpan &source,
                                       float out[32]) {
    if (!out) return false;
    float first[32] = {};
    float second[32] = {};
    if (!ds_lq_copy_pinned_span(source, first, sizeof(first))) return false;
    std::atomic_thread_fence(std::memory_order_acquire);
    if (!ds_lq_copy_pinned_span(source, second, sizeof(second))) return false;
    if (memcmp(first, second, sizeof(first)) == 0) {
        memcpy(out, second, sizeof(second));
        return true;
    }
    float third[32] = {};
    std::atomic_thread_fence(std::memory_order_acquire);
    if (!ds_lq_copy_pinned_span(source, third, sizeof(third))) return false;
    if (memcmp(second, third, sizeof(second)) == 0 ||
        memcmp(first, third, sizeof(first)) == 0) {
        memcpy(out, third, sizeof(third));
        return true;
    }
    return false;
}

// _location and _forward are adjacent in LActorRoot. Sample the full 24-byte
// block coherently so every enemy costs one span/copy path instead of two.
static bool ds_lq_copy_coherent_motion(const DSLQPinnedSpan &source,
                                       DSLQActorMotion *out) {
    if (!out) return false;
    DSLQActorMotion first = {};
    DSLQActorMotion second = {};
    if (!ds_lq_copy_pinned_span(source, &first, sizeof(first)) ||
        !ds_lq_copy_pinned_span(source, &second, sizeof(second))) return false;
    if (memcmp(&first, &second, sizeof(first)) == 0) {
        *out = second;
        return true;
    }
    DSLQActorMotion third = {};
    if (!ds_lq_copy_pinned_span(source, &third, sizeof(third))) return false;
    if (memcmp(&second, &third, sizeof(second)) == 0) {
        *out = third;
        return true;
    }
    if (memcmp(&first, &third, sizeof(first)) == 0) {
        *out = third;
        return true;
    }
    return false;
}

// Matches ESP.h's VInt2Vector: _location is fixed-point (precision 1000)
// and _forward contributes the small actor-center offset used while sight is
// unavailable. Use the absolute component for negative directions; the
// original helper's log10(-x) path is undefined for those valid directions.
static float ds_lq_forward_decimal_scale(int32_t component) {
    int64_t magnitude = component;
    if (magnitude < 0) magnitude = -magnitude;
    if (magnitude == 0) return 1.0f;
    float scale = 10.0f;
    while (magnitude >= 10) {
        magnitude /= 10;
        scale *= 10.0f;
    }
    return scale;
}

static void ds_lq_location_with_forward(const DSLienQuanVInt3 &location,
                                        const DSLienQuanVInt3 &forward,
                                        bool forwardValid,
                                        float world[3]) {
    world[0] = (float)location.x * 0.001f;
    world[1] = (float)location.y * 0.001f;
    world[2] = (float)location.z * 0.001f;
    if (!forwardValid) return;
    world[0] += (float)forward.x * 0.001f /
        ds_lq_forward_decimal_scale(forward.x);
    world[1] += (float)forward.y * 0.001f /
        ds_lq_forward_decimal_scale(forward.y);
    world[2] += (float)forward.z * 0.001f /
        ds_lq_forward_decimal_scale(forward.z);
}

static bool ds_lq_read_list(uint64_t list, int *sizeOut,
                            uint64_t *itemsOut);
static bool ds_lq_read(uint64_t address, void *buffer, size_t size);
static inline bool ds_lq_valid(uint64_t address);
static uint64_t ds_lq_read_ptr(uint64_t address);
static uint64_t ds_lq_mono_singleton_instance(uint64_t typeInfoRva);
static uint64_t ds_lq_singleton_instance_from_methodinfo(
    uint64_t methodInfoRva);
static int ds_lq_attach_sight_sources(DSLQEnemyReadSource sources[5],
                                      int count);
static uint64_t ds_lq_cbattle_system_instance(void);
static bool ds_lq_read_minimap_geometry(DSLQMinimapGeometry *out);
static uint64_t ds_lq_static_fields_from_typeinfo(uint64_t typeInfoRva);

// Flush hooks run before the mapper invalidates its cache. They only revoke the
// publication: the mapper is about to discard all leases itself.
static void ds_lq_clear_live_source_before_unmap(void) {
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    g_dslqLiveSource = {};
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);
    ds_lq_clear_monsters(false);
}

// Normal source replacement/reset keeps the mapper alive, so release its page
// leases after waiting for any in-flight display memcpy to leave the lock.
static void ds_lq_clear_live_sources(void) {
    DSLQLiveRenderSource old = {};
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    old = g_dslqLiveSource;
    g_dslqLiveSource = {};
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);
    ds_lq_release_source_pins(old);
    ds_lq_clear_monsters();
}

static bool ds_lq_pin_live_camera(uint64_t nativeCamera) {
    uint64_t address = nativeCamera + kDSLienQuanNativeCameraViewMatrixOffset;
    uint64_t mapperEpoch = ds_debug_shmem_epoch();
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    bool alreadyPinned = g_dslqLiveSource.pid == (pid_t)g_dslqPid &&
                         g_dslqLiveSource.vmMap == g_dslqVmMap &&
                         g_dslqLiveSource.mapperEpoch == mapperEpoch &&
                         g_dslqLiveSource.matchEpoch == g_dslqMatchEpoch &&
                         g_dslqLiveSource.camera.remoteAddress == address &&
                         g_dslqLiveSource.camera.localFirst != 0;
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);
    if (alreadyPinned) return true;

    DSLQPinnedSpan source = {};
    if (!ds_lq_pin_span(address, sizeof(float) * 32, &source)) return false;
    DSLQPinnedSpan old = {};
    DSLQLiveRenderSource stale = {};
    bool releaseStale = false;
    bool installed = false;
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    if (source.mapperEpoch == ds_debug_shmem_epoch() &&
        source.vmMap == g_dslqVmMap && g_dslqPid &&
        g_dslqMatchEpoch != 0) {
        old = g_dslqLiveSource.camera;
        if (g_dslqLiveSource.mapperEpoch != source.mapperEpoch ||
            g_dslqLiveSource.vmMap != source.vmMap ||
            g_dslqLiveSource.pid != (pid_t)g_dslqPid ||
            g_dslqLiveSource.matchEpoch != g_dslqMatchEpoch) {
            stale = g_dslqLiveSource;
            releaseStale = true;
            DSLQLiveRenderSource empty = {};
            empty.pid = (pid_t)g_dslqPid;
            empty.vmMap = g_dslqVmMap;
            empty.mapperEpoch = source.mapperEpoch;
            empty.matchEpoch = g_dslqMatchEpoch;
            g_dslqLiveSource = empty;
            old = {};
        }
        g_dslqLiveSource.nativeCamera = nativeCamera;
        g_dslqLiveSource.camera = source;
        g_dslqLiveSource.ready = g_dslqLiveSource.enemyCount > 0;
        installed = true;
    }
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);
    if (releaseStale) ds_lq_release_source_pins(stale);
    else if (installed) ds_lq_unpin_span(old);
    else ds_lq_unpin_span(source);
    return installed;
}

static bool ds_lq_publish_enemy_read_source(
    const uint64_t *actors, const DSLienQuanActorMeta *metas, int count,
    int hostCamp, uint64_t battle, const float viewport[4],
    bool viewportValid) {
    if (!actors || !metas || count <= 0 || hostCamp <= 0 || !battle)
        return false;

    DSLQEnemyReadSource next[5] = {};
    int enemyCount = 0;
    bool allPinned = true;
    uint64_t mapperEpoch = ds_debug_shmem_epoch();
    for (int i = 0; i < count && enemyCount < kDSLQMaxEnemies; i++) {
        if (metas[i].actorCamp == hostCamp) continue;
        DSLQEnemyReadSource &enemy = next[enemyCount++];
        enemy.actor = actors[i];
        enemy.configId = metas[i].configId;
        enemy.playerId = metas[i].playerId;
        if (!ds_lq_pin_span(
                actors[i] + kDSLienQuanActorRootLocationOffset,
                sizeof(DSLQActorMotion), &enemy.motion) ||
            enemy.motion.mapperEpoch != mapperEpoch) {
            allPinned = false;
            break;
        }
    }
    uint64_t actorControls[5] = {};
    uint64_t valueProperties[5] = {};
    uint64_t skillControls[5] = {};
    DSDebugReadRange stateRanges[15] = {};
    for (int i = 0; allPinned && i < enemyCount; i++) {
        stateRanges[i * 3] = {
            next[i].actor + kDSLienQuanActorRootControlOffset,
            &actorControls[i], sizeof(actorControls[i]), NO
        };
        stateRanges[i * 3 + 1] = {
            next[i].actor + kDSLienQuanActorRootValueComponentOffset,
            &valueProperties[i], sizeof(valueProperties[i]), NO
        };
        stateRanges[i * 3 + 2] = {
            next[i].actor + kDSLienQuanActorRootSkillControlOffset,
            &skillControls[i], sizeof(skillControls[i]), NO
        };
    }
    if (allPinned && enemyCount > 0) {
        ds_debug_read_list(g_dslqVmMap, stateRanges,
                           (size_t)enemyCount * 3);
    }
    for (int i = 0; allPinned && i < enemyCount; i++) {
        DSLQEnemyReadSource &enemy = next[i];
        uint64_t actorControl = stateRanges[i * 3].success &&
            ds_lq_valid(actorControls[i]) && !(actorControls[i] & 0x7ULL)
            ? actorControls[i] : 0;
        if (actorControl) {
            (void)ds_lq_pin_span(
                actorControl + kDSLienQuanObjWrapperBehaviorOffset,
                sizeof(int32_t), &enemy.behavior);
        }
        uint64_t valueProperty = stateRanges[i * 3 + 1].success &&
            ds_lq_valid(valueProperties[i]) && !(valueProperties[i] & 0x7ULL)
            ? valueProperties[i] : 0;
        if (valueProperty) {
            (void)ds_lq_pin_span(
                valueProperty + kDSLienQuanCrypticHpOffset,
                sizeof(int32_t) * 2, &enemy.health);
        }
    }
    uint64_t skillArrays[5] = {};
    DSDebugReadRange skillArrayRanges[5] = {};
    for (int i = 0; allPinned && i < enemyCount; i++) {
        uint64_t skillControl = stateRanges[i * 3 + 2].success &&
            ds_lq_valid(skillControls[i]) && !(skillControls[i] & 0x7ULL)
            ? skillControls[i] : 0;
        if (skillControl) {
            skillArrayRanges[i] = {
                skillControl + kDSLienQuanSkillSlotArrayOffset,
                &skillArrays[i], sizeof(skillArrays[i]), NO
            };
        }
    }
    if (allPinned && enemyCount > 0)
        ds_debug_read_list(g_dslqVmMap, skillArrayRanges,
                           (size_t)enemyCount);
    struct DSLQSkillArraySnapshot {
        uint64_t count;
        uint64_t slots[kDSLienQuanSkillSlotCount];
    } skillSnapshots[5] = {};
    DSDebugReadRange skillSnapshotRanges[5] = {};
    for (int i = 0; allPinned && i < enemyCount; i++) {
        uint64_t array = skillArrayRanges[i].success &&
            ds_lq_valid(skillArrays[i]) && !(skillArrays[i] & 0x7ULL)
            ? skillArrays[i] : 0;
        if (!array) continue;
        // max_length at +0x18 is contiguous with the vector at +0x20.
        skillSnapshotRanges[i] = {
            array + 0x18ULL, &skillSnapshots[i], sizeof(skillSnapshots[i]), NO
        };
    }
    if (allPinned && enemyCount > 0) {
        ds_debug_read_list(g_dslqVmMap, skillSnapshotRanges,
                           (size_t)enemyCount);
    }

    int32_t slotTypes[5][kDSLienQuanSkillSlotCount] = {};
    DSDebugReadRange slotTypeRanges[5 * kDSLienQuanSkillSlotCount] = {};
    size_t slotTypeRangeCount = 0;
    for (int i = 0; allPinned && i < enemyCount; i++) {
        if (!skillSnapshotRanges[i].success) continue;
        size_t count = (size_t)MIN(
            skillSnapshots[i].count, (uint64_t)kDSLienQuanSkillSlotCount);
        for (size_t j = 0; j < count; j++) {
            uint64_t slot = skillSnapshots[i].slots[j];
            if (!ds_lq_valid(slot) || (slot & 0x7ULL)) continue;
            slotTypeRanges[slotTypeRangeCount++] = {
                slot + kDSLienQuanSkillSlotTypeOffset,
                &slotTypes[i][j], sizeof(slotTypes[i][j]), NO
            };
        }
    }
    if (allPinned && slotTypeRangeCount > 0)
        ds_debug_read_list(g_dslqVmMap, slotTypeRanges, slotTypeRangeCount);

    for (int i = 0; allPinned && i < enemyCount; i++) {
        if (!skillSnapshotRanges[i].success) continue;
        uint64_t ultimate = 0;
        size_t count = (size_t)MIN(
            skillSnapshots[i].count, (uint64_t)kDSLienQuanSkillSlotCount);
        for (size_t j = 0; j < count; j++) {
            uint64_t slot = skillSnapshots[i].slots[j];
            if (!ds_lq_valid(slot) || (slot & 0x7ULL)) continue;
            if (slotTypes[i][j] == 3 && !ultimate) ultimate = slot;
        }
        if (ds_lq_valid(ultimate) && !(ultimate & 0x7ULL)) {
            (void)ds_lq_pin_span(
                ultimate + kDSLienQuanSkillSlotCooldownOffset,
                sizeof(DSLQLQCrypticInt32), &next[i].ultimateCooldown);
        }
    }
    // Do not publish a roster with permanently missing visibility bytes. The
    // ActorLinker list can trail the logic list briefly at match startup; a
    // later worker pass will retry the complete roster once it is populated.
    if (allPinned && ds_lq_attach_sight_sources(next, enemyCount) != enemyCount)
        allPinned = false;
    if (!allPinned || enemyCount <= 0) {
        for (int i = 0; i < enemyCount; i++)
            ds_lq_release_enemy_pins(next[i]);
        return false;
    }
    DSLQEnemyReadSource oldEnemies[5] = {};
    int oldCount = 0;
    bool installed = false;
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    if (g_dslqLiveSource.pid == (pid_t)g_dslqPid &&
        g_dslqLiveSource.vmMap == g_dslqVmMap &&
        g_dslqLiveSource.mapperEpoch == mapperEpoch &&
        g_dslqLiveSource.matchEpoch == g_dslqMatchEpoch &&
        g_dslqLiveSource.camera.localFirst != 0) {
        oldCount = MIN(MAX(g_dslqLiveSource.enemyCount, 0),
                       kDSLQMaxEnemies);
        for (int i = 0; i < oldCount; i++)
            oldEnemies[i] = g_dslqLiveSource.enemies[i];
        memset(g_dslqLiveSource.enemies, 0,
               sizeof(g_dslqLiveSource.enemies));
        memcpy(g_dslqLiveSource.enemies, next,
               (size_t)enemyCount * sizeof(next[0]));
        g_dslqLiveSource.enemyCount = enemyCount;
        g_dslqLiveSource.battle = battle;
        g_dslqLiveSource.hostCamp = hostCamp;
        g_dslqLiveSource.viewportValid = viewportValid;
        if (viewport && viewportValid) {
            memcpy(g_dslqLiveSource.viewport, viewport,
                   sizeof(g_dslqLiveSource.viewport));
        } else {
            memset(g_dslqLiveSource.viewport, 0,
                   sizeof(g_dslqLiveSource.viewport));
        }
        g_dslqLiveSource.ready = true;
        installed = true;
    }
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);

    if (installed) {
        uint32_t heroIds[kDSLQMaxEnemies] = {};
        for (int i = 0; i < enemyCount; i++)
            heroIds[i] = next[i].configId;
        ds_lq_prewarm_hero_images(heroIds, enemyCount);
        for (int i = 0; i < oldCount; i++)
            ds_lq_release_enemy_pins(oldEnemies[i]);
    } else {
        for (int i = 0; i < enemyCount; i++)
            ds_lq_release_enemy_pins(next[i]);
    }
    return installed;
}

static void ds_lq_reset_lerp_positions(void) {
    os_unfair_lock_lock(&g_dslqLerpPositionLock);
    memset(g_dslqLerpPositions, 0, sizeof(g_dslqLerpPositions));
    g_dslqLerpEpoch = 0;
    g_dslqLerpSequence = 0;
    os_unfair_lock_unlock(&g_dslqLerpPositionLock);
}

// Port of ESP.h's Vector3 Lerp: large discontinuities snap, normal samples
// advance 20% toward the newly read position.
static bool ds_lq_lerp_position(uint64_t epoch, uint64_t actor,
                                uint32_t playerId, float position[3]) {
    if (!position) return false;
    os_unfair_lock_lock(&g_dslqLerpPositionLock);
    if (g_dslqLerpEpoch != epoch) {
        memset(g_dslqLerpPositions, 0, sizeof(g_dslqLerpPositions));
        g_dslqLerpEpoch = epoch;
        g_dslqLerpSequence = 0;
    }
    uint64_t sequence = ++g_dslqLerpSequence;
    int slotIndex = -1;
    for (int i = 0; i < kDSLQMaxEnemies; i++) {
        DSLQLerpPosition &slot = g_dslqLerpPositions[i];
        if (!slot.valid) continue;
        if ((actor && slot.actor == actor) ||
            (!actor && playerId && slot.playerId == playerId)) {
            slotIndex = i;
            break;
        }
    }
    if (slotIndex < 0) {
        uint64_t oldestUse = UINT64_MAX;
        for (int i = 0; i < kDSLQMaxEnemies; i++) {
            if (!g_dslqLerpPositions[i].valid) {
                slotIndex = i;
                break;
            }
            if (g_dslqLerpPositions[i].lastUse < oldestUse) {
                oldestUse = g_dslqLerpPositions[i].lastUse;
                slotIndex = i;
            }
        }
    }
    DSLQLerpPosition &slot = g_dslqLerpPositions[slotIndex];
    if (!slot.valid || slot.actor != actor || slot.playerId != playerId) {
        slot = { true, actor, playerId, position[0], position[1], position[2],
                 sequence };
    } else {
        float dx = position[0] - slot.x;
        float dy = position[1] - slot.y;
        float dz = position[2] - slot.z;
        if (sqrtf(dx * dx + dy * dy + dz * dz) > 1.0f) {
            slot.x = position[0];
            slot.y = position[1];
            slot.z = position[2];
        } else {
            slot.x += dx * 0.2f;
            slot.y += dy * 0.2f;
            slot.z += dz * 0.2f;
        }
        slot.lastUse = sequence;
    }
    position[0] = slot.x;
    position[1] = slot.y;
    position[2] = slot.z;
    os_unfair_lock_unlock(&g_dslqLerpPositionLock);
    return true;
}

static bool ds_lq_previous_lerp_position(uint64_t epoch, uint64_t actor,
                                         uint32_t playerId, float position[3]) {
    if (!position) return false;
    os_unfair_lock_lock(&g_dslqLerpPositionLock);
    if (g_dslqLerpEpoch != epoch) {
        os_unfair_lock_unlock(&g_dslqLerpPositionLock);
        return false;
    }
    for (int i = 0; i < kDSLQMaxEnemies; i++) {
        DSLQLerpPosition &slot = g_dslqLerpPositions[i];
        if (!slot.valid ||
            (actor ? slot.actor != actor :
                    (!playerId || slot.playerId != playerId))) continue;
        position[0] = slot.x;
        position[1] = slot.y;
        position[2] = slot.z;
        slot.lastUse = ++g_dslqLerpSequence;
        os_unfair_lock_unlock(&g_dslqLerpPositionLock);
        return true;
    }
    os_unfair_lock_unlock(&g_dslqLerpPositionLock);
    return false;
}

static void ds_lq_reset_runtime_cache(void) {
    ds_lq_clear_live_sources();
    ds_lq_reset_lerp_positions();
    g_dslqMinimapCandidate = {};
    g_dslqMinimapCache = {};
    g_dslqMinimapStableSamples = 0;
    g_dslqMinimapCacheLocked = false;
    g_dslqMinimapCandidateSince = 0;
    g_dslqStorePosMode = -1;
    g_dslqNextStorePosRead = 0;
    if (++g_dslqMatchEpoch == 0) g_dslqMatchEpoch = 1;
    g_dslqCachedBattle = 0;
    g_dslqCachedManager = 0;
    g_dslqCachedHeroList = 0;
    g_dslqCachedHeroItems = 0;
    g_dslqCachedHeroCount = -1;
    g_dslqCachedRootCount = 0;
    memset(g_dslqCachedRootPtrs, 0, sizeof(g_dslqCachedRootPtrs));
    memset(g_dslqCachedRootConfigIds, 0,
           sizeof(g_dslqCachedRootConfigIds));
    memset(g_dslqCachedRootPlayerIds, 0,
           sizeof(g_dslqCachedRootPlayerIds));
    memset(g_dslqCachedRootCamps, 0, sizeof(g_dslqCachedRootCamps));
    g_dslqCachedListItemsOffset = 0;
    g_dslqCachedListSizeOffset = 0;
    g_dslqCachedListLayoutKnown = false;
    g_dslqCachedListLayoutLoose = false;
    g_dslqGraphMisses = 0;
    g_dslqModuleScanBattle = 0;
    g_dslqModuleScanIndex = 0;
    g_dslqDynamicModuleScanIndex = 0;
    g_dslqCachedFramework = 0;
    g_dslqCachedActorManager = 0;
    g_dslqCachedLogicCore = 0;
    g_dslqCachedHostLogic = 0;
    g_dslqCachedHostPlayerId = 0;
    g_dslqCachedHostConfigId = 0;
    g_dslqCachedHostCamp = 0;
    g_dslqCachedHostBattle = 0;
    g_dslqCachedHostActor = 0;
    g_dslqCachedCameraSystem = 0;
    g_dslqCachedManagedCamera = 0;
    g_dslqCachedNativeCamera = 0;
    g_dslqCamZoomScaleSystem = 0;
    g_dslqCamZoomBaseScale = 1.0f;
    g_dslqCamZoomExtraCamera = 0;
    g_dslqCamZoomExtraWritten = NAN;
    g_dslqCamZoomExtraContribution = 0.0f;
    g_dslqAutoSmitePool = 0;
    g_dslqAutoSmiteClassId = 0;
    g_dslqAutoSmiteTargetClass = 0;
    g_dslqAutoSmiteHostActor = 0;
    g_dslqAutoSmiteHostPlayerId = 0;
    g_dslqAutoSmiteLastEnqueue = 0;
    g_dslqSmiteCaesarPenaltyUntil = 0;
    g_dslqSmiteSlayerPenaltyUntil = 0;
    g_dslqSmitePenaltyNegativeUntil = 0;
    g_dslqAutoSmiteWasEnabled = false;
    g_dslqCachedViewportValid = false;
    memset(g_dslqCachedViewport, 0, sizeof(g_dslqCachedViewport));
    g_dslqRosterLocked = false;
    g_dslqRosterCandidateSignature = 0;
    g_dslqRosterStablePasses = 0;
    g_dslqRosterStableSince = 0;
    g_dslqNextRosterRefresh = 0;
    g_dslqNextDiscovery = 0;
    g_dslqNextCameraRepin = 0;
    g_dslqNextCameraIdentityCheck = 0;
    g_dslqDiscoveryFailures = 0;
    g_dslqCameraRepinFailures = 0;
    g_dslqCameraIdentityMisses = 0;
    g_dslqRosterIdentityMisses = 0;
    g_dslqHostIdentityMisses = 0;
    g_dslqRosterTornSamples = 0;
    g_dslqZeroRootsSince = 0;
    g_dslqRecoveryFlags.store(0, std::memory_order_release);
    g_dslqCameraSampleFailureStreak.store(0, std::memory_order_release);
    g_dslqLocationSampleFailureStreak.store(0, std::memory_order_release);
    g_dslqStaleSourceFailureStreak.store(0, std::memory_order_release);
    g_dslqNextFallbackScan = 0;
}

// Unity's singleton holders survive scene/match teardown. Preserve only
// those roots across a confirmed transition; every object reached beneath
// them belongs to the old match and is cleared by the normal runtime reset.
static void ds_lq_reset_match_cache(void) {
    uint64_t framework = g_dslqCachedFramework;
    uint64_t logicCore = g_dslqCachedLogicCore;
    uint64_t cameraSystem = g_dslqCachedCameraSystem;
    ds_lq_reset_runtime_cache();
    g_dslqCachedFramework = framework;
    g_dslqCachedLogicCore = logicCore;
    g_dslqCachedCameraSystem = cameraSystem;
}

// A confirmed match transition must invalidate the mapper as well as the
// object graph. The same virtual address may refer to a different vm_object
// after Unity tears a scene down, even though the process and vm_map persist.
static void ds_lq_reset_match_mapping(void) {
    g_dslqTargetActive.store(false, std::memory_order_release);
    if (g_dslqPid && g_dslqVmMap &&
        ds_debug_shmem_target_matches(DSDebugShmemOwner::LienQuan,
                                      (pid_t)g_dslqPid, g_dslqVmMap)) {
        ds_debug_shmem_invalidate_target_pages();
    }
    ds_lq_reset_match_cache();
    g_dslqRegionsReady = false;
    g_dslqNextAttach = 0;
}

// Lifecycle callers invoke this while already serialized on ds_bridge_queue.
// Keeping it synchronous prevents a reset queued by pause from landing after a
// later resume has already published a fresh source.
static void ds_lq_overlay_reset(void) {
    g_dslqTargetActive.store(false, std::memory_order_release);
    BOOL targetAlive = NO;
    if (g_dslqProc && g_dslqPid && off_proc_p_pid && ds_isvalid(g_dslqProc) &&
        ds_pid_alive_userspace((pid_t)g_dslqPid)) {
        targetAlive = ds_kread32(g_dslqProc + off_proc_p_pid) == g_dslqPid;
    }
    if (g_dslqPid && g_dslqVmMap &&
        ds_debug_shmem_target_matches(DSDebugShmemOwner::LienQuan,
                                      (pid_t)g_dslqPid, g_dslqVmMap)) {
        ds_debug_shmem_release_owner(DSDebugShmemOwner::LienQuan, targetAlive);
    }
    ds_lq_reset_runtime_cache();
    g_dslqProc = 0;
    g_dslqPid = 0;
    g_dslqVmMap = 0;
    g_dslqBase = 0;
    g_dslqRegionsReady = false;
    g_dslqNextAttach = 0;
    ds_lq_watch_target_pid(0);
}

static inline uint64_t ds_lq_addr(uint64_t rva) {
    return g_dslqBase ? g_dslqBase + rva : 0;
}

static inline bool ds_lq_valid(uint64_t address) {
    return address >= 0x100000000ULL && address < 0x1600000000ULL;
}

static uint64_t ds_lq_read_ptr(uint64_t address) {
    uint64_t value = 0;
    if (!ds_lq_valid(address) || !g_dslqVmMap) return 0;
    if (!ds_debug_read_bytes(g_dslqVmMap, address, &value, sizeof(value))) return 0;
    // Managed/native object pointers are at least 8-byte aligned. Packed
    // list metadata such as 0x0000000300000003 must not pass as a pointer.
    return ds_lq_valid(value) && (value & 0x7ULL) == 0 ? value : 0;
}

static bool ds_lq_read(uint64_t address, void *buffer, size_t length) {
    if (!g_dslqVmMap || !ds_lq_valid(address) || !buffer || !length)
        return false;
    return ds_debug_read_bytes(g_dslqVmMap, address, buffer, length);
}

static bool ds_lq_camera_zoom_enabled(void) {
    return g_dslqCamZoomEnabled.load(std::memory_order_acquire);
}

static void ds_lq_auto_smite_set(bool enabled) {
    g_dslqAutoSmiteEnabled.store(enabled, std::memory_order_release);
    [NSUserDefaults.standardUserDefaults setBool:enabled
                                           forKey:kDSHostedAutoSmiteEnabledKey];
}

static void ds_lq_auto_smite_objectives_only_set(bool enabled) {
    g_dslqAutoSmiteObjectivesOnly.store(enabled, std::memory_order_release);
    [NSUserDefaults.standardUserDefaults
        setBool:enabled forKey:kDSHostedAutoSmiteObjectivesOnlyKey];
}

static float ds_lq_camera_zoom_value(void) {
    return g_dslqCamZoomValue.load(std::memory_order_acquire);
}

// Callable from any thread (floating menu on main). Only touches atomics and
// NSUserDefaults; the bridge queue applies the value on its next pass.
static void ds_lq_camera_zoom_set(bool enabled, float value) {
    if (!isfinite(value)) value = 1.0f;
    value = fminf(fmaxf(value, 1.0f), 10.0f);
    g_dslqCamZoomEnabled.store(enabled, std::memory_order_release);
    g_dslqCamZoomValue.store(value, std::memory_order_release);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:enabled forKey:kDSHostedCamZoomEnabledKey];
    [defaults setDouble:value forKey:kDSHostedCamZoomValueKey];
}

static void ds_lq_camera_sync_moba_extra(uint64_t cameraSystem,
                                          float contribution) {
    if (!cameraSystem || !isfinite(contribution)) return;
    uint64_t mobaCamera = ds_lq_read_ptr(
        cameraSystem + kDSLienQuanCameraSystemMobaCameraOffset);
    if (!ds_lq_valid(mobaCamera)) return;
    uint64_t address = mobaCamera + kDSLienQuanMobaCameraAdditionZoomOffset;
    float observed = NAN;
    if (!ds_lq_read(address, &observed, sizeof(observed)) ||
        !isfinite(observed) || fabsf(observed) > 32.0f) {
        return;
    }
    bool cameraChanged = mobaCamera != g_dslqCamZoomExtraCamera;
    if (cameraChanged) {
        g_dslqCamZoomExtraCamera = mobaCamera;
        g_dslqCamZoomExtraWritten = NAN;
        g_dslqCamZoomExtraContribution = 0.0f;
    }
    float gameExtra = observed;
    if (cameraChanged && fabsf(observed - contribution) < 0.0001f) {
        // The external app may reconnect while the game and Moba_Camera stay
        // alive. Recognize our already-installed delta instead of adding it
        // a second time.
        gameExtra = 0.0f;
    } else if (isfinite(g_dslqCamZoomExtraWritten) &&
        fabsf(observed - g_dslqCamZoomExtraWritten) < 0.0001f) {
        gameExtra -= g_dslqCamZoomExtraContribution;
    }
    float combined = gameExtra + contribution;
    if (fabsf(observed - combined) >= 0.0001f) {
        if (!ds_debug_write_bytes(g_dslqVmMap, address, &combined,
                                  sizeof(combined))) {
            return;
        }
        uint8_t changed = 1;
        ds_debug_write_bytes(g_dslqVmMap,
                             mobaCamera + kDSLienQuanMobaCameraChangedOffset,
                             &changed, sizeof(changed));
    }
    g_dslqCamZoomExtraWritten = combined;
    g_dslqCamZoomExtraContribution = contribution;
}

static void ds_lq_camera_zoom_tick(CFAbsoluteTime now) {
    (void)now;
    if (!g_dslqCamZoomLoadedDefaults) {
        g_dslqCamZoomLoadedDefaults = true;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        bool enabled = [defaults boolForKey:kDSHostedCamZoomEnabledKey];
        id stored = [defaults objectForKey:kDSHostedCamZoomValueKey];
        float value = stored ? (float)[stored doubleValue] : 1.0f;
        if (!isfinite(value)) value = 1.0f;
        g_dslqCamZoomEnabled.store(enabled, std::memory_order_release);
        g_dslqCamZoomValue.store(fminf(fmaxf(value, 1.0f), 10.0f),
                                 std::memory_order_release);
    }
    uint64_t cameraSystem = g_dslqCachedCameraSystem;
    if (!cameraSystem) return;
    bool enabled = g_dslqCamZoomEnabled.load(std::memory_order_acquire);
    if (!enabled) {
        // Disabling only stops further writes; it does not restore a baseline.
        return;
    }
    float desired = g_dslqCamZoomValue.load(std::memory_order_acquire);
    float ageRate = NAN;
    float currentZoom = NAN;
    if (!ds_lq_read(cameraSystem + kDSLienQuanCameraSystemZoomRateOffset,
                    &ageRate, sizeof(ageRate)) ||
        !ds_lq_read(cameraSystem + kDSLienQuanCameraSystemCurrentZoomOffset,
                    &currentZoom, sizeof(currentZoom))) {
        return;
    }
    bool systemChanged = cameraSystem != g_dslqCamZoomScaleSystem;
    if (systemChanged) {
        float scale = 1.0f;
        if (isfinite(ageRate) && ageRate > 0.1f &&
            isfinite(currentZoom) && currentZoom > 0.1f) {
            float candidate = currentZoom / ageRate;
            if (candidate >= 0.5f && candidate <= 2.0f) scale = candidate;
        }
        g_dslqCamZoomScaleSystem = cameraSystem;
        g_dslqCamZoomBaseScale = scale;
    }
    float heroZoomScale = 1.0f;
    if (g_dslqCachedHostConfigId == kDSLienQuanYueConfigId &&
        isfinite(ageRate) && ageRate >= 1.0f && ageRate <= 2.0f) {
        heroZoomScale = ageRate;
    }
    float contribution = g_dslqCamZoomBaseScale * heroZoomScale *
                         (desired - 1.0f) * 1.5f;
    ds_lq_camera_sync_moba_extra(cameraSystem, contribution);
}

static bool ds_lq_is_unity_framework_path(const char *path) {
    return path && (strstr(path, "/UnityFramework.framework/UnityFramework") ||
                    strstr(path, "UnityFramework.framework/UnityFramework") ||
                    strstr(path, "/UnityFramework"));
}

static bool ds_lq_unity_header_matches(uint64_t vmMap, uint64_t base) {
    struct mach_header_64 header = {};
    if (!ds_lq_read(base, &header, sizeof(header)) || header.magic != MH_MAGIC_64 ||
        header.filetype != MH_DYLIB || !header.ncmds || header.ncmds > 1024 ||
        header.sizeofcmds > 64 * 1024) return false;
    size_t length = sizeof(header) + header.sizeofcmds;
    std::vector<uint8_t> commands(length);
    if (!ds_lq_read(base, commands.data(), length)) return false;
    static const char needle[] = "UnityFramework.framework/UnityFramework";
    const uint8_t *cursor = commands.data() + sizeof(header);
    const uint8_t *end = cursor + header.sizeofcmds;
    for (uint32_t i = 0; i < header.ncmds; i++) {
        if (cursor + sizeof(struct load_command) > end) break;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(struct load_command) || cursor + command->cmdsize > end) break;
        if (command->cmd == LC_ID_DYLIB) {
            const struct dylib_command *dylib = (const struct dylib_command *)cursor;
            uint32_t offset = dylib->dylib.name.offset;
            if (offset >= sizeof(struct dylib_command) && offset < command->cmdsize) {
                const char *name = (const char *)cursor + offset;
                size_t available = (size_t)(end - (const uint8_t *)name);
                size_t needleLength = sizeof(needle) - 1;
                for (size_t j = 0; j + needleLength <= available && name[j]; j++) {
                    if (memcmp(name + j, needle, needleLength) == 0) return true;
                }
            }
        }
        cursor += command->cmdsize;
    }
    return false;
}

static uint64_t ds_lq_find_unity_framework_base(pid_t pid, uint64_t vmMap) {
    std::vector<DSDebugVMRegion> regions;
    os_unfair_lock_lock(&g_debugVMRegionsLock);
    regions = g_debugVMRegions;
    os_unfair_lock_unlock(&g_debugVMRegionsLock);

    std::vector<uint64_t> pathCandidates;
    // Cheap pass first: path lookup does not create shared-page mappings.
    for (const DSDebugVMRegion &region : regions) {
        char path[1024] = {};
        int length = proc_regionfilename(pid, region.start, path, sizeof(path));
        if (length > 0 && ds_lq_is_unity_framework_path(path)) {
            pathCandidates.push_back(region.start);
        }
    }
    for (uint64_t start : pathCandidates) {
        if (ds_lq_unity_header_matches(vmMap, start)) {
            return start;
        }
    }

    // Pathless fallback used by DarkLQ. This is expensive because probing a
    // target header creates a shared mapping, so use it only when the cheap
    // path pass found no UnityFramework regions at all.
    if (!pathCandidates.empty()) {
        return 0;
    }
    // Current dumped UnityFramework __TEXT is 0xC214000. Probe this narrow
    // band first so pathless devices normally create only one mapping.
    static const uint64_t kUnityTextMin = 0x0C000000ULL;
    static const uint64_t kUnityTextMax = 0x0C400000ULL;
    for (const DSDebugVMRegion &region : regions) {
        uint64_t size = region.end > region.start ? region.end - region.start : 0;
        if (size < kUnityTextMin || size > kUnityTextMax) continue;
        if (ds_lq_unity_header_matches(vmMap, region.start)) {
            return region.start;
        }
    }
    static const uint64_t kMinimumUnityTextRegionSize = 0x08000000ULL;
    for (const DSDebugVMRegion &region : regions) {
        if (region.end <= region.start ||
            region.end - region.start < kMinimumUnityTextRegionSize) continue;
        if (ds_lq_unity_header_matches(vmMap, region.start)) {
            return region.start;
        }
    }
    return 0;
}

// Kernel-pointer lifetime watcher for the attached target. The instant the
// game exits, drop every cached kernel address derived from it (proc, vm_map,
// shared-page mappings) WITHOUT touching them: the proc_task/zone elements
// may already be freed, so even a "harmless" confirmation kread can fault on
// an unmapped zone page and panic the kernel. This shrinks the stale-pointer
// window from the ~1s attach poll to event time. Runs on ds_bridge_queue,
// serialized with the reader and attach paths.
static void ds_lq_watch_target_pid(uint32_t pid) {
    if (g_dslqProcWatcher) {
        dispatch_source_cancel(g_dslqProcWatcher);
        g_dslqProcWatcher = nil;
    }
    if (!pid) return;
    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid,
        DISPATCH_PROC_EXIT | DISPATCH_PROC_EXEC, ds_bridge_queue());
    if (!source) return;
    g_dslqProcWatcher = source;
    dispatch_source_set_event_handler(source, ^{
        dispatch_source_cancel(source);
        if (g_dslqProcWatcher == source) g_dslqProcWatcher = nil;
        if (!g_dslqPid || g_dslqPid != pid) return;
        g_dslqTargetActive.store(false, std::memory_order_release);
        if (g_dslqVmMap &&
            ds_debug_shmem_target_matches(DSDebugShmemOwner::LienQuan,
                                          (pid_t)pid, g_dslqVmMap)) {
            ds_debug_shmem_release_owner(DSDebugShmemOwner::LienQuan, NO);
        }
        ds_lq_reset_runtime_cache();
        g_dslqProc = 0;
        g_dslqPid = 0;
        g_dslqVmMap = 0;
        g_dslqBase = 0;
        g_dslqRegionsReady = false;
        g_dslqNextAttach = 0;
    });
    dispatch_resume(source);
}

static bool ds_lq_attach(void) {
    static dispatch_once_t s_unmapHookOnce;
    dispatch_once(&s_unmapHookOnce, ^{
        ds_debug_set_pre_unmap_hook(
            ds_lq_clear_live_source_before_unmap);
    });
    if (!ds_is_ready()) {
        g_dslqTargetActive.store(false, std::memory_order_release);
        return false;
    }
    double now = CFAbsoluteTimeGetCurrent();
    if (g_dslqProc && g_dslqPid && g_dslqVmMap &&
        ds_isvalid(g_dslqProc) && off_proc_p_pid) {
        bool ownsMapper = ds_debug_shmem_target_matches(
            DSDebugShmemOwner::LienQuan, (pid_t)g_dslqPid, g_dslqVmMap);
        if (now < g_dslqNextAttach) {
            return ownsMapper && g_dslqBase != 0;
        }
        // Userspace gate first: if the game already exited, the cached proc
        // is a freed proc_task element whose zone page may be unmapped — a
        // kread of it panics the kernel. Never issue that read for a dead
        // pid; fall through to the detach path instead.
        uint32_t cachedPid = 0;
        if (ds_pid_alive_userspace((pid_t)g_dslqPid)) {
            cachedPid = ds_kread32(g_dslqProc + off_proc_p_pid);
        }
        if (cachedPid && cachedPid == g_dslqPid) {
            if (!ownsMapper) {
                ds_lq_reset_runtime_cache();
                if (!ds_debug_shmem_claim_target(
                        DSDebugShmemOwner::LienQuan, (pid_t)cachedPid,
                        g_dslqProc, g_dslqVmMap)) {
                    g_dslqNextAttach = now + 0.75;
                    return false;
                }
                g_dslqRegionsReady = false;
            }
            if (!g_dslqRegionsReady &&
                !ds_debug_vm_regions_rebuild(
                    g_dslqVmMap, (pid_t)cachedPid, YES)) {
                g_dslqNextAttach = now + 0.75;
                return false;
            }
            g_dslqRegionsReady = true;
            g_dslqTargetActive.store(true, std::memory_order_release);
            if (!g_dslqBase) {
                g_dslqBase = ds_lq_find_unity_framework_base(
                    (pid_t)cachedPid, g_dslqVmMap);
                if (!g_dslqBase) {
                    g_dslqNextAttach = now + 0.75;
                    return false;
                }
            }
            g_dslqNextAttach = now + 1.0;
            return true;
        }
        g_dslqTargetActive.store(false, std::memory_order_release);
        if (ownsMapper) {
            ds_debug_shmem_release_owner(DSDebugShmemOwner::LienQuan, NO);
        }
        ds_lq_reset_runtime_cache();
        g_dslqProc = 0;
        g_dslqPid = 0;
        g_dslqVmMap = 0;
        g_dslqBase = 0;
        g_dslqRegionsReady = false;
        ds_lq_watch_target_pid(0);
    }
    // Failure deadlines also apply to the cold path. In particular, do not
    // repeat a 16k-entry vm_map walk on every display-paced reader callback.
    if (now < g_dslqNextAttach) return false;

    uint64_t proc = proc_find_by_name(kDSLienQuanTargetProcessName);
    if (!ds_isvalid(proc)) {
        g_dslqTargetActive.store(false, std::memory_order_release);
        g_dslqProc = g_dslqVmMap = g_dslqBase = 0;
        g_dslqPid = 0;
        g_dslqRegionsReady = false;
        g_dslqNextAttach = now + 0.75;
        ds_lq_watch_target_pid(0);
        return false;
    }
    uint32_t pid = off_proc_p_pid ? ds_kread32(proc + off_proc_p_pid) : 0;
    uint64_t task = proc_task(proc);
    uint64_t vmMap = ds_isvalid(task) ? task_get_vm_map(task) : 0;
    if (!pid || !ds_isvalid(vmMap)) {
        g_dslqTargetActive.store(false, std::memory_order_release);
        g_dslqNextAttach = now + 0.75;
        return false;
    }
    bool identityChanged = g_dslqProc != proc || g_dslqPid != pid ||
                           g_dslqVmMap != vmMap;
    if (identityChanged) {
        ds_lq_reset_runtime_cache();
        g_dslqBase = 0;
        g_dslqRegionsReady = false;
    }
    g_dslqProc = proc;
    g_dslqPid = pid;
    g_dslqVmMap = vmMap;
    ds_lq_watch_target_pid(pid);
    if (!ds_debug_shmem_claim_target(DSDebugShmemOwner::LienQuan,
                                     (pid_t)pid, proc, vmMap)) {
        g_dslqTargetActive.store(false, std::memory_order_release);
        g_dslqNextAttach = now + 0.75;
        return false;
    }
    g_dslqTargetActive.store(true, std::memory_order_release);
    if (identityChanged &&
        !ds_debug_vm_regions_rebuild(vmMap, (pid_t)pid, YES)) {
        g_dslqNextAttach = now + 0.75;
        return false;
    }
    if (identityChanged) g_dslqRegionsReady = true;
    // TypeInfo RVAs from dump.cs are relative to UnityFramework, not the kgvn
    // executable image. Match LQVIP's path-based region selection.
    if (!g_dslqBase) {
        g_dslqBase = ds_lq_find_unity_framework_base((pid_t)pid, vmMap);
    }
    if (!g_dslqBase) {
        g_dslqNextAttach = now + 0.75;
        return false;
    }
    g_dslqNextAttach = now + 1.0;
    return true;
}

static bool ds_lq_read_list_at(uint64_t list, uint64_t itemsOffset,
                               uint64_t sizeOffset, int *sizeOut,
                               uint64_t *itemsOut, bool loose) {
    uint64_t items = ds_lq_read_ptr(list + itemsOffset);
    int32_t size = 0;
    uint64_t capacity = 0;
    if (!items || !ds_lq_read(list + sizeOffset, &size, sizeof(size)) ||
        size < 0 || size > 256) return false;
    bool capacityOK = ds_lq_read(items + 0x18, &capacity, sizeof(capacity)) &&
                      capacity <= 10000 && (uint64_t)size <= capacity;
    if (!capacityOK && !loose) return false;
    size_t readable = 0x20;
    if (size > 0) readable += (size_t)(size - 1) * 0x10 + sizeof(uint64_t);
    uint8_t probe = 0;
    if (readable > PAGE_SIZE ||
        !ds_lq_read(items + readable - 1, &probe, sizeof(probe))) return false;
    if (sizeOut) *sizeOut = size;
    if (itemsOut) *itemsOut = items;
    return true;
}

static bool ds_lq_read_list(uint64_t list, int *sizeOut, uint64_t *itemsOut) {
    static const uint64_t layouts[][2] = {{0x10, 0x18}, {0x08, 0x10}, {0x00, 0x08}};
    for (const auto &layout : layouts) {
        if (ds_lq_read_list_at(list, layout[0], layout[1], sizeOut, itemsOut, false))
            return true;
    }
    for (const auto &layout : layouts) {
        if (ds_lq_read_list_at(list, layout[0], layout[1], sizeOut, itemsOut, true))
            return true;
    }
    return false;
}

static int ds_lq_attach_sight_sources(DSLQEnemyReadSource sources[5],
                                      int count) {
    count = MIN(MAX(count, 0), kDSLQMaxEnemies);
    if (!sources || count <= 0 || !g_dslqVmMap) return 0;

    uint32_t rootIds[5] = {};
    DSDebugReadRange rootRanges[5] = {};
    for (int i = 0; i < count; i++) {
        rootRanges[i] = {
            sources[i].actor + kDSLienQuanActorRootObjectIdOffset,
            &rootIds[i], sizeof(rootIds[i]), NO
        };
    }
    ds_debug_read_list(g_dslqVmMap, rootRanges, (size_t)count);

    uint64_t framework = g_dslqCachedFramework;
    if (!framework) {
        framework = ds_lq_mono_singleton_instance(
            kDSLienQuanKyriosFrameworkTypeInfoRva);
        if (framework) g_dslqCachedFramework = framework;
    }
    uint64_t actorManager = g_dslqCachedActorManager;
    if (!actorManager && framework) {
        actorManager = ds_lq_read_ptr(
            framework + kDSLienQuanKyriosActorManagerOffset);
        if (actorManager) g_dslqCachedActorManager = actorManager;
    }
    uint64_t list = actorManager
        ? ds_lq_read_ptr(actorManager +
                         kDSLienQuanActorManagerHeroActorsOffset) : 0;
    int linkerCount = -1;
    uint64_t items = 0;
    if (!list || !ds_lq_read_list(list, &linkerCount, &items) ||
        linkerCount <= 0 || linkerCount > 64 || !items) return 0;

    uint8_t slots[64 * kDSLienQuanPoolObjHandleStride] = {};
    if (!ds_lq_read(items + kDSLienQuanArrayDataOffset, slots,
                    (size_t)linkerCount * kDSLienQuanPoolObjHandleStride))
        return 0;
    uint64_t candidates[64] = {};
    int candidateCount = 0;
    for (int i = 0; i < linkerCount && candidateCount < 64; i++) {
        const uint8_t *slot = slots +
            (size_t)i * kDSLienQuanPoolObjHandleStride;
        uint64_t direct = 0;
        uint64_t handle = 0;
        memcpy(&direct, slot, sizeof(direct));
        memcpy(&handle, slot + kDSLienQuanPoolObjHandleObjectOffset,
               sizeof(handle));
        if (ds_lq_valid(handle) && !(handle & 0x7ULL))
            candidates[candidateCount++] = handle;
        if (candidateCount < 64 && direct != handle &&
            ds_lq_valid(direct) && !(direct & 0x7ULL))
            candidates[candidateCount++] = direct;
    }
    uint32_t linkerIds[64] = {};
    DSDebugReadRange linkerRanges[64] = {};
    for (int i = 0; i < candidateCount; i++) {
        linkerRanges[i] = {
            candidates[i] + kDSLienQuanActorLinkerObjectIdOffset,
            &linkerIds[i], sizeof(linkerIds[i]), NO
        };
    }
    if (candidateCount > 0)
        ds_debug_read_list(g_dslqVmMap, linkerRanges,
                           (size_t)candidateCount);

    int attached = 0;
    for (int root = 0; root < count; root++) {
        if (!rootRanges[root].success || !rootIds[root]) continue;
        for (int candidate = 0; candidate < candidateCount; candidate++) {
            if (!linkerRanges[candidate].success ||
                linkerIds[candidate] != rootIds[root]) continue;
            if (ds_lq_pin_span(
                    candidates[candidate] +
                        kDSLienQuanActorLinkerVisibleOffset,
                    sizeof(uint8_t), &sources[root].sight)) {
                attached++;
                break;
            }
        }
    }
    return attached;
}

static bool ds_lq_detect_list_layout(uint64_t list, int expectedSize,
                                     uint64_t expectedItems,
                                     uint64_t *itemsOffsetOut,
                                     uint64_t *sizeOffsetOut,
                                     bool *looseOut) {
    static const uint64_t layouts[][2] = {
        {0x10, 0x18}, {0x08, 0x10}, {0x00, 0x08}
    };
    for (int pass = 0; pass < 2; pass++) {
        bool loose = pass != 0;
        for (const auto &layout : layouts) {
            int size = -1;
            uint64_t items = 0;
            if (!ds_lq_read_list_at(list, layout[0], layout[1],
                                    &size, &items, loose) ||
                size != expectedSize || items != expectedItems) continue;
            if (itemsOffsetOut) *itemsOffsetOut = layout[0];
            if (sizeOffsetOut) *sizeOffsetOut = layout[1];
            if (looseOut) *looseOut = loose;
            return true;
        }
    }
    return false;
}

static bool ds_lq_read_cached_list(uint64_t list, uint64_t itemsOffset,
                                   uint64_t sizeOffset, int *sizeOut,
                                   uint64_t *itemsOut) {
    if (!list || sizeOffset != itemsOffset + sizeof(uint64_t)) return false;
    struct {
        uint64_t items;
        int32_t size;
        int32_t version;
    } header = {};
    if (!ds_lq_read(list + itemsOffset, &header, sizeof(header)) ||
        !ds_lq_valid(header.items) || (header.items & 0x7ULL) != 0 ||
        header.size < 0 || header.size > kDSLQMaxHeroes) return false;
    if (sizeOut) *sizeOut = header.size;
    if (itemsOut) *itemsOut = header.items;
    return true;
}

static bool ds_lq_read_hero_root_candidate(
    uint64_t actor, DSLienQuanVInt3 *locationOut,
    DSLienQuanActorMeta *metaOut);
static bool ds_lq_location_valid(const DSLienQuanVInt3 *location);

static bool ds_lq_parse_hero_fields(const uint8_t fields[0x94],
                                    DSLienQuanVInt3 *locationOut,
                                    DSLienQuanActorMeta *metaOut) {
    if (!fields) return false;
    DSLienQuanActorMeta meta = {};
    DSLienQuanVInt3 location = {};
    memcpy(&meta, fields, sizeof(meta));
    memcpy(&location,
           fields + (kDSLienQuanActorRootLocationOffset -
                     kDSLienQuanActorRootMetaOffset),
           sizeof(location));
    if (meta.actorType != 0 ||
        (meta.configId == 0 && meta.playerId == 0) ||
        !ds_lq_location_valid(&location)) return false;
    if (locationOut) *locationOut = location;
    if (metaOut) *metaOut = meta;
    return true;
}

static bool ds_lq_read_hero_fields_exact(
    uint64_t actor, DSLienQuanVInt3 *locationOut,
    DSLienQuanActorMeta *metaOut) {
    if (!ds_lq_valid(actor)) return false;
    uint8_t fields[0x94] = {};
    if (!ds_lq_read(actor + kDSLienQuanActorRootMetaOffset,
                    fields, sizeof(fields))) return false;
    return ds_lq_parse_hero_fields(fields, locationOut, metaOut);
}

static uint64_t ds_lq_read_hero_root_exact(
    uint64_t items, int index, DSLienQuanVInt3 *locationOut,
    DSLienQuanActorMeta *metaOut) {
    if (!items || index < 0 || index >= kDSLQMaxHeroes) return 0;
    uint64_t slot = items + kDSLienQuanArrayDataOffset +
        (uint64_t)index * kDSLienQuanHeroElementStride +
        kDSLienQuanHeroObjectOffset;
    uint64_t actor = ds_lq_read_ptr(slot);
    return ds_lq_read_hero_fields_exact(actor, locationOut, metaOut)
        ? actor : 0;
}

static bool ds_lq_read_actor_location(uint64_t actorRoot, DSLienQuanVInt3 *out);
static uint64_t ds_lq_static_fields_from_typeinfo(uint64_t typeInfoRva);
static uint64_t ds_lq_mono_singleton_instance(uint64_t typeInfoRva);
static uint64_t ds_lq_framework_instance(void);

static uint64_t ds_lq_singleton_instance_from_class(uint64_t klass) {
    uint64_t fields = klass
        ? ds_lq_read_ptr(klass + kDSLienQuanIl2CppStaticFieldsOffset)
        : 0;
    return fields ? ds_lq_read_ptr(fields) : 0;
}

static uint64_t ds_lq_logic_core_instance(uint64_t *singletonClassOut) {
    if (singletonClassOut) *singletonClassOut = 0;
    uint64_t methodInfo = ds_lq_read_ptr(
        ds_lq_addr(kDSLienQuanLogicCoreMethodInfoRva));
    uint64_t methodClass = methodInfo ? ds_lq_read_ptr(methodInfo + 0x20) : 0;
    uint64_t rgctx = methodClass
        ? ds_lq_read_ptr(methodClass + kDSLienQuanIl2CppRGCTXDataOffset)
        : 0;
    uint64_t singletonClass = rgctx ? ds_lq_read_ptr(rgctx + 0x10) : 0;
    if (singletonClassOut) *singletonClassOut = singletonClass;
    uint64_t instance = ds_lq_singleton_instance_from_class(singletonClass);
    if (instance) return instance;
    if (singletonClassOut) *singletonClassOut = methodClass;
    return ds_lq_singleton_instance_from_class(methodClass);
}

static uint64_t ds_lq_cbattle_system_instance(void) {
    uint64_t instance = ds_lq_mono_singleton_instance(
        kDSLienQuanCBattleSystemTypeInfoRva);
    if (instance) return instance;
    uint64_t methodInfo = ds_lq_read_ptr(
        ds_lq_addr(kDSLienQuanCBattleSingletonMethodInfoRva));
    uint64_t methodClass = methodInfo ? ds_lq_read_ptr(methodInfo + 0x20) : 0;
    uint64_t rgctx = methodClass
        ? ds_lq_read_ptr(methodClass + kDSLienQuanIl2CppRGCTXDataOffset)
        : 0;
    uint64_t singletonClass = rgctx ? ds_lq_read_ptr(rgctx + 0x10) : 0;
    instance = ds_lq_singleton_instance_from_class(singletonClass);
    return instance ? instance : ds_lq_singleton_instance_from_class(methodClass);
}

static uint64_t ds_lq_battle_logic_instance(void) {
    uint64_t methodInfo = ds_lq_read_ptr(
        ds_lq_addr(kDSLienQuanBattleSingletonMethodInfoRva));
    uint64_t methodClass = methodInfo ? ds_lq_read_ptr(methodInfo + 0x20) : 0;
    uint64_t rgctx = methodClass
        ? ds_lq_read_ptr(methodClass + kDSLienQuanIl2CppRGCTXDataOffset)
        : 0;
    uint64_t singletonClass = rgctx ? ds_lq_read_ptr(rgctx + 0x10) : 0;
    uint64_t instance = ds_lq_singleton_instance_from_class(singletonClass);
    return instance ? instance : ds_lq_singleton_instance_from_class(methodClass);
}

// Mirrors SLevelContext.GetGameRoomType() (RVA 0x6166058). The backing
// Room_type_Match field is not authoritative for match-made modes.
static int32_t ds_lq_game_room_type(int32_t mapType, int32_t levelId) {
    switch (mapType) {
        case 1:
            switch (levelId) {
                case 20001:
                case 23001:
                case 23011:
                    return 5;
                case 20009:
                    return 3;
                case 20011:
                case 40001:
                    return 0;
                case 20111:
                    return 1;
                case 23002:
                case 23012:
                    return 2;
                case 50002:
                    return 6;
                case 80003:
                case 80004:
                    return 0;
                case 90001:
                    return 4;
                default:
                    return 10;
            }
        case 3:
            return (levelId == 20011 || levelId == 20111) ? 1 : 10;
        case 4:
            switch (levelId) {
                case 20009: return 3;
                case 32000: return 9;
                case 50002: return 6;
                case 70001: return 7;
                case 70002: return 12;
                case 90001: return 4;
                case 90009: return 11;
                default: return 10;
            }
        default:
            return 10;
    }
}

static bool ds_lq_read_minimap_geometry(DSLQMinimapGeometry *out) {
    if (out) *out = {};
    if (!out) return false;
    uint64_t battleSystem = ds_lq_cbattle_system_instance();
    uint64_t minimap = battleSystem
        ? ds_lq_read_ptr(battleSystem + kDSLienQuanCBattleTheMinimapSysOffset)
        : 0;
    uint64_t transfer = minimap
        ? ds_lq_read_ptr(minimap + kDSLienQuanMinimapTransferOffset) : 0;
    uint64_t cuiManager = ds_lq_singleton_instance_from_methodinfo(
        kDSLienQuanCUIManagerSingletonMethodInfoRva);
    uint64_t formCamera = cuiManager
        ? ds_lq_read_ptr(cuiManager + kDSLienQuanCUIManagerFormCameraOffset)
        : 0;
    uint64_t nativeFormCamera = formCamera
        ? ds_lq_read_ptr(formCamera + kDSLienQuanUnityObjectCachedPtrOffset) : 0;
    uint64_t battleLogic = ds_lq_battle_logic_instance();
    uint64_t gameContext = battleLogic
        ? ds_lq_read_ptr(battleLogic +
                         kDSLienQuanBattleLogicGameContextOffset)
        : 0;
    uint64_t levelContext = gameContext
        ? ds_lq_read_ptr(gameContext +
                         kDSLienQuanGameContextLevelContextOffset)
        : 0;
    if (!battleSystem || !minimap || !transfer) {
        return false;
    }

    // MMSize (+0x08) and MMPos (+0x10) are one contiguous 16-byte block.
    // Read that block, the live conversion matrix, Unity's current render
    // resolution, and the optional level identity in one scatter pass.
    // CMapTransferData +0x08 through mmUGUIAnchorPos (+0x34).
    float mm[13] = {};
    float worldUIFactorSmall[4] = {};
    float screenSize[2] = {};
    float formCameraViewport[4] = {};
    uint8_t levelFields[0x10] = {};
    uint64_t gameSettingsFields = ds_lq_static_fields_from_typeinfo(
        kDSLienQuanGameSettingsTypeInfoRva);
    DSDebugReadRange ranges[5] = {
        { transfer + kDSLienQuanMinimapMMSizeOffset,
          mm, sizeof(mm), NO },
        { battleSystem + kDSLienQuanCBattleWorldUIFactorSmallOffset,
          worldUIFactorSmall, sizeof(worldUIFactorSmall), NO },
        { gameSettingsFields + kDSLienQuanScreenResolutionXOffset,
          screenSize, sizeof(screenSize), NO },
        { nativeFormCamera + kDSLienQuanNativeCameraViewportOffset,
          formCameraViewport, sizeof(formCameraViewport), NO },
        {}
    };
    size_t rangeCount = 4;
    if (levelContext) {
        ranges[rangeCount++] = {
            levelContext + kDSLienQuanLevelContextLevelIdOffset,
            levelFields, sizeof(levelFields), NO
        };
    }
    ds_debug_read_list(g_dslqVmMap, ranges, rangeCount);
    float mmSize[2] = {mm[0], mm[1]};
    float mmPos[2] = {mm[2], mm[3]};
    float mmAnchorPos[2] = {mm[11], mm[12]};
    bool screenSizeValid = gameSettingsFields && ranges[2].success &&
        isfinite(screenSize[0]) && isfinite(screenSize[1]) &&
        screenSize[0] >= 640.0f && screenSize[1] >= 320.0f &&
        screenSize[0] > screenSize[1];
    bool formViewportValid = ranges[3].success &&
        isfinite(formCameraViewport[0]) &&
        isfinite(formCameraViewport[1]) &&
        isfinite(formCameraViewport[2]) &&
        isfinite(formCameraViewport[3]) &&
        formCameraViewport[2] > 0.05f &&
        formCameraViewport[3] > 0.05f;
    bool valuesValid = ranges[0].success && ranges[1].success &&
        screenSizeValid &&
        formViewportValid &&
        isfinite(mmPos[0]) && isfinite(mmPos[1]) &&
        isfinite(mmSize[0]) && isfinite(mmSize[1]) &&
        isfinite(worldUIFactorSmall[0]) &&
        isfinite(worldUIFactorSmall[1]) &&
        isfinite(worldUIFactorSmall[2]) &&
        isfinite(worldUIFactorSmall[3]) &&
        mmSize[0] > 0.0f && mmSize[1] > 0.0f;
    bool valid = valuesValid;
    int32_t levelId = 0;
    int32_t levelMapType = 0;
    bool roomTypeOK = rangeCount == 5 && ranges[4].success;
    if (roomTypeOK) {
        memcpy(&levelId, levelFields, sizeof(levelId));
        memcpy(&levelMapType,
               levelFields + (kDSLienQuanLevelContextMapTypeOffset -
                              kDSLienQuanLevelContextLevelIdOffset),
               sizeof(levelMapType));
        roomTypeOK = levelId > 0;
    }
    int32_t roomType = roomTypeOK
        ? ds_lq_game_room_type(levelMapType, levelId) : -1;
    int32_t renderRoomType = mmSize[0] > 1.5f * mmSize[1]
        ? 3 : roomType;
    if (!valid) return false;

    out->valid = true;
    // ESP.h identifies the wide 3v3 prefab from its final screen aspect.
    out->roomType = renderRoomType;
    memcpy(out->mmPos, mmPos, sizeof(out->mmPos));
    memcpy(out->mmSize, mmSize, sizeof(out->mmSize));
    memcpy(out->mmAnchorPos, mmAnchorPos, sizeof(out->mmAnchorPos));
    out->storePosMode = g_dslqStorePosMode;
    memcpy(out->screenSize, screenSize, sizeof(out->screenSize));
    memcpy(out->formCameraViewport, formCameraViewport,
           sizeof(out->formCameraViewport));
    memcpy(out->worldUIFactorSmall, worldUIFactorSmall,
           sizeof(out->worldUIFactorSmall));
    return true;
}

static bool ds_lq_read_store_pos_mode(int32_t *modeOut) {
    if (!modeOut) return false;
    uint64_t fields = ds_lq_static_fields_from_typeinfo(
        kDSLienQuanGameSettingsTypeInfoRva);
    uint64_t config = fields
        ? ds_lq_read_ptr(fields + kDSLienQuanStorePosModeOffset) : 0;
    int32_t mode = -1;
    if (!config ||
        !ds_lq_read(config + kDSLienQuanConfigIntValueOffset,
                    &mode, sizeof(mode)) ||
        (mode != 0 && mode != 1)) {
        return false;
    }
    *modeOut = mode;
    return true;
}

static void ds_lq_refresh_minimap_geometry(CFAbsoluteTime now) {
    if (now >= g_dslqNextStorePosRead) {
        g_dslqNextStorePosRead = now + 1.0;
        int32_t mode = -1;
        if (ds_lq_read_store_pos_mode(&mode) &&
            mode != g_dslqStorePosMode) {
            bool changedInMatch = g_dslqStorePosMode >= 0;
            g_dslqStorePosMode = mode;
            if (changedInMatch) {
                // Store side also moves mmFinalScreenPos. Reacquire the whole
                // minimap geometry instead of applying the new mode to stale
                // coordinates cached before the setting changed.
                g_dslqMinimapCandidate = {};
                g_dslqMinimapStableSamples = 0;
                g_dslqMinimapCacheLocked = false;
                g_dslqMinimapCandidateSince = 0;
            }
        }
    }

    DSLQMinimapGeometry geometry = g_dslqMinimapCache;
    if (!g_dslqMinimapCacheLocked) {
        if (!ds_lq_read_minimap_geometry(&geometry)) {
            g_dslqMinimapCandidate = {};
            g_dslqMinimapStableSamples = 0;
            g_dslqMinimapCandidateSince = 0;
            return;
        }

        auto close = [](float lhs, float rhs, float tolerance) {
            return isfinite(lhs) && isfinite(rhs) &&
                   fabsf(lhs - rhs) <= tolerance;
        };
        bool matchesCandidate = g_dslqMinimapStableSamples > 0 &&
            geometry.roomType == g_dslqMinimapCandidate.roomType;
        for (int i = 0; matchesCandidate && i < 2; i++) {
            matchesCandidate =
                close(geometry.mmSize[i], g_dslqMinimapCandidate.mmSize[i],
                      0.05f) &&
                close(geometry.mmPos[i], g_dslqMinimapCandidate.mmPos[i],
                      0.05f) &&
                close(geometry.screenSize[i],
                      g_dslqMinimapCandidate.screenSize[i], 0.05f);
        }
        matchesCandidate = matchesCandidate &&
            geometry.storePosMode == g_dslqMinimapCandidate.storePosMode;
        for (int i = 0; matchesCandidate && i < 2; i++) {
            matchesCandidate = close(
                geometry.mmAnchorPos[i],
                g_dslqMinimapCandidate.mmAnchorPos[i], 0.05f);
        }
        for (int i = 0; matchesCandidate && i < 4; i++) {
            matchesCandidate = close(
                geometry.formCameraViewport[i],
                g_dslqMinimapCandidate.formCameraViewport[i], 0.0001f);
        }
        for (int i = 0; matchesCandidate && i < 4; i++) {
            matchesCandidate = close(
                geometry.worldUIFactorSmall[i],
                g_dslqMinimapCandidate.worldUIFactorSmall[i], 0.0001f);
        }
        if (!matchesCandidate) {
            g_dslqMinimapCandidate = geometry;
            g_dslqMinimapStableSamples = 1;
            g_dslqMinimapCandidateSince = now;
        } else if (g_dslqMinimapStableSamples < 5) {
            g_dslqMinimapStableSamples++;
        }
        // FightForm applies StorePosMode after the minimap first becomes
        // readable. In practice that can happen several seconds after the
        // transfer object is created, especially on slower devices. Do not
        // lock the pre-layout mmFinalScreenPos for the whole match: require
        // the complete runtime geometry to remain unchanged across the UI
        // setup window, then retain the resulting value for the match.
        if (g_dslqMinimapStableSamples >= 5 &&
            g_dslqMinimapCandidateSince > 0 &&
            now - g_dslqMinimapCandidateSince >= 5.0) {
            g_dslqMinimapCache = geometry;
            g_dslqMinimapCacheLocked = true;
        }
    }
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    if (g_dslqLiveSource.ready &&
        g_dslqLiveSource.matchEpoch == g_dslqMatchEpoch) {
        g_dslqLiveSource.minimap = geometry;
    }
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);
}

static bool ds_lq_minimap_point(const DSLQMinimapGeometry &map,
                                float x, float z, int32_t team,
                                float *widthOut, float *heightOut,
                                float *dxOut, float *dyOut) {
    if (!map.valid || !widthOut || !heightOut || !dxOut || !dyOut)
        return false;
    // Exact CvtWorld2UISM calculation from dump.cs RVA 0x5B26290.
    // The overlay marker belongs to the always-visible small minimap. curMapType
    // can briefly remain Big after the expanded map closes, so it must not
    // select the big-map conversion data here.
    float screenWidth = map.screenSize[0];
    float screenHeight = map.screenSize[1];
    // Node3D.Ratio() reads UnityEngine.Screen.width/height, not iOS nativeBounds.
    float ratio = MIN(screenWidth / 1136.0f, screenHeight / 640.0f);
    float sizeX = map.mmSize[0];
    float sizeY = map.mmSize[1];
    // Use the live matrix consumed by CBattleSystem.CvtWorld2UISM for every
    // map. It already contains the current map's scale, rotation and camp
    // orientation; room-specific world extents are only an approximation.
    (void)team;
    const float *factor = map.worldUIFactorSmall;
    float exactU = x * factor[0] + z * factor[1];
    float exactV = x * factor[2] + z * factor[3];
    float dx = exactU * ratio;
    float dy = -exactV * ratio;
    *widthOut = sizeX;
    *heightOut = sizeY;
    *dxOut = dx;
    *dyOut = dy;
    return isfinite(sizeX) && isfinite(sizeY) && ratio > 0.0f &&
           isfinite(dx) && isfinite(dy);
}

static int ds_lq_count_pointer_slots(uint64_t items, int count,
                                     uint64_t stride) {
    if (!items || count <= 0) return 0;
    int limit = count > 16 ? 16 : count;
    uint64_t base = items + 0x20;
    int hits = 0;
    for (int i = 0; i < limit; i++) {
        if (ds_lq_read_ptr(base + (uint64_t)i * stride)) hits++;
    }
    return hits;
}

static bool ds_lq_read_context_list(uint64_t listView, int maxCount,
                                    uint64_t *contextOut,
                                    uint64_t *contextOffsetOut, int *countOut,
                                    uint64_t *itemsOut) {
    if (contextOut) *contextOut = 0;
    if (contextOffsetOut) *contextOffsetOut = 0;
    if (countOut) *countOut = -1;
    if (itemsOut) *itemsOut = 0;
    if (!listView) return false;

    bool found = false;
    int bestScore = -1;
    uint64_t bestContext = 0;
    uint64_t bestOffset = 0;
    int bestCount = -1;
    uint64_t bestItems = 0;
    for (uint64_t offset = 0; offset <= 0x80; offset += 0x08) {
        uint64_t context = ds_lq_read_ptr(listView + offset);
        int count = -1;
        uint64_t items = 0;
        if (!context || !ds_lq_read_list(context, &count, &items) ||
            count > maxCount)
            continue;
        int nonZero = ds_lq_count_pointer_slots(items, count, sizeof(uint64_t));
        int score = nonZero * 1000 + (count > 0 ? 100 : 0) + count;
        if (!found || score > bestScore ||
            (score == bestScore && offset == kDSLienQuanListViewContextOffset)) {
            found = true;
            bestScore = score;
            bestContext = context;
            bestOffset = offset;
            bestCount = count;
            bestItems = items;
        }
    }
    if (!found) return false;
    if (contextOut) *contextOut = bestContext;
    if (contextOffsetOut) *contextOffsetOut = bestOffset;
    if (countOut) *countOut = bestCount;
    if (itemsOut) *itemsOut = bestItems;
    return true;
}

static bool ds_lq_read_hero_root_candidate(uint64_t actor,
                                           DSLienQuanVInt3 *locationOut,
                                           DSLienQuanActorMeta *metaOut) {
    if (!actor) return false;
    uint64_t expectedClass = ds_lq_read_ptr(
        ds_lq_addr(kDSLienQuanActorRootTypeInfoRva));
    uint64_t actorClass = ds_lq_read_ptr(actor);
    bool actorClassOK = false;
    for (int depth = 0; actorClass && depth < 8; depth++) {
        if (actorClass == expectedClass) {
            actorClassOK = true;
            break;
        }
        actorClass = ds_lq_read_ptr(
            actorClass + kDSLienQuanIl2CppParentClassOffset);
    }
    if (!actorClassOK) return false;
    DSLienQuanVInt3 location = {};
    DSLienQuanActorMeta meta = {};
    if (!ds_lq_read_actor_location(actor, &location) ||
        !ds_lq_read(actor + kDSLienQuanActorRootMetaOffset,
                    &meta, sizeof(meta)) ||
        meta.actorType != 0 ||
        (meta.configId == 0 && meta.playerId == 0)) return false;
    if (locationOut) *locationOut = location;
    if (metaOut) *metaOut = meta;
    return true;
}

static uint64_t ds_lq_read_hero_root_at(uint64_t items, int index,
                                        DSLienQuanVInt3 *locationOut,
                                        DSLienQuanActorMeta *metaOut) {
    uint64_t base = items + 0x20;
    uint64_t slots[3] = {
        base + (uint64_t)index * 0x10 +
            kDSLienQuanPoolObjHandleObjectOffset,
        base + (uint64_t)index * 0x10,
        base + (uint64_t)index * sizeof(uint64_t),
    };
    for (int layout = 0; layout < 3; layout++) {
        if ((layout > 0 && slots[layout] == slots[0]) ||
            (layout > 1 && slots[layout] == slots[1])) continue;
        uint64_t actor = ds_lq_read_ptr(slots[layout]);
        if (ds_lq_read_hero_root_candidate(
                actor, locationOut, metaOut)) return actor;
    }
    return 0;
}

static int ds_lq_count_lactor_roots(uint64_t items, int count,
                                    int stopAfter) {
    if (!items || count <= 0) return 0;
    int limit = count > kDSLQMaxHeroes ? kDSLQMaxHeroes : count;
    int hits = 0;
    for (int i = 0; i < limit; i++) {
        if (!ds_lq_read_hero_root_at(items, i, NULL, NULL)) continue;
        hits++;
        if (stopAfter > 0 && hits >= stopAfter) break;
    }
    return hits;
}

static bool ds_lq_try_actor_root_list(uint64_t manager, uint64_t offset,
                                      uint64_t *listOut,
                                      uint64_t *itemsOut, int *countOut) {
    uint64_t list = manager ? ds_lq_read_ptr(manager + offset) : 0;
    uint64_t items = 0;
    int count = -1;
    bool ok = list && list != manager &&
              ds_lq_read_list(list, &count, &items) &&
              (offset != kDSLienQuanGameActorMgrHeroActorsOffset ||
               count <= kDSLQMaxHeroes) &&
              ds_lq_count_lactor_roots(items, count, 1) > 0;
    if (listOut) *listOut = list;
    if (itemsOut) *itemsOut = items;
    if (countOut) *countOut = count;
    return ok;
}

static bool ds_lq_try_actor_manager(uint64_t manager,
                                    uint64_t *heroListOut,
                                    uint64_t *heroItemsOut,
                                    int *heroCountOut) {
    if (!manager) return false;
    if (ds_lq_try_actor_root_list(
            manager, kDSLienQuanGameActorMgrHeroActorsOffset,
            heroListOut, heroItemsOut, heroCountOut)) return true;
    return ds_lq_try_actor_root_list(
        manager, kDSLienQuanGameActorMgrGameActorsOffset,
        heroListOut, heroItemsOut, heroCountOut);
}

static bool ds_lq_try_battle(uint64_t battle, uint64_t *managerOut,
                             uint64_t *heroListOut,
                             uint64_t *heroItemsOut, int *heroCountOut) {
    if (!battle) return false;
    uint64_t expectedClass = ds_lq_read_ptr(
        ds_lq_addr(kDSLienQuanLBattleLogicTypeInfoRva));
    uint64_t battleClass = ds_lq_read_ptr(battle);
    bool battleClassOK = false;
    for (int depth = 0; battleClass && depth < 8; depth++) {
        if (battleClass == expectedClass) {
            battleClassOK = true;
            break;
        }
        battleClass = ds_lq_read_ptr(
            battleClass + kDSLienQuanIl2CppParentClassOffset);
    }
    if (!battleClassOK) return false;

    if (g_dslqModuleScanBattle != battle) {
        g_dslqModuleScanBattle = battle;
        g_dslqModuleScanIndex = 0;
        g_dslqDynamicModuleScanIndex = 0;
    }

    uint64_t manager = ds_lq_read_ptr(
        battle + kDSLienQuanBattleGameActorMgrOffset);
    if (ds_lq_try_actor_manager(manager, heroListOut,
                                heroItemsOut, heroCountOut)) {
        if (managerOut) *managerOut = manager;
        return true;
    }

    uint64_t listView = ds_lq_read_ptr(
        battle + kDSLienQuanBattleModulesOffset);
    uint64_t context = 0;
    uint64_t contextOffset = 0;
    uint64_t items = 0;
    int count = -1;
    if (ds_lq_read_context_list(listView, 96, &context, &contextOffset,
                                &count, &items)) {
        int limit = count > 96 ? 96 : count;
        uint64_t base = items + 0x20;
        int batch = limit > 8 ? 8 : limit;
        for (int step = 0; step < batch; step++) {
            int i = limit > 0
                ? (g_dslqModuleScanIndex + step) % limit : 0;
            uint64_t candidates[3] = {
                ds_lq_read_ptr(base + (uint64_t)i * sizeof(uint64_t)),
                ds_lq_read_ptr(base + (uint64_t)i * 0x10),
                ds_lq_read_ptr(base + (uint64_t)i * 0x10 +
                               kDSLienQuanPoolObjHandleObjectOffset),
            };
            for (int j = 0; j < 3; j++) {
                if ((j > 0 && candidates[j] == candidates[0]) ||
                    (j > 1 && candidates[j] == candidates[1])) continue;
                if (!ds_lq_try_actor_manager(candidates[j], heroListOut,
                                             heroItemsOut, heroCountOut))
                    continue;
                if (managerOut) *managerOut = candidates[j];
                return true;
            }
        }
        if (limit > 0)
            g_dslqModuleScanIndex =
                (g_dslqModuleScanIndex + batch) % limit;
    }

    uint64_t modules = ds_lq_read_ptr(
        battle + kDSLienQuanBattleDynamicModulesOffset);
    int32_t moduleCount = -1;
    if (modules && ds_lq_read(modules + 0x18, &moduleCount,
                              sizeof(moduleCount)) &&
        moduleCount >= 0 && moduleCount <= 96) {
        int batch = moduleCount > 8 ? 8 : moduleCount;
        for (int step = 0; step < batch; step++) {
            int i = moduleCount > 0
                ? (g_dslqDynamicModuleScanIndex + step) % moduleCount : 0;
            uint64_t candidate = ds_lq_read_ptr(
                modules + 0x20 + (uint64_t)i * sizeof(uint64_t));
            if (!ds_lq_try_actor_manager(candidate, heroListOut,
                                         heroItemsOut, heroCountOut))
                continue;
            if (managerOut) *managerOut = candidate;
            return true;
        }
        if (moduleCount > 0)
            g_dslqDynamicModuleScanIndex =
                (g_dslqDynamicModuleScanIndex + batch) % moduleCount;
    }
    return false;
}

static bool ds_lq_try_desk(uint64_t desk, uint64_t *battleOut,
                           uint64_t *managerOut, uint64_t *heroListOut,
                           uint64_t *heroItemsOut, int *heroCountOut) {
    uint64_t battle = desk
        ? ds_lq_read_ptr(desk + kDSLienQuanDeskBattleLogicOffset)
        : 0;
    uint64_t manager = 0;
    uint64_t heroList = 0;
    uint64_t heroItems = 0;
    int heroCount = -1;
    bool ok = ds_lq_try_battle(battle, &manager, &heroList,
                               &heroItems, &heroCount);
    if (battleOut) *battleOut = battle;
    if (managerOut) *managerOut = manager;
    if (heroListOut) *heroListOut = heroList;
    if (heroItemsOut) *heroItemsOut = heroItems;
    if (heroCountOut) *heroCountOut = heroCount;
    return ok;
}

static bool ds_lq_try_logic_candidate(uint64_t candidate,
                                      uint64_t *battleOut,
                                      uint64_t *managerOut,
                                      uint64_t *heroListOut,
                                      uint64_t *heroItemsOut,
                                      int *heroCountOut) {
    if (!candidate) return false;
    if (ds_lq_try_battle(candidate, managerOut, heroListOut,
                         heroItemsOut, heroCountOut)) {
        if (battleOut) *battleOut = candidate;
        return true;
    }
    if (ds_lq_try_desk(candidate, battleOut, managerOut, heroListOut,
                       heroItemsOut, heroCountOut)) return true;
    uint64_t refObject = ds_lq_read_ptr(
        candidate + kDSLienQuanRefWrapperObjectOffset);
    if (refObject && ds_lq_try_battle(refObject, managerOut, heroListOut,
                                      heroItemsOut, heroCountOut)) {
        if (battleOut) *battleOut = refObject;
        return true;
    }
    return refObject && ds_lq_try_desk(
        refObject, battleOut, managerOut, heroListOut,
        heroItemsOut, heroCountOut);
}

static bool ds_lq_scan_object_for_manager(uint64_t object,
                                          uint64_t *managerOut,
                                          uint64_t *heroListOut,
                                          uint64_t *heroItemsOut,
                                          int *heroCountOut) {
    if (!object) return false;
    for (uint64_t offset = 0x10; offset <= 0x220; offset += 0x08) {
        uint64_t candidate = ds_lq_read_ptr(object + offset);
        if (!ds_lq_try_actor_manager(candidate, heroListOut,
                                     heroItemsOut, heroCountOut)) continue;
        if (managerOut) *managerOut = candidate;
        return true;
    }
    return false;
}

static bool ds_lq_scan_object_for_logic(uint64_t object,
                                        uint64_t *battleOut,
                                        uint64_t *managerOut,
                                        uint64_t *heroListOut,
                                        uint64_t *heroItemsOut,
                                        int *heroCountOut) {
    if (!object) return false;
    for (uint64_t offset = 0x10; offset <= 0x180; offset += 0x08) {
        uint64_t candidate = ds_lq_read_ptr(object + offset);
        if (ds_lq_try_logic_candidate(candidate, battleOut, managerOut,
                                      heroListOut, heroItemsOut,
                                      heroCountOut)) return true;
        if (!candidate) continue;
        for (uint64_t inner = 0x10; inner <= 0x90; inner += 0x08) {
            uint64_t nested = ds_lq_read_ptr(candidate + inner);
            if (ds_lq_try_logic_candidate(nested, battleOut, managerOut,
                                          heroListOut, heroItemsOut,
                                          heroCountOut)) return true;
        }
    }
    return false;
}

static bool ds_lq_find_manager_from_players(uint64_t playerCenter,
                                            uint64_t *battleOut,
                                            uint64_t *managerOut,
                                            uint64_t *heroListOut,
                                            uint64_t *heroItemsOut,
                                            int *heroCountOut) {
    uint64_t listView = playerCenter
        ? ds_lq_read_ptr(playerCenter + kDSLienQuanPlayerCenterPlayersOffset)
        : 0;
    if (!listView) return false;

    uint64_t context = 0;
    uint64_t contextOffset = 0;
    uint64_t items = 0;
    int playerCount = -1;
    if (!ds_lq_read_context_list(listView, 16, &context, &contextOffset,
                                 &playerCount, &items) || playerCount <= 0)
        return false;

    int limit = playerCount > 16 ? 16 : playerCount;
    uint64_t base = items + 0x20;
    for (int i = 0; i < limit; i++) {
        uint64_t slots[3] = {
            base + (uint64_t)i * sizeof(uint64_t),
            base + (uint64_t)i * 0x10,
            base + (uint64_t)i * 0x10 +
                kDSLienQuanPoolObjHandleObjectOffset,
        };
        for (int layout = 0; layout < 3; layout++) {
            if ((layout == 1 && slots[1] == slots[0]) ||
                (layout == 2 && (slots[2] == slots[0] ||
                                 slots[2] == slots[1]))) continue;
            uint64_t player = ds_lq_read_ptr(slots[layout]);
            if (!player) continue;
            uint32_t playerId = 0;
            int32_t camp = -1;
            if (!ds_lq_read(player + kDSLienQuanPlayerIdOffset,
                            &playerId, sizeof(playerId)) ||
                !ds_lq_read(player + kDSLienQuanPlayerCampOffset,
                            &camp, sizeof(camp)) ||
                playerId == 0 || playerId > 100000000 ||
                camp < 0 || camp > 8) continue;
            uint64_t refWrapper = ds_lq_read_ptr(
                player + kDSLienQuanPlayerBattleRefOffset);
            uint64_t battle = refWrapper
                ? ds_lq_read_ptr(refWrapper +
                                 kDSLienQuanRefWrapperObjectOffset)
                : 0;
            uint64_t manager = 0;
            uint64_t heroList = 0;
            int heroCount = -1;
            uint64_t heroItems = 0;
            bool listOK = ds_lq_try_battle(
                battle, &manager, &heroList, &heroItems, &heroCount);
            int rootHits = listOK
                ? ds_lq_count_lactor_roots(
                    heroItems, heroCount, kDSLQMaxHeroes)
                : 0;
            if (rootHits <= 0) break;

            if (battleOut) *battleOut = battle;
            if (managerOut) *managerOut = manager;
            if (heroListOut) *heroListOut = heroList;
            if (heroItemsOut) *heroItemsOut = heroItems;
            if (heroCountOut) *heroCountOut = heroCount;
            return true;
        }
    }
    return false;
}

static int ds_lq_matrix_nonzero_count(const float matrix[16]) {
    int nonZero = 0;
    float maxAbs = 0.0f;
    for (int i = 0; i < 16; i++) {
        if (!isfinite(matrix[i])) return -1;
        float value = fabsf(matrix[i]);
        if (value > 0.000001f) nonZero++;
        if (value > maxAbs) maxAbs = value;
    }
    if (maxAbs <= 0.0001f || maxAbs >= 1000000.0f) return -1;
    return nonZero;
}

static void ds_lq_multiply_matrices(const float lhs[16], const float rhs[16],
                                    float result[16]) {
    for (int row = 0; row < 4; row++) {
        for (int column = 0; column < 4; column++) {
            float value = 0.0f;
            for (int inner = 0; inner < 4; inner++) {
                value += lhs[row * 4 + inner] * rhs[inner * 4 + column];
            }
            result[row * 4 + column] = value;
        }
    }
}

static bool ds_lq_project_combined(const float matrix[16], float x, float y,
                                   float z, float *uOut, float *vOut) {
    float clipW = x * matrix[3] + y * matrix[7] +
                  z * matrix[11] + matrix[15];
    if (!isfinite(clipW) || clipW < 0.0001f) return false;
    float ndcX = (x * matrix[0] + y * matrix[4] +
                  z * matrix[8] + matrix[12]) / clipW;
    float ndcY = (x * matrix[1] + y * matrix[5] +
                  z * matrix[9] + matrix[13]) / clipW;
    if (!isfinite(ndcX) || !isfinite(ndcY) ||
        ndcX < -1.8f || ndcX > 1.8f || ndcY < -1.8f || ndcY > 1.8f)
        return false;
    if (uOut) *uOut = (1.0f + ndcX) * 0.5f;
    if (vOut) *vOut = (1.0f - ndcY) * 0.5f;
    return true;
}

static uint64_t ds_lq_roster_signature(const uint64_t *actors,
                                       const DSLienQuanActorMeta *metas,
                                       int count, int expectedCount) {
    uint64_t xorPart = 0;
    uint64_t sumPart = 0;
    for (int i = 0; i < count; i++) {
        uint64_t value = actors[i] ^ ((uint64_t)metas[i].playerId << 32) ^
            ((uint64_t)metas[i].configId << 1) ^
            ((uint64_t)(uint32_t)metas[i].actorCamp << 56);
        value ^= value >> 30;
        value *= 0xbf58476d1ce4e5b9ULL;
        value ^= value >> 27;
        value *= 0x94d049bb133111ebULL;
        value ^= value >> 31;
        xorPart ^= value;
        sumPart += value;
    }
    return xorPart ^ (sumPart << 1) ^ ((uint64_t)(uint32_t)count << 48) ^
           (uint64_t)(uint32_t)expectedCount;
}

static bool ds_lq_roster_observation_complete(
    const uint64_t *actors, const DSLienQuanActorMeta *metas, int count,
    int expectedCount) {
    if (!actors || !metas || expectedCount <= 0 ||
        expectedCount > kDSLQMaxHeroes || count != expectedCount) return false;
    for (int i = 0; i < count; i++) {
        if (!actors[i] || !metas[i].playerId || metas[i].actorCamp <= 0)
            return false;
        for (int j = 0; j < i; j++) {
            if (actors[j] == actors[i] ||
                metas[j].playerId == metas[i].playerId) return false;
        }
    }
    return true;
}

static bool ds_lq_jungle_monster_allowed(uint32_t configId) {
    switch (configId) {
        case 49:
        case 123:
        case 124:
        case 7009:
        case 7010:
        case 7011:
        case 7012:
        case 7024:
        case 70092:
        case 70093:
        case 547010:
        case 547011:
            return true;
        default:
            return false;
    }
}

static bool ds_lq_auto_smite_target_allowed(uint32_t configId,
                                             bool objectivesOnly) {
    if (!ds_lq_jungle_monster_allowed(configId)) return false;
    if (!objectivesOnly) return true;
    switch (configId) {
        case 7010:
        case 7011:
        case 547010:
        case 547011:
            return false;
        default:
            return true;
    }
}

static uint64_t ds_lq_monster_roster_signature(
    const DSLQMonsterReadEntry *monsters,
    const uint64_t *valueProperties, const uint64_t *gameObjects, int count) {
    uint64_t xorPart = 0;
    uint64_t sumPart = 0;
    for (int i = 0; i < count; i++) {
        uint64_t value = monsters[i].actor ^
            ((uint64_t)monsters[i].configId << 17) ^
            ((uint64_t)(uint32_t)monsters[i].actorCamp << 53) ^
            (valueProperties ? valueProperties[i] : 0) ^
            (gameObjects ? ((gameObjects[i] << 23) |
                            (gameObjects[i] >> 41)) : 0);
        value ^= value >> 30;
        value *= 0xbf58476d1ce4e5b9ULL;
        value ^= value >> 27;
        value *= 0x94d049bb133111ebULL;
        value ^= value >> 31;
        xorPart ^= value;
        sumPart += value;
    }
    return xorPart ^ (sumPart << 1) ^
        ((uint64_t)(uint32_t)count << 48);
}

static bool ds_lq_copy_coherent_monster_sample(
    const DSLQMonsterReadEntry &source, DSLQActorMotion *motionOut,
    int32_t *hpOut) {
    if (!motionOut || !hpOut) return false;
    for (int attempt = 0; attempt < 3; attempt++) {
        DSLQLQCrypticInt32 hpBefore = {};
        DSLQLQCrypticInt32 hpAfter = {};
        DSLQActorMotion motion = {};
        if (!ds_lq_copy_pinned_span(source.health, &hpBefore,
                                    sizeof(hpBefore)) ||
            !ds_lq_copy_coherent_motion(source.motion, &motion) ||
            !ds_lq_copy_pinned_span(source.health, &hpAfter,
                                    sizeof(hpAfter)) ||
            memcmp(&hpBefore, &hpAfter, sizeof(hpBefore)) != 0 ||
            !ds_lq_location_valid(&motion.location)) continue;
        int32_t hp = ds_lq_cryptic_int32_value(hpAfter);
        if (hp < 0 || hp > 100000000) continue;
        *motionOut = motion;
        *hpOut = hp;
        return true;
    }
    return false;
}

static bool ds_lq_copy_coherent_monster_motion(
    const DSLQMonsterReadEntry &source, DSLQActorMotion *motionOut) {
    if (!motionOut) return false;
    DSLQActorMotion motion = {};
    if (!ds_lq_copy_coherent_motion(source.motion, &motion) ||
        !ds_lq_location_valid(&motion.location)) return false;
    *motionOut = motion;
    return true;
}

typedef struct {
    uint64_t list;
    uint64_t items;
    uint64_t capacity;
    int32_t size;
    int32_t version;
} DSLQManagedListState;

typedef struct {
    int32_t skillId;
    int32_t damage;
} DSLQSmiteState;

typedef struct {
    bool caesarReduced;
    bool slayerReduced;
} DSLQSmiteDamagePenalty;

enum : uint8_t {
    kDSLQSmitePenaltyGroupNone = 0,
    kDSLQSmitePenaltyGroupCaesar = 1 << 0,
    kDSLQSmitePenaltyGroupSlayer = 1 << 1,
};

typedef struct {
    uint64_t actor;
    uint32_t objectId;
    int32_t hp;
} DSLQSmiteTarget;

static bool ds_lq_write_verified(uint64_t address, const void *buffer,
                                 size_t length) {
    uint8_t observed[0x80] = {};
    if (!buffer || !length || length > sizeof(observed) ||
        !ds_debug_write_bytes(g_dslqVmMap, address, buffer, length) ||
        !ds_lq_read(address, observed, length)) return false;
    return memcmp(observed, buffer, length) == 0;
}

static bool ds_lq_read_managed_list(uint64_t list,
                                    DSLQManagedListState *out) {
    if (out) *out = {};
    if (!out || !ds_lq_valid(list) || (list & 0x7ULL)) return false;
    uint64_t items = ds_lq_read_ptr(list + 0x08);
    int32_t metadata[2] = {};
    uint64_t capacity = 0;
    if (!items || !ds_lq_read(list + 0x10, metadata, sizeof(metadata)) ||
        !ds_lq_read(items + kDSLienQuanManagedArrayLengthOffset,
                    &capacity, sizeof(capacity)) ||
        metadata[0] < 0 || capacity > 65536 ||
        (uint64_t)metadata[0] > capacity) return false;
    out->list = list;
    out->items = items;
    out->capacity = capacity;
    out->size = metadata[0];
    out->version = metadata[1];
    return true;
}

static bool ds_lq_managed_list_unchanged(
    const DSLQManagedListState &expected) {
    DSLQManagedListState observed = {};
    return ds_lq_read_managed_list(expected.list, &observed) &&
           observed.items == expected.items &&
           observed.capacity == expected.capacity &&
           observed.size == expected.size &&
           observed.version == expected.version;
}

static uint64_t ds_lq_managed_array_object(uint64_t array,
                                           uint64_t index) {
    uint64_t length = 0;
    if (!array ||
        !ds_lq_read(array + kDSLienQuanManagedArrayLengthOffset,
                    &length, sizeof(length)) ||
        index >= length || length > 4096) return 0;
    return ds_lq_read_ptr(array + kDSLienQuanManagedArrayDataOffset +
                          index * sizeof(uint64_t));
}

static int32_t ds_lq_normalize_smite_id(int32_t skillId) {
    return skillId > 3100000 ? skillId - 3100000 : skillId;
}

static bool ds_lq_is_smite_id(int32_t skillId) {
    int32_t normalized = ds_lq_normalize_smite_id(skillId);
    return normalized == 80104 || normalized == 80116;
}

static bool ds_lq_host_has_fenrir(uint64_t hostActor) {
    uint64_t equip = ds_lq_read_ptr(hostActor + 0x328);
    uint64_t equips = equip ? ds_lq_read_ptr(equip + 0x48) : 0;
    int32_t count = 0;
    uint64_t length = 0;
    if (!equips || !ds_lq_read(equip + 0x50, &count, sizeof(count)) ||
        !ds_lq_read(equips + kDSLienQuanManagedArrayLengthOffset,
                    &length, sizeof(length)) ||
        count <= 0 || count > 64 || length > 64) return false;
    int32_t limit = MIN(count, (int32_t)length);
    limit = MIN(limit, 6);
    uint8_t entries[6 * 0x0C] = {};
    if (limit <= 0 ||
        !ds_lq_read(equips + kDSLienQuanManagedArrayDataOffset,
                    entries, (size_t)limit * 0x0C)) return false;
    for (int32_t i = 0; i < limit; i++) {
        uint16_t equipId = 0;
        memcpy(&equipId, entries + (size_t)i * 0x0C, sizeof(equipId));
        if (equipId == 1138) return true;
    }
    return false;
}

static uint64_t ds_lq_find_host_actor_linker(uint64_t hostActor) {
    uint32_t hostObjectId = 0;
    if (!hostActor ||
        !ds_lq_read(hostActor + kDSLienQuanActorRootObjectIdOffset,
                    &hostObjectId, sizeof(hostObjectId)) || !hostObjectId)
        return 0;
    uint64_t framework = g_dslqCachedFramework;
    uint64_t actorManager = g_dslqCachedActorManager;
    if (!actorManager && framework) {
        actorManager = ds_lq_read_ptr(
            framework + kDSLienQuanKyriosActorManagerOffset);
        if (actorManager) g_dslqCachedActorManager = actorManager;
    }
    uint64_t list = actorManager ? ds_lq_read_ptr(
        actorManager + kDSLienQuanActorManagerHeroActorsOffset) : 0;
    int count = 0;
    uint64_t items = 0;
    if (!list || !ds_lq_read_list(list, &count, &items) ||
        count <= 0 || count > 64 || !items) return 0;
    for (int i = 0; i < count; i++) {
        uint64_t slot = items + kDSLienQuanArrayDataOffset +
            (uint64_t)i * kDSLienQuanPoolObjHandleStride;
        uint64_t candidates[2] = {
            ds_lq_read_ptr(slot + kDSLienQuanPoolObjHandleObjectOffset),
            ds_lq_read_ptr(slot)
        };
        for (uint64_t candidate : candidates) {
            if (!candidate) continue;
            uint32_t objectId = 0;
            if (ds_lq_read(candidate + kDSLienQuanActorLinkerObjectIdOffset,
                           &objectId, sizeof(objectId)) &&
                objectId == hostObjectId) return candidate;
        }
    }
    return 0;
}

static uint8_t ds_lq_smite_penalty_group(uint32_t monsterConfigId) {
    switch (monsterConfigId) {
        case 7012:
        case 70093:
        case 123:
        case 124:
            return kDSLQSmitePenaltyGroupCaesar;
        case 70092:
        case 7024:
        case 7009:
            return kDSLQSmitePenaltyGroupSlayer;
        default:
            return kDSLQSmitePenaltyGroupNone;
    }
}

static CFTimeInterval ds_lq_smite_penalty_remaining(
    uint64_t buff, uint64_t logicFrameTick) {
    int32_t duration = 0;
    uint64_t startTick = 0;
    if (!ds_lq_read(buff + kDSLienQuanBuffSkillDurationOffset,
                    &duration, sizeof(duration)) ||
        duration <= 0 || duration > 86400000)
        return kDSLQSmitePenaltyNegativeCache;
    if (!logicFrameTick ||
        !ds_lq_read(buff + kDSLienQuanBuffSkillInitStampOffset,
                    &startTick, sizeof(startTick)) ||
        !startTick || logicFrameTick < startTick)
        return (CFTimeInterval)duration / 1000.0;
    uint64_t elapsed = logicFrameTick - startTick;
    if (elapsed >= (uint64_t)duration)
        return kDSLQSmitePenaltyNegativeCache;
    return (CFTimeInterval)((uint64_t)duration - elapsed) / 1000.0;
}

static bool ds_lq_read_smite_damage_penalty(
    CFAbsoluteTime now, uint64_t hostActor, uint8_t requiredGroups,
    DSLQSmiteDamagePenalty *out) {
    if (out) *out = {};
    if (!out) return false;
    out->caesarReduced = now < g_dslqSmiteCaesarPenaltyUntil;
    out->slayerReduced = now < g_dslqSmiteSlayerPenaltyUntil;
    uint8_t activeGroups =
        (out->caesarReduced ? kDSLQSmitePenaltyGroupCaesar : 0) |
        (out->slayerReduced ? kDSLQSmitePenaltyGroupSlayer : 0);
    if (!(requiredGroups & ~activeGroups) ||
        now < g_dslqSmitePenaltyNegativeUntil) return true;

    uint64_t linker = ds_lq_find_host_actor_linker(hostActor);
    uint64_t buffControl = linker ? ds_lq_read_ptr(
        linker + kDSLienQuanActorLinkerBuffControlOffset) : 0;
    uint64_t spawned = buffControl ? ds_lq_read_ptr(
        buffControl + kDSLienQuanSpawnedBuffListOffset) : 0;
    if (!linker || !buffControl || !spawned) return false;

    uint64_t logicFrameTick = 0;
    uint64_t battleLogic = ds_lq_battle_logic_instance();
    if (battleLogic) {
        ds_lq_read(battleLogic + kDSLienQuanBattleLogicFrameTickOffset,
                   &logicFrameTick, sizeof(logicFrameTick));
    }

    for (int attempt = 0; attempt < 2; attempt++) {
        DSLQManagedListState state = {};
        if (!ds_lq_read_managed_list(spawned, &state) ||
            state.size < 0 || state.size > 256) return false;
        DSLQSmiteDamagePenalty observed = {};
        CFTimeInterval caesarRemaining = 0;
        CFTimeInterval slayerRemaining = 0;
        for (int32_t i = 0; i < state.size; i++) {
            uint64_t buff = ds_lq_read_ptr(
                state.items + kDSLienQuanManagedArrayDataOffset +
                (uint64_t)i * sizeof(uint64_t));
            uint64_t cfgData = buff ? ds_lq_read_ptr(
                buff + kDSLienQuanBuffSkillCfgDataOffset) : 0;
            int32_t skillId = 0;
            if (!cfgData ||
                !ds_lq_read(cfgData + kDSLienQuanBuffCfgSkillIdOffset,
                            &skillId, sizeof(skillId))) continue;
            switch (skillId) {
                case 7012920:
                case 7012921:
                    observed.caesarReduced = true;
                    caesarRemaining = MAX(
                        caesarRemaining,
                        ds_lq_smite_penalty_remaining(buff, logicFrameTick));
                    break;
                case 7024910:
                case 7024930:
                case 7012930:
                    observed.slayerReduced = true;
                    slayerRemaining = MAX(
                        slayerRemaining,
                        ds_lq_smite_penalty_remaining(buff, logicFrameTick));
                    break;
                default:
                    break;
            }
        }
        if (!ds_lq_managed_list_unchanged(state)) continue;
        if (observed.caesarReduced &&
            g_dslqSmiteCaesarPenaltyUntil <= now) {
            g_dslqSmiteCaesarPenaltyUntil = now + caesarRemaining;
        }
        if (observed.slayerReduced &&
            g_dslqSmiteSlayerPenaltyUntil <= now) {
            g_dslqSmiteSlayerPenaltyUntil = now + slayerRemaining;
        }
        g_dslqSmitePenaltyNegativeUntil =
            now + kDSLQSmitePenaltyNegativeCache;
        out->caesarReduced = now < g_dslqSmiteCaesarPenaltyUntil;
        out->slayerReduced = now < g_dslqSmiteSlayerPenaltyUntil;
        return true;
    }
    return false;
}

static int32_t ds_lq_effective_smite_damage(
    int32_t rawDamage, uint32_t monsterConfigId,
    const DSLQSmiteDamagePenalty &penalty) {
    uint8_t group = ds_lq_smite_penalty_group(monsterConfigId);
    bool reduced =
        (group == kDSLQSmitePenaltyGroupCaesar && penalty.caesarReduced) ||
        (group == kDSLQSmitePenaltyGroupSlayer && penalty.slayerReduced);
    return reduced ? rawDamage / 2 : rawDamage;
}

static bool ds_lq_read_smite_state(uint64_t hostActor,
                                   bool verifyVisual,
                                   DSLQSmiteState *out) {
    if (out) *out = {};
    if (!out || !hostActor) return false;
    uint64_t skillControl = ds_lq_read_ptr(
        hostActor + kDSLienQuanActorRootSkillControlOffset);
    uint64_t slots = skillControl ? ds_lq_read_ptr(
        skillControl + kDSLienQuanSkillSlotArrayOffset) : 0;
    uint64_t slot = ds_lq_managed_array_object(slots, 5);
    int32_t slotType = -1;
    int32_t damage = 0;
    DSLQLQCrypticInt32 cooldown = {};
    uint64_t skill = slot ? ds_lq_read_ptr(
        slot + kDSLienQuanLogicSkillSlotSkillOffset) : 0;
    int32_t skillId = 0;
    if (!slot || !skill ||
        !ds_lq_read(slot + kDSLienQuanSkillSlotTypeOffset,
                    &slotType, sizeof(slotType)) || slotType != 5 ||
        !ds_lq_read(slot + kDSLienQuanSkillSlotCooldownOffset,
                    &cooldown, sizeof(cooldown)) ||
        ds_lq_cryptic_int32_value(cooldown) != 0 ||
        !ds_lq_read(slot + kDSLienQuanLogicSkillSlotSyncDataOffset +
                        kDSLienQuanSkillStateDataDamageOffset,
                    &damage, sizeof(damage)) ||
        !ds_lq_read(skill + kDSLienQuanLogicSkillIdOffset,
                    &skillId, sizeof(skillId)) ||
        !ds_lq_is_smite_id(skillId) || damage <= 0 || damage > 1000000)
        return false;

    if (verifyVisual) {
        uint64_t linker = ds_lq_find_host_actor_linker(hostActor);
        uint64_t visualControl = linker ? ds_lq_read_ptr(
            linker + kDSLienQuanActorLinkerSkillControlOffset) : 0;
        uint64_t visualSlots = visualControl ? ds_lq_read_ptr(
            visualControl + kDSLienQuanVisualSkillSlotArrayOffset) : 0;
        uint64_t visualSlot = ds_lq_managed_array_object(visualSlots, 5);
        if (!visualSlot) return false;
        int32_t visualType = -1;
        int32_t visualDamage = 0;
        uint64_t visualSkill = ds_lq_read_ptr(
            visualSlot + kDSLienQuanVisualSkillSlotSkillOffset);
        int32_t visualSkillId = 0;
        if (!visualSkill ||
            !ds_lq_read(visualSlot + kDSLienQuanVisualSkillSlotTypeOffset,
                        &visualType, sizeof(visualType)) || visualType != 5 ||
            !ds_lq_read(visualSlot + kDSLienQuanVisualSkillSlotInfoDataOffset +
                            kDSLienQuanSkillStateDataDamageOffset,
                        &visualDamage, sizeof(visualDamage)) ||
            !ds_lq_read(visualSkill + kDSLienQuanVisualSkillIdOffset,
                        &visualSkillId, sizeof(visualSkillId)) ||
            !ds_lq_is_smite_id(visualSkillId) ||
            ds_lq_normalize_smite_id(visualSkillId) !=
                ds_lq_normalize_smite_id(skillId) ||
            visualDamage <= 0 || visualDamage > 1000000) return false;
        damage = MIN(damage, visualDamage);
        skillId = visualSkillId;
    }
    if (ds_lq_host_has_fenrir(hostActor)) {
        damage = (int32_t)MIN((int64_t)1000000,
                              (int64_t)damage * 13LL / 10LL);
    }
    out->skillId = skillId;
    out->damage = damage;
    return true;
}

static bool ds_lq_smite_target_still_valid(
    uint64_t actor, const DSLienQuanVInt3 &hostLocation, int32_t rawDamage,
    const DSLQSmiteDamagePenalty &penalty, bool objectivesOnly,
    DSLQSmiteTarget *out) {
    if (out) *out = {};
    DSLienQuanActorMeta meta = {};
    DSLienQuanVInt3 location = {};
    uint8_t recycled = 1;
    uint8_t destroyed = 1;
    uint32_t objectId = 0;
    uint64_t value = ds_lq_read_ptr(
        actor + kDSLienQuanActorRootValueComponentOffset);
    uint64_t gameObject = ds_lq_read_ptr(
        actor + kDSLienQuanActorRootGameObjectOffset);
    DSLQLQCrypticInt32 hpBefore = {};
    DSLQLQCrypticInt32 hpAfter = {};
    if (!value || !gameObject ||
        !ds_lq_read(value + kDSLienQuanCrypticHpOffset,
                    &hpBefore, sizeof(hpBefore)) ||
        !ds_lq_read(actor + kDSLienQuanActorRootMetaOffset,
                    &meta, sizeof(meta)) || meta.actorType != 1 ||
        !ds_lq_auto_smite_target_allowed(meta.configId, objectivesOnly) ||
        !ds_lq_read_actor_location(actor, &location) ||
        !ds_lq_read(actor + kDSLienQuanActorRootObjectIdOffset,
                    &objectId, sizeof(objectId)) || !objectId ||
        !ds_lq_read(actor + kDSLienQuanActorRootRecycledOffset,
                    &recycled, sizeof(recycled)) || recycled ||
        !ds_lq_read(gameObject + kDSLienQuanEngineGameObjectDestroyedOffset,
                    &destroyed, sizeof(destroyed)) || destroyed ||
        !ds_lq_read(value + kDSLienQuanCrypticHpOffset,
                    &hpAfter, sizeof(hpAfter)) ||
        memcmp(&hpBefore, &hpAfter, sizeof(hpBefore)) != 0) return false;
    int32_t hp = ds_lq_cryptic_int32_value(hpAfter);
    int32_t damage = ds_lq_effective_smite_damage(
        rawDamage, meta.configId, penalty);
    int64_t dx = (int64_t)location.x - hostLocation.x;
    int64_t dz = (int64_t)location.z - hostLocation.z;
    static const int64_t kSmiteRangeSquared = 6400LL * 6400LL;
    if (hp <= 0 || hp > damage || dx * dx + dz * dz > kSmiteRangeSquared)
        return false;
    if (out) *out = {actor, objectId, hp};
    return true;
}

static bool ds_lq_smite_pool_has_message(uint64_t pool,
                                         uint64_t targetClass) {
    uint64_t poolList = pool ? ds_lq_read_ptr(pool + 0x08) : 0;
    DSLQManagedListState state = {};
    if (!targetClass || !ds_lq_read_managed_list(poolList, &state) ||
        state.size <= 0) return false;
    uint64_t object = ds_lq_read_ptr(
        state.items + kDSLienQuanManagedArrayDataOffset +
        (uint64_t)(state.size - 1) * sizeof(uint64_t));
    return object && ds_lq_read_ptr(object) == targetClass;
}

static int32_t ds_lq_smite_static_class_id(void) {
    uint64_t methodInfo = ds_lq_read_ptr(ds_lq_addr(
        kDSLienQuanMsgUseSkillTargetPoolGetMethodInfoRva));
    uint64_t poolClass = methodInfo ? ds_lq_read_ptr(methodInfo + 0x20) : 0;
    uint64_t staticFields = poolClass ? ds_lq_read_ptr(
        poolClass + kDSLienQuanIl2CppStaticFieldsOffset) : 0;
    int32_t classId = 0;
    if (!staticFields ||
        !ds_lq_read(staticFields, &classId, sizeof(classId)) || classId <= 0)
        return 0;
    return classId;
}

// ClassObjPool<T>'s closed generic class stores T at RGCTX slot 4. Unlike the
// generic static CLASS_ID this is already usable before ClassObjPool<T>.Get()
// runs for the first time, which is exactly the state before the first manual
// smite cast.
static uint64_t ds_lq_pool_element_class(uint64_t pool) {
    uint64_t poolClass = pool ? ds_lq_read_ptr(pool) : 0;
    uint64_t rgctx = poolClass ? ds_lq_read_ptr(poolClass + 0xC0) : 0;
    return rgctx ? ds_lq_read_ptr(rgctx + 4 * sizeof(uint64_t)) : 0;
}

static uint64_t ds_lq_find_smite_message_pool(uint64_t targetClass,
                                               int32_t *classIdOut) {
    if (classIdOut) *classIdOut = 0;
    if (!targetClass) return 0;
    uint64_t repository = ds_lq_singleton_instance_from_methodinfo(
        kDSLienQuanObjectPoolRepositoryMethodInfoRva);
    uint64_t repositories = repository
        ? ds_lq_read_ptr(repository + 0x08) : 0;
    uint64_t repositoryCount = 0;
    if (!repositories ||
        !ds_lq_read(repositories + kDSLienQuanManagedArrayLengthOffset,
                    &repositoryCount, sizeof(repositoryCount)) ||
        !repositoryCount || repositoryCount > 8) return 0;
    int32_t targetClassId = ds_lq_smite_static_class_id();
    uint64_t emptyCandidate = 0;
    int32_t emptyCandidateClassId = 0;
    for (uint64_t repositoryIndex = 0;
         repositoryIndex < repositoryCount; repositoryIndex++) {
        uint64_t listView = ds_lq_managed_array_object(
            repositories, repositoryIndex);
        uint64_t wrappers = listView ? ds_lq_read_ptr(
            listView + kDSLienQuanListViewContextOffset) : 0;
        DSLQManagedListState wrapperList = {};
        if (!ds_lq_read_managed_list(wrappers, &wrapperList) ||
            wrapperList.size <= 0 || wrapperList.size > 4096) continue;
        for (int32_t i = 0; i < wrapperList.size; i++) {
            uint64_t wrapper = ds_lq_read_ptr(
                wrapperList.items + kDSLienQuanManagedArrayDataOffset +
                (uint64_t)i * sizeof(uint64_t));
            uint64_t pool = wrapper ? ds_lq_read_ptr(wrapper + 0x18) : 0;
            if (!pool) continue;
            int32_t wrapperClassId = 0;
            if (!ds_lq_read(wrapper + 0x08, &wrapperClassId,
                            sizeof(wrapperClassId)) || wrapperClassId <= 0)
                continue;
            if (ds_lq_pool_element_class(pool) == targetClass) {
                if (classIdOut) *classIdOut = wrapperClassId;
                return pool;
            }
            if (ds_lq_smite_pool_has_message(pool, targetClass)) {
                if (classIdOut) *classIdOut = wrapperClassId;
                return pool;
            }
            if (targetClassId && wrapperClassId == targetClassId &&
                !emptyCandidate) {
                emptyCandidate = pool;
                emptyCandidateClassId = wrapperClassId;
            }
        }
    }
    if (emptyCandidate && classIdOut)
        *classIdOut = emptyCandidateClassId;
    return emptyCandidate;
}

typedef struct {
    uint64_t pool;
    uint64_t message;
    uint64_t messageClass;
} DSLQSmiteMessageDonor;

static bool ds_lq_class_inherits_from(uint64_t klass, uint64_t parent) {
    for (int depth = 0; klass && depth < 24; depth++) {
        if (klass == parent) return true;
        klass = ds_lq_read_ptr(
            klass + kDSLienQuanIl2CppParentClassOffset);
    }
    return false;
}

static uint64_t ds_lq_pooled_object_base_class(uint64_t klass) {
    for (int depth = 0; klass && depth < 24; depth++) {
        uint64_t parent = ds_lq_read_ptr(
            klass + kDSLienQuanIl2CppParentClassOffset);
        if (!parent) return 0;
        uint64_t grandparent = ds_lq_read_ptr(
            parent + kDSLienQuanIl2CppParentClassOffset);
        if (!grandparent) return klass;
        klass = parent;
    }
    return 0;
}

static bool ds_lq_read_class_instance_size(uint64_t klass,
                                            uint32_t *sizeOut) {
    if (sizeOut) *sizeOut = 0;
    uint32_t size = 0;
    if (!klass || !sizeOut ||
        !ds_lq_read(klass + kDSLienQuanIl2CppClassInstanceSizeOffset,
                    &size, sizeof(size)) || size < 0x20 || size > 0x10000)
        return false;
    *sizeOut = size;
    return true;
}

// Before MsgRequestUseSkillTarget is used for the first time its pool can be
// valid but empty. Borrow any inactive PooledClassObjectBase allocation that
// is large enough, then retag it during the atomic dequeue/publish path. The
// normal frame release puts it into the target pool, so this is only needed
// once per match.
static bool ds_lq_find_smite_message_donor(
    uint64_t targetClass, uint64_t targetPool,
    DSLQSmiteMessageDonor *out) {
    if (out) *out = {};
    uint64_t pooledBase = ds_lq_pooled_object_base_class(targetClass);
    uint32_t targetSize = 0;
    if (!out || !pooledBase ||
        !ds_lq_read_class_instance_size(targetClass, &targetSize) ||
        targetSize < 0x5A) return false;

    uint64_t repository = ds_lq_singleton_instance_from_methodinfo(
        kDSLienQuanObjectPoolRepositoryMethodInfoRva);
    uint64_t repositories = repository ? ds_lq_read_ptr(
        repository + 0x08) : 0;
    uint64_t repositoryCount = 0;
    if (!repositories ||
        !ds_lq_read(repositories + kDSLienQuanManagedArrayLengthOffset,
                    &repositoryCount, sizeof(repositoryCount)) ||
        !repositoryCount || repositoryCount > 8) return false;

    uint32_t bestSize = UINT32_MAX;
    for (uint64_t repositoryIndex = 0;
         repositoryIndex < repositoryCount; repositoryIndex++) {
        uint64_t listView = ds_lq_managed_array_object(
            repositories, repositoryIndex);
        uint64_t wrappers = listView ? ds_lq_read_ptr(
            listView + kDSLienQuanListViewContextOffset) : 0;
        DSLQManagedListState wrapperList = {};
        if (!ds_lq_read_managed_list(wrappers, &wrapperList) ||
            wrapperList.size <= 0 || wrapperList.size > 4096) continue;
        for (int32_t i = 0; i < wrapperList.size; i++) {
            uint64_t wrapper = ds_lq_read_ptr(
                wrapperList.items + kDSLienQuanManagedArrayDataOffset +
                (uint64_t)i * sizeof(uint64_t));
            uint64_t pool = wrapper ? ds_lq_read_ptr(wrapper + 0x18) : 0;
            uint64_t poolList = pool && pool != targetPool
                ? ds_lq_read_ptr(pool + 0x08) : 0;
            DSLQManagedListState state = {};
            if (!ds_lq_read_managed_list(poolList, &state) || state.size <= 0)
                continue;
            uint64_t message = ds_lq_read_ptr(
                state.items + kDSLienQuanManagedArrayDataOffset +
                (uint64_t)(state.size - 1) * sizeof(uint64_t));
            uint64_t messageClass = message ? ds_lq_read_ptr(message) : 0;
            uint64_t elementClass = ds_lq_pool_element_class(pool);
            uint32_t messageSize = 0;
            uint32_t usingSeq = 1;
            uint64_t holderRef = 1;
            if (!messageClass || messageClass == targetClass ||
                !elementClass || elementClass != messageClass ||
                !ds_lq_class_inherits_from(messageClass, pooledBase) ||
                !ds_lq_read_class_instance_size(messageClass, &messageSize) ||
                messageSize < targetSize || messageSize >= bestSize ||
                !ds_lq_read(message + 0x08, &usingSeq, sizeof(usingSeq)) ||
                !ds_lq_read(message + 0x10, &holderRef, sizeof(holderRef)) ||
                usingSeq || holderRef) continue;
            bestSize = messageSize;
            *out = {pool, message, messageClass};
        }
    }
    return out->message != 0;
}

static uint64_t ds_lq_list_metadata(int32_t size, int32_t version) {
    return (uint64_t)(uint32_t)size |
           ((uint64_t)(uint32_t)version << 32);
}

static bool ds_lq_enqueue_smite_message(uint64_t framework,
                                        uint32_t playerId,
                                        uint32_t targetId,
                                        int32_t skillId) {
    uint64_t targetClass = ds_lq_read_ptr(
        ds_lq_addr(kDSLienQuanMsgUseSkillTargetTypeInfoRva));
    if (!targetClass || !playerId || !targetId ||
        !ds_lq_is_smite_id(skillId)) return false;
    uint64_t hostLogic = ds_lq_read_ptr(
        framework + kDSLienQuanKyriosHostLogicOffset);
    uint32_t livePlayerId = 0;
    if (!hostLogic ||
        !ds_lq_read(hostLogic + kDSLienQuanHostPlayerIdOffset,
                    &livePlayerId, sizeof(livePlayerId)) || !livePlayerId)
        return false;
    if (livePlayerId != playerId) return false;
    if (targetClass != g_dslqAutoSmiteTargetClass) {
        g_dslqAutoSmiteTargetClass = targetClass;
        g_dslqAutoSmitePool = 0;
        g_dslqAutoSmiteClassId = 0;
    }
    uint64_t targetPool = 0;
    uint64_t sourcePool = 0;
    uint64_t sourceList = 0;
    DSLQManagedListState sourceState = {};
    uint64_t sourceSlot = 0;
    uint64_t message = 0;
    bool convertedDonor = false;
    for (int attempt = 0; attempt < 2 && !targetPool; attempt++) {
        uint64_t candidatePool = g_dslqAutoSmitePool;
        int32_t candidateClassId = g_dslqAutoSmiteClassId;
        if (!candidatePool) {
            candidatePool = ds_lq_find_smite_message_pool(
                targetClass, &candidateClassId);
            if (!candidatePool) return false;
        }
        uint64_t candidateList = ds_lq_read_ptr(candidatePool + 0x08);
        DSLQManagedListState candidateState = {};
        if (ds_lq_read_managed_list(candidateList, &candidateState)) {
            targetPool = candidatePool;
            g_dslqAutoSmitePool = candidatePool;
            g_dslqAutoSmiteClassId = candidateClassId;
            if (candidateState.size <= 0) break;
            uint64_t candidateSlot = candidateState.items +
                kDSLienQuanManagedArrayDataOffset +
                (uint64_t)(candidateState.size - 1) * sizeof(uint64_t);
            uint64_t candidate = ds_lq_read_ptr(candidateSlot);
            if (candidate && ds_lq_read_ptr(candidate) == targetClass) {
                message = candidate;
                sourcePool = candidatePool;
                sourceList = candidateList;
                sourceState = candidateState;
                sourceSlot = candidateSlot;
                break;
            }
            targetPool = 0;
        }
        // ObjectPoolRepository replaces its per-message pools between
        // matches. Do not leave a detached or mismatched pool cached forever.
        g_dslqAutoSmitePool = 0;
        g_dslqAutoSmiteClassId = 0;
    }
    if (!targetPool) return false;

    uint64_t oldMessageClass = targetClass;
    if (!message) {
        DSLQSmiteMessageDonor donor = {};
        if (!ds_lq_find_smite_message_donor(targetClass, targetPool, &donor))
            return false;
        sourcePool = donor.pool;
        sourceList = ds_lq_read_ptr(sourcePool + 0x08);
        if (!ds_lq_read_managed_list(sourceList, &sourceState) ||
            sourceState.size <= 0) return false;
        sourceSlot = sourceState.items + kDSLienQuanManagedArrayDataOffset +
            (uint64_t)(sourceState.size - 1) * sizeof(uint64_t);
        message = ds_lq_read_ptr(sourceSlot);
        oldMessageClass = message ? ds_lq_read_ptr(message) : 0;
        if (message != donor.message || oldMessageClass != donor.messageClass)
            return false;
        convertedDonor = true;
    }

    uint64_t adapter = ds_lq_read_ptr(framework + 0x20);
    uint64_t pipe = adapter ? ds_lq_read_ptr(adapter + 0x10) : 0;
    uint64_t frame = pipe ? ds_lq_read_ptr(pipe + 0x08) : 0;
    uint64_t frameList = frame ? ds_lq_read_ptr(frame + 0x30) : 0;
    DSLQManagedListState frameState = {};
    if (!ds_lq_read_managed_list(frameList, &frameState) ||
        frameState.size < 0 || (uint64_t)frameState.size >= frameState.capacity)
        return false;

    uint32_t oldUsingSeq = 0;
    uint64_t oldHolderRef = 0;
    uint32_t oldReqSeq = 0;
    uint8_t oldPayload[0x42] = {};
    int32_t targetClassId = g_dslqAutoSmiteClassId;
    if (targetClassId <= 0 ||
        !ds_lq_read(message + 0x08, &oldUsingSeq, sizeof(oldUsingSeq)) ||
        !ds_lq_read(message + 0x10, &oldHolderRef, sizeof(oldHolderRef)) ||
        !ds_lq_read(targetPool + 0x10, &oldReqSeq, sizeof(oldReqSeq)) ||
        !ds_lq_read(message + 0x18, oldPayload, sizeof(oldPayload)) ||
        ds_lq_read_ptr(message) != oldMessageClass ||
        !ds_lq_managed_list_unchanged(sourceState) ||
        ds_lq_read_ptr(sourceSlot) != message ||
        !ds_lq_managed_list_unchanged(frameState) ||
        ds_lq_read_ptr(pipe + 0x08) != frame) return false;

    uint64_t holderRef = ds_lq_read_ptr(targetPool + 0x18);
    uint32_t nextSeq = oldReqSeq + 1;
    if (!nextSeq) nextSeq = 1;
    uint64_t oldSourceMetadata = ds_lq_list_metadata(
        sourceState.size, sourceState.version);
    uint64_t newSourceMetadata = ds_lq_list_metadata(
        sourceState.size - 1, sourceState.version + 1);
    bool sourceRemoved = ds_lq_write_verified(sourceList + 0x10,
                                              &newSourceMetadata,
                                              sizeof(newSourceMetadata));
    if (!sourceRemoved) {
        uint64_t observedMetadata = 0;
        if (!ds_lq_read(sourceList + 0x10, &observedMetadata,
                        sizeof(observedMetadata)) ||
            observedMetadata != newSourceMetadata) return false;
    }

    auto rollbackSource = [&]() {
        DSLQManagedListState current = {};
        if (!ds_lq_read_managed_list(sourceList, &current) ||
            current.items != sourceState.items ||
            current.size != sourceState.size - 1 ||
            current.version != sourceState.version + 1 ||
            ds_lq_read_ptr(sourceSlot) != message) return;
        ds_debug_write_bytes(g_dslqVmMap, message,
                             &oldMessageClass, sizeof(oldMessageClass));
        ds_debug_write_bytes(g_dslqVmMap, message + 0x18,
                             oldPayload, sizeof(oldPayload));
        ds_debug_write_bytes(g_dslqVmMap, message + 0x08,
                             &oldUsingSeq, sizeof(oldUsingSeq));
        ds_debug_write_bytes(g_dslqVmMap, message + 0x10,
                             &oldHolderRef, sizeof(oldHolderRef));
        ds_debug_write_bytes(g_dslqVmMap, targetPool + 0x10,
                             &oldReqSeq, sizeof(oldReqSeq));
        ds_debug_write_bytes(g_dslqVmMap, sourceList + 0x10,
                             &oldSourceMetadata, sizeof(oldSourceMetadata));
    };

    uint8_t payload[0x42] = {};
    memcpy(payload, oldPayload, 0x10);
    int32_t priority = 1;
    int32_t slotType = 5;
    memcpy(payload, &priority, sizeof(priority));
    memcpy(payload + 0x10, &targetClassId, sizeof(targetClassId));
    memcpy(payload + 0x14, &playerId, sizeof(playerId));
    memcpy(payload + 0x34, &targetId, sizeof(targetId));
    memcpy(payload + 0x38, &slotType, sizeof(slotType));
    memcpy(payload + 0x3C, &skillId, sizeof(skillId));
    bool objectReady = holderRef &&
        (!convertedDonor || ds_lq_write_verified(
            message, &targetClass, sizeof(targetClass))) &&
        ds_lq_write_verified(targetPool + 0x10,
                             &nextSeq, sizeof(nextSeq)) &&
        ds_lq_write_verified(message + 0x08, &nextSeq, sizeof(nextSeq)) &&
        ds_lq_write_verified(message + 0x10, &holderRef, sizeof(holderRef)) &&
        ds_lq_write_verified(message + 0x18, payload, sizeof(payload));
    if (!objectReady || !ds_lq_managed_list_unchanged(frameState) ||
        ds_lq_read_ptr(pipe + 0x08) != frame) {
        rollbackSource();
        return false;
    }

    uint64_t frameSlot = frameState.items +
        kDSLienQuanManagedArrayDataOffset +
        (uint64_t)frameState.size * sizeof(uint64_t);
    uint64_t newFrameMetadata = ds_lq_list_metadata(
        frameState.size + 1, frameState.version + 1);
    bool slotReady = ds_lq_write_verified(frameSlot, &message,
                                          sizeof(message));
    if (!slotReady) {
        uint64_t observedMessage = 0;
        slotReady = ds_lq_read(frameSlot, &observedMessage,
                               sizeof(observedMessage)) &&
                    observedMessage == message;
    }
    if (!slotReady) {
        rollbackSource();
        return false;
    }
    bool published = ds_lq_write_verified(frameList + 0x10,
                                          &newFrameMetadata,
                                          sizeof(newFrameMetadata));
    if (!published) {
        uint64_t observedMetadata = 0;
        bool metadataRead = ds_lq_read(frameList + 0x10,
                                      &observedMetadata,
                                      sizeof(observedMetadata));
        if (metadataRead && observedMetadata == newFrameMetadata) {
            published = true;
        } else if (metadataRead && observedMetadata ==
                   ds_lq_list_metadata(frameState.size,
                                       frameState.version)) {
            uint64_t zero = 0;
            ds_debug_write_bytes(g_dslqVmMap, frameSlot,
                                 &zero, sizeof(zero));
            rollbackSource();
            return false;
        } else {
            // The game advanced or swapped this list after our pointer write.
            // Do not restore either list into an unknown newer state.
            return true;
        }
    }
    uint64_t zero = 0;
    ds_debug_write_bytes(g_dslqVmMap, sourceSlot, &zero, sizeof(zero));
    return true;
}

static void ds_lq_auto_smite_tick(CFAbsoluteTime now, uint64_t framework,
                                  uint64_t hostActor,
                                  uint32_t hostPlayerId) {
    if (!g_dslqAutoSmiteLoadedDefaults) {
        g_dslqAutoSmiteLoadedDefaults = true;
        bool enabled = [NSUserDefaults.standardUserDefaults
            boolForKey:kDSHostedAutoSmiteEnabledKey];
        g_dslqAutoSmiteEnabled.store(enabled, std::memory_order_release);
        bool objectivesOnly = [NSUserDefaults.standardUserDefaults
            boolForKey:kDSHostedAutoSmiteObjectivesOnlyKey];
        g_dslqAutoSmiteObjectivesOnly.store(objectivesOnly,
                                             std::memory_order_release);
    }
    bool enabled = g_dslqAutoSmiteEnabled.load(std::memory_order_acquire);
    if (!enabled) {
        if (g_dslqAutoSmiteWasEnabled) {
            g_dslqAutoSmiteLastEnqueue = 0;
            g_dslqAutoSmitePool = 0;
            g_dslqAutoSmiteClassId = 0;
            g_dslqAutoSmiteHostActor = 0;
            g_dslqAutoSmiteHostPlayerId = 0;
            g_dslqSmiteCaesarPenaltyUntil = 0;
            g_dslqSmiteSlayerPenaltyUntil = 0;
            g_dslqSmitePenaltyNegativeUntil = 0;
        }
        g_dslqAutoSmiteWasEnabled = false;
        return;
    }
    g_dslqAutoSmiteWasEnabled = true;
    if (!framework || !hostActor || !hostPlayerId ||
        now - g_dslqAutoSmiteLastEnqueue < 0.30) return;

    if (hostActor != g_dslqAutoSmiteHostActor ||
        hostPlayerId != g_dslqAutoSmiteHostPlayerId) {
        g_dslqAutoSmiteHostActor = hostActor;
        g_dslqAutoSmiteHostPlayerId = hostPlayerId;
        g_dslqAutoSmitePool = 0;
        g_dslqAutoSmiteClassId = 0;
        g_dslqAutoSmiteLastEnqueue = 0;
        g_dslqSmiteCaesarPenaltyUntil = 0;
        g_dslqSmiteSlayerPenaltyUntil = 0;
        g_dslqSmitePenaltyNegativeUntil = 0;
    }

    // Resolve the specific pool once when the feature becomes active. This
    // keeps repository traversal out of the HP-threshold path.
    uint64_t targetClass = ds_lq_read_ptr(
        ds_lq_addr(kDSLienQuanMsgUseSkillTargetTypeInfoRva));
    if (targetClass && targetClass != g_dslqAutoSmiteTargetClass) {
        g_dslqAutoSmiteTargetClass = targetClass;
        g_dslqAutoSmitePool = 0;
        g_dslqAutoSmiteClassId = 0;
    }
    if (!targetClass) return;
    if (!g_dslqAutoSmitePool) {
        g_dslqAutoSmitePool = ds_lq_find_smite_message_pool(
            targetClass, &g_dslqAutoSmiteClassId);
    }

    DSLQSmiteState smite = {};
    DSLQSmiteDamagePenalty penalty = {};
    bool objectivesOnly = g_dslqAutoSmiteObjectivesOnly.load(
        std::memory_order_acquire);
    DSLienQuanVInt3 hostLocation = {};
    if (!ds_lq_read_smite_state(hostActor, false, &smite) ||
        !ds_lq_read_actor_location(hostActor, &hostLocation)) return;

    // Preload the penalty while an objective approaches the contest window,
    // even if the host is still far away. A negative result is refreshed at
    // 10 Hz; a positive result is cached for the buff's actual remaining time.
    // This keeps the buff walk off the critical tick when the host jumps in.
    bool hasRawCandidate = false;
    bool shouldPrefetchPenalty = false;
    uint8_t requiredPenaltyGroups = kDSLQSmitePenaltyGroupNone;
    os_unfair_lock_lock(&g_dslqMonsterLock);
    const DSLQMonsterReadSource &rawSource = g_dslqMonsterSource;
    if (rawSource.ready && rawSource.pid == (pid_t)g_dslqPid &&
        rawSource.vmMap == g_dslqVmMap &&
        rawSource.matchEpoch == g_dslqMatchEpoch) {
        int count = MIN(MAX(rawSource.count, 0), kDSLQMaxMonsters);
        for (int i = 0; i < count; i++) {
            const DSLQMonsterReadEntry &entry = rawSource.monsters[i];
            if (!ds_lq_auto_smite_target_allowed(entry.configId,
                                                  objectivesOnly)) continue;
            DSLQActorMotion motion = {};
            int32_t hp = 0;
            uint8_t recycled = 1;
            uint8_t destroyed = 1;
            if (!ds_lq_copy_pinned_span(entry.recycled, &recycled,
                                        sizeof(recycled)) || recycled ||
                !ds_lq_copy_pinned_span(entry.destroyed, &destroyed,
                                        sizeof(destroyed)) || destroyed ||
                !ds_lq_copy_coherent_monster_sample(entry, &motion, &hp) ||
                hp <= 0) continue;
            uint8_t penaltyGroup =
                ds_lq_smite_penalty_group(entry.configId);
            if (penaltyGroup != kDSLQSmitePenaltyGroupNone &&
                (int64_t)hp <= (int64_t)smite.damage * 2) {
                shouldPrefetchPenalty = true;
                requiredPenaltyGroups |= penaltyGroup;
            }
            if (hp > smite.damage) continue;
            int64_t dx = (int64_t)motion.location.x - hostLocation.x;
            int64_t dz = (int64_t)motion.location.z - hostLocation.z;
            if (dx * dx + dz * dz > 6400LL * 6400LL) continue;
            hasRawCandidate = true;
            requiredPenaltyGroups |= penaltyGroup;
        }
    }
    os_unfair_lock_unlock(&g_dslqMonsterLock);
    if ((!hasRawCandidate && !shouldPrefetchPenalty) ||
        !ds_lq_read_smite_damage_penalty(now, hostActor,
                                         requiredPenaltyGroups, &penalty))
        return;
    if (!hasRawCandidate) return;

    uint64_t selectedActor = 0;
    int32_t selectedHp = INT32_MAX;
    os_unfair_lock_lock(&g_dslqMonsterLock);
    const DSLQMonsterReadSource &source = g_dslqMonsterSource;
    if (source.ready && source.pid == (pid_t)g_dslqPid &&
        source.vmMap == g_dslqVmMap && source.matchEpoch == g_dslqMatchEpoch) {
        int count = MIN(MAX(source.count, 0), kDSLQMaxMonsters);
        for (int i = 0; i < count; i++) {
            const DSLQMonsterReadEntry &entry = source.monsters[i];
            if (!ds_lq_auto_smite_target_allowed(entry.configId,
                                                  objectivesOnly)) continue;
            int32_t effectiveDamage = ds_lq_effective_smite_damage(
                smite.damage, entry.configId, penalty);
            DSLQActorMotion motion = {};
            int32_t hp = 0;
            uint8_t recycled = 1;
            uint8_t destroyed = 1;
            if (!ds_lq_copy_pinned_span(entry.recycled, &recycled,
                                        sizeof(recycled)) || recycled ||
                !ds_lq_copy_pinned_span(entry.destroyed, &destroyed,
                                        sizeof(destroyed)) || destroyed ||
                !ds_lq_copy_coherent_monster_sample(entry, &motion, &hp) ||
                hp <= 0 || hp > effectiveDamage) continue;
            int64_t dx = (int64_t)motion.location.x - hostLocation.x;
            int64_t dz = (int64_t)motion.location.z - hostLocation.z;
            if (dx * dx + dz * dz > 6400LL * 6400LL) continue;
            if (hp < selectedHp) {
                selectedActor = entry.actor;
                selectedHp = hp;
            }
        }
    }
    os_unfair_lock_unlock(&g_dslqMonsterLock);
    if (!selectedActor) return;

    DSLQSmiteState confirmedSmite = {};
    DSLQSmiteDamagePenalty confirmedPenalty = {};
    DSLQSmiteTarget target = {};
    DSLienQuanVInt3 confirmedHostLocation = {};
    if (!ds_lq_read_smite_state(hostActor, true, &confirmedSmite) ||
        confirmedSmite.skillId != smite.skillId ||
        !ds_lq_read_smite_damage_penalty(now, hostActor,
                                         requiredPenaltyGroups,
                                         &confirmedPenalty) ||
        !ds_lq_read_actor_location(hostActor, &confirmedHostLocation) ||
        !ds_lq_smite_target_still_valid(selectedActor, confirmedHostLocation,
                                        confirmedSmite.damage,
                                        confirmedPenalty, objectivesOnly,
                                        &target)) return;
    if (ds_lq_enqueue_smite_message(framework, hostPlayerId,
                                    target.objectId,
                                    confirmedSmite.skillId)) {
        g_dslqAutoSmiteLastEnqueue = now;
    }
}

static void ds_lq_confirm_empty_monster_roster(uint64_t battle) {
    static const uint8_t kEmptyRosterConfirmationPasses = 5;
    if (g_dslqMonsterEmptyStablePasses < kEmptyRosterConfirmationPasses)
        g_dslqMonsterEmptyStablePasses++;
    if (g_dslqMonsterEmptyStablePasses < kEmptyRosterConfirmationPasses)
        return;

    DSLQMonsterReadSource old = {};
    os_unfair_lock_lock(&g_dslqMonsterLock);
    old = g_dslqMonsterSource;
    g_dslqMonsterSource = {};
    memset(g_dslqMonsterFrameStates, 0,
           sizeof(g_dslqMonsterFrameStates));
    os_unfair_lock_unlock(&g_dslqMonsterLock);
    ds_lq_release_monster_pins(old);

    g_dslqMonsterBattle = battle;
    g_dslqMonsterInstalledSignature = 0;
    g_dslqMonsterRosterCandidateSignature = 0;
    g_dslqMonsterRosterStablePasses = 0;
}

static void ds_lq_refresh_monsters(CFAbsoluteTime now, uint64_t manager,
                                   uint64_t battle, int32_t hostCamp) {
    if (!manager || !battle || hostCamp <= 0) return;
    if (g_dslqMonsterBattle != battle) {
        ds_lq_clear_monsters();
        g_dslqMonsterBattle = battle;
    }
    if (now < g_dslqNextMonsterRosterRefresh) return;
    g_dslqNextMonsterRosterRefresh = now + 0.10;

    uint64_t list = ds_lq_read_ptr(
        manager + kDSLienQuanGameActorMgrMonsterActorsOffset);
    int listCount = 0;
    uint64_t items = 0;
    if (!list || !ds_lq_read_list(list, &listCount, &items) ||
        listCount < 0 || listCount > 64 || !items) {
        g_dslqMonsterRosterCandidateSignature = 0;
        g_dslqMonsterRosterStablePasses = 0;
        g_dslqMonsterEmptyStablePasses = 0;
        return;
    }
    if (listCount == 0) {
        ds_lq_confirm_empty_monster_roster(battle);
        return;
    }

    uint8_t slots[64 * kDSLienQuanPoolObjHandleStride] = {};
    if (!ds_lq_read(items + kDSLienQuanArrayDataOffset, slots,
                    (size_t)listCount * kDSLienQuanPoolObjHandleStride)) {
        g_dslqMonsterRosterCandidateSignature = 0;
        g_dslqMonsterRosterStablePasses = 0;
        g_dslqMonsterEmptyStablePasses = 0;
        return;
    }
    uint64_t candidates[64] = {};
    int candidateCount = 0;
    for (int i = 0; i < listCount; i++) {
        const uint8_t *slot = slots +
            (size_t)i * kDSLienQuanPoolObjHandleStride;
        uint64_t direct = 0;
        uint64_t handle = 0;
        memcpy(&direct, slot, sizeof(direct));
        memcpy(&handle, slot + kDSLienQuanPoolObjHandleObjectOffset,
               sizeof(handle));
        uint64_t actor = ds_lq_valid(handle) && !(handle & 0x7ULL)
            ? handle : direct;
        if (!ds_lq_valid(actor) || (actor & 0x7ULL)) continue;
        bool duplicate = false;
        for (int j = 0; j < candidateCount; j++) {
            if (candidates[j] == actor) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) candidates[candidateCount++] = actor;
    }
    if (candidateCount <= 0) {
        g_dslqMonsterRosterCandidateSignature = 0;
        g_dslqMonsterRosterStablePasses = 0;
        g_dslqMonsterEmptyStablePasses = 0;
        return;
    }

    // Read metadata, HP owner and lifecycle owner in one candidate range. The
    // managed actor list changes asynchronously, so a valid ID/HP alone does
    // not mean that the actor is still active.
    static const size_t kMonsterRosterBlockSize =
        (size_t)(kDSLienQuanActorRootRecycledOffset + sizeof(uint8_t) -
                 kDSLienQuanActorRootMetaOffset);
    uint8_t fields[64][kMonsterRosterBlockSize] = {};
    DSDebugReadRange ranges[64] = {};
    for (int i = 0; i < candidateCount; i++) {
        ranges[i] = { candidates[i] + kDSLienQuanActorRootMetaOffset,
                      fields[i], sizeof(fields[i]), NO };
    }
    ds_debug_read_list(g_dslqVmMap, ranges, (size_t)candidateCount);

    DSLQMonsterReadEntry observed[kDSLQMaxMonsters] = {};
    uint64_t valueProperties[kDSLQMaxMonsters] = {};
    uint64_t gameObjects[kDSLQMaxMonsters] = {};
    int observedCount = 0;
    int validMetaCount = 0;
    for (int i = 0; i < candidateCount; i++) {
        // MonsterActors can mutate while a despawned slot is removed. One slot
        // may fail while the remaining entries are still coherent and usable.
        if (!ranges[i].success) continue;
        validMetaCount++;
        DSLienQuanActorMeta meta = {};
        uint64_t valueProperty = 0;
        uint64_t gameObject = 0;
        uint8_t recycled = 0;
        memcpy(&meta, fields[i], sizeof(meta));
        memcpy(&valueProperty,
               fields[i] + (kDSLienQuanActorRootValueComponentOffset -
                            kDSLienQuanActorRootMetaOffset),
               sizeof(valueProperty));
        memcpy(&gameObject,
               fields[i] + (kDSLienQuanActorRootGameObjectOffset -
                            kDSLienQuanActorRootMetaOffset),
               sizeof(gameObject));
        memcpy(&recycled,
               fields[i] + (kDSLienQuanActorRootRecycledOffset -
                            kDSLienQuanActorRootMetaOffset),
               sizeof(recycled));
        if (meta.actorType != 1 || meta.actorCamp == hostCamp ||
            !ds_lq_jungle_monster_allowed(meta.configId) || recycled ||
            !ds_lq_valid(gameObject) || (gameObject & 0x7ULL)) continue;
        if (observedCount >= kDSLQMaxMonsters) break;
        observed[observedCount].actor = candidates[i];
        observed[observedCount].configId = meta.configId;
        observed[observedCount].actorCamp = meta.actorCamp;
        valueProperties[observedCount] =
            ds_lq_valid(valueProperty) && !(valueProperty & 0x7ULL)
                ? valueProperty : 0;
        gameObjects[observedCount] = gameObject;
        observedCount++;
    }
    if (observedCount <= 0) {
        if (validMetaCount == candidateCount)
            ds_lq_confirm_empty_monster_roster(battle);
        else
            g_dslqMonsterEmptyStablePasses = 0;
        return;
    }
    g_dslqMonsterEmptyStablePasses = 0;

    uint64_t signature = ds_lq_monster_roster_signature(
        observed, valueProperties, gameObjects, observedCount);
    if (signature == g_dslqMonsterInstalledSignature) {
        g_dslqMonsterRosterCandidateSignature = 0;
        g_dslqMonsterRosterStablePasses = 0;
        return;
    }
    if (signature != g_dslqMonsterRosterCandidateSignature) {
        g_dslqMonsterRosterCandidateSignature = signature;
        g_dslqMonsterRosterStablePasses = 1;
        return;
    }
    if (++g_dslqMonsterRosterStablePasses < 2) return;

    DSLQMonsterReadSource next = {};
    next.pid = (pid_t)g_dslqPid;
    next.vmMap = g_dslqVmMap;
    next.mapperEpoch = ds_debug_shmem_epoch();
    next.matchEpoch = g_dslqMatchEpoch;
    next.battle = battle;
    if (!next.mapperEpoch) return;
    uint64_t publishedValueProperties[kDSLQMaxMonsters] = {};
    bool allMotionPinned = true;
    for (int i = 0; i < observedCount; i++) {
        DSLQMonsterReadEntry entry = {};
        entry.actor = observed[i].actor;
        entry.configId = observed[i].configId;
        entry.actorCamp = observed[i].actorCamp;
        bool pinned = ds_lq_pin_span(
            observed[i].actor + kDSLienQuanActorRootLocationOffset,
            sizeof(DSLQActorMotion), &entry.motion) &&
            entry.motion.mapperEpoch == next.mapperEpoch;
        if (!pinned) {
            ds_lq_unpin_span(entry.motion);
            allMotionPinned = false;
            break;
        }
        if (valueProperties[i] &&
            (!ds_lq_pin_span(
                 valueProperties[i] + kDSLienQuanCrypticHpOffset,
                 sizeof(DSLQLQCrypticInt32), &entry.health) ||
             entry.health.mapperEpoch != next.mapperEpoch)) {
            ds_lq_unpin_span(entry.health);
            entry.health = {};
        }
        if (entry.health.localFirst)
            publishedValueProperties[next.count] = valueProperties[i];
        // Visual position source: gameObject.m_Transform.position. A failed
        // pin is non-fatal — the sampler falls back to _location.
        uint64_t transform = ds_lq_read_ptr(
            gameObjects[i] + kDSLienQuanEngineGameObjectTransformOffset);
        if (ds_lq_valid(transform) && !(transform & 0x7ULL)) {
            if (!ds_lq_pin_span(
                     transform + kDSLienQuanEngineTransformPositionOffset,
                     sizeof(DSLienQuanVInt3), &entry.visualPos) ||
                entry.visualPos.mapperEpoch != next.mapperEpoch) {
                ds_lq_unpin_span(entry.visualPos);
                entry.visualPos = {};
            }
        }
        if (!ds_lq_pin_span(
                observed[i].actor + kDSLienQuanActorRootRecycledOffset,
                sizeof(uint8_t), &entry.recycled) ||
            entry.recycled.mapperEpoch != next.mapperEpoch ||
            !ds_lq_pin_span(
                gameObjects[i] + kDSLienQuanEngineGameObjectDestroyedOffset,
                sizeof(uint8_t), &entry.destroyed) ||
            entry.destroyed.mapperEpoch != next.mapperEpoch) {
            ds_lq_unpin_span(entry.recycled);
            ds_lq_unpin_span(entry.destroyed);
            ds_lq_unpin_span(entry.visualPos);
            ds_lq_unpin_span(entry.health);
            ds_lq_unpin_span(entry.motion);
            allMotionPinned = false;
            break;
        }
        next.monsters[next.count++] = entry;
    }
    if (!allMotionPinned || next.count != observedCount) {
        ds_lq_release_monster_pins(next);
        return;
    }
    next.ready = true;

    DSLQMonsterReadSource old = {};
    DSLQMonsterFrameState nextStates[kDSLQMaxMonsters] = {};
    os_unfair_lock_lock(&g_dslqMonsterLock);
    old = g_dslqMonsterSource;
    for (int i = 0; i < next.count; i++) {
        nextStates[i].actor = next.monsters[i].actor;
        nextStates[i].configId = next.monsters[i].configId;
        for (int j = 0; j < old.count; j++) {
            if (next.monsters[i].actor != old.monsters[j].actor ||
                next.monsters[i].configId != old.monsters[j].configId)
                continue;
            nextStates[i] = g_dslqMonsterFrameStates[j];
            break;
        }
    }
    g_dslqMonsterSource = next;
    memcpy(g_dslqMonsterFrameStates, nextStates, sizeof(nextStates));
    os_unfair_lock_unlock(&g_dslqMonsterLock);
    ds_lq_release_monster_pins(old);
    g_dslqMonsterInstalledSignature = ds_lq_monster_roster_signature(
        next.monsters, publishedValueProperties, gameObjects, next.count);
    g_dslqMonsterRosterCandidateSignature = 0;
    g_dslqMonsterRosterStablePasses = 0;
}

static int ds_lq_copy_projected_monsters(
    DSLQProjectedMonster out[kDSLQMaxMonsters], uint64_t *epochOut) {
    if (epochOut) *epochOut = 0;
    if (!out) return 0;
    memset(out, 0, sizeof(DSLQProjectedMonster) * kDSLQMaxMonsters);

    struct MonsterFrameSample {
        uint64_t actor;
        uint32_t configId;
        int32_t hp;
        bool hpSampleValid;
        bool ready;
        bool explicitlyHidden;
        float world[3];
    } samples[kDSLQMaxMonsters] = {};
    int sourceCount = 0;
    uint64_t monsterEpoch = 0;
    uint64_t monsterBattle = 0;
    uint64_t mapperEpoch = ds_debug_shmem_epoch();
    bool sourceWasPublished = false;
    bool anySpanFailure = false;
    os_unfair_lock_lock(&g_dslqMonsterLock);
    const DSLQMonsterReadSource &monsters = g_dslqMonsterSource;
    sourceWasPublished = monsters.ready;
    bool sourceOK = monsters.ready && monsters.pid == (pid_t)g_dslqPid &&
        monsters.vmMap == g_dslqVmMap &&
        monsters.mapperEpoch == mapperEpoch && monsters.matchEpoch != 0 &&
        monsters.battle != 0 && monsters.count > 0 &&
        monsters.count <= kDSLQMaxMonsters;
    if (sourceOK) {
        monsterEpoch = monsters.matchEpoch;
        monsterBattle = monsters.battle;
        sourceCount = monsters.count;
        for (int i = 0; i < monsters.count; i++) {
            const DSLQMonsterReadEntry &entry = monsters.monsters[i];
            DSLQMonsterFrameState &state = g_dslqMonsterFrameStates[i];
            MonsterFrameSample &sample = samples[i];
            sample.actor = entry.actor;
            sample.configId = entry.configId;
            if (state.actor != entry.actor ||
                state.configId != entry.configId) {
                state = {};
                state.actor = entry.actor;
                state.configId = entry.configId;
            }
            uint8_t recycled = 0;
            uint8_t destroyed = 0;
            if (!ds_lq_copy_pinned_span(entry.recycled, &recycled,
                                        sizeof(recycled)) ||
                !ds_lq_copy_pinned_span(entry.destroyed, &destroyed,
                                        sizeof(destroyed))) {
                os_unfair_lock_unlock(&g_dslqMonsterLock);
                return -1;
            }
            // LEngineGameObject.m_Active is a presentation state and may
            // briefly toggle during view/LOD transitions while the logical
            // monster is still alive. Only permanent lifecycle fields may
            // invalidate the held HP and motion sample.
            if (recycled || destroyed) {
                state = {};
                state.actor = entry.actor;
                state.configId = entry.configId;
                sample.explicitlyHidden = true;
                continue;
            }
            DSLQActorMotion motion = {};
            int32_t hp = 0;
            bool hasHealthSource = entry.health.localFirst != 0;
            // HP updates must not freeze position tracking: when the
            // hp-coupled sample loses coherence (combat write mid-read),
            // fall back to a motion-only coherent sample so the bar keeps
            // following the monster. hpSampleValid stays false on such
            // frames, so the dead-monster gate below only ever runs on a
            // freshly sampled HP value.
            bool hpSampled = hasHealthSource &&
                ds_lq_copy_coherent_monster_sample(entry, &motion, &hp);
            bool sampled = hpSampled ||
                ds_lq_copy_coherent_monster_motion(entry, &motion);
            bool hpSampleValid = hpSampled;
            // Dead monster actors are commonly moved back to world origin.
            // Never feed that teardown position into the persistent smoother,
            // otherwise their HP label briefly travels through screen center.
            if (hpSampleValid && hp < 1) {
                state.hp = 0;
                state.hasHealth = false;
                memset(state.world, 0, sizeof(state.world));
                memset(state.pendingWorld, 0, sizeof(state.pendingWorld));
                state.pendingSamples = 0;
                state.hasMotion = false;
                sample.explicitlyHidden = true;
                continue;
            }
            if (hpSampleValid) {
                state.hp = hp;
                state.hasHealth = true;
            }
            if (sampled) {
                float fresh[3] = {};
                ds_lq_location_with_forward(motion.location, motion.forward,
                                            true, fresh);
                // LActorRoot._location is the battle-logic position: for AI
                // monsters it snaps on logic events (aggro, leash, return to
                // camp) while the model keeps walking, so a bar driven by
                // _location blinks at spots the monster already left. ESP.h
                // used ActorLinker_getPosition() (the visual position) for
                // exactly this reason; the read-only equivalent is the pinned
                // LEngineTransform.position. Fall back to _location when the
                // transform sample is missing or torn.
                if (entry.visualPos.localFirst) {
                    DSLienQuanVInt3 visual = {};
                    DSLienQuanVInt3 confirm = {};
                    if (ds_lq_copy_pinned_span(entry.visualPos, &visual,
                                               sizeof(visual)) &&
                        ds_lq_copy_pinned_span(entry.visualPos, &confirm,
                                               sizeof(confirm)) &&
                        memcmp(&visual, &confirm, sizeof(visual)) == 0 &&
                        ds_lq_location_valid(&visual)) {
                        fresh[0] = (float)visual.x * 0.001f;
                        fresh[1] = (float)visual.y * 0.001f;
                        fresh[2] = (float)visual.z * 0.001f;
                    }
                }
                if (!state.hasMotion) {
                    float dx = fresh[0] - state.pendingWorld[0];
                    float dy = fresh[1] - state.pendingWorld[1];
                    float dz = fresh[2] - state.pendingWorld[2];
                    bool sameCandidate = state.pendingSamples > 0 &&
                        dx * dx + dy * dy + dz * dz <= 1.0f;
                    if (!sameCandidate) {
                        memcpy(state.pendingWorld, fresh, sizeof(fresh));
                        state.pendingSamples = 1;
                    } else if (state.pendingSamples < 3) {
                        state.pendingSamples++;
                    }
                    if (state.pendingSamples >= 3) {
                        memcpy(state.world, fresh, sizeof(fresh));
                        state.pendingSamples = 0;
                        state.hasMotion = true;
                    }
                } else {
                    float dx = fresh[0] - state.world[0];
                    float dy = fresh[1] - state.world[1];
                    float dz = fresh[2] - state.world[2];
                    bool jumped = dx * dx + dy * dy + dz * dz > 16.0f;
                    if (jumped) {
                        float candidateDx = fresh[0] - state.pendingWorld[0];
                        float candidateDy = fresh[1] - state.pendingWorld[1];
                        float candidateDz = fresh[2] - state.pendingWorld[2];
                        bool sameCandidate = state.pendingSamples > 0 &&
                            candidateDx * candidateDx +
                            candidateDy * candidateDy +
                            candidateDz * candidateDz <= 1.0f;
                        if (!sameCandidate) {
                            memcpy(state.pendingWorld, fresh, sizeof(fresh));
                            state.pendingSamples = 1;
                        } else if (state.pendingSamples < 3) {
                            state.pendingSamples++;
                        }
                        if (state.pendingSamples >= 3) {
                            memcpy(state.world, fresh, sizeof(fresh));
                            state.pendingSamples = 0;
                        }
                    } else {
                        state.pendingSamples = 0;
                        for (int axis = 0; axis < 3; axis++) {
                            state.world[axis] +=
                                (fresh[axis] - state.world[axis]) * 0.2f;
                        }
                    }
                }
            }
            if (!state.hasMotion) {
                anySpanFailure = true;
                continue;
            }
            sample.hp = state.hp;
            sample.hpSampleValid = state.hasHealth;
            sample.ready = true;
            memcpy(sample.world, state.world, sizeof(sample.world));
        }
    }
    os_unfair_lock_unlock(&g_dslqMonsterLock);
    if (!sourceOK) return sourceWasPublished ? -1 : 0;
    if (anySpanFailure) return -1;

    float viewProjection[16] = {};
    DSLQMinimapGeometry minimap = {};
    int32_t hostCamp = 0;
    float viewport[4] = {};
    bool viewportValid = false;
    bool projectionOK = g_dslqProjectionFrameCache.valid &&
        g_dslqProjectionFrameCache.mapperEpoch == mapperEpoch &&
        g_dslqProjectionFrameCache.matchEpoch == monsterEpoch &&
        g_dslqProjectionFrameCache.battle == monsterBattle;
    if (projectionOK) {
        memcpy(viewProjection,
               g_dslqProjectionFrameCache.viewProjection,
               sizeof(viewProjection));
        minimap = g_dslqProjectionFrameCache.minimap;
        hostCamp = g_dslqProjectionFrameCache.hostCamp;
        viewportValid = g_dslqProjectionFrameCache.viewportValid;
        memcpy(viewport, g_dslqProjectionFrameCache.viewport,
               sizeof(viewport));
    } else {
        float matrices[32] = {};
        bool cameraOK = false;
        os_unfair_lock_lock(&g_dslqLiveSourceLock);
        const DSLQLiveRenderSource &source = g_dslqLiveSource;
        if (source.ready && source.matchEpoch == monsterEpoch &&
            source.battle == monsterBattle && source.camera.localFirst) {
            cameraOK = ds_lq_copy_coherent_camera(source.camera, matrices);
            minimap = source.minimap;
            hostCamp = source.hostCamp;
            viewportValid = source.viewportValid;
            memcpy(viewport, source.viewport, sizeof(viewport));
        }
        os_unfair_lock_unlock(&g_dslqLiveSourceLock);
        if (!cameraOK || hostCamp <= 0 ||
            ds_lq_matrix_nonzero_count(matrices) < 4 ||
            ds_lq_matrix_nonzero_count(matrices + 16) < 4) return -1;
        ds_lq_multiply_matrices(matrices, matrices + 16, viewProjection);
        projectionOK = true;
    }
    if (!projectionOK || hostCamp <= 0) return -1;
    for (int i = 0; i < sourceCount; i++) {
        const MonsterFrameSample &sample = samples[i];
        DSLQProjectedMonster &projected = out[i];
        projected.actor = sample.actor;
        projected.configId = sample.configId;
        if (!sample.ready || sample.explicitlyHidden) continue;
        projected.hp = sample.hp;
        projected.hpSampleValid = sample.hpSampleValid;
        projected.minimapValid = ds_lq_minimap_point(
            minimap, sample.world[0], sample.world[2], hostCamp,
            &projected.minimapWidthPx, &projected.minimapHeightPx,
            &projected.minimapX, &projected.minimapY);
        projected.minimapCenterXPx = minimap.mmPos[0];
        projected.minimapCenterYPx = minimap.mmPos[1];
        projected.minimapScreenWidthPx = minimap.screenSize[0];
        projected.minimapScreenHeightPx = minimap.screenSize[1];
        projected.minimapAnchorXPx = minimap.mmAnchorPos[0];
        projected.minimapAnchorYPx = minimap.mmAnchorPos[1];
        projected.minimapStorePosMode = minimap.storePosMode;
        memcpy(projected.minimapFormCameraViewport,
               minimap.formCameraViewport,
               sizeof(projected.minimapFormCameraViewport));
        projected.minimapRoomType = minimap.roomType;
        bool elevated = sample.configId == 7010 || sample.configId == 7011 ||
            sample.configId == 49 || sample.configId == 547010 ||
            sample.configId == 547011 || sample.configId == 7012 ||
            sample.configId == 70093 || sample.configId == 123 ||
            sample.configId == 124 || sample.configId == 70092 ||
            sample.configId == 7024 || sample.configId == 7009;
        float u = 0.0f;
        float v = 0.0f;
        if (!ds_lq_project_combined(
                viewProjection, sample.world[0],
                sample.world[1] + (elevated ? 1.0f : 0.0f),
                sample.world[2], &u, &v)) continue;
        projected.u = viewportValid ? viewport[0] + u * viewport[2] : u;
        projected.v = viewportValid ? viewport[1] + v * viewport[3] : v;
        projected.visible = true;
    }
    if (epochOut) *epochOut = monsterEpoch;
    return sourceCount;
}

// Main-thread display path: sample the pinned position/camera spans, apply the
// ESP.h smoothing rule, then project. No target-memory lookup occurs here.
static int ds_lq_copy_projected_heroes(DSLQProjectedHero out[5],
                                       uint64_t *epochOut) {
    g_dslqProjectionFrameCache.valid = false;
    if (epochOut) *epochOut = 0;
    if (!out) return 0;
    memset(out, 0, sizeof(DSLQProjectedHero) * kDSLQMaxEnemies);

    uint64_t mapperEpoch = ds_debug_shmem_epoch();
    DSLienQuanVInt3 positions[5] = {};
    DSLQActorMotion motions[5] = {};
    float worldPositions[5][3] = {};
    bool positionReadOK[5] = {};
    bool motionReadOK[5] = {};
    bool locationValid[5] = {};
    bool dead[5] = {};
    bool sightSampleValid[5] = {};
    bool sightVisible[5] = {};
    float matrices[32] = {};
    float viewport[4] = {};
    bool viewportOK = false;
    int enemyCount = 0;
    uint64_t renderEpoch = 0;
    uint64_t renderBattle = 0;
    bool sourceOK = false;
    bool sourceWasPublished = false;
    bool cameraReadOK = false;
    DSLQMinimapGeometry minimap = {};
    int32_t hostCamp = 0;

    // This lock is a mapping-lifetime guard, not a game-memory lock. Worker
    // flush/replacement waits until these small local copies are complete.
    os_unfair_lock_lock(&g_dslqLiveSourceLock);
    const DSLQLiveRenderSource &source = g_dslqLiveSource;
    sourceWasPublished = source.ready;
    sourceOK = source.ready && source.mapperEpoch == mapperEpoch &&
               source.pid > 0 && source.vmMap != 0 &&
               source.matchEpoch != 0 && source.battle != 0 &&
               source.enemyCount > 0 &&
               source.enemyCount <= kDSLQMaxEnemies;
    if (sourceOK) {
        enemyCount = source.enemyCount;
        renderEpoch = source.matchEpoch;
        renderBattle = source.battle;
        viewportOK = source.viewportValid;
        memcpy(viewport, source.viewport, sizeof(viewport));
        minimap = source.minimap;
        hostCamp = source.hostCamp;
        for (int i = 0; i < enemyCount; i++) {
            out[i].configId = source.enemies[i].configId;
            out[i].playerId = source.enemies[i].playerId;
            out[i].actor = source.enemies[i].actor;
            out[i].visible = false;
            motionReadOK[i] = ds_lq_copy_coherent_motion(
                source.enemies[i].motion, &motions[i]);
            DSLQLQCrypticInt32 rawHp = {};
            out[i].hpSampleValid = source.enemies[i].health.localFirst &&
                ds_lq_copy_pinned_span(source.enemies[i].health, &rawHp,
                                       sizeof(rawHp));
            if (out[i].hpSampleValid)
                out[i].hp = ds_lq_cryptic_int32_value(rawHp);
            DSLQLQCrypticInt32 rawUltimate = {};
            out[i].ultimateCooldownValid =
                source.enemies[i].ultimateCooldown.localFirst &&
                ds_lq_copy_pinned_span(
                    source.enemies[i].ultimateCooldown, &rawUltimate,
                    sizeof(rawUltimate));
            if (out[i].ultimateCooldownValid) {
                int32_t milliseconds = MAX(
                    ds_lq_cryptic_int32_value(rawUltimate), 0);
                out[i].ultimateCooldown = (milliseconds + 999) / 1000;
            }
            int32_t behavior = 0;
            bool behaviorValid = source.enemies[i].behavior.localFirst &&
                ds_lq_copy_pinned_span(source.enemies[i].behavior, &behavior,
                                       sizeof(behavior));
            dead[i] = behaviorValid &&
                      (behavior == 1 || behavior == 27);
            if (source.enemies[i].sight.localFirst) {
                uint8_t visible = 0;
                sightSampleValid[i] = ds_lq_copy_pinned_span(
                    source.enemies[i].sight, &visible,
                    sizeof(visible));
                sightVisible[i] = visible != 0;
            }
        }
        cameraReadOK = source.nativeCamera != 0 &&
            source.camera.remoteAddress == source.nativeCamera +
                kDSLienQuanNativeCameraViewMatrixOffset &&
            ds_lq_copy_coherent_camera(source.camera, matrices);
    }
    os_unfair_lock_unlock(&g_dslqLiveSourceLock);

    if (!sourceOK) {
        if (sourceWasPublished) {
            uint32_t failures = g_dslqStaleSourceFailureStreak.fetch_add(
                1, std::memory_order_acq_rel) + 1;
            if (failures >= 3) {
                g_dslqRecoveryFlags.fetch_or(kDSLQRecoverStaleSource,
                                             std::memory_order_release);
            }
            // A published source can be briefly stale while the worker swaps
            // its mapper or refreshes the roster. Keep the last complete
            // render batch instead of clearing every icon for one callback.
            return -1;
        }
        g_dslqStaleSourceFailureStreak.store(0, std::memory_order_release);
        return 0;
    }
    g_dslqStaleSourceFailureStreak.store(0, std::memory_order_release);
    if (epochOut) *epochOut = renderEpoch;
    bool anySpanFailure = false;
    for (int i = 0; i < enemyCount; i++) {
        if (dead[i]) {
            positionReadOK[i] = true;
            locationValid[i] = true;
            continue;
        }
        bool currentLocationValid = false;
        if (motionReadOK[i]) {
            positions[i] = motions[i].location;
            currentLocationValid = ds_lq_location_valid(&positions[i]);
            if (currentLocationValid) {
                ds_lq_location_with_forward(
                    positions[i], motions[i].forward, true,
                    worldPositions[i]);
                positionReadOK[i] = ds_lq_lerp_position(
                    renderEpoch, out[i].actor, out[i].playerId,
                    worldPositions[i]);
                locationValid[i] = positionReadOK[i];
            }
        }
        if (!currentLocationValid &&
            ds_lq_previous_lerp_position(renderEpoch, out[i].actor,
                                         out[i].playerId, worldPositions[i])) {
            // Hold the last valid actor sample for one bad/torn read. The
            // camera is still sampled for this callback, so the icon remains
            // in the correct screen space without a visibility blink.
            positionReadOK[i] = true;
            locationValid[i] = true;
        }
        if (!positionReadOK[i]) {
            anySpanFailure = true;
            continue;
        }
    }
    if (anySpanFailure) {
        uint32_t failures = g_dslqLocationSampleFailureStreak.fetch_add(
            1, std::memory_order_acq_rel) + 1;
        if (failures >= 3) {
            g_dslqRecoveryFlags.fetch_or(kDSLQRecoverLocations,
                                         std::memory_order_release);
        }
        // PUBG publishes a complete per-frame batch. Do not partially apply
        // an LQ batch when an actor has neither a fresh nor a held sample.
        return -1;
    }
    g_dslqLocationSampleFailureStreak.store(0, std::memory_order_release);
    if (!cameraReadOK || ds_lq_matrix_nonzero_count(matrices) < 4 ||
        ds_lq_matrix_nonzero_count(matrices + 16) < 4) {
        uint32_t failures = g_dslqCameraSampleFailureStreak.fetch_add(
            1, std::memory_order_acq_rel) + 1;
        if (failures >= 3) {
            g_dslqRecoveryFlags.fetch_or(kDSLQRecoverCamera,
                                         std::memory_order_release);
        }
        // Do not publish an empty projection on a transient camera failure;
        // the renderer keeps the last valid icon frames for this callback.
        return -1;
    }
    g_dslqCameraSampleFailureStreak.store(0, std::memory_order_release);


    float viewProjection[16] = {};
    ds_lq_multiply_matrices(matrices, matrices + 16, viewProjection);
    g_dslqProjectionFrameCache.mapperEpoch = mapperEpoch;
    g_dslqProjectionFrameCache.matchEpoch = renderEpoch;
    g_dslqProjectionFrameCache.battle = renderBattle;
    memcpy(g_dslqProjectionFrameCache.viewProjection, viewProjection,
           sizeof(viewProjection));
    memcpy(g_dslqProjectionFrameCache.viewport, viewport,
           sizeof(viewport));
    g_dslqProjectionFrameCache.viewportValid = viewportOK;
    g_dslqProjectionFrameCache.minimap = minimap;
    g_dslqProjectionFrameCache.hostCamp = hostCamp;
    g_dslqProjectionFrameCache.valid = true;
    for (int i = 0; i < enemyCount; i++) {
        if (dead[i]) continue;
        if (!positionReadOK[i] || !locationValid[i]) continue;
        out[i].minimapValid = ds_lq_minimap_point(
            minimap, worldPositions[i][0], worldPositions[i][2], hostCamp,
            &out[i].minimapWidthPx, &out[i].minimapHeightPx,
            &out[i].minimapX, &out[i].minimapY);
        out[i].minimapCenterXPx = minimap.mmPos[0];
        out[i].minimapCenterYPx = minimap.mmPos[1];
        out[i].minimapScreenWidthPx = minimap.screenSize[0];
        out[i].minimapScreenHeightPx = minimap.screenSize[1];
        out[i].minimapAnchorXPx = minimap.mmAnchorPos[0];
        out[i].minimapAnchorYPx = minimap.mmAnchorPos[1];
        out[i].minimapStorePosMode = minimap.storePosMode;
        memcpy(out[i].minimapFormCameraViewport,
               minimap.formCameraViewport,
               sizeof(out[i].minimapFormCameraViewport));
        out[i].minimapRoomType = minimap.roomType;
        if (sightSampleValid[i] && sightVisible[i]) {
            out[i].minimapValid = false;
            continue;
        }
        float u = 0.0f;
        float v = 0.0f;
        if (!ds_lq_project_combined(
                viewProjection,
                worldPositions[i][0], worldPositions[i][1] + 0.90f,
                worldPositions[i][2], &u, &v)) {
            continue;
        }
        out[i].u = viewportOK ? viewport[0] + u * viewport[2] : u;
        out[i].v = viewportOK ? viewport[1] + v * viewport[3] : v;
        out[i].visible = true;
    }
    return enemyCount;
}

static void ds_lq_tick(void) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    bool runFallbackScan = now >= g_dslqNextFallbackScan;
    bool attached = ds_lq_attach();
    if (!attached) {
        return;
    }
    uint64_t framework = 0;
    uint64_t actorManager = 0;
    uint64_t logicCore = 0;
    uint64_t desk = 0;
    uint64_t battle = 0;
    uint64_t manager = 0;
    uint64_t heroList = 0;
    int heroCount = -1;
    uint64_t heroItems = 0;
    bool usingGraphCache = false;
    bool heroListOK = false;
    if (g_dslqCachedManager && g_dslqCachedListLayoutKnown &&
        g_dslqCachedHeroList && g_dslqCachedHeroItems &&
        g_dslqCachedHeroCount > 0 &&
        g_dslqCachedHeroCount <= kDSLQMaxHeroes) {
        battle = g_dslqCachedBattle;
        manager = g_dslqCachedManager;
        heroList = g_dslqCachedHeroList;
        heroItems = g_dslqCachedHeroItems;
        heroCount = g_dslqCachedHeroCount;
        heroListOK = true;
        usingGraphCache = true;
    }
    if (heroListOK && usingGraphCache && !g_dslqRosterLocked) {
        // Distinct 10 Hz observations prevent worker callbacks from
        // declaring the very first partially-populated list stable.
        if (now < g_dslqNextRosterRefresh) return;
        g_dslqNextRosterRefresh = now + 0.10;
        int observedCount = -1;
        uint64_t observedItems = 0;
        if (!ds_lq_read_cached_list(
                heroList, g_dslqCachedListItemsOffset,
                g_dslqCachedListSizeOffset, &observedCount,
                &observedItems) ||
            observedCount <= 0 || observedCount > kDSLQMaxHeroes ||
            !observedItems) {
            g_dslqRosterCandidateSignature = 0;
            g_dslqRosterStablePasses = 0;
            g_dslqRosterStableSince = 0;
            if (++g_dslqGraphMisses >= 4)
                ds_lq_reset_match_mapping();
            return;
        }
        g_dslqGraphMisses = 0;
        if (observedCount != heroCount || observedItems != heroItems) {
            heroCount = observedCount;
            heroItems = observedItems;
            g_dslqCachedHeroCount = observedCount;
            g_dslqCachedHeroItems = observedItems;
            g_dslqCachedRootCount = 0;
            memset(g_dslqCachedRootPtrs, 0,
                   sizeof(g_dslqCachedRootPtrs));
            g_dslqRosterCandidateSignature = 0;
            g_dslqRosterStablePasses = 0;
            g_dslqRosterStableSince = 0;
        }
    }
    if (heroListOK && usingGraphCache && g_dslqRosterLocked &&
        now >= g_dslqNextRosterRefresh) {
        g_dslqNextRosterRefresh = now + 0.50;
        int observedCount = -1;
        uint64_t observedItems = 0;
        bool identityHeaderOK = ds_lq_read_cached_list(
            heroList, g_dslqCachedListItemsOffset,
            g_dslqCachedListSizeOffset, &observedCount, &observedItems);
        bool rosterEnded = identityHeaderOK && observedCount == 0;
        bool identitySampleComplete = identityHeaderOK &&
                     observedCount > 0 &&
                     observedCount <= kDSLQMaxHeroes && observedItems != 0;
        bool reusedActorChanged = false;
        bool identityOK = identitySampleComplete &&
                     observedCount == g_dslqCachedHeroCount &&
                     observedItems == g_dslqCachedHeroItems &&
                     observedCount == g_dslqCachedRootCount;
        if (identityOK) {
            uint8_t slots[kDSLQMaxHeroes *
                          kDSLienQuanHeroElementStride] = {};
            identityOK = ds_lq_read(
                observedItems + kDSLienQuanArrayDataOffset, slots,
                (size_t)observedCount * kDSLienQuanHeroElementStride);
            uint64_t observedActors[kDSLQMaxHeroes] = {};
            for (int i = 0; identityOK && i < observedCount; i++) {
                uint64_t actor = 0;
                memcpy(&actor,
                       slots + (size_t)i * kDSLienQuanHeroElementStride +
                           kDSLienQuanHeroObjectOffset,
                       sizeof(actor));
                identityOK = actor != 0;
                observedActors[i] = actor;
            }
            // List order is not identity. Unity can compact/reorder the
            // managed array while the same actors remain alive. Match both
            // the pointer and stable actor metadata because Unity may reuse
            // every allocation at the same address in the next match.
            for (int i = 0; identityOK && i < g_dslqCachedRootCount; i++) {
                int found = -1;
                for (int j = 0; j < observedCount; j++) {
                    if (observedActors[j] == g_dslqCachedRootPtrs[i]) {
                        found = j;
                        break;
                    }
                }
                if (found < 0) {
                    identityOK = false;
                    break;
                }
                DSLienQuanActorMeta observedMeta = {};
                if (!ds_lq_read(observedActors[found] +
                                    kDSLienQuanActorRootMetaOffset,
                                &observedMeta, sizeof(observedMeta)) ||
                    observedMeta.configId !=
                        g_dslqCachedRootConfigIds[i] ||
                    observedMeta.playerId !=
                        g_dslqCachedRootPlayerIds[i] ||
                    observedMeta.actorCamp != g_dslqCachedRootCamps[i]) {
                    reusedActorChanged = true;
                    identityOK = false;
                }
            }
        }
        if (identityOK) {
            g_dslqRosterIdentityMisses = 0;
            g_dslqRosterTornSamples = 0;
        } else if (rosterEnded) {
            g_dslqRosterTornSamples = 0;
            if (++g_dslqRosterIdentityMisses >= 2) {
                ds_lq_reset_match_mapping();
                return;
            }
        } else if (!identitySampleComplete) {
            // A failed/torn validation read is not a topology change; the
            // last publication keeps rendering while the storm passes. A
            // roster that stays torn for seconds belongs to a replaced list,
            // so unlock it and let the refresh path re-validate instead of
            // trusting the stale list forever. The live source and mapper
            // stay up: no blank frame, no region rebuild.
            g_dslqRosterIdentityMisses = 0;
            if (++g_dslqRosterTornSamples >= 8) {
                g_dslqRosterTornSamples = 0;
                g_dslqRosterLocked = false;
                g_dslqRosterCandidateSignature = 0;
                g_dslqRosterStablePasses = 0;
                g_dslqRosterStableSince = 0;
                g_dslqNextRosterRefresh = 0;
            }
        } else if (++g_dslqRosterIdentityMisses >= 2) {
            if (reusedActorChanged) {
                ds_lq_reset_match_mapping();
                return;
            }
            g_dslqRosterIdentityMisses = 0;
            g_dslqRosterTornSamples = 0;
            g_dslqRosterLocked = false;
            g_dslqRosterCandidateSignature = 0;
            g_dslqRosterStablePasses = 0;
            g_dslqRosterStableSince = 0;
            g_dslqCachedRootCount = 0;
            memset(g_dslqCachedRootPtrs, 0,
                   sizeof(g_dslqCachedRootPtrs));
            // Keep rendering the last complete publication while the new
            // roster is validated and pinned. Replacement is atomic.
            g_dslqNextRosterRefresh = 0;
            return;
        }
    }
    if (!heroListOK) {
        logicCore = g_dslqCachedLogicCore;
        if (!logicCore) {
            logicCore = ds_lq_logic_core_instance(NULL);
            if (logicCore) g_dslqCachedLogicCore = logicCore;
        }
        desk = logicCore
            ? ds_lq_read_ptr(logicCore +
                             kDSLienQuanLogicCoreCurrentDeskOffset)
            : 0;
        heroListOK = ds_lq_try_desk(desk, &battle, &manager, &heroList,
                                    &heroItems, &heroCount);
        if (!heroListOK && runFallbackScan) {
            g_dslqNextFallbackScan = now + 0.75;
            framework = g_dslqCachedFramework;
            if (!framework) {
                framework = ds_lq_mono_singleton_instance(
                    kDSLienQuanKyriosFrameworkTypeInfoRva);
                g_dslqCachedFramework = framework;
            }
            actorManager = framework
                ? ds_lq_read_ptr(
                    framework + kDSLienQuanKyriosActorManagerOffset)
                : 0;
        }
    }
    uint64_t listView = 0;
    uint64_t deskContext = 0;
    uint64_t deskContextOffset = 0;
    uint64_t deskItems = 0;
    int deskCount = -1;
    int chosenDesk = -1;
    int chosenLayout = -1;
    if (!heroListOK && runFallbackScan && logicCore) {
        listView = ds_lq_read_ptr(
            logicCore + kDSLienQuanLogicCoreInstancesOffset);
    }
    if (!heroListOK && ds_lq_read_context_list(
            listView, 16, &deskContext, &deskContextOffset, &deskCount,
            &deskItems)) {
        int limit = deskCount > 16 ? 16 : deskCount;
        uint64_t base = deskItems + 0x20;
        for (int i = 0; i < limit && !heroListOK; i++) {
            uint64_t slots[3] = {
                base + (uint64_t)i * sizeof(uint64_t),
                base + (uint64_t)i * 0x10,
                base + (uint64_t)i * 0x10 + kDSLienQuanPoolObjHandleObjectOffset,
            };
            for (int layout = 0; layout < 3; layout++) {
                uint64_t candidate = ds_lq_read_ptr(slots[layout]);
                if (!candidate) continue;
                if (ds_lq_try_desk(candidate, &battle, &manager, &heroList,
                                   &heroItems, &heroCount)) {
                    desk = candidate;
                    chosenDesk = i;
                    chosenLayout = layout;
                    heroListOK = true;
                    break;
                }
            }
        }
    }
    uint64_t playerCenter = runFallbackScan && framework
        ? ds_lq_read_ptr(framework + kDSLienQuanKyriosPlayerCenterOffset)
        : 0;
    uint64_t fallbackHost = runFallbackScan && framework
        ? ds_lq_read_ptr(framework + kDSLienQuanKyriosHostLogicOffset)
        : 0;
    if (!heroListOK && runFallbackScan) {
        uint64_t editorFramework = ds_lq_framework_instance();
        int phase = g_dslqFallbackPhase++ % 10;
        if (phase == 0) {
            battle = editorFramework
                ? ds_lq_read_ptr(editorFramework +
                                 kDSLienQuanFrameworkBattleLogicOffset)
                : 0;
            heroListOK = ds_lq_try_battle(
                battle, &manager, &heroList, &heroItems, &heroCount);
        } else if (phase == 1) {
            heroListOK = ds_lq_find_manager_from_players(
                playerCenter, &battle, &manager, &heroList,
                &heroItems, &heroCount);
        } else {
            uint64_t object = 0;
            bool managerOnly = false;
            switch (phase) {
                case 2: object = playerCenter; break;
                case 3: object = fallbackHost; break;
                case 4: object = framework; break;
                case 5: object = actorManager; break;
                case 6: object = logicCore; break;
                case 7: object = playerCenter; managerOnly = true; break;
                case 8: object = framework; managerOnly = true; break;
                default: object = actorManager; managerOnly = true; break;
            }
            heroListOK = managerOnly
                ? ds_lq_scan_object_for_manager(
                    object, &manager, &heroList, &heroItems, &heroCount)
                : ds_lq_scan_object_for_logic(
                    object, &battle, &manager, &heroList,
                    &heroItems, &heroCount);
        }
    }
    if (heroListOK) {
        if (!usingGraphCache) {
            uint64_t itemsOffset = 0;
            uint64_t sizeOffset = 0;
            bool loose = false;
            int exactCount = -1;
            uint64_t exactItems = 0;
            if (ds_lq_read_cached_list(
                    heroList, kDSLienQuanHeroListItemsOffset,
                    kDSLienQuanHeroListSizeOffset,
                    &exactCount, &exactItems) &&
                exactCount == heroCount && exactItems == heroItems) {
                itemsOffset = kDSLienQuanHeroListItemsOffset;
                sizeOffset = kDSLienQuanHeroListSizeOffset;
                loose = true;
            } else if (!ds_lq_detect_list_layout(
                           heroList, heroCount, heroItems,
                           &itemsOffset, &sizeOffset, &loose)) {
                heroListOK = false;
            }
            if (heroListOK) {
                g_dslqCachedListItemsOffset = itemsOffset;
                g_dslqCachedListSizeOffset = sizeOffset;
                g_dslqCachedListLayoutKnown = true;
                g_dslqCachedListLayoutLoose = loose;
            }
        }
    }
    if (heroListOK) {
        g_dslqCachedBattle = battle;
        g_dslqCachedManager = manager;
        g_dslqCachedHeroList = heroList;
        g_dslqCachedHeroItems = heroItems;
        g_dslqCachedHeroCount = heroCount;
    } else if (g_dslqCachedManager && ++g_dslqGraphMisses < 4) {
        // A Unity frame can briefly expose null/replaced references. Keep the
        // last complete publication rather than flashing a partial graph.
        return;
    } else if (g_dslqGraphMisses >= 4) {
        // A replaced desk normally means a new match. Drop match-scoped host,
        // graph and camera objects together so no pointer crosses scenes.
        ds_lq_reset_match_mapping();
        return;
    }

    int validRoots = 0;
    uint64_t validRootPtrs[16] = {};
    DSLienQuanActorMeta validRootMetas[16] = {};
    bool refreshRoster = !usingGraphCache || !g_dslqRosterLocked ||
                         g_dslqCachedRootCount <= 0;
    if (heroListOK && refreshRoster && heroItems && heroCount > 0) {
        int limit = heroCount > kDSLQMaxHeroes ? kDSLQMaxHeroes : heroCount;
        uint8_t slots[kDSLQMaxHeroes * kDSLienQuanHeroElementStride] = {};
        bool slotsRead = ds_lq_read(
            heroItems + kDSLienQuanArrayDataOffset,
            slots, (size_t)limit * kDSLienQuanHeroElementStride);
        if (slotsRead) {
            uint64_t actors[kDSLQMaxHeroes] = {};
            uint8_t fields[kDSLQMaxHeroes][0x94] = {};
            DSDebugReadRange ranges[kDSLQMaxHeroes] = {};
            int rangeCount = 0;
            for (int i = 0; i < limit; i++) {
                uint64_t actor = 0;
                memcpy(&actor,
                       slots + (size_t)i * kDSLienQuanHeroElementStride +
                           kDSLienQuanHeroObjectOffset,
                       sizeof(actor));
                if (!ds_lq_valid(actor) || (actor & 0x7ULL)) continue;
                actors[rangeCount] = actor;
                ranges[rangeCount] = {
                    actor + kDSLienQuanActorRootMetaOffset,
                    fields[rangeCount], sizeof(fields[rangeCount]), NO
                };
                rangeCount++;
            }
            if (rangeCount > 0)
                ds_debug_read_list(g_dslqVmMap, ranges, (size_t)rangeCount);
            for (int i = 0; i < rangeCount; i++) {
                DSLienQuanVInt3 location = {};
                DSLienQuanActorMeta meta = {};
                if (!ranges[i].success ||
                    !ds_lq_parse_hero_fields(fields[i], &location, &meta))
                    continue;
                int rootIndex = validRoots++;
                validRootPtrs[rootIndex] = actors[i];
                validRootMetas[rootIndex] = meta;
            }
        } else {
            for (int i = 0; i < limit; i++) {
                DSLienQuanVInt3 location = {};
                DSLienQuanActorMeta meta = {};
                uint64_t actor = ds_lq_read_hero_root_exact(
                    heroItems, i, &location, &meta);
                if (!actor) continue;
                int rootIndex = validRoots++;
                validRootPtrs[rootIndex] = actor;
                validRootMetas[rootIndex] = meta;
            }
        }
        if (validRoots > 0) {
            g_dslqCachedRootCount = validRoots;
            for (int i = 0; i < validRoots; i++) {
                g_dslqCachedRootPtrs[i] = validRootPtrs[i];
                g_dslqCachedRootConfigIds[i] = validRootMetas[i].configId;
                g_dslqCachedRootPlayerIds[i] = validRootMetas[i].playerId;
                g_dslqCachedRootCamps[i] = validRootMetas[i].actorCamp;
            }
        }
    } else if (heroListOK && !refreshRoster) {
        validRoots = g_dslqCachedRootCount;
        for (int i = 0; i < validRoots; i++) {
            validRootPtrs[i] = g_dslqCachedRootPtrs[i];
            validRootMetas[i].configId = g_dslqCachedRootConfigIds[i];
            validRootMetas[i].playerId = g_dslqCachedRootPlayerIds[i];
            validRootMetas[i].actorCamp = g_dslqCachedRootCamps[i];
        }
    }
    if (usingGraphCache && !heroListOK) {
        if (++g_dslqGraphMisses >= 4) ds_lq_reset_match_mapping();
        return;
    }
    if (heroListOK && validRoots <= 0) {
        if (g_dslqRosterLocked) {
            // Zero/invalid coordinates can be a legitimate gameplay state
            // (death, respawn, or a transient game write). Match and roster
            // identity checks own topology invalidation; keep these leases so
            // the next raw display sample can recover without a mapper flush.
            g_dslqGraphMisses = 0;
        } else {
            // An unlocked roster is re-validating after a torn streak. Root
            // reads can keep failing for a whole GC storm, and a few consecutive
            // misses cover too little real time to justify resetting here; that would
            // blank the overlay over and over. Ride the storm out on the last
            // publication and only rebuild the cache after a full grace
            // window of continuous failure.
            if (!g_dslqZeroRootsSince) {
                g_dslqZeroRootsSince = now;
            } else if (now - g_dslqZeroRootsSince >= 3.0) {
                g_dslqZeroRootsSince = 0;
                g_dslqGraphMisses = 0;
                ds_lq_reset_match_mapping();
            }
            return;
        }
    } else if (validRoots > 0) {
        g_dslqZeroRootsSince = 0;
    }
    if (heroListOK) g_dslqGraphMisses = 0;

    uint32_t recovery = g_dslqRecoveryFlags.exchange(
        0, std::memory_order_acq_rel);
    if (recovery & kDSLQRecoverCamera) {
        g_dslqCameraSampleFailureStreak.store(0,
                                              std::memory_order_release);
        g_dslqCachedCameraSystem = 0;
        g_dslqCachedManagedCamera = 0;
        g_dslqCachedNativeCamera = 0;
        g_dslqCachedViewportValid = false;
        g_dslqNextCameraRepin = MAX(g_dslqNextCameraRepin, now + 0.10);
    }
    if (recovery & kDSLQRecoverLocations) {
        g_dslqRosterLocked = false;
        g_dslqRosterStablePasses = 0;
        g_dslqRosterStableSince = 0;
        g_dslqNextRosterRefresh = 0;
        // Keep the last pinned batch until a complete replacement is ready.
    }
    if (recovery & kDSLQRecoverStaleSource) {
        ds_lq_clear_live_sources();
        // The source is gone; unlock the roster so this very pass re-pins
        // and re-publishes instead of waiting for an identity miss.
        g_dslqRosterLocked = false;
        g_dslqRosterCandidateSignature = 0;
        g_dslqRosterStablePasses = 0;
        g_dslqRosterStableSince = 0;
        g_dslqNextRosterRefresh = 0;
    }
    uint64_t cameraSystem = g_dslqCachedCameraSystem;
    uint64_t managedCamera = g_dslqCachedManagedCamera;
    uint64_t nativeCamera = g_dslqCachedNativeCamera;
    bool cameraLookupAttempted = false;
    if (!nativeCamera && now >= g_dslqNextCameraRepin) {
        cameraLookupAttempted = true;
        cameraSystem = ds_lq_mono_singleton_instance(
            kDSLienQuanCameraSystemTypeInfoRva);
        managedCamera = cameraSystem
            ? ds_lq_read_ptr(cameraSystem +
                             kDSLienQuanCameraSystemMainCameraOffset)
            : 0;
        nativeCamera = ds_lq_read_ptr(
            managedCamera + kDSLienQuanUnityObjectCachedPtrOffset);
    }
    if (nativeCamera && now >= g_dslqNextCameraIdentityCheck) {
        g_dslqNextCameraIdentityCheck = now + 1.0;
        uint64_t currentSystem = ds_lq_mono_singleton_instance(
            kDSLienQuanCameraSystemTypeInfoRva);
        uint64_t currentManaged = currentSystem
            ? ds_lq_read_ptr(currentSystem +
                             kDSLienQuanCameraSystemMainCameraOffset)
            : 0;
        uint64_t currentNative = currentManaged
            ? ds_lq_read_ptr(currentManaged +
                             kDSLienQuanUnityObjectCachedPtrOffset)
            : 0;
        if (currentNative) {
            g_dslqCameraIdentityMisses = 0;
            if (currentNative != nativeCamera) {
                g_dslqCachedViewportValid = false;
                g_dslqNextCameraRepin = 0;
            }
            cameraSystem = currentSystem;
            managedCamera = currentManaged;
            nativeCamera = currentNative;
        } else if (++g_dslqCameraIdentityMisses >= 3) {
            g_dslqCameraIdentityMisses = 0;
            cameraSystem = managedCamera = nativeCamera = 0;
            g_dslqCachedCameraSystem = 0;
            g_dslqCachedManagedCamera = 0;
            g_dslqCachedNativeCamera = 0;
            g_dslqCachedViewportValid = false;
            g_dslqNextCameraRepin = now + 0.10;
        }
    }
    float viewport[4] = {};
    bool viewportOK = g_dslqCachedViewportValid;
    if (viewportOK) {
        memcpy(viewport, g_dslqCachedViewport, sizeof(viewport));
    } else {
        viewportOK = nativeCamera &&
            ds_lq_read(nativeCamera + kDSLienQuanNativeCameraViewportOffset,
                       viewport, sizeof(viewport)) &&
            isfinite(viewport[0]) && isfinite(viewport[1]) &&
            isfinite(viewport[2]) && isfinite(viewport[3]) &&
            viewport[2] > 0.0f && viewport[3] > 0.0f;
        if (viewportOK) {
            memcpy(g_dslqCachedViewport, viewport, sizeof(viewport));
            g_dslqCachedViewportValid = true;
        }
    }
    if (nativeCamera && nativeCamera != g_dslqCachedNativeCamera &&
        now >= g_dslqNextCameraRepin) {
        bool cameraPinned = ds_lq_pin_live_camera(nativeCamera);
        if (cameraPinned) {
            g_dslqCameraSampleFailureStreak.store(0,
                                                  std::memory_order_release);
            g_dslqCameraRepinFailures = 0;
            g_dslqNextCameraRepin = 0;
            g_dslqCachedCameraSystem = cameraSystem;
            g_dslqCachedManagedCamera = managedCamera;
            g_dslqCachedNativeCamera = nativeCamera;
        } else {
            uint8_t failures = MIN(
                (int)g_dslqCameraRepinFailures + 1, 4);
            g_dslqCameraRepinFailures = failures;
            g_dslqNextCameraRepin = now +
                MIN(1.0, 0.05 * (double)(1u << failures));
            g_dslqCachedCameraSystem = 0;
            g_dslqCachedManagedCamera = 0;
            g_dslqCachedNativeCamera = 0;
            g_dslqCachedViewportValid = false;
            nativeCamera = 0;
        }
    } else if (!nativeCamera && cameraLookupAttempted) {
        uint8_t failures = MIN((int)g_dslqCameraRepinFailures + 1, 4);
        g_dslqCameraRepinFailures = failures;
        g_dslqNextCameraRepin = now +
            MIN(1.0, 0.05 * (double)(1u << failures));
        g_dslqCachedCameraSystem = 0;
        g_dslqCachedManagedCamera = 0;
        g_dslqCachedNativeCamera = 0;
        g_dslqCachedViewportValid = false;
    }
    ds_lq_camera_zoom_tick(now);

    framework = framework ? framework : g_dslqCachedFramework;
    if (!framework) {
        framework = ds_lq_mono_singleton_instance(
            kDSLienQuanKyriosFrameworkTypeInfoRva);
        if (framework) g_dslqCachedFramework = framework;
    }
    uint64_t hostLogic = framework
        ? ds_lq_read_ptr(framework + kDSLienQuanKyriosHostLogicOffset) : 0;
    if (hostLogic) g_dslqCachedHostLogic = hostLogic;
    uint32_t vHostPlayerId = 0;
    uint32_t battleHostPlayerId = 0;
    uint32_t logicHostPlayerId = 0;
    uint64_t logicHostPlayer = 0;
    uint64_t hostActor = 0;
    uint32_t hostPlayerId = 0;
    uint32_t hostConfigId = 0;
    int hostCamp = 0;

    bool liveHostIdOK = hostLogic &&
        ds_lq_read(hostLogic + kDSLienQuanHostPlayerIdOffset,
                   &vHostPlayerId, sizeof(vHostPlayerId)) && vHostPlayerId;
    bool cachedHostIdMismatch = liveHostIdOK &&
        g_dslqCachedHostPlayerId &&
        vHostPlayerId != g_dslqCachedHostPlayerId;
    if (cachedHostIdMismatch) {
        g_dslqAutoSmitePool = 0;
        g_dslqAutoSmiteClassId = 0;
        g_dslqAutoSmiteLastEnqueue = 0;
        if (++g_dslqHostIdentityMisses >= 2) {
            ds_lq_reset_match_mapping();
            return;
        }
    } else {
        g_dslqHostIdentityMisses = 0;
    }

    if (!cachedHostIdMismatch && battle == g_dslqCachedHostBattle &&
        g_dslqCachedHostCamp > 0) {
        for (int i = 0; i < validRoots; i++) {
            if (validRootPtrs[i] != g_dslqCachedHostActor ||
                validRootMetas[i].playerId != g_dslqCachedHostPlayerId ||
                validRootMetas[i].configId != g_dslqCachedHostConfigId ||
                validRootMetas[i].actorCamp != g_dslqCachedHostCamp)
                continue;
            hostActor = validRootPtrs[i];
            hostPlayerId = validRootMetas[i].playerId;
            hostConfigId = validRootMetas[i].configId;
            hostCamp = validRootMetas[i].actorCamp;
            break;
        }
    } else if (!cachedHostIdMismatch &&
               battle == g_dslqCachedHostBattle) {
        for (int i = 0; i < validRoots; i++) {
            if (validRootPtrs[i] != g_dslqCachedHostActor &&
                validRootMetas[i].playerId != g_dslqCachedHostPlayerId)
                continue;
            hostActor = validRootPtrs[i];
            hostPlayerId = validRootMetas[i].playerId;
            hostConfigId = validRootMetas[i].configId;
            hostCamp = validRootMetas[i].actorCamp;
            break;
        }
    }

    if (!hostCamp) {
        ds_lq_read(battle + kDSLienQuanBattleHostPlayerIdOffset,
                   &battleHostPlayerId, sizeof(battleHostPlayerId));
        logicHostPlayer = ds_lq_read_ptr(
            battle + kDSLienQuanBattleHostPlayerOffset);
        ds_lq_read(logicHostPlayer + kDSLienQuanLogicHostPlayerIdOffset,
                   &logicHostPlayerId, sizeof(logicHostPlayerId));
        uint64_t hostActorCandidates[2] = {
            ds_lq_read_ptr(logicHostPlayer + kDSLienQuanLogicHostActorOffset),
            ds_lq_read_ptr(
                logicHostPlayer + kDSLienQuanLogicHostActorOffset + 0x08)
        };
        for (uint64_t candidate : hostActorCandidates) {
            for (int i = 0; candidate && i < validRoots; i++) {
                if (candidate != validRootPtrs[i]) continue;
                hostActor = candidate;
                hostPlayerId = validRootMetas[i].playerId;
                hostConfigId = validRootMetas[i].configId;
                hostCamp = validRootMetas[i].actorCamp;
                break;
            }
            if (hostCamp) break;
        }
        uint32_t hostIds[2] = {battleHostPlayerId, logicHostPlayerId};
        for (int source = 0; !hostCamp && source < 2; source++) {
            for (int i = 0; hostIds[source] && i < validRoots; i++) {
                if (hostIds[source] != validRootMetas[i].playerId) continue;
                hostActor = validRootPtrs[i];
                hostPlayerId = hostIds[source];
                hostConfigId = validRootMetas[i].configId;
                hostCamp = validRootMetas[i].actorCamp;
                break;
            }
        }
    }

    if (!hostCamp) {
        for (int i = 0; vHostPlayerId && i < validRoots; i++) {
            if (vHostPlayerId != validRootMetas[i].playerId) continue;
            hostActor = validRootPtrs[i];
            hostPlayerId = vHostPlayerId;
            hostConfigId = validRootMetas[i].configId;
            hostCamp = validRootMetas[i].actorCamp;
            break;
        }
    }
    if (hostCamp) {
        g_dslqCachedHostPlayerId = hostPlayerId;
        g_dslqCachedHostConfigId = hostConfigId;
        g_dslqCachedHostCamp = hostCamp;
        g_dslqCachedHostBattle = battle;
        g_dslqCachedHostActor = hostActor;
    }

    if (refreshRoster) {
        int expectedCount = MIN(MAX(heroCount, 0), kDSLQMaxHeroes);
        bool complete = ds_lq_roster_observation_complete(
            validRootPtrs, validRootMetas, validRoots, expectedCount);
        uint64_t signature = complete
            ? ds_lq_roster_signature(validRootPtrs, validRootMetas,
                                     validRoots, expectedCount)
            : 0;
        if (!complete) {
            g_dslqRosterCandidateSignature = 0;
            g_dslqRosterStablePasses = 0;
            g_dslqRosterStableSince = 0;
        } else if (signature != g_dslqRosterCandidateSignature) {
            g_dslqRosterCandidateSignature = signature;
            g_dslqRosterStablePasses = 1;
            g_dslqRosterStableSince = now;
            if (hostCamp > 0) {
                uint32_t heroIds[kDSLQMaxEnemies] = {};
                int enemyCount = 0;
                for (int i = 0;
                     i < validRoots && enemyCount < kDSLQMaxEnemies; i++) {
                    if (validRootMetas[i].actorCamp == hostCamp) continue;
                    heroIds[enemyCount++] = validRootMetas[i].configId;
                }
                if (enemyCount > 0)
                    ds_lq_prewarm_hero_images(heroIds, enemyCount);
            }
        } else {
            g_dslqRosterStablePasses++;
        }

        // Use the list's observed participant count rather than hard-coding
        // ten, so a stable one-player training roster can lock too.
        bool stable = complete && hostCamp > 0 &&
            g_dslqRosterStablePasses >= 4 &&
            now - g_dslqRosterStableSince >= 0.35;
        if (stable) {
            int enemyCount = 0;
            for (int i = 0; i < validRoots; i++) {
                if (validRootMetas[i].actorCamp != hostCamp) enemyCount++;
            }
            bool sourceReady = enemyCount == 0;
            if (enemyCount > 0 && now >= g_dslqNextDiscovery) {
                sourceReady = ds_lq_publish_enemy_read_source(
                    validRootPtrs, validRootMetas, validRoots, hostCamp,
                    battle, viewport, viewportOK);
                if (sourceReady) {
                    g_dslqDiscoveryFailures = 0;
                    g_dslqNextDiscovery = 0;
                } else {
                    uint8_t failures = MIN(
                        (int)g_dslqDiscoveryFailures + 1, 4);
                    g_dslqDiscoveryFailures = failures;
                    g_dslqNextDiscovery = now +
                        MIN(1.0, 0.05 * (double)(1u << failures));
                }
            }
            if (sourceReady) {
                g_dslqRosterLocked = true;
                g_dslqNextRosterRefresh = now + 0.50;
            }
        }
    }

    ds_lq_refresh_minimap_geometry(now);
    ds_lq_refresh_monsters(now, manager, battle, hostCamp);
    uint64_t autoSmiteFramework = framework
        ? framework : g_dslqCachedFramework;
    ds_lq_auto_smite_tick(now, autoSmiteFramework, hostActor, hostPlayerId);
}

static uint64_t ds_lq_static_fields_from_typeinfo(uint64_t typeInfoRva) {
    uint64_t typeInfo = ds_lq_addr(typeInfoRva);
    uint64_t klass = ds_lq_read_ptr(typeInfo);
    return klass ? ds_lq_read_ptr(klass + kDSLienQuanIl2CppStaticFieldsOffset) : 0;
}

// CameraSystem inherits the generic MonoSingleton static field holder; its
// own Il2CppClass static fields are not the instance slot used by the beta.
static uint64_t ds_lq_mono_singleton_instance(uint64_t typeInfoRva) {
    uint64_t typeInfo = ds_lq_addr(typeInfoRva);
    uint64_t klass = ds_lq_read_ptr(typeInfo);
    uint64_t parent = klass ? ds_lq_read_ptr(klass + kDSLienQuanIl2CppParentClassOffset) : 0;
    uint64_t fields = parent ? ds_lq_read_ptr(parent + kDSLienQuanIl2CppStaticFieldsOffset) : 0;
    uint64_t instance = fields ? ds_lq_read_ptr(fields) : 0;
    return instance && ds_lq_read_ptr(instance) == klass ? instance : 0;
}

static uint64_t ds_lq_singleton_instance_from_methodinfo(
    uint64_t methodInfoRva) {
    uint64_t methodInfo = ds_lq_read_ptr(ds_lq_addr(methodInfoRva));
    uint64_t klass = methodInfo ? ds_lq_read_ptr(methodInfo + 0x20) : 0;
    // Generic Singleton<T> MethodInfo layout used by GetInstance:
    // klass->rgctx_data(+0xC0), context class(+0x10), static_fields(+0xB8).
    uint64_t genericContext = klass ? ds_lq_read_ptr(klass + 0xC0) : 0;
    uint64_t holderClass = genericContext
        ? ds_lq_read_ptr(genericContext + 0x10) : 0;
    uint64_t fields = holderClass
        ? ds_lq_read_ptr(holderClass + kDSLienQuanIl2CppStaticFieldsOffset) : 0;
    uint64_t instance = fields ? ds_lq_read_ptr(fields) : 0;
    // The object is CUIManager while MethodInfo::klass is its generic
    // Singleton<CUIManager> base, so their class pointers intentionally differ.
    return ds_lq_valid(instance) && !(instance & 0x7ULL) &&
           ds_lq_valid(ds_lq_read_ptr(instance)) ? instance : 0;
}

static uint64_t ds_lq_framework_instance(void) {
    uint64_t fields = ds_lq_static_fields_from_typeinfo(
        kDSLienQuanFrameworkEditorProxyTypeInfoRva);
    return fields ? ds_lq_read_ptr(fields + kDSLienQuanProxyInstanceOffset) : 0;
}

static bool ds_lq_location_valid(const DSLienQuanVInt3 *location) {
    return location &&
           (location->x != 0 || location->y != 0 || location->z != 0) &&
           location->x > -100000000 && location->x < 100000000 &&
           location->y > -100000000 && location->y < 100000000 &&
           location->z > -100000000 && location->z < 100000000;
}

static bool ds_lq_read_actor_location(uint64_t actorRoot, DSLienQuanVInt3 *out) {
    if (!out || !ds_lq_valid(actorRoot)) return false;
    if (!ds_lq_read(actorRoot + kDSLienQuanActorRootLocationOffset,
                    out, sizeof(*out))) return false;
    return ds_lq_location_valid(out);
}
