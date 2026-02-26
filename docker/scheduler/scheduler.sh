#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# scheduler.sh — 定时版本检查与自动构建
# 按可配置周期检查 Caddy 新版本，发现新版本时自动触发构建
# ============================================================================

# 解析 CHECK_INTERVAL 环境变量为秒数
# 支持格式：Nd（天）、Nh（小时）、纯数字（秒）
parse_interval() {
    local interval="$1"
    case "$interval" in
        *d) echo $(( ${interval%d} * 86400 )) ;;
        *h) echo $(( ${interval%h} * 3600 )) ;;
        *)  echo "$interval" ;;
    esac
}

# 查询 GitHub 最新稳定版本
get_latest_version() {
    local api_url="https://api.github.com/repos/caddyserver/caddy/releases/latest"
    local curl_args=(-fsSL)
    [[ -n "${GITHUB_TOKEN:-}" ]] && curl_args+=(-H "Authorization: token ${GITHUB_TOKEN}")
    curl "${curl_args[@]}" "$api_url" | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/'
}

# 读取当前已构建版本
get_current_version() {
    local version_file="${VERSION_FILE:-/repo/caddy/.current-version}"
    [[ -f "$version_file" ]] && cat "$version_file" || echo ""
}

# 触发完整构建流程（builder → signer）
trigger_build() {
    local version="$1"
    docker compose run --rm -e CADDY_VERSION="$version" builder
    docker compose run --rm -e CADDY_VERSION="$version" signer
}

# 支持测试时 source 单独函数
if [[ "${_SOURCED_FOR_TEST:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi

# === 主循环 ===
INTERVAL_SECONDS=$(parse_interval "${CHECK_INTERVAL:-10d}")
FIRST_RUN=true

while true; do
    if [[ "$FIRST_RUN" != true ]]; then
        sleep "$INTERVAL_SECONDS"
    fi
    FIRST_RUN=false

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    LATEST=$(get_latest_version 2>/dev/null) || {
        echo "[ERROR] [$TIMESTAMP] GitHub API 查询失败，等待下一个检查周期" >&2
        continue
    }
    CURRENT=$(get_current_version)

    echo "[INFO] [$TIMESTAMP] 检查版本: 最新=$LATEST, 当前=${CURRENT:-无}" >&2

    if [[ "$LATEST" == "$CURRENT" ]]; then
        echo "[INFO] [$TIMESTAMP] 当前版本已是最新 ($LATEST)，跳过构建" >&2
        continue
    fi

    echo "[INFO] [$TIMESTAMP] 发现新版本 $LATEST，触发构建..." >&2
    if trigger_build "$LATEST"; then
        echo "$LATEST" > "${VERSION_FILE:-/repo/caddy/.current-version}"
        echo "[INFO] [$TIMESTAMP] 构建完成，版本更新为 $LATEST" >&2
    else
        echo "[ERROR] [$TIMESTAMP] 构建失败" >&2
    fi
done
