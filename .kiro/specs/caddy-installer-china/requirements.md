# 需求文档：Caddy Server 中国发行版安装脚本

## 简介

本项目创建一个独立的 Shell 安装脚本（`install-caddy.sh`），专门解决 Caddy Server 官方 APT/COPR 仓库在部分 Linux 发行版上不兼容的问题。脚本采用多级 fallback 安装策略：优先使用官方包仓库（标准发行版）、自建 DNF 仓库（COPR 不支持的 RPM 系发行版）、最终回退到官方 API 静态二进制下载。该脚本作为 WebCasa 项目的外部依赖被调用。

## 术语表

- **Installer**：本项目的 `install-caddy.sh` 安装脚本
- **Caddy**：Caddy Server，目标安装的 Web 服务器二进制程序
- **Standard_Distro**：标准 Linux 发行版，包括 Debian、Ubuntu、Fedora、CentOS Stream、RHEL、AlmaLinux、Rocky Linux
- **Unsupported_RPM_Distro**：COPR 不支持的 RPM 系发行版，包括中国国产发行版（openEuler、openAnolis、Alibaba Cloud Linux、openCloudOS、Kylin Server）以及 Amazon Linux 2023（OS_ID: `amzn`）和 Oracle Linux（OS_ID: `ol`）
- **Self_Hosted_Repo**：自建 DNF 仓库，用于托管 Caddy RPM 包，替代 Fedora COPR 以解决 COPR 不兼容发行版的安装问题
- **Official_APT_Repo**：Caddy 官方通过 Cloudsmith 托管的 APT 仓库
- **Official_COPR_Repo**：Caddy 官方 Fedora COPR 仓库（@caddy/caddy）
- **Caddy_Download_API**：Caddy 官方静态二进制下载接口，地址为 `https://caddyserver.com/api/download`
- **OS_Detection**：操作系统检测模块，通过读取 `/etc/os-release` 获取发行版信息
- **WebCasa**：调用本脚本的上游项目（https://github.com/web-casa/webcasa）

## 需求

### 需求 1：操作系统检测与分类

**用户故事：** 作为脚本调用者，我希望脚本能自动识别当前操作系统的类型和版本，以便选择正确的安装策略。

#### 验收标准

1. WHEN `/etc/os-release` 文件存在时，THE OS_Detection SHALL 读取该文件并提取 `ID`、`ID_LIKE`、`VERSION_ID`、`NAME` 和 `PLATFORM_ID` 字段
2. WHEN `ID` 字段值为 `debian`、`ubuntu`、`fedora`、`centos`、`rhel`、`almalinux` 或 `rocky` 时，THE OS_Detection SHALL 将该系统分类为 Standard_Distro
3. WHEN `ID` 字段值为 `openEuler`、`anolis`、`alinux`、`opencloudos`、`kylin`（且 `ID_LIKE` 包含 `rhel` 或 `centos` 或 `fedora`）、`amzn`（且 `VERSION_ID` 为 `2023`）或 `ol` 时，THE OS_Detection SHALL 将该系统分类为 Unsupported_RPM_Distro
4. WHEN `ID` 字段值为 `amzn` 且 `VERSION_ID` 为 `2023` 时，THE OS_Detection SHALL 将该系统映射到 EPEL 9 兼容仓库路径
5. WHEN `ID` 字段值为 `ol` 且 `VERSION_ID` 主版本为 `8` 时，THE OS_Detection SHALL 将该系统映射到 EPEL 8 兼容仓库路径
6. WHEN `ID` 字段值为 `ol` 且 `VERSION_ID` 主版本为 `9` 时，THE OS_Detection SHALL 将该系统映射到 EPEL 9 兼容仓库路径
7. IF `/etc/os-release` 文件不存在，THEN THE OS_Detection SHALL 输出错误信息并以退出码 2 终止脚本
8. IF 检测到的操作系统不属于任何已知分类，THEN THE OS_Detection SHALL 输出警告信息并回退到 Caddy_Download_API 安装方式
9. THE OS_Detection SHALL 检测系统 CPU 架构，识别 `x86_64`（amd64）和 `aarch64`（arm64）为必须支持的架构
10. WHEN 检测到的 CPU 架构为 `loongarch64` 或 `riscv64` 时，THE OS_Detection SHALL 将其标记为可选支持架构并尝试继续安装
11. IF 检测到的 CPU 架构不属于已知支持列表，THEN THE OS_Detection SHALL 输出错误信息并以退出码 2 终止脚本

