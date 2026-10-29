#!/usr/bin/env bash
# ============================================================
# common.sh — 公共函数库
# ============================================================
# 所有管理脚本 source 此文件以获取通用功能
# ============================================================

set -o pipefail

# ── 颜色 ──
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_DIM='\033[2m'

# ── 项目根目录 ──
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 输出函数（等宽前缀，message 始终对齐在同一列） ──
# [INFO]  [ OK ]  [WARN]  [FAIL]  都是 6 字符，后缀 2 空格 → 消息从第 9 列开始
info()    { printf "${COLOR_BLUE}[INFO]${COLOR_RESET}  %s\n" "$*"; }
success() { printf "${COLOR_GREEN}[ OK ]${COLOR_RESET}  %s\n" "$*"; }
warn()    { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET}  %s\n" "$*"; }
error()   { printf "${COLOR_RED}[FAIL]${COLOR_RESET}  %s\n" "$*" >&2; }

# 标题行
header() {
    echo ""
    printf "${COLOR_CYAN}${COLOR_BOLD}── %s${COLOR_RESET}\n" "$*"
    echo ""
}

# 次级信息（调用方自行控制缩进）
dim() { printf "${COLOR_DIM}%s${COLOR_RESET}\n" "$*"; }

# 分隔线
separator() {
    printf "${COLOR_DIM}%s${COLOR_RESET}\n" "$(printf '─%.0s' {1..52})"
}

# ── 环境变量加载 ──
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

# ── Docker 检查 ──
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker"
        return 1
    fi
    if ! docker info &> /dev/null; then
        error "Docker 未运行，请先启动 Docker"
        return 1
    fi
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

# ── Compose 命令包装 ──
compose_cmd() {
    if [[ -z "${COMPOSE_CMD:-}" ]]; then
        check_docker || return 1
    fi
    cd "$PROJECT_ROOT" && $COMPOSE_CMD "$@"
}

# ── 服务列表 ──
get_services() {
    compose_cmd config --services 2>/dev/null
}

# ── 确保本地镜像存在（只拉取缺失镜像）──
ensure_images() {
    local output image
    local images=()
    local present=()
    local missing=()

    output=$(compose_cmd config --images 2>/dev/null | sort -u || true)

    # 旧版 Compose 不支持 config --images 时回退
    if [[ -z "$output" ]]; then
        output=$(compose_cmd config 2>/dev/null \
            | awk '/^[[:space:]]+image:/ {print $2}' \
            | sort -u || true)
    fi

    while IFS= read -r image; do
        [[ -n "$image" ]] && images+=("$image")
    done <<< "$output"

    if [[ ${#images[@]} -eq 0 ]]; then
        warn "未获取到镜像清单，跳过镜像检查"
        return 0
    fi

    for image in "${images[@]}"; do
        if docker image inspect "$image" >/dev/null 2>&1; then
            present+=("$image")
        else
            missing+=("$image")
        fi
    done

    if [[ ${#present[@]} -gt 0 ]]; then
        info "本地已存在镜像，跳过拉取:"
        for image in "${present[@]}"; do
            dim "       $image"
        done
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        success "所有镜像已存在，无需拉取"
        return 0
    fi

    info "拉取缺失镜像:"
    for image in "${missing[@]}"; do
        dim "       $image"
    done

    for image in "${missing[@]}"; do
        if ! docker pull "$image"; then
            error "镜像拉取失败: $image"
            return 1
        fi
    done

    success "缺失镜像拉取完成"
}

# ── 判断 Compose 是否支持 up --pull never ──
compose_supports_pull_never() {
    local help_text
    help_text=$(compose_cmd up --help 2>&1 || true)
    [[ "$help_text" == *"--pull"* && "$help_text" == *"never"* ]]
}

# ── 检查服务是否运行 ──
is_service_running() {
    local service="$1" container_id status
    container_id=$(compose_cmd ps -q "$service" 2>/dev/null)
    [[ -z "$container_id" ]] && return 1
    status=$(docker inspect -f '{{.State.Status}}' "$container_id" 2>/dev/null)
    [[ "$status" == "running" ]]
}

# ── 获取容器资源 ──
get_container_stats() {
    local service="$1" container_id
    container_id=$(compose_cmd ps -q "$service" 2>/dev/null)
    [[ -z "$container_id" ]] && { echo "N/A"; return; }
    docker stats --no-stream --format "CPU {{.CPUPerc}} | MEM {{.MemUsage}} | NET {{.NetIO}}" "$container_id" 2>/dev/null || echo "N/A"
}

# ── 校验服务名 ──
validate_service() {
    local target="$1"
    [[ -z "$target" ]] && return 0
    while IFS= read -r svc; do
        [[ "$svc" == "$target" ]] && return 0
    done < <(get_services 2>/dev/null)
    error "未知服务: $target"
    info "可用: $(get_services 2>/dev/null | tr '\n' ' ')"
    return 1
}

# ── 确认操作 ──
confirm() {
    local prompt="${1:-确认执行此操作?}"
    printf "${COLOR_YELLOW}%s (y/N) ${COLOR_RESET}" "$prompt"
    read -r answer
    case "$answer" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}
