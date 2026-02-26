# 需求文档：自建 RPM 仓库构建系统（产品线架构）

## 简介

本功能为一套自动化构建系统，用于搭建自建的 RPM 仓库，为各类 Linux 发行版提供 Caddy Server 的 RPM 包分发。核心设计理念是**按产品线（Product Line）而非按发行版组织构建和目录结构**。

由于 Caddy 是纯 Go 语言编写的静态编译程序（`CGO_ENABLED=0`），同一架构的二进制文件可跨发行版复用，无 glibc 版本依赖。因此，兼容同一 RPM 版本的发行版被归入同一产品线，每个产品线每个架构仅构建一个 RPM 包。

系统定义 7 条产品线：
- **EL8** — 覆盖 RHEL 8、CentOS Stream 8、AlmaLinux 8、Rocky Linux 8、Anolis 8、Oracle Linux 8、OpenCloudOS 8、Kylin V10、Alibaba Cloud Linux 3
- **EL9** — 覆盖 RHEL 9、CentOS Stream 9、AlmaLinux 9、Rocky Linux 9、Anolis 23、Oracle Linux 9、OpenCloudOS 9、Kylin V11、Alibaba Cloud Linux 4
- **EL10** — 覆盖 RHEL 10、CentOS Stream 10、AlmaLinux 10、Rocky Linux 10、Oracle Linux 10
- **AL2023** — 覆盖 Amazon Linux 2023
- **Fedora** — 覆盖 Fedora 42、Fedora 43（独立产品线，不归入 EL 系列）
- **openEuler 22** — 覆盖 openEuler 22.03 LTS
- **openEuler 24** — 覆盖 openEuler 24.03 LTS

真实目录结构按产品线组织，通过符号链接提供发行版友好路径，使客户端可以使用直觉化的 `{distro}/{version}/` URL 访问仓库。

## 术语表

- **Build_System**: 自建 RPM 仓库构建系统，包含构建脚本及相关配置，本需求的主体系统
- **Build_Script**: 主构建脚本（`build-repo.sh`），Build_System 的核心执行入口
- **Product_Line**: 产品线，一组共享相同 RPM 兼容性的发行版集合，取值为 `el8`、`el9`、`el10`、`al2023`、`fedora`、`openeuler/22`、`openeuler/24`
- **Product_Line_Map**: 产品线映射表，定义每个发行版/版本到其所属 Product_Line 的映射关系
- **Caddy_API**: Caddy 官方二进制下载 API（`https://caddyserver.com/api/download`）
- **RPM_Packager**: 将 Caddy 二进制文件打包为 RPM 格式的组件（使用 nfpm 工具）
- **GPG_Signer**: 使用 GPG 密钥对 RPM 包和仓库元数据进行签名的组件
- **Repo_Generator**: 使用 createrepo 生成 YUM/DNF 仓库元数据的组件
- **Symlink_Generator**: 生成发行版友好路径符号链接的组件
- **Distro_ID**: 发行版标识，与 `/etc/os-release` 中的 `ID` 字段一致（如 `fedora`、`centos`、`rhel`、`almalinux`、`rocky`、`anolis`、`alinux`、`openEuler`、`kylin`、`opencloudos`、`ol`、`amzn`）
- **Distro_Version**: 发行版原生主版本号（如 Anolis 的 `8` 和 `23`，openEuler 的 `20`、`22`、`24`，Kylin 的 `V10`、`V11`，Alibaba Cloud Linux 的 `3`、`4`）
- **Target_Arch**: 目标 CPU 架构，取值为 `x86_64` 或 `aarch64`
- **Output_Directory**: 仓库输出根目录，包含完整的仓库目录结构
- **nfpm**: 一个无需 rpmbuild 即可创建 RPM/DEB 包的打包工具
- **createrepo**: 用于生成 YUM/DNF 仓库元数据（repodata）的标准工具
- **Atomic_Publish**: 原子发布机制，通过目录交换实现零停机部署和回滚
- **Repo_Template**: 客户端 .repo 配置文件模板，为每个支持的发行版生成

