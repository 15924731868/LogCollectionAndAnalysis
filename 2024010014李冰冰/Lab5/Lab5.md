s找到负责读文件的 `loki.source.file "linux_logs"`，重点看下面几项：

| 配置内容 | 回答的问题 |
| :--- | :--- |
| `targets` 中的 `__path__` | 从哪个路径读取文件？ |
| `targets` 中的 `job`、`host` | 给日志加上哪些来源标记，也就是“标签”？ |
| `file_match` | 是否定期检查这些路径下有没有新文件？ |
| `forward_to` | 读到的日志交给谁发送？这里交给 `loki.write.local.receiver`，也就是上面的发送部分 |

本次读取以下文件，并用 `job` 区分来源：

| 采集路径 | `job` 标签 | 本次要求 |
| :--- | :--- | :--- |
| `/var/log/syslog` | `syslog` | 查到本人通过 logger 写入的测试日志 |
| `/var/log/auth.log` | `auth` | 验证权限，并查询 sudo 活动 |
| `/var/log/nginx/access.log` | `nginx_access` | 提前配置，Lab6 用真实 HTTP 请求产生数据后验证 |
| `/var/log/nginx/error.log` | `nginx_error` | 提前配置，有错误记录时才有可查询的数据 |

**标签可以理解为日志的来源说明**：`job` 表示哪一类日志，`host` 表示来自哪台主机，`filename` 表示来自哪个文件。所有标签都相同的日志归为一组，Loki 把这样的一组叫作“日志流”。同一条消息从不同文件读入，标签不同，就会分到不同的组。

标签也需要控制数量。`job` 通常只有几类，HTTP 状态码（如 `200`、`404`）的种类也有限；完整 URI（请求地址，如 `/news?page=1`）却可能有大量不同值。把这些变化很多的内容都作为标签，会产生太多日志组，增加存储和查询的负担。

本次只读取表中的当前日志文件，不重新导入 `.1`、`.gz` 等旧日志。Alloy 会记住读到了哪里；只要这份记录和日志文件正常保留，重启后就可以接着读。

> **注意查询结果中的时间**
> 按本次配置，Loki 中的时间是 Alloy 读到日志的时间，没有使用日志正文里原本的时间。因此，旧文件刚被读取时，其中的旧日志也可能出现在“最近一小时”里。后面要重新发送一条测试日志，并对照正文里的时间确认是刚写入的那条，才能说明新日志也在正常收集。

> **记录**
>
> ① Alloy 能否正常读取上面的两个文件？
>
> 答：Alloy 可以正常读取`/var/log/syslog`与`/var/log/auth.log`
>
> ② 哪个配置项决定“读哪个文件”？哪个决定“发到哪里”？`forward_to` 把读到的日志交给了谁？
>
> 答：`loki.source.file`下的`targets`中的`__path__`决定读取哪些日志文件；`loki.write "local"`中的 endpoint 的 url 决定日志发送到哪里；`forward_to`将读到的日志交给`loki.write.local.receiver`

### 4.3 写入新日志，用 API 查到同一条记录

Alloy 启动后，再执行一次写日志的命令：

```bash
logger -p user.notice -t lab3_read "student_id=你的学号 name=你的姓名 action=write_test result=success"
```

把学号和姓名替换为自己的，再查看本地最新一条记录：

```bash
sudo grep 'student_id=你的学号' /var/log/syslog | tail -n 1
```

先确认这条日志已经写入本地文件。如果暂时没有结果，等 1～2 秒再查；找到后记下这行日志的时间，再检查 Alloy 是否把它送到了 Loki。

等待约 15 秒，给 Alloy 留出读取和发送的时间，再查看 Loki 里有哪些日志来源：

```bash
curl -sS http://127.0.0.1:3100/loki/api/v1/label/job/values
```

返回的 `job` 列表中应包含 `syslog`。其他来源只有在读到日志后才会出现，暂时没有 nginx 的记录不影响本次实验。

**接着查找刚才那条带学号的新日志：**

```bash
curl -sS -G http://127.0.0.1:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="syslog"} |= "student_id=你的学号" |= "lab3_read" |= "action=write_test"' \
  --data-urlencode 'since=1h' \
  --data-urlencode 'limit=20'
```

