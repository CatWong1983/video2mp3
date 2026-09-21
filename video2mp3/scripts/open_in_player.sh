#!/bin/bash
# open_in_player.sh — 把转换好的 mp3 交给本地音乐 App（video2mp3.sh / media2mp3.sh 共用）
#
# Usage: open_in_player.sh <file.mp3>
#
# Env:
#   VIDEO2MP3_ACTION  auto(默认) | play | open | none
#       auto — 智能模式：QQ音乐没在运行 → play（队列本来是空的，自动播放+自动入库）；
#              QQ音乐正在运行 → open（你排的播放队列原样保留，只激活窗口+通知，
#              新歌在「本地歌曲」里点一下就听）。网易云两种情形都不清队列，总是 play
#       play — 总是自动播放。注意：QQ音乐会用这首歌替换当前播放队列
#       open — 总是只激活窗口+通知，不动播放队列
#              （QQ音乐此模式不会自动导入曲库，需手动添加文件夹，见 SKILL.md）
#       none — 什么都不做，只保存文件
#   VIDEO2MP3_PLAYER  强制指定 App 名，如 "QQMusic" / "NetEase Cloud Music"

set -euo pipefail

MP3="${1:?Usage: open_in_player.sh <file.mp3>}"
ACTION="${VIDEO2MP3_ACTION:-auto}"
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

# auto 智能模式：QQ音乐正在运行时 open -a 会用新歌替换用户排好的播放队列，
# 降级为 open（弹窗让用户当场决定：直接播 or 稍后听）；QQ音乐没在跑则队列本来就空，直接 play
if [ "$ACTION" = "auto" ]; then
  if [ "$PLAYER" = "QQMusic" ] && pgrep -f "/Applications/QQMusic.app" >/dev/null 2>&1; then
    ACTION="open"
  else
    ACTION="play"
  fi
fi

# QQ音乐：确保输出目录已写入「本地歌曲」自动扫描配置（幂等；首次配置会重启一次 QQ音乐，
# 之后新歌落盘即出现在本地歌曲，用户零手动设置）
if [ "$PLAYER" = "QQMusic" ]; then
  "$(dirname "$0")/setup_qqmusic_monitor.sh" "$(dirname "$MP3")" || true
fi

# 网易云 open 文件不清播放队列（实测），open 模式直接升级为 play
if [ "$ACTION" = "open" ] && [[ "$PLAYER" == *NetEase* || "$PLAYER" == *Netease* ]]; then
  ACTION="play"
fi

if [ "$ACTION" = "play" ]; then
  if [ -n "$PLAYER" ]; then
    if [ "$PLAYER" = "QQMusic" ]; then
      echo ">> 用 QQMusic 播放（会替换当前播放队列；文件自动导入「本地歌曲」）..."
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
  # 通知以播放器名义发（兜底 Finder）：直接 osascript 会以 "Script Editor" 名义弹，
  # 其他用户没给它开通知权限就根本看不到。文件名和 App 名都走 argv，不拼进源码
  NOTIFY_VIA="$PLAYER"
  [ -n "$NOTIFY_VIA" ] || NOTIFY_VIA="Finder"
  osascript - "$NOTIFY_VIA" "$(basename "$MP3")" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  tell application (item 1 of argv) to display notification (item 2 of argv) with title "video2mp3 转换完成" sound name "Glass"
end run
APPLESCRIPT
  if [ -n "$PLAYER" ]; then
    echo ">> 激活 ${PLAYER}（不替换播放队列；歌曲已存入曲库目录，在「本地歌曲」中播放）"
    open -a "$PLAYER"
  else
    open -R "$MP3"
  fi
fi
