#!/usr/bin/env bats
# ============================================================================
# test_prop_epel_mapping.bats — Property 4: EPEL 版本映射正确性
# Feature: caddy-installer-china, Property 4: EPEL 版本映射正确性
#
# For any Unsupported_RPM_Distro 的 OS_ID 和 VERSION_ID 组合，
# detect_classify 函数应根据映射规则产生正确的 EPEL_VERSION 值（8 或 9）。
#
# EPEL 映射规则:
#   openEuler       → major 20/22 → EPEL 8, others → EPEL 9
#   anolis / alinux → major 8 → EPEL 8, major 23 → EPEL 9, others → EPEL 9
#   opencloudos     → major 8 → EPEL 8, major 9 → EPEL 9, others → EPEL 9
#   kylin           → V10 → EPEL 8 (requires ID_LIKE containing rhel/centos/fedora)
#   amzn            → VERSION_ID=2023 → EPEL 9
#   ol              → major 8 → EPEL 8, major 9 → EPEL 9, others → EPEL 9
#
# **Validates: Requirements 1.4, 1.5, 1.6, 5.2**
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

# Helper: compute expected EPEL_VERSION for a given OS_ID and VERSION_ID
compute_expected_epel() {
    local os_id="$1"
    local version_id="$2"
    local major="${version_id%%.*}"

    case "$os_id" in
        openEuler)
            case "$major" in
                20|22) echo "8" ;;
                *)     echo "9" ;;
            esac
            ;;
        anolis|alinux)
            case "$major" in
                8)  echo "8" ;;
                23) echo "9" ;;
                *)  echo "9" ;;
            esac
            ;;
        opencloudos)
            case "$major" in
                8) echo "8" ;;
                9) echo "9" ;;
                *) echo "9" ;;
            esac
            ;;
        kylin)
            # kylin always maps to EPEL 8
            echo "8"
            ;;
        amzn)
            # amzn 2023 → EPEL 9
            echo "9"
            ;;
        ol)
            case "$major" in
                8) echo "8" ;;
                9) echo "9" ;;
                *) echo "9" ;;
            esac
            ;;
    esac
}

# Helper: generate appropriate VERSION_ID for a given unsupported RPM distro
gen_version_for_distro() {
    local os_id="$1"
    case "$os_id" in
        openEuler)   gen_openeuler_version ;;
        anolis|alinux) gen_anolis_version ;;
        opencloudos) gen_opencloudos_version ;;
        ol)          gen_ol_version ;;
        kylin)       echo "V10" ;;
        amzn)        echo "2023" ;;
    esac
}

# ============================================================================
# Test 1: Random unsupported RPM distro EPEL mapping (100 iterations)
# ============================================================================

