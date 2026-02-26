#!/bin/bash
# 创建 caddy 系统用户和组
if ! getent group caddy >/dev/null 2>&1; then
    groupadd --system caddy
fi
if ! getent passwd caddy >/dev/null 2>&1; then
    useradd --system --gid caddy --home-dir /var/lib/caddy --shell /sbin/nologin caddy
fi
systemctl daemon-reload
