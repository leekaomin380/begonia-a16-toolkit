# 不用 Magisk 安装系统特权应用

很多 Android 项目标称 "requires root"，但真实要求往往只是**作为系统特权应用安装**
以获得某些签名级/特权级权限。两者的区别在需要规避 root 检测的场景下很关键
（金融类 App、部分社交应用的风控）。

## 典型例子：BCR（自动通话录音）

[chenxiaolong/BCR](https://github.com/chenxiaolong/BCR) 的说明写的是
"for rooted Android devices"，其发布包是 Magisk/KernelSU 模块格式。但把模块解开看：

```
system/priv-app/com.chiller3.bcr/app-release.apk
system/etc/permissions/privapp-permissions-com.chiller3.bcr.xml
system/addon.d/51-com.chiller3.bcr.sh          # 仅用于在 OTA 后自动恢复
```

**是一个纯 `/system` 覆盖层**，没有任何需要 Magisk 运行时才能完成的事。它需要的是：

```
android.permission.CAPTURE_AUDIO_OUTPUT      # 录到对方声音的前提，特权级
android.permission.CONTROL_INCALL_EXPERIENCE # 被 Telecom 绑定为 InCallService
```

这些权限只授予 `/system/priv-app` 下、且在 `privapp-permissions` 白名单中声明的应用。

## 安装步骤

```bash
adb root && adb remount        # 需要 /system 可写

adb shell mkdir -p /system/priv-app/<pkg>
adb push app.apk /system/priv-app/<pkg>/
adb push privapp-permissions-<pkg>.xml /system/etc/permissions/

adb shell '
  chmod 755 /system/priv-app/<pkg>
  chmod 644 /system/priv-app/<pkg>/app.apk /system/etc/permissions/privapp-permissions-<pkg>.xml
  chown -R root:root /system/priv-app/<pkg> /system/etc/permissions/privapp-permissions-<pkg>.xml
  chcon u:object_r:system_file:s0 /system/priv-app/<pkg>
  chcon u:object_r:system_file:s0 /system/priv-app/<pkg>/app.apk
  chcon u:object_r:system_file:s0 /system/etc/permissions/privapp-permissions-<pkg>.xml'

adb reboot                     # 必须重启，让 PackageManager 扫描并授予特权权限
```

重启后验证：

```console
$ adb shell dumpsys package <pkg> | grep -E "granted=true"
android.permission.CAPTURE_AUDIO_OUTPUT: granted=true
android.permission.CONTROL_INCALL_EXPERIENCE: granted=true
```

运行时权限仍需单独授予：

```bash
for p in RECORD_AUDIO READ_PHONE_STATE POST_NOTIFICATIONS; do
  adb shell pm grant <pkg> android.permission.$p
done
```

## 关于 adb root

LineageOS 在 开发者选项 里提供「Root 身份的调试」（Rooted debugging）。它**不是
Magisk**：不修改 boot 镜像、不注入 su 守护进程、不 hook zygote，因此不产生
Magisk 那类可被检测的特征。用完可以关掉——对 `/system` 的修改已落盘，不依赖它。

注意：直接写 `settings put global adb_root 1` **不生效**，必须从 UI 拨动开关
（Settings 应用在拨动时会同时重启 adbd）。

## 前置条件与限制

- `/system` 必须可写。若启用了 dm-verity，修改会导致启动校验失败。
  判据看挂载源而非属性：`mount | grep ' / '`，显示 `/dev/block/dm-N` 表示 verity 生效。
- ROM 的 OTA 更新会覆盖 `/system`，修改需要重做（Magisk 模块的 `addon.d` 脚本正是
  为解决这个问题而存在）。
