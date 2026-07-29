#!/usr/bin/env bash
# ============================================================
# start.sh — 启动服务
# ============================================================
# 用法:
#   ./scripts/start.sh              # 启动全部服务
#   ./scripts/start.sh postgres     # 只启动 PostgreSQL
#   ./scripts/start.sh redis        # 只启动 Redis
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

load_env
check_docker

# 参数解析
TARGET_SERVICE="${1:-}"

if [[ -n "$TARGET_SERVICE" ]]; then
    validate_service "$TARGET_SERVICE" || exit 1
    header "🚀 启动 ${TARGET_SERVICE}"
else
    header "🚀 启动 Middleware 全部服务"
fi

# 检查是否有正在运行的服务
has_running=false
while IFS= read -r service; do
    if is_service_running "$service"; then
        if [[ -z "$TARGET_SERVICE" ]] || [[ "$service" == "$TARGET_SERVICE" ]]; then
            warn "服务 $service 已在运行中"
            has_running=true
        fi
    fi
done < <(get_services)

if $has_running; then
    info "部分服务已在运行，将重新创建已更改的容器"
fi

# 启动服务
if [[ -n "$TARGET_SERVICE" ]]; then
    info "正在启动 ${TARGET_SERVICE}..."
    compose_cmd up -d --remove-orphans "$TARGET_SERVICE"
else
    info "正在启动所有服务..."
    compose_cmd up -d --remove-orphans
fi

echo ""
separator
echo ""

# 等待健康检查
info "等待服务健康检查..."
max_wait=60
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

# 最终状态检查
if [[ $waited -ge $max_wait ]]; then
    warn "服务启动超时，请检查日志: ./scripts/logs.sh${TARGET_SERVICE:+ $TARGET_SERVICE}"
else
    success "服务已启动并在运行中"
fi

echo ""
info "服务状态总览:"
if [[ -n "$TARGET_SERVICE" ]]; then
    "${SCRIPT_DIR}/status.sh" "$TARGET_SERVICE"
else
    "${SCRIPT_DIR}/status.sh"
fi
