#!/usr/bin/env bats
# ============================================================================
# test_prop_security_opts.bats — Property 4: 安全选项全覆盖
# Feature: docker-repo-system, Property 4: 安全选项全覆盖
#
# For any docker-compose.yml 中定义的服务，security_opt 应包含
# no-new-privileges:true。
#
# Test approach: Parse docker-compose.yml to verify every service has
# no-new-privileges:true in security_opt. Since the input is a static config
# file, a single pass validates the property.
#
# **Validates: Requirement 8.5**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMPOSE_FILE="$PROJECT_ROOT/docker/docker-compose.yml"
}

# ============================================================================
# Property 4: 安全选项全覆盖
# ============================================================================

@test "Property 4: builder 服务配置 no-new-privileges:true" {
    run bash -c "sed -n '/^  builder:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'no-new-privileges:true'"
    assert_success
}

@test "Property 4: signer 服务配置 no-new-privileges:true" {
    run bash -c "sed -n '/^  signer:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'no-new-privileges:true'"
    assert_success
}

@test "Property 4: repo-server 服务配置 no-new-privileges:true" {
    run bash -c "sed -n '/^  repo-server:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'no-new-privileges:true'"
    assert_success
}

@test "Property 4: scheduler 服务配置 no-new-privileges:true" {
    run bash -c "sed -n '/^  scheduler:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'no-new-privileges:true'"
    assert_success
}

@test "Property 4: repo-manager 服务配置 no-new-privileges:true" {
    run bash -c "sed -n '/^  repo-manager:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'no-new-privileges:true'"
    assert_success
}

@test "Property 4: 所有 5 个服务均配置 no-new-privileges:true" {
    local count
    count=$(grep -c 'no-new-privileges:true' "$COMPOSE_FILE")
    [[ "$count" -ge 5 ]]
}
