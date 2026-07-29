#!/usr/bin/env bash
# ============================================================
# logs.sh — 查看服务日志
# ============================================================
# 用法:
#   ./scripts/logs.sh              # 查看所有服务日志
#   ./scripts/logs.sh postgres     # 查看 PostgreSQL 日志
#   ./scripts/logs.sh redis        # 查看 Redis 日志
#   ./scripts/logs.sh -f postgres  # 实时跟踪 PostgreSQL 日志
#   ./scripts/logs.sh --tail 100   # 查看最近 100 行
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

load_env
check_docker

# 解析参数
FOLLOW=""
TAIL="--tail=100"
SERVICE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--follow)
            FOLLOW="-f"
            shift
            ;;
        --tail)
            TAIL="--tail=$2"
            shift 2
            ;;
        *)
            SERVICE="$1"
            shift
            ;;
    esac
done

if [[ -n "$SERVICE" ]]; then
    header "📋 查看 ${SERVICE} 日志"
    compose_cmd logs ${FOLLOW} ${TAIL} "$SERVICE"
else
    header "📋 查看所有服务日志"
    compose_cmd logs ${FOLLOW} ${TAIL}
fi
