# Lab2 Linux 系统日志管理实验
> 实验环境：VMware Workstation + Ubuntu 24.04，SSH远程连接操作

## 一、实验目的
1. 了解Linux系统日志默认存放目录 `/var/log`，掌握常用日志文件功能。
2. 掌握 `ls`、`file`、`tail` 命令查看日志文件属性与日志内容。
3. 熟练使用 `journalctl`，按日志条数、时间范围、日志级别过滤 systemd 日志。
4. 区分传统 syslog 文本日志与 journald 二进制日志体系的差异。

## 二、实验环境
- 虚拟化平台：VMware
- 操作系统：Ubuntu 24.04 LTS
- 登录方式：SSH远程登录

## 三、实验步骤与命令
### 1. SSH登录验证
```bash
whoami
hostname -I
pwd
作用：确认登录用户名、主机 IP、当前工作目录。
2. 查看 /var/log 目录内容
bash
sudo ls -lh /var/log
3. 查看日志文件类型
bash
sudo file /var/log/syslog /var/log/auth.log /var/log/wtmp /var/log/btmp
4. 查看 journal 日志存储目录
bash
sudo ls -ld /var/log/journal /run/log/journal
5. 查看 syslog 日志最后 20 行
bash
sudo tail -n 20 /var/log/syslog
6. journalctl 查询日志
bash
# 查看最新30条日志
sudo journalctl -n 30

# 查看系统时间 + 按时间段筛选日志
date
sudo journalctl --since "2026-09-17 08:00:00" --until "2026-09-17 10:00:00"

# 只查看 warning 及以上级别警告日志
sudo journalctl -p warning
journalctl 分页操作：空格向下翻页，q 退出日志查看器。
四、实验结果说明
传统 syslog 日志（/var/log）
表格
文件	作用
/var/log/syslog	系统通用日志，记录大部分系统服务运行信息
/var/log/auth.log	身份认证、SSH 登录、sudo 操作安全审计日志
/var/log/wtmp	用户登录记录，二进制文件，不可直接 cat 读取
/var/log/btmp	登录失败记录，二进制格式
journald 日志
journald 是 systemd 配套日志服务，日志为二进制格式，存储路径分为持久化 /var/log/journal 和内存临时存储 /run/log/journal。支持丰富筛选条件：时间、日志等级、服务、进程 PID 等，适合故障排查和安全审计。
五、实验总结
本次实验学习了 Linux 两套日志体系：传统 syslog 文件日志和 journald 日志。
学会 SSH 远程登录查看系统日志；tail快速查看日志尾部；journalctl按条件过滤日志。
系统日志是系统故障排查、安全行为审计的核心数据源，通过日志可以发现服务异常、非法登录、系统警告等安全与运维信息。