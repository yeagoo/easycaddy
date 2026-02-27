#!/usr/bin/env bash
# ============================================================================
# install-caddy.sh — Caddy Server 中国发行版安装脚本
# 支持多种 Linux 发行版（包括中国国产发行版）的 Caddy 自动安装
# 采用三级 fallback 策略：官方包仓库 → 自建 DNF 仓库 → 官方 API 二进制下载
# ============================================================================
set -euo pipefail

# === 参数解析结果 ===
OPT_VERSION=""              # --version 指定的目标版本
OPT_METHOD=""               # --method: "repo" | "binary" | ""（自动）
OPT_PREFIX="/usr/local/bin" # --prefix: 二进制安装目录
OPT_MIRROR=""               # --mirror: 镜像地址
OPT_SKIP_SERVICE=false      # --skip-service
OPT_SKIP_CAP=false          # --skip-cap
OPT_YES=false               # -y/--yes

# === OS 检测结果 ===
OS_ID=""                    # /etc/os-release 中的 ID
OS_ID_LIKE=""               # /etc/os-release 中的 ID_LIKE
OS_VERSION_ID=""            # /etc/os-release 中的 VERSION_ID
OS_NAME=""                  # /etc/os-release 中的 NAME
OS_PLATFORM_ID=""           # /etc/os-release 中的 PLATFORM_ID
OS_CLASS=""                 # "standard_deb" | "standard_rpm" | "unsupported_rpm" | "unknown"
OS_ARCH=""                  # "amd64" | "arm64" | "loongarch64" | "riscv64"
OS_ARCH_RAW=""              # uname -m 原始值
EPEL_VERSION=""             # EPEL 兼容版本: "8" | "9"
OS_MAJOR_VERSION=""         # 发行版原生主版本号（用于自建仓库路径）
PKG_MANAGER=""              # "apt" | "dnf" | "yum"

# === 运行时状态 ===
CADDY_BIN=""                # 安装后的 Caddy 二进制路径
INSTALL_METHOD_USED=""      # 实际使用的安装方式
TEMP_DIR=""                 # 临时目录路径（用于清理）
USE_COLOR=true              # 是否启用彩色输出

# ============================================================================
# 工具函数模块
# ============================================================================

# 检测 stderr 是否为终端，决定是否启用彩色输出
util_has_color() {
    if [[ -t 2 ]]; then
        USE_COLOR=true
    else
        USE_COLOR=false
    fi
}

# 信息日志（蓝色），输出到 stderr
util_log_info() {
    local msg="$1"
    if [[ "$USE_COLOR" == true ]]; then
        printf '\033[0;34m[INFO]\033[0m %s\n' "$msg" >&2
    else
        printf '[INFO] %s\n' "$msg" >&2
    fi
}

# 成功日志（绿色），输出到 stderr
util_log_success() {
    local msg="$1"
    if [[ "$USE_COLOR" == true ]]; then
        printf '\033[0;32m[OK]\033[0m %s\n' "$msg" >&2
    else
        printf '[OK] %s\n' "$msg" >&2
    fi
}

# 警告日志（黄色），输出到 stderr
util_log_warn() {
    local msg="$1"
    if [[ "$USE_COLOR" == true ]]; then
        printf '\033[0;33m[WARN]\033[0m %s\n' "$msg" >&2
    else
        printf '[WARN] %s\n' "$msg" >&2
    fi
}

# 错误日志（红色），输出到 stderr
util_log_error() {
    local msg="$1"
    if [[ "$USE_COLOR" == true ]]; then
        printf '\033[0;31m[ERROR]\033[0m %s\n' "$msg" >&2
    else
        printf '[ERROR] %s\n' "$msg" >&2
    fi
}

# 清理临时文件
util_cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# 注册信号处理（测试模式下跳过，避免 source 时触发 trap）
if [[ "${_SOURCED_FOR_TEST:-}" != true ]]; then
    trap util_cleanup EXIT
    trap 'util_log_error "收到中断信号，正在清理..."; exit 130' INT TERM
fi

