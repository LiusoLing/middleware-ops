# SkyWalking 集成实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Middleware 工程中集成 SkyWalking 10.3.0 + BanyanDB 0.9.0，UI 暴露在宿主机 8801 端口。

**Architecture:** 三个容器组成单向依赖链：`skywalking-ui` → `skywalking-oap` → `skywalking-banyandb`。UI 通过 `SW_OAP_ADDRESS` 访问 OAP，OAP 通过 `SW_STORAGE_BANYANDB_TARGETS` 使用 BanyanDB 存储，BanyanDB 数据写入命名卷。所有服务接入现有 `docker-network`，管理脚本通过 `compose config --services` 自动发现，无需修改。

**Tech Stack:** Docker Compose、Apache SkyWalking OAP/UI 10.3.0、BanyanDB 0.9.0、Bash 管理脚本。

## Global Constraints

- UI 宿主机端口固定为 `8801`（容器内 8080）。
- OAP 宿主机端口为 `11800`（gRPC）和 `12800`（HTTP）。
- BanyanDB 端口 `17912`/`17913` 不暴露到宿主机。
- 版本默认值：`SKYWALKING_VERSION=10.3.0`、`BANYANDB_VERSION=0.9.0`。
- 命名卷名称：`skywalking-banyandb-data`，挂载到 BanyanDB 容器 `/tmp`。
- 所有新增服务必须包含 `restart: unless-stopped`、`TZ`、`docker-network`、日志轮转（`max-size: 10m`、`max-file: 3`）和 healthcheck。
- 文档使用中文，风格与现有 README/CHANGELOG 保持一致。
- 不修改 `scripts/` 下任何文件；不提交 `.env`；不提交未跟踪的 `dokuwiki/` 目录。
- 当前环境没有 Docker，可用 `python3` + PyYAML 做静态校验；若执行环境有 Docker，追加 `docker compose --env-file .env.example config --quiet`。

---

### Task 1: 在 docker-compose.yml 中新增 SkyWalking 服务

**Files:**
- Modify: `docker-compose.yml:30-36`（volumes 段）
- Modify: `docker-compose.yml:271`（文件末尾，services 段）

**Interfaces:**
- Produces: 服务名 `skywalking-banyandb`、`skywalking-oap`、`skywalking-ui`；数据卷 `skywalking-banyandb-data`；环境变量 `SKYWALKING_VERSION`、`BANYANDB_VERSION`、`SKYWALKING_UI_PORT`、`SKYWALKING_OAP_GRPC_PORT`、`SKYWALKING_OAP_HTTP_PORT`。

- [ ] **Step 1: 编写失败的结构校验**

运行：

```bash
python3 - <<'PY'
import yaml

with open('docker-compose.yml') as f:
    compose = yaml.safe_load(f)

expected_services = {'skywalking-banyandb', 'skywalking-oap', 'skywalking-ui'}
assert expected_services.issubset(compose['services']), compose['services'].keys()
assert 'skywalking-banyandb-data' in compose['volumes'], compose['volumes'].keys()

oap_ports = compose['services']['skywalking-oap']['ports']
assert '${SKYWALKING_OAP_GRPC_PORT:-11800}:11800' in oap_ports
assert '${SKYWALKING_OAP_HTTP_PORT:-12800}:12800' in oap_ports

ui_ports = compose['services']['skywalking-ui']['ports']
assert '${SKYWALKING_UI_PORT:-8801}:8080' in ui_ports
print('skywalking compose assertions passed')
PY
```

Expected: `AssertionError`（服务尚不存在）。

- [ ] **Step 2: 新增 BanyanDB 数据卷**

在 `volumes:` 段 `dokuwiki-data` 之后加入：

```yaml
  skywalking-banyandb-data:
    name: skywalking-banyandb-data
```

- [ ] **Step 3: 新增三个服务定义**

在 `docker-compose.yml` 文件末尾（`dokuwiki` 服务之后）追加：

