#!/usr/bin/env bash
# ============================================================================
# build-repo.sh — 自建 RPM 仓库构建系统
# 按产品线组织构建 Caddy Server RPM 包，通过符号链接提供发行版友好路径
# 支持 7 条产品线 × 2 架构 = 14 个 RPM 包，28+ 个发行版友好路径
# ============================================================================
set -euo pipefail

# === 退出码常量 ===
EXIT_OK=0
EXIT_ARG_ERROR=1
EXIT_DEP_MISSING=2
EXIT_DOWNLOAD_FAIL=3
EXIT_PACKAGE_FAIL=4
EXIT_SIGN_FAIL=5
EXIT_METADATA_FAIL=6
EXIT_PUBLISH_FAIL=7
EXIT_VERIFY_FAIL=8

# === 参数解析结果 ===
OPT_VERSION=""                              # --version: Caddy 版本号
OPT_OUTPUT="./repo"                         # --output: 仓库输出根目录
OPT_GPG_KEY_ID=""                           # --gpg-key-id: GPG 密钥 ID
OPT_GPG_KEY_FILE=""                         # --gpg-key-file: GPG 私钥文件路径
OPT_ARCH="all"                              # --arch: x86_64 | aarch64 | all
OPT_DISTRO="all"                            # --distro: distro:version,... | all
OPT_BASE_URL="https://rpms.example.com"     # --base-url: .repo 模板基础 URL
OPT_STAGE=""                                # --stage: build | sign | publish | verify
OPT_ROLLBACK=false                          # --rollback: 回滚到最近备份
OPT_SM2_KEY=""                              # --sm2-key: SM2 私钥路径（国密产品线）

# === 运行时状态 ===
CADDY_VERSION=""            # 最终确定的 Caddy 版本号
TARGET_ARCHS=()             # 目标架构列表
TARGET_PRODUCT_LINES=()     # 目标产品线列表
STAGING_DIR=""              # staging 目录路径
BUILD_START_TIME=""         # 构建开始时间
RPM_COUNT=0                 # 生成的 RPM 包计数
SYMLINK_COUNT=0             # 生成的符号链接计数

# === 脚本目录（用于定位 packaging/ 资源文件）===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === 颜色输出控制 ===
USE_COLOR=true

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

# 错误日志（红色），输出到 stderr
util_log_error() {
    local msg="$1"
    if [[ "$USE_COLOR" == true ]]; then
        printf '\033[0;31m[ERROR]\033[0m %s\n' "$msg" >&2
    else
        printf '[ERROR] %s\n' "$msg" >&2
    fi
}

# ============================================================================
# 产品线映射模块
# ============================================================================

# 产品线标识 → 目录路径（使用 -gA 确保 source 时为全局变量）
declare -gA PRODUCT_LINE_PATHS=(
    [el8]="el8"
    [el9]="el9"
    [el10]="el10"
    [al2023]="al2023"
    [fedora]="fedora"
    [oe22]="openeuler/22"
    [oe24]="openeuler/24"
)

# 产品线标识 → RPM 包标签
declare -gA PRODUCT_LINE_TAGS=(
    [el8]="el8"
    [el9]="el9"
    [el10]="el10"
    [al2023]="al2023"
    [fedora]="fc"
    [oe22]="oe22"
    [oe24]="oe24"
)

# 产品线标识 → 压缩算法
declare -gA PRODUCT_LINE_COMPRESS=(
    [el8]="xz"
    [el9]="zstd"
    [el10]="zstd"
    [al2023]="zstd"
    [fedora]="zstd"
    [oe22]="zstd"
    [oe24]="zstd"
)

# 发行版 → 产品线映射（distro_id:version → product_line_id）
declare -gA DISTRO_TO_PRODUCT_LINE=(
    # EL8
    [rhel:8]="el8" [centos:8]="el8" [almalinux:8]="el8" [rocky:8]="el8"
    [anolis:8]="el8" [ol:8]="el8" [opencloudos:8]="el8"
    [kylin:V10]="el8" [alinux:3]="el8"
    # EL9
    [rhel:9]="el9" [centos:9]="el9" [almalinux:9]="el9" [rocky:9]="el9"
    [anolis:23]="el9" [ol:9]="el9" [opencloudos:9]="el9"
    [kylin:V11]="el9" [alinux:4]="el9"
    # EL10
    [rhel:10]="el10" [centos:10]="el10" [almalinux:10]="el10"
    [rocky:10]="el10" [ol:10]="el10"
    # AL2023
    [amzn:2023]="al2023"
    # Fedora
    [fedora:42]="fedora" [fedora:43]="fedora"
    # openEuler
    [openEuler:22]="oe22" [openEuler:24]="oe24"
)

# 全部产品线 ID 列表（用于 "all" 模式）
ALL_PRODUCT_LINES=(el8 el9 el10 al2023 fedora oe22 oe24)

# ----------------------------------------------------------------------------
# resolve_product_lines "$distro_spec"
# 将 --distro 参数值解析为产品线 ID 集合，结果存入 TARGET_PRODUCT_LINES
# 参数: distro_spec — "all" 或逗号分隔的 distro:version 列表
# ----------------------------------------------------------------------------
resolve_product_lines() {
    local distro_spec="$1"

    if [[ "$distro_spec" == "all" ]]; then
        TARGET_PRODUCT_LINES=("${ALL_PRODUCT_LINES[@]}")
        return 0
    fi

    local -A seen_pls=()
    local result=()
    local IFS=','

    for entry in $distro_spec; do
        # 去除首尾空白
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"

        # openEuler:20 特殊处理：输出警告并跳过
        if [[ "$entry" == "openEuler:20" ]]; then
            util_log_error "openEuler 20 is not supported, skipping"
            continue
        fi

        # 查找映射
        local pl_id="${DISTRO_TO_PRODUCT_LINE[$entry]:-}"
        if [[ -z "$pl_id" ]]; then
            util_log_error "Unknown distro:version '$entry'. Valid values: ${!DISTRO_TO_PRODUCT_LINE[*]}"
            exit "$EXIT_ARG_ERROR"
        fi

        # 去重
        if [[ -z "${seen_pls[$pl_id]:-}" ]]; then
            seen_pls[$pl_id]=1
            result+=("$pl_id")
        fi
    done

    TARGET_PRODUCT_LINES=("${result[@]}")

    # 如果解析后产品线列表为空，说明所有指定的 distro 都被跳过或无效
    if [[ ${#TARGET_PRODUCT_LINES[@]} -eq 0 ]]; then
        util_log_error "没有有效的目标产品线（所有指定的 distro 均被跳过或不支持）"
        exit "$EXIT_ARG_ERROR"
    fi
}

# ----------------------------------------------------------------------------
# get_product_line_path "$pl_id"
# 返回产品线的目录路径
# ----------------------------------------------------------------------------
get_product_line_path() {
    local pl_id="$1"
    printf '%s' "${PRODUCT_LINE_PATHS[$pl_id]}"
}

# ----------------------------------------------------------------------------
# get_product_line_tag "$pl_id"
# 返回产品线的 RPM 包标签
# ----------------------------------------------------------------------------
get_product_line_tag() {
    local pl_id="$1"
    printf '%s' "${PRODUCT_LINE_TAGS[$pl_id]}"
}

# ----------------------------------------------------------------------------
# get_compress_type "$pl_id"
# 返回产品线的压缩算法
# ----------------------------------------------------------------------------
get_compress_type() {
    local pl_id="$1"
    printf '%s' "${PRODUCT_LINE_COMPRESS[$pl_id]}"
}

# ============================================================================
# 参数解析模块
# ============================================================================

# ----------------------------------------------------------------------------
# parse_show_help
# 输出用法说明到 stderr 并以退出码 0 退出
# ----------------------------------------------------------------------------
parse_show_help() {
    cat >&2 <<'EOF'
用法: build-repo.sh [选项]

选项:
  --version <VERSION>      指定要打包的 Caddy 版本号（如 2.9.0）
  --output <DIR>           仓库输出根目录（默认: ./repo）
  --gpg-key-id <KEY_ID>    用于签名的 GPG 密钥 ID
  --gpg-key-file <PATH>    GPG 私钥文件路径（用于 nfpm 签名，适合 CI/CD）
  --arch <ARCH>            目标架构: x86_64, aarch64, all（默认: all）
  --distro <SPEC>          目标发行版: distro:version,... 或 all（默认: all）
  --base-url <URL>         .repo 模板基础 URL（默认: https://rpms.example.com）
  --stage <STAGE>          执行指定阶段: build, sign, publish, verify
  --rollback               回滚到最近一次备份
  --sm2-key <PATH>         SM2 私钥文件路径（国密产品线，可选）
  -h, --help               显示此帮助信息

示例:
  bash build-repo.sh --version 2.9.0
  bash build-repo.sh --version 2.9.0 --arch x86_64 --distro anolis:8,anolis:23
  bash build-repo.sh --stage build --gpg-key-file /path/to/key.gpg
  bash build-repo.sh --rollback
EOF
    exit 0
}

# ----------------------------------------------------------------------------
# parse_args "$@"
# 解析命令行参数，设置全局变量。无效参数以退出码 1 终止。
# ----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --version 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_VERSION="$2"
                shift 2
                ;;
            --output)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --output 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_OUTPUT="$2"
                shift 2
                ;;
            --gpg-key-id)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --gpg-key-id 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_GPG_KEY_ID="$2"
                shift 2
                ;;
            --gpg-key-file)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --gpg-key-file 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_GPG_KEY_FILE="$2"
                shift 2
                ;;
            --arch)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --arch 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_ARCH="$2"
                if [[ "$OPT_ARCH" != "x86_64" && "$OPT_ARCH" != "aarch64" && "$OPT_ARCH" != "all" ]]; then
                    util_log_error "--arch 仅允许 'x86_64'、'aarch64' 或 'all'，收到: '$OPT_ARCH'"
                    exit "$EXIT_ARG_ERROR"
                fi
                shift 2
                ;;
            --distro)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --distro 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_DISTRO="$2"
                shift 2
                ;;
            --base-url)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --base-url 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_BASE_URL="$2"
                shift 2
                ;;
            --stage)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --stage 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_STAGE="$2"
                if [[ "$OPT_STAGE" != "build" && "$OPT_STAGE" != "sign" && "$OPT_STAGE" != "publish" && "$OPT_STAGE" != "verify" ]]; then
                    util_log_error "--stage 仅允许 'build'、'sign'、'publish' 或 'verify'，收到: '$OPT_STAGE'"
                    exit "$EXIT_ARG_ERROR"
                fi
                shift 2
                ;;
            --rollback)
                OPT_ROLLBACK=true
                shift
                ;;
            --sm2-key)
                if [[ $# -lt 2 ]]; then
                    util_log_error "参数 --sm2-key 需要一个值"
                    exit "$EXIT_ARG_ERROR"
                fi
                OPT_SM2_KEY="$2"
                shift 2
                ;;
            -h|--help)
                parse_show_help
                ;;
            *)
                util_log_error "未知参数: $1"
                cat >&2 <<'EOF'
