#!/usr/bin/env bats
# ============================================================================
# test_prop_compress.bats — Property 10: 压缩算法映射正确性
# Feature: selfhosted-rpm-repo-builder, Property 10: 压缩算法映射正确性
#
# For any 产品线 ID，get_compress_type 应返回正确的压缩算法：
# EL8 返回 xz，EL9/EL10/AL2023/Fedora/openEuler 22/openEuler 24 返回 zstd。
#
# 同时验证 generate_nfpm_config 生成的配置中 compression 字段与产品线匹配。
#
# **Validates: Requirements 6.9**
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

# Return the expected compression algorithm for a given product line ID
get_expected_compress() {
    local pl_id="$1"
    case "$pl_id" in
        el8)    echo "xz" ;;
        el9)    echo "zstd" ;;
        el10)   echo "zstd" ;;
        al2023) echo "zstd" ;;
        fedora) echo "zstd" ;;
        oe22)   echo "zstd" ;;
        oe24)   echo "zstd" ;;
    esac
}

setup() {
    setup_test_env
    source_build_repo_script

    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"

    # Create fake binary files for both architectures
    mkdir -p "${TEST_TEMP_DIR}/bin"
    echo "fake-binary" > "${TEST_TEMP_DIR}/bin/caddy-x86_64"
    echo "fake-binary" > "${TEST_TEMP_DIR}/bin/caddy-aarch64"
    DOWNLOADED_ARCHS=([x86_64]="${TEST_TEMP_DIR}/bin/caddy-x86_64" [aarch64]="${TEST_TEMP_DIR}/bin/caddy-aarch64")
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 10: compression algorithm mapping correctness (100 iterations)
# ============================================================================

@test "Property 10: get_compress_type returns correct algorithm (100 iterations)" {
    for i in $(seq 1 100); do
        # Pick a random product line
        local pl_id
        pl_id="${KNOWN_PRODUCT_LINES[$(( RANDOM % ${#KNOWN_PRODUCT_LINES[@]} ))]}"

        local expected
        expected="$(get_expected_compress "$pl_id")"

        local actual
        actual="$(get_compress_type "$pl_id")"

        if [[ "$actual" != "$expected" ]]; then
            fail "Iteration ${i}: get_compress_type('${pl_id}') returned '${actual}', expected '${expected}'"
        fi
    done
}

@test "Property 10: nfpm config compression field matches product line (100 iterations)" {
    for i in $(seq 1 100); do
        # Pick a random product line
        local pl_id
        pl_id="${KNOWN_PRODUCT_LINES[$(( RANDOM % ${#KNOWN_PRODUCT_LINES[@]} ))]}"

        # Pick a random architecture
        local arch
        case $(( RANDOM % 2 )) in
            0) arch="x86_64" ;;
            1) arch="aarch64" ;;
        esac

        # Generate random version
        CADDY_VERSION="$(gen_caddy_version_number)"

        local expected
        expected="$(get_expected_compress "$pl_id")"

        # Generate nfpm config
        local config_file
        config_file="$(generate_nfpm_config "$pl_id" "$arch")"

        if [[ ! -f "$config_file" ]]; then
            fail "Iteration ${i}: config file not created (pl=${pl_id}, arch=${arch})"
        fi

        # Verify the compression field in the generated YAML
        if ! grep -q "compression: \"${expected}\"" "$config_file"; then
            local actual_line
            actual_line="$(grep 'compression:' "$config_file" || echo '<not found>')"
            fail "Iteration ${i}: nfpm config compression mismatch for pl=${pl_id}, arch=${arch}. Expected 'compression: \"${expected}\"', got '${actual_line}'"
        fi

        # Clean up config files between iterations
        rm -rf "${STAGING_DIR}/nfpm-configs"
    done
}