### 需求 2：已安装检测与跳过

**用户故事：** 作为脚本调用者，我希望脚本在 Caddy 已安装时自动跳过安装过程，以避免重复安装。

#### 验收标准

1. THE Installer SHALL 在执行任何安装操作之前，通过 `command -v caddy` 检测 Caddy 是否已安装
2. WHEN `command -v caddy` 返回成功且未指定 `--version` 参数时，THE Installer SHALL 输出已安装的 Caddy 路径到 stdout 并以退出码 0 正常退出
3. WHEN `command -v caddy` 返回成功且指定了 `--version` 参数时，THE Installer SHALL 比较已安装版本与目标版本，若版本一致则跳过安装
4. WHEN 已安装版本与 `--version` 指定的目标版本不一致时，THE Installer SHALL 继续执行安装流程以更新 Caddy

### 需求 3：官方 APT 仓库安装（标准 Debian 系发行版）

**用户故事：** 作为标准 Debian/Ubuntu 系统的用户，我希望脚本使用 Caddy 官方 APT 仓库安装，以获得标准的包管理体验。

#### 验收标准

1. WHEN OS_Detection 将系统分类为 Standard_Distro 且包管理器为 `apt` 时，THE Installer SHALL 使用 Official_APT_Repo 进行安装
2. THE Installer SHALL 安装 `debian-keyring`、`debian-archive-keyring` 和 `apt-transport-https` 依赖包
3. THE Installer SHALL 通过 `curl` 获取 Cloudsmith GPG 密钥并存储到 `/usr/share/keyrings/` 目录
4. THE Installer SHALL 将 Caddy 官方 APT 源写入 `/etc/apt/sources.list.d/caddy-stable.list`，使用 `any-version` 作为 distribution
5. WHEN APT 仓库配置完成后，THE Installer SHALL 执行 `apt-get update` 并安装 `caddy` 包
6. IF APT 仓库安装过程中任一步骤失败，THEN THE Installer SHALL 输出错误详情到 stderr 并回退到 Caddy_Download_API 安装方式

### 需求 4：官方 COPR 仓库安装（标准 RHEL 系发行版）

**用户故事：** 作为标准 Fedora/CentOS/RHEL 系统的用户，我希望脚本使用 Caddy 官方 COPR 仓库安装，以获得标准的包管理体验。

#### 验收标准

1. WHEN OS_Detection 将系统分类为 Standard_Distro 且包管理器为 `dnf` 或 `yum` 时，THE Installer SHALL 使用 Official_COPR_Repo 进行安装
2. THE Installer SHALL 执行 `dnf install -y 'dnf-command(copr)'` 安装 COPR 插件
3. THE Installer SHALL 执行 `dnf copr enable -y @caddy/caddy` 启用 Caddy COPR 仓库
4. WHEN COPR 仓库启用后，THE Installer SHALL 执行 `dnf install -y caddy` 安装 Caddy 包
5. IF COPR 仓库安装过程中任一步骤失败，THEN THE Installer SHALL 输出错误详情到 stderr 并回退到 Caddy_Download_API 安装方式

### 需求 5：自建 DNF 仓库安装（COPR 不支持的 RPM 系发行版）

**用户故事：** 作为 COPR 不支持的 RPM 系发行版的用户，我希望脚本通过自建 DNF 仓库安装 Caddy RPM 包，以绕过 COPR 的兼容性限制。

#### 验收标准

1. WHEN OS_Detection 将系统分类为 Unsupported_RPM_Distro 时，THE Installer SHALL 使用 Self_Hosted_Repo 进行安装
2. THE Installer SHALL 根据 OS_Detection 检测到的 EPEL 兼容版本（EPEL 8 或 EPEL 9）选择对应的仓库路径
3. THE Installer SHALL 将自建仓库的 `.repo` 配置文件写入 `/etc/yum.repos.d/` 目录
4. THE Installer SHALL 导入自建仓库的 GPG 公钥用于包签名验证
5. WHEN 仓库配置完成后，THE Installer SHALL 通过 `dnf install -y caddy` 或 `yum install -y caddy` 安装 Caddy 包
6. THE Installer SHALL 根据 OS_Detection 检测到的架构（x86_64 或 aarch64）选择对应的仓库 baseurl
7. IF 自建 DNF 仓库安装过程中任一步骤失败，THEN THE Installer SHALL 输出错误详情到 stderr 并回退到 Caddy_Download_API 安装方式
8. THE Installer SHALL 支持通过 `--mirror` 参数指定自建仓库的镜像地址


