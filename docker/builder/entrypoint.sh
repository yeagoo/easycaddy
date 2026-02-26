#!/usr/bin/env bash
set -euo pipefail

# Builder 容器入口脚本
# 将环境变量转换为 build-repo.sh --stage build 的 CLI 参数
# 未设置的环境变量不生成对应参数

# 清理环境变量值：去除行内注释和首尾空白
# Docker Compose .env 文件不支持行内注释，但用户可能误加
strip_env() {
    local val="$1"
    # 去除 # 及其后面的内容（行内注释）
    val="${val%%#*}"
    # 去除首尾空白
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$val"
}

# 构建 build-repo.sh 命令行参数
build_args() {
    local args=(--stage build --output /repo)

    local ver; ver="$(strip_env "${CADDY_VERSION:-}")"
    local arch; arch="$(strip_env "${TARGET_ARCH:-}")"
    local distro; distro="$(strip_env "${TARGET_DISTRO:-}")"
    local base; base="$(strip_env "${BASE_URL:-}")"

    [[ -n "$ver" ]]    && args+=(--version "$ver")
    [[ -n "$arch" ]]   && args+=(--arch "$arch")
    [[ -n "$distro" ]] && args+=(--distro "$distro")
    [[ -n "$base" ]]   && args+=(--base-url "$base")

    printf '%s\n' "${args[@]}"
}

# 支持测试时 source 单独函数
if [[ "${_SOURCED_FOR_TEST:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi

# 构建参数并执行
mapfile -t ARGS < <(build_args)
exec bash /app/build-repo.sh "${ARGS[@]}"
