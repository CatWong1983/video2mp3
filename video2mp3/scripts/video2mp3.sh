#!/bin/bash
# video2mp3.sh — 抖音/小红书视频链接 → 本地 mp3 → 用本地音乐 App 打开播放
#
# Usage:
#   video2mp3.sh <链接或完整分享文本> [输出目录]
#
# Env overrides:
#   VIDEO2MP3_DIR     默认输出目录 (default: ~/Music/video2mp3)
#   VIDEO2MP3_ACTION  open(默认,不动播放队列) / play(自动播放,会替换队列) / none(只保存)
#   VIDEO2MP3_PLAYER  指定播放器 App 名，如 "QQMusic" / "NetEase Cloud Music"

set -euo pipefail

INPUT="${1:?Usage: video2mp3.sh <url-or-share-text> [output-dir]}"
OUTDIR="${2:-${VIDEO2MP3_DIR:-$HOME/Music/video2mp3}}"
mkdir -p "$OUTDIR"

# 从分享文本中提取第一个 URL（抖音/小红书分享文本都内嵌链接）
URL=$(printf '%s' "$INPUT" | grep -oE 'https?://[^[:space:]"'"'"'<>，。)）]+' | head -n1 || true)
if [ -z "${URL:-}" ]; then
  echo "ERROR: 输入中没有找到 URL: $INPUT" >&2
  exit 1
fi
echo ">> URL: $URL"

command -v yt-dlp >/dev/null || { echo "ERROR: 需要 yt-dlp (brew install yt-dlp)" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ERROR: 需要 ffmpeg (brew install ffmpeg)" >&2; exit 1; }

# 下载最佳音轨 → 转 mp3 → 嵌入封面与歌手元数据
# --print after_move:filepath 让 yt-dlp 输出最终文件路径
if ! FILEPATH=$(yt-dlp \
  --no-playlist \
  --no-warnings \
  --retries 3 \
  -x --audio-format mp3 --audio-quality 0 \
  --embed-thumbnail --convert-thumbnails jpg \
  --embed-metadata \
  --parse-metadata "uploader:%(meta_artist)s" \
  -o "$OUTDIR/%(title).80B [%(id)s].%(ext)s" \
  --print after_move:filepath \
  "$URL" | tail -n1); then
  echo "ERROR: yt-dlp 下载失败。" >&2
  echo "提示: 抖音/小红书目前对 yt-dlp 有反爬限制，请改用浏览器抓包路径（见 SKILL.md Step 3），" >&2
  echo "      拿到媒体流地址后运行: media2mp3.sh <流URL> <referer> <标题> <作者>" >&2
  exit 1
fi

if [ -z "$FILEPATH" ] || [ ! -f "$FILEPATH" ]; then
  echo "ERROR: 下载或转码失败，未找到输出文件" >&2
  exit 1
fi
echo ">> MP3: $FILEPATH"

# 交给本地音乐 App（默认不动播放队列，详见 open_in_player.sh 头注释）
"$(dirname "$0")/open_in_player.sh" "$FILEPATH"
