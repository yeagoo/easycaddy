#!/usr/bin/env bats
# ============================================================================
# test_prop_download_url.bats — Property 5: 下载 URL 构造正确性
# Feature: selfhosted-rpm-repo-builder, Property 5: 下载 URL 构造正确性
#
# For any 目标架构（x86_64 → amd64、aarch64 → arm64）和版本号组合，
# 构造的下载 URL 应为
# https://caddyserver.com/api/download?os=linux&arch={go_arch}&version={version}
#
# **Validates: Requirements 5.1, 5.2**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'
load '../test_helper/generators_repo'

# Source build-repo.sh for testing (without executing main)
source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

setup() {
    setup_test_env
    source_build_repo_script
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 5a: map_arch_to_go returns correct Go arch mapping (100 iterations)
# ============================================================================

@test "Property 5: map_arch_to_go maps x86_64→amd64 and aarch64→arm64 correctly (100 iterations)" {
    for i in $(seq 1 100); do
        # Randomly pick an arch
        if (( RANDOM % 2 == 0 )); then
            local arch="x86_64"
            local expected_go="amd64"
        else
            local arch="aarch64"
            local expected_go="arm64"
        fi

        local result
        result="$(map_arch_to_go "$arch")"

        if [[ "$result" != "$expected_go" ]]; then
            fail "Iteration ${i}: map_arch_to_go '${arch}' returned '${result}', expected '${expected_go}'"
        fi
    done
}

# ============================================================================
# Property 5b: build_download_url constructs correct URL format
# (100 iterations)
# ============================================================================

@test "Property 5: build_download_url constructs correct URL for random version and arch (100 iterations)" {
    for i in $(seq 1 100); do
        local version
        version="$(gen_caddy_version_number)"
        CADDY_VERSION="$version"

        # Randomly pick an arch
        if (( RANDOM % 2 == 0 )); then
            local arch="x86_64"
            local go_arch="amd64"
        else
            local arch="aarch64"
            local go_arch="arm64"
        fi

        local result
        result="$(build_download_url "$go_arch")"

        local expected="https://caddyserver.com/api/download?os=linux&arch=${go_arch}&version=${version}"

        if [[ "$result" != "$expected" ]]; then
            fail "Iteration ${i}: build_download_url '${go_arch}' with version '${version}' returned '${result}', expected '${expected}'"
        fi
    done
}

# ============================================================================
# Property 5c: end-to-end — map_arch_to_go + build_download_url produce
# correct URL for any system arch and version (100 iterations)
# ============================================================================

@test "Property 5: end-to-end arch mapping + URL construction (100 iterations)" {
    for i in $(seq 1 100); do
        local version
        version="$(gen_caddy_version_number)"
        CADDY_VERSION="$version"

        # Randomly pick a system arch
        local archs=(x86_64 aarch64)
        local arch="${archs[$(( RANDOM % 2 ))]}"

        local go_arch
        go_arch="$(map_arch_to_go "$arch")"

        local url
        url="$(build_download_url "$go_arch")"

        # Verify URL contains correct components
        if [[ "$url" != *"os=linux"* ]]; then
            fail "Iteration ${i}: URL missing 'os=linux': ${url}"
        fi
        if [[ "$url" != *"arch=${go_arch}"* ]]; then
            fail "Iteration ${i}: URL missing 'arch=${go_arch}': ${url}"
        fi
        if [[ "$url" != *"version=${version}"* ]]; then
            fail "Iteration ${i}: URL missing 'version=${version}': ${url}"
        fi
        if [[ "$url" != "https://caddyserver.com/api/download?"* ]]; then
            fail "Iteration ${i}: URL has wrong base: ${url}"
        fi
    done
}
