# begonia A16 VoLTE 修复

在 Redmi Note 8 Pro（`begonia`，MediaTek Helio G90T）的 Android 16 自定义 ROM 上，
**拨出的电话永远停在 DIALING、既不振铃也不接通**。

根因不是配置，是 ROM 少打包了一个 64 位私有库：

```
/system/lib64/libmtk_vt_wrapper.so   缺失
/system/lib/libmtk_vt_wrapper.so     存在（32 位，对 64 位进程无用）
```

`com.mediatek.ims` 是 64 位进程，它在静态初始化时 `dlopen` 该库失败并崩溃，随后陷入
无限重启，导致整条 VoLTE 链路从最底层断掉。完整因果链见 [docs/root-cause.md](docs/root-cause.md)。

> **本仓库不分发任何专有二进制。** 所需的库由使用者自行从对应机型的官方固件转储中提取。

## 快速修复

前置：bootloader 已解锁、设备通过 adb 连接、开发者选项里开启「Root 身份的调试」
（LineageOS 自带能力，**不是 Magisk**，不修改 boot 镜像）。

```bash
./tools/install-fix.sh      # 取 blob -> 校验 -> 修补 -> 安装
# 重启后
./tools/diagnose-volte.sh   # 验证
```

预期变化：

| | 修复前 | 修复后 |
|---|---|---|
| `com.mediatek.ims` 进程 | `app=null` + `Restarting` | 正常存活 |
| `ImsRegistrationTechnology` | `-1`（未注册） | `0`（LTE） |
| 拨号通道 | `dialGsm`（CS 电路域） | `ImsPhoneCallTracker`（VoLTE） |
| 通话状态 | 永远 `DIALING` | `ALERTING` → `ACTIVE` |
| 设置里的 VoLTE 开关 | 不渲染 | 出现 |

## 为什么这个故障值得单独记录

表象（"打不了电话"）与根因（少一个 `.so`）之间隔着**六层**，中间任何一层单独看
都像配置问题：

```
库缺失 → 静态初始化崩溃 → IMS 进程重启循环 → MMTEL feature 未创建
      → 框架只查询不下发 SET_IMS_ENABLE → 退回 CS 电路域
      → 运营商已关停 2G/3G，无回落路径 → 永远 DIALING
```

所以本仓库的重点不只是补一个文件，而是**那条排查路径**——见
[docs/root-cause.md](docs/root-cause.md) 里每一层的验证命令。

## 通用工具（不限于本机型）

| 工具 | 用途 | 可迁移性 |
|---|---|---|
| `elf-redirect-needed.py` | 把 `DT_NEEDED` 重定向到已存在的库，让旧 blob 能在新 Android 上加载 | 高 |
| `diagnose-volte.sh` | 自定义 ROM 上 VoLTE 故障的分层诊断 | 高（MTK 平台） |
| `extract-blob.sh` | 从固件转储仓库按路径取单个文件，免下整包固件 | 高 |
| `sdat2img.py` | BLOCK OTA 的 `.dat.br` + `transfer.list` → 裸镜像 | 高 |
| `install-fix.sh` | 本机型的一键修复 | 低（机型专属） |

## 其它文档

- [无按键刷机](docs/flashing-without-buttons.md) —— 音量键损坏时怎么刷，含三条已验证失效的路径
- [不用 Magisk 安装系统特权应用](docs/system-app-without-magisk.md) —— 适用于标称 "requires root" 但实为"需系统权限"的项目
- [begonia A16 实测状态](docs/findings.md) —— 哪些能用、哪些不能

## 上游

这个缺陷的正确修复位置在 ROM 的 `proprietary-files.txt`——加一行让下一个构建自带
64 位库即可。本仓库是给"卡在现有构建上的人"的临时方案。上游 issue 见 `docs/upstream-report.md`。

## 许可

工具与文档采用 MIT。专有二进制不在本仓库范围内，其权利归各自所有者。
