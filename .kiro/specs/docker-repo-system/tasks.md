# 实现计划：Docker 容器化 RPM 仓库构建系统

## 概述

将现有 `build-repo.sh` 系统容器化，创建 5 个 Docker 容器（builder、signer、repo-server、scheduler、repo-manager），通过 Docker Compose 编排。实现按设计文档中的目录结构 `docker/` 组织所有容器化文件，复用现有 `build-repo.sh` 脚本。

## 任务

- [x] 1. 创建项目结构和基础配置文件
  - [x] 1.1 创建 `docker/` 目录结构和 `.env.example` 环境变量模板
    - 创建 `docker/` 及子目录：`builder/`、`signer/`、`scheduler/`、`repo-manager/`、`repo-server/`
    - 创建 `.env.example` 文件，包含所有环境变量（CADDY_VERSION、TARGET_ARCH、TARGET_DISTRO、BASE_URL、GPG_KEY_ID、DOMAIN_NAME、CHECK_INTERVAL、GITHUB_TOKEN、API_TOKEN、MANAGER_PORT）
    - _需求: 6.5_

- [x] 2. 实现 Builder 容器
  - [x] 2.1 创建 `docker/builder/Dockerfile`（多阶段构建）
    - 阶段 1：基于 Fedora 安装 Go 并编译 nfpm
    - 阶段 2：安装运行时依赖（createrepo_c、curl、rpm-build、rpm-sign、gnupg2），创建非 root 用户 `builder`
    - 复制 `build-repo.sh` 和 `packaging/` 到镜像
    - 使用 `USER builder` 指令，设置 ENTRYPOINT
    - 依赖安装层与脚本复制层分离以利用层缓存，安装后执行 `dnf clean all`
    - _需求: 1.1, 1.6, 7.1, 7.2, 8.1_

  - [x] 2.2 创建 `docker/builder/entrypoint.sh` 入口脚本
    - 将环境变量（CADDY_VERSION、TARGET_ARCH、TARGET_DISTRO、BASE_URL）转换为 `build-repo.sh --stage build` 的 CLI 参数
    - 未设置的环境变量不生成对应参数
    - 构建产物写入 `/repo`（repo-data Volume 挂载点）
    - _需求: 1.2, 1.3, 1.4, 1.5_

  - [x] 2.3 编写 entrypoint 环境变量映射的属性测试
    - **Property 2: 环境变量到 CLI 参数映射**
    - **验证: 需求 1.4, 2.5**

  - [x] 2.4 编写 entrypoint 退出码传播的属性测试
    - **Property 1: 容器退出码传播**
    - **验证: 需求 1.3, 2.4**

- [x] 3. 实现 Signer 容器
  - [x] 3.1 创建 `docker/signer/Dockerfile`
    - 基于 Fedora，仅安装 gnupg2、rpm-sign 最小依赖集
    - 创建非 root 用户 `signer`，安装后 `dnf clean all`
    - 镜像体积目标小于 200MB
    - _需求: 2.1, 7.3, 8.2_

  - [x] 3.2 创建 `docker/signer/entrypoint.sh` 入口脚本
    - 检查 `/gpg-keys/*.gpg` 文件权限，非 600/400 时拒绝启动并输出错误
    - 导入 GPG 密钥，依次执行 `build-repo.sh --stage sign` 和 `--stage publish`
    - 通过 GPG_KEY_ID 环境变量接收密钥 ID
    - 退出前清除 GPG 密钥材料（`gpgconf --kill gpg-agent` + `rm -rf ~/.gnupg`）
    - _需求: 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 8.7_

  - [x] 3.3 编写 GPG 密钥文件权限校验的属性测试
    - **Property 6: GPG 密钥文件权限校验**
    - **验证: 需求 8.7**

- [x] 4. 检查点 - 确保 builder 和 signer 容器测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 5. 实现 Repo Server 容器
  - [x] 5.1 创建 `docker/repo-server/Caddyfile` 配置
    - 使用 `{$DOMAIN_NAME:localhost}` 环境变量支持域名配置
    - 配置 `file_server browse`，根目录 `/srv/repo`
    - 配置 Cache-Control：repomd.xml 设置 `no-cache, must-revalidate`，RPM 文件设置 `max-age=86400`
    - 启用 JSON 格式访问日志输出到 stdout
    - _需求: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 5.2 编写 Caddyfile 配置验证的单元测试
    - 验证 Cache-Control 头配置、日志配置、域名环境变量
    - _需求: 3.5, 3.6_

