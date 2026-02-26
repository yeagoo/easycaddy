#!/usr/bin/env bash
set -euo pipefail

# Builder 容器入口脚本
# 将环境变量转换为 build-repo.sh --stage build 的 CLI 参数
# 未设置的环境变量不生成对应参数

# 构建 build-repo.sh 命令行参数
build_args() {
    local args=(--stage build --output /repo)

    [[ -n "${CADDY_VERSION:-}" ]] && args+=(--version "$CADDY_VERSION")
    [[ -n "${TARGET_ARCH:-}" ]]   && args+=(--arch "$TARGET_ARCH")
    [[ -n "${TARGET_DISTRO:-}" ]] && args+=(--distro "$TARGET_DISTRO")
    [[ -n "${BASE_URL:-}" ]]      && args+=(--base-url "$BASE_URL")

    printf '%s\n' "${args[@]}"
}

# 支持测试时 source 单独函数
if [[ "${_SOURCED_FOR_TEST:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi

# 构建参数并执行
mapfile -t ARGS < <(build_args)
exec bash /app/build-repo.sh "${ARGS[@]}"
