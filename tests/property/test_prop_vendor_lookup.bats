#!/usr/bin/env bats
# ============================================================================
# test_prop_vendor_lookup.bats — Property 4: vendor/ 目录二进制文件查找
# Feature: selfhosted-rpm-repo-builder, Property 4: vendor/ 目录二进制文件查找
#
# For any 版本号和架构组合，当 vendor/caddy-{version}-linux-{go_arch} 文件存在时，
# download_caddy_binary 应使用本地文件而非发起网络下载；
# 当文件不存在时，应从 Caddy_API 下载。
#
# **Validates: Requirements 4.1, 4.2**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'
load '../test_helper/generators_repo'

# Source build-repo.sh for testing (without executing main)
source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

setup() {
    setup_test_env
    source_build_repo_script
}

teardown() {
    teardown_test_env
}

# Helper: pick a random arch from x86_64 or aarch64
gen_target_arch() {
    local archs=(x86_64 aarch64)
    echo "${archs[$(( RANDOM % 2 ))]}"
}

# ============================================================================
# Property 4a: vendor file exists → download_caddy_binary uses local file,
# no curl call (100 iterations)
# ============================================================================

@test "Property 4: vendor file exists → uses local file, no curl (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset state
        DOWNLOADED_ARCHS=()

        local version arch go_arch
        version="$(gen_caddy_version_number)"
        arch="$(gen_target_arch)"
        go_arch="$(map_arch_to_go "$arch")"

        CADDY_VERSION="$version"

        # Create vendor directory and file in TEST_TEMP_DIR
        local work_dir="${TEST_TEMP_DIR}/iter_${i}"
        mkdir -p "${work_dir}/vendor"
        echo "fake-caddy-binary" > "${work_dir}/vendor/caddy-${version}-linux-${go_arch}"

        # Create a recording mock for curl to detect if it's called
        create_recording_mock curl 0

        # Call download_caddy_binary directly (not with run) so DOWNLOADED_ARCHS persists
        pushd "$work_dir" >/dev/null
        download_caddy_binary "$arch" 2>/dev/null
        local rc=$?
        popd >/dev/null

        if [[ "$rc" -ne 0 ]]; then
            fail "Iteration ${i}: download_caddy_binary failed with exit ${rc} when vendor file exists (version=${version}, arch=${arch})"
        fi

        # Verify curl was NOT called
        local curl_calls
        curl_calls="$(get_mock_call_count curl)"
        if [[ "$curl_calls" -ne 0 ]]; then
            fail "Iteration ${i}: curl was called ${curl_calls} time(s) when vendor file exists (version=${version}, arch=${arch})"
        fi

        # Verify DOWNLOADED_ARCHS points to the vendor file
        local expected_path="vendor/caddy-${version}-linux-${go_arch}"
        if [[ "${DOWNLOADED_ARCHS[$arch]:-}" != "$expected_path" ]]; then
            fail "Iteration ${i}: DOWNLOADED_ARCHS[${arch}]='${DOWNLOADED_ARCHS[$arch]:-}', expected '${expected_path}'"
        fi
    done
}

# ============================================================================
# Property 4b: vendor file missing → download_caddy_binary attempts curl
# download (100 iterations)
# ============================================================================

@test "Property 4: vendor file missing → attempts curl download (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset state
        DOWNLOADED_ARCHS=()

        local version arch go_arch
        version="$(gen_caddy_version_number)"
        arch="$(gen_target_arch)"
        go_arch="$(map_arch_to_go "$arch")"

        CADDY_VERSION="$version"

        # Create work directory WITHOUT vendor file
        local work_dir="${TEST_TEMP_DIR}/iter_${i}"
        mkdir -p "${work_dir}"

        # Create a mock for curl that writes a fake binary to the -o destination
        local mock_script="${MOCK_BIN_DIR}/curl"
        local args_file="${MOCK_BIN_DIR}/curl.args"
        cat > "$mock_script" << MOCK_EOF
#!/usr/bin/env bash
echo "\$@" >> '${args_file}'
# Find the -o argument and write fake content there
args=("\$@")
for (( idx=0; idx<\${#args[@]}; idx++ )); do
    if [[ "\${args[\$idx]}" == "-o" ]]; then
        next_idx=\$(( idx + 1 ))
        echo "fake-binary-content" > "\${args[\$next_idx]}"
    fi
done
# Output HTTP status code (curl -w '%{http_code}')
echo "200"
exit 0
MOCK_EOF
        chmod +x "$mock_script"
        : > "$args_file"

        # Call download_caddy_binary from the work directory
        pushd "$work_dir" >/dev/null
        download_caddy_binary "$arch" 2>/dev/null
        local rc=$?
        popd >/dev/null

        if [[ "$rc" -ne 0 ]]; then
            fail "Iteration ${i}: download_caddy_binary failed with exit ${rc} when no vendor file (version=${version}, arch=${arch})"
        fi

        # Verify curl WAS called
        local curl_calls
        curl_calls="$(get_mock_call_count curl)"
        if [[ "$curl_calls" -eq 0 ]]; then
            fail "Iteration ${i}: curl was NOT called when vendor file is missing (version=${version}, arch=${arch})"
        fi
    done
}
