# 启动脚本镜像复用实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `start.sh` 和 `restart.sh` 复用本地已有镜像，只拉取缺失镜像，并阻止 Compose 对 `latest` 镜像的二次拉取。

**Architecture:** 在 `common.sh` 中新增两个可复用函数：`ensure_images()` 负责检查并补齐缺失镜像，`compose_supports_pull_never()` 负责探测 Compose 是否支持 `--pull never`。`start.sh` 与 `restart.sh` 在启动前调用检查，并用探测结果构造 `up` 参数。

**Tech Stack:** Bash 3.2 兼容脚本、Docker CLI、Docker Compose v2/v1。

## Global Constraints

- 仅修改 `scripts/common.sh`、`scripts/start.sh`、`scripts/restart.sh`，新增 `scripts/tests/test_ensure_images.sh`。
- 不修改 `scripts/init.sh`、`scripts/update.sh`、`docker-compose.yml`。
- 兼容 macOS 自带 Bash 3.2：禁止使用 `mapfile`、关联数组、`${arr[-1]}`。
- 保持现有输出风格：`info`、`dim`、`success`、`warn`、`error`。
- `--pull never` 仅在当前 Compose 的 `up --help` 明确包含 `--pull` 与 `never` 时追加。
- 已存在的镜像绝不调用 `docker pull`；缺失镜像拉取失败必须返回非 0。
- `restart.sh` 的镜像检查必须发生在停止服务之前。
- 当前环境没有 Docker，运行时验证只能在有 Docker 的机器执行。

---

### Task 1: 在 common.sh 中新增镜像检查函数

**Files:**
- Modify: `scripts/common.sh:87-90`（`get_services` 之后、`is_service_running` 之前）
- Test: `scripts/tests/test_ensure_images.sh`（新建）

**Interfaces:**
- Produces: `ensure_images()`，无参数，返回 0 表示镜像齐全或无需检查，返回 1 表示拉取失败。
- Produces: `compose_supports_pull_never()`，无参数，返回 0 表示支持 `--pull never`，返回 1 表示不支持。
- Consumes: 现有的 `compose_cmd`、`info`、`dim`、`success`、`warn`、`error` 函数。

- [ ] **Step 1: 新建失败测试脚本**

创建 `scripts/tests/test_ensure_images.sh`：

```bash
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
chmod +x scripts/tests/test_ensure_images.sh
./scripts/tests/test_ensure_images.sh
```

Expected: 失败，提示 `ensure_images: command not found` 或 `compose_supports_pull_never: command not found`。

- [ ] **Step 3: 在 common.sh 中实现 ensure_images**

在 `get_services()` 之后加入：

```bash
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
```

- [ ] **Step 4: 在 common.sh 中实现 compose_supports_pull_never**

紧接 `ensure_images()` 之后加入：

```bash
# ── 判断 Compose 是否支持 up --pull never ──
compose_supports_pull_never() {
    local help_text
    help_text=$(compose_cmd up --help 2>&1 || true)
    [[ "$help_text" == *"--pull"* && "$help_text" == *"never"* ]]
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
./scripts/tests/test_ensure_images.sh
```

Expected:

```text
PASS: all images present
PASS: only missing image pulled
PASS: pull failure propagates
PASS: empty image list does not block
PASS: detects --pull never support
PASS: detects missing --pull never support
all ensure_images tests passed
```

- [ ] **Step 6: 提交**

```bash
git add scripts/common.sh scripts/tests/test_ensure_images.sh
git commit -m "feat(scripts): 新增本地镜像检查与缺失镜像拉取函数"
```

---

### Task 2: start.sh 使用镜像检查并禁止启动时拉取

**Files:**
- Modify: `scripts/start.sh:44-51`

**Interfaces:**
- Consumes: `ensure_images()` 与 `compose_supports_pull_never()`（Task 1）。
- Produces: `start.sh` 启动前复用本地镜像；已有镜像不再触发拉取。

- [ ] **Step 1: 编写静态检查确认当前不具备目标行为**

```bash
grep -q 'ensure_images || exit 1' scripts/start.sh \
  && grep -q 'up_args+=(--pull never)' scripts/start.sh \
  && echo "start.sh image reuse present"
```

Expected: 退出码为 1（不输出 `start.sh image reuse present`）。

- [ ] **Step 2: 修改启动逻辑**

将原来的启动块：

```bash
# 启动服务
if [[ -n "$TARGET_SERVICE" ]]; then
    info "正在启动 ${TARGET_SERVICE}..."
    compose_cmd up -d --remove-orphans "$TARGET_SERVICE"
else
    info "正在启动所有服务..."
    compose_cmd up -d --remove-orphans
fi
```

替换为：

