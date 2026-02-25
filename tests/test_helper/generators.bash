#!/usr/bin/env bash
# ============================================================================
# generators.bash — 随机数据生成器
# 用于属性测试中生成随机 OS_ID、版本号、架构字符串、参数组合等
# ============================================================================

# 已知的标准 Debian 系发行版 ID
KNOWN_STANDARD_DEB_IDS=(debian ubuntu)

# 已知的标准 RPM 系发行版 ID
KNOWN_STANDARD_RPM_IDS=(fedora centos rhel almalinux rocky)

# 已知的 COPR 不支持的 RPM 系发行版 ID
KNOWN_UNSUPPORTED_RPM_IDS=(openEuler anolis alinux opencloudos kylin amzn ol)

# 所有已知发行版 ID
KNOWN_ALL_IDS=("${KNOWN_STANDARD_DEB_IDS[@]}" "${KNOWN_STANDARD_RPM_IDS[@]}" "${KNOWN_UNSUPPORTED_RPM_IDS[@]}")

# 已知支持的架构
KNOWN_SUPPORTED_ARCHS=(x86_64 aarch64)

# 已知可选支持的架构
KNOWN_OPTIONAL_ARCHS=(loongarch64 riscv64)

# 所有已知架构（含可选）
KNOWN_ALL_ARCHS=("${KNOWN_SUPPORTED_ARCHS[@]}" "${KNOWN_OPTIONAL_ARCHS[@]}")

# 未知架构示例（用于测试拒绝逻辑）
UNKNOWN_ARCHS=(mips64 s390x ppc64le armv7l sparc64 i686 i386)

# 有效的 --method 值
VALID_METHODS=(repo binary "")

# 生成随机整数 [min, max]
gen_random_int() {
    local min="$1"
    local max="$2"
    echo $(( RANDOM % (max - min + 1) + min ))
}

