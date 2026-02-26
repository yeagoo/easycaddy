#!/usr/bin/env bats
# ============================================================================
# test_prop_repo_template.bats — Property 14: .repo 模板生成正确性
# Feature: selfhosted-rpm-repo-builder, Property 14: .repo 模板生成正确性
#
# For any distro_id:version 和 base_url 组合，生成的 .repo 模板文件应：
# - 命名为 caddy-{distro_id}-{version}.repo
# - baseurl 使用发行版友好路径格式 {base_url}/caddy/{distro_id}/{version}/$basearch/
# - 包含 gpgcheck=1、repo_gpgcheck=1 和正确的 gpgkey URL
# - Fedora: baseurl 为 {base_url}/caddy/fedora/$basearch/（不含版本号）
#
# **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'
load '../test_helper/generators_repo'

source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

setup() {
    setup_test_env
    source_build_repo_script
    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 14: .repo template generation correctness (100 iterations)
# ============================================================================

@test "Property 14: .repo template is correct for random distro:version and base_url (100 iterations)" {
    for i in $(seq 1 100); do
        # Clean up staging dir for each iteration
        rm -rf "${STAGING_DIR:?}"/*

        # Randomly pick a distro:version and base_url
        local dv
        dv="${KNOWN_DISTRO_VERSIONS[$(( RANDOM % ${#KNOWN_DISTRO_VERSIONS[@]} ))]}"
        local distro_id="${dv%%:*}"
        local version="${dv#*:}"

        local base_url
        base_url="$(gen_base_url)"

        # Set OPT_BASE_URL and call generate_repo_templates
        OPT_BASE_URL="$base_url"
        generate_repo_templates 2>/dev/null

        # Verify .repo file exists with correct name
        local repo_file="${STAGING_DIR}/caddy/templates/caddy-${distro_id}-${version}.repo"
        if [[ ! -f "$repo_file" ]]; then
            fail "Iteration ${i}: .repo file missing at ${repo_file} for '${dv}' with base_url='${base_url}'"
        fi

        local content
        content="$(cat "$repo_file")"

        # Verify gpgcheck=1
        if ! echo "$content" | grep -q '^gpgcheck=1$'; then
            fail "Iteration ${i}: .repo file for '${dv}' missing gpgcheck=1"
        fi

        # Verify repo_gpgcheck=1
        if ! echo "$content" | grep -q '^repo_gpgcheck=1$'; then
            fail "Iteration ${i}: .repo file for '${dv}' missing repo_gpgcheck=1"
        fi

        # Verify gpgkey URL
        if ! echo "$content" | grep -q "^gpgkey=${base_url}/caddy/gpg\\.key\$"; then
            fail "Iteration ${i}: .repo file for '${dv}' missing correct gpgkey. Expected: gpgkey=${base_url}/caddy/gpg.key"
        fi

        # Verify baseurl based on distro type
        if [[ "$distro_id" == "fedora" ]]; then
            # Fedora: baseurl without version number
            local expected_baseurl="${base_url}/caddy/fedora/\$basearch/"
            if ! echo "$content" | grep -q "^baseurl=${base_url}/caddy/fedora/\\\$basearch/\$"; then
                local actual_baseurl
                actual_baseurl="$(echo "$content" | grep '^baseurl=')"
                fail "Iteration ${i}: Fedora .repo baseurl incorrect. Expected: baseurl=${expected_baseurl}, Got: ${actual_baseurl}"
            fi
        else
            # Non-Fedora: baseurl with distro_id/version
            local expected_baseurl="${base_url}/caddy/${distro_id}/${version}/\$basearch/"
            if ! echo "$content" | grep -q "^baseurl=${base_url}/caddy/${distro_id}/${version}/\\\$basearch/\$"; then
                local actual_baseurl
                actual_baseurl="$(echo "$content" | grep '^baseurl=')"
                fail "Iteration ${i}: .repo baseurl incorrect for '${dv}'. Expected: baseurl=${expected_baseurl}, Got: ${actual_baseurl}"
            fi
        fi
    done
}
