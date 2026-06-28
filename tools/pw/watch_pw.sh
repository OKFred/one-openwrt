#!/bin/sh

PID_FILE="uploader.pid"

# Load public helper and load .env file
. "$(dirname "$0")/../../utils/index.sh"
load_env "$(dirname "$0")/.env"


# Check if required environment variables are set
err=0

if [ -z "$LOG_FILE" ]; then
    echo "[ERROR] LOG_FILE is not set." >&2
    err=1
fi

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

upload_batch() {
    lines="$1"
    [ -z "$lines" ] && return

    # Generate JSON payload using jq
    payload=$(jq -n \
        --arg device_id_raw "$DEVICE_ID" \
        --arg traffic_method "$TRAFFIC_METHOD" \
        --arg lines_str "$lines" \
        '{
            device_id: ($device_id_raw | tonumber? // $device_id_raw),
            traffic_method: $traffic_method,
            category: "pw",
            logs: ($lines_str | split("\n") | map(select(. != "")))
        }')

    if [ -z "$payload" ]; then
        if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then
            echo "[DEBUG] Failed to generate payload (jq error) for batch."
        fi
        return
    fi

    if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] Payload:"
        echo "$payload" | jq . || echo "$payload"
    fi

    # Upload asynchronously
    curl -s -X POST "$LOG_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d "$payload" >/dev/null 2>&1 &
}

start_app() {
    echo "[INFO] starting pw log uploader..."
    if [ ! -f "$LOG_FILE" ]; then
        echo "[WARN] $LOG_FILE does not exist. Waiting for it to be created..."
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE"
    fi

    # Follow the log file and upload entries in batches
    tail -F "$LOG_FILE" | (
        buffer=""
        count=0
        last_flush=$(date +%s)
        BATCH_SIZE=20
        BATCH_TIMEOUT=5

        while true; do
            start_time=$(date +%s)
            read -r -t 2 line
            status=$?
            end_time=$(date +%s)
            elapsed_read=$((end_time - start_time))

            if [ $status -eq 0 ]; then
                [ -z "$line" ] && continue
                buffer="${buffer}${line}
"
                count=$((count + 1))
            else
                # Non-zero status: check if it's EOF (instant return) or Timeout (took >= 2s)
                if [ "$elapsed_read" -lt 2 ]; then
                    # EOF / Error (pipe closed)
                    if [ "$count" -gt 0 ]; then
                        upload_batch "$buffer"
                    fi
                    break
                else
                    # Timeout: keep looping
                    :
                fi
            fi

            now=$(date +%s)
            elapsed=$((now - last_flush))
            if [ "$count" -gt 0 ] && { [ "$count" -ge "$BATCH_SIZE" ] || [ "$elapsed" -ge "$BATCH_TIMEOUT" ]; }; then
                upload_batch "$buffer"
                buffer=""
                count=0
                last_flush=$now
            fi
        done
    )
}

stop_app() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "[INFO] stopping pw log uploader pid=$PID"
        kill "$PID" 2>/dev/null
        rm -f "$PID_FILE"
    fi
    # Stop possible orphaned tail processes
    pgrep -f "tail -F $LOG_FILE" | xargs kill 2>/dev/null
}

# CLI entrypoint
case "$1" in
    start)
        stop_app
        start_app >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        ;;
    stop)
        stop_app
        ;;
    restart)
        stop_app
        sleep 1
        start_app >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        ;;
    run)
        start_app
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|run}"
        ;;
esac