```yaml
  # ==========================================================
  # SkyWalking BanyanDB
  # ==========================================================
  skywalking-banyandb:
    image: apache/skywalking-banyandb:${BANYANDB_VERSION:-0.9.0}
    container_name: skywalking-banyandb
    hostname: skywalking-banyandb
    restart: unless-stopped

    command: standalone

    environment:
      TZ: ${TZ:-Asia/Shanghai}

    volumes:
      # BanyanDB 默认数据目录位于 /tmp 下
      - skywalking-banyandb-data:/tmp

    networks:
      - docker-network

    healthcheck:
      test: ["CMD", "./bydbctl", "health", "--config=-", "--addr=http://127.0.0.1:17913"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ==========================================================
  # SkyWalking OAP
  # ==========================================================
  skywalking-oap:
    image: apache/skywalking-oap-server:${SKYWALKING_VERSION:-10.3.0}
    container_name: skywalking-oap
    hostname: skywalking-oap
    restart: unless-stopped

    depends_on:
      skywalking-banyandb:
        condition: service_healthy

    environment:
      TZ: ${TZ:-Asia/Shanghai}
      SW_STORAGE: banyandb
      SW_STORAGE_BANYANDB_TARGETS: skywalking-banyandb:17912
      SW_HEALTH_CHECKER: default

    ports:
      - "${SKYWALKING_OAP_GRPC_PORT:-11800}:11800"
      - "${SKYWALKING_OAP_HTTP_PORT:-12800}:12800"

    networks:
      - docker-network

    healthcheck:
      test: ["CMD", "/skywalking/bin/swctl", "ch"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ==========================================================
  # SkyWalking UI
  # ==========================================================
  skywalking-ui:
    image: apache/skywalking-ui:${SKYWALKING_VERSION:-10.3.0}
    container_name: skywalking-ui
    hostname: skywalking-ui
    restart: unless-stopped

    depends_on:
      skywalking-oap:
        condition: service_healthy

    environment:
      TZ: ${TZ:-Asia/Shanghai}
      SW_OAP_ADDRESS: http://skywalking-oap:12800

    ports:
      - "${SKYWALKING_UI_PORT:-8801}:8080"

    networks:
      - docker-network

    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:8080/ || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

- [ ] **Step 4: 重新运行结构校验**

运行 Step 1 的 Python 命令。

Expected: `skywalking compose assertions passed`。

如果环境有 Docker，再运行：

```bash
docker compose --env-file .env.example config --quiet && echo "compose config OK"
```

Expected: `compose config OK`。

- [ ] **Step 5: 提交**

```bash
git add docker-compose.yml
git commit -m "feat(skywalking): 集成 SkyWalking OAP、UI 与 BanyanDB 服务"
```

---

### Task 2: 在 .env.example 中新增 SkyWalking 变量

**Files:**
- Modify: `.env.example:58-60`（DokuWiki 段之后）

**Interfaces:**
- Consumes: Task 1 中 `docker-compose.yml` 使用的变量名。
- Produces: `SKYWALKING_VERSION`、`BANYANDB_VERSION`、`SKYWALKING_UI_PORT`、`SKYWALKING_OAP_GRPC_PORT`、`SKYWALKING_OAP_HTTP_PORT` 的模板值。

- [ ] **Step 1: 编写失败的变量校验**

运行：

```bash
python3 - <<'PY'
from pathlib import Path

text = Path('.env.example').read_text()
expected = {
    'SKYWALKING_VERSION': '10.3.0',
    'BANYANDB_VERSION': '0.9.0',
    'SKYWALKING_UI_PORT': '8801',
    'SKYWALKING_OAP_GRPC_PORT': '11800',
    'SKYWALKING_OAP_HTTP_PORT': '12800',
}
for key, value in expected.items():
    assert f'{key}={value}' in text, f'missing {key}={value}'
