# Week 1 — System Architecture

Sơ đồ theo cùng phong cách **Web request** và **Deployment** của DevOps Challenge 1: [architecture.svg](architecture.svg).

## 1. Web request — chạy thực tế

```text
Windows Browser / Client
    │ HTTP :8080 qua VMware NAT (IP demo 192.168.79.129)
    ▼
Ubuntu VM — UFW (inbound deny; allow TCP 22,80,8080)
    │
    ▼
Nginx reverse proxy :8080
    │ proxy_pass http://127.0.0.1:8000
    ▼
Gunicorn + Flask Task Manager (loopback :8000)
    │ SQL read/write, DATABASE_URL từ EnvironmentFile
    ▼
PostgreSQL 18.6 (loopback :5432) → taskdb.tasks
    │
    ▼
VM disk /dev/sda2 (data persisted)

systemd taskmanager.service → runs Gunicorn/Flask
/etc/devops-task-manager.env → EnvironmentFile for systemd
```

Cổng 80 vẫn dành cho ứng dụng DevOps Challenge 1 (`Nginx :80 → Flask :5000`). Hai site tồn tại độc lập trong cùng máy ảo. Không có load balancer, HTTPS hay Docker trong Week 1.

## 2. Deployment — thao tác thủ công

```text
GitHub: trvannhan/devops-final-task-manager
           │ git clone / git pull (manual)
           ▼
/home/vannhan/devops-final-task-manager
           ├── .venv + pip install -r requirements.txt
           ├── scripts/taskmanager.service → /etc/systemd/system/
           ├── scripts/nginx-taskmanager.conf → /etc/nginx/sites-available/
           └── .env (local only) → /etc/devops-task-manager.env

systemctl daemon-reload / enable --now taskmanager
nginx -t / systemctl reload nginx
curl :8080/health → verify PostgreSQL connection
```

## 3. Networking & security

| Thành phần | Bind/port | Ghi chú |
|---|---|---|
| Windows Client | → 192.168.79.129:8080 | IP demo, DHCP có thể đổi |
| Nginx new site | 0.0.0.0:8080 | UFW cho phép |
| Gunicorn/Flask | 127.0.0.1:8000 | Không truy cập trực tiếp từ Windows |
| PostgreSQL | 127.0.0.1:5432 | Không mở trên mạng ngoài |
| Nginx old site | :80 | Bài 10% vẫn hoạt động |
| SSH | :22 | UFW mở cho lab; cần giới hạn IP cho môi trường public |

Lưu ý hệ thống dùng **VMware NAT** theo môi trường được mô tả trong quá trình triển khai; mạng NAT và IP cần xác nhận trong VMware settings nếu thay VM hoặc chuyển máy.

## 4. Week 1 versus later weeks

**Week 1:** manually deploy code, app/DB operations, server/security basics, architecture, evidence.  
**Week 2:** container + CI/CD (chưa thực hiện).  
**Week 3:** monitoring, alerts, backup/restore.  
**Week 4:** full presentation and troubleshooting.
