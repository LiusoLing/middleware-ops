# Spring Boot 接入指南

## 概述

本指南说明如何让 Spring Boot 应用连接到 Middleware 项目中的 PostgreSQL 和 Redis。

---

## 1. 添加依赖

### Maven (pom.xml)

```xml
<!-- PostgreSQL -->
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>

<!-- Redis -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-redis</artifactId>
</dependency>

<!-- 连接池（推荐） -->
<dependency>
    <groupId>com.zaxxer</groupId>
    <artifactId>HikariCP</artifactId>
</dependency>

<!-- Redis 连接池 -->
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-pool2</artifactId>
</dependency>
```

### Gradle (build.gradle)

```groovy
dependencies {
    runtimeOnly 'org.postgresql:postgresql'
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'
    implementation 'org.apache.commons:commons-pool2'
}
```

---

## 2. 配置应用

### 方式一：通过 .env 文件统一管理（推荐）

Spring Boot 支持读取 `.env` 文件，配置一次即可:

#### 2.1 添加 dotenv 支持

```xml
<dependency>
    <groupId>me.paulschwarz</groupId>
    <artifactId>spring-dotenv</artifactId>
    <version>4.0.0</version>
</dependency>
```

#### 2.2 在 Spring Boot 项目根目录创建符号链接

```bash
# 在 Spring Boot 项目目录下
ln -s ../middleware/.env .env
```

#### 2.3 application.yml

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:${POSTGRES_PORT:5432}/${POSTGRES_DB:middleware}
    username: ${POSTGRES_USER:admin}
    password: ${POSTGRES_PASSWORD}
    driver-class-name: org.postgresql.Driver
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      idle-timeout: 300000
      connection-timeout: 20000
      max-lifetime: 1200000
      leak-detection-threshold: 60000

  data:
    redis:
      host: localhost
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD}
      database: 0
      lettuce:
        pool:
          max-active: 16
          max-idle: 8
          min-idle: 4
          max-wait: 2000ms
      timeout: 5000ms
```

### 方式二：手动指定

#### application.yml

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/middleware
    username: admin
    password: your-postgres-password
    driver-class-name: org.postgresql.Driver
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5

  data:
    redis:
      host: localhost
      port: 6379
      password: your-redis-password
      database: 0
      lettuce:
        pool:
          max-active: 16
          max-idle: 8
          min-idle: 4
```

---

## 3. Redis 配置类

```java
package com.example.config;

import org.springframework.cache.annotation.EnableCaching;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext;
import org.springframework.data.redis.serializer.StringRedisSerializer;

import java.time.Duration;

@Configuration
@EnableCaching
public class RedisConfig {

    @Bean
    public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory factory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(factory);

        // Key 序列化
        template.setKeySerializer(new StringRedisSerializer());
        template.setHashKeySerializer(new StringRedisSerializer());

        // Value 序列化（JSON）
        GenericJackson2JsonRedisSerializer jsonSerializer =
            new GenericJackson2JsonRedisSerializer();
        template.setValueSerializer(jsonSerializer);
        template.setHashValueSerializer(jsonSerializer);

        template.afterPropertiesSet();
        return template;
    }

    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory factory) {
        RedisCacheConfiguration config = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(30))
            .serializeKeysWith(
                RedisSerializationContext.SerializationPair
                    .fromSerializer(new StringRedisSerializer()))
            .serializeValuesWith(
                RedisSerializationContext.SerializationPair
                    .fromSerializer(new GenericJackson2JsonRedisSerializer()))
            .disableCachingNullValues();

        return RedisCacheManager.builder(factory)
            .cacheDefaults(config)
            .build();
    }
}
```

---

## 4. JPA 配置

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate   # 生产环境用 validate，开发环境用 update
    show-sql: false
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
        format_sql: true
        jdbc:
          batch_size: 50
          fetch_size: 100

  sql:
    init:
      mode: never   # 不自动执行 schema.sql，由 Flyway/Liquibase 管理
