#!/bin/bash
# open_in_player.sh — 把转换好的 mp3 交给本地音乐 App（video2mp3.sh / media2mp3.sh 共用）
#
# Usage: open_in_player.sh <file.mp3>
#
# Env:
#   VIDEO2MP3_ACTION  auto(默认) | play | open | none
#       auto — 智能模式：QQ音乐没在运行 → play（队列本来是空的，自动播放+自动入库）；
#              QQ音乐正在运行 → open（弹窗让你选：直接播=替换队列 / 稍后听=进「本地歌曲」）。
#              网易云两种情形都不清队列，总是 play
#       play — 总是自动播放。注意：QQ音乐会用这首歌替换当前播放队列
#       open — 总是不动播放队列（QQ音乐会弹窗让你当场决定；输出目录由
#              setup_qqmusic_monitor.sh 自动写入「本地歌曲」监控，无需手动配置）
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
  # open 模式：不清队列。
  # QQ音乐：弹窗让用户当场决定（闭环，不再静默）——「直接播放」替换队列立刻听；
  # 「稍后听」/45 秒无操作/弹窗失败 → 不抢焦点，只发通知，歌已在「本地歌曲」等用户点
  if [ "$PLAYER" = "QQMusic" ]; then
    CHOICE=$(osascript - "$(basename "$MP3" .mp3)" <<'APPLESCRIPT' 2>/dev/null || echo "later"
on run argv
  try
    set r to display dialog "转换完成：" & item 1 of argv & return & return & "QQ音乐正在播放你队列里的歌。两个选择：" & return & return & "▶ 直接播放 —— 马上听这首，但当前队列会被清空替换成它" & return & "♡ 稍后听 —— 不打断现在的播放；这首已放进「本地歌曲」，随时可点" buttons {"稍后听", "直接播放"} default button "稍后听" giving up after 45
    if gave up of r then
      return "later"
    else
      return button returned of r
    end if
  on error
    return "later"
  end try
end run
APPLESCRIPT
)
    if [ "$CHOICE" = "直接播放" ]; then
      echo ">> 已切换：QQ音乐正在播放（当前队列被这首歌替换）"
      open -a QQMusic "$MP3"
      exit 0
    fi
    echo ">> 歌已在 QQ音乐「本地歌曲」（监控目录自动导入），当前队列未动，想听点开即可"
  else
    echo ">> 激活 ${PLAYER:-系统}（不替换播放队列）"
  fi
  # 通知以播放器名义发（兜底 Finder）：直接 osascript 会以 "Script Editor" 名义弹，
  # 用户没给它开通知权限就根本看不到。文件名和 App 名都走 argv，不拼进源码
  NOTIFY_VIA="$PLAYER"
  [ -n "$NOTIFY_VIA" ] || NOTIFY_VIA="Finder"
  osascript - "$NOTIFY_VIA" "$(basename "$MP3")" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  tell application (item 1 of argv) to display notification (item 2 of argv) with title "video2mp3 转换完成" sound name "Glass"
end run
APPLESCRIPT
  if [ "$PLAYER" != "QQMusic" ]; then
    if [ -n "$PLAYER" ]; then open -a "$PLAYER"; else open -R "$MP3"; fi
  fi
fi
