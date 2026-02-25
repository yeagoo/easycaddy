#!/usr/bin/env bash
# ============================================================================
# mock_helpers.bash — Mock 工具函数
# 用于模拟 os-release 文件、mock 外部命令（curl、apt-get、dnf 等）
# 所有文件系统操作使用临时目录，测试后自动清理
# ============================================================================

# 全局临时目录（每个测试用例独立）
TEST_TEMP_DIR=""
# Mock 命令的 bin 目录（通过 PATH 注入）
MOCK_BIN_DIR=""
# 原始 PATH（用于恢复）
ORIGINAL_PATH=""

# ============================================================================
# 临时目录管理
# ============================================================================

# 创建测试用临时目录，设置 MOCK_BIN_DIR 并注入 PATH
setup_test_env() {
    TEST_TEMP_DIR="$(mktemp -d)"
    MOCK_BIN_DIR="${TEST_TEMP_DIR}/mock_bin"
    mkdir -p "$MOCK_BIN_DIR"
    ORIGINAL_PATH="$PATH"
    # 将 mock bin 目录放在 PATH 最前面，优先于真实命令
    export PATH="${MOCK_BIN_DIR}:${PATH}"
}

# 清理测试临时目录，恢复 PATH
teardown_test_env() {
    if [[ -n "$ORIGINAL_PATH" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    TEST_TEMP_DIR=""
    MOCK_BIN_DIR=""
    ORIGINAL_PATH=""
}

# ============================================================================
# os-release 文件模拟
# ============================================================================

# 创建模拟的 /etc/os-release 文件
# 用法: create_mock_os_release [ID] [VERSION_ID] [ID_LIKE] [NAME] [PLATFORM_ID]
create_mock_os_release() {
    local id="${1:-linux}"
    local version_id="${2:-1.0}"
    local id_like="${3:-}"
    local name="${4:-Linux}"
    local platform_id="${5:-}"

    local os_release_dir="${TEST_TEMP_DIR}/etc"
    mkdir -p "$os_release_dir"

    local os_release_file="${os_release_dir}/os-release"
    {
        echo "ID=${id}"
        echo "VERSION_ID=\"${version_id}\""
        echo "NAME=\"${name}\""
        if [[ -n "$id_like" ]]; then
            echo "ID_LIKE=\"${id_like}\""
        fi
        if [[ -n "$platform_id" ]]; then
            echo "PLATFORM_ID=\"${platform_id}\""
        fi
    } > "$os_release_file"

    echo "$os_release_file"
}

# 创建带有自定义内容的 os-release 文件
# 用法: create_mock_os_release_raw "RAW_CONTENT"
create_mock_os_release_raw() {
    local content="$1"
    local os_release_dir="${TEST_TEMP_DIR}/etc"
    mkdir -p "$os_release_dir"

    local os_release_file="${os_release_dir}/os-release"
    echo "$content" > "$os_release_file"
    echo "$os_release_file"
}

# ============================================================================
# 外部命令 Mock
# ============================================================================

# 创建 mock 命令脚本
# 用法: create_mock_command <command_name> <exit_code> [stdout_output] [stderr_output]
create_mock_command() {
    local cmd_name="$1"
    local exit_code="${2:-0}"
    local stdout_output="${3:-}"
    local stderr_output="${4:-}"

    local mock_script="${MOCK_BIN_DIR}/${cmd_name}"
    {
        echo '#!/usr/bin/env bash'
        if [[ -n "$stdout_output" ]]; then
            echo "echo '${stdout_output}'"
        fi
        if [[ -n "$stderr_output" ]]; then
            echo "echo '${stderr_output}' >&2"
        fi
        echo "exit ${exit_code}"
    } > "$mock_script"
    chmod +x "$mock_script"
}

# 创建记录调用参数的 mock 命令
# 调用参数会被记录到 ${MOCK_BIN_DIR}/${cmd_name}.args 文件
# 用法: create_recording_mock <command_name> <exit_code> [stdout_output]
create_recording_mock() {
    local cmd_name="$1"
    local exit_code="${2:-0}"
    local stdout_output="${3:-}"

    local mock_script="${MOCK_BIN_DIR}/${cmd_name}"
    local args_file="${MOCK_BIN_DIR}/${cmd_name}.args"

    cat > "$mock_script" << 'MOCK_INNER'
#!/usr/bin/env bash
MOCK_INNER

    # 追加动态部分
    {
        echo "echo \"\$@\" >> '${args_file}'"
        if [[ -n "$stdout_output" ]]; then
            echo "echo '${stdout_output}'"
        fi
        echo "exit ${exit_code}"
    } >> "$mock_script"
    chmod +x "$mock_script"

    # 创建空的 args 文件
    : > "$args_file"
}

# 获取 mock 命令的调用记录
# 用法: get_mock_args <command_name>
get_mock_args() {
    local cmd_name="$1"
    local args_file="${MOCK_BIN_DIR}/${cmd_name}.args"
    if [[ -f "$args_file" ]]; then
        cat "$args_file"
    fi
}

# 获取 mock 命令的调用次数
# 用法: get_mock_call_count <command_name>
get_mock_call_count() {
    local cmd_name="$1"
    local args_file="${MOCK_BIN_DIR}/${cmd_name}.args"
    if [[ -f "$args_file" ]]; then
        wc -l < "$args_file" | tr -d ' '
    else
        echo "0"
    fi
}

# ============================================================================
# 常用 Mock 命令快捷方式
# ============================================================================

# Mock curl 命令（成功，输出指定内容）
mock_curl_success() {
    local output="${1:-}"
    create_mock_command curl 0 "$output"
}

# Mock curl 命令（失败，指定退出码）
mock_curl_failure() {
    local exit_code="${1:-1}"
    local stderr_msg="${2:-curl: connection failed}"
    create_mock_command curl "$exit_code" "" "$stderr_msg"
}

# Mock apt-get 命令（成功）
mock_apt_get_success() {
    create_recording_mock apt-get 0
}

# Mock apt-get 命令（失败）
mock_apt_get_failure() {
    local exit_code="${1:-100}"
    create_mock_command apt-get "$exit_code" "" "E: Unable to fetch packages"
}

# Mock dnf 命令（成功）
mock_dnf_success() {
    create_recording_mock dnf 0
}

# Mock dnf 命令（失败）
mock_dnf_failure() {
    local exit_code="${1:-1}"
    create_mock_command dnf "$exit_code" "" "Error: Failed to install packages"
}

# Mock yum 命令（成功）
mock_yum_success() {
    create_recording_mock yum 0
}

# Mock yum 命令（失败）
mock_yum_failure() {
    local exit_code="${1:-1}"
    create_mock_command yum "$exit_code" "" "Error: Failed to install packages"
}

# Mock systemctl 命令（成功）
mock_systemctl_success() {
    create_recording_mock systemctl 0
}

# Mock systemctl 命令（不可用 — 从 PATH 中移除）
mock_systemctl_unavailable() {
    # 创建一个总是返回 127 的 mock（模拟命令不存在）
    create_mock_command systemctl 127 "" "bash: systemctl: command not found"
}

# Mock setcap 命令（成功）
mock_setcap_success() {
    create_recording_mock setcap 0
}

# Mock setcap 命令（不可用）
mock_setcap_unavailable() {
    create_mock_command setcap 127 "" "bash: setcap: command not found"
}

# Mock setcap 命令（失败）
mock_setcap_failure() {
    create_mock_command setcap 1 "" "Failed to set capabilities"
}

# Mock caddy 命令（已安装，返回版本）
mock_caddy_installed() {
    local version="${1:-v2.7.6}"
    create_mock_command caddy 0 "${version} h1:abc123"
}

# Mock caddy 命令（未安装）
mock_caddy_not_installed() {
    # 移除任何已有的 caddy mock，让 command -v 找不到
    rm -f "${MOCK_BIN_DIR}/caddy"
}

# Mock uname 命令（返回指定架构）
mock_uname_arch() {
    local arch="$1"
    local mock_script="${MOCK_BIN_DIR}/uname"
    cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
# Mock uname: 当参数为 -m 时返回指定架构，其他参数传递给真实 uname
if [[ "\$1" == "-m" ]]; then
    echo "${arch}"
else
    # 调用真实的 uname（跳过 mock）
    local real_uname
    real_uname=\$(which -a uname 2>/dev/null | grep -v "${MOCK_BIN_DIR}" | head -1)
    if [[ -n "\$real_uname" ]]; then
        "\$real_uname" "\$@"
    fi
fi
MOCK_EOF
    chmod +x "$mock_script"
}

# Mock id 命令（返回指定 UID）
mock_id_uid() {
    local uid="$1"
    local mock_script="${MOCK_BIN_DIR}/id"
    cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
if [[ "\$1" == "-u" ]]; then
    echo "${uid}"
else
    echo "${uid}"
fi
MOCK_EOF
    chmod +x "$mock_script"
}

# Mock sudo 命令（可用）
mock_sudo_available() {
    create_mock_command sudo 0
}

# Mock sudo 命令（不可用）
mock_sudo_unavailable() {
    rm -f "${MOCK_BIN_DIR}/sudo"
    # 确保真实 sudo 也不在 PATH 中（如果需要完全隔离）
}

# ============================================================================
# 脚本加载辅助
# ============================================================================

# 获取项目根目录（相对于 tests/ 目录）
get_project_root() {
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    echo "$dir"
}

# Source install-caddy.sh 中的函数（不执行主流程）
# 通过设置一个标志变量来阻止脚本执行 main
source_install_script() {
    local project_root
    project_root="$(get_project_root)"
    local script="${project_root}/install-caddy.sh"

    if [[ ! -f "$script" ]]; then
        echo "ERROR: install-caddy.sh not found at ${script}" >&2
        return 1
    fi

    # Source 脚本但跳过 trap 和主流程执行
    # 我们通过只提取函数定义来实现
    # 先重置全局变量，再 source
    _SOURCED_FOR_TEST=true
    source "$script"
}

# 重置 install-caddy.sh 中的所有全局变量到初始值
reset_script_globals() {
    OPT_VERSION=""
    OPT_METHOD=""
    OPT_PREFIX="/usr/local/bin"
    OPT_MIRROR=""
    OPT_SKIP_SERVICE=false
    OPT_SKIP_CAP=false
    OPT_YES=false

    OS_ID=""
    OS_ID_LIKE=""
    OS_VERSION_ID=""
    OS_NAME=""
    OS_PLATFORM_ID=""
    OS_CLASS=""
    OS_ARCH=""
    OS_ARCH_RAW=""
    EPEL_VERSION=""
    PKG_MANAGER=""

    CADDY_BIN=""
    INSTALL_METHOD_USED=""
    TEMP_DIR=""
    USE_COLOR=true
}
