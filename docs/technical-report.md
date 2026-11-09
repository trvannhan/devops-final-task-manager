# Từ phát triển đến vận hành: Triển khai tự động và tin cậy ứng dụng Task Manager trên Ubuntu với Docker, GitHub Actions và Prometheus

**Môn học:** DevOps – Final Project 2026
**Nhóm thực hiện:** Trần Văn Nhân (23090036 – Nhóm trưởng) · Trần Văn Lực (23090019) · Nguyễn Vũ Hoàng Long (23090026)
**Repository:** https://github.com/trvannhan/devops-final-task-manager (Release tag: `v1.0.0`)

---

## Tóm tắt (Abstract)

Báo cáo này trình bày quá trình thiết kế, triển khai, tự động hóa, giám sát và vận hành ứng dụng web quản lý công việc (Task Manager) sử dụng Flask và PostgreSQL trên máy ảo Ubuntu 26.04.1 LTS xuyên suốt 4 tuần của đồ án môn học DevOps. Hệ thống cung cấp giao diện web và REST API để tạo, xem, đánh dấu hoàn thành và xóa công việc, với dữ liệu được lưu trữ bền vững trong PostgreSQL 18. Về mặt triển khai, ứng dụng và cơ sở dữ liệu được đóng gói bằng Docker Compose phía sau reverse proxy Nginx ở cổng 8080; quy trình CI/CD trên GitHub Actions tự động thực hiện ba giai đoạn kiểm thử (`pytest`, `promtool`, `amtool`), đóng gói Docker image gắn nhãn mã commit đẩy lên GitHub Container Registry (`ghcr.io`), và triển khai xuống máy ảo thông qua self-hosted runner kết nối chủ động ra ngoài mạng NAT kèm bước smoke test xác minh phiên bản. Về giám sát và độ tin cậy, stack Prometheus, Alertmanager, Grafana, node-exporter và blackbox-exporter theo dõi tài nguyên máy chủ và hai đường kiểm tra `/health` (qua Nginx và trực tiếp vào container app) với 7 luật cảnh báo đã được kiểm thử tự động và thực nghiệm phát hiện sự cố dừng ứng dụng trong khoảng 30–45 giây. Về bảo mật và an toàn dữ liệu, tường lửa UFW chỉ mở cổng 22 và 8080, các cổng giám sát chỉ lắng nghe trên `127.0.0.1` truy cập qua SSH tunnel, thông tin mật được quản lý qua GitHub Secrets, và ứng dụng kết nối database bằng role quyền tối thiểu `taskapp_rw` (bị từ chối khi thử `DROP TABLE`). Quy trình sao lưu hằng ngày lúc 02:00 bằng `pg_dump` kèm kiểm tra toàn vẹn `sha256`, tích hợp cảnh báo `BackupTooOld` và kịch bản khôi phục an toàn đã được kiểm chứng thực tế trên dữ liệu thử nghiệm.

**Từ khóa:** DevOps, CI/CD, Docker Compose, GitHub Actions, Self-hosted Runner, Prometheus, Grafana, PostgreSQL, Backup and Restore.

---

## 1. Giới thiệu

### 1.1. Bối cảnh dự án và mục tiêu
Trong quy trình phát triển phần mềm truyền thống, việc triển khai thủ công ứng dụng lên máy chủ thường dẫn đến sai lệch cấu hình giữa các môi trường (configuration drift), tốn thời gian khi phát hành bản cập nhật, thiếu công cụ phát hiện sớm khi dịch vụ ngưng trệ và tiềm ẩn rủi ro mất dữ liệu nếu không có quy trình sao lưu/khôi phục được kiểm chứng. Mục tiêu của dự án là xây dựng một hệ thống DevOps đầu-cuối (end-to-end) cho một ứng dụng Web/API có cơ sở dữ liệu quan hệ, đáp ứng đầy đủ các tiêu chí: tự động hóa kiểm thử và triển khai, khả năng tái tạo môi trường từ máy sạch (reproducibility), giám sát và cảnh báo chủ động, bảo mật theo nguyên tắc quyền tối thiểu và sẵn sàng phục hồi sau sự cố.

### 1.2. Phạm vi chức năng, nguồn code và công nghệ lựa chọn
- **Phạm vi chức năng ứng dụng:** Ứng dụng Task Manager cung cấp giao diện quản lý công việc trực quan và 5 REST API endpoints: `GET /health` (kiểm tra kết nối thực tế tới PostgreSQL bằng truy vấn `SELECT 1` và trả về phiên bản mã commit đang chạy), `GET /api/tasks` (lấy danh sách công việc), `POST /api/tasks` (thêm công việc mới, kiểm tra hợp lệ tiêu đề 1–200 ký tự và mô tả tối đa 1000 ký tự), `PATCH /api/tasks/<id>` (đánh dấu hoàn thành/làm lại), và `DELETE /api/tasks/<id>` (xóa công việc).
- **Nguồn code và phạm vi tự thực hiện:** Mã nguồn ứng dụng (`app/main.py`, `app/templates/index.html`, `app/static/`) được khởi tạo với sự hỗ trợ của trợ lý AI, sau đó các thành viên trong nhóm trực tiếp rà soát, viết bộ kiểm thử tự động, thiết kế kiến trúc hạ tầng, viết cấu hình Docker/Compose, xây dựng workflow CI/CD, thiết lập hệ thống giám sát Prometheus/Grafana, viết kịch bản sao lưu/khôi phục, cấu hình bảo mật Ubuntu/Nginx/UFW và biên soạn toàn bộ tài liệu vận hành. Dự án không sao chép khuôn mẫu (template) có sẵn của bên thứ ba.

*Bảng 1. Ngăn xếp công nghệ (Technology Stack) đã lựa chọn và lý do sử dụng*

| Tầng hệ thống | Công nghệ lựa chọn | Lý do lựa chọn trong kiến trúc DevOps |
|---|---|---|
| **Ảo hóa & Hệ điều hành** | VMware Workstation (NAT – VMnet8), Ubuntu 26.04.1 LTS (2 vCPU, 4 GB RAM, 35 GB Disk) | Môi trường Linux chuẩn công nghiệp, cô lập hoàn toàn với máy host Windows, hỗ trợ tạo snapshot để kiểm thử quy trình cài đặt từ máy sạch. |
| **Reverse Proxy** | Nginx (trên host Ubuntu, lắng nghe `:8080`) | Hiệu năng cao, tách biệt điểm vào của người dùng với container ứng dụng, đồng thời giữ cho dự án khác ở cổng 80 trên cùng VM hoạt động song song. |
| **Web/API & WSGI** | Python 3.14, Flask 3.1.3, Gunicorn 23.0.0, `psycopg` 3.3.3 | Gọn nhẹ, khởi động nhanh, dễ viết kiểm thử tích hợp (`pytest`) và minh họa rõ luồng kết nối cơ sở dữ liệu cũng như xử lý lỗi `503`. |
| **Cơ sở dữ liệu** | PostgreSQL 18 (`postgres:18`) | Hệ quản trị CSDL quan hệ mạnh mẽ, hỗ trợ phân quyền chi tiết cấp độ bảng/schema (`GRANT`/`REVOKE`) và công cụ sao lưu chuẩn `pg_dump`/`pg_restore`. |
| **Container hóa** | Docker Engine & Docker Compose v2 | Định nghĩa toàn bộ 7 dịch vụ, 2 mạng nội bộ và 4 persistent volumes dưới dạng mã (Infrastructure as Code), đảm bảo môi trường nhất quán. |
| **CI/CD & Registry** | GitHub Actions, GitHub Container Registry (`ghcr.io`), Self-hosted Runner | Tích hợp trực tiếp với mã nguồn trên GitHub; self-hosted runner giải quyết bài toán triển khai tự động vào máy ảo nằm sau mạng NAT. |
| **Giám sát & Cảnh báo** | Prometheus v3.5.0, Alertmanager v0.28.1, Grafana 12.0.0, Node Exporter v1.9.1, Blackbox Exporter v0.27.0 | Bộ công cụ mã nguồn mở tiêu chuẩn cho phép thu thập cả chỉ số phần cứng VM, chỉ số sao lưu (`textfile collector`) và thăm dò HTTP hộp đen, hỗ trợ kiểm thử luật cảnh báo bằng `promtool`. |

