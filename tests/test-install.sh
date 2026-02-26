#!/usr/bin/env bash
# ============================================================================
# test-install.sh — 多发行版 RPM 安装测试
# 在各个发行版的 Docker 容器中安装 RPM 并验证基本功能
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPM_DIR="${1:-/tmp/rpm-test}"
HOST_ARCH="$(uname -m)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_DISTROS=()

# 测试矩阵：镜像名 | RPM 相对路径 | RPM 文件名匹配模式 | 显示名称
TESTS=(
    # === 国际发行版 ===
    "almalinux:8|caddy/el8/${HOST_ARCH}/Packages|caddy-*.el8.${HOST_ARCH}.rpm|AlmaLinux 8 (EL8)"
    "almalinux:9|caddy/el9/${HOST_ARCH}/Packages|caddy-*.el9.${HOST_ARCH}.rpm|AlmaLinux 9 (EL9)"
    "almalinux:10|caddy/el10/${HOST_ARCH}/Packages|caddy-*.el10.${HOST_ARCH}.rpm|AlmaLinux 10 (EL10)"
    "rockylinux:8|caddy/el8/${HOST_ARCH}/Packages|caddy-*.el8.${HOST_ARCH}.rpm|Rocky Linux 8 (EL8)"
    "rockylinux:9|caddy/el9/${HOST_ARCH}/Packages|caddy-*.el9.${HOST_ARCH}.rpm|Rocky Linux 9 (EL9)"
    "amazonlinux:2023|caddy/al2023/${HOST_ARCH}/Packages|caddy-*.al2023.${HOST_ARCH}.rpm|Amazon Linux 2023"
    "fedora:42|caddy/fedora/${HOST_ARCH}/Packages|caddy-*.fc.${HOST_ARCH}.rpm|Fedora 42"
    "oraclelinux:8|caddy/el8/${HOST_ARCH}/Packages|caddy-*.el8.${HOST_ARCH}.rpm|Oracle Linux 8 (EL8)"
    "oraclelinux:9|caddy/el9/${HOST_ARCH}/Packages|caddy-*.el9.${HOST_ARCH}.rpm|Oracle Linux 9 (EL9)"
    # === 国产操作系统 ===
    "openanolis/anolisos:8|caddy/el8/${HOST_ARCH}/Packages|caddy-*.el8.${HOST_ARCH}.rpm|Anolis OS 8 (龙蜥)"
    "openanolis/anolisos:23|caddy/el9/${HOST_ARCH}/Packages|caddy-*.el9.${HOST_ARCH}.rpm|Anolis OS 23 (龙蜥)"
    "openeuler/openeuler:22.03-lts|caddy/openeuler/22/${HOST_ARCH}/Packages|caddy-*.oe22.${HOST_ARCH}.rpm|openEuler 22.03 (欧拉)"
    "openeuler/openeuler:24.03-lts|caddy/openeuler/24/${HOST_ARCH}/Packages|caddy-*.oe24.${HOST_ARCH}.rpm|openEuler 24.03 (欧拉)"
    "opencloudos/opencloudos:8.8|caddy/el8/${HOST_ARCH}/Packages|caddy-*.el8.${HOST_ARCH}.rpm|OpenCloudOS 8 (腾讯)"
    "opencloudos/opencloudos:9.0|caddy/el9/${HOST_ARCH}/Packages|caddy-*.el9.${HOST_ARCH}.rpm|OpenCloudOS 9 (腾讯)"
)

