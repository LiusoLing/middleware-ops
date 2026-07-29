# 部署指南

## 环境要求

| 组件 | 最低版本 | 推荐版本 |
|------|---------|---------|
| Docker | 24.0+ | 27.0+ |
| Docker Compose | v2.20+ | v2.30+ |
| 操作系统 | macOS 12+ / Ubuntu 22.04+ | macOS 15+ / Ubuntu 24.04+ |
| 内存 | 2 GB | 4 GB+ |
| 磁盘 | 10 GB 可用 | 20 GB+ (SSD) |

---

## 安装 Docker

### macOS

```bash
brew install --cask docker
```

或从官网下载: https://www.docker.com/products/docker-desktop

### Ubuntu / Debian

```bash
# 官方脚本（推荐）
curl -fsSL https://get.docker.com | bash

# 添加当前用户到 docker 组（免 sudo）
sudo usermod -aG docker $USER
newgrp docker

# 安装 Docker Compose 插件
sudo apt-get install docker-compose-plugin
```

### CentOS / RHEL / Fedora

```bash
sudo dnf install docker docker-compose-plugin
sudo systemctl enable docker --now
```

---

## 快速部署

### 1. 获取项目

```bash
git clone <repo-url> middleware
cd middleware
```

### 2. 配置环境变量

```bash
cp .env.example .env
vim .env
```

**必须修改的配置:**

```ini
POSTGRES_PASSWORD=<生成一个强密码>
REDIS_PASSWORD=<生成一个强密码>
```

生成强密码:
```bash
# 方式 1: openssl
openssl rand -base64 32

# 方式 2: /dev/urandom
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32

# 方式 3: uuidgen
uuidgen
```

### 3. 初始化环境

```bash
./scripts/init.sh
```

这个脚本会:
- 检查 Docker 环境
- 创建必要的目录
- 拉取镜像
- 创建 Docker 网络

### 4. 启动服务

```bash
./scripts/start.sh
```

### 5. 验证

```bash
./scripts/status.sh
./scripts/doctor.sh
```

---

## 验证连接

### PostgreSQL

```bash
# 通过 docker exec
./scripts/logs.sh postgres

# 通过 psql 客户端（需本地安装）
psql -h localhost -p 5432 -U admin -d middleware
# 输入 .env 中的 POSTGRES_PASSWORD
```

### Redis

```bash
# 通过 redis-cli
docker exec -it $(docker ps -qf name=redis) redis-cli -a <密码> ping
# 应返回 PONG
```

---

## 不同环境的配置建议

### 开发环境（本地 Macbook）

```ini
# .env 开发配置
POSTGRES_SHM_SIZE=128mb
REDIS_MAXMEMORY=128mb
```

### 测试环境（云服务器 2C4G）

```ini
# .env 测试配置
POSTGRES_SHM_SIZE=256mb
REDIS_MAXMEMORY=512mb
```

同时调整 `postgresql.conf`:
```ini
shared_buffers = '1GB'
effective_cache_size = '3GB'
maintenance_work_mem = '256MB'
```

### 生产环境（云服务器 4C8G+）

```ini
# .env 生产配置
POSTGRES_SHM_SIZE=512mb
REDIS_MAXMEMORY=2gb
REDIS_MAXMEMORY_POLICY=allkeys-lru
```

同时调整 `postgresql.conf`:
```ini
shared_buffers = '2GB'
effective_cache_size = '6GB'
maintenance_work_mem = '512MB'
work_mem = '32MB'
max_connections = 300
```

---

## 防火墙配置

### 内网部署（推荐）

只允许内网访问数据库端口:

```bash
# UFW (Ubuntu)
sudo ufw allow from 10.0.0.0/8 to any port 5432
sudo ufw allow from 10.0.0.0/8 to any port 6379
sudo ufw enable
```

### 仅本机访问

```yaml
# docker-compose.yml 修改
ports:
  - "127.0.0.1:${POSTGRES_PORT:-5432}:5432"
```

---

## 开机自启

服务默认配置了 `restart: unless-stopped`，Docker 启动时自动恢复。

配置 Docker 开机自启:
```bash
sudo systemctl enable docker
```

验证:
```bash
sudo systemctl is-enabled docker
```

---

## 卸载

```bash
# 停止并删除所有容器和网络
./scripts/stop.sh

# 删除数据卷（⚠️ 所有数据将丢失！）
docker volume rm postgres-data redis-data

# 删除项目目录
cd ..
rm -rf middleware
```
