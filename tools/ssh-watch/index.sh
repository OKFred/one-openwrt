#!/bin/sh
# =============================================================================
# ssh-watch/index.sh — SSH 异常登录监控脚本
# 监听 sshd-session 中的 "Invalid user" 事件，并追查发起连接的本地进程
# 适用于 OpenWrt / BusyBox 环境
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/ssh-watch.log"
PID_FILE="${SCRIPT_DIR}/ssh-watch.pid"

# 日志颜色（仅终端输出使用）
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# 带时间戳的日志记录（同时写文件 + 输出到 stderr）
# -----------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[$ts] [$level] $msg"

    # 写入日志文件
    echo "$line" >> "$LOG_FILE"

    # 终端彩色输出
    case "$level" in
        ALERT)  echo "${RED}${line}${NC}" >&2 ;;
        WARN)   echo "${YELLOW}${line}${NC}" >&2 ;;
        INFO)   echo "${GREEN}${line}${NC}" >&2 ;;
        *)      echo "${CYAN}${line}${NC}" >&2 ;;
    esac
}

# -----------------------------------------------------------------------------
# 通过源端口查找本地进程（仅在源 IP 为 127.0.0.1 时有意义）
# 依次尝试 ss、netstat、/proc 三种方式
# -----------------------------------------------------------------------------
find_process_by_port() {
    local src_port="$1"
    local found=""

    # 方法 1：ss（BusyBox iproute2）
    # 匹配 127.0.0.1:<src_port> 作为本端（ESTABLISHED 或 TIME-WAIT）
    if command -v ss >/dev/null 2>&1; then
        # 查找持有该源端口的连接，提取 PID
        local ss_out
        ss_out="$(ss -tnp 2>/dev/null | grep ":${src_port}[[:space:]]")"
        if [ -n "$ss_out" ]; then
            local pid
            pid="$(echo "$ss_out" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)"
            if [ -n "$pid" ]; then
                local comm
                comm="$(cat /proc/${pid}/comm 2>/dev/null || echo 'unknown')"
                local cmdline
                cmdline="$(tr '\0' ' ' < /proc/${pid}/cmdline 2>/dev/null | head -c 200)"
                found="PID=${pid} COMM=${comm} CMDLINE=[${cmdline}]"
            fi
        fi
    fi

    # 方法 2：netstat（如果 ss 未找到）
    if [ -z "$found" ] && command -v netstat >/dev/null 2>&1; then
        local net_out
        net_out="$(netstat -tnp 2>/dev/null | grep "[[:space:]]127\.0\.0\.1:${src_port}[[:space:]]")"
        if [ -n "$net_out" ]; then
            local pid_comm
            pid_comm="$(echo "$net_out" | awk '{print $NF}' | head -1)"
            found="PID/PROG=${pid_comm} (netstat)"
        fi
    fi

    # 方法 3：遍历 /proc/net/tcp（纯 BusyBox 兜底）
    # /proc/net/tcp 中端口以16进制存储，本地地址格式 0100007F:8AEE
    if [ -z "$found" ] && [ -f /proc/net/tcp ]; then
        # 将十进制端口号转为4位大写16进制
        local hex_port
        hex_port="$(printf '%04X' "$src_port")"
        # 本地 127.0.0.1 以小端16进制表示为 0100007F
        local line_match
        line_match="$(awk -v hp="$hex_port" '
            $2 ~ "0100007F:" hp { print $0 }
        ' /proc/net/tcp 2>/dev/null | head -1)"

        if [ -n "$line_match" ]; then
            # 第10列是 inode
            local inode
            inode="$(echo "$line_match" | awk '{print $10}')"
            if [ -n "$inode" ]; then
                # 在 /proc/*/fd/* 中找匹配该 inode 的符号链接
                local pid
                pid="$(ls -la /proc/*/fd 2>/dev/null \
                    | awk -v ino="socket:\[${inode}\]" '$NF == ino {print FILENAME}' \
                    | grep -oE '/proc/[0-9]+' | head -1 | cut -d/ -f3)"
                if [ -n "$pid" ]; then
                    local comm
                    comm="$(cat /proc/${pid}/comm 2>/dev/null || echo 'unknown')"
                    local cmdline
                    cmdline="$(tr '\0' ' ' < /proc/${pid}/cmdline 2>/dev/null | head -c 200)"
                    found="PID=${pid} COMM=${comm} CMDLINE=[${cmdline}] (via /proc/net/tcp inode=${inode})"
                fi
            fi
        fi
    fi

    if [ -n "$found" ]; then
        echo "$found"
    else
        echo "UNKNOWN (connection may have closed before lookup, port=${src_port})"
    fi
}

