#!/usr/bin/env bash
# ============================================================
# common.sh — 公共函数库
# ============================================================
# 所有管理脚本 source 此文件以获取通用功能
# ============================================================

set -o pipefail

# ============================================================
# 颜色定义
# ============================================================
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_DIM='\033[2m'

# ============================================================
# 项目根目录（脚本在 scripts/ 下，dirname 两次得到根目录）
# ============================================================
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================================================
# 输出函数
# ============================================================
info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}  $*"; }
success() { echo -e "${COLOR_GREEN}[✔]${COLOR_RESET}    $*"; }
warn()    { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}  $*"; }
error()   { echo -e "${COLOR_RED}[✘]${COLOR_RESET}    $*" >&2; }
header()  { echo -e "\n${COLOR_CYAN}${COLOR_BOLD}$*${COLOR_RESET}\n"; }
dim()     { echo -e "${COLOR_DIM}$*${COLOR_RESET}"; }

# 输出分隔线
separator() {
    echo -e "${COLOR_DIM}$(printf '━%.0s' {1..50})${COLOR_RESET}"
}

# ============================================================
# 环境变量加载
# ============================================================
load_env() {
    local env_file="${PROJECT_ROOT}/.env"
    if [[ ! -f "$env_file" ]]; then
        error ".env 文件不存在，请先执行: cp .env.example .env"
        return 1
    fi
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
}

# ============================================================
# Docker 检查
# ============================================================
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker"
        return 1
    fi

    if ! docker info &> /dev/null; then
        error "Docker 未运行，请先启动 Docker"
        return 1
    fi

    # 检测 compose 命令
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        error "Docker Compose 未安装"
        return 1
    fi
    readonly COMPOSE_CMD
}

# ============================================================
# Compose 命令包装
# ============================================================
compose_cmd() {
    if [[ -z "${COMPOSE_CMD:-}" ]]; then
        check_docker || return 1
    fi
    cd "$PROJECT_ROOT" && $COMPOSE_CMD "$@"
}

# ============================================================
# 服务列表
# ============================================================
get_services() {
    compose_cmd config --services 2>/dev/null
}

# ============================================================
# 检查服务是否运行
# ============================================================
is_service_running() {
    local service="$1"
    local container_id
    container_id=$(compose_cmd ps -q "$service" 2>/dev/null)
    if [[ -z "$container_id" ]]; then
        return 1
    fi
    local status
    status=$(docker inspect -f '{{.State.Status}}' "$container_id" 2>/dev/null)
    [[ "$status" == "running" ]]
}

# ============================================================
# 获取容器资源使用
# ============================================================
get_container_stats() {
    local service="$1"
    local container_id
    container_id=$(compose_cmd ps -q "$service" 2>/dev/null)
    if [[ -z "$container_id" ]]; then
        echo "N/A"
        return
    fi
    docker stats --no-stream --format "CPU {{.CPUPerc}} | MEM {{.MemUsage}} | NET {{.NetIO}}" "$container_id" 2>/dev/null || echo "N/A"
}

# ============================================================
# 校验服务名是否在 compose 配置中
# 用法: validate_service "postgres"  → 有效返回 0，无效返回 1 并报错
# ============================================================
validate_service() {
    local target="$1"
    if [[ -z "$target" ]]; then
        return 0  # 空表示操作全部服务，合法
    fi
    while IFS= read -r svc; do
        if [[ "$svc" == "$target" ]]; then
            return 0
        fi
    done < <(get_services 2>/dev/null)
    error "未知服务: $target"
    info "可用服务: $(get_services 2>/dev/null | tr '\n' ' ')"
    return 1
}

# ============================================================
# 确认操作
# ============================================================
confirm() {
    local prompt="${1:-确认执行此操作?}"
    echo -e "${COLOR_YELLOW}${prompt} (y/N)${COLOR_RESET}"
    read -r answer
    case "$answer" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}
