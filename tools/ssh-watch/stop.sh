#!/bin/sh
# ssh-watch/stop.sh — 停止监控脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="${SCRIPT_DIR}/ssh-watch.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "[WARN] PID 文件不存在: $PID_FILE，服务可能未运行。"
    exit 0
fi

PID="$(cat "$PID_FILE")"

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    rm -f "$PID_FILE"
    echo "[INFO] ssh-watch (PID=$PID) 已停止。"
else
    echo "[WARN] 进程 PID=$PID 不存在，清理 PID 文件。"
    rm -f "$PID_FILE"
fi
