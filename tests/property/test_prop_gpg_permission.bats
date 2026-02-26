#!/usr/bin/env bats
# ============================================================================
# test_prop_gpg_permission.bats — Property 6: GPG 密钥文件权限校验
# Feature: docker-repo-system, Property 6: GPG 密钥文件权限校验
#
# For any 文件权限值，当权限不是 600 或 400 时，signer 容器的 entrypoint 脚本
# 应拒绝启动并输出权限错误提示；当权限是 600 或 400 时，应正常继续执行。
#
# Test approach:
# 1. Source the signer entrypoint with _SOURCED_FOR_TEST=true
# 2. For 100 iterations, generate a random file permission
# 3. Create a temp directory with a .gpg file set to that permission
# 4. Call check_gpg_permissions and verify:
#    - Permission 600 or 400: return code 0
#    - Any other permission: return code 1 and stderr contains error message
#
# **Validates: Requirements 8.7**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/generators_docker.bash"
    source "$PROJECT_ROOT/tests/test_helper/mock_helpers.bash"
    setup_test_env
    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/signer/entrypoint.sh"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 6: GPG 密钥文件权限校验 (100 iterations)
# ============================================================================

@test "Property 6: GPG 密钥文件权限校验 — 随机权限正确判断安全性" {
    for i in $(seq 1 100); do
        local perm
        perm="$(gen_file_permission)"

        # Create temp gpg key dir with a test file
        local gpg_dir="${TEST_TEMP_DIR}/gpg-keys-${i}"
        mkdir -p "$gpg_dir"
        touch "$gpg_dir/test.gpg"
        chmod "$perm" "$gpg_dir/test.gpg"

        local exit_code=0
        local stderr_output
        stderr_output="$(check_gpg_permissions "$gpg_dir" 2>&1 >/dev/null)" || exit_code=$?

        if [[ "$perm" == "600" || "$perm" == "400" ]]; then
            [[ "$exit_code" -eq 0 ]] || \
                fail "Iteration ${i}: Permission ${perm} should be accepted but got exit code ${exit_code}"
        else
            [[ "$exit_code" -ne 0 ]] || \
                fail "Iteration ${i}: Permission ${perm} should be rejected but got exit code 0"
            [[ "$stderr_output" == *"权限不安全"* ]] || \
                fail "Iteration ${i}: Expected error message about unsafe permissions for ${perm}"
        fi
    done
}
