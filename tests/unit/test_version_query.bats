#!/usr/bin/env bats
# ============================================================================
# test_version_query.bats — 版本查询单元测试
# 测试 resolve_version 函数的 API 响应解析、v 前缀去除、网络失败处理
# 以及 extract_version_from_tag 函数的具体示例
# 验证需求: 14.1, 14.2, 14.3
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

# Reset relevant global variables between tests
reset_version_globals() {
    OPT_VERSION=""
    CADDY_VERSION=""
}

# Create a mock curl that returns a GitHub API response with the given version
create_mock_curl_github_api() {
    local version="$1"
    local mock_script="${MOCK_BIN_DIR}/curl"
    cat > "$mock_script" << MOCK_EOF
#!/bin/bash
echo '{"tag_name": "v${version}", "name": "v${version}"}'
MOCK_EOF
    chmod +x "$mock_script"
}

setup() {
    setup_test_env
    source_build_repo_script
    reset_version_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# 1. resolve_version with OPT_VERSION set (Requirements 14.2, 2.7)
# ============================================================================

@test "resolve_version: OPT_VERSION set → CADDY_VERSION equals OPT_VERSION (v stripped)" {
    OPT_VERSION="v2.9.0"
    resolve_version
    [[ "$CADDY_VERSION" == "2.9.0" ]]
}

@test "resolve_version: OPT_VERSION='v2.9.0' → CADDY_VERSION='2.9.0'" {
    OPT_VERSION="v2.9.0"
    resolve_version
    [[ "$CADDY_VERSION" == "2.9.0" ]]
}

@test "resolve_version: OPT_VERSION='2.9.0' → CADDY_VERSION='2.9.0'" {
    OPT_VERSION="2.9.0"
    resolve_version
    [[ "$CADDY_VERSION" == "2.9.0" ]]
}

# ============================================================================
# 2. resolve_version with empty OPT_VERSION and mock curl (Requirements 14.1)
# ============================================================================

@test "resolve_version: empty OPT_VERSION + valid API response → CADDY_VERSION set correctly" {
    OPT_VERSION=""
    create_mock_curl_github_api "2.8.4"

    resolve_version

    [[ "$CADDY_VERSION" == "2.8.4" ]]
}

# ============================================================================
# 3. resolve_version with empty OPT_VERSION and curl failing (Requirements 14.3)
# ============================================================================

@test "resolve_version: empty OPT_VERSION + curl failing → exit code 3" {
    OPT_VERSION=""
    create_mock_command curl 22 "" "curl: (22) The requested URL returned error: 403"

    run resolve_version

    assert_failure 3
}

# ============================================================================
# 4. resolve_version with empty OPT_VERSION and invalid API response (Requirements 14.3)
# ============================================================================

@test "resolve_version: empty OPT_VERSION + invalid API response → exit code 3" {
    OPT_VERSION=""
    # Mock curl returns invalid JSON without tag_name
    create_mock_command curl 0 '{"message": "Not Found"}'

    run resolve_version

    assert_failure 3
}

# ============================================================================
# 5. extract_version_from_tag specific examples (Requirements 14.2)
# ============================================================================

@test "extract_version_from_tag: 'v2.9.0' → '2.9.0'" {
    local result
    result="$(extract_version_from_tag "v2.9.0")"
    [[ "$result" == "2.9.0" ]]
}

@test "extract_version_from_tag: '2.9.0' → '2.9.0'" {
    local result
    result="$(extract_version_from_tag "2.9.0")"
    [[ "$result" == "2.9.0" ]]
}

@test "extract_version_from_tag: 'v1.0.0-beta.1' → '1.0.0-beta.1'" {
    local result
    result="$(extract_version_from_tag "v1.0.0-beta.1")"
    [[ "$result" == "1.0.0-beta.1" ]]
}
