#!/usr/bin/env bash
# 从 GitHub 上的固件转储仓库按路径取单个文件。
#
# 为什么需要它：补一个缺失的私有库只要几十 KB，没必要下载 4GB 官方固件包。
#
# 用法:
#   ./extract-blob.sh <owner/repo> <branch> <path/in/repo> [输出文件]
# 例:
#   ./extract-blob.sh ZyCromerZ/redmi_begonia_dump \
#       begonia-user-11-RP1A.200720.011-V12.5.3.0.RGGIDXM-release-keys \
#       system/system/lib64/libmtk_vt_wrapper.so
set -euo pipefail
[ $# -ge 3 ] || { sed -n '2,12p' "$0"; exit 1; }
REPO=$1; BRANCH=$2; RPATH=$3; OUT=${4:-$(basename "$RPATH")}
URL="https://raw.githubusercontent.com/$REPO/$BRANCH/$RPATH"
echo "取: $URL"
curl -fsSL -o "$OUT" "$URL" || { echo "下载失败 —— 检查仓库/分支/路径"; exit 1; }
# 转储仓库对不存在的路径会返回 HTML/文本，务必校验类型
TYPE=$(file -b "$OUT")
echo "得到: $OUT ($(wc -c < "$OUT") bytes)"
echo "类型: $TYPE"
case "$TYPE" in
  *ELF*|*Android*|*Zip*|*data*) ;;
  *) echo "警告: 看起来不是二进制文件，很可能是 404 页面" >&2; exit 2;;
esac
