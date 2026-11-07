# Lien Quan Unity Reader Port

Data-source rule: use DarkLQ only for verified UnityFramework base discovery.
Use LQVIP/KGVNPlayerESP as the reference for singleton, list, actor, position,
camera, snapshot, and rendering data paths.

## Muc tieu

Port reader Lien Quan vao pipeline hien tai cua DarkPubg, giu lai shared-page reader, cache, reader queue, batch read, snapshot lock va HUD/projection. Backend moi dung process `kgvn` va doc actor logic qua singleton hardcode.

## Chain runtime da xac nhan bang dump va log

```text
Singleton<LLogicCore> MethodInfo RVA 0xD10E9D0
  -> MethodInfo + 0x20 = generic method class
  -> class + 0xC0 = RGCTX
  -> RGCTX + 0x10 = Singleton<LLogicCore> class
  -> class + 0xB8 = static_fields
  -> static_fields + 0x00 = LLogicCore instance
  -> LLogicCore + 0x40 = curUpdatingDesk
  -> LDeskBase + 0x38 = DeskBattleLogic
  -> LBattleLogic + 0xF8 = LGameActorMgr
  -> LGameActorMgr + 0x48 = HeroActors
  -> HeroActors runtime wrapper: items +0x08, size +0x10
     (cac layout khac chi giu trong fallback discovery)
  -> Il2CppArray + 0x20 = element data
  -> HeroActors runtime slot stride 0x10; element + 0x00 = LActorRoot
  -> LActorRoot + 0x58 = ActorMeta
  -> LActorRoot + 0xE0 = VInt3 _location
```

Log 5v5 cuoi xac nhan source D, graph/cache/list on dinh, local actor dung camp
va projection khong con nhay. Fast path doc header list trong mot block 16 byte,
doc 10 slot trong mot block, moi `LActorRoot` trong mot block tu `+0x58` den
`+0xDC`; local actor duoc cache theo `battle`. Dia chi heap trong log khong duoc
hardcode.

Log 6 xac nhan fast path voi 2 hero con 8 read / 596 byte moi tick. Reader duoc
dua len cung cadence 120 Hz cua bridge/renderer PUBG; bo validation actor bi lap,
bo `proc_find_by_name` lap moi giay va bo `fsync` khoi reader queue.

Log 7 xac nhan 120 Hz van gay CPU cao du hot tick chi con 6 read. AOV co roster
co dinh theo tran, nen `HeroActors`/slot/`ActorMeta` chi doc mot lan luc bat dau
tran. Theo pattern PUBG, worker 60 Hz scatter-read tat ca `_location` 12 byte
trong mot batch va publish world snapshot; `CADisplayLink` doc camera block 128
byte tu shared page, project va render tren luong display. Hai luong chi trao doi
snapshot qua lock ngan, khong doc memory trong lock. Viewport cache theo native
camera. Moi giay chi kiem tra `currentDesk -> battle` de phat hien tran moi va
dung lai roster cache.

## Offset managed

- Process: `kgvn`
- `KyriosFramework_TypeInfo`: `0xD0BB320`
- `LFrameworkEditorProxy_TypeInfo`: `0xD0BBE00`
- `Il2CppClass.static_fields`: `0xB8`
- `Il2CppClass.rgctx_data`: `0xC0`
- `LLogicCore.curUpdatingDesk`: `0x40`
- `LDeskBase.DeskBattleLogic`: `0x38`
- `LFramework._battleLogic`: `0x68`
- `LBattleLogic.gameActorMgr`: `0xF8`
- `LBattleLogic.HostPlayerId`: `0x88`
- `LBattleLogic.HostPlayer`: `0x2C8`
- `LHostPlayer.m_hostPlayerId`: `0x10`
- `LHostPlayer.m_HostActor`: `0x20`
- `LGameActorMgr.GameActors`: `0x38`
- `LGameActorMgr.AllActorList`: `0x40`
- `LGameActorMgr.HeroActors`: `0x48`
- `LGameActorMgr.MonsterActors`: `0x70`
- `List<T> managed _items/_size`: `0x10/0x18`
- `HeroActors runtime wrapper _items/_size`: `0x08/0x10`
- `Il2CppArray.vector`: `0x20`
- `HeroActors runtime element stride`: `0x10`
- `HeroActors runtime LActorRoot pointer`: element `+0x00`
- `PoolObjHandle._handleObj`: `0x08` (chi dung cho container giu struct handle)
- `LActorRoot.name`: `0x20`
- `LActorRoot.mRealObjID`: `0x28`
- `LActorRoot.TheActorMeta`: `0x58`
- `LActorRoot._location`: `0xE0`
- `LActorRoot._forward`: `0xEC`
- `LActorRoot.ActorControl`: `0x308`
- `LActorRoot.SkillControl`: `0x328`
- `LActorRoot.ValueComponent`: `0x338`
- `LActorRoot.EquipComponent`: `0x348`
- `LActorRoot.ObjLinker`: `0x370`
- `LActorRoot._gameObject`: `0x410`
- `LActorRoot.isRecycled`: `0x420`
- `ActorLinker.SkillControl`: `0x18`
- `ActorLinker.BuffControl`: `0x40`
- `ActorLinker.mRealObjID`: `0x148`
- `ActorLinker.<bVisible>`: `0x1DD`