这是一条分成多行书写的命令，行尾 `\` 表示下一行仍属于同一条命令。查询中的学号也要替换为自己的。`query=` 后面的查询语句叫作 **LogQL**，用来告诉 Loki“查哪个来源、找什么内容”。

| 参数或内容 | 含义 |
| :--- | :--- |
| `-G` | 把后面的查询条件放到请求地址中，用 GET 方式发送 |
| `--data-urlencode` | 处理查询中的空格、引号等符号，让它们能正确传给 Loki |
| `query=...` | 告诉 Loki 要查什么 |
| `{job="syslog"}` | 先选择 `job` 为 `syslog` 的日志 |
| `\|= "文本"` | 再要求日志正文包含这段文本，多个过滤条件要同时满足 |
| `since=1h` | 查询最近一小时的范围 |
| `limit=20` | 最多返回 20 条日志 |

返回结果使用 JSON 格式，可以重点看两处：`status` 为 `success` 表示查询正常执行，`data.result` 才是查到的日志。**要找到自己的学号和 `action=write_test`，并核对日志正文中的时间与刚才本地最新一行一致。** 如果结果为空，或只有之前的旧记录，还需要继续检查。

> **记录**
>
> ① 返回了哪些 `job`？API 返回的本人新日志原文是什么？
>
> 答：API 返回的 job：`syslog`
API 返回本人新日志原文：`user123-VMware-Virtual-Platform lab3_read: student_id=2024010014 name=李冰冰 action=write_test result=success`
>
> ② 如果只看到 `success`，而 `data.result` 为空，你会先检查什么？
>
> 答：先检查本地 syslog 是否生成对应日志；检查 Alloy 服务是否正常、是否拥有日志文件读取权限；检查查询语句、时间范围是否正确；查看 Alloy 服务日志确认是否成功推送日志到 Loki

保存 `imgs/lab5_alloy.png`，保留文件读取权限验证、`job` 查询和包含本人日志的 API 结果；可以合理拼图。

![确认日志已进入 Loki](imgs/lab5_alloy.png)

---

## 五、任务 4：配置 Grafana，在网页查到日志

用 API 查到新日志后，就可以接上 Grafana，在网页中查看同一条记录了。如果 API 还查不到，请先按第四节检查日志是否已送到 Loki。

### 5.1 让 Grafana 连接 Loki

```bash
cd ~/Lab5
sudo bash install.sh grafana
```

脚本会告诉 Grafana 到哪里查询日志，并启动 Grafana。这样的连接设置在界面里叫作“数据源”，本次数据源的名字是 **Loki**。

```bash
systemctl is-active grafana-server
```

注意 Grafana 的服务名是 `grafana-server`。正常应输出 `active`。

```bash
sudo cat /etc/grafana/provisioning/datasources/loki.yml
```

找到其中的 `http://127.0.0.1:3100`。这是 **Grafana 用来访问 Loki** 的地址。两个软件都在 Ubuntu 虚拟机里，因此这里的 `127.0.0.1` 就是它们所在的这台虚拟机。

```bash
hostname -I
```

大写 `-I` 列出虚拟机的 IP 地址。选择 Windows 能够访问的那个地址，通常就是 Xshell 连接时使用的 IP。

在 **Windows 浏览器**打开 `http://虚拟机IP:3000`。首次登录默认账号和密码都是 `admin`，登录后按页面提示修改密码；已经设置过则使用自己的密码。**报告和截图中不要出现密码。**

| 访问方向 | 本次地址 | 为什么这样写 |
| :--- | :--- | :--- |
| Windows 浏览器 → Grafana | `http://虚拟机IP:3000` | Windows 上的 `127.0.0.1` 指向 Windows 自己，要用虚拟机 IP 才能找到 Grafana |
| Grafana → Loki | `http://127.0.0.1:3100` | 两个软件都在虚拟机内，可以直接通过本机地址连接 |

进入 **Connections → Data sources → Loki**，点击 **Test** 或 **Save & test**（不同版本名称略有不同），确认出现连接成功的提示。

