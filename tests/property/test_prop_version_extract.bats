#!/usr/bin/env bats
# ============================================================================
# test_prop_version_extract.bats — Property 20: 版本号提取正确性
# Feature: selfhosted-rpm-repo-builder, Property 20: 版本号提取正确性
#
# For any GitHub API 返回的 tag_name 字符串（格式为 vX.Y.Z），
# 版本提取逻辑应正确去除 v 前缀，返回 X.Y.Z。
#
# **Validates: Requirements 14.2**
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
# Property 20a: v-prefixed version strings have v stripped (100 iterations)
# ============================================================================

@test "Property 20: extract_version_from_tag strips v prefix from vX.Y.Z (100 iterations)" {
    for i in $(seq 1 100); do
        local version
        version="$(gen_caddy_version_number)"
        local tag="v${version}"

        local result
        result="$(extract_version_from_tag "$tag")"

        if [[ "$result" != "$version" ]]; then
            fail "Iteration ${i}: extract_version_from_tag '${tag}' returned '${result}', expected '${version}'"
        fi
    done
}

# ============================================================================
# Property 20b: version strings without v prefix pass through unchanged (100 iterations)
# ============================================================================

@test "Property 20: extract_version_from_tag passes through non-v-prefixed versions unchanged (100 iterations)" {
    for i in $(seq 1 100); do
        local version
        version="$(gen_caddy_version_number)"

        local result
        result="$(extract_version_from_tag "$version")"

        if [[ "$result" != "$version" ]]; then
            fail "Iteration ${i}: extract_version_from_tag '${version}' returned '${result}', expected '${version}'"
        fi
    done
}
