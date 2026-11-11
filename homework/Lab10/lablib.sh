#!/usr/bin/env bash
# Lab10 自带公共函数。调用方先设置 LAB_NAME，再 source 本文件。
# Lab10 目录可以单独上传，不依赖其他实验目录的公共脚本。
# 用法示例：
#   LAB_NAME="Lab10"
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lablib.sh"
set -euo pipefail

LAB_NAME="${LAB_NAME:-lab}"
STATE_ROOT="${STATE_ROOT:-/opt/loglab-state}"
STATE_DIR="${STATE_ROOT}/${LAB_NAME}"

log() {
  printf '[%s] %s\n' "$LAB_NAME" "$*"
}

die() {
  printf '[%s] 错误：%s\n' "$LAB_NAME" "$*" >&2
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 sudo 运行本脚本。"
  fi
}

state_init() {
  mkdir -p "$STATE_DIR/backups"
  touch "$STATE_DIR/backup.list"
}

safe_key() {
  printf '%s' "$1" | sed 's#/#__#g'
}

# 备份一个文件、目录或符号链接。重复调用不会覆盖第一次的备份。
backup_path() {
  local target="$1" key
  key="$(safe_key "$target")"
  mkdir -p "$STATE_DIR/backups"
  if grep -Fxq -- "$target" "$STATE_DIR/backup.list" 2>/dev/null; then
    return 0
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    cp -a "$target" "$STATE_DIR/backups/${key}"
  else
    : > "$STATE_DIR/backups/${key}.MISSING"
  fi
  printf '%s\n' "$target" >> "$STATE_DIR/backup.list"
}

# 按 backup.list 恢复；实验新建的文件/目录会被删除。
restore_backups() {
  if [ ! -f "$STATE_DIR/backup.list" ]; then
    log "没有备份清单，跳过文件恢复。"
    return 0
  fi
  local target key
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    key="$(safe_key "$target")"
    if [ -e "$STATE_DIR/backups/${key}.MISSING" ]; then
      rm -rf -- "$target"
      log "已删除实验新建的 $target"
    elif [ -e "$STATE_DIR/backups/${key}" ] || [ -L "$STATE_DIR/backups/${key}" ]; then
      rm -rf -- "$target"
      cp -a "$STATE_DIR/backups/${key}" "$target"
      log "已恢复 $target"
    else
      log "备份缺失，保留现状：$target"
    fi
  done < "$STATE_DIR/backup.list"
}

require_active() {
  local service="$1"
  systemctl is-active --quiet "$service" \
    || die "服务 $service 未运行，请先完成 Lab5/Lab6 或恢复快照。"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || die "缺少命令：$1。请先按实验文档安装。"
}

restart_if_active() {
  local service="$1"
  if systemctl is-active --quiet "$service"; then
    systemctl restart "$service"
  fi
}