### 需求 6：官方 API 静态二进制下载（终极 Fallback）

**用户故事：** 作为任意 Linux 系统的用户，我希望在包仓库方式均失败时，脚本能通过 Caddy 官方 API 下载静态二进制文件完成安装。

#### 验收标准

1. WHEN 包仓库安装方式失败或用户通过 `--method binary` 指定时，THE Installer SHALL 使用 Caddy_Download_API 下载静态二进制文件
2. THE Installer SHALL 根据检测到的操作系统和架构构造正确的下载 URL（`https://caddyserver.com/api/download?os=linux&arch={arch}`）
3. WHEN 指定了 `--version` 参数时，THE Installer SHALL 在下载 URL 中附加 `&version={version}` 参数
4. THE Installer SHALL 将下载的二进制文件安装到 `--prefix` 指定的目录（默认 `/usr/local/bin/caddy`）
5. THE Installer SHALL 为安装的二进制文件设置可执行权限（`chmod +x`）
6. IF 下载过程中连接超时超过 30 秒，THEN THE Installer SHALL 输出网络错误信息并以退出码 3 终止脚本
7. IF 下载过程中总耗时超过 120 秒，THEN THE Installer SHALL 输出网络超时信息并以退出码 3 终止脚本
8. IF 下载的文件大小为 0 或文件校验失败，THEN THE Installer SHALL 删除无效文件、输出错误信息并以退出码 1 终止脚本

### 需求 7：脚本命令行接口

**用户故事：** 作为脚本调用者，我希望通过命令行参数控制安装行为，以适应不同的部署场景。

#### 验收标准

1. THE Installer SHALL 支持以下命令行参数：`--version`、`--method`、`--prefix`、`--mirror`、`--skip-service`、`--skip-cap`、`-y`/`--yes`、`-h`/`--help`
2. WHEN 指定 `--version` 参数时，THE Installer SHALL 安装指定版本的 Caddy
3. WHEN 指定 `--method repo` 时，THE Installer SHALL 仅使用包仓库方式安装，失败时不回退到二进制下载
4. WHEN 指定 `--method binary` 时，THE Installer SHALL 直接使用 Caddy_Download_API 下载安装
5. WHEN 指定 `--prefix` 参数时，THE Installer SHALL 将二进制文件安装到指定目录（仅对 binary 方式生效）
6. WHEN 指定 `--mirror` 参数时，THE Installer SHALL 使用指定的镜像地址替代默认仓库地址
7. WHEN 指定 `--skip-service` 参数时，THE Installer SHALL 跳过 systemd 服务处理步骤
8. WHEN 指定 `--skip-cap` 参数时，THE Installer SHALL 跳过 `setcap` 权限设置步骤
9. WHEN 指定 `-y` 或 `--yes` 参数时，THE Installer SHALL 自动确认所有交互式提示
10. WHEN 指定 `-h` 或 `--help` 参数时，THE Installer SHALL 输出帮助信息并以退出码 0 退出
11. IF 收到未知参数，THEN THE Installer SHALL 输出错误信息和帮助提示并以退出码 1 终止脚本
12. THE Installer SHALL 支持通过管道调用（`curl -fsSL ... | bash`）和直接执行（`bash install-caddy.sh [OPTIONS]`）两种方式

### 需求 8：systemd 服务处理

**用户故事：** 作为 WebCasa 项目的集成方，我希望脚本在包管理器安装后禁用 Caddy 默认的 systemd 服务，以避免与 WebCasa 自身的 Caddy 管理逻辑冲突。

#### 验收标准

1. WHEN 通过包管理器安装 Caddy 且未指定 `--skip-service` 参数时，THE Installer SHALL 检测 `caddy.service` 是否存在
2. WHEN `caddy.service` 存在且处于运行状态时，THE Installer SHALL 执行 `systemctl stop caddy.service` 停止服务
3. WHEN `caddy.service` 存在且处于启用状态时，THE Installer SHALL 执行 `systemctl disable caddy.service` 禁用服务
4. IF `systemctl` 命令不可用（如容器环境），THEN THE Installer SHALL 跳过服务处理并输出提示信息到 stderr

### 需求 9：权限设置

