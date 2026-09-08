# 根因分析：一个缺失的 .so 如何让整台手机打不了电话

设备：Redmi Note 8 Pro (`begonia`)，MediaTek Helio G90T (mt6785)
系统：LineageOS 23.2 / Android 16 (API 36)，非官方构建
运营商：中国联通（已关停 2G/3G，因此无 CSFB 回落路径）

## 症状

拨出的电话进入 `DIALING` 后**永远停在那里**——不振铃、不接通、也不报错。呼入同样
不通。但**短信收发正常**。

短信正常这一点很关键：它说明信令通道完好，故障范围被限定在语音承载。

## 排查路径（含走过的弯路）

### 第一天：把配置层查了个遍，全部健康

| 检查项 | 命令 | 结果 |
|---|---|---|
| 平台级 VoLTE | `cmd overlay lookup android android:bool/config_device_volte_available` | `true` |
| 运营商配置 | `dumpsys carrier_config \| grep carrier_volte_available_bool` | `true`（按 Phone Id 分列） |
| 隐藏开关标志 | `dumpsys carrier_config \| grep hide_enhanced_4g_lte_bool` | `false` |
| vendor 属性 | `getprop \| grep -iE "volte\|ims_support"` | `ims_support=1` `volte_support=1` `mtk.volte.enable=3` |
| ImsService 绑定 | `cmd phone ims get-ims-service -s 1 -d -f 1` | `com.mediatek.ims` |
| IMS HAL 实例 | `lshal list -i \| grep imsAosp` | `IRadio/imsAospSlot1/2` 在运行 |
| IMS APN | `content query --uri content://telephony/carriers` | 存在 `type=ims` 条目 |
| 网络侧 VoPS | `dumpsys telephony.registry \| grep LteVopsSupportInfo` | `mVopsSupport=2` |
| IMS 注册 | `logcat -b radio \| grep ImsRegistrationTechnology` | **`-1`（未注册）** |

**每一层都说"应该能用"，但 IMS 就是不注册。**

> **弯路一：常量读反。** `mVopsSupport=2` 一度被判为"网络不支持 VoLTE"。实际
> `android.telephony.LteVopsSupportInfo` 的常量从 1 起：
> `NOT_AVAILABLE=1, SUPPORTED=2, NOT_SUPPORTED=3`。**2 是 SUPPORTED**，网络侧没问题。

> **弯路二：`dumpsys` 分节。** `dumpsys carrier_config` 会输出多段（默认段 + 每个
> Phone Id 一段）。用 `grep ... | head -N` 很容易只看到第一段的默认值 `false` 而
> 误判为根因。务必按 `Phone Id` 分列查看。

> **弯路三：设置值 ≠ 生效值。** 用 `settings put global volte_vt_enabled 1` 直接写
> 数据库，**不会**触发框架的 `ImsManager` 把配置下发给调制解调器。这也解释了当时
> 观察到的异常：RIL 日志里只有 `IMS_REGISTRATION_STATE`（查询），从无 `SET_IMS_ENABLE`
> （下发）。

### 第二天：一条命令命中

设置界面里**根本不渲染 VoLTE 开关**。AOSP 只在三种情况下隐藏它，前两种已排除，
剩下"MMTEL 能力不可达"。于是不再查配置，改查**服务本身**：

```console
$ adb shell dumpsys activity services com.mediatek.ims
  * ServiceRecord{... com.mediatek.ims/.MtkDynamicImsService c:com.android.phone}
    app=null
  * Restarting ServiceRecord{... MtkDynamicImsService ...}
    app=null

$ adb shell ps -A | grep mediatek.ims
（无输出）
```

`app=null` + `Restarting` + 进程不存在 = **服务在崩溃循环里**。

```console
$ adb shell logcat -b crash | grep -A6 mediatek.ims
E AndroidRuntime: FATAL EXCEPTION: ProviderHandlerThread
E AndroidRuntime: Process: com.mediatek.ims, PID: ****
E AndroidRuntime: java.lang.UnsatisfiedLinkError: dlopen failed:
                  library "libmtk_vt_wrapper.so" not found
E AndroidRuntime:   at com.mediatek.ims.internal.ImsVTProvider.<clinit>(ImsVTProvider.java:101)
E AndroidRuntime:   at com.mediatek.ims.internal.ImsVTProviderUtil.setContextAndInitRefVTPInternal
```

### 库为什么找不到

```console
$ adb shell find /system /vendor -name "libmtk_vt*"
/system/lib/libmtk_vt_service.so      # 32 位
/system/lib/libmtk_vt_wrapper.so      # 32 位
# /system/lib64/ 下没有

$ adb shell dumpsys package com.mediatek.ims | grep CpuAbi
primaryCpuAbi=null      # APK 内无原生库 -> 在 zygote64_32 系统上按 64 位运行
```

