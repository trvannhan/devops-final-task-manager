# DevOps Task Manager — Final Project 2026 (Week 1)

Ứng dụng web Flask + JSON API + cơ sở dữ liệu PostgreSQL, triển khai thủ công trên máy ảo Ubuntu, phía sau reverse proxy Nginx.
**Week 1: triển khai thủ công. Docker và CI/CD sẽ được bổ sung ở Week 2.**

## Nguồn code và phạm vi
- Nguồn: mã nguồn ứng dụng được viết với sự hỗ trợ của trợ lý AI, sau đó nhóm review, kiểm thử và triển khai. Không sao chép template từ dự án bên thứ ba.
- Phần nhóm tự thực hiện: mã nguồn ứng dụng, thiết kế kiến trúc triển khai, cấu hình Ubuntu/Nginx/systemd/UFW, tài liệu.

## Chức năng
- Xem danh sách công việc, thêm công việc, đánh dấu hoàn thành/làm lại, xóa.
- API: `GET /health`, `GET /api/tasks`, `POST /api/tasks`, `PATCH /api/tasks/<id>`, `DELETE /api/tasks/<id>`.
- Dữ liệu lưu trong PostgreSQL (không lưu trên trình duyệt), nên vẫn còn sau khi tải lại trang hoặc khởi động lại máy.

## Kiến trúc
Trình duyệt -> Nginx trên VM (`:8080`) -> Gunicorn/Flask (`127.0.0.1:8000`) -> PostgreSQL (`127.0.0.1:5432`) -> ổ đĩa VM.
Xem chi tiết tại [`docs/architecture.md`](docs/architecture.md) và [`docs/architecture.png`](docs/architecture.png).

![Sơ đồ kiến trúc](docs/architecture.png)

> Cổng 80 trên cùng VM thuộc về một project khác của môn học (`devops-app`). Task Manager dùng cổng **8080** để hai project chạy song song; hướng dẫn này không thay đổi site ở cổng 80.

## Môi trường máy chủ
| Mục | Giá trị |
|-----|---------|
| Ảo hóa | VMware Workstation, mạng NAT (VMnet8); máy Windows (host) truy cập trực tiếp vào VM |
| Hệ điều hành | Ubuntu 26.04.1 LTS |
| CPU / RAM / Disk | 2 vCPU / 4 GB RAM (dùng được 3.3 GiB) / 35 GB (`/dev/sda2`) |
| PostgreSQL | 18.6 (gói Ubuntu `18.6-0ubuntu0.26.04.1`) |
| Python | 3.14.4 |
| User quản trị | `vannhan` (SSH) |

Địa chỉ IP của VM không được ghi trong repository; dùng lệnh `hostname -I` trên VM để xem.

## Hướng dẫn cài đặt thủ công (Ubuntu 26.04)
Nên tạo snapshot cho VM trước khi bắt đầu.

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip postgresql nginx curl ufw openssh-server
sudo systemctl enable --now postgresql nginx ssh
```

### 1. Tạo user và database PostgreSQL
```bash
sudo -u postgres psql
```
Trong `psql` (dùng mật khẩu riêng, dài, chỉ gồm chữ và số; không commit mật khẩu lên Git):
```sql
CREATE USER taskapp WITH PASSWORD 'CHANGE_ME_LONG_RANDOM_PASSWORD';
CREATE DATABASE taskdb OWNER taskapp;
\q
```

### 2. Lấy mã nguồn và cài thư viện
```bash
cd ~
git clone https://github.com/trvannhan/devops-final-task-manager.git
cd devops-final-task-manager
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
sudo cp .env.example /etc/devops-task-manager.env
sudo chmod 600 /etc/devops-task-manager.env
sudo nano /etc/devops-task-manager.env
```
Trong file môi trường, đặt
`DATABASE_URL=postgresql://taskapp:YOUR_OWN_PASSWORD@127.0.0.1:5432/taskdb`
với mật khẩu giống mật khẩu của role PostgreSQL ở bước 1. File này nằm ngoài repository và chỉ root đọc được.

