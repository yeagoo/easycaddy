# 实现计划：Caddy Server 中国发行版安装脚本

## 概述

将 `install-caddy.sh` 安装脚本按模块逐步实现，从工具函数和参数解析开始，逐步构建 OS 检测、各安装策略、后置处理，最终集成为完整脚本。每个步骤增量构建，确保代码始终可运行。使用 bats-core 作为测试框架。

## 任务

- [x] 1. 搭建项目结构与工具函数模块
  - [x] 1.1 创建 `install-caddy.sh` 脚本骨架
    - 创建文件，添加 shebang (`#!/usr/bin/env bash`)、`set -euo pipefail` 严格模式
    - 定义所有全局变量（参数解析结果、OS 检测结果、运行时状态）并赋初始值
    - 实现 `util_has_color` 函数：检测 stderr 是否为终端，设置 `USE_COLOR`
    - 实现 `util_log_info`、`util_log_success`、`util_log_warn`、`util_log_error` 四个日志函数，根据 `USE_COLOR` 决定是否输出 ANSI 颜色转义序列，所有输出写入 stderr
    - 实现 `util_cleanup` 函数：删除 `TEMP_DIR` 中的临时文件
    - 注册 `trap util_cleanup EXIT` 和 `trap 'util_log_error "收到中断信号，正在清理..."; exit 130' INT TERM`
    - 实现 `util_check_root` 函数：检测 root 权限或 sudo 可用性，不足时以退出码 4 终止
    - _需求: 10.7, 10.8, 10.9, 13.1, 13.2, 13.3, 13.5, 13.6_

  - [x] 1.2 搭建 bats-core 测试框架
    - 创建 `tests/test_helper/generators.bash`：随机数据生成器（随机 OS_ID、版本号、架构字符串、参数组合等）
    - 创建 `tests/test_helper/mock_helpers.bash`：Mock 工具函数（模拟 os-release 文件、mock 外部命令等）
    - _需求: 13.3_

  - [x] 1.3 编写工具函数单元测试
    - 创建 `tests/unit/test_log_functions.bats`：测试四个日志函数的 stderr 输出、颜色控制
    - 创建 `tests/unit/test_exit_codes.bats`：测试 `util_check_root` 的退出码行为
    - _需求: 10.7, 10.8, 10.9, 13.5_

  - [x] 1.4 编写日志输出属性测试
    - **Property 13: 日志输出规范性**
    - 创建 `tests/property/test_prop_log_output.bats`：循环 100 次随机日志消息，验证输出到 stderr、颜色控制正确
    - **验证需求: 10.7, 10.8, 10.9**


- [x] 2. 实现命令行参数解析模块
  - [x] 2.1 实现 `parse_args` 和 `parse_show_help` 函数
    - 实现 `parse_show_help`：输出帮助信息到 stderr 并以退出码 0 退出
    - 实现 `parse_args "$@"`：使用 `while` + `case` 解析所有参数（`--version`、`--method`、`--prefix`、`--mirror`、`--skip-service`、`--skip-cap`、`-y`/`--yes`、`-h`/`--help`）
    - 设置对应全局变量（OPT_VERSION、OPT_METHOD、OPT_PREFIX、OPT_MIRROR、OPT_SKIP_SERVICE、OPT_SKIP_CAP、OPT_YES）
    - 遇到未知参数时输出错误信息和帮助提示，以退出码 1 终止
    - 验证 `--method` 值仅允许 `repo` 或 `binary`
    - _需求: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12_

  - [x] 2.2 编写参数解析单元测试
    - 创建 `tests/unit/test_parse_args.bats`：测试各参数正确解析、未知参数拒绝、`--help` 输出、`--method` 值验证
    - _需求: 7.1, 7.11_

  - [x] 2.3 编写参数解析属性测试
    - **Property 8: 命令行参数解析正确性**
    - 创建 `tests/property/test_prop_parse_args.bats`：循环 100 次随机有效参数组合，验证全局变量正确设置；循环随机未知参数，验证退出码 1
    - **验证需求: 7.1, 7.2, 7.5, 7.6, 7.11**

