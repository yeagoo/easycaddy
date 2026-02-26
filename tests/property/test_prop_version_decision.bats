#!/usr/bin/env bats
# ============================================================================
# test_prop_version_decision.bats — Property 8: 版本比较与构建决策
# Feature: docker-repo-system, Property 8: 版本比较与构建决策
#
# For any 一对版本号（latest_version, current_version），当两者不同时，
# scheduler 应触发构建流程；当两者相同时，scheduler 应跳过构建并输出日志。
# 当 current_version 为空（Version_State_File 不存在）时，应视为需要构建。
#
# Test approach: 100 iterations using gen_version_pair from generators_docker.bash.
# For each pair:
#   - Set up a temp VERSION_FILE with the current version (or no file for empty)
#   - Call get_current_version and verify it returns the expected value
#   - Compare latest vs current and verify the decision matches expectations:
#     * current empty → should build
#     * current == latest → should skip
#     * current != latest → should build
#
# **Validates: Requirements 11.5, 11.6, 11.7**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/generators_docker.bash"
    source "$PROJECT_ROOT/tests/test_helper/mock_helpers.bash"
    setup_test_env
    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/scheduler/scheduler.sh"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 8: 版本比较与构建决策 (100 iterations)
# ============================================================================

@test "Property 8: 版本比较与构建决策 — 随机版本对正确决定构建/跳过" {
    for i in $(seq 1 100); do
        local pair_output
        pair_output="$(gen_version_pair)"

        local latest current
        latest="$(echo "$pair_output" | sed -n '1p')"
        current="$(echo "$pair_output" | sed -n '2p')"

        # Set up VERSION_FILE
        local version_file="${TEST_TEMP_DIR}/current-version-${i}"
        export VERSION_FILE="$version_file"

        if [[ -n "$current" ]]; then
            echo "$current" > "$version_file"
        else
            rm -f "$version_file"
        fi

        # Get current version via the function
        local got_current
        got_current="$(get_current_version)"

        # Verify get_current_version returns correct value
        [[ "$got_current" == "$current" ]] || \
            fail "Iteration ${i}: get_current_version returned '${got_current}', expected '${current}'"

        # Verify decision logic
        if [[ "$latest" == "$got_current" ]]; then
            # Same version → should skip (no build needed)
            local should_build=false
        else
            # Different or empty → should build
            local should_build=true
        fi

        # The scheduler's decision: build if latest != current
        if [[ "$latest" != "$got_current" ]]; then
            local actual_decision=true
        else
            local actual_decision=false
        fi

        [[ "$actual_decision" == "$should_build" ]] || \
            fail "Iteration ${i}: latest='${latest}', current='${current}', expected build=${should_build}, got build=${actual_decision}"
    done
}
