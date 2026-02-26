# 使用说明

本项目提供两种方式构建和维护 Caddy RPM 自建仓库：**直接运行脚本**（适合手动操作或已有服务器环境）和 **Docker 容器化部署**（适合自动化运维和无人值守场景）。

---

## 一、项目概览

系统核心是 `build-repo.sh` 脚本，负责：

- 从 GitHub 下载 Caddy 二进制文件
- 使用 nfpm 打包为 RPM（7 条产品线 × 2 架构 = 14 个包）
- 生成 repodata 元数据和符号链接（覆盖 28+ 个发行版路径）
- GPG 签名 RPM 包和 repomd.xml
- 原子发布到正式目录，自动保留 3 个回滚备份

Docker 容器化方案将上述流程拆分为 5 个容器，通过 Docker Compose 编排，支持定时自动更新。

---

## 二、方式一：直接运行脚本

适合在已有 Fedora/CentOS 服务器上手动操作。

### 前置依赖

| 工具 | 安装方式 |
|------|---------|
| curl | `dnf install curl` |
| nfpm | [nfpm.goreleaser.com/install](https://nfpm.goreleaser.com/install/) |
| createrepo_c | `dnf install createrepo_c` |
| gnupg2 | `dnf install gnupg2` |
| rpm | `dnf install rpm` |

### 快速开始

```bash
# 构建全部产品线（自动查询最新 Caddy 版本）
bash build-repo.sh --gpg-key-id YOUR_KEY_ID --output ./repo

# 指定版本构建
bash build-repo.sh --version 2.9.0 --gpg-key-id YOUR_KEY_ID --output ./repo
```

构建完成后，`stdout` 输出仓库根目录绝对路径，`stderr` 输出构建摘要。

### 常用命令

```bash
# 仅构建指定发行版
bash build-repo.sh --version 2.9.0 --distro anolis:8,openEuler:22

# 仅构建 x86_64 架构
bash build-repo.sh --version 2.9.0 --arch x86_64 --gpg-key-id YOUR_KEY_ID

# 分阶段执行（适合 CI/CD）
bash build-repo.sh --version 2.9.0 --gpg-key-file /path/to/key.gpg --stage build
bash build-repo.sh --stage sign
bash build-repo.sh --stage publish
bash build-repo.sh --stage verify

# 回滚到上一版本
bash build-repo.sh --rollback
```

### 命令行参数一览

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--version <VER>` | Caddy 版本号 | 自动查询最新 |
| `--output <DIR>` | 仓库输出目录 | `./repo` |
| `--gpg-key-id <ID>` | GPG 密钥 ID | — |
| `--gpg-key-file <PATH>` | GPG 私钥文件（CI/CD 用） | — |
| `--arch <ARCH>` | 目标架构：`x86_64`/`aarch64`/`all` | `all` |
| `--distro <SPEC>` | 目标发行版 | `all` |
| `--base-url <URL>` | .repo 模板基础 URL | `https://rpms.example.com` |
| `--stage <STAGE>` | 执行阶段：`build`/`sign`/`publish`/`verify` | 全部 |
| `--rollback` | 回滚到最近备份 | — |
| `--sm2-key <PATH>` | SM2 私钥（国密，可选） | — |

### 离线构建

```bash
# 有网络的机器上预下载
bash vendor-download.sh --version 2.9.0

# 离线机器上构建（自动使用 vendor/ 中的文件）
bash build-repo.sh --version 2.9.0 --gpg-key-id YOUR_KEY_ID
```

### 托管仓库

构建产物是纯静态文件，任何 Web 服务器都可以托管：

```
# Caddy 示例
rpms.yoursite.com {
    root * /path/to/repo
    file_server browse
}
```

### 退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | 参数错误 |
| 2 | 依赖缺失 |
| 3 | 下载失败 |
| 4 | 打包失败 |
| 5 | 签名失败 |
| 6 | 元数据生成失败 |
| 7 | 发布失败 |
| 8 | 验证失败 |

---

## 三、方式二：Docker 容器化部署

适合需要自动化更新和长期运维的场景。系统拆分为 5 个容器：

| 容器 | 类型 | 职责 |
|------|------|------|
| Builder | 一次性任务 | 构建 RPM 包 |
| Signer | 一次性任务 | GPG 签名并原子发布 |
| Repo Server | 常驻服务 | Caddy 静态文件服务（HTTP/HTTPS） |
| Scheduler | 常驻服务 | 定时检查新版本，自动触发构建 |
| Repo Manager | 常驻服务（可选） | 管理 API（手动构建、回滚、状态查询） |

### 架构图

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Scheduler   │────▶│   Builder    │────▶│   Signer     │
│ (定时检查)   │     │ (构建 RPM)   │     │ (GPG 签名)   │
└──────────────┘     └──────┬───────┘     └──────┬───────┘
                            │                    │
                      ┌─────▼────────────────────▼─────┐
                      │         repo-data Volume       │
                      └─────┬──────────────────────────┘
                            │ (只读挂载)
                      ┌─────▼──────┐     ┌──────────────┐
                      │Repo Server │     │ Repo Manager │
                      │  :80/:443  │     │   :8080      │
                      └────────────┘     └──────────────┘
```

### 前置条件

- Docker Engine >= 24.0
- Docker Compose v2（`docker compose` 命令）

```bash
docker --version          # 确认 24.0+
docker compose version    # 确认 v2.x
```

### 快速开始（5 步）

```bash
# 1. 克隆仓库
git clone https://github.com/yourorg/caddy-rpm-repo.git && cd caddy-rpm-repo

# 2. 配置环境变量
cp docker/.env.example docker/.env
# 编辑 docker/.env，至少设置 GPG_KEY_ID

# 3. 准备 GPG 密钥
mkdir -p gpg-keys
cp /path/to/your/private.gpg gpg-keys/
chmod 600 gpg-keys/private.gpg

# 4. 启动服务
docker compose -f docker/docker-compose.yml up -d

# 5. 验证
docker compose -f docker/docker-compose.yml ps
```

启动后 Scheduler 会立即检查并触发首次构建。构建完成后仓库即可访问。

### 环境变量配置

编辑 `docker/.env`：

| 变量名 | 说明 | 默认值 | 必填 |
|--------|------|--------|------|
| `CADDY_VERSION` | Caddy 版本号（留空自动查询） | 自动 | 否 |
| `TARGET_ARCH` | 目标架构 | `all` | 否 |
| `TARGET_DISTRO` | 目标发行版 | `all` | 否 |
| `BASE_URL` | .repo 模板基础 URL | `https://rpms.example.com` | 否 |
| `GPG_KEY_ID` | GPG 签名密钥 ID | — | 是 |
| `DOMAIN_NAME` | 服务域名（自动 HTTPS） | `localhost` | 否 |
| `CHECK_INTERVAL` | 版本检查周期（`Nd` 天/`Nh` 小时） | `10d` | 否 |
| `GITHUB_TOKEN` | GitHub API 令牌（避免限流） | — | 否 |
| `API_TOKEN` | 管理 API 认证令牌 | — | 启用管理 API 时必填 |
| `MANAGER_PORT` | 管理 API 端口 | `8080` | 否 |

### 日常运维

为简洁起见，建议设置别名：

```bash
alias dc='docker compose -f docker/docker-compose.yml'
```

**手动触发构建：**

```bash
dc run --rm builder
dc run --rm signer

# 指定版本
dc run --rm -e CADDY_VERSION=2.9.1 builder
dc run --rm -e CADDY_VERSION=2.9.1 signer
```

**回滚：**

```bash
# 通过管理 API
curl -X POST -H "Authorization: Bearer YOUR_TOKEN" http://localhost:8080/api/rollback

# 或直接执行
dc run --rm signer bash /app/build-repo.sh --rollback --output /repo
```

**查看日志：**

```bash
dc logs scheduler        # 查看调度日志
dc logs builder          # 查看构建日志
dc logs -f scheduler     # 实时跟踪
```

**查看当前版本：**

```bash
# 读取版本文件
docker compose -f docker/docker-compose.yml exec repo-server cat /srv/repo/caddy/.current-version

# 通过管理 API
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:8080/api/status
```

**修改检查周期：**

```bash
# 编辑 docker/.env 中的 CHECK_INTERVAL
dc restart scheduler
```

**启用管理 API（可选）：**

```bash
docker compose -f docker/docker-compose.yml --profile management up -d
```

### CI/CD 模式

使用覆盖文件禁用常驻服务，仅运行构建和签名：

```bash
docker compose -f docker/docker-compose.yml -f docker/docker-compose.ci.yml run --rm builder
docker compose -f docker/docker-compose.yml -f docker/docker-compose.ci.yml run --rm signer
```

退出码会传播到 CI/CD 流水线。

### 安全特性

- 所有容器以非 root 用户运行
- Builder/Signer 使用只读文件系统 + `cap_drop: ALL`
- 所有容器配置 `no-new-privileges:true`
- GPG 密钥仅 Signer 容器可访问（只读），退出时自动清除
- 密钥文件权限必须为 600 或 400，否则拒绝启动
- 内部网络隔离，仅 Repo Server 和 Repo Manager 对外暴露端口

---

## 四、客户端配置

### 方式一：使用安装脚本（推荐）

```bash
bash install-caddy.sh --mirror https://rpms.yoursite.com
```

脚本自动检测发行版，配置 `.repo` 文件，导入 GPG 公钥并安装 Caddy。支持 28+ 个 RPM 发行版（含 Anolis、openEuler、Kylin 等国产发行版）。

### 方式二：手动配置

创建 `/etc/yum.repos.d/caddy.repo`：

```ini
[caddy-selfhosted]
name=Caddy Self-Hosted Repository
baseurl=https://rpms.yoursite.com/caddy/$DISTRO/$VERSION/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://rpms.yoursite.com/caddy/gpg.key
```

其中 `$DISTRO/$VERSION` 根据发行版替换，例如：
- RHEL 9 → `el9`（无版本号子目录）
- Anolis 8 → `anolis/8`
- openEuler 22 → `openeuler/22`
- Fedora → `fedora`（无版本号子目录）

然后安装：

```bash
rpm --import https://rpms.yoursite.com/caddy/gpg.key
dnf install caddy
```

---

## 五、运行测试

项目包含完整的单元测试和属性测试套件，使用 [bats-core](https://github.com/bats-core/bats-core) 框架。

```bash
# 运行全部测试
./tests/libs/bats-core/bin/bats tests/unit/ tests/property/

# 仅运行 Docker 相关测试
./tests/libs/bats-core/bin/bats \
  tests/unit/test_caddyfile.bats \
  tests/unit/test_scheduler.bats \
  tests/unit/test_manager.bats \
  tests/unit/test_compose_config.bats \
  tests/property/test_prop_*.bats

# 运行单个测试文件
./tests/libs/bats-core/bin/bats tests/unit/test_scheduler.bats
```

测试覆盖：
- 单元测试：Caddyfile 配置、scheduler 各函数、manager API 端点、docker-compose.yml 配置验证
- 属性测试（每个 100 次随机迭代）：退出码传播、环境变量映射、GPG 权限校验、间隔解析、版本决策、API 认证、状态格式、Volume 隔离、安全选项、非 root 用户

---

## 六、项目文件结构

```
├── build-repo.sh                  # 主构建脚本
├── install-caddy.sh               # 客户端安装脚本
├── USAGE.md                       # 本文档
├── packaging/                     # RPM 打包资源
├── docker/
│   ├── docker-compose.yml         # 主编排文件
│   ├── docker-compose.ci.yml      # CI/CD 覆盖文件
│   ├── .env.example               # 环境变量模板
│   ├── README.md                  # Docker 部署详细文档
│   ├── builder/                   # Builder 容器
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   ├── signer/                    # Signer 容器
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   ├── repo-server/               # Repo Server 容器
│   │   └── Caddyfile
│   ├── scheduler/                 # Scheduler 容器
│   │   ├── Dockerfile
│   │   └── scheduler.sh
│   └── repo-manager/              # Repo Manager 容器
│       ├── Dockerfile
│       └── manager.sh
└── tests/
    ├── unit/                      # 单元测试
    ├── property/                  # 属性测试
    ├── test_helper/               # 测试辅助工具
    └── libs/                      # bats-core, bats-assert
```

如需 Docker 部署的更详细说明（故障排查、GPG 密钥准备、更换域名等），请参阅 `docker/README.md`。
