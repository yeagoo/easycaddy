# Caddy RPM 自建仓库构建系统

一套自动化工具链，用于构建和维护自建的 Caddy Server RPM 仓库。按产品线组织构建，通过符号链接提供发行版友好路径，支持 28+ 个 RPM 发行版。

## 系统架构

核心理念：Caddy 是纯 Go 静态编译（`CGO_ENABLED=0`），同一架构的二进制文件可跨发行版复用。因此将兼容同一 RPM 版本的发行版归入同一产品线，每个产品线每个架构仅构建一个 RPM 包。

**7 条产品线 × 2 架构 = 14 个 RPM 包，覆盖 28+ 个发行版路径。**

| 产品线 | 覆盖发行版 |
|--------|-----------|
| EL8 | RHEL 8, CentOS Stream 8, AlmaLinux 8, Rocky 8, Anolis 8, Oracle Linux 8, OpenCloudOS 8, Kylin V10, Alibaba Cloud Linux 3 |
| EL9 | RHEL 9, CentOS Stream 9, AlmaLinux 9, Rocky 9, Anolis 23, Oracle Linux 9, OpenCloudOS 9, Kylin V11, Alibaba Cloud Linux 4 |
| EL10 | RHEL 10, CentOS Stream 10, AlmaLinux 10, Rocky 10, Oracle Linux 10 |
| AL2023 | Amazon Linux 2023 |
| Fedora | Fedora 42, 43 |
| openEuler 22 | openEuler 22.03 LTS |
| openEuler 24 | openEuler 24.03 LTS |

## 前置依赖

