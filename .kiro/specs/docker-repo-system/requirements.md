# 需求文档

## 简介

将现有的 `build-repo.sh` 自建 RPM 仓库构建系统容器化，拆分为职责单一的 Docker 容器，通过 Docker Compose 编排。系统包含五个容器：builder（构建 RPM 包）、signer（GPG 签名）、repo-server（静态文件服务）、scheduler（定时版本检查与自动构建）、repo-manager（可选管理 API）。容器间通过共享 Volume 传递产物，签名密钥通过独立 Volume 隔离，实现构建环境与密钥环境的安全分离。scheduler 容器按可配置周期（默认 10 天）自动检查 Caddy 新版本并触发构建，实现仓库的无人值守更新。

## 术语表

- **Builder_Container**: 一次性任务容器，负责执行 `build-repo.sh --stage build`，安装 nfpm、createrepo_c、curl 等构建依赖，构建完成后退出
- **Signer_Container**: 一次性任务容器，负责执行 `build-repo.sh --stage sign` 和 `--stage publish`，挂载 GPG 密钥进行 RPM 签名和仓库元数据签名
- **Repo_Server_Container**: 常驻服务容器，使用 Caddy 托管仓库产物目录，提供静态文件 HTTP/HTTPS 服务
- **Repo_Manager_Container**: 可选常驻服务容器，提供管理 API（触发构建、回滚、查看状态），支持 webhook 触发自动构建
- **Compose_Orchestrator**: Docker Compose 编排文件，定义容器、Volume、网络和依赖关系
- **repo-data_Volume**: 仓库产物共享 Volume，由 Builder_Container 写入，Signer_Container 读写，Repo_Server_Container 只读挂载
- **gpg-keys_Volume**: GPG 签名密钥 Volume，仅由 Signer_Container 只读挂载
- **Build_Script**: 现有的 `build-repo.sh` 脚本，支持 `--stage build|sign|publish|verify` 分阶段执行
- **Vendor_Directory**: `vendor/` 目录，存放预下载的 Caddy 二进制文件，用于离线构建
- **Scheduler_Container**: 定时任务容器，按可配置的周期（默认 10 天）检查 Caddy 新版本，发现新版本时自动触发完整构建流程
- **Version_State_File**: 版本状态文件，记录当前已构建的 Caddy 版本号，存储在 repo-data_Volume 中，供 Scheduler_Container 判断是否需要构建

## 需求

### 需求 1: Builder 容器镜像

**用户故事:** 作为 DevOps 工程师，我希望有一个包含所有构建依赖的 Docker 镜像，以便在隔离环境中可重复地构建 RPM 包。

#### 验收标准

1. THE Builder_Container 镜像 SHALL 基于 Fedora 或 CentOS Stream 基础镜像构建，并预装 nfpm、createrepo_c、curl、rpm-build、rpm-sign 工具
2. WHEN Builder_Container 启动时，THE Builder_Container SHALL 执行 `build-repo.sh --stage build`，将 RPM 包和仓库元数据写入 repo-data_Volume
3. WHEN 构建阶段完成时，THE Builder_Container SHALL 以退出码 0 退出；WHEN 构建失败时，THE Builder_Container SHALL 以非零退出码退出
4. THE Builder_Container SHALL 通过环境变量接收构建参数（CADDY_VERSION、TARGET_ARCH、TARGET_DISTRO、BASE_URL）
5. WHERE Vendor_Directory 已挂载，THE Builder_Container SHALL 优先使用 vendor/ 目录中的预下载二进制文件进行离线构建
6. THE Builder_Container 的 Dockerfile SHALL 使用多阶段构建，将 nfpm 安装与运行时环境分离，减小最终镜像体积

### 需求 2: Signer 容器镜像

**用户故事:** 作为安全工程师，我希望签名操作在独立容器中执行，使 GPG 密钥与构建环境隔离，降低密钥泄露风险。

#### 验收标准

1. THE Signer_Container 镜像 SHALL 预装 gnupg2、rpm-sign 工具，用于 RPM 包签名和 repomd.xml 签名
2. THE Signer_Container SHALL 以只读方式挂载 gpg-keys_Volume，从中加载 GPG 私钥
3. WHEN Signer_Container 启动时，THE Signer_Container SHALL 依次执行 `build-repo.sh --stage sign` 和 `build-repo.sh --stage publish`
4. WHEN 签名和发布阶段完成时，THE Signer_Container SHALL 以退出码 0 退出；WHEN 签名失败时，THE Signer_Container SHALL 以非零退出码退出
5. THE Signer_Container SHALL 通过环境变量接收 GPG_KEY_ID 参数
6. WHERE CI/CD 环境中运行，THE Signer_Container SHALL 支持通过 Docker secrets 或环境变量注入 GPG 密钥文件路径
7. THE Signer_Container SHALL 在容器退出时清除内存中的 GPG 密钥材料，确保密钥不残留在容器层中