使用 --help 查看可用选项
EOF
                exit "$EXIT_ARG_ERROR"
                ;;
        esac
    done
}

# ============================================================================
# 依赖检查模块
# ============================================================================

# ----------------------------------------------------------------------------
# check_dependencies
# 检查必要工具是否可用：curl、nfpm、createrepo_c（或 createrepo）、gpg、rpm
# 缺失时输出工具名称和安装建议，以退出码 2 终止
# ----------------------------------------------------------------------------
check_dependencies() {
    local missing=()
    local suggestions=()

    if ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
        suggestions+=("  curl: dnf install curl")
    fi

    if ! command -v nfpm >/dev/null 2>&1; then
        missing+=("nfpm")
        suggestions+=("  nfpm: https://nfpm.goreleaser.com/install/")
    fi

    if ! command -v createrepo_c >/dev/null 2>&1 && ! command -v createrepo >/dev/null 2>&1; then
        missing+=("createrepo_c")
        suggestions+=("  createrepo_c: dnf install createrepo_c")
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        missing+=("gpg")
        suggestions+=("  gpg: dnf install gnupg2")
    fi

    if ! command -v rpm >/dev/null 2>&1; then
        missing+=("rpm")
        suggestions+=("  rpm: dnf install rpm")
    fi

    if ! command -v flock >/dev/null 2>&1; then
        missing+=("flock")
        suggestions+=("  flock: dnf install util-linux")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        util_log_error "缺少必要工具: ${missing[*]}"
        util_log_error "安装建议:"
        for s in "${suggestions[@]}"; do
            util_log_error "$s"
        done
        exit "$EXIT_DEP_MISSING"
    fi
}

# ----------------------------------------------------------------------------
# check_gpg_key "$key_id"
# 检查 GPG 密钥 ID 是否存在于本地密钥环
# 不存在时输出错误信息并以退出码 2 终止
# ----------------------------------------------------------------------------
check_gpg_key() {
    local key_id="$1"
    if ! gpg --list-keys "$key_id" >/dev/null 2>&1; then
        util_log_error "GPG 密钥 '$key_id' 不存在于本地密钥环"
        exit "$EXIT_DEP_MISSING"
    fi
}

# ============================================================================
# 版本查询模块
# ============================================================================

# ----------------------------------------------------------------------------
# extract_version_from_tag "$tag"
# 从 tag_name 中提取版本号，去除 v 前缀
# 可独立测试的纯函数
# ----------------------------------------------------------------------------
extract_version_from_tag() {
    local tag="$1"
    printf '%s' "${tag#v}"
}

# ----------------------------------------------------------------------------
# resolve_version
# 确定要打包的 Caddy 版本号，设置 CADDY_VERSION 全局变量
# - OPT_VERSION 非空时直接使用（去除可能的 v 前缀）
# - OPT_VERSION 为空时通过 GitHub Releases API 查询最新稳定版本
# 失败时以退出码 3 终止
# Requirements: 14.1, 14.2, 14.3, 14.4, 2.7
# ----------------------------------------------------------------------------
resolve_version() {
    if [[ -n "$OPT_VERSION" ]]; then
        CADDY_VERSION="$(extract_version_from_tag "$OPT_VERSION")"
        util_log_info "使用指定版本: ${CADDY_VERSION}"
        return 0
    fi

    util_log_info "查询 Caddy 最新稳定版本..."
    local api_response
    local curl_args=(-fsSL)
    [[ -n "${GITHUB_TOKEN:-}" ]] && curl_args+=(-H "Authorization: token ${GITHUB_TOKEN}")
    api_response="$(curl "${curl_args[@]}" "https://api.github.com/repos/caddyserver/caddy/releases/latest" 2>/dev/null)" || {
        util_log_error "查询 Caddy 版本失败: 无法访问 GitHub Releases API"
        exit "$EXIT_DOWNLOAD_FAIL"
    }

    local tag_name
    tag_name="$(printf '%s' "$api_response" | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/')" || true

    if [[ -z "$tag_name" ]]; then
        util_log_error "查询 Caddy 版本失败: 无法从 API 响应中提取版本号"
        exit "$EXIT_DOWNLOAD_FAIL"
    fi

    CADDY_VERSION="$tag_name"
    util_log_info "最新稳定版本: ${CADDY_VERSION}"
}

# ============================================================================
# 二进制下载模块
# ============================================================================

# 已下载架构追踪：arch → binary_path（跨产品线复用）
declare -gA DOWNLOADED_ARCHS=()

# ----------------------------------------------------------------------------
# map_arch_to_go "$arch"
# 将系统架构映射为 Go 架构标识
# x86_64 → amd64, aarch64 → arm64
# ----------------------------------------------------------------------------
map_arch_to_go() {
    local arch="$1"
    case "$arch" in
        x86_64)  printf 'amd64' ;;
        aarch64) printf 'arm64' ;;
        *)
            util_log_error "不支持的架构: $arch"
            exit "$EXIT_DOWNLOAD_FAIL"
            ;;
    esac
}

# ----------------------------------------------------------------------------
# build_download_url "$go_arch"
# 构造 Caddy API 下载 URL
# 需要 CADDY_VERSION 全局变量已设置
# ----------------------------------------------------------------------------
build_download_url() {
    local go_arch="$1"
    printf 'https://caddyserver.com/api/download?os=linux&arch=%s&version=%s' "$go_arch" "$CADDY_VERSION"
}

