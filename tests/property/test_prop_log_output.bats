#!/usr/bin/env bats
# ============================================================================
# test_prop_log_output.bats — Property 13: 日志输出规范性
# Feature: caddy-installer-china, Property 13: 日志输出规范性
#
# For any 日志函数调用（util_log_info、util_log_success、util_log_warn、
# util_log_error），输出应写入 stderr 而非 stdout；当 USE_COLOR=true 时应包含
# 对应的 ANSI 颜色转义序列（蓝/绿/黄/红），当 USE_COLOR=false 时不应包含任何
# ANSI 转义序列。
#
# **Validates: Requirements 10.7, 10.8, 10.9**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'

setup() {
    setup_test_env
    source_install_script
}

teardown() {
    teardown_test_env
}

# Helper: call a log function, capture stdout and stderr separately
# Usage: call_log_func <func_name> <message>
# Sets: LOG_STDOUT, LOG_STDERR
call_log_func() {
    local func="$1"
    local msg="$2"
    LOG_STDOUT=""
    LOG_STDERR=""
    LOG_STDOUT="$("$func" "$msg" 2>"${TEST_TEMP_DIR}/prop_stderr.out")"
    LOG_STDERR="$(cat "${TEST_TEMP_DIR}/prop_stderr.out")"
}

# ============================================================================
# Property 13: 日志输出规范性 — 所有输出到 stderr，stdout 为空
# ============================================================================

@test "Property 13: all log functions output to stderr, stdout is empty (100 iterations)" {
    local funcs=(util_log_info util_log_success util_log_warn util_log_error)

    for i in $(seq 1 100); do
        local msg
        msg="$(gen_random_log_message)"

        for func in "${funcs[@]}"; do
            call_log_func "$func" "$msg"

            # stdout MUST be empty
            if [[ -n "$LOG_STDOUT" ]]; then
                fail "Iteration ${i}: ${func} wrote to stdout: '${LOG_STDOUT}' (msg='${msg}')"
            fi

            # stderr MUST contain the message
            if [[ -z "$LOG_STDERR" ]]; then
                fail "Iteration ${i}: ${func} produced no stderr output (msg='${msg}')"
            fi
        done
    done
}

# ============================================================================
# Property 13: USE_COLOR=true 时包含正确的 ANSI 颜色转义序列
# ============================================================================

@test "Property 13: with USE_COLOR=true, log functions include correct ANSI color codes (100 iterations)" {
    USE_COLOR=true

    # Expected ANSI color codes per function
    # info=blue(\033[0;34m), success=green(\033[0;32m), warn=yellow(\033[0;33m), error=red(\033[0;31m)
    local -A expected_colors
    expected_colors[util_log_info]=$'\033[0;34m'
    expected_colors[util_log_success]=$'\033[0;32m'
    expected_colors[util_log_warn]=$'\033[0;33m'
    expected_colors[util_log_error]=$'\033[0;31m'

    local reset_code=$'\033[0m'

    for i in $(seq 1 100); do
        local msg
        msg="$(gen_random_log_message)"

        for func in util_log_info util_log_success util_log_warn util_log_error; do
            call_log_func "$func" "$msg"

            local expected_color="${expected_colors[$func]}"

            # Must contain the expected color code
            if [[ "$LOG_STDERR" != *"${expected_color}"* ]]; then
                fail "Iteration ${i}: ${func} missing color code (msg='${msg}')"
            fi

            # Must contain the reset code
            if [[ "$LOG_STDERR" != *"${reset_code}"* ]]; then
                fail "Iteration ${i}: ${func} missing reset code (msg='${msg}')"
            fi
        done
    done
}

# ============================================================================
# Property 13: USE_COLOR=false 时不包含任何 ANSI 转义序列
# ============================================================================

@test "Property 13: with USE_COLOR=false, log functions contain no ANSI escape sequences (100 iterations)" {
    USE_COLOR=false

    local esc=$'\033'

    for i in $(seq 1 100); do
        local msg
        msg="$(gen_random_log_message)"

        for func in util_log_info util_log_success util_log_warn util_log_error; do
            call_log_func "$func" "$msg"

            # Must NOT contain any ESC character
            if [[ "$LOG_STDERR" == *"${esc}"* ]]; then
                fail "Iteration ${i}: ${func} contains ANSI escape sequence with USE_COLOR=false (msg='${msg}')"
            fi
        done
    done
}