ROM 打包时保留了无用的 32 位版本，**丢掉了 64 位版本**。该 ROM 的设备树提交记录里
有多条 `Drop 32bit ... blobs` / `Nuke useless MTK config` 一类的裁剪操作，这次裁反了。

讽刺之处：崩溃的是**视频通话**模块，而视频通话本来就是关的
（`persist.vendor.vilte_support=0`）——但它在**静态初始化块**里无条件加载，
异常直接终结整个进程，把语音一起拖死。

## 完整因果链

```
1. /system/lib64/libmtk_vt_wrapper.so 缺失
2.   -> ImsVTProvider.<clinit> 中 System.loadLibrary 抛 UnsatisfiedLinkError
3.     -> com.mediatek.ims 进程崩溃，被系统无限重启（app=null + Restarting）
4.       -> MMTEL feature 从未创建
5.         -> 设置不渲染 VoLTE 开关；框架只轮询 IMS_REGISTRATION_STATE，
              从不下发 SET_IMS_ENABLE
6.           -> 拨号交给 GsmCdmaCallTracker，走 CS 电路域（日志 dialGsm）
7.             -> 运营商已关停 2G/3G，无 CSFB 可回落
8.               -> 呼叫永远停在 DIALING
```

**中间任何一层单独看都像配置问题**，这是排查耗时的原因。

## 修复

上游 blob 的 arm64 版本可从同机型固件转储取得。但它是 Android 11 时代的产物，
依赖三个在 Android 16 上已不存在的库：

```
libhidltransport.so                              # Android 11 后已从系统移除
libvcodec_cap.so                                 # MTK 私有，本 ROM 未打包
vendor.mediatek.hardware.videotelephony@1.0.so   # 同上
```

**不去搬运这些旧依赖**（会引发级联，且把 Android 11 的 HIDL 运行时塞进 Android 16
本身就危险）。改为对 ELF 做**非破坏性修补**：把这三条 `DT_NEEDED` 的 `d_val` 指向
`.dynstr` 中已存在的另一个库名（`liblog.so`，它本来就在依赖表里）。

不改写字符串表本身，因此不会破坏相邻符号。

```bash
python3 tools/elf-redirect-needed.py in.so out.so liblog.so \
    libhidltransport.so libvcodec_cap.so vendor.mediatek.hardware.videotelephony@1.0.so
```

**这个办法成立的前提**：被重定向掉的依赖，其代码路径在运行时不会被执行。本例中
视频通话已禁用，我们只需要 `System.loadLibrary` 不抛异常，让静态初始化走完即可。
若那些依赖的函数会真正被调用，程序会在运行时崩溃，而不是加载时失败。

安装（属主/权限/SELinux 上下文必须与同目录其它库一致）：

```bash
adb push patched.so /system/lib64/libmtk_vt_wrapper.so
adb shell chmod 644 /system/lib64/libmtk_vt_wrapper.so
adb shell chown root:root /system/lib64/libmtk_vt_wrapper.so
adb shell chcon u:object_r:system_lib_file:s0 /system/lib64/libmtk_vt_wrapper.so
```

> `/system` 可写的前提是本构建**未启用 dm-verity**。判据不是 `ro.boot.veritymode`
> 属性（它反映 bootloader 设置，可能与实际不符），而是挂载源：
> `mount | grep ' / '` 若显示块设备（如 `/dev/block/sdc40`）而非 `/dev/block/dm-N`，
> 则 verity 未生效。

## 校验和

```
上游原始 blob (arm64)   sha256  1f2a039c094d3cfc0a01c633b061570039543389ca8e5ad60f3d773a820cc2fb
本文档所述方法修补后     sha256  af87ae4c6379876e02bd3c1e9294273b7df001d91dc6d630e3708ec15357a2ad
```

## 验证

```console
$ adb shell ps -A | grep mediatek.ims
**** com.mediatek.ims                                  # 进程存活

$ adb shell dumpsys activity services com.mediatek.ims | grep app=
    app=ProcessRecord{... com.mediatek.ims/1001}       # 不再是 null

$ adb shell logcat -b radio | grep -oE "ImsRegistrationTechnology =-?[0-9]+"
ImsRegistrationTechnology =0                           # 0 = REGISTRATION_TECH_LTE

# 实拨后
$ adb shell logcat -b radio | grep -c ImsPhoneCallTracker
37                                                     # 走 IMS，不再是 dialGsm
# 呼叫状态推进：ALERTING -> ACTIVE
```

## 方法论小结

**先确认进程活着，再查配置。** 第一天把配置层查了个遍，全部健康；第二天靠
`dumpsys activity services <pkg>` 一击命中。配置查得再深，也发现不了服务根本没在跑。