| 工具 | 用途 | 安装方式 |
|------|------|---------|
| curl | 下载 Caddy 二进制 | `dnf install curl` |
| nfpm | RPM 打包 | [nfpm.goreleaser.com/install](https://nfpm.goreleaser.com/install/) |
| createrepo_c | 仓库元数据生成 | `dnf install createrepo_c` |
| gpg | GPG 签名 | `dnf install gnupg2` |
| rpm | RPM 签名验证 | `dnf install rpm` |

可选：`rpmlint`（verify 阶段检查）、`gpgsm` + `rpmsign`（国密 SM2 签名）。

## 快速开始

```bash
# 1. 构建全部产品线和架构（自动查询最新 Caddy 版本）
bash build-repo.sh --gpg-key-id YOUR_KEY_ID --output ./repo

# 2. 指定版本构建
bash build-repo.sh --version 2.9.0 --gpg-key-id YOUR_KEY_ID --output ./repo
```

构建完成后，stdout 输出仓库根目录绝对路径，stderr 输出构建摘要。

## 命令行参数

```
build-repo.sh [选项]

选项:
  --version <VERSION>      Caddy 版本号（如 2.9.0），不指定则自动查询最新版
  --output <DIR>           仓库输出根目录（默认: ./repo）
  --gpg-key-id <KEY_ID>    GPG 密钥 ID（用于 rpm --addsign 和 repomd 签名）
  --gpg-key-file <PATH>    GPG 私钥文件路径（用于 nfpm 内置签名，适合 CI/CD）
  --arch <ARCH>            目标架构: x86_64 | aarch64 | all（默认: all）
  --distro <SPEC>          目标发行版: distro:version,... | all（默认: all）
  --base-url <URL>         .repo 模板基础 URL（默认: https://rpms.example.com）
  --stage <STAGE>          执行指定阶段: build | sign | publish | verify
  --rollback               回滚到最近一次备份
  --sm2-key <PATH>         SM2 私钥文件路径（国密产品线，可选）
  -h, --help               显示帮助信息
```

## 使用示例

### 基本构建

```bash
# 构建全部 7 条产品线 × 2 架构 = 14 个 RPM 包
bash build-repo.sh --version 2.9.0 --gpg-key-id ABCD1234

# 仅构建指定发行版（自动解析到对应产品线）
bash build-repo.sh --version 2.9.0 --distro anolis:8,anolis:23,openEuler:22

# 仅构建 x86_64 架构
bash build-repo.sh --version 2.9.0 --arch x86_64 --gpg-key-id ABCD1234
```

### CI/CD 分阶段执行

```bash
# 使用密钥文件（无需交互式 GPG agent）
bash build-repo.sh --version 2.9.0 --gpg-key-file /path/to/key.gpg --stage build
bash build-repo.sh --stage sign
bash build-repo.sh --stage publish
bash build-repo.sh --stage verify
```

四个阶段：
- **build** — 下载二进制、构建 RPM、生成 repodata、符号链接、.repo 模板
- **sign** — 签名所有 RPM 包和 repomd.xml
- **publish** — 原子交换 staging → 正式目录，备份旧版本
- **verify** — rpmlint 检查、repodata 验证、签名验证、符号链接验证

### 离线构建

```bash
# 在有网络的机器上预下载二进制
bash vendor-download.sh --version 2.9.0

# 在离线机器上构建（自动使用 vendor/ 中的文件）
bash build-repo.sh --version 2.9.0 --gpg-key-id ABCD1234
```

### 回滚

```bash
# 回滚到最近一次备份
bash build-repo.sh --rollback
```

系统自动保留最近 3 个备份，更早的在每次发布时自动清理。

### 自定义 .repo 模板 URL

```bash
bash build-repo.sh --version 2.9.0 --base-url https://rpms.yoursite.com
```

### 国密（SM2/SM3）签名

```bash
bash build-repo.sh --version 2.9.0 --gpg-key-id ABCD1234 --sm2-key /path/to/sm2.key
```

国密产品线输出到独立目录 `{output}/caddy-sm/`，生成独立的 `gpg-sm2.key` 公钥文件。

## 构建产物目录结构

```
repo/
├── caddy/
│   ├── el8/                          # EL8 产品线（真实目录）
│   │   ├── x86_64/
│   │   │   ├── Packages/
│   │   │   │   └── caddy-2.9.0-1.el8.x86_64.rpm
│   │   │   └── repodata/
│   │   │       ├── repomd.xml
│   │   │       └── repomd.xml.asc
│   │   └── aarch64/
│   │       ├── Packages/
│   │       └── repodata/
│   ├── el9/                          # EL9 产品线
│   ├── el10/                         # EL10 产品线
│   ├── al2023/                       # AL2023 产品线
│   ├── fedora/                       # Fedora 产品线
│   ├── openeuler/
│   │   ├── 22/                       # openEuler 22 产品线
│   │   └── 24/                       # openEuler 24 产品线
│   │
│   ├── anolis/                       # 符号链接目录
│   │   ├── 8  → ../el8/             # Anolis 8 → EL8
│   │   └── 23 → ../el9/             # Anolis 23 → EL9
│   ├── rhel/
│   │   ├── 8  → ../el8/
│   │   ├── 9  → ../el9/
│   │   └── 10 → ../el10/
│   ├── centos/
│   │   ├── 8  → ../el8/
│   │   ├── 9  → ../el9/
│   │   └── 10 → ../el10/
│   ├── almalinux/
│   │   ├── 8  → ../el8/
│   │   ├── 9  → ../el9/
│   │   └── 10 → ../el10/
│   ├── rocky/
│   │   ├── 8  → ../el8/
│   │   ├── 9  → ../el9/
│   │   └── 10 → ../el10/
│   ├── kylin/
│   │   ├── V10 → ../el8/
│   │   └── V11 → ../el9/
│   ├── alinux/
│   │   ├── 3  → ../el8/             # Alibaba Cloud Linux 3 → EL8
│   │   └── 4  → ../el9/             # Alibaba Cloud Linux 4 → EL9
│   ├── amzn/
│   │   └── 2023 → ../al2023/
│   │   ...（更多符号链接）
│   │
│   ├── templates/                    # .repo 配置文件模板
│   │   ├── caddy-anolis-8.repo
│   │   ├── caddy-rhel-9.repo
│   │   ├── caddy-fedora-42.repo
│   │   └── ...
│   └── gpg.key                       # GPG 公钥
│
├── caddy-sm/                         # 国密产品线（可选，--sm2-key 时生成）
│   └── ...
└── .rollback/                        # 回滚备份
    ├── 20260226-143000/
    └── 20260225-120000/
```

## 客户端配置

### 方式一：使用 install-caddy.sh 自动配置

```bash
# install-caddy.sh 已集成自建仓库支持
bash install-caddy.sh --mirror https://rpms.yoursite.com
```

脚本会自动检测发行版和版本，生成正确的 `.repo` 配置。

### 方式二：手动配置

将对应的 `.repo` 模板文件复制到客户端：

```bash
# 例如 Anolis 8
sudo cp caddy-anolis-8.repo /etc/yum.repos.d/caddy.repo
sudo rpm --import https://rpms.yoursite.com/caddy/gpg.key
sudo dnf install caddy
```

或手动创建 `/etc/yum.repos.d/caddy.repo`：

```ini
[caddy-selfhosted]
name=Caddy Self-Hosted Repository
baseurl=https://rpms.yoursite.com/caddy/anolis/8/$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://rpms.yoursite.com/caddy/gpg.key
```

Fedora 用户的 baseurl 不含版本号：

```ini
baseurl=https://rpms.yoursite.com/caddy/fedora/$basearch/
```

## 使用 Caddy/Nginx 托管仓库

构建产物是纯静态文件，任何 Web 服务器都可以托管。以 Caddy 为例：

```
rpms.yoursite.com {
    root * /path/to/repo
    file_server browse
}
```

确保符号链接能被正确跟随（Caddy 默认支持）。

## 退出码

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

## 运行测试

```bash
# 运行全部测试（单元测试 + 属性测试）
./tests/libs/bats-core/bin/bats tests/unit/ tests/property/

# 仅运行单元测试
./tests/libs/bats-core/bin/bats tests/unit/

# 仅运行属性测试
./tests/libs/bats-core/bin/bats tests/property/

# 运行特定测试文件
./tests/libs/bats-core/bin/bats tests/unit/test_product_line_map.bats
```

测试框架使用 [bats-core](https://github.com/bats-core/bats-core)，已作为 git submodule 包含在 `tests/libs/` 中。

## 项目文件结构

```
├── build-repo.sh              # 主构建脚本
├── vendor-download.sh         # 离线构建辅助脚本
├── install-caddy.sh           # 客户端安装脚本（集成自建仓库支持）
├── packaging/
│   ├── caddy.service          # systemd 服务单元
│   ├── Caddyfile              # 默认配置文件
│   ├── LICENSE                # Apache License 2.0
│   └── scripts/
│       ├── postinstall.sh     # RPM 安装后脚本
│       ├── preremove.sh       # RPM 卸载前脚本
│       ├── selinux-postinstall.sh
│       └── selinux-preremove.sh
└── tests/
    ├── unit/                  # 单元测试（9 个套件）
    ├── property/              # 属性测试（22 个套件 × 100 次随机迭代）
    ├── test_helper/           # 测试辅助函数和生成器
    └── libs/                  # bats-core, bats-assert (git submodules)
```

## 许可证

Apache License 2.0
