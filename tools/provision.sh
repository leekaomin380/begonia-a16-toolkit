#!/usr/bin/env bash
# 刷机后的一次性配置。把「决定」固化成可执行序列 —— 文档能记录知识，
# 但记录不了「你想要什么」。
#
# 用法:
#   ./provision.sh                 执行全部阶段
#   ./provision.sh apps media bcr  只执行指定阶段
#   ./provision.sh --list          列出所有阶段
#
# 阶段:
#   prefs   系统偏好（关闭 adb 授权超时等）
#   debloat 移除不需要的预装应用
#   apps    安装微信 / Google 时钟
#   media   导入 Pixel 铃声与壁纸
#   bcr     安装并配置 BCR 自动通话录音（需要 root）
set -uo pipefail

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*"; exit 1; }
stage(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }

PIXEL_DUMP=gm-stuffs/google_husky_dump
PIXEL_BRANCH=husky-user-14-AP2A.240705.005-11942872-release-keys

# ---------------------------------------------------------------- 前置检查
preflight() {
  command -v adb >/dev/null || die "未找到 adb（brew install android-platform-tools）"
  adb get-state >/dev/null 2>&1 || die "设备未连接或未授权 USB 调试"
  local dev; dev=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
  [ "$dev" = "begonia" ] || warn "机型是 $dev，不是 begonia —— 请自行确认适用性"
  ok "设备: $dev / Android $(adb shell getprop ro.build.version.release | tr -d '\r')"
}

# ---------------------------------------------------------------- 系统偏好
do_prefs() {
  stage "系统偏好"
  # adb 授权默认 7 天过期，过期后每次重启都要在手机上重新确认。置 0 = 永不过期。
  adb shell settings put global adb_allowed_connection_time 0 && ok "已关闭 adb 授权超时"
}

# ---------------------------------------------------------------- 移除应用
# 用 `pm uninstall --user 0`：只对当前用户卸载，不动 /system，
# 随时可用 `cmd package install-existing <pkg>` 恢复。
REMOVE=(
  org.lunaris.dolby              # Dolby Atmos
  com.android.fmradio            # FM 电台
  com.android.fmradio.recordings # FM 电台录音
  com.android.deskclock          # 系统时钟（由 Google 时钟取代）
)
# 【踩过的坑】不要移除 org.lineageos.twelve —— 它是系统里唯一的音频播放器，
# 移除后无法播放 BCR 的 .oga 通话录音。本次曾误删并装回。
KEEP_GUARD=(org.lineageos.twelve)

do_debloat() {
  stage "移除预装应用"
  for p in "${REMOVE[@]}"; do
    if adb shell "pm list packages 2>/dev/null" | grep -q "^package:$p$"; then
      r=$(adb shell "pm uninstall --user 0 $p" 2>&1 | tr -d '\r')
      [ "$r" = "Success" ] && ok "已移除 $p" || warn "$p -> $r"
    else
      ok "$p 本就不存在，跳过"
    fi
  done
  for p in "${KEEP_GUARD[@]}"; do
    adb shell "pm list packages 2>/dev/null" | grep -q "^package:$p$" \
      && ok "保留 $p（音频播放器，勿删）" \
      || { warn "$p 缺失，正在恢复"; adb shell "cmd package install-existing $p"; }
  done
}