### 3. Tạo bảng
```bash
cd ~/devops-final-task-manager
sudo bash -c 'set -a; . /etc/devops-task-manager.env; set +a; psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f schema.sql'
```
Kết quả mong đợi: `CREATE TABLE`. Bảng thuộc sở hữu của `taskapp`. Không để lộ `DATABASE_URL` trong video demo.

### 4. Service systemd, Nginx và firewall
Kiểm tra đường dẫn trong `scripts/taskmanager.service` khớp với user của bạn, sau đó:
```bash
sudo cp scripts/taskmanager.service /etc/systemd/system/taskmanager.service
sudo systemctl daemon-reload
sudo systemctl enable --now taskmanager

sudo cp scripts/nginx-taskmanager.conf /etc/nginx/sites-available/taskmanager
sudo ln -sfn /etc/nginx/sites-available/taskmanager /etc/nginx/sites-enabled/taskmanager
sudo nginx -t
sudo systemctl reload nginx
```
Firewall (kiểm tra SSH hoạt động trước khi bật UFW):
```bash
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp     # Task Manager
sudo ufw allow 80/tcp       # project devops-app có sẵn (giữ lại nếu vẫn dùng)
sudo ufw enable
sudo ufw status verbose
```
Tuyệt đối không mở cổng 8000 (Gunicorn) và 5432 (PostgreSQL); cả hai chỉ lắng nghe trên 127.0.0.1.

### 5. Kiểm tra
```bash
lsb_release -a
hostname -I
sudo systemctl is-active postgresql nginx taskmanager
sudo ss -lntp | grep -E ':22 |:8080 |:8000 |:5432 '

curl -i http://127.0.0.1:8080/health
curl -i -X POST http://127.0.0.1:8080/api/tasks -H 'Content-Type: application/json' \
     -d '{"title":"Demo Week 1","description":"Test read/write"}'
curl -s http://127.0.0.1:8080/api/tasks; echo
# thay số 1 bằng id trả về từ lệnh POST ở trên
curl -i -X PATCH http://127.0.0.1:8080/api/tasks/1 -H 'Content-Type: application/json' -d '{"completed":true}'; echo
sudo -u postgres psql -d taskdb -c 'SELECT id,title,completed FROM tasks ORDER BY id DESC LIMIT 10;'

.venv/bin/python -m pytest -q
```
Kết quả mong đợi của `/health`: `{"database":"connected","status":"ok"}`.

Trên trình duyệt Windows, mở `http://<VM_IP>:8080/` (thay `<VM_IP>` bằng IP thật của VM), thêm một công việc, tải lại trang, đánh dấu hoàn thành và đối chiếu với kết quả câu lệnh SQL ở trên.

## Hồ sơ nộp Week 1
- [x] Kiến trúc: `docs/architecture.md`, `docs/architecture.png`
- [x] Repository, mã nguồn, README này
- [x] Phân công nhiệm vụ (bên dưới)
- [x] Minh chứng server trong `evidence/`: phiên bản OS, đăng nhập SSH, `ufw status`, các cổng đang lắng nghe, trạng thái service
- [x] Minh chứng app + DB: kết quả POST/GET/PATCH và câu SELECT trong PostgreSQL (không lộ mật khẩu)
- [x] Ảnh truy cập web từ Windows qua cổng 8080 (`evidence/07a`, `07b`)
- [ ] Video demo dự phòng

## Phân công nhiệm vụ
| Thành viên | MSSV | Phụ trách | Minh chứng |
|------------|------|-----------|------------|
| Trần Văn Nhân (nhóm trưởng) | 23090036 | Máy ảo Ubuntu và SSH, Flask app/API, GitHub repository | ảnh VM, minh chứng API, commit |
| Trần Văn Lực | 23090019 | Firewall UFW, triển khai Nginx + systemd, sơ đồ kiến trúc | `ufw status`, trạng thái service, `docs/` |
| Nguyễn Vũ Hoàng Long | 23090026 | Database PostgreSQL và CRUD, README, video demo | minh chứng SQL, README, video |

## Các tuần tiếp theo
- Week 2: Dockerfile, Docker Compose, volume, kiểm thử tự động và CI/CD.
- Week 3: giám sát (metrics, dashboard, cảnh báo), firewall/secrets, backup/restore.
- Week 4: demo toàn hệ thống, troubleshooting playbook và báo cáo kỹ thuật.
