#!/usr/bin/env bash
# ============================================================================
# vendor-download.sh — 预下载 Caddy 二进制文件到 vendor/ 目录
# 用于在有网络的环境中预下载，支持离线构建
# ============================================================================
set -euo pipefail

# === 环境变量：确保离线构建兼容 ===
export GOPROXY=off
export CGO_ENABLED=0

# === 架构列表 ===
GO_ARCHS=(amd64 arm64)

# ============================================================================
# 日志函数
# ============================================================================

log_info() {
    printf '[INFO] %s\n' "$1" >&2
}

log_error() {
    printf '[ERROR] %s\n' "$1" >&2
}

# ============================================================================
# 用法说明
# ============================================================================

show_help() {
    cat >&2 <<'EOF'
用法: vendor-download.sh --version <VERSION>

预下载 Caddy 二进制文件到 vendor/ 目录，用于离线构建。

选项:
  --version <VERSION>  Caddy 版本号（如 2.9.0，必需）
  -h, --help           显示此帮助信息

示例:
  bash vendor-download.sh --version 2.9.0
EOF
    exit 0
}

# ============================================================================
# 参数解析
# ============================================================================

VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            if [[ $# -lt 2 ]]; then
                log_error "参数 --version 需要一个值"
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "未知参数: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    log_error "必须指定 --version 参数"
    exit 1
fi

# 去除可能的 v 前缀
VERSION="${VERSION#v}"

# ============================================================================
# 下载
# ============================================================================

mkdir -p vendor

for go_arch in "${GO_ARCHS[@]}"; do
    dest="vendor/caddy-${VERSION}-linux-${go_arch}"

    if [[ -f "$dest" ]]; then
        log_info "已存在，跳过: ${dest}"
        continue
    fi

    url="https://caddyserver.com/api/download?os=linux&arch=${go_arch}&version=${VERSION}"
    log_info "下载 Caddy ${VERSION} (linux/${go_arch})..."

    http_code="$(curl -fSL -o "$dest" -w '%{http_code}' "$url" 2>/dev/null)" || {
        log_error "下载失败 (${go_arch}): curl 退出码 $?, HTTP 状态码 ${http_code:-unknown}"
        rm -f "$dest"
        exit 1
    }

    if [[ ! -s "$dest" ]]; then
        log_error "下载文件大小为 0: ${dest}"
        rm -f "$dest"
        exit 1
    fi

    chmod +x "$dest"
    log_info "下载完成: ${dest}"
done

log_info "所有二进制文件已下载到 vendor/ 目录"
