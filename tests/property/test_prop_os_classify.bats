#!/usr/bin/env bats
# ============================================================================
# test_prop_os_classify.bats — Property 2: OS 分类正确性
# Feature: caddy-installer-china, Property 2: OS 分类正确性
#
# For any OS_ID 和 ID_LIKE 组合，detect_classify 函数应产生正确的 OS_CLASS 值：
# 标准 Debian 系 ID 映射到 standard_deb，标准 RPM 系 ID 映射到 standard_rpm，
# 已知的不支持 COPR 的 RPM 系 ID（满足附加条件）映射到 unsupported_rpm，
# 其他所有 ID 映射到 unknown。
#
# **Validates: Requirements 1.2, 1.3, 1.8**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Test 1: Random standard deb IDs → always standard_deb (100 iterations)
# ============================================================================

@test "Property 2.1: random standard deb IDs always classify as standard_deb (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="$(gen_standard_deb_id)"
        OS_VERSION_ID="$(gen_random_version)"
        OS_ID_LIKE="$(gen_random_id_like)"

        detect_classify

        if [[ "$OS_CLASS" != "standard_deb" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' expected OS_CLASS='standard_deb' got='${OS_CLASS}'"
        fi
    done
}

# ============================================================================
# Test 2: Random standard rpm IDs → always standard_rpm (100 iterations)
# ============================================================================

@test "Property 2.2: random standard rpm IDs always classify as standard_rpm (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="$(gen_standard_rpm_id)"
        OS_VERSION_ID="$(gen_random_version)"
        OS_ID_LIKE="$(gen_random_id_like)"

        detect_classify

        if [[ "$OS_CLASS" != "standard_rpm" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' expected OS_CLASS='standard_rpm' got='${OS_CLASS}'"
        fi
    done
}

# ============================================================================
# Test 3: Random unsupported rpm IDs with proper conditions → always
#          unsupported_rpm (100 iterations)
# ============================================================================

@test "Property 2.3: random unsupported rpm IDs with correct conditions always classify as unsupported_rpm (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="$(gen_unsupported_rpm_id)"

        # Set up the right conditions for each unsupported RPM distro
        case "$OS_ID" in
            kylin)
                # kylin needs ID_LIKE containing rhel/centos/fedora
                OS_ID_LIKE="$(gen_rpm_id_like)"
                OS_VERSION_ID="V10"
                ;;
            amzn)
                # amzn needs VERSION_ID="2023"
                OS_VERSION_ID="2023"
                OS_ID_LIKE=""
                ;;
            openEuler)
                OS_VERSION_ID="$(gen_openeuler_version)"
                OS_ID_LIKE=""
                ;;
            anolis|alinux)
                OS_VERSION_ID="$(gen_anolis_version)"
                OS_ID_LIKE="rhel centos fedora"
                ;;
            opencloudos)
                OS_VERSION_ID="$(gen_opencloudos_version)"
                OS_ID_LIKE=""
                ;;
            ol)
                OS_VERSION_ID="$(gen_ol_version)"
                OS_ID_LIKE="fedora"
                ;;
        esac

        detect_classify

        if [[ "$OS_CLASS" != "unsupported_rpm" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' VERSION_ID='${OS_VERSION_ID}' ID_LIKE='${OS_ID_LIKE}' expected OS_CLASS='unsupported_rpm' got='${OS_CLASS}'"
        fi
    done
}

# ============================================================================
# Test 4: Random unknown IDs → always unknown (100 iterations)
# ============================================================================

@test "Property 2.4: random unknown OS IDs always classify as unknown (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="$(gen_unknown_os_id)"
        OS_VERSION_ID="$(gen_random_version)"
        OS_ID_LIKE="$(gen_random_id_like)"

        detect_classify

        if [[ "$OS_CLASS" != "unknown" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' expected OS_CLASS='unknown' got='${OS_CLASS}'"
        fi
    done
}

# ============================================================================
# Test 5: Mixed random OS_ID from all categories → correct classification
#          (100 iterations)
# ============================================================================

@test "Property 2.5: mixed random OS_IDs from all categories produce correct classification (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="$(gen_random_os_id)"
        OS_VERSION_ID="$(gen_random_version)"
        OS_ID_LIKE="$(gen_random_id_like)"

        # Determine expected classification based on OS_ID
        local expected_class
        case "$OS_ID" in
            debian|ubuntu)
                expected_class="standard_deb"
                ;;
            fedora|centos|rhel|almalinux|rocky)
                expected_class="standard_rpm"
                ;;
            openEuler|anolis|alinux|opencloudos|ol)
                expected_class="unsupported_rpm"
                ;;
            kylin)
                # kylin depends on ID_LIKE
                if [[ "$OS_ID_LIKE" == *rhel* || "$OS_ID_LIKE" == *centos* || "$OS_ID_LIKE" == *fedora* ]]; then
                    expected_class="unsupported_rpm"
                else
                    expected_class="unknown"
                fi
                ;;
            amzn)
                # amzn depends on VERSION_ID
                if [[ "$OS_VERSION_ID" == "2023" ]]; then
                    expected_class="unsupported_rpm"
                else
                    expected_class="unknown"
                fi
                ;;
            *)
                expected_class="unknown"
                ;;
        esac

        detect_classify

        if [[ "$OS_CLASS" != "$expected_class" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' VERSION_ID='${OS_VERSION_ID}' ID_LIKE='${OS_ID_LIKE}' expected='${expected_class}' got='${OS_CLASS}'"
        fi
    done
}
