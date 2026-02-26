#!/usr/bin/env bats
# ============================================================================
# test_caddyfile.bats — Caddyfile 配置验证
# 验证 Cache-Control 头配置、日志配置、域名环境变量
#
# Requirements: 3.5, 3.6
# ============================================================================

setup() {
    load '../libs/bats-support/load'
    load '../libs/bats-assert/load'
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CADDYFILE="$PROJECT_ROOT/docker/repo-server/Caddyfile"
}

@test "Caddyfile: 使用 DOMAIN_NAME 环境变量配置域名" {
    run grep -c '{\$DOMAIN_NAME:localhost}' "$CADDYFILE"
    assert_success
    assert_output "1"
}

@test "Caddyfile: 根目录配置为 /srv/repo" {
    run grep 'root \* /srv/repo' "$CADDYFILE"
    assert_success
}

@test "Caddyfile: 启用 file_server browse" {
    run grep 'file_server browse' "$CADDYFILE"
    assert_success
}

@test "Caddyfile: repomd.xml 设置 no-cache" {
    run grep 'no-cache, must-revalidate' "$CADDYFILE"
    assert_success
}

@test "Caddyfile: RPM 文件设置 max-age=86400" {
    run grep 'max-age=86400' "$CADDYFILE"
    assert_success
}

@test "Caddyfile: 日志输出到 stdout" {
    run grep 'output stdout' "$CADDYFILE"
    assert_success
}

@test "Caddyfile: 日志格式为 JSON" {
    run grep 'format json' "$CADDYFILE"
    assert_success
}