# ----------------------------------------------------------------------------
# download_caddy_binary "$arch"
# 为指定架构下载 Caddy 二进制文件
# - 优先使用 vendor/ 目录中的本地文件
# - 不存在时从 Caddy API 下载
# - 同一架构仅下载一次，跨产品线复用
# - 下载后验证文件大小 > 0
# 结果路径存入 DOWNLOADED_ARCHS[$arch]
# Requirements: 4.1, 4.2, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6
# ----------------------------------------------------------------------------
download_caddy_binary() {
    local arch="$1"

    # 同一架构仅下载一次
    if [[ -n "${DOWNLOADED_ARCHS[$arch]:-}" ]]; then
        util_log_info "架构 ${arch} 二进制文件已就绪，复用: ${DOWNLOADED_ARCHS[$arch]}"
        return 0
    fi

    local go_arch
    go_arch="$(map_arch_to_go "$arch")"

    local vendor_file="vendor/caddy-${CADDY_VERSION}-linux-${go_arch}"

    # 优先使用 vendor/ 目录中的本地文件
    if [[ -f "$vendor_file" ]]; then
        util_log_info "使用 vendor 目录文件: ${vendor_file}"
        DOWNLOADED_ARCHS[$arch]="$vendor_file"
        return 0
    fi

    # 从 Caddy API 下载
    local download_url
    download_url="$(build_download_url "$go_arch")"

    # 创建临时目录存放下载文件（如果尚未创建）
    local tmp_dir="${TMPDIR:-/tmp}/caddy-build-$$"
    mkdir -p "$tmp_dir"
    local dest="${tmp_dir}/caddy-${CADDY_VERSION}-linux-${go_arch}"

    util_log_info "下载 Caddy ${CADDY_VERSION} (${arch}/${go_arch})..."
    util_log_info "URL: ${download_url}"

    local http_code
    local curl_exit=0
    http_code="$(curl -fSL -o "$dest" -w '%{http_code}' "$download_url" 2>/dev/null)" || curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
        util_log_error "下载 Caddy 二进制文件失败 (架构: ${arch})"
        util_log_error "curl 退出码: ${curl_exit}, HTTP 状态码: ${http_code:-unknown}"
        rm -f "$dest"
        exit "$EXIT_DOWNLOAD_FAIL"
    fi

    # 验证文件大小 > 0
    if [[ ! -s "$dest" ]]; then
        util_log_error "下载的文件大小为 0 字节: ${dest}"
        rm -f "$dest"
        exit "$EXIT_DOWNLOAD_FAIL"
    fi

    chmod +x "$dest"
    DOWNLOADED_ARCHS[$arch]="$dest"
    util_log_info "下载完成: ${dest} ($(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null || echo '?') 字节)"
}

# ============================================================================
# RPM 打包模块（nfpm）
# ============================================================================

# ----------------------------------------------------------------------------
# generate_nfpm_config "$pl_id" "$arch"
# 动态生成 nfpm YAML 配置文件，输出生成的文件路径到 stdout
# 参数:
#   pl_id — 产品线 ID（如 el8、el9、fedora、oe22 等）
#   arch  — 目标架构（x86_64 或 aarch64）
# 需要全局变量: CADDY_VERSION, DOWNLOADED_ARCHS, OPT_GPG_KEY_FILE, STAGING_DIR, SCRIPT_DIR
# Requirements: 6.1, 6.3, 6.8, 6.9, 9.2
# ----------------------------------------------------------------------------
generate_nfpm_config() {
    local pl_id="$1"
    local arch="$2"

    local pl_tag
    pl_tag="$(get_product_line_tag "$pl_id")"

    local compress_type
    compress_type="$(get_compress_type "$pl_id")"

    local binary_path="${DOWNLOADED_ARCHS[$arch]}"

    local config_dir="${STAGING_DIR:-${TMPDIR:-/tmp}}/nfpm-configs"
    mkdir -p "$config_dir"
    local config_file="${config_dir}/nfpm-${pl_id}-${arch}.yaml"

    local pkg_dir="${SCRIPT_DIR}/packaging"

    # Generate base YAML config
    cat > "$config_file" <<EOF
name: caddy
arch: "${arch}"
platform: linux
version: "${CADDY_VERSION}"
release: "1.${pl_tag}"
maintainer: "Caddy <https://caddyserver.com>"
description: "Caddy - powerful, enterprise-ready, open source web server"
vendor: "Caddy"
homepage: "https://caddyserver.com"
license: "Apache-2.0"

rpm:
  compression: "${compress_type}"
EOF

    # Conditionally add GPG signature config
    if [[ -n "${OPT_GPG_KEY_FILE:-}" ]]; then
        cat >> "$config_file" <<EOF
  signature:
    key_file: "${OPT_GPG_KEY_FILE}"
EOF
    fi

    # Add contents and scripts sections
    cat >> "$config_file" <<EOF

contents:
  - src: "${binary_path}"
    dst: /usr/bin/caddy
    file_info:
      mode: 0755
  - src: "${pkg_dir}/caddy.service"
    dst: /usr/lib/systemd/system/caddy.service
  - src: "${pkg_dir}/Caddyfile"
    dst: /etc/caddy/Caddyfile
    type: config|noreplace
  - src: "${pkg_dir}/LICENSE"
    dst: /usr/share/licenses/caddy/LICENSE
  - dst: /etc/caddy/
    type: dir
  - dst: /var/lib/caddy/
    type: dir

scripts:
  postinstall: "${pkg_dir}/scripts/postinstall.sh"
  preremove: "${pkg_dir}/scripts/preremove.sh"
EOF

    printf '%s' "$config_file"
}

# ----------------------------------------------------------------------------
# build_rpm "$pl_id" "$arch"
# 调用 nfpm 生成 RPM 包，放置到 staging 目录
# 参数:
#   pl_id — 产品线 ID（如 el8、el9、fedora、oe22 等）
#   arch  — 目标架构（x86_64 或 aarch64）
# 幂等性：如目标目录已存在相同版本 RPM 包，跳过并输出提示
# nfpm 失败以退出码 4 终止
# 成功时递增 RPM_COUNT
# Requirements: 6.1, 6.2, 6.3, 6.12, 15.1
# ----------------------------------------------------------------------------
build_rpm() {
    local pl_id="$1"
    local arch="$2"

    local pl_tag
    pl_tag="$(get_product_line_tag "$pl_id")"
    local pl_path
    pl_path="$(get_product_line_path "$pl_id")"

    local rpm_name="caddy-${CADDY_VERSION}-1.${pl_tag}.${arch}.rpm"
    local target_dir="${STAGING_DIR}/caddy/${pl_path}/${arch}/Packages"
    local target_rpm="${target_dir}/${rpm_name}"

    # Idempotency: skip if RPM already exists
    if [[ -f "$target_rpm" ]]; then
        util_log_info "RPM 已存在，跳过: ${rpm_name}"
        return 0
    fi

    mkdir -p "$target_dir"

    # Generate nfpm config
    local config_file
    config_file="$(generate_nfpm_config "$pl_id" "$arch")"

    util_log_info "构建 RPM: ${rpm_name}"

    # Call nfpm to build the RPM
    if ! nfpm package --config "$config_file" --packager rpm --target "$target_dir" 2>&1; then
        util_log_error "nfpm 打包失败: ${rpm_name}"
        exit "$EXIT_PACKAGE_FAIL"
    fi

    # Verify the RPM was created
    if [[ ! -f "$target_rpm" ]]; then
        util_log_error "RPM 文件未生成: ${target_rpm}"
        exit "$EXIT_PACKAGE_FAIL"
    fi

    RPM_COUNT=$((RPM_COUNT + 1))
    util_log_info "RPM 构建完成: ${rpm_name}"
}

# ============================================================================
# SELinux 可选子包模块（caddy-selinux）
# ============================================================================

# SELinux 策略文件路径（相对于 SCRIPT_DIR）
SELINUX_POLICY_FILE="packaging/caddy.pp"

# ----------------------------------------------------------------------------
# generate_selinux_nfpm_config "$pl_id" "$arch"
# 动态生成 caddy-selinux 子包的 nfpm YAML 配置文件，输出生成的文件路径到 stdout
# 参数:
#   pl_id — 产品线 ID（如 el8、el9、fedora、oe22 等）
#   arch  — 目标架构（x86_64 或 aarch64）
# 需要全局变量: CADDY_VERSION, OPT_GPG_KEY_FILE, STAGING_DIR, SCRIPT_DIR
# Requirements: 8.1, 8.2, 8.3
# ----------------------------------------------------------------------------
generate_selinux_nfpm_config() {
    local pl_id="$1"
    local arch="$2"

    local pl_tag
    pl_tag="$(get_product_line_tag "$pl_id")"

    local compress_type
    compress_type="$(get_compress_type "$pl_id")"

    local config_dir="${STAGING_DIR:-${TMPDIR:-/tmp}}/nfpm-configs"
    mkdir -p "$config_dir"
    local config_file="${config_dir}/nfpm-selinux-${pl_id}-${arch}.yaml"

    local pkg_dir="${SCRIPT_DIR}/packaging"
    local policy_src="${SCRIPT_DIR}/${SELINUX_POLICY_FILE}"

    # Generate base YAML config
    cat > "$config_file" <<EOF
name: caddy-selinux
arch: "${arch}"
platform: linux
version: "${CADDY_VERSION}"
release: "1.${pl_tag}"
maintainer: "Caddy <https://caddyserver.com>"
description: "SELinux policy module for Caddy web server"
vendor: "Caddy"
homepage: "https://caddyserver.com"
license: "Apache-2.0"

rpm:
  compression: "${compress_type}"
EOF

    # Conditionally add GPG signature config
    if [[ -n "${OPT_GPG_KEY_FILE:-}" ]]; then
        cat >> "$config_file" <<EOF
  signature:
    key_file: "${OPT_GPG_KEY_FILE}"
EOF
    fi

    # Add contents and scripts sections
    cat >> "$config_file" <<EOF

contents:
  - src: "${policy_src}"
    dst: /usr/share/selinux/packages/caddy.pp

scripts:
  postinstall: "${pkg_dir}/scripts/selinux-postinstall.sh"
  preremove: "${pkg_dir}/scripts/selinux-preremove.sh"
EOF

    printf '%s' "$config_file"
}

