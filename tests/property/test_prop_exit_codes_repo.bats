#!/usr/bin/env bats
# ============================================================================
# test_prop_exit_codes_repo.bats — Property 19: 退出码映射正确性
# Feature: selfhosted-rpm-repo-builder, Property 19: 退出码映射正确性
#
# For any 错误类别，脚本的退出码应与定义的映射一致：
#   成功→0、参数错误→1、依赖缺失→2、下载失败→3、打包失败→4、
#   签名失败→5、元数据失败→6、发布失败→7、验证失败→8。
#
# Test approach:
# - Verify exit code constants are correctly defined
# - Test specific error scenarios produce the correct exit codes
#
# **Validates: Requirements 18.2**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
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
    USE_COLOR=false
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 19.1: Exit code constants are correctly defined
# ============================================================================

@test "Property 19: exit code constants match the defined mapping" {
    # Verify all 9 exit code constants
    [[ "$EXIT_OK"            -eq 0 ]] || fail "EXIT_OK should be 0, got ${EXIT_OK}"
    [[ "$EXIT_ARG_ERROR"     -eq 1 ]] || fail "EXIT_ARG_ERROR should be 1, got ${EXIT_ARG_ERROR}"
    [[ "$EXIT_DEP_MISSING"   -eq 2 ]] || fail "EXIT_DEP_MISSING should be 2, got ${EXIT_DEP_MISSING}"
    [[ "$EXIT_DOWNLOAD_FAIL" -eq 3 ]] || fail "EXIT_DOWNLOAD_FAIL should be 3, got ${EXIT_DOWNLOAD_FAIL}"
    [[ "$EXIT_PACKAGE_FAIL"  -eq 4 ]] || fail "EXIT_PACKAGE_FAIL should be 4, got ${EXIT_PACKAGE_FAIL}"
    [[ "$EXIT_SIGN_FAIL"     -eq 5 ]] || fail "EXIT_SIGN_FAIL should be 5, got ${EXIT_SIGN_FAIL}"
    [[ "$EXIT_METADATA_FAIL" -eq 6 ]] || fail "EXIT_METADATA_FAIL should be 6, got ${EXIT_METADATA_FAIL}"
    [[ "$EXIT_PUBLISH_FAIL"  -eq 7 ]] || fail "EXIT_PUBLISH_FAIL should be 7, got ${EXIT_PUBLISH_FAIL}"
    [[ "$EXIT_VERIFY_FAIL"   -eq 8 ]] || fail "EXIT_VERIFY_FAIL should be 8, got ${EXIT_VERIFY_FAIL}"
}

# ============================================================================
# Property 19.2: Exit code 1 — invalid arguments (100 iterations)
# ============================================================================

