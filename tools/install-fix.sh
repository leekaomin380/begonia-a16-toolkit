#!/usr/bin/env bash
# 一键修复：取 blob -> 修补 DT_NEEDED -> 安装到 /system/lib64
#
# 前置条件：
#   1. 设备已通过 adb 连接
#   2. 已在 开发者选项 中开启「Root 身份的调试」(LineageOS 自带，非 Magisk)
#   3. /system 可写（本 ROM 未启用 dm-verity；用 `mount | grep ' / '` 确认
#      挂载源是块设备而非 /dev/block/dm-N）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

DUMP_REPO=ZyCromerZ/redmi_begonia_dump
DUMP_BRANCH=begonia-user-11-RP1A.200720.011-V12.5.3.0.RGGIDXM-release-keys
BLOB_PATH=system/system/lib64/libmtk_vt_wrapper.so
# 上游 blob 的 sha256（原始未修补版本）
BLOB_SHA=1f2a039c094d3cfc0a01c633b061570039543389ca8e5ad60f3d773a820cc2fb

echo "[1/5] 从固件转储取 libmtk_vt_wrapper.so (arm64)"
bash "$HERE/extract-blob.sh" "$DUMP_REPO" "$DUMP_BRANCH" "$BLOB_PATH" "$WORK/orig.so"
GOT=$(shasum -a 256 "$WORK/orig.so" | awk '{print $1}')
[ "$GOT" = "$BLOB_SHA" ] || { echo "校验和不符：期望 $BLOB_SHA 实得 $GOT"; exit 1; }
echo "  校验和通过"

echo "[2/5] 重定向已在 Android 16 上消失的依赖"
python3 "$HERE/elf-redirect-needed.py" "$WORK/orig.so" "$WORK/patched.so" \
  liblog.so libhidltransport.so libvcodec_cap.so vendor.mediatek.hardware.videotelephony@1.0.so

echo "[3/5] 取得 root 并重挂载 /system"
adb root >/dev/null 2>&1 || true
sleep 3
[ "$(adb shell id -u | tr -d '\r')" = "0" ] || {
  echo "未取得 root。请在 设置->系统->开发者选项 中开启「Root 身份的调试」"; exit 1; }
adb remount >/dev/null 2>&1 || adb shell mount -o rw,remount /

echo "[4/5] 安装并设置属主/权限/SELinux 上下文"
adb push "$WORK/patched.so" /system/lib64/libmtk_vt_wrapper.so >/dev/null
adb shell 'chmod 644 /system/lib64/libmtk_vt_wrapper.so
           chown root:root /system/lib64/libmtk_vt_wrapper.so
           chcon u:object_r:system_lib_file:s0 /system/lib64/libmtk_vt_wrapper.so
           ls -lZ /system/lib64/libmtk_vt_wrapper.so'

echo "[5/5] 重启后验证"
cat <<'TIP'

  重启设备，然后运行:
      ./diagnose-volte.sh

  预期变化:
      IMS 进程                存在（此前 app=null + Restarting）
      ImsRegistrationTechnology   0（此前 -1）
      拨号走的通道             ImsPhoneCallTracker（此前 dialGsm）
TIP
