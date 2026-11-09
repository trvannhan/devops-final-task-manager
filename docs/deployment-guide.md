# Deployment guide: triển khai từ máy Ubuntu sạch

Tài liệu này dựng lại **toàn bộ hệ thống** (ứng dụng, database, CI/CD, giám sát, backup) trên một VM Ubuntu mới, theo đúng cấu hình đang chạy ở Week 4. Không cần các bước thủ công của Week 1 (systemd, PostgreSQL trên host).

Thời gian ước tính: khoảng 30–45 phút, phần lớn là chờ cài gói và chờ pipeline.

## 0. Yêu cầu

| Mục | Giá trị đã kiểm chứng |
|-----|-----------------------|
| Hệ điều hành | Ubuntu 26.04.1 LTS (Desktop hoặc Server) |
| Tài nguyên | 2 vCPU, 4 GB RAM, ≥ 20 GB đĩa trống |
| Mạng | VMware NAT (VMnet8); VM cần ra Internet (kéo image, kết nối GitHub). Không cần IP public |
| Tài khoản | User thường có quyền `sudo` (ví dụ `vannhan`); quyền admin trên repository GitHub |

> [!TIP]
> Tạo snapshot VM trước khi bắt đầu để có thể quay lại trạng thái sạch và kiểm thử lại.

## 1. Lấy mã nguồn và chuẩn bị VM (một lệnh)

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/trvannhan/devops-final-task-manager.git ~/devops-final-task-manager
cd ~/devops-final-task-manager
bash scripts/bootstrap-vm.sh
# Nếu VM có project khác dùng cổng 80:  OPEN_PORT_80=1 bash scripts/bootstrap-vm.sh
newgrp docker        # hoặc đăng xuất/đăng nhập lại để nhóm docker có hiệu lực
```

[`scripts/bootstrap-vm.sh`](../scripts/bootstrap-vm.sh) làm các việc sau (chạy lại nhiều lần không sao):

| Bước | Kết quả |
|------|---------|
| Cài gói | git, curl, cron, ufw, openssh-server, nginx, docker.io, docker-compose-v2 |
| Bật dịch vụ | ssh, nginx, docker, cron (tự chạy khi khởi động VM) |
| Quyền Docker | User hiện tại vào nhóm `docker` (runner chạy bằng user này) |
| Thư mục deploy | `/opt/taskmanager`, chủ sở hữu là user hiện tại, quyền 750 |
| Nginx | Site `:8080` → `127.0.0.1:8000`, đã `nginx -t` trước khi reload |
| UFW | `deny incoming`, chỉ mở 22 và 8080 (80 nếu có `OPEN_PORT_80=1`) |

Kiểm tra nhanh:
```bash
sudo ufw status verbose                 # 22, 8080 ALLOW
systemctl is-active ssh nginx docker    # active x3
docker ps                               # chạy được không cần sudo
```

## 2. Tạo GitHub Secrets

Repository → **Settings → Secrets and variables → Actions → New repository secret**. Chỉ dùng chữ và số, tạo bằng `openssl rand -hex 16`:

| Secret | Dùng cho |
|--------|----------|
| `POSTGRES_PASSWORD` | Role `taskapp` (chủ database, dùng cho backup/restore) |
| `APP_DB_PASSWORD` | Role `taskapp_rw` mà ứng dụng dùng (chỉ đọc/ghi dữ liệu) |
| `GRAFANA_ADMIN_PASSWORD` | Đăng nhập Grafana, user `admin` |

> [!IMPORTANT]
> Tạo đủ 3 secret **trước** khi chạy pipeline. Job đã xếp hàng trước khi tạo secret vẫn thấy secret rỗng (playbook mục 5).

## 3. Cài self-hosted runner

VM dùng NAT, GitHub không SSH vào được, nên runner trong VM tự kết nối ra GitHub để nhận job deploy.

1. Repository → **Settings → Actions → Runners → New self-hosted runner** → *Linux*, *x64*.
2. Chạy trên VM các lệnh GitHub hiển thị (tải về `~/actions-runner`, `./config.sh --url ... --token ...`, Enter để giữ tên và label mặc định).
3. Cài runner thành service, chạy bằng user hiện tại:
   ```bash
   cd ~/actions-runner
   sudo ./svc.sh install "$USER"
   sudo ./svc.sh start
   ```
4. Trang *Runners* hiện runner **Idle** (xanh) là được.

## 4. Chạy pipeline lần đầu

Repository → **Actions → CI/CD → Run workflow** (nhánh `main`), hoặc push một commit lên `main`.

Pipeline tự làm toàn bộ phần còn lại:

| Job | Việc |
|-----|------|
| Test (máy GitHub) | pytest 6 test (có PostgreSQL 18 tạm), kiểm tra `docker-compose.yml`, `promtool check config` + `promtool test rules`, `amtool check-config`, kiểm tra JSON dashboard |
| Build & push | Build image, gắn tag mã commit, đẩy lên `ghcr.io` |
| Deploy (runner trong VM) | Chép `docker-compose.yml`, `schema.sql`, `monitoring/`, `scripts/` vào `/opt/taskmanager`; ghi `.env` (quyền 600) từ Secrets; `docker compose pull`; khởi động db (lần đầu tự tạo bảng từ `schema.sql`); áp dụng `scripts/db-roles.sql`; chạy toàn bộ container; cài cron backup 02:00; smoke test `/health` phải trả đúng version; kiểm tra Prometheus/Alertmanager/Grafana sẵn sàng |

## 5. Kiểm tra sau khi triển khai

```bash
cd /opt/taskmanager
docker compose ps                                  # 7 container, app và db: healthy
curl -s http://127.0.0.1:8080/health; echo         # {"database":"connected","status":"ok","version":"<7 ký tự commit>"}
curl -s -X POST http://127.0.0.1:8080/api/tasks -H 'Content-Type: application/json' \
     -d '{"title":"Kiểm tra máy sạch"}'; echo       # 201
