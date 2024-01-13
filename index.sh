#!/bin/bash
#@description: 用于下载Openwrt固件并自动扩容
#@author: Fred Zhang Qi
#@datetime: 2024-01-13

#文件依赖
#⚠️import--需要引入包含函数的文件
source ./components/the_image_downloader.sh
source ./components/the_image_resizer.sh

main() {
  echo -e "\033[32m"
  date
  echo "执行需要管理员权限。请注意"
  echo -e "script running....开始运行\033[0m"
  local image_url="https://downloads.openwrt.org/releases/23.05.2/targets/x86/64/openwrt-23.05.2-x86-64-generic-ext4-combined-efi.img.gz"
  local save_as="op.img.gz"
  the_image_downloader $image_url $save_as
  the_image_resizer "op.img"

  echo "done--大功告成"
  echo -e "\033[0m"
}

main
