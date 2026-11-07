# Bàn giao Sol: làm icon AOV bám mượt, không nội suy

Ngày rà soát: 2026-09-13. Workspace: /Users/mac/Desktop/LienQuanDS.

## 1. Mục tiêu duy nhất của đợt tối ưu

Giảm độ trễ và dao động từ lúc lấy vị trí thật đến lúc cập nhật icon, cả khi có và mất sight. Chuẩn so sánh là xương PUBG bám mượt trong chính project này. Theo xác nhận của người dùng, LQVIP còn kém mượt hơn bản AOV hiện tại: chỉ dùng nó làm reference tìm đúng actor/địch, không dùng làm baseline hiệu năng. Không xem giảm CPU trung bình hoặc tăng worker Hz là đủ để kết luận icon đã mượt.

Đây là kế hoạch nghiên cứu lại theo đường thực thi của project, chưa phải bản sửa đã chạy thiết bị. Chỉ thay Markdown trong lượt này. Sol triển khai từng bước có số đo đối chiếu; không làm một đợt refactor lớn rồi mới thử.

Ràng buộc:

- Giữ nguồn tọa độ LActorRoot._location; không tự thay bằng ActorLinker/Unity Transform.
- Không lerp, extrapolation, animation vị trí, bộ lọc làm mượt hoặc giữ mẫu cũ một giây để che giật.
- Singleton và offset đã kiểm chứng; không resolve tên method trong hot path.
- Tối đa 10 hero, tối đa 5 icon địch. Roster lấy khi vào trận và khóa khi đã hoàn chỉnh; phòng tập không bắt buộc đủ 10.
- Giữ fallback discovery cần cho trận người, nhưng tách khỏi đường lấy mẫu ổn định.
- Giữ cache ảnh/layer và các tối ưu hữu ích của PUBG.
- Không sửa/reset các thay đổi ngoài phạm vi đang có trong worktree.
- Build sau khi sửa source: DARKSPEED_UNSIGNED=1 ./build-darkspeed.sh.

## 2. Đối chiếu trực tiếp với xương PUBG trong project

| Cơ chế PUBG đang dùng | Đối chiếu AOV / việc cần làm |
| --- | --- |
| ds_pubg_read_skeletons_batch đọc mesh/C2W, sau đó bone buffers, transform rồi mới refresh health | Giữ khoảng lấy dữ liệu chuyển động ngắn; AOV không chen discovery/meta/log vào giữa các mẫu position và camera |
| Health có nhịp riêng 30 Hz, bone không bị buộc theo health | Dữ liệu tĩnh roster/camp và debug không được chi phối nhịp vị trí |
| Worker publish world-space; main đọc camera live rồi project | AOV đã có cùng cách chia cơ bản; phải đo độ trễ từng chặng, không chỉ port lại mô hình hai luồng |
| ds_pubg_read_camera_now đọc hai mẫu local, kiểm tra coherence và retry giới hạn | Đây là khác biệt cụ thể cần kiểm chứng cho AOV; không chép ngưỡng POV sang ma trận |
| Camera source được khóa trong khi copy và invalidation | Dùng làm chuẩn lifetime khi đưa location spans vào display, rà cả đường flush chung |
| Bone world lấy từ transform; AOV lấy raw _location | Đo nhịp dữ liệu thực của cả hai nếu cần, không kết luận nguồn AOV là thủ phạm trước khi loại trừ nghẽn trong app |

Các điểm chính ở DSBridgePubg.inc.mm: ds_pubg_read_camera_now (1031), ds_pubg_read_skeletons_batch (1681), ds_pubg_publish (1768); render chung ở DSBridgeESP.inc.mm. Chạy baseline PUBG riêng trên cùng thiết bị, dùng cùng cách đo callback/sample age nếu khả thi. Không chạy đồng thời hai backend để so CPU. Mục tiêu là học cơ chế giúp bone bám chắc và kiểm chứng cơ chế nào còn thiếu ở AOV, không port toàn bộ reader nhiều player của PUBG.

