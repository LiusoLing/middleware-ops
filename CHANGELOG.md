# Changelog

此项目的所有重要变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

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
