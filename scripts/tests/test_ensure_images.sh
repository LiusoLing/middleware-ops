#!/usr/bin/env bash
# ============================================================
# test_ensure_images.sh — ensure_images 单元测试（无需 Docker）
# ============================================================
# 用法:
#   ./scripts/tests/test_ensure_images.sh
# ============================================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${TEST_DIR}/../common.sh"

PULL_LOG=""
STUB_IMAGES=()
STUB_PRESENT=()
STUB_PULL_FAIL=0
STUB_HELP=""

compose_cmd() {
    if [[ "${1:-}" == "config" && "${2:-}" == "--images" ]]; then
        if [[ ${#STUB_IMAGES[@]} -gt 0 ]]; then
            printf '%s\n' "${STUB_IMAGES[@]}"
        fi
        return 0
    fi
    if [[ "${1:-}" == "up" && "${2:-}" == "--help" ]]; then
        printf '%s\n' "$STUB_HELP"
        return 0
    fi
    return 1
}

docker() {
    local sub="${1:-}"
    case "$sub" in
        image)
            local image="${3:-}"
            local present
            if [[ ${#STUB_PRESENT[@]} -gt 0 ]]; then
                for present in "${STUB_PRESENT[@]}"; do
                    [[ "$present" == "$image" ]] && return 0
                done
            fi
            return 1
            ;;
        pull)
            printf '%s\n' "${2:-}" >> "$PULL_LOG"
            [[ "$STUB_PULL_FAIL" == "1" ]] && return 1
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

setup_case() {
    PULL_LOG=$(mktemp)
    STUB_IMAGES=("$@")
    STUB_PRESENT=()
    STUB_PULL_FAIL=0
    STUB_HELP=""
}

cleanup_case() {
    rm -f "$PULL_LOG"
}

# 场景 1：全部镜像已存在 → 不拉取
setup_case "postgres:18-alpine" "redis:7-alpine"
STUB_PRESENT=("postgres:18-alpine" "redis:7-alpine")
ensure_images >/dev/null 2>&1
[[ ! -s "$PULL_LOG" ]] || fail "expected no pulls, got: $(tr '\n' ' ' < "$PULL_LOG")"
cleanup_case
echo "PASS: all images present"

# 场景 2：部分缺失 → 只拉缺失镜像
setup_case "postgres:18-alpine" "sentinel-dashboard:latest"
STUB_PRESENT=("postgres:18-alpine")
ensure_images >/dev/null 2>&1
[[ "$(cat "$PULL_LOG")" == "sentinel-dashboard:latest" ]] || fail "unexpected pulls: $(cat "$PULL_LOG")"
cleanup_case
echo "PASS: only missing image pulled"

# 场景 3：拉取失败 → 返回非 0
setup_case "missing:latest"
STUB_PULL_FAIL=1
if ensure_images >/dev/null 2>&1; then
    fail "ensure_images should fail when docker pull fails"
fi
cleanup_case
echo "PASS: pull failure propagates"

# 场景 4：镜像清单为空 → 不阻塞
setup_case
ensure_images >/dev/null 2>&1
[[ ! -s "$PULL_LOG" ]] || fail "expected no pulls for empty image list"
cleanup_case
echo "PASS: empty image list does not block"

# 场景 5：Compose 支持 --pull never
STUB_HELP='      --pull string   Pull image before running ("always"|"missing"|"never")'
if ! compose_supports_pull_never; then
    fail "expected compose_supports_pull_never to return 0"
fi
echo "PASS: detects --pull never support"

# 场景 6：Compose 不支持 --pull never
STUB_HELP='      --pull          Pull newer images'
if compose_supports_pull_never; then
    fail "expected compose_supports_pull_never to return 1"
fi
echo "PASS: detects missing --pull never support"

echo "all ensure_images tests passed"
