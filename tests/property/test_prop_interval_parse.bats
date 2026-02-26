#!/usr/bin/env bats
# ============================================================================
# test_prop_interval_parse.bats — Property 7: CHECK_INTERVAL 解析正确性
# Feature: docker-repo-system, Property 7: CHECK_INTERVAL 解析正确性
#
# For any 合法的 CHECK_INTERVAL 值（格式为 Nd 或 Nh，其中 N 为正整数），
# parse_interval 函数应返回正确的秒数：
#   Nd → N × 86400
#   Nh → N × 3600
#   纯数字 → 原值
#
# Test approach: 100 iterations using gen_check_interval from generators_docker.bash.
# For each generated interval, compute the expected seconds and verify parse_interval
# returns the correct value.
#
# **Validates: Requirements 11.2**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    source "$PROJECT_ROOT/tests/test_helper/generators_docker.bash"
    _SOURCED_FOR_TEST=true source "$PROJECT_ROOT/docker/scheduler/scheduler.sh"
}

# ============================================================================
# Property 7: CHECK_INTERVAL 解析正确性 (100 iterations)
# ============================================================================

@test "Property 7: CHECK_INTERVAL 解析正确性 — 随机间隔值正确转换为秒数" {
    for i in $(seq 1 100); do
        local interval
        interval="$(gen_check_interval)"

        local expected
        case "$interval" in
            *d) expected=$(( ${interval%d} * 86400 )) ;;
            *h) expected=$(( ${interval%h} * 3600 )) ;;
            *)  expected="$interval" ;;
        esac

        local actual
        actual="$(parse_interval "$interval")"

        [[ "$actual" -eq "$expected" ]] || \
            fail "Iteration ${i}: parse_interval('${interval}') = ${actual}, expected ${expected}"
    done
}
