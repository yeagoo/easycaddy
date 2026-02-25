#!/usr/bin/env bats
# ============================================================================
# test_prop_dnf_repo.bats — Property 11: 自建 DNF 仓库配置文件正确性
# Feature: caddy-installer-china, Property 11: 自建 DNF 仓库配置文件正确性
#
# For any EPEL_VERSION、OS_ARCH_RAW 和 OPT_MIRROR 组合，生成的 .repo 文件应包含
# 正确的 baseurl（格式为 {mirror}/caddy/{epel_version}/{arch}/）、gpgcheck=1、
# 正确的 gpgkey URL。
#
# **Validates: Requirements 5.3, 5.6, 5.8**
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
# Property 11: 随机 EPEL_VERSION/OS_ARCH_RAW/OPT_MIRROR → .repo 文件内容正确 (100 iterations)
# ============================================================================

@test "Property 11: random EPEL_VERSION/OS_ARCH_RAW/OPT_MIRROR produce correct .repo content (100 iterations)" {
    for i in $(seq 1 100); do
        local base_url epel_version arch output

        base_url="$(gen_random_mirror_url)"
        epel_version="$(gen_random_epel_version)"
        arch="$(gen_supported_arch)"

        output="$(_generate_dnf_repo_content "$base_url" "$epel_version" "$arch")"

        # Verify output contains [caddy-selfhosted] section header
        if [[ "$output" != *"[caddy-selfhosted]"* ]]; then
            fail "Iteration ${i}: output missing [caddy-selfhosted], got: '${output}' (base_url=${base_url}, epel=${epel_version}, arch=${arch})"
        fi

        # Verify baseurl contains {base_url}/caddy/{epel_version}/{arch}/
        local expected_baseurl="baseurl=${base_url}/caddy/${epel_version}/${arch}/"
        if [[ "$output" != *"${expected_baseurl}"* ]]; then
            fail "Iteration ${i}: output missing expected baseurl '${expected_baseurl}', got: '${output}' (base_url=${base_url}, epel=${epel_version}, arch=${arch})"
        fi

        # Verify gpgcheck=1
        if [[ "$output" != *"gpgcheck=1"* ]]; then
            fail "Iteration ${i}: output missing gpgcheck=1, got: '${output}' (base_url=${base_url}, epel=${epel_version}, arch=${arch})"
        fi

        # Verify gpgkey contains {base_url}/caddy/gpg.key
        local expected_gpgkey="gpgkey=${base_url}/caddy/gpg.key"
        if [[ "$output" != *"${expected_gpgkey}"* ]]; then
            fail "Iteration ${i}: output missing expected gpgkey '${expected_gpgkey}', got: '${output}' (base_url=${base_url}, epel=${epel_version}, arch=${arch})"
        fi
    done
}
