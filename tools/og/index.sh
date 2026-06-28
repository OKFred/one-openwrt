if [ ! -f .env ]; then
  echo ".env file required--未检测到 .env 文件，请先配置环境。"
  exit 0
fi

chmod 755 *.sh
chmod 755 og
./watch_og.sh run &