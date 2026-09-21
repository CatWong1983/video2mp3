#!/bin/bash
# media2mp3.sh — 直接媒体流地址（浏览器抓包得到）→ 本地 mp3 → 用本地音乐 App 打开播放
#
# Usage:
#   media2mp3.sh <media_url> <referer> <title> <artist> [输出目录]
#
# 例:
#   media2mp3.sh 'https://v5-...zjcdn.com/...' 'https://www.douyin.com/' '歌名' '博主名'
#
# Env:
#   VIDEO2MP3_DIR     默认输出目录 (default: ~/Music/video2mp3)
#   VIDEO2MP3_ACTION  open(默认,不动播放队列) / play(自动播放,会替换队列) / none(只保存)
#   VIDEO2MP3_PLAYER  播放器 App 名 ("QQMusic" / "NetEase Cloud Music")

set -euo pipefail

MEDIA_URL="${1:?Usage: media2mp3.sh <media_url> <referer> <title> <artist> [output-dir]}"
REFERER="${2:?missing referer, e.g. https://www.douyin.com/}"
TITLE="${3:?missing title}"
ARTIST="${4:-未知歌手}"
OUTDIR="${5:-${VIDEO2MP3_DIR:-$HOME/Music/video2mp3}}"
mkdir -p "$OUTDIR"

command -v ffmpeg >/dev/null || { echo "ERROR: 需要 ffmpeg (brew install ffmpeg)" >&2; exit 1; }

# 文件名清洗：去掉 / \ : 等非法字符
SAFE=$(printf '%s - %s' "$ARTIST" "$TITLE" | tr '/\\:*?"<>|' '--------' | cut -c1-120)
TMP=$(mktemp -t video2mp3).bin
trap 'rm -f "$TMP"' EXIT

echo ">> 下载媒体流..."
curl -sfS -H "Referer: $REFERER" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" -o "$TMP" "$MEDIA_URL"

MP3="$OUTDIR/$SAFE.mp3"
echo ">> 转码 mp3: $MP3"
ffmpeg -y -loglevel error -i "$TMP" -vn -codec:a libmp3lame -q:a 2 \
  -metadata title="$TITLE" -metadata artist="$ARTIST" "$MP3"

echo ">> MP3: $MP3"

# 交给本地音乐 App（默认不动播放队列，详见 open_in_player.sh 头注释）
"$(dirname "$0")/open_in_player.sh" "$MP3"