# 检测 root 权限或 sudo 可用性，不足时以退出码 4 终止
util_check_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        util_log_info "当前用户非 root，将使用 sudo 执行特权操作"
        return 0
    fi

    util_log_error "需要 root 权限或 sudo 才能安装 Caddy"
    exit 4
}

# ============================================================================
# 参数解析模块
# ============================================================================

# 输出帮助信息到 stderr 并以退出码 0 退出
parse_show_help() {
    cat >&2 <<'EOF'
用法: install-caddy.sh [选项]

选项:
  --version <VERSION>    安装指定版本的 Caddy（如 2.7.6）
  --method <METHOD>      安装方式: repo（仅包仓库）或 binary（仅二进制下载）
  --prefix <DIR>         二进制安装目录（默认 /usr/local/bin，仅 binary 方式生效）
  --mirror <URL>         使用指定的镜像地址替代默认仓库地址
  --skip-service         跳过 systemd 服务处理步骤
  --skip-cap             跳过 setcap 权限设置步骤
  -y, --yes              自动确认所有交互式提示
  -h, --help             显示此帮助信息

示例:
  bash install-caddy.sh
  bash install-caddy.sh --version 2.7.6
  bash install-caddy.sh --method binary --prefix /opt/bin
  curl -fsSL https://example.com/install-caddy.sh | bash -s -- --yes
EOF
    exit 0
}

# 解析命令行参数，设置全局变量
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --version 需要一个值"
                    parse_show_help
                fi
                OPT_VERSION="$2"
                shift 2
                ;;
            --method)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --method 需要一个值"
                    parse_show_help
                fi
                OPT_METHOD="$2"
                if [[ "$OPT_METHOD" != "repo" && "$OPT_METHOD" != "binary" ]]; then
                    util_log_error "--method 仅允许 'repo' 或 'binary'，收到: '$OPT_METHOD'"
                    exit 1
                fi
                shift 2
                ;;
            --prefix)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --prefix 需要一个值"
                    parse_show_help
                fi
                OPT_PREFIX="$2"
                shift 2
                ;;
            --mirror)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --mirror 需要一个值"
                    parse_show_help
                fi
                OPT_MIRROR="$2"
                shift 2
                ;;
            --skip-service)
                OPT_SKIP_SERVICE=true
                shift
                ;;
            --skip-cap)
                OPT_SKIP_CAP=true
                shift
                ;;
            -y|--yes)
                OPT_YES=true
                shift
                ;;
            -h|--help)
                parse_show_help
                ;;
            *)
                util_log_error "未知参数: $1"
                cat >&2 <<'EOF'
使用 --help 查看可用选项
EOF
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# OS 检测与分类模块
# ============================================================================

# 读取 /etc/os-release，提取 ID、ID_LIKE、VERSION_ID、NAME、PLATFORM_ID 字段
# 参数: $1 — os-release 文件路径（可选，默认 /etc/os-release，便于测试）
# 文件不存在时输出错误并以退出码 2 终止
detect_os() {
    local os_release_file="${OS_RELEASE_FILE:-${1:-/etc/os-release}}"

    if [[ ! -f "$os_release_file" ]]; then
        util_log_error "无法找到 ${os_release_file}，无法检测操作系统"
        exit 2
    fi

    # 逐行解析，处理带引号和不带引号的值
    while IFS='=' read -r key value; do
        # 去除值两端的引号
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        case "$key" in
            ID)          OS_ID="$value" ;;
            ID_LIKE)     OS_ID_LIKE="$value" ;;
            VERSION_ID)  OS_VERSION_ID="$value" ;;
            NAME)        OS_NAME="$value" ;;
            PLATFORM_ID) OS_PLATFORM_ID="$value" ;;
        esac
    done < "$os_release_file"
}

