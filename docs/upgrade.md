# 升级指南

## 概述

使用 `update.sh` 脚本可以安全地升级 Docker 镜像版本。

升级流程:
1. 自动备份当前数据
2. 拉取最新镜像
3. 重建并重启容器
4. 等待健康检查
5. 清理旧镜像

---

## 检查可用更新

```bash
./scripts/update.sh --check
```

这只会拉取最新镜像（不重启容器），确认版本后可手动执行升级。

---

## 升级所有服务

```bash
./scripts/update.sh
```

## 升级单个服务

```bash
# 升级 PostgreSQL
./scripts/update.sh postgres

# 升级 Redis
./scripts/update.sh redis
```

---

## 升级 PostgreSQL 大版本

PostgreSQL 大版本升级（如 17 → 18）需要额外步骤:

### 方式 1: 逻辑备份恢复（推荐，最安全）

```bash
# 1. 备份全部数据
./scripts/backup.sh

# 2. 停止并删除旧容器+数据卷
./scripts/stop.sh
docker volume rm postgres-data
docker volume create postgres-data

# 3. 修改 .env 中的版本号
# POSTGRES_VERSION=18

# 4. 启动新版本
./scripts/start.sh

# 5. 恢复数据
./scripts/restore.sh
```

### 方式 2: pg_upgrade（保留数据文件）

```bash
# 1. 备份（必须！）
./scripts/backup.sh

# 2. 进入容器执行 pg_upgrade
docker exec -it $(docker ps -qf name=postgres) bash
pg_upgrade -U admin \
  -d /var/lib/postgresql/data/pgdata \
  -D /var/lib/postgresql/data/pgdata_new \
  -b /usr/lib/postgresql/17/bin \
  -B /usr/lib/postgresql/18/bin
```

---

## 升级 Redis

Redis 升级相对简单:

```bash
# 修改 .env
# REDIS_VERSION=7.4

# 升级
./scripts/update.sh redis
```

因为 Redis 使用 RDB + AOF 持久化，数据会自动加载。

---

## 升级 SkyWalking 10.x → 11.x（不保留历史数据）

SkyWalking 11 引入了破坏性变更：

- 原内置 UI 被移除，改用独立发版的 **Horizon UI**（镜像 tag 形如 `horizon-<version>`，容器端口 8081）
- BanyanDB 需要 0.11 及以上版本（本项目使用 0.11.1）
- OAP 新增 Admin REST 端口 **17128**，Horizon UI 的模板同步、集群状态等功能依赖该端口

本项目已改用新的 BanyanDB 数据卷 `skywalking-banyandb-data-v11`，因此升级会从空数据启动，**旧追踪数据不会保留**。

### 1. 更新 `.env`

从 `.env.example` 复制新增配置，或手动确认以下变量：

```dotenv
SKYWALKING_VERSION=11.0.0
SKYWALKING_UI_VERSION=horizon-1.0.1
BANYANDB_VERSION=0.11.1
SKYWALKING_OAP_ADMIN_PORT=17128
HORIZON_AUTH_LOCAL_USERS='[{"username":"admin","passwordHash":"$argon2id$...","roles":["admin"]}]'
```

`HORIZON_AUTH_LOCAL_USERS` 是 Horizon UI 的登录用户列表，不能为空，否则无法登录。默认示例账号为 `admin` / `admin`，请务必按 `.env.example` 注释生成新的 Argon2id 哈希替换。

### 2. 停止旧版本

```bash
./scripts/stop.sh
```

> 旧数据卷 `skywalking-banyandb-data` 不再被使用，确认无需保留后可删除：
> `docker volume rm skywalking-banyandb-data`

### 3. 启动新版本

```bash
./scripts/start.sh
```

### 4. 验证

```bash
curl -f http://localhost:12800/healthcheck
curl -f http://localhost:17128/debugging/config/dump
curl -f http://localhost:8801/api/health
```

浏览器打开 <http://localhost:8801>，使用 `HORIZON_AUTH_LOCAL_USERS` 中的账号登录。

---

## 回滚

如果升级后出现问题:

### 回滚镜像版本

```bash
# 方式 1: 使用之前的备份恢复
./scripts/stop.sh
docker volume rm postgres-data redis-data
docker volume create postgres-data
docker volume create redis-data
./scripts/start.sh
./scripts/restore.sh <升级前的备份日期>

# 方式 2: 指定旧版本镜像
# 在 .env 中改回旧版本号，然后
./scripts/update.sh
```

### 从备份恢复（最可靠）

```bash
# 列出备份，找到升级前的备份
./scripts/restore.sh --list

# 恢复
./scripts/restore.sh 2026-07-28
```

---

## 升级清单

在执行升级前:

- [ ] 已创建最新备份 `./scripts/backup.sh`
- [ ] 确认备份文件完整（检查 `metadata.json`）
- [ ] 阅读了新版本的 Release Notes / Changelog
- [ ] 检查了 Breaking Changes
- [ ] 在测试环境先验证
- [ ] 通知团队成员
- [ ] 准备了回滚方案

---

## 定期更新流程（生产环境）

```bash
# 每月维护窗口
# 1. 通知团队
# 2. 全量备份
./scripts/backup.sh

# 3. 检查更新
./scripts/update.sh --check

# 4. 执行升级
./scripts/update.sh

# 5. 验证
./scripts/status.sh
./scripts/doctor.sh

# 6. 应用层健康检查
curl -f http://your-app/health || echo "需要检查应用"
```
