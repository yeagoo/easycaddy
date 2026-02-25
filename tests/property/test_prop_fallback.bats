#!/usr/bin/env bats
# ============================================================================
# test_prop_fallback.bats — Property 7: 包仓库失败自动回退
# Feature: caddy-installer-china, Property 7: 包仓库失败自动回退
#
# For any 包仓库安装失败的情况，当 OPT_METHOD 不为 "repo" 时，脚本应自动回退到
# Caddy_Download_API 二进制下载方式；当 OPT_METHOD="repo" 时，不应回退而直接以
# 失败退出。
#
# **Validates: Requirements 3.6, 4.5, 5.7**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'

# OS_CLASS values that attempt repo install first (and can fail/fallback)
FALLBACK_OS_CLASSES=(standard_deb standard_rpm unsupported_rpm)

# Get matching PKG_MANAGER for a given OS_CLASS
_pkg_manager_for_class() {
    case "$1" in
        standard_deb)    echo "apt" ;;
        standard_rpm)    echo "dnf" ;;
        unsupported_rpm) echo "dnf" ;;
        *)               echo "" ;;
    esac
}

setup() {
    setup_test_env
    source_install_script
    reset_script_globals

    # File to record which install method was ultimately called
    FALLBACK_RECORD_FILE="${TEST_TEMP_DIR}/fallback_record"
}

teardown() {
    teardown_test_env
}

# Set up mocks for fallback testing.
# Repo install functions FAIL (return 1).
# install_binary_download SUCCEEDS and records "binary".
_setup_fallback_mocks() {
    local record_file="$FALLBACK_RECORD_FILE"

    # Repo install functions — all FAIL
    eval "install_apt_repo() { return 1; }"
    eval "install_copr_repo() { return 1; }"
    eval "install_selfhosted_repo() { return 1; }"

    # Binary download — SUCCEEDS and records
    eval "install_binary_download() { echo 'binary' > '${record_file}'; return 0; }"

    # Mock pre-install functions
    eval 'util_has_color() { return 0; }'
    eval 'parse_args() { return 0; }'
    eval 'util_check_root() { return 0; }'
    eval 'detect_os() { return 0; }'
    eval 'detect_arch() { return 0; }'
    eval 'detect_classify() { return 0; }'
    eval 'detect_pkg_manager() { return 0; }'

    # Mock check_installed to return 1 (not installed)
    eval 'check_installed() { return 1; }'

    # Mock post-processing functions
    eval 'post_disable_service() { return 0; }'
    eval 'post_set_capabilities() { return 0; }'
    eval 'post_verify() { return 0; }'

    # Set CADDY_BIN so path resolution works
    CADDY_BIN="/usr/bin/caddy"
}

# ============================================================================
# Test 1: OPT_METHOD="" (auto) — repo fails → binary fallback triggered
#          (100 iterations with random OS_CLASS)
# ============================================================================

@test "Property 7.1: repo failure with OPT_METHOD='' triggers binary fallback (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals
        _setup_fallback_mocks

        # Pick random OS_CLASS that tries repo first
        local os_class
        os_class="$(gen_pick_one "${FALLBACK_OS_CLASSES[@]}")"
        local pkg_manager
        pkg_manager="$(_pkg_manager_for_class "$os_class")"

        # Set globals — auto mode (no explicit method)
        OS_CLASS="$os_class"
        OPT_METHOD=""
        PKG_MANAGER="$pkg_manager"
        CADDY_BIN="/usr/bin/caddy"

        # Clear record file
        : > "$FALLBACK_RECORD_FILE"

        # Run main — should succeed via binary fallback
        run main

        # Verify exit code is 0 (success via fallback)
        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: OS_CLASS='${os_class}' OPT_METHOD='' expected exit 0 (binary fallback) but got exit ${status}"
        fi

        # Verify binary download was called
        local actual=""
        if [[ -f "$FALLBACK_RECORD_FILE" ]]; then
            actual="$(cat "$FALLBACK_RECORD_FILE" | tr -d '[:space:]')"
        fi

        if [[ "$actual" != "binary" ]]; then
            fail "Iteration ${i}: OS_CLASS='${os_class}' OPT_METHOD='' expected binary fallback but got '${actual}'"
        fi
    done
}

# ============================================================================
# Test 2: OPT_METHOD="repo" — repo fails → exit 1, no binary fallback
#          (100 iterations with random OS_CLASS)
# ============================================================================

@test "Property 7.2: repo failure with OPT_METHOD='repo' exits with failure, no binary fallback (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals
        _setup_fallback_mocks

        # Pick random OS_CLASS that tries repo first
        local os_class
        os_class="$(gen_pick_one "${FALLBACK_OS_CLASSES[@]}")"
        local pkg_manager
        pkg_manager="$(_pkg_manager_for_class "$os_class")"

        # Set globals — repo-only mode
        OS_CLASS="$os_class"
        OPT_METHOD="repo"
        PKG_MANAGER="$pkg_manager"
        CADDY_BIN="/usr/bin/caddy"

        # Clear record file
        : > "$FALLBACK_RECORD_FILE"

        # Run main — should fail (exit 1)
        run main

        # Verify exit code is 1 (failure, no fallback)
        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: OS_CLASS='${os_class}' OPT_METHOD='repo' expected exit 1 but got exit ${status}"
        fi

        # Verify binary download was NOT called
        local actual=""
        if [[ -f "$FALLBACK_RECORD_FILE" ]]; then
            actual="$(cat "$FALLBACK_RECORD_FILE" | tr -d '[:space:]')"
        fi

        if [[ "$actual" == "binary" ]]; then
            fail "Iteration ${i}: OS_CLASS='${os_class}' OPT_METHOD='repo' binary fallback should NOT have been called"
        fi
    done
}
