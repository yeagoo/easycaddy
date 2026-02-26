#!/usr/bin/env bats
# ============================================================================
# test_prop_status_format.bats — Property 10: 状态 API 响应格式
# Feature: docker-repo-system, Property 10: 状态 API 响应格式
#
# For any 系统状态（无论是否有过构建），GET /api/status 应返回有效的 JSON 响应，
# 包含 last_build_time、version、status 三个字段。
#
# Test approach: 100 iterations with random status data.
# For each iteration:
#   1. Randomly create or skip STATUS_FILE with random last_build_time and status values
#   2. Randomly create or skip VERSION_FILE with a random version
#   3. Call get_status_json
#   4. Verify the output is valid JSON containing all 3 required fields:
#      last_build_time, version, status
#
# **Validates: Requirements 4.5**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/generators_docker.bash"
    source "$PROJECT_ROOT/tests/test_helper/mock_helpers.bash"
    setup_test_env

    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/repo-manager/manager.sh"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 10: 状态 API 响应格式 (100 iterations)
# ============================================================================

@test "Property 10: 状态 API 响应格式 — 随机状态数据返回有效 JSON" {
    for i in $(seq 1 100); do
        export STATUS_FILE="${TEST_TEMP_DIR}/status-${i}"
        export VERSION_FILE="${TEST_TEMP_DIR}/version-${i}"

        # Randomly populate status file
        if (( RANDOM % 2 == 0 )); then
            echo "last_build_time=2024-01-$(( RANDOM % 28 + 1 ))T$(( RANDOM % 24 )):00:00" > "$STATUS_FILE"
            local statuses=(success failure running)
            echo "status=${statuses[$(( RANDOM % 3 ))]}" >> "$STATUS_FILE"
        fi

        # Randomly populate version file
        if (( RANDOM % 2 == 0 )); then
            gen_version_string > "$VERSION_FILE"
        fi

        local json_output
        json_output="$(get_status_json)"

        # Verify JSON contains all 3 required fields
        [[ "$json_output" == *'"last_build_time":'* ]] || \
            fail "Iteration ${i}: Missing last_build_time field. Output: ${json_output}"
        [[ "$json_output" == *'"version":'* ]] || \
            fail "Iteration ${i}: Missing version field. Output: ${json_output}"
        [[ "$json_output" == *'"status":'* ]] || \
            fail "Iteration ${i}: Missing status field. Output: ${json_output}"

        # Verify it starts with { and ends with }
        [[ "$json_output" == "{"* ]] || \
            fail "Iteration ${i}: JSON should start with {. Output: ${json_output}"
        [[ "$json_output" == *"}" ]] || \
            fail "Iteration ${i}: JSON should end with }. Output: ${json_output}"
    done
}
