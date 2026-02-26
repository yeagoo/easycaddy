#!/usr/bin/env bats
# ============================================================================
# test_prop_arch_dedup.bats — Property 6: 每架构仅下载一次
# Feature: selfhosted-rpm-repo-builder, Property 6: 每架构仅下载一次
#
# For any 产品线集合和架构，同一架构的 Caddy 二进制文件应仅下载一次，
# 在所有产品线间复用。
#
# **Validates: Requirements 5.6**
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
# Property 6a: calling download_caddy_binary twice for same arch → second
# call returns immediately without curl (100 iterations)
# ============================================================================

@test "Property 6: duplicate arch call returns immediately, no curl (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset state
        DOWNLOADED_ARCHS=()

        local version arch go_arch
        version="$(gen_caddy_version_number)"
        arch="$(gen_target_arch)"
        go_arch="$(map_arch_to_go "$arch")"

        CADDY_VERSION="$version"

        # Pre-populate DOWNLOADED_ARCHS to simulate a previous download
        local fake_path="/tmp/caddy-${version}-linux-${go_arch}"
        DOWNLOADED_ARCHS[$arch]="$fake_path"

        # Create a recording mock for curl to detect if it's called
        create_recording_mock curl 0
        : > "${MOCK_BIN_DIR}/curl.args"

        # Call download_caddy_binary directly (not with run) so state is visible
        download_caddy_binary "$arch" 2>/dev/null
        local rc=$?

        if [[ "$rc" -ne 0 ]]; then
            fail "Iteration ${i}: download_caddy_binary failed with exit ${rc} for already-downloaded arch (version=${version}, arch=${arch})"
        fi

        # Verify curl was NOT called
        local curl_calls
        curl_calls="$(get_mock_call_count curl)"
        if [[ "$curl_calls" -ne 0 ]]; then
            fail "Iteration ${i}: curl was called ${curl_calls} time(s) for already-downloaded arch=${arch}"
        fi

        # Verify DOWNLOADED_ARCHS still points to the original path
        if [[ "${DOWNLOADED_ARCHS[$arch]}" != "$fake_path" ]]; then
            fail "Iteration ${i}: DOWNLOADED_ARCHS[${arch}] changed from '${fake_path}' to '${DOWNLOADED_ARCHS[$arch]}'"
        fi
    done
}

# ============================================================================
# Property 6b: multiple product lines with same arch → only one download
# (100 iterations)
# ============================================================================

@test "Property 6: multiple calls for same arch across product lines → single download (100 iterations)" {
    for i in $(seq 1 100); do
        # Reset state
        DOWNLOADED_ARCHS=()

        local version arch go_arch
        version="$(gen_caddy_version_number)"
        arch="$(gen_target_arch)"
        go_arch="$(map_arch_to_go "$arch")"

        CADDY_VERSION="$version"

        # Create work directory with vendor file for the first call
        local work_dir="${TEST_TEMP_DIR}/iter_${i}"
        mkdir -p "${work_dir}/vendor"
        echo "fake-caddy-binary" > "${work_dir}/vendor/caddy-${version}-linux-${go_arch}"

        # Create a recording mock for curl
        create_recording_mock curl 0
        : > "${MOCK_BIN_DIR}/curl.args"

        # Simulate multiple product lines calling download_caddy_binary for same arch
        local num_calls=$(( RANDOM % 5 + 2 ))  # 2-6 calls

        pushd "$work_dir" >/dev/null
        for (( j = 0; j < num_calls; j++ )); do
            download_caddy_binary "$arch" 2>/dev/null
            local rc=$?
            if [[ "$rc" -ne 0 ]]; then
                popd >/dev/null
                fail "Iteration ${i}, call ${j}: download_caddy_binary failed with exit ${rc} (version=${version}, arch=${arch})"
            fi
        done
        popd >/dev/null

        # Verify curl was never called (vendor file was used on first call,
        # subsequent calls reuse DOWNLOADED_ARCHS)
        local curl_calls
        curl_calls="$(get_mock_call_count curl)"
        if [[ "$curl_calls" -ne 0 ]]; then
            fail "Iteration ${i}: curl was called ${curl_calls} time(s) for ${num_calls} calls with same arch=${arch} (vendor file present)"
        fi
    done
}