```

---

## 5. 数据库迁移（Flyway）

推荐使用 Flyway 管理数据库版本:

```xml
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
</dependency>
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-database-postgresql</artifactId>
</dependency>
```

SQL 迁移文件放在 `src/main/resources/db/migration/`:

```
db/migration/
├── V1__init_schema.sql
├── V2__add_user_table.sql
└── V3__add_indexes.sql
```

---

## 6. 健康检查

```java
package com.example.health;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class MiddlewareHealthIndicator implements HealthIndicator {

    private final JdbcTemplate jdbcTemplate;
    private final RedisConnectionFactory redisConnectionFactory;

    public MiddlewareHealthIndicator(JdbcTemplate jdbcTemplate,
                                      RedisConnectionFactory redisConnectionFactory) {
        this.jdbcTemplate = jdbcTemplate;
        this.redisConnectionFactory = redisConnectionFactory;
    }

    @Override
    public Health health() {
        Health.Builder builder = Health.up();

        // 检查 PostgreSQL
        try {
            jdbcTemplate.queryForObject("SELECT 1", Integer.class);
            builder.withDetail("postgresql", "connected");
        } catch (Exception e) {
            builder.down().withDetail("postgresql", "disconnected: " + e.getMessage());
            return builder.build();
        }

        // 检查 Redis
        try {
            var connection = redisConnectionFactory.getConnection();
            connection.ping();
            builder.withDetail("redis", "connected");
        } catch (Exception e) {
            builder.down().withDetail("redis", "disconnected: " + e.getMessage());
            return builder.build();
        }

        return builder.build();
    }
}
```

启用健康检查端点:
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: always
```

---

## 7. Docker Compose 整合（开发环境）

将 Spring Boot 应用也纳入 Middleware 管理:

```yaml
# docker-compose.yml 中添加
services:
  # ... PostgreSQL, Redis ...

  app:
    build: ../my-app
    container_name: my-app
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB:-middleware}
      SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER:-admin}
      SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD}
      SPRING_DATA_REDIS_HOST: redis
      SPRING_DATA_REDIS_PORT: 6379
      SPRING_DATA_REDIS_PASSWORD: ${REDIS_PASSWORD}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - docker-network
```

---

## 8. 多环境配置

### application-dev.yml（本地开发）

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/middleware
  data:
    redis:
      host: localhost
```

### application-prod.yml（生产环境）

```yaml
spring:
  datasource:
    url: jdbc:postgresql://postgres:5432/middleware
    hikari:
      maximum-pool-size: 50
      minimum-idle: 10
  data:
    redis:
      host: redis
      lettuce:
        pool:
          max-active: 32
          max-idle: 16
```

---

## 9. AI Agent 接入示例（Python）

不仅是 Spring Boot，AI Agent 也可以通过读取同一个 `.env` 文件连接:

```python
import os
import psycopg2
import redis
from dotenv import load_dotenv

# 加载 middleware 的 .env
load_dotenv('../middleware/.env')

# PostgreSQL
pg_conn = psycopg2.connect(
    host='localhost',
    port=os.getenv('POSTGRES_PORT', 5432),
    user=os.getenv('POSTGRES_USER', 'admin'),
    password=os.getenv('POSTGRES_PASSWORD'),
    database=os.getenv('POSTGRES_DB', 'middleware')
)

# Redis
redis_client = redis.Redis(
    host='localhost',
    port=int(os.getenv('REDIS_PORT', 6379)),
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True
)
```

---

## 10. SkyWalking 链路追踪接入

Middleware 已内置 SkyWalking 11.0.0 + Horizon UI：

- UI：<http://localhost:8801>（默认账号 `admin` / `admin`，请按 README 修改）
- Agent 上报地址：`localhost:11800`
- OAP HTTP API：<http://localhost:12800>
- OAP Admin API：<http://localhost:17128>

### 10.1 下载 Java Agent

以当前最新的 9.8.0 为例：

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
3. 启动应用后打开 <http://localhost:8801>，使用 `.env` 中 `HORIZON_AUTH_LOCAL_USERS` 配置的账号登录，在服务列表中应出现 `my-app`。

---

## 快速验证

```bash
# 1. 启动中间件
cd middleware && ./scripts/start.sh

# 2. 启动 Spring Boot 应用
cd my-app && ./mvnw spring-boot:run

# 3. 检查健康端点
curl http://localhost:8080/actuator/health
```
