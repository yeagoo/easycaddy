#!/usr/bin/env bats
# ============================================================================
# test_prop_rpm_count.bats — Property 7: RPM 包数量正确性
# Feature: selfhosted-rpm-repo-builder, Property 7: RPM 包数量正确性
#
# For any 目标产品线集合（大小为 N）和目标架构集合（大小为 M），
# 生成的 RPM 包总数应恰好为 N × M。
#
# **Validates: Requirements 6.2**
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

setup() {
    setup_test_env
    source_build_repo_script
    create_nfpm_mock

    # Set up test environment
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
# Property 7: RPM count = N product lines × M architectures (100 iterations)
# ============================================================================

@test "Property 7: RPM count = N product lines × M architectures (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset RPM_COUNT and clean staging
        RPM_COUNT=0
        rm -rf "${STAGING_DIR:?}"/*

        # Random subset of product lines (1-7)
        local -a shuffled=("${KNOWN_PRODUCT_LINES[@]}")
        local count=$(( RANDOM % 7 + 1 ))

        # Fisher-Yates shuffle
        local j k tmp
        for (( j=${#shuffled[@]}-1; j>0; j-- )); do
            k=$(( RANDOM % (j+1) ))
            tmp="${shuffled[$j]}"
            shuffled[$j]="${shuffled[$k]}"
            shuffled[$k]="$tmp"
        done
        local -a pls=("${shuffled[@]:0:$count}")

        # Random architecture set (1 or 2 architectures)
        local -a archs=()
        case $(( RANDOM % 3 )) in
            0) archs=(x86_64) ;;
            1) archs=(aarch64) ;;
            2) archs=(x86_64 aarch64) ;;
        esac

        local expected=$(( ${#pls[@]} * ${#archs[@]} ))

        # Build RPMs for each product line × architecture combination
        for pl in "${pls[@]}"; do
            for arch in "${archs[@]}"; do
                build_rpm "$pl" "$arch" 2>/dev/null
            done
        done

        # Assert RPM_COUNT matches expected
        if [[ "$RPM_COUNT" -ne "$expected" ]]; then
            fail "Iteration ${i}: RPM_COUNT=${RPM_COUNT}, expected=${expected} (pls=${pls[*]}, archs=${archs[*]})"
        fi

        # Count actual RPM files on disk
        local actual_files
        actual_files=$(find "$STAGING_DIR" -name '*.rpm' -type f | wc -l | tr -d ' ')
        if [[ "$actual_files" -ne "$expected" ]]; then
            fail "Iteration ${i}: actual RPM files=${actual_files}, expected=${expected} (pls=${pls[*]}, archs=${archs[*]})"
        fi
    done
}
