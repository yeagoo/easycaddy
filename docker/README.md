# Docker 容器化 RPM 仓库构建系统

自动构建、签名并托管 Caddy RPM 仓库的容器化方案。系统将 `build-repo.sh` 拆分为职责单一的容器，通过 Docker Compose 编排，支持无人值守的自动版本更新。

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

系统由 6 个容器组成，通过共享 Volume 传递数据：

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

辅助容器:
  volume-init ── 初始化 repo-data 卷权限（alpine，启动后立即退出）

Volume 关系:
  repo-data   ── volume-init (读写) / Builder (读写) / Signer (读写) / Repo Server (只读) / Scheduler (读写)
  gpg-keys    ── Signer (只读)
```

**容器职责：**

| 容器 | 类型 | 职责 |
|------|------|------|
| volume-init | 初始化（启动即退出） | 设置 `repo-data` 卷的文件权限（UID/GID 1500） |
| Builder | 一次性任务 | 执行 `build-repo.sh --stage build`，下载 Caddy 并构建 RPM 包 |
| Signer | 一次性任务 | 执行 `--stage sign` 和 `--stage publish`，GPG 签名并原子发布 |
| Repo Server | 常驻服务 | Caddy 静态文件服务，提供 HTTP/HTTPS 访问 |
| Scheduler | 常驻服务 | 按周期检查 Caddy 新版本，自动触发 Builder → Signer 构建链 |
| Repo Manager | 常驻服务（可选） | 管理 API，支持手动触发构建、回滚、状态查询 |

**容器依赖关系：**

```
volume-init → builder → signer
                          ↑
                      scheduler (定时触发)
```

- `volume-init` 最先运行，确保卷权限正确后退出
- `builder` 等待 `volume-init` 成功后启动
- `signer` 等待 `volume-init` 和 `builder` 都成功后启动
- `scheduler` 常驻运行，定时通过 Docker socket 触发 builder → signer

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

### 首次部署（完整流程）

```bash
# 1. 克隆仓库
git clone https://github.com/yourorg/caddy-rpm-repo.git && cd caddy-rpm-repo

# 2. 配置环境变量
cp docker/.env.example docker/.env
# 编辑 docker/.env，至少设置 GPG_KEY_ID 和 DOMAIN_NAME

# 3. 准备 GPG 密钥
mkdir -p gpg-keys
cp /path/to/your/private.gpg gpg-keys/
chmod 600 gpg-keys/private.gpg

# 4. 构建镜像
docker compose -f docker/docker-compose.yml build

# 5. 启动所有服务
docker compose -f docker/docker-compose.yml up -d

# 6. 查看服务状态
docker compose -f docker/docker-compose.yml ps -a
```

### 仅构建 RPM（不启动常驻服务）

如果只想构建 RPM 包，不需要启动 Repo Server 和 Scheduler：

```bash
# 构建镜像（首次或 Dockerfile 变更后）
docker compose -f docker/docker-compose.yml build builder signer

# 启动 builder（会自动先运行 volume-init）
docker compose -f docker/docker-compose.yml up -d builder

# 查看构建日志
docker compose -f docker/docker-compose.yml logs -f builder

# builder 成功后启动 signer 签名
docker compose -f docker/docker-compose.yml up -d signer
```

### 构建指定版本

默认情况下，builder 会自动查询 GitHub 获取最新 Caddy 版本。也可以在 `.env` 中指定版本：

```bash
# 方式 1：写入 .env 文件
echo "CADDY_VERSION=2.11.1" >> docker/.env

# 方式 2：命令行临时指定
CADDY_VERSION=2.11.1 docker compose -f docker/docker-compose.yml up -d builder
```

> **提示：** 显式指定版本号可以避免构建时依赖外网访问 GitHub API，推荐在网络受限环境中使用。

### `.env` 最小配置示例

```bash
# docker/.env
CADDY_VERSION=2.11.1               # 可选：留空则自动查询最新版本
GPG_KEY_ID=ABCDEF1234567890        # 必填：你的 GPG 密钥 ID
DOMAIN_NAME=rpms.example.com       # 你的域名
CHECK_INTERVAL=10d                 # 每 10 天检查一次新版本
```

---

## 详细配置

### 环境变量

所有环境变量通过 `docker/.env` 文件配置：

| 变量名 | 说明 | 默认值 | 必填 |
|--------|------|--------|------|
| `CADDY_VERSION` | Caddy 版本号，留空则自动查询最新版本（需外网） | 自动查询 | 否 |
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

以下命令均在项目根目录执行。为简洁起见，建议设置别名：

```bash
alias dc='docker compose -f docker/docker-compose.yml'
```

### 查看服务状态

```bash
# 查看所有容器状态（包括已退出的一次性容器）
dc ps -a

# 预期状态：
#   volume-init  — Exited (0)（正常，初始化完成即退出）
#   builder      — Exited (0)（正常，构建完成即退出）
#   signer       — Exited (0) 或 Created（等待 builder 完成）
#   repo-server  — Up（常驻）
#   scheduler    — Up（常驻）
```

### 重新构建镜像

修改 Dockerfile 或脚本后需要重新构建：

```bash
# 构建所有镜像
dc build

# 仅构建指定服务
dc build builder signer
```

### 手动触发构建

```bash
# 构建最新版本（自动查询 GitHub）
dc up -d builder
# 等待 builder 完成后
dc up -d signer

# 构建指定版本
CADDY_VERSION=2.11.1 dc up -d builder
# 等待 builder 完成后
dc up -d signer
```

### 查看构建日志

```bash
# 查看 builder 日志
dc logs builder

# 查看 signer 日志
dc logs signer

# 实时跟踪 scheduler 日志
dc logs -f scheduler

