#!/usr/bin/env bash
# Sao lưu database taskdb (Week 3).
#
#   File      : /opt/taskmanager/backups/taskdb-YYYYMMDD-HHMMSS.dump (định dạng custom của pg_dump)
#               kèm file .sha256 để kiểm tra toàn vẹn khi restore
#   Lịch      : 02:00 mỗi ngày (cron do pipeline cài), chạy tay được bất cứ lúc nào
#   Lưu giữ   : xóa bản cũ hơn KEEP_DAYS ngày (mặc định 7)
#   Giám sát  : ghi thời điểm backup thành công vào backups/metrics/backup.prom,
#               Prometheus cảnh báo BackupTooOld nếu quá 26 giờ chưa có backup
#
# Cách dùng:  bash /opt/taskmanager/scripts/backup.sh
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/taskmanager}"
BACKUP_DIR="${BACKUP_DIR:-$DEPLOY_DIR/backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"
METRICS_DIR="$BACKUP_DIR/metrics"

log() { echo "$(date '+%F %T') [backup] $*"; }

cd "$DEPLOY_DIR"
umask 077
mkdir -p "$BACKUP_DIR"
mkdir -p "$METRICS_DIR"
chmod 755 "$METRICS_DIR"

stamp="$(date +%Y%m%d-%H%M%S)"
file="$BACKUP_DIR/taskdb-$stamp.dump"
tmp="$file.part"
trap 'rm -f "$tmp"' EXIT

log "Bắt đầu backup database taskdb -> $file"
docker compose exec -T db pg_dump -U taskapp -d taskdb --format=custom > "$tmp"

# Kiểm tra file đọc được trước khi coi là thành công
docker compose exec -T db pg_restore --list < "$tmp" > /dev/null
mv "$tmp" "$file"
sha256sum "$file" > "$file.sha256"

size="$(stat -c %s "$file")"
rows="$(docker compose exec -T db psql -U taskapp -d taskdb -tAc 'SELECT count(*) FROM tasks')"
log "Hoàn tất: $(basename "$file"), $size bytes, $rows task"

# Chính sách lưu giữ
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'taskdb-*.dump*' -o -name 'pre-restore-*.dump' \) \
  -mtime +"$KEEP_DAYS" -print -delete \
  | while read -r old; do log "Xóa bản cũ hơn $KEEP_DAYS ngày: $(basename "$old")"; done

# Số liệu cho Prometheus (node-exporter textfile collector)
umask 022
cat > "$METRICS_DIR/backup.prom.tmp" <<EOF
# HELP taskmanager_backup_last_success_timestamp_seconds Unix time of the last successful database backup.
# TYPE taskmanager_backup_last_success_timestamp_seconds gauge
taskmanager_backup_last_success_timestamp_seconds $(date +%s)
# HELP taskmanager_backup_last_size_bytes Size of the last database backup file.
# TYPE taskmanager_backup_last_size_bytes gauge
taskmanager_backup_last_size_bytes $size
# HELP taskmanager_backup_last_rows Number of tasks in the last database backup.
# TYPE taskmanager_backup_last_rows gauge
taskmanager_backup_last_rows $rows
EOF
mv "$METRICS_DIR/backup.prom.tmp" "$METRICS_DIR/backup.prom"

log "Danh sách backup hiện có:"
ls -lh "$BACKUP_DIR"/taskdb-*.dump
