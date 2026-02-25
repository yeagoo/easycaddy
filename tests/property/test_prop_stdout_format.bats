#!/usr/bin/env bats
# ============================================================================
# test_prop_stdout_format.bats — Property 14: stdout 输出格式正确性
# Feature: caddy-installer-china, Property 14: stdout 输出格式正确性
#
# For any 成功的安装路径，脚本 stdout 的最后一行应为 Caddy 二进制文件的
# 绝对路径（以 `/` 开头），且该路径应与 CADDY_BIN 一致。
#
# **Validates: Requirements 10.6**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'

# Random absolute path components for generating diverse paths
PATH_PREFIXES=(/usr /opt /home /var /srv /tmp /root /mnt /data /app)
PATH_MIDDLES=(bin sbin local/bin caddy/bin tools custom lib exec share)
PATH_USERS=(user admin deploy caddy www ops)

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# Generate a random absolute path for caddy binary
_gen_random_caddy_path() {
    local prefix middle
    prefix="$(gen_pick_one "${PATH_PREFIXES[@]}")"

    # Randomly decide depth (1-3 levels)
    local depth
    depth=$(gen_random_int 1 3)

    local path="$prefix"
    for _ in $(seq 1 "$depth"); do
        middle="$(gen_pick_one "${PATH_MIDDLES[@]}" "${PATH_USERS[@]}")"
        path="${path}/${middle}"
    done
    path="${path}/caddy"
    echo "$path"
}

# Set up all mocks so main() runs to completion with success
_setup_main_mocks() {
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

    # Route to binary download (simplest path)
    OS_CLASS="unknown"
}

# ============================================================================
# Test: 100 random absolute paths — stdout last line is the absolute path
# ============================================================================

@test "Property 14: stdout last line is absolute path matching CADDY_BIN (100 iterations)" {
    for i in $(seq 1 100); do
        reset_script_globals
        _setup_main_mocks

        # Generate a random absolute path
        local random_path
        random_path="$(_gen_random_caddy_path)"

        CADDY_BIN="$random_path"

        run main

        # main should succeed
        if [[ "$status" -ne 0 ]]; then
            fail "Iteration ${i}: main exited with ${status}, expected 0 (CADDY_BIN='${random_path}')"
        fi

        # Get the last line of stdout
        local last_line
        last_line="$(echo "$output" | tail -n 1)"

        # Last line must start with /
        if [[ "$last_line" != /* ]]; then
            fail "Iteration ${i}: last line '${last_line}' does not start with / (CADDY_BIN='${random_path}')"
        fi

        # Last line must match CADDY_BIN
        if [[ "$last_line" != "$random_path" ]]; then
            fail "Iteration ${i}: last line '${last_line}' != CADDY_BIN '${random_path}'"
        fi
    done
}
