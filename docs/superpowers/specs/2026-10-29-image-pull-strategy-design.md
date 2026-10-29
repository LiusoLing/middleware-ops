# 启动脚本镜像复用设计

- 日期：2026-10-29
- 状态：已确认
- 范围：`scripts/start.sh`、`scripts/restart.sh`、`scripts/common.sh`

## 1. 背景

用户执行 `./scripts/start.sh` 时，Docker Compose 会对本地已存在的镜像发起拉取，典型例子是 `bladex/sentinel-dashboard:latest`。

原因有两层：

1. `start.sh` 调用 `docker compose up -d`，默认拉取策略是 `missing`。
2. Docker Compose v2.11+ 对 `latest` 标签存在特殊处理，即使本地已有同名镜像，也可能重新访问仓库。
3. `init.sh` 中另有显式的 `compose_cmd pull`，会无条件拉取全部镜像。

目标是让日常启动优先复用本地镜像，减少对镜像仓库的依赖和等待时间。

## 2. 目标

- `start.sh` 和 `restart.sh` 启动前检查本地镜像。
- 本地已存在的镜像不拉取。
- 本地缺失的镜像自动拉取。
- 显式升级镜像仍通过 `update.sh` 完成。
- 保持现有脚本风格、输出格式和 macOS Bash 3.2 兼容性。

## 3. 非目标

- 不修改 `init.sh` 的“初始化拉取全部镜像”行为。
- 不修改 `update.sh` 的“强制拉取最新镜像”行为。
- 不修改 `docker-compose.yml` 的 `pull_policy`。
- 不改变直接执行 `docker compose up` 的默认行为。

## 4. 行为设计

### 4.1 start.sh

执行顺序：

1. 加载 `.env`、检查 Docker、校验目标服务（保持现状）。
2. 调用 `ensure_images`：
   - 获取 compose 中所有镜像引用并去重。
   - 逐个执行 `docker image inspect`。
   - 已存在：输出“跳过拉取”及镜像名。
   - 不存在：执行 `docker pull`，失败则终止。
3. 构造启动参数：
   - 基础参数：`-d --remove-orphans`
   - 若当前 Compose 支持 `--pull never`，追加该参数
4. 执行 `up`，后续健康检查逻辑保持不变。

### 4.2 restart.sh

与 `start.sh` 相同的 `ensure_images` 和 `up` 参数，但检查发生在**停止服务之前**，避免拉取失败导致服务被停掉。

### 4.3 单服务启动

`start.sh <service>` 仍检查 compose 中的全量镜像清单。这样能覆盖 `depends_on` 依赖服务的镜像，避免 `up --pull never` 因依赖镜像缺失而失败。检查只读本地状态，只有缺失镜像才会真正拉取。

## 5. 实现设计

### 5.1 common.sh 新增函数

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

```bash
# ── 判断 Compose 是否支持 up --pull never ──
compose_supports_pull_never() {
    local help_text
    help_text=$(compose_cmd up --help 2>&1 || true)
    [[ "$help_text" == *"--pull"* && "$help_text" == *"never"* ]]
}
```

### 5.2 start.sh 修改

在 `compose_cmd up` 之前加入：

```bash
ensure_images || exit 1

up_args=(-d --remove-orphans)
if compose_supports_pull_never; then
    up_args+=(--pull never)
fi
```

启动调用改为：

```bash
compose_cmd up "${up_args[@]}" "$TARGET_SERVICE"
compose_cmd up "${up_args[@]}"
```

### 5.3 restart.sh 修改

在停止服务之前调用：

```bash
ensure_images || exit 1
```

启动部分与 `start.sh` 使用相同的 `up_args` 构造方式。

## 6. 兼容性

- Bash 3.2：不使用 `mapfile`、关联数组、`${arr[-1]}`。
- Compose v2：`config --images` 正常使用。
- Compose v1：`config --images` 不可用时回退解析 `image:` 行。
- 不支持 `--pull never` 的旧版本：自动省略该参数；这些版本本身没有 `latest` 重拉行为。
- 镜像清单为空：输出警告并继续，不阻塞启动。

## 7. 错误处理

- `docker pull` 失败：输出失败的镜像名，`ensure_images` 返回 1，调用方 `exit 1`。
- 无法获取镜像清单：警告后继续，由 Compose 自身处理。
- 拉取失败不会发生在服务停止之后（`restart.sh` 先检查再停止）。

## 8. 验证

静态检查：

```bash
bash -n scripts/common.sh scripts/start.sh scripts/restart.sh
```

桩测试（无 Docker 环境）：

1. 全部镜像存在 → `docker pull` 调用次数为 0。
2. 部分镜像缺失 → 只对缺失镜像调用 `docker pull`。
3. `docker pull` 失败 → `ensure_images` 返回非 0。

真实环境验证：

```bash
./scripts/start.sh
./scripts/restart.sh
```

预期输出包含“本地已存在镜像，跳过拉取”，且不出现 Pulling 日志。

## 9. 风险与回滚

- 风险：本地镜像长期不更新。通过 `./scripts/update.sh` 显式升级，README 已说明该入口。
- 风险：镜像清单解析依赖 `docker compose config` 输出格式。已提供 `--images` 与 `image:` 行两种获取方式。
- 回滚：还原 `common.sh`、`start.sh`、`restart.sh` 三个文件的改动即可。
