#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# manager.sh — 管理 API 服务
# 使用 socat 监听 HTTP 请求，提供构建、回滚、状态查询 API
# ============================================================================

MANAGER_PORT="${MANAGER_PORT:-8080}"
STATUS_FILE="${STATUS_FILE:-/repo/.manager-status}"
VERSION_FILE="${VERSION_FILE:-/repo/caddy/.current-version}"

# 验证 Bearer Token 认证
# 参数: $1 — Authorization 头值
# 返回: 0 — 认证成功, 1 — 认证失败
check_auth() {
    local auth_header="${1:-}"
    local expected="Bearer ${API_TOKEN:-}"

    if [[ -z "${API_TOKEN:-}" ]]; then
        return 1
    fi

    if [[ "$auth_header" == "$expected" ]]; then
        return 0
    fi

    return 1
}

# 获取状态 JSON
get_status_json() {
    local last_build_time="" version="" status="unknown"

    if [[ -f "$STATUS_FILE" ]]; then
        last_build_time=$(grep '^last_build_time=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2- || echo "")
        status=$(grep '^status=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2- || echo "unknown")
    fi

    if [[ -f "$VERSION_FILE" ]]; then
        version=$(cat "$VERSION_FILE" 2>/dev/null || echo "")
    fi

    printf '{"last_build_time":"%s","version":"%s","status":"%s"}' \
        "$last_build_time" "$version" "$status"
}

# 构建 HTTP 响应
# 参数: $1 — 状态码, $2 — 状态文本, $3 — 响应体
send_response() {
    local code="$1"
    local status_text="$2"
    local body="$3"
    local content_length=${#body}

    printf 'HTTP/1.1 %s %s\r\n' "$code" "$status_text"
    printf 'Content-Type: application/json\r\n'
    printf 'Content-Length: %d\r\n' "$content_length"
    printf '\r\n'
    printf '%s' "$body"
}

# 处理 HTTP 请求
# 参数: $1 — 请求方法, $2 — 请求路径, $3 — Authorization 头
handle_request() {
    local method="$1"
    local path="$2"
    local auth_header="${3:-}"

    # 认证检查
    if ! check_auth "$auth_header"; then
        send_response 401 "Unauthorized" '{"error":"unauthorized"}'
        return
    fi

    case "${method} ${path}" in
        "GET /api/status")
            local status_json
            status_json="$(get_status_json)"
            send_response 200 "OK" "$status_json"
            ;;
        "POST /api/build")
            docker compose run --rm builder && docker compose run --rm signer
            local build_time
            build_time="$(date -Iseconds)"
            echo "last_build_time=${build_time}" > "$STATUS_FILE"
            echo "status=success" >> "$STATUS_FILE"
            send_response 200 "OK" '{"result":"build triggered"}'
            ;;
        "POST /api/rollback")
            bash /app/build-repo.sh --rollback --output /repo
            send_response 200 "OK" '{"result":"rollback completed"}'
            ;;
        "POST /api/webhook")
            docker compose run --rm builder && docker compose run --rm signer
            send_response 200 "OK" '{"result":"webhook build triggered"}'
            ;;
        *)
            send_response 404 "Not Found" '{"error":"not found"}'
            ;;
    esac
}

# 支持测试时 source 单独函数
if [[ "${_SOURCED_FOR_TEST:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi

# === 主循环：使用 socat 监听 HTTP 请求 ===
echo "[INFO] Repo Manager API 启动，监听端口 ${MANAGER_PORT}" >&2

while true; do
    socat TCP-LISTEN:${MANAGER_PORT},reuseaddr,fork EXEC:"bash $0 --handle-connection" 2>/dev/null || {
        echo "[ERROR] socat 监听失败，5 秒后重试" >&2
        sleep 5
    }
done