### 1.3. Lộ trình 4 tuần và phân công thành viên

*Bảng 2. Lộ trình thực hiện qua 4 mốc kiểm tra (Week 1–4) và phân công nhiệm vụ*

| Thành viên | MSSV | Phụ trách chính (Week 1 → Week 4) | Minh chứng đóng góp |
|---|---|---|---|
| **Trần Văn Nhân** *(Nhóm trưởng)* | 23090036 | **W1:** Thiết lập VM Ubuntu, SSH, Flask API & giao diện web.<br>**W2:** Viết `Dockerfile`, `docker-compose.yml`, workflow `.github/workflows/ci-cd.yml`, cài đặt self-hosted runner.<br>**W4:** Viết `scripts/bootstrap-vm.sh` và `docs/deployment-guide.md`. | Lịch sử commit trên GitHub, cấu hình CI/CD, ảnh minh chứng VM/API/pipeline (`evidence/week2/`). |
| **Trần Văn Lực** | 23090019 | **W1:** Cấu hình tường lửa UFW, Nginx reverse proxy `:8080`, systemd service.<br>**W2–W4:** Thiết kế sơ đồ kiến trúc (`docs/architecture*.svg/png`); cấu hình Prometheus, Alertmanager, Blackbox, Grafana dashboard; kiểm thử cảnh báo; biên soạn `docs/security.md` và `docs/playbook.md`. | Cấu hình trong `monitoring/`, sơ đồ kiến trúc, ảnh minh chứng giám sát & cảnh báo (`evidence/week3/01`–`08`). |
| **Nguyễn Vũ Hoàng Long** | 23090026 | **W1–W2:** Thiết kế `schema.sql`, viết bộ test đơn vị & tích hợp (`tests/test_app.py`, `tests/test_integration.py`), script di trú dữ liệu.<br>**W3–W4:** Phân quyền `scripts/db-roles.sql`, viết và kiểm chứng `scripts/backup.sh`, `scripts/restore.sh`; biên soạn `README.md`, báo cáo kỹ thuật và dựng video demo. | Minh chứng SQL, bộ test CRUD, ảnh backup/restore (`evidence/week3/09`–`10`), báo cáo và video. |

---

## 2. Kiến trúc hệ thống

### 2.1. Sơ đồ kiến trúc hoàn chỉnh (Final Architecture)

![Hình 1. Sơ đồ kiến trúc hoàn chỉnh của hệ thống Task Manager (Final, Week 1–4)](architecture-final.png)

*Hình 1. Sơ đồ kiến trúc hoàn chỉnh của hệ thống Task Manager bao gồm luồng CI/CD, luồng xử lý yêu cầu, phân tách mạng Docker, hệ thống giám sát và sao lưu tự động.*

### 2.2. Mô tả từng thành phần và luồng xử lý yêu cầu (Request Flow)
1. **Trình duyệt người dùng → Tường lửa UFW:** Người dùng trên máy host Windows truy cập ứng dụng tại địa chỉ `http://<VM_IP>:8080`. Tường lửa UFW đóng vai trò chốt chặn đầu tiên với chính sách mặc định từ chối mọi kết nối đi vào (`deny incoming`), chỉ cho phép cổng `22/tcp` (SSH) và `8080/tcp`.
2. **Nginx Reverse Proxy (trên host Ubuntu):** Nginx lắng nghe ở cổng `8080`, tiếp nhận HTTP request từ người dùng và chuyển tiếp (`proxy_pass http://127.0.0.1:8000`) kèm các header chuẩn (`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`). Việc đặt Nginx trên host thay vì trong container giúp giữ nguyên cấu hình ổn định từ Tuần 1 và không làm ảnh hưởng tới một dự án môn học khác đang dùng chung Nginx ở cổng 80.
3. **Container `app` (Gunicorn + Flask):** Chạy 2 tiến trình worker Gunicorn, chỉ gắn cổng vào giao diện loopback của máy chủ (`127.0.0.1:8000:8000`). Ứng dụng xử lý logic nghiệp vụ và mở kết nối tới `db:5432` thông qua mạng nội bộ `backend` bằng tài khoản giới hạn quyền `taskapp_rw`.
4. **Container `db` (PostgreSQL 18) và Volume `pgdata`:** Lưu trữ bảng `tasks` trên Docker named volume `pgdata` gắn tại `/var/lib/postgresql`. Container `db` hoàn toàn không publish cổng 5432 ra máy chủ host.
5. **Khối giám sát và sao lưu:** `blackbox-exporter` thăm dò định kỳ `/health` qua cả Nginx lẫn thẳng vào container `app`; `node-exporter` thu thập chỉ số phần cứng VM và tệp chỉ số sao lưu `backup.prom`; `prometheus` kéo dữ liệu mỗi 15 giây, đánh giá 7 luật cảnh báo và đẩy sang `alertmanager`; `grafana` truy vấn Prometheus để hiển thị dashboard thời gian thực.

### 2.3. Quy hoạch cổng dịch vụ và lý do chỉ mở `127.0.0.1` cho giám sát

*Bảng 3. Bảng quy hoạch cổng dịch vụ trên máy ảo Ubuntu*

| Cổng | Dịch vụ / Thành phần | Địa chỉ lắng nghe | Mở trên UFW | Lý do thiết kế |
|---|---|---|---|---|
| `22/tcp` | OpenSSH Server (`sshd`) | `0.0.0.0` / `[::]` | **Có** | Quản trị hệ thống từ xa và tạo đường hầm SSH (SSH tunnel) để xem các giao diện giám sát nội bộ. |
| `8080/tcp` | Nginx Reverse Proxy (Task Manager) | `0.0.0.0` / `[::]` | **Có** | Cổng duy nhất phục vụ người dùng cuối truy cập giao diện web và REST API. |
| `80/tcp` | Nginx (dự án `devops-app` khác) | `0.0.0.0` / `[::]` | Có (ngoài phạm vi) | Giữ nguyên để hai dự án môn học chạy song song trên cùng máy ảo. |
| `8000/tcp` | Container `app` (Gunicorn) | `127.0.0.1` | **Không** | Chặn truy cập trực tiếp từ mạng ngoài vào Gunicorn; mọi request bắt buộc phải đi qua Nginx `:8080`. |
| `5432/tcp` | Container `db` (PostgreSQL 18) | Chỉ trong mạng `backend` | **Không** | Không publish ra host; chỉ container `app` và lệnh quản trị nội bộ mới kết nối được vào database. |
| `9090/tcp` | Container `prometheus` | `127.0.0.1` | **Không** | Prometheus không có xác thực đăng nhập mặc định; nếu mở ra mạng ngoài sẽ làm lộ cấu hình và chỉ số hệ thống. |
| `9093/tcp` | Container `alertmanager` | `127.0.0.1` | **Không** | Alertmanager không có xác thực mặc định; nếu lộ ra ngoài, kẻ xấu có thể tạo *Silence* để vô hiệu hóa cảnh báo. |
| `3000/tcp` | Container `grafana` | `127.0.0.1` | **Không** | Không phơi trang đăng nhập quản trị ra mạng; quản trị viên truy cập an toàn qua SSH tunnel. |

