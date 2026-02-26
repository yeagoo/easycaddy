#!/usr/bin/env bats
# ============================================================================
# test_prop_exit_code_propagation.bats — Property 1: 容器退出码传播
# Feature: docker-repo-system, Property 1: 容器退出码传播
#
# For any 容器（builder 或 signer），当内部 build-repo.sh 进程以退出码 N 退出时，
# 容器本身也应以相同的退出码 N 退出。成功时退出码为 0，失败时为非零。
#
# Test approach: Since entrypoint.sh uses `exec bash /app/build-repo.sh "${ARGS[@]}"`,
# exec replaces the shell process, so build-repo.sh's exit code becomes the container's
# exit code. We test this by:
# 1. Creating a modified entrypoint that points to a mock build-repo.sh in temp dir
# 2. Running the entrypoint via bash (exec will replace the bash process)
# 3. Verifying the exit code matches the mock's exit code
#
# For 100 iterations:
# - Generate a random exit code (0-8) using gen_exit_code
# - Create a temporary mock build-repo.sh that exits with that code
# - Run the modified entrypoint.sh
# - Verify the exit code matches
#
# **Validates: Requirements 1.3, 2.4**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/generators_docker.bash"
    source "$PROJECT_ROOT/tests/test_helper/mock_helpers.bash"
    setup_test_env

    # Create a modified entrypoint that uses our temp dir instead of /app
    MOCK_ENTRYPOINT="${TEST_TEMP_DIR}/entrypoint.sh"
    sed "s|/app/build-repo.sh|${TEST_TEMP_DIR}/build-repo.sh|g" \
        "$PROJECT_ROOT/docker/builder/entrypoint.sh" > "$MOCK_ENTRYPOINT"
    chmod +x "$MOCK_ENTRYPOINT"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 1: 容器退出码传播 (100 iterations)
# ============================================================================

@test "Property 1: 容器退出码传播 — build-repo.sh 退出码正确传播到容器" {
    for i in $(seq 1 100); do
        local expected_code
        expected_code="$(gen_exit_code)"

        # Create mock build-repo.sh that exits with the expected code
        cat > "${TEST_TEMP_DIR}/build-repo.sh" << EOF
#!/usr/bin/env bash
exit ${expected_code}
EOF
        chmod +x "${TEST_TEMP_DIR}/build-repo.sh"

        # Run entrypoint — exec replaces the bash process with the mock,
        # so the exit code propagates correctly
        local actual_code=0
        bash "$MOCK_ENTRYPOINT" || actual_code=$?

        [[ "$actual_code" -eq "$expected_code" ]] || \
            fail "Iteration ${i}: Expected exit code ${expected_code}, got ${actual_code}"
    done
}