@test "Property 4.1: random unsupported RPM distro OS_ID/VERSION_ID → correct EPEL_VERSION (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="$(gen_unsupported_rpm_id)"
        OS_VERSION_ID="$(gen_version_for_distro "$OS_ID")"

        # Set up required conditions
        case "$OS_ID" in
            kylin)
                OS_ID_LIKE="$(gen_rpm_id_like)"
                ;;
            amzn)
                OS_ID_LIKE=""
                ;;
            *)
                OS_ID_LIKE=""
                ;;
        esac

        local expected
        expected="$(compute_expected_epel "$OS_ID" "$OS_VERSION_ID")"

        detect_classify

        if [[ "$EPEL_VERSION" != "$expected" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' VERSION_ID='${OS_VERSION_ID}' expected EPEL_VERSION='${expected}' got='${EPEL_VERSION}'"
        fi

        # Also verify OS_CLASS is unsupported_rpm
        if [[ "$OS_CLASS" != "unsupported_rpm" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' VERSION_ID='${OS_VERSION_ID}' expected OS_CLASS='unsupported_rpm' got='${OS_CLASS}'"
        fi
    done
}

# ============================================================================
# Test 2: openEuler EPEL mapping — major 20/22 → 8, ≥24 → 9 (100 iterations)
# ============================================================================

@test "Property 4.2: openEuler EPEL version mapping correctness (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="openEuler"
        OS_VERSION_ID="$(gen_openeuler_version)"
        OS_ID_LIKE=""

        local expected
        expected="$(compute_expected_epel openEuler "$OS_VERSION_ID")"

        detect_classify

        if [[ "$EPEL_VERSION" != "$expected" ]]; then
            fail "Iteration ${i}: openEuler VERSION_ID='${OS_VERSION_ID}' expected EPEL='${expected}' got='${EPEL_VERSION}'"
        fi
    done
}

# ============================================================================
# Test 3: anolis/alinux EPEL mapping — 8→8, 23→9, others→9 (100 iterations)
# ============================================================================

@test "Property 4.3: anolis/alinux EPEL version mapping correctness (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="$(gen_pick_one anolis alinux)"
        OS_VERSION_ID="$(gen_anolis_version)"
        OS_ID_LIKE="rhel centos fedora"

        local expected
        expected="$(compute_expected_epel "$OS_ID" "$OS_VERSION_ID")"

        detect_classify

        if [[ "$EPEL_VERSION" != "$expected" ]]; then
            fail "Iteration ${i}: OS_ID='${OS_ID}' VERSION_ID='${OS_VERSION_ID}' expected EPEL='${expected}' got='${EPEL_VERSION}'"
        fi
    done
}

# ============================================================================
# Test 4: opencloudos EPEL mapping — 8→8, 9→9, others→9 (100 iterations)
# ============================================================================

@test "Property 4.4: opencloudos EPEL version mapping correctness (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="opencloudos"
        OS_VERSION_ID="$(gen_opencloudos_version)"
        OS_ID_LIKE=""

        local expected
        expected="$(compute_expected_epel opencloudos "$OS_VERSION_ID")"

        detect_classify

        if [[ "$EPEL_VERSION" != "$expected" ]]; then
            fail "Iteration ${i}: opencloudos VERSION_ID='${OS_VERSION_ID}' expected EPEL='${expected}' got='${EPEL_VERSION}'"
        fi
    done
}

# ============================================================================
# Test 5: Oracle Linux EPEL mapping — 8→8, 9→9, others→9 (100 iterations)
# ============================================================================

@test "Property 4.5: Oracle Linux (ol) EPEL version mapping correctness (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="ol"
        OS_VERSION_ID="$(gen_ol_version)"
        OS_ID_LIKE="fedora"

        local expected
        expected="$(compute_expected_epel ol "$OS_VERSION_ID")"

        detect_classify

        if [[ "$EPEL_VERSION" != "$expected" ]]; then
            fail "Iteration ${i}: ol VERSION_ID='${OS_VERSION_ID}' expected EPEL='${expected}' got='${EPEL_VERSION}'"
        fi
    done
}

# ============================================================================
# Test 6: kylin always maps to EPEL 8 (100 iterations)
# ============================================================================

@test "Property 4.6: kylin with valid ID_LIKE always maps to EPEL 8 (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="kylin"
        OS_VERSION_ID="V10"
        OS_ID_LIKE="$(gen_rpm_id_like)"

        detect_classify

        if [[ "$EPEL_VERSION" != "8" ]]; then
            fail "Iteration ${i}: kylin VERSION_ID='${OS_VERSION_ID}' ID_LIKE='${OS_ID_LIKE}' expected EPEL='8' got='${EPEL_VERSION}'"
        fi

        if [[ "$OS_CLASS" != "unsupported_rpm" ]]; then
            fail "Iteration ${i}: kylin expected OS_CLASS='unsupported_rpm' got='${OS_CLASS}'"
        fi
    done
}

# ============================================================================
# Test 7: Amazon Linux 2023 always maps to EPEL 9 (100 iterations)
# ============================================================================

@test "Property 4.7: Amazon Linux 2023 always maps to EPEL 9 (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        OS_ID="amzn"
        OS_VERSION_ID="2023"
        OS_ID_LIKE=""

        detect_classify

        if [[ "$EPEL_VERSION" != "9" ]]; then
            fail "Iteration ${i}: amzn VERSION_ID='2023' expected EPEL='9' got='${EPEL_VERSION}'"
        fi

        if [[ "$OS_CLASS" != "unsupported_rpm" ]]; then
            fail "Iteration ${i}: amzn expected OS_CLASS='unsupported_rpm' got='${OS_CLASS}'"
        fi
    done
}
