#!/usr/bin/env bats
# ============================================================================
# test_prop_parse_args.bats — Property 8: 命令行参数解析正确性
# Feature: caddy-installer-china, Property 8: 命令行参数解析正确性
#
# For any 有效的命令行参数组合，parse_args 函数应正确设置对应的全局变量
# （OPT_VERSION、OPT_METHOD、OPT_PREFIX、OPT_MIRROR、OPT_SKIP_SERVICE、
# OPT_SKIP_CAP、OPT_YES）；For any 未知参数字符串，parse_args 应以退出码 1 终止。
#
# **Validates: Requirements 7.1, 7.2, 7.5, 7.6, 7.11**
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
# Property 8: 有效参数组合 → 全局变量正确设置 (100 iterations)
# ============================================================================

@test "Property 8: random valid parameter combinations correctly set global variables (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset globals before each iteration
        reset_script_globals

        # Build random args as an array directly
        local args=()
        local expected_version=""
        local expected_method=""
        local expected_prefix="/usr/local/bin"
        local expected_mirror=""
        local expected_skip_service="false"
        local expected_skip_cap="false"
        local expected_yes="false"

        # Randomly add --version
        if (( RANDOM % 3 == 0 )); then
            local ver
            ver="$(gen_caddy_version)"
            args+=(--version "$ver")
            expected_version="$ver"
        fi

        # Randomly add --method
        if (( RANDOM % 3 == 0 )); then
            local method
            method="$(gen_pick_one repo binary)"
            args+=(--method "$method")
            expected_method="$method"
        fi

        # Randomly add --prefix
        if (( RANDOM % 4 == 0 )); then
            local prefix
            prefix="$(gen_random_prefix)"
            args+=(--prefix "$prefix")
            expected_prefix="$prefix"
        fi

        # Randomly add --mirror
        if (( RANDOM % 4 == 0 )); then
            local mirror
            mirror="$(gen_random_mirror_url)"
            args+=(--mirror "$mirror")
            expected_mirror="$mirror"
        fi

        # Randomly add --skip-service
        if (( RANDOM % 4 == 0 )); then
            args+=(--skip-service)
            expected_skip_service="true"
        fi

        # Randomly add --skip-cap
        if (( RANDOM % 4 == 0 )); then
            args+=(--skip-cap)
            expected_skip_cap="true"
        fi

        # Randomly add -y or --yes
        if (( RANDOM % 4 == 0 )); then
            local yes_flag
            yes_flag="$(gen_pick_one -y --yes)"
            args+=("$yes_flag")
            expected_yes="true"
        fi

        # Call parse_args with the generated args
        parse_args "${args[@]}"

        # Verify each global variable
        if [[ "$OPT_VERSION" != "$expected_version" ]]; then
            fail "Iteration ${i}: OPT_VERSION='${OPT_VERSION}' expected='${expected_version}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_METHOD" != "$expected_method" ]]; then
            fail "Iteration ${i}: OPT_METHOD='${OPT_METHOD}' expected='${expected_method}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_PREFIX" != "$expected_prefix" ]]; then
            fail "Iteration ${i}: OPT_PREFIX='${OPT_PREFIX}' expected='${expected_prefix}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_MIRROR" != "$expected_mirror" ]]; then
            fail "Iteration ${i}: OPT_MIRROR='${OPT_MIRROR}' expected='${expected_mirror}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_SKIP_SERVICE" != "$expected_skip_service" ]]; then
            fail "Iteration ${i}: OPT_SKIP_SERVICE='${OPT_SKIP_SERVICE}' expected='${expected_skip_service}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_SKIP_CAP" != "$expected_skip_cap" ]]; then
            fail "Iteration ${i}: OPT_SKIP_CAP='${OPT_SKIP_CAP}' expected='${expected_skip_cap}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_YES" != "$expected_yes" ]]; then
            fail "Iteration ${i}: OPT_YES='${OPT_YES}' expected='${expected_yes}' args=(${args[*]:-})"
        fi
    done
}

# ============================================================================
# Property 8: 未知参数 → 退出码 1 (100 iterations)
# ============================================================================

@test "Property 8: random unknown parameters exit with code 1 (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        local unknown_arg
        unknown_arg="$(gen_unknown_cli_arg)"

        run parse_args "$unknown_arg"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: unknown arg '${unknown_arg}' exited with code ${status}, expected 1"
        fi
    done
}
