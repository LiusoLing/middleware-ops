#!/usr/bin/env bash
# ============================================================
# restart.sh — 重启服务
# ============================================================
# 用法:
#   ./scripts/restart.sh              # 重启全部服务
#   ./scripts/restart.sh postgres     # 只重启 PostgreSQL
#   ./scripts/restart.sh redis        # 只重启 Redis
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
    header "🔄 重启 ${TARGET_SERVICE}"
else
    header "🔄 重启 Middleware 全部服务"
fi

# 停止前确保镜像齐全，避免拉取失败造成无谓停机
ensure_images || exit 1

# 停止
if [[ -n "$TARGET_SERVICE" ]]; then
    info "正在停止 ${TARGET_SERVICE}..."
    compose_cmd stop "$TARGET_SERVICE"
else
    info "正在停止所有服务..."
    compose_cmd down --remove-orphans
fi
success "服务已停止"

sleep 2

# 构造启动参数；支持的 Compose 版本禁止启动时再次拉取
up_args=(-d --remove-orphans)
if compose_supports_pull_never; then
    up_args+=(--pull never)
fi

# 启动
if [[ -n "$TARGET_SERVICE" ]]; then
    info "正在启动 ${TARGET_SERVICE}..."
    compose_cmd up "${up_args[@]}" "$TARGET_SERVICE"
else
    info "正在启动所有服务..."
    compose_cmd up "${up_args[@]}"
fi

echo ""
separator
echo ""

# 等待健康检查
info "等待服务就绪..."
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

if [[ $waited -ge $max_wait ]]; then
    warn "服务启动超时"
else
    success "服务已重启"
fi

echo ""
info "服务状态总览:"
if [[ -n "$TARGET_SERVICE" ]]; then
    "${SCRIPT_DIR}/status.sh" "$TARGET_SERVICE"
else
    "${SCRIPT_DIR}/status.sh"
fi
