#!/usr/bin/env bash
# ============================================================================
# generators_repo.bash — 仓库构建系统专用随机数据生成器
# 用于 build-repo.sh 属性测试中生成随机产品线、distro:version 等
# ============================================================================

# 已知的产品线 ID 列表
KNOWN_PRODUCT_LINES=(el8 el9 el10 al2023 fedora oe22 oe24)

# 有效的 distro:version 对（与 build-repo.sh 中 DISTRO_TO_PRODUCT_LINE 一致）
KNOWN_DISTRO_VERSIONS=(
    "rhel:8" "centos:8" "almalinux:8" "rocky:8" "anolis:8"
    "ol:8" "opencloudos:8" "kylin:V10" "alinux:3"
    "rhel:9" "centos:9" "almalinux:9" "rocky:9" "anolis:23"
    "ol:9" "opencloudos:9" "kylin:V11" "alinux:4"
    "rhel:10" "centos:10" "almalinux:10" "rocky:10" "ol:10"
    "fedora:42" "fedora:43"
    "amzn:2023"
    "openEuler:22" "openEuler:24"
)

# 期望的 distro:version → product_line 映射（用于测试验证）
declare -gA EXPECTED_DISTRO_PL_MAP=(
    [rhel:8]="el8" [centos:8]="el8" [almalinux:8]="el8" [rocky:8]="el8"
    [anolis:8]="el8" [ol:8]="el8" [opencloudos:8]="el8"
    [kylin:V10]="el8" [alinux:3]="el8"
    [rhel:9]="el9" [centos:9]="el9" [almalinux:9]="el9" [rocky:9]="el9"
    [anolis:23]="el9" [ol:9]="el9" [opencloudos:9]="el9"
    [kylin:V11]="el9" [alinux:4]="el9"
    [rhel:10]="el10" [centos:10]="el10" [almalinux:10]="el10"
    [rocky:10]="el10" [ol:10]="el10"
    [amzn:2023]="al2023"
    [fedora:42]="fedora" [fedora:43]="fedora"
    [openEuler:22]="oe22" [openEuler:24]="oe24"
)

# ============================================================================
# 生成器函数
# ============================================================================

# 从 KNOWN_DISTRO_VERSIONS 中随机选择一个有效的 distro:version
gen_valid_distro_version() {
    local idx=$(( RANDOM % ${#KNOWN_DISTRO_VERSIONS[@]} ))
    echo "${KNOWN_DISTRO_VERSIONS[$idx]}"
}

# 生成随机的无效 distro:version 字符串
gen_invalid_distro_version() {
    local invalid_distros=(
        "gentoo:1" "arch:2024" "void:6" "alpine:3"
        "suse:15" "nixos:24" "ubuntu:22" "debian:12"
        "rhel:7" "centos:7" "centos:6" "rhel:6"
        "fedora:38" "fedora:39" "fedora:40"
        "amzn:2" "amzn:1"
        "openEuler:20" "openEuler:21"
        "anolis:7" "alinux:2"
        "unknown:99" "fake:0"
    )
    # Exclude openEuler:20 since it has special handling (warning + skip, not exit 1)
    local filtered=()
    for entry in "${invalid_distros[@]}"; do
        if [[ "$entry" != "openEuler:20" ]]; then
            filtered+=("$entry")
        fi
    done
    local idx=$(( RANDOM % ${#filtered[@]} ))
    echo "${filtered[$idx]}"
}

# 从 KNOWN_PRODUCT_LINES 中随机选择一个产品线 ID
gen_product_line_id() {
    local idx=$(( RANDOM % ${#KNOWN_PRODUCT_LINES[@]} ))
    echo "${KNOWN_PRODUCT_LINES[$idx]}"
}

# 生成随机的 Caddy 版本号（无 v 前缀，如 "2.7.6"）
gen_caddy_version_number() {
    local major=2
    local minor=$(( RANDOM % 10 ))
    local patch=$(( RANDOM % 30 ))
    echo "${major}.${minor}.${patch}"
}

# 生成随机的 --distro 参数值（逗号分隔的 distro:version 列表或 "all"）
gen_distro_spec() {
    # 30% chance of "all"
    if (( RANDOM % 10 < 3 )); then
        echo "all"
        return
    fi
    # Pick 1-4 random distro:version entries
    local count=$(( RANDOM % 4 + 1 ))
    local result=""
    for (( j = 0; j < count; j++ )); do
        local dv
        dv="$(gen_valid_distro_version)"
        if [[ -n "$result" ]]; then
            result="${result},${dv}"
        else
            result="$dv"
        fi
    done
    echo "$result"
}

# 生成随机的 base URL（如 "https://rpms.example.com"）
gen_base_url() {
    local domains=(rpms.example.com cdn.myrepo.cn repo.internal.net mirrors.company.com packages.test.org)
    local paths=("" /caddy /repo /packages)
    local domain="${domains[$(( RANDOM % ${#domains[@]} ))]}"
    local path="${paths[$(( RANDOM % ${#paths[@]} ))]}"
    echo "https://${domain}${path}"
}

# 从 build, sign, publish, verify 中随机选择一个阶段名
gen_stage_name() {
    local stages=(build sign publish verify)
    local idx=$(( RANDOM % ${#stages[@]} ))
    echo "${stages[$idx]}"
}

# 从 x86_64, aarch64, all 中随机选择一个有效架构
gen_valid_arch() {
    local archs=(x86_64 aarch64 all)
    local idx=$(( RANDOM % ${#archs[@]} ))
    echo "${archs[$idx]}"
}

# 生成随机的有效 build-repo.sh 命令行参数组合（返回空格分隔的参数字符串）
# 注意：调用者应将结果放入数组中使用
gen_build_repo_cli_args() {
    local args=()

    # Randomly add --version
    if (( RANDOM % 3 == 0 )); then
        args+=(--version "$(gen_caddy_version_number)")
    fi

    # Randomly add --output
    if (( RANDOM % 4 == 0 )); then
        local dirs=(./repo ./output /tmp/repo-test ./build-out)
        args+=(--output "${dirs[$(( RANDOM % ${#dirs[@]} ))]}")
    fi

    # Randomly add --gpg-key-id
    if (( RANDOM % 4 == 0 )); then
        args+=(--gpg-key-id "ABCD$(( RANDOM % 10000 ))EF")
    fi

    # Randomly add --gpg-key-file
    if (( RANDOM % 4 == 0 )); then
        args+=(--gpg-key-file "/tmp/key-$(( RANDOM % 1000 )).gpg")
    fi

    # Randomly add --arch
    if (( RANDOM % 3 == 0 )); then
        args+=(--arch "$(gen_valid_arch)")
    fi

    # Randomly add --distro
    if (( RANDOM % 3 == 0 )); then
        args+=(--distro "$(gen_distro_spec)")
    fi

    # Randomly add --base-url
    if (( RANDOM % 4 == 0 )); then
        args+=(--base-url "$(gen_base_url)")
    fi

    # Randomly add --stage
    if (( RANDOM % 4 == 0 )); then
        args+=(--stage "$(gen_stage_name)")
    fi

    # Randomly add --rollback
    if (( RANDOM % 5 == 0 )); then
        args+=(--rollback)
    fi

    # Randomly add --sm2-key
    if (( RANDOM % 5 == 0 )); then
        args+=(--sm2-key "/tmp/sm2-$(( RANDOM % 1000 )).key")
    fi

    echo "${args[@]}"
}
