#!/usr/bin/env bats
# ============================================================================
# test_nfpm_config.bats — nfpm 配置生成与 RPM 构建单元测试
# 测试 systemd 服务文件内容、postinstall/preremove 脚本、
# generate_nfpm_config 各产品线配置、GPG 签名配置、架构处理、
# build_rpm 幂等性和 nfpm 失败处理
#
# Requirements: 6.1–6.12, 7.1–7.5
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators_repo'

# Source build-repo.sh for testing (without executing main)
source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

# Create a mock nfpm that parses --config and --target to create a dummy RPM
create_nfpm_mock() {
    local mock_script="${MOCK_BIN_DIR}/nfpm"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
config_file=""
target_dir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) config_file="$2"; shift 2 ;;
        --packager) shift 2 ;;
        --target) target_dir="$2"; shift 2 ;;
        package) shift ;;
        *) shift ;;
    esac
done
if [[ -z "$config_file" || -z "$target_dir" ]]; then
    echo "mock nfpm: missing --config or --target" >&2
    exit 1
fi
name=$(grep '^name:' "$config_file" | head -1 | sed 's/name: *//' | tr -d '"')
version=$(grep '^version:' "$config_file" | head -1 | sed 's/version: *//' | tr -d '"')
release=$(grep '^release:' "$config_file" | head -1 | sed 's/release: *//' | tr -d '"')
arch=$(grep '^arch:' "$config_file" | head -1 | sed 's/arch: *//' | tr -d '"')
rpm_name="${name}-${version}-${release}.${arch}.rpm"
mkdir -p "$target_dir"
echo "fake-rpm" > "${target_dir}/${rpm_name}"
exit 0
MOCK_EOF
    chmod +x "$mock_script"
}

# Create a mock nfpm that always fails
create_nfpm_fail_mock() {
    local mock_script="${MOCK_BIN_DIR}/nfpm"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
echo "nfpm: packaging error" >&2
exit 1
MOCK_EOF
    chmod +x "$mock_script"
}

