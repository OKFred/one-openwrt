### @description: 用于 openwrt 固件的自动下载、解压、扩容、打包

### @author: Fred

### @datetime: 2024-01-13

## 运行方法

`cd $HOME/one-openwrt && git reset --hard HEAD && git pull && chmod +x index.sh && ./index.sh`

## 在 virtualBox 中运行

需要转换虚拟磁盘
`cd "C:\Program Files\Oracle\VirtualBox"`
`.\VBoxManage convertfromraw /path/to/your/op.img /path/to/your/op.vmdk --format VMDK`

## 说明

本想使用 Github Actions 定期自动运行，但是免费版本容量只有 500MB。  
有需要的可以自托管 runner 运行，或者直接拉取到本地运行。

1. 自动下载固件
2. 自动解压固件
3. 扩容
4. 重新打包成 img.gz 供下载

## 额外功能

### 流量审计与限制

- 基于 OG 和 PW 的日志分析。（og暂时只兼容了arrch64，有需要请自行替换）

#### 启动方式

进入 `tools` 目录并运行引导脚本：

```bash
cd tools
chmod +x index.sh
./index.sh
```

**运行说明**：

- 运行前，需确保 `tools/og/` 和 `tools/pw/` 目录下已分别配置了相应的 `.env` 配置文件。脚本在检测不到 `.env` 时会提示 `.env file required` 并退出。
- 启动时会询问是否将脚本添加至 `/etc/rc.local`（配置开机自启）：
  - 确认添加：将自动把启动命令追加到 `/etc/rc.local` 的 `exit 0` 之前，并具有防重复写入机制。
  - 选择跳过：则直接在当前终端启动这两个后台服务（`og/index.sh` 与 `pw/index.sh` 均会通过 `&` 在后台并发运行）。

#### 配套 API 服务

日志审计与限制功能需要配套的后端 API 服务接收并处理上传的数据。
您需要在 `tools/og/.env` 和 `tools/pw/.env` 中正确配置相关的 API 接口环境。主要配置项包括：

- `LOG_URL`: 后端 API 的日志接收接口地址（例如 `http://<your-server-ip>/api/logs`）。
- `AUTH_TOKEN`: Bearer 认证 Token，用于接口的安全鉴权。
- `DEVICE_ID`: 当前设备的唯一 ID。
- `TRAFFIC_METHOD` (或 `DEVICE_LOCATION`): 用于审计日志分类的流量模式/地理位置标识。
- `LOG_FILE` (仅 `pw` 服务需要): 指定待监控审计的日志文件绝对路径。
