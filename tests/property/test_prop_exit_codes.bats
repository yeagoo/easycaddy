#!/usr/bin/env bats
# ============================================================================
# test_prop_exit_codes.bats — Property 12: 退出码映射正确性
# Feature: caddy-installer-china, Property 12: 退出码映射正确性
#
# For any 错误类别，脚本的退出码应与定义的映射一致：
#   成功→0，一般性失败→1，环境不支持→2，网络错误→3，权限不足→4
#
# **Validates: Requirements 10.1, 10.2, 10.3, 10.4, 10.5, 13.5**
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
# Helper: set up a fully-mocked main that succeeds end-to-end
# ============================================================================
_setup_success_mocks() {
    eval 'util_has_color() { USE_COLOR=false; }'
    eval 'parse_args() { return 0; }'
    eval 'util_check_root() { return 0; }'
    eval 'detect_os() { return 0; }'
    eval 'detect_arch() { return 0; }'
    eval 'detect_classify() { return 0; }'
    eval 'detect_pkg_manager() { return 0; }'
    eval 'check_installed() { return 1; }'
    eval 'install_binary_download() { return 0; }'
    eval 'install_apt_repo() { return 0; }'
    eval 'install_copr_repo() { return 0; }'
    eval 'install_selfhosted_repo() { return 0; }'
    eval 'post_disable_service() { return 0; }'
    eval 'post_set_capabilities() { return 0; }'
    eval 'post_verify() { return 0; }'

    OS_CLASS="unknown"
    CADDY_BIN="/usr/bin/caddy"
}

# ============================================================================
# Exit Code 0: Success — main completes successfully
# Validates: Requirement 10.1
# ============================================================================

@test "Property 12.1: exit code 0 on successful install (main with all mocks succeeding)" {
    _setup_success_mocks

    run main
    [ "$status" -eq 0 ]
}

# ============================================================================
# Exit Code 1: General failure — unknown argument
# Validates: Requirement 10.2
# ============================================================================

@test "Property 12.2a: exit code 1 for unknown arguments (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals

        local unknown_arg
        unknown_arg="$(gen_unknown_cli_arg)"

        run parse_args "$unknown_arg"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: parse_args '${unknown_arg}' expected exit 1 but got exit ${status}"
        fi
    done
}

# ============================================================================
# Exit Code 1: General failure — invalid --method value
# Validates: Requirement 10.2
# ============================================================================

@test "Property 12.2b: exit code 1 for invalid --method values" {
    local invalid_methods=(apt dnf yum source compile auto invalid "" "REPO" "BINARY")

    for method in "${invalid_methods[@]}"; do
        reset_script_globals

        run parse_args --method "$method"

        if [[ "$status" -ne 1 ]]; then
            fail "--method '${method}' expected exit 1 but got exit ${status}"
        fi
    done
}

# ============================================================================
# Exit Code 1: General failure — post_verify failure
# Validates: Requirement 10.2
# ============================================================================

@test "Property 12.2c: exit code 1 when post_verify fails (caddy version fails)" {
    # Mock caddy binary that fails on 'version' subcommand
    create_mock_command caddy 1 "" "error: cannot run"
    CADDY_BIN="${MOCK_BIN_DIR}/caddy"

    run post_verify

    [ "$status" -eq 1 ]
}

# ============================================================================
# Exit Code 1: General failure — binary download with empty file
# Validates: Requirement 10.2
# ============================================================================

@test "Property 12.2d: exit code 1 when downloaded binary file is empty" {
    TEMP_DIR="$(mktemp -d)"
    OS_ARCH="amd64"
    OPT_VERSION=""
    OPT_PREFIX="${TEST_TEMP_DIR}/install_dir"
    mkdir -p "$OPT_PREFIX"

    # Mock curl that succeeds but creates an empty file
    local mock_script="${MOCK_BIN_DIR}/curl"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
# Find the -o argument and create an empty file
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) touch "$2"; exit 0 ;;
        *) shift ;;
    esac
done
exit 0
MOCK_EOF
    chmod +x "$mock_script"

    run install_binary_download

    [ "$status" -eq 1 ]

    # Clean up
    rm -rf "$TEMP_DIR"
}

# ============================================================================
# Exit Code 2: Environment unsupported — os-release missing
# Validates: Requirement 10.3
# ============================================================================

@test "Property 12.3a: exit code 2 when os-release file is missing" {
    OS_RELEASE_FILE="${TEST_TEMP_DIR}/nonexistent/os-release"

    run detect_os

    [ "$status" -eq 2 ]
}

# ============================================================================
# Exit Code 2: Environment unsupported — unknown architecture
# Validates: Requirement 10.3
# ============================================================================

@test "Property 12.3b: exit code 2 for unknown architectures (iterates all unknown archs)" {
    for arch in "${UNKNOWN_ARCHS[@]}"; do
        mock_uname_arch "$arch"

        run detect_arch

        if [[ "$status" -ne 2 ]]; then
            fail "Architecture '${arch}' expected exit 2 but got exit ${status}"
        fi
    done
}

# ============================================================================
# Exit Code 3: Network error — curl failures in binary download
# Validates: Requirement 10.4
# ============================================================================

