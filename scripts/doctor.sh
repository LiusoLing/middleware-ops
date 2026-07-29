#!/usr/bin/env bash
# ============================================================
# doctor.sh — 环境自检
# ============================================================
# 全面检查运行环境，发现问题直接报告
# 检查项:
#   - Docker / Docker Compose
#   - 配置文件完整性
#   - 端口占用
#   - 数据目录权限
#   - 磁盘空间 / inode
#   - 内存 / swap
#   - UID / GID
#   - 存储驱动 (overlay2)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

header "🩺 Middleware Doctor — 环境自检"
echo ""

# 问题计数器
ISSUES=0
WARNINGS=0
CHECKS=0

# 辅助函数
check_pass() {
    CHECKS=$((CHECKS + 1))
    printf "  ${COLOR_GREEN}✔${COLOR_RESET} %s\n" "$1"
}

check_fail() {
    CHECKS=$((CHECKS + 1))
    ISSUES=$((ISSUES + 1))
    printf "  ${COLOR_RED}✘${COLOR_RESET} %s\n" "$1"
    if [[ -n "${2:-}" ]]; then
        dim "    → $2"
    fi
}

check_warn() {
    CHECKS=$((CHECKS + 1))
    WARNINGS=$((WARNINGS + 1))
    printf "  ${COLOR_YELLOW}⚠${COLOR_RESET} %s\n" "$1"
    if [[ -n "${2:-}" ]]; then
        dim "    → $2"
    fi
}

# ============================================================
# 1. Docker 环境
# ============================================================
echo -e "${COLOR_BOLD}1. Docker Environment${COLOR_RESET}"
echo ""

if command -v docker &> /dev/null; then
    docker_version
    docker_version=$(docker --version 2>/dev/null | head -1)
    check_pass "Docker CLI: $docker_version"

    if docker info &> /dev/null; then
        check_pass "Docker Daemon: running"

        # 检查存储驱动
        storage_driver
        storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
        if [[ "$storage_driver" == "overlay2" ]]; then
            check_pass "Storage Driver: $storage_driver"
        else
            check_warn "Storage Driver: $storage_driver (推荐 overlay2)"
        fi
    else
        check_fail "Docker Daemon: 未运行" "请启动 Docker Desktop 或 dockerd"
    fi

    # Docker Compose
    if docker compose version &> /dev/null; then
        compose_version
        compose_version=$(docker compose version 2>/dev/null | head -1)
        check_pass "Docker Compose: $compose_version"
    elif command -v docker-compose &> /dev/null; then
        compose_version
        compose_version=$(docker-compose --version 2>/dev/null | head -1)
        check_warn "Docker Compose (legacy): $compose_version (建议使用 docker compose)"
    else
        check_fail "Docker Compose: 未安装"
    fi
else
    check_fail "Docker CLI: 未安装" "请安装 Docker Desktop: https://www.docker.com/products/docker-desktop"
fi

echo ""

# ============================================================
# 2. 配置文件
# ============================================================
echo -e "${COLOR_BOLD}2. Configuration Files${COLOR_RESET}"
echo ""

# .env
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    check_pass ".env: 存在"

    # 检查是否改了默认密码
    load_env 2>/dev/null || true
    if [[ "${POSTGRES_PASSWORD:-}" == "change_me_postgres" ]]; then
        check_warn "POSTGRES_PASSWORD: 仍为默认值，请修改"
    fi
    if [[ "${REDIS_PASSWORD:-}" == "change_me_redis" ]]; then
        check_warn "REDIS_PASSWORD: 仍为默认值，请修改"
    fi
else
    check_fail ".env: 不存在" "请执行: cp .env.example .env"
fi

# docker-compose.yml
if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
    check_pass "docker-compose.yml: 存在"
else
    check_fail "docker-compose.yml: 不存在" "请检查项目文件完整性"
fi

# postgresql.conf
if [[ -f "${PROJECT_ROOT}/postgres/conf/postgresql.conf" ]]; then
    check_pass "postgresql.conf: 存在"
else
    check_warn "postgresql.conf: 不存在（将使用 PostgreSQL 默认配置）"
fi

echo ""

# ============================================================
# 3. 端口检查
# ============================================================
echo -e "${COLOR_BOLD}3. Port Availability${COLOR_RESET}"
echo ""