### Ghi chú phạm vi reference LQVIP

Reference: /Users/mac/Desktop/LienQuanEXT/LQVIP/sources/PlayExt/esp/lib/KGVNPlayerESP.mm.

Code tại kgvnReadVisualPosition (khoảng dòng 867) lấy mRealObjID của LActorRoot, tra bảng vị trí visual rồi chuyển về VInt3. kgvnRefreshVisualPosMap (3191, được gọi tại 3249) dựng bảng từ ActorLinker.myTransform qua kgvnReadUnityTransformWorldPos. Các collector, ví dụ dòng 2084, ưu tiên kgvnReadVisualPosition rồi mới fallback về raw _location.

Như vậy, code reference thực sự có đường vị trí Unity Transform, không chỉ khác số byte đọc hoặc cách tìm singleton. Chú thích của reference gọi đây là vị trí render-interpolated; điều đó chưa chứng minh mỗi frame thực tế đều chọn nhánh visual. Cần phân biệt bằng log source nếu so sánh trên thiết bị.

Thông tin này chỉ để tránh port nhầm nguồn vị trí khi tham khảo cách tìm actor. Không dùng độ mượt LQVIP để giải thích hay đánh giá AOV hiện tại. Nếu đo được raw chỉ đổi từng bước trong khi hình nhân vật chuyển động giữa các bước thì mới ghi nhận giới hạn đó; hiện chưa có số đo đủ để khẳng định nhịp raw hoặc xem nó là nguyên nhân chính.

Đợt này vẫn giữ _location theo yêu cầu. Đo giới hạn nguồn dữ liệu riêng với độ trễ do app; không âm thầm port nhánh visual để làm bài test trông mượt hơn.

## 3. Luồng hiện tại và điều đã tối ưu

| Chặng | Code cần đọc | Hành vi hiện tại |
| --- | --- | --- |
| Lập lịch worker | DSBridgeESP.inc.mm: ds_hosted_overlay_frame | Timer yêu cầu 120 Hz trên serial bridge queue |
| Lấy vị trí | DSBridgeLienQuan.inc.mm: ds_lq_debug_tick | Copy 12 byte VInt3 mỗi cached root từ span đã pin; lỗi mới đi read-list |
| Xuất dữ liệu | Các biến g_dslqWorldHeroes / g_dslqProjectionLock | Worker lọc camp và publish tối đa 5 world positions |
| Nhịp vẽ | DSBridgeESP.inc.mm: displayLinkDidFire, ds_hosted_consume_render_snapshot | CADisplayLink; có fallback dispatch main khi display link im hơn 0,10 giây |
| Camera và chiếu | DSBridgeLienQuan.inc.mm: ds_lq_copy_projected_heroes | Lấy world snapshot rồi đọc camera live 128 byte, nhân ma trận và project |
| Icon | DSBridgeESP.inc.mm: ds_hosted_apply_pubg | Layer pool, cache UIImage, cập nhật position trực tiếp, tắt implicit actions |

Source hiện tại đã cho AOV project lại khi worker generation chưa đổi. Camera đã đọc ở display time. Không đề xuất hai việc này như những fix còn thiếu.

128 byte là hai ma trận 4×4 float: view 64 byte + projection 64 byte. 16 byte đang dùng cho viewport không thay thế được hai ma trận. Không cắt xuống 16/64 byte khi chưa chứng minh có nguồn view-projection kết hợp hoặc projection bất biến và cơ chế invalidation đúng.

Ảnh không bị vẽ lại bằng CPU mỗi frame trong đường icon đang xét: contents chỉ đổi khi configId đổi. Vẫn cần đo first decode và việc slot đổi chủ; không quy toàn bộ giật cho render ảnh.

## 4. Xếp hạng vấn đề liên quan trực tiếp đến icon

