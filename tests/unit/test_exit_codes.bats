#!/usr/bin/env bats
# ============================================================================
# test_exit_codes.bats — 退出码行为单元测试
# 测试 util_check_root 的退出码行为
# 验证需求: 13.5
# ============================================================================

# 加载 bats 辅助库
load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'

setup() {
    setup_test_env
    source_install_script
    PROJECT_ROOT="$(get_project_root)"
}

teardown() {
    teardown_test_env
}

# Helper: create a restricted PATH that includes basic system commands
# but excludes sudo. We copy needed binaries into a clean dir.
create_no_sudo_path() {
    local safe_bin="${TEST_TEMP_DIR}/safe_bin"
    mkdir -p "$safe_bin"
    # Link essential commands that util_check_root needs (id is already mocked)
    # We need bash, env, printf etc. but those are builtins or in /usr/bin
    # Strategy: create a PATH with MOCK_BIN_DIR (has mocked id) + safe_bin
    # Copy/link everything from /usr/bin EXCEPT sudo
    # That's too heavy. Instead, create a minimal set.
    # Actually, util_check_root only needs: id (mocked), command (builtin), printf (builtin)
    # The issue is bats' `run` needs bash and env.
    # So we symlink bash and env into safe_bin
    ln -sf /usr/bin/bash "$safe_bin/bash"
    ln -sf /usr/bin/env "$safe_bin/env"
    # Also need basic coreutils for bats internals
    for cmd in cat printf mkdir rm mktemp dirname basename readlink wc tr head tail sed grep; do
        local real_path
        real_path="$(command -v "$cmd" 2>/dev/null || true)"
        if [[ -n "$real_path" ]]; then
            ln -sf "$real_path" "$safe_bin/$cmd"
        fi
    done
    echo "${MOCK_BIN_DIR}:${safe_bin}"
}

# ============================================================================
# util_check_root 测试
# ============================================================================

@test "util_check_root: returns 0 when running as root (uid=0)" {
    mock_id_uid 0
    run util_check_root
    assert_success
}

@test "util_check_root: returns 0 when non-root but sudo available" {
    mock_id_uid 1000
    mock_sudo_available
    run util_check_root
    assert_success
}

@test "util_check_root: logs info message when using sudo" {
    mock_id_uid 1000
    mock_sudo_available
    run util_check_root
    assert_success
    # Should mention sudo usage in stderr output (bats captures both stdout+stderr in $output)
    assert_output --partial "sudo"
}

@test "util_check_root: exits with code 4 when non-root and no sudo" {
    mock_id_uid 1000
    # Use a helper script to run util_check_root with a restricted PATH
    # that has no sudo available
    local helper_script="${TEST_TEMP_DIR}/check_root_test.sh"
    cat > "$helper_script" << SCRIPT_EOF
#!/usr/bin/env bash
set -euo pipefail
_SOURCED_FOR_TEST=true
source "${PROJECT_ROOT}/install-caddy.sh"
# Override id to return non-root
id() { echo "1000"; }
# Ensure command -v sudo fails
sudo() { :; }
unset -f sudo 2>/dev/null || true
# Remove sudo from hash table
hash -d sudo 2>/dev/null || true
util_check_root
SCRIPT_EOF
    chmod +x "$helper_script"

    # Run with a PATH that excludes sudo
    local no_sudo_path
    no_sudo_path="$(create_no_sudo_path)"
    run env PATH="$no_sudo_path" bash "$helper_script"
    assert_failure
    assert_equal "$status" 4
}

@test "util_check_root: outputs error message when permissions insufficient" {
    mock_id_uid 1000
    local helper_script="${TEST_TEMP_DIR}/check_root_test.sh"
    cat > "$helper_script" << SCRIPT_EOF
#!/usr/bin/env bash
set -euo pipefail
_SOURCED_FOR_TEST=true
source "${PROJECT_ROOT}/install-caddy.sh"
id() { echo "1000"; }
util_check_root
SCRIPT_EOF
    chmod +x "$helper_script"

    local no_sudo_path
    no_sudo_path="$(create_no_sudo_path)"
    run env PATH="$no_sudo_path" bash "$helper_script"
    assert_failure
    assert_output --partial "root"
}
