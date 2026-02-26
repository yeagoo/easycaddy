#!/usr/bin/env bats
# ============================================================================
# test_prop_repodata.bats — Property 12: repodata 生成与验证
# Feature: selfhosted-rpm-repo-builder, Property 12: repodata 生成与验证
#
# For any 产品线和架构目录，执行 createrepo_c 后应在该目录下生成
# repodata/repomd.xml 文件。
#
# **Validates: Requirements 10.3, 10.7**
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

create_createrepo_mock() {
    local mock_script="${MOCK_BIN_DIR}/createrepo_c"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
# Mock createrepo_c: create fake repodata
repo_dir=""
for arg in "$@"; do
    if [[ "$arg" != --* ]]; then
        repo_dir="$arg"
    fi
done
if [[ -n "$repo_dir" ]]; then
    mkdir -p "${repo_dir}/repodata"
    echo '<?xml version="1.0" encoding="UTF-8"?><repomd/>' > "${repo_dir}/repodata/repomd.xml"
fi
exit 0
MOCK_EOF
    chmod +x "$mock_script"
}

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
    create_createrepo_mock

    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"
}

teardown() {
    teardown_test_env
}

@test "Property 12: repodata/repomd.xml exists after generate_repodata (100 iterations)" {
    for i in $(seq 1 100); do
        local pl_id
        pl_id="${KNOWN_PRODUCT_LINES[$(( RANDOM % ${#KNOWN_PRODUCT_LINES[@]} ))]}"

        local arch
        case $(( RANDOM % 2 )) in
            0) arch="x86_64" ;;
            1) arch="aarch64" ;;
        esac

        local pl_path
        pl_path="$(get_expected_pl_path "$pl_id")"
        local repo_dir="${STAGING_DIR}/caddy/${pl_path}/${arch}"
        mkdir -p "${repo_dir}/Packages"
        echo "fake-rpm" > "${repo_dir}/Packages/caddy-2.9.0-1.el9.x86_64.rpm"

        generate_repodata "$repo_dir" 2>/dev/null

        if [[ ! -f "${repo_dir}/repodata/repomd.xml" ]]; then
            fail "Iteration ${i}: repomd.xml missing in ${repo_dir}/repodata/ (pl=${pl_id}, arch=${arch})"
        fi

        # Clean up for next iteration
        rm -rf "${STAGING_DIR:?}/caddy"
    done
}

@test "Property 12: generate_repodata fails when createrepo_c fails (100 iterations)" {
    # Replace mock with failing version
    local mock_script="${MOCK_BIN_DIR}/createrepo_c"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$mock_script"
    # Also shadow createrepo
    local mock_script2="${MOCK_BIN_DIR}/createrepo"
    cat > "$mock_script2" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "$mock_script2"

    for i in $(seq 1 100); do
        local pl_id
        pl_id="${KNOWN_PRODUCT_LINES[$(( RANDOM % ${#KNOWN_PRODUCT_LINES[@]} ))]}"
        local pl_path
        pl_path="$(get_expected_pl_path "$pl_id")"
        local repo_dir="${TEST_TEMP_DIR}/fail_repo_${i}"
        mkdir -p "${repo_dir}/Packages"

        run generate_repodata "$repo_dir"
        if [[ "$status" -ne 6 ]]; then
            fail "Iteration ${i}: expected exit code 6, got ${status} (pl=${pl_id})"
        fi
    done
}
