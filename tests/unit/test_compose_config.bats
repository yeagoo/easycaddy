#!/usr/bin/env bats
# ============================================================================
# test_compose_config.bats — docker-compose.yml 配置验证
# 验证服务定义完整性、Volume 挂载正确性、网络配置、安全选项
#
# Requirements: 5.1, 5.2, 6.1, 6.6, 8.4, 8.5, 8.6
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMPOSE_FILE="$PROJECT_ROOT/docker/docker-compose.yml"
}

# ============================================================================
# 1. 服务定义完整性 (Requirement 6.1)
# ============================================================================

@test "compose: 定义 builder 服务" {
    run grep -E '^  builder:' "$COMPOSE_FILE"
    assert_success
}

@test "compose: 定义 signer 服务" {
    run grep -E '^  signer:' "$COMPOSE_FILE"
    assert_success
}

@test "compose: 定义 repo-server 服务" {
    run grep -E '^  repo-server:' "$COMPOSE_FILE"
    assert_success
}

@test "compose: 定义 scheduler 服务" {
    run grep -E '^  scheduler:' "$COMPOSE_FILE"
    assert_success
}

@test "compose: 定义 repo-manager 服务" {
    run grep -E '^  repo-manager:' "$COMPOSE_FILE"
    assert_success
}

# ============================================================================
# 2-3. Volume 定义 (Requirement 5.1, 5.2)
# ============================================================================

@test "compose: 定义 repo-data volume" {
    run grep -E '^  repo-data:' "$COMPOSE_FILE"
    assert_success
}

@test "compose: 定义 gpg-keys volume" {
    run grep -E '^  gpg-keys:' "$COMPOSE_FILE"
    assert_success
}

# ============================================================================
# 4-5. 网络配置 (Requirement 6.6)
# ============================================================================

@test "compose: internal 网络配置 internal: true" {
    # Extract the networks section, then the internal block
    run bash -c "sed -n '/^networks:/,/^[a-z]/p' '$COMPOSE_FILE' | sed -n '/^  internal:/,/^  [a-z]/p' | grep -q 'internal: true'"
    assert_success
}

@test "compose: 定义 external 网络" {
    run bash -c "sed -n '/^networks:/,\$p' '$COMPOSE_FILE' | grep -qE '^  external:'"
    assert_success
}

# ============================================================================
# 6-7. 重启策略 (Requirement 6.4, 6.3)
# ============================================================================

@test "compose: builder 配置 restart: no" {
    run bash -c "sed -n '/^  builder:/,/^\$/p' '$COMPOSE_FILE' | grep -qE 'restart:.*\"?no\"?'"
    assert_success
}

@test "compose: repo-server 配置 restart: unless-stopped" {
    run bash -c "sed -n '/^  repo-server:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'restart: unless-stopped'"
    assert_success
}

# ============================================================================
# 8. 依赖关系 (Requirement 6.2)
# ============================================================================

@test "compose: signer 依赖 builder" {
    run bash -c "sed -n '/^  signer:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'builder'"
    assert_success
}

# ============================================================================
# 9. Profiles (Requirement 6.1)
# ============================================================================

@test "compose: repo-manager 配置 profiles: [management]" {
    run bash -c "sed -n '/^  repo-manager:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'management'"
    assert_success
}

# ============================================================================
# 10. 端口暴露 (Requirement 6.6)
# ============================================================================

@test "compose: repo-server 暴露端口 80" {
    run bash -c "sed -n '/^  repo-server:/,/^\$/p' '$COMPOSE_FILE' | grep -qE '\"?80:80\"?'"
    assert_success
}

@test "compose: repo-server 暴露端口 443" {
    run bash -c "sed -n '/^  repo-server:/,/^\$/p' '$COMPOSE_FILE' | grep -qE '\"?443:443\"?'"
    assert_success
}

# ============================================================================
# 11-12. 安全配置 (Requirement 8.4, 8.6)
# ============================================================================

@test "compose: builder 配置 read_only: true" {
    run bash -c "sed -n '/^  builder:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'read_only: true'"
    assert_success
}

@test "compose: builder 配置 cap_drop: ALL" {
    run bash -c "sed -n '/^  builder:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'ALL'"
    assert_success
}
