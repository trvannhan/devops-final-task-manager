# Checklist bảo mật (Week 3)

Nguyên tắc: chỉ mở đúng những gì người dùng cần, mỗi thành phần chỉ có quyền tối thiểu, không có mật khẩu nào nằm trong Git.

## 1. Cổng và firewall

UFW mặc định chặn mọi kết nối vào (`default deny incoming`), chỉ cho phép các cổng dưới đây.

| Cổng | Dịch vụ | Lắng nghe trên | Mở trong UFW | Lý do |
|------|---------|----------------|--------------|-------|
| 22 | SSH quản trị | mọi interface | có | Quản trị VM, tạo SSH tunnel xem Grafana |
| 8080 | Nginx → Task Manager | mọi interface | có | Cổng duy nhất người dùng truy cập |
| 80 | Nginx → project khác (`devops-app`) | mọi interface | có | Không thuộc hệ thống này |
| 8000 | Container app (Gunicorn) | 127.0.0.1 | không | Chỉ Nginx gọi vào |
| 5432 | Container db (PostgreSQL) | chỉ trong network `backend` của Docker, không publish ra host | không | Chỉ container app truy cập |
| 9090 | Prometheus | 127.0.0.1 | không | Xem qua SSH tunnel |
| 9093 | Alertmanager | 127.0.0.1 | không | Xem qua SSH tunnel |
| 3000 | Grafana | 127.0.0.1 | không | Xem qua SSH tunnel, có đăng nhập |

Kiểm tra:
```bash
sudo ufw status verbose
sudo ss -lntp | grep -E ':22 |:8080 |:8000 |:5432 |:9090 |:9093 |:3000 '
```
Kết quả đúng: 8000, 9090, 9093, 3000 chỉ hiện `127.0.0.1`; 5432 không xuất hiện (PostgreSQL trên VM đã tắt, container db không publish cổng).

Xem Grafana/Prometheus/Alertmanager từ Windows bằng SSH tunnel (không mở thêm cổng nào):
```powershell
ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 vannhan@<VM_IP>
```

## 2. Mạng giữa các container

| Network | Thành viên | Ý nghĩa |
|---------|-----------|---------|
| `backend` | app, db | Chỉ app nói chuyện được với database |
| `monitoring` | app, prometheus, alertmanager, grafana, node-exporter, blackbox | Các container giám sát **không** truy cập được database |

## 3. Secrets

| Secret (GitHub → Settings → Secrets and variables → Actions) | Dùng cho |
|---|---|
| `POSTGRES_PASSWORD` | Role `taskapp` (chủ sở hữu DB, dùng cho backup/restore) |
| `APP_DB_PASSWORD` | Role `taskapp_rw` mà ứng dụng dùng |
| `GRAFANA_ADMIN_PASSWORD` | Tài khoản `admin` của Grafana |

- Không có mật khẩu nào trong mã nguồn hay trong Git; GitHub che giá trị secret trong log của Actions.
- Khi deploy, runner ghi các secret ra `/opt/taskmanager/.env` với quyền `600` (chỉ user `vannhan` đọc được). File này không nằm trong repository (`.gitignore`).
- `GITHUB_TOKEN` để kéo image từ ghcr.io do GitHub cấp tự động cho mỗi lần chạy và hết hạn sau khi job kết thúc.
- Ai xem được secret: chỉ chủ repository sửa/ghi đè được; không ai, kể cả chủ repo, xem lại được giá trị trên GitHub.

Kiểm tra:
```bash
ls -l /opt/taskmanager/.env          # -rw------- vannhan vannhan
git -C ~/devops-final-task-manager grep -nI -E 'PASSWORD=[A-Za-z0-9]{12,}' || echo "không có mật khẩu trong Git"
```

## 4. Phân quyền database

| Role | Quyền | Dùng ở đâu |
|------|-------|-----------|
| `taskapp` | Chủ sở hữu database `taskdb` | Tạo bảng, `backup.sh`, `restore.sh` |
| `taskapp_rw` | Chỉ `SELECT, INSERT, UPDATE, DELETE` trên bảng `tasks` và dùng sequence | Ứng dụng (`DATABASE_URL`) |

Quyền được áp dụng bằng `scripts/db-roles.sql` mỗi lần deploy. Nếu ứng dụng bị khai thác, kẻ tấn công cũng không xóa được bảng, không tạo bảng, không đổi cấu trúc.

Kiểm tra (role của app không xóa được bảng):
```bash
cd /opt/taskmanager
docker compose exec db psql -U taskapp -d taskdb -c '\du'
APP_PW="$(grep '^APP_DB_PASSWORD=' .env | cut -d= -f2-)"
docker compose exec -e PGPASSWORD="$APP_PW" db psql -h localhost -U taskapp_rw -d taskdb -c 'DROP TABLE tasks'
unset APP_PW
```
Kết quả đúng: `ERROR: must be owner of table tasks`.

## 5. Container và image

- Container app chạy bằng user thường `appuser` (uid 10001), không phải root.
- Image cố định phiên bản (`postgres:18`, `prom/prometheus:v3.5.0`, `grafana/grafana:12.0.0`...), image app gắn tag theo mã commit.
- Mọi container có `restart: unless-stopped`, giới hạn log `10m x 3 file` và giới hạn RAM cho các container giám sát.
- File cấu hình giám sát được gắn vào container ở chế độ chỉ đọc (`:ro`).

## 6. Việc nên làm thêm (chưa làm trong phạm vi môn học)

- SSH chỉ dùng khóa (`PasswordAuthentication no`) và giới hạn IP được SSH.
- HTTPS cho Nginx (cần tên miền hoặc chứng chỉ tự ký).
- Sao chép backup ra ngoài VM định kỳ (ví dụ `scp` về máy Windows) để tránh mất cả VM lẫn backup.
