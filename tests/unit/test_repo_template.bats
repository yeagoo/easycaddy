#!/usr/bin/env bats
# ============================================================================
# test_repo_template.bats — .repo 模板生成单元测试
# 测试 generate_repo_templates 函数
# - 模板文件命名格式
# - Fedora 特殊处理（baseurl 不含版本号）
# - 非 Fedora baseurl 含版本号
# - gpgcheck=1 和 repo_gpgcheck=1
# - gpgkey URL 正确
# - SELinux 安装说明注释
# - name 字段包含发行版显示名称和版本
# - 所有 28 个 distro:version 条目均生成模板
# - 模板输出目录为 {STAGING_DIR}/caddy/templates/
#
# Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators_repo'

source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

setup() {
    setup_test_env
    source_build_repo_script
    STAGING_DIR="${TEST_TEMP_DIR}/staging"
    mkdir -p "$STAGING_DIR"
    OPT_BASE_URL="https://rpms.example.com"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# 1. Template file naming: caddy-{distro_id}-{version}.repo (Req 13.2)
# ============================================================================

@test "template file naming: caddy-{distro_id}-{version}.repo for rhel:8" {
    generate_repo_templates 2>/dev/null
    [[ -f "${STAGING_DIR}/caddy/templates/caddy-rhel-8.repo" ]]
}

@test "template file naming: caddy-{distro_id}-{version}.repo for anolis:23" {
    generate_repo_templates 2>/dev/null
    [[ -f "${STAGING_DIR}/caddy/templates/caddy-anolis-23.repo" ]]
}

@test "template file naming: caddy-{distro_id}-{version}.repo for openEuler:22" {
    generate_repo_templates 2>/dev/null
    [[ -f "${STAGING_DIR}/caddy/templates/caddy-openEuler-22.repo" ]]
}

@test "template file naming: caddy-{distro_id}-{version}.repo for fedora:42" {
    generate_repo_templates 2>/dev/null
    [[ -f "${STAGING_DIR}/caddy/templates/caddy-fedora-42.repo" ]]
}

@test "template file naming: caddy-{distro_id}-{version}.repo for kylin:V10" {
    generate_repo_templates 2>/dev/null
    [[ -f "${STAGING_DIR}/caddy/templates/caddy-kylin-V10.repo" ]]
}

@test "template file naming: caddy-{distro_id}-{version}.repo for amzn:2023" {
    generate_repo_templates 2>/dev/null
    [[ -f "${STAGING_DIR}/caddy/templates/caddy-amzn-2023.repo" ]]
}

# ============================================================================
# 2. Fedora baseurl has no version number (Req 13.3)
# ============================================================================

@test "Fedora baseurl does not contain version number" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-fedora-42.repo")"
    echo "$content" | grep -q '^baseurl=https://rpms\.example\.com/caddy/fedora/\$basearch/$'
}

@test "Fedora 43 baseurl also has no version number" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-fedora-43.repo")"
    echo "$content" | grep -q '^baseurl=https://rpms\.example\.com/caddy/fedora/\$basearch/$'
}

# ============================================================================
# 3. Non-Fedora baseurl has version (Req 13.3)
# ============================================================================

@test "non-Fedora baseurl includes distro_id and version for rhel:9" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-rhel-9.repo")"
    echo "$content" | grep -q '^baseurl=https://rpms\.example\.com/caddy/rhel/9/\$basearch/$'
}

@test "non-Fedora baseurl includes distro_id and version for anolis:23" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-anolis-23.repo")"
    echo "$content" | grep -q '^baseurl=https://rpms\.example\.com/caddy/anolis/23/\$basearch/$'
}

@test "non-Fedora baseurl includes distro_id and version for openEuler:22" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-openEuler-22.repo")"
    echo "$content" | grep -q '^baseurl=https://rpms\.example\.com/caddy/openEuler/22/\$basearch/$'
}

@test "non-Fedora baseurl includes distro_id and version for kylin:V10" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-kylin-V10.repo")"
    echo "$content" | grep -q '^baseurl=https://rpms\.example\.com/caddy/kylin/V10/\$basearch/$'
}

# ============================================================================
# 4. gpgcheck=1 present (Req 13.4)
# ============================================================================

@test "gpgcheck=1 is present in repo template" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-rhel-8.repo")"
    echo "$content" | grep -q '^gpgcheck=1$'
}

# ============================================================================
# 5. repo_gpgcheck=1 present (Req 13.4)
# ============================================================================

@test "repo_gpgcheck=1 is present in repo template" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-centos-9.repo")"
    echo "$content" | grep -q '^repo_gpgcheck=1$'
}

# ============================================================================
# 6. gpgkey URL correct (Req 13.4)
# ============================================================================

@test "gpgkey URL points to {base_url}/caddy/gpg.key" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-rocky-8.repo")"
    echo "$content" | grep -q '^gpgkey=https://rpms\.example\.com/caddy/gpg\.key$'
}

