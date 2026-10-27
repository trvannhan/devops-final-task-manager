# DevOps Task Manager — Final Project 2026 (Week 1)

Flask web + JSON API + PostgreSQL database, deployed manually on an Ubuntu VM behind Nginx.
**Week 1: manual deployment. Docker and CI/CD will be added in Week 2.**

## Source and scope
- Source: application code was written with the help of an AI assistant, then reviewed, tested and deployed by the team. No third-party project template was copied.
- Team's own work: application code, deployment architecture, Ubuntu/Nginx/systemd/UFW configuration, documentation.

## Features
- View all tasks, add a task, mark completed/reopen, delete.
- `GET /health`, `GET /api/tasks`, `POST /api/tasks`, `PATCH /api/tasks/<id>`, `DELETE /api/tasks/<id>`.
- Tasks are stored in PostgreSQL (not browser local storage), so they survive page reloads and restarts.

## Architecture
Browser -> Nginx on the VM (`:8080`) -> Gunicorn/Flask (`127.0.0.1:8000`) -> PostgreSQL (`127.0.0.1:5432`) -> VM disk.
See [`docs/architecture.md`](docs/architecture.md) and [`docs/architecture.png`](docs/architecture.png).

![Architecture](docs/architecture.png)

> Port 80 on the same VM belongs to another course project (`devops-app`). Task Manager uses **8080** so both run side by side; nothing in this guide touches the port-80 site.

## Server environment
| Item | Value |
|------|-------|
| Hypervisor | VMware, bridged network |
| OS | Ubuntu 26.04.1 LTS |
| CPU / RAM / Disk | 2 vCPU / 3.3 GiB RAM / 35 GB disk (`/dev/sda2`) |
| PostgreSQL | 18.6 (Ubuntu package `18.6-0ubuntu0.26.04.1`) |
| Python | 3.14.4 |
| Admin user | `vannhan` (SSH) |

The VM's IP address is not recorded in this repository; use `hostname -I` on the VM.

## Manual installation (Ubuntu 26.04)
Take a VM snapshot first.

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip postgresql nginx curl ufw
sudo systemctl enable --now postgresql nginx
```

### 1. PostgreSQL user and database
```bash
sudo -u postgres psql
```
Inside `psql` (use your own long alphanumeric password, never commit it):
```sql
CREATE USER taskapp WITH PASSWORD 'CHANGE_ME_LONG_RANDOM_PASSWORD';
CREATE DATABASE taskdb OWNER taskapp;
\q
```

### 2. Get the code and install dependencies
```bash
cd ~
git clone https://github.com/trvannhan/devops-final-task-manager.git
cd devops-final-task-manager
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
sudo cp .env.example /etc/devops-task-manager.env
sudo chmod 600 /etc/devops-task-manager.env
sudo nano /etc/devops-task-manager.env
```
In the environment file set
`DATABASE_URL=postgresql://taskapp:YOUR_OWN_PASSWORD@127.0.0.1:5432/taskdb`
with the same password as the PostgreSQL role. The file lives outside the repository and is readable by root only.

### 3. Create the table
```bash
cd ~/devops-final-task-manager
sudo bash -c 'set -a; . /etc/devops-task-manager.env; set +a; psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f schema.sql'
```
Expected output: `CREATE TABLE`. The table is owned by `taskapp`. Do not show `DATABASE_URL` in demo videos.

### 4. systemd service, Nginx and firewall
Check the paths in `scripts/taskmanager.service` match your user, then:
```bash
sudo cp scripts/taskmanager.service /etc/systemd/system/taskmanager.service
sudo systemctl daemon-reload
sudo systemctl enable --now taskmanager

sudo cp scripts/nginx-taskmanager.conf /etc/nginx/sites-available/taskmanager
sudo ln -sfn /etc/nginx/sites-available/taskmanager /etc/nginx/sites-enabled/taskmanager
sudo nginx -t
sudo systemctl reload nginx
```
Firewall (confirm SSH works before enabling UFW):
```bash
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp     # Task Manager
sudo ufw allow 80/tcp       # existing devops-app project (keep if still used)
sudo ufw enable
sudo ufw status verbose
```
Never open 8000 (Gunicorn) or 5432 (PostgreSQL); both listen on 127.0.0.1 only.

### 5. Verification
```bash
lsb_release -a
hostname -I
sudo systemctl is-active postgresql nginx taskmanager
sudo ss -lntp | grep -E ':22 |:8080 |:8000 |:5432 '

curl -i http://127.0.0.1:8080/health
curl -i -X POST http://127.0.0.1:8080/api/tasks -H 'Content-Type: application/json' \
     -d '{"title":"Demo Week 1","description":"Test read/write"}'
curl -s http://127.0.0.1:8080/api/tasks
# replace 1 with the id returned by the POST above
curl -i -X PATCH http://127.0.0.1:8080/api/tasks/1 -H 'Content-Type: application/json' -d '{"completed":true}'
sudo -u postgres psql -d taskdb -c 'SELECT id,title,completed FROM tasks ORDER BY id DESC LIMIT 10;'

.venv/bin/python -m pytest -q
```
Expected `/health`: `{"database":"connected","status":"ok"}`.

From the Windows browser open `http://<VM_IP>:8080/`, add a task, reload the page, mark it completed, and match the result with the SQL query above.

## Week 1 deliverables
- [x] Architecture: `docs/architecture.md`, `docs/architecture.png`
- [x] Repository, source code, this README
- [x] Team task allocation (below)
- [ ] Server evidence in `evidence/`: OS release, SSH login, `ufw status`, listening ports, service status
- [ ] App + DB evidence: POST/GET/PATCH responses and PostgreSQL SELECT (no passwords)
- [ ] Screenshot/video of the site opened from Windows on port 8080

## Team task allocation
| Member | Student ID | Responsibility | Evidence |
|--------|-----------|----------------|----------|
| Trần Văn Nhân (lead) | 23090036 | Ubuntu VM and SSH, Flask app/API, GitHub repository | VM screenshots, API evidence, commits |
| Trần Văn Lực | 23090019 | UFW firewall, Nginx + systemd deployment, architecture diagram | `ufw status`, service status, `docs/` |
| Nguyễn Vũ Hoàng Long | 23090026 | PostgreSQL database and CRUD, README, demo video | SQL evidence, README, video |

## Next weeks
Week 2: Dockerfile, Compose, volume, automated tests and CI/CD. Week 3: metrics, dashboard, alerts, firewall/secrets, backup/restore. Week 4: full demo, troubleshooting playbook and technical report.
