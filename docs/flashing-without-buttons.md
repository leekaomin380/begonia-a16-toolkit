# 音量键损坏时如何刷机

动因：一台音量键失灵的 Redmi Note 8 Pro。结论可推广到任何**按键损坏**或**没有可用
自定义 recovery** 的设备。

## 先说三条已验证失效的路径

记录失败路径和记录成功路径同样有价值——能省掉重复踩坑。

| 路径 | 结果 |
|---|---|
| `fastboot boot twrp.img`（临时引导，不写分区） | **被小米 bootloader 拒绝**：`usb_read failed`，设备直接重启回系统 |
| `fastboot reboot recovery` | **返回 OKAY 但被忽略**，实际启动的是系统（`ro.bootmode=normal`） |
| `fastboot flash recovery` 后让系统启动一次再 `adb reboot recovery` | **MIUI 在正常开机时会把 stock recovery 刷回去**，TWRP 被冲掉 |

三条路各断在不同环节，构成死结：进 recovery 需要物理按键，而软件路径要么被禁、
要么被还原。

## 可用的路径

`adb reboot bootloader` **可用**——不需要任何物理按键。所以 fastboot 是能进的，
问题只在 recovery。

于是**绕开 recovery**：把 ROM 的 BLOCK OTA 数据在电脑上还原成裸镜像，全程 fastboot 刷入。

### 步骤

```bash
# 1. 确认包格式（ota-type=BLOCK 才适用本方法）
unzip -p rom.zip META-INF/com/android/metadata | grep -E 'ota-type|pre-device|post-sdk'

# 2. 解包
unzip rom.zip system.new.dat.br system.transfer.list \
              vendor.new.dat.br vendor.transfer.list \
              boot.img dtbo.img vbmeta.img

# 3. 还原成裸镜像
brotli -d system.new.dat.br -o system.new.dat
python3 tools/sdat2img.py system.transfer.list system.new.dat system.img
brotli -d vendor.new.dat.br -o vendor.new.dat
python3 tools/sdat2img.py vendor.transfer.list vendor.new.dat vendor.img

# 4. 刷入
adb reboot bootloader
fastboot flash system  system.img
fastboot flash vendor  vendor.img
fastboot flash boot    boot.img
fastboot flash dtbo    dtbo.img
fastboot flash vbmeta  vbmeta.img
fastboot erase userdata     # 等价于 recovery 里的 Format Data
fastboot erase metadata
fastboot reboot
```

## 这个方法的额外好处：精确控制写哪些分区

走 recovery 就得接受 `updater-script` 写什么就是什么。直刷则由你决定。

以本例的 ROM 为例，它的 `updater-script` 除 system/vendor 外还会写整套 MTK 固件：

```
preloader_ufs.img -> /dev/block/sda 和 sdb    # 一阶段引导，写坏 = 不可恢复硬砖
lk.img            -> lk / lk2                 # bootloader
tee.img           -> tee1 / tee2
md1img.img        -> md1img                   # 基带
scp / sspm / spmfw / gz / audio_dsp / cam_vpu*
```

`preloader` 和 `lk` 是唯一能造成**永久硬砖**的写入目标（防回滚保护 ARB 也只在写
bootloader 链固件时触发）。直刷时跳过它们，这类风险直接归零。

刷完若发现基带或摄像头异常，再单独补刷对应固件即可——**把不可逆的动作放到最后，
且只在确有必要时做**。

### 先刷后擦，不要先擦后刷

`ota-type=BLOCK` 的镜像是整分区覆写，预先 wipe system/vendor 是冗余动作，只会制造
一个"旧系统已清空、新系统未装上"的不可逆窗口。若刷入因兼容性问题早期失败，先擦会
让设备无系统可启动；不擦则原系统完好，重启即回。

## 软砖 vs 硬砖

只要不碰 preloader/lk，最坏情况是**软砖**（系统起不来）。bootloader 解锁 + fastboot
可用的前提下，随时可以刷回官方固件恢复。风险的真实性质是**停机时间**，不是永久报废。

## 还需要 recovery 的场合

本方法不能替代 recovery 的全部功能（如 nandroid 备份）。若确需 TWRP，注意某些 ROM
的 zip 里自带匹配版本的 `twrp.img`，可直接 `fastboot flash recovery` 取出使用。
