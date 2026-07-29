#!/bin/bash
# ============================================================
# 000-config.sh — 注入自定义 PostgreSQL 配置
# ============================================================
# 此脚本在数据库首次初始化时执行（PGDATA 为空时）。
# 容器重启不会重复执行，因为 PGDATA 已存在。
#
# 设计原则:
#   - 不替换整个 postgresql.conf，而是通过 include_dir 追加自定义参数
#   - 保留 Docker entrypoint 生成的默认配置
#   - pg_hba.conf 从挂载的模板文件复制
# ============================================================
set -e

echo "[000-config] 应用自定义 PostgreSQL 配置..."

# ---- 1. 创建 conf.d 目录并加入 include_dir ----
CONF_D_DIR="/etc/postgresql/conf.d"
mkdir -p "$CONF_D_DIR"

# 只在还没有 include_dir 时追加，防止重复
if ! grep -q "include_dir = '$CONF_D_DIR'" "$PGDATA/postgresql.conf" 2>/dev/null; then
    echo "" >> "$PGDATA/postgresql.conf"
    echo "# ---- 自定义配置（conf.d 目录） ----" >> "$PGDATA/postgresql.conf"
    echo "include_dir = '$CONF_D_DIR'" >> "$PGDATA/postgresql.conf"
    echo "[000-config] include_dir 已追加到 postgresql.conf"
else
    echo "[000-config] include_dir 已存在，跳过"
fi

# ---- 2. 替换 pg_hba.conf ----
# Docker entrypoint 生成的 pg_hba.conf 默认只有 trust/local 规则
# 用我们挂载的安全配置文件替换
HBA_SOURCE="/tmp/custom_pg_hba.conf"
HBA_TARGET="$PGDATA/pg_hba.conf"

if [[ -f "$HBA_SOURCE" ]]; then
    cp "$HBA_SOURCE" "$HBA_TARGET"
    chmod 600 "$HBA_TARGET"
    echo "[000-config] pg_hba.conf 已替换"
else
    echo "[000-config] 警告: $HBA_SOURCE 不存在，使用默认 pg_hba.conf"
fi

echo "[000-config] 配置注入完成"