> **记录**：浏览器实际访问地址是什么？为什么浏览器用虚拟机 IP，而数据源配置里可以用 `127.0.0.1`？
>
> 答：浏览器访问地址：`http://172.20.10.5:3000`；浏览器运行在 Windows 主机，`127.0.0.1`代表 Windows 本机，所以需要填写虚拟机真实 IP；Grafana 和 Loki 都运行在 Ubuntu 虚拟机内部，虚拟机内部 127.0.0.1 代表本机，可以直接通信

保存 `imgs/lab5_datasource.png`，保留 Loki 数据源名称、连接地址和测试成功的结果。

![数据源测试](imgs/lab5_datasource.png)

### 5.2 在 Explore 页面查询自己的日志

打开查询页面 **Explore**，选择 **Loki** 数据源，再选择 **Code** 模式，这样就可以直接输入查询语句。

**查询语句怎么写？先选来源，再筛选文字。** 例如：

```logql
{job="syslog"} |= "lab3_read" |= "student_id=你的学号"
```

从左到右读，就能看懂它在查什么：

| 这一段 | 含义 |
| :--- | :--- |
| `{job="syslog"}` | 从 `syslog` 这个来源中查找日志。`job` 的值来自 Alloy 的采集配置 |
| `\|= "lab3_read"` | 只保留正文中包含 `lab3_read` 的记录，也就是我们写日志时使用的标记 |
| `\|= "student_id=你的学号"` | 再筛选出自己的记录，使用前换成实际学号 |

花括号里的 `=` 表示标签值相等，花括号外的 `|=` 表示正文包含指定文字。**多个 `|=` 要同时满足**，每增加一个条件，就是进一步缩小结果范围。文字匹配区分大小写，输入时使用英文双引号。

**时间范围在页面上设置。** 把它设为 **Last 1 hour**（最近一小时），查询就只查看这段时间内的日志；不用把 API 命令里的 `since=1h` 写进查询框。

现在再加上 `action=write_test`，只看这次写入测试的记录。下面这条与 4.3 节的查询相同，替换学号后输入：

```logql
{job="syslog"} |= "student_id=你的学号" |= "lab3_read" |= "action=write_test"
```

在网页中直接输入查询语句即可，不需要加 `query=`。点击 **Run query** 执行查询，再展开自己的日志，查看 `job`、`host`、`filename`。

核对日志内容是否与 API 查到的一致。它的 `job` 应为 `syslog`，`filename` 应为 `/var/log/syslog`。如果距离写入已经超过一小时，可以扩大时间范围，或重新发送一条测试日志。

> **记录**
>
> ① 网页查到的完整日志原文是什么？与 API 返回的记录是否一致？
>
> 答：网页日志原文：`user123-VMware-Virtual-Platform lab3_read: student_id=2024010014 name=李冰冰 action=write_test result=success`；网页查询结果与 API 返回记录内容完全一致。
>
> ② 这条日志的 `job`、`host`、`filename` 分别是什么？
>
> 答：`job="syslog"`，`host="user123‑VMware‑Virtual‑Platform"`，`filename="/var/log/syslog"`

保存 `imgs/lab5_explore.png`，保留数据源、时间范围、查询语句、本人日志正文和展开后的标签。

![本人日志与展开标签](imgs/lab5_explore.png)

---

## 六、任务 5：继续练习日志查询

### 6.1 按结果筛选测试日志

前面按 `action=write_test` 查找了测试日志，也可以按结果查找。在 Explore 中输入：

```logql
{job="syslog"} |= "student_id=你的学号" |= "lab3_read" |= "result=success"
```

这条查询仍然从 `syslog` 中查找本人日志，只是把最后一个条件换成了 `result=success`。可以看到，`job` 决定从哪里查，后面的文字条件决定保留哪些记录。

> **记录**：这条查询查到了什么？其中 `job="syslog"` 和 `|= "result=success"` 各起什么作用？
>
> 答：查到本人那条 result=success 的测试日志；`job="syslog"`筛选标签，限定只取 syslog 来源的日志流；`|= "result=success"`做正文关键字过滤，只保留正文包含该文本的日志。

### 6.2 查找一次 sudo 操作的日志

