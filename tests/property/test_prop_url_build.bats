#!/usr/bin/env bats
# ============================================================================
# test_prop_url_build.bats — Property 9: 二进制下载 URL 构造正确性
# Feature: caddy-installer-china, Property 9: 二进制下载 URL 构造正确性
#
# For any OS_ARCH 和 OPT_VERSION 组合，_build_download_url 构造的下载 URL 应包含
# 正确的 os=linux 和 arch={OS_ARCH} 参数，当 OPT_VERSION 非空时还应包含
# version={OPT_VERSION} 参数。
#
# **Validates: Requirements 6.2, 6.3, 6.4**
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
# Property 9: 随机 OS_ARCH/OPT_VERSION → URL 格式正确 (100 iterations)
# ============================================================================

@test "Property 9: random OS_ARCH/OPT_VERSION combinations produce correct download URL (100 iterations)" {
    local arch_choices=(amd64 arm64 loongarch64 riscv64)

    for i in $(seq 1 100); do
        reset_script_globals

        # Pick a random OS_ARCH from the valid set
        local arch
        arch="$(gen_pick_one "${arch_choices[@]}")"
        OS_ARCH="$arch"

        # Randomly decide whether OPT_VERSION is empty or a version string
        local version=""
        if (( RANDOM % 2 == 0 )); then
            version="$(gen_caddy_version)"
        fi
        OPT_VERSION="$version"

        # Call _build_download_url
        run _build_download_url

        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: _build_download_url failed with exit code ${status} (OS_ARCH='${arch}', OPT_VERSION='${version}')"
        fi

        local url="$output"

        # 1. URL starts with the correct base
        if [[ "$url" != "https://caddyserver.com/api/download?"* ]]; then
            fail "Iteration ${i}: URL does not start with expected base. Got: '${url}' (OS_ARCH='${arch}', OPT_VERSION='${version}')"
        fi

        # 2. URL contains os=linux
        if [[ "$url" != *"os=linux"* ]]; then
            fail "Iteration ${i}: URL missing 'os=linux'. Got: '${url}' (OS_ARCH='${arch}', OPT_VERSION='${version}')"
        fi

        # 3. URL contains arch={OS_ARCH}
        if [[ "$url" != *"arch=${arch}"* ]]; then
            fail "Iteration ${i}: URL missing 'arch=${arch}'. Got: '${url}' (OS_ARCH='${arch}', OPT_VERSION='${version}')"
        fi

        # 4. When OPT_VERSION non-empty: URL contains version={OPT_VERSION}
        if [[ -n "$version" ]]; then
            if [[ "$url" != *"version=${version}"* ]]; then
                fail "Iteration ${i}: URL missing 'version=${version}'. Got: '${url}' (OS_ARCH='${arch}', OPT_VERSION='${version}')"
            fi
        fi

        # 5. When OPT_VERSION empty: URL does NOT contain "version="
        if [[ -z "$version" ]]; then
            if [[ "$url" == *"version="* ]]; then
                fail "Iteration ${i}: URL should not contain 'version=' when OPT_VERSION is empty. Got: '${url}' (OS_ARCH='${arch}')"
            fi
        fi
    done
}
