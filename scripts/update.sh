#!/usr/bin/env bash
# ============================================================
# update.sh — 升级 Docker 镜像
# ============================================================
# 功能:
#   - 拉取最新镜像
#   - 自动备份当前数据
#   - 重启服务
#   - 等待健康检查通过
#
# 用法:
#   ./scripts/update.sh              # 升级所有服务
#   ./scripts/update.sh postgres     # 升级 PostgreSQL
#   ./scripts/update.sh redis        # 升级 Redis
#   ./scripts/update.sh --check      # 仅检查是否有更新
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

header "⬆️  Middleware Update — 镜像升级"

load_env
check_docker

# 参数解析
TARGET_SERVICE=""
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|-c)
            CHECK_ONLY=true
            shift
            ;;
        *)
            TARGET_SERVICE="$1"
            shift
            ;;
    esac
done

# ---- 1. 更新前备份 ----
if ! $CHECK_ONLY; then
    info "升级前创建安全备份..."
    "${SCRIPT_DIR}/backup.sh"
    echo ""
fi

# ---- 2. 拉取最新镜像 ----
if [[ -n "$TARGET_SERVICE" ]]; then
    info "拉取 $TARGET_SERVICE 最新镜像..."
    compose_cmd pull "$TARGET_SERVICE" 2>&1 | while IFS= read -r line; do
        dim "  $line"
    done
else
    info "拉取所有服务最新镜像..."
    compose_cmd pull 2>&1 | while IFS= read -r line; do
        dim "  $line"
    done
fi

echo ""

if $CHECK_ONLY; then
    info "镜像已拉取，使用 ./scripts/start.sh 启动新版本"
    info "或使用 ./scripts/update.sh 自动完成全部流程"
    exit 0
fi

# ---- 3. 重建并重启服务 ----
if [[ -n "$TARGET_SERVICE" ]]; then
    info "重建并重启 $TARGET_SERVICE..."
    compose_cmd up -d --force-recreate "$TARGET_SERVICE" 2>&1 | tail -1
else
    info "重建并重启所有服务..."
    compose_cmd up -d --force-recreate 2>&1 | tail -1
fi

echo ""
separator
echo ""

# ---- 4. 等待健康检查 ----
info "等待服务健康检查..."
max_wait=90
waited=0
interval=2

while [[ $waited -lt $max_wait ]]; do
    all_healthy=true

    if [[ -n "$TARGET_SERVICE" ]]; then
        if ! is_service_running "$TARGET_SERVICE"; then
            all_healthy=false
        fi
    else
        while IFS= read -r service; do
            if ! is_service_running "$service"; then
                all_healthy=false
                break
            fi
        done < <(get_services)
    fi

    if $all_healthy; then
        break
    fi

    sleep $interval
    waited=$((waited + interval))
    echo -n "."
done
echo ""

if [[ $waited -ge $max_wait ]]; then
    warn "服务启动超时，请检查日志: ./scripts/logs.sh"
else
    success "所有服务已更新并正常运行"
fi

echo ""

# ---- 5. 清理旧镜像 ----
info "清理旧镜像..."
docker image prune -f 2>&1 | tail -1

echo ""
info "当前运行版本:"
compose_cmd images 2>/dev/null | while IFS= read -r line; do
    dim "  $line"
done

echo ""
success "🎉 升级完成！"
info "请检查服务状态: ./scripts/status.sh"
echo ""