在虚拟机里执行：

```bash
sudo -k
```

`sudo` 通常会暂时记住最近一次密码验证。`-k` 会清除这个记录，让下一次需要密码的 sudo 操作重新提示输入；它不会修改密码。

```bash
sudo true
```

`true` 本身不做其他操作，只表示命令成功结束。这里通过 sudo 运行它，是为了留下一条 sudo 操作记录。按提示输入密码即可，不要写进报告。

在 Explore 中查询：

```logql
{job="auth"} |= "sudo"
```

这条查询在 `auth` 来源中查找包含 `sudo` 的日志。如果没有结果，检查 `/var/log/auth.log` 是否出现新行、Alloy 能否读取，以及网页的时间范围是否合适。

### 6.3 记录查询结果，保留实验环境

把实际用过的三条查询写在下面，学号等内容要换成自己的，**让查询语句可以直接复制使用**。除了截图，也要用文字简单说明查到了什么。

| 查询目的 | 实际 LogQL | 查到的结果摘要 |
| :--- | :--- | :--- |
| 在 syslog 中查本人测试日志 | `{job="syslog"} |= "student_id=2024010014" |= "lab3_read" |= "action=write_test"` | 查询到本人logger生成、action=write_test的测试日志记录 |
| 筛选本人结果为 success 的测试日志 | `{job="syslog"} |= "student_id=2024010014" |= "lab3_read" |= "result=success"` | 筛选出本人测试中result字段为success的测试日志 |
| 查询 sudo 认证活动 | `{job="auth"} |= "sudo"` | 获取系统sudo命令执行、密码校验相关的认证操作日志 |



完成这三条查询后，你就检查了日志从写入文件、发送到 Loki，再到网页显示的整个过程，也比较了不同来源的记录。

**完成后保留本次安装的软件和配置，并创建“Lab5 平台可用”快照。** 下次还要接着使用，正常结束实验时不运行 `restore.sh`。

Lab6 会继续使用这些成果：

| Lab5 留下的成果 | Lab6 怎样继续使用 |
| :--- | :--- |
| 已安装的 nginx | 在 8080 端口配置演示网站，通过访问网页产生日志 |
| 已配置的 `nginx_access` 采集路径 | 继续用 Alloy 读取新生成的 access.log |
| 可用的 Loki 和 Grafana 数据源 | 不重装平台，直接在 Explore 查询 nginx 日志 |
| `{job="..."}` 与 `\|=` 过滤 | 先找到自己的访问记录，再提取状态码等内容 |
| 日志来源和采集时间 | 确定统计哪些日志、哪个时间段 |

本次还没有 nginx 日志也没关系，Lab6 会通过实际访问网页来产生。到时将继续学习：**怎样从日志中找出状态码，怎样统计最近五分钟的访问次数。**

---

## 七、知识问答

每题用 1～3 句话回答，无需另做实验。

1. 本地文件里有自己的日志，但用 Loki API 查不到，你会先检查哪两处？如果 API 能查到，而网页查不到，又该检查什么？

   > 填写：先检查 Alloy 服务状态、Alloy 读取日志文件的权限，再核对 Alloy 推送给 Loki 的目标地址配置是否正确。API 能够查到但网页查不到，需要核对 Grafana 选中的数据源、页面时间范围、LogQL 查询语句是否与 API 查询保持一致

2. 用自己的话说明，一条日志怎样经过“logger → 文件 → Alloy → Loki → Grafana”。rsyslog 和 Alloy 分别做什么？日志内容由 Grafana 保存吗？

   > 填写：logger 命令产生日志消息，rsyslog 接收消息写入本地`/var/log/syslog`磁盘文件；Alloy 读取磁盘上的日志文件，推送给 Loki；Loki 存储日志；Grafana 向 Loki 发起查询，展示返回结果。rsyslog 负责接收系统日志消息并写入本地磁盘文件；Alloy 负责读取本地日志文件，转发给 Loki。**Grafana 不保存日志，日志全部保存在 Loki**

