#!/usr/bin/env bats
# ============================================================================
# test_prop_nfpm_config.bats — Property 9: nfpm 配置完整性
# Feature: selfhosted-rpm-repo-builder, Property 9: nfpm 配置完整性
#
# For any 产品线和架构组合，动态生成的 nfpm 配置应包含：
# - 二进制文件安装到 /usr/bin/caddy（mode: 0755）
# - systemd 服务文件安装到 /usr/lib/systemd/system/caddy.service
# - 默认配置文件 /etc/caddy/Caddyfile（类型为 config|noreplace）
# - LICENSE 文件安装到 /usr/share/licenses/caddy/LICENSE
# - 目录条目 /etc/caddy/ 和 /var/lib/caddy/
# - postinstall 和 preremove 生命周期脚本
# - 正确的 version、arch 和 release 字段
#
# **Validates: Requirements 6.4, 6.5, 6.6, 6.7, 6.8, 6.10, 6.11**
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

# Get expected product line tag for a given pl_id
get_expected_pl_tag() {
    local pl_id="$1"
    case "$pl_id" in
        el8)    echo "el8" ;;
        el9)    echo "el9" ;;
        el10)   echo "el10" ;;
        al2023) echo "al2023" ;;
        fedora) echo "fc" ;;
        oe22)   echo "oe22" ;;
        oe24)   echo "oe24" ;;
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
# Property 9: nfpm config completeness (100 iterations)
# ============================================================================

@test "Property 9: nfpm config completeness (100 iterations)" {
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
        local version
        version="$(gen_caddy_version_number)"
        CADDY_VERSION="$version"

        local expected_tag
        expected_tag="$(get_expected_pl_tag "$pl_id")"

        # Call generate_nfpm_config
        local config_file
        config_file="$(generate_nfpm_config "$pl_id" "$arch")"

        # Config file must exist
        if [[ ! -f "$config_file" ]]; then
            fail "Iteration ${i}: config file not created (pl=${pl_id}, arch=${arch})"
        fi

        local content
        content="$(cat "$config_file")"

        # --- Assert version, arch, release fields ---
        if ! echo "$content" | grep -q "^version: \"${version}\""; then
            fail "Iteration ${i}: missing version field '${version}' (pl=${pl_id}, arch=${arch})"
        fi

        if ! echo "$content" | grep -q "^arch: \"${arch}\""; then
            fail "Iteration ${i}: missing arch field '${arch}' (pl=${pl_id}, arch=${arch})"
        fi

        if ! echo "$content" | grep -q "^release: \"1\\.${expected_tag}\""; then
            fail "Iteration ${i}: missing release field '1.${expected_tag}' (pl=${pl_id}, arch=${arch})"
        fi

        # --- Assert binary installed to /usr/bin/caddy with mode 0755 ---
        if ! echo "$content" | grep -q "dst: /usr/bin/caddy"; then
            fail "Iteration ${i}: missing dst: /usr/bin/caddy (pl=${pl_id}, arch=${arch})"
        fi
        if ! echo "$content" | grep -q "mode: 0755"; then
            fail "Iteration ${i}: missing mode: 0755 for /usr/bin/caddy (pl=${pl_id}, arch=${arch})"
        fi

        # --- Assert systemd service file ---
        if ! echo "$content" | grep -q "dst: /usr/lib/systemd/system/caddy.service"; then
            fail "Iteration ${i}: missing dst: /usr/lib/systemd/system/caddy.service (pl=${pl_id}, arch=${arch})"
        fi

        # --- Assert default config file with config|noreplace ---
        if ! echo "$content" | grep -q "dst: /etc/caddy/Caddyfile"; then
            fail "Iteration ${i}: missing dst: /etc/caddy/Caddyfile (pl=${pl_id}, arch=${arch})"
        fi
        if ! echo "$content" | grep -q "type: config|noreplace"; then
            fail "Iteration ${i}: missing type: config|noreplace (pl=${pl_id}, arch=${arch})"
        fi

        # --- Assert LICENSE file ---
        if ! echo "$content" | grep -q "dst: /usr/share/licenses/caddy/LICENSE"; then
            fail "Iteration ${i}: missing dst: /usr/share/licenses/caddy/LICENSE (pl=${pl_id}, arch=${arch})"
        fi

        # --- Assert directory entries ---
        if ! echo "$content" | grep -q "dst: /etc/caddy/"; then
            fail "Iteration ${i}: missing dst: /etc/caddy/ dir entry (pl=${pl_id}, arch=${arch})"
        fi
        if ! echo "$content" | grep -q "dst: /var/lib/caddy/"; then
            fail "Iteration ${i}: missing dst: /var/lib/caddy/ dir entry (pl=${pl_id}, arch=${arch})"
        fi

        # --- Assert postinstall and preremove lifecycle scripts ---
        if ! echo "$content" | grep -q "postinstall:"; then
            fail "Iteration ${i}: missing postinstall script reference (pl=${pl_id}, arch=${arch})"
        fi
        if ! echo "$content" | grep -q "preremove:"; then
            fail "Iteration ${i}: missing preremove script reference (pl=${pl_id}, arch=${arch})"
        fi

        # Clean up config files between iterations
        rm -rf "${STAGING_DIR}/nfpm-configs"
    done
}