# -----------------------------------------------------------------------------
# 处理一条 "Invalid user" 日志行
# 样例：Mon Jun 29 02:16:04 2026 auth.info sshd-session[12950]: Invalid user user_arm_114 from 127.0.0.1 port 35518
# -----------------------------------------------------------------------------
handle_invalid_user() {
    local raw_line="$1"

    # 提取字段
    local username src_ip src_port sshd_pid
    username="$(echo "$raw_line" | grep -oE 'Invalid user ([^ ]+)' | awk '{print $3}')"
    src_ip="$(echo "$raw_line" | grep -oE 'from ([0-9a-f.:]+)' | awk '{print $2}')"
    src_port="$(echo "$raw_line" | grep -oE 'port ([0-9]+)' | awk '{print $2}')"
    sshd_pid="$(echo "$raw_line" | grep -oE 'sshd-session\[([0-9]+)\]' | grep -oE '[0-9]+')"

    log "ALERT" "========================================"
    log "ALERT" "检测到非法 SSH 登录尝试！"
    log "ALERT" "  用户名  : ${username:-<empty>}"
    log "ALERT" "  来源 IP : ${src_ip:-unknown}"
    log "ALERT" "  来源端口: ${src_port:-unknown}"
    log "ALERT" "  sshd PID: ${sshd_pid:-unknown}"
    log "ALERT" "  原始日志: $raw_line"

    # 如果来源是本地回环，尝试反查进程
    case "$src_ip" in
        127.0.0.1|::1|"[::1]")
            log "WARN" "  ⚠️  来源为本机回环地址！可能有本地程序在暴力破解 SSH！"
            if [ -n "$src_port" ]; then
                log "INFO" "  正在通过端口 $src_port 追查发起进程..."
                local proc_info
                proc_info="$(find_process_by_port "$src_port")"
                log "ALERT" "  发起进程: $proc_info"
            fi
            ;;
        *)
            log "WARN" "  来源为外部 IP：$src_ip — 可能是外网扫描攻击"
            ;;
    esac

    # 额外快照：当前所有到 22 端口的连接
    log "INFO" "  [快照] 当前 SSH 连接列表:"
    if command -v ss >/dev/null 2>&1; then
        ss -tnp 'dport = :22 or sport = :22' 2>/dev/null | while IFS= read -r l; do
            log "INFO" "    $l"
        done
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tnp 2>/dev/null | grep ':22 ' | while IFS= read -r l; do
            log "INFO" "    $l"
        done
    fi

    log "ALERT" "========================================"
}

# -----------------------------------------------------------------------------
# 主循环：用 logread -f 实时跟踪系统日志
# OpenWrt 日志存于内存环形缓冲区，通过 logread 读取
# -----------------------------------------------------------------------------
main() {
    log "INFO" "ssh-watch 启动，日志文件: $LOG_FILE"
    log "INFO" "PID: $$"
    echo $$ > "$PID_FILE"

    log "INFO" "开始监听 logread -f，等待 sshd-session Invalid user 事件..."
    log "INFO" "按 Ctrl+C 停止。"

    # logread -f 持续输出新日志（类似 tail -f）
    logread -f 2>/dev/null | while IFS= read -r line; do
        # 过滤 sshd-session 中的 Invalid user（排除 Connection closed 行，只处理第一条）
        case "$line" in
            *"sshd-session"*"Invalid user"*"from"*"port"*)
                handle_invalid_user "$line"
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# 启动
# -----------------------------------------------------------------------------
main