@test "Property 12.4: exit code 3 for curl network errors (all known curl error codes)" {
    local curl_error_codes=(6 7 28 35 22)

    for code in "${curl_error_codes[@]}"; do
        reset_script_globals
        TEMP_DIR="$(mktemp -d)"
        OS_ARCH="amd64"
        OPT_VERSION=""

        mock_curl_failure "$code"

        run install_binary_download

        if [[ "$status" -ne 3 ]]; then
            fail "curl exit code ${code} expected script exit 3 but got exit ${status}"
        fi

        rm -rf "$TEMP_DIR"
    done
}

# ============================================================================
# Exit Code 3: Network error — random curl failure codes also produce exit 3
# Validates: Requirement 10.4
# ============================================================================

@test "Property 12.4b: exit code 3 for random non-zero curl exit codes (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals
        TEMP_DIR="$(mktemp -d)"
        OS_ARCH="amd64"
        OPT_VERSION=""

        local code
        code=$(gen_random_int 1 255)

        mock_curl_failure "$code"

        run install_binary_download

        if [[ "$status" -ne 3 ]]; then
            fail "Iteration ${i}: curl exit code ${code} expected script exit 3 but got exit ${status}"
        fi

        rm -rf "$TEMP_DIR"
    done
}

# ============================================================================
# Exit Code 4: Permission denied — non-root, no sudo
# Validates: Requirement 10.5, 13.5
# ============================================================================

@test "Property 12.5: exit code 4 when non-root and no sudo available" {
    # Mock id to return non-zero UID (non-root)
    mock_id_uid 1000

    # Remove sudo from PATH
    rm -f "${MOCK_BIN_DIR}/sudo"
    # Create a wrapper that hides real sudo
    local mock_script="${MOCK_BIN_DIR}/sudo"
    cat > "$mock_script" << 'MOCK_EOF'
#!/usr/bin/env bash
exit 127
MOCK_EOF
    chmod +x "$mock_script"
    # Actually we need command -v sudo to fail, so remove the mock
    rm -f "${MOCK_BIN_DIR}/sudo"

    # Override command to hide real sudo
    eval 'command() {
        if [[ "$1" == "-v" && "$2" == "sudo" ]]; then
            return 1
        fi
        builtin command "$@"
    }'

    run util_check_root

    [ "$status" -eq 4 ]

    # Restore command
    unset -f command
}

# ============================================================================
# Comprehensive: iterate all exit code categories and verify mapping
# This is the "property" test — for each error category, verify the correct
# exit code is produced.
# ============================================================================

@test "Property 12: comprehensive exit code mapping across all error categories" {
    # Category → expected exit code → trigger function
    # We test each category in sequence

    # --- Exit Code 0: Success ---
    reset_script_globals
    _setup_success_mocks
    run main
    [[ "$status" -eq 0 ]] || fail "Exit code 0 (success): expected 0, got ${status}"

    # Re-source to restore real functions after _setup_success_mocks overrides
    source_install_script

    # --- Exit Code 1: Unknown argument ---
    reset_script_globals
    run parse_args --unknown-arg
    [[ "$status" -eq 1 ]] || fail "Exit code 1 (unknown arg): expected 1, got ${status}"

    # --- Exit Code 1: Invalid method ---
    reset_script_globals
    run parse_args --method invalid
    [[ "$status" -eq 1 ]] || fail "Exit code 1 (invalid method): expected 1, got ${status}"

    # --- Exit Code 1: post_verify failure ---
    reset_script_globals
    create_mock_command caddy 1 "" "error"
    CADDY_BIN="${MOCK_BIN_DIR}/caddy"
    run post_verify
    [[ "$status" -eq 1 ]] || fail "Exit code 1 (verify fail): expected 1, got ${status}"

    # --- Exit Code 2: os-release missing ---
    reset_script_globals
    OS_RELEASE_FILE="${TEST_TEMP_DIR}/nonexistent"
    run detect_os
    [[ "$status" -eq 2 ]] || fail "Exit code 2 (os-release missing): expected 2, got ${status}"

    # --- Exit Code 2: Unknown architecture ---
    reset_script_globals
    mock_uname_arch "sparc64"
    run detect_arch
    [[ "$status" -eq 2 ]] || fail "Exit code 2 (unknown arch): expected 2, got ${status}"

    # --- Exit Code 3: Network error (curl failure) ---
    reset_script_globals
    TEMP_DIR="$(mktemp -d)"
    OS_ARCH="amd64"
    OPT_VERSION=""
    mock_curl_failure 28
    run install_binary_download
    [[ "$status" -eq 3 ]] || fail "Exit code 3 (network error): expected 3, got ${status}"
    rm -rf "$TEMP_DIR"

    # --- Exit Code 4: Permission denied ---
    reset_script_globals
    mock_id_uid 1000
    rm -f "${MOCK_BIN_DIR}/sudo"
    eval 'command() {
        if [[ "$1" == "-v" && "$2" == "sudo" ]]; then
            return 1
        fi
        builtin command "$@"
    }'
    run util_check_root
    [[ "$status" -eq 4 ]] || fail "Exit code 4 (permission denied): expected 4, got ${status}"
    unset -f command
}
