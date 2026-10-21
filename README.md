# DevOps Task Manager — Final Project 2026 (Week 1)

Flask Web + JSON API + PostgreSQL database. Original educational starter; code prepared for this project. **Week 1: manual deployment; Docker/CI/CD will be added in Week 2.**

## Features
- View all tasks, add a task, mark completed/reopen, delete.
- `GET /health`, `GET /api/tasks`, `POST /api/tasks`, `PATCH /api/tasks/<id>`, `DELETE /api/tasks/<id>`.
- PostgreSQL stores task records, not browser local storage.

## Architecture
Browser -> Ubuntu VM Nginx (`:80`) -> Gunicorn/Flask (`127.0.0.1:8000`) -> PostgreSQL (`127.0.0.1:5432`) -> VM disk. See `docs/architecture.md`.

## Ubuntu 24.04 VMware setup (existing user `vannhan`)
Snapshot the old VM first. Keep old `devops-app` intact; new project runs on `8000`. **If the old Nginx site listens on port 80, disable its site only when ready to switch the demo to Task Manager.**

```bash
sudo apt update
sudo apt install -y git python3 python3-venv python3-pip postgresql nginx curl ufw
sudo systemctl enable --now postgresql nginx
```

### 1. PostgreSQL (choose a long secret, do not share it)
```bash
sudo -u postgres psql
```
Run inside `psql` (replace the demo password with a strong alphanumeric secret):
```sql
CREATE USER taskapp WITH PASSWORD 'CHANGE_ME_LONG_RANDOM_PASSWORD';
CREATE DATABASE taskdb OWNER taskapp;
\q
```

### 2. Get code and install
Create a **new** public GitHub repository named `devops-final-task-manager`, then push this project's source from Windows. On Ubuntu (example account `vannhan`):
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
Set `DATABASE_URL=postgresql://taskapp:YOUR_OWN_PASSWORD@127.0.0.1:5432/taskdb` in the environment file; use the same password as for the PostgreSQL role. Do not commit the real credentials.

### 3. Initialize schema (edit .env location first)
```bash
cd /home/vannhan/devops-final-task-manager
sudo bash -c 'set -a; source /etc/devops-task-manager.env; set +a; /home/vannhan/devops-final-task-manager/.venv/bin/python -c "import os,psycopg,pathlib; conn=psycopg.connect(os.environ["DATABASE_URL"]); conn.execute(pathlib.Path("schema.sql").read_text()); conn.commit(); conn.close(); print("Schema created")"'
```
Do not print the DATABASE_URL in demo videos.

### 4. Run service and Nginx
Edit `scripts/taskmanager.service` paths if needed, then:
```bash
sudo cp scripts/taskmanager.service /etc/systemd/system/taskmanager.service
sudo systemctl daemon-reload
sudo systemctl enable --now taskmanager
sudo cp scripts/nginx-taskmanager.conf /etc/nginx/sites-available/taskmanager
sudo ln -sfn /etc/nginx/sites-available/taskmanager /etc/nginx/sites-enabled/taskmanager
sudo rm -f /etc/nginx/sites-enabled/default
# Disable ONLY the old site symlink, not its config file:
sudo rm -f /etc/nginx/sites-enabled/devops-app
sudo nginx -t
sudo systemctl reload nginx
```
Before `sudo ufw enable`, confirm SSH is accessible. On a private classroom network:
```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw enable
sudo ufw status verbose
```
Restrict SSH source IP and add HTTPS if exposing VM on Internet. Never open DB 5432 or Gunicorn 8000 to external clients.

### 5. Verification and evidence
```bash
lsb_release -a
hostname -I
sudo systemctl is-active postgresql nginx taskmanager
curl -i http://127.0.0.1/health
curl -i -X POST http://127.0.0.1/api/tasks -H 'Content-Type: application/json' -d '{"title":"Demo Week 1","description":"Test read/write"}'
curl -s http://127.0.0.1/api/tasks
sudo -u postgres psql -d taskdb -c 'SELECT id,title,completed FROM tasks ORDER BY id DESC LIMIT 10;'
sudo ss -lntp | grep -E ':22|:80|:8000|:5432'
.venv/bin/pytest -q
```
On Windows browser visit `http://<VM_IP>/` (replace VM_IP with VM IPv4). Add a task, refresh, complete it; correlate with SQL query. Expected `/health`: `{ "status":"ok", "database":"connected" }`.

### Week 1 deliverables
- `docs/architecture.md` and exported diagram as `architecture.png`/`pdf`
- GitHub repo, documented installation and responsibilities
- screenshots: Ubuntu release, SSH, `ufw status`, listening ports, service status
- successful POST/GET/PATCH and PostgreSQL SELECT (no credentials)
- screenshot/video accessing site from Windows

## Team task allocation (edit names and contribution evidence)
- Member 1: Flask app/API and database CRUD
- Member 2: Ubuntu/SSH/UFW/Nginx/systemd
- Member 3: Git repository, documentation, architecture, live demo

## Next weeks
Week 2: Dockerfile, Compose, volume, automated tests and CI/CD. Week 3: metrics, dashboard, alerts, firewall/secrets, backup/restore. Week 4: full demo, troubleshooting playbook and technical report.