# 检测 CPU 架构，映射到 Caddy 下载 API 的架构名
# 设置 OS_ARCH（映射后）和 OS_ARCH_RAW（原始 uname -m 值）
# 不支持的架构以退出码 2 终止
detect_arch() {
    OS_ARCH_RAW="$(uname -m)"

    case "$OS_ARCH_RAW" in
        x86_64)
            OS_ARCH="amd64"
            ;;
        aarch64)
            OS_ARCH="arm64"
            ;;
        loongarch64)
            OS_ARCH="loongarch64"
            util_log_warn "loongarch64 为可选支持架构，部分功能可能不可用"
            ;;
        riscv64)
            OS_ARCH="riscv64"
            util_log_warn "riscv64 为可选支持架构，部分功能可能不可用"
            ;;
        *)
            util_log_error "不支持的 CPU 架构: ${OS_ARCH_RAW}"
            exit 2
            ;;
    esac
}

# 根据 OS_ID 和 ID_LIKE 分类操作系统，设置 OS_CLASS 和 EPEL_VERSION
detect_classify() {
    local major_version
    # 提取主版本号（取 VERSION_ID 中第一个 '.' 之前的部分）
    major_version="${OS_VERSION_ID%%.*}"

    # 默认设置 OS_MAJOR_VERSION 为 major_version，特殊发行版在各分支中覆盖
    OS_MAJOR_VERSION="$major_version"

    case "$OS_ID" in
        # 标准 Debian 系
        debian|ubuntu)
            OS_CLASS="standard_deb"
            ;;
        # 标准 RPM 系
        fedora|centos|rhel|almalinux|rocky)
            OS_CLASS="standard_rpm"
            ;;
        # COPR 不支持的 RPM 系 — openEuler
        openEuler)
            OS_CLASS="unsupported_rpm"
            case "$major_version" in
                20|22) EPEL_VERSION="8" ;;
                *)     EPEL_VERSION="9" ;;
            esac
            ;;
        # COPR 不支持的 RPM 系 — Anolis / Alibaba Cloud Linux
        anolis|alinux)
            OS_CLASS="unsupported_rpm"
            case "$major_version" in
                8)  EPEL_VERSION="8" ;;
                23) EPEL_VERSION="9" ;;
                *)  EPEL_VERSION="9" ;;
            esac
            ;;
        # COPR 不支持的 RPM 系 — OpenCloudOS
        opencloudos)
            OS_CLASS="unsupported_rpm"
            case "$major_version" in
                8) EPEL_VERSION="8" ;;
                9) EPEL_VERSION="9" ;;
                *) EPEL_VERSION="9" ;;
            esac
            ;;
        # COPR 不支持的 RPM 系 — Kylin（需要 ID_LIKE 包含 rhel/centos/fedora）
        kylin)
            if [[ "$OS_ID_LIKE" == *rhel* || "$OS_ID_LIKE" == *centos* || "$OS_ID_LIKE" == *fedora* ]]; then
                OS_CLASS="unsupported_rpm"
                # V10 → EPEL 8（检查 VERSION_ID 包含 "V10" 或主版本为 10）
                if [[ "$OS_VERSION_ID" == *V10* || "$major_version" == "10" ]]; then
                    EPEL_VERSION="8"
                    OS_MAJOR_VERSION="V10"
                else
                    EPEL_VERSION="9"
                    OS_MAJOR_VERSION="V11"
                fi
            else
                OS_CLASS="unknown"
            fi
            ;;
        # COPR 不支持的 RPM 系 — Amazon Linux（仅 2023）
        amzn)
            if [[ "$OS_VERSION_ID" == "2023" ]]; then
                OS_CLASS="unsupported_rpm"
                EPEL_VERSION="9"
                OS_MAJOR_VERSION="2023"
            else
                OS_CLASS="unknown"
            fi
            ;;
        # COPR 不支持的 RPM 系 — Oracle Linux
        ol)
            OS_CLASS="unsupported_rpm"
            case "$major_version" in
                8) EPEL_VERSION="8" ;;
                9) EPEL_VERSION="9" ;;
                *) EPEL_VERSION="9" ;;
            esac
            ;;
        # 其他所有发行版
        *)
            OS_CLASS="unknown"
            ;;
    esac
}

# 检测可用的包管理器（按优先级: apt → dnf → yum）
# 设置 PKG_MANAGER 全局变量
detect_pkg_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    else
        PKG_MANAGER=""
    fi
}

# ============================================================================
# 已安装检测模块
# ============================================================================

