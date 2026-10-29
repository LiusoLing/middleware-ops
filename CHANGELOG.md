# Changelog

此项目的所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [1.3.0] - 2026-10-30

### Changed

- SkyWalking OAP 升级至 11.0.0（当前最新稳定版）
- SkyWalking UI 改用独立的 Horizon UI 1.0.1（镜像 tag `horizon-1.0.1`，容器端口 8081）
- BanyanDB 升级至 0.11.1（兼容 SkyWalking 11 的 BanyanDB API 0.11）
- OAP 新增 Admin REST 端口 17128，供 Horizon UI 的模板同步、集群状态、DSL 调试、Inspect 使用
- Horizon UI 新增本地登录认证，通过 `HORIZON_AUTH_LOCAL_USERS` 配置（默认 admin/admin，务必修改）
- `.env` 新增 `SKYWALKING_UI_VERSION`、`SKYWALKING_OAP_ADMIN_PORT`、`HORIZON_AUTH_LOCAL_USERS`

### Removed

- 旧版 SkyWalking UI（OAP 10.x 内置，容器端口 8080）
- 旧 BanyanDB 数据卷 `skywalking-banyandb-data`：升级使用新卷 `skywalking-banyandb-data-v11`，历史追踪数据不保留
- OAP 10.x 的 `SW_OAP_ADDRESS` UI 配置方式（由 Horizon 的 `HORIZON_OAP_QUERY_URL` / `HORIZON_OAP_ADMIN_URL` 取代）

---

## [1.2.0] - 2026-10-29

### Added

- SkyWalking OAP + UI 服务（10.3.0），UI 默认端口 8801
- BanyanDB 0.9.0 存储，数据持久化到命名卷 skywalking-banyandb-data
- OAP 暴露 11800（Agent gRPC）与 12800（HTTP API）
- .env 新增 SKYWALKING_*、BANYANDB_* 配置项
- docs/spring-boot.md 新增 SkyWalking Java Agent 接入指南

### Changed

- Sentinel Dashboard 默认镜像调整为 `ochh/sentinel-dashboard`

---

## [1.1.0] - 2026-07-29

### Added

- Sentinel Dashboard 服务（bladex/sentinel-dashboard），默认端口 8858
- Nacos 服务（nacos/nacos-server v3.2.2），默认端口 8080/9080/9081
- Nacos 集成 PostgreSQL 持久化，自动创建 nacos 数据库（003-nacos-db.sql）
- sentinel/conf/application.properties 配置文件
- DokuWiki 知识库服务（linuxserver/dokuwiki），默认端口 8088
- nacos/conf 配置目录
- 支持通过 .env 自定义用户名、密码和端口

---

## [1.0.0] - 2026-07-29

### Added

- 项目骨架搭建完成（目录结构、.env、docker-compose.yml）
- PostgreSQL 18-alpine 服务，生产级配置
- Redis 7-alpine 服务，AOF + RDB 持久化
- 管理脚本：init / start / stop / restart / status / logs
- 运维脚本：backup / restore / update / clean / doctor
- 环境自检脚本 doctor.sh
- PostgreSQL 自定义配置（postgresql.conf、pg_hba.conf）
- initdb 初始化脚本
- 完整文档：部署指南、备份恢复、升级、故障排查、Spring Boot 接入指南
- 统一 .env 环境变量管理

---

[1.0.0]: https://github.com/user/middleware/releases/tag/v1.0.0
