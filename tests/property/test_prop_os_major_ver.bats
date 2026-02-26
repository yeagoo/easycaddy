#!/usr/bin/env bats
# ============================================================================
# Property 22: OS_MAJOR_VERSION 设置正确性
# Feature: selfhosted-rpm-repo-builder
# Validates: Requirements 19.2
#
# For any supported OS_ID and OS_VERSION_ID combination,
# detect_classify should correctly set OS_MAJOR_VERSION to the
# distro's native major version number.
# ============================================================================

# Load test helpers
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

# --- Known OS_ID + VERSION_ID → expected OS_MAJOR_VERSION mappings ---

# Format: "OS_ID:VERSION_ID:ID_LIKE:expected_OS_MAJOR_VERSION"
KNOWN_OS_COMBOS=(
    "openEuler:22.03:fedora:22"
    "openEuler:24.03:fedora:24"
    "anolis:8.8::8"
    "anolis:23.1::23"
    "alinux:3.2::3"
    "alinux:4.0::4"
    "kylin:V10:rhel centos fedora:V10"
    "kylin:V11:rhel centos fedora:V11"
    "amzn:2023::2023"
    "ol:8.9::8"
    "ol:9.3::9"
    "opencloudos:8.8::8"
    "opencloudos:9.0::9"
    "centos:8.5::8"
    "centos:9::9"
    "rhel:8.10::8"
    "rhel:9.4::9"
    "rhel:10.0::10"
    "almalinux:8.9::8"
    "almalinux:9.4::9"
    "rocky:8.9::8"
    "rocky:9.4::9"
    "fedora:42::42"
    "fedora:43::43"
)

gen_os_combo() {
    local idx=$(( RANDOM % ${#KNOWN_OS_COMBOS[@]} ))
    echo "${KNOWN_OS_COMBOS[$idx]}"
}

# --- Property Tests ---

@test "Property 22: OS_MAJOR_VERSION is set correctly for random distro combos (100 iterations)" {
    for (( i = 0; i < 100; i++ )); do
        local combo os_id version_id id_like expected
        combo="$(gen_os_combo)"

        # Parse the combo string
        os_id="$(echo "$combo" | cut -d: -f1)"
        version_id="$(echo "$combo" | cut -d: -f2)"
        id_like="$(echo "$combo" | cut -d: -f3)"
        expected="$(echo "$combo" | cut -d: -f4)"

        # Reset globals
        reset_script_globals
        OS_ID="$os_id"
        OS_VERSION_ID="$version_id"
        OS_ID_LIKE="$id_like"

        # Run detect_classify
        detect_classify

        # Verify OS_MAJOR_VERSION
        if [[ "$OS_MAJOR_VERSION" != "$expected" ]]; then
            echo "FAIL iteration $i: OS_ID=$os_id VERSION_ID=$version_id"
            echo "Expected OS_MAJOR_VERSION='$expected', got '$OS_MAJOR_VERSION'"
            return 1
        fi
    done
}

@test "Property 22: Kylin V10 sets OS_MAJOR_VERSION=V10 regardless of VERSION_ID format" {
    local kylin_v10_versions=("V10" "V10.1" "V10 (Tercel)")
    for ver in "${kylin_v10_versions[@]}"; do
        reset_script_globals
        OS_ID="kylin"
        OS_VERSION_ID="$ver"
        OS_ID_LIKE="rhel centos fedora"

        detect_classify

        if [[ "$OS_MAJOR_VERSION" != "V10" ]]; then
            echo "FAIL: VERSION_ID='$ver' → OS_MAJOR_VERSION='$OS_MAJOR_VERSION' (expected V10)"
            return 1
        fi
    done
}

@test "Property 22: Amazon Linux 2023 sets OS_MAJOR_VERSION=2023" {
    reset_script_globals
    OS_ID="amzn"
    OS_VERSION_ID="2023"

    detect_classify

    assert_equal "$OS_MAJOR_VERSION" "2023"
}

@test "Property 22: openEuler 22.03 sets OS_MAJOR_VERSION=22" {
    reset_script_globals
    OS_ID="openEuler"
    OS_VERSION_ID="22.03"

    detect_classify

    assert_equal "$OS_MAJOR_VERSION" "22"
}

@test "Property 22: openEuler 24.03 sets OS_MAJOR_VERSION=24" {
    reset_script_globals
    OS_ID="openEuler"
    OS_VERSION_ID="24.03"

    detect_classify

    assert_equal "$OS_MAJOR_VERSION" "24"
}

@test "Property 22: Anolis 23 sets OS_MAJOR_VERSION=23" {
    reset_script_globals
    OS_ID="anolis"
    OS_VERSION_ID="23.1"

    detect_classify

    assert_equal "$OS_MAJOR_VERSION" "23"
}

@test "Property 22: alinux 3 sets OS_MAJOR_VERSION=3" {
    reset_script_globals
    OS_ID="alinux"
    OS_VERSION_ID="3.2"

    detect_classify

    assert_equal "$OS_MAJOR_VERSION" "3"
}

@test "Property 22: alinux 4 sets OS_MAJOR_VERSION=4" {
    reset_script_globals
    OS_ID="alinux"
    OS_VERSION_ID="4.0"

    detect_classify

    assert_equal "$OS_MAJOR_VERSION" "4"
}
