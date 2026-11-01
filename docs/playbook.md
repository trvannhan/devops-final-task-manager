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

| # | Sự cố | Nguồn |
|---|-------|-------|
| 1 | Container app dừng | Thực nghiệm (demo cảnh báo Week 3) |
| 2 | Database mất kết nối | Thực nghiệm |
| 3 | Sai biến môi trường (mật khẩu database) | Thực nghiệm |
| 4 | Lỗi cấu hình proxy Nginx | Thực nghiệm |
| 5 | Deploy thất bại vì thiếu secret | **Đã xảy ra** 28/10/2026 |
| 6 | SSH bị từ chối kết nối | **Đã xảy ra** 27/10/2026 |
| 7 | Job Deploy đứng ở Queued | **Đã xảy ra** 27–28/10/2026 |

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

**Khắc phục**: không sửa tay `.env`. Chạy lại pipeline để ghi lại `.env` từ GitHub Secrets và đặt lại mật khẩu role cho khớp:
GitHub → **Actions** → **CI/CD** → **Run workflow** (nhánh `main`). Hoặc nếu biết giá trị đúng, sửa `.env` rồi `docker compose up -d app`.

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

**Khắc phục**: chép lại cấu hình chuẩn từ Git rồi nạp lại.
```bash
sudo cp ~/devops-final-task-manager/scripts/nginx-taskmanager.conf /etc/nginx/sites-available/taskmanager
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
