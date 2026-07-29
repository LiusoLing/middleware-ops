#!/usr/bin/env bash
# ============================================================
# backup.sh — 一键备份数据
# ============================================================
# 功能:
#   - PostgreSQL: pg_dumpall → gzip 压缩
#   - Redis: 触发 BGSAVE → 拷贝 RDB 文件
#   - 生成 metadata.json 记录备份元信息
#   - 自动清理过期备份
#
# 用法:
#   ./scripts/backup.sh                # 备份全部服务
#   ./scripts/backup.sh postgres       # 只备份 PostgreSQL
#   ./scripts/backup.sh redis          # 只备份 Redis
#   ./scripts/backup.sh --no-compress  # 不压缩
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

load_env
check_docker

# 配置
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DATE=$(date +%Y-%m-%d)
BACKUP_ROOT="${PROJECT_ROOT}/${BACKUP_DIR:-backups}"
BACKUP_PATH="${BACKUP_ROOT}/${BACKUP_DATE}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
COMPRESS=true
TARGET_SERVICE=""

# 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-compress)
            COMPRESS=false
            shift
            ;;
        *)
            # 可能是服务名
            if [[ -z "$TARGET_SERVICE" ]]; then
                TARGET_SERVICE="$1"
                validate_service "$TARGET_SERVICE" || exit 1
            else
                error "多余参数: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -n "$TARGET_SERVICE" ]]; then
    header "💾 备份 ${TARGET_SERVICE}"
else
    header "💾 Middleware Backup — 数据备份"
fi

# 创建备份目录
mkdir -p "${BACKUP_PATH}/postgres"
mkdir -p "${BACKUP_PATH}/redis"

info "备份时间: ${BACKUP_DATE} ${TIMESTAMP}"
info "备份目录: ${BACKUP_PATH}"
echo ""

POSTGRES_BACKUP_SUCCESS=false
REDIS_BACKUP_SUCCESS=false
POSTGRES_BACKUP_FILE="null"
REDIS_BACKUP_FILE="null"
POSTGRES_BACKUP_SIZE="N/A"
REDIS_BACKUP_SIZE="N/A"

# ============================================================
# PostgreSQL 备份 (pg_dumpall)
# ============================================================
do_backup_postgres() {
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$TARGET_SERVICE" != "postgres" ]]; then
        dim "  跳过 PostgreSQL（指定了 $TARGET_SERVICE）"
        return
    fi

    if ! compose_cmd ps postgres 2>/dev/null | grep -q "Up"; then
        warn "PostgreSQL 未运行，跳过"
        return
    fi

    info "备份 PostgreSQL..."

    local pg_user="${POSTGRES_USER:-postgres}"
    local pg_file="${BACKUP_PATH}/postgres/postgres_${TIMESTAMP}.sql"

    if docker exec "$(compose_cmd ps -q postgres)" \
        pg_dumpall -U "$pg_user" --no-password \
        > "$pg_file" 2>/tmp/pg_backup_error; then

        local pg_size_raw
        pg_size_raw=$(wc -c < "$pg_file" 2>/dev/null || echo 0)
        local pg_size
        if [[ "$(uname)" == "Darwin" ]]; then
            pg_size=$(echo "$pg_size_raw" | awk '{printf "%.1f MB", $1/1024/1024}')
        else
            pg_size=$(numfmt --to=iec "$pg_size_raw" 2>/dev/null || echo "${pg_size_raw} bytes")
        fi

        if $COMPRESS; then
            info "压缩 PostgreSQL 备份..."
            gzip -f "$pg_file"
            success "PostgreSQL 备份完成: postgres_${TIMESTAMP}.sql.gz ($pg_size)"
            POSTGRES_BACKUP_FILE="postgres/postgres_${TIMESTAMP}.sql.gz"
        else
            success "PostgreSQL 备份完成: postgres_${TIMESTAMP}.sql ($pg_size)"
            POSTGRES_BACKUP_FILE="postgres/postgres_${TIMESTAMP}.sql"
        fi
        POSTGRES_BACKUP_SIZE="$pg_size"
        POSTGRES_BACKUP_SUCCESS=true
    else
        local pg_error
        pg_error=$(cat /tmp/pg_backup_error 2>/dev/null || echo "未知错误")
        error "PostgreSQL 备份失败: $pg_error"
        rm -f "$pg_file" /tmp/pg_backup_error
    fi
}

