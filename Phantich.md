# Phân tích KGVN ANOGS/ANORT và đối chiếu project DarkPubg

Ngày kiểm tra: 2026-09-19

## 1. Kết luận nhanh

1. ANOGS có anti-debug thực tế:
   - Dùng `sysctl(KERN_PROC_PID)` để đọc `P_TRACED` của chính game.
   - Gọi trực tiếp syscall `ptrace(PT_DENY_ATTACH)` mà không import symbol `_ptrace`.
2. `task_get_special_port` trong ANOGS không phải bằng chứng detect task port ngoài:
   - Call-site dùng `mach_task_self()`.
   - Selector là `4`, tức `TASK_BOOTSTRAP_PORT`.
3. Tất cả direct call `vm_read`/`vm_write` đã kiểm tra trong ANOGS và ANORT đều thao tác trên `mach_task_self()`.
   - Chưa có bằng chứng chúng dùng các call này để theo dõi một process khác đang đọc/ghi game.
   - ANOGS có quét VM map của chính game, nhưng các call-site hiện tại chỉ dùng địa chỉ, kích thước, protection, path và một số thuộc tính basic của region.
   - Các call `mach_vm_region_recurse`/`vm_region_recurse_64` không sử dụng `ref_count` hoặc `share_mode` mà kernel trả về.
4. Project DarkPubg hiện tại không dùng `task_for_pid`, `vm_read`, `vm_write`, `mach_vm_read` hay `mach_vm_write` để attach `kgvn`.
   - Project lấy kernel read/write primitive.
   - Tìm `proc` của `kgvn`, lấy `task -> vm_map` trong kernel.
   - Tạo local alias tới các page của game và đọc/ghi qua `memcpy`.
5. Các entitlement `com.apple.system-task-ports`, `task_for_pid-allow`, `get-task-allow`, `platform-application`, `com.apple.private.security.no-sandbox` và `run-unsigned-code` đã được loại khỏi file cấu hình vì không thuộc luồng hoạt động của project hiện tại.
   - `DarkPubg.xcarchive` và IPA hiện tại đều unsigned.
   - Không có entitlement blob và không có `embedded.mobileprovision`.
   - Archive/IPA cũ không được build lại trong lần rà soát này; trạng thái unsigned của chúng không thay đổi.
6. Có rủi ro liên quan trực tiếp đến project, nhưng không phải do task port:
   - ANOGS có code liệt kê process.
   - DarkPubg chạy nền bằng audio và có tên process/bundle rõ ràng.
   - Project đọc memory `kgvn` bằng page alias.
   - Tính năng camera zoom có ghi vào memory game khi được bật.
   - Project chạy kernel exploit và sửa kernel object/refcount để tạo mapping.
7. Với riêng dấu vết VM do page alias tạo ra:
   - Project không sửa `vm_map_entry` của game.
   - Project chắc chắn tăng `vm_object.ref_count` của page target và sửa backing entry tạm thuộc phía DarkPubg.
   - ANOGS hiện có API đủ để hỏi metadata object, nhưng các direct call-site đã truy không đọc `ref_count`/`share_mode`.
   - Vì vậy chưa có đường detect trực tiếp đã xác nhận cho alias read-only này trong binary đang phân tích.

Kết luận tổng quát:

> Chưa có bằng chứng trong các binary này cho thấy ANOGS detect mọi external read/write hoặc detect riêng cơ chế shared-page của DarkPubg. Tuy nhiên ANOGS chắc chắn có anti-debug, process enumeration và jailbreak-related logic. Project không bị ràng buộc bởi `PT_DENY_ATTACH` vì nó không attach bằng debugger/task port, nhưng vẫn có bề mặt bị phát hiện ở process identity, môi trường jailbreak/kernel exploit, memory mutation và game-state integrity.

---

## 2. Phạm vi và nguồn dữ liệu

### 2.1. KGVNFramework

Ba binary được phân tích call-site chi tiết:

| Binary | Kiến trúc | SHA-256 |
|---|---|---|
| `KGVNFramework/anogs.framework/anogs` | arm64 | `bde3bf2f8fe2f80c70d4d81092ec554ea53f0d88b4baad7d268aa479eba626c1` |
| `KGVNFramework/anort.framework/anort` | arm64 | `6c3ee70af0c0d8d5907781ae46c4b5d1b247047fb5d99dda49e5d2f58650cb08` |
| `KGVNFramework/UnityFramework.framework/UnityFramework` | arm64 | `a0d5683d53f3c616dadbf12769101d20ff634ab13bc9e4afe2b1eb1bebdaff22` |