print('.env.example skywalking assertions passed')
PY
```

Expected: `AssertionError: missing SKYWALKING_VERSION=10.3.0`。

- [ ] **Step 2: 追加配置段**

在 `.env.example` 的 DokuWiki 段之后加入：

```bash
# -------------------- SkyWalking --------------------
SKYWALKING_VERSION=10.3.0
BANYANDB_VERSION=0.9.0
SKYWALKING_UI_PORT=8801
SKYWALKING_OAP_GRPC_PORT=11800
SKYWALKING_OAP_HTTP_PORT=12800
```

- [ ] **Step 3: 重新运行变量校验**

运行 Step 1 的 Python 命令。

Expected: `.env.example skywalking assertions passed`。

- [ ] **Step 4: 提交**

```bash
git add .env.example
git commit -m "feat(skywalking): 新增 SkyWalking 环境变量模板"
```

---

### Task 3: 更新 README 与 CHANGELOG

**Files:**
- Modify: `README.md:5`（项目简介）
- Modify: `README.md:98-104`（服务表）
- Modify: `README.md:120-125`（日志命令）
- Modify: `README.md:145-161`（配置表）
- Modify: `README.md:37-92`（目录结构后的说明）
- Modify: `CHANGELOG.md:10`（新增版本条目）

**Interfaces:**
- Consumes: Task 1 的服务名、Task 2 的变量名。
- Produces: 用户可查阅的服务端口、变量和日志命令说明。

- [ ] **Step 1: 更新 README 项目简介**

将第 5 行：

```markdown
一套标准化的中间件基础设施，通过 Docker Compose 统一管理 PostgreSQL、Redis 等服务，提供一键部署、备份恢复、健康检查等运维能力。
```

改为：

```markdown
一套标准化的中间件基础设施，通过 Docker Compose 统一管理 PostgreSQL、Redis、SkyWalking 等服务，提供一键部署、备份恢复、健康检查等运维能力。
```

- [ ] **Step 2: 更新 README 服务表**

在 DokuWiki 行之后加入：

```markdown
| SkyWalking OAP | 10.3.0 | 11800 / 12800 | 链路追踪服务端 / Agent 上报 |
| SkyWalking UI | 10.3.0 | 8801 | APM 可视化控制台 |
| BanyanDB | 0.9.0 | 内部 17912 | SkyWalking 时序存储 |
```

- [ ] **Step 3: 更新 README 日志命令示例**

在 `./scripts/logs.sh dokuwiki` 之后加入：

```bash
./scripts/logs.sh skywalking-oap   # 查看 SkyWalking OAP 日志
./scripts/logs.sh skywalking-ui    # 查看 SkyWalking UI 日志
./scripts/logs.sh skywalking-banyandb  # 查看 BanyanDB 日志
```

- [ ] **Step 4: 更新 README 配置表**

在 `DOKUWIKI_PORT` 行之后加入：

```markdown
| `SKYWALKING_UI_PORT` | SkyWalking UI 端口 | `8801` |
| `SKYWALKING_OAP_GRPC_PORT` | OAP Agent gRPC 端口 | `11800` |
| `SKYWALKING_OAP_HTTP_PORT` | OAP HTTP API 端口 | `12800` |
| `SKYWALKING_VERSION` | SkyWalking 镜像版本 | `10.3.0` |
| `BANYANDB_VERSION` | BanyanDB 镜像版本 | `0.9.0` |
```

- [ ] **Step 5: 更新 README 目录结构说明**

在目录结构代码块之后、`## 包含的服务` 之前加入：

```markdown
> SkyWalking 的 BanyanDB 数据保存在 Docker 命名卷 `skywalking-banyandb-data` 中。
```

- [ ] **Step 6: 更新 CHANGELOG**

在 `## [1.1.0] - 2026-07-29` 之前加入：

```markdown
## [1.2.0] - 2026-10-29

### Added

- SkyWalking OAP + UI 服务（10.3.0），UI 默认端口 8801
- BanyanDB 0.9.0 存储，数据持久化到命名卷 skywalking-banyandb-data
- OAP 暴露 11800（Agent gRPC）与 12800（HTTP API）
- .env 新增 SKYWALKING_*、BANYANDB_* 配置项
- docs/spring-boot.md 新增 SkyWalking Java Agent 接入指南

---

```

- [ ] **Step 7: 运行文档校验**

```bash
grep -q 'SkyWalking OAP' README.md
grep -q 'SKYWALKING_UI_PORT' README.md
grep -q 'skywalking-oap' README.md
grep -q 'skywalking-banyandb-data' README.md
grep -q '\[1.2.0\] - 2026-10-29' CHANGELOG.md
echo "README/CHANGELOG assertions passed"
```

Expected: `README/CHANGELOG assertions passed`。

- [ ] **Step 8: 提交**

```bash
git add README.md CHANGELOG.md
git commit -m "docs(skywalking): 更新服务清单、配置说明与更新日志"
```

---

### Task 4: 在 docs/spring-boot.md 中新增 Agent 接入指南

**Files:**
- Modify: `docs/spring-boot.md:410-412`（在 `## 快速验证` 之前插入新章节）

**Interfaces:**
- Consumes: Task 1 的 OAP gRPC 地址 `localhost:11800`、UI 地址 `http://localhost:8801`；Docker 网络内 OAP 地址 `skywalking-oap:11800`。
- Produces: 开发者可直接照抄的 Agent 下载、JVM 参数、环境变量和 IDEA 配置示例。

- [ ] **Step 1: 插入 SkyWalking 章节**

在 `## 快速验证` 之前插入：

````markdown
## 10. SkyWalking 链路追踪接入

Middleware 已内置 SkyWalking：

- UI：<http://localhost:8801>
- Agent 上报地址：`localhost:11800`
- OAP HTTP API：<http://localhost:12800>

### 10.1 下载 Java Agent

