#!/bin/bash
#@description: 菜单化显示工具箱列表
#@author: Fred Zhang Qi
#@datetime: 2024-02-01

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
    echo "09. about--关于"
    echo "00. exit--退出"
    echo
    echo -n "your choice--请输入你的选择："
    read the_user_choice
    case "$the_user_choice" in
    01 | 1) the_nginx_installer ;;
    02 | 2) the_nginx_forwarder ;;
    03 | 3) the_nginx_restarter ;;
    04 | 4) the_nginx_port_cleaner ;;
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
