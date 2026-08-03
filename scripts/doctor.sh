#!/usr/bin/env bash
# ============================================================
# doctor.sh — 环境自检
# ============================================================
# 全面检查运行环境，发现问题直接报告
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

header "🩺  Middleware Doctor — 环境自检"
echo ""

ISSUES=0
WARNINGS=0
CHECKS=0

check_pass() {
    CHECKS=$((CHECKS + 1))
    printf "  ${COLOR_GREEN}✔${COLOR_RESET}  %s\n" "$1"
}

check_fail() {
    CHECKS=$((CHECKS + 1))
    ISSUES=$((ISSUES + 1))
    printf "  ${COLOR_RED}✘${COLOR_RESET}  %s\n" "$1"
    [[ -n "${2:-}" ]] && dim "      → $2"
}

check_warn() {
    CHECKS=$((CHECKS + 1))
    WARNINGS=$((WARNINGS + 1))
    printf "  ${COLOR_YELLOW}⚠${COLOR_RESET}  %s\n" "$1"
    [[ -n "${2:-}" ]] && dim "      → $2"
}

# ============================================================
# 1. Docker 环境
# ============================================================
echo -e "${COLOR_BOLD}  1. Docker Environment${COLOR_RESET}"
echo ""

if command -v docker &> /dev/null; then
    check_pass "Docker CLI     $(docker --version 2>/dev/null | head -1)"

    if docker info &> /dev/null; then
        check_pass "Docker Daemon  running"
        sd=$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
        if [[ "$sd" == "overlay2" ]]; then
            check_pass "Storage Driver $sd"
        else
            check_warn "Storage Driver $sd (推荐 overlay2)"
        fi
    else
        check_fail "Docker Daemon  未运行" "请启动 Docker Desktop 或 dockerd"
    fi

    if docker compose version &> /dev/null; then
        check_pass "Compose        $(docker compose version 2>/dev/null | head -1)"
    elif command -v docker-compose &> /dev/null; then
        check_warn "Compose        $(docker-compose --version 2>/dev/null | head -1) (建议使用 docker compose 插件)"
    else
        check_fail "Compose        未安装"
    fi
else
    check_fail "Docker CLI     未安装" "https://www.docker.com/products/docker-desktop"
fi

echo ""

# ============================================================
# 2. 配置文件
# ============================================================
echo -e "${COLOR_BOLD}  2. Configuration${COLOR_RESET}"
echo ""

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    check_pass ".env           已存在"
    load_env 2>/dev/null || true
    if [[ "${POSTGRES_PASSWORD:-}" == "change_me_postgres" ]] || [[ "${POSTGRES_PASSWORD:-}" == "change_you_password" ]]; then
        check_warn "PG 密码        仍为默认值，请修改 .env"
    fi
    if [[ "${REDIS_PASSWORD:-}" == "change_me_redis" ]] || [[ "${REDIS_PASSWORD:-}" == "change_you_password" ]]; then
        check_warn "Redis 密码     仍为默认值，请修改 .env"
    fi
else
    check_fail ".env           不存在" "请执行: cp .env.example .env"
fi

[[ -f "${PROJECT_ROOT}/docker-compose.yml" ]] \
    && check_pass "compose.yml    存在" \
    || check_fail "compose.yml    不存在"

[[ -f "${PROJECT_ROOT}/postgres/conf/conf.d/custom.conf" ]] \
    && check_pass "custom.conf    存在" \
    || check_warn "custom.conf    不存在（将使用 PostgreSQL 默认配置）"

echo ""

# ============================================================
# 3. 端口
# ============================================================
echo -e "${COLOR_BOLD}  3. Ports${COLOR_RESET}"
echo ""

