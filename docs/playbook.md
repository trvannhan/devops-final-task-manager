# Troubleshooting playbook

Mỗi sự cố gồm: **triệu chứng → xác minh → nguyên nhân → khắc phục → phòng tránh**. Các lệnh chạy trên VM, trong thư mục `/opt/taskmanager` (trừ khi ghi khác).

Bước chung khi có sự cố: mở Grafana (dashboard *Task Manager – Tổng quan hệ thống*) xem ô nào đỏ, rồi chạy:
```bash
cd /opt/taskmanager
docker compose ps
curl -s -o /dev/null -w 'qua Nginx: %{http_code}\n' http://127.0.0.1:8080/health
curl -s -o /dev/null -w 'thẳng app: %{http_code}\n' http://127.0.0.1:8000/health
```

| Qua Nginx | Thẳng app | Nghĩa là | Xem mục |
|---|---|---|---|
| 200 | 200 | Hệ thống bình thường | — |
| 502 | 000 (không kết nối được) | Container app dừng | 1 |
| 503 | 503 | App chạy nhưng mất kết nối database | 2, 3 |
| 502/404 | 200 | App bình thường, lỗi ở Nginx | 4 |
| 000 (Nginx dừng) | 200 | Nginx không chạy | 4, 8 |
| 200 (trong VM) | 200 | Trong VM bình thường nhưng từ Windows không vào được: firewall/mạng | 8 |

| # | Sự cố | Nguồn |
|---|-------|-------|
| 1 | Container app dừng | Thực nghiệm (demo cảnh báo Week 3) |
| 2 | Database mất kết nối | Thực nghiệm |
| 3 | Sai biến môi trường (mật khẩu database) | Thực nghiệm |
| 4 | Lỗi cấu hình proxy Nginx | Thực nghiệm |
| 5 | Deploy thất bại vì thiếu secret | **Đã xảy ra** 28/10/2026 |
| 6 | SSH bị từ chối kết nối | **Đã xảy ra** 27/10/2026 |
| 7 | Job Deploy đứng ở Queued | **Đã xảy ra** 27–28/10/2026 |
| 8 | Dịch vụ không truy cập được từ bên ngoài (firewall, Nginx dừng, đổi IP) | Thực nghiệm (Week 4) |

Ánh xạ với các lỗi giảng viên có thể chọn ở Week 4: *container stopped* → mục 1; *database mất kết nối* → mục 2; *sai biến môi trường* → mục 3; *lỗi cấu hình proxy* → mục 4; *dịch vụ không truy cập được* → mục 8.

---

## 1. Container app dừng

**Triệu chứng**
- Web `:8080` báo **502 Bad Gateway**.
- Grafana: ô *Container app* và *Web qua Nginx* chuyển **DOWN**; cảnh báo **AppContainerDown** bật sau khoảng 30–45 giây.

**Xác minh**
```bash
docker compose ps app                       # STATUS: Exited, hoặc không có trong danh sách
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/health   # 000
docker compose logs --tail 50 app           # xem dòng cuối trước khi dừng
```

**Nguyên nhân thường gặp**: có người chạy `docker compose stop app`, app bị lỗi khi khởi động, hoặc hết RAM (OOM).

**Khắc phục**
```bash
docker compose up -d app
docker compose ps app                        # Up (healthy)
curl -s http://127.0.0.1:8080/health; echo   # "database":"connected"
```
Cảnh báo tự chuyển sang *resolved* sau khoảng 15–30 giây.

**Phòng tránh**: `restart: unless-stopped` tự khởi động lại khi app crash; cảnh báo AppContainerDown; HEALTHCHECK trong Dockerfile.

---

## 2. Database mất kết nối

**Triệu chứng**
- Web hiện "Database unavailable"; `/health` trả **503** `{"database":"unavailable"}`.
- Grafana: cả hai ô DOWN (blackbox yêu cầu `"database":"connected"`); cảnh báo **AppContainerDown**.

