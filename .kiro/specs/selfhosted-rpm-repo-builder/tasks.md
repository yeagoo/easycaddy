# 实施计划：自建 RPM 仓库构建系统（产品线架构）

## 概述

基于需求和设计文档，将自建 RPM 仓库构建系统拆分为增量式编码任务。核心脚本为 `build-repo.sh`（纯 Bash），按产品线组织构建，通过符号链接提供发行版友好路径。每个任务在前一任务基础上递进，最终完成完整的构建系统。

## 任务

- [x] 1. 创建项目骨架与核心数据结构
  - [x] 1.1 创建 `build-repo.sh` 脚本骨架，包含 shebang、`set -euo pipefail`、`_SOURCED_FOR_TEST` 模式支持、全局变量声明（`OPT_VERSION`、`OPT_OUTPUT`、`OPT_GPG_KEY_ID`、`OPT_GPG_KEY_FILE`、`OPT_ARCH`、`OPT_DISTRO`、`OPT_BASE_URL`、`OPT_STAGE`、`OPT_ROLLBACK`、`OPT_SM2_KEY`、`CADDY_VERSION`、`TARGET_ARCHS`、`TARGET_PRODUCT_LINES`、`STAGING_DIR`、`BUILD_START_TIME`、`RPM_COUNT`、`SYMLINK_COUNT`）
    - 创建日志函数 `util_log_info` 和 `util_log_error`，输出到 stderr，格式为 `[INFO]` 和 `[ERROR]`
    - 创建退出码常量：`EXIT_OK=0`、`EXIT_ARG_ERROR=1`、`EXIT_DEP_MISSING=2`、`EXIT_DOWNLOAD_FAIL=3`、`EXIT_PACKAGE_FAIL=4`、`EXIT_SIGN_FAIL=5`、`EXIT_METADATA_FAIL=6`、`EXIT_PUBLISH_FAIL=7`、`EXIT_VERIFY_FAIL=8`
    - _Requirements: 18.1, 18.2, 18.3, 18.4_

  - [x] 1.2 实现产品线映射模块：定义 `PRODUCT_LINE_PATHS`、`PRODUCT_LINE_TAGS`、`PRODUCT_LINE_COMPRESS`、`DISTRO_TO_PRODUCT_LINE` 关联数组，以及符号链接映射数据
    - 实现 `resolve_product_lines "$distro_spec"` 函数：将 `--distro` 参数值解析为产品线 ID 集合，`all` 返回全部 7 条产品线，无效 distro:version 以退出码 1 终止
    - 实现 `get_product_line_path "$pl_id"`、`get_product_line_tag "$pl_id"`、`get_compress_type "$pl_id"` 辅助函数
    - openEuler 20 应输出警告到 stderr 并跳过
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 1.3 编写产品线映射属性测试
    - **Property 1: 产品线映射正确性**
    - **Validates: Requirements 1.1, 1.3, 1.4**
    - 创建 `tests/test_helper/generators_repo.bash`，包含 `KNOWN_PRODUCT_LINES`、`KNOWN_DISTRO_VERSIONS` 数组及 `gen_valid_distro_version`、`gen_invalid_distro_version`、`gen_product_line_id` 等生成器函数
    - 创建 `tests/property/test_prop_product_line.bats`，循环 100 次随机输入验证映射正确性

  - [x] 1.4 编写产品线映射单元测试
    - 创建 `tests/unit/test_product_line_map.bats`
    - 测试每个 distro:version 的具体映射结果、openEuler 20 警告、无效输入错误处理
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 2. 实现命令行参数解析与依赖检查
  - [x] 2.1 实现 `parse_args "$@"` 函数，解析所有命令行参数（`--version`、`--output`、`--gpg-key-id`、`--gpg-key-file`、`--arch`、`--distro`、`--base-url`、`--stage`、`--rollback`、`--sm2-key`、`-h`/`--help`）
    - 验证 `--arch` 仅接受 `x86_64`、`aarch64` 或 `all`
    - 验证 `--stage` 仅接受 `build`、`sign`、`publish`、`verify`
    - 无效参数以退出码 1 终止，输出描述性错误信息
    - 实现 `parse_show_help` 函数输出用法说明
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 16.1_

  - [x] 2.2 编写命令行参数解析属性测试
    - **Property 2: 命令行参数解析正确性**
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.8, 20.2**
    - 创建 `tests/property/test_prop_build_args.bats`，在 `generators_repo.bash` 中添加 `gen_caddy_version_number`、`gen_distro_spec`、`gen_base_url`、`gen_stage_name` 等生成器

  - [x] 2.3 编写命令行参数解析单元测试
    - 创建 `tests/unit/test_build_parse_args.bats`
    - 测试各参数正确解析、默认值、`--help` 输出、`--rollback` 标志、无效参数错误
    - _Requirements: 2.1–2.9_

  - [x] 2.4 实现依赖检查模块：`check_dependencies` 函数检查 `curl`、`nfpm`、`createrepo_c`（或 `createrepo`）、`gpg`、`rpm` 可用性；`check_gpg_key "$key_id"` 函数检查 GPG 密钥存在性
    - 缺失工具输出名称和安装建议，退出码 2
    - GPG 密钥不存在退出码 2
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 2.5 编写依赖检查属性测试
    - **Property 3: 依赖检查正确性**
    - **Validates: Requirements 3.1, 3.2**
    - 创建 `tests/property/test_prop_dep_check.bats`

  - [x] 2.6 编写依赖检查单元测试
    - 创建 `tests/unit/test_dependency_check.bats`
    - 测试各工具存在/缺失组合、GPG 密钥存在/不存在
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 3. 检查点 - 确保核心数据结构和参数解析测试通过
  - 确保所有测试通过，如有疑问请询问用户。

