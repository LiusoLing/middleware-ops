# Middleware

> 生产级中间件统一管理工程

一套标准化的中间件基础设施，通过 Docker Compose 统一管理 PostgreSQL、Redis 等服务，提供一键部署、备份恢复、健康检查等运维能力。

设计目标：**易维护、易扩展、一键操作、生产可用**。

---

## 快速开始

```bash
# 1. 克隆项目
git clone <repo-url> middleware
cd middleware

# 2. 配置环境变量
cp .env.example .env
# 编辑 .env 修改密码等敏感信息
vim .env

# 3. 初始化（检查环境、创建目录）
./scripts/init.sh

# 4. 启动全部服务
./scripts/start.sh

# 5. 查看服务状态
./scripts/status.sh
```

---

## 目录结构

```text
middleware/
├── README.md                   # 项目说明
├── CHANGELOG.md                # 更新日志
├── LICENSE                     # 开源协议
├── .env                        # 环境变量（密码等敏感信息，不提交 Git）
├── .env.example                # 环境变量模板
├── .gitignore
├── docker-compose.yml          # 服务编排
│
├── scripts/                    # 管理脚本
│   ├── init.sh                 # 环境初始化
│   ├── start.sh                # 启动全部服务
│   ├── stop.sh                 # 停止全部服务
│   ├── restart.sh              # 重启全部服务
│   ├── status.sh               # 服务状态总览
│   ├── logs.sh                 # 查看日志
│   ├── doctor.sh               # 环境自检
│   ├── backup.sh               # 一键备份
│   ├── restore.sh              # 一键恢复
│   ├── update.sh               # 升级镜像
│   └── clean.sh                # 清理资源
│
├── postgres/                   # PostgreSQL 配置
│   ├── conf/
│   │   ├── postgresql.conf     # 主配置文件
│   │   ├── pg_hba.conf         # 访问控制
│   │   └── initdb/             # 初始化 SQL 脚本
│   └── data/                   # 持久化数据（运行时）
│
├── redis/                      # Redis 配置
│   └── data/                   # 持久化数据（运行时，含 AOF/RDB）
│
├── sentinel/                   # Sentinel Dashboard 配置
│   └── conf/
│       └── application.properties
│
├── nacos/                      # Nacos 配置
│   └── conf/
│
├── dokuwiki/                   # DokuWiki 数据
│   └── data/                   # 页面、配置、插件持久化
│
├── backups/                    # 备份文件
│   ├── postgres/
│   └── redis/
│
├── logs/                       # 运行日志
│
└── docs/                       # 文档
    ├── deployment.md           # 部署指南
    ├── backup.md               # 备份与恢复
    ├── upgrade.md              # 升级指南
    ├── troubleshooting.md      # 故障排查
    └── spring-boot.md          # Spring Boot 接入指南
```

---

## 包含的服务

| 服务 | 版本 | 端口 | 说明 |
|------|------|------|------|
| PostgreSQL | 18-alpine | 5432 | 关系型数据库 |
| Redis | 7-alpine | 6379 | 缓存 / 消息队列 |
| Sentinel Dashboard | latest | 8858 | 流量控制 / 熔断降级 |
| Nacos | v3.2.2 | 8080 / 9080 / 9081 | 注册中心 / 配置中心 |
| DokuWiki | latest | 8088 | 知识库 / Wiki |

> 后续规划：MinIO、RabbitMQ、Elasticsearch、Prometheus、Grafana、Ollama、Qdrant、Neo4j、Kafka 等。

---

## 常用命令

```bash
# 服务管理
./scripts/start.sh      # 启动所有服务
./scripts/stop.sh       # 停止所有服务
./scripts/restart.sh    # 重启所有服务
./scripts/status.sh     # 查看服务状态总览

# 日志
./scripts/logs.sh              # 查看所有服务日志
./scripts/logs.sh postgres     # 查看 PostgreSQL 日志
./scripts/logs.sh redis        # 查看 Redis 日志
./scripts/logs.sh sentinel     # 查看 Sentinel 日志
./scripts/logs.sh nacos        # 查看 Nacos 日志
./scripts/logs.sh dokuwiki     # 查看 DokuWiki 日志

# 备份恢复
./scripts/backup.sh            # 一键备份所有数据
./scripts/restore.sh           # 从最新备份恢复
./scripts/restore.sh 20260729  # 从指定日期备份恢复

# 运维
./scripts/update.sh            # 升级所有镜像
./scripts/update.sh postgres   # 升级 PostgreSQL 镜像
./scripts/doctor.sh            # 环境自检
./scripts/clean.sh             # 清理未使用的 Docker 资源
```

---

## 配置说明

所有可配置项集中在 `.env` 文件中：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `TZ` | 时区 | `Asia/Shanghai` |
| `POSTGRES_PORT` | PostgreSQL 端口 | `5432` |
| `POSTGRES_USER` | PostgreSQL 用户 | `admin` |
| `POSTGRES_PASSWORD` | PostgreSQL 密码 | 无，必须修改 |
| `POSTGRES_DB` | 默认数据库 | `middleware` |
| `REDIS_PORT` | Redis 端口 | `6379` |
| `REDIS_PASSWORD` | Redis 密码 | 无，必须修改 |
| `REDIS_MAXMEMORY` | Redis 最大内存 | `256mb` |
| `SENTINEL_PORT` | Sentinel Dashboard 端口 | `8858` |
| `SENTINEL_USERNAME` | Dashboard 登录用户名 | `sentinel` |
| `SENTINEL_PASSWORD` | Dashboard 登录密码 | `sentinel` |
| `NACOS_HTTP_PORT` | Nacos HTTP 端口 | `8080` |
| `NACOS_VERSION` | Nacos 镜像版本 | `v3.2.2` |
| `NACOS_AUTH_TOKEN` | Nacos JWT 签名密钥 | 必须修改 |
| `DOKUWIKI_PORT` | DokuWiki 端口 | `8088` |

---

## 安全建议

1. **立即修改密码**：`cp .env.example .env` 后编辑 `.env` 中所有 `change_me_*` 密码
2. **不要提交 .env**：`.gitignore` 已配置忽略 `.env` 文件
3. **生产环境建议**：
   - 使用更强的密码（至少 32 位随机字符串）
   - 限制端口暴露范围（仅内网可访问）
   - 定期备份并异地存储备份文件
   - 启用防火墙规则

---

## 扩展新服务

只需两步：

1. 在 `docker-compose.yml` 中添加新服务定义
2. 创建对应的配置目录（如 `minio/conf/`）

管理脚本会自动识别新服务，无需修改。

---

## 许可证

MIT License — 详见 [LICENSE](LICENSE)
