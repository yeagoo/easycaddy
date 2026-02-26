#!/usr/bin/env bats
# ============================================================================
# install-caddy.sh 联动更新单元测试
# 测试 OS_MAJOR_VERSION 设置、_generate_dnf_repo_content 输出、repo_gpgcheck
# Requirements: 19.1–19.5
# ============================================================================

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
# OS_MAJOR_VERSION 设置测试
# ============================================================================

@test "detect_classify: openEuler 22.03 → OS_MAJOR_VERSION=22" {
    OS_ID="openEuler"; OS_VERSION_ID="22.03"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "22"
}

@test "detect_classify: openEuler 24.03 → OS_MAJOR_VERSION=24" {
    OS_ID="openEuler"; OS_VERSION_ID="24.03"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "24"
}

@test "detect_classify: anolis 8.8 → OS_MAJOR_VERSION=8" {
    OS_ID="anolis"; OS_VERSION_ID="8.8"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "8"
}

@test "detect_classify: anolis 23.1 → OS_MAJOR_VERSION=23" {
    OS_ID="anolis"; OS_VERSION_ID="23.1"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "23"
}

@test "detect_classify: alinux 3.2 → OS_MAJOR_VERSION=3" {
    OS_ID="alinux"; OS_VERSION_ID="3.2"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "3"
}

@test "detect_classify: alinux 4.0 → OS_MAJOR_VERSION=4" {
    OS_ID="alinux"; OS_VERSION_ID="4.0"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "4"
}

@test "detect_classify: kylin V10 → OS_MAJOR_VERSION=V10" {
    OS_ID="kylin"; OS_VERSION_ID="V10"; OS_ID_LIKE="rhel centos fedora"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "V10"
}

@test "detect_classify: kylin V11 → OS_MAJOR_VERSION=V11" {
    OS_ID="kylin"; OS_VERSION_ID="V11"; OS_ID_LIKE="rhel centos fedora"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "V11"
}

@test "detect_classify: amzn 2023 → OS_MAJOR_VERSION=2023" {
    OS_ID="amzn"; OS_VERSION_ID="2023"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "2023"
}

@test "detect_classify: rhel 9.4 → OS_MAJOR_VERSION=9" {
    OS_ID="rhel"; OS_VERSION_ID="9.4"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "9"
}

@test "detect_classify: centos 8.5 → OS_MAJOR_VERSION=8" {
    OS_ID="centos"; OS_VERSION_ID="8.5"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "8"
}

@test "detect_classify: fedora 42 → OS_MAJOR_VERSION=42" {
    OS_ID="fedora"; OS_VERSION_ID="42"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "42"
}

@test "detect_classify: ol 9.3 → OS_MAJOR_VERSION=9" {
    OS_ID="ol"; OS_VERSION_ID="9.3"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "9"
}

@test "detect_classify: opencloudos 8.8 → OS_MAJOR_VERSION=8" {
    OS_ID="opencloudos"; OS_VERSION_ID="8.8"
    detect_classify
    assert_equal "$OS_MAJOR_VERSION" "8"
}

# ============================================================================
# _generate_dnf_repo_content 输出测试
# ============================================================================

@test "_generate_dnf_repo_content: baseurl uses distro-friendly path for anolis:8" {
    OS_NAME="Anolis OS"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "anolis" "8" "x86_64")"
    echo "$output" | grep -qF 'baseurl=https://rpms.example.com/caddy/anolis/8/$basearch/'
}

@test "_generate_dnf_repo_content: baseurl uses distro-friendly path for openEuler:22" {
    OS_NAME="openEuler"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "openEuler" "22" "aarch64")"
    echo "$output" | grep -qF 'baseurl=https://rpms.example.com/caddy/openEuler/22/$basearch/'
}

@test "_generate_dnf_repo_content: baseurl uses distro-friendly path for kylin:V10" {
    OS_NAME="Kylin"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "kylin" "V10" "x86_64")"
    echo "$output" | grep -qF 'baseurl=https://rpms.example.com/caddy/kylin/V10/$basearch/'
}

@test "_generate_dnf_repo_content: baseurl uses distro-friendly path for amzn:2023" {
    OS_NAME="Amazon Linux"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "amzn" "2023" "x86_64")"
    echo "$output" | grep -qF 'baseurl=https://rpms.example.com/caddy/amzn/2023/$basearch/'
}

@test "_generate_dnf_repo_content: contains repo_gpgcheck=1" {
    OS_NAME="Test"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "rhel" "9" "x86_64")"
    echo "$output" | grep -qF 'repo_gpgcheck=1'
}

@test "_generate_dnf_repo_content: contains gpgcheck=1" {
    OS_NAME="Test"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "rhel" "9" "x86_64")"
    echo "$output" | grep -qF 'gpgcheck=1'
}

@test "_generate_dnf_repo_content: gpgkey URL correct" {
    OS_NAME="Test"
    local output
    output="$(_generate_dnf_repo_content "https://cdn.myrepo.cn" "centos" "8" "x86_64")"
    echo "$output" | grep -qF 'gpgkey=https://cdn.myrepo.cn/caddy/gpg.key'
}

@test "_generate_dnf_repo_content: name field contains OS_NAME and version" {
    OS_NAME="Anolis OS"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "anolis" "23" "x86_64")"
    local name_line
    name_line="$(echo "$output" | grep '^name=')"
    echo "$name_line" | grep -qF "Anolis OS"
    echo "$name_line" | grep -qF "23"
}

@test "_generate_dnf_repo_content: name field uses OS_NAME not product line name" {
    OS_NAME="openEuler"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "openEuler" "22" "x86_64")"
    local name_line
    name_line="$(echo "$output" | grep '^name=')"
    echo "$name_line" | grep -qF "openEuler"
    echo "$name_line" | grep -qF "22"
    # Should NOT contain "EPEL" or product line names
    ! echo "$name_line" | grep -qF "EPEL"
}

@test "_generate_dnf_repo_content: custom base_url is used correctly" {
    OS_NAME="Test"
    local output
    output="$(_generate_dnf_repo_content "https://custom.mirror.cn/packages" "rhel" "9" "x86_64")"
    echo "$output" | grep -qF 'baseurl=https://custom.mirror.cn/packages/caddy/rhel/9/$basearch/'
    echo "$output" | grep -qF 'gpgkey=https://custom.mirror.cn/packages/caddy/gpg.key'
}

@test "_generate_dnf_repo_content: section header is [caddy-selfhosted]" {
    OS_NAME="Test"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "rhel" "9" "x86_64")"
    echo "$output" | grep -qF '[caddy-selfhosted]'
}

@test "_generate_dnf_repo_content: enabled=1 is present" {
    OS_NAME="Test"
    local output
    output="$(_generate_dnf_repo_content "https://rpms.example.com" "rhel" "9" "x86_64")"
    echo "$output" | grep -qF 'enabled=1'
}
