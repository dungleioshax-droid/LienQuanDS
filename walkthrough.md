# Báo cáo: Khắc phục lỗi Icon Menu không tự động xoay ngang khi vào game

## 1. Vấn đề người dùng phản hồi
- Khi người dùng khởi chạy game PUBG Mobile (game chạy ở màn hình ngang - landscape), icon menu nổi và cửa sổ menu của DarkPubg không tự động xoay ngang đồng thời cùng game như trước đây.

---

## 2. Nguyên nhân cốt lõi (Root Causes)

1. **Khóa luồng điều kiện kiểm tra góc xoay (`Early Return`) trong `ds_hosted_apply_orientation`**:
   - Trước đây trong [DSBridgeESP.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgeESP.inc.mm#L2141):
     ```objc
     if (!g_hostedLayer || (int)orientation == g_hostedLastOrientation) return;
     ```
   - Đoạn code trên dùng chung `g_hostedLastOrientation` cho cả lớp ESP (`g_hostedLayer`) và cửa sổ menu (`g_hostedMenuViewController`). Nếu `g_hostedLastOrientation` đã mang giá trị góc xoay trước đó hoặc `g_hostedLayer` chưa sẵn sàng, hàm trả về ngay lập tức (`return`), khiến cho lệnh `[g_hostedMenuViewController dsApplyOrientation]` không bao giờ được gọi.

2. **`FBSOrientationObserver` không đẩy sự kiện cập nhật tới Menu**:
   - Trong [DSBridge.mm](file:///home/dungle/DarkPubg/darksword/DSBridge.mm#L1515), khi nhận sự kiện xoay từ FrontBoard (`FBSOrientationUpdate`), observer chỉ lưu giá trị vào biến nguyên tử `g_activeOrientation.store((int)update.orientation)` mà không gọi ngay `ds_hosted_apply_orientation(ori, duration)`.

3. **Thiếu cơ chế fallback phát hiện game ngang khi vừa chuyển ứng dụng**:
   - Khi chuyển từ SpringBoard (dọc) vào PUBG Mobile, trước khi FrontBoard kịp gửi thông báo cập nhật, `ds_active_orientation()` trả về mặc định `UIInterfaceOrientationPortrait`.

---

## 3. Các giải pháp đã triển khai

1. **Tách biệt độc lập luồng xoay của ESP Layer và Floating Menu**:
   - Trong [DSBridgeESP.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgeESP.inc.mm#L2164), tách riêng việc cập nhật góc xoay của `g_hostedLayer` và `g_hostedMenuViewController`. Bất kể layer ESP có thay đổi hay không, menu view controller vẫn luôn nhận được lệnh xoay:
     ```objc
     // 2. Floating Menu View Controller
     if (g_hostedMenuViewController) {
         [g_hostedMenuViewController dsApplyOrientation:orientation duration:duration];
     }
     ```

2. **Kích hoạt xoay ngay lập tức trong `FBSOrientationObserver`**:
   - Trong [DSBridge.mm](file:///home/dungle/DarkPubg/darksword/DSBridge.mm#L1528), ngay khi FrontBoard báo góc xoay của game thay đổi, hàm lập tức dispatch về Main Queue gọi `ds_hosted_apply_orientation(ori, duration)` để xoay menu mượt mà theo đúng thời gian chuyển cảnh (`duration`).

3. **Fallback tự động nhận diện game PUBG Mobile**:
   - Trong [DSBridge.mm](file:///home/dungle/DarkPubg/darksword/DSBridge.mm#L819), khi `ds_pubg_has_render_source()` phát hiện tiến trình game PUBG đang kết nối và vẽ, hệ thống tự động xác định góc xoay là `UIInterfaceOrientationLandscapeRight`.

4. **Bổ sung lắng nghe xoay thiết bị vật lý**:
   - Đăng ký observer `UIDeviceOrientationDidChangeNotification` để khi người dùng cầm nghiêng máy, menu tự nhận diện và căn chỉnh chuẩn xác theo tư thế cầm máy.

5. **Hiệu ứng xoay mượt mà (`UIView Animation`) cho Menu Icon & Panel**:
   - Trong `dsApplyOrientation:duration:`, áp dụng `UIViewAnimationOptionCurveEaseInOut` kết hợp cập nhật lại toạ độ neo (`_buttonAnchorUnit`) theo kích thước màn hình ngang.

---

## 4. Kết quả build Menu Xoay Ngang
- **Commit**: `2c648b8` (`fix(menu): synchronize menu icon orientation transition with game launch and device rotation`).
- **GitHub Actions Run**: [Workflow Run 43416716821](https://github.com/dungleioshax-droid/LienQuanDS/actions/runs/43416716821) — Kết quả: **Success**.

---

## 5. Chuyển đổi hiển thị tổng địch (Player/Bot Count) từ ImGui sang UIKit

### Yêu cầu chuyển đổi:
Đoạn mã ImGui gốc từ người dùng:
```cpp
sprintf(extra, "PLAYER AROUNO[ %d ]", totalEnemies);
ImGui::GetForegroundDrawList()->AddText(NULL ,25,{580,66}, 红色, extra);
sprintf(extra, "BOT AROUNO[ %d ]", totalBots);
ImGui::GetForegroundDrawList()->AddText(NULL ,25,{glWidth / 2,66}, 红色, extra);
```

### Triển khai UIKit & CoreAnimation (Trong [DSBridgeESP.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgeESP.inc.mm#L2881-L2905)):
1. **Lớp hiển thị đồ họa thuần túy (`CATextLayer`)**:
   - Tận dụng `g_hostedPUBGTopCountLabel` được quản lý bởi `CALayer` phân cấp của SpringBoard, đảm bảo không có rủi ro về overhead hay xung đột luồng OpenGL/Metal của ImGui.
2. **Định dạng nhãn và màu sắc**:
   - Chuỗi ký tự chuẩn: `[NSString stringWithFormat:@"PLAYER AROUNO[ %d ]   BOT AROUNO[ %d ]", totalEnemies, totalBots]`.
   - Font chữ: Monospaced số học kích thước 16.0 pt (`UIFontWeightHeavy`), tương thích hoàn hảo tỉ lệ màn hình iOS landscape.
   - Màu chữ đỏ nổi bật: `[UIColor colorWithRed:255.0/255.0 green:59.0/255.0 blue:48.0/255.0 alpha:1.0]`.
   - Đổ bóng màu đen tương phản (`shadowColor = black`, `shadowRadius = 1.5`, `shadowOpacity = 1.0`), giúp đọc thông tin dễ dàng trên mọi địa hình bản đồ trong game.
3. **Căn lề chuẩn xác theo mọi kích thước màn hình**:
   - Tọa độ Y: `lblY = 14.0f` nằm ngay dưới Dynamic Island/Notch ở mép trên màn hình.
   - Chiều rộng `lblW = 440.0f`, tự động căn giữa ngang qua `lblX = (width - lblW) * 0.5f`.
4. **Đồng bộ hóa với vòng lặp tick dữ liệu**:
   - Số lượng `totalEnemies` và `totalBots` được trích xuất an toàn từ `ds_pubg_get_total_counts(&totalEnemies, &totalBots)` với khóa bộ nhớ `os_unfair_lock`.

---

## 6. Kết quả Build nhãn đếm người chơi & bot
- **Commit**: `71e260b` (`feat(esp): format top count label as PLAYER AROUNO and BOT AROUNO in red`).
- **GitHub Actions Run**: [Workflow Run 43450935854](https://github.com/dungleioshax-droid/LienQuanDS/actions/runs/43450935854) — Kết quả: **Success**.

---

## 7. Khắc phục lỗi không phân biệt được Địch/Bot & Hiển thị Quốc Tịch (Player Flag)

### A. Vấn đề phát hiện qua ảnh thực tế của người dùng:
1. **Toàn bộ hiển thị là địch, Bot luôn bằng 0 (`BOT AROUND [0]`)**:
   - Khi vào trận, cả bot và người chơi thật đều bị đếm vào `PLAYER AROUND` (ví dụ `PLAYER AROUND [4]  BOT AROUND [0]`).
   - Tên bot như `nmichu06`, `isaacpt` bị hiển thị như người chơi thật thay vì badge `BOT`.
   - **Nguyên nhân cốt lõi**: Trong phiên bản game mới, Tencent triển khai MLAI (Machine Learning AI / Smart Bots) khiến cờ đơn lẻ `bIsAI` (offset `0xA50`) không phản ánh đủ các dạng bot (`bIsMLAI` tại `0xA51`, `bIsAIWithPet` tại `0xA52`, `MLAIDisplayUID` tại `0x6D0`, hoặc các bot không cấp phát `PlayerState`).
2. **Quốc tịch / Quốc kỳ không hoạt động**:
   - Menu có nút bật/tắt `g_pubgEspFlag` ("QUỐC KỲ" / "PLAYER FLAG") nhưng mã render ESP hoàn toàn chưa đọc trường `Nation` và chưa có logic vẽ cờ.

---

### B. Giải pháp triển khai:

1. **Nhận diện Bot đa tầng (Multi-Factor Bot Detection) trong [DSBridgePUBG.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgePUBG.inc.mm#L3270-L3345)**:
   - **Tầng 1 (Character AI Flags)**: Quét toàn bộ họ cờ AI trên `UAECharacter`: `bIsAI` (0xA50), `bIsMLAI` (0xA51), `bIsAIWithPet` (0xA52), cùng tương thích ngược phiên bản cũ (0xA40, 0xA41).
   - **Tầng 2 (PlayerState Flags)**: Kiểm tra `bIsABot` (`ps + 0x4DC & 0x4`) và `MLAIDisplayUID` (`ps + 0x6D0`).
   - **Tầng 3 (AI Controller on Client)**: Trên máy khách, người chơi thật điều khiển từ xa không bao giờ có `Controller` (`pawn + 0x4E8 == 0`). Nếu `pawn` có `Controller` chứa `"AI"` hoặc `"Fake"`, khẳng định 100% là Bot.
   - **Tầng 4 (Real Player Verification)**: Người chơi thật trực tuyến luôn sở hữu `PlayerState`, `PlayerUID` (mã tài khoản 7-11 số) và/hoặc `Nation` (mã quốc gia 2 ký tự). Bất kỳ pawn nào không có cả `PlayerState`, không có `PlayerUID`, không có `Nation` đều được định danh chính xác là Bot.

2. **Đọc dữ liệu Quốc tịch (`Nation`)**:
   - Thêm trường `char nation[16];` vào `DSPUBGProjectedPlayer` trong [DSBridge.mm](file:///home/dungle/DarkPubg/darksword/DSBridge.mm#L916-L920).
   - Đọc trường `FString Nation` từ `UAECharacter + 0x970ULL` và fallback từ `AUAEPlayerState + 0x6F0ULL` bằng hàm chuyển đổi UTF-16 sang UTF-8 `ds_pubg_read_fstring_nation`.

3. **Chuyển đổi mã quốc gia sang Emoji Quốc kỳ chuẩn Apple Color Emoji trong [DSBridgeESP.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgeESP.inc.mm#L1327-L1340)**:
   - Sử dụng thuật toán Unicode chuẩn Regional Indicator Symbol (`0x1F1E6 + (char - 'A')`) thông qua cặp surrogate pair UTF-16 (`0xD83C`, `0xDDE6 + (c - 'A')`).
   - Ví dụ: `"VN"` -> `🇻🇳`, `"TH"` -> `🇹🇭`, `"US"` -> `🇺🇸`, `"ID"` -> `🇮🇩`, `"CN"` -> `🇨🇳`...
   - Tự động hiển thị cờ màu sống động phía trước tên người chơi: `🇻🇳 DũngLê`.
   - Đối với Bot, nhãn hiển thị chính xác chữ `BOT`.
   - Tự động mở rộng kích thước badge (`headerW = 92.0f`) khi bật cờ để bố cục thông tin cân đối, đẹp mắt.

---

## 8. Kết quả Build & Sản phẩm xuất bản (Đợt trước)

- **Commit**: `0796cd6` (`fix(esp): multi-factor bot detection and player nationality flag rendering`).
- **GitHub Actions Run**: [Workflow Run 43563918068](https://github.com/dungleioshax-droid/LienQuanDS/actions/runs/43563918068) — Kết quả: **Success**.

---

## 9. Khắc phục lỗi ESP không hiện lên màn hình dù đếm đúng tổng địch

### A. Vấn đề người dùng phản hồi:
- Khi vào trận, dòng chữ đếm trên đỉnh màn hình `PLAYER AROUND [x]  BOT AROUND [y]` đếm hoàn toàn chính xác số lượng địch và bot.
- Tuy nhiên, trên màn hình lại **hoàn toàn không hiển thị bất kỳ khung hộp (Box), khung xương (Skeleton), đường kẻ (Line), thanh máu hay thông tin người chơi** nào.

### B. Nguyên nhân cốt lõi (Root Causes):
1. **Lỗi ngắt sớm (`Early Skip / continue`) trong vòng lặp render `ds_hosted_apply_pubg`**:
   - Trong [DSBridgeESP.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgeESP.inc.mm#L1217-L1262), điều kiện `if (!p.isVisible || outsideBounds)` bị chèn khối kiểm tra Arrow 360 với lệnh `continue;`.
   - Khi địch được chiếu lên màn hình nhưng cờ `p.isVisible` bị đánh dấu sai hoặc trùng lặp, khối này ẩn toàn bộ các layer hiển thị (`box.hidden = YES; skel.hidden = YES; line.hidden = YES; info.hidden = YES; hpBar.hidden = YES; wLabel.hidden = YES;`) rồi gọi `continue;`, khiến mã vẽ chi tiết ở phần dưới hàm không bao giờ được chạm tới.
2. **Nhầm lẫn giữa cờ ẩn sau tường (`isOccluded`) và cờ hiển thị trong góc nhìn (`isVisible`)**:
   - Trong [DSBridgePUBG.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgePUBG.inc.mm#L3427), hàm kiểm tra che khuất (occlusion) bằng timestamp render của Unreal Engine ghi đè trực tiếp lên `p.isVisible`: `p.isVisible = (fabsf(lastSubmit - lastRender) <= 0.06f);`.
   - Vốn dĩ ESP là công cụ để nhìn xuyên tường (Wallhack): khi địch đứng sau vật cản, họ phải được vẽ bằng **màu đỏ**, còn khi nhìn thấy trực tiếp thì vẽ bằng **màu xanh lá**. Việc ghi đè `p.isVisible = false` đã biến mọi địch đứng sau tường thành "ngoài màn hình", khiến hệ thống ẩn sạch toàn bộ layer.
3. **Bộ lọc Bot tĩnh (`g_pubgEspBot`)**:
   - Biến `g_pubgEspBot` không có nút bật/tắt trên Menu UI nhưng vẫn bị kiểm tra `if (ai && !g_pubgEspBot) continue;`. Nếu NSUserDefaults lưu giá trị 0, toàn bộ bot sẽ bị ẩn.
4. **Vùng giới hạn chiếu hình (`Bounding Check`) quá hẹp**:
   - Trong [DSBridgePUBG.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgePUBG.inc.mm#L3373), điều kiện `centerX - boxW * 0.5f <= screenW` sử dụng độ phân giải mặc định mà không có biên đệm dự phòng cho người chơi đang di chuyển từ mép màn hình vào.

### C. Các giải pháp đã triển khai:
1. **Tách biệt độc lập cờ `isOccluded` và `isVisible`**:
   - Trong [DSBridge.mm](file:///home/dungle/DarkPubg/darksword/DSBridge.mm#L880-L882): Thêm trường `bool isOccluded;` vào cấu trúc `DSPUBGProjectedPlayer`.
   - Trong [DSBridgePUBG.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgePUBG.inc.mm#L3410-L3431): Cập nhật riêng `p.isOccluded = !(renderedThisFrame && drawnOnScreen);`. Biến `p.isVisible = true;` luôn giữ nguyên khi mục tiêu nằm trong góc nhìn phía trước camera.
   - Trong [DSBridgeESP.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgeESP.inc.mm#L1353): Dùng `isOccluded` thuần túy để chọn màu sắc (`Xanh` khi nhìn thấy, `Đỏ` khi sau vật cản/gục), tuyệt đối không ẩn layer.
2. **Tái cấu trúc rành mạch vòng lặp On-Screen vs Off-Screen**:
   - Định nghĩa cờ chuẩn xác: `const BOOL isOffScreen = (!p.isVisible || outsideBounds || p.boxWidth <= 0.0f || p.boxHeight <= 0.0f);`.
   - Nếu `isOffScreen == true`: Ẩn layer on-screen, vẽ mũi tên chỉ hướng 3D ở viền màn hình (`Boundary Arrow`) nếu bật tính năng, sau đó kết thúc vòng lặp bằng `continue;`.
   - Nếu `isOffScreen == false` (mục tiêu trên màn hình):
     - Vẽ đầy đủ Hộp 3D / 2D (`box`).
     - Vẽ Khung xương 16 khớp + vòng tròn đầu (`skel`).
     - Vẽ Đường kẻ Snapline (`line`).
     - Vẽ Badge thông tin Người chơi/BOT + Quốc kỳ (`info`).
     - Vẽ Thanh máu 3 vạch liền kề bo góc chuẩn MADNESS (`hpBg`, `hpBar`).
     - Vẽ Khoảng cách & Team ID (`wLabel`).
     - Vẽ Tam giác xanh AI Mark (`aiMark`).
     - Vẽ Vòng xoay tam giác đỏ rỗng 360° quanh chân mục tiêu (`Arrow 360`) khi bật menu ARROW.
3. **Mở rộng biên chiếu hình màn hình**:
   - Cho phép biên độ `-150.0f` tới `screenW + 150.0f` để đối tượng vừa bước vào mép màn hình được vẽ mượt mà, không bị chớp nháy (pop-in).
4. **Bảo đảm cờ hiển thị Bot luôn bật**:
   - Ép buộc `g_pubgEspBot = YES;` trong `MadnessMenuView.m` để tránh bị NSUserDefaults cũ làm ẩn bot.

---

## 10. Kết quả Build & File IPA Hoàn Thiện (Bản trước)

- **Commit**: `6f487d3` (`fix(esp): restore on-screen player rendering, fix bot visibility filter, and loosen screen projection bounds`).
- **GitHub Actions Run**: [Workflow Run 43592886930](https://github.com/dungleioshax-droid/LienQuanDS/actions/runs/43592886930) — Kết quả: **Success**.

---

## 11. Khắc phục sự hiểu nhầm về "Mũi tên 360 xoay vòng vòng"

### A. Vấn đề người dùng phản hồi:
- *"Sao mũi tên 360 nó xoay vòng vòng kiểu gì vậy bạn sao nó không thay thế cái cũ mà vẫn hiện cái cũ thế kia"*

### B. Nguyên nhân và sự nhầm lẫn trong code:
1. **Nguồn gốc nhầm lẫn trong commit `63056dc`**:
   - Ở bản trước, commit `63056dc` đã hiểu sai từ khóa "Mũi tên 360" và tự ý tạo hàm `ds_pubg_apply_arrow360`: vẽ một chùm 5 mũi tên tam giác màu đỏ xoay tít 360 độ liên tục như chong chóng dưới chân địch ở cự ly gần trên màn hình.
   - Trong khi đó, tính năng mũi tên mà người dùng cần (từ yêu cầu ban đầu) là **mũi tên cảnh báo ở viền màn hình** (chỉ hướng 360 độ cho địch ở sau lưng/ngoài tầm nhìn 180° kèm số mét, ví dụ `◀ 87m`).
2. **Hệ quả nhìn thấy trong game**:
   - Dưới chân địch trên màn hình thì xuất hiện một vòng mũi tên xoay tròn quái dị ("xoay vòng vòng kiểu gì vậy").
   - Ở mép viền màn hình thì mũi tên chỉ hướng cũ màu vàng (`◀ 87m`) vẫn xuất hiện song song mà không được thay thế ("sao nó không thay thế cái cũ mà vẫn hiện cái cũ thế kia").

### C. Giải pháp xử lý triệt để:
1. **Xóa bỏ hoàn toàn hiệu ứng xoay tròn quanh chân địch**:
   - Xóa bỏ toàn bộ cụm hàm và thông số `ds_pubg_apply_arrow360`, `ds_pubg_arrow360_path`, `ds_pubg_arrow360_phase` trong [DSBridgeESP.inc.mm](file:///home/dungle/DarkPubg/darksword/DSBridgeESP.inc.mm).
   - Với người chơi đã nằm trong khung hình (On-Screen): Ẩn hoàn toàn các layer mũi tên (`arrow.hidden = YES; arrowText.hidden = YES;`), chỉ hiển thị các layer chuẩn gồm Hộp 3D/2D, Khung xương, Thanh máu 3 vạch, Snapline, Badge tên/BOT, Quốc kỳ.
2. **Khôi phục nút menu và vai trò chuẩn xác của Mũi Tên viền màn hình**:
   - Trong [MadnessMenuView.m](file:///home/dungle/DarkPubg/darksword/MadnessMenu/MadnessMenuView.m#L495-L517): Đổi lại tên nút chuẩn: Tiếng Việt là `MŨI TÊN`, Tiếng Anh là `DRAW ARROW`.
   - Nút này điều khiển chuyên biệt cho việc hiển thị mũi tên chỉ hướng ở mép viền màn hình (kèm số mét) khi có địch ở sau lưng hoặc ngoài góc nhìn camera.

---

## 12. Kết quả Build & File IPA Mới Nhất

- **Commit**: `fdc60fe` (`fix(esp): remove unwanted target swirl animation and restore off-screen arrow toggle`).
- **GitHub Actions Run**: [Workflow Run 43595105586](https://github.com/dungleioshax-droid/LienQuanDS/actions/runs/43595105586).
- **File IPA hoàn thiện**: [DarkPubg_1.0-1.ipa](file:///home/dungle/DarkPubg/packages/DarkPubg_1.0-1.ipa).
