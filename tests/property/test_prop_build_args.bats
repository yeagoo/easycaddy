#!/usr/bin/env bats
# ============================================================================
# test_prop_build_args.bats — Property 2: 命令行参数解析正确性
# Feature: selfhosted-rpm-repo-builder, Property 2: 命令行参数解析正确性
#
# For any 有效的命令行参数组合（--version、--output、--gpg-key-id、--gpg-key-file、
# --arch、--distro、--base-url、--stage、--sm2-key），parse_args 函数应正确设置
# 对应的全局变量；For any 未知参数字符串，parse_args 应以退出码 1 终止；
# --arch 参数仅接受 x86_64、aarch64 或 all；
# --stage 参数仅接受 build、sign、publish、verify。
#
# **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.8, 20.2**
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

# Reset build-repo.sh global variables between iterations
reset_build_repo_globals() {
    OPT_VERSION=""
    OPT_OUTPUT="./repo"
    OPT_GPG_KEY_ID=""
    OPT_GPG_KEY_FILE=""
    OPT_ARCH="all"
    OPT_DISTRO="all"
    OPT_BASE_URL="https://rpms.example.com"
    OPT_STAGE=""
    OPT_ROLLBACK=false
    OPT_SM2_KEY=""
    TARGET_PRODUCT_LINES=()
    TARGET_ARCHS=()
}

setup() {
    setup_test_env
    source_build_repo_script
    reset_build_repo_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 2a: 有效参数组合 → 全局变量正确设置 (100 iterations)
# ============================================================================

@test "Property 2: random valid parameter combinations correctly set global variables (100 iterations)" {
    for i in $(seq 1 100); do
        reset_build_repo_globals

        local args=()
        local expected_version=""
        local expected_output="./repo"
        local expected_gpg_key_id=""
        local expected_gpg_key_file=""
        local expected_arch="all"
        local expected_distro="all"
        local expected_base_url="https://rpms.example.com"
        local expected_stage=""
        local expected_rollback=false
        local expected_sm2_key=""

        # Randomly add --version
        if (( RANDOM % 3 == 0 )); then
            local ver
            ver="$(gen_caddy_version_number)"
            args+=(--version "$ver")
            expected_version="$ver"
        fi

        # Randomly add --output
        if (( RANDOM % 4 == 0 )); then
            local dirs=(./repo ./output /tmp/repo-test ./build-out)
            local out="${dirs[$(( RANDOM % ${#dirs[@]} ))]}"
            args+=(--output "$out")
            expected_output="$out"
        fi

        # Randomly add --gpg-key-id
        if (( RANDOM % 4 == 0 )); then
            local key_id="ABCD$(( RANDOM % 10000 ))EF"
            args+=(--gpg-key-id "$key_id")
            expected_gpg_key_id="$key_id"
        fi

        # Randomly add --gpg-key-file
        if (( RANDOM % 4 == 0 )); then
            local key_file="/tmp/key-$(( RANDOM % 1000 )).gpg"
            args+=(--gpg-key-file "$key_file")
            expected_gpg_key_file="$key_file"
        fi

        # Randomly add --arch
        if (( RANDOM % 3 == 0 )); then
            local arch
            arch="$(gen_valid_arch)"
            args+=(--arch "$arch")
            expected_arch="$arch"
        fi

        # Randomly add --distro
        if (( RANDOM % 3 == 0 )); then
            local distro
            distro="$(gen_distro_spec)"
            args+=(--distro "$distro")
            expected_distro="$distro"
        fi

        # Randomly add --base-url
        if (( RANDOM % 4 == 0 )); then
            local url
            url="$(gen_base_url)"
            args+=(--base-url "$url")
            expected_base_url="$url"
        fi

        # Randomly add --stage
        if (( RANDOM % 4 == 0 )); then
            local stage
            stage="$(gen_stage_name)"
            args+=(--stage "$stage")
            expected_stage="$stage"
        fi

        # Randomly add --rollback
        if (( RANDOM % 5 == 0 )); then
            args+=(--rollback)
            expected_rollback=true
        fi

        # Randomly add --sm2-key
        if (( RANDOM % 5 == 0 )); then
            local sm2="/tmp/sm2-$(( RANDOM % 1000 )).key"
            args+=(--sm2-key "$sm2")
            expected_sm2_key="$sm2"
        fi

        # Call parse_args with the generated args
        parse_args "${args[@]+"${args[@]}"}"

        # Verify each global variable
        if [[ "$OPT_VERSION" != "$expected_version" ]]; then
            fail "Iteration ${i}: OPT_VERSION='${OPT_VERSION}' expected='${expected_version}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_OUTPUT" != "$expected_output" ]]; then
            fail "Iteration ${i}: OPT_OUTPUT='${OPT_OUTPUT}' expected='${expected_output}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_GPG_KEY_ID" != "$expected_gpg_key_id" ]]; then
            fail "Iteration ${i}: OPT_GPG_KEY_ID='${OPT_GPG_KEY_ID}' expected='${expected_gpg_key_id}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_GPG_KEY_FILE" != "$expected_gpg_key_file" ]]; then
            fail "Iteration ${i}: OPT_GPG_KEY_FILE='${OPT_GPG_KEY_FILE}' expected='${expected_gpg_key_file}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_ARCH" != "$expected_arch" ]]; then
            fail "Iteration ${i}: OPT_ARCH='${OPT_ARCH}' expected='${expected_arch}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_DISTRO" != "$expected_distro" ]]; then
            fail "Iteration ${i}: OPT_DISTRO='${OPT_DISTRO}' expected='${expected_distro}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_BASE_URL" != "$expected_base_url" ]]; then
            fail "Iteration ${i}: OPT_BASE_URL='${OPT_BASE_URL}' expected='${expected_base_url}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_STAGE" != "$expected_stage" ]]; then
            fail "Iteration ${i}: OPT_STAGE='${OPT_STAGE}' expected='${expected_stage}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_ROLLBACK" != "$expected_rollback" ]]; then
            fail "Iteration ${i}: OPT_ROLLBACK='${OPT_ROLLBACK}' expected='${expected_rollback}' args=(${args[*]:-})"
        fi
        if [[ "$OPT_SM2_KEY" != "$expected_sm2_key" ]]; then
            fail "Iteration ${i}: OPT_SM2_KEY='${OPT_SM2_KEY}' expected='${expected_sm2_key}' args=(${args[*]:-})"
        fi
    done
}

