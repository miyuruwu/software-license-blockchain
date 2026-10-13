# Kết quả kiểm tra

Ngày kiểm tra: 08/10/2026.

- Foundry Forge: 1.7.1.
- Solidity: 0.8.28.
- OpenZeppelin Contracts: 5.6.1, khóa phiên bản bằng package-lock.json.
- Biên dịch thành công.
- 26 kiểm thử thành công; 0 thất bại; 0 bỏ qua.
- Fuzz test chạy 256 trường hợp cho ví sở hữu và thời hạn giấy phép.

Các nhóm đã kiểm tra: phân quyền admin/nhà phát hành, giới hạn quản lý theo chủ phần mềm, cấp giấy phép, cấp trùng, dữ liệu không hợp lệ, hết hạn đúng thời điểm, gia hạn, thu hồi, cấp lại giữ lịch sử, tạm ngừng/bật lại phần mềm, sự kiện cấp phép và cấu hình vai trò trong script triển khai.

Script Deploy được thực thi trong kiểm thử Foundry để xác minh vai trò được cấp đúng. Chưa phát giao dịch triển khai lên Anvil hoặc testnet. Lệnh chạy script độc lập trong môi trường hạn chế quyền hiện tại gặp lỗi `Access is denied`; bản kiểm thử của script chạy thành công.

Foundry phát cảnh báo không ghi được cache chữ ký vào thư mục người dùng, nhưng quá trình biên dịch và cả 26 kiểm thử kết thúc với mã thành công. Công cụ định dạng của Forge 1.7.1 trên môi trường Windows này không đọc được đường dẫn nguồn; không tính đây là một kiểm tra đã đạt.

Đây là kiểm thử chức năng của bộ khung bài tập lớn, chưa phải kiểm toán bảo mật. Giao diện, xác thực chữ ký ví và ứng dụng mẫu sẽ cần kiểm thử tích hợp khi được triển khai.
