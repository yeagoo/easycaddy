#!/usr/bin/env bats
# ============================================================================
# test_scheduler.bats — scheduler.sh 单元测试
# 测试 parse_interval 各格式、get_latest_version mock curl、
# get_current_version 文件存在/不存在、首次运行立即检查逻辑
#
# Requirements: 11.2, 11.3, 11.4, 11.7, 11.12
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/mock_helpers.bash"
    setup_test_env
    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/scheduler/scheduler.sh"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# parse_interval 测试 (Requirement 11.2)
# ============================================================================

@test "parse_interval: 5d → 432000 秒" {
    run parse_interval "5d"
    assert_success
    assert_output "432000"
}

@test "parse_interval: 12h → 43200 秒" {
    run parse_interval "12h"
    assert_success
    assert_output "43200"
}

@test "parse_interval: 纯数字 3600 → 3600" {
    run parse_interval "3600"
    assert_success
    assert_output "3600"
}

@test "parse_interval: 1d → 86400 秒" {
    run parse_interval "1d"
    assert_success
    assert_output "86400"
}

@test "parse_interval: 24h → 86400 秒" {
    run parse_interval "24h"
    assert_success
    assert_output "86400"
}

@test "parse_interval: 10d（默认值）→ 864000 秒" {
    run parse_interval "10d"
    assert_success
    assert_output "864000"
}

# ============================================================================
# get_current_version 测试 (Requirement 11.4, 11.7)
# ============================================================================

@test "get_current_version: 文件存在时返回版本号" {
    local version_file="${TEST_TEMP_DIR}/.current-version"
    echo "2.9.1" > "$version_file"
    export VERSION_FILE="$version_file"

    run get_current_version
    assert_success
    assert_output "2.9.1"
}

@test "get_current_version: 文件不存在时返回空" {
    export VERSION_FILE="${TEST_TEMP_DIR}/nonexistent"

    run get_current_version
    assert_success
    assert_output ""
}

# ============================================================================
# get_latest_version 测试 (Requirement 11.3)
# ============================================================================

@test "get_latest_version: 正确解析 GitHub API 响应" {
    local mock_script="${MOCK_BIN_DIR}/curl"
    cat > "$mock_script" << 'EOF'
#!/usr/bin/env bash
echo '{"tag_name": "v2.9.1", "name": "v2.9.1"}'
EOF
    chmod +x "$mock_script"

    run get_latest_version
    assert_success
    assert_output "2.9.1"
}

@test "get_latest_version: 支持 GITHUB_TOKEN 认证" {
    local mock_script="${MOCK_BIN_DIR}/curl"
    local args_file="${MOCK_BIN_DIR}/curl.args"
    cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
echo "\$@" >> '${args_file}'
echo '{"tag_name": "v2.10.0"}'
MOCK_EOF
    chmod +x "$mock_script"
    : > "$args_file"

    export GITHUB_TOKEN="test-token-123"
    run get_latest_version
    assert_success
    assert_output "2.10.0"

    # Verify Authorization header was passed
    run cat "$args_file"
    assert_output --partial "Authorization: token test-token-123"
    unset GITHUB_TOKEN
}
