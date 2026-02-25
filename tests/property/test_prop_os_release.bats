#!/usr/bin/env bats
# ============================================================================
# test_prop_os_release.bats — Property 1: os-release 字段提取正确性
# Feature: caddy-installer-china, Property 1: os-release 字段提取正确性
#
# For any 包含 ID、ID_LIKE、VERSION_ID、NAME、PLATFORM_ID 字段的
# /etc/os-release 文件内容，detect_os 函数解析后设置的全局变量值应与文件中
# 对应字段的值完全一致。
#
# **Validates: Requirements 1.1**
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
# Property 1: os-release 字段提取正确性 (100 iterations)
# ============================================================================

@test "Property 1: detect_os extracts all os-release fields correctly for random inputs (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset globals before each iteration
        reset_script_globals

        # Generate random values for each field
        local rand_id rand_version rand_id_like rand_name rand_platform_id
        rand_id="$(gen_known_os_id)"
        rand_version="$(gen_random_version)"
        rand_id_like="$(gen_random_id_like)"
        rand_name="$(gen_random_os_name)"
        rand_platform_id="$(gen_random_platform_id)"

        # Create mock os-release file with generated values
        local os_file
        os_file="$(create_mock_os_release "$rand_id" "$rand_version" "$rand_id_like" "$rand_name" "$rand_platform_id")"

        # Call detect_os with the mock file
        OS_RELEASE_FILE="$os_file" detect_os

        # Verify each global variable matches the generated value
        if [[ "$OS_ID" != "$rand_id" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' expected='${rand_id}'"
        fi
        if [[ "$OS_VERSION_ID" != "$rand_version" ]]; then
            fail "Iteration ${i}: OS_VERSION_ID='${OS_VERSION_ID}' expected='${rand_version}'"
        fi
        if [[ "$OS_ID_LIKE" != "$rand_id_like" ]]; then
            fail "Iteration ${i}: OS_ID_LIKE='${OS_ID_LIKE}' expected='${rand_id_like}'"
        fi
        if [[ "$OS_NAME" != "$rand_name" ]]; then
            fail "Iteration ${i}: OS_NAME='${OS_NAME}' expected='${rand_name}'"
        fi
        if [[ "$OS_PLATFORM_ID" != "$rand_platform_id" ]]; then
            fail "Iteration ${i}: OS_PLATFORM_ID='${OS_PLATFORM_ID}' expected='${rand_platform_id}'"
        fi
    done
}