# 检测 Caddy 是否已安装
# 通过 command -v caddy 检测，找到时设置 CADDY_BIN 为其路径
# 返回 0 表示已安装，1 表示未安装
check_installed() {
    local caddy_path
    if caddy_path="$(command -v caddy 2>/dev/null)"; then
        CADDY_BIN="$caddy_path"
        return 0
    fi
    return 1
}

# 比较已安装的 Caddy 版本与 OPT_VERSION 是否匹配
# caddy version 输出格式: "v2.7.6 h1:abc123"
# 提取版本号（去掉 "v" 前缀和 hash 后缀），与 OPT_VERSION 比较
# OPT_VERSION 可能带或不带 "v" 前缀
# 返回 0 表示匹配，1 表示不匹配
check_version_match() {
    local raw_output installed_version target_version

    # 获取 caddy version 输出
    raw_output="$("$CADDY_BIN" version 2>/dev/null)" || return 1

    # 提取版本号：取第一个空格前的部分，去掉 "v" 前缀
    installed_version="${raw_output%% *}"
    installed_version="${installed_version#v}"

    # 规范化目标版本：去掉可能的 "v" 前缀
    target_version="${OPT_VERSION#v}"

    if [[ "$installed_version" == "$target_version" ]]; then
        return 0
    fi
    return 1
}

# ============================================================================
# 特权执行辅助函数
# ============================================================================

# 以特权方式执行命令：root 用户直接执行，非 root 用户通过 sudo 执行
_run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ============================================================================
# APT 仓库安装模块
# ============================================================================

# 生成 APT 源文件内容
# 参数: $1 — 仓库 URL（可选，默认使用官方 Cloudsmith 地址或 OPT_MIRROR）
# 输出: APT 源行内容到 stdout
_generate_apt_source_line() {
    local repo_url="${1:-}"
    local default_repo_url="https://dl.cloudsmith.io/public/caddy/stable/deb/debian"

    if [[ -n "$repo_url" ]]; then
        : # 使用传入的 URL
    elif [[ -n "$OPT_MIRROR" ]]; then
        repo_url="${OPT_MIRROR}/deb/debian"
    else
        repo_url="$default_repo_url"
    fi

    printf 'deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] %s any-version main\n' "$repo_url"
}