**用户故事：** 作为 WebCasa 项目的集成方，我希望 Caddy 二进制文件具有绑定低端口的能力，以便在非 root 用户下监听 80/443 端口。

#### 验收标准

1. WHEN 安装完成且未指定 `--skip-cap` 参数时，THE Installer SHALL 对 Caddy 二进制文件执行 `setcap 'cap_net_bind_service=+ep'`
2. IF `setcap` 命令不可用，THEN THE Installer SHALL 输出警告信息到 stderr 提示用户手动安装 `libcap2-bin`（Debian 系）或 `libcap`（RPM 系）
3. IF `setcap` 执行失败，THEN THE Installer SHALL 输出警告信息到 stderr 但不终止脚本（以非致命错误处理）

### 需求 10：退出码与输出约定

**用户故事：** 作为脚本调用者（WebCasa），我希望脚本遵循明确的退出码和输出约定，以便程序化地判断安装结果。

#### 验收标准

1. THE Installer SHALL 在安装成功时以退出码 0 退出
2. THE Installer SHALL 在一般性安装失败时以退出码 1 退出
3. THE Installer SHALL 在操作系统或架构不支持时以退出码 2 退出
4. THE Installer SHALL 在网络错误时以退出码 3 退出
5. THE Installer SHALL 在权限不足（非 root 且无 sudo）时以退出码 4 退出
6. THE Installer SHALL 在安装成功时将 Caddy 二进制文件的绝对路径作为最后一行输出到 stdout
7. THE Installer SHALL 将所有日志信息（进度、警告、错误）输出到 stderr
8. THE Installer SHALL 使用彩色输出区分信息级别：绿色表示成功，黄色表示警告，红色表示错误，蓝色表示信息
9. WHEN stdout 不是终端（被管道或重定向）时，THE Installer SHALL 禁用彩色输出

### 需求 11：WebCasa 兼容性契约

**用户故事：** 作为 WebCasa 项目的集成方，我希望安装后的 Caddy 满足 WebCasa 的运行时要求。

#### 验收标准

1. THE Installer SHALL 确保安装后的 Caddy 二进制文件位于 `$PATH` 中，或安装到 `/usr/bin/caddy` 或 `/usr/local/bin/caddy`
2. THE Installer SHALL 在安装完成后验证 `caddy version` 命令可正常执行
3. IF `caddy version` 验证失败，THEN THE Installer SHALL 输出错误信息并以退出码 1 终止脚本
4. THE Installer SHALL 确保安装的 Caddy 支持 `start`、`stop`、`reload`、`validate`、`fmt`、`version` 子命令
5. WHEN 安装完成后，THE Installer SHALL 验证 Caddy Admin API 默认监听地址为 `http://localhost:2019`（通过 `caddy version` 确认二进制可用即可，不启动服务验证）

### 需求 12：网络环境适配

**用户故事：** 作为中国大陆的用户，我希望脚本在网络超时和镜像源方面做合理适配，以应对网络不稳定的情况。

#### 验收标准

1. THE Installer SHALL 为所有网络请求设置 30 秒的连接超时（`curl --connect-timeout 30`）
2. THE Installer SHALL 为所有下载操作设置 120 秒的最大超时（`curl --max-time 120`）
3. WHEN 指定 `--mirror` 参数时，THE Installer SHALL 使用镜像地址替代默认的仓库 URL 或下载 URL
4. THE Installer SHALL 在网络请求失败时输出具体的错误原因（DNS 解析失败、连接超时、SSL 错误等）到 stderr

### 需求 13：代码质量与兼容性

**用户故事：** 作为开发者，我希望脚本代码质量高且兼容性好，以便维护和在各种环境中可靠运行。

#### 验收标准

1. THE Installer SHALL 使用纯 Bash 编写，兼容 Bash 4.0 及以上版本
2. THE Installer SHALL 在脚本开头设置 `set -euo pipefail` 启用严格模式
3. THE Installer SHALL 采用函数化组织结构，每个主要功能封装为独立函数
4. THE Installer SHALL 使用中文注释说明关键逻辑，使用英文命名变量和函数
5. THE Installer SHALL 在脚本开头检测 root 权限或 sudo 可用性，权限不足时以退出码 4 终止
6. IF 脚本执行过程中收到 `SIGINT` 或 `SIGTERM` 信号，THEN THE Installer SHALL 清理临时文件并以非零退出码退出
