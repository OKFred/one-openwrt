#!/bin/sh

BIN="./OpenGFW"
CFG="./config.yaml"
RULE="./rule.yaml"
PID_FILE="openGFW.pid"
UPLOAD_PID_FILE="upload.pid"
FIFO_FILE="openGFW.fifo"

# Load public helper and load .env file
. "$(dirname "$0")/../utils/index.sh"
load_env "$(dirname "$0")/.env"


# Check if required environment variables are set. If not, error and exit.
err=0

if [ -z "$LOG_URL" ]; then
    echo "[ERROR] LOG_URL is not set." >&2
    err=1
fi

if [ -z "$DEVICE_ID" ]; then
    echo "[ERROR] DEVICE_ID is not set." >&2
    err=1
fi

if [ -z "$TRAFFIC_METHOD" ]; then
    if [ -n "$DEVICE_LOCATION" ]; then
        TRAFFIC_METHOD="$DEVICE_LOCATION"
    else
        echo "[ERROR] TRAFFIC_METHOD (or DEVICE_LOCATION) is not set." >&2
        err=1
    fi
fi

if [ -z "$AUTH_TOKEN" ]; then
    echo "[ERROR] AUTH_TOKEN is not set." >&2
    err=1
fi

if [ "$err" -ne 0 ]; then
    echo "[FATAL] Missing required configuration. Exiting..." >&2
    exit 1
fi

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
    
    # Ensure FIFO exists
    if [ -e "$FIFO_FILE" ] && [ ! -p "$FIFO_FILE" ]; then
        rm -f "$FIFO_FILE"
    fi
    [ -p "$FIFO_FILE" ] || mkfifo "$FIFO_FILE"

    # Start OpenGFW and redirect logs to the FIFO.
    $BIN -c "$CFG" "$RULE" > "$FIFO_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    # Read from the FIFO and upload parsed entries.
    while read -r line; do
        parse_and_upload "$line"
    done < "$FIFO_FILE" &
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
    # Clean up the FIFO file
    rm -f "$FIFO_FILE"
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