| Ưu tiên | Bằng chứng trong code | Chưa biết / tác động cần đo |
| --- | --- | --- |
| P0 | World lấy từ worker, camera lấy mới hơn ở display; hai nhịp độc lập | Tuổi vị trí và lệch thời điểm camera-position có gây phần lớn giật không |
| P0 | displayLinkDidFire bỏ qua timestamp/targetTimestamp; thống kê display gộp cả fallback | Overlay thực tế chạy đều bao nhiêu Hz khi app ở nền, có đang phụ thuộc fallback không |
| P1 | PUBG dùng bone transforms; AOV dùng raw _location | Đo nhịp đổi raw để phân biệt bước dữ liệu với miss của app, không mặc định lỗi do nguồn |
| P1 | AOV copy camera một lần; validation chủ yếu finite/nonzero | Có đọc trúng lúc game đang cập nhật ma trận, gây UV outlier không |
| P1 | Pin/reset/flush có nhiều đường và worker sở hữu location spans | Phải bảo đảm lifetime trước khi đưa copy raw vào display |
| P2 | AOV render vẫn copy PUBG snapshot, gán style debug mỗi frame | Chi phí có đủ lớn để trễ callback hay chỉ là overhead nhỏ |
| P2 | Layer gán theo danh sách projected đã compact, không theo playerId | Churn contents khi một actor ra/vào màn hình; không giải thích mọi giật lúc đi thẳng |

P0 là thứ cần xử lý/đo trước; bảng không khẳng định mọi mục đều đã chứng minh là nguyên nhân.

## 5. Bước A — đo đúng một chuỗi frame trước khi sửa kiến trúc

Chỉnh instrumentation nhẹ, không log JSON từng frame.

Mỗi mẫu đo lưu số vào bộ đệm/histogram RAM giới hạn dung lượng; tổng hợp một lần/giây và serialize ở log queue. Có ba chế độ off, timing, full. Reset cửa sổ timing khi pause/resume hoặc đổi match epoch. Không tạo backlog log vô hạn.

Các nhóm cần đo:

- Worker: callback gap, thời gian toàn ds_hosted_overlay_frame, thời gian riêng ds_lq_debug_tick; tách discovery/fallback/pin/steady copy. Đo riêng phần ngoài LQ tick để không bỏ sót bridge queue nghẽn.
- Mẫu vị trí: location_sample_start/end, publish_time, sequence và match epoch. Theo từng playerId, đếm raw position thực sự đổi và khoảng cách thời gian giữa các lần đổi khi đang di chuyển.
- Display: callback origin (display-link/fallback), timestamp, targetTimestamp, callback arrival và interval; không coi preferredFrameRateRange là FPS thực tế.
- Projection: thời điểm lấy camera, tuổi mẫu position tại projection, thời gian chờ khóa, copy/project/layer-update duration; số camera fail, projection reject, icon hide và lý do.
- Tổng hợp: p50/p95/p99/max cho gap, sample age và callback duration; đếm deadline slack âm so với targetTimestamp. CATransaction commit không phải bằng chứng frame đã hiện ra màn hình.

Instrumentation hiện có chưa đủ: g_dslqPublishedAt bắt nguồn từ đầu tick, không phải thời điểm copy _location; repeated_snapshot chỉ nói sequence lặp, không nói actor đứng yên hay reader miss. display_frames tăng ở đường thử project và không phân biệt callback origin. DSLQTickTiming chưa bao hết công việc worker; static cửa sổ có thể kéo gap qua pause.

Baseline log 9: 175 snapshot, 129 graph.cache=true; các mẫu cache có 2 roots và camera hợp lệ, 127 mẫu ops=0/bytes=24, hai mẫu ops=1/bytes=32. Không có timing event trong log này. Log lấy mẫu chậm không chứng minh 120 Hz, không chứng minh không có spike giữa hai dòng và không đại diện trận 5v5.

