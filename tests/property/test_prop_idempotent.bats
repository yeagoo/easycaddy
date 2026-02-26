#!/usr/bin/env bats
# ============================================================================
# test_prop_idempotent.bats — Property 16: 幂等性
# Feature: selfhosted-rpm-repo-builder, Property 16: 幂等性
#
# For any 相同的输入参数，重复执行构建脚本应产生相同的仓库目录结构；
# 当目标目录中已存在相同版本的 RPM 包时，应跳过下载和打包步骤。
#
# Test approach: For 100 iterations, randomly pick a product line and arch,
# call build_rpm twice with the same parameters, and verify:
# 1. The second call skips (RPM already exists message)
# 2. RPM_COUNT only increments once
# 3. The RPM file is the same
#
# **Validates: Requirements 15.1, 15.2**
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

# Create a mock nfpm that parses YAML config to create correctly-named dummy RPM
create_nfpm_mock() {
    local mock_script="${MOCK_BIN_DIR}/nfpm"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
# Mock nfpm: parse arguments and create a dummy RPM file
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

# Extract fields from YAML config
name=$(grep '^name:' "$config_file" | head -1 | sed 's/name: *//' | tr -d '"')
version=$(grep '^version:' "$config_file" | head -1 | sed 's/version: *//' | tr -d '"')
release=$(grep '^release:' "$config_file" | head -1 | sed 's/release: *//' | tr -d '"')
arch=$(grep '^arch:' "$config_file" | head -1 | sed 's/arch: *//' | tr -d '"')

# Create dummy RPM file matching expected naming pattern
rpm_name="${name}-${version}-${release}.${arch}.rpm"
mkdir -p "$target_dir"
echo "fake-rpm-content-$(date +%s%N)" > "${target_dir}/${rpm_name}"
exit 0
MOCK_EOF
    chmod +x "$mock_script"
}

setup() {
    setup_test_env
    source_build_repo_script
    create_nfpm_mock

    # Set up test environment
    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"

    # Create fake binary files for both architectures
    mkdir -p "${TEST_TEMP_DIR}/bin"
    echo "fake-binary" > "${TEST_TEMP_DIR}/bin/caddy-x86_64"
    echo "fake-binary" > "${TEST_TEMP_DIR}/bin/caddy-aarch64"
    declare -gA DOWNLOADED_ARCHS=([x86_64]="${TEST_TEMP_DIR}/bin/caddy-x86_64" [aarch64]="${TEST_TEMP_DIR}/bin/caddy-aarch64")
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 16: Idempotency (100 iterations)
# ============================================================================

@test "Property 16: build_rpm is idempotent — second call skips, RPM_COUNT increments once, file unchanged (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset state for each iteration
        RPM_COUNT=0
        rm -rf "${STAGING_DIR:?}"/*

        # Random product line and arch
        local pl_id
        pl_id="$(gen_product_line_id)"

        local archs=(x86_64 aarch64)
        local arch="${archs[$(( RANDOM % 2 ))]}"

        # Random version
        CADDY_VERSION="$(gen_caddy_version_number)"

        # First call — should build the RPM
        local stderr_first="${TEST_TEMP_DIR}/stderr_first_${i}"
        build_rpm "$pl_id" "$arch" 2>"$stderr_first"

        # Verify RPM_COUNT is 1 after first call
        if [[ "$RPM_COUNT" -ne 1 ]]; then
            fail "Iteration ${i}: After first build_rpm, RPM_COUNT=${RPM_COUNT}, expected 1 (pl=${pl_id}, arch=${arch}, ver=${CADDY_VERSION})"
        fi

        # Get the RPM file path and its content hash
        local pl_tag
        pl_tag="$(get_product_line_tag "$pl_id")"
        local pl_path
        pl_path="$(get_product_line_path "$pl_id")"
        local rpm_name="caddy-${CADDY_VERSION}-1.${pl_tag}.${arch}.rpm"
        local rpm_path="${STAGING_DIR}/caddy/${pl_path}/${arch}/Packages/${rpm_name}"

        if [[ ! -f "$rpm_path" ]]; then
            fail "Iteration ${i}: RPM file not found after first call: ${rpm_path}"
        fi

        local first_content
        first_content="$(cat "$rpm_path")"

        # Second call — should skip (idempotent)
        local stderr_second="${TEST_TEMP_DIR}/stderr_second_${i}"
        build_rpm "$pl_id" "$arch" 2>"$stderr_second"

        # 1. Verify the second call outputs skip message
        if ! grep -qF "RPM 已存在，跳过" "$stderr_second"; then
            fail "Iteration ${i}: Second build_rpm did not output skip message. pl=${pl_id}, arch=${arch}, ver=${CADDY_VERSION}. Stderr: $(cat "$stderr_second")"
        fi

        # 2. Verify RPM_COUNT is still 1 (not incremented by second call)
        if [[ "$RPM_COUNT" -ne 1 ]]; then
            fail "Iteration ${i}: After second build_rpm, RPM_COUNT=${RPM_COUNT}, expected 1 (pl=${pl_id}, arch=${arch}, ver=${CADDY_VERSION})"
        fi

        # 3. Verify the RPM file content is unchanged
        local second_content
        second_content="$(cat "$rpm_path")"
        if [[ "$first_content" != "$second_content" ]]; then
            fail "Iteration ${i}: RPM file content changed after second call. pl=${pl_id}, arch=${arch}, ver=${CADDY_VERSION}"
        fi
    done
}
