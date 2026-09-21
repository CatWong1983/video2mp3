#!/bin/bash
# make_lyrics.sh — 用 whisper.cpp 转录音频，生成同名 .lrc 滚动歌词
# QQ音乐会自动加载同目录同名 .lrc（已实测：播放页滚动歌词正常）；
# 已有 .lrc 时不覆盖。任何失败都只告警不阻塞主流程。
#
# Usage: make_lyrics.sh <file.mp3>
#
# Env:
#   VIDEO2MP3_LYRICS        1(默认)生成 / 0 关闭
#   VIDEO2MP3_WHISPER_MODEL 模型路径（默认 ~/.video2mp3/models/ggml-small.bin，缺失自动下载）
#   VIDEO2MP3_WHISPER_LANG  识别语言（默认 zh）

set -euo pipefail

MP3="${1:?Usage: make_lyrics.sh <file.mp3>}"
LRC="${MP3%.*}.lrc"

[ "${VIDEO2MP3_LYRICS:-1}" = "0" ] && exit 0
[ -s "$LRC" ] && exit 0

if ! command -v whisper-cli >/dev/null; then
  echo ">> 未安装 whisper-cli（brew install whisper-cpp），跳过歌词" >&2
  exit 0
fi

MODEL="${VIDEO2MP3_WHISPER_MODEL:-$HOME/.video2mp3/models/ggml-small.bin}"
if [ ! -f "$MODEL" ]; then
  echo ">> 首次生成歌词：下载 whisper small 模型（约 460MB，一次性）..."
  mkdir -p "$(dirname "$MODEL")"
  if ! curl -sfSL -o "$MODEL" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"; then
    rm -f "$MODEL"
    echo ">> 模型下载失败，跳过歌词（可设 VIDEO2MP3_WHISPER_MODEL 指向已有模型）" >&2
    exit 0
  fi
fi

echo ">> 生成歌词（whisper 转录）..."
if whisper-cli -m "$MODEL" -l "${VIDEO2MP3_WHISPER_LANG:-zh}" -olrc -of "${MP3%.*}" -f "$MP3" >/dev/null 2>&1 && [ -s "$LRC" ]; then
  echo ">> 歌词: $LRC"
else
  rm -f "$LRC"
  echo ">> 歌词生成失败（不影响 mp3 本身）" >&2
fi
