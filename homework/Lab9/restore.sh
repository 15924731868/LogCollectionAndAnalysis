#!/usr/bin/env bash
# Lab9：清理实验账号，还原被移走的系统轮转文件。
# /var/log/auth.log、Loki 中的数据与实验产生的记录副本均保留，供复盘与评分。

set -euo pipefail

LAB_NAME="Lab9"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lablib.sh"

AUTH_LOG="/var/log/auth.log"
ROTATED="${AUTH_LOG}.1"

need_root

if ! systemctl is-active --quiet alloy; then
  systemctl start alloy
  log "已启动 alloy。"
fi

if [ -f "$STATE_DIR/users" ]; then
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    if id "$u" >/dev/null 2>&1; then
      userdel "$u" 2>/dev/null || true
      log "已删除账号 $u"
    fi
    if getent group "$u" >/dev/null 2>&1; then
      groupdel "$u" 2>/dev/null || true
    fi
  done < "$STATE_DIR/users"
fi

if [ -e "${ROTATED}.lab9bak" ]; then
  if [ -e "$ROTATED" ]; then
    mv -f "$ROTATED" "$STATE_DIR/auth.log.1"
    log "实验产生的副本已保存到 $STATE_DIR/auth.log.1"
  fi
  mv -f "${ROTATED}.lab9bak" "$ROTATED"
  log "已还原系统原有的 $ROTATED"
elif [ -e "$ROTATED" ]; then
  log "保留实验产生的 $ROTATED；其中包含阶段 A 的记录。"
fi

rm -f "$STATE_DIR/done" "$STATE_DIR/bg_stop"

log "清理完成。日志文件与平台数据未删除。"
log "如需重新执行，运行 sudo bash setup.sh。"
