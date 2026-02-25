#!/usr/bin/env bats
# ============================================================================
# test_check_installed.bats — 已安装检测单元测试
# 测试 check_installed 和 check_version_match 函数
# 场景: caddy 存在/不存在、版本匹配/不匹配
# 验证需求: 2.1, 2.2, 2.3, 2.4
# ============================================================================

# 加载 bats 辅助库
load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# check_installed: caddy 存在时返回 0（需求 2.1）
# ============================================================================

@test "check_installed: returns 0 when caddy exists in PATH" {
    mock_caddy_installed "v2.7.6"
    run check_installed
    assert_success
}

# ============================================================================
# check_installed: caddy 不存在时返回 1（需求 2.1）
# ============================================================================

@test "check_installed: returns 1 when caddy not in PATH" {
    mock_caddy_not_installed
    # Restrict PATH to only mock bin dir (which has no caddy) plus essential dirs
    # This ensures the real system caddy is not found
    local saved_path="$PATH"
    export PATH="${MOCK_BIN_DIR}:/usr/lib/bats-core"
    run check_installed
    export PATH="$saved_path"
    assert_failure
}

# ============================================================================
# check_installed: 找到 caddy 时设置 CADDY_BIN（需求 2.2）
# ============================================================================

@test "check_installed: sets CADDY_BIN when caddy found" {
    mock_caddy_installed "v2.7.6"
    check_installed
    [[ -n "$CADDY_BIN" ]]
    [[ "$CADDY_BIN" == *caddy* ]]
}

@test "check_installed: CADDY_BIN points to mock caddy path" {
    mock_caddy_installed "v2.7.6"
    check_installed
    [[ "$CADDY_BIN" == "${MOCK_BIN_DIR}/caddy" ]]
}

# ============================================================================
# check_version_match: 版本匹配时返回 0（需求 2.3）
# ============================================================================

@test "check_version_match: returns 0 when versions match exactly" {
    mock_caddy_installed "v2.7.6"
    check_installed
    OPT_VERSION="2.7.6"
    run check_version_match
    assert_success
}

# ============================================================================
# check_version_match: v 前缀处理（需求 2.3）
# ============================================================================

@test "check_version_match: returns 0 when OPT_VERSION has v prefix" {
    mock_caddy_installed "v2.7.6"
    check_installed
    OPT_VERSION="v2.7.6"
    run check_version_match
    assert_success
}

@test "check_version_match: returns 0 when installed has v prefix and OPT_VERSION does not" {
    mock_caddy_installed "v2.8.0"
    check_installed
    OPT_VERSION="2.8.0"
    run check_version_match
    assert_success
}

# ============================================================================
# check_version_match: 版本不匹配时返回 1（需求 2.4）
# ============================================================================

@test "check_version_match: returns 1 when versions differ" {
    mock_caddy_installed "v2.7.6"
    check_installed
    OPT_VERSION="2.8.0"
    run check_version_match
    assert_failure
}

@test "check_version_match: returns 1 for major version difference" {
    mock_caddy_installed "v1.0.0"
    check_installed
    OPT_VERSION="2.0.0"
    run check_version_match
    assert_failure
}

# ============================================================================
# check_version_match: caddy version 命令失败时返回 1
# ============================================================================

@test "check_version_match: returns 1 when caddy version command fails" {
    # Create a mock caddy that fails on "version" subcommand
    local mock_script="${MOCK_BIN_DIR}/caddy"
    cat > "$mock_script" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$mock_script"
    CADDY_BIN="$mock_script"
    OPT_VERSION="2.7.6"
    run check_version_match
    assert_failure
}
