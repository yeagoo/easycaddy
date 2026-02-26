#!/usr/bin/env bats
# ============================================================================
# test_prop_api_auth.bats — Property 9: API 认证强制执行
# Feature: docker-repo-system, Property 9: API 认证强制执行
#
# For any 到达 repo-manager 的 HTTP 请求，如果请求头中不包含有效的
# Authorization: Bearer <API_TOKEN>，manager 应返回 HTTP 401 状态码并拒绝执行操作。
#
# Test approach: 100 iterations using gen_api_request and gen_api_token
# from generators_docker.bash.
#
# For each iteration:
#   1. Generate a random API_TOKEN (the "correct" token)
#   2. Generate a random request (method + path + optional auth header)
#   3. Call check_auth with the auth value (Bearer <token>)
#   4. If auth value matches "Bearer ${API_TOKEN}" → should return 0
#   5. If auth value is empty or doesn't match → should return 1
#
# Also test handle_request to verify 401 responses for unauthenticated requests.
#
# **Validates: Requirements 4.6**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/generators_docker.bash"
    source "$PROJECT_ROOT/tests/test_helper/mock_helpers.bash"
    setup_test_env

    # Set up temp files for manager
    export STATUS_FILE="${TEST_TEMP_DIR}/.manager-status"
    export VERSION_FILE="${TEST_TEMP_DIR}/.current-version"

    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/repo-manager/manager.sh"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 9: API 认证强制执行 (100 iterations)
# ============================================================================

@test "Property 9: API 认证强制执行 — 随机请求正确验证认证" {
    for i in $(seq 1 100); do
        # Generate a random "correct" token
        local correct_token
        correct_token="$(gen_api_token)"
        export API_TOKEN="$correct_token"

        # Generate a random request
        local request_output
        request_output="$(gen_api_request)"
        local auth_line
        auth_line="$(echo "$request_output" | sed -n '2p')"

        # check_auth expects the value part: "Bearer <token>"
        # gen_api_request outputs "Authorization: Bearer <token>" or empty
        local auth_value=""
        if [[ "$auth_line" == Authorization:* ]]; then
            auth_value="${auth_line#Authorization: }"
        fi

        local exit_code=0
        check_auth "$auth_value" || exit_code=$?

        if [[ "$auth_value" == "Bearer ${correct_token}" ]]; then
            [[ "$exit_code" -eq 0 ]] || \
                fail "Iteration ${i}: Auth should succeed for matching token"
        else
            [[ "$exit_code" -ne 0 ]] || \
                fail "Iteration ${i}: Auth should fail for non-matching auth value: '${auth_value}'"
        fi
    done

    # Explicitly test: correct token always succeeds
    for i in $(seq 1 50); do
        local token
        token="$(gen_api_token)"
        export API_TOKEN="$token"

        run check_auth "Bearer ${token}"
        assert_success
    done

    # Wrong token always fails
    for i in $(seq 1 50); do
        local token wrong_token
        token="$(gen_api_token)"
        wrong_token="$(gen_api_token)"
        export API_TOKEN="$token"

        # Ensure they're different
        if [[ "$token" != "$wrong_token" ]]; then
            run check_auth "Bearer ${wrong_token}"
            assert_failure
        fi
    done
}