**Xác minh**
```bash
docker compose ps db                         # Exited hoặc unhealthy
curl -s http://127.0.0.1:8000/health; echo   # 503, database unavailable
docker compose logs --tail 30 app | grep -i database
docker compose logs --tail 30 db
```

**Nguyên nhân thường gặp**: container db bị dừng, hết dung lượng đĩa, volume lỗi.

**Khắc phục**
```bash
docker compose up -d --wait db
curl -s http://127.0.0.1:8080/health; echo   # app tự kết nối lại, không cần restart app
docker compose exec db psql -U taskapp -d taskdb -c 'SELECT count(*) FROM tasks;'
```
Nếu dữ liệu hỏng: khôi phục từ backup (`scripts/restore.sh`).

**Phòng tránh**: healthcheck `pg_isready` + `depends_on: service_healthy`; app trả lỗi JSON 503 thay vì sập; backup hằng ngày; cảnh báo HostDiskAlmostFull.

---

## 3. Sai biến môi trường (mật khẩu database)

**Triệu chứng**
- `/health` trả **503** dù container db vẫn `healthy`.
- Log app có `password authentication failed for user "taskapp_rw"`.

**Xác minh**
```bash
docker compose ps                                        # db healthy, app Up
docker compose logs --tail 30 app | grep -i "password authentication"
grep -c '^APP_DB_PASSWORD=' .env                         # có biến (KHÔNG in giá trị)
```

**Nguyên nhân**: file `.env` bị sửa tay sai, hoặc đổi secret `APP_DB_PASSWORD` trên GitHub nhưng chưa deploy lại.

**Khắc phục**: đặt lại mật khẩu role `taskapp_rw` theo giá trị đang có trong `.env`, rồi khởi động lại app. Không in giá trị mật khẩu ra màn hình:
```bash
cd /opt/taskmanager
APP_PW="$(grep '^APP_DB_PASSWORD=' .env | cut -d= -f2-)"
docker compose exec -T db psql -U taskapp -d taskdb -v app_password="$APP_PW" < scripts/db-roles.sql
unset APP_PW
docker compose restart app
sleep 10
curl -s http://127.0.0.1:8080/health; echo   # "database":"connected"
```
Nếu mật khẩu trong `.env` cũng sai (không khớp GitHub Secrets), chạy lại deploy để pipeline ghi lại `.env` từ Secrets và chạy `db-roles.sql`: vào **Actions → CI/CD → Run workflow** (nhánh `main`; workflow có `workflow_dispatch`), hoặc đẩy một commit mới lên `main`.

**Các biến khác trong `.env` bị sai hoặc bị xoá**

| Triệu chứng | Nguyên nhân |
|---|---|
| `docker compose up` báo `APP_DB_PASSWORD chưa được đặt` (hoặc `POSTGRES_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`) | Biến bị xoá khỏi `.env`; `docker-compose.yml` dùng cú pháp `${VAR:?...}` nên dừng ngay, không chạy với giá trị rỗng |
| `docker compose up -d app` báo `manifest unknown` / `not found` | `APP_IMAGE` trỏ tới tag không tồn tại trên ghcr.io |
| `/health` trả `version` khác commit mới nhất | `APP_IMAGE` bị đổi về một tag cũ |

Kiểm tra mà không in mật khẩu ra màn hình:
```bash
cd /opt/taskmanager
cut -d= -f1 .env                                   # đủ 4 biến: POSTGRES_PASSWORD, APP_DB_PASSWORD, GRAFANA_ADMIN_PASSWORD, APP_IMAGE
grep '^APP_IMAGE=' .env                            # tag phải là mã commit mới nhất trên main
docker compose config --quiet && echo "compose OK"
ls -l .env                                         # -rw------- (600)
```
Khắc phục chung: không sửa tay `.env`. Chạy lại **Actions → CI/CD → Run workflow** (nhánh `main`) để pipeline ghi lại `.env` đúng từ GitHub Secrets, đặt lại mật khẩu role và chạy smoke test.

