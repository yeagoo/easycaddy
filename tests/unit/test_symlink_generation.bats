#!/usr/bin/env bats
# ============================================================================
# test_symlink_generation.bats — 符号链接生成单元测试
# 测试 generate_symlinks 和 validate_symlinks 函数
# - 相对路径验证
# - Fedora 不生成版本链接
# - 符号链接目标不存在时的警告
# - validate_symlinks 检测无效链接
#
# Requirements: 11.1, 11.2, 11.3, 11.4, 11.5
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

# Create product line directories under STAGING_DIR/caddy/
create_product_line_dirs() {
    local caddy_dir="${STAGING_DIR}/caddy"
    mkdir -p "${caddy_dir}/el8/x86_64/Packages"
    mkdir -p "${caddy_dir}/el9/x86_64/Packages"
    mkdir -p "${caddy_dir}/el10/x86_64/Packages"
    mkdir -p "${caddy_dir}/al2023/x86_64/Packages"
    mkdir -p "${caddy_dir}/fedora/x86_64/Packages"
    mkdir -p "${caddy_dir}/openeuler/22/x86_64/Packages"
    mkdir -p "${caddy_dir}/openeuler/24/x86_64/Packages"
}

setup() {
    setup_test_env
    source_build_repo_script

    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"
    SYMLINK_COUNT=0
}

teardown() {
    teardown_test_env
}

# ============================================================================
# 1. generate_symlinks creates symlinks for non-Fedora distros
# ============================================================================

@test "generate_symlinks creates symlinks for EL8 distros" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    # Check a few EL8 symlinks
    [[ -L "${caddy_dir}/rhel/8" ]]
    [[ -L "${caddy_dir}/centos/8" ]]
    [[ -L "${caddy_dir}/anolis/8" ]]
    [[ -L "${caddy_dir}/kylin/V10" ]]
    [[ -L "${caddy_dir}/alinux/3" ]]
}

@test "generate_symlinks creates symlinks for EL9 distros" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    [[ -L "${caddy_dir}/rhel/9" ]]
    [[ -L "${caddy_dir}/anolis/23" ]]
    [[ -L "${caddy_dir}/kylin/V11" ]]
    [[ -L "${caddy_dir}/alinux/4" ]]
}

@test "generate_symlinks creates symlinks for EL10 distros" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    [[ -L "${caddy_dir}/rhel/10" ]]
    [[ -L "${caddy_dir}/centos/10" ]]
    [[ -L "${caddy_dir}/almalinux/10" ]]
    [[ -L "${caddy_dir}/rocky/10" ]]
    [[ -L "${caddy_dir}/ol/10" ]]
}

@test "generate_symlinks creates symlink for AL2023" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    [[ -L "${caddy_dir}/amzn/2023" ]]
}

@test "generate_symlinks creates symlinks for openEuler" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    [[ -L "${caddy_dir}/openEuler/22" ]]
    [[ -L "${caddy_dir}/openEuler/24" ]]
}

# ============================================================================
# 2. Fedora does NOT generate version symlinks (Requirement 11.2)
# ============================================================================

@test "generate_symlinks does NOT create symlinks for fedora:42" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    # fedora/42 and fedora/43 should NOT exist as symlinks
    [[ ! -L "${caddy_dir}/fedora/42" ]]
    [[ ! -L "${caddy_dir}/fedora/43" ]]
}

# ============================================================================
# 3. Symlinks use relative paths (Requirement 11.3)
# ============================================================================

@test "symlinks use relative paths starting with .." {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    local target
    target="$(readlink "${caddy_dir}/anolis/8")"
    [[ "$target" == "../el8" ]]
}

@test "symlink for amzn/2023 points to ../al2023" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local target
    target="$(readlink "${STAGING_DIR}/caddy/amzn/2023")"
    [[ "$target" == "../al2023" ]]
}

@test "symlink for openEuler/22 points to ../openeuler/22" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local target
    target="$(readlink "${STAGING_DIR}/caddy/openEuler/22")"
    [[ "$target" == "../openeuler/22" ]]
}

@test "symlink for openEuler/24 points to ../openeuler/24" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local target
    target="$(readlink "${STAGING_DIR}/caddy/openEuler/24")"
    [[ "$target" == "../openeuler/24" ]]
}