# ----------------------------------------------------------------------------
# build_selinux_rpm "$pl_id" "$arch"
# 构建 caddy-selinux 子包 RPM
# - 仅在 SELinux 策略文件存在时构建
# - 与 build_rpm 相同的幂等性模式
# 参数:
#   pl_id — 产品线 ID
#   arch  — 目标架构
# Requirements: 8.1, 8.2, 8.3
# ----------------------------------------------------------------------------
build_selinux_rpm() {
    local pl_id="$1"
    local arch="$2"

    # Only build if SELinux policy file exists
    if [[ ! -f "${SCRIPT_DIR}/${SELINUX_POLICY_FILE}" ]]; then
        return 0
    fi

    local pl_tag
    pl_tag="$(get_product_line_tag "$pl_id")"
    local pl_path
    pl_path="$(get_product_line_path "$pl_id")"

    local rpm_name="caddy-selinux-${CADDY_VERSION}-1.${pl_tag}.${arch}.rpm"
    local target_dir="${STAGING_DIR}/caddy/${pl_path}/${arch}/Packages"
    local target_rpm="${target_dir}/${rpm_name}"

    # Idempotency: skip if RPM already exists
    if [[ -f "$target_rpm" ]]; then
        util_log_info "SELinux RPM 已存在，跳过: ${rpm_name}"
        return 0
    fi

    mkdir -p "$target_dir"

    # Generate nfpm config
    local config_file
    config_file="$(generate_selinux_nfpm_config "$pl_id" "$arch")"

    util_log_info "构建 SELinux RPM: ${rpm_name}"

    # Call nfpm to build the RPM
    if ! nfpm package --config "$config_file" --packager rpm --target "$target_dir" 2>&1; then
        util_log_error "nfpm 打包失败 (SELinux): ${rpm_name}"
        exit "$EXIT_PACKAGE_FAIL"
    fi

    # Verify the RPM was created
    if [[ ! -f "$target_rpm" ]]; then
        util_log_error "SELinux RPM 文件未生成: ${target_rpm}"
        exit "$EXIT_PACKAGE_FAIL"
    fi

    RPM_COUNT=$((RPM_COUNT + 1))
    util_log_info "SELinux RPM 构建完成: ${rpm_name}"
}

# ============================================================================
# GPG 签名模块
# ============================================================================

# ----------------------------------------------------------------------------
# sign_rpm "$rpm_path"
# 对 RPM 包签名
# - 如果 OPT_GPG_KEY_FILE 已设置，nfpm 在构建时已完成签名，直接返回
# - 否则回退到 rpm --addsign（需要 OPT_GPG_KEY_ID）
# 签名失败以退出码 5 终止
# Requirements: 9.1, 9.2, 9.3
# ----------------------------------------------------------------------------
sign_rpm() {
    local rpm_path="$1"

    # If nfpm signing was configured (OPT_GPG_KEY_FILE set), signing was done during build
    if [[ -n "${OPT_GPG_KEY_FILE:-}" ]]; then
        util_log_info "RPM 已通过 nfpm 内置签名: $(basename "$rpm_path")"
        return 0
    fi

    # Fall back to rpm --addsign
    if [[ -z "${OPT_GPG_KEY_ID:-}" ]]; then
        util_log_error "未指定 GPG 密钥 ID 或密钥文件，无法签名 RPM"
        exit "$EXIT_SIGN_FAIL"
    fi

    util_log_info "签名 RPM: $(basename "$rpm_path")"
    if ! rpm --addsign --define "%_gpg_name ${OPT_GPG_KEY_ID}" "$rpm_path" >/dev/null 2>&1; then
        util_log_error "RPM 签名失败: $(basename "$rpm_path")"
        exit "$EXIT_SIGN_FAIL"
    fi
}

# ----------------------------------------------------------------------------
# verify_rpm_signature "$rpm_path"
# 使用 rpm -K 验证 RPM 签名
# 验证失败以退出码 5 终止
# Requirements: 9.4, 9.5
# ----------------------------------------------------------------------------
verify_rpm_signature() {
    local rpm_path="$1"
    util_log_info "验证 RPM 签名: $(basename "$rpm_path")"
    if ! rpm -K "$rpm_path" >/dev/null 2>&1; then
        util_log_error "RPM 签名验证失败: $(basename "$rpm_path")"
        exit "$EXIT_SIGN_FAIL"
    fi
}

# ----------------------------------------------------------------------------
# sign_repomd "$repomd_path"
# 使用 gpg --detach-sign --armor 对 repomd.xml 生成分离签名 repomd.xml.asc
# 签名失败以退出码 5 终止
# Requirements: 10.8
# ----------------------------------------------------------------------------
sign_repomd() {
    local repomd_path="$1"
    local asc_path="${repomd_path}.asc"

    util_log_info "签名 repomd.xml: ${repomd_path}"

    local gpg_args=(--detach-sign --armor --output "$asc_path")
    if [[ -n "${OPT_GPG_KEY_ID:-}" ]]; then
        gpg_args+=(--local-user "${OPT_GPG_KEY_ID}")
    fi

    if ! gpg "${gpg_args[@]}" "$repomd_path" 2>/dev/null; then
        util_log_error "repomd.xml 签名失败: ${repomd_path}"
        exit "$EXIT_SIGN_FAIL"
    fi
}

# ----------------------------------------------------------------------------
# export_gpg_pubkey "$output_path"
# 导出 GPG 公钥到指定文件（ASCII-armored PGP 格式）
# 需要 OPT_GPG_KEY_ID 已设置
# 导出失败或文件为空以退出码 5 终止
# Requirements: 10.9
# ----------------------------------------------------------------------------
export_gpg_pubkey() {
    local output_path="$1"

    if [[ -z "${OPT_GPG_KEY_ID:-}" ]]; then
        util_log_error "未指定 GPG 密钥 ID，无法导出公钥"
        exit "$EXIT_SIGN_FAIL"
    fi

    util_log_info "导出 GPG 公钥: ${output_path}"
    if ! gpg --export --armor "${OPT_GPG_KEY_ID}" > "$output_path" 2>/dev/null; then
        util_log_error "GPG 公钥导出失败"
        exit "$EXIT_SIGN_FAIL"
    fi

    if [[ ! -s "$output_path" ]]; then
        util_log_error "导出的 GPG 公钥文件为空"
        rm -f "$output_path"
        exit "$EXIT_SIGN_FAIL"
    fi
}

# ============================================================================
# 国密（SM2/SM3）签名模块（可选）
# 当 --sm2-key 参数提供时启用，使用 SM2 密钥签名、SM3 摘要算法
# 输出到独立目录 {output_dir}/caddy-sm/，与标准产品线隔离
# Requirements: 20.1, 20.2, 20.3, 20.4
# ============================================================================

# ----------------------------------------------------------------------------
# check_sm2_tools
# 检查 SM2 签名所需工具是否可用（gpgsm、rpmsign）
# 返回值: 0 — 工具可用, 1 — 工具不可用
# ----------------------------------------------------------------------------
check_sm2_tools() {
    local missing=()

    if ! command -v gpgsm >/dev/null 2>&1; then
        missing+=("gpgsm")
    fi

    if ! command -v rpmsign >/dev/null 2>&1; then
        missing+=("rpmsign")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        util_log_error "国密签名所需工具不可用: ${missing[*]}，跳过 SM2 签名"
        return 1
    fi

    return 0
}