3. `job`、完整 URI（请求地址）、HTTP 状态码，哪些通常只有少量不同值，哪些可能有很多？为什么不适合把日志里的所有内容都作为标签保存？

   > 填写：`job`、HTTP 状态码取值数量少；完整 URI 会有大量不同取值。标签每一组不同组合会生成一条日志流，如果把变化很多的字段全部设为标签，会产生大量日志流，消耗大量存储与查询性能

---

## 八、常见问题

| 现象 | 原因 | 处理 |
| :--- | :--- | :--- |
| 脚本提示 `$'\r': command not found` 等错误 | 文件使用了 Windows 的换行格式，Bash 无法正确读取 | 在虚拟机的 `~/Lab5/` 中执行 `sed -i 's/\r$//' install.sh restore.sh`，再重试原命令 |
| `packages` 安装失败 | 可能是网络、软件源或磁盘空间问题，具体看报错 | 按报错提示处理，再重新运行安装命令；安装成功后继续配置 |
| 配置 Loki 时提示 `install: invalid group 'loki'` | 旧版脚本假定用户组也叫 `loki`，但实际组名可能不同 | 用 `id loki` 查看用户和组；上传新版 `install.sh` 后重新运行 `sudo bash install.sh loki`，脚本会使用实际组名 |
| 发了消息，syslog 中没有新行 | rsyslog 未运行，或系统默认的日志规则被修改 | 检查 `systemctl is-active rsyslog` 和 `/etc/rsyslog.d/50-default.conf`，确认有写入 `/var/log/syslog` 的规则 |
| Loki 显示 `active`，但 `/ready` 没返回 `ready` | 可能还在启动，也可能是配置或数据目录有问题 | 先等 30～60 秒；一直不成功时查看 `journalctl -u loki` |
| Alloy 读不了日志 | `alloy` 用户没有权限读文件或进入目录 | 用 `sudo -u alloy head -n 1 文件` 检查，再核对 `adm` 组和文件、目录权限；修改后重启 Alloy |
| API 返回 `success`，但结果为空 | 查询执行了，但没找到符合条件的日志 | 依次检查本地有没有新行、Alloy 能否读取、Alloy 是否报错，最后核对查询条件和时间范围 |
| API 能查到本人日志，网页却查不到 | 网页使用的数据源、时间范围或查询条件不一致 | 在网页中使用与 API 相同的查询，核对是否选中了 Loki 和正确的时间范围 |
| Windows 浏览器打不开 Grafana | 服务未启动，或 IP、网络、防火墙设置有问题 | 先在虚拟机用 `curl -I http://127.0.0.1:3000` 检查服务，再检查网络；不要关闭全部防火墙规则 |
| 找不到 `nginx_access` 或 `nginx_error` | 还没有产生日志，或没有错误记录 | 本次不要求这两个来源有数据，Lab6 访问网页后再检查 |
| 旧日志出现在最近的时间范围内 | 本次使用 Alloy 读到日志的时间 | 重新写入一条带标记的日志来检查，注意区分日志产生和被读取的时间 |
| 想撤销本次配置或重新搭建 | 需要恢复原来的配置文件 | 先阅读 9.2 节，确认恢复脚本会做什么；正常结束实验时不用执行 |

---

## 九、选读内容

**本节不要求执行、填写或截图**，供感兴趣时查阅。

### 9.1 在 Explore 中观察实时日志

Explore 的 **Live** 模式会持续显示新收到的日志。可以先打开 `{job="syslog"} |= "lab3_read"` 的实时查询，再在终端执行一次 2.4 节的 logger 命令，观察它多久会出现在网页中。

这是同一批日志的另一种查看方式，不需要另外提交截图。

### 9.2 恢复脚本能恢复什么，不能恢复什么

如果要撤销本次配置，可以使用上传到虚拟机的 `~/Lab5/restore.sh`。它会停止 Loki、Alloy、Grafana，并恢复第一次配置前备份的文件。**软件、Loki 中的日志、Grafana 中的仪表盘（Dashboard）都会保留，软件源和用户组设置也不会撤销。**

这个脚本只恢复部分配置，效果与恢复虚拟机快照不同。运行后平台会停止服务，Lab6 就无法直接继续，所以正常完成实验时请保留当前环境。

