#!/usr/bin/env bats
# ============================================================================
# test_prop_gpg_volume_isolation.bats — Property 3: GPG 密钥 Volume 隔离
# Feature: docker-repo-system, Property 3: GPG 密钥 Volume 隔离
#
# For any docker-compose.yml 中定义的服务，gpg-keys Volume 应仅被 signer 服务
# 挂载，且挂载模式为只读（:ro）。其他服务（builder、repo-server、scheduler、
# repo-manager）不应挂载 gpg-keys Volume。
#
# Test approach: Parse docker-compose.yml to verify gpg-keys volume isolation.
# Since the input is a static config file, a single pass validates the property.
#
# **Validates: Requirement 5.2**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMPOSE_FILE="$PROJECT_ROOT/docker/docker-compose.yml"
}

# Helper: extract a service block from compose file
service_block() {
    sed -n "/^  ${1}:/,/^$/p" "$COMPOSE_FILE"
}

# ============================================================================
# Property 3: GPG 密钥 Volume 隔离
# ============================================================================

@test "Property 3: signer 服务挂载 gpg-keys volume" {
    run bash -c "service_block() { sed -n '/^  signer:/,/^\$/p' '$COMPOSE_FILE'; }; service_block | grep -q 'gpg-keys'"
    assert_success
}

@test "Property 3: signer 的 gpg-keys 挂载为只读 (:ro)" {
    run bash -c "sed -n '/^  signer:/,/^\$/p' '$COMPOSE_FILE' | grep 'gpg-keys' | grep -q ':ro'"
    assert_success
}

@test "Property 3: builder 服务不挂载 gpg-keys volume" {
    run bash -c "sed -n '/^  builder:/,/^\$/p' '$COMPOSE_FILE' | grep -c 'gpg-keys' || true"
    assert_output "0"
}

@test "Property 3: repo-server 服务不挂载 gpg-keys volume" {
    run bash -c "sed -n '/^  repo-server:/,/^\$/p' '$COMPOSE_FILE' | grep -c 'gpg-keys' || true"
    assert_output "0"
}

@test "Property 3: scheduler 服务不挂载 gpg-keys volume" {
    run bash -c "sed -n '/^  scheduler:/,/^\$/p' '$COMPOSE_FILE' | grep -c 'gpg-keys' || true"
    assert_output "0"
}

@test "Property 3: repo-manager 服务不挂载 gpg-keys volume" {
    run bash -c "sed -n '/^  repo-manager:/,/^\$/p' '$COMPOSE_FILE' | grep -c 'gpg-keys' || true"
    assert_output "0"
}
