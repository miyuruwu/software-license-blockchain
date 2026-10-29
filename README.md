# Quản lý bản quyền phần mềm bằng Blockchain

Bộ khung phần smart contract cho bài tập lớn, dùng Solidity 0.8.28, Foundry và OpenZeppelin Contracts 5.6.1. Hiện chưa có giao diện web, backend hay ứng dụng phần mềm mẫu.

## Phạm vi phiên bản đầu

- Quản trị viên cấp và thu hồi vai trò nhà phát hành.
- Nhà phát hành đăng ký phần mềm với tên, phiên bản, địa chỉ metadata và mã băm tệp phần mềm.
- Chỉ nhà phát hành đã đăng ký phần mềm đó được cấp, gia hạn, thu hồi giấy phép và thay đổi trạng thái phần mềm.
- Giấy phép gắn với ví người dùng, có thời hạn và không chuyển nhượng.
- Kiểm tra giấy phép và đọc lịch sử thay đổi qua event.

Không có thanh toán, NFT, nâng cấp proxy hoặc cơ chế chống bẻ khóa trong phiên bản này. Mã băm phần mềm giúp đối chiếu tệp, không tự chứng minh quyền sở hữu trí tuệ.

## Quy tắc nghiệp vụ

1. Mỗi cặp `(softwareId, holder)` có một giấy phép hiện hành.
2. `expiresAt` là Unix timestamp tính bằng giây; tại đúng thời điểm hết hạn, giấy phép không còn hợp lệ.
3. Giấy phép hết hạn nhưng chưa thu hồi phải được gia hạn; không cấp trùng.
4. Gia hạn phải tăng thời hạn và thời hạn mới phải nằm trong tương lai.
5. Giấy phép đã thu hồi không được gia hạn. Cấp lại tạo ID mới, giữ nguyên bản ghi cũ.
6. Tạm ngừng phần mềm khiến tất cả giấy phép của phần mềm đó không hợp lệ. Bật lại khôi phục giấy phép còn hạn và chưa thu hồi.
7. Thu hồi vai trò nhà phát hành chặn các thao tác quản lý tiếp theo, nhưng không tự hủy giấy phép đã cấp. Admin có thể cấp lại vai trò; phiên bản này chưa hỗ trợ chuyển chủ sở hữu phần mềm.
8. Admin không tự có vai trò nhà phát hành, trừ khi được cấp vai trò đó. Tránh thu hồi hoặc từ bỏ vai trò admin cuối cùng vì có thể làm mất quyền quản trị.

## Cấu trúc

```text
src/SoftwareLicenseManager.sol       Smart contract
test/SoftwareLicenseManager.t.sol    Kiểm thử và fuzz test
script/Deploy.s.sol                  Triển khai contract
foundry.toml                        Cấu hình trình biên dịch
package.json / package-lock.json    Phiên bản OpenZeppelin cố định
```

## Chạy kiểm thử

Cần Node.js/npm và Foundry. Hướng dẫn cài Foundry: https://getfoundry.sh/introduction/installation/

Mở terminal tại thư mục dự án:

```powershell
npm ci
forge build
forge test -vv
```

OpenZeppelin được cài vào `node_modules`; `foundry.toml` đã cấu hình đường dẫn import. Bộ kiểm thử dùng giao diện cheatcode tối thiểu nên không cần tải thêm `forge-std`.

## Triển khai và demo trên Anvil

Terminal thứ nhất:

```powershell
anvil
```

Terminal thứ hai, trong thư mục dự án:

```powershell
# Chép địa chỉ tài khoản local đầu tiên và thứ hai do Anvil hiển thị.
$env:ADMIN_ADDRESS = 'DIA_CHI_VI_QUAN_TRI'
$env:PUBLISHER_ADDRESS = 'DIA_CHI_VI_NHA_PHAT_HANH'

# --unlocked chỉ dùng với tài khoản mở khóa trên Anvil local.
forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --unlocked --sender $env:ADMIN_ADDRESS --broadcast
```

Lưu địa chỉ contract được trả về rồi thử luồng dưới đây. Đây là lệnh PowerShell; thay địa chỉ và tên phần mềm phù hợp.

```powershell
$contract = 'DIA_CHI_CONTRACT'
$holder = 'DIA_CHI_VI_NGUOI_DUNG'
$rpc = 'http://127.0.0.1:8545'
$artifactHash = cast keccak 'demo-software-v1'

# Trên contract mới, phần mềm đầu tiên và giấy phép đầu tiên đều có ID = 1.
cast send $contract 'registerSoftware(string,string,string,bytes32)' 'Demo Editor' '1.0' 'https://example.com/demo.json' $artifactHash --from $env:PUBLISHER_ADDRESS --unlocked --rpc-url $rpc

# Ví dụ băm ở trên là băm chuỗi demo. Khi dùng thật, băm nội dung tệp phát hành.
$expiresAt = [DateTimeOffset]::UtcNow.AddDays(30).ToUnixTimeSeconds()
cast send $contract 'issueLicense(uint256,address,uint64)' 1 $holder $expiresAt --from $env:PUBLISHER_ADDRESS --unlocked --rpc-url $rpc
cast call $contract 'isLicenseValid(uint256,address)(bool)' 1 $holder --rpc-url $rpc

$newExpiresAt = [DateTimeOffset]::UtcNow.AddDays(60).ToUnixTimeSeconds()
cast send $contract 'renewLicense(uint256,uint64)' 1 $newExpiresAt --from $env:PUBLISHER_ADDRESS --unlocked --rpc-url $rpc
cast send $contract 'revokeLicense(uint256)' 1 --from $env:PUBLISHER_ADDRESS --unlocked --rpc-url $rpc
cast call $contract 'isLicenseValid(uint256,address)(bool)' 1 $holder --rpc-url $rpc
```

