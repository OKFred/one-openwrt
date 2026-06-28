# ssh-watch — SSH 入侵监控工具

监听 OpenWrt `sshd-session` 日志中的非法登录尝试，**重点追查来自本机 `127.0.0.1` 的可疑连接**。

## 背景

日志中出现如下条目，说明有程序在从**本机**发起 SSH 暴力破解：

```
auth.info sshd-session[12950]: Invalid user user_arm_114 from 127.0.0.1 port 35518
```

来源是 `127.0.0.1`（回环地址），意味着**攻击者不是外网，而是路由器本身运行的某个进程**。

## 功能

- 实时监听 `logread -f`
- 匹配 `sshd-session` 的 `Invalid user` 事件
- 提取：用户名、来源 IP、来源端口
- 若来源为本地（`127.0.0.1`/`::1`），通过以下三种方式追查进程：
  1. `ss -tnp`（iproute2，最快）
  2. `netstat -tnp`（net-tools 备选）
  3. `/proc/net/tcp` + `/proc/PID/fd`（纯 BusyBox 兜底）
- 记录日志到 `ssh-watch.log`

## 使用

```sh
# 上传到路由器
scp -r tools/ssh-watch root@192.168.1.1:/root/ssh-watch

# 赋权
chmod +x /root/ssh-watch/index.sh /root/ssh-watch/stop.sh

# 前台运行（看实时输出）
sh /root/ssh-watch/index.sh

# 后台运行
sh /root/ssh-watch/index.sh &

# 停止
sh /root/ssh-watch/stop.sh

# 查看日志
tail -f /root/ssh-watch/ssh-watch.log
```

## 输出示例

```
[2026-06-29 02:16:04] [ALERT] ========================================
[2026-06-29 02:16:04] [ALERT] 检测到非法 SSH 登录尝试！
[2026-06-29 02:16:04] [ALERT]   用户名  : user_arm_114
[2026-06-29 02:16:04] [ALERT]   来源 IP : 127.0.0.1
[2026-06-29 02:16:04] [ALERT]   来源端口: 35518
[2026-06-29 02:16:04] [ALERT]   sshd PID: 12950
[2026-06-29 02:16:04] [WARN]    ⚠️  来源为本机回环地址！可能有本地程序在暴力破解 SSH！
[2026-06-29 02:16:04] [INFO]    正在通过端口 35518 追查发起进程...
[2026-06-29 02:16:04] [ALERT]   发起进程: PID=3721 COMM=python3 CMDLINE=[python3 /tmp/bot.py]
[2026-06-29 02:16:04] [ALERT] ========================================
```

## 注意事项

- 由于连接极短，进程查找存在**竞态**（连接关闭后端口释放，无法再反查）
- 若无法定位进程，建议配合 `ps` 和 `lsof` 手动排查可疑进程
- 发现可疑进程后，用 `kill <PID>` 终止，并检查 `/tmp`、`/var` 下的可疑文件
