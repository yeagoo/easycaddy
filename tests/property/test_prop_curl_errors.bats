#!/usr/bin/env bats
# ============================================================================
# test_prop_curl_errors.bats — Property 16: 网络错误诊断信息
# Feature: caddy-installer-china, Property 16: 网络错误诊断信息
#
# For any curl 失败退出码，脚本应输出对应的具体错误描述到 stderr。
# 测试 _describe_curl_error 函数对已知和未知 curl 退出码的映射正确性。
#
# **Validates: Requirements 12.4**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'

setup() {
    setup_test_env
    source_install_script
    reset_script_globals
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 16: 已知 curl 错误码映射到正确的中文描述
# ============================================================================

@test "Property 16: known curl error codes map to correct Chinese descriptions" {
    # 已知错误码 → 期望描述
    local -a codes=(6 7 28 35 22)
    local -a expected_descs=(
        "DNS 解析失败"
        "连接被拒绝"
        "连接超时"
        "SSL 握手失败"
        "HTTP 错误（服务器返回 4xx/5xx）"
    )

    for i in "${!codes[@]}"; do
        local code="${codes[$i]}"
        local expected="${expected_descs[$i]}"
        local actual
        actual="$(_describe_curl_error "$code")"
        [[ "$actual" == "$expected" ]] || \
            fail "curl exit code ${code}: expected '${expected}', got '${actual}'"
    done
}

# ============================================================================
# Property 16: 未知 curl 错误码输出包含 "未知网络错误" 和退出码数字
# 循环 100 次随机未知退出码
# ============================================================================

@test "Property 16: unknown curl error codes produce '未知网络错误' with exit code number (100 iterations)" {
    local known_codes=" 6 7 28 35 22 "

    for iteration in $(seq 1 100); do
        # 生成随机退出码，排除已知码
        local code
        while true; do
            code=$(gen_random_int 1 255)
            # 排除已知的 curl 错误码
            if [[ "$known_codes" != *" $code "* ]]; then
                break
            fi
        done

        local actual
        actual="$(_describe_curl_error "$code")"

        # 验证包含 "未知网络错误"
        [[ "$actual" == *"未知网络错误"* ]] || \
            fail "Iteration ${iteration}: curl exit code ${code}: expected output to contain '未知网络错误', got '${actual}'"

        # 验证包含退出码数字
        [[ "$actual" == *"${code}"* ]] || \
            fail "Iteration ${iteration}: curl exit code ${code}: expected output to contain the code number '${code}', got '${actual}'"
    done
}