# 完整的 APT 仓库安装流程
# 安装依赖 → 导入 GPG 密钥 → 配置源 → apt-get update → apt-get install caddy
# 失败时返回非零退出码（由调用方决定是否回退）
install_apt_repo() {
    local gpg_key_url="https://dl.cloudsmith.io/public/caddy/stable/gpg.key"
    local gpg_key_path="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    local apt_source_file="/etc/apt/sources.list.d/caddy-stable.list"

    # 如果指定了镜像，替换 GPG 密钥 URL 的基础部分
    if [[ -n "$OPT_MIRROR" ]]; then
        gpg_key_url="${OPT_MIRROR}/gpg.key"
    fi

    # 步骤 1: 安装依赖包
    util_log_info "安装 APT 依赖包..."
    if ! _run_privileged apt-get install -y debian-keyring debian-archive-keyring apt-transport-https; then
        util_log_error "安装 APT 依赖包失败"
        return 1
    fi

    # 步骤 2: 获取 GPG 密钥
    util_log_info "获取 Caddy GPG 密钥..."
    # 先下载到临时文件，避免 curl 部分失败时写入损坏的密钥
    if [[ -z "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
        TEMP_DIR="$(mktemp -d)"
    fi
    local gpg_tmp="${TEMP_DIR}/caddy-gpg.key"
    if ! curl --connect-timeout 30 --max-time 120 -fSL -o "$gpg_tmp" "$gpg_key_url"; then
        util_log_error "获取 GPG 密钥失败: ${gpg_key_url}"
        rm -f "$gpg_tmp"
        return 1
    fi
    if [[ ! -s "$gpg_tmp" ]]; then
        util_log_error "下载的 GPG 密钥文件为空"
        rm -f "$gpg_tmp"
        return 1
    fi
    if ! _run_privileged gpg --dearmor -o "$gpg_key_path" < "$gpg_tmp"; then
        util_log_error "GPG 密钥 dearmor 失败"
        rm -f "$gpg_tmp"
        return 1
    fi
    rm -f "$gpg_tmp"

    # 步骤 3: 写入 APT 源文件
    util_log_info "配置 APT 源..."
    local source_line
    source_line="$(_generate_apt_source_line)"
    if ! printf '%s\n' "$source_line" | _run_privileged tee "$apt_source_file" >/dev/null; then
        util_log_error "写入 APT 源文件失败: ${apt_source_file}"
        return 1
    fi

    # 步骤 4: 更新包索引
    util_log_info "更新 APT 包索引..."
    if ! _run_privileged apt-get update; then
        util_log_error "apt-get update 失败"
        return 1
    fi

    # 步骤 5: 安装 Caddy
    util_log_info "通过 APT 安装 Caddy..."
    if ! _run_privileged apt-get install -y caddy; then
        util_log_error "apt-get install caddy 失败"
        return 1
    fi

    util_log_success "Caddy 已通过 APT 仓库安装成功"
    return 0
}

# ============================================================================
# COPR 仓库安装模块
# ============================================================================

# 完整的 COPR 仓库安装流程
# 安装 COPR 插件 → 启用 @caddy/caddy 仓库 → dnf install caddy
# 失败时返回非零退出码（由调用方决定是否回退）
install_copr_repo() {
    # 步骤 1: 安装 COPR 插件
    util_log_info "安装 DNF COPR 插件..."
    if ! _run_privileged dnf install -y 'dnf-command(copr)'; then
        util_log_error "安装 COPR 插件失败"
        return 1
    fi

    # 步骤 2: 启用 Caddy COPR 仓库
    util_log_info "启用 Caddy COPR 仓库..."
    if ! _run_privileged dnf copr enable -y @caddy/caddy; then
        util_log_error "启用 Caddy COPR 仓库失败"
        return 1
    fi

    # 步骤 3: 安装 Caddy
    util_log_info "通过 COPR 仓库安装 Caddy..."
    if ! _run_privileged dnf install -y caddy; then
        util_log_error "dnf install caddy 失败"
        return 1
    fi

    util_log_success "Caddy 已通过 COPR 仓库安装成功"
    return 0
}

# ============================================================================
# 自建 DNF 仓库安装模块
# ============================================================================

# 默认自建仓库基础 URL（用户应通过 --mirror 指定实际地址）
_SELFHOSTED_DEFAULT_BASE_URL="https://repo.example.com"

# 生成 DNF .repo 配置文件内容
# 参数: $1 — 基础 URL, $2 — 发行版 ID (OS_ID), $3 — 主版本号 (OS_MAJOR_VERSION), $4 — 架构（原始 uname -m 值）
# 输出: .repo 文件内容到 stdout
# 使用发行版友好路径: {base_url}/caddy/{distro_id}/{version}/$basearch/
# Requirements: 19.1, 19.3, 19.4, 19.5
_generate_dnf_repo_content() {
    local base_url="$1"
    local distro_id="$2"
    local distro_version="$3"
    local arch="$4"

    # 使用 OS_NAME 作为人类可读名称，回退到 distro_id
    local display_name="${OS_NAME:-$distro_id}"

    cat <<EOF
[caddy-selfhosted]
name=Caddy Self-Hosted Repository (${display_name} ${distro_version} - ${arch})
baseurl=${base_url}/caddy/${distro_id}/${distro_version}/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${base_url}/caddy/gpg.key
EOF
}

# 完整的自建 DNF 仓库安装流程
# 写入 .repo 文件 → 导入 GPG 密钥 → dnf/yum install caddy
# 失败时返回非零退出码（由调用方决定是否回退）
install_selfhosted_repo() {
    local base_url="${OPT_MIRROR:-${_SELFHOSTED_DEFAULT_BASE_URL}}"
    local repo_file="/etc/yum.repos.d/caddy-selfhosted.repo"
    local gpg_key_url="${base_url}/caddy/gpg.key"

    # 步骤 1: 写入 .repo 配置文件
    util_log_info "配置自建 DNF 仓库..."
    local repo_content
    repo_content="$(_generate_dnf_repo_content "$base_url" "$OS_ID" "$OS_MAJOR_VERSION" "$OS_ARCH_RAW")"
    if ! printf '%s\n' "$repo_content" | _run_privileged tee "$repo_file" >/dev/null; then
        util_log_error "写入仓库配置文件失败: ${repo_file}"
        return 1
    fi

    # 步骤 2: 导入 GPG 公钥
    util_log_info "导入 GPG 公钥..."
    if ! _run_privileged rpm --import "$gpg_key_url"; then
        util_log_error "导入 GPG 公钥失败: ${gpg_key_url}"
        return 1
    fi

    # 步骤 3: 安装 Caddy
    util_log_info "通过自建仓库安装 Caddy..."
    if ! _run_privileged "${PKG_MANAGER}" install -y caddy; then
        util_log_error "${PKG_MANAGER} install caddy 失败"
        return 1
    fi

    util_log_success "Caddy 已通过自建 DNF 仓库安装成功"
    return 0
}

# ============================================================================
# 二进制下载安装模块
# ============================================================================

# 构造 Caddy 二进制下载 URL
# 根据 OS_ARCH 和 OPT_VERSION 构造完整的下载 URL
# 输出: 下载 URL 到 stdout
_build_download_url() {
    local url="https://caddyserver.com/api/download?os=linux&arch=${OS_ARCH}"
    if [[ -n "$OPT_VERSION" ]]; then
        url="${url}&version=${OPT_VERSION}"
    fi
    printf '%s' "$url"
}

# 将 curl 退出码映射到中文错误描述
# 参数: $1 — curl 退出码
# 输出: 错误描述到 stdout
_describe_curl_error() {
    local code="$1"
    case "$code" in
        6)  printf 'DNS 解析失败' ;;
        7)  printf '连接被拒绝' ;;
        28) printf '连接超时' ;;
        35) printf 'SSL 握手失败' ;;
        22) printf 'HTTP 错误（服务器返回 4xx/5xx）' ;;
        *)  printf '未知网络错误（curl 退出码: %s）' "$code" ;;
    esac
}

