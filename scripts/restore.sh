#!/usr/bin/env bash
# Khôi phục database taskdb từ một file backup (Week 3).
#
# Cách dùng:
#   bash /opt/taskmanager/scripts/restore.sh                     # liệt kê các bản backup
#   bash /opt/taskmanager/scripts/restore.sh <file.dump>         # khôi phục (hỏi xác nhận)
#   bash /opt/taskmanager/scripts/restore.sh <file.dump> --yes   # khôi phục không hỏi
#
# Các bước: kiểm tra sha256 -> backup an toàn trạng thái hiện tại -> dừng app
#           -> pg_restore --clean trong 1 transaction -> chạy lại app -> kiểm tra /health
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/taskmanager}"
BACKUP_DIR="${BACKUP_DIR:-$DEPLOY_DIR/backups}"

log() { echo "$(date '+%F %T') [restore] $*"; }
die() { log "LỖI: $*" >&2; exit 1; }

cd "$DEPLOY_DIR"

if [ $# -eq 0 ]; then
  echo "Các bản backup hiện có (mới nhất ở dưới):"
  ls -1tr "$BACKUP_DIR"/taskdb-*.dump 2>/dev/null || echo "  (chưa có bản nào)"
  echo "Cách dùng: $0 <file.dump> [--yes]"
  exit 0
fi

file="$(readlink -f "$1")"
[ -f "$file" ] || die "Không tìm thấy file $1"

if [ -f "$file.sha256" ]; then
  sha256sum --check --quiet "$file.sha256" || die "File backup bị hỏng (sai sha256)"
  log "Kiểm tra sha256: OK"
else
  log "Cảnh báo: không có file $file.sha256, bỏ qua kiểm tra toàn vẹn"
fi

log "Nội dung bản backup: $(docker compose exec -T db pg_restore --list < "$file" | grep -c 'TABLE DATA') bảng dữ liệu"

if [ "${2:-}" != "--yes" ]; then
  read -r -p "Khôi phục sẽ GHI ĐÈ toàn bộ dữ liệu hiện tại bằng $(basename "$file"). Gõ YES để tiếp tục: " answer
  [ "$answer" = "YES" ] || die "Đã hủy"
fi

safety="$BACKUP_DIR/pre-restore-$(date +%Y%m%d-%H%M%S).dump"
(umask 077; docker compose exec -T db pg_dump -U taskapp -d taskdb --format=custom > "$safety")
log "Đã lưu trạng thái hiện tại vào $(basename "$safety") (phòng khi cần quay lại)"

log "Dừng app để không có ghi dữ liệu trong lúc khôi phục"
docker compose stop app
trap 'docker compose start app > /dev/null' EXIT

log "Đang khôi phục..."
docker compose exec -T db pg_restore -U taskapp -d taskdb \
  --clean --if-exists --single-transaction --exit-on-error < "$file"

log "Khởi động lại app"
docker compose start app
trap - EXIT

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8080/health > /dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS http://127.0.0.1:8080/health && echo
log "Hoàn tất. Số task sau khi khôi phục: $(docker compose exec -T db psql -U taskapp -d taskdb -tAc 'SELECT count(*) FROM tasks')"
