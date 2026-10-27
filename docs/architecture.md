# Kiến trúc triển khai Week 1

![Sơ đồ kiến trúc Task Manager](architecture.png)

File nguồn có thể chỉnh sửa: [`architecture.svg`](architecture.svg).

```text
Trình duyệt Windows (client, máy host)
        | HTTP :8080
        v
VM Ubuntu 26.04.1 (VMware, mạng NAT VMnet8)
  Nginx :8080 (cổng mở ra ngoài, reverse proxy)
        | proxy_pass
        v
  Gunicorn + Flask 127.0.0.1:8000   <- systemd taskmanager.service
        | psycopg (DATABASE_URL)        nạp /etc/devops-task-manager.env
        v
  PostgreSQL 18.6 127.0.0.1:5432 (database taskdb, role taskapp)
        | lưu dữ liệu bền vững
        v
  Ổ đĩa ảo Ubuntu (/var/lib/postgresql)

GitHub repository -> git clone / git pull thủ công -> /home/vannhan/devops-final-task-manager
SSH :22 (chỉ dành cho quản trị).
```

## Luồng request
1. Người dùng mở `http://VM_IP:8080` trên trình duyệt Windows.
2. UFW cho phép kết nối vào cổng 8080; Nginx nhận request.
3. Nginx chuyển tiếp (`proxy_pass`) tới Gunicorn/Flask tại `127.0.0.1:8000`.
4. Flask đọc/ghi bảng `tasks` trong PostgreSQL tại `127.0.0.1:5432`.
5. Kết quả JSON trả ngược lại qua Nginx về trình duyệt.

## Bảng cổng
| Cổng | Dịch vụ | Lắng nghe trên | Mở trong UFW |
|------|---------|----------------|--------------|
| 22   | SSH (quản trị) | mọi interface | có |
| 8080 | Nginx -> Task Manager | mọi interface | có |
| 80   | Nginx -> project khác của môn học (`devops-app`), không thuộc hệ thống này | mọi interface | có |
| 8000 | Gunicorn/Flask | chỉ 127.0.0.1 | không |
| 5432 | PostgreSQL | chỉ 127.0.0.1 | không |

Cổng 8000 và 5432 chỉ gắn với localhost, nên client chỉ có thể truy cập ứng dụng thông qua Nginx ở cổng 8080.

## Ghi chú về mạng NAT
VM dùng mạng NAT của VMware (VMnet8) nên có IP riêng trong mạng ảo. Máy Windows chạy VMware truy cập trực tiếp được vào VM. Nếu muốn máy khác trong mạng LAN truy cập, cần chuyển sang chế độ Bridged hoặc cấu hình port forwarding trong Virtual Network Editor.