# 通过 Caddy 官方 API 下载静态二进制文件并安装
# 构造 URL → curl 下载到临时文件 → 校验文件大小 → 安装到 OPT_PREFIX/caddy → chmod +x
# curl 失败时映射错误码并以退出码 3 终止
# 下载文件无效时删除文件并以退出码 1 终止
install_binary_download() {
    local download_url temp_file curl_exit_code=0 error_desc

    # 构造下载 URL
    download_url="$(_build_download_url)"
    util_log_info "下载 Caddy 二进制文件: ${download_url}"

    # 确保临时目录存在
    if [[ -z "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
        TEMP_DIR="$(mktemp -d)"
    fi
    temp_file="${TEMP_DIR}/caddy_download"

    # 使用 curl 下载
    set +e
    curl --connect-timeout 30 --max-time 120 -fSL -o "$temp_file" "$download_url"
    curl_exit_code=$?
    set -e

    # 处理 curl 错误
    if [[ "$curl_exit_code" -ne 0 ]]; then
        error_desc="$(_describe_curl_error "$curl_exit_code")"
        util_log_error "下载失败: ${error_desc}"
        # 清理可能的部分下载文件
        rm -f "$temp_file"
        exit 3
    fi

    # 校验下载文件大小（不为 0）
    if [[ ! -s "$temp_file" ]]; then
        util_log_error "下载的文件无效（大小为 0）"
        rm -f "$temp_file"
        exit 1
    fi

    # 安装到目标目录
    util_log_info "安装 Caddy 到 ${OPT_PREFIX}/caddy..."
    if ! _run_privileged mkdir -p "$OPT_PREFIX"; then
        util_log_error "创建安装目录失败: ${OPT_PREFIX}"
        rm -f "$temp_file"
        exit 1
    fi

    if ! _run_privileged cp "$temp_file" "${OPT_PREFIX}/caddy"; then
        util_log_error "复制文件到 ${OPT_PREFIX}/caddy 失败"
        rm -f "$temp_file"
        exit 1
    fi

    if ! _run_privileged chmod +x "${OPT_PREFIX}/caddy"; then
        util_log_error "设置可执行权限失败: ${OPT_PREFIX}/caddy"
        exit 1
    fi

    # 清理临时文件
    rm -f "$temp_file"

    CADDY_BIN="${OPT_PREFIX}/caddy"
    util_log_success "Caddy 已通过二进制下载安装成功"
    return 0
}

# ============================================================================
# 后置处理模块
# ============================================================================

# 检测并停止/禁用 caddy.service
# 受 --skip-service 控制；systemctl 不可用时跳过并输出提示到 stderr
post_disable_service() {
    # 受 --skip-service 控制
    if [[ "$OPT_SKIP_SERVICE" == true ]]; then
        return 0
    fi

    # 检测 systemctl 是否可用
    if ! command -v systemctl >/dev/null 2>&1; then
        util_log_warn "systemctl 不可用，跳过服务处理"
        return 0
    fi

    # 检测 caddy.service 是否存在
    if ! systemctl list-unit-files caddy.service >/dev/null 2>&1; then
        util_log_info "未检测到 caddy.service，跳过服务处理"
        return 0
    fi

    # 检查 caddy.service 是否在 list-unit-files 输出中（确认单元文件存在）
    if ! systemctl list-unit-files caddy.service 2>/dev/null | grep -q 'caddy.service'; then
        util_log_info "未检测到 caddy.service，跳过服务处理"
        return 0
    fi

    # 如果服务正在运行，停止它
    if systemctl is-active --quiet caddy.service 2>/dev/null; then
        util_log_info "停止 caddy.service..."
        _run_privileged systemctl stop caddy.service || true
    fi

    # 如果服务已启用，禁用它
    if systemctl is-enabled --quiet caddy.service 2>/dev/null; then
        util_log_info "禁用 caddy.service..."
        _run_privileged systemctl disable caddy.service || true
    fi

    util_log_success "caddy.service 已停止并禁用"
    return 0
}

# 对 Caddy 二进制执行 setcap 设置端口绑定能力
# 受 --skip-cap 控制；setcap 不可用或执行失败时仅警告不终止
post_set_capabilities() {
    # 受 --skip-cap 控制
    if [[ "$OPT_SKIP_CAP" == true ]]; then
        return 0
    fi

    # 确定 Caddy 二进制路径
    local caddy_bin="${CADDY_BIN:-$(command -v caddy 2>/dev/null || true)}"
    if [[ -z "$caddy_bin" ]]; then
        util_log_warn "未找到 Caddy 二进制文件，跳过 setcap"
        return 0
    fi

    # 检测 setcap 是否可用
    if ! command -v setcap >/dev/null 2>&1; then
        util_log_warn "setcap 不可用，无法设置端口绑定能力。请安装 libcap2-bin（Debian 系）或 libcap（RPM 系）"
        return 0
    fi

    # 执行 setcap
    util_log_info "设置 Caddy 端口绑定能力..."
    if ! _run_privileged setcap 'cap_net_bind_service=+ep' "$caddy_bin"; then
        util_log_warn "setcap 执行失败，Caddy 可能无法在非 root 用户下绑定 80/443 端口"
        return 0
    fi

    util_log_success "已为 Caddy 设置端口绑定能力 (cap_net_bind_service)"
    return 0
}

# 验证 Caddy 安装成功
# 执行 caddy version，失败时以退出码 1 终止
post_verify() {
    local caddy_bin="${CADDY_BIN:-$(command -v caddy 2>/dev/null || true)}"
    if [[ -z "$caddy_bin" ]]; then
        util_log_error "未找到 Caddy 二进制文件，安装验证失败"
        exit 1
    fi

    util_log_info "验证 Caddy 安装..."
    if ! "$caddy_bin" version >/dev/null 2>&1; then
        util_log_error "caddy version 执行失败，安装可能已损坏"
        exit 1
    fi

    util_log_success "Caddy 安装验证成功: $("$caddy_bin" version 2>/dev/null)"
    return 0
}

# ============================================================================
# 主流程
# ============================================================================

# 主函数：串联所有模块，实现完整安装流程
main() {
    # 1. 检测颜色支持
    util_has_color

    # 2. 解析命令行参数
    parse_args "$@"

    # 3. 检测 root/sudo 权限
    util_check_root

    # 4-7. 检测操作系统、架构、分类、包管理器
    detect_os
    detect_arch
    detect_classify
    detect_pkg_manager

    # 8. 检测是否已安装
    if check_installed; then
        if [[ -z "$OPT_VERSION" ]]; then
            # 未指定 --version，已安装即跳过
            util_log_success "Caddy 已安装: ${CADDY_BIN}"
            printf '%s\n' "$CADDY_BIN"
            exit 0
        fi
        if check_version_match; then
            # 版本匹配，跳过安装
            util_log_success "Caddy ${OPT_VERSION} 已安装，无需更新"
            printf '%s\n' "$CADDY_BIN"
            exit 0
        fi
        # 版本不匹配，继续安装流程
        util_log_info "已安装的 Caddy 版本与目标版本 ${OPT_VERSION} 不一致，将进行更新"
    fi

    # 9. 路由安装方式
    local install_rc=0

    if [[ "$OPT_METHOD" == "binary" ]]; then
        # 用户明确指定二进制下载
        INSTALL_METHOD_USED="binary"
        install_binary_download
    else
        # 根据 OS_CLASS 选择安装方式
        case "$OS_CLASS" in
            standard_deb)
                INSTALL_METHOD_USED="apt"
                util_log_info "使用 APT 仓库安装..."
                install_apt_repo || install_rc=$?
                ;;
            standard_rpm)
                INSTALL_METHOD_USED="copr"
                util_log_info "使用 COPR 仓库安装..."
                install_copr_repo || install_rc=$?
                ;;
            unsupported_rpm)
                INSTALL_METHOD_USED="selfhosted"
                util_log_info "使用自建 DNF 仓库安装..."
                install_selfhosted_repo || install_rc=$?
                ;;
            unknown|*)
                # 未知 OS 直接使用二进制下载
                INSTALL_METHOD_USED="binary"
                util_log_info "未知操作系统分类，使用二进制下载安装..."
                install_binary_download
                install_rc=0
                ;;
        esac

        # Fallback 逻辑：包仓库失败时的处理
        if [[ "$install_rc" -ne 0 ]]; then
            if [[ "$OPT_METHOD" == "repo" ]]; then
                # 用户明确指定仅使用仓库，不回退
                util_log_error "包仓库安装失败，--method=repo 模式下不回退到二进制下载"
                exit 1
            fi
            # 自动回退到二进制下载
            util_log_warn "包仓库安装失败，回退到二进制下载方式..."
            INSTALL_METHOD_USED="binary"
            install_binary_download
        fi
    fi

    # 10. 后置处理
    post_disable_service
    post_set_capabilities
    post_verify

    # 11. 确定 Caddy 二进制路径
    if [[ -z "$CADDY_BIN" ]]; then
        CADDY_BIN="$(command -v caddy 2>/dev/null || true)"
    fi

    if [[ -z "$CADDY_BIN" ]]; then
        # 尝试常见路径
        if [[ -x "/usr/bin/caddy" ]]; then
            CADDY_BIN="/usr/bin/caddy"
        elif [[ -x "/usr/local/bin/caddy" ]]; then
            CADDY_BIN="/usr/local/bin/caddy"
        else
            util_log_error "安装完成但无法定位 Caddy 二进制文件"
            exit 1
        fi
    fi

    # 12. 输出 Caddy 二进制绝对路径到 stdout（最后一行）
    util_log_success "Caddy 安装完成 (方式: ${INSTALL_METHOD_USED})"
    printf '%s\n' "$CADDY_BIN"

    # 13. 成功退出
    exit 0
}

# ============================================================================
# 脚本入口：仅在非测试模式下执行 main
# ============================================================================
if [[ "${_SOURCED_FOR_TEST:-}" != true ]]; then
    main "$@"
fi
