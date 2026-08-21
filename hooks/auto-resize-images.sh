#!/usr/bin/env bash
# Pre-hook for Read tool: auto-resize images > 2000px
# Uses ffmpeg for size detection and resizing

FFMPEG="$HOME/.local/bin/ffmpeg"
MAX_PX=2000

input=$(cat)

file_path=$(echo "$input" | grep -oP '"file_path"\s*:\s*"[^"]*"' | head -1 | grep -oP ':\s*"\K[^"]+')
[ -z "$file_path" ] && exit 0

case "${file_path,,}" in
  *.png|*.jpg|*.jpeg|*.webp|*.gif|*.bmp|*.tiff|*.tif) ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

dims=$("$FFMPEG" -i "$file_path" 2>&1 | grep -oP '\d{2,5}x\d{2,5}' | head -1)
[ -z "$dims" ] && exit 0

width=${dims%%x*}
height=${dims##*x}

[ "$width" -le "$MAX_PX" ] && [ "$height" -le "$MAX_PX" ] && exit 0

# 원본 덮어쓰기 (사본/캐시 불필요)
if [ "$width" -ge "$height" ]; then
  scale="scale=${MAX_PX}:-2"
else
  scale="scale=-2:${MAX_PX}"
fi

TMP="${file_path}.tmp.${file_path##*.}"
"$FFMPEG" -i "$file_path" -vf "$scale" -update 1 -y "$TMP" 2>/dev/null
if [ -f "$TMP" ]; then
  mv "$TMP" "$file_path"
fi
exit 0
