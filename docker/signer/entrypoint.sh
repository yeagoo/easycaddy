#!/usr/bin/env bash
set -euo pipefail

# Signer 容器入口脚本
# 检查 GPG 密钥文件权限 → 导入密钥 → 签名 → 发布 → 清除密钥材料

# 检查 GPG 密钥文件权限
# 返回 0 表示权限正确，返回 1 表示权限不安全
check_gpg_permissions() {
    local gpg_dir="${1:-/gpg-keys}"
    local found_keys=false

    for key_file in "$gpg_dir"/*.gpg; do
        [[ -f "$key_file" ]] || continue
        found_keys=true
        local perms
        perms=$(stat -c '%a' "$key_file" 2>/dev/null || stat -f '%Lp' "$key_file" 2>/dev/null)
        if [[ "$perms" != "600" && "$perms" != "400" ]]; then
            echo "[ERROR] GPG 密钥文件权限不安全: $key_file (当前: $perms，要求: 600 或 400)" >&2
            return 1
        fi
    done

    if [[ "$found_keys" == false ]]; then
        echo "[ERROR] 未找到 GPG 密钥文件: $gpg_dir/*.gpg" >&2
        return 1
    fi

    return 0
}

# 清除 GPG 密钥材料
cleanup_gpg() {
    gpgconf --kill gpg-agent 2>/dev/null || true
    rm -rf ~/.gnupg 2>/dev/null || true
}

# 支持测试时 source 单独函数
if [[ "${_SOURCED_FOR_TEST:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi

# 确保退出时清除密钥材料
trap cleanup_gpg EXIT

# 检查 GPG 密钥文件权限
check_gpg_permissions || exit 1

# 导入 GPG 密钥
gpg --import /gpg-keys/*.gpg

# 构建签名阶段参数
SIGN_ARGS=(--stage sign --output /repo)
[[ -n "${GPG_KEY_ID:-}" ]] && SIGN_ARGS+=(--gpg-key-id "$GPG_KEY_ID")

# 构建发布阶段参数
PUBLISH_ARGS=(--stage publish --output /repo)

# 执行签名
bash /app/build-repo.sh "${SIGN_ARGS[@]}"

# 执行发布
exec bash /app/build-repo.sh "${PUBLISH_ARGS[@]}"
