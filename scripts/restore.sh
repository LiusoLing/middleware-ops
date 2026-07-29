#!/usr/bin/env bash
# ============================================================
# restore.sh — 从备份恢复数据
# ============================================================
# 功能:
#   - 从指定日期（或最新）的备份恢复数据
#   - 恢复前自动创建安全备份
#   - 支持按服务选择性恢复
#
# 用法:
#   ./scripts/restore.sh                        # 恢复全部（最新备份）
#   ./scripts/restore.sh 2026-07-29             # 从指定日期恢复全部
#   ./scripts/restore.sh --service postgres     # 只恢复 PostgreSQL
#   ./scripts/restore.sh --service redis        # 只恢复 Redis
#   ./scripts/restore.sh 2026-07-29 --service postgres  # 组合使用
#   ./scripts/restore.sh --list                 # 列出所有备份
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

load_env
check_docker

BACKUP_ROOT="${PROJECT_ROOT}/${BACKUP_DIR:-backups}"

# ---- 参数解析 ----
RESTORE_DATE=""
LIST_ONLY=false
TARGET_SERVICE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list|-l)
            LIST_ONLY=true
            shift
            ;;
        --service|-s)
            TARGET_SERVICE="$2"
            validate_service "$TARGET_SERVICE" || exit 1
            shift 2
            ;;
        *)
            RESTORE_DATE="$1"
            shift
            ;;
    esac
done

# ---- 列出备份 ----
if $LIST_ONLY; then
    info "可用备份:"
    echo ""
    if [[ -d "$BACKUP_ROOT" ]]; then
        local dirs
        dirs=$(ls -1t "$BACKUP_ROOT" 2>/dev/null || true)
        if [[ -z "$dirs" ]]; then
            dim "  (无备份)"
        else
            while IFS= read -r dir; do
                if [[ -d "${BACKUP_ROOT}/${dir}" ]]; then
                    local size
                    size=$(du -sh "${BACKUP_ROOT}/${dir}" 2>/dev/null | cut -f1)
                    printf "  ${COLOR_BOLD}%-16s${COLOR_RESET} %s\n" "$dir" "$size"

                    if [[ -f "${BACKUP_ROOT}/${dir}/metadata.json" ]]; then
                        local pg_file
                        pg_file=$(grep -o '"file": *"[^"]*"' "${BACKUP_ROOT}/${dir}/metadata.json" 2>/dev/null | head -1 | cut -d'"' -f4 || echo "N/A")
                        dim "    PostgreSQL: ${pg_file:-N/A}"
                        local redis_file
                        redis_file=$(grep -o '"file": *"[^"]*"' "${BACKUP_ROOT}/${dir}/metadata.json" 2>/dev/null | tail -1 | cut -d'"' -f4 || echo "N/A")
                        dim "    Redis: ${redis_file:-N/A}"
                    fi
                    echo ""
                fi
            done <<< "$dirs"
        fi
    else
        dim "  备份目录不存在"
    fi
    exit 0
fi

if [[ -n "$TARGET_SERVICE" ]]; then
    header "📥 恢复 ${TARGET_SERVICE}"
else
    header "📥 Middleware Restore — 数据恢复"
fi

# ---- 确定恢复日期 ----
if [[ -z "$RESTORE_DATE" ]]; then
    RESTORE_DATE=$(ls -1t "$BACKUP_ROOT" 2>/dev/null | head -1 || true)
    if [[ -z "$RESTORE_DATE" ]]; then
        error "没有可用的备份"
        echo ""
        dim "  可以先执行: ./scripts/backup.sh"
        exit 1
    fi
    info "使用最新备份: $RESTORE_DATE"
else
    info "使用指定备份: $RESTORE_DATE"
fi

RESTORE_PATH="${BACKUP_ROOT}/${RESTORE_DATE}"

if [[ ! -d "$RESTORE_PATH" ]]; then
    error "备份目录不存在: $RESTORE_PATH"
    echo ""
    info "可用备份:"
    ls -1t "$BACKUP_ROOT" 2>/dev/null | while IFS= read -r d; do
        [[ -d "${BACKUP_ROOT}/${d}" ]] && dim "  $d"
    done
    exit 1
fi

echo ""

# ---- 安全确认 ----
echo -e "${COLOR_RED}${COLOR_BOLD}⚠️  警告: 恢复操作将覆盖当前数据！${COLOR_RESET}"
echo ""
info "恢复来源: $RESTORE_PATH"
if [[ -n "$TARGET_SERVICE" ]]; then
    info "恢复范围: 仅 $TARGET_SERVICE"
fi

if [[ -f "${RESTORE_PATH}/metadata.json" ]]; then
    dim "备份元信息:"
    dim "$(cat "${RESTORE_PATH}/metadata.json" | sed 's/^/  /')"
fi

echo ""
if ! confirm "确认要从 $RESTORE_DATE 的备份恢复数据吗？此操作不可逆！"; then
    info "已取消恢复操作"
    exit 0
fi

echo ""

