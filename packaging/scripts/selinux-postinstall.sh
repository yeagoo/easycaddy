#!/bin/bash
# caddy-selinux postinstall: 加载 SELinux 策略模块
# semodule 失败时仅警告，不阻断 RPM 安装
if command -v semodule >/dev/null 2>&1; then
    semodule -i /usr/share/selinux/packages/caddy.pp || echo "[WARN] SELinux 策略模块加载失败，请手动执行: semodule -i /usr/share/selinux/packages/caddy.pp" >&2
fi
