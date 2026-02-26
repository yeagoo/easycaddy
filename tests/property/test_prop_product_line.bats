#!/usr/bin/env bats
# ============================================================================
# test_prop_product_line.bats — Property 1: 产品线映射正确性
# Feature: selfhosted-rpm-repo-builder, Property 1: 产品线映射正确性
#
# For any 有效的 distro_id:version 组合（来自 Product_Line_Map 中的 28 个条目），
# resolve_product_lines 函数应返回正确的产品线 ID；
# For any 不在映射表中的 distro_id:version 组合，函数应以退出码 1 终止。
#
# **Validates: Requirements 1.1, 1.3, 1.4**
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

# Reset build-repo.sh global variables between iterations
reset_build_repo_globals() {
    TARGET_PRODUCT_LINES=()
}

setup() {
    setup_test_env
    source_build_repo_script
    reset_build_repo_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 1a: valid distro:version → correct product line (100 iterations)
# ============================================================================

@test "Property 1: random valid distro:version maps to correct product line (100 iterations)" {
    for i in $(seq 1 100); do
        reset_build_repo_globals

        local dv
        dv="$(gen_valid_distro_version)"

        # Call resolve_product_lines with a single valid distro:version
        resolve_product_lines "$dv"

        # Should return exactly one product line
        if [[ ${#TARGET_PRODUCT_LINES[@]} -ne 1 ]]; then
            fail "Iteration ${i}: distro '${dv}' returned ${#TARGET_PRODUCT_LINES[@]} product lines, expected 1"
        fi

        # The returned product line should match the expected mapping
        local expected="${EXPECTED_DISTRO_PL_MAP[$dv]}"
        local actual="${TARGET_PRODUCT_LINES[0]}"
        if [[ "$actual" != "$expected" ]]; then
            fail "Iteration ${i}: distro '${dv}' mapped to '${actual}', expected '${expected}'"
        fi
    done
}

# ============================================================================
# Property 1b: invalid distro:version → exit code 1 (100 iterations)
# ============================================================================

@test "Property 1: random invalid distro:version exits with code 1 (100 iterations)" {
    for i in $(seq 1 100); do
        reset_build_repo_globals

        local dv
        dv="$(gen_invalid_distro_version)"

        run resolve_product_lines "$dv"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: invalid distro '${dv}' exited with code ${status}, expected 1"
        fi
    done
}

# ============================================================================
# Property 1c: resolve_product_lines "all" returns all 7 product lines
# ============================================================================

@test "Property 1: resolve_product_lines 'all' returns all 7 product lines" {
    reset_build_repo_globals

    resolve_product_lines "all"

    # Should return exactly 7 product lines
    if [[ ${#TARGET_PRODUCT_LINES[@]} -ne 7 ]]; then
        fail "Expected 7 product lines, got ${#TARGET_PRODUCT_LINES[@]}: ${TARGET_PRODUCT_LINES[*]}"
    fi

    # Verify all known product lines are present
    for pl in "${KNOWN_PRODUCT_LINES[@]}"; do
        local found=false
        for actual_pl in "${TARGET_PRODUCT_LINES[@]}"; do
            if [[ "$actual_pl" == "$pl" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" != true ]]; then
            fail "Product line '${pl}' not found in result: ${TARGET_PRODUCT_LINES[*]}"
        fi
    done
}

# ============================================================================
# Property 1d: openEuler:20 outputs warning and is skipped
# ============================================================================

@test "Property 1: openEuler:20 outputs warning to stderr and is skipped" {
    reset_build_repo_globals

    run resolve_product_lines "openEuler:20"

    # Should succeed (exit 0) but with empty product lines
    assert_success
    # stderr should contain warning about openEuler 20
    assert_output --partial "openEuler 20 is not supported"
}