---

## 3. Containerization

### 3.1. Thiết kế `Dockerfile`: Các lựa chọn tối ưu và bảo mật
Tệp `Dockerfile` đóng gói ứng dụng Flask/Gunicorn được thiết kế với các quyết định kỹ thuật cụ thể sau:
- **Base image `python:3.14-slim` và lý do không dùng multi-stage build:** Ứng dụng chỉ sử dụng 3 thư viện trong `requirements.txt` (`Flask==3.1.3`, `gunicorn==23.0.0`, `psycopg[binary]==3.3.3`). Do tất cả đều là gói Python thuần hoặc đã có gói nhị phân dựng sẵn (`wheel`), quá trình cài đặt không cần trình biên dịch C (`gcc`, `build-essential`) hay thư viện phát triển hệ thống (`libpq-dev`), đồng thời phần giao diện sử dụng HTML/CSS/JS thuần không có bước biên dịch Node.js/Webpack. Vì vậy, việc dùng trực tiếp `python:3.14-slim` kết hợp biến môi trường `PIP_NO_CACHE_DIR=1`, tệp `.dockerignore` (loại bỏ `.git`, `.venv`, `tests/`, `docs/`, `evidence/`) và tách riêng `requirements-dev.txt` (không cài `pytest` vào image chạy thật) đã mang lại image nhỏ gọn, sạch sẽ mà không cần đến multi-stage build.
- **Tối ưu hóa bộ nhớ đệm lớp (Layer Caching):** Lệnh `COPY requirements.txt .` và `RUN pip install -r requirements.txt` được đặt **trước** lệnh `COPY app ./app`. Khi lập trình viên chỉ sửa mã nguồn Python hoặc giao diện HTML, Docker Buildx tái sử dụng hoàn toàn lớp thư viện đã cài đặt từ cache, giúp giảm thời gian build trên CI từ **19 giây** (không cache) xuống chỉ còn **7 giây** (có cache).
- **Chạy bằng tài khoản không đặc quyền (Non-root User):** Tạo tài khoản hệ thống `RUN useradd --system --uid 10001 --no-create-home appuser` và chuyển ngữ cảnh bằng `USER appuser` trước khi chạy Gunicorn. Nếu ứng dụng gặp lỗ hổng thực thi mã từ xa (RCE), tiến trình bên trong container cũng không có quyền `root`.
- **Nhúng phiên bản mã nguồn (`APP_VERSION`) và `HEALTHCHECK` tự động:** Sử dụng `ARG APP_VERSION=dev` và `ENV APP_VERSION=${APP_VERSION}` để pipeline truyền 7 ký tự đầu của mã commit vào lúc build. Chỉ thị `HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3` dùng chính trình thông dịch Python có sẵn trong image để gọi `http://127.0.0.1:8000/health`, không cần cài thêm `curl` hay `wget` vào image.

### 3.2. Thiết kế `docker-compose.yml`: Network, Volume, Logging và Resource Limits
Tệp `docker-compose.yml` quản lý đồng bộ cả 7 container (`db`, `app`, `prometheus`, `alertmanager`, `node-exporter`, `blackbox`, `grafana`):
- **Thứ tự khởi động phụ thuộc sức khỏe (`depends_on: service_healthy`):** Container `db` được cấu hình healthcheck `pg_isready -U taskapp -d taskdb` mỗi 5 giây; container `app` chỉ được khởi tạo sau khi `db` đã báo `healthy`, tránh lỗi ứng dụng khởi động trước khi PostgreSQL sẵn sàng nhận kết nối. Tương tự, ở lần khởi tạo đầu tiên khi volume còn trống, tệp `./schema.sql` gắn vào `/docker-entrypoint-initdb.d/01-schema.sql:ro` tự động tạo bảng `tasks`.
- **Phân tách 2 mạng (`backend` và `monitoring`) và 4 Named Volumes:** Dữ liệu của PostgreSQL, Prometheus, Alertmanager và Grafana lần lượt được lưu trên 4 volume độc lập (`pgdata`, `prometheus-data`, `alertmanager-data`, `grafana-data`).
- **Xoay vòng nhật ký (Log Rotation) và giới hạn bộ nhớ:** Sử dụng YAML anchor `x-logging: &default-logging` áp dụng cấu hình `driver: json-file` với `max-size: "10m"` và `max-file: "3"` cho toàn bộ 7 dịch vụ (tối đa 30 MB log mỗi container), ngăn chặn triệt để nguy cơ log phình to làm đầy ổ đĩa 35 GB của máy ảo. Các container giám sát đều được áp trần bộ nhớ (`mem_limit`: Prometheus `512m`, Grafana `256m`, Alertmanager `128m`, Node Exporter & Blackbox `64m`) để bảo vệ tài nguyên cho ứng dụng chính.

### 3.3. Thực nghiệm chứng minh tính bền vững dữ liệu (Persistence)
Tại mốc kiểm tra Tuần 2 (`evidence/week2/02-migrate-week1-data.png` và `04-persistence.png`), nhóm đã di trú toàn bộ dữ liệu từ PostgreSQL trên host (Tuần 1) sang container `db` bằng script `scripts/migrate-host-db-to-docker.sh`, thêm mới bản ghi trên giao diện web rồi thực hiện xóa hoàn toàn các container đang chạy bằng lệnh `docker compose down` (không kèm cờ `-v`), sau đó khởi tạo lại bằng `docker compose up -d`. Kết quả kiểm tra trên trình duyệt và câu lệnh `SELECT` trong `psql` xác nhận toàn bộ các công việc trước đó vẫn còn nguyên vẹn trong volume `pgdata`.

---

## 4. CI/CD Pipeline

### 4.1. Cấu trúc Pipeline 3 Job và giải thích từng bước
Pipeline được định nghĩa tại `.github/workflows/ci-cd.yml`, tự động kích hoạt khi `push` hoặc mở `pull_request` vào nhánh `main`, hoặc chạy thủ công qua nút **Run workflow** (`workflow_dispatch`):

```
[Push / PR / Run workflow]
        │
        ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ Job 1: Test (ubuntu-latest + service container postgres:18)               │
│  • pytest -v (3 unit tests + 3 PostgreSQL integration tests CRUD)         │
│  • docker compose config --quiet (kiểm tra cú pháp Compose & biến .env)   │
│  • promtool check config & promtool test rules alerts.test.yml            │
│  • amtool check-config & kiểm tra cú pháp JSON của Grafana dashboard      │
└───────┬───────────────────────────────────────────────────────────────────┘
        │ (Nếu lỗi hoặc là Pull Request → Dừng tại đây, chặn gộp nhánh)
        ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ Job 2: Build & push image (ubuntu-latest, chỉ chạy trên nhánh main)       │
│  • Lấy 7 ký tự đầu của GITHUB_SHA làm APP_VERSION                         │
│  • Buildx build image (cache type=gha) & đẩy lên ghcr.io:<sha> và :latest │
└───────┬───────────────────────────────────────────────────────────────────┘
        ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ Job 3: Deploy to Ubuntu VM (runs-on: [self-hosted, linux], concurrency)   │
│  • Chép docker-compose.yml, schema.sql, monitoring/, scripts/ → /opt/...  │
│  • Kiểm tra đủ 3 GitHub Secrets → tạo /opt/taskmanager/.env (quyền 600)   │
│  • docker compose pull → khởi động db → chạy scripts/db-roles.sql         │
│  • docker compose up -d --no-build --remove-orphans & cài cron backup 2h  │
│  • Smoke test: gọi http://127.0.0.1:8080/health khớp đúng "version":<sha> │
│  • Kiểm tra Prometheus / Alertmanager / Grafana ready → prune image cũ    │
└───────────────────────────────────────────────────────────────────────────┘
```