- [x] 3. 实现 OS 检测与分类模块
  - [x] 3.1 实现 `detect_os`、`detect_arch`、`detect_classify`、`detect_pkg_manager` 函数
    - 实现 `detect_os`：读取 `/etc/os-release`，提取 `ID`、`ID_LIKE`、`VERSION_ID`、`NAME`、`PLATFORM_ID` 字段。文件不存在时输出错误并以退出码 2 终止
    - 实现 `detect_arch`：通过 `uname -m` 检测架构，映射 `x86_64`→`amd64`、`aarch64`→`arm64`，标记 `loongarch64`/`riscv64` 为可选支持，未知架构退出码 2
    - 实现 `detect_classify`：根据 OS_ID 和 ID_LIKE 分类 OS_CLASS（`standard_deb`/`standard_rpm`/`unsupported_rpm`/`unknown`），设置 EPEL_VERSION
    - EPEL 版本映射：openEuler 20.03/22.03→8, 24.03+→9；anolis/alinux 8.x→8, 23.x→9；opencloudos 8.x→8, 9.x→9；kylin V10→8；amzn 2023→9；ol 8.x→8, 9.x→9
    - 实现 `detect_pkg_manager`：检测 apt/dnf/yum 可用性
    - _需求: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11_

  - [x] 3.2 编写 OS 检测单元测试
    - 创建 `tests/unit/test_detect_os.bats`：测试各已知发行版的检测结果、os-release 缺失处理
    - 创建 `tests/unit/test_detect_arch.bats`：测试各架构映射、loongarch64/riscv64 可选支持、未知架构拒绝
    - _需求: 1.1, 1.7, 1.9, 1.10, 1.11_

  - [x] 3.3 编写 os-release 字段提取属性测试
    - **Property 1: os-release 字段提取正确性**
    - 创建 `tests/property/test_prop_os_release.bats`：循环 100 次随机 os-release 文件内容，验证 `detect_os` 解析后全局变量与文件字段值一致
    - **验证需求: 1.1**

  - [x] 3.4 编写 OS 分类属性测试
    - **Property 2: OS 分类正确性**
    - 创建 `tests/property/test_prop_os_classify.bats`：循环 100 次随机 OS_ID/ID_LIKE 组合，验证 OS_CLASS 分类正确
    - **验证需求: 1.2, 1.3, 1.8**

  - [x] 3.5 编写架构检测属性测试
    - **Property 3: 架构检测与映射正确性**
    - 创建 `tests/property/test_prop_arch_detect.bats`：循环 100 次随机架构字符串，验证映射和退出码正确
    - **验证需求: 1.9, 1.10, 1.11**

  - [x] 3.6 编写 EPEL 版本映射属性测试
    - **Property 4: EPEL 版本映射正确性**
    - 创建 `tests/property/test_prop_epel_mapping.bats`：循环 100 次随机 Unsupported_RPM_Distro 的 OS_ID/VERSION_ID 组合，验证 EPEL_VERSION 正确
    - **验证需求: 1.4, 1.5, 1.6, 5.2**

- [x] 4. 检查点 - 确保基础模块测试通过
  - 确保所有测试通过，如有问题请向用户确认。


- [x] 5. 实现已安装检测模块
  - [x] 5.1 实现 `check_installed` 和 `check_version_match` 函数
    - 实现 `check_installed`：通过 `command -v caddy` 检测 Caddy 是否已安装，返回 0（已安装）或 1（未安装）
    - 实现 `check_version_match`：运行 `caddy version` 提取版本号，与 OPT_VERSION 比较，返回 0（匹配）或 1（不匹配）
    - 在主流程中集成：已安装且版本匹配时输出路径到 stdout 并退出码 0；未指定 `--version` 时已安装即跳过
    - _需求: 2.1, 2.2, 2.3, 2.4_

  - [x] 5.2 编写已安装检测单元测试
    - 创建 `tests/unit/test_check_installed.bats`：测试 caddy 存在/不存在、版本匹配/不匹配场景
    - _需求: 2.1, 2.2, 2.3, 2.4_

  - [x] 5.3 编写版本比较属性测试
    - **Property 5: 版本比较正确性**
    - 创建 `tests/property/test_prop_version_compare.bats`：循环 100 次随机语义化版本字符串对，验证比较结果正确
    - **验证需求: 2.3, 2.4**

