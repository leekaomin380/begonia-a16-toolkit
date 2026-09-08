# begonia + Android 16 实测状态

设备：Redmi Note 8 Pro (`begonia`)，Helio G90T，6GB/128GB，静态分区（无 super）
系统：LineageOS 23.2 UNOFFICIAL，构建日期 2026-03-28
环境：中国联通（46001），卡槽 2

## 功能状态

| 功能 | 状态 | 说明 |
|---|---|---|
| 启动 / Wi-Fi / 蓝牙 / GPS | 可用 | |
| 摄像头 | 可用 | |
| 短信 | 可用 | 收发均正常 |
| 移动数据 | 可用 | LTE |
| **通话** | 修复后可用 | 见 [root-cause.md](root-cause.md)；开箱状态不可用 |
| **VoLTE** | 修复后可用 | 同上 |
| **指纹** | **不可用** | 开发者本人在 XDA 帖中确认；与本仓库的修复无关 |
| 通话录音（手动） | 可用 | LineageOS 拨号器自带 |
| 通话录音（自动） | 需装 BCR | 见 [system-app-without-magisk.md](system-app-without-magisk.md) |

### 通话录音的音源（已实测）

LineageOS 拨号器的 RRO 在本构建中已把录音开关覆盖为启用，且音源为 `VOICE_CALL(4)`
而非源码默认的 `MIC(1)`：

```console
$ adb shell cmd overlay lookup com.android.dialer com.android.dialer:bool/call_recording_enabled
true
$ adb shell cmd overlay lookup com.android.dialer com.android.dialer:integer/call_recording_audio_source
4
```

**注意：读源码默认值会得出相反结论**（LineageOS 上游默认是 `false` / `MIC`），
必须用 `cmd overlay lookup` 查设备实际生效值。

BCR 走同一条特权音源路径。实测一通真实来电录音，**通话双方声音均清晰可辨**——
即 MTK 的音频 HAL 确实接受 `VOICE_CALL` 音源，不需要 root 或音源改写。
录音参数：OGG/Opus 48kbps、16kHz 单声道（电话带宽）、零丢帧、零缓冲溢出。

原帖的 `What's working` 把 Fingerprint 列为可用，**与实测不符**；`Known issues`
栏原文是 "Need to check"，即未系统测试过。

## 值得记录的构建细节

**构建指纹是伪装的。** OTA 元数据里：

```
post-build=Redmi/begonia/begonia:11/RP1A.200720.011/V12.5.8.0.RGGMIXM:user/release-keys
post-sdk-level=36
```

对外声称 Android 11 / MIUI 12.5.8 / release-keys，实际 SDK 是 36（Android 16）。
这是自定义 ROM 通过 Play Integrity 的常规做法，但要注意：**同时读这两个字段的风控
引擎会看到矛盾**。对依赖 Google 认证链的应用（银行、WhatsApp）这个伪装是必要的；
对自建风控体系的应用（如微信国内版，它不走 FCM，用自建 TCP 长连接）反而可能是
负面信号。

实测同期三个 begonia 的 Android 16 构建（LineageOS 23.2 / Infinity-X 3.5 / 3.8）
**指纹字符串逐字节相同**——它们同源于一套设备树。可用 HTTP Range 请求读 zip 头部的
`META-INF/com/android/metadata` 对比，无需下载整包。

**自带固件，无需预刷底包。** `pre-device=begonia` 且无 `pre-build` 约束，
说明是可整刷的完整包。

**verity 未启用。** `ro.boot.veritymode` 属性显示 `enforcing`，但 `/` 直接挂载在
块设备上（`/dev/block/sdc40`）而非 dm 映射——属性反映的是 bootloader 设置，
与实际生效状态不一致。因此 `/system` 可写。

**分区布局为静态分区**，无 `super`，`ota-type=BLOCK`。这与 2020 年前后的 TWRP 假设
相符，也是可以用 fastboot 直刷镜像的前提。

## 与运营商相关

中国联通已关停 2G/3G，**没有 CSFB 回落路径**。这意味着 VoLTE 不工作 = 完全无法通话
（而不是"降级到 2G 通话"）。在其它仍保留 2G 的运营商或地区，同一个 ROM 缺陷可能只
表现为"通话质量下降"而非"完全不通"，因此更难被发现——这可能是该缺陷长期未被报告的
原因之一。
