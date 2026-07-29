# 故障排查

## 快速诊断

遇到问题时，首先执行:

```bash
# 环境自检
./scripts/doctor.sh

# 查看服务状态
./scripts/status.sh

# 查看日志
./scripts/logs.sh
```

---

## 常见问题

### 1. 容器无法启动

**症状**: `./scripts/start.sh` 执行后容器反复重启

**排查**:
```bash
# 查看具体容器的日志
./scripts/logs.sh postgres
./scripts/logs.sh redis
```

**常见原因**:

#### a. 端口冲突
```bash
# 检查端口占用
lsof -i :5432
lsof -i :6379

# 解决: 修改 .env 中的端口号
POSTGRES_PORT=5433
REDIS_PORT=6380
```

#### b. 数据目录权限
```bash
# 检查权限
ls -la postgres/data/
ls -la redis/data/

# 修复
chmod 700 postgres/data/
chmod 700 redis/data/
```

#### c. 磁盘空间不足
```bash
df -h

# 清理
./scripts/clean.sh
docker system prune -a
```

---

### 2. PostgreSQL 连接拒绝

**症状**:
```
connection refused
FATAL: no pg_hba.conf entry for host
```

**排查**:
```bash
# 检查 PostgreSQL 是否运行
./scripts/status.sh

# 检查 pg_hba.conf
cat postgres/conf/pg_hba.conf

# 检查是否监听了正确地址
docker exec $(docker ps -qf name=postgres) pg_isready
```

**解决**: 如果从宿主机以外的 IP 连接，需要在 `pg_hba.conf` 中添加对应网段。

---

### 3. Redis 认证失败

**症状**:
```
NOAUTH Authentication required
WRONGPASS invalid username-password pair
```

**排查**:
```bash
# 检查密码是否一致
grep REDIS_PASSWORD .env

# 从容器内部测试
docker exec -it $(docker ps -qf name=redis) redis-cli -a $(grep REDIS_PASSWORD .env | cut -d'=' -f2) ping
```

**解决**: 确保 `.env` 中的 `REDIS_PASSWORD` 与连接时使用的密码一致。

---

### 4. 数据卷空间不足

**症状**: 容器日志中出现 "no space left on device"

**排查**:
```bash
# 查看 Docker 磁盘使用
docker system df

# 查看数据卷实际大小
docker system df -v | grep -A 5 "postgres-data\|redis-data"
```

**解决**:
```bash
# 清理未使用的 Docker 资源
./scripts/clean.sh

# 清理 Docker 构建缓存
docker builder prune -a -f

# 清理旧日志（PostgreSQL 容器内）
docker exec $(docker ps -qf name=postgres) bash -c "find /var/log/postgresql -name '*.log' -mtime +7 -delete"
```

---

### 5. 内存不足

**症状**: 容器被 OOM Killer 杀死，日志中出现 "Out of memory"

**排查**:
```bash
# 检查容器资源使用
docker stats --no-stream
```

**解决**:
- 减少 `REDIS_MAXMEMORY` 的值
- 减少 PostgreSQL 的 `shared_buffers`
- 增加宿主机内存或 swap

---

### 6. 容器间网络不通

**症状**: 应用无法连接到中间件

**排查**:
```bash
# 检查网络是否存在
docker network ls | grep middleware

# 检查容器是否在同一网络
docker network inspect docker-network

# 从应用容器测试连接
docker exec <app-container> ping postgres
docker exec <app-container> ping redis
```

---

### 7. 备份失败

**症状**: `./scripts/backup.sh` 报错

**原因排查**:
```bash
# 检查磁盘空间
df -h backups/

# 检查服务是否运行
./scripts/status.sh

# 手动测试备份命令
docker exec $(docker ps -qf name=postgres) pg_dumpall -U admin --no-password > /tmp/test_backup.sql
```

---

## 日志分析

### 关键日志位置

| 服务 | 日志位置 |
|------|---------|
| PostgreSQL | `docker logs postgres18` |
| Redis | `docker logs redis7` |
| PostgreSQL 容器内 | `/var/log/postgresql/` |
| Redis 容器内 | 输出到 stdout |

### PostgreSQL 慢查询

查找慢查询:
```bash
./scripts/logs.sh postgres | grep "duration"
```

查看 pg_stat_statements:
```sql
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Redis 慢日志

```bash
docker exec $(docker ps -qf name=redis) redis-cli -a <密码> SLOWLOG GET 10
```

---

## 性能调优检查

```bash
# 检查索引使用情况（PostgreSQL）
docker exec $(docker ps -qf name=postgres) psql -U admin -d middleware -c "
SELECT
    schemaname || '.' || relname AS table,
    seq_scan,
    idx_scan,
    CASE WHEN seq_scan + idx_scan = 0 THEN 0
         ELSE round(100.0 * idx_scan / (seq_scan + idx_scan), 1)
    END AS idx_scan_pct
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 10;
"

# 检查 Redis 内存碎片率
docker exec $(docker ps -qf name=redis) redis-cli -a <密码> INFO memory | grep mem_fragmentation_ratio
# 如果 > 1.5，考虑重启 Redis 整理内存
```

---

## 获取帮助

1. 先执行 `./scripts/doctor.sh` 获取诊断报告
2. 检查 `./scripts/logs.sh <service>` 查看完整日志
3. 查阅官方文档:
   - PostgreSQL: https://www.postgresql.org/docs/
   - Redis: https://redis.io/docs/