- [x] 6. 实现 APT 仓库安装模块
  - [x] 6.1 实现 `install_apt_repo` 函数
    - 安装依赖包：`debian-keyring`、`debian-archive-keyring`、`apt-transport-https`
    - 通过 curl 获取 Cloudsmith GPG 密钥并存储到 `/usr/share/keyrings/caddy-stable-archive-keyring.gpg`
    - 将 APT 源写入 `/etc/apt/sources.list.d/caddy-stable.list`，使用 `any-version` 作为 distribution
    - 支持 `--mirror` 参数替代默认仓库 URL
    - 执行 `apt-get update` 和 `apt-get install -y caddy`
    - 任一步骤失败时返回非零退出码（由调用方决定是否回退）
    - curl 命令包含 `--connect-timeout 30` 和 `--max-time 120`
    - _需求: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 12.1, 12.2_

  - [x] 6.2 编写 APT 源文件属性测试
    - **Property 10: APT 源文件内容正确性**
    - 创建 `tests/property/test_prop_apt_source.bats`：循环 100 次随机镜像地址，验证生成的 APT 源文件内容格式正确
    - **验证需求: 3.4**

- [x] 7. 实现 COPR 仓库安装模块
  - [x] 7.1 实现 `install_copr_repo` 函数
    - 执行 `dnf install -y 'dnf-command(copr)'` 安装 COPR 插件
    - 执行 `dnf copr enable -y @caddy/caddy` 启用仓库
    - 执行 `dnf install -y caddy` 安装 Caddy
    - 任一步骤失败时返回非零退出码
    - _需求: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 8. 实现自建 DNF 仓库安装模块
  - [x] 8.1 实现 `install_selfhosted_repo` 函数
    - 根据 EPEL_VERSION 和 OS_ARCH_RAW 构造仓库 baseurl：`{MIRROR_BASE_URL}/caddy/{epel_version}/{arch}/`
    - 生成 `.repo` 配置文件写入 `/etc/yum.repos.d/caddy-selfhosted.repo`，包含 `gpgcheck=1` 和 `gpgkey` URL
    - 导入 GPG 公钥
    - 通过 `dnf install -y caddy` 或 `yum install -y caddy` 安装
    - 支持 `--mirror` 参数指定镜像地址
    - 任一步骤失败时返回非零退出码
    - _需求: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8_

  - [x] 8.2 编写自建 DNF 仓库配置属性测试
    - **Property 11: 自建 DNF 仓库配置文件正确性**
    - 创建 `tests/property/test_prop_dnf_repo.bats`：循环 100 次随机 EPEL_VERSION/OS_ARCH_RAW/OPT_MIRROR 组合，验证 `.repo` 文件内容正确
    - **验证需求: 5.3, 5.6, 5.8**

- [x] 9. 实现二进制下载安装模块
  - [x] 9.1 实现 `install_binary_download` 函数
    - 构造下载 URL：`https://caddyserver.com/api/download?os=linux&arch={OS_ARCH}`，OPT_VERSION 非空时附加 `&version={OPT_VERSION}`
    - 使用 curl 下载：`--connect-timeout 30`、`--max-time 120`、`-fSL`、`-o {temp_file}`
    - 校验下载文件大小（不为 0）
    - 安装到 `{OPT_PREFIX}/caddy`，设置 `chmod +x`
    - 实现 curl 错误码映射：退出码 6/7/28/35/22 等映射到具体错误描述，统一以退出码 3 终止
    - 下载文件无效时删除文件并以退出码 1 终止
    - _需求: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 12.1, 12.2, 12.3, 12.4_

  - [x] 9.2 编写 URL 构造单元测试
    - 创建 `tests/unit/test_url_construction.bats`：测试各种 OS_ARCH/OPT_VERSION 组合的 URL 构造结果
    - _需求: 6.2, 6.3_

  - [x] 9.3 编写二进制下载 URL 属性测试
    - **Property 9: 二进制下载 URL 构造正确性**
    - 创建 `tests/property/test_prop_url_build.bats`：循环 100 次随机 OS_ARCH/OPT_VERSION 组合，验证 URL 格式正确
    - **验证需求: 6.2, 6.3, 6.4**

  - [x] 9.4 编写网络超时配置属性测试
    - **Property 15: 网络超时配置正确性**
    - 创建 `tests/property/test_prop_curl_timeout.bats`：验证脚本中所有 curl 命令包含正确的超时参数
    - **验证需求: 12.1, 12.2**

  - [x] 9.5 编写网络错误诊断属性测试
    - **Property 16: 网络错误诊断信息**
    - 创建 `tests/property/test_prop_curl_errors.bats`：循环各 curl 错误码，验证输出对应的具体错误描述到 stderr
    - **验证需求: 12.4**

- [x] 10. 检查点 - 确保安装模块测试通过
  - 确保所有测试通过，如有问题请向用户确认。


