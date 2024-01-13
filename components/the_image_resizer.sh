#!/bin/bash
#@description: Openwrt固件扩容
#@author: Fred Zhang Qi
#@datetime: 2024-01-13

#文件依赖
#⚠️import--需要引入包含函数的文件
#none

the_image_resizer() {
  local img_file=$1
  echo "先将原版的"$img_file"解压"
  gzip -d $img_file
  echo "然后扩容至约1.9G"
  dd if=/dev/zero bs=4096k count=512 >>$img_file
  echo "观察文件大小是否变化"
  ls -lh
  echo "挂载到系统"
  losetup -f $img_file
  losetup
  lsblk
  return 0;
  echo "使用分区助手，重建需要扩容的分区"
  fdisk /dev/loop0
  echo "更新分区信息"
  partx -u /dev/loop0
  lsblk
  echo "检查错误"
  e2fsck -f /dev/loop0p2
  echo "完成扩容"
  resize2fs /dev/loop0p2

  ##
  echo "自行检查是否为UEFI启动镜像👇"
}