## 需求

### 需求 1：产品线映射与发行版支持矩阵

**用户故事：** 作为仓库维护者，我希望系统内置完整的发行版到产品线映射表，以便每个发行版版本都能正确归入对应的产品线进行构建。

#### 验收标准

1. THE Build_System SHALL 内置 Product_Line_Map，定义以下完整映射关系：
   - EL8 产品线：`rhel:8`、`centos:8`（CentOS Stream 8）、`almalinux:8`、`rocky:8`、`anolis:8`、`ol:8`、`opencloudos:8`、`kylin:V10`、`alinux:3`
   - EL9 产品线：`rhel:9`、`centos:9`（CentOS Stream 9）、`almalinux:9`、`rocky:9`、`anolis:23`、`ol:9`、`opencloudos:9`、`kylin:V11`、`alinux:4`
   - EL10 产品线：`rhel:10`、`centos:10`（CentOS Stream 10）、`almalinux:10`、`rocky:10`、`ol:10`
   - AL2023 产品线：`amzn:2023`
   - Fedora 产品线：`fedora:42`、`fedora:43`
   - openEuler 22 产品线：`openEuler:22`
   - openEuler 24 产品线：`openEuler:24`
2. THE Build_System SHALL 将 openEuler 20 视为不受支持的版本，并在用户指定时输出警告信息到 stderr
3. WHEN 用户通过 `--distro` 参数指定发行版时, THE Build_Script SHALL 通过 Product_Line_Map 解析出需要构建的产品线集合，并仅构建涉及的产品线
4. IF 用户指定了不在 Product_Line_Map 中的发行版/版本组合, THEN THE Build_Script SHALL 输出错误信息并以退出码 1 终止

### 需求 2：命令行参数解析

**用户故事：** 作为仓库维护者，我希望通过命令行参数控制构建行为，以便灵活地指定版本、输出目录和 GPG 密钥等配置。

#### 验收标准

1. THE Build_Script SHALL 接受 `--version <VERSION>` 参数指定要打包的 Caddy 版本号
2. THE Build_Script SHALL 接受 `--output <DIR>` 参数指定仓库输出根目录，默认值为 `./repo`
3. THE Build_Script SHALL 接受 `--gpg-key-id <KEY_ID>` 参数指定用于签名的 GPG 密钥 ID
4. THE Build_Script SHALL 接受 `--arch <ARCH>` 参数指定目标架构，允许值为 `x86_64`、`aarch64` 或 `all`，默认值为 `all`
5. THE Build_Script SHALL 接受 `--distro <DISTRO:VERSION>[,...]` 参数指定目标发行版和版本号组合，格式为逗号分隔的 `distro_id:major_version` 列表（如 `anolis:8,anolis:23,openEuler:22`），默认值为 `all`（构建所有产品线）
6. THE Build_Script SHALL 接受 `--gpg-key-file <PATH>` 参数指定 GPG 私钥文件路径（用于 nfpm 签名配置，适合 CI/CD 环境）
7. IF `--version` 参数未提供, THEN THE Build_Script SHALL 自动从 Caddy GitHub Releases API 查询最新稳定版本号
8. IF 提供了无效的参数值, THEN THE Build_Script SHALL 输出描述性错误信息并以退出码 1 终止
9. THE Build_Script SHALL 接受 `-h` 或 `--help` 参数并输出用法说明后以退出码 0 退出

### 需求 3：依赖检查

**用户故事：** 作为仓库维护者，我希望脚本在执行前检查所有必要的外部工具是否可用，以便在缺少依赖时尽早获得明确的错误提示。

#### 验收标准