![Hình 2. Pipeline CI/CD chạy xanh cả 3 job trên GitHub Actions sau khi push commit 983f55d (tổng thời gian 1m 38s)](../evidence/week2/06-commit-pipeline-green.png)

*Hình 2. Minh chứng pipeline thực thi tự động cả 3 job: `Test` (31s) → `Build & push image` (21s) → `Deploy to Ubuntu VM` (34s).*

### 4.2. Self-hosted Runner và lý do lựa chọn cho môi trường VMware NAT
Máy ảo Ubuntu của nhóm hoạt động trong mạng **VMware NAT (VMnet8)** trên máy tính cá nhân: máy ảo chỉ có địa chỉ IP riêng nội bộ và hoàn toàn **không có IP công cộng (public IP)**. Trong mô hình này, các runner đám mây của GitHub không thể mở kết nối SSH chiều đi vào (inbound) tới máy ảo nếu không cấu hình port-forwarding trên router hoặc dùng dịch vụ đường hầm bên thứ ba.

Việc cài đặt **GitHub Actions self-hosted runner** dưới dạng dịch vụ nền (`systemd` service `actions.runner...`, chạy dưới quyền user `vannhan`) ngay bên trong máy ảo đã giải quyết triệt để vấn đề:
- Tiến trình runner từ bên trong máy ảo chủ động mở kết nối **HTTPS chiều đi ra (outbound port 443)** tới máy chủ GitHub để nhận job `Deploy`. Mạng NAT cho phép kết nối chiều đi ra một cách tự nhiên nên không cần mở thêm bất kỳ cổng vào nào trên tường lửa hay router.
- Không phải lưu trữ khóa SSH riêng tư (SSH private key) trên GitHub Secrets, loại bỏ rủi ro lộ quyền truy cập shell của máy chủ nếu tài khoản CI bị xâm phạm.

### 4.3. Quản lý Secrets trong Pipeline, Smoke Test và chặn bản lỗi
- **Luồng truyền Secrets:** Ba biến nhạy cảm (`POSTGRES_PASSWORD`, `APP_DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`) được lưu trong *GitHub Repository Secrets*. Ở job `Deploy`, trước khi chạm vào các container, script kiểm tra nếu thiếu bất kỳ biến nào sẽ báo lỗi `::error::Chưa tạo secret...` và dừng ngay; khi đủ cả 3 biến, script đặt `umask 077` rồi mới ghi ra `/opt/taskmanager/.env` (quyền `600`).
- **Smoke Test xác minh phiên bản:** Sau khi `docker compose up -d`, pipeline không coi việc câu lệnh thoát với mã `0` là đã thành công mà thực hiện vòng lặp gọi `curl -fsS http://127.0.0.1:8080/health` (đi xuyên qua Nginx vào container `app` và kiểm tra tới `db`) trong tối đa 60 giây. Phản hồi JSON bắt buộc phải chứa đúng `"version":"<7 ký tự đầu của GITHUB_SHA vừa push>"` thì bước deploy mới được đánh dấu xanh. Tiếp đó, bước `Check monitoring stack` kiểm tra thêm các endpoint `/-/ready` của Prometheus (`:9090`), Alertmanager (`:9093`) và `/api/health` của Grafana (`:3000`).
- **Kiểm chứng chặn Pull Request lỗi:** Trong thực nghiệm Tuần 2 (`evidence/week2/08-pr-test-fail.png` và `09-test-fail-log.png`), nhóm tạo nhánh mới, cố ý sửa sai một khẳng định kiểm thử và mở Pull Request #1. Job `Test` lập tức báo đỏ sau 25 giây và chặn không cho phép chạy sang giai đoạn Build hay Deploy.

---

## 5. Giám sát, cảnh báo và tra cứu log

### 5.1. Kiến trúc Stack giám sát
Hệ thống giám sát gồm 5 container nằm trong mạng `monitoring`, với chu kỳ thu thập và đánh giá luật là **15 giây** (`scrape_interval: 15s`, `evaluation_interval: 15s`):
- **`node-exporter` (`v1.9.1`):** Gắn `/` của máy chủ vào `/host:ro,rslave` để đo CPU, RAM, dung lượng ổ đĩa `/` và thời gian chạy (uptime) của VM. Đồng thời bật bộ thu thập `--collector.textfile.directory=/textfile` (gắn với `/opt/taskmanager/backups/metrics:ro`) để đọc tệp `backup.prom` do script sao lưu ghi ra.
- **`blackbox-exporter` (`v0.27.0`):** Định nghĩa module `http_health` kiểm tra giao thức HTTP GET trong thời gian chờ 5 giây, yêu cầu mã trạng thái `200` và thân phản hồi phải chứa chuỗi `"database"\s*:\s*"connected"`. Prometheus sử dụng kỹ thuật `relabel_configs` để thăm dò 2 mục tiêu:
  - `via="nginx"` (`http://host.docker.internal:8080/health`): Kiểm tra toàn trình từ Nginx vào ứng dụng và database.
  - `via="app"` (`http://app:8000/health`): Kiểm tra trực tiếp container ứng dụng, giúp phân biệt ngay lỗi do Nginx hay do container `app`/`db`.
- **`prometheus` (`v3.5.0`) & `alertmanager` (`v0.28.1`):** Lưu trữ chuỗi thời gian trong 7 ngày (`--storage.tsdb.retention.time=7d`), đánh giá 7 luật cảnh báo và gửi sang Alertmanager. Alertmanager gom nhóm theo `alertname` (`group_wait: 10s`, `group_interval: 1m`, `repeat_interval: 4h`) và áp dụng luật ức chế (`inhibit_rules`): khi `AppContainerDown` đã bật thì tự động ẩn `AppDownViaNginx` để tránh báo động trùng lặp.
- **`grafana` (`12.0.0`):** Tự động nạp (provision) nguồn dữ liệu Prometheus và bảng điều khiển *"Task Manager – Tổng quan hệ thống"* từ tệp JSON lưu trong Git (`monitoring/grafana/dashboards/taskmanager-overview.json`), hiển thị 6 ô chỉ số tổng quan (Web qua Nginx, Container app, Cảnh báo đang bật, Uptime VM, Thời gian từ lần backup gần nhất, Phần trăm ổ đĩa) và 4 biểu đồ chuỗi thời gian (CPU, RAM, Thời gian phản hồi `/health`, Lịch sử trạng thái `/health`).

### 5.2. Bảy luật cảnh báo và kiểm thử bằng `promtool`

*Bảng 4. Danh sách 7 luật cảnh báo trong `monitoring/prometheus/alerts.yml`*

