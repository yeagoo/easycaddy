#!/usr/bin/env bats
# ============================================================================
# test_post_processing.bats — 后置处理单元测试
# 测试 post_disable_service、post_set_capabilities、post_verify 函数
# 场景: systemctl 可用/不可用、setcap 可用/不可用/失败、caddy version 验证成功/失败
# 验证需求: 8.1, 8.2, 8.3, 8.4, 9.1, 9.2, 9.3
# ============================================================================

# 加载 bats 辅助库
load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
    # Mock id to return uid 0 (root) since functions use _run_privileged
    mock_id_uid 0
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Helper: 创建智能 systemctl mock，根据子命令返回不同结果
# 参数:
#   $1 — list-unit-files 是否包含 caddy.service ("yes" / "no")
#   $2 — is-active 退出码 (0=active, 非0=inactive)
#   $3 — is-enabled 退出码 (0=enabled, 非0=disabled)
# ============================================================================
create_smart_systemctl_mock() {
    local has_unit="${1:-yes}"
    local is_active_rc="${2:-0}"
    local is_enabled_rc="${3:-0}"

    local mock_script="${MOCK_BIN_DIR}/systemctl"
    cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
# Record all calls
echo "\$@" >> "${MOCK_BIN_DIR}/systemctl.args"

case "\$1" in
    list-unit-files)
        if [[ "${has_unit}" == "yes" ]]; then
            echo "caddy.service enabled"
            exit 0
        else
            echo ""
            exit 0
        fi
        ;;
    is-active)
        exit ${is_active_rc}
        ;;
    is-enabled)
        exit ${is_enabled_rc}
        ;;
    stop|disable)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_EOF
    chmod +x "$mock_script"
    : > "${MOCK_BIN_DIR}/systemctl.args"
}

# ============================================================================
# post_disable_service: OPT_SKIP_SERVICE=true 时跳过（需求 7.7）
# ============================================================================

@test "post_disable_service: skips when OPT_SKIP_SERVICE=true" {
    OPT_SKIP_SERVICE=true
    create_smart_systemctl_mock "yes" 0 0
    run post_disable_service
    assert_success
    # systemctl should not have been called at all
    [[ ! -s "${MOCK_BIN_DIR}/systemctl.args" ]]
}

# ============================================================================
# post_disable_service: systemctl 不可用时跳过并输出警告（需求 8.4）
# ============================================================================

@test "post_disable_service: skips with warning when systemctl unavailable" {
    OPT_SKIP_SERVICE=false
    # Remove any systemctl from mock bin
    rm -f "${MOCK_BIN_DIR}/systemctl"
    # Also ensure real systemctl is not found by restricting PATH
    local saved_path="$PATH"
    export PATH="${MOCK_BIN_DIR}"
    run post_disable_service
    export PATH="$saved_path"
    assert_success
    assert_output --partial "systemctl 不可用"
}

# ============================================================================
# post_disable_service: caddy.service 不存在时跳过（需求 8.1）
# ============================================================================

@test "post_disable_service: skips when caddy.service does not exist" {
    OPT_SKIP_SERVICE=false
    create_smart_systemctl_mock "no" 1 1
    run post_disable_service
    assert_success
    assert_output --partial "未检测到 caddy.service"
}

# ============================================================================
# post_disable_service: 服务 active 且 enabled 时 stop 和 disable（需求 8.2, 8.3）
# ============================================================================

@test "post_disable_service: stops and disables when service is active and enabled" {
    OPT_SKIP_SERVICE=false
    create_smart_systemctl_mock "yes" 0 0
    run post_disable_service
    assert_success
    # Verify stop and disable were called
    local args
    args="$(cat "${MOCK_BIN_DIR}/systemctl.args")"
    echo "$args" | grep -q "stop caddy.service"
    echo "$args" | grep -q "disable caddy.service"
}

# ============================================================================
# post_disable_service: 服务 active 但未 enabled 时只 stop（需求 8.2）
# ============================================================================

@test "post_disable_service: only stops when service is active but not enabled" {
    OPT_SKIP_SERVICE=false
    # is-active=0 (active), is-enabled=1 (not enabled)
    create_smart_systemctl_mock "yes" 0 1
    run post_disable_service
    assert_success
    local args
    args="$(cat "${MOCK_BIN_DIR}/systemctl.args")"
    echo "$args" | grep -q "stop caddy.service"
    # disable should NOT be called
    ! echo "$args" | grep -q "disable caddy.service"
}