- [x] 6. 实现 Scheduler 容器
  - [x] 6.1 创建 `docker/scheduler/scheduler.sh` 定时检查脚本
    - 实现 `parse_interval` 函数：解析 `Nd`（天）和 `Nh`（小时）格式为秒数
    - 实现 `get_latest_version` 函数：查询 GitHub Releases API，支持 GITHUB_TOKEN 认证
    - 实现 `get_current_version` 函数：读取 `/repo/caddy/.current-version`，文件不存在返回空
    - 实现 `trigger_build` 函数：通过 `docker compose run` 启动 builder 和 signer
    - 主循环：启动时立即检查一次，之后按 CHECK_INTERVAL 周期循环
    - API 失败、构建失败时记录错误日志但不终止容器
    - 采用 `_SOURCED_FOR_TEST` 模式支持测试时 source 单独函数
    - _需求: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7, 11.8, 11.9, 11.10, 11.12_

  - [x] 6.2 创建 `docker/scheduler/Dockerfile`
    - 基于 Fedora，安装 curl、docker-cli（用于 docker compose 命令）
    - 创建非 root 用户，ENTRYPOINT 指向 scheduler.sh
    - _需求: 11.1, 11.11_

  - [x] 6.3 编写 CHECK_INTERVAL 解析的属性测试
    - **Property 7: CHECK_INTERVAL 解析正确性**
    - **验证: 需求 11.2**

  - [x] 6.4 编写版本比较与构建决策的属性测试
    - **Property 8: 版本比较与构建决策**
    - **验证: 需求 11.5, 11.6, 11.7**

  - [x] 6.5 编写 scheduler.sh 单元测试
    - 测试 `parse_interval` 各格式（天、小时、纯数字）
    - 测试 `get_latest_version` mock curl 响应
    - 测试 `get_current_version` 文件存在/不存在
    - 测试首次运行立即检查逻辑
    - _需求: 11.2, 11.3, 11.4, 11.7, 11.12_

- [x] 7. 检查点 - 确保 scheduler 测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 8. 实现 Repo Manager 容器（可选）
  - [x] 8.1 创建 `docker/repo-manager/manager.sh` 管理 API 脚本
    - 使用 socat/ncat 监听 HTTP 请求（默认端口 8080）
    - 实现 API 端点：POST /api/build、POST /api/rollback、GET /api/status、POST /api/webhook
    - 实现 Bearer Token 认证，未认证请求返回 HTTP 401
    - GET /api/status 返回 JSON 格式（last_build_time、version、status 字段）
    - POST /api/build 通过 Docker socket 启动 builder + signer 容器
    - POST /api/rollback 执行 `build-repo.sh --rollback`
    - 采用 `_SOURCED_FOR_TEST` 模式支持测试
    - _需求: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_

  - [x] 8.2 创建 `docker/repo-manager/Dockerfile`
    - 基于 Fedora，安装 socat/ncat、curl、docker-cli
    - 创建非 root 用户，ENTRYPOINT 指向 manager.sh
    - _需求: 4.7_

  - [x] 8.3 编写 API 认证的属性测试
    - **Property 9: API 认证强制执行**
    - **验证: 需求 4.6**

  - [x] 8.4 编写状态 API 响应格式的属性测试
    - **Property 10: 状态 API 响应格式**
    - **验证: 需求 4.5**

  - [x] 8.5 编写 manager.sh 单元测试
    - 测试各 API 端点响应、认证成功/失败、JSON 响应格式
    - _需求: 4.1, 4.5, 4.6_