| Tên cảnh báo | Nhóm | Biểu thức PromQL (`expr`) | Ngưỡng chờ (`for`) | Mức độ | Ý nghĩa vận hành |
|---|---|---|---|---|---|
| `AppDownViaNginx` | `taskmanager-app` | `probe_success{job="health", via="nginx"} == 0` | `30s` | `critical` | Người dùng không truy cập được ứng dụng qua cổng Nginx `:8080`. |
| `AppContainerDown` | `taskmanager-app` | `probe_success{job="health", via="app"} == 0` | `30s` | `critical` | Container `app` dừng, lỗi tiến trình hoặc mất kết nối tới PostgreSQL. |
| `HealthCheckSlow` | `taskmanager-app` | `probe_duration_seconds{job="health", via="nginx"} > 1` | `2m` | `warning` | `/health` phản hồi chậm hơn 1 giây kéo dài trên 2 phút. |
| `HostHighCpu` | `taskmanager-host` | `100 * (1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[2m]))) > 85` | `2m` | `warning` | CPU của máy ảo vượt 85% liên tục trong 2 phút. |
| `HostHighMemory` | `taskmanager-host` | `100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 90` | `2m` | `warning` | RAM sử dụng của máy ảo vượt 90% trong 2 phút. |
| `HostDiskAlmostFull` | `taskmanager-host` | Tỷ lệ dung lượng đã dùng của phân vùng `/` > `85` | `5m` | `warning` | Ổ đĩa `/` vượt 85%, cần kiểm tra thư mục `backups/` và image cũ. |
| `BackupTooOld` | `taskmanager-backup` | `time() - taskmanager_backup_last_success_timestamp_seconds > 26 * 3600` | `10m` | `warning` | Quá 26 giờ chưa có bản sao lưu database thành công mới. |

Toàn bộ các biểu thức cảnh báo được kiểm thử tự động trong CI bằng lệnh `promtool test rules alerts.test.yml` với 4 kịch bản chuỗi thời gian giả lập (app chết hơn 30s phải bật `AppContainerDown`; lỗi chớp nhoáng 15s không được báo động giả; backup cũ hơn 26h phải bật `BackupTooOld` sau 10m; và backup mới chạy thì không cảnh báo). Trong thực nghiệm dừng container `app` ngày 04/11/2026 (`evidence/week3/03`–`08`), cảnh báo chuyển sang `FIRING` sau **30–45 giây** và tự động `resolved` sau **15–30 giây** kể từ khi khởi động lại dịch vụ.

![Hình 3. Dashboard Grafana ghi nhận khoảng thời gian sự cố (vùng đỏ) và trạng thái bình thường trở lại](../evidence/week3/05-dashboard-su-co.png)

*Hình 3. Dashboard Grafana hiển thị trực quan khoảng thời gian `/health` bị gián đoạn (vùng đỏ) và phục hồi (vùng xanh).*

### 5.3. Thu thập và cách tra cứu nhật ký (Application & Proxy Logs)
Gunicorn được cấu hình ghi toàn bộ access log (`--access-logfile -`) và error log/exception của Flask (`logging.INFO`) ra luồng chuẩn `stdout`/`stderr`. Docker thu thập các dòng nhật ký này kèm dấu thời gian (timestamp). Khi cần điều tra sự cố theo khung thời gian hoặc lọc mã lỗi, người vận hành sử dụng các lệnh chuẩn hóa sau:
```bash
cd /opt/taskmanager
# 1. Xem log của ứng dụng trong 30 phút gần nhất kèm dấu thời gian
docker compose logs --timestamps --since 30m app
# 2. Tra cứu log chính xác trong một khung giờ xảy ra sự cố
docker compose logs --timestamps --since 2026-11-04T11:25:00 --until 2026-11-04T11:35:00 app
# 3. Chỉ lọc các HTTP request trả về mã lỗi 4xx hoặc 5xx
docker compose logs --since 1h app | grep -E '" (4|5)[0-9]{2} '
# 4. Lọc traceback / lỗi kết nối cơ sở dữ liệu trong ứng dụng và lỗi phía Nginx
docker compose logs --since 1h app | grep -iE 'error|exception|failed'
sudo tail -n 50 /var/log/nginx/error.log
```

---

## 6. Bảo mật

Hệ thống áp dụng mô hình phòng thủ theo chiều sâu (Defense in Depth) qua 5 lớp, được tài liệu hóa chi tiết trong `docs/security.md`:

### 6.1. Tường lửa UFW và cô lập mạng giữa các Container (Network Isolation)
- **Tường lửa Host:** UFW chặn toàn bộ kết nối đến mặc định và chỉ mở cổng `22/tcp` và `8080/tcp`. Các cổng `8000`, `9090`, `9093`, `3000` chỉ gắn vào `127.0.0.1` và được kiểm chứng bằng `sudo ss -lntp`.
- **Cô lập mạng Docker:** Container `db` chỉ thuộc mạng `backend`, trong khi 5 container giám sát chỉ thuộc mạng `monitoring`. Nhờ đó, các thành phần giám sát hoàn toàn không có đường định tuyến mạng tới cổng `5432` của PostgreSQL. Quản trị viên xem Grafana/Prometheus/Alertmanager từ máy Windows thông qua SSH local port forwarding (tunnel) qua cổng 22 đã xác thực.

### 6.2. Phân quyền cơ sở dữ liệu tối thiểu (DB Least Privilege)
Kịch bản `scripts/db-roles.sql` phân tách rõ hai vai trò trong PostgreSQL và được áp dụng tự động ở mỗi lần deploy:

*Bảng 5. Phân tách quyền hạn giữa hai role trong cơ sở dữ liệu `taskdb`*

| Role | Quyền hạn trong PostgreSQL | Nơi sử dụng | Tác dụng bảo mật |
|---|---|---|---|
| `taskapp` | Chủ sở hữu database `taskdb` và bảng `tasks` (toàn quyền DDL + DML). | Chỉ dùng nội bộ khi tạo bảng (`schema.sql`), phân quyền (`db-roles.sql`), sao lưu (`backup.sh`) và khôi phục (`restore.sh`). | Không bao giờ đưa vào biến môi trường của ứng dụng web. |
| `taskapp_rw` | `NOSUPERUSER NOCREATEDB NOCREATEROLE`; thu hồi quyền `CREATE` trên schema `public`; chỉ cấp `SELECT, INSERT, UPDATE, DELETE` trên bảng `tasks` và `USAGE, SELECT` trên `tasks_id_seq`. | Container `app` kết nối qua biến `DATABASE_URL`. | Nếu ứng dụng bị khai thác lỗ hổng, kẻ tấn công không thể xóa bảng (`DROP TABLE`), không thể `TRUNCATE` hay thay đổi cấu trúc bảng. |

**Kết quả kiểm chứng thực tế:** Khi thử dùng tài khoản `taskapp_rw` để chạy lệnh xóa bảng:
```bash
docker compose exec -e PGPASSWORD="$APP_DB_PASSWORD" db \
  psql -h localhost -U taskapp_rw -d taskdb -c 'DROP TABLE tasks;'
# Kết quả: ERROR:  must be owner of table tasks
```
Câu lệnh bị từ chối ngay lập tức, chứng minh nguyên tắc quyền tối thiểu hoạt động đúng thiết kế.

### 6.3. Luồng bảo vệ Secrets và gia cố Container (Container Hardening)
- **Luồng Secrets (Secrets Flow):** GitHub Actions Secrets (`POSTGRES_PASSWORD`, `APP_DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`) → truyền qua biến môi trường của bước deploy (được GitHub tự động che `***` trong log) → ghi xuống `/opt/taskmanager/.env` với `umask 077` (quyền `-rw-------`, chỉ chủ sở hữu `vannhan` đọc được) → nạp vào container khi khởi chạy. Kiểm tra toàn bộ lịch sử Git bằng `git grep` xác nhận không có mật khẩu nào bị lộ trong mã nguồn.
- **Gia cố Container (Container Hardening):** Container `app` chạy dưới quyền user thường `appuser` (UID 10001); toàn bộ tệp cấu hình gắn vào các container (`schema.sql`, `monitoring/prometheus`, `monitoring/alertmanager`, `monitoring/blackbox`, `monitoring/grafana`) đều sử dụng cờ chỉ đọc (`:ro`); Grafana tắt hoàn toàn tính năng tự đăng ký (`GF_USERS_ALLOW_SIGN_UP: "false"`) và truy cập ẩn danh (`GF_AUTH_ANONYMOUS_ENABLED: "false"`).

