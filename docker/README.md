# Docker 容器化 RPM 仓库构建系统

自动构建、签名并托管 Caddy RPM 仓库的容器化方案。系统将 `build-repo.sh` 拆分为 5 个职责单一的容器，通过 Docker Compose 编排，支持无人值守的自动版本更新。

## 目录

- [系统架构](#系统架构)
- [前置条件](#前置条件)
- [快速开始](#快速开始)
- [详细配置](#详细配置)
- [运维操作](#运维操作)
- [故障排查](#故障排查)
- [客户端配置](#客户端配置)
- [安全注意事项](#安全注意事项)

---

## 系统架构

系统由 5 个容器组成，通过共享 Volume 传递数据：

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Scheduler   │────▶│   Builder    │────▶│   Signer     │
│ (定时检查)   │     │ (构建 RPM)   │     │ (GPG 签名)   │
│ 常驻服务     │     │ 一次性任务   │     │ 一次性任务   │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       │ Docker         写入 .staging/      签名 + 原子发布
       │ socket             │                    │
       │              ┌─────▼────────────────────▼─────┐
       └─────────────▶│         repo-data Volume       │
                      │  .staging/ → caddy/（原子交换） │
                      │  .current-version（版本状态）   │
                      └─────┬──────────────────────────┘
                            │ (只读挂载)
                      ┌─────▼──────┐     ┌──────────────┐
                      │Repo Server │     │ Repo Manager │
                      │  (Caddy)   │     │ (管理 API)   │
                      │  :80/:443  │     │   :8080      │
                      └────────────┘     └──────────────┘
                            │                    │
                      ┌─────▼────────────────────▼─────┐
                      │           客户端 / 管理员       │
                      └────────────────────────────────┘

Volume 关系:
  repo-data   ── Builder (读写) / Signer (读写) / Repo Server (只读) / Scheduler (读写)
  gpg-keys    ── Signer (只读)
```

**容器职责：**

| 容器 | 类型 | 职责 |
|------|------|------|
| Builder | 一次性任务 | 执行 `build-repo.sh --stage build`，构建 RPM 包 |
| Signer | 一次性任务 | 执行 `--stage sign` 和 `--stage publish`，GPG 签名并原子发布 |
| Repo Server | 常驻服务 | Caddy 静态文件服务，提供 HTTP/HTTPS 访问 |
| Scheduler | 常驻服务 | 按周期检查 Caddy 新版本，自动触发构建 |
| Repo Manager | 常驻服务（可选） | 管理 API，支持手动触发构建、回滚、状态查询 |

---

## 前置条件

### 软件要求

- **Docker Engine** >= 24.0
- **Docker Compose** v2（`docker compose` 命令，非旧版 `docker-compose`）

验证安装：

```bash
docker --version          # Docker version 24.0+
docker compose version    # Docker Compose version v2.x
```

### GPG 密钥准备

系统使用 GPG 密钥对 RPM 包和仓库元数据进行签名。部署前需准备密钥：

1. **生成 GPG 密钥**（如果还没有）：

```bash
gpg --full-generate-key
# 选择 RSA and RSA，密钥长度 4096，按提示填写信息
```

2. **导出私钥到文件**：

```bash
# 查看密钥 ID
gpg --list-secret-keys --keyid-format LONG

# 导出私钥（替换为你的密钥 ID）
gpg --export-secret-keys YOUR_KEY_ID > gpg-keys/private.gpg
```

3. **设置文件权限**（必须为 600 或 400，否则 Signer 容器拒绝启动）：

```bash
mkdir -p gpg-keys
chmod 600 gpg-keys/private.gpg
```

---

## 快速开始

从克隆仓库到 RPM 仓库可用，只需 5 步：

```bash
# 1. 克隆仓库
git clone https://github.com/yourorg/caddy-rpm-repo.git && cd caddy-rpm-repo

# 2. 配置环境变量
cp docker/.env.example docker/.env
# 编辑 docker/.env，至少设置 GPG_KEY_ID 和 DOMAIN_NAME

# 3. 准备 GPG 密钥（将私钥放入 gpg-keys 目录）
mkdir -p gpg-keys && cp /path/to/your/private.gpg gpg-keys/ && chmod 600 gpg-keys/private.gpg

# 4. 构建并启动服务
docker compose -f docker/docker-compose.yml up -d

# 5. 验证服务运行
docker compose -f docker/docker-compose.yml ps
```

`.env` 配置示例：

```bash
# docker/.env
GPG_KEY_ID=ABCDEF1234567890        # 必填：你的 GPG 密钥 ID
DOMAIN_NAME=rpms.example.com       # 你的域名
CHECK_INTERVAL=10d                 # 每 10 天检查一次新版本
```

启动后，Scheduler 会立即执行一次版本检查并触发首次构建。构建完成后，RPM 仓库即可通过 `https://rpms.example.com` 访问。

---

## 详细配置

### 环境变量

所有环境变量通过 `docker/.env` 文件配置：

| 变量名 | 说明 | 默认值 | 必填 |
|--------|------|--------|------|
| `CADDY_VERSION` | Caddy 版本号，留空则自动查询最新版本 | 自动查询 | 否 |
| `TARGET_ARCH` | 目标架构（`x86_64`、`aarch64`、`all`） | `all` | 否 |
| `TARGET_DISTRO` | 目标发行版（`distro:version,...`、`all`） | `all` | 否 |
| `BASE_URL` | `.repo` 模板中的基础 URL | `https://rpms.example.com` | 否 |
| `GPG_KEY_ID` | GPG 签名密钥 ID | — | 是 |
| `DOMAIN_NAME` | Caddy 服务域名（用于自动 HTTPS） | `localhost` | 否 |
| `CHECK_INTERVAL` | Scheduler 检查新版本的周期 | `10d` | 否 |
| `GITHUB_TOKEN` | GitHub API 认证令牌（避免匿名限流 60 次/小时） | — | 否 |
| `API_TOKEN` | Repo Manager API 认证令牌 | — | 是（启用管理 API 时） |
| `MANAGER_PORT` | Repo Manager 监听端口 | `8080` | 否 |

### CHECK_INTERVAL 格式

| 格式 | 示例 | 含义 |
|------|------|------|
| `Nd` | `10d` | 每 N 天检查一次 |
| `Nh` | `12h` | 每 N 小时检查一次 |

### 启用管理 API（可选）

Repo Manager 默认不启动。启用方式：

```bash
# 设置 API_TOKEN 后，使用 management profile 启动
docker compose -f docker/docker-compose.yml --profile management up -d
```

### CI/CD 模式

在 CI/CD 环境中，可使用覆盖文件禁用常驻服务，仅运行构建和签名：

```bash
# 仅执行构建
docker compose -f docker/docker-compose.yml -f docker/docker-compose.ci.yml run --rm builder
echo $?  # 退出码传播到 CI/CD 流水线

# 仅执行签名和发布
docker compose -f docker/docker-compose.yml -f docker/docker-compose.ci.yml run --rm signer
```

---

## 运维操作

以下命令均在项目根目录执行，使用 `-f docker/docker-compose.yml` 指定编排文件。为简洁起见，后续示例省略 `-f` 参数，你可以设置别名：

```bash
alias dc='docker compose -f docker/docker-compose.yml'
```

### 手动触发构建

```bash
# 构建最新版本
dc run --rm builder
dc run --rm signer

# 构建指定版本
dc run --rm -e CADDY_VERSION=2.9.1 builder
dc run --rm -e CADDY_VERSION=2.9.1 signer
```

### 回滚到上一版本

```bash
# 通过管理 API 回滚（需启用 Repo Manager）
curl -X POST -H "Authorization: Bearer YOUR_API_TOKEN" http://localhost:8080/api/rollback

# 或直接在 signer 容器中执行
dc run --rm signer bash /app/build-repo.sh --rollback --output /repo
```

### 查看构建日志

```bash
# 查看所有服务日志
dc logs

# 查看特定服务日志
dc logs scheduler
dc logs builder
dc logs signer

# 实时跟踪日志
dc logs -f scheduler
```

### 查看当前已构建版本

```bash
# 方式 1：读取版本状态文件
docker compose -f docker/docker-compose.yml exec repo-server cat /srv/repo/caddy/.current-version

# 方式 2：通过管理 API 查询（需启用 Repo Manager）
curl -H "Authorization: Bearer YOUR_API_TOKEN" http://localhost:8080/api/status
# 返回: {"last_build_time":"...","version":"2.9.1","status":"success"}
```

### 修改检查周期

编辑 `docker/.env`：

```bash
CHECK_INTERVAL=6h    # 改为每 6 小时检查一次
```

重启 Scheduler 使配置生效：

```bash
dc restart scheduler
```

### 更换 GPG 密钥

```bash
# 1. 导出新密钥
gpg --export-secret-keys NEW_KEY_ID > gpg-keys/private.gpg
chmod 600 gpg-keys/private.gpg

# 2. 更新 .env 中的 GPG_KEY_ID
# GPG_KEY_ID=NEW_KEY_ID

# 3. 重新执行一次完整构建（使用新密钥重新签名所有包）
dc run --rm builder
dc run --rm signer
```

### 更换域名

```bash
# 1. 更新 .env 中的 DOMAIN_NAME
# DOMAIN_NAME=new-rpms.example.com

# 2. 如果 BASE_URL 也需要更新
# BASE_URL=https://new-rpms.example.com

# 3. 重启 Repo Server（Caddy 会自动为新域名获取证书）
dc restart repo-server

# 4. 重新构建以更新 .repo 模板中的 URL
dc run --rm builder
dc run --rm signer
```

---

## 故障排查

### 构建失败

**症状：** Builder 容器以非零退出码退出。

**排查步骤：**

```bash
# 查看构建日志
dc logs builder
```

**常见原因及解决方法：**

| 退出码 | 原因 | 解决方法 |
|--------|------|---------|
| 2 | 构建依赖缺失 | 检查 Dockerfile 中的依赖安装是否完整，重新构建镜像 |
| 3 | 下载失败 / 版本查询失败 | 检查网络连接，确认 GitHub API 可访问 |
| 4 | nfpm 打包失败 | 检查 `packaging/` 目录中的配置文件 |

```bash
# 重新构建镜像
dc build builder

# 重试构建
dc run --rm builder
```

### 签名失败

**症状：** Signer 容器以非零退出码退出。

**排查步骤：**

```bash
dc logs signer
```

**常见原因及解决方法：**

| 问题 | 原因 | 解决方法 |
|------|------|---------|
| 权限错误拒绝启动 | GPG 密钥文件权限不是 600 或 400 | `chmod 600 gpg-keys/private.gpg` |
| 密钥导入失败 | 密钥文件损坏或格式错误 | 重新导出密钥：`gpg --export-secret-keys KEY_ID > gpg-keys/private.gpg` |
| 签名失败 | GPG_KEY_ID 与密钥文件不匹配 | 确认 `.env` 中的 `GPG_KEY_ID` 与导出的密钥 ID 一致 |

### API 限流

**症状：** Scheduler 日志中出现 `GitHub API 查询失败`。

**原因：** GitHub API 匿名访问限制为 60 次/小时。

**解决方法：**

```bash
# 在 .env 中配置 GitHub Token
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# 重启 Scheduler
dc restart scheduler
```

配置 Token 后，API 限制提升至 5000 次/小时。

### 证书获取失败

**症状：** Repo Server 启动后 HTTPS 不可用。

**排查步骤：**

```bash
dc logs repo-server
```

**常见原因及解决方法：**

| 问题 | 解决方法 |
|------|---------|
| 域名未解析到服务器 IP | 检查 DNS 记录，确保域名指向正确的 IP |
| 端口 80/443 被占用 | 停止占用端口的服务，或修改端口映射 |
| 防火墙阻止 ACME 验证 | 开放 80 和 443 端口的入站流量 |
| 使用 `localhost` 域名 | Caddy 对 `localhost` 使用自签名证书，这是正常行为 |

### 磁盘空间不足

**症状：** 构建失败，日志中出现磁盘空间相关错误。

**排查步骤：**

```bash
# 查看 Docker 磁盘使用
docker system df

# 查看 Volume 使用情况
docker volume ls
```

**解决方法：**

```bash
# 清理未使用的 Docker 资源
docker system prune -f

# 清理未使用的 Volume（谨慎操作）
docker volume prune -f

# 清理旧的构建镜像缓存
docker builder prune -f
```

---

## 客户端配置

### 使用 install-caddy.sh（推荐）

最简单的方式是使用 `install-caddy.sh` 脚本的 `--mirror` 参数：

```bash
# 使用自建仓库安装 Caddy
curl -fsSL https://rpms.example.com/caddy/templates/install-caddy.sh | bash -s -- --mirror https://rpms.example.com
```

脚本会自动配置 `.repo` 文件、导入 GPG 公钥并安装 Caddy。

### 手动配置 .repo 文件

如果需要手动配置，根据你的发行版创建对应的 `.repo` 文件：

**RHEL / CentOS / Rocky Linux / AlmaLinux 8：**

```ini
# /etc/yum.repos.d/caddy.repo
[caddy]
name=Caddy RPM Repository
baseurl=https://rpms.example.com/caddy/el8/$basearch
enabled=1
gpgcheck=1
gpgkey=https://rpms.example.com/caddy/gpg.key
```

**RHEL / CentOS / Rocky Linux / AlmaLinux 9：**

```ini
# /etc/yum.repos.d/caddy.repo
[caddy]
name=Caddy RPM Repository
baseurl=https://rpms.example.com/caddy/el9/$basearch
enabled=1
gpgcheck=1
gpgkey=https://rpms.example.com/caddy/gpg.key
```

**Fedora：**

```ini
# /etc/yum.repos.d/caddy.repo
[caddy]
name=Caddy RPM Repository
baseurl=https://rpms.example.com/caddy/fedora$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://rpms.example.com/caddy/gpg.key
```

配置完成后安装 Caddy：

```bash
# 导入 GPG 公钥
rpm --import https://rpms.example.com/caddy/gpg.key

# 安装 Caddy
dnf install caddy
```

---

## 安全注意事项

### GPG 密钥管理

- GPG 私钥文件权限**必须**设置为 `600` 或 `400`，否则 Signer 容器拒绝启动
- 私钥通过独立的 `gpg-keys` Volume 挂载，仅 Signer 容器可访问（只读）
- Builder、Repo Server、Scheduler 容器**无法**访问 GPG 密钥
- Signer 容器在退出时自动清除内存中的 GPG 密钥材料（`gpgconf --kill gpg-agent` + `rm -rf ~/.gnupg`）
- 建议将 `gpg-keys/` 目录加入 `.gitignore`，避免密钥被提交到版本控制

### Docker Socket 风险

Scheduler 和 Repo Manager 容器挂载了 Docker socket（`/var/run/docker.sock`），用于启动 Builder 和 Signer 容器。这意味着：

- 这两个容器拥有**宿主机级别的 Docker 控制权限**
- 恶意代码可能通过 Docker socket 逃逸到宿主机
- **缓解措施：**
  - 两个容器均配置了 `no-new-privileges:true`
  - 容器运行在隔离的 `internal` 网络中，不暴露端口到外部
  - Repo Manager 需要 Bearer Token 认证才能执行操作
  - 如果不需要自动构建，可以不启动 Scheduler，改为手动触发
  - 如果不需要管理 API，Repo Manager 默认不启动（需 `--profile management`）

### 网络隔离

系统定义了两个 Docker 网络：

| 网络 | 类型 | 说明 |
|------|------|------|
| `internal` | bridge (internal) | 容器间内部通信，**不可访问外部网络** |
| `external` | bridge | 仅 Repo Server 和 Repo Manager 连接，用于对外提供服务 |

- Builder 和 Signer 仅连接 `internal` 网络，无法直接访问互联网（Builder 通过 Scheduler 触发时由 Scheduler 的网络环境提供连接）
- 所有容器配置了 `no-new-privileges:true` 安全选项
- Builder 和 Signer 容器使用只读文件系统（`read_only: true`），仅允许写入指定的 Volume 和 tmpfs
- Builder 和 Signer 容器丢弃所有 Linux capabilities（`cap_drop: ALL`）
- 所有容器以非 root 用户运行
