#!/usr/bin/env bats
# ============================================================================
# test_prop_symlinks.bats — Property 13: 符号链接生成正确性
# Feature: selfhosted-rpm-repo-builder, Property 13: 符号链接生成正确性
#
# For any Product_Line_Map 中的 distro_id:version 条目，应在
# {output_dir}/caddy/{distro_id}/{version}/ 创建符号链接，指向对应产品线目录；
# 符号链接应使用相对路径；符号链接目标应为有效目录。
#
# **Validates: Requirements 11.1, 11.2, 11.3, 11.4**
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

# Create all product line directories under STAGING_DIR/caddy/
create_all_product_line_dirs() {
    local caddy_dir="${STAGING_DIR}/caddy"
    mkdir -p "${caddy_dir}/el8"
    mkdir -p "${caddy_dir}/el9"
    mkdir -p "${caddy_dir}/el10"
    mkdir -p "${caddy_dir}/al2023"
    mkdir -p "${caddy_dir}/fedora"
    mkdir -p "${caddy_dir}/openeuler/22"
    mkdir -p "${caddy_dir}/openeuler/24"
}

# Map product line ID to its expected directory path
get_expected_pl_path() {
    case "$1" in
        el8)    echo "el8" ;;
        el9)    echo "el9" ;;
        el10)   echo "el10" ;;
        al2023) echo "al2023" ;;
        fedora) echo "fedora" ;;
        oe22)   echo "openeuler/22" ;;
        oe24)   echo "openeuler/24" ;;
    esac
}

setup() {
    setup_test_env
    source_build_repo_script
    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"
    SYMLINK_COUNT=0
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 13: symlink generation correctness (100 iterations)
# ============================================================================

@test "Property 13: random distro:version symlink is correct or skipped for fedora (100 iterations)" {
    for i in $(seq 1 100); do
        # Clean up staging dir for each iteration
        rm -rf "${STAGING_DIR:?}"/*
        SYMLINK_COUNT=0

        # Randomly pick a distro:version
        local dv
        dv="${KNOWN_DISTRO_VERSIONS[$(( RANDOM % ${#KNOWN_DISTRO_VERSIONS[@]} ))]}"
        local distro_id="${dv%%:*}"
        local version="${dv#*:}"

        # Look up expected product line
        local expected_pl="${EXPECTED_DISTRO_PL_MAP[$dv]}"
        local expected_pl_path
        expected_pl_path="$(get_expected_pl_path "$expected_pl")"

        # Create all product line directories so symlinks can resolve
        create_all_product_line_dirs

        # Call generate_symlinks
        generate_symlinks 2>/dev/null

        local caddy_dir="${STAGING_DIR}/caddy"
        local symlink_path="${caddy_dir}/${distro_id}/${version}"

        if [[ "$expected_pl" == "fedora" ]]; then
            # Fedora entries should NOT have version symlinks
            if [[ -L "$symlink_path" ]]; then
                fail "Iteration ${i}: fedora entry '${dv}' should NOT have symlink at ${symlink_path}"
            fi
        else
            # Non-fedora: symlink should exist
            if [[ ! -L "$symlink_path" ]]; then
                fail "Iteration ${i}: symlink missing at ${symlink_path} for '${dv}'"
            fi

            # Symlink should use relative path starting with ..
            local link_target
            link_target="$(readlink "$symlink_path")"
            if [[ "$link_target" != ../* ]]; then
                fail "Iteration ${i}: symlink '${symlink_path}' target '${link_target}' does not start with '../' (not relative)"
            fi

            # Symlink should point to the correct product line path
            if [[ "$link_target" != "../${expected_pl_path}" ]]; then
                fail "Iteration ${i}: symlink '${symlink_path}' points to '${link_target}', expected '../${expected_pl_path}'"
            fi

            # Symlink should resolve to a valid directory
            if [[ ! -d "$symlink_path" ]]; then
                fail "Iteration ${i}: symlink '${symlink_path}' does not resolve to a valid directory"
            fi
        fi
    done
}
