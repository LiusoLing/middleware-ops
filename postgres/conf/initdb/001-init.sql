-- ============================================================
-- 001-init.sql — 数据库初始化
-- ============================================================
-- 此脚本在 PostgreSQL 容器首次启动时自动执行
-- 放在 /docker-entrypoint-initdb.d/ 目录下
-- ============================================================

-- 启用 pg_stat_statements 扩展（已在 shared_preload_libraries 中加载）
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 启用 UUID 支持
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 启用 pgcrypto（加密函数）
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 创建应用数据库（示例）
-- 根据实际项目需求修改
-- ============================================================

-- 应用数据库
-- CREATE DATABASE my_app WITH OWNER = :POSTGRES_USER ENCODING = 'UTF8' LC_COLLATE = 'en_US.utf8' LC_CTYPE = 'en_US.utf8' TEMPLATE = template0;

-- 注释: 在实际项目中，取消上面 CREATE DATABASE 行的注释
-- 并为每个应用创建独立的数据库

-- ============================================================
-- 配置全局默认权限
-- ============================================================

-- 撤销 public schema 的公共创建权限（安全加固）
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- 撤销 public 数据库的公共连接权限
REVOKE ALL ON DATABASE template1 FROM PUBLIC;

-- ============================================================
-- 日志记录
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE '  PostgreSQL 初始化完成';
    RAISE NOTICE '  扩展: pg_stat_statements, uuid-ossp, pgcrypto';
    RAISE NOTICE '============================================';
END $$;
