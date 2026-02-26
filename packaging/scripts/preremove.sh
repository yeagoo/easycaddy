#!/bin/bash
systemctl stop caddy.service 2>/dev/null || true
systemctl disable caddy.service 2>/dev/null || true
