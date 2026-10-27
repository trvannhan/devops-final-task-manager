# Week 1 Evidence

Screenshots taken on the Ubuntu VM and the Windows client on 2026-10-27.
Private IP addresses are masked. No passwords, tokens or `DATABASE_URL` values appear in any screenshot.

| File | What it proves |
|------|----------------|
| `01-os.png` | OS and resources: Ubuntu 26.04.1 LTS, 2 vCPU, 3.3 GiB RAM, 35 GB disk |
| `02-ssh.png` | SSH login from Windows (PowerShell) to the VM as `vannhan` |
| `03-ufw-ports.png` | UFW active, default deny incoming, allows 22 and 8080 (80 belongs to another project). Nginx listens on `0.0.0.0:8080`; Gunicorn `127.0.0.1:8000` and PostgreSQL `127.0.0.1:5432` are localhost only |
| `04-services.png` | `postgresql`, `nginx`, `taskmanager` are active; `taskmanager.service` is enabled and runs Gunicorn with 2 workers on 127.0.0.1:8000 |
| `05-api.png` | `GET /health` 200 (database connected), `POST /api/tasks` 201 (task id 6), `GET /api/tasks`, `PATCH /api/tasks/6` 200 (`completed: true`) |
| `06-sql.png` | `SELECT` in PostgreSQL shows task 6 "Demo Week 1" with `completed = t`, matching the API calls |
| `07a-browser-add.png` | Windows browser at `VM_IP:8080`: task "Demo từ Windows" added and still present after reload |
| `07b-browser-complete.png` | Same task marked completed from the browser; counters updated |
| `08-tests.png` | Automated tests: `3 passed` |
