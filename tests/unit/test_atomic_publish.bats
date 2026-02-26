#!/usr/bin/env bats
# ============================================================================
# test_atomic_publish.bats — 原子发布与回滚单元测试
# 测试 atomic_publish、rollback_latest、cleanup_old_backups 函数
# - staging → 原子交换流程
# - 交换前备份现有正式目录
# - 备份目录使用时间戳格式
# - 成功交换后清理 staging 目录
# - staging caddy/ 不存在时退出码 7
# - rollback 恢复最近备份
# - rollback 删除当前正式目录后恢复
# - 无备份时 rollback 退出码 7
# - rollback 目录不存在时退出码 7
# - cleanup 保留最近 3 个备份
# - cleanup 3 个或更少时全部保留
# - cleanup 删除最旧的备份
# - cleanup rollback 目录不存在时无操作
#
# Requirements: 12.1–12.6
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators_repo'

source_build_repo_script() {
    local project_root
    project_root="$(get_project_root)"
    _SOURCED_FOR_TEST=true
    source "${project_root}/build-repo.sh"
}

setup() {
    setup_test_env
    source_build_repo_script
    OPT_OUTPUT="${TEST_TEMP_DIR}/repo"
    mkdir -p "$OPT_OUTPUT"
    STAGING_DIR="${OPT_OUTPUT}/.staging"
    mkdir -p "$STAGING_DIR"
}

teardown() { teardown_test_env; }

# ============================================================================
# atomic_publish — staging caddy/ is moved to production caddy/
# ============================================================================

@test "atomic_publish moves staging caddy/ to production caddy/" {
    mkdir -p "${STAGING_DIR}/caddy/el8/x86_64/Packages"
    echo "test-rpm" > "${STAGING_DIR}/caddy/el8/x86_64/Packages/caddy-2.9.0-1.el8.x86_64.rpm"

    atomic_publish 2>/dev/null

    [[ -f "${OPT_OUTPUT}/caddy/el8/x86_64/Packages/caddy-2.9.0-1.el8.x86_64.rpm" ]]
    [[ ! -d "${STAGING_DIR}/caddy" ]]
}

# ============================================================================
# atomic_publish — existing production caddy/ is backed up before swap
# ============================================================================

@test "atomic_publish backs up existing production caddy/ before swap" {
    # Create existing production directory
    mkdir -p "${OPT_OUTPUT}/caddy/el8"
    echo "old-content" > "${OPT_OUTPUT}/caddy/el8/old-file.txt"

    # Create staging directory
    mkdir -p "${STAGING_DIR}/caddy/el8"
    echo "new-content" > "${STAGING_DIR}/caddy/el8/new-file.txt"

    atomic_publish 2>/dev/null

    # Production should have new content
    [[ -f "${OPT_OUTPUT}/caddy/el8/new-file.txt" ]]
    [[ ! -f "${OPT_OUTPUT}/caddy/el8/old-file.txt" ]]

    # Backup should exist in .rollback/
    local backup_count
    backup_count="$(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    [[ "$backup_count" -eq 1 ]]

    # Backup should contain old content
    local backup_dir
    backup_dir="$(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -f "${backup_dir}/caddy/el8/old-file.txt" ]]
    [[ "$(cat "${backup_dir}/caddy/el8/old-file.txt")" == "old-content" ]]
}

# ============================================================================
# atomic_publish — backup directory has timestamp format
# ============================================================================

@test "atomic_publish backup directory name matches YYYYMMDD-HHMMSS format" {
    mkdir -p "${OPT_OUTPUT}/caddy/el8"
    mkdir -p "${STAGING_DIR}/caddy/el8"

    atomic_publish 2>/dev/null

    local backup_dir
    backup_dir="$(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d | head -1)"
    local dirname
    dirname="$(basename "$backup_dir")"

    # Verify timestamp format: YYYYMMDD-HHMMSS
    [[ "$dirname" =~ ^[0-9]{8}-[0-9]{6}$ ]]
}

# ============================================================================
# atomic_publish — staging directory is cleaned up after successful swap
# ============================================================================

@test "atomic_publish cleans up staging directory after successful swap" {
    mkdir -p "${STAGING_DIR}/caddy/el9"
    echo "content" > "${STAGING_DIR}/caddy/el9/test.txt"

    atomic_publish 2>/dev/null

    # .staging/ should be removed (or at least caddy/ inside it)
    [[ ! -d "${STAGING_DIR}/caddy" ]]
}

# ============================================================================
# atomic_publish — fails with exit code 7 when staging caddy/ doesn't exist
# ============================================================================

@test "atomic_publish fails with exit code 7 when staging caddy/ does not exist" {
    # STAGING_DIR exists but caddy/ subdirectory does not
    [[ -d "$STAGING_DIR" ]]
    [[ ! -d "${STAGING_DIR}/caddy" ]]

    run atomic_publish
    assert_failure
    [[ "$status" -eq 7 ]]
}

@test "atomic_publish outputs error when staging caddy/ does not exist" {
    run atomic_publish
    assert_failure
    assert_output --partial "staging"
}

# ============================================================================
# atomic_publish — no backup created when no existing production dir
# ============================================================================