**Phòng tránh**: `.env` chỉ do pipeline tạo; mỗi lần deploy chạy `scripts/db-roles.sql` đặt lại mật khẩu role theo secret; smoke test chặn deploy hỏng.

---

## 4. Lỗi cấu hình proxy Nginx

**Triệu chứng**
- Web `:8080` báo **502 Bad Gateway** (hoặc 404), nhưng `http://127.0.0.1:8000/health` vẫn **200**.
- Grafana: *Web qua Nginx* DOWN nhưng *Container app* UP → cảnh báo **AppDownViaNginx** (không có AppContainerDown).

**Xác minh**
```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/health    # 200: app không có lỗi
sudo nginx -t
grep -n 'proxy_pass\|listen' /etc/nginx/sites-enabled/taskmanager
sudo tail -n 20 /var/log/nginx/error.log      # connect() failed (111: Connection refused) ...
```

**Nguyên nhân**: `proxy_pass` trỏ sai cổng (ví dụ `127.0.0.1:8001`), site bị tắt, hoặc file cấu hình lỗi cú pháp.

**Khắc phục**: chép lại cấu hình chuẩn rồi nạp lại. File chuẩn nằm ở `/opt/taskmanager/scripts/`, được pipeline cập nhật từ Git mỗi lần deploy.
```bash
sudo cp /opt/taskmanager/scripts/nginx-taskmanager.conf /etc/nginx/sites-available/taskmanager
sudo ln -sfn /etc/nginx/sites-available/taskmanager /etc/nginx/sites-enabled/taskmanager
sudo nginx -t && sudo systemctl reload nginx
curl -s http://127.0.0.1:8080/health; echo
```

**Phòng tránh**: cấu hình Nginx lưu trong Git; luôn `nginx -t` trước khi reload; hai đường kiểm tra (via=nginx, via=app) giúp khoanh vùng lỗi ngay.

---

## 5. Deploy thất bại vì thiếu secret (đã xảy ra 28/10/2026)

**Triệu chứng**: job *Deploy to Ubuntu VM* đỏ ở bước **Write .env from GitHub Secrets**, các bước sau bị bỏ qua. Web vẫn chạy bản cũ.

**Xác minh**: mở log bước đó, có dòng `Chưa tạo secret ... trong GitHub`. Kiểm tra **Settings → Secrets and variables → Actions**.

**Nguyên nhân thực tế**: job Deploy được xếp hàng từ tối 27/10, trước khi tạo secret `POSTGRES_PASSWORD`. GitHub đóng gói dữ liệu của job lúc xếp hàng nên giá trị secret trong job vẫn rỗng dù sau đó đã tạo.

**Khắc phục**: tạo đủ secret, rồi bấm **Re-run failed jobs** (job mới lấy secret hiện tại). Đã xử lý thành công lúc 11:50 ngày 28/10.

**Phòng tránh**: bước kiểm tra secret báo lỗi rõ tên secret còn thiếu; README liệt kê đủ các secret cần tạo trước khi chạy pipeline.

---

## 6. SSH bị từ chối kết nối (đã xảy ra 27/10/2026)

**Triệu chứng**: `ssh vannhan@<VM_IP>` báo `connect to host ... port 22: Connection refused`.

**Xác minh**: `Connection refused` (không phải timeout) nghĩa là mạng tới được VM nhưng không có dịch vụ ở cổng 22. Trên VM: `sudo ss -lntp | grep ':22 '` không có kết quả.

**Nguyên nhân thực tế**: Ubuntu Desktop không cài sẵn OpenSSH server.

**Khắc phục**
```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo ufw allow OpenSSH
```

**Phòng tránh**: README thêm `openssh-server` vào bước cài đặt ban đầu.

