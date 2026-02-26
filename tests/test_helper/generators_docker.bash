#!/usr/bin/env bash
# ============================================================================
# generators_docker.bash — Docker 容器化系统专用随机数据生成器
# 用于 docker-repo-system 属性测试中生成随机退出码、环境变量组合等
# ============================================================================

# 有效的退出码范围（0-8，覆盖 build-repo.sh 所有退出码）
VALID_EXIT_CODES=(0 1 2 3 4 5 6 7 8)

# 环境变量名列表（builder entrypoint 支持的环境变量）
ENV_VAR_NAMES=(CADDY_VERSION TARGET_ARCH TARGET_DISTRO BASE_URL GPG_KEY_ID)

# 各环境变量的示例值池
declare -gA ENV_VAR_VALUES=(
    [CADDY_VERSION]="2.7.6 2.8.0 2.8.4 2.9.0 2.9.1 2.10.0"
    [TARGET_ARCH]="x86_64 aarch64 all"
    [TARGET_DISTRO]="all rhel:9 centos:9,almalinux:9 fedora:42 rhel:8,rhel:9,rhel:10"
    [BASE_URL]="https://rpms.example.com https://cdn.myrepo.cn https://repo.internal.net/caddy https://mirrors.company.com"
    [GPG_KEY_ID]="ABCD1234EF 9F2E8A3B7C D4E5F6A7B8 1A2B3C4D5E"
)

# 文件权限值池（包含有效和无效权限）
VALID_PERMISSIONS=(600 400)
INVALID_PERMISSIONS=(644 755 777 666 700 750 664 444 111 000 777 775 660)
ALL_PERMISSIONS=(600 400 644 755 777 666 700 750 664 444 111 000 775 660)

# CHECK_INTERVAL 格式的数值范围
INTERVAL_DAYS_MAX=30
INTERVAL_HOURS_MAX=720

# 版本号组件范围
VERSION_MAJOR=2
VERSION_MINOR_MAX=15
VERSION_PATCH_MAX=30

# API 端点列表
API_ENDPOINTS=("/api/build" "/api/rollback" "/api/status" "/api/webhook")
API_METHODS=("POST" "POST" "GET" "POST")

# ============================================================================
# 生成器函数
# ============================================================================

# 生成随机退出码（0-8）
# Property 1: 容器退出码传播
gen_exit_code() {
    local idx=$(( RANDOM % ${#VALID_EXIT_CODES[@]} ))
    echo "${VALID_EXIT_CODES[$idx]}"
}

# 生成随机环境变量组合
# Property 2: 环境变量到 CLI 参数映射
# 输出 key=value 行，随机包含/排除每个环境变量
gen_env_vars() {
    local var_name values_str values_arr idx
    for var_name in "${ENV_VAR_NAMES[@]}"; do
        # 50% 概率包含该环境变量
        if (( RANDOM % 2 == 0 )); then
            values_str="${ENV_VAR_VALUES[$var_name]}"
            read -ra values_arr <<< "$values_str"
            idx=$(( RANDOM % ${#values_arr[@]} ))
            echo "${var_name}=${values_arr[$idx]}"
        fi
    done
}

# 生成随机文件权限（八进制）
# Property 6: GPG 密钥文件权限校验
# 返回三位八进制权限字符串，包含有效（600, 400）和无效权限
gen_file_permission() {
    local idx=$(( RANDOM % ${#ALL_PERMISSIONS[@]} ))
    echo "${ALL_PERMISSIONS[$idx]}"
}

# 生成随机有效文件权限（仅 600 或 400）
gen_valid_file_permission() {
    local idx=$(( RANDOM % ${#VALID_PERMISSIONS[@]} ))
    echo "${VALID_PERMISSIONS[$idx]}"
}

# 生成随机无效文件权限（非 600/400）
gen_invalid_file_permission() {
    local idx=$(( RANDOM % ${#INVALID_PERMISSIONS[@]} ))
    echo "${INVALID_PERMISSIONS[$idx]}"
}

# 生成随机 CHECK_INTERVAL 值（Nd 或 Nh）
# Property 7: CHECK_INTERVAL 解析正确性
gen_check_interval() {
    local format=$(( RANDOM % 2 ))
    if (( format == 0 )); then
        # 天格式：1d - 30d
        local days=$(( RANDOM % INTERVAL_DAYS_MAX + 1 ))
        echo "${days}d"
    else
        # 小时格式：1h - 720h
        local hours=$(( RANDOM % INTERVAL_HOURS_MAX + 1 ))
        echo "${hours}h"
    fi
}

# 生成随机版本号字符串（如 "2.9.1"）
gen_version_string() {
    local minor=$(( RANDOM % VERSION_MINOR_MAX ))
    local patch=$(( RANDOM % VERSION_PATCH_MAX ))
    echo "${VERSION_MAJOR}.${minor}.${patch}"
}

# 生成随机版本号对（latest, current）
# Property 8: 版本比较与构建决策
# 输出两行：第一行是 latest 版本，第二行是 current 版本
# 场景分布：40% 不同版本，30% 相同版本，30% current 为空（首次运行）
gen_version_pair() {
    local scenario=$(( RANDOM % 10 ))
    local latest
    latest="$(gen_version_string)"

    if (( scenario < 4 )); then
        # 40%: 不同版本 → 应触发构建
        local current
        current="$(gen_version_string)"
        # 确保不同
        while [[ "$current" == "$latest" ]]; do
            current="$(gen_version_string)"
        done
        echo "$latest"
        echo "$current"
    elif (( scenario < 7 )); then
        # 30%: 相同版本 → 应跳过构建
        echo "$latest"
        echo "$latest"
    else
        # 30%: current 为空（首次运行）→ 应触发构建
        echo "$latest"
        echo ""
    fi
}

# 生成随机 Bearer Token
# Property 10: 状态 API 响应格式
gen_api_token() {
    local length=$(( RANDOM % 32 + 16 ))
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local token=""
    local i
    for (( i = 0; i < length; i++ )); do
        token+="${chars:$(( RANDOM % ${#chars} )):1}"
    done
    echo "$token"
}

# 生成随机 API 请求（有/无认证）
# Property 9: API 认证强制执行
# 输出格式：
#   第一行: METHOD /path
#   第二行: Authorization 头（有认证时）或空行（无认证时）
gen_api_request() {
    local idx=$(( RANDOM % ${#API_ENDPOINTS[@]} ))
    local method="${API_METHODS[$idx]}"
    local endpoint="${API_ENDPOINTS[$idx]}"
    local has_auth=$(( RANDOM % 2 ))

    echo "${method} ${endpoint}"
    if (( has_auth == 1 )); then
        local token
        token="$(gen_api_token)"
        echo "Authorization: Bearer ${token}"
    else
        echo ""
    fi
}
