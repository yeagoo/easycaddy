#!/usr/bin/env bats
# ============================================================================
# test_prop_arch_detect.bats — Property 3: 架构检测与映射正确性
# Feature: caddy-installer-china, Property 3: 架构检测与映射正确性
#
# For any uname -m 返回的架构字符串，detect_arch 函数应将 x86_64 映射到 amd64、
# aarch64 映射到 arm64，将 loongarch64 和 riscv64 标记为可选支持架构并继续，
# 对所有其他未知架构字符串返回退出码 2。
#
# **Validates: Requirements 1.9, 1.10, 1.11**
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
# Test 1: Random supported architectures → correct mapping and success
#          (100 iterations)
# ============================================================================

@test "Property 3.1: random supported archs (x86_64/aarch64) always map correctly and succeed (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        local arch
        arch="$(gen_supported_arch)"
        mock_uname_arch "$arch"

        detect_arch

        # Determine expected mapping
        local expected_arch
        case "$arch" in
            x86_64)   expected_arch="amd64" ;;
            aarch64)  expected_arch="arm64" ;;
        esac

        if [[ "$OS_ARCH" != "$expected_arch" ]]; then
            fail "Iteration ${i}: arch='${arch}' expected OS_ARCH='${expected_arch}' got='${OS_ARCH}'"
        fi

        if [[ "$OS_ARCH_RAW" != "$arch" ]]; then
            fail "Iteration ${i}: arch='${arch}' expected OS_ARCH_RAW='${arch}' got='${OS_ARCH_RAW}'"
        fi
    done
}

# ============================================================================
# Test 2: Random optional architectures → correct mapping and success
#          (100 iterations)
# ============================================================================

@test "Property 3.2: random optional archs (loongarch64/riscv64) always map correctly and succeed (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        local arch
        arch="$(gen_pick_one "${KNOWN_OPTIONAL_ARCHS[@]}")"
        mock_uname_arch "$arch"

        # Use run to capture stderr warning output without failing
        run detect_arch

        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: arch='${arch}' expected success (exit 0) got exit code ${status}"
        fi

        # Verify warning was emitted
        if [[ "$output" != *"可选支持架构"* ]]; then
            fail "Iteration ${i}: arch='${arch}' expected warning about optional support, got output='${output}'"
        fi

        # Also verify the globals are set correctly by calling without run
        reset_script_globals
        mock_uname_arch "$arch"
        detect_arch

        if [[ "$OS_ARCH" != "$arch" ]]; then
            fail "Iteration ${i}: arch='${arch}' expected OS_ARCH='${arch}' got='${OS_ARCH}'"
        fi

        if [[ "$OS_ARCH_RAW" != "$arch" ]]; then
            fail "Iteration ${i}: arch='${arch}' expected OS_ARCH_RAW='${arch}' got='${OS_ARCH_RAW}'"
        fi
    done
}

# ============================================================================
# Test 3: Random unknown architectures → always exit code 2
#          (100 iterations)
# ============================================================================

@test "Property 3.3: random unknown archs always exit with code 2 (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        local arch
        arch="$(gen_unknown_arch)"
        mock_uname_arch "$arch"

        run detect_arch

        if [[ "$status" -ne 2 ]]; then
            fail "Iteration ${i}: arch='${arch}' expected exit code 2 got=${status}"
        fi

        if [[ "$output" != *"不支持的 CPU 架构"* ]]; then
            fail "Iteration ${i}: arch='${arch}' expected error message about unsupported arch, got output='${output}'"
        fi
    done
}

# ============================================================================
# Test 4: Mixed random architectures from all categories → correct behavior
#          (100 iterations)
# ============================================================================

@test "Property 3.4: mixed random archs from all categories produce correct behavior (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        local arch
        arch="$(gen_random_arch)"
        mock_uname_arch "$arch"

        run detect_arch

        case "$arch" in
            x86_64)
                if [[ "$status" -ne 0 ]]; then
                    fail "Iteration ${i}: arch='${arch}' expected success got exit code ${status}"
                fi
                ;;
            aarch64)
                if [[ "$status" -ne 0 ]]; then
                    fail "Iteration ${i}: arch='${arch}' expected success got exit code ${status}"
                fi
                ;;
            loongarch64|riscv64)
                if [[ "$status" -ne 0 ]]; then
                    fail "Iteration ${i}: arch='${arch}' expected success (optional) got exit code ${status}"
                fi
                if [[ "$output" != *"可选支持架构"* ]]; then
                    fail "Iteration ${i}: arch='${arch}' expected optional support warning"
                fi
                ;;
            *)
                if [[ "$status" -ne 2 ]]; then
                    fail "Iteration ${i}: arch='${arch}' expected exit code 2 got=${status}"
                fi
                if [[ "$output" != *"不支持的 CPU 架构"* ]]; then
                    fail "Iteration ${i}: arch='${arch}' expected unsupported arch error"
                fi
                ;;
        esac
    done
}
