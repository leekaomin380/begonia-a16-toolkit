Thanks for maintaining this device tree. I hit a reproducible issue on the LineageOS 23.2 build and traced it end-to-end, so I'm reporting it with the full diagnosis — I believe the blobs are declared but never actually extracted.

## Symptom

Outgoing calls stay in `DIALING` forever — no ringback, no connect, no error. Incoming calls fail too. SMS works in both directions. On a carrier with no 2G/3G left (China Unicom), this makes voice calls completely unusable.

## Root cause

`com.mediatek.ims` crashes on startup and is stuck in a restart loop:

```
java.lang.UnsatisfiedLinkError: dlopen failed: library "libmtk_vt_wrapper.so" not found
    at com.mediatek.ims.internal.ImsVTProvider.<clinit>(ImsVTProvider.java:101)
    at com.mediatek.ims.internal.ImsVTProviderUtil.setContextAndInitRefVTPInternal(ImsVTProviderUtil.java:961)
```

```
$ adb shell dumpsys activity services com.mediatek.ims
  * ServiceRecord{... com.mediatek.ims/.MtkDynamicImsService c:com.android.phone}
    app=null
  * Restarting ServiceRecord{...}

$ adb shell ps -A | grep mediatek.ims
(no output)
```

On device, only the 32-bit copy exists:

```
$ adb shell find /system /vendor -name "libmtk_vt*"
/system/lib/libmtk_vt_service.so
/system/lib/libmtk_vt_wrapper.so
# nothing under /system/lib64/
```

`com.mediatek.ims` has `primaryCpuAbi=null`, so on this `zygote64_32` device it runs 64-bit and cannot load the 32-bit `.so`. Because the load happens in a **static initializer**, the exception kills the whole process — taking MMTEL (voice) down with it, even though ViLTE is disabled (`persist.vendor.vilte_support=0`).

## Why I think it's an extraction problem, not a config one

`device_redmi_begonia/proprietary-files.txt` (branch `avium-16.2`) declares them correctly:

```
998: system_ext/lib64/libmtk_vt_service.so:system/lib64/libmtk_vt_service.so|302d3ab3c5b3fa0107520fe36098b32cd0a8dd96
999: system_ext/lib64/libmtk_vt_wrapper.so:system/lib64/libmtk_vt_wrapper.so|af4d486c516c920ea99c362aebbf04180e96035c
```

But `vendor_redmi_begonia/proprietary/system_ext/lib64/` (same branch) contains 41 blobs and **none of them match `vt` or `ims`**. The neighbouring `libimsma*.so` entries on lines 994–997 appear to be missing as well.

So the entries are declared, the blobs were never committed, and the build completed silently without them.

## Downstream chain

```
missing lib64 blob
  -> ImsVTProvider.<clinit> throws UnsatisfiedLinkError
    -> com.mediatek.ims crash-loops (app=null + Restarting)
      -> MMTEL feature never created
        -> Enhanced 4G LTE toggle not rendered in Settings;
           framework only polls IMS_REGISTRATION_STATE, never sends SET_IMS_ENABLE
          -> dialing falls back to GsmCdmaCallTracker (dialGsm)
            -> no CSFB available on this carrier
              -> call hangs in DIALING
```

Every layer above this looks healthy, which makes it easy to misdiagnose as carrier config: `config_device_volte_available=true`, `carrier_volte_available_bool=true`, `hide_enhanced_4g_lte_bool=false`, IMS APNs present, `IRadio/imsAospSlot1/2` HALs running, ImsService correctly bound to `com.mediatek.ims`.

## Workaround I verified

Pulled the arm64 blob from a stock MIUI dump and installed it to `/system/lib64/`. The stock blob has `DT_NEEDED` entries for `libhidltransport.so`, `libvcodec_cap.so` and `vendor.mediatek.hardware.videotelephony@1.0.so`, none of which exist on Android 16, so I redirected those three entries to `liblog.so` (an existing dependency) without touching `.dynstr`. Since ViLTE is disabled, the VT code paths never execute — `System.loadLibrary` just needs to succeed.

Result:

```
ImsRegistrationTechnology: -1  ->  0 (LTE)
call routing: dialGsm  ->  ImsPhoneCallTracker
call states: ALERTING -> ACTIVE   (calls actually connect)
```

Tooling and the full write-up: https://github.com/leekaomin380/begonia-a16-toolkit

## Suggestions

1. Re-run `extract-files` and confirm the `system_ext/lib64` IMS/VT blobs actually land in the vendor repo — a silent skip here costs all voice functionality.
2. Optionally, guard `ImsVTProviderUtil` initialization behind `vilte_support` so a missing VT blob can never take MMTEL down with it. That would make the failure mode degrade gracefully instead of catastrophically.

Environment: LineageOS 23.2-20260328-UNOFFICIAL-begonia, Android 16 (API 36), China Unicom (46001). Happy to run any further diagnostics — I have the device.
