#!/usr/bin/env bats
# ============================================================================
# test_prop_dep_check.bats — Property 3: 依赖检查正确性
# Feature: selfhosted-rpm-repo-builder, Property 3: 依赖检查正确性
#
# For any 必要工具（curl、nfpm、createrepo_c/createrepo、gpg、rpm）的可用性子集，
# check_dependencies 函数应准确报告所有缺失的工具名称，并在任一工具缺失时
# 以退出码 2 终止。
#
# **Validates: Requirements 3.1, 3.2**
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
# This ensures real system tools (curl, gpg, rpm, etc.) are NOT found
run_check_deps_isolated() {
    PATH="${MOCK_BIN_DIR}" run check_dependencies
}

# ============================================================================
# Property 3a: all tools present → check_dependencies succeeds (100 iterations)
# ============================================================================

@test "Property 3: all required tools present → check_dependencies succeeds (100 iterations)" {
    for i in $(seq 1 100); do
        # Create mocks for all required tools (with normal PATH so chmod works)
        create_all_tool_mocks

        # Run check_dependencies with isolated PATH
        run_check_deps_isolated

        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: check_dependencies failed with exit code ${status} when all tools present. Output: ${output}"
        fi
    done
}

# ============================================================================
# Property 3b: random subset of tools missing → exit code 2 and reports
# missing tool names (100 iterations)
#
# For each iteration, randomly decide which tools to remove (at least one).
# Verify exit code is 2 and that each missing tool name appears in output.
# ============================================================================

@test "Property 3: random missing tools → exit code 2 and reports missing names (100 iterations)" {
    for i in $(seq 1 100); do
        # Start with all tools present
        create_all_tool_mocks

        # Randomly decide which tools to remove (at least 1)
        local removed=()
        for tool in "${REQUIRED_TOOLS[@]}"; do
            if (( RANDOM % 2 == 0 )); then
                remove_tool_mock "$tool"
                removed+=("$tool")
            fi
        done

        # Ensure at least one tool is removed
        if [[ ${#removed[@]} -eq 0 ]]; then
            local idx=$(( RANDOM % ${#REQUIRED_TOOLS[@]} ))
            local tool="${REQUIRED_TOOLS[$idx]}"
            remove_tool_mock "$tool"
            removed+=("$tool")
        fi

        # Run with isolated PATH
        run_check_deps_isolated

        # Should exit with code 2
        if [[ "$status" -ne 2 ]]; then
            fail "Iteration ${i}: expected exit code 2 with missing tools [${removed[*]}], got ${status}. Output: ${output}"
        fi

        # Each removed tool name should appear in the error output
        # Note: createrepo_c is special — check_dependencies accepts either createrepo_c or createrepo
        for tool in "${removed[@]}"; do
            if [[ "$tool" == "createrepo_c" ]]; then
                # createrepo_c is only reported missing when createrepo is also absent
                if [[ ! -x "${MOCK_BIN_DIR}/createrepo" ]]; then
                    if [[ "$output" != *"createrepo_c"* ]]; then
                        fail "Iteration ${i}: output missing 'createrepo_c' when both createrepo_c and createrepo are absent. Removed: [${removed[*]}]. Output: ${output}"
                    fi
                fi
            else
                if [[ "$output" != *"$tool"* ]]; then
                    fail "Iteration ${i}: output missing tool name '${tool}'. Removed: [${removed[*]}]. Output: ${output}"
                fi
            fi
        done
    done
}

# ============================================================================
# Property 3c: createrepo fallback — if createrepo_c is missing but createrepo
# is present, check_dependencies should NOT report createrepo_c as missing
# (100 iterations)
# ============================================================================

@test "Property 3: createrepo fallback — createrepo present compensates for missing createrepo_c (100 iterations)" {
    for i in $(seq 1 100); do
        # Create all tools
        create_all_tool_mocks

        # Remove createrepo_c but add createrepo as fallback
        remove_tool_mock "createrepo_c"
        create_mock_command "createrepo" 0

        # Run with isolated PATH
        run_check_deps_isolated

        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: check_dependencies failed with exit code ${status} when createrepo is available as fallback. Output: ${output}"
        fi
    done
}
