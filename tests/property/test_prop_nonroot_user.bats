#!/usr/bin/env bats
# ============================================================================
# test_prop_nonroot_user.bats — Property 5: 非 root 用户运行
# Feature: docker-repo-system, Property 5: 非 root 用户运行
#
# For any 容器 Dockerfile（builder、signer），应包含 USER 指令指定非 root 用户。
# repo-server 使用 caddy:2-alpine 官方镜像，默认以非 root 用户运行。
#
# Test approach: Parse Dockerfiles to verify USER directive with non-root user.
# Since the input is static files, a single pass validates the property.
#
# **Validates: Requirements 8.1, 8.2, 8.3**
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMPOSE_FILE="$PROJECT_ROOT/docker/docker-compose.yml"
}

# ============================================================================
# Property 5: 非 root 用户运行
# ============================================================================

@test "Property 5: builder Dockerfile 包含 USER 指令且用户非 root" {
    local dockerfile="$PROJECT_ROOT/docker/builder/Dockerfile"
    # Check USER directive exists
    run grep -E '^USER ' "$dockerfile"
    assert_success
    # Verify user is not root
    refute_output --partial 'root'
}

@test "Property 5: builder Dockerfile 使用 'builder' 用户" {
    local dockerfile="$PROJECT_ROOT/docker/builder/Dockerfile"
    run grep -E '^USER builder' "$dockerfile"
    assert_success
}

@test "Property 5: signer Dockerfile 包含 USER 指令且用户非 root" {
    local dockerfile="$PROJECT_ROOT/docker/signer/Dockerfile"
    # Check USER directive exists
    run grep -E '^USER ' "$dockerfile"
    assert_success
    # Verify user is not root
    refute_output --partial 'root'
}

@test "Property 5: signer Dockerfile 使用 'signer' 用户" {
    local dockerfile="$PROJECT_ROOT/docker/signer/Dockerfile"
    run grep -E '^USER signer' "$dockerfile"
    assert_success
}

@test "Property 5: repo-server 使用 caddy:2-alpine 官方镜像（默认非 root）" {
    run bash -c "sed -n '/^  repo-server:/,/^\$/p' '$COMPOSE_FILE' | grep -q 'image: caddy:2-alpine'"
    assert_success
}