setup() {
    setup_test_env
    source_build_repo_script
    create_nfpm_mock

    CADDY_VERSION="2.9.0"
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
# 1. systemd service file content validation (Requirements 7.1–7.5)
# ============================================================================

@test "caddy.service contains User=caddy" {
    run grep -q 'User=caddy' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains Group=caddy" {
    run grep -q 'Group=caddy' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains AmbientCapabilities=CAP_NET_BIND_SERVICE" {
    run grep -q 'AmbientCapabilities=CAP_NET_BIND_SERVICE' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains ProtectSystem=full" {
    run grep -q 'ProtectSystem=full' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains ProtectHome=true" {
    run grep -q 'ProtectHome=true' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains PrivateTmp=true" {
    run grep -q 'PrivateTmp=true' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains NoNewPrivileges=true" {
    run grep -q 'NoNewPrivileges=true' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains Type=notify" {
    run grep -q 'Type=notify' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains XDG_DATA_HOME=/var/lib/caddy" {
    run grep -q 'XDG_DATA_HOME=/var/lib/caddy' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains XDG_CONFIG_HOME=/etc/caddy" {
    run grep -q 'XDG_CONFIG_HOME=/etc/caddy' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

@test "caddy.service contains WantedBy=multi-user.target" {
    run grep -q 'WantedBy=multi-user.target' "${SCRIPT_DIR}/packaging/caddy.service"
    assert_success
}

# ============================================================================
# 2. postinstall.sh content validation (Requirements 7.4)
# ============================================================================

@test "postinstall.sh creates caddy group" {
    run grep -q 'groupadd.*caddy' "${SCRIPT_DIR}/packaging/scripts/postinstall.sh"
    assert_success
}

@test "postinstall.sh creates caddy user" {
    run grep -q 'useradd.*caddy' "${SCRIPT_DIR}/packaging/scripts/postinstall.sh"
    assert_success
}

@test "postinstall.sh runs systemctl daemon-reload" {
    run grep -q 'systemctl daemon-reload' "${SCRIPT_DIR}/packaging/scripts/postinstall.sh"
    assert_success
}

# ============================================================================
# 3. preremove.sh content validation (Requirements 6.10)
# ============================================================================

@test "preremove.sh stops caddy.service" {
    run grep -q 'systemctl stop caddy.service' "${SCRIPT_DIR}/packaging/scripts/preremove.sh"
    assert_success
}

@test "preremove.sh disables caddy.service" {
    run grep -q 'systemctl disable caddy.service' "${SCRIPT_DIR}/packaging/scripts/preremove.sh"
    assert_success
}

# ============================================================================
# 4. generate_nfpm_config for each product line (Requirements 6.1, 6.3, 6.9)
# ============================================================================

@test "generate_nfpm_config el8: compression xz, release 1.el8" {
    local config_file
    config_file="$(generate_nfpm_config "el8" "x86_64")"

    run grep 'compression:' "$config_file"
    assert_success
    assert_output --partial 'xz'

    run grep '^release:' "$config_file"
    assert_success
    assert_output --partial '1.el8'
}

@test "generate_nfpm_config el9: compression zstd, release 1.el9" {
    local config_file
    config_file="$(generate_nfpm_config "el9" "x86_64")"

    run grep 'compression:' "$config_file"
    assert_success
    assert_output --partial 'zstd'

    run grep '^release:' "$config_file"
    assert_success
    assert_output --partial '1.el9'
}

@test "generate_nfpm_config fedora: compression zstd, release 1.fc" {
    local config_file
    config_file="$(generate_nfpm_config "fedora" "x86_64")"

    run grep 'compression:' "$config_file"
    assert_success
    assert_output --partial 'zstd'

    run grep '^release:' "$config_file"
    assert_success
    assert_output --partial '1.fc'
}

@test "generate_nfpm_config oe22: compression zstd, release 1.oe22" {
    local config_file
    config_file="$(generate_nfpm_config "oe22" "x86_64")"

    run grep 'compression:' "$config_file"
    assert_success
    assert_output --partial 'zstd'

    run grep '^release:' "$config_file"
    assert_success
    assert_output --partial '1.oe22'
}

# ============================================================================
# 5. generate_nfpm_config GPG key file handling (Requirements 9.2)
# ============================================================================

@test "generate_nfpm_config with GPG key file includes signature section" {
    OPT_GPG_KEY_FILE="/tmp/test-key.gpg"
    local config_file
    config_file="$(generate_nfpm_config "el9" "x86_64")"

    run grep 'key_file:' "$config_file"
    assert_success
    assert_output --partial '/tmp/test-key.gpg'

    run grep 'signature:' "$config_file"
    assert_success
}

@test "generate_nfpm_config without GPG key file omits signature section" {
    OPT_GPG_KEY_FILE=""
    local config_file
    config_file="$(generate_nfpm_config "el9" "x86_64")"

    run grep 'signature:' "$config_file"
    assert_failure
}

# ============================================================================
# 6. generate_nfpm_config architecture handling (Requirements 6.8)
# ============================================================================

@test "generate_nfpm_config x86_64 architecture" {
    local config_file
    config_file="$(generate_nfpm_config "el9" "x86_64")"

    run grep '^arch:' "$config_file"
    assert_success
    assert_output --partial 'x86_64'
}

@test "generate_nfpm_config aarch64 architecture" {
    local config_file
    config_file="$(generate_nfpm_config "el9" "aarch64")"

    run grep '^arch:' "$config_file"
    assert_success
    assert_output --partial 'aarch64'
}

# ============================================================================
# 7. build_rpm idempotency (Requirements 15.1)
# ============================================================================

@test "build_rpm skips when RPM already exists" {
    RPM_COUNT=0

    # First build creates the RPM
    build_rpm "el9" "x86_64" 2>/dev/null
    [[ "$RPM_COUNT" -eq 1 ]]

    # Second build should skip (RPM already exists) and output skip message
    run build_rpm "el9" "x86_64"
    assert_success
    assert_output --partial '已存在'
}

@test "RPM_COUNT does not increment when skipping existing RPM" {
    RPM_COUNT=0

    # Build the RPM first
    build_rpm "el9" "x86_64" 2>/dev/null

    local count_after_first="$RPM_COUNT"
    [[ "$count_after_first" -eq 1 ]]

    # Build again — should skip
    build_rpm "el9" "x86_64" 2>/dev/null

    # RPM_COUNT should still be 1
    [[ "$RPM_COUNT" -eq 1 ]]
}

# ============================================================================
# 8. build_rpm nfpm failure (Requirements 6.12)
# ============================================================================

@test "build_rpm exits with EXIT_PACKAGE_FAIL when nfpm fails" {
    create_nfpm_fail_mock

    run build_rpm "el9" "x86_64"
    assert_failure
    [[ "$status" -eq 4 ]]
}
