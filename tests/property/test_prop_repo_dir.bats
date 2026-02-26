#!/usr/bin/env bats
# ============================================================================
# test_prop_repo_dir.bats — Property 11: 仓库目录结构正确性
# Feature: selfhosted-rpm-repo-builder, Property 11: 仓库目录结构正确性
#
# For any 产品线和架构组合，签名后的 RPM 包应放置在
# {output_dir}/caddy/{pl_path}/{arch}/Packages/ 目录中。
#
# **Validates: Requirements 10.1, 10.2**
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
if [[ -z "$config_file" || -z "$target_dir" ]]; then exit 1; fi
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

# Expected pl_path for each product line
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
    create_nfpm_mock

    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"

    mkdir -p "${TEST_TEMP_DIR}/bin"
    echo "fake-binary" > "${TEST_TEMP_DIR}/bin/caddy-x86_64"
    echo "fake-binary" > "${TEST_TEMP_DIR}/bin/caddy-aarch64"
    DOWNLOADED_ARCHS=([x86_64]="${TEST_TEMP_DIR}/bin/caddy-x86_64" [aarch64]="${TEST_TEMP_DIR}/bin/caddy-aarch64")
}

teardown() {
    teardown_test_env
}

@test "Property 11: RPM placed in {staging}/caddy/{pl_path}/{arch}/Packages/ (100 iterations)" {
    for i in $(seq 1 100); do
        RPM_COUNT=0
        rm -rf "${STAGING_DIR:?}"/*

        local pl_id
        pl_id="${KNOWN_PRODUCT_LINES[$(( RANDOM % ${#KNOWN_PRODUCT_LINES[@]} ))]}"

        local arch
        case $(( RANDOM % 2 )) in
            0) arch="x86_64" ;;
            1) arch="aarch64" ;;
        esac

        CADDY_VERSION="$(gen_caddy_version_number)"

        build_rpm "$pl_id" "$arch" 2>/dev/null

        local expected_path
        expected_path="$(get_expected_pl_path "$pl_id")"
        local packages_dir="${STAGING_DIR}/caddy/${expected_path}/${arch}/Packages"

        if [[ ! -d "$packages_dir" ]]; then
            fail "Iteration ${i}: Packages dir missing: ${packages_dir} (pl=${pl_id}, arch=${arch})"
        fi

        local rpm_count
        rpm_count=$(find "$packages_dir" -name '*.rpm' -type f | wc -l | tr -d ' ')
        if [[ "$rpm_count" -ne 1 ]]; then
            fail "Iteration ${i}: expected 1 RPM in ${packages_dir}, found ${rpm_count}"
        fi
    done
}
