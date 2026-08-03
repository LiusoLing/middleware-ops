#!/usr/bin/env bash
# ============================================================
# status.sh — 服务状态总览
# ============================================================
# 输出格式化的服务状态信息，包括:
#   - 容器运行状态
#   - 网络状态
#   - 数据卷状态
#   - CPU / 内存使用
#
# 用法:
#   ./scripts/status.sh              # 全部服务总览
#   ./scripts/status.sh postgres     # 只看 PostgreSQL
#   ./scripts/status.sh redis        # 只看 Redis
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

load_env
check_docker 2>/dev/null || true

TARGET_SERVICE="${1:-}"
if [[ -n "$TARGET_SERVICE" ]]; then
    validate_service "$TARGET_SERVICE" || exit 1
fi

echo ""
echo -e "${COLOR_CYAN}${COLOR_BOLD}  ═══════════════════════════════════════${COLOR_RESET}"
if [[ -n "$TARGET_SERVICE" ]]; then
    echo -e "${COLOR_CYAN}${COLOR_BOLD}    Middleware Status — ${TARGET_SERVICE}${COLOR_RESET}"
else
    echo -e "${COLOR_CYAN}${COLOR_BOLD}    Middleware Status${COLOR_RESET}"
fi
echo -e "${COLOR_CYAN}${COLOR_BOLD}  ═══════════════════════════════════════${COLOR_RESET}"
echo ""

# ── 服务状态 ──
echo -e "${COLOR_BOLD}  Services${COLOR_RESET}"
echo ""

while IFS= read -r service; do
    [[ -n "$TARGET_SERVICE" && "$service" != "$TARGET_SERVICE" ]] && continue

    if is_service_running "$service" 2>/dev/null; then
        cid=$(compose_cmd ps -q "$service" 2>/dev/null)
        health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$cid" 2>/dev/null || echo "N/A")
        ports=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} → {{(index $conf 0).HostPort}} {{end}}' "$cid" 2>/dev/null || echo "N/A")
        image=$(docker inspect -f '{{.Config.Image}}' "$cid" 2>/dev/null || echo "N/A")
        created=$(docker inspect -f '{{.Created}}' "$cid" 2>/dev/null | cut -d'T' -f1 || echo "N/A")

        printf "  ${COLOR_GREEN}●${COLOR_RESET} ${COLOR_BOLD}%-18s${COLOR_RESET} ${COLOR_GREEN}%-10s${COLOR_RESET}\n" "$service" "Running"
        dim "       Image    $image"
        dim "       Ports    $ports"
        dim "       Health   $health"
        dim "       Created  $created"

        if [[ -n "$TARGET_SERVICE" ]]; then
            ip_addr=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cid" 2>/dev/null || echo "N/A")
            dim "       IP       $ip_addr"
            env_vars=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$cid" 2>/dev/null | grep -v 'PASSWORD\|PASS\|SECRET\|KEY' | head -8)
            if [[ -n "$env_vars" ]]; then
                dim "       Env"
                echo "$env_vars" | while IFS= read -r ev; do
                    [[ -n "$ev" ]] && dim "         $ev"
                done
            fi
        fi
    else
        printf "  ${COLOR_RED}○${COLOR_RESET} ${COLOR_BOLD}%-18s${COLOR_RESET} ${COLOR_RED}%-10s${COLOR_RESET}\n" "$service" "Stopped"
    fi
    echo ""
done < <(get_services 2>/dev/null || true)

# ── 全量模式：网络 & 数据卷 ──
if [[ -z "$TARGET_SERVICE" ]]; then
    echo -e "${COLOR_BOLD}  Network${COLOR_RESET}"
    echo ""

    net="docker-network"
    if docker network inspect "$net" &>/dev/null; then
        subnet=$(docker network inspect "$net" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "N/A")
        printf "  ${COLOR_GREEN}●${COLOR_RESET} ${COLOR_BOLD}%-22s${COLOR_RESET} ${COLOR_GREEN}Active${COLOR_RESET}\n" "$net"
        dim "       Subnet   $subnet"
    else
        printf "  ${COLOR_RED}○${COLOR_RESET} ${COLOR_BOLD}%-22s${COLOR_RESET} ${COLOR_RED}Not Found${COLOR_RESET}\n" "$net"
    fi

    echo ""
    echo -e "${COLOR_BOLD}  Volumes${COLOR_RESET}"
    echo ""

    while IFS= read -r vol; do
        if docker volume inspect "$vol" &>/dev/null; then
            mp=$(docker volume inspect "$vol" -f '{{.Mountpoint}}' 2>/dev/null || echo "N/A")
            vs=$(du -sh "$mp" 2>/dev/null | cut -f1 || echo "N/A")
            printf "  ${COLOR_GREEN}●${COLOR_RESET} ${COLOR_BOLD}%-22s${COLOR_RESET} ${COLOR_GREEN}OK${COLOR_RESET}\n" "$vol"
            dim "       Size     $vs"
            dim "       Mount    $mp"
        else
            printf "  ${COLOR_YELLOW}○${COLOR_RESET} ${COLOR_BOLD}%-22s${COLOR_RESET} ${COLOR_YELLOW}Not Created${COLOR_RESET}\n" "$vol"
        fi
        echo ""
    done < <(compose_cmd config --volumes 2>/dev/null || true)
