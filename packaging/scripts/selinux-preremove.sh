#!/bin/bash
# caddy-selinux preremove: 移除 SELinux 策略模块
if command -v semodule >/dev/null 2>&1; then
    semodule -r caddy 2>/dev/null || true
fi