---

## 7. Backup và Restore

### 7.1. Chiến lược sao lưu và tích hợp trực tiếp với hệ thống giám sát
Script `scripts/backup.sh` thực hiện sao lưu cơ sở dữ liệu hằng ngày lúc **02:00 sáng** qua `cron` (do pipeline tự động cài đặt) với các cơ chế đảm bảo an toàn:
1. **Định dạng và ghi nguyên tử:** Sử dụng `pg_dump -U taskapp -d taskdb --format=custom` ghi ra tệp tạm `.dump.part` trong thư mục `/opt/taskmanager/backups/` (quyền `700`), kiểm tra đọc lại mục lục bằng `pg_restore --list < "$tmp" > /dev/null` thành công rồi mới đổi tên thành `taskdb-YYYYMMDD-HHMMSS.dump` và tạo tệp băm `sha256sum "$file" > "$file.sha256"`.
2. **Chính sách lưu giữ 7 ngày:** Tự động xóa các bản `.dump` và `pre-restore-*.dump` cũ hơn 7 ngày (`find ... -mtime +7 -delete`).
3. **Tích hợp với Prometheus (`BackupTooOld` alert):** Ngay sau khi sao lưu xong, script ghi nguyên tử 3 chỉ số vào `/opt/taskmanager/backups/metrics/backup.prom`:
   - `taskmanager_backup_last_success_timestamp_seconds`: Thời điểm Unix timestamp của lần sao lưu thành công vừa chạy.
   - `taskmanager_backup_last_size_bytes`: Kích thước tệp sao lưu (bytes).
   - `taskmanager_backup_last_rows`: Số lượng công việc trong bảng `tasks` lúc sao lưu.
   `node-exporter` thu thập tệp này đưa vào Prometheus; trên Grafana có riêng một ô hiển thị *"Backup gần nhất (cách đây)"* và luật `BackupTooOld` sẽ phát cảnh báo nếu quá 26 giờ không có bản sao lưu mới.

### 7.2. Quy trình khôi phục an toàn và kết quả thực nghiệm
Script `scripts/restore.sh` thực hiện khôi phục qua 6 bước bảo vệ: (1) kiểm tra mã băm `sha256sum --check` và `pg_restore --list`; (2) yêu cầu người dùng gõ chính xác `YES` in hoa để xác nhận; (3) tự động tạo bản sao lưu trạng thái hiện tại ra `pre-restore-YYYYMMDD-HHMMSS.dump` để phòng trường hợp cần quay lại; (4) tạm dừng container `app` để ngắt kết nối ghi; (5) chạy `pg_restore --clean --if-exists --single-transaction --exit-on-error` (nếu lỗi giữa chừng sẽ tự rollback toàn bộ); và (6) áp dụng lại `db-roles.sql`, khởi động lại `app`, kiểm tra `/health` và in tổng số bản ghi sau khôi phục.

**Kết quả thực nghiệm ngày 04/11/2026 (`evidence/week3/09` và `10`):**
- Lúc `12:08:59`, chạy `backup.sh` khi bảng `tasks` có **8 công việc** → hoàn tất sau **3 giây** (`12:09:02`), tạo tệp `taskdb-20261104-120859.dump` nặng **4040 bytes**.
- Gửi `POST /api/tasks` thêm công việc `"Test restore"` (`id=9`) → đếm trong DB tăng lên **9 công việc**.
- Chạy `restore.sh` với tệp backup lúc `12:08:59`: thử gõ `yes` thường bị từ chối hủy lệnh; khi chạy lại và gõ `YES` hoa lúc `12:11:23`, hệ thống tạo bản `pre-restore`, dừng app, khôi phục và khởi động lại app hoàn tất lúc `12:11:37` (tổng cộng **14 giây**). Truy vấn lại `SELECT count(*) FROM tasks` trả về đúng **8 công việc**, bản ghi thử nghiệm tạo sau thời điểm backup đã được loại bỏ hoàn toàn.

![Hình 4. Minh chứng quá trình kiểm tra sha256, tạo bản pre-restore và khôi phục database về đúng 8 công việc](../evidence/week3/10-restore-thanh-cong.png)

*Hình 4. Nhật ký thực thi `restore.sh` thành công trong 14 giây và xác nhận số lượng công việc trở về 8.*

---

## 8. Xử lý sự cố (Troubleshooting)

### 8.1. Phương pháp khoanh vùng sự cố nhanh
Tài liệu `docs/playbook.md` của nhóm xây dựng quy trình chuẩn gồm 5 mục cho mỗi sự cố (**Triệu chứng → Xác minh → Nguyên nhân → Khắc phục → Phòng tránh**) cho tổng cộng **8 kịch bản sự cố** (bao gồm đầy đủ cả 5 lỗi giảng viên có thể chọn khi kiểm tra trực tiếp: container dừng, mất kết nối DB, sai biến môi trường, lỗi cấu hình proxy Nginx, và dịch vụ không truy cập được từ bên ngoài do firewall/mạng).

Khi có sự cố, người trực đối chiếu dashboard Grafana với kết quả của **2 lệnh `curl` chẩn đoán** chạy trên VM để khoanh vùng ngay tầng bị lỗi trong vòng vài giây:
```bash
curl -s -o /dev/null -w 'qua Nginx: %{http_code}\n' http://127.0.0.1:8080/health
curl -s -o /dev/null -w 'thẳng app: %{http_code}\n' http://127.0.0.1:8000/health
```

*Bảng 6. Ma trận khoanh vùng nhanh nguyên nhân sự cố từ kết quả kiểm tra `/health`*

| Kết quả từ Windows | `curl :8080` (qua Nginx) | `curl :8000` (thẳng app) | Kết luận tầng bị lỗi | Mục trong Playbook |
|---|---|---|---|---|
| Timeout / Refused | `200` | `200` | Trong VM bình thường; lỗi ở tường lửa UFW chặn cổng 8080 hoặc đổi IP VM | Mục 8 |
| 502 / Refused | `502` / `404` / `000` | `200` | Container `app` và `db` bình thường; lỗi cấu hình `proxy_pass` hoặc Nginx dừng | Mục 4, 8 |
| 502 Bad Gateway | `502` | `000` | Container `app` bị dừng (`Exited`) | Mục 1 |
| 503 Unavailable | `503` | `503` | Container `app` đang chạy nhưng mất kết nối tới `db` hoặc sai mật khẩu `.env` | Mục 2, 3 |

### 8.2. Tóm tắt các sự cố thực tế đã xảy ra và bài học rút ra

*Bảng 7. Tổng hợp các sự cố thực tế nhóm đã gặp trong quá trình triển khai (Week 1–3)*

