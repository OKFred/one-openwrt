#!/bin/bash
#@description: 用于下载Openwrt固件并自动扩容
#@author: Fred Zhang Qi
#@datetime: 2024-01-13

#文件依赖
#⚠️import--需要引入包含函数的文件
source ./components/the_image_version_getter.sh
source ./components/the_image_downloader.sh
source ./components/the_image_resizer.sh

main() {
  echo -e "\033[32m"
  date
  echo "执行需要管理员权限。请注意"
  echo -e "script running....开始运行\033[0m"
  local save_as="op.img.gz"
  if [ -f $save_as ]; then
    ls -la $save_as
    echo "文件已存在，是否重新下载？"
    read -p "请输入：y/n：" need_download
    if [ $need_download == 'y' ]; then
      download $save_as
    else
      echo "使用已存在的$save_as"
    fi
  else
    download $save_as
  fi
  the_image_resizer $save_as

  echo "done--大功告成"
  echo -e "\033[0m"
}

download() {
  local save_as=$1
  echo "开始下载"
  local latest_version=$(the_image_version_getter)
  echo "最新版本是：$latest_version"
  local image_url="https://downloads.openwrt.org/releases/$latest_version/targets/x86/64/openwrt-$latest_version-x86-64-generic-ext4-combined-efi.img.gz"
  the_image_downloader $image_url $save_as
}

main
