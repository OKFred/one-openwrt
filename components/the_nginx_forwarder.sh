#!/bin/bash
#@description: 快速配置nginx端口转发
#@author: Fred Zhang Qi
#@datetime: 2024-02-01

#文件依赖
#⚠️import--需要引入包含函数的文件
#none

the_nginx_env="/etc/nginx/.env"
the_nginx_conf_dir="/etc/nginx/conf.d"

the_nginx_forwarder() {
  the_environment_checker
  if [ $? -ne 0 ]; then
    exit 1
  fi
  echo "开始配置新的conf"
  echo -e "\033[33m"
  echo "🚩port--请输入端口"
  read port
  echo "🚩upstream--请输入后端服务地址"
  read upstream
  echo -e "\033[0m"
  the_port_checker $port
  if [ $? -ne 0 ]; then
    exit 1
  fi
  #从env中读取server_name，wwwroot
  #例 server_name=www.example.com
  #   wwwroot=/var/www/html
  source $the_nginx_env
  echo "当前变量："
  echo "server_name=$server_name"
  echo "wwwroot=$wwwroot"
  echo "server {
	# 域名	
	server_name $server_name;
	
	# 端口
	listen $port ssl http2;
	
	#证书文件
	ssl_certificate /etc/ssl/certs/$server_name.crt; 

	#私钥文件
	ssl_certificate_key /etc/ssl/keys/$server_name.key; 
	ssl_session_timeout 5m;

	#加密协议
	ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;

	#加密套件
	ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE; 
	ssl_prefer_server_ciphers on;

	# 网站目录
	root $wwwroot;

	# 网站主页
	index index.html index.htm index.php;

    #禁止访问DOTFILES
    location ~ /\. {
        deny all;
    }

	 # minio对象存储
	 location / {
			proxy_set_header X-Real-IP \$remote_addr;
			proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
			proxy_set_header Host \$http_host;
			proxy_set_header X-NginX-Proxy true;
			proxy_set_header  X-Forwarded-Proto \$scheme;
			proxy_pass $upstream;
			proxy_redirect off;

			#WebSocket设置
			 proxy_read_timeout 300s;
			 proxy_send_timeout 300s;

			 proxy_http_version 1.1;
			 proxy_set_header Upgrade \$http_upgrade;
			 proxy_set_header Connection \$connection_upgrade;
	 }

	#  隐藏nginx版本号
	server_tokens off;
}" >$the_nginx_conf_dir/$port.conf
}

the_environment_checker() {
  #检查nginx命令以及配置目录是否存在
  if [ -z "$(which nginx)" ]; then
    echo "nginx命令不存在"
    exit 1
  fi
  if [ ! -d $the_nginx_conf_dir ]; then
    echo "nginx配置目录不存在"
    exit 1
  fi
}

the_port_checker() {
  this_port=$1
  if [ -z "$(netstat -tunlp | grep $this_port)" ]; then
    # echo "端口：$this_port 未被占用"
  else
    #echo "端口：$this_port 已被占用"
    exit 1
  fi
  #遍历conf.d目录下的配置文件，了解端口占用情况
  for file in $(ls $the_nginx_conf_dir); do
    if [ "${file##*.}" != "conf" ]; then
      continue
    fi #如果文件不是以.conf结尾，则跳过
    nginx_port=$(cat $the_nginx_conf_dir/$file | grep "listen" | awk '{print $2}' | awk -F ";" '{print $1}')
    if [ $this_port -eq $nginx_port ]; then
      #echo "端口：$this_port 已被占用"
      exit 1
    fi
  done
}