1. THE Build_Script SHALL 在执行构建前检查以下工具是否可用：`curl`、`nfpm`、`createrepo`（或 `createrepo_c`）、`gpg`、`rpm`
2. IF 任一必要工具不可用, THEN THE Build_Script SHALL 输出缺失工具的名称及安装建议，并以退出码 2 终止
3. THE Build_Script SHALL 检查指定的 GPG 密钥 ID 是否存在于本地 GPG 密钥环中
4. IF 指定的 GPG 密钥 ID 不存在于本地密钥环, THEN THE Build_Script SHALL 输出错误信息并以退出码 2 终止

### 需求 4：离线构建支持

**用户故事：** 作为仓库维护者，我希望构建系统支持完全离线构建模式，以便在无外网访问的环境中也能完成 RPM 打包。

#### 验收标准

1. THE Build_System SHALL 支持通过 `vendor/` 目录提供预下载的 Caddy 二进制文件，格式为 `vendor/caddy-{version}-linux-{go_arch}`（其中 go_arch 为 `amd64` 或 `arm64`）
2. WHEN `vendor/` 目录中存在匹配版本和架构的二进制文件时, THE Build_Script SHALL 使用本地文件而非从 Caddy_API 下载
3. THE Build_System SHALL 在构建过程中设置 `GOPROXY=off` 和 `CGO_ENABLED=0` 环境变量，确保无网络依赖
4. THE Build_System SHALL 提供 `vendor-download.sh` 辅助脚本，用于在有网络的环境中预下载所有必要的二进制文件到 `vendor/` 目录

### 需求 5：Caddy 二进制下载

**用户故事：** 作为仓库维护者，我希望脚本能自动从 Caddy 官方 API 下载指定版本和架构的二进制文件，以便无需手动获取。

#### 验收标准

1. WHEN 构建开始且 `vendor/` 目录中无匹配文件时, THE Build_Script SHALL 为每个 Target_Arch 从 Caddy_API 下载对应的 Linux 二进制文件
2. THE Build_Script SHALL 使用 URL 格式 `https://caddyserver.com/api/download?os=linux&arch={go_arch}&version={version}` 下载二进制文件，其中 go_arch 为 `amd64`（对应 x86_64）或 `arm64`（对应 aarch64）
3. IF 下载失败, THEN THE Build_Script SHALL 输出包含 HTTP 状态码或 curl 错误码的错误信息，并以退出码 3 终止
4. WHEN 下载完成后, THE Build_Script SHALL 验证下载文件大小大于 0 字节
5. IF 下载文件大小为 0 字节, THEN THE Build_Script SHALL 输出错误信息并以退出码 3 终止
6. THE Build_Script SHALL 为每个 Target_Arch 仅下载一次二进制文件，同一架构的文件在所有产品线间复用

### 需求 6：RPM 打包（按产品线构建）

**用户故事：** 作为仓库维护者，我希望脚本按产品线将 Caddy 二进制文件打包为 RPM 格式，每个产品线每个架构仅生成一个 RPM 包，以便高效地管理和分发。

#### 验收标准