@test "Property 19: exit code 1 for invalid/unknown arguments (100 iterations)" {
    for i in $(seq 1 100); do
        # Generate a random unknown argument
        local suffixes=("foo" "bar" "baz" "qux" "invalid" "wrong" "nope" "bad" "xyz" "test")
        local idx=$(( RANDOM % ${#suffixes[@]} ))
        local unknown_arg="--${suffixes[$idx]}-$(( RANDOM % 10000 ))"

        run parse_args "$unknown_arg"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: parse_args '${unknown_arg}' expected exit 1 but got exit ${status}"
        fi
    done
}

# ============================================================================
# Property 19.3: Exit code 1 — invalid --arch values
# ============================================================================

@test "Property 19: exit code 1 for invalid --arch values" {
    local invalid_archs=("arm" "i386" "i686" "mips" "ppc64" "s390x" "sparc" "invalid" "ALL" "X86_64")

    for arch in "${invalid_archs[@]}"; do
        run parse_args --arch "$arch"

        if [[ "$status" -ne 1 ]]; then
            fail "--arch '${arch}' expected exit 1 but got exit ${status}"
        fi
    done
}

# ============================================================================
# Property 19.4: Exit code 1 — invalid --stage values
# ============================================================================

@test "Property 19: exit code 1 for invalid --stage values" {
    local invalid_stages=("test" "deploy" "release" "compile" "package" "BUILD" "SIGN" "invalid")

    for stage in "${invalid_stages[@]}"; do
        run parse_args --stage "$stage"

        if [[ "$status" -ne 1 ]]; then
            fail "--stage '${stage}' expected exit 1 but got exit ${status}"
        fi
    done
}

# ============================================================================
# Property 19.5: Exit code 1 — invalid distro:version
# ============================================================================

@test "Property 19: exit code 1 for invalid distro:version combinations (100 iterations)" {
    for i in $(seq 1 100); do
        local invalid_dv
        invalid_dv="$(gen_invalid_distro_version)"

        run resolve_product_lines "$invalid_dv"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: resolve_product_lines '${invalid_dv}' expected exit 1 but got exit ${status}"
        fi
    done
}

# ============================================================================
# Property 19.6: Exit code 2 — dependency missing
# ============================================================================

@test "Property 19: exit code 2 when required tools are missing" {
    # Remove all required tools from PATH by creating failing mocks
    create_mock_command curl 127 "" "command not found"
    create_mock_command nfpm 127 "" "command not found"
    create_mock_command createrepo_c 127 "" "command not found"
    create_mock_command createrepo 127 "" "command not found"
    create_mock_command gpg 127 "" "command not found"
    create_mock_command rpm 127 "" "command not found"

    # Override command -v to report tools as missing
    eval 'command() {
        if [[ "$1" == "-v" ]]; then
            case "$2" in
                curl|nfpm|createrepo_c|createrepo|gpg|rpm) return 1 ;;
            esac
        fi
        builtin command "$@"
    }'

    run check_dependencies

    unset -f command

    [[ "$status" -eq 2 ]] || fail "check_dependencies with missing tools expected exit 2 but got exit ${status}"
}

# ============================================================================
# Property 19.7: Exit code 5 — sign failure (no GPG key specified)
# ============================================================================

@test "Property 19: exit code 5 when signing without GPG key" {
    OPT_GPG_KEY_FILE=""
    OPT_GPG_KEY_ID=""

    run sign_rpm "/fake/path/caddy-2.9.0-1.el8.x86_64.rpm"

    [[ "$status" -eq 5 ]] || fail "sign_rpm without GPG key expected exit 5 but got exit ${status}"
}

# ============================================================================
# Property 19.8: Exit code 5 — export GPG pubkey without key ID
# ============================================================================

@test "Property 19: exit code 5 when exporting GPG pubkey without key ID" {
    OPT_GPG_KEY_ID=""

    run export_gpg_pubkey "${TEST_TEMP_DIR}/gpg.key"

    [[ "$status" -eq 5 ]] || fail "export_gpg_pubkey without key ID expected exit 5 but got exit ${status}"
}

# ============================================================================
# Property 19.9: Exit code 7 — publish failure (staging dir missing)
# ============================================================================

@test "Property 19: exit code 7 when staging directory does not exist" {
    STAGING_DIR="${TEST_TEMP_DIR}/nonexistent-staging"
    OPT_OUTPUT="${TEST_TEMP_DIR}/output"
    mkdir -p "$OPT_OUTPUT"

    run atomic_publish

    [[ "$status" -eq 7 ]] || fail "atomic_publish with missing staging expected exit 7 but got exit ${status}"
}

# ============================================================================
# Property 19.10: Exit code 7 — rollback failure (no backups)
# ============================================================================

@test "Property 19: exit code 7 when rollback has no backups" {
    OPT_OUTPUT="${TEST_TEMP_DIR}/output"
    mkdir -p "$OPT_OUTPUT"

    run rollback_latest

    [[ "$status" -eq 7 ]] || fail "rollback_latest with no backups expected exit 7 but got exit ${status}"
}

# ============================================================================
# Property 19.11: Comprehensive exit code mapping verification
# Verify all exit codes are unique and cover the full range 0-8
# ============================================================================

@test "Property 19: all exit codes are unique and cover range 0-8" {
    local -A code_map=(
        [EXIT_OK]="$EXIT_OK"
        [EXIT_ARG_ERROR]="$EXIT_ARG_ERROR"
        [EXIT_DEP_MISSING]="$EXIT_DEP_MISSING"
        [EXIT_DOWNLOAD_FAIL]="$EXIT_DOWNLOAD_FAIL"
        [EXIT_PACKAGE_FAIL]="$EXIT_PACKAGE_FAIL"
        [EXIT_SIGN_FAIL]="$EXIT_SIGN_FAIL"
        [EXIT_METADATA_FAIL]="$EXIT_METADATA_FAIL"
        [EXIT_PUBLISH_FAIL]="$EXIT_PUBLISH_FAIL"
        [EXIT_VERIFY_FAIL]="$EXIT_VERIFY_FAIL"
    )

    # Verify we have exactly 9 exit codes
    local count=${#code_map[@]}
    [[ "$count" -eq 9 ]] || fail "Expected 9 exit code constants, got ${count}"

    # Verify all values are unique
    local -A seen_values=()
    for name in "${!code_map[@]}"; do
        local val="${code_map[$name]}"
        if [[ -n "${seen_values[$val]:-}" ]]; then
            fail "Duplicate exit code value ${val}: ${name} and ${seen_values[$val]}"
        fi
        seen_values[$val]="$name"
    done

    # Verify range 0-8 is fully covered
    for expected in $(seq 0 8); do
        if [[ -z "${seen_values[$expected]:-}" ]]; then
            fail "Exit code ${expected} is not assigned to any constant"
        fi
    done
}
