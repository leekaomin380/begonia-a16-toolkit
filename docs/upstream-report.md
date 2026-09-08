# 上游缺陷报告（待提交）

这个缺陷的正确修复位置在 ROM 构建配置里——在 `proprietary-files.txt` 中补一行，
让下一个构建自带 64 位库即可。对维护者来说是一行的事，却能让所有使用者受益。

## 提交渠道

该构建的设备树未完整公开（`begonia-lineage` 组织最后更新停在 2023-02，
无 Android 16 分支），因此没有可直接开 issue 的仓库。可用渠道：

1. **XDA 原帖回复** —— 维护者在该帖中活跃回复过用户（如指纹问题）。最直接。
   `[ROM][UNOFFICIAL] LineageOS 23.2 [Redmi Note 8 Pro/begonia]`
2. **维护者的 Telegram 频道** `t.me/danascapeprojects`
3. **内核仓库 issue** `WuXing90/begonia_kernel_dev` —— 严格说不对口（这是内核而非
   proprietary-files），但可作为备选。

## 报告正文（英文，可直接粘贴）

---

**Subject: VoLTE broken — `libmtk_vt_wrapper.so` missing from `/system/lib64` (64-bit variant not packaged)**

Thanks for the build. I hit a reproducible issue and traced it to a packaging problem,
so I'm reporting it with the full diagnosis in case it's a one-line fix.

**Symptom**

Outgoing calls stay in `DIALING` forever — no ringback, no connect, no error. Incoming
calls fail too. SMS works fine in both directions. On a carrier with no 2G/3G left
(China Unicom), this means voice calls are completely unusable.

**Root cause**

`com.mediatek.ims` crashes on startup and is stuck in a restart loop:

```
java.lang.UnsatisfiedLinkError: dlopen failed: library "libmtk_vt_wrapper.so" not found
    at com.mediatek.ims.internal.ImsVTProvider.<clinit>(ImsVTProvider.java:101)
    at com.mediatek.ims.internal.ImsVTProviderUtil.setContextAndInitRefVTPInternal(ImsVTProviderUtil.java:961)
```

```
$ adb shell dumpsys activity services com.mediatek.ims
  * ServiceRecord{... com.mediatek.ims/.MtkDynamicImsService ...}
    app=null
  * Restarting ServiceRecord{... }
```

The library is present, but only as the 32-bit variant:

```
$ adb shell find /system /vendor -name "libmtk_vt*"
/system/lib/libmtk_vt_service.so
/system/lib/libmtk_vt_wrapper.so
# nothing under /system/lib64/
```

`com.mediatek.ims` has `primaryCpuAbi=null` (no bundled native libs), so it runs 64-bit
on this `zygote64_32` device and cannot load the 32-bit `.so`.

Because the load happens in a **static initializer**, the exception kills the whole
process — taking MMTEL (voice) down with it, even though ViLTE is disabled
(`persist.vendor.vilte_support=0`).

**Downstream effects**

MMTEL feature never gets created → the Enhanced 4G LTE toggle is not rendered in
Settings → the framework only polls `IMS_REGISTRATION_STATE` and never sends
`SET_IMS_ENABLE` → dialing falls back to `GsmCdmaCallTracker` (`dialGsm`) → no CSFB
available → call hangs in `DIALING`.

Every layer above this looks healthy, which makes it easy to misdiagnose as a carrier
config issue: `config_device_volte_available=true`, `carrier_volte_available_bool=true`,
`hide_enhanced_4g_lte_bool=false`, IMS APNs present, `IRadio/imsAospSlot1/2` HALs
running, ImsService correctly bound to `com.mediatek.ims`.

**Suggested fix**

Add the 64-bit variant to `proprietary-files.txt` (it exists in stock MIUI for this
device, e.g. `V12.5.3.0.RGGIDXM`):

```
system/lib64/libmtk_vt_wrapper.so
```

Note that the stock blob has `DT_NEEDED` entries for `libhidltransport.so`,
`libvcodec_cap.so` and `vendor.mediatek.hardware.videotelephony@1.0.so`, none of which
exist on Android 16. As a local workaround I redirected those three `DT_NEEDED` entries
to `liblog.so` (an existing dependency) without touching `.dynstr`, which is enough for
`System.loadLibrary` to succeed. Since ViLTE is disabled, the VT code paths are never
executed. A cleaner upstream fix might be to also ship the missing deps, or to guard the
VT provider initialization behind the `vilte_support` property so it doesn't run at all.

**Verified after the workaround**

```
ImsRegistrationTechnology: -1 -> 0 (LTE)
call routing: dialGsm -> ImsPhoneCallTracker
call states: ALERTING -> ACTIVE (call actually connects)
```

Environment: LineageOS 23.2-20260328-UNOFFICIAL-begonia, Android 16 (API 36),
China Unicom (46001).

---

## 提交前的检查

- 报告中不含任何设备标识（IMEI、手机号、序列号）
- 语气：这是一个免费的社区构建，报告的目的是帮助修复而非索赔
- 已提供完整的诊断证据和可操作的修复建议，这是维护者最难自行获得的部分
  （他没有这台设备 + 该运营商环境的组合）
