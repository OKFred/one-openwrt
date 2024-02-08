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
  local this_port=$port
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
  echo "nginx命令以及配置目录存在"
}