## 6. Bước B — thử lấy raw positions sát camera ở display time

Đây là thử nghiệm chính để loại bỏ tuổi snapshot worker mà vẫn hoàn toàn không nội suy.

Giữ worker phụ trách attach/discovery, roster/meta/camp, pin và recovery. Sau khi roster hợp lệ, worker publish một nguồn đọc bất biến gồm epoch, identity actor/player, tối đa 5 location spans của địch, camera source và viewport tương ứng.

Display callback copy raw _location từ nguồn đã pin và camera gần nhau, sau đó project và cập nhật layer trong cùng callback. Với 5 địch, payload một lượt bình thường là 5×12 + 128 = 188 byte, chưa tính metadata/copy nội bộ hoặc retry. Không thêm kernel call, scan, map page, lookup singleton, load ảnh hay I/O lên main thread.

Điều kiện bắt buộc trước khi thử:

1. Không cho main đọc trực tiếp mảng g_dslqLiveLocations hiện do worker sửa.
2. Thiết kế lifetime cho cả camera và location mapping: clear/replace nguồn dưới cùng cơ chế đồng bộ trước unmap; mapping còn sống suốt memcpy, kể cả span qua hai page.
3. Match/process/map epoch phải khớp; pointer trông hợp lệ không đủ xác định cùng đối tượng.
4. Khóa chỉ bảo vệ publish/lifetime và copy ngắn; không giữ khóa khi scan, pin, kernel read, log hoặc project.
5. Worker recovery ở ngoài hot path, có backoff. Nếu span mất, báo recovery và đếm lỗi; không dùng vị trí epoch cũ.
6. Các đường eviction, flush, disable, resume và backend switch đều tuân thủ hợp đồng lifetime mới. Lock cục bộ không chặn game đang ghi dữ liệu.

A/B cùng kịch bản: A dùng world snapshot worker hiện tại; B dùng raw copy gần camera ở display. So sánh sample age, UV steps/outliers, callback p99, CPU và video. Không chạy hai reader nặng song song trong bài test chính.

Giữ thay đổi nếu giảm độ trễ/dao động mà không tạo main-thread stall. Không tăng worker Hz để thay cho bước này. Worker được giảm tần suất sau khi display không còn phụ thuộc vào nó để có vị trí mới, nhưng vẫn phải phát hiện chuyển trận/lỗi nguồn kịp thời.

## 7. Bước C — xử lý nhịp display và camera theo kết quả đo

### C1. Display callback

Nếu callback đều và deadline còn dư, không đổi scheduler chỉ để đẹp số Hz.

Nếu phần lớn callback đến từ fallback hoặc interval dao động, điều tra CADisplayLink/run-loop/hosted overlay lifecycle trong DSBridgeESP.inc.mm và app lifecycle. Tách recovery/watchdog khỏi cập nhật định kỳ; tránh worker tiếp tục xếp nhiều tác vụ main. Giữ tối đa một fallback pending.

Không xóa fallback vô điều kiện: cần xác minh display link còn chạy khi app nền. Hai callback trong cùng chu kỳ màn hình không tạo thêm hai frame hiển thị.

### C2. Camera coherence

PUBG ds_pubg_read_camera_now đọc hai mẫu POV và retry có giới hạn; kiểm tra location/rotation/FOV. Cuối cùng có thể chấp nhận mẫu sane mới nhất. Không có quy tắc giữ camera/vị trí một giây để làm mượt ở hàm này.

AOV hiện copy cặp ma trận một lần. Nếu log cho thấy UV outlier/camera sample bất thường, thử hai lượt copy local và tối đa một retry, với validation phù hợp ma trận và thời gian lấy mẫu. Đếm retry và chi phí.

Không copy nguyên ngưỡng độ/góc/khoảng cách của PUBG sang AOV; không yêu cầu hai camera sample bằng nhau tuyệt đối khi đang pan. Không dùng kết quả nonzero đơn thuần như chứng minh coherence. Có thể đánh giá độ dịch UV của cùng điểm kiểm tra khi so hai mẫu, nhưng ngưỡng phải phân biệt được camera chuyển động hợp lệ.