1. THE RPM_Packager SHALL 使用 nfpm 工具将 Caddy 二进制文件打包为 RPM 格式
2. THE RPM_Packager SHALL 为每个 Product_Line 和 Target_Arch 的组合生成一个 RPM 包（共 7 产品线 × 2 架构 = 14 个 RPM 包，而非按发行版逐一构建）
3. THE RPM_Packager SHALL 生成的 RPM 包名格式为 `caddy-{version}-1.{product_line_tag}.{arch}.rpm`（如 `caddy-2.9.0-1.el8.x86_64.rpm`、`caddy-2.9.0-1.el9.x86_64.rpm`、`caddy-2.9.0-1.el10.x86_64.rpm`、`caddy-2.9.0-1.al2023.x86_64.rpm`、`caddy-2.9.0-1.fc.x86_64.rpm`、`caddy-2.9.0-1.oe22.x86_64.rpm`、`caddy-2.9.0-1.oe24.x86_64.rpm`）
4. THE RPM_Packager SHALL 在 RPM 包中将 Caddy 二进制文件安装到 `/usr/bin/caddy`
5. THE RPM_Packager SHALL 在 RPM 包中包含 systemd 服务单元文件，安装到 `/usr/lib/systemd/system/caddy.service`
6. THE RPM_Packager SHALL 在 RPM 包中包含默认配置文件 `/etc/caddy/Caddyfile`（类型为 `config|noreplace`，升级时不覆盖用户修改）
7. THE RPM_Packager SHALL 在 RPM 包中创建配置目录 `/etc/caddy/` 和数据目录 `/var/lib/caddy/` 的目录条目
8. THE RPM_Packager SHALL 动态生成 nfpm 配置文件，包含正确的版本号、架构和产品线信息
9. THE RPM_Packager SHALL 根据产品线选择压缩算法：EL8 产品线使用 xz 压缩（RPM 4.14 不支持 zstd），EL9、EL10、AL2023、Fedora、openEuler 22、openEuler 24 产品线使用 zstd 压缩
10. THE RPM_Packager SHALL 在 nfpm 配置中包含 systemd 生命周期脚本：`postinstall` 执行 `systemctl daemon-reload`，`preremove` 执行 `systemctl stop caddy.service && systemctl disable caddy.service`
11. THE RPM_Packager SHALL 在 RPM 包中包含 Caddy 的 Apache License 2.0 许可证文件，安装到 `/usr/share/licenses/caddy/LICENSE`
12. IF nfpm 打包失败, THEN THE Build_Script SHALL 输出错误信息并以退出码 4 终止

### 需求 7：systemd 服务配置

**用户故事：** 作为系统管理员，我希望 RPM 包中的 systemd 服务单元文件遵循安全最佳实践，以便 Caddy 以最小权限运行。

#### 验收标准

1. THE RPM_Packager SHALL 在 systemd 服务单元文件中配置 `User=caddy` 和 `Group=caddy`
2. THE RPM_Packager SHALL 在 systemd 服务单元文件中配置 `AmbientCapabilities=CAP_NET_BIND_SERVICE`，允许 Caddy 以非 root 用户绑定 80/443 端口
3. THE RPM_Packager SHALL 在 systemd 服务单元文件中配置 XDG 标准路径：`Environment=XDG_DATA_HOME=/var/lib/caddy` 和 `Environment=XDG_CONFIG_HOME=/etc/caddy`
4. THE RPM_Packager SHALL 在 postinstall 脚本中创建 `caddy` 系统用户和组（如不存在），home 目录为 `/var/lib/caddy`
5. THE RPM_Packager SHALL 在 systemd 服务单元文件中包含安全加固配置：`ProtectSystem=full`、`ProtectHome=true`、`PrivateTmp=true`、`NoNewPrivileges=true`

### 需求 8：SELinux 策略（可选子包）

**用户故事：** 作为安全管理员，我希望 SELinux 策略作为可选子包提供，以便在需要时安装而不强制修改全局策略。

#### 验收标准

1. THE Build_System SHALL 将 SELinux 策略模块作为独立的可选子包 `caddy-selinux` 构建
2. THE `caddy-selinux` 子包 SHALL 在安装时加载 SELinux 策略模块，在卸载时移除
3. THE `caddy` 主包 SHALL 在无 `caddy-selinux` 子包时正常运行（SELinux 策略为可选依赖，非强制）
4. WHERE SELinux 处于 enforcing 模式且未安装 `caddy-selinux`, THE Build_System SHALL 在客户端 .repo 模板中提供安装 `caddy-selinux` 的说明

### 需求 9：RPM 签名

**用户故事：** 作为仓库维护者，我希望所有生成的 RPM 包都经过 GPG 签名，以便客户端可以验证包的完整性和来源。

#### 验收标准

