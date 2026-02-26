#!/usr/bin/env bats
# ============================================================================
# test_prop_backup_retention.bats — Property 15: 回滚备份保留策略
# Feature: selfhosted-rpm-repo-builder, Property 15: 回滚备份保留策略
#
# For any 数量的回滚备份，系统应仅保留最近 3 个备份，自动清理更早的备份。
# 备份目录名为时间戳格式（YYYYMMDD-HHMMSS），按名称排序即为时间排序。
#
# **Validates: Requirements 12.6**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'
load '../test_helper/generators'
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
}

teardown() {
    teardown_test_env
}

# Generate a random timestamp directory name in YYYYMMDD-HHMMSS format
gen_random_timestamp() {
    local year=$(( 2020 + RANDOM % 6 ))
    local month=$(( RANDOM % 12 + 1 ))
    local day=$(( RANDOM % 28 + 1 ))
    local hour=$(( RANDOM % 24 ))
    local min=$(( RANDOM % 60 ))
    local sec=$(( RANDOM % 60 ))
    printf "%04d%02d%02d-%02d%02d%02d" "$year" "$month" "$day" "$hour" "$min" "$sec"
}

# ============================================================================
# Property 15: backup retention policy (100 iterations)
# ============================================================================

@test "Property 15: cleanup_old_backups keeps at most 3 most recent backups (100 iterations)" {
    for i in $(seq 1 100); do
        # Clean up rollback dir for each iteration
        rm -rf "${OPT_OUTPUT}/.rollback"

        # Create a random number of backup directories (1-10)
        local num_backups=$(( RANDOM % 10 + 1 ))
        local timestamps=()

        mkdir -p "${OPT_OUTPUT}/.rollback"

        for (( j = 0; j < num_backups; j++ )); do
            local ts
            ts="$(gen_random_timestamp)"
            # Ensure uniqueness by appending index if needed
            while [[ -d "${OPT_OUTPUT}/.rollback/${ts}" ]]; do
                ts="$(gen_random_timestamp)"
            done
            timestamps+=("$ts")
            mkdir -p "${OPT_OUTPUT}/.rollback/${ts}"
        done

        # Call cleanup_old_backups
        cleanup_old_backups 2>/dev/null

        # Count remaining backups
        local remaining=()
        while IFS= read -r dir; do
            [[ -n "$dir" ]] && remaining+=("$(basename "$dir")")
        done < <(find "${OPT_OUTPUT}/.rollback" -mindepth 1 -maxdepth 1 -type d | sort)

        local remaining_count=${#remaining[@]}

        # Verify at most 3 backups remain
        if [[ "$remaining_count" -gt 3 ]]; then
            fail "Iteration ${i}: Expected at most 3 backups, got ${remaining_count} (created ${num_backups})"
        fi

        # Verify correct count: min(num_backups, 3)
        local expected_count=$num_backups
        if [[ "$expected_count" -gt 3 ]]; then
            expected_count=3
        fi
        if [[ "$remaining_count" -ne "$expected_count" ]]; then
            fail "Iteration ${i}: Expected ${expected_count} backups, got ${remaining_count} (created ${num_backups})"
        fi

        # Verify the remaining are the 3 most recent (by name sort)
        if [[ "$num_backups" -gt 3 ]]; then
            # Sort all timestamps and get the last 3
            local sorted_all=()
            while IFS= read -r ts; do
                sorted_all+=("$ts")
            done < <(printf '%s\n' "${timestamps[@]}" | sort)

            local expected_kept=()
            local total=${#sorted_all[@]}
            for (( k = total - 3; k < total; k++ )); do
                expected_kept+=("${sorted_all[$k]}")
            done

            # Compare remaining with expected
            for (( k = 0; k < 3; k++ )); do
                if [[ "${remaining[$k]}" != "${expected_kept[$k]}" ]]; then
                    fail "Iteration ${i}: Remaining backup ${k} is '${remaining[$k]}', expected '${expected_kept[$k]}'. All created: ${timestamps[*]}"
                fi
            done
        fi
    done
}
