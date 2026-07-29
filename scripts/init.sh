#!/usr/bin/env bash
# ============================================================
# init.sh — 环境初始化
# ============================================================
# 功能:
#   1. 检查 Docker 环境
#   2. 生成 .env 文件
#   3. 创建必要的目录
#   4. 拉取镜像
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

header "🔧 Middleware 环境初始化"

# ---- 1. 检查 .env 文件 ----
info "检查 .env 配置文件..."
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    warn ".env 文件不存在"
    if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
        info "从 .env.example 复制默认配置..."
        cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
        success ".env 文件已创建"
        warn "⚠️  请编辑 .env 文件修改默认密码！"
        echo ""
        dim "   vim ${PROJECT_ROOT}/.env"
        echo ""
    else
        error ".env.example 也不存在，请检查项目文件完整性"
        exit 1
    fi
else
    success ".env 文件已存在"
fi

# 加载环境变量
load_env

# ---- 2. 检查 Docker ----
info "检查 Docker 环境..."
check_docker
success "Docker 环境就绪 (${COMPOSE_CMD})"

# ---- 3. 创建必要目录 ----
info "检查目录结构..."
local dirs=(
    "${PROJECT_ROOT}/postgres/data"
    "${PROJECT_ROOT}/redis/data"
    "${PROJECT_ROOT}/backups/postgres"
    "${PROJECT_ROOT}/backups/redis"
    "${PROJECT_ROOT}/logs"
)
for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        dim "  创建目录: $dir"
    fi
done
success "目录结构完整"

# ---- 4. 设置权限 ----
info "设置数据目录权限..."
if [[ -d "${PROJECT_ROOT}/postgres/data" ]]; then
    chmod 700 "${PROJECT_ROOT}/postgres/data" 2>/dev/null || warn "无法设置 postgres/data 权限"
fi
if [[ -d "${PROJECT_ROOT}/redis/data" ]]; then
    chmod 700 "${PROJECT_ROOT}/redis/data" 2>/dev/null || warn "无法设置 redis/data 权限"
fi
success "权限设置完成"

# ---- 5. 拉取镜像 ----
info "拉取 Docker 镜像..."
compose_cmd pull 2>&1 | while IFS= read -r line; do
    dim "  $line"
done
success "镜像拉取完成"

# ---- 6. 创建 Docker 网络（如果不存在） ----
info "检查 Docker 网络..."
local network_name="docker-network"
if docker network inspect "$network_name" &>/dev/null; then
    success "网络 $network_name 已存在"
else
    compose_cmd up -d --no-start 2>&1 | tail -1
    success "网络已创建"
    compose_cmd down 2>/dev/null
fi

echo ""
separator
echo ""
success "🎉 初始化完成！"
echo ""
info "下一步:"
dim "  1. 编辑 .env 修改密码:  vim .env"
dim "  2. 启动全部服务:      ./scripts/start.sh"
dim "  3. 查看服务状态:      ./scripts/status.sh"
echo ""