check_port() {
    local p="$1" label="$2" pid pname
    if command -v lsof &> /dev/null; then
        pid=$(lsof -ti:"$p" 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            if [[ "$pname" == *"docker"* ]] || [[ "$pname" == "com.docker"* ]]; then
                check_pass ":$p ($label)    已由 Docker 占用"
            else
                check_warn ":$p ($label)    被 $pname (PID $pid) 占用"
            fi
        else
            check_pass ":$p ($label)    可用"
        fi
    elif command -v ss &> /dev/null; then
        if ss -tlnp | grep -q ":$p "; then
            check_warn ":$p ($label)    已被占用"
        else
            check_pass ":$p ($label)    可用"
        fi
    else
        dim "    端口检查需要 lsof 或 ss 命令"
    fi
}

check_port "${POSTGRES_PORT:-5432}" "PostgreSQL"
check_port "${REDIS_PORT:-6379}" "Redis"
check_port "${SENTINEL_PORT:-8858}" "Sentinel"
check_port "${NACOS_HTTP_PORT:-8080}" "Nacos HTTP"
check_port "${DOKUWIKI_PORT:-8088}" "DokuWiki"

echo ""

# ============================================================
# 4. 目录与权限
# ============================================================
echo -e "${COLOR_BOLD}  4. Directories${COLOR_RESET}"
echo ""

check_dir() {
    local d="$1" label="$2"
    if [[ -d "$d" ]]; then
        if [[ -r "$d" ]]; then
            check_pass "$label"
        else
            check_fail "$label  (不可读)" "chmod 755 $d"
        fi
    else
        check_fail "$label  (不存在)" "mkdir -p $d"
    fi
}

check_dir "${PROJECT_ROOT}/postgres/data"  "postgres/data"
check_dir "${PROJECT_ROOT}/redis/data"     "redis/data"
check_dir "${PROJECT_ROOT}/sentinel/conf"  "sentinel/conf"
check_dir "${PROJECT_ROOT}/nacos/conf"     "nacos/conf"
check_dir "${PROJECT_ROOT}/dokuwiki/data"  "dokuwiki/data"
check_dir "${PROJECT_ROOT}/backups"        "backups"
check_dir "${PROJECT_ROOT}/logs"           "logs"

echo ""

# ============================================================
# 5. 系统资源
# ============================================================
echo -e "${COLOR_BOLD}  5. System Resources${COLOR_RESET}"
echo ""

# 磁盘
disk_line=$(df -h "$PROJECT_ROOT" 2>/dev/null | tail -1)
if [[ -n "$disk_line" ]]; then
    disk_info=$(echo "$disk_line" | awk '{print $5 " used, " $4 " avail"}')
    used_pct=$(df "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ "$used_pct" -gt 90 ]]; then
        check_warn "Disk           $disk_info ⚠"
    else
        check_pass "Disk           $disk_info"
    fi
else
    dim "    无法检查磁盘空间"
fi

# inode
if command -v df &> /dev/null; then
    inode_line=$(df -i "$PROJECT_ROOT" 2>/dev/null | tail -1)
    if [[ -n "$inode_line" ]]; then
        inode_info=$(echo "$inode_line" | awk '{print $5 " used, " $4 " avail"}')
        inode_pct=$(echo "$inode_line" | awk '{print $5}' | sed 's/%//')
        if [[ "$inode_pct" -gt 90 ]]; then
            check_warn "Inode          $inode_info ⚠"
        else
            check_pass "Inode          $inode_info"
        fi
    fi
fi

# 内存
if [[ "$(uname)" == "Darwin" ]]; then
    total_mem=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024/1024}')
    [[ -n "$total_mem" ]] && check_pass "Memory         $total_mem total"
elif command -v free &> /dev/null; then
    total_mem=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    avail_mem=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')
    avail_kb=$(free 2>/dev/null | awk '/^Mem:/ {print $7}')
    if [[ -n "$total_mem" ]]; then
        if [[ "${avail_kb:-0}" -lt 524288 ]]; then  # < 512 MB
            check_warn "Memory         $total_mem total, $avail_mem avail (偏低)"
        else
            check_pass "Memory         $total_mem total, $avail_mem avail"
        fi
    fi
fi

# swap
if [[ "$(uname)" == "Linux" ]] && command -v free &> /dev/null; then
    swap_total=$(free 2>/dev/null | awk '/^Swap:/ {print $2}')
    if [[ "$swap_total" != "0" ]] && [[ -n "$swap_total" ]]; then
        check_pass "Swap           已配置"
    else
        check_warn "Swap           未配置（生产环境建议启用）"
    fi
fi

echo ""

# ============================================================
# 6. Docker 资源
# ============================================================
echo -e "${COLOR_BOLD}  6. Docker Usage${COLOR_RESET}"
echo ""

if docker info &> /dev/null; then
    docker system df 2>/dev/null | head -5 | while IFS= read -r line; do
        dim "     $line"
    done
fi

echo ""

# ============================================================
# 7. 系统信息
# ============================================================
echo -e "${COLOR_BOLD}  7. System${COLOR_RESET}"
echo ""

check_pass "OS             $(uname -s) $(uname -r) ($(uname -m))"
command -v bash &> /dev/null && check_pass "Shell          $(bash --version 2>/dev/null | head -1)"

echo ""

# ============================================================
# 总结
# ============================================================
separator
echo ""

passed=$((CHECKS - ISSUES - WARNINGS))
printf "  %-12s ${COLOR_BOLD}%d${COLOR_RESET}\n" "Total checks" "$CHECKS"
printf "  %-12s ${COLOR_GREEN}%d${COLOR_RESET}\n" "Passed" "$passed"
[[ $WARNINGS -gt 0 ]] && printf "  %-12s ${COLOR_YELLOW}%d${COLOR_RESET}\n" "Warnings" "$WARNINGS"
[[ $ISSUES -gt 0 ]]   && printf "  %-12s ${COLOR_RED}%d${COLOR_RESET}\n" "Issues" "$ISSUES"

echo ""

if [[ $ISSUES -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    success "Everything is OK!"
elif [[ $ISSUES -eq 0 ]]; then
    warn "发现 $WARNINGS 个警告，建议处理后再启动服务"
else
    error "发现 $ISSUES 个问题，请修复后再启动服务"
fi

echo ""
