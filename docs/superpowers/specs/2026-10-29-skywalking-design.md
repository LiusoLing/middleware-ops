# SkyWalking 集成设计

- 日期：2026-10-29
- 状态：已确认
- 范围：在 Middleware 工程中新增 Apache SkyWalking APM 服务

## 1. 目标

为中间件工程增加一套可用的 SkyWalking 链路追踪基础设施：

- UI 通过宿主机 `8801` 端口访问
- Java Agent 通过宿主机 `11800` 上报数据
- 数据持久化，容器重建后不丢失
- 与现有服务一样由 `docker-compose.yml` 统一编排，管理脚本无需改造

## 2. 非目标

- 不引入 Elasticsearch、Prometheus、Grafana
- 不暴露 BanyanDB 管理端口
- 不提供 UI 认证或 HTTPS（生产环境由反向代理/内网访问控制）
- 不做多节点 OAP 集群

## 3. 技术选型

| 组件 | 镜像 | 版本 | 说明 |
|------|------|------|------|
| SkyWalking OAP | `apache/skywalking-oap-server` | `10.3.0` | 链路追踪服务端 |
| SkyWalking UI | `apache/skywalking-ui` | `10.3.0` | Web 控制台 |
| BanyanDB | `apache/skywalking-banyandb` | `0.9.0` | 时序存储 |

选型理由：

- SkyWalking 10.2.0 起永久移除 H2 存储，官方推荐 BanyanDB 或 Elasticsearch。
- BanyanDB 单容器、资源占用低，官方 quickstart 已验证 `10.3.0 + 0.9.0` 组合。
- Elasticsearch 内存与运维成本明显更高，当前仓库无 ES 依赖。

## 4. 架构与端口

```text
宿主机                           docker-network
┌──────────────┐      ┌─────────────────────────────┐
│ :8801        │─────▶│ skywalking-ui :8080         │
└──────────────┘      └──────────┬──────────────────┘
                                 │ SW_OAP_ADDRESS
┌──────────────┐      ┌──────────▼──────────────────┐
│ :11800       │─────▶│ skywalking-oap :11800/:12800│
│ :12800       │      └──────────┬──────────────────┘
└──────────────┘                 │ banyandb:17912
                      ┌──────────▼──────────────────┐
                      │ skywalking-banyandb :17912  │
                      └─────────────────────────────┘
```

| 服务 | 容器端口 | 宿主机端口 | 用途 |
|------|----------|------------|------|
| skywalking-ui | 8080 | 8801 | 控制台 |
| skywalking-oap | 11800 | 11800 | Agent gRPC 上报 |
| skywalking-oap | 12800 | 12800 | HTTP API / GraphQL / 健康检查 |
| skywalking-banyandb | 17912 / 17913 | 不暴露 | 存储 gRPC / HTTP |

## 5. docker-compose.yml 变更

### 5.1 数据卷

新增命名卷：

```yaml
volumes:
  skywalking-banyandb-data:
    name: skywalking-banyandb-data
```

### 5.2 skywalking-banyandb

```yaml
skywalking-banyandb:
  image: apache/skywalking-banyandb:${BANYANDB_VERSION:-0.9.0}
  container_name: skywalking-banyandb
  hostname: skywalking-banyandb
  restart: unless-stopped
  command: standalone
  environment:
    TZ: ${TZ:-Asia/Shanghai}
  volumes:
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
```

BanyanDB 默认把数据写在 `/tmp` 下的 stream/measure/metadata/property 目录，因此挂载命名卷到 `/tmp` 即可完整持久化。

### 5.3 skywalking-oap

```yaml
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
```

### 5.4 skywalking-ui

```yaml
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

## 6. .env.example 变更

```bash
# -------------------- SkyWalking --------------------
SKYWALKING_VERSION=10.3.0
BANYANDB_VERSION=0.9.0
SKYWALKING_UI_PORT=8801
SKYWALKING_OAP_GRPC_PORT=11800
SKYWALKING_OAP_HTTP_PORT=12800
```

## 7. 文档变更

- **README.md**
  - 服务表新增 SkyWalking UI / OAP / BanyanDB
  - 配置表新增 SkyWalking 变量
  - 日志命令示例增加 `skywalking-oap`、`skywalking-ui`
  - 目录结构补充 BanyanDB 数据卷说明
- **docs/spring-boot.md**
  - 新增“SkyWalking 链路追踪接入”章节
  - Java Agent 9.8.0 下载与解压
  - JVM 参数：`-javaagent`、`-Dskywalking.agent.service_name`、`-Dskywalking.collector.backend_service=localhost:11800`
  - 环境变量写法与 IntelliJ IDEA VM options 示例
  - UI 地址 `http://localhost:8801`
- **CHANGELOG.md**
  - 新增 `[1.2.0] - 2026-10-29` 条目

## 8. 验证

```bash
docker compose config
./scripts/start.sh skywalking-ui      # 按依赖自动启动 BanyanDB + OAP + UI
./scripts/status.sh                   # 三个服务 Running/healthy
curl -f http://localhost:12800/healthcheck
curl -f http://localhost:8801/
```

验收标准：

1. `docker compose config` 无错误。
2. 三个容器均达到 healthy。
3. OAP `/healthcheck` 返回 200。
4. 浏览器可打开 `http://localhost:8801`。
5. 重启/重建容器后，BanyanDB 数据卷仍存在。

## 9. 风险与备注

- OAP 与 BanyanDB 版本必须匹配；升级时需同时更新 `SKYWALKING_VERSION` 与 `BANYANDB_VERSION`。
- UI 默认无认证，生产环境需限制访问来源。
- 首次启动 OAP 需要等待 BanyanDB 健康，启动时间可能超过 60 秒，`start.sh` 的超时提示不代表启动失败。
- 回滚：移除三个服务定义与数据卷，执行 `./scripts/start.sh` 重建其余服务。