| Sự cố thực tế & Thời điểm | Triệu chứng & Cách xác minh | Nguyên nhân gốc (Root Cause) | Cách khắc phục & Bài học phòng tránh |
|---|---|---|---|
| **1. SSH bị từ chối kết nối**<br>*(27/10/2026 – Tuần 1)* | Lệnh `ssh vannhan@<VM_IP>` từ Windows báo `port 22: Connection refused` ngay lập tức (không phải timeout). Trên VM chạy `sudo ss -lntp \| grep ':22 '` không có kết quả. | Bản cài đặt Ubuntu Desktop không cài sẵn gói `openssh-server` mặc định như bản Server. | **Khắc phục:** Cài `openssh-server`, bật service `ssh` và mở `ufw allow OpenSSH`.<br>**Bài học:** Phân biệt rõ *Connection refused* (mạng thông nhưng không có tiến trình lắng nghe) với *Connection timed out* (bị firewall chặn hoặc sai IP); đưa cài đặt SSH vào `scripts/bootstrap-vm.sh`. |
| **2. Job Deploy đứng ở trạng thái Queued**<br>*(27–28/10/2026 – Tuần 2)* | Job `Test` và `Build` đã xanh nhưng job `Deploy to Ubuntu VM` đứng ở *Queued* rất lâu không chạy. Trang *Settings → Actions → Runners* báo runner *Offline*. | Lần đầu do chưa cài đặt self-hosted runner; lần sau do tắt máy ảo khi nghỉ làm việc khiến tiến trình runner ngắt kết nối với GitHub. | **Khắc phục:** Cài đặt runner dưới dạng dịch vụ hệ thống (`sudo ./svc.sh install vannhan && sudo ./svc.sh start`).<br>**Bài học:** Dịch vụ hạ tầng phải được đăng ký với `systemd` để tự khởi động cùng hệ điều hành; luôn kiểm tra runner ở trạng thái *Idle* trước buổi demo. |
| **3. Deploy thất bại ở bước ghi `.env` vì thiếu Secret**<br>*(28/10/2026 – Tuần 2)* | Job `Deploy` báo đỏ tại bước `Write .env from GitHub Secrets` dù vừa mới tạo thêm secret trên giao diện web GitHub. | Job đã được xếp hàng (*Queued*) từ tối 27/10 **trước khi** secret được tạo. GitHub Actions chốt giá trị các secrets tại thời điểm tạo lượt chạy, nên job đang chờ vẫn nhận giá trị rỗng. | **Khắc phục:** Sau khi tạo đủ secret, bấm **Re-run failed jobs** để khởi tạo lượt chạy mới nhận secret hiện tại.<br>**Bài học:** Thêm vòng lặp kiểm tra đầu bước deploy in rõ tên secret bị thiếu (`::error::Chưa tạo secret $name...`) và quy định thứ tự tạo secret trước trong `deployment-guide.md`. |
| **4. Lỗi xác thực mật khẩu `taskapp_rw` khi nâng cấp phân quyền**<br>*(04/11/2026 – Tuần 3)* | `/health` trả mã `503` (biểu đồ Grafana đỏ từ 11:26–11:33, Hình 3) dù cả `app` và `db` đều `Up`. Log của `app` báo `password authentication failed for user "taskapp_rw"`. | Khi chuyển sang dùng role quyền tối thiểu `taskapp_rw`, mật khẩu của role trong volume `pgdata` chưa khớp với biến `APP_DB_PASSWORD` nạp cho container `app`. | **Khắc phục:** Chạy `scripts/db-roles.sql` với mật khẩu lấy từ `.env` rồi `docker compose restart app` (commit `3248be8`).<br>**Bài học:** Mọi thay đổi phân quyền phải được viết thành kịch bản *idempotent* và chạy tự động trong pipeline mỗi lần deploy. |

---

## 9. Đánh giá và hạn chế

### 9.1. Bảng số liệu đo đạc thực tế và những điểm hệ thống đã làm tốt

*Bảng 8. Tổng hợp số liệu đo đạc thực nghiệm trên hệ thống*

| Hạng mục đo đạc | Kết quả thực tế | Phương pháp đo và nguồn minh chứng |
|---|---|---|
| **Tổng thời gian chạy pipeline CI/CD** | **1m 19s – 1m 38s** *(Test: 29–31s, Build: 21–38s, Deploy: 34–71s)* | Bộ đếm của GitHub Actions trên các lượt chạy thực tế (`evidence/week2/05`, `06`). |
| **Thời gian đóng gói Docker image** | **7 giây** (có cache lớp `pip`) / **19 giây** (không cache) | Nhật ký Docker Buildx summary trên GitHub Actions (`evidence/week2/05`, `06`). |
| **Độ trễ phản hồi `/health` bình thường** | **25 ms – 75 ms** (trung bình ~40 ms) | Chỉ số `probe_duration_seconds` của `blackbox-exporter` trên Grafana (`evidence/week3/01`). |
| **Thời gian phát hiện sự cố dừng app (MTTD)** | **30 – 45 giây** (lên Alertmanager sau **40 – 55 giây**) | Thực nghiệm `docker compose stop app` ngày 04/11 (`evidence/week3/03`–`06`). |
| **Thời gian tự tắt cảnh báo sau khi khôi phục** | **15 – 30 giây** | Thực nghiệm `docker compose up -d app` ngày 04/11 (`evidence/week3/07`–`08`). |
| **Thời gian sao lưu & kích thước tệp dump** | **3 giây** · **4040 bytes (~4.0 KB)** cho 8 bản ghi | Nhật ký `backup.sh` ngày 04/11 (`12:08:59` → `12:09:02`, `evidence/week3/09`). |
| **Thời gian khôi phục hoàn chỉnh (`restore.sh`)** | **14 giây** (thời gian dừng/chạy lại app và nạp DB ~4 giây) | Nhật ký `restore.sh` ngày 04/11 (`12:11:23` → `12:11:37`, `evidence/week3/10`). |
| **Tài nguyên máy ảo khi chạy đủ 7 container** | **CPU: 15–35%** · **RAM: ~52% (~1.7/3.3 GiB)** · **Disk: 51.9%** | Chỉ số `node-exporter` trên Grafana (`evidence/week3/01`, `05`). |

**Những điểm hệ thống đã thực hiện tốt:**
- **Tự động hóa và kiểm chứng đầu-cuối:** Không chỉ kiểm thử mã nguồn Python với PostgreSQL thật, pipeline còn kiểm tra tự động cả cấu hình `docker-compose.yml`, cấu hình Prometheus/Alertmanager, JSON dashboard và chạy unit test cho các luật cảnh báo (`promtool test rules`) trước khi cho phép build.
- **Khả năng quan sát và chẩn đoán cao:** Thiết kế hai mũi thăm dò `via=nginx` và `via=app` kết hợp luật ức chế (`inhibit_rules`) giúp phân biệt ngay lỗi ở tầng proxy hay tầng ứng dụng mà không bị ngập trong cảnh báo trùng lặp.
- **Tự động hóa khôi phục và tái tạo:** Có đầy đủ kịch bản `scripts/bootstrap-vm.sh` để dựng lại máy chủ từ đầu, cùng bộ kịch bản `backup.sh`/`restore.sh` có kiểm tra `sha256`, tạo bản phòng hộ `pre-restore` và xuất chỉ số giám sát trực tiếp ra Prometheus.

### 9.2. Các hạn chế kỹ thuật hiện tại và hướng phát triển

*Bảng 9. Phân tích các hạn chế hiện tại của hệ thống và hướng nâng cấp*

