#!/usr/bin/env bats
# ============================================================================
# test_prop_version_compare.bats — Property 5: 版本比较正确性
# Feature: caddy-installer-china, Property 5: 版本比较正确性
#
# For any 两个语义化版本字符串，check_version_match 函数应在版本一致时返回 0
# （跳过安装），版本不一致时返回 1（继续安装）。
#
# **Validates: Requirements 2.3, 2.4**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 5a: 匹配版本 → 返回 0 (100 iterations)
# ============================================================================

@test "Property 5: matching versions return 0 (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        # Generate a random version (without "v" prefix)
        local version
        version="$(gen_random_version)"

        # Mock caddy to output "v{version} h1:abc123"
        mock_caddy_installed "v${version}"

        # Set CADDY_BIN to the mock
        CADDY_BIN="${MOCK_BIN_DIR}/caddy"

        # Randomly decide whether OPT_VERSION has "v" prefix or not
        if (( RANDOM % 2 == 0 )); then
            OPT_VERSION="${version}"
        else
            OPT_VERSION="v${version}"
        fi

        run check_version_match

        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: version='${version}' OPT_VERSION='${OPT_VERSION}' expected exit 0, got ${status}"
        fi
    done
}

# ============================================================================
# Property 5b: 不匹配版本 → 返回 1 (100 iterations)
# ============================================================================

@test "Property 5: non-matching versions return 1 (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        # Generate two different random versions
        local installed_version target_version
        installed_version="$(gen_random_version)"
        target_version="$(gen_random_version)"

        # Ensure they are actually different
        while [[ "$installed_version" == "$target_version" ]]; do
            target_version="$(gen_random_version)"
        done

        # Mock caddy with the installed version
        mock_caddy_installed "v${installed_version}"
        CADDY_BIN="${MOCK_BIN_DIR}/caddy"

        # Set OPT_VERSION to the different target version (randomly with/without "v")
        if (( RANDOM % 2 == 0 )); then
            OPT_VERSION="${target_version}"
        else
            OPT_VERSION="v${target_version}"
        fi

        run check_version_match

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: installed='${installed_version}' target='${target_version}' OPT_VERSION='${OPT_VERSION}' expected exit 1, got ${status}"
        fi
    done
}

# ============================================================================
# Property 5c: "v" 前缀规范化 — 任意前缀组合均正确匹配 (100 iterations)
# ============================================================================

@test "Property 5: v-prefix normalization works for all prefix combinations (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        # Generate a random version (bare, no prefix)
        local version
        version="$(gen_random_version)"

        # Randomly choose prefix for installed version: "v" or ""
        local installed_prefix=""
        if (( RANDOM % 2 == 0 )); then
            installed_prefix="v"
        fi

        # Randomly choose prefix for OPT_VERSION: "v" or ""
        local opt_prefix=""
        if (( RANDOM % 2 == 0 )); then
            opt_prefix="v"
        fi

        # Mock caddy with the chosen prefix combination
        mock_caddy_installed "${installed_prefix}${version}"
        CADDY_BIN="${MOCK_BIN_DIR}/caddy"
        OPT_VERSION="${opt_prefix}${version}"

        run check_version_match

        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: version='${version}' installed_prefix='${installed_prefix}' opt_prefix='${opt_prefix}' expected exit 0, got ${status}"
        fi
    done
}