Toàn bộ Mach-O trong `KGVNFramework/` cũng được quét import để tìm các API task, Mach VM, process và debug liên quan.

Quan hệ load đáng chú ý:

- `UnityFramework` link tới cả `anogs.framework/anogs` và `anort.framework/anort`.
- `anort` link tới `anogs`.

### 2.2. Project DarkPubg

Đã kiểm tra:

- `supports/entitlements-darksword.plist`
- `supports/darksword.xcconfig`
- `DarkPubg.xcodeproj/project.pbxproj`
- `Resources/Info.plist`
- Source trong `darksword/`, `sources/` và `Vendor/darksword-kexploit/`
- `DarkPubg.xcarchive/Products/Applications/DarkPubg.app`
- `packages/DarkPubg_1.0-1.ipa`

Executable trong archive và IPA có cùng SHA-256:

`9a11e09a6847e52f3682173d8cba1928d89d26935e2dd21c566bba8569d29459`

---

## 3. Cách đọc kết quả

Tài liệu phân biệt bốn mức bằng chứng:

| Mức | Ý nghĩa |
|---|---|
| Import | Binary có tham chiếu dynamic symbol. Chưa tự động chứng minh mục đích anti-cheat. |
| Direct call-site | Có lệnh gọi cụ thể và có thể truy vết tham số trực tiếp. |
| Chuỗi/symbol | Chỉ là dấu vết. Có thể đến từ SDK khác hoặc là false positive. |
| Runtime/server | Chỉ xác nhận được khi trace trên máy thật hoặc có telemetry server. Không thể kết luận từ static binary. |

Một import API không tự động có nghĩa là API đó đang detect hành vi từ process khác. Ví dụ, `vm_read(mach_task_self(), ...)` là một thao tác đọc của chính process, không phải notification khi process ngoài đọc nó.

---

## 4. ANOGS: import và direct call

### 4.1. Import liên quan

ANOGS import trực tiếp:

| Nhóm | API |
|---|---|
| Task/process | `task_get_special_port`, `task_info`, `pid_for_task`, `getpid`, `proc_regionfilename` |
| Mach VM | `mach_vm_region_recurse`, `mach_vm_remap` |
| Legacy VM | `vm_read`, `vm_write`, `vm_copy`, `vm_protect`, `vm_region_64`, `vm_region_recurse_64`, `vm_remap`, `vm_deallocate` |
| System/process info | `sysctl`, `sysctlbyname` |
| Dynamic resolution | `dlopen`, `dlsym` |

Không có direct import:

- `task_for_pid`
- `mach_vm_read`
- `mach_vm_write`
- `ptrace`

Lưu ý: không import `_ptrace` không có nghĩa là không dùng ptrace. ANOGS gọi ptrace bằng syscall trực tiếp, được phân tích ở mục 4.5.

### 4.2. `task_get_special_port`

Chỉ có một direct call, tại virtual address `0x139c68`:

```c
task_get_special_port(mach_task_self(), 4, &port);
```

Theo header Mach của SDK:

```c
#define TASK_BOOTSTRAP_PORT 4
```

Điều đã xác nhận:

- Task là current task (`mach_task_self()`).
- Port là bootstrap port.
- Port sau đó được đưa cho callback nội bộ và được deallocate.

Điều không thể suy ra từ call này:

- Detect process khác đang giữ task port của game.
- Detect `task_for_pid`.
- Detect external memory reader.
- Ban người chơi vì task port.

### 4.3. `vm_read`

ANOGS có 7 direct call `vm_read`:

| Address | Task argument | Ghi chú |
|---|---|---|
| `0x0d993c` | `mach_task_self()` | Helper kiểm tra một range có đọc được hay không. |
| `0x0d9a08` | `mach_task_self()` | Đọc page và so sánh Mach-O magic `0xFEEDFACF`. |
| `0x16f564` | `mach_task_self()` | Wrapper đọc memory nội bộ. |
| `0x16f618` | `mach_task_self()` | Wrapper đọc memory nội bộ. |
| `0x171dcc` | `mach_task_self()` | Helper probe/read range. |
| `0x229f10` | `mach_task_self()` | Helper đọc và deallocate buffer. |
| `0x22a278` | `mach_task_self()` | Đọc từng page khi duyệt memory range. |