@test "symlink for kylin/V10 points to ../el8" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local target
    target="$(readlink "${STAGING_DIR}/caddy/kylin/V10")"
    [[ "$target" == "../el8" ]]
}

@test "symlink for kylin/V11 points to ../el9" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local target
    target="$(readlink "${STAGING_DIR}/caddy/kylin/V11")"
    [[ "$target" == "../el9" ]]
}

@test "symlink for alinux/3 points to ../el8" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local target
    target="$(readlink "${STAGING_DIR}/caddy/alinux/3")"
    [[ "$target" == "../el8" ]]
}

@test "symlink for alinux/4 points to ../el9" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local target
    target="$(readlink "${STAGING_DIR}/caddy/alinux/4")"
    [[ "$target" == "../el9" ]]
}

# ============================================================================
# 4. Symlinks resolve to valid directories (Requirement 11.4)
# ============================================================================

@test "symlinks resolve to valid directories" {
    create_product_line_dirs

    generate_symlinks 2>/dev/null

    local caddy_dir="${STAGING_DIR}/caddy"
    # anolis/8 → ../el8 should resolve to a real directory
    [[ -d "${caddy_dir}/anolis/8" ]]
    # amzn/2023 → ../al2023 should resolve to a real directory
    [[ -d "${caddy_dir}/amzn/2023" ]]
    # openEuler/22 → ../openeuler/22 should resolve to a real directory
    [[ -d "${caddy_dir}/openEuler/22" ]]
}

# ============================================================================
# 5. Symlink target doesn't exist: warning and skip (Requirement 11.5)
# ============================================================================

@test "generate_symlinks warns and skips when target directory does not exist" {
    # Only create el8 directory, not el9 or others
    mkdir -p "${STAGING_DIR}/caddy/el8"

    run generate_symlinks
    # Should succeed (doesn't exit with error)
    assert_success
    # Should contain warning about missing targets
    assert_output --partial '符号链接目标不存在'
}

@test "generate_symlinks skips entries with missing target and creates valid ones" {
    # Only create el8 directory
    mkdir -p "${STAGING_DIR}/caddy/el8"

    SYMLINK_COUNT=0
    generate_symlinks 2>/dev/null

    # Should have created symlinks only for el8 distros (9 entries: rhel:8, centos:8, almalinux:8, rocky:8, anolis:8, ol:8, opencloudos:8, kylin:V10, alinux:3)
    [[ "$SYMLINK_COUNT" -gt 0 ]]

    # el8 symlinks should exist
    [[ -L "${STAGING_DIR}/caddy/rhel/8" ]]

    # el9 symlinks should NOT exist (target missing)
    [[ ! -L "${STAGING_DIR}/caddy/rhel/9" ]]
}

# ============================================================================
# 6. SYMLINK_COUNT is incremented correctly
# ============================================================================

@test "SYMLINK_COUNT reflects number of created symlinks" {
    create_product_line_dirs

    SYMLINK_COUNT=0
    generate_symlinks 2>/dev/null

    # Total non-Fedora entries: 28 - 2 (fedora:42, fedora:43) = 26
    [[ "$SYMLINK_COUNT" -eq 26 ]]
}

# ============================================================================
# 7. validate_symlinks tests
# ============================================================================

@test "validate_symlinks returns 0 when all symlinks are valid" {
    create_product_line_dirs
    generate_symlinks 2>/dev/null

    run validate_symlinks
    assert_success
}

@test "validate_symlinks returns 1 when invalid symlinks exist" {
    local caddy_dir="${STAGING_DIR}/caddy"
    mkdir -p "${caddy_dir}/fake"
    # Create a symlink pointing to a non-existent target
    ln -sfn "../nonexistent" "${caddy_dir}/fake/broken"

    run validate_symlinks
    assert_failure
    assert_output --partial '无效符号链接'
}

@test "validate_symlinks reports broken symlink target" {
    local caddy_dir="${STAGING_DIR}/caddy"
    mkdir -p "${caddy_dir}/test"
    ln -sfn "../does_not_exist" "${caddy_dir}/test/link"

    run validate_symlinks
    assert_failure
    assert_output --partial 'does_not_exist'
}

@test "validate_symlinks returns 0 when no symlinks exist" {
    mkdir -p "${STAGING_DIR}/caddy"

    run validate_symlinks
    assert_success
}
