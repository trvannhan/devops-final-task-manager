# Minh chứng Week 1

Ảnh chụp trên máy ảo Ubuntu và máy client Windows ngày 27/10/2026.
Địa chỉ IP riêng đã được che. Không ảnh nào chứa mật khẩu, token hoặc giá trị `DATABASE_URL`.

| File | Chứng minh điều gì |
|------|--------------------|
| `01-os.png` | Hệ điều hành và tài nguyên: Ubuntu 26.04.1 LTS, 2 vCPU, RAM 3.3 GiB khả dụng, ổ đĩa 35 GB |
| `02-ssh.png` | Đăng nhập SSH từ Windows (PowerShell) vào VM bằng user `vannhan` |
| `03-ufw-ports.png` | UFW đang bật, mặc định chặn kết nối vào, chỉ mở 22 và 8080 (cổng 80 thuộc project khác). Nginx lắng nghe `0.0.0.0:8080`; Gunicorn `127.0.0.1:8000` và PostgreSQL `127.0.0.1:5432` chỉ chạy nội bộ |
| `04-services.png` | `postgresql`, `nginx`, `taskmanager` đều active; `taskmanager.service` được enable và chạy Gunicorn 2 worker tại 127.0.0.1:8000 |
| `05-api.png` | `GET /health` trả 200 (database connected), `POST /api/tasks` trả 201 (tạo task id 6), `GET /api/tasks`, `PATCH /api/tasks/6` trả 200 (`completed: true`) |
| `06-sql.png` | Câu `SELECT` trong PostgreSQL có task 6 "Demo Week 1" với `completed = t`, khớp với các lệnh API |
| `07a-browser-add.png` | Trình duyệt Windows truy cập `VM_IP:8080`: thêm task "Demo từ Windows", task vẫn còn sau khi tải lại trang |
| `07b-browser-complete.png` | Đánh dấu hoàn thành task đó trên trình duyệt; các ô thống kê cập nhật theo |
| `08-tests.png` | Kiểm thử tự động: `3 passed` |
