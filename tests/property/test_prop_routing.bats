#!/usr/bin/env bats
# ============================================================================
# test_prop_routing.bats — Property 6: 安装方式路由正确性
# Feature: caddy-installer-china, Property 6: 安装方式路由正确性
#
# For any OS_CLASS 和 OPT_METHOD 组合，脚本应选择正确的安装方式：
# OPT_METHOD="binary" 时直接二进制下载；standard_deb 使用 APT；
# standard_rpm 使用 COPR；unsupported_rpm 使用自建仓库；unknown 使用二进制下载。
#
# **Validates: Requirements 3.1, 4.1, 5.1, 6.1**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'

# Valid OS_CLASS values for routing
ROUTING_OS_CLASSES=(standard_deb standard_rpm unsupported_rpm unknown)

# Valid OPT_METHOD values for routing
ROUTING_OPT_METHODS=("" repo binary)

# Valid PKG_MANAGER values
ROUTING_PKG_MANAGERS=(apt dnf yum "")

setup() {
    setup_test_env
    source_install_script
    reset_script_globals

    # File to record which install method was called (survives subshell)
    ROUTING_RECORD_FILE="${TEST_TEMP_DIR}/routing_record"
}

teardown() {
    teardown_test_env
}

# Set up all mocks so main() can run without real side effects.
# Install functions write their method name to ROUTING_RECORD_FILE.
_setup_main_mocks() {
    local record_file="$ROUTING_RECORD_FILE"

    # Mock install functions — record which was called
    eval "install_apt_repo() { echo 'apt' > '${record_file}'; return 0; }"
    eval "install_copr_repo() { echo 'copr' > '${record_file}'; return 0; }"
    eval "install_selfhosted_repo() { echo 'selfhosted' > '${record_file}'; return 0; }"
    eval "install_binary_download() { echo 'binary' > '${record_file}'; return 0; }"

    # Mock pre-install functions — set globals directly instead
    eval 'util_has_color() { return 0; }'
    eval 'parse_args() { return 0; }'
    eval 'util_check_root() { return 0; }'
    eval 'detect_os() { return 0; }'
    eval 'detect_arch() { return 0; }'
    eval 'detect_classify() { return 0; }'
    eval 'detect_pkg_manager() { return 0; }'

    # Mock check_installed to return 1 (not installed) so routing proceeds
    eval 'check_installed() { return 1; }'

    # Mock post-processing functions
    eval 'post_disable_service() { return 0; }'
    eval 'post_set_capabilities() { return 0; }'
    eval 'post_verify() { return 0; }'

    # Set CADDY_BIN so main doesn't fail at the path resolution step
    CADDY_BIN="/usr/bin/caddy"
}

# Compute expected install method for a given OS_CLASS/OPT_METHOD combination
_expected_method() {
    local os_class="$1"
    local opt_method="$2"

    if [[ "$opt_method" == "binary" ]]; then
        echo "binary"
        return
    fi

    case "$os_class" in
        standard_deb)    echo "apt" ;;
        standard_rpm)    echo "copr" ;;
        unsupported_rpm) echo "selfhosted" ;;
        unknown|*)       echo "binary" ;;
    esac
}

# ============================================================================
# Test 1: Random OS_CLASS/OPT_METHOD combinations → correct routing
#          (100 iterations)
# ============================================================================

@test "Property 6.1: random OS_CLASS/OPT_METHOD combinations route to correct install method (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals
        _setup_main_mocks

        # Pick random values
        local os_class opt_method pkg_manager
        os_class="$(gen_pick_one "${ROUTING_OS_CLASSES[@]}")"
        opt_method="$(gen_pick_one "${ROUTING_OPT_METHODS[@]}")"
        pkg_manager="$(gen_pick_one "${ROUTING_PKG_MANAGERS[@]}")"

        # Set globals before calling main
        OS_CLASS="$os_class"
        OPT_METHOD="$opt_method"
        PKG_MANAGER="$pkg_manager"
        CADDY_BIN="/usr/bin/caddy"

        # Clear record file
        : > "$ROUTING_RECORD_FILE"

        local expected
        expected="$(_expected_method "$os_class" "$opt_method")"

        # Run main — it exits with 0, install functions write to record file
        run main

        # Read which install method was actually called
        local actual=""
        if [[ -f "$ROUTING_RECORD_FILE" ]]; then
            actual="$(cat "$ROUTING_RECORD_FILE" | tr -d '[:space:]')"
        fi

        if [[ "$actual" != "$expected" ]]; then
            fail "Iteration ${i}: OS_CLASS='${os_class}' OPT_METHOD='${opt_method}' PKG_MANAGER='${pkg_manager}' expected='${expected}' got='${actual}' (exit_status=${status})"
        fi
    done
}