Kết luận:

> Tất cả direct call `vm_read` đã tìm thấy trong ANOGS đều đọc chính address space của ANOGS/game process. Không có call trực tiếp nào trong danh sách này đọc task của DarkPubg hoặc một external process.

Điều này không loại trừ khả năng có code ẩn qua `dlsym`, code obfuscated hoặc server-side logic, nhưng import `vm_read` hiện tại không phải bằng chứng detect external read.

### 4.4. `vm_write`

ANOGS có một direct call `vm_write`, tại `0x16fad0`.

Data flow của wrapper bắt đầu tại `0x16f914` cho thấy:

1. Lấy `mach_task_self()`.
2. Kiểm tra region bằng `vm_region_64`.
3. Nếu cần, đổi protection bằng `vm_protect`.
4. Gọi `vm_write(mach_task_self(), address, data, length)`.
5. Khôi phục protection.

Wrapper này có nhiều call-site nội bộ. Nó là helper patch/write memory của chính process.

Kết luận:

> Direct call `vm_write` đã xác nhận không theo dõi external writer. Nó chủ động ghi memory của chính process.

### 4.5. Quét VM map: có quét, nhưng chưa khớp dấu vết alias của project

ANOGS thực sự duyệt VM map của chính process. Đây là phần cần phân biệt rõ với việc "detect process ngoài đang map page của game".

#### `mach_vm_region_recurse`

Có hai direct call:

| Address | Task | Dữ liệu thực sự được dùng |
|---|---|---|
| `0x22aee8` | `mach_task_self()` | Address, size và path từ `proc_regionfilename`; dùng để tìm region chứa một address. |
| `0x23b164` | `mach_task_self()` | Address, size, path và `protection`; dùng để tạo inventory VM map. |

Cả hai truyền count `0x13`, nên kernel có thể trả `vm_region_submap_info_64`, trong đó có `ref_count` và `share_mode`. Tuy nhiên data flow của hai hàm không đọc hai trường này:

- Hàm `0x22ae40` không đọc field nào từ info buffer.
- Hàm quanh `0x23b0d0` chỉ load field đầu tiên là `protection`; sau đó pack page count, protection bits và thông tin path.

#### `vm_region_recurse_64`

ANOGS có hai direct call, đều dùng `mach_task_self()`:

- `0x16f8e0`: chỉ trả về `protection & 7` và region size cho caller.
- `0x1ef948`: chỉ dùng address/size để duyệt ranh giới region; không đọc object metadata.

#### `vm_region_64`

Các direct call đều dùng flavor `9`, tức `VM_REGION_BASIC_INFO_64`, và đều query current task. Flavor này trả các field basic gồm protection, max protection, inheritance, `shared`, reserved, offset và behavior; nó không trả `vm_object.ref_count` hay `share_mode`.

Một số helper tại `0x8bd38`, vùng `0x195af4` và `0x196658` có so sánh năm field đầu, bao gồm `shared`, để phân nhóm/duyệt các region liền kề. Đây là sử dụng thực của field `shared`, nhưng chưa phải rule báo "external alias".

Điểm quan trọng khi đối chiếu với project:

- XNU lấy `VM_REGION_BASIC_INFO_64.shared` từ bit `is_shared` của chính `vm_map_entry` đang được query.
- Project chỉ đọc target `vm_map_entry` để lấy `vm_object`; không ghi đè entry của game.
- Project ghi đè backing entry tạm được tạo trong DarkPubg và tăng `vm_object.ref_count` của target.
- Do đó bit `shared` mà ANOGS đọc từ VM entry của game không bị cơ chế hiện tại đổi trực tiếp.

