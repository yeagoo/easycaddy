#!/usr/bin/env bats
# ============================================================================
# test_dependency_check.bats — 依赖检查单元测试
# 测试各工具存在/缺失组合、GPG 密钥存在/不存在
# 验证需求: 3.1, 3.2, 3.3, 3.4
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'
load '../test_helper/generators_repo'

# Source build-repo.sh for testing (without executing main)
source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

setup() {
    setup_test_env
    source_build_repo_script
}

teardown() {
    teardown_test_env
}

# Required tools that check_dependencies checks for
REQUIRED_TOOLS=(curl nfpm createrepo_c gpg rpm)

# Create mock commands for all required tools in MOCK_BIN_DIR
create_all_tool_mocks() {
    for tool in "${REQUIRED_TOOLS[@]}"; do
        create_mock_command "$tool" 0
    done
}

# Remove a specific mock command from MOCK_BIN_DIR
remove_tool_mock() {
    local tool="$1"
    rm -f "${MOCK_BIN_DIR}/${tool}"
}

# Run check_dependencies with PATH restricted to only MOCK_BIN_DIR
run_check_deps_isolated() {
    PATH="${MOCK_BIN_DIR}" run check_dependencies
}

# ============================================================================
# 1. All tools present → success (Req 3.1)
# ============================================================================

@test "check_dependencies: all tools present → success" {
    create_all_tool_mocks
    run_check_deps_isolated
    assert_success
}

# ============================================================================
# 2. curl missing → exit 2, reports curl (Req 3.1, 3.2)
# ============================================================================

@test "check_dependencies: curl missing → exit 2 and reports curl" {
    create_all_tool_mocks
    remove_tool_mock "curl"
    run_check_deps_isolated
    assert_failure 2
    assert_output --partial "curl"
}

# ============================================================================
# 3. nfpm missing → exit 2, reports nfpm (Req 3.1, 3.2)
# ============================================================================

@test "check_dependencies: nfpm missing → exit 2 and reports nfpm" {
    create_all_tool_mocks
    remove_tool_mock "nfpm"
    run_check_deps_isolated
    assert_failure 2
    assert_output --partial "nfpm"
}

# ============================================================================
# 4. createrepo_c missing but createrepo present → success (Req 3.1)
# ============================================================================

@test "check_dependencies: createrepo_c missing but createrepo present → success" {
    create_all_tool_mocks
    remove_tool_mock "createrepo_c"
    create_mock_command "createrepo" 0
    run_check_deps_isolated
    assert_success
}

# ============================================================================
# 5. Both createrepo_c and createrepo missing → exit 2, reports createrepo_c (Req 3.1, 3.2)
# ============================================================================

@test "check_dependencies: both createrepo_c and createrepo missing → exit 2 and reports createrepo_c" {
    create_all_tool_mocks
    remove_tool_mock "createrepo_c"
    # Ensure no createrepo fallback exists
    remove_tool_mock "createrepo"
    run_check_deps_isolated
    assert_failure 2
    assert_output --partial "createrepo_c"
}

# ============================================================================
# 6. gpg missing → exit 2, reports gpg (Req 3.1, 3.2)
# ============================================================================

@test "check_dependencies: gpg missing → exit 2 and reports gpg" {
    create_all_tool_mocks
    remove_tool_mock "gpg"
    run_check_deps_isolated
    assert_failure 2
    assert_output --partial "gpg"
}

# ============================================================================
# 7. rpm missing → exit 2, reports rpm (Req 3.1, 3.2)
# ============================================================================

@test "check_dependencies: rpm missing → exit 2 and reports rpm" {
    create_all_tool_mocks
    remove_tool_mock "rpm"
    run_check_deps_isolated
    assert_failure 2
    assert_output --partial "rpm"
}

# ============================================================================
# 8. Multiple tools missing → exit 2, reports all missing tools (Req 3.2)
# ============================================================================

@test "check_dependencies: multiple tools missing → exit 2 and reports all" {
    create_all_tool_mocks
    remove_tool_mock "curl"
    remove_tool_mock "nfpm"
    remove_tool_mock "gpg"
    run_check_deps_isolated
    assert_failure 2
    assert_output --partial "curl"
    assert_output --partial "nfpm"
    assert_output --partial "gpg"
}

@test "check_dependencies: all tools missing → exit 2 and reports all" {
    # Don't create any mocks — MOCK_BIN_DIR is empty
    PATH="${MOCK_BIN_DIR}" run check_dependencies
    assert_failure 2
    assert_output --partial "curl"
    assert_output --partial "nfpm"
    assert_output --partial "createrepo_c"
    assert_output --partial "gpg"
    assert_output --partial "rpm"
}

# ============================================================================
# 9. check_gpg_key with existing key → success (Req 3.3)
# ============================================================================

@test "check_gpg_key: existing key → success" {
    # Create a mock gpg that succeeds for --list-keys
    local mock_script="${MOCK_BIN_DIR}/gpg"
    cat > "$mock_script" << 'MOCK_EOF'
#!/bin/bash
# Mock gpg: succeed for --list-keys with any key_id
exit 0
MOCK_EOF
    chmod +x "$mock_script"

    # Use MOCK_BIN_DIR prepended to PATH (setup already does this)
    run check_gpg_key "ABCDEF1234567890"
    assert_success
}

# ============================================================================
# 10. check_gpg_key with non-existing key → exit 2 (Req 3.3, 3.4)
# ============================================================================

@test "check_gpg_key: non-existing key → exit 2" {
    # Create a mock gpg that fails for --list-keys (key not found)
    local mock_script="${MOCK_BIN_DIR}/gpg"
    cat > "$mock_script" << 'MOCK_EOF'
#!/bin/bash
# Mock gpg: fail for --list-keys (key not found)
if [[ "$1" == "--list-keys" ]]; then
    echo "gpg: error reading key: No public key" >&2
    exit 2
fi
exit 0
MOCK_EOF
    chmod +x "$mock_script"

    run check_gpg_key "NONEXISTENT_KEY"
    assert_failure 2
    assert_output --partial "不存在于本地密钥环"
}