# ----------------------------------------------------------------------------
# sign_rpm_sm2 "$rpm_path"
# 使用 SM2 密钥和 SM3 摘要算法对 RPM 包签名
# 如果 SM2 工具不可用，优雅跳过
# 参数:
#   rpm_path — RPM 包文件路径
# Requirements: 20.1
# ----------------------------------------------------------------------------
sign_rpm_sm2() {
    local rpm_path="$1"

    if ! check_sm2_tools; then
        return 0
    fi

    util_log_info "SM2 签名 RPM: $(basename "$rpm_path")"
    if ! rpmsign --addsign --digest-algo=sm3 --key-file="$OPT_SM2_KEY" "$rpm_path" >/dev/null 2>&1; then
        util_log_error "SM2 RPM 签名失败: $(basename "$rpm_path")"
        exit "$EXIT_SIGN_FAIL"
    fi
}

# ----------------------------------------------------------------------------
# sign_repomd_sm2 "$repomd_path"
# 使用 SM2 密钥对 repomd.xml 生成分离签名
# 参数:
#   repomd_path — repomd.xml 文件路径
# Requirements: 20.1
# ----------------------------------------------------------------------------
sign_repomd_sm2() {
    local repomd_path="$1"
    local asc_path="${repomd_path}.asc"

    if ! check_sm2_tools; then
        return 0
    fi

    util_log_info "SM2 签名 repomd.xml: ${repomd_path}"
    if ! gpgsm --detach-sign --armor --output "$asc_path" "$repomd_path" 2>/dev/null; then
        util_log_error "SM2 repomd.xml 签名失败: ${repomd_path}"
        exit "$EXIT_SIGN_FAIL"
    fi
}

# ----------------------------------------------------------------------------
# export_sm2_pubkey "$output_path"
# 导出 SM2 公钥到指定文件
# 参数:
#   output_path — 输出文件路径（如 gpg-sm2.key）
# Requirements: 20.4
# ----------------------------------------------------------------------------
export_sm2_pubkey() {
    local output_path="$1"

    if ! check_sm2_tools; then
        return 0
    fi

    util_log_info "导出 SM2 公钥: ${output_path}"
    if ! gpgsm --export --armor > "$output_path" 2>/dev/null; then
        util_log_error "SM2 公钥导出失败"
        exit "$EXIT_SIGN_FAIL"
    fi

    if [[ ! -s "$output_path" ]]; then
        util_log_error "导出的 SM2 公钥文件为空"
        rm -f "$output_path"
        exit "$EXIT_SIGN_FAIL"
    fi
}

# ----------------------------------------------------------------------------
# stage_build_sm2
# 国密产品线构建阶段：
#   1. 复制已构建的 RPM 包到 {output_dir}/caddy-sm/ 目录
#   2. 使用 SM2 签名所有 RPM 包
#   3. 生成独立的 repodata
#   4. 使用 SM2 签名 repomd.xml
#   5. 导出 SM2 公钥到 gpg-sm2.key
# 仅在 OPT_SM2_KEY 非空时调用
# Requirements: 20.1, 20.2, 20.3, 20.4
# ----------------------------------------------------------------------------
stage_build_sm2() {
    if [[ -z "${OPT_SM2_KEY:-}" ]]; then
        return 0
    fi

    util_log_info "开始国密（SM2/SM3）产品线构建..."

    if ! check_sm2_tools; then
        util_log_error "SM2 工具不可用，跳过国密产品线构建"
        return 0
    fi

    local sm_dir="${STAGING_DIR}/caddy-sm"
    local src_dir="${STAGING_DIR}/caddy"

    # Copy RPM packages from standard build to caddy-sm/ directory
    for pl_id in "${TARGET_PRODUCT_LINES[@]}"; do
        local pl_path
        pl_path="$(get_product_line_path "$pl_id")"
        for arch in "${TARGET_ARCHS[@]}"; do
            local src_pkg_dir="${src_dir}/${pl_path}/${arch}/Packages"
            local dst_pkg_dir="${sm_dir}/${pl_path}/${arch}/Packages"

            if [[ ! -d "$src_pkg_dir" ]]; then
                continue
            fi

            mkdir -p "$dst_pkg_dir"
            # Copy RPM files
            while IFS= read -r -d '' rpm_file; do
                cp "$rpm_file" "$dst_pkg_dir/"
            done < <(find "$src_pkg_dir" -name '*.rpm' -print0 2>/dev/null)
        done
    done

    # Sign all RPMs with SM2
    while IFS= read -r -d '' rpm_file; do
        sign_rpm_sm2 "$rpm_file"
    done < <(find "$sm_dir" -name '*.rpm' -print0 2>/dev/null)

    # Generate repodata for each product line × architecture
    for pl_id in "${TARGET_PRODUCT_LINES[@]}"; do
        local pl_path
        pl_path="$(get_product_line_path "$pl_id")"
        for arch in "${TARGET_ARCHS[@]}"; do
            local repo_dir="${sm_dir}/${pl_path}/${arch}"
            if [[ -d "${repo_dir}/Packages" ]]; then
                generate_repodata "$repo_dir"
            fi
        done
    done

    # Sign all repomd.xml with SM2
    while IFS= read -r -d '' repomd_file; do
        sign_repomd_sm2 "$repomd_file"
    done < <(find "$sm_dir" -path '*/repodata/repomd.xml' -print0 2>/dev/null)

    # Export SM2 public key
    export_sm2_pubkey "${sm_dir}/gpg-sm2.key"

    util_log_info "国密产品线构建完成"
}

# ============================================================================
# 仓库元数据生成模块
# ============================================================================

# ----------------------------------------------------------------------------
# generate_repodata "$repo_dir"
# 对指定目录执行 createrepo_c（或 createrepo）生成仓库元数据
# - 使用 --general-compress-type=xz 确保兼容所有产品线
# - 使用 --update 支持增量更新
# - 验证 repomd.xml 已生成
# 失败以退出码 6 终止
# Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7
# ----------------------------------------------------------------------------
generate_repodata() {
    local repo_dir="$1"

    util_log_info "生成仓库元数据: ${repo_dir}"

    # Prefer createrepo_c, fall back to createrepo
    local createrepo_cmd="createrepo_c"
    if ! command -v createrepo_c >/dev/null 2>&1; then
        createrepo_cmd="createrepo"
    fi

    if ! "$createrepo_cmd" --general-compress-type=xz --update "$repo_dir" >/dev/null 2>&1; then
        util_log_error "仓库元数据生成失败: ${repo_dir}"
        exit "$EXIT_METADATA_FAIL"
    fi

    # Verify repomd.xml was created
    if [[ ! -f "${repo_dir}/repodata/repomd.xml" ]]; then
        util_log_error "repomd.xml 未生成: ${repo_dir}/repodata/repomd.xml"
        exit "$EXIT_METADATA_FAIL"
    fi

    util_log_info "仓库元数据生成完成: ${repo_dir}"
}

# ============================================================================
# 符号链接生成模块
# ============================================================================

# ----------------------------------------------------------------------------
# generate_symlinks
# 遍历 DISTRO_TO_PRODUCT_LINE 映射表，为每个 distro:version 创建相对路径符号链接
# - Fedora 产品线不生成版本符号链接（客户端直接使用 caddy/fedora/{arch}/）
# - 符号链接目标不存在时输出警告到 stderr 并跳过
# - 符号链接使用相对路径，确保仓库目录可整体迁移
# 成功创建的链接递增 SYMLINK_COUNT
# Requirements: 11.1, 11.2, 11.3, 11.4, 11.5
# ----------------------------------------------------------------------------
generate_symlinks() {
    util_log_info "生成发行版友好路径符号链接..."

    local caddy_dir="${STAGING_DIR}/caddy"

    for distro_version in "${!DISTRO_TO_PRODUCT_LINE[@]}"; do
        local pl_id="${DISTRO_TO_PRODUCT_LINE[$distro_version]}"

        # Skip Fedora — clients use caddy/fedora/{arch}/ directly
        if [[ "$pl_id" == "fedora" ]]; then
            continue
        fi

        # Extract distro_id and version from "distro_id:version"
        local distro_id="${distro_version%%:*}"
        local version="${distro_version#*:}"

        # Get the product line directory path
        local pl_path
        pl_path="$(get_product_line_path "$pl_id")"

        # Check if the target directory exists
        if [[ ! -d "${caddy_dir}/${pl_path}" ]]; then
            util_log_error "符号链接目标不存在，跳过: ${caddy_dir}/${pl_path} (${distro_id}:${version})" >&2
            continue
        fi

        # Create the symlink parent directory
        mkdir -p "${caddy_dir}/${distro_id}"

        # Create relative symlink: caddy/{distro_id}/{version} → ../{pl_path}
        ln -sfn "../${pl_path}" "${caddy_dir}/${distro_id}/${version}"

        SYMLINK_COUNT=$((SYMLINK_COUNT + 1))
    done

    util_log_info "符号链接生成完成: ${SYMLINK_COUNT} 个"
}