@test "atomic_publish does not create backup when no existing production caddy/" {
    mkdir -p "${STAGING_DIR}/caddy/el8"
    [[ ! -d "${OPT_OUTPUT}/caddy" ]]

    atomic_publish 2>/dev/null

    # No rollback directory should be created
    [[ ! -d "${OPT_OUTPUT}/.rollback" ]] || \
        [[ "$(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]]
}

# ============================================================================
# rollback_latest — restores most recent backup to production
# ============================================================================

@test "rollback_latest restores most recent backup to production" {
    # Create two backups with different timestamps
    mkdir -p "${OPT_OUTPUT}/.rollback/20240101-100000/caddy/el8"
    echo "old-backup" > "${OPT_OUTPUT}/.rollback/20240101-100000/caddy/el8/data.txt"

    mkdir -p "${OPT_OUTPUT}/.rollback/20240601-120000/caddy/el9"
    echo "latest-backup" > "${OPT_OUTPUT}/.rollback/20240601-120000/caddy/el9/data.txt"

    rollback_latest 2>/dev/null

    # Production should have the latest backup content
    [[ -f "${OPT_OUTPUT}/caddy/el9/data.txt" ]]
    [[ "$(cat "${OPT_OUTPUT}/caddy/el9/data.txt")" == "latest-backup" ]]
}

# ============================================================================
# rollback_latest — removes current production before restoring
# ============================================================================

@test "rollback_latest removes current production caddy/ before restoring" {
    # Create existing production
    mkdir -p "${OPT_OUTPUT}/caddy/el8"
    echo "current-prod" > "${OPT_OUTPUT}/caddy/el8/current.txt"

    # Create backup
    mkdir -p "${OPT_OUTPUT}/.rollback/20240601-120000/caddy/el9"
    echo "backup-data" > "${OPT_OUTPUT}/.rollback/20240601-120000/caddy/el9/restored.txt"

    rollback_latest 2>/dev/null

    # Old production content should be gone
    [[ ! -f "${OPT_OUTPUT}/caddy/el8/current.txt" ]]
    # Restored content should be present
    [[ -f "${OPT_OUTPUT}/caddy/el9/restored.txt" ]]
    [[ "$(cat "${OPT_OUTPUT}/caddy/el9/restored.txt")" == "backup-data" ]]
}

# ============================================================================
# rollback_latest — fails with exit code 7 when no backups exist
# ============================================================================

@test "rollback_latest fails with exit code 7 when rollback dir is empty" {
    mkdir -p "${OPT_OUTPUT}/.rollback"
    # Directory exists but has no backup subdirectories

    run rollback_latest
    assert_failure
    [[ "$status" -eq 7 ]]
}

# ============================================================================
# rollback_latest — fails with exit code 7 when rollback dir doesn't exist
# ============================================================================

@test "rollback_latest fails with exit code 7 when rollback dir does not exist" {
    [[ ! -d "${OPT_OUTPUT}/.rollback" ]]

    run rollback_latest
    assert_failure
    [[ "$status" -eq 7 ]]
}

# ============================================================================
# cleanup_old_backups — keeps exactly 3 when more than 3 exist
# ============================================================================

@test "cleanup_old_backups keeps exactly 3 backups when 5 exist" {
    mkdir -p "${OPT_OUTPUT}/.rollback/20240101-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240201-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240301-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240401-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240501-100000"

    cleanup_old_backups 2>/dev/null

    local count
    count="$(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    [[ "$count" -eq 3 ]]
}

# ============================================================================
# cleanup_old_backups — keeps all when 3 or fewer exist
# ============================================================================

@test "cleanup_old_backups keeps all when exactly 3 exist" {
    mkdir -p "${OPT_OUTPUT}/.rollback/20240101-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240201-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240301-100000"

    cleanup_old_backups 2>/dev/null

    local count
    count="$(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    [[ "$count" -eq 3 ]]
}

@test "cleanup_old_backups keeps all when only 1 exists" {
    mkdir -p "${OPT_OUTPUT}/.rollback/20240101-100000"

    cleanup_old_backups 2>/dev/null

    local count
    count="$(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    [[ "$count" -eq 1 ]]
}

# ============================================================================
# cleanup_old_backups — removes oldest backups (by timestamp name)
# ============================================================================

@test "cleanup_old_backups removes the two oldest when 5 exist" {
    mkdir -p "${OPT_OUTPUT}/.rollback/20240101-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240201-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240301-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240401-100000"
    mkdir -p "${OPT_OUTPUT}/.rollback/20240501-100000"

    cleanup_old_backups 2>/dev/null

    # Oldest two should be removed
    [[ ! -d "${OPT_OUTPUT}/.rollback/20240101-100000" ]]
    [[ ! -d "${OPT_OUTPUT}/.rollback/20240201-100000" ]]
    # Newest three should remain
    [[ -d "${OPT_OUTPUT}/.rollback/20240301-100000" ]]
    [[ -d "${OPT_OUTPUT}/.rollback/20240401-100000" ]]
    [[ -d "${OPT_OUTPUT}/.rollback/20240501-100000" ]]
}

# ============================================================================
# cleanup_old_backups — does nothing when rollback dir doesn't exist
# ============================================================================

@test "cleanup_old_backups does nothing when rollback dir does not exist" {
    [[ ! -d "${OPT_OUTPUT}/.rollback" ]]

    # Should return 0 without error
    run cleanup_old_backups
    assert_success
}
