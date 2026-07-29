-- ============================================================
-- 002-user.sql — 用户和权限设置
-- ============================================================
-- 此脚本创建应用用户并配置权限
-- 根据实际项目需求修改
-- ============================================================

-- ============================================================
-- 创建只读用户（示例）
-- ============================================================

-- 取消注释并按需修改:
-- CREATE ROLE readonly_user WITH LOGIN PASSWORD 'readonly_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION CONNECTION LIMIT 10;
-- GRANT CONNECT ON DATABASE my_app TO readonly_user;
-- GRANT USAGE ON SCHEMA public TO readonly_user;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly_user;

-- ============================================================
-- 创建应用用户（每个应用一个独立用户）
-- ============================================================

-- 取消注释并按需修改:
-- CREATE ROLE app_user WITH LOGIN PASSWORD 'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION CONNECTION LIMIT 50;
-- GRANT CONNECT ON DATABASE my_app TO app_user;
-- GRANT USAGE, CREATE ON SCHEMA public TO app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
-- GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO app_user;

-- ============================================================
-- 创建复制用户（用于主从复制）
-- ============================================================

-- 取消注释并按需修改:
-- CREATE ROLE replicator WITH LOGIN PASSWORD 'replicator_password' REPLICATION;

-- ============================================================
-- 权限检查
-- ============================================================
DO $$
DECLARE
    role_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO role_count FROM pg_roles;
    RAISE NOTICE '当前角色总数: %', role_count;
    RAISE NOTICE '用户初始化完成';
END $$;