# ----------------------------------------------------------------------------
# validate_symlinks
# 验证 {STAGING_DIR}/caddy/ 下所有符号链接指向有效目标
# 无效链接输出警告到 stderr
# 返回值: 0 — 全部有效, 1 — 存在无效链接
# Requirements: 11.4, 11.5
# ----------------------------------------------------------------------------
validate_symlinks() {
    util_log_info "验证符号链接..."

    local caddy_dir="${STAGING_DIR}/caddy"
    local invalid_count=0

    # Find all symlinks under caddy/
    while IFS= read -r -d '' symlink; do
        if [[ ! -e "$symlink" ]]; then
            local target
            target="$(readlink "$symlink")"
            util_log_error "无效符号链接: ${symlink} → ${target}" >&2
            invalid_count=$((invalid_count + 1))
        fi
    done < <(find "$caddy_dir" -type l -print0 2>/dev/null)

    if [[ "$invalid_count" -gt 0 ]]; then
        util_log_error "发现 ${invalid_count} 个无效符号链接"
        return 1
    fi

    util_log_info "所有符号链接验证通过"
    return 0
}

# ============================================================================
# .repo 模板生成模块
# ============================================================================

# 发行版 ID → 人类可读名称映射
declare -gA DISTRO_DISPLAY_NAMES=(
    [rhel]="RHEL"
    [centos]="CentOS"
    [almalinux]="AlmaLinux"
    [rocky]="Rocky Linux"
    [anolis]="Anolis OS"
    [ol]="Oracle Linux"
    [opencloudos]="OpenCloudOS"
    [kylin]="Kylin"
    [alinux]="Alibaba Cloud Linux"
    [fedora]="Fedora"
    [amzn]="Amazon Linux"
    [openEuler]="openEuler"
)

# ----------------------------------------------------------------------------
# generate_repo_templates
# 为 DISTRO_TO_PRODUCT_LINE 中每个 distro:version 生成 .repo 配置文件模板
# - 文件命名: caddy-{distro_id}-{distro_version}.repo
# - baseurl 使用发行版友好路径: {base_url}/caddy/{distro_id}/{distro_version}/$basearch/
# - Fedora 特殊处理: baseurl 为 {base_url}/caddy/fedora/$basearch/（不含版本号）
# - 包含 gpgcheck=1、repo_gpgcheck=1、gpgkey
# - 包含 SELinux 安装说明注释
# 模板写入 {STAGING_DIR}/caddy/templates/ 目录
# Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6, 8.4
# ----------------------------------------------------------------------------
generate_repo_templates() {
    util_log_info "生成 .repo 配置文件模板..."

    local templates_dir="${STAGING_DIR}/caddy/templates"
    mkdir -p "$templates_dir"

    local base_url="${OPT_BASE_URL}"
    local count=0

    for distro_version in "${!DISTRO_TO_PRODUCT_LINE[@]}"; do
        local distro_id="${distro_version%%:*}"
        local version="${distro_version#*:}"

        # Human-readable distro name
        local distro_name="${DISTRO_DISPLAY_NAMES[$distro_id]:-$distro_id}"

        # File naming: caddy-{distro_id}-{distro_version}.repo
        local repo_file="${templates_dir}/caddy-${distro_id}-${version}.repo"

        # Fedora special handling: baseurl without version number
        local baseurl
        if [[ "$distro_id" == "fedora" ]]; then
            baseurl="${base_url}/caddy/fedora/\$basearch/"
        else
            baseurl="${base_url}/caddy/${distro_id}/${version}/\$basearch/"
        fi

        cat > "$repo_file" <<EOF
[caddy-selfhosted]
name=Caddy Self-Hosted Repository (${distro_name} ${version} - \$basearch)
baseurl=${baseurl}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=${base_url}/caddy/gpg.key
# 如需 SELinux 支持，请安装 caddy-selinux 子包：
# dnf install caddy-selinux
EOF

        count=$((count + 1))
    done

    util_log_info ".repo 模板生成完成: ${count} 个"
}

# ============================================================================
# 原子发布模块
# ============================================================================

# ----------------------------------------------------------------------------
# atomic_publish
# 将 staging 目录中的构建产物原子交换到正式目录
# 流程:
#   1. 如果正式 caddy/ 目录存在，备份到 {OPT_OUTPUT}/.rollback/{timestamp}/
#   2. mv staging caddy/ → 正式 caddy/
#   3. 如果 mv 失败，保留 staging 目录不删除，退出码 7
#   4. 成功后清理空的 .staging/ 目录
# 需要全局变量: OPT_OUTPUT, STAGING_DIR
# Requirements: 12.1, 12.2, 12.3, 12.5
# ----------------------------------------------------------------------------
atomic_publish() {
    util_log_info "开始原子发布..."

    local production_dir="${OPT_OUTPUT}/caddy"
    local staging_caddy="${STAGING_DIR}/caddy"

    # Verify staging caddy/ exists
    if [[ ! -d "$staging_caddy" ]]; then
        util_log_error "staging 目录不存在: ${staging_caddy}"
        exit "$EXIT_PUBLISH_FAIL"
    fi

    # If production caddy/ exists, backup it
    if [[ -d "$production_dir" ]]; then
        local timestamp
        timestamp="$(date +%Y%m%d-%H%M%S)"
        local rollback_dir="${OPT_OUTPUT}/.rollback/${timestamp}"

        util_log_info "备份当前正式目录到: ${rollback_dir}/caddy"
        mkdir -p "$rollback_dir"
        if ! mv "$production_dir" "${rollback_dir}/caddy"; then
            util_log_error "备份正式目录失败"
            exit "$EXIT_PUBLISH_FAIL"
        fi
    fi

    # Atomic swap: mv staging caddy/ → production caddy/
    util_log_info "原子交换: ${staging_caddy} → ${production_dir}"
    if ! mv "$staging_caddy" "$production_dir"; then
        util_log_error "原子交换失败，staging 目录保留: ${staging_caddy}"
        # 尝试恢复备份（如果刚才做了备份）
        if [[ -n "${rollback_dir:-}" && -d "${rollback_dir}/caddy" ]]; then
            util_log_error "正在恢复备份..."
            mv "${rollback_dir}/caddy" "$production_dir" 2>/dev/null || true
        fi
        exit "$EXIT_PUBLISH_FAIL"
    fi

    # Clean up empty .staging/ directory after successful swap
    rmdir "$STAGING_DIR" 2>/dev/null || true

    # Also publish caddy-sm/ if it exists (SM2/国密 product line)
    local staging_sm="${OPT_OUTPUT}/.staging/caddy-sm"
    local production_sm="${OPT_OUTPUT}/caddy-sm"
    if [[ -d "$staging_sm" ]]; then
        util_log_info "发布国密产品线目录: caddy-sm/"
        if [[ -d "$production_sm" ]]; then
            # 先备份旧目录，再移入新目录，避免 rm -rf 后 mv 失败导致数据丢失
            local sm_backup="${OPT_OUTPUT}/.caddy-sm.bak.$$"
            if ! mv "$production_sm" "$sm_backup"; then
                util_log_error "国密产品线旧目录备份失败"
                exit "$EXIT_PUBLISH_FAIL"
            fi
            if ! mv "$staging_sm" "$production_sm"; then
                util_log_error "国密产品线目录发布失败，正在恢复旧目录..."
                mv "$sm_backup" "$production_sm" 2>/dev/null || true
                exit "$EXIT_PUBLISH_FAIL"
            fi
            # 新目录就位后再删除旧备份
            rm -rf "$sm_backup"
        else
            if ! mv "$staging_sm" "$production_sm"; then
                util_log_error "国密产品线目录发布失败"
                exit "$EXIT_PUBLISH_FAIL"
            fi
        fi
    fi

    util_log_info "原子发布完成"
}

