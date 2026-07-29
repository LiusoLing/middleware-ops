#!/usr/bin/env bash
# ============================================================
# clean.sh — 清理 Docker 资源
# ============================================================
# 功能:
#   - 清理未使用的镜像、容器、网络、数据卷
#   - 清理指定服务或全部的本地日志
#
# 用法:
#   ./scripts/clean.sh                # 清理未使用的 Docker 资源
#   ./scripts/clean.sh --all          # 清理所有（包括已停止的容器）
#   ./scripts/clean.sh --volumes      # 包括清理未使用的数据卷（危险！）
#   ./scripts/clean.sh --logs         # 清理全部本地日志文件
#   ./scripts/clean.sh --logs postgres # 只清理 PostgreSQL 容器日志
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

load_env
check_docker

CLEAN_ALL=false
CLEAN_VOLUMES=false
CLEAN_LOGS=false
TARGET_SERVICE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all|-a)
            CLEAN_ALL=true
            shift
            ;;
        --volumes|-v)
            CLEAN_VOLUMES=true
            shift
            ;;
        --logs|-l)
            CLEAN_LOGS=true
            shift
            # --logs 后面可以跟可选的服务名
            if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
                TARGET_SERVICE="$1"
                validate_service "$TARGET_SERVICE" || exit 1
                shift
            fi
            ;;
        *)
            # 也支持直接传服务名作为清理目标（清理该服务的日志）
            if [[ -z "$TARGET_SERVICE" ]]; then
                TARGET_SERVICE="$1"
                validate_service "$TARGET_SERVICE" || exit 1
                CLEAN_LOGS=true
            else
                warn "未知参数: $1"
            fi
            shift
            ;;
    esac
done

header "🧹 Middleware Clean — 资源清理"

echo ""

# ============================================================
# 显示当前 Docker 资源使用
# ============================================================
info "当前 Docker 资源使用:"
echo ""
docker system df 2>/dev/null || true
echo ""

# ============================================================
# 清理容器日志（Docker 容器内日志截断）
# ============================================================
if $CLEAN_LOGS; then
    if [[ -n "$TARGET_SERVICE" ]]; then
        info "清理 ${TARGET_SERVICE} 容器日志..."
        container_id
        container_id=$(compose_cmd ps -q "$TARGET_SERVICE" 2>/dev/null || true)
        if [[ -n "$container_id" ]]; then
            # 截断容器日志文件而不是删除容器
            log_path
            log_path=$(docker inspect -f '{{.LogPath}}' "$container_id" 2>/dev/null || true)
            if [[ -n "$log_path" ]] && [[ -f "$log_path" ]]; then
                if echo -n | sudo tee "$log_path" &>/dev/null || echo -n > "$log_path" 2>/dev/null; then
                    success "已清理 ${TARGET_SERVICE} 容器日志"
                else
                    warn "无法截断 ${TARGET_SERVICE} 容器日志（可能需要 sudo）"
                fi
            else
                # fallback: 如果无法直接截断文件，recreate 容器
                dim "  尝试通过重建容器清理日志..."
            fi
        else
            dim "  ${TARGET_SERVICE} 容器未运行，跳过容器日志清理"
        fi
        echo ""
    else
        info "清理所有容器日志..."
        while IFS= read -r service; do
            cid
            cid=$(compose_cmd ps -q "$service" 2>/dev/null || true)
            if [[ -n "$cid" ]]; then
                log_path
                log_path=$(docker inspect -f '{{.LogPath}}' "$cid" 2>/dev/null || true)
                if [[ -n "$log_path" ]] && [[ -f "$log_path" ]]; then
                    if echo -n | sudo tee "$log_path" &>/dev/null || echo -n > "$log_path" 2>/dev/null; then
                        dim "  ✔ $service"
                    else
                        dim "  ⚠ $service (需要 sudo)"
                    fi
                else
                    dim "  - $service (无日志文件)"
                fi
            fi
        done < <(get_services)
        success "容器日志清理完成"
        echo ""
    fi

    # 清理本地日志目录
    log_dir="${PROJECT_ROOT}/logs"
    if [[ -d "$log_dir" ]]; then
        info "清理本地日志文件..."
        log_count
        log_count=$(find "$log_dir" -type f ! -name '.gitkeep' | wc -l | tr -d ' ')
        if [[ "$log_count" -gt 0 ]]; then
            find "$log_dir" -type f ! -name '.gitkeep' -delete
            success "已清理 $log_count 个本地日志文件"
        else
            dim "  没有本地日志文件需要清理"
        fi
    fi
    echo ""
fi

# ============================================================
# 清理未使用的镜像
# ============================================================
info "清理未使用的 Docker 镜像..."
docker image prune -f 2>&1 | tail -1
echo ""

# ============================================================
# 清理已停止的容器
# ============================================================
if $CLEAN_ALL; then
    info "清理已停止的容器..."
    docker container prune -f 2>&1 | tail -1
    echo ""
fi

# ============================================================
# 清理未使用的网络
# ============================================================
info "清理未使用的 Docker 网络..."
docker network prune -f 2>&1 | tail -1
echo ""

# ============================================================
# 清理构建缓存
# ============================================================
info "清理 Docker 构建缓存..."
docker builder prune -f 2>&1 | tail -1
echo ""

# ============================================================
# 清理未使用的数据卷（危险操作，需确认）
# ============================================================
if $CLEAN_VOLUMES; then
    echo ""
    echo -e "${COLOR_RED}${COLOR_BOLD}⚠️  清理未使用的数据卷将永久删除数据！${COLOR_RESET}"
    echo ""

    warn "以下数据卷未被使用，将被删除:"
    docker volume ls -qf dangling=true | while IFS= read -r vol; do
        if [[ -n "$vol" ]]; then
            size
            size=$(docker volume inspect "$vol" -f '{{.Mountpoint}}' 2>/dev/null | xargs du -sh 2>/dev/null | cut -f1 || echo "N/A")
            dim "  - $vol ($size)"
        fi
    done
    echo ""

    if confirm "确认删除以上数据卷？此操作不可恢复！"; then
        docker volume prune -f 2>&1 | tail -1
        success "数据卷已清理"
    else
        info "已跳过数据卷清理"
    fi
fi

echo ""
separator
echo ""

# 显示清理后状态
info "清理后 Docker 资源使用:"
echo ""
docker system df 2>/dev/null || true
echo ""

success "🎉 清理完成！"
echo ""
