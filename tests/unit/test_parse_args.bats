#!/usr/bin/env bats
# ============================================================================
# test_parse_args.bats — 参数解析单元测试
# 测试 parse_args 各参数正确解析、未知参数拒绝、--help 输出、--method 值验证
# 验证需求: 7.1, 7.11
# ============================================================================

# 加载 bats 辅助库
load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# 默认值测试（无参数）
# ============================================================================

@test "parse_args: no arguments sets default values" {
    parse_args
    [[ "$OPT_VERSION" == "" ]]
    [[ "$OPT_METHOD" == "" ]]
    [[ "$OPT_PREFIX" == "/usr/local/bin" ]]
    [[ "$OPT_MIRROR" == "" ]]
    [[ "$OPT_SKIP_SERVICE" == "false" ]]
    [[ "$OPT_SKIP_CAP" == "false" ]]
    [[ "$OPT_YES" == "false" ]]
}

# ============================================================================
# 各参数正确解析
# ============================================================================

@test "parse_args: --version sets OPT_VERSION" {
    parse_args --version 2.7.6
    [[ "$OPT_VERSION" == "2.7.6" ]]
}

@test "parse_args: --method repo sets OPT_METHOD" {
    parse_args --method repo
    [[ "$OPT_METHOD" == "repo" ]]
}

@test "parse_args: --method binary sets OPT_METHOD" {
    parse_args --method binary
    [[ "$OPT_METHOD" == "binary" ]]
}

@test "parse_args: --prefix sets OPT_PREFIX" {
    parse_args --prefix /opt/bin
    [[ "$OPT_PREFIX" == "/opt/bin" ]]
}

@test "parse_args: --mirror sets OPT_MIRROR" {
    parse_args --mirror https://mirror.example.com
    [[ "$OPT_MIRROR" == "https://mirror.example.com" ]]
}

@test "parse_args: --skip-service sets OPT_SKIP_SERVICE=true" {
    parse_args --skip-service
    [[ "$OPT_SKIP_SERVICE" == "true" ]]
}

@test "parse_args: --skip-cap sets OPT_SKIP_CAP=true" {
    parse_args --skip-cap
    [[ "$OPT_SKIP_CAP" == "true" ]]
}

@test "parse_args: -y sets OPT_YES=true" {
    parse_args -y
    [[ "$OPT_YES" == "true" ]]
}

@test "parse_args: --yes sets OPT_YES=true" {
    parse_args --yes
    [[ "$OPT_YES" == "true" ]]
}

# ============================================================================
# 多参数组合
# ============================================================================

@test "parse_args: multiple parameters combined" {
    parse_args --version 2.8.0 --method binary --prefix /opt/caddy --mirror https://m.example.com --skip-service --skip-cap --yes
    [[ "$OPT_VERSION" == "2.8.0" ]]
    [[ "$OPT_METHOD" == "binary" ]]
    [[ "$OPT_PREFIX" == "/opt/caddy" ]]
    [[ "$OPT_MIRROR" == "https://m.example.com" ]]
    [[ "$OPT_SKIP_SERVICE" == "true" ]]
    [[ "$OPT_SKIP_CAP" == "true" ]]
    [[ "$OPT_YES" == "true" ]]
}

# ============================================================================
# 未知参数拒绝（退出码 1）
# ============================================================================

@test "parse_args: unknown parameter exits with code 1" {
    run parse_args --unknown-flag
    assert_failure
    [[ "$status" -eq 1 ]]
}

@test "parse_args: unknown parameter outputs error to stderr" {
    run parse_args --bogus
    assert_failure
    assert_output --partial "未知参数"
}

# ============================================================================
# --method 值验证
# ============================================================================

@test "parse_args: --method with invalid value exits with code 1" {
    run parse_args --method invalid
    assert_failure
    [[ "$status" -eq 1 ]]
}

@test "parse_args: --method with invalid value outputs error" {
    run parse_args --method foobar
    assert_failure
    assert_output --partial "仅允许"
}

# ============================================================================
# --help 输出（退出码 0）
# ============================================================================

@test "parse_args: -h exits with code 0" {
    run parse_args -h
    assert_success
}

@test "parse_args: --help exits with code 0" {
    run parse_args --help
    assert_success
}

@test "parse_args: --help outputs help text" {
    run parse_args --help
    assert_success
    assert_output --partial "用法"
    assert_output --partial "--version"
    assert_output --partial "--method"
}