- [x] 4. 实现版本查询与二进制下载
  - [x] 4.1 实现 `resolve_version` 函数：当 `OPT_VERSION` 为空时，通过 GitHub Releases API 查询最新稳定版本号，从 `tag_name` 字段提取版本号并去除 `v` 前缀，设置 `CADDY_VERSION` 全局变量
    - 版本确定后输出到 stderr
    - 查询失败退出码 3
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 2.7_

  - [x] 4.2 编写版本号提取属性测试
    - **Property 20: 版本号提取正确性**
    - **Validates: Requirements 14.2**
    - 创建 `tests/property/test_prop_version_extract.bats`

  - [x] 4.3 编写版本查询单元测试
    - 创建 `tests/unit/test_version_query.bats`
    - 测试 API 响应解析、v 前缀去除、网络失败处理
    - _Requirements: 14.1, 14.2, 14.3_

  - [x] 4.4 实现 `download_caddy_binary "$arch"` 函数：优先使用 `vendor/caddy-{version}-linux-{go_arch}` 本地文件，不存在时从 `https://caddyserver.com/api/download?os=linux&arch={go_arch}&version={version}` 下载
    - 架构映射：`x86_64` → `amd64`、`aarch64` → `arm64`
    - 验证下载文件大小 > 0 字节，否则退出码 3
    - 下载失败输出 HTTP 状态码或 curl 错误码，退出码 3
    - 同一架构仅下载一次，跨产品线复用
    - _Requirements: 4.1, 4.2, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [x] 4.5 编写 vendor/ 目录查找属性测试
    - **Property 4: vendor/ 目录二进制文件查找**
    - **Validates: Requirements 4.1, 4.2**
    - 创建 `tests/property/test_prop_vendor_lookup.bats`

  - [x] 4.6 编写下载 URL 构造属性测试
    - **Property 5: 下载 URL 构造正确性**
    - **Validates: Requirements 5.1, 5.2**
    - 创建 `tests/property/test_prop_download_url.bats`

  - [x] 4.7 编写架构去重属性测试
    - **Property 6: 每架构仅下载一次**
    - **Validates: Requirements 5.6**
    - 创建 `tests/property/test_prop_arch_dedup.bats`

