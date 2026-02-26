#!/usr/bin/env bats
# ============================================================================
# test_product_line_map.bats — 产品线映射单元测试
# 测试 resolve_product_lines、get_product_line_path、get_product_line_tag、
# get_compress_type 函数的具体映射结果、openEuler 20 警告、无效输入错误处理
# 验证需求: 1.1, 1.2, 1.3, 1.4
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

# Reset build-repo.sh global variables between tests
reset_build_repo_globals() {
    TARGET_PRODUCT_LINES=()
}

setup() {
    setup_test_env
    source_build_repo_script
    reset_build_repo_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# 1. EL8 distro mappings (Requirements 1.1)
# ============================================================================

@test "resolve_product_lines: rhel:8 maps to el8" {
    resolve_product_lines "rhel:8"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: centos:8 maps to el8" {
    resolve_product_lines "centos:8"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: almalinux:8 maps to el8" {
    resolve_product_lines "almalinux:8"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: rocky:8 maps to el8" {
    resolve_product_lines "rocky:8"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: anolis:8 maps to el8" {
    resolve_product_lines "anolis:8"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: ol:8 maps to el8" {
    resolve_product_lines "ol:8"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: opencloudos:8 maps to el8" {
    resolve_product_lines "opencloudos:8"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: kylin:V10 maps to el8" {
    resolve_product_lines "kylin:V10"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: alinux:3 maps to el8" {
    resolve_product_lines "alinux:3"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

# ============================================================================
# 2. EL9 distro mappings (Requirements 1.1)
# ============================================================================

@test "resolve_product_lines: rhel:9 maps to el9" {
    resolve_product_lines "rhel:9"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: centos:9 maps to el9" {
    resolve_product_lines "centos:9"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: almalinux:9 maps to el9" {
    resolve_product_lines "almalinux:9"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: rocky:9 maps to el9" {
    resolve_product_lines "rocky:9"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: anolis:23 maps to el9" {
    resolve_product_lines "anolis:23"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: ol:9 maps to el9" {
    resolve_product_lines "ol:9"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: opencloudos:9 maps to el9" {
    resolve_product_lines "opencloudos:9"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: kylin:V11 maps to el9" {
    resolve_product_lines "kylin:V11"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

@test "resolve_product_lines: alinux:4 maps to el9" {
    resolve_product_lines "alinux:4"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
}

# ============================================================================
# 3. EL10 distro mappings (Requirements 1.1)
# ============================================================================

@test "resolve_product_lines: rhel:10 maps to el10" {
    resolve_product_lines "rhel:10"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el10" ]]
}

@test "resolve_product_lines: centos:10 maps to el10" {
    resolve_product_lines "centos:10"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el10" ]]
}

@test "resolve_product_lines: almalinux:10 maps to el10" {
    resolve_product_lines "almalinux:10"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el10" ]]
}

@test "resolve_product_lines: rocky:10 maps to el10" {
    resolve_product_lines "rocky:10"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el10" ]]
}

@test "resolve_product_lines: ol:10 maps to el10" {
    resolve_product_lines "ol:10"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el10" ]]
}

# ============================================================================
# 4. AL2023 mapping (Requirements 1.1)
# ============================================================================

@test "resolve_product_lines: amzn:2023 maps to al2023" {
    resolve_product_lines "amzn:2023"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "al2023" ]]
}

# ============================================================================
# 5. Fedora mappings (Requirements 1.1)
# ============================================================================

@test "resolve_product_lines: fedora:42 maps to fedora" {
    resolve_product_lines "fedora:42"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "fedora" ]]
}

@test "resolve_product_lines: fedora:43 maps to fedora" {
    resolve_product_lines "fedora:43"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "fedora" ]]
}

# ============================================================================
# 6. openEuler mappings (Requirements 1.1)
# ============================================================================

@test "resolve_product_lines: openEuler:22 maps to oe22" {
    resolve_product_lines "openEuler:22"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "oe22" ]]
}

@test "resolve_product_lines: openEuler:24 maps to oe24" {
    resolve_product_lines "openEuler:24"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "oe24" ]]
}

# ============================================================================
# 7. openEuler:20 warning and skip (Requirements 1.2)
# ============================================================================

@test "resolve_product_lines: openEuler:20 outputs warning and returns empty" {
    run resolve_product_lines "openEuler:20"
    assert_success
    assert_output --partial "openEuler 20 is not supported"
}

@test "resolve_product_lines: openEuler:20 among valid entries skips only openEuler:20" {
    resolve_product_lines "rhel:8,openEuler:20,rhel:9"
    # Should have el8 and el9, openEuler:20 skipped
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 2 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
    [[ "${TARGET_PRODUCT_LINES[1]}" == "el9" ]]
}

# ============================================================================
# 8. Invalid distro:version exits with code 1 (Requirements 1.4)
# ============================================================================

@test "resolve_product_lines: unknown distro exits with code 1" {
    run resolve_product_lines "gentoo:1"
    assert_failure 1
}

@test "resolve_product_lines: rhel:7 (unsupported version) exits with code 1" {
    run resolve_product_lines "rhel:7"
    assert_failure 1
}

@test "resolve_product_lines: ubuntu:22 exits with code 1" {
    run resolve_product_lines "ubuntu:22"
    assert_failure 1
}

@test "resolve_product_lines: amzn:2 exits with code 1" {
    run resolve_product_lines "amzn:2"
    assert_failure 1
}

