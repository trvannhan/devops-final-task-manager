# DevOps Task Manager — Final Project 2026

Ứng dụng web Flask + JSON API + cơ sở dữ liệu PostgreSQL, chạy trên máy ảo Ubuntu phía sau reverse proxy Nginx.

| Tuần | Cách triển khai | Hướng dẫn |
|------|-----------------|-----------|
| Week 1 | Thủ công: venv + systemd + PostgreSQL cài trên VM | [Hướng dẫn cài đặt thủ công](#hướng-dẫn-cài-đặt-thủ-công-week-1) |
| Week 2 | Docker Compose + GitHub Actions CI/CD, deploy tự động qua self-hosted runner | [Week 2](#week-2-docker-compose-và-cicd) |
| Week 3 | Giám sát (Prometheus, Grafana, Alertmanager), bảo mật, backup/restore, playbook | [Week 3](#week-3-giám-sát-bảo-mật-và-backup) |
| **Week 4** | Bản final: deployment guide từ máy sạch, sơ đồ final, playbook 8 sự cố, technical report, demo | [Week 4](#week-4-final-demo-và-troubleshooting) |

**Bản phát hành final:** [`v1.0.0`](https://github.com/trvannhan/devops-final-task-manager/releases/tag/v1.0.0) · **Báo cáo kỹ thuật:** [`docs/DevOps_Final_Project_2026_Technical_Report.docx`](docs/DevOps_Final_Project_2026_Technical_Report.docx)

> **Triển khai mới từ đầu:** làm theo [`docs/deployment-guide.md`](docs/deployment-guide.md) (không cần các bước thủ công của Week 1). Các phần Week 1–3 bên dưới giữ lại làm lịch sử và minh chứng từng checkpoint.

## Nguồn code và phạm vi
- Nguồn: mã nguồn ứng dụng được viết với sự hỗ trợ của trợ lý AI, sau đó nhóm review, kiểm thử và triển khai. Không sao chép template từ dự án bên thứ ba.
- Phần nhóm tự thực hiện: mã nguồn ứng dụng, thiết kế kiến trúc triển khai, cấu hình Ubuntu/Nginx/systemd/UFW, tài liệu.

## Chức năng
- Xem danh sách công việc, thêm công việc, đánh dấu hoàn thành/làm lại, xóa.
- API: `GET /health`, `GET /api/tasks`, `POST /api/tasks`, `PATCH /api/tasks/<id>`, `DELETE /api/tasks/<id>`.
- Dữ liệu lưu trong PostgreSQL (không lưu trên trình duyệt), nên vẫn còn sau khi tải lại trang hoặc khởi động lại máy.

## Kiến trúc
Kiến trúc final (Week 4): Trình duyệt → UFW → Nginx `:8080` trên VM → container app (`127.0.0.1:8000`) → container PostgreSQL (volume `pgdata`); GitHub Actions deploy qua self-hosted runner; Prometheus/Grafana/Alertmanager giám sát; cron backup hằng ngày.

![Sơ đồ kiến trúc final](docs/architecture-final.png)

Chi tiết từng lớp và lý do thiết kế: [`docs/architecture.md`](docs/architecture.md). Sơ đồ Week 1 (triển khai thủ công) bên dưới; sơ đồ Week 2 ở [phần Week 2](#kiến-trúc-week-2).

Week 1: Trình duyệt -> Nginx trên VM (`:8080`) -> Gunicorn/Flask (`127.0.0.1:8000`) -> PostgreSQL (`127.0.0.1:5432`) -> ổ đĩa VM.

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

## Hướng dẫn cài đặt thủ công (Week 1)
Phần này mô tả cách triển khai Week 1 (Ubuntu 26.04). Từ Week 2, ứng dụng chạy bằng Docker, xem [Week 2](#week-2-docker-compose-và-cicd).

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
.venv/bin/pip install -r requirements-dev.txt
sudo install -m 600 /dev/null /etc/devops-task-manager.env
sudo nano /etc/devops-task-manager.env
```
Trong file môi trường, ghi dòng
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

## Week 2: Docker Compose và CI/CD

### Kiến trúc Week 2
![Kiến trúc Week 2](docs/architecture-week2.png)

- **CI/CD:** mỗi commit lên `main` chạy 3 job: *Test* (máy GitHub, có PostgreSQL 18 tạm, 6 test) → *Build & push* (image gắn tag mã commit, đẩy lên `ghcr.io`) → *Deploy* (self-hosted runner trong VM kéo image mới, `docker compose up -d`, rồi smoke test `/health`). Test lỗi thì pipeline dừng; Pull Request chỉ chạy Test.
- **Vận hành:** Trình duyệt → UFW → Nginx `:8080` trên VM (giữ từ Week 1) → container `app` (`127.0.0.1:8000`) → container `db` (PostgreSQL 18, chỉ trong network `backend`) → volume `pgdata`.
- **Vì sao dùng self-hosted runner:** VM dùng mạng NAT, không có IP public, nên GitHub không thể SSH vào VM. Runner chạy trong VM tự kết nối ra GitHub qua HTTPS để nhận job deploy, không cần mở thêm cổng nào.

File nguồn sơ đồ có thể chỉnh sửa: [`docs/architecture-week2.svg`](docs/architecture-week2.svg).

### Các file của Week 2
| File | Vai trò |
|------|---------|
| `Dockerfile` | Image `python:3.14-slim`, cài thư viện trước để tận dụng cache, chạy Gunicorn bằng user không phải root, có `HEALTHCHECK` |
| `.dockerignore` | Loại `.git`, tests, docs, evidence... khỏi image |
| `docker-compose.yml` | Service `app` + `db` (PostgreSQL 18), network `backend`, volume `pgdata`; app chỉ mở `127.0.0.1:8000` |
| `.github/workflows/ci-cd.yml` | Pipeline test → build → deploy |
| `tests/test_integration.py` | Test CRUD với PostgreSQL thật; test lỗi làm pipeline fail |
| `requirements-dev.txt` | Thư viện cho test (pytest), tách khỏi image chạy thật |
| `scripts/migrate-host-db-to-docker.sh` | Chuyển dữ liệu Week 1 sang container (chạy một lần) |

Phiên bản đang chạy (7 ký tự đầu của commit) hiển thị ở `GET /health` (`"version"`) và ở chân trang web, dùng để chứng minh deploy thành công.

### Cài đặt trên VM (làm một lần)
**1. Cài Docker và cho user `vannhan` dùng Docker**
```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker vannhan
newgrp docker
docker compose version
```

**2. Tạo thư mục deploy**
```bash
sudo install -d -o vannhan -g vannhan -m 750 /opt/taskmanager
```

**3. Tạo secret trên GitHub**: repository → *Settings* → *Secrets and variables* → *Actions* → *New repository secret*, tên `POSTGRES_PASSWORD`, giá trị là mật khẩu mới chỉ gồm chữ và số.

**4. Dừng app Week 1** để giải phóng cổng 8000 (Nginx và PostgreSQL trên VM giữ nguyên):
```bash
sudo systemctl disable --now taskmanager
```

**5. Cài self-hosted runner**: repository → *Settings* → *Actions* → *Runners* → *New self-hosted runner* → chọn *Linux*, *x64*. Chạy các lệnh GitHub hiển thị (tải về, `./config.sh --url ... --token ...`, nhấn Enter để giữ tên và label mặc định), sau đó cài runner thành service:
```bash
cd ~/actions-runner
sudo ./svc.sh install vannhan
sudo ./svc.sh start
```
Runner hiện trạng thái **Idle** (màu xanh) trong trang *Runners* là được.

**6. Chạy pipeline**: push một commit lên `main`. Nếu job bị lỗi hoặc bị hủy, vào tab *Actions* → chọn lượt chạy → **Re-run failed jobs**.

**7. Chuyển dữ liệu Week 1 sang container** (một lần, sau khi deploy đầu tiên thành công):
```bash
cd ~/devops-final-task-manager && git pull
bash scripts/migrate-host-db-to-docker.sh
```

### Kiểm tra
```bash
cd /opt/taskmanager
docker compose ps                       # app và db: running (healthy)
curl -s http://127.0.0.1:8080/health; echo   # có "version":"<7 ký tự commit>"
docker volume ls | grep pgdata
docker compose exec db psql -U taskapp -d taskdb -c 'SELECT id,title,completed FROM tasks ORDER BY id;'
```

### Demo Week 2
1. **Persistence**: thêm một task trên web, rồi xóa và tạo lại container; task vẫn còn.
   ```bash
   cd /opt/taskmanager
   docker compose down          # xóa container, KHÔNG dùng -v (sẽ xóa volume)
   docker compose up -d
   ```
2. **Commit → pipeline → bản mới**: sửa một dòng nhỏ (ví dụ chữ trong `app/templates/index.html`), commit và push lên `main`; mở tab *Actions* xem 3 job chuyển xanh; tải lại web thấy nội dung mới và số version ở chân trang trùng với commit vừa push.
3. **Test thất bại**: tạo nhánh, cố ý làm sai một assert trong `tests/`, mở Pull Request; job *Test* báo đỏ, job *Build* và *Deploy* không chạy.

### Hồ sơ nộp Week 2
- [x] `Dockerfile` + `docker-compose.yml`
- [x] Workflow `.github/workflows/ci-cd.yml`
- [x] Test source (`tests/`)
- [x] Ảnh workflow chạy xanh cả 3 job (`evidence/week2/05`, `06`)
- [x] Ảnh `docker compose ps`, volume và dữ liệu còn sau khi tạo lại container (`evidence/week2/01`, `04`)
- [x] Ảnh phiên bản trước (`v1b21dc9`) và sau khi deploy (`v983f55d`) (`evidence/week2/03`, `07`)
- [x] Ảnh pipeline fail khi test lỗi qua Pull Request (`evidence/week2/08`, `09`)

## Week 3: Giám sát, bảo mật và backup

### Tổng quan
| Yêu cầu | Cách làm | File |
|---------|----------|------|
| Giám sát CPU, RAM, health | node-exporter (CPU/RAM/disk VM) + blackbox (gọi `/health` qua Nginx và thẳng container app) → Prometheus → Grafana | `monitoring/` |
| Dashboard + cảnh báo | Dashboard *Task Manager – Tổng quan hệ thống*; 7 luật cảnh báo, có unit test (`promtool test rules`) chạy trong CI | `monitoring/grafana/`, `monitoring/prometheus/alerts*.yml` |
| Log ứng dụng | Gunicorn ghi access log ra stdout, Docker lưu json-file (giới hạn 10 MB x 3 file mỗi container) | `docker-compose.yml` |
| Firewall, cổng | UFW chỉ mở 22, 8080 (80 là project khác); mọi cổng giám sát chỉ trên 127.0.0.1 | [`docs/security.md`](docs/security.md) |
| Secrets | GitHub Secrets → `.env` quyền 600, không có mật khẩu trong Git | [`docs/security.md`](docs/security.md) |
| Phân quyền DB | App dùng role `taskapp_rw` chỉ có SELECT/INSERT/UPDATE/DELETE | `scripts/db-roles.sql` |
| Backup | `pg_dump` hằng ngày 02:00 (cron), giữ 7 ngày, kiểm tra sha256, cảnh báo nếu quá 26 giờ chưa backup | `scripts/backup.sh` |
| Restore | Kiểm tra sha256 → lưu trạng thái hiện tại → dừng app → `pg_restore` trong 1 transaction → chạy lại app | `scripts/restore.sh` |
| Xử lý sự cố | 8 sự cố (3 đã xảy ra thật) | [`docs/playbook.md`](docs/playbook.md) |

### Cài đặt (làm một lần)
1. Tạo thêm 2 secret trong **Settings → Secrets and variables → Actions** (chỉ chữ và số, ví dụ `openssl rand -hex 16`):
   - `APP_DB_PASSWORD`: mật khẩu role `taskapp_rw` của ứng dụng
   - `GRAFANA_ADMIN_PASSWORD`: mật khẩu đăng nhập Grafana (user `admin`)
2. Push lên `main`. Nếu job *Deploy* đỏ vì thiếu secret, tạo đủ secret rồi bấm **Re-run failed jobs**. Pipeline tự: copy cấu hình giám sát và script, tạo `.env`, áp dụng phân quyền DB, chạy toàn bộ container, cài cron backup 02:00, kiểm tra Prometheus/Alertmanager/Grafana.

### Xem dashboard từ Windows (SSH tunnel)
Các cổng giám sát không mở ra ngoài. Trên PowerShell của Windows chạy (để cửa sổ này mở trong lúc xem):
```powershell
ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 vannhan@<VM_IP>
```
Rồi mở trên trình duyệt Windows:
- Grafana: http://localhost:3000 (user `admin`) → *Dashboards → Task Manager → Task Manager – Tổng quan hệ thống*
- Prometheus: http://localhost:9090 (*Alerts*, *Status → Targets*)
- Alertmanager: http://localhost:9093

### Kiểm tra cảnh báo
```bash
cd /opt/taskmanager
docker compose stop app      # sau 30-45 giây: AppContainerDown bật (Prometheus Alerts, Alertmanager, Grafana)
docker compose start app     # sau 15-30 giây: cảnh báo tự hết
```

### Tra cứu log theo thời gian
```bash
cd /opt/taskmanager
docker compose logs --timestamps --since 30m app                      # 30 phút gần nhất
docker compose logs --timestamps --since 2026-11-05T14:00:00 --until 2026-11-05T14:15:00 app
docker compose logs --since 1h app | grep -E '" (4|5)[0-9]{2} '       # chỉ request lỗi 4xx/5xx
docker compose logs --since 1h app | grep -iE 'error|exception'        # lỗi của ứng dụng
sudo tail -n 50 /var/log/nginx/error.log                              # lỗi phía Nginx
```

### Backup và restore
```bash
bash /opt/taskmanager/scripts/backup.sh                     # backup ngay
ls -lh /opt/taskmanager/backups/                            # các bản backup + .sha256
tail -n 20 /opt/taskmanager/backups/backup.log              # log của backup tự động
crontab -l | grep taskmanager-backup                        # lịch 02:00 hằng ngày
bash /opt/taskmanager/scripts/restore.sh                    # liệt kê bản backup
bash /opt/taskmanager/scripts/restore.sh /opt/taskmanager/backups/taskdb-YYYYMMDD-HHMMSS.dump
```
Chiến lược lưu trữ: 1 bản mỗi ngày, giữ 7 ngày gần nhất (bản `pre-restore-*` tạo trước mỗi lần restore cũng giữ 7 ngày); thư mục `backups/` quyền 700. Nên chép định kỳ một bản ra ngoài VM (ví dụ `scp` về máy Windows) để phòng mất cả VM.

### Hồ sơ nộp Week 3
- [x] Cấu hình dashboard, cảnh báo: `monitoring/`
- [x] Security/ports checklist: [`docs/security.md`](docs/security.md)
- [x] Backup và restore scripts: `scripts/backup.sh`, `scripts/restore.sh`
- [x] Incident playbook: [`docs/playbook.md`](docs/playbook.md)
- [x] Ảnh minh chứng giám sát và cảnh báo: dashboard lúc bình thường và lúc sự cố, Prometheus/Alertmanager lúc cảnh báo bật và đã tắt (`evidence/week3/01`–`08`, mô tả trong `evidence/week3/README.md`)
- [x] Ảnh log backup và restore (`evidence/week3/09`–`10`)

## Week 4: Final demo và troubleshooting

### Tài liệu final
| Tài liệu | Nội dung |
|----------|----------|
| [`docs/deployment-guide.md`](docs/deployment-guide.md) | Dựng lại toàn bộ hệ thống từ Ubuntu sạch: `scripts/bootstrap-vm.sh` → GitHub Secrets → runner → pipeline → kiểm tra |
| [`scripts/bootstrap-vm.sh`](scripts/bootstrap-vm.sh) | Cài gói, Docker, Nginx `:8080`, UFW (22, 8080), thư mục `/opt/taskmanager`; chạy lại nhiều lần không sao |
| [`docs/architecture.md`](docs/architecture.md) | Sơ đồ final + lý do thiết kế từng lớp |
| [`docs/playbook.md`](docs/playbook.md) | 8 sự cố (3 đã xảy ra thật), mỗi mục: triệu chứng → xác minh → nguyên nhân → khắc phục → phòng tránh |
| [`docs/security.md`](docs/security.md) | Cổng/firewall, secrets, phân quyền DB, container |
| [`docs/technical-report.md`](docs/technical-report.md) | Báo cáo kỹ thuật theo chuẩn rubric (bản Word: [`docs/DevOps_Final_Project_2026_Technical_Report.docx`](docs/DevOps_Final_Project_2026_Technical_Report.docx)) |

### Demo end-to-end
1. **Commit → CI/CD → bản mới**: sửa chữ trong `app/templates/index.html`, push lên `main`; tab *Actions* 3 job xanh; web và `/health` hiện version mới trùng 7 ký tự đầu của commit.
2. **Giám sát**: Grafana (CPU/RAM, trạng thái `/health` qua Nginx và thẳng app), Prometheus *Targets* đều UP, `docker compose logs`.
3. **Bảo mật**: `sudo ufw status verbose`, `sudo ss -lntp` (chỉ 22, 8080 mở ra ngoài), `.env` quyền 600, role `taskapp_rw` không `DROP TABLE` được.
4. **Backup/restore**: `backup.sh` → thêm task thử nghiệm → `restore.sh` → task thử nghiệm biến mất, số task trở về như lúc backup.
5. **Troubleshooting**: gây một lỗi trong bảng dưới, khoanh vùng bằng `docker compose ps` và 2 lệnh `curl` `/health` (qua Nginx `:8080` và thẳng app `:8000`), khắc phục theo [`docs/playbook.md`](docs/playbook.md).

| Lỗi có thể demo | Playbook |
|---|---|
| Container stopped | Mục 1 |
| Database mất kết nối | Mục 2 |
| Sai biến môi trường | Mục 3 |
| Lỗi cấu hình proxy | Mục 4 |
| Dịch vụ không truy cập được | Mục 8 |

### Hồ sơ nộp Week 4
- [x] Sơ đồ kiến trúc final: `docs/architecture-final.png` (nguồn `.svg`)
- [x] Deployment guide từ máy sạch + `scripts/bootstrap-vm.sh`
- [x] Troubleshooting playbook ≥ 3 sự cố (hiện có 8)
- [x] Ảnh minh chứng end-to-end bản final `c7bb2f4`: pipeline, smoke test, web (`evidence/week4/01`–`03`, mô tả trong [`evidence/week4/README.md`](evidence/week4/README.md))
- [x] Troubleshooting: demo trực tiếp trong buổi báo cáo theo `docs/playbook.md`
- [x] Technical report 6–10 trang: [`docs/DevOps_Final_Project_2026_Technical_Report.docx`](docs/DevOps_Final_Project_2026_Technical_Report.docx) (nguồn Markdown: [`docs/technical-report.md`](docs/technical-report.md))
- [ ] Video demo final 5–10 phút
- [x] Release/tag [`v1.0.0`](https://github.com/trvannhan/devops-final-task-manager/releases/tag/v1.0.0) (commit `059b4c9`)

## Phân công nhiệm vụ
| Thành viên | MSSV | Week 1 | Week 2–4 | Minh chứng |
|------------|------|--------|----------|------------|
| Trần Văn Nhân (nhóm trưởng) | 23090036 | Máy ảo Ubuntu và SSH, Flask app/API, GitHub repository | `Dockerfile`, `docker-compose.yml`; CI/CD GitHub Actions (Test → Build & push ghcr.io → Deploy), self-hosted runner, smoke test; deployment guide và `scripts/bootstrap-vm.sh`; sơ đồ kiến trúc final; tổng hợp technical report; xử lý 3 sự cố thật (playbook mục 5–7) | `.github/workflows/ci-cd.yml`, `evidence/week2/`, `docs/deployment-guide.md`, `docs/technical-report.md` |
| Trần Văn Lực | 23090019 | Firewall UFW, triển khai Nginx + systemd, sơ đồ kiến trúc | Giám sát Prometheus, Grafana (dashboard 11 panel), Alertmanager, blackbox; 7 luật cảnh báo và `promtool test rules`; checklist bảo mật (cổng, firewall, 2 mạng Docker); playbook mục 1, 4, 8 | `monitoring/`, `docs/security.md`, `evidence/week3/01`–`08` |
| Nguyễn Vũ Hoàng Long | 23090026 | Database PostgreSQL và CRUD, README, video demo | Chuyển dữ liệu Week 1 vào container; phân quyền DB (`taskapp_rw`); backup/restore, cron 02:00 và cảnh báo BackupTooOld; playbook mục 2, 3; README; ảnh minh chứng Week 4 và video final | `scripts/backup.sh`, `scripts/restore.sh`, `scripts/db-roles.sql`, `evidence/week3/09`–`10`, video |

Phần trình bày Week 4:
| Phần | Người trình bày |
|------|-----------------|
| Kiến trúc và trách nhiệm thành viên (3 phút) | Trần Văn Nhân |
| Commit → pipeline → production (5–7 phút) | Trần Văn Nhân |
| Giám sát và bảo mật | Trần Văn Lực |
| Backup và restore | Nguyễn Vũ Hoàng Long |
| Live troubleshooting | Người phụ trách mục playbook tương ứng: Lực (container dừng, proxy, không truy cập được), Long (database, sai biến môi trường) |

## Hướng phát triển
Chưa làm trong phạm vi đồ án: chạy thử deployment guide trên một VM hoàn toàn mới, rollback tự động khi smoke test lỗi, quét lỗ hổng image (Trivy), gửi cảnh báo qua Telegram/Email, HTTPS cho Nginx, sao lưu ra ngoài VM.
