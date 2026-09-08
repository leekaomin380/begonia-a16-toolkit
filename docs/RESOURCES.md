# 资源清单

本项目实际用到的全部外部资源，含来源、校验和与获取方式，便于重建环境或换机复用。

> 所有二进制均**不随仓库分发**，此处只记录出处。

## 一、系统与恢复

| 资源 | 来源 | 校验和 |
|---|---|---|
| LineageOS 23.2 UNOFFICIAL (begonia, 2026-03-28) | `sourceforge.net/projects/danascape/files/begonia/lineage-23.2/20260328/` | md5 `2c5009e77a8ccebb7d1e1ddbbe161f84`，1,392,467,047 B |
| TWRP 3.4.0 (begonia，官方最新) | `dl.twrp.me/begonia/twrp-3.4.0-0-begonia.img` | sha256 `efebe70aea5a31803015dc06e635313c166d8a77e4132a8eb2fac244b5e4447f` |

TWRP 下载须带 Referer，否则拿到的是确认页 HTML：

```bash
curl -L -H "Referer: https://dl.twrp.me/begonia/twrp-3.4.0-0-begonia.img.html" \
     -o twrp.img "https://dl.twrp.me/begonia/twrp-3.4.0-0-begonia.img"
```

> 实测该机型 `fastboot boot` 被 bootloader 拒绝，TWRP 最终未被使用——刷机走的是
> fastboot 直刷镜像。详见 [flashing-without-buttons.md](flashing-without-buttons.md)。

## 二、缺失的私有库（本项目的核心）

| 资源 | 来源 | 校验和 |
|---|---|---|
| `libmtk_vt_wrapper.so` (arm64) | `ZyCromerZ/redmi_begonia_dump`，分支 `begonia-user-11-RP1A.200720.011-V12.5.3.0.RGGIDXM-release-keys`，路径 `system/system/lib64/libmtk_vt_wrapper.so` | sha256 `1f2a039c094d3cfc0a01c633b061570039543389ca8e5ad60f3d773a820cc2fb` |
| 同上，经本仓库工具修补后 | 由 `tools/elf-redirect-needed.py` 生成 | sha256 `af87ae4c6379876e02bd3c1e9294273b7df001d91dc6d630e3708ec15357a2ad` |

选择该转储的理由：分支的区域代码 `RGGIDXM` 与目标设备原厂固件一致。

```bash
./tools/extract-blob.sh ZyCromerZ/redmi_begonia_dump \
  begonia-user-11-RP1A.200720.011-V12.5.3.0.RGGIDXM-release-keys \
  system/system/lib64/libmtk_vt_wrapper.so
```

## 三、应用

| 资源 | 来源 | 备注 |
|---|---|---|
| BCR v3.8（自动通话录音） | `github.com/chenxiaolong/BCR/releases` | 模块 zip 解开后按 [system-app-without-magisk.md](system-app-without-magisk.md) 安装 |
| 微信 Android 版 | `weixin.qq.com` 首页的 arm64 直链（腾讯官方 CDN `dldir1v6.qq.com`） | 页面 HTML 里可直接 grep 出 `.apk` 链接 |

## 四、Pixel 原生素材

全部来自 Pixel 8 Pro 官方固件转储 `gm-stuffs/google_husky_dump`，
分支 `husky-user-14-AP2A.240705.005-11942872-release-keys`：

| 资源 | 仓库内路径 | 说明 |
|---|---|---|
| 铃声（12 首） | `product/media/audio/ringtones/` | 直接是 `.ogg` 散文件 |
| 壁纸（16 张） | `product/app/PixelWallpapers2023/PixelWallpapers2023.apk` | 需解包，图片在 `res/drawable/`，单张 5–7MB |
| Google 时钟 | `product/app/PrebuiltDeskClockGoogle/PrebuiltDeskClockGoogle.apk` | 14.4MB，可直接 `adb install` |

通用取法（免下整包固件）：

```bash
# 列目录
curl -s "https://api.github.com/repos/<owner>/<repo>/contents/<path>?ref=<branch>"
# 取单文件
./tools/extract-blob.sh <owner>/<repo> <branch> <path>
```

## 五、本机工具链

```bash
brew install android-platform-tools   # adb / fastboot
brew install brotli                   # 解压 .dat.br
# python3 系统自带；本仓库脚本无第三方依赖
```

## 六、评估过但未采用

| 资源 | 未采用原因 |
|---|---|
| Project Infinity-X 3.5 VANILLA (begonia) | 维护更活跃，但 begonia 设备树冻结在 Android 15、无 A16 分支、framework 明示不开源——可审计性弱于 LineageOS |
| crDroid (begonia) | 止步 v10.6 / Android 14 (2024-07)，无 A16 版本 |
| `playback_fix.zip` (261MB, `t.me/sai_hub/541`) | 明确标注 "only for A16 QPR1"，而本构建是 QPR2；跨代际刷入风险大于收益 |
| MIUI 官方 fastboot 包（约 4GB） | 作为回滚保险预留，最终未用到 |

## 七、评估 ROM 的省流技巧

用 HTTP Range 只取 zip 头部，即可读出 OTA 元数据（构建指纹、SDK 版本、ota-type），
无需下载整包：

```bash
curl -sL -r 0-400000 "<rom-url>" -o head.bin
# 再解析 head.bin 中 META-INF/com/android/metadata 的本地文件头
```

本项目用它在不下载三个 1.5GB ROM 的前提下，确认它们的构建指纹逐字节相同。