1. WHEN RPM 包生成后, THE GPG_Signer SHALL 使用指定的 GPG 密钥对每个 RPM 包进行签名
2. THE GPG_Signer SHALL 优先使用 nfpm 内置的 `rpm.signature.key_file` 配置进行签名（适合无交互的 CI/CD 环境），或回退到 `rpm --addsign` 命令
3. IF 签名失败, THEN THE Build_Script SHALL 输出错误信息并以退出码 5 终止
4. WHEN 签名完成后, THE Build_Script SHALL 使用 `rpm -K` 验证每个 RPM 包的签名有效性
5. IF 签名验证失败, THEN THE Build_Script SHALL 输出错误信息并以退出码 5 终止

### 需求 10：产品线目录结构与仓库元数据

**用户故事：** 作为仓库维护者，我希望生成的仓库目录结构按产品线组织，并为每个产品线/架构目录生成仓库元数据，以便 DNF/YUM 客户端可以正确索引和安装包。

#### 验收标准

1. THE Build_Script SHALL 按照以下真实目录结构组织 RPM 包：
   ```
   {output_dir}/
     caddy/
       gpg.key
       el8/{arch}/Packages/*.rpm + repodata/
       el9/{arch}/Packages/*.rpm + repodata/
       el10/{arch}/Packages/*.rpm + repodata/
       al2023/{arch}/Packages/*.rpm + repodata/
       fedora/{arch}/Packages/*.rpm + repodata/
       openeuler/22/{arch}/Packages/*.rpm + repodata/
       openeuler/24/{arch}/Packages/*.rpm + repodata/
   ```
2. THE Build_Script SHALL 将签名后的 RPM 包放置到对应产品线的 `{product_line_path}/{arch}/Packages/` 目录中
3. WHEN RPM 包放置完成后, THE Repo_Generator SHALL 对每个 `{product_line_path}/{arch}/` 目录执行 `createrepo_c`（或 `createrepo`）生成 repodata
4. THE Repo_Generator SHALL 在执行 createrepo 时强制使用 `--general-compress-type=xz` 参数，确保元数据文件（primary.xml、filelists.xml、other.xml）使用 xz 压缩，以兼容所有产品线的 librepo 库
5. IF 目标目录已存在旧的 repodata, THEN THE Repo_Generator SHALL 使用 `--update` 参数增量更新元数据
6. IF createrepo 执行失败, THEN THE Build_Script SHALL 输出错误信息并以退出码 6 终止
7. WHEN 元数据生成完成后, THE Build_Script SHALL 验证每个产品线/架构目录中存在 `repodata/repomd.xml` 文件
8. WHEN 元数据生成完成后, THE GPG_Signer SHALL 使用 `gpg --detach-sign --armor` 对每个 `repodata/repomd.xml` 生成分离签名文件 `repomd.xml.asc`，以支持客户端的 `repo_gpgcheck=1` 验证
9. THE Build_Script SHALL 在 `{output_dir}/caddy/` 目录下导出 GPG 公钥文件，命名为 `gpg.key`（ASCII-armored PGP 公钥格式）

### 需求 11：发行版友好路径（符号链接生成）

**用户故事：** 作为终端用户，我希望通过直觉化的发行版名称和版本号访问仓库，而无需了解底层产品线概念，以便 .repo 配置中的 baseurl 对用户友好。

#### 验收标准