### 需求 3: Repo Server 容器

**用户故事:** 作为运维工程师，我希望有一个常驻的静态文件服务容器，以便客户端通过 HTTP/HTTPS 访问 RPM 仓库。

#### 验收标准

1. THE Repo_Server_Container SHALL 使用 Caddy 作为 Web 服务器，以只读方式挂载 repo-data_Volume 并提供静态文件服务
2. THE Repo_Server_Container SHALL 在端口 80 和 443 上监听 HTTP 和 HTTPS 请求
3. THE Repo_Server_Container SHALL 配置 Caddy 自动 HTTPS（通过 ACME 协议获取证书），并支持通过环境变量指定域名
4. WHEN repo-data_Volume 中的文件更新时，THE Repo_Server_Container SHALL 立即提供更新后的文件，无需重启容器
5. THE Repo_Server_Container SHALL 配置适当的 Cache-Control 响应头：repomd.xml 设置 no-cache，RPM 包文件设置 max-age=86400
6. THE Repo_Server_Container SHALL 启用 Caddy 访问日志，记录请求路径、状态码和客户端 IP
7. IF Repo_Server_Container 无法绑定监听端口，THEN THE Repo_Server_Container SHALL 输出错误日志并以非零退出码退出

### 需求 4: Repo Manager 容器（可选）

**用户故事:** 作为 DevOps 工程师，我希望有一个管理 API 服务，以便通过 HTTP 接口或 webhook 触发构建、查看状态和执行回滚。

#### 验收标准

1. WHERE Repo_Manager_Container 已启用，THE Repo_Manager_Container SHALL 提供 REST API 端点：POST /api/build（触发构建）、POST /api/rollback（执行回滚）、GET /api/status（查看构建状态）
2. WHERE Repo_Manager_Container 已启用，THE Repo_Manager_Container SHALL 提供 POST /api/webhook 端点，接收 GitHub/Gitea webhook 事件并触发自动构建
3. WHEN POST /api/build 请求到达时，THE Repo_Manager_Container SHALL 启动 Builder_Container 和 Signer_Container 执行完整构建流程
4. WHEN POST /api/rollback 请求到达时，THE Repo_Manager_Container SHALL 执行 `build-repo.sh --rollback` 恢复到最近备份
5. WHEN GET /api/status 请求到达时，THE Repo_Manager_Container SHALL 返回 JSON 格式的构建状态（最近构建时间、版本号、成功/失败状态）
6. THE Repo_Manager_Container SHALL 通过 API 密钥或 Bearer Token 进行身份验证，拒绝未认证的请求并返回 HTTP 401 状态码
7. THE Repo_Manager_Container SHALL 在管理端口（默认 8080）上监听，该端口与 Repo_Server_Container 的服务端口隔离

### 需求 5: Volume 设计与数据流

**用户故事:** 作为系统架构师，我希望容器间通过明确定义的 Volume 共享数据，以便实现职责分离和最小权限原则。

#### 验收标准

1. THE Compose_Orchestrator SHALL 定义 repo-data 命名 Volume，由 Builder_Container 以读写方式挂载，由 Signer_Container 以读写方式挂载，由 Repo_Server_Container 以只读方式挂载
2. THE Compose_Orchestrator SHALL 定义 gpg-keys 命名 Volume，仅由 Signer_Container 以只读方式挂载
3. THE Builder_Container SHALL 将构建产物写入 repo-data_Volume 的 `.staging/` 子目录，与正式发布目录隔离
4. WHEN Signer_Container 执行 publish 阶段时，THE Signer_Container SHALL 将 `.staging/` 中的产物原子交换到 repo-data_Volume 的正式目录
5. THE Repo_Server_Container SHALL 仅能读取 repo-data_Volume 中的正式发布目录，无法访问 `.staging/` 目录或 gpg-keys_Volume
6. WHERE Vendor_Directory 需要使用，THE Compose_Orchestrator SHALL 支持将宿主机 vendor/ 目录以只读 bind mount 方式挂载到 Builder_Container


### 需求 6: Docker Compose 编排

**用户故事:** 作为 DevOps 工程师，我希望通过一个 docker-compose.yml 文件定义完整的容器编排，以便一键启动整个仓库系统。

#### 验收标准