`VInt3` dung precision 1000; doi sang world units bang phep chia cho `1000.0f`.

## Ke hoach implementation

1. Tao backend `DSBridgeLienQuan.inc.mm`, tai su dung cac helper low-level tu `DSBridgeESP.inc.mm`/`DSBridge.mm`.
2. Them attach target `kgvn`, image-base discovery va static TypeInfo pointer read.
3. Implement singleton cache; khong scan object graph khi graph da cache con hop le.
4. Hot path chi doc layout chuan cua `HeroActors +0x48`; `GameActors +0x38` va cac layout khac chi lam fallback discovery.
5. Batch-read toan bo slot `PoolObjHandle`; moi actor doc lien tuc `ActorMeta` + `_location` mot lan, validate truoc khi publish snapshot.
6. Giu snapshot format/projection/HUD hien tai; thay root position input bang `VInt3` logic.
7. Render marker/icon theo pool layer persistent: tao anh mot lan, gan `CALayer.contents`, moi frame chi doi `position`, `hidden`, mau vien va text khi gia tri that su thay doi.
8. Dua hero-id image cache tu beta sang; cache theo `configId`, khong decode `NSData -> UIImage` trong render loop.
9. Them camera singleton/managed-camera bridge sau khi actor snapshot chay on dinh. Native camera offsets chi dung sau validation matrix.
10. Test lobby -> vao tran -> mat sight -> actor spawn/despawn; do tick time, image decode count va page-cache miss rate.
11. Chi sau khi Lien Quan on dinh moi doi ten include/backend mac dinh; backend PUBG UE4 giu lai lam fallback.

## Toi uu hot path da ap dung

- Log 9: 129 snapshot trong tran deu co 2 actor va camera hop le; 127 mau
  chi copy 24 byte vi tri. Log 4 Hz khong do duoc jitter tung frame.
- Display AOV van doc camera khi generation worker khong doi, tranh bo
  luot render luc worker tre. Khong noi suy vi tri.
- Bao ve page vi tri da pin khoi LRU eviction; chup context debug tren worker
  truoc khi gui qua queue log de tranh data race.
- Event `timing` moi giay thong ke worker Hz, tick/gap avg-max, tuoi snapshot
  tai render va so frame lap snapshot. Can log tren thiet bi de xac nhan.

- Roster `HeroActors` chi discovery mot lan moi tran.
- Pin camera 128 byte va cac span `LActorRoot._location`; hot path chi
  `memcpy` tu mapping local, khong resolve/map lai page.
- Reader cap nhat `_location` theo timer 120 Hz va khong noi suy.
- Neu vm-region miss, bo lan doc hien tai va rebuild index tren queue nen, toi
  da mot lan moi giay, giong backend PUBG.
- Format JSON va ghi log chay tren queue rieng, khong chan ESP reader.

## Offset can coi la runtime-only

Native `TransformAccessArray` va native `Camera` offsets trong ban beta khong duoc `dump.cs` xac nhan. Khong dung chung lam chain discovery; phai co validation rieng va fallback ve logic position.

## Tieu chi hoan thanh

- Khong resolve ten actor trong hot path.
- Khong scan full actor graph moi frame.
- Reader queue khong bi giat khi list actor thay doi.
- Vi tri van cap nhat khi actor mat sight.
- Snapshot cu van duoc render neu mot frame doc memory that bai.
- Hero icon moi `configId` chi decode mot lan trong suot vong doi process.
- Render frame binh thuong khong tao UIImage/CALayer moi.