1. WHEN 产品线目录构建完成后, THE Symlink_Generator SHALL 为 Product_Line_Map 中每个发行版/版本组合生成符号链接，指向对应的产品线目录
2. THE Symlink_Generator SHALL 生成的符号链接路径格式为 `{output_dir}/caddy/{distro_id}/{distro_version}/` → 对应产品线目录，例如：
   - `caddy/anolis/8/` → `caddy/el8/`
   - `caddy/anolis/23/` → `caddy/el9/`
   - `caddy/centos/8/` → `caddy/el8/`
   - `caddy/centos/9/` → `caddy/el9/`
   - `caddy/centos/10/` → `caddy/el10/`
   - `caddy/rhel/8/` → `caddy/el8/`
   - `caddy/rhel/9/` → `caddy/el9/`
   - `caddy/rhel/10/` → `caddy/el10/`
   - `caddy/almalinux/8/` → `caddy/el8/`
   - `caddy/almalinux/9/` → `caddy/el9/`
   - `caddy/almalinux/10/` → `caddy/el10/`
   - `caddy/rocky/8/` → `caddy/el8/`
   - `caddy/rocky/9/` → `caddy/el9/`
   - `caddy/rocky/10/` → `caddy/el10/`
   - `caddy/ol/8/` → `caddy/el8/`
   - `caddy/ol/9/` → `caddy/el9/`
   - `caddy/ol/10/` → `caddy/el10/`
   - `caddy/opencloudos/8/` → `caddy/el8/`
   - `caddy/opencloudos/9/` → `caddy/el9/`
   - `caddy/kylin/V10/` → `caddy/el8/`
   - `caddy/kylin/V11/` → `caddy/el9/`
   - `caddy/alinux/3/` → `caddy/el8/`
   - `caddy/alinux/4/` → `caddy/el9/`
   - `caddy/fedora/42/` → 不生成符号链接（Fedora 产品线直接使用 `caddy/fedora/{arch}/` 路径，.repo 模板中不包含版本号）
   - `caddy/fedora/43/` → 同上
   - `caddy/amzn/2023/` → `caddy/al2023/`
   - `caddy/openEuler/22/` → `caddy/openeuler/22/`
   - `caddy/openEuler/24/` → `caddy/openeuler/24/`
3. THE Symlink_Generator SHALL 使用相对路径创建符号链接，确保仓库目录可整体迁移
4. WHEN 符号链接生成完成后, THE Build_Script SHALL 验证每个符号链接指向有效的目标目录
5. IF 符号链接目标不存在, THEN THE Build_Script SHALL 输出警告信息到 stderr 并跳过该链接

### 需求 12：原子发布与回滚

**用户故事：** 作为仓库维护者，我希望新版本发布时实现零停机切换，并在出现问题时能快速回滚到上一版本。

#### 验收标准

1. THE Build_Script SHALL 将构建产物先写入临时的 staging 目录（`{output_dir}/.staging/`），而非直接写入最终目录
2. WHEN 构建和验证全部完成后, THE Build_Script SHALL 通过原子目录交换（`mv` 操作）将 staging 目录替换为正式目录
3. THE Build_Script SHALL 在交换前将当前正式目录备份为 `{output_dir}/.rollback/{timestamp}/`
4. THE Build_Script SHALL 接受 `--rollback` 参数，将仓库恢复到最近一次备份状态
5. IF 原子交换失败, THEN THE Build_Script SHALL 保留 staging 目录不删除，输出错误信息并以退出码 7 终止
6. THE Build_Script SHALL 保留最近 3 个回滚备份，自动清理更早的备份

### 需求 13：客户端 .repo 配置模板生成

**用户故事：** 作为仓库维护者，我希望构建系统自动生成每个支持发行版的 .repo 配置文件模板，以便用户可以直接下载使用。

#### 验收标准

