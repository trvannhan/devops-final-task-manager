#!/usr/bin/env bash
# Chuyển dữ liệu bảng tasks từ PostgreSQL cài trên VM (Week 1) sang container db (Week 2).
# Chỉ chạy MỘT lần, sau khi pipeline đã deploy container lần đầu.
# Cách chạy (trên VM):  bash scripts/migrate-host-db-to-docker.sh
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-taskmanager-db-1}"   # tên do "name: taskmanager" trong docker-compose.yml

if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  echo "Không thấy container $DB_CONTAINER đang chạy. Hãy để pipeline deploy xong trước." >&2
  exit 1
fi

in_container() {
  docker exec -i -e PGOPTIONS='-c timezone=Asia/Ho_Chi_Minh' "$DB_CONTAINER" \
    psql -U taskapp -d taskdb -v ON_ERROR_STOP=1 "$@"
}

existing=$(in_container -tAc 'SELECT count(*) FROM tasks')
if [ "$existing" != "0" ]; then
  echo "Container DB đã có $existing task. Dừng lại để tránh ghi trùng dữ liệu." >&2
  exit 1
fi

host_count=$(sudo -u postgres psql -d taskdb -tAc 'SELECT count(*) FROM tasks')
echo "PostgreSQL trên VM có $host_count task. Đang chuyển sang container..."

sudo -u postgres pg_dump --data-only --table=tasks taskdb | in_container -q

echo "Hoàn tất. Dữ liệu trong container:"
in_container -c 'SELECT id, title, completed FROM tasks ORDER BY id'
