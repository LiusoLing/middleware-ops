-- ============================================================
-- 003-nacos-db.sql — Nacos 数据库初始化
-- ============================================================
-- 为 Nacos 服务创建独立的数据库
-- Nacos Server 首次启动时会自动创建所需的表结构
-- ============================================================

-- 创建 nacos 数据库（如果不存在）
SELECT 'CREATE DATABASE nacos'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'nacos')\gexec

-- 记录
DO $$
BEGIN
    RAISE NOTICE 'Nacos 数据库初始化完成';
END $$;