# ----------------------------------------------------------------------------
# rollback_latest
# 恢复最近一次备份到正式目录
# 流程:
#   1. 找到 {OPT_OUTPUT}/.rollback/ 中最新的备份
#   2. 如果当前正式 caddy/ 存在，删除它
#   3. mv 备份的 caddy/ → 正式 caddy/
#   4. 如果没有备份，退出码 7
# 需要全局变量: OPT_OUTPUT
# Requirements: 12.4
# ----------------------------------------------------------------------------
rollback_latest() {
    util_log_info "开始回滚到最近备份..."

    local rollback_base="${OPT_OUTPUT}/.rollback"
    local production_dir="${OPT_OUTPUT}/caddy"

    # Check if rollback directory exists and has backups
    if [[ ! -d "$rollback_base" ]]; then
        util_log_error "没有可用的回滚备份"
        exit "$EXIT_PUBLISH_FAIL"
    fi

    # Find the most recent backup (sorted by name = timestamp)
    local latest_backup=""
    while IFS= read -r dir; do
        latest_backup="$dir"
    done < <(find "$rollback_base" -mindepth 1 -maxdepth 1 -type d | sort)

    if [[ -z "$latest_backup" ]]; then
        util_log_error "没有可用的回滚备份"
        exit "$EXIT_PUBLISH_FAIL"
    fi

    util_log_info "回滚到备份: ${latest_backup}"

    # Remove current production directory if it exists
    if [[ -d "$production_dir" ]]; then
        util_log_info "移除当前正式目录: ${production_dir}"
        local rollback_tmp="${production_dir}.rollback-tmp.$$"
        if ! mv "$production_dir" "$rollback_tmp"; then
            util_log_error "移除当前正式目录失败"
            exit "$EXIT_PUBLISH_FAIL"
        fi
    fi

    # Move the backup caddy/ to production
    if [[ ! -d "${latest_backup}/caddy" ]]; then
        util_log_error "备份目录中不存在 caddy/ 子目录: ${latest_backup}"
        # 恢复刚才移走的正式目录
        if [[ -d "${rollback_tmp:-}" ]]; then
            mv "$rollback_tmp" "$production_dir" 2>/dev/null || true
        fi
        exit "$EXIT_PUBLISH_FAIL"
    fi

    if ! mv "${latest_backup}/caddy" "$production_dir"; then
        util_log_error "回滚 mv 失败"
        # 恢复刚才移走的正式目录
        if [[ -d "${rollback_tmp:-}" ]]; then
            mv "$rollback_tmp" "$production_dir" 2>/dev/null || true
        fi
        exit "$EXIT_PUBLISH_FAIL"
    fi

    # mv 成功后再删除旧的正式目录
    rm -rf "${rollback_tmp:-}" 2>/dev/null || true

    # Clean up the empty backup directory
    rmdir "$latest_backup" 2>/dev/null || true

    util_log_info "回滚完成"
}

# ----------------------------------------------------------------------------
# cleanup_old_backups
# 保留最近 3 个备份，清理更早的备份
# 备份目录名为时间戳格式（YYYYMMDD-HHMMSS），按名称排序即为时间排序
# 需要全局变量: OPT_OUTPUT
# Requirements: 12.6
# ----------------------------------------------------------------------------
cleanup_old_backups() {
    local rollback_base="${OPT_OUTPUT}/.rollback"

    if [[ ! -d "$rollback_base" ]]; then
        return 0
    fi

    # List all backup directories sorted by name (timestamp), oldest first
    local backups=()
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && backups+=("$dir")
    done < <(find "$rollback_base" -mindepth 1 -maxdepth 1 -type d | sort)

    local count=${#backups[@]}
    local keep=3

    if [[ "$count" -le "$keep" ]]; then
        return 0
    fi

    local remove_count=$((count - keep))
    util_log_info "清理旧备份: 保留 ${keep} 个，删除 ${remove_count} 个"

    for ((i = 0; i < remove_count; i++)); do
        util_log_info "删除旧备份: ${backups[$i]}"
        rm -rf "${backups[$i]}"
    done
}

# ============================================================================
# 验证测试模块（verify 阶段）
# ============================================================================

# ----------------------------------------------------------------------------
# verify_rpmlint
# 对生产目录下每个 RPM 包执行 rpmlint 检查
# 任一 RPM 检查失败以退出码 8 终止
# Requirements: 17.1, 17.6
# ----------------------------------------------------------------------------
verify_rpmlint() {
    util_log_info "验证 RPM 包 (rpmlint)..."

    local caddy_dir="${OPT_OUTPUT}/caddy"
    local fail_count=0

    while IFS= read -r -d '' rpm_file; do
        util_log_info "rpmlint: $(basename "$rpm_file")"
        if ! rpmlint "$rpm_file" 2>&1; then
            util_log_error "rpmlint 检查失败: $(basename "$rpm_file")"
            fail_count=$((fail_count + 1))
        fi
    done < <(find "$caddy_dir" -name '*.rpm' -print0 2>/dev/null)

    if [[ "$fail_count" -gt 0 ]]; then
        util_log_error "rpmlint 检查失败: ${fail_count} 个 RPM 包未通过"
        exit "$EXIT_VERIFY_FAIL"
    fi

    util_log_info "rpmlint 检查全部通过"
}

# ----------------------------------------------------------------------------
# verify_repodata
# 验证生产目录下所有 repodata/repomd.xml 存在且格式正确（包含 <repomd 标签）
# 任一验证失败以退出码 8 终止
# Requirements: 17.2, 17.6
# ----------------------------------------------------------------------------
verify_repodata() {
    util_log_info "验证仓库元数据 (repomd.xml)..."

    local caddy_dir="${OPT_OUTPUT}/caddy"
    local fail_count=0
    local found_count=0

    while IFS= read -r -d '' repomd_file; do
        found_count=$((found_count + 1))
        util_log_info "验证: ${repomd_file}"

        if [[ ! -f "$repomd_file" ]]; then
            util_log_error "repomd.xml 不存在: ${repomd_file}"
            fail_count=$((fail_count + 1))
            continue
        fi

        if ! grep -q '<repomd' "$repomd_file" 2>/dev/null; then
            util_log_error "repomd.xml 格式错误（缺少 <repomd 标签）: ${repomd_file}"
            fail_count=$((fail_count + 1))
        fi
    done < <(find "$caddy_dir" -path '*/repodata/repomd.xml' -print0 2>/dev/null)

    if [[ "$found_count" -eq 0 ]]; then
        util_log_error "未找到任何 repomd.xml 文件"
        exit "$EXIT_VERIFY_FAIL"
    fi

    if [[ "$fail_count" -gt 0 ]]; then
        util_log_error "repomd.xml 验证失败: ${fail_count} 个文件未通过"
        exit "$EXIT_VERIFY_FAIL"
    fi

    util_log_info "repomd.xml 验证全部通过 (${found_count} 个)"
}

# ----------------------------------------------------------------------------
# verify_signatures
# 验证生产目录下所有 RPM 签名（rpm -K）和 repomd.xml.asc（gpg --verify）
# 任一验证失败以退出码 8 终止
# Requirements: 17.3, 17.4, 17.6
# ----------------------------------------------------------------------------
verify_signatures() {
    util_log_info "验证签名..."

    local caddy_dir="${OPT_OUTPUT}/caddy"
    local fail_count=0

    # Verify RPM signatures
    while IFS= read -r -d '' rpm_file; do
        util_log_info "验证 RPM 签名: $(basename "$rpm_file")"
        if ! rpm -K "$rpm_file" >/dev/null 2>&1; then
            util_log_error "RPM 签名验证失败: $(basename "$rpm_file")"
            fail_count=$((fail_count + 1))
        fi
    done < <(find "$caddy_dir" -name '*.rpm' -print0 2>/dev/null)

    # Verify repomd.xml.asc signatures
    while IFS= read -r -d '' asc_file; do
        local repomd_file="${asc_file%.asc}"
        util_log_info "验证 repomd.xml 签名: ${asc_file}"
        if ! gpg --verify "$asc_file" "$repomd_file" >/dev/null 2>&1; then
            util_log_error "repomd.xml 签名验证失败: ${asc_file}"
            fail_count=$((fail_count + 1))
        fi
    done < <(find "$caddy_dir" -name 'repomd.xml.asc' -print0 2>/dev/null)

    if [[ "$fail_count" -gt 0 ]]; then
        util_log_error "签名验证失败: ${fail_count} 个文件未通过"
        exit "$EXIT_VERIFY_FAIL"
    fi

    util_log_info "签名验证全部通过"
}

# ----------------------------------------------------------------------------
# verify_symlinks
# 验证所有符号链接有效，复用 validate_symlinks 函数
# 验证失败以退出码 8 终止
# Requirements: 17.5, 17.6
# ----------------------------------------------------------------------------
verify_symlinks() {
    util_log_info "验证符号链接..."

    # Reuse validate_symlinks, but operate on production directory
    local saved_staging_dir="${STAGING_DIR}"
    STAGING_DIR="${OPT_OUTPUT}"

    if ! validate_symlinks; then
        STAGING_DIR="${saved_staging_dir}"
        util_log_error "符号链接验证失败"
        exit "$EXIT_VERIFY_FAIL"
    fi

    STAGING_DIR="${saved_staging_dir}"
    util_log_info "符号链接验证通过"
}

# ============================================================================
# CI/CD 阶段控制模块
# ============================================================================

# ----------------------------------------------------------------------------
# stage_build
# Build 阶段：解析产品线、查询版本、下载二进制、构建 RPM、生成元数据、
#              生成符号链接、生成 .repo 模板、导出 GPG 公钥
# Requirements: 16.1, 16.2
# ----------------------------------------------------------------------------
stage_build() {
    resolve_product_lines "$OPT_DISTRO"

    # Determine target architectures
    if [[ "$OPT_ARCH" == "all" ]]; then
        TARGET_ARCHS=(x86_64 aarch64)
    else
        TARGET_ARCHS=("$OPT_ARCH")
    fi

    # Set up staging directory
    STAGING_DIR="${OPT_OUTPUT}/.staging"
    mkdir -p "$STAGING_DIR"

    resolve_version

    # Download binaries for each architecture
    for arch in "${TARGET_ARCHS[@]}"; do
        download_caddy_binary "$arch"
    done

    # Build RPMs for each product line × architecture
    for pl_id in "${TARGET_PRODUCT_LINES[@]}"; do
        for arch in "${TARGET_ARCHS[@]}"; do
            build_rpm "$pl_id" "$arch"
        done
    done

    # Optionally build SELinux subpackage RPMs (if policy file exists)
    if [[ -f "${SCRIPT_DIR}/${SELINUX_POLICY_FILE}" ]]; then
        util_log_info "检测到 SELinux 策略文件，构建 caddy-selinux 子包..."
        for pl_id in "${TARGET_PRODUCT_LINES[@]}"; do
            for arch in "${TARGET_ARCHS[@]}"; do
                build_selinux_rpm "$pl_id" "$arch"
            done
        done
    fi

    # Generate repodata for each product line × architecture
    for pl_id in "${TARGET_PRODUCT_LINES[@]}"; do
        local pl_path
        pl_path="$(get_product_line_path "$pl_id")"
        for arch in "${TARGET_ARCHS[@]}"; do
            generate_repodata "${STAGING_DIR}/caddy/${pl_path}/${arch}"
        done
    done

    # Generate symlinks
    generate_symlinks

    # Generate .repo templates
    generate_repo_templates

    # Export GPG public key
    if [[ -n "${OPT_GPG_KEY_ID:-}" ]]; then
        export_gpg_pubkey "${STAGING_DIR}/caddy/gpg.key"
    fi

    # Build SM2 (国密) product line if --sm2-key is set
    if [[ -n "${OPT_SM2_KEY:-}" ]]; then
        stage_build_sm2
    fi
}

# ----------------------------------------------------------------------------
# stage_sign
# Sign 阶段：签名所有 RPM 包、签名所有 repomd.xml 文件
# Requirements: 16.1, 16.2
# ----------------------------------------------------------------------------
stage_sign() {
    local caddy_dir="${STAGING_DIR:-${OPT_OUTPUT}/.staging}/caddy"

    # Sign all RPMs
    while IFS= read -r -d '' rpm_file; do
        sign_rpm "$rpm_file"
    done < <(find "$caddy_dir" -name '*.rpm' -print0 2>/dev/null)

    # Sign all repomd.xml files
    while IFS= read -r -d '' repomd_file; do
        sign_repomd "$repomd_file"
    done < <(find "$caddy_dir" -path '*/repodata/repomd.xml' -print0 2>/dev/null)
}

# ----------------------------------------------------------------------------
# stage_publish
# Publish 阶段：原子发布、清理旧备份
# Requirements: 16.1, 16.2
# ----------------------------------------------------------------------------
stage_publish() {
    STAGING_DIR="${STAGING_DIR:-${OPT_OUTPUT}/.staging}"
    atomic_publish
    cleanup_old_backups
}

# ----------------------------------------------------------------------------
# stage_verify
# Verify 阶段：rpmlint 检查、repodata 验证、签名验证、符号链接验证
# Requirements: 16.1, 16.2
# ----------------------------------------------------------------------------
stage_verify() {
    verify_rpmlint
    verify_repodata
    verify_signatures
    verify_symlinks
}

# ----------------------------------------------------------------------------
# run_stage "$stage_name"
# 执行指定阶段：
#   1. 输出 [STAGE] {stage_name}: starting 到 stderr
#   2. 调用对应阶段函数
#   3. 输出 [STAGE] {stage_name}: completed 到 stderr
# 阶段函数失败时自动传播退出码（set -e）
# Requirements: 16.3, 16.4
# ----------------------------------------------------------------------------
run_stage() {
    local stage_name="$1"

    printf '[STAGE] %s: starting\n' "$stage_name" >&2

    case "$stage_name" in
        build)   stage_build   ;;
        sign)    stage_sign    ;;
        publish) stage_publish ;;
        verify)  stage_verify  ;;
        *)
            util_log_error "未知阶段: ${stage_name}"
            exit "$EXIT_ARG_ERROR"
            ;;
    esac

    printf '[STAGE] %s: completed\n' "$stage_name" >&2
}

