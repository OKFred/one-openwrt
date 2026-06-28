#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[INFO] Stopper--正在停止流量审计与限制服务..."

# 1. 尝试使用官方的 stop 命令进行优雅停止
if [ -d "$SCRIPT_DIR/pw" ]; then
    echo "[INFO] 正在调用 watch_pw.sh stop..."
    (cd "$SCRIPT_DIR/pw" && sh ./watch_pw.sh stop)
fi

if [ -d "$SCRIPT_DIR/og" ]; then
    echo "[INFO] 正在调用 watch_og.sh stop..."
    (cd "$SCRIPT_DIR/og" && sh ./watch_og.sh stop)
fi

# 等待 1 秒让进程释放资源
sleep 1

# 2. 强力清理残留进程的辅助函数
kill_by_pattern() {
    local pattern="$1"
    local desc="$2"
    # 获取进程 PID，排除 grep 进程和当前 stop.sh 进程自身
    local pids
    pids=$(ps -w | grep "$pattern" | grep -v "grep" | grep -v "stop.sh" | awk '{print $1}')
    if [ -n "$pids" ]; then
        echo "[WARN] 发现残留的 $desc 进程 (PID: $pids)，正在强制清理..."
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null
        done
    fi
}

# 3. 开始执行残留进程清理
# 清理监控与守护脚本本身
kill_by_pattern "watch_og\.sh" "watch_og 守护脚本"
kill_by_pattern "watch_pw\.sh" "watch_pw 守护脚本"
kill_by_pattern "inotifywait" "inotifywait 规则监控"
kill_by_pattern "\./og" "OpenGFW 二进制程序"

# 读取 pw 配置，清理残留的 tail 日志跟踪进程
if [ -f "$SCRIPT_DIR/pw/.env" ]; then
    # 读取环境变量中的 LOG_FILE 路径
    LOG_FILE=$(grep -E "^LOG_FILE=" "$SCRIPT_DIR/pw/.env" | cut -d'=' -f2- | tr -d '"'\''')
    if [ -n "$LOG_FILE" ]; then
        kill_by_pattern "tail -F $LOG_FILE" "tail 日志追踪"
    fi
fi

# 4. 最终状态检查
check_remnants() {
    # 检查是否还有与服务相关的关键进程名在运行
    local check_patterns="watch_og\.sh|watch_pw\.sh|inotifywait|\./og"
    if [ -n "$LOG_FILE" ]; then
        check_patterns="$check_patterns|tail -F $LOG_FILE"
    fi

    local remnants
    remnants=$(ps -w | grep -E "$check_patterns" | grep -v "grep" | grep -v "stop.sh")

    if [ -n "$remnants" ]; then
        echo "[WARNING] 注意：仍有疑似残留的进程未被成功清理："
        echo "$remnants"
    else
        echo "[INFO] 进程检查完毕，所有相关服务已完全停止，无残留进程。"
    fi
}

echo "----------------------------------------"
check_remnants
echo "----------------------------------------"
echo "[INFO] Tip--提示：如果您之前配置了开机自启，本次操作仅停止当前运行的进程，下次开机仍会自动启动。"
