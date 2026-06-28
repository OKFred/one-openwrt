#!/bin/bash
#@description: 菜单化显示工具箱列表
#@author: Fred Zhang Qi
#@datetime: 2024-02-01

# 自动为当前目录及子目录下的所有 .sh 脚本加上执行权限
find "$(dirname "$0")" -name "*.sh" -exec chmod +x {} \; 2>/dev/null

#文件依赖
#⚠️import--需要引入包含函数的文件
source ./components/the_nginx_installer.sh
source ./components/the_nginx_forwarder.sh
source ./components/the_nginx_restarter.sh
source ./components/the_nginx_port_cleaner.sh

menu_title() {
  #clear
  date
  echo "执行需要管理员权限。请注意"
  echo "*********************"
  echo "*****   工具箱Tool   *****"
}

menu_back() {
  echo
  echo -n "press any key--按任意键返回."
  read
}

main() {
  while (true); do
    menu_title
    echo "01. nginx installer--安装配置nginx"
    echo "02. nginx forwarder--配置nginx转发"
    echo "03. nginx restarter--重启nginx"
    echo "04. nginx port cleaner--清理nginx端口"
    echo "05. traffic audit--启动流量审计与限制"
    echo "06. traffic audit stopper--停止流量审计与限制"
    echo "07. ssh watch--启动 SSH 入侵监控"
    echo "08. ssh watch stopper--停止 SSH 入侵监控"
    echo "09. about--关于"
    echo "00. exit--退出"
    echo
    echo -n "your choice--请输入你的选择："
    read the_user_choice
    case "$the_user_choice" in
    "") exit 0 ;;
    01 | 1) the_nginx_installer ;;
    02 | 2) the_nginx_forwarder ;;
    03 | 3) the_nginx_restarter ;;
    04 | 4) the_nginx_port_cleaner ;;
    05 | 5) sh ./tools/index.sh ;;
    06 | 6) sh ./tools/stop.sh ;;
    07 | 7) sh ./tools/ssh-watch/index.sh &
           echo "[INFO] ssh-watch 已在后台启动，日志: ./tools/ssh-watch/ssh-watch.log" && menu_back ;;
    08 | 8) sh ./tools/ssh-watch/stop.sh && menu_back ;;
    09 | 9) nano readme.md ;;
    00 | 0) exit 1 ;;
    u) echo "???" ;;
    *) echo "error input--输入有误，请重新输入！" && menu_back ;;
    esac
    echo
  done
}

clear
main
