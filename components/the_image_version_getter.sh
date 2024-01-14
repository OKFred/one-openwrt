#!/bin/bash
#@description: 获取最新版本号
#@author: Fred Zhang Qi
#@datetime: 2024-01-13

#文件依赖
#⚠️import--需要引入包含函数的文件
#none

the_image_version_getter() {
  local config_js_url="https://firmware-selector.openwrt.org/config.js"
  #获取最新版本号
  wget $config_js_url
  local latest_version=$(cat config.js | grep "default_version" | awk '{print $2}' | awk -F\" '{print $2}')
  echo $latest_version
}