- [x] 11. 实现后置处理模块
  - [x] 11.1 实现 `post_disable_service`、`post_set_capabilities`、`post_verify` 函数
    - 实现 `post_disable_service`：检测 `systemctl` 可用性，检测 `caddy.service` 是否存在，运行中则 stop，启用状态则 disable。`systemctl` 不可用时跳过并输出提示到 stderr。受 `--skip-service` 控制
    - 实现 `post_set_capabilities`：对 Caddy 二进制执行 `setcap 'cap_net_bind_service=+ep'`。`setcap` 不可用时输出警告提示安装 `libcap2-bin`（Debian 系）或 `libcap`（RPM 系）。执行失败时仅警告不终止。受 `--skip-cap` 控制
    - 实现 `post_verify`：执行 `caddy version` 验证安装成功，失败时以退出码 1 终止
    - _需求: 8.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3, 11.2, 11.3_

  - [x] 11.2 编写后置处理单元测试
    - 创建 `tests/unit/test_post_processing.bats`：测试 systemctl 可用/不可用、setcap 可用/不可用/失败、caddy version 验证成功/失败
    - _需求: 8.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3_

- [x] 12. 集成主流程与 Fallback 逻辑
  - [x] 12.1 实现 `main` 函数，串联所有模块
    - 实现主流程：解析参数 → 检测权限 → 检测 OS/架构 → 检测已安装 → 路由安装方式 → 后置处理 → 输出路径
    - 实现安装方式路由：根据 OPT_METHOD 和 OS_CLASS 选择 APT/COPR/自建仓库/二进制下载
    - 实现 Fallback 逻辑：包仓库失败时，若 `OPT_METHOD != "repo"` 则自动回退到二进制下载；`OPT_METHOD="repo"` 时直接失败退出
    - 确保 stdout 最后一行输出 Caddy 二进制绝对路径
    - 确保安装后 Caddy 位于 `$PATH` 中或 `/usr/bin/caddy` 或 `/usr/local/bin/caddy`
    - _需求: 3.6, 4.5, 5.7, 6.1, 7.3, 7.4, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 11.1, 11.4, 11.5_

  - [x] 12.2 编写安装方式路由属性测试
    - **Property 6: 安装方式路由正确性**
    - 创建 `tests/property/test_prop_routing.bats`：循环 100 次随机 OS_CLASS/OPT_METHOD 组合，验证选择的安装方式正确
    - **验证需求: 3.1, 4.1, 5.1, 6.1**

  - [x] 12.3 编写 Fallback 逻辑属性测试
    - **Property 7: 包仓库失败自动回退**
    - 创建 `tests/property/test_prop_fallback.bats`：模拟包仓库失败，验证 `OPT_METHOD` 非 `repo` 时回退到二进制下载，`repo` 时直接失败
    - **验证需求: 3.6, 4.5, 5.7**

  - [x] 12.4 编写退出码映射属性测试
    - **Property 12: 退出码映射正确性**
    - 创建 `tests/property/test_prop_exit_codes.bats`：循环各错误类别，验证退出码与定义映射一致
    - **验证需求: 10.1, 10.2, 10.3, 10.4, 10.5, 13.5**

  - [x] 12.5 编写 stdout 输出格式属性测试
    - **Property 14: stdout 输出格式正确性**
    - 创建 `tests/property/test_prop_stdout_format.bats`：循环 100 次随机安装路径，验证 stdout 最后一行为绝对路径
    - **验证需求: 10.6**

- [x] 13. 实现管道调用支持与颜色自动检测
  - [x] 13.1 完善管道调用与颜色检测逻辑
    - 确保脚本支持 `curl -fsSL ... | bash` 管道调用方式和 `bash install-caddy.sh [OPTIONS]` 直接执行方式
    - 在脚本入口处检测 stdout 是否为终端（`[[ -t 2 ]]`），非终端时设置 `USE_COLOR=false` 禁用彩色输出
    - _需求: 7.12, 10.9_

- [x] 14. 最终检查点 - 全量测试通过
  - 确保所有测试通过，如有问题请向用户确认。

## 备注

- 标记 `*` 的子任务为可选任务，可跳过以加速 MVP 开发
- 每个任务引用了具体的需求编号，确保可追溯性
- 检查点任务确保增量验证
- 属性测试验证通用正确性属性（每个属性循环 100 次随机输入）
- 单元测试验证具体示例和边界情况
- 所有测试使用 bats-core 框架，通过 mock 隔离外部依赖