fi

# ── 资源使用 ──
echo -e "${COLOR_BOLD}  Resources${COLOR_RESET}"
echo ""

while IFS= read -r service; do
    [[ -n "$TARGET_SERVICE" && "$service" != "$TARGET_SERVICE" ]] && continue

    if is_service_running "$service" 2>/dev/null; then
        cid=$(compose_cmd ps -q "$service" 2>/dev/null)
        stats=$(docker stats --no-stream --format "CPU {{.CPUPerc}}  |  Mem {{.MemUsage}} ({{.MemPerc}})" "$cid" 2>/dev/null || echo "N/A")
        printf "  ${COLOR_BOLD}%-18s${COLOR_RESET}\n" "$service"
        dim "       $stats"
        echo ""
    fi
done < <(get_services 2>/dev/null || true)

# ── 连接信息 ──
echo -e "${COLOR_BOLD}  Connections${COLOR_RESET}"
echo ""

if { [[ -z "$TARGET_SERVICE" ]] || [[ "$TARGET_SERVICE" == "postgres" ]]; } && is_service_running "postgres" 2>/dev/null; then
    pg_host="${POSTGRES_HOST:-localhost}"
    pg_port="${POSTGRES_PORT:-5432}"
    pg_user="${POSTGRES_USER:-postgres}"
    printf "  ${COLOR_BOLD}%-18s${COLOR_RESET} postgresql://%s:****@%s:%s/${POSTGRES_DB:-postgres}\n" \
        "PostgreSQL" "$pg_user" "$pg_host" "$pg_port"
fi

if { [[ -z "$TARGET_SERVICE" ]] || [[ "$TARGET_SERVICE" == "redis" ]]; } && is_service_running "redis" 2>/dev/null; then
    redis_host="${REDIS_HOST:-localhost}"
    redis_port="${REDIS_PORT:-6379}"
    printf "  ${COLOR_BOLD}%-18s${COLOR_RESET} redis://:****@%s:%s/%s\n" \
        "Redis" "$redis_host" "$redis_port" "${REDIS_DB:-0}"
fi

if { [[ -z "$TARGET_SERVICE" ]] || [[ "$TARGET_SERVICE" == "sentinel" ]]; } && is_service_running "sentinel" 2>/dev/null; then
    sentinel_host="${SENTINEL_HOST:-localhost}"
    sentinel_port="${SENTINEL_PORT:-8858}"
    sentinel_user="${SENTINEL_USERNAME:-sentinel}"
    printf "  ${COLOR_BOLD}%-18s${COLOR_RESET} http://%s:%s  (user: %s)\n" \
        "Sentinel" "$sentinel_host" "$sentinel_port" "$sentinel_user"
fi

if { [[ -z "$TARGET_SERVICE" ]] || [[ "$TARGET_SERVICE" == "nacos" ]]; } && is_service_running "nacos" 2>/dev/null; then
    nacos_host="${NACOS_HOST:-localhost}"
    nacos_port="${NACOS_HTTP_PORT:-8080}"
    printf "  ${COLOR_BOLD}%-18s${COLOR_RESET} http://%s:%s/nacos  (auth: nacos/nacos)\n" \
        "Nacos" "$nacos_host" "$nacos_port"
fi

if { [[ -z "$TARGET_SERVICE" ]] || [[ "$TARGET_SERVICE" == "dokuwiki" ]]; } && is_service_running "dokuwiki" 2>/dev/null; then
    dw_host="${DOKUWIKI_HOST:-localhost}"
    dw_port="${DOKUWIKI_PORT:-8088}"
    printf "  ${COLOR_BOLD}%-18s${COLOR_RESET} http://%s:%s\n" \
        "DokuWiki" "$dw_host" "$dw_port"
fi

echo ""
