# Week 1 — Server Configuration & Verification

Thông tin dưới đây dựa trên ảnh lệnh Terminal/website nhóm cung cấp ngày **21/10/2026**. Đây là môi trường **VMware local lab**, không phải public production.

## Cấu hình máy ảo

| Thuộc tính | Giá trị |
|---|---|
| VM / OS | DevOps-Ubuntu / Ubuntu 26.04.1 LTS |
| User | vannhan |
| CPU | 2 vCPU (`nproc`) |
| RAM | 3.3 GiB; swap 3.8 GiB (`free -h`) |
| Disk | VMware virtual disk `sda` 35 GiB (`lsblk`) |
| Root partition | `/dev/sda2`: 35 GiB, 11 GiB used, 22 GiB available, 33% usage (`df -h /`) |
| IP tại thời điểm kiểm thử | `192.168.79.129` (`hostname -I`) |
| Network | VMware NAT (cần xác nhận VM settings khi tái tạo) |
| Database | PostgreSQL 18.6 / cluster `18 main` online / :5432 |
| Web/API | Flask 3.1.3, Gunicorn, `taskmanager.service` |
| Reverse proxy | Nginx `:8080` → `127.0.0.1:8000` |
| Legacy site | Nginx `:80` → app cũ `:5000` |

## Port và firewall

```text
22/tcp      SSH                  UFW ALLOW IN (lab)
80/tcp      Legacy DevOps app    UFW ALLOW IN (lab)
8080/tcp    Task Manager Nginx   UFW ALLOW IN (lab)
8000/tcp    Gunicorn             bound to 127.0.0.1 only
5432/tcp    PostgreSQL           bound to 127.0.0.1 only
Default: deny (incoming), allow (outgoing)
```

Kiểm tra tại VM:

```bash
lsb_release -a
whoami
nproc
free -h
lsblk -d -o NAME,SIZE,TYPE,MODEL
df -h /
hostname -I
sudo ufw status verbose
sudo ss -lntp
systemctl is-enabled taskmanager
systemctl is-active taskmanager nginx
pg_lsclusters
curl -i http://127.0.0.1:8080/health
```

**SSH:** cổng 22 đã được allow trong UFW; cần thêm một ảnh terminal Windows `ssh vannhan@<IP>` hoặc `Test-NetConnection <IP> -Port 22` để chứng minh kết nối máy khách, không tự khẳng định SSH đã kiểm thử trong Week 1 này.

## Kết quả kiểm tra đã quan sát

- `sudo nginx -t`: syntax OK, test successful.
- `curl 127.0.0.1:8080/health`: `{"database":"connected","status":"ok"}`.
- `curl 127.0.0.1:80/health`: `{"status":"ok"}` cho bài cũ.
- Từ Chrome trên Windows: mở được site `:8080`, thêm task `Test from Windows`, `Firewall Test - Week 1`; giao diện hiển thị lại các bản ghi.
- Sau reboot ngày 21/10/2026 lúc 13:31:08: `taskmanager` active, `nginx` active, PostgreSQL `18 main` online, health check trả về DB connected.
- Trong quá trình kiểm tra `taskdb`, nhóm đã đối chiếu `SELECT id,title,completed FROM tasks` với dữ liệu trên website.

## Lưu ý bảo mật và giới hạn

Không đưa mật khẩu hoặc nội dung `/etc/devops-task-manager.env` lên GitHub; không đưa IP private hay credentials khách hàng vào demo công khai khi không cần thiết. Lab dùng HTTP, chưa có TLS. Các rule SSH/HTTP có nguồn `Anywhere`, chỉ phù hợp lab tin cậy; hạn chế IP nguồn và cấu hình HTTPS trước triển khai ra Internet.