# ---------------------------------------------------------------- 安装应用
do_apps() {
  stage "安装应用"

  # 微信：从腾讯官方页面动态解析 arm64 直链（版本会变，不写死）
  local url
  url=$(curl -s -m 30 -A "Mozilla/5.0 (Linux; Android 11)" https://weixin.qq.com/ \
        | grep -oE 'https://[a-z0-9.]*qq\.com/weixin/android/[^"]*arm64[^"]*\.apk' \
        | sort -u | tail -1)
  if [ -n "$url" ]; then
    echo "  下载微信: $url"
    curl -sL -m 900 "$url" -o "$WORK/wechat.apk" \
      && adb install -r "$WORK/wechat.apk" >/dev/null 2>&1 \
      && ok "微信已安装" || warn "微信安装失败"
  else
    warn "未能从 weixin.qq.com 解析出 arm64 直链，跳过"
  fi

  # Google 时钟：取自 Pixel 8 Pro 官方固件转储
  local capk
  capk=$(curl -s -m 30 "https://api.github.com/repos/$PIXEL_DUMP/contents/product/app/PrebuiltDeskClockGoogle?ref=$PIXEL_BRANCH" \
         | python3 -c "import sys,json;print(next((f['download_url'] for f in json.load(sys.stdin) if f['name'].endswith('.apk')),''))" 2>/dev/null)
  if [ -n "$capk" ]; then
    curl -sL -m 600 "$capk" -o "$WORK/clock.apk" \
      && adb install -r "$WORK/clock.apk" >/dev/null 2>&1 \
      && ok "Google 时钟已安装" || warn "Google 时钟安装失败"
  else
    warn "未能定位 Google 时钟 APK，跳过"
  fi
}

