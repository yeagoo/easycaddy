#!/usr/bin/env bats
# ============================================================================
# test_url_construction.bats — URL 构造单元测试
# 测试 _build_download_url 函数在各种 OS_ARCH/OPT_VERSION 组合下的 URL 构造结果
# 验证需求: 6.2, 6.3
# ============================================================================

# 加载 bats 辅助库
load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# amd64 without version → correct base URL (需求 6.2)
# ============================================================================

@test "_build_download_url: amd64 without version returns correct base URL" {
    OS_ARCH="amd64"
    OPT_VERSION=""
    run _build_download_url
    assert_success
    assert_output "https://caddyserver.com/api/download?os=linux&arch=amd64"
}

# ============================================================================
# arm64 without version → correct base URL (需求 6.2)
# ============================================================================

@test "_build_download_url: arm64 without version returns correct base URL" {
    OS_ARCH="arm64"
    OPT_VERSION=""
    run _build_download_url
    assert_success
    assert_output "https://caddyserver.com/api/download?os=linux&arch=arm64"
}

# ============================================================================
# amd64 with version "2.7.6" → URL includes &version=2.7.6 (需求 6.3)
# ============================================================================

@test "_build_download_url: amd64 with version 2.7.6 appends version param" {
    OS_ARCH="amd64"
    OPT_VERSION="2.7.6"
    run _build_download_url
    assert_success
    assert_output "https://caddyserver.com/api/download?os=linux&arch=amd64&version=2.7.6"
}

# ============================================================================
# arm64 with version "v2.8.0" → URL includes &version=v2.8.0 (需求 6.3)
# ============================================================================

@test "_build_download_url: arm64 with version v2.8.0 appends version param" {
    OS_ARCH="arm64"
    OPT_VERSION="v2.8.0"
    run _build_download_url
    assert_success
    assert_output "https://caddyserver.com/api/download?os=linux&arch=arm64&version=v2.8.0"
}

# ============================================================================
# loongarch64 without version → correct URL (需求 6.2)
# ============================================================================

@test "_build_download_url: loongarch64 without version returns correct URL" {
    OS_ARCH="loongarch64"
    OPT_VERSION=""
    run _build_download_url
    assert_success
    assert_output "https://caddyserver.com/api/download?os=linux&arch=loongarch64"
}

# ============================================================================
# Empty OS_ARCH → still constructs URL (edge case)
# ============================================================================

@test "_build_download_url: empty OS_ARCH still constructs URL" {
    OS_ARCH=""
    OPT_VERSION=""
    run _build_download_url
    assert_success
    assert_output "https://caddyserver.com/api/download?os=linux&arch="
}
