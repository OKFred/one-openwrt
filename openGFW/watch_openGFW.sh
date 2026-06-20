#!/bin/sh

BIN="./OpenGFW"
CFG="./config.yaml"
RULE="./rule.yaml"
PID_FILE="openGFW.pid"
UPLOAD_PID_FILE="upload.pid"
LOG_FILE="openGFW.log"

# Upload settings. Override them with environment variables if needed.
LOG_URL="${LOG_URL:-http://127.0.0.1:8787/firewall/logs}"
DEVICE_ID="${DEVICE_ID:-1}"
TRAFFIC_METHOD="${TRAFFIC_METHOD:-${DEVICE_LOCATION:-direct}}"
AUTH_TOKEN="${AUTH_TOKEN:-abc123}"
DEBUG="${DEBUG:-0}"

generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        printf 'log-%s-%s-%s' "$(date +%s)" "$$" "$(awk 'BEGIN { srand(); printf "%06d", rand() * 1000000 }')"
    fi
}

parse_and_upload() {
    line="$1"
    [ -z "$line" ] && return

    # OpenGFW log fields are separated by tabs.
    log_time=$(printf '%s\n' "$line" | cut -f1)

    # Ignore non-log lines.
    case "$log_time" in
        [0-9]*) ;;
        *) return ;;
    esac

    payload=$(jq -n \
        --arg device_id_raw "$DEVICE_ID" \
        --arg traffic_method "$TRAFFIC_METHOD" \
        --arg line "$line" \
        '{
            device_id: ($device_id_raw | tonumber? // $device_id_raw),
            traffic_method: $traffic_method,
            category: "openGFW",
            logs: [$line]
        }')

    if [ -z "$payload" ]; then
        if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then
            echo "[DEBUG] Failed to generate payload (jq error) for line: $line"
        fi
        return
    fi

    if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] Payload:"
        echo "$payload" | jq . || echo "$payload"
    fi

    # Upload asynchronously.
    curl -s -X POST "$LOG_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d "$payload" >/dev/null 2>&1 &
}

start_app() {
    echo "[INFO] starting OpenGFW..."
    # Start OpenGFW and redirect logs to a file.
    $BIN -c "$CFG" "$RULE" > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    # Follow the log file and upload parsed entries.
    tail -f "$LOG_FILE" | while read -r line; do
        parse_and_upload "$line"
    done &
    echo $! > "$UPLOAD_PID_FILE"
}

stop_app() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "[INFO] stopping OpenGFW pid=$PID"
        kill "$PID" 2>/dev/null
        rm -f "$PID_FILE"
    fi
    if [ -f "$UPLOAD_PID_FILE" ]; then
        UPID=$(cat "$UPLOAD_PID_FILE")
        echo "[INFO] stopping log uploader pid=$UPID"
        kill "$UPID" 2>/dev/null
        rm -f "$UPLOAD_PID_FILE"
    fi
    # Stop possible orphaned tail processes.
    pgrep -f "tail -f $LOG_FILE" | xargs kill 2>/dev/null
}

restart_app() {
    stop_app
    sleep 1
    start_app
}

watch_rule() {
    echo "[INFO] watching $RULE ..."

    inotifywait -m -e modify,create,delete,move "$RULE" |
    while read -r _ event _; do
        echo "[INFO] rule changed: $event"
        restart_app
    done
}

# CLI entrypoint.
case "$1" in
    start)
        start_app
        watch_rule
        ;;
    stop)
        stop_app
        ;;
    restart)
        restart_app
        ;;
    run)
        start_app
        watch_rule
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|run}"
        ;;
esac