---

## 7. Job Deploy đứng ở Queued (đã xảy ra 27–28/10/2026)

**Triệu chứng**: job Test và Build xanh, nhưng *Deploy to Ubuntu VM* đứng ở **Queued** rất lâu.

**Xác minh**: **Settings → Actions → Runners**: runner *Offline* hoặc chưa có runner. Trên VM:
```bash
systemctl list-units 'actions.runner*' --no-pager
```

**Nguyên nhân**: chưa cài runner (27/10), hoặc VM/laptop đang tắt nên runner không kết nối được GitHub.

**Khắc phục**: bật VM; nếu service dừng thì `cd ~/actions-runner && sudo ./svc.sh start`. Job đang chờ tự chạy khi runner online (GitHub giữ job trong hàng chờ tối đa 24 giờ; quá hạn thì **Re-run**).

**Phòng tránh**: runner cài dạng service (tự chạy khi VM khởi động); khi demo kiểm tra trang Runners trước.

---

## 8. Dịch vụ không truy cập được từ bên ngoài

**Triệu chứng**
- Trình duyệt Windows mở `http://<VM_IP>:8080` bị **timeout** (quay mãi) hoặc **ERR_CONNECTION_REFUSED**.
- Có thể Grafana vẫn xanh hết: blackbox gọi Nginx từ **bên trong** VM nên không đi qua UFW. Đây là điểm mù của giám sát nội bộ, cần kiểm tra từ phía người dùng.

**Xác minh**: kiểm tra lần lượt từ ngoài vào trong để khoanh vùng.
```powershell
# Trên Windows
Test-NetConnection <VM_IP> -Port 8080     # TcpTestSucceeded: False = không tới được cổng
ping <VM_IP>                              # không ping được = sai IP hoặc VM tắt/mất mạng
```
```bash
# Trên VM
hostname -I                                            # IP hiện tại có đúng IP đang gõ không
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health   # 200 = Nginx + app ổn trong VM
systemctl is-active nginx                              # inactive/failed = Nginx dừng
sudo ss -lntp | grep ':8080 '                          # không có dòng nào = không ai lắng nghe 8080
sudo ufw status numbered | grep 8080                   # không có ALLOW 8080 = firewall chặn
```

| Windows | Trong VM `curl :8080` | Nguyên nhân |
|---|---|---|
| Timeout | 200 | UFW chặn 8080 (packet bị drop) |
| Connection refused | 000 | Nginx dừng hoặc site không `listen 8080` |
| Ping cũng không được | — | VM đổi IP (DHCP của VMnet8), VM tắt, hoặc card mạng VM bị ngắt |

**Nguyên nhân thường gặp**: rule `allow 8080/tcp` bị xóa khi chỉnh UFW; Nginx dừng (`systemctl stop nginx`, hoặc reload lỗi cú pháp rồi restart); VM nhận IP mới sau khi khởi động lại.

**Khắc phục**
```bash
# Firewall
sudo ufw allow 8080/tcp
sudo ufw status verbose
# Nginx
sudo nginx -t && sudo systemctl start nginx
systemctl is-active nginx
# Kiểm tra lại trong VM
curl -s http://127.0.0.1:8080/health; echo
```
Trên Windows chạy lại `Test-NetConnection <VM_IP> -Port 8080` và mở lại trình duyệt. Nếu IP đổi, dùng IP mới (`hostname -I`) cho cả trình duyệt và lệnh SSH tunnel.

**Phòng tránh**: rule UFW nằm trong `scripts/bootstrap-vm.sh` (chạy lại được, không sợ chạy nhiều lần); `systemctl enable nginx` để Nginx tự chạy khi khởi động; luôn `nginx -t` trước khi reload; checklist trước demo có bước kiểm tra từ Windows; có thể đặt IP cố định cho VM (DHCP reservation của VMnet8 hoặc netplan).