1. THE Compose_Orchestrator SHALL 定义 builder、signer、repo-server 三个核心服务，以及可选的 repo-manager 服务
2. THE Compose_Orchestrator SHALL 配置 builder 和 signer 服务的依赖关系：signer 依赖 builder 成功完成后启动
3. THE Compose_Orchestrator SHALL 配置 repo-server 服务为 `restart: unless-stopped`，确保服务持续运行
4. THE Compose_Orchestrator SHALL 配置 builder 和 signer 服务为 `restart: no`，确保一次性任务完成后不自动重启
5. THE Compose_Orchestrator SHALL 通过 `.env` 文件支持配置：CADDY_VERSION、TARGET_ARCH、TARGET_DISTRO、GPG_KEY_ID、BASE_URL、DOMAIN_NAME
6. THE Compose_Orchestrator SHALL 定义独立的 bridge 网络，仅 repo-server 和 repo-manager 暴露端口到宿主机
7. WHERE repo-manager 服务已启用，THE Compose_Orchestrator SHALL 配置 repo-manager 能够通过 Docker socket 启动 builder 和 signer 容器

### 需求 7: Dockerfile 构建优化

**用户故事:** 作为 DevOps 工程师，我希望 Docker 镜像构建高效且体积小，以便加快 CI/CD 流水线速度和减少存储开销。

#### 验收标准

1. THE Builder_Container 的 Dockerfile SHALL 利用 Docker 层缓存，将依赖安装层与脚本复制层分离
2. THE Builder_Container 的 Dockerfile SHALL 在安装依赖后清理包管理器缓存（dnf clean all），减小镜像体积
3. THE Signer_Container 的 Dockerfile SHALL 仅安装签名所需的最小依赖集（gnupg2、rpm-sign），镜像体积小于 200MB
4. THE Repo_Server_Container 的 Dockerfile SHALL 基于官方 Caddy 镜像构建，仅添加自定义 Caddyfile 配置
5. WHEN 构建脚本 build-repo.sh 或 packaging/ 目录内容变更时，THE Dockerfile SHALL 仅重建受影响的层，复用未变更的依赖层

### 需求 8: 安全性

**用户故事:** 作为安全工程师，我希望容器化方案遵循最小权限原则，以便降低安全风险。

#### 验收标准

1. THE Builder_Container SHALL 以非 root 用户身份运行构建任务
2. THE Signer_Container SHALL 以非 root 用户身份运行签名任务，并通过文件权限限制 GPG 密钥的访问范围
3. THE Repo_Server_Container SHALL 以非 root 用户身份运行 Caddy 服务
4. THE Compose_Orchestrator SHALL 为 builder 和 signer 容器配置 `read_only: true` 文件系统，仅允许写入指定的 Volume 和 tmpfs 挂载点
5. THE Compose_Orchestrator SHALL 为所有容器配置 `no-new-privileges: true` 安全选项
6. THE Compose_Orchestrator SHALL 为 builder 和 signer 容器配置 `cap_drop: ALL`，仅添加必要的 Linux capabilities
7. IF GPG 密钥文件权限不是 600 或 400，THEN THE Signer_Container SHALL 拒绝启动并输出权限错误提示

### 需求 9: 健康检查与日志

**用户故事:** 作为运维工程师，我希望容器具备健康检查和结构化日志，以便监控系统运行状态。

#### 验收标准

1. THE Repo_Server_Container SHALL 配置 Docker 健康检查，每 30 秒通过 HTTP 请求验证 Caddy 服务可用性
2. WHERE Repo_Manager_Container 已启用，THE Repo_Manager_Container SHALL 配置 Docker 健康检查，每 30 秒验证 API 端点可用性
3. THE Builder_Container SHALL 将构建日志输出到 stderr，遵循现有 build-repo.sh 的 `[INFO]`/`[ERROR]` 日志格式
4. THE Signer_Container SHALL 将签名日志输出到 stderr，遵循现有 build-repo.sh 的日志格式
5. WHEN 容器异常退出时，THE Compose_Orchestrator SHALL 通过 Docker 日志驱动保留容器日志，支持 `docker compose logs` 查看

### 需求 10: CI/CD 集成

**用户故事:** 作为 DevOps 工程师，我希望容器化方案能够集成到 CI/CD 流水线中，以便自动化构建和发布流程。

#### 验收标准

1. THE Compose_Orchestrator SHALL 支持通过 `docker compose run builder` 单独执行构建阶段
2. THE Compose_Orchestrator SHALL 支持通过 `docker compose run signer` 单独执行签名和发布阶段
3. WHEN 在 CI/CD 环境中运行时，THE Builder_Container 和 Signer_Container SHALL 支持通过 `--exit-code-from` 将容器退出码传播到 CI/CD 流水线
4. THE Compose_Orchestrator SHALL 提供 `docker-compose.ci.yml` 覆盖文件，用于 CI/CD 场景下禁用 repo-server 和 repo-manager 服务
5. WHERE SM2 国密签名已启用，THE Signer_Container SHALL 支持通过环境变量 SM2_KEY_PATH 指定 SM2 私钥路径

