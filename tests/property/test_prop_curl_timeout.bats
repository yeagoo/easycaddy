#!/usr/bin/env bats
# ============================================================================
# test_prop_curl_timeout.bats — Property 15: 网络超时配置正确性
# Feature: caddy-installer-china, Property 15: 网络超时配置正确性
#
# For any 脚本中构造的 curl 命令，应包含 --connect-timeout 30 和 --max-time 120 参数。
# 这是一个静态分析测试：读取 install-caddy.sh，找到所有实际执行的 curl 调用，
# 验证每个 curl 命令都包含正确的超时参数。
#
# **Validates: Requirements 12.1, 12.2**
# ============================================================================

load '../libs/bats-support/load'
load '../libs/bats-assert/load'
load '../test_helper/mock_helpers'

setup() {
    PROJECT_ROOT="$(get_project_root)"
    SCRIPT_FILE="${PROJECT_ROOT}/install-caddy.sh"
}

# Helper: extract all actual curl command invocations from the script,
# handling heredocs and line continuations. Returns results in
# CURL_COMMANDS array and CURL_LINE_NUMS array.
_extract_curl_commands() {
    CURL_COMMANDS=()
    CURL_LINE_NUMS=()

    local in_heredoc=false
    local heredoc_marker=""
    local collecting=false
    local full_command=""
    local start_line_num=0
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Track heredoc blocks — skip content inside them
        if $in_heredoc; then
            # Check if this line ends the heredoc
            local trimmed
            trimmed="$(echo "$line" | sed 's/^[[:space:]]*//')"
            if [[ "$trimmed" == "$heredoc_marker" ]]; then
                in_heredoc=false
                heredoc_marker=""
            fi
            continue
        fi

        # Detect heredoc start (e.g., cat << EOF, cat >&2 <<'EOF', cat <<- 'MARKER')
        if echo "$line" | grep -qP '<<-?\s*\\?[\x27"]?([A-Za-z_]+)[\x27"]?'; then
            heredoc_marker="$(echo "$line" | sed -E "s/.*<<-?[[:space:]]*\\\\?['\"]?([A-Za-z_]+)['\"]?.*/\1/")"
            in_heredoc=true
            continue
        fi

        # Handle line continuation for an ongoing curl command
        if $collecting; then
            full_command+=" ${line}"
            if [[ ! "$line" =~ \\[[:space:]]*$ ]]; then
                collecting=false
                CURL_COMMANDS+=("$full_command")
                CURL_LINE_NUMS+=("$start_line_num")
                full_command=""
            fi
            continue
        fi

        # Skip pure comment lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Detect actual curl command invocations:
        # Lines where 'curl' appears as a command being executed (not in strings)
        if echo "$line" | grep -qP '(?:^|[|;&!]\s*|if\s+!?\s*)curl\b' ||
           echo "$line" | grep -qP '^\s+curl\b'; then
            start_line_num=$line_num
            full_command="$line"
            if [[ "$line" =~ \\[[:space:]]*$ ]]; then
                collecting=true
            else
                CURL_COMMANDS+=("$full_command")
                CURL_LINE_NUMS+=("$start_line_num")
                full_command=""
            fi
        fi
    done < "$SCRIPT_FILE"
}

# ============================================================================
# Property 15: 所有 curl 命令包含 --connect-timeout 30
# ============================================================================

@test "Property 15: all curl invocations in install-caddy.sh include --connect-timeout 30" {
    _extract_curl_commands

    [[ ${#CURL_COMMANDS[@]} -gt 0 ]] || fail "No curl command invocations found in ${SCRIPT_FILE}"

    for idx in "${!CURL_COMMANDS[@]}"; do
        local cmd="${CURL_COMMANDS[$idx]}"
        local lnum="${CURL_LINE_NUMS[$idx]}"
        if [[ "$cmd" != *"--connect-timeout 30"* ]]; then
            fail "Line ${lnum}: curl command missing '--connect-timeout 30': ${cmd}"
        fi
    done
}

# ============================================================================
# Property 15: 所有 curl 命令包含 --max-time 120
# ============================================================================

@test "Property 15: all curl invocations in install-caddy.sh include --max-time 120" {
    _extract_curl_commands

    [[ ${#CURL_COMMANDS[@]} -gt 0 ]] || fail "No curl command invocations found in ${SCRIPT_FILE}"

    for idx in "${!CURL_COMMANDS[@]}"; do
        local cmd="${CURL_COMMANDS[$idx]}"
        local lnum="${CURL_LINE_NUMS[$idx]}"
        if [[ "$cmd" != *"--max-time 120"* ]]; then
            fail "Line ${lnum}: curl command missing '--max-time 120': ${cmd}"
        fi
    done
}

# ============================================================================
# Property 15: 脚本至少包含一个带超时参数的 curl 命令（健全性检查）
# ============================================================================

@test "Property 15: script contains at least one curl command with both timeout parameters" {
    _extract_curl_commands

    [[ ${#CURL_COMMANDS[@]} -gt 0 ]] || fail "Expected at least one curl command in ${SCRIPT_FILE}, found none"

    # Verify at least one command has both timeout params
    local found_both=false
    for cmd in "${CURL_COMMANDS[@]}"; do
        if [[ "$cmd" == *"--connect-timeout 30"* && "$cmd" == *"--max-time 120"* ]]; then
            found_both=true
            break
        fi
    done

    $found_both || fail "No curl command found with both --connect-timeout 30 and --max-time 120"
}