# ---------------------------------------------------------------- 素材
do_media() {
  stage "导入 Pixel 铃声与壁纸"

  # 铃声：转储里是散文件，直接逐个取
  mkdir -p "$WORK/ring"
  curl -s -m 60 "https://api.github.com/repos/$PIXEL_DUMP/contents/product/media/audio/ringtones?ref=$PIXEL_BRANCH" \
    | python3 -c "
import sys,json
for f in json.load(sys.stdin):
    if f['name'].lower().endswith(('.ogg','.mp3','.m4a')): print(f['download_url'])
" > "$WORK/ring_urls.txt" 2>/dev/null
  if [ -s "$WORK/ring_urls.txt" ]; then
    (cd "$WORK/ring" && while read -r u; do curl -sL -m 120 -O "$u"; done < "$WORK/ring_urls.txt")
    adb shell mkdir -p /sdcard/Ringtones >/dev/null 2>&1
    adb push "$WORK"/ring/*.ogg /sdcard/Ringtones/ >/dev/null 2>&1 \
      && ok "铃声 $(ls "$WORK/ring" | wc -l | tr -d ' ') 首已导入" || warn "铃声导入失败"
  else
    warn "未能列出铃声目录，跳过"
  fi

  # 壁纸：打包在 APK 里，需解包；真正的壁纸是 res/drawable 下 >100KB 的图
  local wapk
  wapk=$(curl -s -m 30 "https://api.github.com/repos/$PIXEL_DUMP/contents/product/app/PixelWallpapers2023?ref=$PIXEL_BRANCH" \
         | python3 -c "import sys,json;print(next((f['download_url'] for f in json.load(sys.stdin) if f['name'].endswith('.apk')),''))" 2>/dev/null)
  if [ -n "$wapk" ]; then
    curl -sL -m 900 "$wapk" -o "$WORK/wp.apk"
    mkdir -p "$WORK/wp" && unzip -o -q "$WORK/wp.apk" 'res/*' -d "$WORK/wp" 2>/dev/null
    mkdir -p "$WORK/wpout"
    find "$WORK/wp" -type f \( -iname '*.webp' -o -iname '*.jpg' -o -iname '*.png' \) -size +100k \
      -exec cp {} "$WORK/wpout/" \; 2>/dev/null
    local n; n=$(ls "$WORK/wpout" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" -gt 0 ]; then
      adb shell mkdir -p /sdcard/Pictures/PixelWallpapers >/dev/null 2>&1
      adb push "$WORK/wpout/." /sdcard/Pictures/PixelWallpapers/ >/dev/null 2>&1 \
        && ok "壁纸 $n 张已导入" || warn "壁纸导入失败"
    else
      warn "APK 内未找到壁纸图片"
    fi
  else
    warn "未能定位壁纸 APK，跳过"
  fi

  adb shell 'content call --uri content://media/external/audio/media --method scan_volume' >/dev/null 2>&1
  adb shell 'content call --uri content://media/external/images/media --method scan_volume' >/dev/null 2>&1
  ok "已触发媒体库扫描"
}

# ---------------------------------------------------------------- BCR
do_bcr() {
  stage "安装 BCR（自动通话录音）"
  adb root >/dev/null 2>&1; sleep 3
  [ "$(adb shell id -u 2>/dev/null | tr -d '\r')" = "0" ] \
    || die "需要 root。请在 设置->系统->开发者选项 中开启「Root 身份的调试」（LineageOS 自带，非 Magisk）"
  adb remount >/dev/null 2>&1 || adb shell mount -o rw,remount /

  local url
  url=$(curl -s -m 30 https://api.github.com/repos/chenxiaolong/BCR/releases/latest \
        | python3 -c "import sys,json;print(next((a['browser_download_url'] for a in json.load(sys.stdin)['assets'] if a['name'].endswith('release.zip')),''))" 2>/dev/null)
  [ -n "$url" ] || die "未能取得 BCR 发布地址"
  curl -sL -m 600 "$url" -o "$WORK/bcr.zip" || die "BCR 下载失败"
  unzip -o -q "$WORK/bcr.zip" -d "$WORK/bcr"

  # BCR 的模块包本质是一个 /system 覆盖层，不需要 Magisk 运行时
  adb shell 'mkdir -p /system/priv-app/com.chiller3.bcr'
  adb push "$WORK/bcr/system/priv-app/com.chiller3.bcr/app-release.apk" \
           /system/priv-app/com.chiller3.bcr/ >/dev/null
  adb push "$WORK/bcr/system/etc/permissions/privapp-permissions-com.chiller3.bcr.xml" \
           /system/etc/permissions/ >/dev/null
  adb shell '
    chmod 755 /system/priv-app/com.chiller3.bcr
    chmod 644 /system/priv-app/com.chiller3.bcr/app-release.apk \
              /system/etc/permissions/privapp-permissions-com.chiller3.bcr.xml
    chown -R root:root /system/priv-app/com.chiller3.bcr \
                       /system/etc/permissions/privapp-permissions-com.chiller3.bcr.xml
    chcon u:object_r:system_file:s0 /system/priv-app/com.chiller3.bcr
    chcon u:object_r:system_file:s0 /system/priv-app/com.chiller3.bcr/app-release.apk
    chcon u:object_r:system_file:s0 /system/etc/permissions/privapp-permissions-com.chiller3.bcr.xml'
  ok "BCR 已安装到 /system/priv-app"

  echo "  重启以让 PackageManager 扫描并授予特权权限..."
  adb reboot
  until adb devices 2>/dev/null | grep -qE "	device$"; do sleep 5; done
  until adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do sleep 5; done

  for p in RECORD_AUDIO READ_PHONE_STATE READ_CALL_LOG READ_CONTACTS POST_NOTIFICATIONS; do
    adb shell "pm grant com.chiller3.bcr android.permission.$p" >/dev/null 2>&1
  done
  if adb shell 'dumpsys package com.chiller3.bcr 2>/dev/null' | grep -q "CAPTURE_AUDIO_OUTPUT: granted=true"; then
    ok "特权权限已授予（CAPTURE_AUDIO_OUTPUT —— 录到对方声音的前提）"
  else
    warn "CAPTURE_AUDIO_OUTPUT 未授予，录音将只有本机麦克风一路"
  fi
  cat <<'TIP'

  仍需手动完成一步（SAF 目录授权无法脚本化）：
    打开 BCR -> 保存目录 -> 选择 Recordings/Call recordings -> 允许
    否则录音会落在应用私有目录，文件管理器里看不到。
TIP
}

# ---------------------------------------------------------------- 主流程
ALL=(prefs debloat apps media bcr)
[ "${1:-}" = "--list" ] && { printf '%s\n' "${ALL[@]}"; exit 0; }
STAGES=("$@"); [ ${#STAGES[@]} -eq 0 ] && STAGES=("${ALL[@]}")

preflight
for s in "${STAGES[@]}"; do
  case "$s" in
    prefs) do_prefs ;; debloat) do_debloat ;; apps) do_apps ;;
    media) do_media ;; bcr) do_bcr ;;
    *) warn "未知阶段: $s" ;;
  esac
done
printf '\n\033[1m完成。\033[0m BCR 的保存目录仍需手动授权（见上）。\n'
