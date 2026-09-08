#!/usr/bin/env bash
# 自定义 ROM 上 VoLTE 不工作的分层诊断。
#
# 诊断顺序刻意如此：先确认「进程活着」，再查配置。
# 反过来做会浪费大量时间 —— 配置查得再深，也发现不了服务根本没在跑。
#
# 用法: ./diagnose-volte.sh [ims-package]   默认 com.mediatek.ims
set -uo pipefail
PKG="${1:-com.mediatek.ims}"
s() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
adb get-state >/dev/null 2>&1 || { echo "设备未连接"; exit 1; }

s "0. 设备"
adb shell getprop ro.product.device
adb shell getprop ro.build.version.release
adb shell getprop ro.lineage.version 2>/dev/null

s "1. IMS 服务进程是否存活   <- 最先查这个"
if adb shell "ps -A -o PID,NAME 2>/dev/null | grep -i '$PKG'" | grep -q .; then
  adb shell "ps -A -o PID,NAME 2>/dev/null | grep -i '$PKG'"
  echo "  -> 进程存在"
else
  echo "  -> 进程不存在。这就是故障点，继续看第 2 项和第 3 项。"
fi

s "2. 服务绑定状态   app=null + Restarting 表示崩溃循环"
adb shell "dumpsys activity services $PKG 2>/dev/null | grep -E 'ServiceRecord|app=' | head -4"

s "3. 崩溃原因   UnsatisfiedLinkError 通常意味着 ROM 少打包了某个 .so"
adb shell "logcat -d -b crash -t 3000 2>/dev/null | grep -A4 -i '$PKG' | head -20"

s "4. ImsService 是否被框架绑定   空 = 未配置"
echo -n "  设备默认(MMTEL): "; adb shell cmd phone ims get-ims-service -s 1 -d -f 1 2>&1
echo -n "  运营商覆盖(MMTEL): "; adb shell cmd phone ims get-ims-service -s 1 -c -f 1 2>&1

s "5. IMS 注册技术   -1=未注册  0=LTE  1=IWLAN"
adb shell "logcat -d -b radio -t 2000 2>/dev/null | grep -oE 'ImsRegistrationTechnology =-?[0-9]+' | tail -3"

s "6. 平台级开关"
for k in config_device_volte_available config_carrier_volte_available; do
  echo -n "  $k = "; adb shell cmd overlay lookup android "android:bool/$k" 2>&1
done

s "7. 运营商配置（按 Phone Id 分列）"
adb shell 'dumpsys carrier_config 2>/dev/null' | awk '
  /Phone Id *=/ { id=$0 }
  /carrier_volte_available_bool|hide_enhanced_4g_lte_bool/ { print "  [" id "] " $0 }' | head -8

s "8. 用户开关"
for k in volte_vt_enabled enhanced_4g_mode_enabled; do
  echo -n "  $k = "; adb shell settings get global "$k" 2>&1
done

s "9. IMS 类型 APN 是否存在"
adb shell 'content query --uri content://telephony/carriers --projection name,apn,type 2>/dev/null' \
  | grep -i 'type=ims' | head -3 || echo "  未找到 ims 类型 APN"

s "10. 实拨时走哪条通道   ImsPhoneCallTracker=VoLTE  GsmCdmaCallTracker=CS电路域"
echo "  手动拨一通电话后运行:"
echo "    adb shell \"logcat -d -b radio -t 2000 | grep -coE 'ImsPhoneCallTracker|dialGsm'\""
