#!/usr/bin/env bats
# ============================================================================
# test_prop_apt_source.bats — Property 10: APT 源文件内容正确性
# Feature: caddy-installer-china, Property 10: APT 源文件内容正确性
#
# For any 镜像地址配置（默认或 --mirror 指定），生成的 APT 源文件内容应包含
# 正确的 signed-by 密钥路径、正确的仓库 URL、any-version 作为 distribution、
# main 作为 component。
#
# **Validates: Requirements 3.4**
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
# Property 10: 随机镜像地址 → APT 源文件内容格式正确 (100 iterations)
# ============================================================================

@test "Property 10: random mirror URLs produce correctly formatted APT source lines (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        local mirror_url
        mirror_url="$(gen_random_mirror_url)"
        OPT_MIRROR="$mirror_url"

        local output
        output="$(_generate_apt_source_line)"

        # Verify output starts with "deb "
        if [[ "$output" != deb\ * ]]; then
            fail "Iteration ${i}: output does not start with 'deb ', got: '${output}' (mirror=${mirror_url})"
        fi

        # Verify output contains signed-by keyring path
        if [[ "$output" != *"signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg"* ]]; then
            fail "Iteration ${i}: output missing signed-by keyring path, got: '${output}' (mirror=${mirror_url})"
        fi

        # Verify output contains the mirror URL + /deb/debian
        local expected_repo_url="${mirror_url}/deb/debian"
        if [[ "$output" != *"${expected_repo_url}"* ]]; then
            fail "Iteration ${i}: output missing expected repo URL '${expected_repo_url}', got: '${output}' (mirror=${mirror_url})"
        fi

        # Verify output contains "any-version main"
        if [[ "$output" != *"any-version main"* ]]; then
            fail "Iteration ${i}: output missing 'any-version main', got: '${output}' (mirror=${mirror_url})"
        fi
    done
}

# ============================================================================
# Property 10: 空 OPT_MIRROR → 使用默认 Cloudsmith URL
# ============================================================================

@test "Property 10: empty OPT_MIRROR uses default Cloudsmith URL" {
    reset_script_globals
    OPT_MIRROR=""

    local output
    output="$(_generate_apt_source_line)"

    local default_url="https://dl.cloudsmith.io/public/caddy/stable/deb/debian"

    # Verify output starts with "deb "
    if [[ "$output" != deb\ * ]]; then
        fail "output does not start with 'deb ', got: '${output}'"
    fi

    # Verify output contains signed-by keyring path
    if [[ "$output" != *"signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg"* ]]; then
        fail "output missing signed-by keyring path, got: '${output}'"
    fi

    # Verify output contains the default Cloudsmith URL
    if [[ "$output" != *"${default_url}"* ]]; then
        fail "output missing default Cloudsmith URL, got: '${output}'"
    fi

    # Verify output contains "any-version main"
    if [[ "$output" != *"any-version main"* ]]; then
        fail "output missing 'any-version main', got: '${output}'"
    fi
}
