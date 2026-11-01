-- Phân quyền database theo nguyên tắc quyền tối thiểu (Week 3).
--   taskapp    : chủ sở hữu database, dùng cho tạo bảng, backup, restore (không dùng trong app)
--   taskapp_rw : role của ứng dụng, chỉ SELECT/INSERT/UPDATE/DELETE trên bảng tasks,
--                không tạo/xóa bảng, không đổi cấu trúc
-- Chạy lại nhiều lần vẫn an toàn. Pipeline chạy file này mỗi lần deploy:
--   docker compose exec -T db psql -U taskapp -d taskdb -v ON_ERROR_STOP=1 \
--     -v app_password="$APP_DB_PASSWORD" < scripts/db-roles.sql

SELECT 'CREATE ROLE taskapp_rw LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'taskapp_rw') \gexec

ALTER ROLE taskapp_rw WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'app_password';

REVOKE ALL ON DATABASE taskdb FROM PUBLIC;
GRANT CONNECT ON DATABASE taskdb TO taskapp_rw;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO taskapp_rw;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE tasks TO taskapp_rw;
GRANT USAGE, SELECT ON SEQUENCE tasks_id_seq TO taskapp_rw;
