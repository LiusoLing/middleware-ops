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
echo -e "${COLOR_CYAN}${COLOR_BOLD}====================================${COLOR_RESET}"
if [[ -n "$TARGET_SERVICE" ]]; then
    echo -e "${COLOR_CYAN}${COLOR_BOLD}  Middleware Status — ${TARGET_SERVICE}${COLOR_RESET}"
else
    echo -e "${COLOR_CYAN}${COLOR_BOLD}  Middleware Status${COLOR_RESET}"
fi
echo -e "${COLOR_CYAN}${COLOR_BOLD}====================================${COLOR_RESET}"
echo ""

# ---- 服务状态 ----
echo -e "${COLOR_BOLD}Services${COLOR_RESET}"
echo ""

while IFS= read -r service; do
    # 如果指定了目标服务，只显示该服务
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$service" != "$TARGET_SERVICE" ]]; then
        continue
    fi

    if is_service_running "$service" 2>/dev/null; then
        local container_id
        container_id=$(compose_cmd ps -q "$service" 2>/dev/null)
        local health
        health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$container_id" 2>/dev/null || echo "N/A")
        local ports
        ports=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}' "$container_id" 2>/dev/null || echo "N/A")
        local image
        image=$(docker inspect -f '{{.Config.Image}}' "$container_id" 2>/dev/null || echo "N/A")
        local created
        created=$(docker inspect -f '{{.Created}}' "$container_id" 2>/dev/null | cut -d'T' -f1 || echo "N/A")

        printf "  ${COLOR_GREEN}●${COLOR_RESET} ${COLOR_BOLD}%-16s${COLOR_RESET} ${COLOR_GREEN}Running${COLOR_RESET}\n" "$service"
        dim "     Image:    $image"
        dim "     Ports:    $ports"
        dim "     Health:   $health"
        dim "     Created:  $created"

        # 单服务模式显示更多详情
        if [[ -n "$TARGET_SERVICE" ]]; then
            local ip_addr
            ip_addr=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_id" 2>/dev/null || echo "N/A")
            dim "     IP:       $ip_addr"
            local env_vars
            env_vars=$(docker inspect -f '{{range .Config.Env}}{{.}} {{end}}' "$container_id" 2>/dev/null | tr ' ' '\n' | grep -v 'PASSWORD\|PASS\|SECRET\|KEY' | head -10 || echo "N/A")
            if [[ "$env_vars" != "N/A" ]]; then
                dim "     Env:"
                echo "$env_vars" | while IFS= read -r env_line; do
                    [[ -n "$env_line" ]] && dim "       $env_line"
                done
            fi
        fi
    else
        printf "  ${COLOR_RED}○${COLOR_RESET} ${COLOR_BOLD}%-16s${COLOR_RESET} ${COLOR_RED}Stopped${COLOR_RESET}\n" "$service"
    fi
    echo ""
done < <(get_services 2>/dev/null || true)

# 全量模式显示更多信息
if [[ -z "$TARGET_SERVICE" ]]; then
    # ---- 网络 ----
    echo -e "${COLOR_BOLD}Network${COLOR_RESET}"
    echo ""

    local network_name="docker-network"
    if docker network inspect "$network_name" &>/dev/null; then
        printf "  ${COLOR_GREEN}●${COLOR_RESET} ${COLOR_BOLD}%-20s${COLOR_RESET} ${COLOR_GREEN}Active${COLOR_RESET}\n" "$network_name"
        local subnet
        subnet=$(docker network inspect "$network_name" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "N/A")
        dim "     Subnet:   $subnet"
    else
        printf "  ${COLOR_RED}○${COLOR_RESET} ${COLOR_BOLD}%-20s${COLOR_RESET} ${COLOR_RED}Not Found${COLOR_RESET}\n" "$network_name"
    fi

    echo ""

    # ---- 数据卷 ----
    echo -e "${COLOR_BOLD}Volumes${COLOR_RESET}"
    echo ""

    while IFS= read -r volume; do
        if docker volume inspect "$volume" &>/dev/null; then
            local mountpoint
            mountpoint=$(docker volume inspect "$volume" -f '{{.Mountpoint}}' 2>/dev/null || echo "N/A")
            local size
            if [[ -d "$mountpoint" ]]; then
                size=$(du -sh "$mountpoint" 2>/dev/null | cut -f1 || echo "N/A")
            else
                size="N/A"
            fi
            printf "  ${COLOR_GREEN}●${COLOR_RESET} ${COLOR_BOLD}%-20s${COLOR_RESET} ${COLOR_GREEN}OK${COLOR_RESET}\n" "$volume"
            dim "     Size:     $size"
            dim "     Mount:    $mountpoint"
        else
            printf "  ${COLOR_YELLOW}○${COLOR_RESET} ${COLOR_BOLD}%-20s${COLOR_RESET} ${COLOR_YELLOW}Not Created${COLOR_RESET}\n" "$volume"
        fi
        echo ""
    done < <(compose_cmd config --volumes 2>/dev/null || true)
fi

# ---- 资源使用 ----
echo -e "${COLOR_BOLD}Resource Usage${COLOR_RESET}"
echo ""

while IFS= read -r service; do
    if [[ -n "$TARGET_SERVICE" ]] && [[ "$service" != "$TARGET_SERVICE" ]]; then
        continue
    fi

    if is_service_running "$service" 2>/dev/null; then
        local container_id
        container_id=$(compose_cmd ps -q "$service" 2>/dev/null)
        local stats
        stats=$(docker stats --no-stream --format "CPU: {{.CPUPerc}} | Mem: {{.MemUsage}} ({{.MemPerc}})" "$container_id" 2>/dev/null || echo "N/A")
        printf "  ${COLOR_BOLD}%-16s${COLOR_RESET}\n" "$service"
        dim "     $stats"
        echo ""
    fi
done < <(get_services 2>/dev/null || true)

# ---- 连接信息 ----
echo -e "${COLOR_BOLD}Connection Info${COLOR_RESET}"
echo ""

if [[ -z "$TARGET_SERVICE" ]] || [[ "$TARGET_SERVICE" == "postgres" ]]; then
    if is_service_running "postgres" 2>/dev/null; then
        local pg_host="${POSTGRES_HOST:-localhost}"
        local pg_port="${POSTGRES_PORT:-5432}"
        local pg_user="${POSTGRES_USER:-postgres}"
        printf "  ${COLOR_BOLD}%-16s${COLOR_RESET} postgresql://%s:****@%s:%s/${POSTGRES_DB:-postgres}\n" \
            "PostgreSQL" "$pg_user" "$pg_host" "$pg_port"
    fi
fi

if [[ -z "$TARGET_SERVICE" ]] || [[ "$TARGET_SERVICE" == "redis" ]]; then
    if is_service_running "redis" 2>/dev/null; then
        local redis_host="${REDIS_HOST:-localhost}"
        local redis_port="${REDIS_PORT:-6379}"
        printf "  ${COLOR_BOLD}%-16s${COLOR_RESET} redis://:%s@%s:%s\n" \
            "Redis" "${REDIS_PASSWORD:0:4}****" "$redis_host" "$redis_port"
    fi
fi

echo ""

separator
echo ""