1. WHEN 构建完成后, THE Build_Script SHALL 在 `{output_dir}/caddy/templates/` 目录下为每个支持的发行版/版本组合生成 `.repo` 配置文件模板
2. THE Build_Script SHALL 生成的 .repo 模板文件命名格式为 `caddy-{distro_id}-{distro_version}.repo`（如 `caddy-anolis-23.repo`、`caddy-openEuler-22.repo`）
3. THE Build_Script SHALL 在 .repo 模板中使用发行版友好路径（符号链接路径）作为 baseurl，格式为 `{base_url}/caddy/{distro_id}/{distro_version}/$basearch/`；Fedora 产品线特殊处理，baseurl 格式为 `{base_url}/caddy/fedora/$basearch/`（不含版本号，因为 Fedora 产品线目录不使用版本子目录）
4. THE Build_Script SHALL 在 .repo 模板中包含 `gpgcheck=1`、`repo_gpgcheck=1` 和 `gpgkey={base_url}/caddy/gpg.key` 配置
5. THE Build_Script SHALL 接受 `--base-url <URL>` 参数指定 .repo 模板中的基础 URL，默认值为 `https://rpms.example.com`
6. WHERE SELinux 处于 enforcing 模式, THE Build_Script SHALL 在 .repo 模板注释中提供安装 `caddy-selinux` 子包的说明

### 需求 14：版本查询

**用户故事：** 作为仓库维护者，我希望在未指定版本时脚本能自动获取 Caddy 最新稳定版本号，以便始终打包最新版本。

#### 验收标准

1. WHEN `--version` 参数未提供时, THE Build_Script SHALL 通过 Caddy GitHub Releases API（`https://api.github.com/repos/caddyserver/caddy/releases/latest`）查询最新稳定版本号
2. THE Build_Script SHALL 从 API 响应的 `tag_name` 字段提取版本号，并去除 `v` 前缀
3. IF 版本查询失败, THEN THE Build_Script SHALL 输出错误信息并以退出码 3 终止
4. WHEN 版本号确定后, THE Build_Script SHALL 将使用的版本号输出到 stderr

### 需求 15：幂等性与增量构建

**用户故事：** 作为仓库维护者，我希望重复执行脚本时不会产生重复或损坏的结果，以便可以安全地在 CI/CD 中反复运行。

#### 验收标准

1. IF 目标产品线/架构目录中已存在相同版本的 RPM 包, THEN THE Build_Script SHALL 跳过该组合的下载和打包步骤，并输出跳过提示到 stderr
2. WHEN 脚本重复执行时, THE Build_Script SHALL 产生与首次执行相同的仓库目录结构和元数据
3. THE Build_Script SHALL 在构建过程中使用临时目录存放中间文件，并在完成或失败时清理临时目录

### 需求 16：CI/CD 流水线阶段

**用户故事：** 作为 DevOps 工程师，我希望构建系统的各阶段清晰分离，以便在 CI/CD 流水线中灵活编排和监控。

#### 验收标准

1. THE Build_Script SHALL 支持 `--stage <STAGE>` 参数，允许单独执行以下阶段：`build`（下载+打包）、`sign`（RPM 签名+元数据签名）、`publish`（原子发布）、`verify`（验证测试）
2. WHEN `--stage` 参数未提供时, THE Build_Script SHALL 按顺序执行所有阶段：Build → Sign → Publish → Verify
3. THE Build_Script SHALL 在每个阶段完成后输出阶段完成状态到 stderr，格式为 `[STAGE] {stage_name}: completed`
4. IF 任一阶段失败, THEN THE Build_Script SHALL 停止后续阶段执行，输出失败阶段名称和错误信息

### 需求 17：测试门禁

**用户故事：** 作为仓库维护者，我希望构建系统在发布前执行自动化验证测试，以便确保生成的 RPM 包和仓库元数据的质量。

#### 验收标准

1. WHEN verify 阶段执行时, THE Build_Script SHALL 对每个生成的 RPM 包执行 `rpmlint` 检查
2. WHEN verify 阶段执行时, THE Build_Script SHALL 验证每个产品线/架构目录的 `repodata/repomd.xml` 存在且格式正确
3. WHEN verify 阶段执行时, THE Build_Script SHALL 验证每个 RPM 包的 GPG 签名有效（`rpm -K`）
4. WHEN verify 阶段执行时, THE Build_Script SHALL 验证每个 `repomd.xml.asc` 签名文件有效（`gpg --verify`）
5. WHEN verify 阶段执行时, THE Build_Script SHALL 验证所有发行版友好路径符号链接指向有效目标
6. IF 任一验证测试失败, THEN THE Build_Script SHALL 输出失败的测试项和详细信息，并以退出码 8 终止