Nếu cần thí nghiệm camera → positions → camera, ghi rõ đó là kiểm tra coherence gần nhau, không phải snapshot nguyên tử của game. Không retry vô hạn hoặc quay lại ma trận cũ mỗi khi camera di chuyển.

## 8. Bước D — giảm công việc thừa khi dữ liệu đã đúng

Làm sau hoặc cùng bản instrument nhẹ, không trì hoãn thử nghiệm B bằng việc dọn toàn project.

- Tách nhánh AOV render để không copy full PUBG snapshot mỗi callback; giữ đúng trạng thái hide/reset khi đổi backend.
- Chỉ gán font, màu, alignment, frame debug khi style/layout thay đổi. Debug off không format text.
- Prewarm/decode icon khi roster hoàn chỉnh, cache theo configId. Gắn slot ổn định theo playerId/actor identity; đổi contents khi icon thật sự đổi.
- Giữ tọa độ CGFloat không làm tròn pixel; disableActions phải còn hiệu lực. Không thêm CA animation.
- Cache metadata/camp và danh sách địch sau khi biết host camp. Không đọc meta, hero list hoặc refilter toàn roster mỗi display frame.
- Không port batch bones hàng loạt của PUBG khi dữ liệu vị trí địch chỉ 60 byte. Cần đo map/lock/callback, không chỉ đếm bytes.
- Không giả định “chia hai luồng 128 byte” tự nhanh hơn: bản hiện tại có worker/display tách vai trò; thêm luồng có thể tăng skew/lock.

## 9. Điều kiện ổn định nguồn: sửa có mục tiêu, không lấn át icon

Các vấn đề dưới đây có thể tạo mất icon/spike khi chuyển trạng thái. Chỉ đưa vào bản tối ưu chính phần cần cho lifetime hoặc xuất hiện trong trace; ghi riêng phần còn lại.

| Điểm rà lại | Bằng chứng / hướng sửa |
| --- | --- |
| Attach backoff | ds_lq_attach_if_needed kiểm tra deadline ở nhánh đã có proc/map/base, nhưng failure deadline cần chặn cả nhánh cold attach; tránh scan lặp theo timer |
| Roster khóa quá sớm | ds_lq_debug_tick cache khi validRoots > 0; không xem roster đầu tiên đọc được một phần là roster hoàn chỉnh |
| Đổi trận | Check cached LogicCore/currentBattle cần xử lý null, thiếu LogicCore và identity tái sử dụng; không chỉ nonzero pointer khác |
| Location recovery | Fallback đọc thành công phải có đường repin có giới hạn, tránh mãi quay lại read-list |
| Camera recovery | Clear pointer cache và live source đồng bộ; xử lý pin fail, camera thay đối tượng và source cũ còn giá trị hợp lệ |
| Pause/resume/reset | Rà DSBridge.mm, ESP start/stop, cache flush và LQ reset; tránh cached roots tồn tại nhưng pin/region đã mất |
| Mapper chung PUBG/AOV | Có owner/epoch, tránh nhánh backend khác flush mapping đang được display dùng |
| UI/shared state | Kiểm tra consumed generation và UIKit state đọc ngoài main; không sửa race bằng bỏ khóa |
| Logging | Giới hạn pending, ngừng serialize khi đã chạm giới hạn file; đo timing off/on |
| Lifecycle khác | Termination dispatch_sync và build ZIP cập nhật archive cũ là hạng mục riêng, không gọi đó là fix icon steady-state |

Roster hoàn chỉnh dựa vào thông tin trận và số phần tử hợp lệ ổn định trong pha khởi tạo; không hardcode phòng tập phải đủ 10. Khi đã khóa, không polling roster 4 Hz cả trận. Theo dõi epoch/lỗi nguồn nhẹ để mở lại discovery khi thực sự chuyển trận hoặc nguồn bị thay.

