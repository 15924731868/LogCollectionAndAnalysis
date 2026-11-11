#!/usr/bin/env bash
# Lab10：创建 256MB loop 文件系统，放入旧备份文件，并安装日志写入器服务。
# setup 只准备条件，不启动写入器；启动动作放在任务 2，避免“满之前”的状态被提前写满。
set -euo pipefail

LAB_NAME="Lab10"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lablib.sh"

IMG="/opt/loglab-state/Lab10/disk.img"
MNT="/var/log/course-demo"
SIZE="256M"
FILL="220M"

need_root
require_command df
require_command awk
require_command truncate
require_command mkfs.ext4
require_command mount
require_command mountpoint
require_command fallocate
require_command logger
require_command systemctl
require_active loki
require_active grafana-server
require_active alloy
require_active rsyslog
state_init

backup_path /etc/systemd/system/course-logwriter.service
backup_path /usr/local/bin/course-logwriter.sh

# 幂等：先停掉上一次实验的写入器，避免它继续占用旧挂载点或旧镜像。
systemctl stop course-logwriter.service 2>/dev/null || true
systemctl disable course-logwriter.service >/dev/null 2>&1 || true
systemctl reset-failed course-logwriter.service 2>/dev/null || true

if mountpoint -q "$MNT"; then
  umount "$MNT" || umount -l "$MNT"
fi
rm -f "$IMG"

truncate -s "$SIZE" "$IMG"
# -b 1024 固定块大小，-i 16384 减少 inode 表占用，-m 0 去掉 root 保留块；
# 三者共同保证放入 220MB filler.bin 后仍有约 20MB 空间可供写入器写满。
mkfs.ext4 -q -F -b 1024 -i 16384 -m 0 "$IMG"
mkdir -p "$MNT"
mount -o loop "$IMG" "$MNT"
mountpoint -q "$MNT" || die "loop 文件系统没有挂载到 $MNT，请检查 mount 输出后重试。"

# 先放一个 220MB 的“旧备份文件”，留约 20MB 空间给日志写入。
fallocate -l "$FILL" "$MNT/filler.bin"

# 启动写入器之前必须留出可用块；否则后面无法观察“从有空间到写满”的过程。
used_pct="$(df -P "$MNT" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
if [ "${used_pct:-100}" -ge 100 ]; then
  die "放入 filler.bin 后文件系统已满（Use%=${used_pct:-unknown}%），请检查 mkfs 参数；可先运行 restore.sh 再重试。"
fi

cat > /usr/local/bin/course-logwriter.sh <<'EOF'
#!/usr/bin/env bash
# 课程演示用日志写入器：每秒写 1MB，直到文件系统写满。
set -uo pipefail
LOG="/var/log/course-demo/app.log"
ERR="/var/log/course-logwriter.err"
i=0
while true; do
  i=$((i + 1))
  if ! {
         printf '%s line=%d ' "$(date -Is)" "$i" &&
         head -c 1048576 /dev/zero | tr '\0' 'x' &&
         printf '\n'
       } >> "$LOG" 2>>"$ERR"; then
    err="$(tail -n 20 "$ERR" 2>/dev/null | grep -m 1 'No space left on device' || true)"
    if [ -z "$err" ]; then
      err="$(tail -n 1 "$ERR" 2>/dev/null || true)"
    fi
    msg="write failed: ${err:-unknown error}"
    printf '%s\n' "$msg" >> "$ERR"
    logger -t course-logwriter "$msg"
    echo "$msg" >&2
    exit 1
  fi
  sleep 1
done
EOF
chmod 0755 /usr/local/bin/course-logwriter.sh

cat > /etc/systemd/system/course-logwriter.service <<'EOF'
[Unit]
Description=Course log writer (disk full demo)
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/local/bin/course-logwriter.sh
Restart=no

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/course-logwriter.service

systemctl daemon-reload

log "已创建并挂载 256MB loop 文件系统：$MNT"
log "已放入 220MB 的 filler.bin。"
log "已创建 course-logwriter.service，但尚未启动。"
log "下一步：在任务 2 执行 sudo systemctl start course-logwriter.service"
log "当前状态（写入器启动前）："
df -h "$MNT" || true
df -i "$MNT" || true
