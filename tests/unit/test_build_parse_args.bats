#!/usr/bin/env bats
# ============================================================================
# test_build_parse_args.bats — build-repo.sh 命令行参数解析单元测试
# 测试 parse_args 各参数正确解析、默认值、--help 输出、--rollback 标志、
# 无效参数错误
# 验证需求: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9
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
    OPT_VERSION=""
    OPT_OUTPUT="./repo"
    OPT_GPG_KEY_ID=""
    OPT_GPG_KEY_FILE=""
    OPT_ARCH="all"
    OPT_DISTRO="all"
    OPT_BASE_URL="https://rpms.example.com"
    OPT_STAGE=""
    OPT_ROLLBACK=false
    OPT_SM2_KEY=""
    TARGET_PRODUCT_LINES=()
    TARGET_ARCHS=()
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
# 1. Default values when no args provided (Req 2.2, 2.4, 2.5)
# ============================================================================

@test "parse_args: no arguments sets default values" {
    parse_args
    [[ "$OPT_VERSION" == "" ]]
    [[ "$OPT_OUTPUT" == "./repo" ]]
    [[ "$OPT_GPG_KEY_ID" == "" ]]
    [[ "$OPT_GPG_KEY_FILE" == "" ]]
    [[ "$OPT_ARCH" == "all" ]]
    [[ "$OPT_DISTRO" == "all" ]]
    [[ "$OPT_BASE_URL" == "https://rpms.example.com" ]]
    [[ "$OPT_STAGE" == "" ]]
    [[ "$OPT_ROLLBACK" == false ]]
    [[ "$OPT_SM2_KEY" == "" ]]
}

# ============================================================================
# 2. --version sets OPT_VERSION (Req 2.1)
# ============================================================================

@test "parse_args: --version sets OPT_VERSION" {
    parse_args --version 2.9.0
    [[ "$OPT_VERSION" == "2.9.0" ]]
}

@test "parse_args: --version with pre-release version" {
    parse_args --version 2.10.0-beta.1
    [[ "$OPT_VERSION" == "2.10.0-beta.1" ]]
}

# ============================================================================
# 3. --output sets OPT_OUTPUT (Req 2.2)
# ============================================================================

@test "parse_args: --output sets OPT_OUTPUT" {
    parse_args --output /tmp/my-repo
    [[ "$OPT_OUTPUT" == "/tmp/my-repo" ]]
}

@test "parse_args: --output with relative path" {
    parse_args --output ./build-out
    [[ "$OPT_OUTPUT" == "./build-out" ]]
}

# ============================================================================
# 4. --gpg-key-id sets OPT_GPG_KEY_ID (Req 2.3)
# ============================================================================

@test "parse_args: --gpg-key-id sets OPT_GPG_KEY_ID" {
    parse_args --gpg-key-id ABCDEF1234567890
    [[ "$OPT_GPG_KEY_ID" == "ABCDEF1234567890" ]]
}

# ============================================================================
# 5. --gpg-key-file sets OPT_GPG_KEY_FILE (Req 2.6)
# ============================================================================

@test "parse_args: --gpg-key-file sets OPT_GPG_KEY_FILE" {
    parse_args --gpg-key-file /path/to/private.key
    [[ "$OPT_GPG_KEY_FILE" == "/path/to/private.key" ]]
}

# ============================================================================
# 6. --arch valid values (Req 2.4)
# ============================================================================

@test "parse_args: --arch x86_64 sets OPT_ARCH" {
    parse_args --arch x86_64
    [[ "$OPT_ARCH" == "x86_64" ]]
}

@test "parse_args: --arch aarch64 sets OPT_ARCH" {
    parse_args --arch aarch64
    [[ "$OPT_ARCH" == "aarch64" ]]
}

@test "parse_args: --arch all sets OPT_ARCH" {
    parse_args --arch all
    [[ "$OPT_ARCH" == "all" ]]
}

# ============================================================================
# 7. --arch with invalid value exits 1 (Req 2.8)
# ============================================================================

@test "parse_args: --arch with invalid value exits 1" {
    run parse_args --arch arm64
    assert_failure 1
}

@test "parse_args: --arch with invalid value outputs error" {
    run parse_args --arch i386
    assert_failure 1
    assert_output --partial "仅允许"
}

# ============================================================================
# 8. --distro sets OPT_DISTRO (Req 2.5)
# ============================================================================

@test "parse_args: --distro sets OPT_DISTRO with single value" {
    parse_args --distro anolis:8
    [[ "$OPT_DISTRO" == "anolis:8" ]]
}

@test "parse_args: --distro sets OPT_DISTRO with comma-separated list" {
    parse_args --distro "anolis:8,anolis:23,openEuler:22"
    [[ "$OPT_DISTRO" == "anolis:8,anolis:23,openEuler:22" ]]
}

@test "parse_args: --distro all sets OPT_DISTRO" {
    parse_args --distro all
    [[ "$OPT_DISTRO" == "all" ]]
}

# ============================================================================
# 9. --base-url sets OPT_BASE_URL (Req 13.5)
# ============================================================================