以 9.8.0 为例（Java Agent 8.x/9.x 均兼容 OAP 10.x）：

```bash
curl -LO https://archive.apache.org/dist/skywalking/java-agent/9.8.0/apache-skywalking-java-agent-9.8.0.tgz
tar -xzf apache-skywalking-java-agent-9.8.0.tgz -C /opt
```

解压后 Agent 路径为 `/opt/skywalking-agent/skywalking-agent.jar`。

### 10.2 启动参数

```bash
java \
  -javaagent:/opt/skywalking-agent/skywalking-agent.jar \
  -Dskywalking.agent.service_name=my-app \
  -Dskywalking.collector.backend_service=localhost:11800 \
  -jar my-app.jar
```

等价的系统属性与环境变量：

```bash
export SW_AGENT_NAME=my-app
export SW_AGENT_COLLECTOR_BACKEND_SERVICES=localhost:11800
```

### 10.3 IntelliJ IDEA 配置

在 Run/Debug Configurations → VM options 中填入：

```text
-javaagent:/opt/skywalking-agent/skywalking-agent.jar
-Dskywalking.agent.service_name=my-app
-Dskywalking.collector.backend_service=localhost:11800
```

### 10.4 容器内接入

Spring Boot 应用与 middleware 共用 `docker-network` 时，后端地址应使用服务名：

```yaml
services:
  app:
    environment:
      JAVA_TOOL_OPTIONS: "-javaagent:/skywalking/agent/skywalking-agent.jar"
      SW_AGENT_NAME: my-app
      SW_AGENT_COLLECTOR_BACKEND_SERVICES: skywalking-oap:11800
    volumes:
      - /opt/skywalking-agent:/skywalking/agent:ro
    networks:
      - docker-network
```

### 10.5 验证

1. 启动基础设施：`cd middleware && ./scripts/start.sh skywalking-ui`
2. 确认 OAP 健康：`curl -f http://localhost:12800/healthcheck`
3. 启动应用后打开 <http://localhost:8801>，在服务列表中应出现 `my-app`。

````

- [ ] **Step 2: 运行文档校验**

```bash
grep -q '## 10. SkyWalking 链路追踪接入' docs/spring-boot.md
grep -q 'skywalking-oap:11800' docs/spring-boot.md
grep -q 'localhost:8801' docs/spring-boot.md
echo "spring-boot.md assertions passed"
```

Expected: `spring-boot.md assertions passed`。

- [ ] **Step 3: 提交**

```bash
git add docs/spring-boot.md
git commit -m "docs(skywalking): 新增 Spring Boot Java Agent 接入指南"
```

---

## 最终验证

- [ ] 运行全部静态校验：

```bash
python3 - <<'PY'
import yaml
from pathlib import Path

compose = yaml.safe_load(Path('docker-compose.yml').read_text())
for name in ('skywalking-banyandb', 'skywalking-oap', 'skywalking-ui'):
    assert name in compose['services'], name
assert 'skywalking-banyandb-data' in compose['volumes']
assert '${SKYWALKING_UI_PORT:-8801}:8080' in compose['services']['skywalking-ui']['ports']

env = Path('.env.example').read_text()
for line in ('SKYWALKING_VERSION=10.3.0', 'BANYANDB_VERSION=0.9.0', 'SKYWALKING_UI_PORT=8801'):
    assert line in env, line

readme = Path('README.md').read_text()
assert 'SkyWalking UI' in readme and '8801' in readme
assert 'skywalking-banyandb-data' in readme

spring_boot = Path('docs/spring-boot.md').read_text()
assert 'SkyWalking 链路追踪接入' in spring_boot
assert 'skywalking-oap:11800' in spring_boot

changelog = Path('CHANGELOG.md').read_text()
assert '[1.2.0] - 2026-10-29' in changelog
print('all skywalking assertions passed')
PY
```

Expected: `all skywalking assertions passed`。

- [ ] 如果执行环境有 Docker，运行：

```bash
docker compose --env-file .env.example config --quiet
./scripts/start.sh skywalking-ui
./scripts/status.sh
curl -f http://localhost:12800/healthcheck
curl -f http://localhost:8801/
```

Expected: compose 配置无错误；三个服务 healthy；两个 curl 返回 200。若当前环境无 Docker，记录为“运行时验证待在有 Docker 的机器执行”，不得声称已通过运行时验证。

- [ ] 确认工作区只包含预期的已修改文件：

```bash
git status --short
```

Expected: 无 `dokuwiki/` 或 `.env` 被加入暂存区。