check_port() {
    port="$1"
    service="$2"
    if command -v lsof &> /dev/null; then
        pid
        pid=$(lsof -ti:"$port" 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            process_name
            process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            # 如果是 docker-proxy 则认为是正常的
            if [[ "$process_name" == *"docker"* ]] || [[ "$process_name" == "com.docker"* ]]; then
                check_pass "端口 $port ($service): 已被 Docker 容器使用"
            else
                check_warn "端口 $port ($service): 被进程 $process_name (PID $pid) 占用"
            fi
        else
            check_pass "端口 $port ($service): 可用"
        fi
    elif command -v ss &> /dev/null; then
        if ss -tlnp | grep -q ":$port "; then
            check_warn "端口 $port ($service): 已被占用"
        else
            check_pass "端口 $port ($service): 可用"
        fi
    else
        dim "  端口检查需要 lsof 或 ss 命令"
    fi
}

check_port "${POSTGRES_PORT:-5432}" "PostgreSQL"
check_port "${REDIS_PORT:-6379}" "Redis"

echo ""

# ============================================================
# 4. 目录与权限
# ============================================================
echo -e "${COLOR_BOLD}4. Directories & Permissions${COLOR_RESET}"
echo ""

check_dir() {
    dir="$1"
    label="$2"
    if [[ -d "$dir" ]]; then
        if [[ -r "$dir" ]]; then
            check_pass "$label: 存在且可读"
        else
            check_fail "$label: 存在但不可读" "请检查目录权限: chmod 755 $dir"
        fi
    else
        check_fail "$label: 不存在" "请执行: mkdir -p $dir"
    fi
}

check_dir "${PROJECT_ROOT}/postgres/data" "postgres/data"
check_dir "${PROJECT_ROOT}/redis/data" "redis/data"
check_dir "${PROJECT_ROOT}/backups" "backups"
check_dir "${PROJECT_ROOT}/logs" "logs"

echo ""

# ============================================================
# 5. 系统资源
# ============================================================
echo -e "${COLOR_BOLD}5. System Resources${COLOR_RESET}"
echo ""

# 磁盘空间
disk_usage
disk_usage=$(df -h "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $5 " used, " $4 " available"}')
if [[ -n "$disk_usage" ]]; then
    used_pct
    used_pct=$(df "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ "$used_pct" -gt 90 ]]; then
        check_warn "磁盘空间: $disk_usage (空间不足！)"
    else
        check_pass "磁盘空间: $disk_usage"
    fi
else
    dim "  无法检查磁盘空间"
fi

# inode
if command -v df &> /dev/null; then
    inode_usage
    inode_usage=$(df -i "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $5 " used, " $4 " available"}')
    if [[ -n "$inode_usage" ]]; then
        inode_pct
        inode_pct=$(df -i "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
        if [[ "$inode_pct" -gt 90 ]]; then
            check_warn "inode: $inode_usage (inode 不足！)"
        else
            check_pass "inode: $inode_usage"
        fi
    fi
fi

# 内存
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    total_mem
    total_mem=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024/1024}')
    free_mem
    free_mem=$(vm_stat 2>/dev/null | awk '/Pages free/ {free=$3} /Pages inactive/ {inactive=$3} END {printf "%.1f GB", (free+inactive)*4096/1024/1024/1024}')
    if [[ -n "$total_mem" ]]; then
        check_pass "内存: 总共 $total_mem"
    fi
elif command -v free &> /dev/null; then
    # Linux
    total_mem
    total_mem=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    avail_mem
    avail_mem=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')
    if [[ -n "$total_mem" ]]; then
        avail_mem_bytes
        avail_mem_bytes=$(free 2>/dev/null | awk '/^Mem:/ {print $7}')
        min_mem=$((512 * 1024))  # 512MB in KB
        if [[ "$avail_mem_bytes" -lt "$min_mem" ]]; then
            check_warn "内存: $total_mem 总共, $avail_mem 可用 (可用内存偏少)"
        else
            check_pass "内存: $total_mem 总共, $avail_mem 可用"
        fi
    fi
fi

# 检查 swap（仅 Linux）
if [[ "$(uname)" == "Linux" ]] && command -v free &> /dev/null; then
    swap_total
    swap_total=$(free 2>/dev/null | awk '/^Swap:/ {print $2}')
    if [[ "$swap_total" != "0" ]] && [[ -n "$swap_total" ]]; then
        check_pass "Swap: 已配置"
    else
        check_warn "Swap: 未配置（生产环境建议配置 swap）"
    fi
fi

echo ""

# ============================================================
# 6. Docker 资源
# ============================================================
echo -e "${COLOR_BOLD}6. Docker Resources${COLOR_RESET}"
echo ""

# 检查 Docker 磁盘使用
if docker info &> /dev/null; then
    docker_disk
    docker_disk=$(docker system df 2>/dev/null | head -4 || true)
    if [[ -n "$docker_disk" ]]; then
        dim "$docker_disk"
    fi
fi

echo ""

# ============================================================
# 7. 系统信息
# ============================================================
echo -e "${COLOR_BOLD}7. System Info${COLOR_RESET}"
echo ""

check_pass "OS: $(uname -s) $(uname -r)"
check_pass "Architecture: $(uname -m)"

if command -v bash &> /dev/null; then
    bash_version
    bash_version=$(bash --version 2>/dev/null | head -1)
    check_pass "Shell: $bash_version"
fi

echo ""

# ============================================================
# 总结
# ============================================================
separator
echo ""

echo -e "检查总计: ${COLOR_BOLD}$CHECKS${COLOR_RESET} 项"
echo -e "通过:     ${COLOR_GREEN}$((CHECKS - ISSUES - WARNINGS))${COLOR_RESET} 项"

if [[ $WARNINGS -gt 0 ]]; then
    echo -e "警告:     ${COLOR_YELLOW}$WARNINGS${COLOR_RESET} 项"
fi

if [[ $ISSUES -gt 0 ]]; then
    echo -e "问题:     ${COLOR_RED}$ISSUES${COLOR_RESET} 项"
fi

echo ""

if [[ $ISSUES -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    success "🎉 Everything is OK!"
elif [[ $ISSUES -eq 0 ]]; then
    warn "发现 $WARNINGS 个警告，建议处理"
else
    error "发现 $ISSUES 个问题，请修复后再启动服务"
fi

echo ""
