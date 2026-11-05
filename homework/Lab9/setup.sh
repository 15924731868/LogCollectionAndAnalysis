#!/usr/bin/env bash
# Lab9：在两段时间里产生真实会话记录，并分别造成两类记录缺失。
# 会话记录由 PAM 经 rsyslog 写入 /var/log/auth.log，本脚本不向日志文件追加内容。
# 全部动作只在本机执行，不修改网络配置，不访问其他主机。

set -euo pipefail

LAB_NAME="Lab9"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lablib.sh"

AUTH_LOG="/var/log/auth.log"
ROTATED="${AUTH_LOG}.1"
USER_A="lab9a"
USER_B="lab9b"
USER_BG="lab9bg"
SESSIONS_A=6
SESSIONS_B=6
GAP_SECONDS=8

need_root
require_active rsyslog
require_active alloy
require_command journalctl
require_command useradd
require_command userdel
require_command su
state_init

[ -f "$AUTH_LOG" ] || die "找不到 $AUTH_LOG。请先确认 rsyslog 正在运行（systemctl status rsyslog）。"

# 采集器以 alloy 用户运行，读不到文件时平台上不会有任何 auth 记录。
sudo -u alloy head -n 1 "$AUTH_LOG" >/dev/null 2>&1 \
  || die "alloy 用户无法读取 $AUTH_LOG。请按 Lab5 检查 adm 组成员与文件权限后重试。"

if [ -f "$STATE_DIR/done" ]; then
  die "本机已经执行过本实验。请先运行 sudo bash restore.sh，再重新执行。"
fi

# 三个只用于产生会话记录的账号：不设密码，不能登录，不建立家目录。
for u in "$USER_A" "$USER_B" "$USER_BG"; do
  if ! id "$u" >/dev/null 2>&1; then
    useradd -M -s /bin/sh "$u"
  fi
done
printf '%s\n' "$USER_A" "$USER_B" "$USER_BG" > "$STATE_DIR/users"

# 阶段 A 需要把当前 auth.log 复制成轮转文件。若系统已有 .1，先移开，restore.sh 会还原。
if [ -e "$ROTATED" ]; then
  mv "$ROTATED" "${ROTATED}.lab9bak"
fi

session() {
  su -s /bin/sh -c true "$1" 2>/dev/null || true
}

# 背景会话让 auth 日志在整段实验期间保持连续，否则无法判断“某分钟没有记录”是否异常。
rm -f "$STATE_DIR/bg_stop"
(
  while [ ! -f "$STATE_DIR/bg_stop" ]; do
    su -s /bin/sh -c true "$USER_BG" 2>/dev/null || true
    sleep 6
  done
) &
BG_PID=$!

cleanup_bg() {
  touch "$STATE_DIR/bg_stop"
  wait "$BG_PID" 2>/dev/null || true
  rm -f "$STATE_DIR/bg_stop"
}
trap cleanup_bg EXIT

log "先建立一段正常记录，约 15 秒。"
sleep 15

log "阶段 A：产生 ${SESSIONS_A} 次会话记录。"
systemctl stop alloy
for _ in $(seq 1 "$SESSIONS_A"); do
  session "$USER_A"
  sleep "$GAP_SECONDS"
done
sync

# 复制副本后清空当前文件。rsyslog 的写入位置记录在打开的文件描述符上，
# 清空时必须先停住写入，否则下一次写入会落在原来的偏移处，文件前部变成 NUL 空洞。
systemctl stop rsyslog
if ! cp -a "$AUTH_LOG" "$ROTATED" || ! truncate -s 0 "$AUTH_LOG"; then
  systemctl start rsyslog
  die "复制或清空 $AUTH_LOG 失败，已重新启动 rsyslog。"
fi
systemctl start rsyslog
systemctl start alloy
log "阶段 A 完成。"

for _ in $(seq 1 20); do
  systemctl is-active --quiet alloy && break
  sleep 1
done
sleep 8

log "阶段 B：产生 ${SESSIONS_B} 次会话记录。"
for _ in $(seq 1 "$SESSIONS_B"); do
  session "$USER_B"
  sleep "$GAP_SECONDS"
done

log "等待采集器发送阶段 B 的记录，约 30 秒。"
sleep 30
cleanup_bg
trap - EXIT

grep -q "user ${USER_B}" "$AUTH_LOG" \
  || die "阶段 B 的记录没有写入 $AUTH_LOG。请检查 rsyslog 与 PAM 配置后重试。"

sed -i "/user ${USER_B}/d" "$AUTH_LOG"
log "阶段 B 完成。"

touch "$STATE_DIR/done"

cat <<EOF
[${LAB_NAME}] 现场已经准备好。
[${LAB_NAME}] 本机有两段时间的记录出现了缺失，成因不同。
[${LAB_NAME}] 先按第四、五节分别核对平台与本机文件，再读本脚本的实现。
[${LAB_NAME}] 查看日志文件：ls -l /var/log/auth.log*
[${LAB_NAME}] 实验结束后运行：sudo bash restore.sh
EOF