# 查看所有服务日志
dc logs
```

### 回滚到上一版本

```bash
# 通过管理 API 回滚（需启用 Repo Manager）
curl -X POST -H "Authorization: Bearer YOUR_API_TOKEN" http://localhost:8080/api/rollback

# 或直接在 signer 容器中执行
dc run --rm signer bash /app/build-repo.sh --rollback --output /repo
```

### 查看当前已构建版本

```bash
# 方式 1：读取版本状态文件
dc exec repo-server cat /srv/repo/caddy/.current-version

# 方式 2：通过管理 API 查询（需启用 Repo Manager）
curl -H "Authorization: Bearer YOUR_API_TOKEN" http://localhost:8080/api/status
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
dc up -d builder
# 等待完成后
dc up -d signer
```

### 完全清理重建

```bash
# 停止所有容器并删除卷（会丢失已构建的 RPM 包）
dc down -v

# 重新构建镜像并启动
dc build
dc up -d
```

---

## 故障排查

### Builder 退出码 3：版本查询 / 下载失败

**症状：** 日志显示 `查询 Caddy 版本失败: 无法访问 GitHub Releases API`

**原因：** 容器无法访问外网，或 GitHub API 限流。

**解决方法：**

```bash
# 方法 1（推荐）：在 .env 中指定版本号，跳过 GitHub API 查询
echo "CADDY_VERSION=2.11.1" >> docker/.env

# 方法 2：配置 GitHub Token 避免限流
echo "GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx" >> docker/.env
```

### Builder 退出码 1：权限被拒绝

**症状：** 日志显示 `Permission denied` 写入 `/repo`

**原因：** `repo-data` 卷的所有权不正确。`volume-init` 容器负责设置权限，可能未正常运行。

**解决方法：**

```bash
# 检查 volume-init 是否成功
dc ps -a | grep volume-init
# 应显示 Exited (0)

# 如果 volume-init 失败，手动修复卷权限
docker run --rm -v docker_repo-data:/repo alpine chown -R 1500:1500 /repo

# 或者清理卷重新开始
dc down -v
dc up -d
```

### 签名失败

**症状：** Signer 容器以非零退出码退出。

```bash
dc logs signer
```

| 问题 | 原因 | 解决方法 |
|------|------|---------|
| 权限错误拒绝启动 | GPG 密钥文件权限不是 600 或 400 | `chmod 600 gpg-keys/private.gpg` |
| 密钥导入失败 | 密钥文件损坏或格式错误 | 重新导出：`gpg --export-secret-keys KEY_ID > gpg-keys/private.gpg` |
| 签名失败 | GPG_KEY_ID 与密钥文件不匹配 | 确认 `.env` 中的 `GPG_KEY_ID` 与密钥一致 |

### 证书获取失败

**症状：** Repo Server 启动后 HTTPS 不可用。

```bash
dc logs repo-server
```

| 问题 | 解决方法 |
|------|---------|
| 域名未解析到服务器 IP | 检查 DNS 记录 |
| 端口 80/443 被占用 | 停止占用端口的服务，或修改端口映射 |
| 防火墙阻止 ACME 验证 | 开放 80 和 443 端口 |
| 使用 `localhost` 域名 | Caddy 对 `localhost` 使用自签名证书，这是正常行为 |

### 磁盘空间不足

```bash
# 查看 Docker 磁盘使用
docker system df

# 清理未使用的资源
docker system prune -f
docker builder prune -f
```

---

## 客户端配置

### 使用 install-caddy.sh（推荐）

```bash
curl -fsSL https://rpms.example.com/caddy/templates/install-caddy.sh | bash -s -- --mirror https://rpms.example.com
```

### 手动配置 .repo 文件

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

配置完成后安装：

```bash
rpm --import https://rpms.example.com/caddy/gpg.key
dnf install caddy
```

---

## 安全注意事项

### 容器用户与卷权限

- Builder 和 Signer 容器使用统一的 UID/GID（1500），确保对共享卷 `repo-data` 的读写权限一致
- `volume-init` 容器在每次启动时以 root 身份运行 `chown -R 1500:1500 /repo`，确保卷权限正确
- 所有业务容器以非 root 用户运行

### GPG 密钥管理

- GPG 私钥文件权限**必须**设置为 `600` 或 `400`
- 私钥通过独立的 `gpg-keys` Volume 挂载，仅 Signer 容器可访问（只读）
- Builder、Repo Server、Scheduler 容器**无法**访问 GPG 密钥
- 建议将 `gpg-keys/` 目录加入 `.gitignore`

### Docker Socket 风险

Scheduler 和 Repo Manager 挂载了 Docker socket（`/var/run/docker.sock`）：

- 这两个容器拥有宿主机级别的 Docker 控制权限
- **缓解措施：**
  - 配置了 `no-new-privileges:true`
  - 运行在隔离的 `internal` 网络中
  - Repo Manager 需要 Bearer Token 认证
  - 不需要自动构建时可不启动 Scheduler
  - Repo Manager 默认不启动（需 `--profile management`）

### 网络隔离

| 网络 | 类型 | 连接的容器 |
|------|------|-----------|
| `internal` | bridge (internal) | 所有容器（不可访问外部网络） |
| `external` | bridge | Builder、Repo Server、Repo Manager |

- Builder 连接 `external` 网络以访问 GitHub API 和 Caddy 下载服务器
- Signer 仅连接 `internal` 网络，无法访问外网
- 所有容器配置了 `no-new-privileges:true`
- Builder 和 Signer 使用只读文件系统（`read_only: true`），仅允许写入 Volume 和 tmpfs
- Builder 和 Signer 丢弃所有 Linux capabilities（`cap_drop: ALL`）