# ---- 安全备份（恢复前先备份当前数据） ----
info "恢复前创建安全备份..."
"${SCRIPT_DIR}/backup.sh" --no-compress ${TARGET_SERVICE:+"$TARGET_SERVICE"}
echo ""

POSTGRES_RESTORED=false
REDIS_RESTORED=false

# ============================================================
# 恢复 PostgreSQL
# ============================================================
restore_postgres() {
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$TARGET_SERVICE" != "postgres" ]]; then
        dim "  跳过 PostgreSQL（指定了 $TARGET_SERVICE）"
        return
    fi

    PG_BACKUP=$(ls -1t "${RESTORE_PATH}/postgres/" 2>/dev/null | head -1 || true)

    if [[ -z "$PG_BACKUP" ]]; then
        warn "未找到 PostgreSQL 备份文件，跳过"
        return
    fi

    info "恢复 PostgreSQL..."
    local pg_file="${RESTORE_PATH}/postgres/${PG_BACKUP}"
    local is_gzipped=false

    if [[ "$pg_file" == *.gz ]]; then
        is_gzipped=true
    fi

    # 确保 PostgreSQL 在运行
    if ! is_service_running "postgres"; then
        warn "PostgreSQL 未运行，正在启动..."
        compose_cmd up -d postgres
        sleep 5
    fi

    local pg_user="${POSTGRES_USER:-postgres}"
    local pg_container
    pg_container=$(compose_cmd ps -q postgres)

    if [[ -z "$pg_container" ]]; then
        error "无法获取 PostgreSQL 容器 ID"
        return
    fi

    # 先终止现有连接
    info "终止现有数据库连接..."
    docker exec "$pg_container" psql -U "$pg_user" -c "
        SELECT pg_terminate_backend(pg_stat_activity.pid)
        FROM pg_stat_activity
        WHERE pg_stat_activity.datname IS NOT NULL
          AND pid <> pg_backend_pid();
    " 2>/dev/null || true

    # 执行恢复
    info "执行恢复..."
    local restore_exit_code=0
    if $is_gzipped; then
        gunzip -c "$pg_file" | docker exec -i "$pg_container" psql -U "$pg_user" postgres 2>&1 | while IFS= read -r line; do
            dim "  $line"
        done
        restore_exit_code=${PIPESTATUS[0]}
    else
        docker exec -i "$pg_container" psql -U "$pg_user" < "$pg_file" 2>&1 | while IFS= read -r line; do
            dim "  $line"
        done
        restore_exit_code=${PIPESTATUS[0]}
    fi

    if [[ "${restore_exit_code:-0}" -eq 0 ]]; then
        success "PostgreSQL 恢复完成"
        POSTGRES_RESTORED=true
    else
        error "PostgreSQL 恢复过程中出现错误（部分数据可能已恢复）"
    fi
}

# ============================================================
# 恢复 Redis
# ============================================================
restore_redis() {
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$TARGET_SERVICE" != "redis" ]]; then
        dim "  跳过 Redis（指定了 $TARGET_SERVICE）"
        return
    fi

    RDB_BACKUP=$(ls -1t "${RESTORE_PATH}/redis/" 2>/dev/null | head -1 || true)

    if [[ -z "$RDB_BACKUP" ]]; then
        warn "未找到 Redis 备份文件，跳过"
        return
    fi

    info "恢复 Redis..."
    local rdb_file="${RESTORE_PATH}/redis/${RDB_BACKUP}"

    # 确保 Redis 在运行
    if ! is_service_running "redis"; then
        warn "Redis 未运行，正在启动..."
        compose_cmd up -d redis
        sleep 3
    fi

    local redis_password="${REDIS_PASSWORD}"
    local redis_container
    redis_container=$(compose_cmd ps -q redis)

    if [[ -z "$redis_container" ]]; then
        error "无法获取 Redis 容器 ID"
        return
    fi

    info "停止 Redis 写入..."
    docker exec "$redis_container" redis-cli --no-auth-warning -a "$redis_password" SHUTDOWN NOSAVE 2>/dev/null || true
    sleep 2

    local rdb_dest="/data/dump.rdb"
    if [[ "$rdb_file" == *.gz ]]; then
        gunzip -c "$rdb_file" | docker exec -i "$redis_container" tee "$rdb_dest" > /dev/null 2>&1 || true
    else
        docker cp "$rdb_file" "${redis_container}:${rdb_dest}" 2>/dev/null || true
    fi

    info "重启 Redis 容器..."
    compose_cmd restart redis 2>&1 | tail -1

    success "Redis 恢复完成"
    REDIS_RESTORED=true
}

restore_postgres
echo ""
restore_redis

echo ""
separator
echo ""

if $POSTGRES_RESTORED || $REDIS_RESTORED; then
    success "🎉 恢复完成！"
    echo ""
    info "请执行状态检查: ./scripts/status.sh${TARGET_SERVICE:+ $TARGET_SERVICE}"
else
    warn "没有恢复任何数据"
fi

echo ""
