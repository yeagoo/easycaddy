#!/usr/bin/env bats
# ============================================================================
# test_prop_stage_control.bats — Property 17: CI/CD 阶段控制
# Feature: selfhosted-rpm-repo-builder, Property 17: CI/CD 阶段控制
#
# For any 有效的 --stage 参数值（build、sign、publish、verify），
# 仅对应阶段应被执行；每个阶段完成后应输出 [STAGE] {stage_name}: completed 到 stderr。
#
# Test approach: For 100 iterations, randomly pick a stage name, call run_stage
# with stage functions overridden as no-ops, and verify:
# 1. The [STAGE] {stage_name}: completed message appears in stderr
# 2. The [STAGE] {stage_name}: starting message appears in stderr
# 3. Only the selected stage function is called (not others)
#
# **Validates: Requirements 16.1, 16.3**
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
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Property 17: CI/CD stage control (100 iterations)
# ============================================================================

@test "Property 17: run_stage executes only the selected stage and outputs correct [STAGE] messages (100 iterations)" {
    for i in $(seq 1 100); do
        # Pick a random stage
        local stage
        stage="$(gen_stage_name)"

        # Track which stage functions are called
        local call_log="${TEST_TEMP_DIR}/stage_calls_${i}"
        : > "$call_log"

        # Override all stage functions with tracking no-ops
        stage_build()   { echo "build"   >> "$call_log"; }
        stage_sign()    { echo "sign"    >> "$call_log"; }
        stage_publish() { echo "publish" >> "$call_log"; }
        stage_verify()  { echo "verify"  >> "$call_log"; }

        # Call run_stage and capture stderr
        local stderr_output="${TEST_TEMP_DIR}/stderr_${i}"
        run_stage "$stage" 2>"$stderr_output"

        # 1. Verify [STAGE] starting message
        if ! grep -qF "[STAGE] ${stage}: starting" "$stderr_output"; then
            fail "Iteration ${i}: Missing '[STAGE] ${stage}: starting' in stderr. Stage: ${stage}. Stderr: $(cat "$stderr_output")"
        fi

        # 2. Verify [STAGE] completed message
        if ! grep -qF "[STAGE] ${stage}: completed" "$stderr_output"; then
            fail "Iteration ${i}: Missing '[STAGE] ${stage}: completed' in stderr. Stage: ${stage}. Stderr: $(cat "$stderr_output")"
        fi

        # 3. Verify only the selected stage function was called
        local called_stages
        called_stages="$(cat "$call_log")"
        local call_count
        call_count="$(wc -l < "$call_log" | tr -d ' ')"

        if [[ "$call_count" -ne 1 ]]; then
            fail "Iteration ${i}: Expected exactly 1 stage call, got ${call_count}. Stage: ${stage}. Called: ${called_stages}"
        fi

        local called_stage
        called_stage="$(head -1 "$call_log")"
        if [[ "$called_stage" != "$stage" ]]; then
            fail "Iteration ${i}: Expected stage '${stage}' to be called, but '${called_stage}' was called instead"
        fi

        # Re-source to restore original functions for next iteration
        source_build_repo_script
    done
}