- [x] 5. 实现 RPM 打包模块（nfpm）
  - [x] 5.1 创建 RPM 打包所需的静态资源文件
    - 创建 `packaging/caddy.service` systemd 服务单元文件，包含 `User=caddy`、`Group=caddy`、`AmbientCapabilities=CAP_NET_BIND_SERVICE`、XDG 路径配置、安全加固配置（`ProtectSystem=full`、`ProtectHome=true`、`PrivateTmp=true`、`NoNewPrivileges=true`）
    - 创建 `packaging/Caddyfile` 默认配置文件
    - 创建 `packaging/scripts/postinstall.sh`：创建 caddy 系统用户和组（如不存在）、执行 `systemctl daemon-reload`
    - 创建 `packaging/scripts/preremove.sh`：执行 `systemctl stop caddy.service && systemctl disable caddy.service`
    - 创建 `packaging/LICENSE`（Apache License 2.0）
    - _Requirements: 6.4, 6.5, 6.6, 6.7, 6.10, 6.11, 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x] 5.2 实现 `generate_nfpm_config "$pl_id" "$arch"` 函数：动态生成 nfpm YAML 配置文件
    - 包含正确的版本号、架构、产品线标签（release 字段）
    - 根据产品线选择压缩算法：EL8 使用 xz，其他使用 zstd
    - 包含所有 contents 条目（二进制、systemd 服务、Caddyfile、LICENSE、目录）
    - 包含 scripts 条目（postinstall、preremove）
    - 如提供 `OPT_GPG_KEY_FILE`，包含 `rpm.signature.key_file` 配置
    - _Requirements: 6.1, 6.3, 6.8, 6.9, 9.2_

  - [x] 5.3 实现 `build_rpm "$pl_id" "$arch"` 函数：调用 nfpm 生成 RPM 包
    - RPM 文件名格式：`caddy-{version}-1.{pl_tag}.{arch}.rpm`
    - 幂等性：如目标目录已存在相同版本 RPM 包，跳过并输出提示到 stderr
    - nfpm 失败退出码 4
    - _Requirements: 6.1, 6.2, 6.3, 6.12, 15.1_

  - [x] 5.4 编写 RPM 包数量属性测试
    - **Property 7: RPM 包数量正确性**
    - **Validates: Requirements 6.2**
    - 创建 `tests/property/test_prop_rpm_count.bats`

  - [x] 5.5 编写 RPM 文件名格式属性测试
    - **Property 8: RPM 文件名格式正确性**
    - **Validates: Requirements 6.3**
    - 创建 `tests/property/test_prop_rpm_filename.bats`

  - [x] 5.6 编写 nfpm 配置完整性属性测试
    - **Property 9: nfpm 配置完整性**
    - **Validates: Requirements 6.4, 6.5, 6.6, 6.7, 6.8, 6.10, 6.11**
    - 创建 `tests/property/test_prop_nfpm_config.bats`

  - [x] 5.7 编写压缩算法映射属性测试
    - **Property 10: 压缩算法映射正确性**
    - **Validates: Requirements 6.9**
    - 创建 `tests/property/test_prop_compress.bats`

  - [x] 5.8 编写 nfpm 配置生成单元测试
    - 创建 `tests/unit/test_nfpm_config.bats`
    - 测试 systemd 服务文件内容验证（User=caddy、AmbientCapabilities 等）、各产品线压缩算法、GPG 签名配置
    - _Requirements: 6.1–6.12, 7.1–7.5_

- [x] 6. 检查点 - 确保下载和打包模块测试通过
  - 确保所有测试通过，如有疑问请询问用户。

