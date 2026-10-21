# Week 1 — Evidence checklist

Đây là **checklist để nhóm chụp ảnh thật**, không phải các ảnh đã upload. Tạo thư mục `evidence/week1/` rồi lưu ảnh theo bảng. Che mật khẩu, token, environment secrets trước khi push.

| Tên file đề xuất | Nội dung cần chụp | Rubric |
|---|---|---|
| `01-architecture.png` | Xuất `docs/architecture.svg` thành PNG nếu cần | Architecture 0.5 |
| `02-server-specs.png` | `lsb_release -a`, `nproc`, `free -h`, `df -h /` | Server 0.5 |
| `03-network-firewall.png` | `hostname -I`, `sudo ufw status verbose`, `sudo ss -lntp` | Server 0.5 |
| `04-reboot-health.png` | `uptime -s`, `systemctl is-active taskmanager nginx`, `pg_lsclusters`, `curl :8080/health` | Server / App |
| `05-windows-client.png` | Chrome Windows với IP VM :8080 và task đang hiển thị | App + DB 0.7 |
| `06-database-crud.png` | SQL `SELECT id,title,completed FROM tasks ORDER BY id;` | App + DB 0.7 |
| `07-github.png` | Repository, commit history và README | Repository 0.3 |
| `08-ssh.png` | SSH từ Windows sang Ubuntu (sau khi tự kiểm tra) | Server 0.5 |

**Các thao tác demo:** mở website từ Windows → thêm task → refresh → đổi trạng thái → truy vấn PostgreSQL → trình bày service, Nginx và UFW. Không chụp nội dung `.env` hoặc lộ mật khẩu.

**Còn phải thực hiện:** [ ] Upload ảnh thật; [ ] Kiểm tra SSH; [ ] Xác nhận phân công Nhân / Long / Lực; [ ] Chuẩn bị video demo dự phòng.