# ----------------------------------------------------------------------------
# run_all_stages
# 按顺序执行所有阶段：build → sign → publish → verify
# 任一阶段失败停止后续阶段执行（set -e 自动处理）
# Requirements: 16.2
# ----------------------------------------------------------------------------
run_all_stages() {
    run_stage "build"
    run_stage "sign"
    run_stage "publish"
    run_stage "verify"
}

# ----------------------------------------------------------------------------
# cleanup
# 清理临时目录中间文件（nfpm 配置等）
# 由 trap EXIT 调用，确保正常退出和异常退出时都清理
# Requirements: 15.3
# ----------------------------------------------------------------------------
cleanup() {
    # Clean up nfpm config temp files
    if [[ -n "${STAGING_DIR:-}" && -d "${STAGING_DIR}/nfpm-configs" ]]; then
        rm -rf "${STAGING_DIR}/nfpm-configs"
    fi
}

# ----------------------------------------------------------------------------
# main "$@"
# 脚本主入口：解析参数、检查依赖、根据 OPT_STAGE 执行对应阶段或全部阶段
# 构建完成后输出构建摘要到 stderr，stdout 仅输出最终仓库根目录绝对路径
# Requirements: 15.3, 16.1, 16.2, 16.3, 16.4, 18.1, 18.3, 18.4, 18.5
# ----------------------------------------------------------------------------
main() {
    BUILD_START_TIME="$(date +%s)"

    parse_args "$@"

    # Handle rollback
    if [[ "$OPT_ROLLBACK" == true ]]; then
        rollback_latest
        return 0
    fi

    check_dependencies
    if [[ -n "${OPT_GPG_KEY_ID:-}" ]]; then
        check_gpg_key "$OPT_GPG_KEY_ID"
    fi

    # 获取构建锁，防止并发构建竞争 staging 目录
    local lock_file="${OPT_OUTPUT}/.build.lock"
    mkdir -p "$OPT_OUTPUT"
    exec 9>"$lock_file"
    if ! flock -n 9; then
        util_log_error "另一个构建进程正在运行（锁文件: ${lock_file}），请稍后重试"
        exit "$EXIT_PUBLISH_FAIL"
    fi

    # Execute stage(s)
    if [[ -n "$OPT_STAGE" ]]; then
        run_stage "$OPT_STAGE"
    else
        run_all_stages
    fi

    # Build summary to stderr
    local build_end_time
    build_end_time="$(date +%s)"
    local elapsed=$((build_end_time - BUILD_START_TIME))
    util_log_info "=== 构建摘要 ==="
    util_log_info "产品线: ${#TARGET_PRODUCT_LINES[@]} 条"
    util_log_info "RPM 包: ${RPM_COUNT} 个"
    util_log_info "符号链接: ${SYMLINK_COUNT} 个"
    util_log_info "总耗时: ${elapsed} 秒"

    # Output final repo path to stdout (only thing on stdout)
    local repo_abs_path
    repo_abs_path="$(cd "$OPT_OUTPUT" && pwd)"
    printf '%s\n' "$repo_abs_path"
}

# ============================================================================
# 信号处理（测试模式下跳过，避免 source 时触发 trap）
# ============================================================================
if [[ "${_SOURCED_FOR_TEST:-}" != true ]]; then
    trap cleanup EXIT
    trap 'util_log_error "收到中断信号，正在清理..."; exit 130' INT TERM
fi

# ============================================================================
# 脚本入口：仅在非测试模式下执行 main
# ============================================================================
if [[ "${_SOURCED_FOR_TEST:-}" != true ]]; then
    main "$@"
fi