备份放在 `/opt/loglab-state/Lab5/`。如果之后想重新启用课程平台，在虚拟机的 `~/Lab5/` 中依次运行 `sudo bash install.sh loki`、`sudo bash install.sh alloy`、`sudo bash install.sh grafana`，再按第二至五节检查能否正常写入、收集和查询日志。

### 9.3 进阶阅读

- [Loki 概述](https://grafana.com/docs/loki/latest/get-started/overview/)：了解 Loki 怎样保存和查询日志。
- [Grafana Alloy 简介](https://grafana.com/docs/alloy/latest/introduction/)：了解日志采集之外的能力。
- [Promtail 生命周期说明](https://grafana.com/docs/loki/latest/send-data/promtail/)：旧教程中常见的采集工具，了解它停止维护后的替代建议。
- [Elastic Stack 概览](https://www.elastic.co/docs/get-started/the-stack)：对照 Elasticsearch、Kibana、Logstash、Elastic Agent 和 Beats 的分工。
- [OpenSearch 文档](https://docs.opensearch.org/latest/)：了解另一套搜索与分析平台。

阅读时先关注三个问题：谁负责收集，谁负责保存和查询，谁负责展示。熟悉这些分工后，再了解各工具的具体功能。

---

## 十、截图与提交

在 Windows 上，将本文件复制到自己的“学号姓名”文件夹下，保存为 `Lab5/Lab5.md`，并在 `Lab5/` 中创建 `imgs/` 目录。每个任务旁边都有填写区和图片位置，做完一项就记录一项。

**请完整保留模板，在填写区增加答案、实际命令和日志结果。** 自动审核会检查报告的总行数、非空行数，以及 `#`、`-`、`*`、反引号、`|`、`>` 六类字符的数量，每一项都不能少于发布模板。不要删减说明、示例或选读，也不要删除表格、引用和代码块的排版符号。数量检查通过后，还会继续审核回答和截图是否符合实验要求。

本次单独提交 **1 份 Markdown 报告和 5 张截图**。报告中要填写各处记录、三条实际查询和三道简答题。提交前，按下表检查截图是否齐全。

| 操作位置 | 截图必须体现的内容 | 文件名 |
| :--- | :--- | :--- |
| 2.3、2.4 节 | 本地测试日志的查询命令、本人学号和软件版本 | `lab5_prepare.png` |
| 3.2 节 | Loki 服务状态、`/ready` 请求与返回结果 | `lab5_loki.png` |
| 4.1、4.3 节 | Alloy 读取权限、job 标签与包含本人新日志的 API 结果 | `lab5_alloy.png` |
| 5.1 节 | Loki 数据源、连接地址与测试成功结果 | `lab5_datasource.png` |
| 5.2 节 | Explore 的数据源、时间范围、查询、本人日志与展开标签 | `lab5_explore.png` |

- 使用电脑截图，保证文字清晰，不使用手机拍摄屏幕。
- 终端截图应同时显示命令和对应输出，并能辨认本人虚拟机的用户名或主机名。
- 查询页面截图要保留数据源、时间范围、查询语句和关键结果；数据源设置页面按上表截图。
- 同一任务可以拼图，也可以裁掉无关区域，但要保留命令、时间和关键结果。
- 使用本人实验结果，截图中不得出现密码、私钥或访问令牌。
- 图片放在 `imgs/` 中，文件名、扩展名和大小写都要与表格一致，确保报告能正常显示图片。

提交前确认目录结构：

```text
学号姓名/
└── Lab5/
    ├── Lab5.md
    └── imgs/
        ├── lab5_prepare.png
        ├── lab5_loki.png
        ├── lab5_alloy.png
        ├── lab5_datasource.png
        └── lab5_explore.png
```

按仓库 README 的流程单独提交 Lab5，PR 标题为 `[学号姓名]Lab5作业提交`。

---

## 十一、截止时间

**2026 年 10 月 15 日 23:59:59（北京时间）**

请在截止时间前创建 Lab5 的 PR 并完成推送。按仓库 `README.md` 第 4 节的规则，从 10 月 16 日 00:00 起，新建 PR 或继续向已有 PR 推送修改都算超时。如果审核要求修改，也要在截止前完成。
