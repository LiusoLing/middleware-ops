#!/usr/bin/env bash
# ============================================================
# stop.sh — 停止服务
# ============================================================
# 用法:
#   ./scripts/stop.sh              # 停止全部服务
#   ./scripts/stop.sh postgres     # 只停止 PostgreSQL
#   ./scripts/stop.sh redis        # 只停止 Redis
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
    header "🛑 停止 ${TARGET_SERVICE}"
else
    header "🛑 停止 Middleware 全部服务"
fi

# 列出运行中的服务
running_services=""
while IFS= read -r service; do
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$service" != "$TARGET_SERVICE" ]]; then
        continue
    fi
    if is_service_running "$service"; then
        running_services="$running_services $service"
    fi
done < <(get_services)

if [[ -z "$running_services" ]]; then
    warn "没有正在运行的服务"
    exit 0
fi

info "正在停止:${running_services}"

if [[ -n "$TARGET_SERVICE" ]]; then
    compose_cmd stop "$TARGET_SERVICE"
else
    compose_cmd down --remove-orphans
fi

echo ""

# 确认已停止
sleep 2
still_running=""
while IFS= read -r service; do
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$service" != "$TARGET_SERVICE" ]]; then
        continue
    fi
    if is_service_running "$service"; then
        still_running="$still_running $service"
    fi
done < <(get_services)

if [[ -n "$still_running" ]]; then
    warn "以下服务仍在运行:${still_running}"
    warn "尝试强制停止..."
    for svc in $still_running; do
        compose_cmd rm -sf "$svc" 2>/dev/null
    done
fi

success "服务已停止"
