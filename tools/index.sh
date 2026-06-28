#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 将命令添加到 /etc/rc.local，确保不重复
add_to_rc_local() {
    local cmd="$1"
    
    if [ ! -f /etc/rc.local ]; then
        echo -e "#!/bin/sh\n\n$cmd\n\nexit 0" > /etc/rc.local
        chmod +x /etc/rc.local
        echo "[INFO] File missing--/etc/rc.local 不存在，已新建并添加开机自启命令。"
        return 0
    fi

    # 检查是否已包含命令
    if grep -qF "$cmd" /etc/rc.local; then
        echo "[INFO] Boot command exists--开机自启项已存在，跳过添加: $cmd"
        return 0
    fi

    local temp_file
    temp_file=$(mktemp)
    local added=0
    
    # 逐行读取，在第一个 exit 0 之前插入命令
    while IFS= read -r line || [ -n "$line" ]; do
        clean_line=$(echo "$line" | tr -d ' \t\r')
        if [ "$added" -eq 0 ] && [ "$clean_line" = "exit0" ]; then
            echo "$cmd" >> "$temp_file"
            added=1
        fi
        echo "$line" >> "$temp_file"
    done < /etc/rc.local

    # 如果没有找到 exit 0，追加到文件末尾
    if [ "$added" -eq 0 ]; then
        echo "$cmd" >> "$temp_file"
    fi

    cat "$temp_file" > /etc/rc.local
    rm -f "$temp_file"
    chmod +x /etc/rc.local
    echo "[INFO] Will start on boot--已成功将开机自启命令写入 /etc/rc.local: $cmd"
}

# 询问用户是否添加到开机自启
echo -n "Start on boot?--是否将脚本添加到开机自启 (/etc/rc.local)? [y/N]: "
read -r choice

case "$choice" in
    [yY][eE][sS]|[yY])
        echo "[INFO] Config start on boot--正在配置开机自启..."
        add_to_rc_local "(sleep 60 && cd $SCRIPT_DIR/og && sh ./index.sh) &"
        add_to_rc_local "(sleep 60 && cd $SCRIPT_DIR/pw && sh ./index.sh) &"
        ;;
    *)
        echo "[INFO] Skip start on boot--跳过配置开机自启，直接在当前终端启动服务..."
        (cd "$SCRIPT_DIR/og" && sh ./index.sh)
        (cd "$SCRIPT_DIR/pw" && sh ./index.sh)
        ;;
esac
