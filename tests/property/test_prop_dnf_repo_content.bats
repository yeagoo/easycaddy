#!/usr/bin/env bats
# ============================================================================
# Property 21: _generate_dnf_repo_content 输出正确性
# Feature: selfhosted-rpm-repo-builder
# Validates: Requirements 19.1, 19.3, 19.4, 19.5
#
# For any OS_ID, OS_MAJOR_VERSION, arch, and base_url combination,
# _generate_dnf_repo_content should:
# - baseurl uses {base_url}/caddy/{OS_ID}/{OS_MAJOR_VERSION}/$basearch/ format
# - Contains repo_gpgcheck=1
# - name field contains display name and version (not product line name)
# ============================================================================

# Load test helpers
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators_repo'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# --- Generators for install-caddy.sh distro combinations ---

# Known distro combinations: OS_ID, OS_MAJOR_VERSION, OS_NAME
INSTALL_DISTRO_COMBOS=(
    "openEuler:22:openEuler"
    "openEuler:24:openEuler"
    "anolis:8:Anolis OS"
    "anolis:23:Anolis OS"
    "alinux:3:Alibaba Cloud Linux"
    "alinux:4:Alibaba Cloud Linux"
    "kylin:V10:Kylin"
    "kylin:V11:Kylin"
    "amzn:2023:Amazon Linux"
    "ol:8:Oracle Linux"
    "ol:9:Oracle Linux"
    "opencloudos:8:OpenCloudOS"
    "opencloudos:9:OpenCloudOS"
    "centos:8:CentOS"
    "centos:9:CentOS Stream"
    "rhel:8:Red Hat Enterprise Linux"
    "rhel:9:Red Hat Enterprise Linux"
    "almalinux:8:AlmaLinux"
    "rocky:9:Rocky Linux"
    "fedora:42:Fedora"
)

gen_install_distro_combo() {
    local idx=$(( RANDOM % ${#INSTALL_DISTRO_COMBOS[@]} ))
    echo "${INSTALL_DISTRO_COMBOS[$idx]}"
}

gen_install_base_url() {
    local urls=("https://rpms.example.com" "https://cdn.myrepo.cn" "https://repo.internal.net/caddy" "https://mirrors.company.com")
    local idx=$(( RANDOM % ${#urls[@]} ))
    echo "${urls[$idx]}"
}

gen_install_arch() {
    local archs=(x86_64 aarch64)
    local idx=$(( RANDOM % ${#archs[@]} ))
    echo "${archs[$idx]}"
}

# --- Property Tests ---

@test "Property 21: baseurl uses {base_url}/caddy/{OS_ID}/{OS_MAJOR_VERSION}/\$basearch/ format (100 iterations)" {
    for (( i = 0; i < 100; i++ )); do
        local combo base_url arch os_id os_ver os_name
        combo="$(gen_install_distro_combo)"
        base_url="$(gen_install_base_url)"
        arch="$(gen_install_arch)"

        os_id="${combo%%:*}"
        local rest="${combo#*:}"
        os_ver="${rest%%:*}"
        os_name="${rest#*:}"

        OS_NAME="$os_name"
        local output
        output="$(_generate_dnf_repo_content "$base_url" "$os_id" "$os_ver" "$arch")"

        local expected_baseurl="baseurl=${base_url}/caddy/${os_id}/${os_ver}/\$basearch/"
        echo "$output" | grep -qF "$expected_baseurl" || {
            echo "FAIL iteration $i: combo=$combo base_url=$base_url"
            echo "Expected baseurl containing: $expected_baseurl"
            echo "Got output: $output"
            return 1
        }
    done
}

@test "Property 21: repo_gpgcheck=1 is present in output (100 iterations)" {
    for (( i = 0; i < 100; i++ )); do
        local combo base_url arch os_id os_ver os_name
        combo="$(gen_install_distro_combo)"
        base_url="$(gen_install_base_url)"
        arch="$(gen_install_arch)"

        os_id="${combo%%:*}"
        local rest="${combo#*:}"
        os_ver="${rest%%:*}"
        os_name="${rest#*:}"

        OS_NAME="$os_name"
        local output
        output="$(_generate_dnf_repo_content "$base_url" "$os_id" "$os_ver" "$arch")"

        echo "$output" | grep -qF "repo_gpgcheck=1" || {
            echo "FAIL iteration $i: repo_gpgcheck=1 not found"
            echo "Got output: $output"
            return 1
        }
    done
}

@test "Property 21: name field contains display name and version (100 iterations)" {
    for (( i = 0; i < 100; i++ )); do
        local combo base_url arch os_id os_ver os_name
        combo="$(gen_install_distro_combo)"
        base_url="$(gen_install_base_url)"
        arch="$(gen_install_arch)"

        os_id="${combo%%:*}"
        local rest="${combo#*:}"
        os_ver="${rest%%:*}"
        os_name="${rest#*:}"

        OS_NAME="$os_name"
        local output
        output="$(_generate_dnf_repo_content "$base_url" "$os_id" "$os_ver" "$arch")"

        # name should contain the display name and version
        local name_line
        name_line="$(echo "$output" | grep '^name=')"

        echo "$name_line" | grep -qF "$os_name" || {
            echo "FAIL iteration $i: name field missing display name '$os_name'"
            echo "Got: $name_line"
            return 1
        }

        echo "$name_line" | grep -qF "$os_ver" || {
            echo "FAIL iteration $i: name field missing version '$os_ver'"
            echo "Got: $name_line"
            return 1
        }
    done
}

@test "Property 21: gpgkey URL points to {base_url}/caddy/gpg.key (100 iterations)" {
    for (( i = 0; i < 100; i++ )); do
        local combo base_url arch os_id os_ver os_name
        combo="$(gen_install_distro_combo)"
        base_url="$(gen_install_base_url)"
        arch="$(gen_install_arch)"

        os_id="${combo%%:*}"
        local rest="${combo#*:}"
        os_ver="${rest%%:*}"
        os_name="${rest#*:}"

        OS_NAME="$os_name"
        local output
        output="$(_generate_dnf_repo_content "$base_url" "$os_id" "$os_ver" "$arch")"

        echo "$output" | grep -qF "gpgkey=${base_url}/caddy/gpg.key" || {
            echo "FAIL iteration $i: gpgkey URL incorrect"
            echo "Got output: $output"
            return 1
        }
    done
}