- [x] 7. 实现 GPG 签名与仓库元数据生成
  - [x] 7.1 实现 GPG 签名模块
    - 实现 `sign_rpm "$rpm_path"` 函数：优先使用 nfpm 内置签名（`rpm.signature.key_file`），回退到 `rpm --addsign`
    - 实现 `verify_rpm_signature "$rpm_path"` 函数：使用 `rpm -K` 验证签名
    - 实现 `sign_repomd "$repomd_path"` 函数：使用 `gpg --detach-sign --armor` 生成 `repomd.xml.asc`
    - 实现 `export_gpg_pubkey "$output_path"` 函数：导出 GPG 公钥到 `gpg.key`
    - 签名失败退出码 5，验证失败退出码 5
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 10.8, 10.9_

  - [x] 7.2 实现仓库元数据生成模块
    - 实现 `generate_repodata "$repo_dir"` 函数：调用 `createrepo_c --general-compress-type=xz --update`
    - 将签名后的 RPM 包放置到 `{output_dir}/caddy/{pl_path}/{arch}/Packages/` 目录
    - 验证每个产品线/架构目录中存在 `repodata/repomd.xml`
    - 已有 repodata 时使用 `--update` 增量更新
    - createrepo 失败退出码 6
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7_

  - [x] 7.3 编写仓库目录结构属性测试
    - **Property 11: 仓库目录结构正确性**
    - **Validates: Requirements 10.1, 10.2**
    - 创建 `tests/property/test_prop_repo_dir.bats`

  - [x] 7.4 编写 repodata 生成属性测试
    - **Property 12: repodata 生成与验证**
    - **Validates: Requirements 10.3, 10.7**
    - 创建 `tests/property/test_prop_repodata.bats`

- [x] 8. 实现符号链接生成与 .repo 模板
  - [x] 8.1 实现 `generate_symlinks` 函数：遍历 `DISTRO_TO_PRODUCT_LINE` 映射表，为每个 distro:version 创建相对路径符号链接
    - Fedora 产品线不生成版本符号链接
    - 实现 `validate_symlinks` 函数：验证所有符号链接指向有效目标
    - 符号链接目标不存在时输出警告到 stderr 并跳过
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

  - [x] 8.2 编写符号链接生成属性测试
    - **Property 13: 符号链接生成正确性**
    - **Validates: Requirements 11.1, 11.2, 11.3, 11.4**
    - 创建 `tests/property/test_prop_symlinks.bats`

  - [x] 8.3 编写符号链接生成单元测试
    - 创建 `tests/unit/test_symlink_generation.bats`
    - 测试相对路径验证、Fedora 不生成版本链接、目标不存在时的警告
    - _Requirements: 11.1–11.5_

  - [x] 8.4 实现 `generate_repo_templates` 函数：为每个 distro:version 生成 `.repo` 配置文件模板
    - 文件命名：`caddy-{distro_id}-{distro_version}.repo`
    - baseurl 使用发行版友好路径：`{base_url}/caddy/{distro_id}/{distro_version}/$basearch/`
    - Fedora 特殊处理：baseurl 为 `{base_url}/caddy/fedora/$basearch/`（不含版本号）
    - 包含 `gpgcheck=1`、`repo_gpgcheck=1`、`gpgkey={base_url}/caddy/gpg.key`
    - 包含 SELinux 安装说明注释
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6, 8.4_

  - [x] 8.5 编写 .repo 模板生成属性测试
    - **Property 14: .repo 模板生成正确性**
    - **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
    - 创建 `tests/property/test_prop_repo_template.bats`，在 `generators_repo.bash` 中添加 `gen_base_url` 生成器

  - [x] 8.6 编写 .repo 模板生成单元测试
    - 创建 `tests/unit/test_repo_template.bats`
    - 测试 Fedora 特殊处理、SELinux 安装说明、name 字段格式
    - _Requirements: 13.1–13.6_

