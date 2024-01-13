#!/bin/bash
#@description: 下载Openwrt固件
#@author: Fred Zhang Qi
#@datetime: 2024-01-13

#文件依赖
#⚠️import--需要引入包含函数的文件
#none

the_image_downloader() {
  local image_url=$1
  local save_as=$2
  if [ -z "$save_as" ]; then
    echo "文件名默认为op.img.gz"
    save_as="op.img.gz"
  fi
  echo "下载固件："
  wget $image_url -O $save_as
  echo "文件信息："
  ls -lh $save_as
}