# 从数组中随机选择一个元素
gen_pick_one() {
    local arr=("$@")
    local idx=$(( RANDOM % ${#arr[@]} ))
    echo "${arr[$idx]}"
}

# 生成随机的标准 Debian 系 OS_ID
gen_standard_deb_id() {
    gen_pick_one "${KNOWN_STANDARD_DEB_IDS[@]}"
}

# 生成随机的标准 RPM 系 OS_ID
gen_standard_rpm_id() {
    gen_pick_one "${KNOWN_STANDARD_RPM_IDS[@]}"
}

# 生成随机的 Unsupported RPM 系 OS_ID
gen_unsupported_rpm_id() {
    gen_pick_one "${KNOWN_UNSUPPORTED_RPM_IDS[@]}"
}

# 生成随机的已知 OS_ID（任意分类）
gen_known_os_id() {
    gen_pick_one "${KNOWN_ALL_IDS[@]}"
}

# 生成随机的未知 OS_ID（不在已知列表中）
gen_unknown_os_id() {
    local unknown_ids=(gentoo arch void alpine suse nixos)
    gen_pick_one "${unknown_ids[@]}"
}

# 生成随机的 OS_ID（包含已知和未知）
gen_random_os_id() {
    local all_ids=("${KNOWN_ALL_IDS[@]}" gentoo arch void alpine suse)
    gen_pick_one "${all_ids[@]}"
}

# 生成随机版本号（语义化版本格式）
gen_random_version() {
    local major minor patch
    major=$(gen_random_int 0 30)
    minor=$(gen_random_int 0 99)
    patch=$(gen_random_int 0 99)
    echo "${major}.${minor}.${patch}"
}

# 生成随机的简单版本号（主版本.次版本）
gen_random_version_short() {
    local major minor
    major=$(gen_random_int 1 30)
    minor=$(gen_random_int 0 99)
    echo "${major}.${minor}"
}

# 生成随机的主版本号字符串
gen_random_major_version() {
    gen_random_int 7 25
}

# 生成 openEuler 的随机版本号
gen_openeuler_version() {
    local versions=(20.03 22.03 24.03 24.09 25.03)
    gen_pick_one "${versions[@]}"
}

# 生成 anolis/alinux 的随机版本号
gen_anolis_version() {
    local versions=(8.2 8.4 8.6 8.8 8.9 23.0 23.1)
    gen_pick_one "${versions[@]}"
}

# 生成 opencloudos 的随机版本号
gen_opencloudos_version() {
    local versions=(8.5 8.6 8.8 9.0 9.2)
    gen_pick_one "${versions[@]}"
}

# 生成 Oracle Linux 的随机版本号
gen_ol_version() {
    local versions=(8.1 8.5 8.8 8.9 9.0 9.2 9.4)
    gen_pick_one "${versions[@]}"
}

# 生成随机的已知架构字符串
gen_known_arch() {
    gen_pick_one "${KNOWN_ALL_ARCHS[@]}"
}

# 生成随机的支持架构字符串（x86_64 或 aarch64）
gen_supported_arch() {
    gen_pick_one "${KNOWN_SUPPORTED_ARCHS[@]}"
}

# 生成随机的未知架构字符串
gen_unknown_arch() {
    gen_pick_one "${UNKNOWN_ARCHS[@]}"
}

# 生成随机架构字符串（包含已知和未知）
gen_random_arch() {
    local all=("${KNOWN_ALL_ARCHS[@]}" "${UNKNOWN_ARCHS[@]}")
    gen_pick_one "${all[@]}"
}

# 生成随机的 Caddy 版本号（如 v2.7.6）
gen_caddy_version() {
    local major=2
    local minor
    minor=$(gen_random_int 0 9)
    local patch
    patch=$(gen_random_int 0 20)
    echo "v${major}.${minor}.${patch}"
}

# 生成随机的镜像 URL
gen_random_mirror_url() {
    local protocols=(http https)
    local domains=(mirror.example.com cdn.mycompany.cn repo.internal.net mirrors.aliyun.com)
    local paths=(/caddy /packages/caddy /repo/caddy "")
    local proto domain path
    proto=$(gen_pick_one "${protocols[@]}")
    domain=$(gen_pick_one "${domains[@]}")
    path=$(gen_pick_one "${paths[@]}")
    echo "${proto}://${domain}${path}"
}

# 生成随机的安装前缀路径
gen_random_prefix() {
    local prefixes=(/usr/local/bin /usr/bin /opt/caddy/bin /home/user/bin /custom/path)
    gen_pick_one "${prefixes[@]}"
}

# 生成随机的 ID_LIKE 字符串
gen_random_id_like() {
    local id_likes=(
        "rhel centos fedora"
        "rhel fedora"
        "centos rhel"
        "debian"
        "ubuntu debian"
        "fedora"
        ""
    )
    gen_pick_one "${id_likes[@]}"
}

# 生成随机的 RPM 系 ID_LIKE 字符串
gen_rpm_id_like() {
    local id_likes=(
        "rhel centos fedora"
        "rhel fedora"
        "centos rhel"
        "fedora"
    )
    gen_pick_one "${id_likes[@]}"
}

# 生成随机的日志消息（含特殊字符）
gen_random_log_message() {
    local messages=(
        "安装 Caddy Server 版本 $(gen_caddy_version)"
        "检测到操作系统: $(gen_known_os_id)"
        "下载文件到 /tmp/caddy-$(gen_random_int 1000 9999)"
        "Simple ASCII message"
        "Message with special chars: \$PATH & <tag> \"quotes\""
        "Empty-ish"
        "Multi word message with spaces and tabs	here"
        "Unicode: 你好世界 🚀"
        "Path: /usr/local/bin/caddy"
        "Version: $(gen_random_version)"
    )
    gen_pick_one "${messages[@]}"
}

# 生成随机的命令行参数组合
gen_random_cli_args() {
    local args=()

    # 随机添加 --version
    if (( RANDOM % 3 == 0 )); then
        args+=(--version "$(gen_caddy_version)")
    fi

    # 随机添加 --method
    if (( RANDOM % 3 == 0 )); then
        local method
        method=$(gen_pick_one repo binary)
        args+=(--method "$method")
    fi

    # 随机添加 --prefix
    if (( RANDOM % 4 == 0 )); then
        args+=(--prefix "$(gen_random_prefix)")
    fi

    # 随机添加 --mirror
    if (( RANDOM % 4 == 0 )); then
        args+=(--mirror "$(gen_random_mirror_url)")
    fi

    # 随机添加 --skip-service
    if (( RANDOM % 4 == 0 )); then
        args+=(--skip-service)
    fi

    # 随机添加 --skip-cap
    if (( RANDOM % 4 == 0 )); then
        args+=(--skip-cap)
    fi

    # 随机添加 -y/--yes
    if (( RANDOM % 4 == 0 )); then
        local yes_flag
        yes_flag=$(gen_pick_one -y --yes)
        args+=("$yes_flag")
    fi

    echo "${args[@]}"
}

# 生成随机的未知参数
gen_unknown_cli_arg() {
    local unknown_args=(
        --unknown
        --foo
        --bar-baz
        -z
        -x
        --install
        --force
        --verbose
        --debug
        --output
    )
    gen_pick_one "${unknown_args[@]}"
}

# 生成随机的 EPEL 版本
gen_random_epel_version() {
    gen_pick_one 8 9
}

# 生成随机的 OS_NAME
gen_random_os_name() {
    local names=(
        "Debian GNU/Linux"
        "Ubuntu"
        "Fedora Linux"
        "CentOS Stream"
        "Red Hat Enterprise Linux"
        "AlmaLinux"
        "Rocky Linux"
        "openEuler"
        "Anolis OS"
        "Alibaba Cloud Linux"
        "OpenCloudOS"
        "Kylin Linux Advanced Server"
        "Amazon Linux"
        "Oracle Linux Server"
    )
    gen_pick_one "${names[@]}"
}

# 生成随机的 PLATFORM_ID
gen_random_platform_id() {
    local platform_ids=(
        "platform:el8"
        "platform:el9"
        "platform:f38"
        "platform:f39"
        ""
    )
    gen_pick_one "${platform_ids[@]}"
}
