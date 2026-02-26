#!/usr/bin/env bats
# ============================================================================
# test_prop_rpm_filename.bats — Property 8: RPM 文件名格式正确性
# Feature: selfhosted-rpm-repo-builder, Property 8: RPM 文件名格式正确性
#
# For any 版本号、产品线标签和架构组合，生成的 RPM 文件名应严格匹配
# 格式 caddy-{version}-1.{pl_tag}.{arch}.rpm。
#
# **Validates: Requirements 6.3**
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

# Create a mock nfpm that parses --config and --target to create a dummy RPM
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
echo "fake-rpm" > "${target_dir}/${rpm_name}"
exit 0
MOCK_EOF
    chmod +x "$mock_script"
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
    create_nfpm_mock

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
# Property 8: RPM filename matches caddy-{version}-1.{pl_tag}.{arch}.rpm
# (100 iterations)
# ============================================================================

@test "Property 8: RPM filename format correctness (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset state and clean staging
        RPM_COUNT=0
        rm -rf "${STAGING_DIR:?}"/*

        # Generate random version
        local version
        version="$(gen_caddy_version_number)"
        CADDY_VERSION="$version"

        # Pick a random product line
        local pl_id
        pl_id="${KNOWN_PRODUCT_LINES[$(( RANDOM % ${#KNOWN_PRODUCT_LINES[@]} ))]}"
        local expected_tag
        expected_tag="$(get_expected_pl_tag "$pl_id")"

        # Pick a random architecture
        local arch
        case $(( RANDOM % 2 )) in
            0) arch="x86_64" ;;
            1) arch="aarch64" ;;
        esac

        # Build the RPM
        build_rpm "$pl_id" "$arch" 2>/dev/null

        # Find the generated RPM file
        local rpm_file
        rpm_file="$(find "$STAGING_DIR" -name '*.rpm' -type f)"

        # Exactly one RPM should exist
        local rpm_count
        rpm_count="$(echo "$rpm_file" | grep -c '.')"
        if [[ "$rpm_count" -ne 1 ]]; then
            fail "Iteration ${i}: expected 1 RPM file, found ${rpm_count} (pl=${pl_id}, arch=${arch}, version=${version})"
        fi

        # Extract just the filename
        local filename
        filename="$(basename "$rpm_file")"

        # Assert filename matches the regex pattern
        local regex='^caddy-[0-9]+\.[0-9]+\.[0-9]+-1\.[a-z0-9]+\.(x86_64|aarch64)\.rpm$'
        if [[ ! "$filename" =~ $regex ]]; then
            fail "Iteration ${i}: filename '${filename}' does not match regex (pl=${pl_id}, arch=${arch}, version=${version})"
        fi

        # Assert filename exactly equals expected
        local expected_filename="caddy-${version}-1.${expected_tag}.${arch}.rpm"
        if [[ "$filename" != "$expected_filename" ]]; then
            fail "Iteration ${i}: filename '${filename}' != expected '${expected_filename}' (pl=${pl_id}, arch=${arch})"
        fi
    done
}