@test "parse_args: --base-url sets OPT_BASE_URL" {
    parse_args --base-url https://cdn.myrepo.cn/packages
    [[ "$OPT_BASE_URL" == "https://cdn.myrepo.cn/packages" ]]
}

# ============================================================================
# 10. --stage valid values (Req 16.1)
# ============================================================================

@test "parse_args: --stage build sets OPT_STAGE" {
    parse_args --stage build
    [[ "$OPT_STAGE" == "build" ]]
}

@test "parse_args: --stage sign sets OPT_STAGE" {
    parse_args --stage sign
    [[ "$OPT_STAGE" == "sign" ]]
}

@test "parse_args: --stage publish sets OPT_STAGE" {
    parse_args --stage publish
    [[ "$OPT_STAGE" == "publish" ]]
}

@test "parse_args: --stage verify sets OPT_STAGE" {
    parse_args --stage verify
    [[ "$OPT_STAGE" == "verify" ]]
}

# ============================================================================
# 11. --stage with invalid value exits 1 (Req 2.8)
# ============================================================================

@test "parse_args: --stage with invalid value exits 1" {
    run parse_args --stage deploy
    assert_failure 1
}

@test "parse_args: --stage with invalid value outputs error" {
    run parse_args --stage test
    assert_failure 1
    assert_output --partial "仅允许"
}

# ============================================================================
# 12. --rollback sets OPT_ROLLBACK=true (Req 12.4)
# ============================================================================

@test "parse_args: --rollback sets OPT_ROLLBACK=true" {
    parse_args --rollback
    [[ "$OPT_ROLLBACK" == true ]]
}

@test "parse_args: without --rollback OPT_ROLLBACK remains false" {
    parse_args --version 2.9.0
    [[ "$OPT_ROLLBACK" == false ]]
}

# ============================================================================
# 13. --sm2-key sets OPT_SM2_KEY (Req 20.2)
# ============================================================================

@test "parse_args: --sm2-key sets OPT_SM2_KEY" {
    parse_args --sm2-key /path/to/sm2.key
    [[ "$OPT_SM2_KEY" == "/path/to/sm2.key" ]]
}

# ============================================================================
# 14. -h/--help exits 0 with usage output (Req 2.9)
# ============================================================================

@test "parse_args: -h exits with code 0" {
    run parse_args -h
    assert_success
}

@test "parse_args: --help exits with code 0" {
    run parse_args --help
    assert_success
}

@test "parse_args: --help outputs usage text" {
    run parse_args --help
    assert_success
    assert_output --partial "用法"
    assert_output --partial "--version"
    assert_output --partial "--output"
    assert_output --partial "--arch"
    assert_output --partial "--stage"
    assert_output --partial "--rollback"
}

# ============================================================================
# 15. Unknown parameter exits 1 (Req 2.8)
# ============================================================================

@test "parse_args: unknown parameter exits with code 1" {
    run parse_args --unknown-flag
    assert_failure 1
}

@test "parse_args: unknown parameter outputs error to stderr" {
    run parse_args --bogus
    assert_failure 1
    assert_output --partial "未知参数"
}

# ============================================================================
# 16. Multiple parameters combined
# ============================================================================

@test "parse_args: multiple parameters combined" {
    parse_args --version 2.9.0 --output /tmp/repo --gpg-key-id KEY123 \
        --gpg-key-file /key.gpg --arch x86_64 --distro "rhel:9,fedora:42" \
        --base-url https://cdn.example.com --stage build --sm2-key /sm2.key
    [[ "$OPT_VERSION" == "2.9.0" ]]
    [[ "$OPT_OUTPUT" == "/tmp/repo" ]]
    [[ "$OPT_GPG_KEY_ID" == "KEY123" ]]
    [[ "$OPT_GPG_KEY_FILE" == "/key.gpg" ]]
    [[ "$OPT_ARCH" == "x86_64" ]]
    [[ "$OPT_DISTRO" == "rhel:9,fedora:42" ]]
    [[ "$OPT_BASE_URL" == "https://cdn.example.com" ]]
    [[ "$OPT_STAGE" == "build" ]]
    [[ "$OPT_SM2_KEY" == "/sm2.key" ]]
}

@test "parse_args: --rollback combined with other params" {
    parse_args --rollback --output /tmp/repo
    [[ "$OPT_ROLLBACK" == true ]]
    [[ "$OPT_OUTPUT" == "/tmp/repo" ]]
}

# ============================================================================
# 17. Missing value for value-requiring params exits 1 (Req 2.8)
# ============================================================================

@test "parse_args: --version without value exits 1" {
    run parse_args --version
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --output without value exits 1" {
    run parse_args --output
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --gpg-key-id without value exits 1" {
    run parse_args --gpg-key-id
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --gpg-key-file without value exits 1" {
    run parse_args --gpg-key-file
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --arch without value exits 1" {
    run parse_args --arch
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --distro without value exits 1" {
    run parse_args --distro
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --base-url without value exits 1" {
    run parse_args --base-url
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --stage without value exits 1" {
    run parse_args --stage
    assert_failure 1
    assert_output --partial "需要一个值"
}

@test "parse_args: --sm2-key without value exits 1" {
    run parse_args --sm2-key
    assert_failure 1
    assert_output --partial "需要一个值"
}
