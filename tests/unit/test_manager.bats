#!/usr/bin/env bats
# ============================================================================
# test_manager.bats — manager.sh 单元测试
# 测试各 API 端点响应、认证成功/失败、JSON 响应格式
#
# Requirements: 4.1, 4.5, 4.6
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/mock_helpers.bash"
    setup_test_env

    export STATUS_FILE="${TEST_TEMP_DIR}/.manager-status"
    export VERSION_FILE="${TEST_TEMP_DIR}/.current-version"

    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/repo-manager/manager.sh"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# check_auth 测试 (Requirement 4.6)
# ============================================================================

@test "check_auth: 正确 token 认证成功" {
    export API_TOKEN="my-secret-token"
    run check_auth "Bearer my-secret-token"
    assert_success
}

@test "check_auth: 错误 token 认证失败" {
    export API_TOKEN="my-secret-token"
    run check_auth "Bearer wrong-token"
    assert_failure
}

@test "check_auth: 空 auth header 认证失败" {
    export API_TOKEN="my-secret-token"
    run check_auth ""
    assert_failure
}

@test "check_auth: API_TOKEN 未设置时认证失败" {
    unset API_TOKEN
    run check_auth "Bearer any-token"
    assert_failure
}

# ============================================================================
# get_status_json 测试 (Requirement 4.5)
# ============================================================================

@test "get_status_json: 无状态文件时返回空字段 JSON" {
    run get_status_json
    assert_success
    assert_output --partial '"last_build_time":""'
    assert_output --partial '"version":""'
    assert_output --partial '"status":"unknown"'
}

@test "get_status_json: 有状态文件时返回正确值" {
    echo "last_build_time=2024-01-15T10:00:00" > "$STATUS_FILE"
    echo "status=success" >> "$STATUS_FILE"
    echo "2.9.1" > "$VERSION_FILE"

    run get_status_json
    assert_success
    assert_output --partial '"last_build_time":"2024-01-15T10:00:00"'
    assert_output --partial '"version":"2.9.1"'
    assert_output --partial '"status":"success"'
}

# ============================================================================
# send_response 测试 (Requirement 4.1)
# ============================================================================

@test "send_response: 输出正确的 HTTP 响应格式" {
    run send_response 200 "OK" '{"test":"value"}'
    assert_success
    assert_output --partial "HTTP/1.1 200 OK"
    assert_output --partial "Content-Type: application/json"
    assert_output --partial '{"test":"value"}'
}

@test "send_response: 401 响应" {
    run send_response 401 "Unauthorized" '{"error":"unauthorized"}'
    assert_success
    assert_output --partial "HTTP/1.1 401 Unauthorized"
}

# ============================================================================
# handle_request 测试 (Requirement 4.1, 4.5, 4.6)
# ============================================================================

@test "handle_request: 未认证请求返回 401" {
    export API_TOKEN="secret"
    run handle_request "GET" "/api/status" ""
    assert_success
    assert_output --partial "401"
    assert_output --partial "unauthorized"
}

@test "handle_request: GET /api/status 认证成功返回 JSON" {
    export API_TOKEN="secret"
    echo "2.9.1" > "$VERSION_FILE"

    run handle_request "GET" "/api/status" "Bearer secret"
    assert_success
    assert_output --partial "200"
    assert_output --partial '"version":"2.9.1"'
}

@test "handle_request: 未知路径返回 404" {
    export API_TOKEN="secret"
    run handle_request "GET" "/api/unknown" "Bearer secret"
    assert_success
    assert_output --partial "404"
    assert_output --partial "not found"
}