Kết quả kiểm tra trước khi thu hồi là `true`, sau khi thu hồi là `false`. Tài khoản Anvil chỉ dùng cho demo local.

## Kết nối ứng dụng ở bước tiếp theo

Luồng xác thực đề xuất:

1. Người dùng kết nối ví.
2. Backend tạo một thử thách với nonce ngẫu nhiên, domain, chain ID và thời hạn ngắn.
3. Người dùng ký thử thách; backend xác minh chữ ký, thời hạn và nonce chưa sử dụng.
4. Backend lấy địa chỉ từ chữ ký hợp lệ rồi gọi `isLicenseValid(softwareId, holder)` trên đúng mạng và contract.
5. Nếu hợp lệ, cấp phiên truy cập ngắn; kiểm tra lại tại các thao tác được bảo vệ để áp dụng thu hồi/hết hạn.

`isLicenseValid` chỉ kiểm tra quyền sử dụng, không chứng minh người gọi sở hữu ví. Không mở quyền truy cập chỉ vì người dùng nhập một địa chỉ có giấy phép.

Biến `private` trong Solidity không bảo mật dữ liệu trên blockchain. Không lưu khóa kích hoạt, mật khẩu, mã nguồn hoặc thông tin cá nhân ở đây. Metadata có thể lưu ngoài chuỗi; `artifactHash` lưu mã băm của tệp phát hành. URI HTTP có thể thay đổi nội dung, vì vậy cần dùng địa chỉ nội dung cố định nếu muốn metadata bất biến.

Giao diện đọc dữ liệu và lịch sử trực tiếp từ blockchain. Với nhiều bản ghi, dùng event để lập chỉ mục ngoài chuỗi thay vì duyệt toàn bộ trong một giao dịch. ABI sau khi biên dịch nằm tại `out/SoftwareLicenseManager.sol/SoftwareLicenseManager.json`.

## Hướng phát triển

- Giao diện nhà phát hành: đăng ký phần mềm; cấp, gia hạn, thu hồi; xem lịch sử.
- Giao diện người dùng: kết nối ví, xem giấy phép và thời hạn.
- Ứng dụng mẫu: một trình soạn thảo đơn giản có tính năng cần giấy phép.
- Sau khi demo local ổn định: triển khai lên testnet và chuẩn bị báo cáo, sơ đồ kiến trúc, kịch bản demo.

Blockchain lưu quyền sử dụng và lịch sử giao dịch; phần mềm chạy hoàn toàn trên máy người dùng vẫn có thể bị sửa để bỏ qua bước kiểm tra. Phạm vi báo cáo cần phân biệt xác minh giấy phép với chống sao chép tuyệt đối.

## Web dashboard và backend local

Yêu cầu Node.js 20+, npm, và artifact tạo bằng `forge build`. Chạy:

```powershell
npm ci
forge build
npm run dev
```

Mở http://127.0.0.1:3000. Backend tự khởi động Anvil nếu RPC chưa chạy và triển khai contract. Địa chỉ lưu trong `.local/deployment.json`. Windows dùng optional dependency Anvil; Linux/macOS cần `anvil` trong PATH hoặc đặt `ANVIL_BIN` trong `.env`. Cấu hình mẫu ở `.env.example`.

Dashboard hỗ trợ đăng ký/tạm ngừng phần mềm, cấp/gia hạn/thu hồi, phân trang và xác minh giấy phép. API: GET `/api/health`, `/api/state?page=1`, `/api/verify?softwareId=1&holder=0x...`; POST `/api/softwares`, `/api/softwares/:id/status`, `/api/licenses`, `/api/licenses/:id/renew`, `/api/licenses/:id/revoke`. Thời hạn API là Unix timestamp giây.

Bản demo dùng ví Anvil đã mở khóa, chưa có đăng nhập hay xác thực chữ ký ví người dùng. Chỉ phục vụ loopback, chặn request khác origin; không triển khai backend này ra Internet. Chain nằm trong bộ nhớ; reset sẽ mất dữ liệu. Hash mặc định băm tên/phiên bản để demo, có thể nhập hash tệp thật.

Khi server chạy, mở terminal khác và chạy `npm run test:api` để kiểm thử giao dịch (tạo dữ liệu demo). Ctrl+C dừng backend và Anvil do backend khởi động.