# ============================================================================
# post_disable_service: 服务未 active 但 enabled 时只 disable（需求 8.3）
# ============================================================================

@test "post_disable_service: only disables when service is not active but enabled" {
    OPT_SKIP_SERVICE=false
    # is-active=1 (not active), is-enabled=0 (enabled)
    create_smart_systemctl_mock "yes" 1 0
    run post_disable_service
    assert_success
    local args
    args="$(cat "${MOCK_BIN_DIR}/systemctl.args")"
    # stop should NOT be called
    ! echo "$args" | grep -q "stop caddy.service"
    echo "$args" | grep -q "disable caddy.service"
}

# ============================================================================
# post_set_capabilities: OPT_SKIP_CAP=true 时跳过（需求 7.8）
# ============================================================================

@test "post_set_capabilities: skips when OPT_SKIP_CAP=true" {
    OPT_SKIP_CAP=true
    run post_set_capabilities
    assert_success
}

# ============================================================================
# post_set_capabilities: setcap 不可用时输出警告（需求 9.2）
# ============================================================================

@test "post_set_capabilities: warns when setcap unavailable with libcap hint" {
    OPT_SKIP_CAP=false
    mock_caddy_installed "v2.7.6"
    CADDY_BIN="${MOCK_BIN_DIR}/caddy"
    # Remove setcap from PATH
    rm -f "${MOCK_BIN_DIR}/setcap"
    local saved_path="$PATH"
    export PATH="${MOCK_BIN_DIR}"
    run post_set_capabilities
    export PATH="$saved_path"
    assert_success
    # Should mention libcap2-bin or libcap
    assert_output --partial "libcap"
}

# ============================================================================
# post_set_capabilities: setcap 可用且成功（需求 9.1）
# ============================================================================

@test "post_set_capabilities: succeeds when setcap available and works" {
    OPT_SKIP_CAP=false
    mock_caddy_installed "v2.7.6"
    CADDY_BIN="${MOCK_BIN_DIR}/caddy"
    mock_setcap_success
    run post_set_capabilities
    assert_success
    assert_output --partial "cap_net_bind_service"
}

# ============================================================================
# post_set_capabilities: setcap 执行失败时仅警告不终止（需求 9.3）
# ============================================================================

@test "post_set_capabilities: warns but does not fail when setcap execution fails" {
    OPT_SKIP_CAP=false
    mock_caddy_installed "v2.7.6"
    CADDY_BIN="${MOCK_BIN_DIR}/caddy"
    mock_setcap_failure
    run post_set_capabilities
    assert_success
    assert_output --partial "setcap 执行失败"
}

# ============================================================================
# post_set_capabilities: CADDY_BIN 为空且 caddy 不在 PATH 时跳过
# ============================================================================

@test "post_set_capabilities: skips when CADDY_BIN empty and caddy not in PATH" {
    OPT_SKIP_CAP=false
    CADDY_BIN=""
    mock_caddy_not_installed
    # Restrict PATH so caddy is not found
    local saved_path="$PATH"
    export PATH="${MOCK_BIN_DIR}"
    run post_set_capabilities
    export PATH="$saved_path"
    assert_success
    assert_output --partial "未找到 Caddy 二进制文件"
}

# ============================================================================
# post_verify: caddy version 成功（需求 11.2）
# ============================================================================

@test "post_verify: succeeds when caddy version works" {
    mock_caddy_installed "v2.7.6"
    CADDY_BIN="${MOCK_BIN_DIR}/caddy"
    run post_verify
    assert_success
    assert_output --partial "验证成功"
}

# ============================================================================
# post_verify: caddy 二进制未找到时退出码 1（需求 11.3）
# ============================================================================

@test "post_verify: exits with code 1 when caddy binary not found" {
    CADDY_BIN=""
    mock_caddy_not_installed
    local saved_path="$PATH"
    export PATH="${MOCK_BIN_DIR}"
    run post_verify
    export PATH="$saved_path"
    assert_failure
    assert_output --partial "未找到 Caddy 二进制文件"
}

# ============================================================================
# post_verify: caddy version 失败时退出码 1（需求 11.3）
# ============================================================================

@test "post_verify: exits with code 1 when caddy version fails" {
    # Create a caddy mock that fails on "version" subcommand
    local mock_script="${MOCK_BIN_DIR}/caddy"
    cat > "$mock_script" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$mock_script"
    CADDY_BIN="${mock_script}"
    run post_verify
    assert_failure
    assert_output --partial "caddy version 执行失败"
}