@test "gpgkey URL uses custom base_url" {
    OPT_BASE_URL="https://cdn.myrepo.cn/packages"
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-almalinux-9.repo")"
    echo "$content" | grep -q '^gpgkey=https://cdn\.myrepo\.cn/packages/caddy/gpg\.key$'
}

# ============================================================================
# 7. SELinux installation comment present (Req 13.6, 8.4)
# ============================================================================

@test "SELinux installation comment mentions caddy-selinux" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-rhel-8.repo")"
    echo "$content" | grep -q 'caddy-selinux'
}

@test "SELinux comment is present in Fedora template too" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-fedora-42.repo")"
    echo "$content" | grep -q 'caddy-selinux'
}

# ============================================================================
# 8. name field contains distro display name and version (Req 13.3)
# ============================================================================

@test "name field contains RHEL and version 8" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-rhel-8.repo")"
    echo "$content" | grep -q 'name=.*RHEL.*8'
}

@test "name field contains Anolis OS and version 23" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-anolis-23.repo")"
    echo "$content" | grep -q 'name=.*Anolis OS.*23'
}

@test "name field contains openEuler and version 22" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-openEuler-22.repo")"
    echo "$content" | grep -q 'name=.*openEuler.*22'
}

@test "name field contains Fedora and version 42" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-fedora-42.repo")"
    echo "$content" | grep -q 'name=.*Fedora.*42'
}

@test "name field contains Amazon Linux and version 2023" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-amzn-2023.repo")"
    echo "$content" | grep -q 'name=.*Amazon Linux.*2023'
}

@test "name field contains Kylin and version V10" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-kylin-V10.repo")"
    echo "$content" | grep -q 'name=.*Kylin.*V10'
}

@test "name field contains Alibaba Cloud Linux and version 3" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-alinux-3.repo")"
    echo "$content" | grep -q 'name=.*Alibaba Cloud Linux.*3'
}

@test "name field contains Oracle Linux and version 9" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-ol-9.repo")"
    echo "$content" | grep -q 'name=.*Oracle Linux.*9'
}

@test "name field contains Rocky Linux and version 10" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-rocky-10.repo")"
    echo "$content" | grep -q 'name=.*Rocky Linux.*10'
}

@test "name field contains OpenCloudOS and version 8" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-opencloudos-8.repo")"
    echo "$content" | grep -q 'name=.*OpenCloudOS.*8'
}

@test "name field contains CentOS and version 10" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-centos-10.repo")"
    echo "$content" | grep -q 'name=.*CentOS.*10'
}

@test "name field contains AlmaLinux and version 8" {
    generate_repo_templates 2>/dev/null

    local content
    content="$(cat "${STAGING_DIR}/caddy/templates/caddy-almalinux-8.repo")"
    echo "$content" | grep -q 'name=.*AlmaLinux.*8'
}

# ============================================================================
# 9. All 28 distro:version entries generate templates (Req 13.1)
# ============================================================================

@test "all 28 distro:version entries generate template files" {
    generate_repo_templates 2>/dev/null

    local templates_dir="${STAGING_DIR}/caddy/templates"
    local count
    count="$(find "$templates_dir" -name '*.repo' -type f | wc -l | tr -d ' ')"
    [[ "$count" -eq 28 ]]
}

@test "every known distro:version has a corresponding .repo file" {
    generate_repo_templates 2>/dev/null

    local templates_dir="${STAGING_DIR}/caddy/templates"
    for dv in "${KNOWN_DISTRO_VERSIONS[@]}"; do
        local distro_id="${dv%%:*}"
        local version="${dv#*:}"
        local repo_file="${templates_dir}/caddy-${distro_id}-${version}.repo"
        if [[ ! -f "$repo_file" ]]; then
            fail "Missing .repo file for ${dv}: expected ${repo_file}"
        fi
    done
}

# ============================================================================
# 10. Templates directory is {STAGING_DIR}/caddy/templates/ (Req 13.1)
# ============================================================================

@test "templates are written to {STAGING_DIR}/caddy/templates/ directory" {
    generate_repo_templates 2>/dev/null

    [[ -d "${STAGING_DIR}/caddy/templates" ]]
    local count
    count="$(find "${STAGING_DIR}/caddy/templates" -name '*.repo' -type f | wc -l | tr -d ' ')"
    [[ "$count" -gt 0 ]]
}

@test "no .repo files are created outside the templates directory" {
    generate_repo_templates 2>/dev/null

    # Check that no .repo files exist directly under caddy/
    local stray_count
    stray_count="$(find "${STAGING_DIR}/caddy" -maxdepth 1 -name '*.repo' -type f | wc -l | tr -d ' ')"
    [[ "$stray_count" -eq 0 ]]
}