# ============================================================================
# Property 2b: 未知参数 → 退出码 1 (100 iterations)
# ============================================================================

@test "Property 2: random unknown parameters exit with code 1 (100 iterations)" {
    local unknown_args=(
        --unknown --foo --bar-baz -z -x
        --install --force --verbose --debug
        --config --dry-run --quiet --recursive
        --target --source --enable --disable
    )

    for i in $(seq 1 100); do
        reset_build_repo_globals

        local idx=$(( RANDOM % ${#unknown_args[@]} ))
        local unknown_arg="${unknown_args[$idx]}"

        run parse_args "$unknown_arg"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: unknown arg '${unknown_arg}' exited with code ${status}, expected 1"
        fi
    done
}

# ============================================================================
# Property 2c: 无效 --arch 值 → 退出码 1 (100 iterations)
# ============================================================================

@test "Property 2: invalid --arch values exit with code 1 (100 iterations)" {
    local invalid_archs=(
        i386 i686 armv7l ppc64le s390x mips64
        sparc64 riscv64 loongarch64 arm32
        X86_64 AARCH64 All ALL x86 aarch
        x64 arm64 ia64 ppc64
    )

    for i in $(seq 1 100); do
        reset_build_repo_globals

        local idx=$(( RANDOM % ${#invalid_archs[@]} ))
        local bad_arch="${invalid_archs[$idx]}"

        run parse_args --arch "$bad_arch"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: invalid arch '${bad_arch}' exited with code ${status}, expected 1"
        fi
    done
}

# ============================================================================
# Property 2d: 无效 --stage 值 → 退出码 1 (100 iterations)
# ============================================================================

@test "Property 2: invalid --stage values exit with code 1 (100 iterations)" {
    local invalid_stages=(
        test deploy release init clean
        package install upload download
        Build Sign Publish Verify
        BUILD SIGN PUBLISH VERIFY
        building signing publishing verifying
    )

    for i in $(seq 1 100); do
        reset_build_repo_globals

        local idx=$(( RANDOM % ${#invalid_stages[@]} ))
        local bad_stage="${invalid_stages[$idx]}"

        run parse_args --stage "$bad_stage"

        if [[ "$status" -ne 1 ]]; then
            fail "Iteration ${i}: invalid stage '${bad_stage}' exited with code ${status}, expected 1"
        fi
    done
}