```bash
# 确保本地镜像齐全（只拉取缺失镜像）
ensure_images || exit 1

# 构造启动参数；支持的 Compose 版本禁止启动时再次拉取
up_args=(-d --remove-orphans)
if compose_supports_pull_never; then
    up_args+=(--pull never)
fi

# 启动服务
if [[ -n "$TARGET_SERVICE" ]]; then
    info "正在启动 ${TARGET_SERVICE}..."
    compose_cmd up "${up_args[@]}" "$TARGET_SERVICE"
else
    info "正在启动所有服务..."
    compose_cmd up "${up_args[@]}"
fi
```

- [ ] **Step 3: 运行语法与静态检查**

```bash
bash -n scripts/start.sh
grep -q 'ensure_images || exit 1' scripts/start.sh
grep -q 'up_args+=(--pull never)' scripts/start.sh
grep -q 'compose_cmd up "${up_args\[@\]}"' scripts/start.sh
echo "start.sh assertions passed"
```

Expected: `start.sh assertions passed`。

- [ ] **Step 4: 提交**

```bash
git add scripts/start.sh
git commit -m "feat(scripts): start 启动时复用本地镜像"
```

---

### Task 3: restart.sh 使用镜像检查并禁止启动时拉取

**Files:**
- Modify: `scripts/restart.sh:29-48`

**Interfaces:**
- Consumes: `ensure_images()` 与 `compose_supports_pull_never()`（Task 1）。
- Produces: `restart.sh` 在停止服务前补齐镜像，重启时复用本地镜像。

- [ ] **Step 1: 编写静态检查确认当前不具备目标行为**

```bash
grep -q 'ensure_images || exit 1' scripts/restart.sh \
  && grep -q 'up_args+=(--pull never)' scripts/restart.sh \
  && echo "restart.sh image reuse present"
```

Expected: 退出码为 1（不输出 `restart.sh image reuse present`）。

- [ ] **Step 2: 在停止服务之前加入镜像检查**

在 `# 停止` 注释之前加入：

```bash
# 停止前确保镜像齐全，避免拉取失败造成无谓停机
ensure_images || exit 1

```

- [ ] **Step 3: 修改启动逻辑**

将原来的启动块：

```bash
# 启动
if [[ -n "$TARGET_SERVICE" ]]; then
    info "正在启动 ${TARGET_SERVICE}..."
    compose_cmd up -d --remove-orphans "$TARGET_SERVICE"
else
    info "正在启动所有服务..."
    compose_cmd up -d --remove-orphans
fi
```

替换为：

```bash
# 构造启动参数；支持的 Compose 版本禁止启动时再次拉取
up_args=(-d --remove-orphans)
if compose_supports_pull_never; then
    up_args+=(--pull never)
fi

# 启动
if [[ -n "$TARGET_SERVICE" ]]; then
    info "正在启动 ${TARGET_SERVICE}..."
    compose_cmd up "${up_args[@]}" "$TARGET_SERVICE"
else
    info "正在启动所有服务..."
    compose_cmd up "${up_args[@]}"
fi
```

- [ ] **Step 4: 运行语法与静态检查**

```bash
bash -n scripts/restart.sh
grep -q 'ensure_images || exit 1' scripts/restart.sh
grep -q 'up_args+=(--pull never)' scripts/restart.sh
grep -q 'compose_cmd up "${up_args\[@\]}"' scripts/restart.sh
echo "restart.sh assertions passed"
```

Expected: `restart.sh assertions passed`。

- [ ] **Step 5: 提交**

```bash
git add scripts/restart.sh
git commit -m "feat(scripts): restart 重启时复用本地镜像"
```

---

### Task 4: 全量验证

**Files:**
- 无新增或修改。

**Interfaces:**
- Consumes: Task 1-3 的全部改动。

- [ ] **Step 1: 运行全部语法检查**

```bash
bash -n scripts/common.sh
bash -n scripts/start.sh
bash -n scripts/restart.sh
bash -n scripts/tests/test_ensure_images.sh
echo "syntax checks passed"
```

Expected: `syntax checks passed`。

- [ ] **Step 2: 运行单元测试**

```bash
./scripts/tests/test_ensure_images.sh
```

Expected: 以 `all ensure_images tests passed` 结尾。

- [ ] **Step 3: 确认未改动范围**

```bash
git diff main --name-only
```

Expected: 仅包含：

```text
docs/superpowers/plans/2026-10-29-image-pull-strategy.md
docs/superpowers/specs/2026-10-29-image-pull-strategy-design.md
scripts/common.sh
scripts/restart.sh
scripts/start.sh
scripts/tests/test_ensure_images.sh
```

- [ ] **Step 4: 真实环境验证（有 Docker 时执行）**

```bash
./scripts/start.sh
./scripts/restart.sh
```

Expected: 输出包含“本地已存在镜像，跳过拉取”，且没有新的 `Pulling` 日志。当前环境无 Docker，此项记录为待执行，不得声称已通过。
