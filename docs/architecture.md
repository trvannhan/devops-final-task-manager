# Week 1 Deployment Architecture

![Task Manager architecture](architecture.png)

Editable source: [`architecture.svg`](architecture.svg).

```text
Windows browser (client)
        | HTTP :8080
        v
Ubuntu 26.04.1 VM (VMware NAT network, VMnet8)
  Nginx :8080 (public VM interface, reverse proxy)
        | proxy_pass
        v
  Gunicorn + Flask 127.0.0.1:8000   <- systemd taskmanager.service
        | psycopg (DATABASE_URL)        loads /etc/devops-task-manager.env
        v
  PostgreSQL 18.6 127.0.0.1:5432 (database taskdb, role taskapp)
        | persistent DB files
        v
  Ubuntu virtual disk (/var/lib/postgresql)

GitHub repository -> manual git clone / git pull -> /home/vannhan/devops-final-task-manager
SSH :22 (admin only).
```

## Ports

| Port | Service | Listens on | Opened in UFW |
|------|---------|-----------|---------------|
| 22   | SSH (admin) | all interfaces | yes |
| 8080 | Nginx -> Task Manager | all interfaces | yes |
| 80   | Nginx -> another course project (`devops-app`), not part of this system | all interfaces | yes |
| 8000 | Gunicorn/Flask | 127.0.0.1 only | no |
| 5432 | PostgreSQL | 127.0.0.1 only | no |

Ports 8000 and 5432 are bound to localhost, so clients can only reach the application through Nginx on 8080.
