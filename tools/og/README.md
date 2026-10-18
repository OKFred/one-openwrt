# OpenGFW TCP 状态回收修复

`og` 是基于 OpenGFW `v0.3.2` 的 Linux ARM64/v8.0 二进制，禁用 CGO。上游源码版本与补丁、二进制及源码归档的 SHA256 记录在 `build-info.json`。适用于现有 ARM64 部署，其他架构需要另行构建。

## 改动和限制

- 收包设置时间戳，每个 worker 每 5 秒回收空闲超过 120 秒的 TCP 分析状态。
- 清除连接复用池对已完成 stream 的引用，正确释放关闭连接的全部排队页。
- 清理回放时跳过已判决的流，兼容空 context；退出时取消 Feed 并等待 worker 清理。

这是对历史 TCP 状态持续保留问题的缓解，没有设置 RSS 或 TCP 连接数硬上限。**未判决的连接空闲超过 120 秒后会丢失原分析历史**，后续包重新建立分析状态，无 SYN 时可能无法延续原有分析。高流量下的内存峰值及连接池高水位仍需观察。依赖补丁针对当前每个 worker 独立 assembler/pool 的用法。

离线测试覆盖时间戳、1000 条流回收与复用、新鲜流保留、最终判决不重复、排队页释放和退出清理；完整 `gopacket/reassembly` 测试通过。原版在对应残留引用与页释放回归测试中失败。尚未完成实机 NFQUEUE、长期流量与内存趋势验收；race 检测未完成。

## 构建与验证

需要 Bash、**Go 1.26.4**、Git 和常用 Unix 工具。构建脚本固定 module proxy/checksum、目标架构和构建参数；在临时目录应用补丁，不修改 Go module 缓存。可在 Linux 或 Windows Git Bash 构建：

```bash
bash tools/og/build.sh
```

输出为 `tools/og/build/og-linux-arm64`，该目录已忽略。Linux Go 主机可同时运行回归测试：

```bash
bash tools/og/build.sh --test
```

用 `--output PATH` 指定构建文件，或用 `--prepare NEW_DIRECTORY` 导出两个已打补丁的源码目录。构建脚本不会启动服务。运行中的设备应先停止原服务并备份原二进制，再进行受控替换和验收，避免直接覆盖正在执行的文件。

核对仓库中的二进制：

```bash
(cd tools/og && sha256sum -c og.sha256)
```

## 完整源码与许可证

`source/opengfw-ttl-source.zip` 提供此次构建的完整 OpenGFW 和 gopacket 修改后源码，含 `go.mod`、`go.sum`、回归测试和原许可证。解压后两个目录必须保持相邻；其余依赖按 `go.sum` 获取。在 `opengfw` 目录执行：

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 GOARM64=v8.0 \
  go build -mod=readonly -trimpath -buildvcs=false -o ../og-linux-arm64 .
```

也可用 `patches/` 中的补丁，从以下固定 module 版本重建：

- `github.com/apernet/OpenGFW@v0.3.2`，提交 `393c29bd2dec4e3e3b1186f35e21b73fb59470c2`。
- `github.com/google/gopacket@v1.1.20-0.20220810144506-32ee38206866`。

OpenGFW 使用 MPL-2.0；gopacket 和内置 QUIC 分析代码包含各自的 BSD 通知。`THIRD_PARTY_LICENSES.txt` 随二进制保留这些许可证及其他静态链接依赖、Go runtime 的版权和许可证通知，各通知适用于其对应组件。