@test "resolve_product_lines: invalid distro outputs error message" {
    run resolve_product_lines "fake:99"
    assert_failure 1
    assert_output --partial "Unknown distro:version"
}

# ============================================================================
# 9. "all" returns all 7 product lines (Requirements 1.3)
# ============================================================================

@test "resolve_product_lines: 'all' returns exactly 7 product lines" {
    resolve_product_lines "all"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 7 ]]
}

@test "resolve_product_lines: 'all' contains every known product line" {
    resolve_product_lines "all"
    for pl in el8 el9 el10 al2023 fedora oe22 oe24; do
        local found=false
        for actual in "${TARGET_PRODUCT_LINES[@]}"; do
            if [[ "$actual" == "$pl" ]]; then
                found=true
                break
            fi
        done
        [[ "$found" == true ]]
    done
}

# ============================================================================
# 10. Comma-separated distro specs with dedup (Requirements 1.3)
# ============================================================================

@test "resolve_product_lines: comma-separated list resolves multiple product lines" {
    resolve_product_lines "rhel:8,fedora:42,amzn:2023"
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 3 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
    [[ "${TARGET_PRODUCT_LINES[1]}" == "fedora" ]]
    [[ "${TARGET_PRODUCT_LINES[2]}" == "al2023" ]]
}

@test "resolve_product_lines: duplicate distros in same product line are deduped" {
    resolve_product_lines "rhel:8,centos:8,almalinux:8"
    # All map to el8, should be deduped to 1
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 1 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el8" ]]
}

@test "resolve_product_lines: mixed product lines with dedup" {
    resolve_product_lines "rhel:9,anolis:23,rocky:9,fedora:42,fedora:43"
    # rhel:9, anolis:23, rocky:9 all → el9; fedora:42, fedora:43 → fedora
    [[ ${#TARGET_PRODUCT_LINES[@]} -eq 2 ]]
    [[ "${TARGET_PRODUCT_LINES[0]}" == "el9" ]]
    [[ "${TARGET_PRODUCT_LINES[1]}" == "fedora" ]]
}

# ============================================================================
# 11. Helper functions: get_product_line_path, get_product_line_tag,
#     get_compress_type (Requirements 1.1)
# ============================================================================

# --- get_product_line_path ---

@test "get_product_line_path: el8 returns 'el8'" {
    local result
    result="$(get_product_line_path el8)"
    [[ "$result" == "el8" ]]
}

@test "get_product_line_path: el9 returns 'el9'" {
    local result
    result="$(get_product_line_path el9)"
    [[ "$result" == "el9" ]]
}

@test "get_product_line_path: el10 returns 'el10'" {
    local result
    result="$(get_product_line_path el10)"
    [[ "$result" == "el10" ]]
}

@test "get_product_line_path: al2023 returns 'al2023'" {
    local result
    result="$(get_product_line_path al2023)"
    [[ "$result" == "al2023" ]]
}

@test "get_product_line_path: fedora returns 'fedora'" {
    local result
    result="$(get_product_line_path fedora)"
    [[ "$result" == "fedora" ]]
}

@test "get_product_line_path: oe22 returns 'openeuler/22'" {
    local result
    result="$(get_product_line_path oe22)"
    [[ "$result" == "openeuler/22" ]]
}

@test "get_product_line_path: oe24 returns 'openeuler/24'" {
    local result
    result="$(get_product_line_path oe24)"
    [[ "$result" == "openeuler/24" ]]
}

# --- get_product_line_tag ---

@test "get_product_line_tag: el8 returns 'el8'" {
    local result
    result="$(get_product_line_tag el8)"
    [[ "$result" == "el8" ]]
}

@test "get_product_line_tag: fedora returns 'fc'" {
    local result
    result="$(get_product_line_tag fedora)"
    [[ "$result" == "fc" ]]
}

@test "get_product_line_tag: oe22 returns 'oe22'" {
    local result
    result="$(get_product_line_tag oe22)"
    [[ "$result" == "oe22" ]]
}

@test "get_product_line_tag: al2023 returns 'al2023'" {
    local result
    result="$(get_product_line_tag al2023)"
    [[ "$result" == "al2023" ]]
}

# --- get_compress_type ---

@test "get_compress_type: el8 returns 'xz'" {
    local result
    result="$(get_compress_type el8)"
    [[ "$result" == "xz" ]]
}

@test "get_compress_type: el9 returns 'zstd'" {
    local result
    result="$(get_compress_type el9)"
    [[ "$result" == "zstd" ]]
}

@test "get_compress_type: el10 returns 'zstd'" {
    local result
    result="$(get_compress_type el10)"
    [[ "$result" == "zstd" ]]
}

@test "get_compress_type: al2023 returns 'zstd'" {
    local result
    result="$(get_compress_type al2023)"
    [[ "$result" == "zstd" ]]
}

@test "get_compress_type: fedora returns 'zstd'" {
    local result
    result="$(get_compress_type fedora)"
    [[ "$result" == "zstd" ]]
}

@test "get_compress_type: oe22 returns 'zstd'" {
    local result
    result="$(get_compress_type oe22)"
    [[ "$result" == "zstd" ]]
}

@test "get_compress_type: oe24 returns 'zstd'" {
    local result
    result="$(get_compress_type oe24)"
    [[ "$result" == "zstd" ]]
}
