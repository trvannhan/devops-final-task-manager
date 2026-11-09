#!/usr/bin/env bash
# Chuẩn bị một máy Ubuntu SẠCH để chạy Task Manager (Week 4 - deployment guide).
#
# Script làm các bước có thể tự động hoá trên VM:
#   1. Cài gói: git, curl, cron, ufw, openssh-server, nginx, docker.io, docker-compose-v2
#   2. Bật dịch vụ ssh, nginx, docker, cron (tự chạy khi khởi động)
#   3. Cho user hiện tại dùng Docker (nhóm docker)
#   4. Tạo thư mục deploy /opt/taskmanager (chủ sở hữu là user hiện tại, quyền 750)
#   5. Cài site Nginx :8080 -> 127.0.0.1:8000 (scripts/nginx-taskmanager.conf)
#   6. Bật UFW: chặn mọi kết nối vào, chỉ mở 22 (SSH) và 8080 (web)
#
# Script KHÔNG làm (cần thao tác trên GitHub, xem docs/deployment-guide.md):
#   - tạo GitHub Secrets, đăng ký self-hosted runner, chạy pipeline.
#
# Chạy được nhiều lần (idempotent). Cách dùng, trong thư mục repo đã clone:
#   bash scripts/bootstrap-vm.sh               # mở 22 + 8080
#   OPEN_PORT_80=1 bash scripts/bootstrap-vm.sh  # mở thêm 80 (nếu VM có project khác dùng cổng 80)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/taskmanager}"
DEPLOY_USER="${DEPLOY_USER:-$(id -un)}"
OPEN_PORT_80="${OPEN_PORT_80:-0}"

log()  { echo -e "\n\033[1;32m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Hãy chạy bằng user thường có quyền sudo (ví dụ vannhan), không chạy bằng root." >&2
  exit 1
fi

log "1/6 Cài gói hệ thống"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git curl ca-certificates cron ufw openssh-server nginx docker.io docker-compose-v2

log "2/6 Bật dịch vụ ssh, nginx, docker, cron"
sudo systemctl enable --now ssh nginx docker cron

log "3/6 Cho user $DEPLOY_USER dùng Docker"
if id -nG "$DEPLOY_USER" | grep -qw docker; then
  echo "User $DEPLOY_USER đã thuộc nhóm docker"
else
  sudo usermod -aG docker "$DEPLOY_USER"
  warn "Đã thêm $DEPLOY_USER vào nhóm docker. Cần đăng xuất/đăng nhập lại (hoặc 'newgrp docker'),"
  warn "và nếu runner đã cài trước đó thì khởi động lại runner: cd ~/actions-runner && sudo ./svc.sh stop && sudo ./svc.sh start"
fi

log "4/6 Tạo thư mục deploy $DEPLOY_DIR"
sudo install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 750 "$DEPLOY_DIR"
ls -ld "$DEPLOY_DIR"

log "5/6 Cài site Nginx :8080"
# Week 1 dùng systemd + Gunicorn trên host ở cổng 8000; nếu còn thì tắt để container app dùng cổng này
if systemctl list-unit-files taskmanager.service >/dev/null 2>&1 \
   && systemctl is-enabled taskmanager >/dev/null 2>&1; then
  warn "Phát hiện service taskmanager (Week 1) -> tắt để giải phóng cổng 8000"
  sudo systemctl disable --now taskmanager
fi
sudo cp "$REPO_DIR/scripts/nginx-taskmanager.conf" /etc/nginx/sites-available/taskmanager
sudo ln -sfn /etc/nginx/sites-available/taskmanager /etc/nginx/sites-enabled/taskmanager
sudo nginx -t
sudo systemctl reload nginx

log "6/6 Cấu hình firewall UFW"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp comment 'Task Manager (Nginx)'
if [ "$OPEN_PORT_80" = "1" ]; then
  sudo ufw allow 80/tcp comment 'project khac tren cung VM'
fi
sudo ufw --force enable
sudo ufw status verbose

log "Kiểm tra"
echo "Docker      : $(docker --version 2>/dev/null || sudo docker --version)"
echo "Compose     : $(docker compose version 2>/dev/null || sudo docker compose version)"
echo "Dịch vụ     : $(systemctl is-active ssh nginx docker cron | tr '\n' ' ')"
echo "Cổng đang nghe:"
sudo ss -lntp | grep -E ':22 |:8080 |:8000 |:5432 ' || true
if sudo ss -lntp | grep -q ':5432 '; then
  warn "Cổng 5432 đang mở trên host (PostgreSQL Week 1?). Không bắt buộc tắt, nhưng nên tắt nếu không dùng:"
  warn "  sudo systemctl disable --now postgresql"
fi

cat <<EOF

Xong phần VM. Các bước tiếp theo (xem docs/deployment-guide.md):
  1. GitHub -> Settings -> Secrets and variables -> Actions: tạo POSTGRES_PASSWORD, APP_DB_PASSWORD, GRAFANA_ADMIN_PASSWORD
  2. GitHub -> Settings -> Actions -> Runners -> New self-hosted runner (Linux x64), cài vào ~/actions-runner,
     rồi: cd ~/actions-runner && sudo ./svc.sh install $DEPLOY_USER && sudo ./svc.sh start
  3. Actions -> CI/CD -> Run workflow (nhánh main), chờ 3 job xanh
  4. Kiểm tra: curl -s http://127.0.0.1:8080/health
EOF

