#!/bin/bash
#@description: Openwrt固件扩容
#@author: Fred
#@datetime: 2024-01-13

#文件依赖
#⚠️import--需要引入包含函数的文件
#none

the_image_resizer() {
  local img_file=$1
  echo "先将原版的"$img_file"解压"
  gzip -d $img_file
  echo "然后扩容至约2048M"
  img_file=${img_file%.*} #去掉后缀
  dd if=/dev/zero bs=4096k count=512 >>$img_file
  echo "观察文件大小是否变化"
  ls -lh $img_file

  echo "挂载到系统"
  losetup -f $img_file
  losetup
  echo "使用分区助手，重建需要扩容的分区"
  local img_mount_path=$(losetup -a | grep op.img | awk -F: '{print $1}')
  fdisk -l $img_mount_path

  # 记录第二分区的起始扇区
  local start_sector=$(fdisk -l /dev/loop0 | grep p2 | awk '{print $2}')

  # 打印起始扇区
  echo "第二扇区起始值"$start_sector

  # fdisk $img_mount_path
  echo -e "p\nd\n2\nn\n2\n$start_sector\n\nw" | fdisk /dev/loop0

  echo "更新分区信息"
  partx -u $img_mount_path
  lsblk
  echo "检查错误"
  echo -e "y\n" | e2fsck -f $img_mount_path"p2"
  echo "完成扩容"
  resize2fs $img_mount_path"p2"
  lsblk

  # echo "是否为UEFI启动镜像？ [y/n]"
  # read is_uefi
  echo "默认为UEFI启动镜像，调整引导信息"
  local is_uefi="y"
  if [ $is_uefi == "y" ]; then
    echo "UEFI启动的还需要编辑grub，因为PARTUUID分区后改变了"
    echo "建一个空目录"
    mkdir esp
    mount $img_mount_path"p1" esp
    ls -la esp
    echo "观察PARTUUID，两个都复制出来，和GRUB文件里的比较"
    local temp_grub_file=./esp/boot/grub/grub.cfg
    blkid
    local new_partuuid=$(blkid | grep rootfs | awk '{print $6}' | awk -F\" '{print $2}')
    echo "新的PARTUUID是："$new_partuuid
    echo "GRUB文件里错误的ID数字是紧接着第一分区的，需要调整"
    cat $temp_grub_file
    echo "______________________________"
    echo "⚠️旧的引导文件内容👆"
    sed "s/PARTUUID=[a-z0-9-]*/PARTUUID=$new_partuuid/g" $temp_grub_file >grub.cfg.new
    mv grub.cfg.new $temp_grub_file

    cat $temp_grub_file
    echo "______________________________"
    echo "✅新的引导文件内容👆"
    umount $img_mount_path"p1"
    rm -rf esp
  fi

  partx -d $img_mount_path
  losetup -d $img_mount_path
  lsblk
  gzip op.img
  ls -lh
  echo "完成。请手动获取op.img.gz"
}
