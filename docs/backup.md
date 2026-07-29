# 备份与恢复

## 概述

备份系统支持:
- **PostgreSQL**: 使用 `pg_dumpall` 进行逻辑备份
- **Redis**: 触发 `BGSAVE` 后拷贝 RDB 文件
- 备份自动压缩（gzip）
- 元信息记录（metadata.json）
- 自动清理过期备份

---

## 备份

### 一键备份

```bash
./scripts/backup.sh
```

备份位置:
```
backups/
└── 2026-07-29/
    ├── postgres/
    │   └── postgres_20260729_143000.sql.gz
    ├── redis/
    │   └── redis_20260729_143000.rdb.gz
    └── metadata.json
```

### metadata.json 示例

```json
{
  "backup_time": "2026-07-29T14:30:00",
  "timestamp": "20260729_143000",
  "project": "middleware",
  "services": {
    "postgres": {
      "backed_up": true,
      "file": "postgres/postgres_20260729_143000.sql.gz",
      "size": "2.3 MB",
      "version": "18",
      "method": "pg_dumpall"
    },
    "redis": {
      "backed_up": true,
      "file": "redis/redis_20260729_143000.rdb.gz",
      "size": "0.5 MB",
      "version": "7",
      "method": "BGSAVE"
    }
  },
  "hostname": "my-server",
  "compress": true
}
```

### 不压缩备份

```bash
./scripts/backup.sh --no-compress
```

---

## 自动备份（crontab）

### Linux / macOS

```bash
# 编辑 crontab
crontab -e
```

添加:
```cron
# 每天凌晨 2:00 备份
0 2 * * * cd /path/to/middleware && ./scripts/backup.sh >> logs/backup-cron.log 2>&1
```

### 备份到远程存储

```bash
# 备份后同步到远程
./scripts/backup.sh && rsync -avz backups/ user@backup-server:/backups/middleware/
```

### 备份到云存储（rclone）

```bash
# 安装 rclone 并配置远程
# https://rclone.org/

# 备份后同步到 S3 / 腾讯云 COS / 阿里云 OSS
./scripts/backup.sh && rclone sync backups/ remote:bucket/middleware-backups/
```

---

## 恢复

### 查看可用备份

```bash
./scripts/restore.sh --list
```

输出示例:
```
  2026-07-29          15MB
    PostgreSQL: postgres/postgres_20260729_143000.sql.gz
    Redis: redis/redis_20260729_143000.rdb.gz

  2026-07-28          14MB
    PostgreSQL: postgres/postgres_20260728_020000.sql.gz
    Redis: redis/redis_20260728_020000.rdb.gz
```

### 从最新备份恢复

```bash
./scripts/restore.sh
```

### 从指定日期恢复

```bash
./scripts/restore.sh 2026-07-28
```

### 恢复流程

1. **安全备份**: 恢复前自动备份当前数据（防止误操作）
2. **确认**: 要求手动确认（防止意外恢复）
3. **停止服务**: 断开现有连接
4. **导入数据**: 恢复 PostgreSQL + Redis
5. **重启服务**: 重启容器并验证

---

## 备份策略建议

### 开发环境

- 频率: 手动备份，重要变更前
- 保留: 最近 7 天
- 配置: `BACKUP_RETENTION_DAYS=7`

### 测试环境

- 频率: 每天一次
- 保留: 最近 14 天
- 配置: `BACKUP_RETENTION_DAYS=14`

### 生产环境

- 频率: 每天一次 + 每小时 WAL 归档
- 保留: 本地 30 天 + 远程 90 天
- 建议额外配置 WAL 连续归档

---

## 故障恢复场景

### 场景 1: 误删数据

```bash
# 从昨天的备份恢复
./scripts/restore.sh $(date -v-1d +%Y-%m-%d)
```

### 场景 2: 数据库损坏

```bash
# 1. 停止所有服务
./scripts/stop.sh

# 2. 清除损坏的数据卷
docker volume rm postgres-data redis-data

# 3. 重建数据卷
docker volume create postgres-data
docker volume create redis-data

# 4. 启动服务
./scripts/start.sh

# 5. 恢复数据
./scripts/restore.sh
```

### 场景 3: 服务器迁移

```bash
# 在旧服务器上
./scripts/backup.sh
tar -czf middleware-backup.tar.gz backups/ .env

# 复制到新服务器
scp middleware-backup.tar.gz user@new-server:/opt/

# 在新服务器上
tar -xzf middleware-backup.tar.gz
cd middleware
./scripts/init.sh
./scripts/start.sh
./scripts/restore.sh
```
