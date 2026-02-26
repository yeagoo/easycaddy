#!/bin/bash
# caddy-selinux postinstall: 加载 SELinux 策略模块
semodule -i /usr/share/selinux/packages/caddy.pp
