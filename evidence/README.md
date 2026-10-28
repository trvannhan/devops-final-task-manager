# Minh chứng

## Week 1

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

## Week 2 (`week2/`)

Ảnh chụp ngày 28/10/2026. Địa chỉ IP riêng đã được che; không ảnh nào chứa giá trị secret.

| File | Chứng minh điều gì |
|------|--------------------|
| `week2/01-compose-ps-health.png` | Container `app` (image `ghcr.io/...:1b21dc9`) và `db` (`postgres:18`) đều healthy; `/health` qua Nginx :8080 trả `version: 1b21dc9` |
| `week2/02-migrate-week1-data.png` | 7 task của Week 1 được chuyển từ PostgreSQL trên VM sang container, sequence đặt về 7 |
| `week2/03-web-version.png` | Web trước khi cập nhật: chân trang `Database connected · v1b21dc9` |
| `week2/04-persistence.png` | `docker compose down` xóa container nhưng volume `taskmanager_pgdata` còn; sau `up -d` task "Persistence test" (id 8) vẫn còn |
| `week2/05-pipeline-green.png` | Lần deploy đầu: Test → Build & push image → Deploy to Ubuntu VM đều thành công |
| `week2/06-commit-pipeline-green.png` | Commit "update subtitle" (`983f55d`) trên GitHub tự chạy pipeline và deploy trong 1m38s, không đăng nhập server |
| `week2/07-web-after-deploy.png` | Web sau khi deploy: câu mô tả mới và chân trang `v983f55d` |
| `week2/08-pr-test-fail.png` | Pull Request `demo/test-fail`: job Test thất bại, Build và Deploy bị bỏ qua |
| `week2/09-test-fail-log.png` | Log pytest: `test_post_rejects_blank_title FAILED`, `assert 400 == 200`, `1 failed, 5 passed` |