run_test() {
    local image="$1"
    local rpm_path="$2"
    local rpm_pattern="$3"
    local display_name="$4"

    printf "${YELLOW}[TEST]${NC} %-40s " "$display_name"

    # 检查 RPM 文件是否存在
    local rpm_file
    rpm_file=$(ls "${RPM_DIR}/${rpm_path}"/${rpm_pattern} 2>/dev/null | head -1)
    if [[ -z "$rpm_file" ]]; then
        printf "${YELLOW}SKIP${NC} (RPM 文件不存在: ${rpm_path}/${rpm_pattern})\n"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return 0
    fi

    local output
    output=$(docker run --rm \
        -v "${RPM_DIR}:/rpms:ro" \
        "$image" \
        bash -c '
            set -euo pipefail
            # 检测容器内实际架构
            CARCH=$(uname -m)
            # 替换路径中的架构占位符
            RPM_PATH="'"$rpm_path"'"
            RPM_PATTERN="'"$rpm_pattern"'"
            RPM_PATH="${RPM_PATH//'"${HOST_ARCH}"'/${CARCH}}"
            RPM_PATTERN="${RPM_PATTERN//'"${HOST_ARCH}"'/${CARCH}}"

            RPM_FILE=$(ls /rpms/${RPM_PATH}/${RPM_PATTERN} 2>/dev/null | head -1)
            [[ -z "$RPM_FILE" ]] && { echo "RPM not found for arch ${CARCH}: /rpms/${RPM_PATH}/${RPM_PATTERN}"; exit 1; }

            # 安装 RPM（兼容 dnf 和 yum）
            if command -v dnf &>/dev/null; then
                dnf install -y "$RPM_FILE" 2>&1
            else
                yum install -y "$RPM_FILE" 2>&1
            fi

            # 验证项
            ERRORS=()

            # 1. 二进制文件
            test -x /usr/bin/caddy || ERRORS+=("binary not executable")

            # 2. 版本输出
            caddy version >/dev/null 2>&1 || ERRORS+=("version command failed")

            # 3. 配置验证
            caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1 || ERRORS+=("config validation failed")

            # 4. 模块加载
            MODULE_COUNT=$(caddy list-modules 2>/dev/null | wc -l)
            [[ "$MODULE_COUNT" -gt 0 ]] || ERRORS+=("no modules loaded")

            # 5. systemd unit
            test -f /usr/lib/systemd/system/caddy.service || ERRORS+=("systemd unit missing")

            # 6. 目录结构
            test -d /etc/caddy || ERRORS+=("/etc/caddy missing")
            test -d /var/lib/caddy || ERRORS+=("/var/lib/caddy missing")

            if [[ ${#ERRORS[@]} -gt 0 ]]; then
                echo "FAILURES: ${ERRORS[*]}"
                exit 1
            fi

            VERSION=$(caddy version 2>/dev/null | head -1)
            echo "OK version=$VERSION modules=$MODULE_COUNT"
        ' 2>&1)

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local version_info
        version_info=$(echo "$output" | grep "^OK " | tail -1)
        printf "${GREEN}PASS${NC} %s\n" "$version_info"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf "${RED}FAIL${NC}\n"
        # 输出最后几行错误信息
        echo "$output" | tail -5 | sed 's/^/    /'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_DISTROS+=("$display_name")
    fi
}

# === 主流程 ===
echo "============================================"
echo " RPM 安装测试 — 多发行版验证"
echo " RPM 目录: ${RPM_DIR}"
echo "============================================"
echo ""

# 检查 RPM 目录
if [[ ! -d "$RPM_DIR" ]]; then
    echo "错误: RPM 目录不存在: $RPM_DIR"
    echo "用法: $0 [rpm_dir]"
    exit 1
fi

echo "找到 RPM 包:"
find "$RPM_DIR" -name '*.rpm' | sort | sed 's/^/  /'
echo ""

for test_entry in "${TESTS[@]}"; do
    IFS='|' read -r image rpm_path rpm_pattern display_name <<< "$test_entry"
    run_test "$image" "$rpm_path" "$rpm_pattern" "$display_name"
done

echo ""
echo "============================================"
echo " 测试结果汇总"
echo "============================================"
printf " 通过: ${GREEN}%d${NC}\n" "$PASS_COUNT"
printf " 失败: ${RED}%d${NC}\n" "$FAIL_COUNT"
printf " 跳过: ${YELLOW}%d${NC}\n" "$SKIP_COUNT"

if [[ ${#FAILED_DISTROS[@]} -gt 0 ]]; then
    echo ""
    printf " 失败的发行版:\n"
    for d in "${FAILED_DISTROS[@]}"; do
        printf "   ${RED}✗${NC} %s\n" "$d"
    done
fi

echo "============================================"

exit "$FAIL_COUNT"