- [x] 9. 实现原子发布与回滚
  - [x] 9.1 实现原子发布模块
    - 实现 `atomic_publish` 函数：构建产物先写入 `{output_dir}/.staging/`，构建完成后通过 `mv` 原子交换到正式目录
    - 交换前将当前正式目录备份到 `{output_dir}/.rollback/{timestamp}/`
    - 实现 `rollback_latest` 函数：恢复最近一次备份
    - 实现 `cleanup_old_backups` 函数：保留最近 3 个备份，清理更早的
    - 原子交换失败保留 staging 目录不删除，退出码 7
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_

  - [x] 9.2 编写回滚备份保留策略属性测试
    - **Property 15: 回滚备份保留策略**
    - **Validates: Requirements 12.6**
    - 创建 `tests/property/test_prop_backup_retention.bats`

  - [x] 9.3 编写原子发布单元测试
    - 创建 `tests/unit/test_atomic_publish.bats`
    - 测试 staging → 交换流程、回滚恢复、交换失败保留 staging、备份清理
    - _Requirements: 12.1–12.6_

- [x] 10. 检查点 - 确保签名、元数据、符号链接、模板和发布模块测试通过
  - 确保所有测试通过，如有疑问请询问用户。

- [x] 11. 实现 CI/CD 阶段控制与验证测试
  - [x] 11.1 实现 CI/CD 阶段控制逻辑：根据 `--stage` 参数执行对应阶段（`build`、`sign`、`publish`、`verify`），未指定时按顺序执行全部阶段
    - 每个阶段完成后输出 `[STAGE] {stage_name}: completed` 到 stderr
    - 任一阶段失败停止后续阶段执行
    - _Requirements: 16.1, 16.2, 16.3, 16.4_

  - [x] 11.2 实现验证测试模块（verify 阶段）
    - 实现 `verify_rpmlint` 函数：对每个 RPM 包执行 `rpmlint`
    - 实现 `verify_repodata` 函数：验证 `repomd.xml` 存在且格式正确
    - 实现 `verify_signatures` 函数：验证 RPM 签名（`rpm -K`）和 `repomd.xml.asc`（`gpg --verify`）
    - 实现 `verify_symlinks` 函数：验证所有符号链接有效
    - 任一验证失败退出码 8
    - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5, 17.6_

  - [x] 11.3 编写 CI/CD 阶段控制属性测试
    - **Property 17: CI/CD 阶段控制**
    - **Validates: Requirements 16.1, 16.3**
    - 创建 `tests/property/test_prop_stage_control.bats`

  - [x] 11.4 编写幂等性属性测试
    - **Property 16: 幂等性**
    - **Validates: Requirements 15.1, 15.2**
    - 创建 `tests/property/test_prop_idempotent.bats`

- [x] 12. 实现日志输出规范与主流程串联
  - [x] 12.1 实现主流程函数 `main`：串联所有模块，按阶段顺序执行 Build → Sign → Publish → Verify
    - 信号处理：`trap cleanup EXIT`、`trap 'util_log_error "收到中断信号，正在清理..."; exit 130' INT TERM`
    - `cleanup` 函数清理临时目录中间文件
    - 构建完成后输出构建摘要到 stderr（产品线数量、RPM 包总数、符号链接数量、总耗时）
    - stdout 仅输出最终仓库根目录绝对路径
    - 临时目录在完成或失败时清理
    - _Requirements: 15.3, 18.1, 18.3, 18.4, 18.5_

  - [x] 12.2 编写日志输出规范属性测试
    - **Property 18: 日志输出规范性**
    - **Validates: Requirements 18.1, 18.3, 18.4**
    - 创建 `tests/property/test_prop_log_stderr.bats`

  - [x] 12.3 编写退出码映射属性测试
    - **Property 19: 退出码映射正确性**
    - **Validates: Requirements 18.2**
    - 创建 `tests/property/test_prop_exit_codes_repo.bats`

- [x] 13. 检查点 - 确保阶段控制、验证和日志模块测试通过
  - 确保所有测试通过，如有疑问请询问用户。