# ============================================================
# Redis 备份
# ============================================================
do_backup_redis() {
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$TARGET_SERVICE" != "redis" ]]; then
        dim "  跳过 Redis（指定了 $TARGET_SERVICE）"
        return
    fi

    if ! compose_cmd ps redis 2>/dev/null | grep -q "Up"; then
        warn "Redis 未运行，跳过"
        return
    fi

    info "备份 Redis..."

    local redis_password="${REDIS_PASSWORD}"

    # 1. 触发 BGSAVE
    info "触发 Redis BGSAVE..."
    if docker exec "$(compose_cmd ps -q redis)" \
        redis-cli --no-auth-warning -a "$redis_password" BGSAVE &>/dev/null; then

        # 等待 BGSAVE 完成
        local wait_count=0
        while [[ $wait_count -lt 30 ]]; do
            sleep 1
            wait_count=$((wait_count + 1))
        done

        # 2. 拷贝 RDB 文件
        local rdb_file="${BACKUP_PATH}/redis/redis_${TIMESTAMP}.rdb"

        if docker cp "$(compose_cmd ps -q redis):/data/dump.rdb" "$rdb_file" 2>/dev/null; then
            local rdb_size_raw
            rdb_size_raw=$(wc -c < "$rdb_file" 2>/dev/null || echo 0)
            local rdb_size
            if [[ "$(uname)" == "Darwin" ]]; then
                rdb_size=$(echo "$rdb_size_raw" | awk '{printf "%.1f MB", $1/1024/1024}')
            else
                rdb_size=$(numfmt --to=iec "$rdb_size_raw" 2>/dev/null || echo "${rdb_size_raw} bytes")
            fi

            if $COMPRESS; then
                info "压缩 Redis 备份..."
                gzip -f "$rdb_file"
                success "Redis 备份完成: redis_${TIMESTAMP}.rdb.gz ($rdb_size)"
                REDIS_BACKUP_FILE="redis/redis_${TIMESTAMP}.rdb.gz"
            else
                success "Redis 备份完成: redis_${TIMESTAMP}.rdb ($rdb_size)"
                REDIS_BACKUP_FILE="redis/redis_${TIMESTAMP}.rdb"
            fi
            REDIS_BACKUP_SIZE="$rdb_size"
            REDIS_BACKUP_SUCCESS=true
        else
            error "Redis 备份失败: 无法拷贝 RDB 文件"
        fi
    else
        error "Redis BGSAVE 触发失败"
    fi
}

do_backup_postgres
echo ""
do_backup_redis

echo ""

# ============================================================
# 生成 metadata.json
# ============================================================
if $POSTGRES_BACKUP_SUCCESS || $REDIS_BACKUP_SUCCESS; then
    info "生成备份元信息..."

    metadata_file="${BACKUP_PATH}/metadata.json"

    # 如果已有 metadata（之前该日期已备份且现在只备份了部分服务），合并
    if [[ -f "$metadata_file" ]]; then
        cp "$metadata_file" "${metadata_file}.prev"
    fi

    cat > "$metadata_file" << METADATA_EOF
{
  "backup_time": "${BACKUP_DATE}T$(date +%H:%M:%S)",
  "timestamp": "${TIMESTAMP}",
  "project": "middleware",
  "services": {
    "postgres": {
      "backed_up": ${POSTGRES_BACKUP_SUCCESS},
      "file": "${POSTGRES_BACKUP_FILE}",
      "size": "${POSTGRES_BACKUP_SIZE}",
      "version": "${POSTGRES_VERSION:-unknown}",
      "method": "pg_dumpall"
    },
    "redis": {
      "backed_up": ${REDIS_BACKUP_SUCCESS},
      "file": "${REDIS_BACKUP_FILE}",
      "size": "${REDIS_BACKUP_SIZE}",
      "version": "${REDIS_VERSION:-unknown}",
      "method": "BGSAVE"
    }
  },
  "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
  "compress": ${COMPRESS}
}
METADATA_EOF

    success "元信息已保存: metadata.json"
fi

echo ""

# ============================================================
# 清理过期备份
# ============================================================
info "清理 ${RETENTION_DAYS} 天前的备份..."

deleted_count=0
while IFS= read -r -d '' old_backup; do
    if [[ -d "$old_backup" ]]; then
        rm -rf "$old_backup"
        dim "  删除: $(basename "$old_backup")"
        deleted_count=$((deleted_count + 1))
    fi
done < <(find "$BACKUP_ROOT" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -not -path "$BACKUP_ROOT" -print0 2>/dev/null || true)

if [[ $deleted_count -eq 0 ]]; then
    dim "  没有需要清理的过期备份"
else
    success "已清理 $deleted_count 个过期备份"
fi

echo ""
separator
echo ""

# 显示备份列表
info "当前备份列表:"
echo ""

if [[ -d "$BACKUP_ROOT" ]]; then
    backup_dirs=$(ls -1t "$BACKUP_ROOT" 2>/dev/null | head -10)
    if [[ -n "$backup_dirs" ]]; then
        while IFS= read -r dir; do
            if [[ -d "${BACKUP_ROOT}/${dir}" ]]; then
                size=$(du -sh "${BACKUP_ROOT}/${dir}" 2>/dev/null | cut -f1)
                printf "  ${COLOR_BOLD}%-16s${COLOR_RESET} %s\n" "$dir" "$size"
                ls -1 "${BACKUP_ROOT}/${dir}" 2>/dev/null | while IFS= read -r f; do
                    dim "    - $f"
                done
            fi
        done <<< "$backup_dirs"
    else
        dim "  (无备份)"
    fi
fi

echo ""
success "🎉 备份完成！"
info "备份位置: ${BACKUP_PATH}"
echo ""