### 需求 18：日志与退出码

**用户故事：** 作为仓库维护者，我希望脚本提供清晰的日志输出和一致的退出码，以便在自动化流水线中监控构建状态。

#### 验收标准

1. THE Build_Script SHALL 将所有日志信息输出到 stderr，仅将最终仓库根目录绝对路径输出到 stdout
2. THE Build_Script SHALL 使用以下退出码：0（成功）、1（参数错误）、2（依赖缺失）、3（下载/版本查询失败）、4（打包失败）、5（签名或密钥导出失败）、6（元数据生成失败）、7（发布/回滚失败）、8（验证测试失败）
3. THE Build_Script SHALL 在每个主要步骤开始和完成时输出 `[INFO]` 级别日志
4. IF 任一步骤失败, THEN THE Build_Script SHALL 输出 `[ERROR]` 级别日志，包含失败原因和上下文信息
5. THE Build_Script SHALL 在构建完成后输出构建摘要到 stderr，包含：构建的产品线数量、RPM 包总数、符号链接数量、总耗时

### 需求 19：install-caddy.sh 联动更新

**用户故事：** 作为安装脚本的使用者，我希望 `install-caddy.sh` 的自建仓库安装逻辑能适配新的产品线架构，通过发行版友好路径（符号链接）访问仓库，以便客户端体验保持直觉化。

#### 验收标准

1. THE `install-caddy.sh` 中的 `_generate_dnf_repo_content` 函数 SHALL 使用 `{base_url}/caddy/{OS_ID}/{OS_MAJOR_VERSION}/{arch}/` 格式生成 baseurl，其中 `OS_ID` 为发行版标识，`OS_MAJOR_VERSION` 为发行版原生主版本号（通过符号链接解析到产品线目录）
2. THE `install-caddy.sh` 中的 `detect_classify` 函数 SHALL 设置 `OS_MAJOR_VERSION` 全局变量为发行版原生主版本号（如 Anolis 为 `8` 或 `23`，openEuler 为 `22` 或 `24`，Kylin 为 `V10` 或 `V11`，Alibaba Cloud Linux 为 `3` 或 `4`）
3. THE `install-caddy.sh` SHALL 保持对 `--mirror` 参数的兼容性，镜像 URL 仍作为 base_url 使用
4. THE `install-caddy.sh` 中的 `_generate_dnf_repo_content` 函数 SHALL 在 .repo 配置中包含 `repo_gpgcheck=1` 以启用仓库元数据签名验证
5. THE `install-caddy.sh` SHALL 在 .repo 配置的 `name` 字段中使用发行版名称和版本号（如 `Caddy Self-Hosted Repository (Anolis 23 - x86_64)`），而非产品线名称

### 需求 20：国密算法支持（可选产品线）

**用户故事：** 作为面向中国政府客户的运维人员，我希望构建系统支持可选的国密（SM2/SM3）签名产品线，以便满足合规要求。

#### 验收标准

1. WHERE 国密合规要求存在, THE Build_System SHALL 支持构建独立的国密产品线，使用 SM2 密钥对 RPM 包签名、SM3 摘要算法
2. THE Build_Script SHALL 接受 `--sm2-key <PATH>` 参数指定 SM2 私钥文件路径（仅在构建国密产品线时需要）
3. WHERE 国密产品线启用, THE Build_System SHALL 将国密签名的 RPM 包放置在独立的目录结构中（如 `{output_dir}/caddy-sm/`），与标准产品线隔离
4. THE Build_System SHALL 在国密产品线的 .repo 模板中使用独立的 GPG 公钥路径（`gpg-sm2.key`）


