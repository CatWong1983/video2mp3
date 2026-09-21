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
#   VIDEO2MP3_ACTION  play(默认,自动播放) / open(只激活窗口,不动播放队列) / none(只保存)
#   VIDEO2MP3_PLAYER  播放器 App 名 ("QQMusic" / "NetEase Cloud Music")

set -euo pipefail

MEDIA_URL="${1:?Usage: media2mp3.sh <media_url> <referer> <title> <artist> [output-dir]}"
REFERER="${2:?missing referer, e.g. https://www.douyin.com/}"
TITLE="${3:?missing title}"
ARTIST="${4:-未知歌手}"
OUTDIR="${5:-${VIDEO2MP3_DIR:-$HOME/Music/video2mp3}}"
mkdir -p "$OUTDIR"

command -v ffmpeg >/dev/null || { echo "ERROR: 需要 ffmpeg (brew install ffmpeg)" >&2; exit 1; }

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

# 文件名清洗：去掉 / \ : 等非法字符。${var:0:120} 按字符截断（需 UTF-8 locale），
# 不要用 cut -c——C locale 下它按字节切，会把中文切成乱码
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
SAFE=$(printf '%s - %s' "$ARTIST" "$TITLE" | tr '/\\:*?"<>|' '--------')
SAFE=${SAFE:0:120}

TMP=$(mktemp -t video2mp3)
trap 'rm -f "$TMP"' EXIT

# 抖音 CDN 会中途断流（curl 18 partial file）。先 HEAD 拿 Content-Length，
# curl -C - 断点续传重试，最后校验字节数，残缺文件绝不交给 ffmpeg
echo ">> 下载媒体流..."
EXPECTED=$(curl -sfSI -H "Referer: $REFERER" -H "User-Agent: $UA" "$MEDIA_URL" 2>/dev/null | tr -d '\r' | awk 'tolower($1)=="content-length:" {print $2}' | tail -1 || true)
ok=0
for i in 1 2 3 4 5 6 7 8; do
  if curl -sfS -C - -H "Referer: $REFERER" -H "User-Agent: $UA" -o "$TMP" "$MEDIA_URL"; then ok=1; break; fi
  echo ">> 连接中断，断点续传 ($i/8)..." >&2
  sleep 1
done
# curl 退出码为 0 才算完整传完；8 次全断时即使留有部分内容也报错，
# 避免 HEAD 没返回 Content-Length 时残缺文件静默进入 ffmpeg（产出缺尾 mp3）
[ "$ok" = 1 ] || { echo "ERROR: 下载失败，重试 8 次均被 CDN 中断" >&2; exit 1; }
[ -s "$TMP" ] || { echo "ERROR: 下载失败" >&2; exit 1; }
SIZE=$(stat -f%z "$TMP" 2>/dev/null || stat -c%s "$TMP")
if [ -n "${EXPECTED:-}" ] && [ "$SIZE" != "$EXPECTED" ]; then
  echo "ERROR: 下载不完整（$SIZE/$EXPECTED 字节），重试次数已用尽" >&2
  exit 1
fi

# 防静音 mp3：抖音 MSE 音视频分离，若抓错成纯视频轨，-vn 会产出无声文件且不报错
if ! ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$TMP" 2>/dev/null | grep -q audio; then
  echo "ERROR: 下载到的媒体不含音频流（可能抓到了纯视频轨），已中止" >&2
  exit 1
fi

MP3="$OUTDIR/$SAFE.mp3"
echo ">> 转码 mp3: $MP3"
ffmpeg -y -loglevel error -i "$TMP" -vn -codec:a libmp3lame -q:a 2 \
  -metadata title="$TITLE" -metadata artist="$ARTIST" "$MP3"

echo ">> MP3: $MP3"

# 生成滚动歌词（同名 .lrc，QQ音乐自动加载；需在打开播放器前完成）
"$(dirname "$0")/make_lyrics.sh" "$MP3"

# 交给本地音乐 App（默认自动播放，详见 open_in_player.sh 头注释）
"$(dirname "$0")/open_in_player.sh" "$MP3"
