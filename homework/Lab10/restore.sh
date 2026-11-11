#!/usr/bin/env bash
# Lab10：停止写入器，卸载并删除 loop 文件系统，移除服务与脚本。
# 保留 /var/log/course-logwriter.err 和 syslog 中的失败记录作为证据。
set -euo pipefail

LAB_NAME="Lab10"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lablib.sh"

IMG="/opt/loglab-state/Lab10/disk.img"
MNT="/var/log/course-demo"

need_root
require_command mountpoint
require_command systemctl

systemctl stop course-logwriter.service 2>/dev/null || true
systemctl disable course-logwriter.service >/dev/null 2>&1 || true
systemctl reset-failed course-logwriter.service 2>/dev/null || true

if mountpoint -q "$MNT"; then
  umount "$MNT" || umount -l "$MNT"
fi

rm -f "$IMG"
rmdir "$MNT" 2>/dev/null || true

restore_backups
systemctl daemon-reload

log "已停止 course-logwriter，卸载并删除 $MNT 的 loop 文件系统。"
log "保留 /var/log/course-logwriter.err、syslog 和 Loki 中的历史记录。"