### 需求 11: 定时版本检查与自动构建

**用户故事:** 作为仓库维护者，我希望系统能定期自动检查 Caddy 是否有新版本发布，有新版本时自动触发构建，没有则跳过，以便仓库始终保持最新而无需人工干预。

#### 验收标准

1. THE Compose_Orchestrator SHALL 定义 scheduler 服务（Scheduler_Container），作为常驻容器按可配置的周期运行版本检查任务
2. THE Scheduler_Container SHALL 通过环境变量 `CHECK_INTERVAL` 配置检查周期，默认值为 `10d`（10 天），支持 `Nd`（天）、`Nh`（小时）格式
3. WHEN 检查周期到达时，THE Scheduler_Container SHALL 查询 Caddy GitHub Releases API 获取最新稳定版本号
4. THE Scheduler_Container SHALL 读取 repo-data_Volume 中的 Version_State_File（`/repo/caddy/.current-version`）获取当前已构建的版本号
5. IF 最新版本号与 Version_State_File 中记录的版本号不同，THEN THE Scheduler_Container SHALL 自动触发完整构建流程（builder → signer），并在构建成功后更新 Version_State_File
6. IF 最新版本号与 Version_State_File 中记录的版本号相同，THEN THE Scheduler_Container SHALL 输出 `[INFO] 当前版本已是最新 (x.y.z)，跳过构建` 到日志并等待下一个检查周期
7. IF Version_State_File 不存在（首次运行），THEN THE Scheduler_Container SHALL 视为需要构建，触发完整构建流程
8. IF GitHub API 查询失败（网络错误、API 限流等），THEN THE Scheduler_Container SHALL 输出错误日志并等待下一个检查周期，不终止容器
9. THE Scheduler_Container SHALL 在每次检查时输出日志，记录检查时间、查询到的版本号、当前版本号、以及决策结果（构建/跳过/错误）
10. THE Scheduler_Container SHALL 支持通过环境变量 `GITHUB_TOKEN` 配置 GitHub API 认证令牌，避免匿名 API 限流（60 次/小时）
11. THE Compose_Orchestrator SHALL 配置 scheduler 服务为 `restart: unless-stopped`，确保定时任务持续运行
12. THE Scheduler_Container SHALL 在容器启动时立即执行一次版本检查（不等待第一个周期），确保首次部署时仓库立即可用

### 需求 12: 使用文档

**用户故事:** 作为首次部署的用户，我希望有一份详细的使用文档，以便快速理解系统架构、完成部署配置、掌握日常运维操作。

#### 验收标准

1. THE 项目 SHALL 在 `docker/` 目录下提供 `README.md` 使用文档，涵盖系统架构概览、前置条件、快速开始、详细配置、运维操作、故障排查六个章节
2. THE 使用文档 SHALL 包含系统架构图（文本格式），展示五个容器（builder、signer、repo-server、scheduler、repo-manager）之间的数据流和 Volume 关系
3. THE 使用文档 SHALL 包含前置条件章节，列出 Docker Engine 和 Docker Compose 的最低版本要求，以及 GPG 密钥准备步骤
4. THE 使用文档 SHALL 包含快速开始章节，提供从克隆仓库到仓库可用的完整步骤（不超过 5 个命令），包括 `.env` 文件配置示例
5. THE 使用文档 SHALL 包含详细配置章节，列出所有环境变量（名称、说明、默认值、是否必填），以 Markdown 表格形式呈现
6. THE 使用文档 SHALL 包含运维操作章节，覆盖以下场景的具体命令和说明：手动触发构建、回滚到上一版本、查看构建日志、查看当前已构建版本、修改检查周期、更换 GPG 密钥、更换域名
7. THE 使用文档 SHALL 包含故障排查章节，列出常见问题（构建失败、签名失败、API 限流、证书获取失败、磁盘空间不足）的症状、原因和解决方法
8. THE 使用文档 SHALL 包含客户端配置章节，说明终端用户如何在各发行版上配置 `.repo` 文件以使用该仓库，包括 `install-caddy.sh --mirror` 方式和手动配置方式
9. THE 使用文档 SHALL 包含安全注意事项章节，说明 GPG 密钥管理、Docker socket 挂载风险、网络隔离等安全相关配置建议
10. THE 使用文档 SHALL 使用中文编写