Đối chiếu [implementation XNU công khai](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/vm/vm_map.c#L15689-L15734): nhánh `VM_REGION_BASIC_INFO_64` gán `basic->shared = entry->is_shared`. Trong project, kernel write refcount nằm tại `Vendor/darksword-kexploit/TaskRop/vm.m:286`, còn write entry nằm tại `vm.m:297` và target entry chỉ được re-read/validate tại `vm.m:264-276`.

Hai remap helper của ANOGS cũng không phải external-task monitor:

- `vm_remap` tại `0x16f848` remap current task sang current task.
- `mach_vm_remap` tại `0x23e4cc` cũng dùng current task cho cả source và destination, trong một helper patch/copy nội bộ.

Kết luận của phần VM:

> ANOGS có inventory và validation VM map thật. Nhưng trong phiên bản binary này, direct data flow chưa cho thấy nó tiêu thụ `vm_object.ref_count`/`share_mode`, và basic `shared` của entry game không bị project sửa. Vì vậy chưa có bằng chứng static rằng các VM check đã thấy đúng dấu vết page alias read-only của DarkPubg.

Điều này không phải bảo đảm runtime: code resolve gián tiếp, logic obfuscated, detector kernel-level hoặc bản ANOGS khác vẫn có thể kiểm tra thêm metadata.

### 4.6. Anti-debug đã xác nhận

#### Kiểm tra `P_TRACED`

Hàm tại `0x3ab5c` tạo MIB:

```c
int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
sysctl(mib, 4, &info, &size, NULL, 0);
return (info.kp_proc.p_flag & P_TRACED) != 0;
```

Giá trị đã đối chiếu với SDK:

- `CTL_KERN = 1`
- `KERN_PROC = 14`
- `KERN_PROC_PID = 1`
- `P_TRACED = 0x800`

Đây là check debugger thực tế, không còn ở mức "có thể".

#### `ptrace(PT_DENY_ATTACH)` không qua import

Tại `0x3ac08`:

```asm
mov x0, #31
mov x1, #0
mov x2, #0
mov x3, #0
mov x16, #26
svc #0x80
```

Theo SDK/XNU:

- Syscall `26` là `SYS_ptrace`.
- Request `31` là `PT_DENY_ATTACH`.

Vì gọi syscall trực tiếp nên `_ptrace` không xuất hiện trong import table.

Tác dụng:

- Ngăn debugger attach theo đường ptrace thông thường.
- Có thể phát hiện trạng thái game đang bị trace qua `P_TRACED`.
- Không tự động ngăn được kernel read/write hoặc shared-page alias của project.

### 4.7. Process enumeration

Hàm tại `0x9e620` dùng MIB:

```c
{ CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 }
```

Nó gọi `sysctl` hai lần:

1. Lấy kích thước buffer.
2. Allocate và lấy danh sách process.

Vì vậy có thể xác nhận ANOGS có code lấy process list. Static analysis hiện tại chưa xác định đầy đủ:

- Tiêu chí lọc process.
- Có tìm tên `DarkPubg` hay bundle cụ thể hay không.
- Kết quả có được đưa vào report/ban hay không.

### 4.8. Các `sysctlbyname` khác

Đã thấy các query phục vụ thông tin thiết bị/CPU:

- `hw.machine`
- `hw.cputype`
- `hw.cpusubtype`

Không nên gom mọi `sysctl` thành anti-debug. Trong ANOGS có cả hardware query, process enumeration và debugger check; mỗi call-site có mục đích khác nhau.

### 4.9. Jailbreak và hook-related evidence

ANOGS có các chuỗi/code reference như:

- Cảnh báo thiết bị jailbroken.
- `debugger`, `debugger:%s`, `debugger=%s`.
- `set_inline_hook_error`.
- `ms_set_inlie_hook`.
- `inline_hook_opcode_dismatch`.
- `ms_hook_opcode`.

Đây là dấu vết mạnh cho logic jailbreak/debug/hook, nhưng chưa đủ để nói rõ tất cả rule, report ID hay hình phạt server.

---

## 5. ANORT

ANORT import:

- `vm_read`
- `vm_deallocate`
- `mach_task_self_`
- `dlopen`, `dlsym`

Direct call `vm_read` duy nhất tại `0x2a05c`:

```c
vm_read(mach_task_self(), address, size, &data, &data_count);
```

Sau khi đọc, nó gọi `vm_deallocate` trên current task.

Kết luận:

> ANORT có helper probe/read memory của chính process. Không có direct evidence trong call này về external task port, external read hoặc external write detection.

---

## 6. UnityFramework và false positive cũ

UnityFramework là binary rất lớn, chứa code của Unity và nhiều SDK. Import/chuỗi trong nó không thể mặc định quy cho ANOGS.

### 6.1. Dấu vết thật

UnityFramework có:

- Weak import `sysctl`, `sysctlbyname`, `sysctlnametomib`.
- Weak import `task_get_exception_ports`, `task_set_exception_ports`, `task_swap_exception_ports`, `task_threads`, `task_info`.
- Weak import `vm_read_overwrite`, `vm_protect`, `vm_region_64`, `vm_region_recurse_64`.
- Chuỗi `MobileSubstrate` và các path MobileSubstrate.
- Nhiều chuỗi jailbreak và debugger từ APM, crash reporter, Unity/Mono và SDK khác.

### 6.2. Dấu vết sai trong bản phân tích cũ

Hai kết quả cũ là false positive do search substring không có word boundary và không phân biệt hoa/thường:

| Kết quả cũ | Dữ liệu thực tế |
|---|---|
| `Frida` | Khớp vào chuỗi `Friday`. |
| `ptrace` | Khớp vào `StopTraceRoute`/`stopTraceRoute` ở phần `pTrace`. |

UnityFramework không có direct import `_ptrace` và không có chuỗi độc lập `Frida`/`ptrace` trong kết quả này.

Lưu ý: ANOGS vẫn có ptrace thực, nhưng là direct syscall trong ANOGS, không phải dấu vết chuỗi trong UnityFramework.

---

## 7. Quét toàn bộ KGVNFramework

Ngoài ANOGS/ANORT/UnityFramework, các binary có import liên quan gồm:

| Binary | Import đáng chú ý |
|---|---|
| `CrashSight` | `sysctl`, `sysctlbyname`, `task_info`, `vm_protect`, `vm_read_overwrite`, `vm_region_recurse_64` |
| `AWSCore` | `sysctl` |
| `PixVideoCore` | `sysctl` |
| `IJKMediaDynamic` | `sysctl` |

Những import này thường phục vụ crash reporting, unwind, hardware detection hoặc media runtime. Không được coi là anti-cheat nếu chưa truy call-site.

Đã truy thêm các VM call-site của CrashSight:

- Chúng đều query `mach_task_self()`.
- Code nằm trong các hàm/class crash report như `cs_mach_stack_size`, `CSMemoryData` và `CSDevice processMemoryInfo`.
- Luồng thu thập text/stack memory chỉ kiểm tra protection, address và size; không thấy dùng `ref_count` hoặc `share_mode` làm tín hiệu anti-cheat.

ANORT có một syscall trampoline tổng quát và một `vm_read` self-task. Static data flow của syscall trampoline không cung cấp một syscall cố định để kết luận thêm detector VM.

---

## 8. Audit quyền của project DarkPubg

### 8.1. Phải tách "khai báo" và "có hiệu lực"

Entitlement chỉ có hiệu lực khi nằm trong code signature hợp lệ của executable. Việc có key trong file `.plist` hoặc có `CODE_SIGN_ENTITLEMENTS` trong build setting chỉ là yêu cầu cho bước ký.

Sau khi loại sáu key không dùng, file `supports/entitlements-darksword.plist` còn 58 key active theo cú pháp plist. Build setting và script đều trỏ tới file này.

Tuy nhiên artifact hiện tại cho kết quả:

| Kiểm tra | Kết quả |
|---|---|
| `codesign -d` trên app trong archive | `code object is not signed at all` |
| Entitlement blob trên app | Không có |
| `embedded.mobileprovision` | Không có |
| Signing identity trong archive | Rỗng |
| Team trong archive | Rỗng |
| IPA và archive | Cùng executable hash, đều unsigned |

Do đó:

> Artifact hiện tại không có entitlement nào có hiệu lực. Không thể nói app đang có system task port, task-for-pid, platform status hay no-sandbox chỉ dựa vào file cấu hình.

### 8.2. Sáu entitlement không dùng đã được loại bỏ

Ngày 2026-09-19, những key sau đã được xóa khỏi source plist vì được xác nhận là của cấu hình khác và không hoạt động trong project/runtime hiện tại:

- `com.apple.system-task-ports`
- `task_for_pid-allow`
- `get-task-allow`
- `platform-application`
- `com.apple.private.security.no-sandbox`
- `run-unsigned-code`

Static audit cũng phù hợp với thông tin này:

- Executable DarkPubg không import `task_for_pid`.
- Không import `vm_read`, `vm_write`, `mach_vm_read` hoặc `mach_vm_write` để thao tác game.
- Luồng attach thực tế dùng kernel primitive và `vm_map` alias, không dùng task port của game.

Những key này không còn được khai báo trong cấu hình entitlement của project.

Nếu IPA được ký lại bởi công cụ ngoài, quyền có hiệu lực sẽ phụ thuộc vào entitlement blob mà công cụ ký thực sự nhúng vào binary. Cần audit executable đã ký trên thiết bị mới biết kết quả cuối cùng.

### 8.3. Các cấu hình app có thật nhưng không phải entitlement task port

`Resources/Info.plist` khai báo:

- `UIBackgroundModes = audio`.
- File sharing.
- Mở document tại chỗ.
- URL scheme `darkpubg`.
- Bundle ID build hiện tại `com.huami.darkpubg`.

Project dùng `AVAudioSession`/`AVAudioPlayer` để giữ process background-running. Đây là background capability theo Info.plist và runtime, không phải task-port entitlement.

Executable cũng link private/system framework:

- SpringBoardServices
- AssertionServices
- BackBoardServices
- IOKit

Nó import API HID, SpringBoard server, `memorystatus_control`, `proc_*`, Mach port và Mach mapping. Đây là code surface thực, nhưng API import vẫn không đồng nghĩa với entitlement được cấp.

### 8.4. Các entitlement private còn lại trong plist

Plist source còn khai báo nhiều nhóm private entitlement:

- Accessibility, AssistiveTouch, HID và pointer routing.
- SpringBoard/FrontBoard và accessibility window hosting.
- Mach service lookup/register exceptions.
- Jetsam/diagnostic/sysdiagnose.
- Shared preferences.
- Bluetooth, audio, authentication, IDS và MobileAsset.

Có code tương ứng với một số nhóm, ví dụ HID event, SpringBoard HUD và jetsam control. Nhưng artifact unsigned không chứng minh các entitlement này đang có hiệu lực. Một số chức năng còn chạy code trong context SpringBoard qua RemoteCall, nên permission check có thể thấy audit token của SpringBoard thay vì của DarkPubg.

Không nên dùng source plist làm danh sách "quyền app đang có".

---

## 9. Cơ chế đọc/ghi game thực tế của DarkPubg

### 9.1. Khởi tạo kernel primitive

Khi bật HUD:

1. `DSBridgeSetHUDEnabled(YES)` vào `ds_finish_enable()`.
2. Project tải/parse kernelcache và offsets.
3. `DSBridgeBootstrap()` gọi `ds_run()`.
4. `ds_run()` chạy exploit `pe()` để tạo kernel read/write primitive.
5. Project giữ các socket primitive và lưu kernel base/slide.

Project cũng có đường adopt KRW sockets từ process cha qua environment, không cần chạy lại exploit trong process con.

### 9.2. Tìm target `kgvn`

Target được hard-code:

```c
static const char kDSLienQuanTargetProcessName[] = "kgvn";
```

Luồng attach:

```c
proc = proc_find_by_name("kgvn");
pid = kread(proc + off_proc_p_pid);
task = proc_task(proc);
vmMap = task_get_vm_map(task);
```

Đây là kernel object traversal. Không có `task_for_pid(pid, &task_port)`.

### 9.3. Tạo page alias

Project duyệt `vm_map` của target bằng kernel read. Với page cần đọc:

1. Tìm `vm_map_entry` và `vm_object` của page target.
2. Tạo named memory entry trong process DarkPubg.
3. Tăng refcount của target `vm_object` bằng kernel write.
4. Sửa backing `vm_map_entry` của named entry để trỏ vào target object.
5. `mach_vm_map(mach_task_self(), ...)` page đó vào DarkPubg.
6. Cache tối đa 2048 mapping.

Phân biệt chính xác phần nào của target bị ghi:

- `vmgetptrfromentry()` chỉ đọc `vm_map_entry` của game và giải ra target `vm_object`.
- `vmcreateshmemwithobj()` tăng `target_vm_object.ref_count` bằng kernel write.
- Entry bị ghi đè tại bước tạo alias là backing entry của named memory entry được tạo trong DarkPubg, không phải `vm_map_entry` gốc của game.
- `mach_vm_map()` tạo mapping mới trong address space DarkPubg. Address/size/protection/path của mapping gốc trong game không bị đoạn code này sửa.

Do đó VM map của game và backing object cần được coi là hai lớp khác nhau:

| Lớp | Thay đổi bởi alias read-only? |
|---|---|
| Target `vm_map_entry` của game | Không thấy ghi; các field address/size/protection/`is_shared` giữ nguyên theo code hiện tại. |
| Target `vm_object` | Có: `ref_count` được tăng ít nhất 1 cho mỗi object được pin/map. Object-level sharing metadata có thể thay đổi tùy đường kernel mapping. |
| VM map/entry của DarkPubg | Có: xuất hiện local alias và backing entry tạm bị sửa. |
| Byte nội dung game | Không đổi chỉ vì đọc qua alias; chỉ đổi khi có write qua alias. |

Sau khi map, read hot path chỉ là:

```c
memcpy(local_buffer, local_alias + page_offset, length);
```

Vì vậy trên import table không có `vm_read` cho target. External read vẫn tồn tại về mặt hành vi, nhưng được thực hiện qua local alias sau khi kernel object bị sửa.

### 9.4. Ghi vào game

`ds_debug_write_bytes()` ghi bằng:

```c
memcpy(local_alias + page_offset, source, length);
```

Local alias trỏ vào cùng backing object của page `kgvn`, nên đây là write vào memory game dù không gọi `vm_write`.

Call-site rõ ràng hiện tại là camera zoom:

- Ghi `Moba_Camera` additional zoom tại `DSBridgeLienQuan.inc.mm:1160`.
- Ghi byte `changed = 1` tại `DSBridgeLienQuan.inc.mm:1165`.
- Chỉ tiếp tục ghi khi tùy chọn camera zoom được bật.
- Khi tắt, code dừng ghi tiếp nhưng không khôi phục baseline.

Phần ESP/hero/monster chủ yếu đọc memory và render overlay. Static audit hiện tại không thấy nó dùng standard Mach task-port read.

### 9.5. SpringBoard và background behavior

Project:

- Tìm `SpringBoard` qua kernel process list.
- Tạo `RemoteCall` vào SpringBoard và hijack thread/exception-port tạm thời.
- Tạo/register HUD window trong context SpringBoard.
- Sau khi register thành công, cố gắng teardown channel/hijacked thread.
- Phát audio im lặng để tiếp tục chạy nền.

Đây là bề mặt hệ thống riêng, không phải attach vào task `kgvn` bằng task port.

---

## 10. Đối chiếu ANOGS với DarkPubg

| Cơ chế ANOGS | Có liên quan trực tiếp? | Đánh giá |
|---|---|---|
| `P_TRACED` | Không trực tiếp | DarkPubg không debug/ptrace game. Kernel page alias không đặt `P_TRACED`. |
| `PT_DENY_ATTACH` | Không chặn cơ chế hiện tại | Nó chặn ptrace debugger, không chặn kernel primitive/shared alias. |
| `task_get_special_port(mach_task_self(), 4)` | Không | Đây là bootstrap port của chính game. |
| ANOGS `vm_read(mach_task_self())` | Không phải external-read monitor | Đây là self-read helper. |
| ANOGS `vm_write(mach_task_self())` | Không phải external-write monitor | Đây là self-patch helper. |
| ANOGS `mach_vm_region_recurse` | Có quét VM, chưa khớp alias | Chỉ query self-task; direct call-site dùng range/path/protection, không dùng `ref_count`/`share_mode`. |
| ANOGS `vm_region_64` field `shared` | Không đổi trực tiếp bởi cơ chế hiện tại | XNU lấy field này từ target `vm_map_entry.is_shared`; project không sửa entry của game. |
| Process enumeration | Có khả năng liên quan | DarkPubg là process riêng và được giữ background-running. Chưa xác nhận rule tên/process reporting. |
| Jailbreak/hook checks | Có khả năng liên quan | Môi trường cần để chạy unsigned/kernel-exploit app có thể để lại dấu vết. Chưa map hết call/report. |
| Integrity/game-state checks | Có rủi ro | Camera zoom ghi state game; server/client invariant có thể phát hiện mà không cần biết API ghi. |
| Kernel object/page alias | Chưa xác nhận ANOGS detect | Project sửa target object refcount và backing entry phía DarkPubg. Các VM call-site hiện tại không tiêu thụ object `ref_count`/`share_mode`. |
| External app identity | Có rủi ro | Tên executable/display `DarkPubg`, bundle `com.huami.darkpubg`, process chạy nền. ANOGS có process-list code. |

### Trả lời trực tiếp

#### Project có "dính task port" không?

Không theo luồng hiện tại. Project không gọi `task_for_pid` và không dùng task port của `kgvn` để read/write. Nó dùng kernel pointer đến `task/vm_map` và local page alias.

#### Các entitlement task/system trong plist có đang hoạt động không?

Không. Chúng đã được xóa khỏi source plist. Archive/IPA cũ vẫn unsigned và không có entitlement blob; các artifact đó chưa được build lại sau thay đổi này.

#### ANOGS có detect external read/write của project không?

Chưa có bằng chứng để kết luận. Các `vm_read`/`vm_write` của ANOGS đều là self-task operations. ANOGS có quét VM map của game, nhưng direct call-site đã truy không đọc object `ref_count`/`share_mode`; field basic `shared` mà một số helper sử dụng đến từ game `vm_map_entry`, là cấu trúc project không sửa.

Nếu chỉ bật ESP/read-only và camera zoom chưa từng được bật, bằng chứng static hiện tại nghiêng về kết luận rằng VM checks đã thấy không trùng dấu vết alias của project. Đây vẫn không phải bảo đảm "không detect": process list, jailbreak/kernel environment, code gián tiếp và telemetry/server chưa được loại trừ.

Khi bật camera zoom, project ghi byte game thật qua alias. Trường hợp này có rủi ro integrity/game-state riêng, không phụ thuộc ANOGS có nhận ra kỹ thuật ghi hay không.

#### ANOGS có anti-debug không?

Có, đã xác nhận cả `P_TRACED` và `PT_DENY_ATTACH`.

#### Có thể kết luận ban hay report không?

Không. Cần trace callback/report packet và server response. Static binary chỉ xác nhận local checks/capability, không xác nhận policy ban.

---

## 11. Giới hạn của kết quả

Phân tích này chưa bao gồm:

- Dynamic trace trên thiết bị khi game đang chạy.
- Hook các hàm report/network để map event ID.
- Giải mã toàn bộ code obfuscated.
- Xác minh rule server-side.
- Audit executable DarkPubg đã được công cụ ngoài ký và cài trên thiết bị.
- Xác nhận ANOGS có dùng `dlsym` để resolve thêm API nhạy cảm ở runtime hay không.

Kết quả về entitlement chỉ đúng chắc chắn cho archive và IPA hiện có trong workspace. Nếu cài một bản đã được ký lại, cần lấy executable của chính bản cài đặt đó và đọc code signature để biết quyền có hiệu lực.

---

## 12. Kết luận cuối

Bản phân tích cũ đúng ở kết luận rằng import Mach API không đủ để nói ANOGS detect external read/write. Tuy nhiên nó bỏ sót anti-debug đã hiện diện rõ trong call-site và hiểu sai hai substring `Frida`/`ptrace` trong UnityFramework.

Với project hiện tại:

- Không có standard task-port attach vào `kgvn`.
- Không có entitlement có hiệu lực trong artifact unsigned hiện tại.
- Sáu entitlement task/system không dùng đã được xóa khỏi cấu hình nguồn.
- Có kernel read/write primitive và external memory alias thực tế.
- Alias read-only không sửa `vm_map_entry` của game; nó tăng target object refcount và tạo mapping trong DarkPubg.
- Các direct VM scan của ANOGS đã truy không đọc object `ref_count`/`share_mode`, nên chưa có detector khớp trực tiếp dấu vết này.
- Có external memory write khi bật camera zoom.
- Rủi ro hợp lý nhất từ static evidence là process visibility, jailbreak/kernel environment và game-memory/state mutation, không phải `task_get_special_port` hay `vm_read` import của ANOGS.