crontab -l | grep taskmanager-backup               # 0 2 * * * ... backup.sh
bash scripts/backup.sh                             # tạo bản backup đầu tiên (để BackupTooOld không báo)
sudo ss -lntp | grep -E ':8000 |:9090 |:9093 |:3000 '   # tất cả chỉ trên 127.0.0.1
```

Trên Windows:
- Web: `http://<VM_IP>:8080` (lấy IP bằng `hostname -I` trên VM).
- Giám sát qua SSH tunnel (giữ cửa sổ mở):
  ```powershell
  ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 <user>@<VM_IP>
  ```
  Grafana http://localhost:3000 · Prometheus http://localhost:9090/targets (mọi target UP) · Alertmanager http://localhost:9093

## 6. (Tuỳ chọn) Chuyển dữ liệu từ hệ thống cũ

- Từ bản backup của VM cũ: chép file `taskdb-*.dump` và `.sha256` vào `/opt/taskmanager/backups/`, rồi `bash scripts/restore.sh /opt/taskmanager/backups/<file>.dump`.
- Từ PostgreSQL cài trên host (Week 1): `bash scripts/migrate-host-db-to-docker.sh`.

## 7. Vận hành hằng ngày

| Việc | Lệnh |
|------|------|
| Trạng thái | `cd /opt/taskmanager && docker compose ps` |
| Log app | `docker compose logs --timestamps --since 30m app` |
| Backup ngay | `bash /opt/taskmanager/scripts/backup.sh` |
| Restore | `bash /opt/taskmanager/scripts/restore.sh <file.dump>` |
| Cập nhật phiên bản | Push lên `main` (hoặc *Run workflow*); không sửa tay file trong `/opt/taskmanager` vì lần deploy sau sẽ ghi đè |
| Chạy lại một phiên bản cũ | Sửa `APP_IMAGE=ghcr.io/trvannhan/devops-final-task-manager:<sha cũ>` trong `.env`, rồi `docker compose up -d app` |
| Xử lý sự cố | [`playbook.md`](playbook.md) |

## 8. Lỗi hay gặp khi dựng máy mới

| Hiện tượng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Job Deploy đứng ở *Queued* | Runner chưa cài hoặc offline | Bước 3; playbook mục 7 |
| Deploy đỏ ở *Write .env* | Thiếu secret | Bước 2, rồi *Re-run failed jobs*; playbook mục 5 |
| Deploy đỏ: `permission denied ... docker.sock` | Runner khởi động trước khi user vào nhóm `docker` | `cd ~/actions-runner && sudo ./svc.sh stop && sudo ./svc.sh start` |
| Deploy đỏ: `address already in use :8000` | App Week 1 (systemd) còn chạy | `sudo systemctl disable --now taskmanager` |
| Windows không vào được `:8080` | UFW, Nginx hoặc IP VM đổi | Playbook mục 8 |

