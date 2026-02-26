#!/usr/bin/env bats
# ============================================================================
# test_prop_env_to_args.bats — Property 2: 环境变量到 CLI 参数映射
# Feature: docker-repo-system, Property 2: 环境变量到 CLI 参数映射
#
# For any 环境变量组合（CADDY_VERSION、TARGET_ARCH、TARGET_DISTRO、BASE_URL、GPG_KEY_ID），
# 容器 entrypoint 脚本应将其正确转换为对应的 build-repo.sh 命令行参数。
# 未设置的环境变量不应生成对应参数。
#
# Test approach: For 100 iterations, generate random env var combinations using
# gen_env_vars, source the entrypoint script, call build_args, and verify:
# 1. --stage build and --output /repo are always present
# 2. For each set env var, the corresponding --flag and value appear in output
# 3. For each unset env var, the corresponding --flag does NOT appear in output
#
# **Validates: Requirements 1.4, 2.5**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/generators_docker.bash"
    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/builder/entrypoint.sh"
}

# ============================================================================
# Property 2: 环境变量到 CLI 参数映射 (100 iterations)
# ============================================================================

@test "Property 2: 环境变量到 CLI 参数映射 — 随机环境变量组合正确映射为 CLI 参数" {
    for i in $(seq 1 100); do
        # Clear all env vars
        unset CADDY_VERSION TARGET_ARCH TARGET_DISTRO BASE_URL GPG_KEY_ID 2>/dev/null || true

        # Generate and apply random env vars
        local env_output
        env_output="$(gen_env_vars)"

        # Track which vars are set
        local has_version=false has_arch=false has_distro=false has_base_url=false
        local val_version="" val_arch="" val_distro="" val_base_url=""

        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            export "$key=$value"
            case "$key" in
                CADDY_VERSION) has_version=true; val_version="$value" ;;
                TARGET_ARCH) has_arch=true; val_arch="$value" ;;
                TARGET_DISTRO) has_distro=true; val_distro="$value" ;;
                BASE_URL) has_base_url=true; val_base_url="$value" ;;
            esac
        done <<< "$env_output"

        # Call build_args
        local args_output
        args_output="$(build_args)"

        # Always present: --stage build --output /repo
        echo "$args_output" | grep -q -- '--stage' || \
            fail "Iteration ${i}: --stage not found in output. Env: ${env_output}. Output: ${args_output}"
        echo "$args_output" | grep -q -- 'build' || \
            fail "Iteration ${i}: 'build' not found in output. Env: ${env_output}. Output: ${args_output}"
        echo "$args_output" | grep -q -- '--output' || \
            fail "Iteration ${i}: --output not found in output. Env: ${env_output}. Output: ${args_output}"
        echo "$args_output" | grep -q -- '/repo' || \
            fail "Iteration ${i}: '/repo' not found in output. Env: ${env_output}. Output: ${args_output}"

        # Conditional args: CADDY_VERSION → --version
        if $has_version; then
            echo "$args_output" | grep -q -- '--version' || \
                fail "Iteration ${i}: --version not found but CADDY_VERSION=${val_version} is set. Output: ${args_output}"
            echo "$args_output" | grep -q -- "$val_version" || \
                fail "Iteration ${i}: value '${val_version}' not found in output. Output: ${args_output}"
        else
            ! echo "$args_output" | grep -q -- '--version' || \
                fail "Iteration ${i}: --version found but CADDY_VERSION is not set. Output: ${args_output}"
        fi

        # Conditional args: TARGET_ARCH → --arch
        if $has_arch; then
            echo "$args_output" | grep -q -- '--arch' || \
                fail "Iteration ${i}: --arch not found but TARGET_ARCH=${val_arch} is set. Output: ${args_output}"
            echo "$args_output" | grep -q -- "$val_arch" || \
                fail "Iteration ${i}: value '${val_arch}' not found in output. Output: ${args_output}"
        else
            ! echo "$args_output" | grep -q -- '--arch' || \
                fail "Iteration ${i}: --arch found but TARGET_ARCH is not set. Output: ${args_output}"
        fi

        # Conditional args: TARGET_DISTRO → --distro
        if $has_distro; then
            echo "$args_output" | grep -q -- '--distro' || \
                fail "Iteration ${i}: --distro not found but TARGET_DISTRO=${val_distro} is set. Output: ${args_output}"
            echo "$args_output" | grep -q -- "$val_distro" || \
                fail "Iteration ${i}: value '${val_distro}' not found in output. Output: ${args_output}"
        else
            ! echo "$args_output" | grep -q -- '--distro' || \
                fail "Iteration ${i}: --distro found but TARGET_DISTRO is not set. Output: ${args_output}"
        fi

        # Conditional args: BASE_URL → --base-url
        if $has_base_url; then
            echo "$args_output" | grep -q -- '--base-url' || \
                fail "Iteration ${i}: --base-url not found but BASE_URL=${val_base_url} is set. Output: ${args_output}"
            echo "$args_output" | grep -q -- "$val_base_url" || \
                fail "Iteration ${i}: value '${val_base_url}' not found in output. Output: ${args_output}"
        else
            ! echo "$args_output" | grep -q -- '--base-url' || \
                fail "Iteration ${i}: --base-url found but BASE_URL is not set. Output: ${args_output}"
        fi

        # Clean up env vars for next iteration
        unset CADDY_VERSION TARGET_ARCH TARGET_DISTRO BASE_URL GPG_KEY_ID 2>/dev/null || true
    done
}
