#!/usr/bin/env bats
# ============================================================================
# test_log_functions.bats — 日志函数单元测试
# 测试 util_log_info、util_log_success、util_log_warn、util_log_error
# 验证 stderr 输出、颜色控制
# 验证需求: 10.7, 10.8, 10.9
# ============================================================================

# 加载 bats 辅助库
load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'

setup() {
    setup_test_env
    source_install_script
}

teardown() {
    teardown_test_env
}

# Helper: capture stderr from a log function call
# Usage: capture_stderr util_log_info "message"
capture_stderr() {
    "$@" 2>"${TEST_TEMP_DIR}/stderr.out" 1>"${TEST_TEMP_DIR}/stdout.out"
}

get_stderr() {
    cat "${TEST_TEMP_DIR}/stderr.out"
}

get_stdout() {
    cat "${TEST_TEMP_DIR}/stdout.out"
}

# ============================================================================
# util_log_info 测试
# ============================================================================

@test "util_log_info: outputs to stderr, not stdout" {
    capture_stderr util_log_info "test message"
    local stdout_content
    stdout_content="$(get_stdout)"
    [[ -z "$stdout_content" ]]
}

@test "util_log_info: message appears on stderr" {
    capture_stderr util_log_info "hello world"
    local stderr_content
    stderr_content="$(get_stderr)"
    [[ "$stderr_content" == *"[INFO]"* ]]
    [[ "$stderr_content" == *"hello world"* ]]
}

@test "util_log_info: with color enabled, includes blue ANSI code" {
    USE_COLOR=true
    capture_stderr util_log_info "color test"
    local stderr_content
    stderr_content="$(get_stderr)"
    # Blue: \033[0;34m
    [[ "$stderr_content" == *$'\033[0;34m'* ]]
}

@test "util_log_info: with color enabled, includes reset ANSI code" {
    USE_COLOR=true
    capture_stderr util_log_info "color test"
    local stderr_content
    stderr_content="$(get_stderr)"
    # Reset: \033[0m
    [[ "$stderr_content" == *$'\033[0m'* ]]
}

@test "util_log_info: with color disabled, no ANSI escape sequences" {
    USE_COLOR=false
    capture_stderr util_log_info "no color test"
    local stderr_content
    stderr_content="$(get_stderr)"
    # Should not contain ESC character
    [[ "$stderr_content" != *$'\033'* ]]
    [[ "$stderr_content" == *"[INFO] no color test"* ]]
}

# ============================================================================
# util_log_success 测试
# ============================================================================

@test "util_log_success: outputs to stderr, not stdout" {
    capture_stderr util_log_success "test message"
    local stdout_content
    stdout_content="$(get_stdout)"
    [[ -z "$stdout_content" ]]
}

@test "util_log_success: message appears on stderr" {
    capture_stderr util_log_success "done"
    local stderr_content
    stderr_content="$(get_stderr)"
    [[ "$stderr_content" == *"[OK]"* ]]
    [[ "$stderr_content" == *"done"* ]]
}

@test "util_log_success: with color enabled, includes green ANSI code" {
    USE_COLOR=true
    capture_stderr util_log_success "green test"
    local stderr_content
    stderr_content="$(get_stderr)"
    # Green: \033[0;32m
    [[ "$stderr_content" == *$'\033[0;32m'* ]]
}

@test "util_log_success: with color disabled, no ANSI escape sequences" {
    USE_COLOR=false
    capture_stderr util_log_success "plain test"
    local stderr_content
    stderr_content="$(get_stderr)"
    [[ "$stderr_content" != *$'\033'* ]]
    [[ "$stderr_content" == *"[OK] plain test"* ]]
}

# ============================================================================
# util_log_warn 测试
# ============================================================================

@test "util_log_warn: outputs to stderr, not stdout" {
    capture_stderr util_log_warn "test message"
    local stdout_content
    stdout_content="$(get_stdout)"
    [[ -z "$stdout_content" ]]
}

@test "util_log_warn: message appears on stderr" {
    capture_stderr util_log_warn "caution"
    local stderr_content
    stderr_content="$(get_stderr)"
    [[ "$stderr_content" == *"[WARN]"* ]]
    [[ "$stderr_content" == *"caution"* ]]
}

@test "util_log_warn: with color enabled, includes yellow ANSI code" {
    USE_COLOR=true
    capture_stderr util_log_warn "yellow test"
    local stderr_content
    stderr_content="$(get_stderr)"
    # Yellow: \033[0;33m
    [[ "$stderr_content" == *$'\033[0;33m'* ]]
}

@test "util_log_warn: with color disabled, no ANSI escape sequences" {
    USE_COLOR=false
    capture_stderr util_log_warn "plain warn"
    local stderr_content
    stderr_content="$(get_stderr)"
    [[ "$stderr_content" != *$'\033'* ]]
    [[ "$stderr_content" == *"[WARN] plain warn"* ]]
}

# ============================================================================
# util_log_error 测试
# ============================================================================

@test "util_log_error: outputs to stderr, not stdout" {
    capture_stderr util_log_error "test message"
    local stdout_content
    stdout_content="$(get_stdout)"
    [[ -z "$stdout_content" ]]
}

@test "util_log_error: message appears on stderr" {
    capture_stderr util_log_error "failure"
    local stderr_content
    stderr_content="$(get_stderr)"
    [[ "$stderr_content" == *"[ERROR]"* ]]
    [[ "$stderr_content" == *"failure"* ]]
}

@test "util_log_error: with color enabled, includes red ANSI code" {
    USE_COLOR=true
    capture_stderr util_log_error "red test"
    local stderr_content
    stderr_content="$(get_stderr)"
    # Red: \033[0;31m
    [[ "$stderr_content" == *$'\033[0;31m'* ]]
}

@test "util_log_error: with color disabled, no ANSI escape sequences" {
    USE_COLOR=false
    capture_stderr util_log_error "plain error"
    local stderr_content
    stderr_content="$(get_stderr)"
    [[ "$stderr_content" != *$'\033'* ]]
    [[ "$stderr_content" == *"[ERROR] plain error"* ]]
}

# ============================================================================
# 颜色代码正确性交叉验证
# ============================================================================

@test "each log level uses distinct color codes" {
    USE_COLOR=true

    capture_stderr util_log_info "msg"
    local info_out
    info_out="$(get_stderr)"

    capture_stderr util_log_success "msg"
    local success_out
    success_out="$(get_stderr)"

    capture_stderr util_log_warn "msg"
    local warn_out
    warn_out="$(get_stderr)"

    capture_stderr util_log_error "msg"
    local error_out
    error_out="$(get_stderr)"

    # info=blue(34), success=green(32), warn=yellow(33), error=red(31)
    [[ "$info_out" == *"[0;34m"* ]]
    [[ "$success_out" == *"[0;32m"* ]]
    [[ "$warn_out" == *"[0;33m"* ]]
    [[ "$error_out" == *"[0;31m"* ]]
}