- [x] 14. 实现辅助脚本与离线构建支持
  - [x] 14.1 创建 `vendor-download.sh` 辅助脚本
    - 接受 `--version <VERSION>` 参数
    - 为 x86_64（amd64）和 aarch64（arm64）下载 Caddy 二进制文件到 `vendor/` 目录
    - 文件命名：`vendor/caddy-{version}-linux-{go_arch}`
    - 构建过程中设置 `GOPROXY=off` 和 `CGO_ENABLED=0` 环境变量
    - _Requirements: 4.1, 4.3, 4.4_

  - [x] 14.2 实现 SELinux 可选子包 `caddy-selinux` 的构建逻辑
    - 作为独立 RPM 子包构建
    - postinstall 加载 SELinux 策略模块，preremove 移除
    - 主包 `caddy` 不依赖此子包
    - _Requirements: 8.1, 8.2, 8.3_

  - [x] 14.3 实现国密产品线支持（可选）
    - 当 `--sm2-key` 参数提供时，使用 SM2 密钥签名、SM3 摘要算法
    - 输出到独立目录 `{output_dir}/caddy-sm/`
    - 生成独立的 `gpg-sm2.key` 公钥文件
    - _Requirements: 20.1, 20.2, 20.3, 20.4_

- [x] 15. 更新 install-caddy.sh 联动逻辑
  - [x] 15.1 修改 `install-caddy.sh` 中的 `detect_classify` 函数，新增 `OS_MAJOR_VERSION` 全局变量
    - 为每个支持的发行版正确设置 `OS_MAJOR_VERSION`（如 Anolis 的 `8` 或 `23`，openEuler 的 `22` 或 `24`，Kylin 的 `V10` 或 `V11`，Alibaba Cloud Linux 的 `3` 或 `4`）
    - _Requirements: 19.2_

  - [x] 15.2 修改 `install-caddy.sh` 中的 `_generate_dnf_repo_content` 函数
    - baseurl 使用 `{base_url}/caddy/{OS_ID}/{OS_MAJOR_VERSION}/$basearch/` 格式
    - 包含 `repo_gpgcheck=1`
    - `name` 字段使用发行版名称和版本号（非产品线名称）
    - 保持 `--mirror` 参数兼容性
    - _Requirements: 19.1, 19.3, 19.4, 19.5_

  - [x] 15.3 编写 install-caddy.sh _generate_dnf_repo_content 属性测试
    - **Property 21: _generate_dnf_repo_content 输出正确性**
    - **Validates: Requirements 19.1, 19.3, 19.4, 19.5**
    - 创建 `tests/property/test_prop_dnf_repo_content.bats`

  - [x] 15.4 编写 install-caddy.sh OS_MAJOR_VERSION 属性测试
    - **Property 22: OS_MAJOR_VERSION 设置正确性**
    - **Validates: Requirements 19.2**
    - 创建 `tests/property/test_prop_os_major_ver.bats`

  - [x] 15.5 编写 install-caddy.sh 联动更新单元测试
    - 创建 `tests/unit/test_install_caddy_update.bats`
    - 测试 OS_MAJOR_VERSION 设置、repo_gpgcheck=1、name 字段格式
    - _Requirements: 19.1–19.5_

- [x] 16. 最终检查点 - 确保所有测试通过
  - 确保所有测试通过，如有疑问请询问用户。

## 备注

- 标记 `*` 的任务为可选任务，可跳过以加速 MVP 交付
- 每个任务引用了具体的需求编号，确保可追溯性
- 检查点任务确保增量验证
- 属性测试验证通用正确性属性（每个属性循环 100 次随机输入）
- 单元测试验证具体示例和边界情况
- 所有代码使用 Bash 实现，与现有 `install-caddy.sh` 保持一致的技术栈
- 测试框架使用 bats-core，与现有测试保持一致
