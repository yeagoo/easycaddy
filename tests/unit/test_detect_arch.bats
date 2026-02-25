#!/usr/bin/env bats
# ============================================================================
# test_detect_arch.bats — 架构检测单元测试
# 测试 detect_arch 各架构映射、loongarch64/riscv64 可选支持、未知架构拒绝
# 验证需求: 1.9, 1.10, 1.11
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
# detect_arch: 必须支持的架构映射（需求 1.9）
# ============================================================================

@test "detect_arch: x86_64 maps to amd64" {
    mock_uname_arch x86_64
    detect_arch
    [[ "$OS_ARCH" == "amd64" ]]
    [[ "$OS_ARCH_RAW" == "x86_64" ]]
}

@test "detect_arch: aarch64 maps to arm64" {
    mock_uname_arch aarch64
    detect_arch
    [[ "$OS_ARCH" == "arm64" ]]
    [[ "$OS_ARCH_RAW" == "aarch64" ]]
}

# ============================================================================
# detect_arch: 可选支持架构（需求 1.10）
# ============================================================================

@test "detect_arch: loongarch64 is optional supported" {
    mock_uname_arch loongarch64
    detect_arch
    [[ "$OS_ARCH" == "loongarch64" ]]
    [[ "$OS_ARCH_RAW" == "loongarch64" ]]
}

@test "detect_arch: loongarch64 outputs warning to stderr" {
    mock_uname_arch loongarch64
    run detect_arch
    assert_success
    assert_output --partial "可选支持架构"
}

@test "detect_arch: riscv64 is optional supported" {
    mock_uname_arch riscv64
    detect_arch
    [[ "$OS_ARCH" == "riscv64" ]]
    [[ "$OS_ARCH_RAW" == "riscv64" ]]
}

@test "detect_arch: riscv64 outputs warning to stderr" {
    mock_uname_arch riscv64
    run detect_arch
    assert_success
    assert_output --partial "可选支持架构"
}

# ============================================================================
# detect_arch: 未知架构拒绝（需求 1.11）
# ============================================================================

@test "detect_arch: unknown arch mips64 exits with code 2" {
    mock_uname_arch mips64
    run detect_arch
    assert_failure
    [[ "$status" -eq 2 ]]
}

@test "detect_arch: unknown arch s390x exits with code 2" {
    mock_uname_arch s390x
    run detect_arch
    assert_failure
    [[ "$status" -eq 2 ]]
}

@test "detect_arch: unknown arch ppc64le exits with code 2" {
    mock_uname_arch ppc64le
    run detect_arch
    assert_failure
    [[ "$status" -eq 2 ]]
}

@test "detect_arch: unknown arch armv7l exits with code 2" {
    mock_uname_arch armv7l
    run detect_arch
    assert_failure
    [[ "$status" -eq 2 ]]
}

@test "detect_arch: unknown arch i686 exits with code 2" {
    mock_uname_arch i686
    run detect_arch
    assert_failure
    [[ "$status" -eq 2 ]]
}

@test "detect_arch: unknown arch outputs error message" {
    mock_uname_arch sparc64
    run detect_arch
    assert_failure
    assert_output --partial "不支持的 CPU 架构"
}