- [x] 9. 实现 Docker Compose 编排
  - [x] 9.1 创建 `docker/docker-compose.yml` 主编排文件
    - 定义 builder、signer、repo-server、scheduler、repo-manager 五个服务
    - 配置 Volume：repo-data（builder 读写、signer 读写、repo-server 只读）、gpg-keys（仅 signer 只读）
    - 配置 signer 依赖 builder（`condition: service_completed_successfully`）
    - 配置 builder/signer 为 `restart: no`，repo-server/scheduler 为 `restart: unless-stopped`
    - 配置 repo-manager 使用 `profiles: [management]` 实现可选启用
    - 定义 internal（bridge, internal: true）和 external（bridge）网络
    - 仅 repo-server（80/443）和 repo-manager（8080）暴露端口到宿主机
    - 配置 vendor/ 目录以只读 bind mount 挂载到 builder
    - 配置 Docker socket 挂载到 scheduler 和 repo-manager
    - 所有服务配置 `security_opt: [no-new-privileges:true]`
    - builder/signer 配置 `read_only: true`、`cap_drop: [ALL]`、tmpfs 挂载
    - repo-server 配置健康检查（每 30 秒 HTTP 请求）
    - repo-manager 配置健康检查（每 30 秒验证 API 端点）
    - 通过 `.env` 文件传递环境变量
    - _需求: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 8.4, 8.5, 8.6, 9.1, 9.2, 9.5, 11.11_

  - [x] 9.2 创建 `docker/docker-compose.ci.yml` CI/CD 覆盖文件
    - 禁用 repo-server、repo-manager、scheduler 服务（通过 profiles: [disabled]）
    - 支持 `docker compose run builder` 和 `docker compose run signer` 单独执行
    - 支持 `--exit-code-from` 传播退出码到 CI/CD 流水线
    - _需求: 10.1, 10.2, 10.3, 10.4_

  - [x] 9.3 编写 GPG Volume 隔离的属性测试
    - **Property 3: GPG 密钥 Volume 隔离**
    - **验证: 需求 5.2**

  - [x] 9.4 编写安全选项全覆盖的属性测试
    - **Property 4: 安全选项全覆盖**
    - **验证: 需求 8.5**

  - [x] 9.5 编写非 root 用户运行的属性测试
    - **Property 5: 非 root 用户运行**
    - **验证: 需求 8.1, 8.2, 8.3**

  - [x] 9.6 编写 docker-compose.yml 配置验证的单元测试
    - 验证服务定义完整性、Volume 挂载正确性、网络配置、安全选项
    - _需求: 5.1, 5.2, 6.1, 6.6, 8.4, 8.5, 8.6_

- [x] 10. 检查点 - 确保 Docker Compose 配置和所有属性测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 11. 创建测试辅助工具
  - [x] 11.1 创建 `tests/test_helper/generators_docker.bash` 随机数据生成器
    - 实现 `gen_exit_code`：生成随机退出码（0-8）
    - 实现 `gen_env_vars`：生成随机环境变量组合
    - 实现 `gen_file_permission`：生成随机文件权限（八进制）
    - 实现 `gen_check_interval`：生成随机 CHECK_INTERVAL 值（Nd 或 Nh）
    - 实现 `gen_version_pair`：生成随机版本号对（latest, current）
    - 实现 `gen_api_request`：生成随机 API 请求（有/无认证）
    - 实现 `gen_api_token`：生成随机 Bearer Token
    - _需求: 设计文档测试策略_

- [x] 12. 编写使用文档
  - [x] 12.1 创建 `docker/README.md` 使用文档
    - 系统架构概览（文本格式架构图，展示 5 个容器的数据流和 Volume 关系）
    - 前置条件（Docker Engine/Compose 最低版本、GPG 密钥准备步骤）
    - 快速开始（从克隆到仓库可用不超过 5 个命令，含 `.env` 配置示例）
    - 详细配置（所有环境变量的 Markdown 表格：名称、说明、默认值、是否必填）
    - 运维操作（手动触发构建、回滚、查看日志、查看版本、修改检查周期、更换 GPG 密钥、更换域名）
    - 故障排查（构建失败、签名失败、API 限流、证书获取失败、磁盘空间不足）
    - 客户端配置（各发行版 `.repo` 文件配置，含 `install-caddy.sh --mirror` 方式和手动方式）
    - 安全注意事项（GPG 密钥管理、Docker socket 风险、网络隔离）
    - 使用中文编写
    - _需求: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7, 12.8, 12.9, 12.10_

- [x] 13. 最终检查点 - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

## 备注

- 标记 `*` 的任务为可选，可跳过以加快 MVP 进度
- 每个任务引用了具体的需求编号以确保可追溯性
- 检查点确保增量验证
- 属性测试验证通用正确性属性，单元测试验证具体示例和边界情况
- 测试辅助工具（任务 11）应在编写属性测试前完成，但因属性测试均为可选，故放在后面；如需执行属性测试，请先完成任务 11
