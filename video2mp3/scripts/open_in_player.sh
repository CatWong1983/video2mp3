#!/bin/bash
# open_in_player.sh — 把转换好的 mp3 交给本地音乐 App（video2mp3.sh / media2mp3.sh 共用）
#
# Usage: open_in_player.sh <file.mp3>
#
# Env:
#   VIDEO2MP3_ACTION  open(默认) | play | none
#       open — 只激活音乐 App 窗口并发通知，不动当前播放队列（推荐；
#              前提是把输出目录加进了 QQ音乐 本地歌曲，见 SKILL.md）
#       play — 自动播放该文件。注意：QQ音乐会用这首歌替换当前播放队列
#       none — 什么都不做，只保存文件
#   VIDEO2MP3_PLAYER  强制指定 App 名，如 "QQMusic" / "NetEase Cloud Music"

set -euo pipefail

MP3="${1:?Usage: open_in_player.sh <file.mp3>}"
ACTION="${VIDEO2MP3_ACTION:-open}"
PLAYER="${VIDEO2MP3_PLAYER:-auto}"
[ "$PLAYER" = "none" ] && ACTION="none"  # 兼容旧的 VIDEO2MP3_PLAYER=none 用法

if [ "$ACTION" = "none" ]; then
  echo ">> 已保存（VIDEO2MP3_ACTION=none，不打开播放器）"
  exit 0
fi

if [ "$PLAYER" = "auto" ]; then
  if [ -d "/Applications/QQMusic.app" ]; then PLAYER="QQMusic"
  elif [ -d "/Applications/NetEase Cloud Music.app" ]; then PLAYER="NetEase Cloud Music"
  elif [ -d "/Applications/NeteaseMusic.app" ]; then PLAYER="NeteaseMusic"
  else PLAYER=""; fi
fi

# 网易云 open 文件不清播放队列（实测），open 模式直接升级为 play
if [ "$ACTION" = "open" ] && [[ "$PLAYER" == *NetEase* || "$PLAYER" == *Netease* ]]; then
  ACTION="play"
fi

if [ "$ACTION" = "play" ]; then
  if [ -n "$PLAYER" ]; then
    if [ "$PLAYER" = "QQMusic" ]; then
      echo ">> 用 QQMusic 播放（注意：会替换当前播放队列）..."
    else
      echo ">> 用 ${PLAYER} 播放..."
    fi
    open -a "$PLAYER" "$MP3"
  else
    echo ">> 未检测到 QQ 音乐/网易云，用系统默认播放器打开"
    open "$MP3"
  fi
else
  # open 模式：不清队列，激活窗口 + 通知
  osascript -e "display notification \"$(basename "$MP3")\" with title \"video2mp3 转换完成\" sound name \"Glass\"" 2>/dev/null || true
  if [ -n "$PLAYER" ]; then
    echo ">> 激活 ${PLAYER}（不替换播放队列；歌曲已存入曲库目录，在「本地歌曲」中播放）"
    open -a "$PLAYER"
  else
    open -R "$MP3"
  fi
fi