## 10. Ma trận thử nghiệm trên thiết bị

Lặp cùng kịch bản trước/sau, cùng cấu hình game và refresh rate; ghi rõ thời gian vào trận. Không lấy 60 giây chờ vào trận tính vào steady-state.

| Kịch bản | Tách được nguyên nhân nào |
| --- | --- |
| Actor di chuyển, camera giữ cố định nếu thao tác game cho phép | Nhịp raw _location và tuổi vị trí |
| Actor đứng yên, pan camera | Nhịp/camera coherence và display cadence |
| Actor cùng camera đều di chuyển | Temporal skew và độ bám tổng thể |
| Cả hai đứng yên | UV noise, đọc không nhất quán, nhấp nháy hide |
| Có sight / mất sight / có lại | Không đổi nguồn hoặc làm mất slot ngoài ý muốn |
| Phòng tập và trận 5v5, tối đa 5 địch | Chi phí thật, camp/roster đầy đủ |
| Qua mép màn hình, chết/hồi sinh | Identity layer, projection reject và recovery |
| Ra nền/vào lại, hết trận/vào trận mới, restart game | Mapping lifetime, epoch và attach backoff |

Mỗi bài steady-state nên có đoạn di chuyển đủ dài để p99 có ý nghĩa; lưu duration/sample count. So timing off và timing-only để đo overhead logging. Video giúp đối chiếu icon với nhân vật, nhưng log phải giải thích được vị trí raw có đổi hay không.

Ngân sách callback dựa vào nhịp thực đo: 60 Hz khoảng 16,67 ms, 120 Hz khoảng 8,33 ms; overlay chỉ được chiếm một phần, không dùng hết ngân sách. Báo p99 và số miss, không chỉ average FPS.

## 11. Tiêu chí hoàn thành và cách bàn giao

- Chứng minh đường steady-state không scan/map/kernel read trong display callback.
- Tuổi position tại projection giảm sau B; callback p99 và miss không tệ hơn baseline.
- Không dùng epoch cũ sau reset, không đọc span đã unmap, không nháy do layer đổi slot hoặc camera recovery sai.
- Xác nhận đủ roster/camp ở trận người; vị trí vẫn lấy LActorRoot._location.
- Icon không còn các bước nhảy dư do reader/display; nếu raw vẫn đổi theo bậc, chỉ rõ bằng log thay vì hứa mượt tuyệt đối.
- Không đưa nội suy/Transform vào dưới tên “tối ưu”.
- Handoff gồm diff theo từng bước, log A/B, kết quả thiết bị, rủi ro còn lại và lệnh build đúng.

Nếu raw cadence là giới hạn còn lại sau khi sample age và display cadence đã tốt, báo rõ: phần mềm đã giảm độ trễ nhưng không thể tạo vị trí trung gian chưa có trong _location. Đổi nguồn visual là quyết định phạm vi khác, không tự thực hiện trong plan này.

## 12. Trình tự triển khai cho Sol

1. Đọc các hàm mục 3 và đường bone/camera PUBG mục 2; giữ baseline build. LQVIP chỉ tra khi cần xác minh actor identity/discovery.
2. Thêm instrumentation mục 5, lấy trace có chuyển động và pan camera.
3. Sửa lifetime/epoch tối thiểu cần thiết; triển khai A/B raw sampler mục 6.
4. Tùy trace, sửa cadence hoặc camera coherence mục 7.
5. Dọn per-frame overhead/slot ảnh mục 8, đo lại một lần có ý nghĩa.
6. Kiểm tra chuyển trạng thái mục 9–10, build và bàn giao kết quả.

Không kết luận chỉ từ log 9, không bắt đầu bằng refactor toàn bộ lifecycle, không đánh đồng CPU thấp với icon bám mượt.
