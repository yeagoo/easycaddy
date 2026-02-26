#!/bin/bash
# caddy-selinux preremove: 移除 SELinux 策略模块
semodule -r caddy 2>/dev/null || true