| Hạng mục hạn chế | Hiện trạng trong hệ thống | Rủi ro / Hệ quả | Hướng phát triển đề xuất |
|---|---|---|---|
| **1. Chưa có HTTPS (TLS)** | Nginx `:8080` phục vụ giao thức HTTP thuần do chạy trên IP nội bộ VMware NAT chưa có tên miền công cộng. | Lưu lượng giữa trình duyệt và VM chưa được mã hóa tầng truyền tải. | Sử dụng `mkcert` (CA nội bộ) cho môi trường lab hoặc dùng tên miền thật với chứng chỉ Let's Encrypt (DNS-01 challenge) và bật HTTP/2. |
| **2. Chưa có Off-site Backup** | Các tệp `.dump` trong `/opt/taskmanager/backups/` nằm trên cùng ổ đĩa ảo của VM. | Nếu hỏng máy ảo VMware hoặc ổ cứng máy host thì mất cả dữ liệu lẫn bản sao lưu. | Áp dụng quy tắc backup 3-2-1: thêm bước đẩy tệp `.dump` và `.sha256` lên AWS S3 / Cloudflare R2 (bằng `rclone`) hoặc `scp` tự động về máy host. |
| **3. Chưa dùng Connection Pool cho Database** | Hàm `db()` trong `app/main.py` gọi `psycopg.connect(url)` mở kết nối TCP/PostgreSQL mới cho mỗi HTTP request (kể cả mỗi lần `/health` được gọi 15s/lần). | Tốn chi phí bắt tay kết nối khi tải cao và dễ chạm ngưỡng `max_connections` của PostgreSQL nếu có đột biến truy cập. | Sử dụng `psycopg_pool.ConnectionPool` trong ứng dụng Flask hoặc đặt dịch vụ **PgBouncer** phía trước container `db` trong mạng `backend`. |
| **4. SSH chưa khóa xác thực mật khẩu (SSH Key-only)** | Dịch vụ OpenSSH trên VM vẫn cho phép đăng nhập bằng mật khẩu bên cạnh SSH key. | Có nguy cơ bị tấn công vét cạn mật khẩu (brute-force) trên cổng 22. | Cấu hình `/etc/ssh/sshd_config` với `PasswordAuthentication no`, `PermitRootLogin no`, chỉ dùng khóa `Ed25519` và cài đặt `fail2ban`. |
| **5. Cảnh báo chưa đẩy ra ngoài & điểm mù UFW** | Alertmanager mới chỉ hiển thị trên giao diện `web-ui`; `blackbox` thăm dò từ bên trong VM nên không đi qua UFW của host. | Người vận hành phải mở dashboard mới thấy cảnh báo; nếu UFW chặn cổng 8080 thì bên ngoài không vào được nhưng Grafana vẫn xanh. | Cấu hình receiver Alertmanager gửi thông báo qua Telegram Bot / Email; đặt thêm một đầu dò bên ngoài VM (hoặc script kiểm tra từ host). |
| **6. Gián đoạn ngắn khi deploy & chưa tự rollback** | Chỉ có 1 bản sao container `app`; khi thay container mới có khoảng ngắt vài giây; nếu smoke test đỏ thì pipeline dừng nhưng chưa tự lùi bản. | Có thời gian gián đoạn ngắn khi cập nhật phiên bản. | Chạy 2 replica `app` phía sau upstream Nginx để rolling update; nếu smoke test thất bại thì tự động `docker compose up -d` lại tag SHA trước đó. |

---

## 10. Kết luận và Tài liệu tham khảo

### 10.1. Tóm tắt kết quả đạt được
Qua 4 tuần xây dựng và hoàn thiện, nhóm đã phát triển thành công một hệ thống triển khai và vận hành tự động hóa hoàn chỉnh cho ứng dụng Task Manager trên nền tảng Ubuntu, Docker Compose, GitHub Actions và Prometheus/Grafana. Từ một ứng dụng cài đặt thủ công ở Tuần 1, hệ thống cuối cùng đã đạt được khả năng triển khai tự động chỉ trong **~1.5 phút** cho mỗi commit, phát hiện sự cố ngưng dịch vụ trong **30–45 giây**, bảo vệ dữ liệu bằng tường lửa, mạng cô lập, secrets quyền `600` và role database tối thiểu, đồng thời khôi phục chính xác dữ liệu từ bản sao lưu trong **14 giây** và có thể tái tạo toàn bộ trên máy ảo mới bằng kịch bản `scripts/bootstrap-vm.sh`.

### 10.2. Bài học kinh nghiệm DevOps rút ra sau 4 tuần
1. **Tự động hóa phải đi kèm kiểm chứng (Verification):** Một pipeline CI/CD chỉ chạy câu lệnh `docker compose up -d` là chưa đủ; chính bước smoke test đối chiếu trường `"version"` trên `/health` với mã commit và việc kiểm thử cả các luật cảnh báo bằng `promtool` mới là chốt chặn thực sự đảm bảo hệ thống sau khi deploy đang hoạt động đúng.
2. **Tính bất biến và tính lũy đẳng (Idempotency) giúp vận hành ổn định:** Những sự cố thực tế nhóm gặp phải (như lệch mật khẩu role `taskapp_rw` hay sai cấu hình thủ công) đều được giải quyết triệt để khi mọi thao tác cấu hình (`db-roles.sql`, cài đặt `crontab`, tạo `.env`, `bootstrap-vm.sh`) được viết thành kịch bản chạy lại bao nhiêu lần cũng cho ra cùng một trạng thái chuẩn.
3. **Giám sát phải phục vụ khoanh vùng nguyên nhân gốc:** Việc tách hai mũi thăm dò `via=nginx` và `via=app` cùng luật ức chế cảnh báo giúp rút ngắn đáng kể thời gian chẩn đoán (MTTR) khi xảy ra sự cố, biến bảng điều khiển giám sát thành công cụ định hướng hành động trực tiếp gắn liền với Playbook.
4. **Sao lưu chỉ có giá trị khi đã thử nghiệm khôi phục:** Việc thiết kế quy trình `restore.sh` (kiểm tra `sha256`, tạo bản `pre-restore`, chạy trong một transaction và cấp lại quyền cho role ứng dụng) và trực tiếp diễn tập xóa/khôi phục dữ liệu giúp nhóm phát hiện và xử lý trước các chi tiết dễ bị bỏ sót nếu chỉ viết script sao lưu trên lý thuyết.

### 10.3. Tài liệu tham khảo
1. Docker Inc., *Dockerfile Reference & Docker Compose File v2 Specification*, https://docs.docker.com/reference/ (truy cập 10/2026).
2. GitHub Inc., *GitHub Actions Documentation: Building and testing Python, Publishing Docker images & About self-hosted runners*, https://docs.github.com/en/actions (truy cập 10/2026).
3. Prometheus Authors, *Prometheus v3.5 Documentation: Configuration, Alerting Rules & Unit Testing for Rules (`promtool`)*, https://prometheus.io/docs/prometheus/latest/ (truy cập 11/2026).
4. Prometheus Authors, *Blackbox Exporter & Node Exporter (Textfile Collector) Documentation*, https://github.com/prometheus/blackbox_exporter và https://github.com/prometheus/node_exporter (truy cập 11/2026).
5. Grafana Labs, *Grafana v12 Documentation: Provisioning Data Sources and Dashboards*, https://grafana.com/docs/grafana/latest/administration/provisioning/ (truy cập 11/2026).
6. PostgreSQL Global Development Group, *PostgreSQL 18 Documentation: Chapter 22 (Database Roles), `pg_dump` and `pg_restore`*, https://www.postgresql.org/docs/18/ (truy cập 10–11/2026).
7. F5 / Nginx Inc., *Nginx Documentation: Module `ngx_http_proxy_module`*, https://nginx.org/en/docs/http/ngx_http_proxy_module.html (truy cập 10/2026).
8. Canonical Ltd., *Ubuntu Server Documentation: Uncomplicated Firewall (UFW) & OpenSSH Server*, https://documentation.ubuntu.com/server/ (truy cập 10/2026).
9. Beyer, B., Jones, C., Petoff, J., & Murphy, N. R. (2016), *Site Reliability Engineering: How Google Runs Production Systems*, O'Reilly Media (Chapter 6: Monitoring Distributed Systems & Chapter 14: Managing Incidents).
