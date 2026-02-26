#!/usr/bin/env bats
# ============================================================================
# test_prop_log_stderr.bats — Property 18: 日志输出规范性
# Feature: selfhosted-rpm-repo-builder, Property 18: 日志输出规范性
#
# For any 构建执行，所有日志信息应输出到 stderr（不污染 stdout）；
# 每个主要步骤应有 [INFO] 级别日志；失败时应有 [ERROR] 级别日志；
# stdout 仅输出最终仓库根目录绝对路径。
#
# Test approach:
# - Test that util_log_info outputs to stderr with [INFO] prefix, not stdout
# - Test that util_log_error outputs to stderr with [ERROR] prefix, not stdout
# - Test with random messages across 100 iterations
#
# **Validates: Requirements 18.1, 18.3, 18.4**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators_repo'

source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

setup() {
    setup_test_env
    source_build_repo_script
    USE_COLOR=false
}

teardown() {
    teardown_test_env
}

# Helper: generate a random log message
gen_random_message() {
    local words=("构建" "下载" "签名" "验证" "发布" "回滚" "产品线" "RPM" "元数据"
                 "build" "download" "sign" "verify" "publish" "rollback" "product-line"
                 "error" "warning" "success" "failed" "completed" "starting")
    local count=$(( RANDOM % 4 + 1 ))
    local msg=""
    for (( j = 0; j < count; j++ )); do
        local idx=$(( RANDOM % ${#words[@]} ))
        if [[ -n "$msg" ]]; then
            msg="${msg} ${words[$idx]}"
        else
            msg="${words[$idx]}"
        fi
    done
    echo "${msg} $(( RANDOM % 1000 ))"
}

# Helper: call a log function, capture stdout and stderr separately
# Sets: LOG_STDOUT, LOG_STDERR
call_log_func() {
    local func="$1"
    local msg="$2"
    LOG_STDOUT=""
    LOG_STDERR=""
    LOG_STDOUT="$("$func" "$msg" 2>"${TEST_TEMP_DIR}/log_stderr.out")"
    LOG_STDERR="$(cat "${TEST_TEMP_DIR}/log_stderr.out")"
}

# ============================================================================
# Property 18.1: util_log_info outputs to stderr with [INFO] prefix (100 iterations)
# ============================================================================

@test "Property 18: util_log_info outputs to stderr (not stdout) with [INFO] prefix (100 iterations)" {
    for i in $(seq 1 100); do
        local msg
        msg="$(gen_random_message)"

        call_log_func util_log_info "$msg"

        # stdout MUST be empty
        if [[ -n "$LOG_STDOUT" ]]; then
            fail "Iteration ${i}: util_log_info wrote to stdout: '${LOG_STDOUT}' (msg='${msg}')"
        fi

        # stderr MUST contain the message
        if [[ -z "$LOG_STDERR" ]]; then
            fail "Iteration ${i}: util_log_info produced no stderr output (msg='${msg}')"
        fi

        # stderr MUST contain [INFO] prefix
        if [[ "$LOG_STDERR" != *"[INFO]"* ]]; then
            fail "Iteration ${i}: util_log_info missing [INFO] prefix in stderr (msg='${msg}', stderr='${LOG_STDERR}')"
        fi

        # stderr MUST contain the original message
        if [[ "$LOG_STDERR" != *"${msg}"* ]]; then
            fail "Iteration ${i}: util_log_info stderr does not contain message (msg='${msg}', stderr='${LOG_STDERR}')"
        fi
    done
}

# ============================================================================
# Property 18.2: util_log_error outputs to stderr with [ERROR] prefix (100 iterations)
# ============================================================================

@test "Property 18: util_log_error outputs to stderr (not stdout) with [ERROR] prefix (100 iterations)" {
    for i in $(seq 1 100); do
        local msg
        msg="$(gen_random_message)"

        call_log_func util_log_error "$msg"

        # stdout MUST be empty
        if [[ -n "$LOG_STDOUT" ]]; then
            fail "Iteration ${i}: util_log_error wrote to stdout: '${LOG_STDOUT}' (msg='${msg}')"
        fi

        # stderr MUST contain the message
        if [[ -z "$LOG_STDERR" ]]; then
            fail "Iteration ${i}: util_log_error produced no stderr output (msg='${msg}')"
        fi

        # stderr MUST contain [ERROR] prefix
        if [[ "$LOG_STDERR" != *"[ERROR]"* ]]; then
            fail "Iteration ${i}: util_log_error missing [ERROR] prefix in stderr (msg='${msg}', stderr='${LOG_STDERR}')"
        fi

        # stderr MUST contain the original message
        if [[ "$LOG_STDERR" != *"${msg}"* ]]; then
            fail "Iteration ${i}: util_log_error stderr does not contain message (msg='${msg}', stderr='${LOG_STDERR}')"
        fi
    done
}

# ============================================================================
# Property 18.3: Both log functions never pollute stdout (combined test)
# ============================================================================

@test "Property 18: log functions never write to stdout regardless of message content (100 iterations)" {
    local funcs=(util_log_info util_log_error)

    for i in $(seq 1 100); do
        local msg
        msg="$(gen_random_message)"

        for func in "${funcs[@]}"; do
            call_log_func "$func" "$msg"

            # stdout MUST always be empty
            if [[ -n "$LOG_STDOUT" ]]; then
                fail "Iteration ${i}: ${func} wrote to stdout: '${LOG_STDOUT}' (msg='${msg}')"
            fi

            # stderr MUST always have content
            if [[ -z "$LOG_STDERR" ]]; then
                fail "Iteration ${i}: ${func} produced no stderr output (msg='${msg}')"
            fi
        done
    done
}
