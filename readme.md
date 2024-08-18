### @description: 用于 openwrt 固件的自动下载、解压、扩容、打包

### @author: Fred Zhang Qi

### @datetime: 2024-01-13

## 运行方法

`cd $HOME/one-openwrt && git reset --hard HEAD && git pull && chmod +x index.sh && ./index.sh`

## 说明

本想使用 Github Actions 定期自动运行，但是免费版本容量只有 500MB。  
有需要的可以自托管 runner 运行，或者直接拉取到本地运行。

1. 自动下载固件
2. 自动解压固件
3. 扩容
4. 重新打包成 img.gz 供下载
