#!/bin/bash
# bilibili2mp3.sh — 哔哩哔哩视频链接 → 本地 mp3 → 用本地音乐 App 打开播放
#
# Usage:
#   bilibili2mp3.sh <链接或完整分享文本> [输出目录]
#
# 支持：bilibili.com/video/BVxxx、b23.tv 短链、裸 BV 号、av 号、?p=N 选集
#
# 原理：B 站官方 API（view + playurl）匿名可取到 DASH 音轨，无需 yt-dlp/浏览器/登录。
# 注意：api.bilibili.com 按 TLS 指纹风控——浏览器 UA + curl 指纹会被 412，
#       裸 curl（默认 UA）反而稳定 200，所以这里不要加 -H "User-Agent: ..."。
#
# Env: 同 video2mp3.sh（VIDEO2MP3_DIR / VIDEO2MP3_ACTION / VIDEO2MP3_PLAYER）

set -euo pipefail

INPUT="${1:?Usage: bilibili2mp3.sh <url-or-share-text> [output-dir]}"
OUTDIR="${2:-${VIDEO2MP3_DIR:-$HOME/Music/video2mp3}}"
mkdir -p "$OUTDIR"

command -v curl >/dev/null || { echo "ERROR: 需要 curl" >&2; exit 1; }
command -v node >/dev/null || { echo "ERROR: 需要 node (brew install node)" >&2; exit 1; }

# 从分享文本中提取第一个 URL
URL=$(printf '%s' "$INPUT" | grep -oE 'https?://[^[:space:]"'"'"'<>，。)）]+' | head -n1 || true)

# b23.tv 短链：跟随 302 拿到真实地址
if [[ "${URL:-}" == *b23.tv* ]]; then
  URL=$(curl -sfS -L --max-redirs 5 -o /dev/null -w '%{url_effective}' "$URL") || { echo "ERROR: b23.tv 短链解析失败: $URL" >&2; exit 1; }
fi

# BV 号：优先从 URL 取，其次允许用户直接给裸 BV 号（分享文本里也常出现）
BVID=$(printf '%s\n%s' "${URL:-}" "$INPUT" | grep -oE 'BV[0-9A-Za-z]{10}' | head -n1 || true)
AID=""
if [ -z "${BVID:-}" ]; then
  AID=$(printf '%s' "${URL:-}$INPUT" | grep -oE 'av([0-9]+)' | head -n1 | tr -d 'av' || true)
fi
if [ -z "${BVID:-}" ] && [ -z "${AID:-}" ]; then
  echo "ERROR: 输入中没有找到 BV 号 / av 号 / bilibili 链接: $INPUT" >&2
  exit 1
fi

# 选集：URL 里的 ?p=N（默认第 1 P）
PAGE=$(printf '%s' "${URL:-}" | grep -oE '[?&]p=[0-9]+' | head -n1 | grep -oE '[0-9]+' || true)
PAGE=${PAGE:-1}

# --- view API：拿标题/UP主/cid ---
if [ -n "${BVID:-}" ]; then VIEW_API="https://api.bilibili.com/x/web-interface/view?bvid=$BVID"
else VIEW_API="https://api.bilibili.com/x/web-interface/view?aid=$AID"; fi
echo ">> 解析视频信息: ${BVID:-av$AID} (P$PAGE)"
VIEW=$(curl -sfS "$VIEW_API") || { echo "ERROR: view API 请求失败（网络或 B 站风控）" >&2; exit 1; }

META=$(printf '%s' "$VIEW" | node -e '
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (d.code !== 0) { console.error("ERROR: view API code=" + d.code + " " + (d.message||"")); process.exit(1); }
const v = d.data;
const p = Math.min(Math.max(parseInt(process.argv[1]) || 1, 1), v.pages.length);
const pg = v.pages[p - 1];
// 多分 P 时用分 P 标题，单 P 用视频标题
const title = v.pages.length > 1 ? `${v.title} P${p} ${pg.part}` : v.title;
console.log(JSON.stringify({ bvid: v.bvid, cid: pg.cid, title, author: (v.owner && v.owner.name) || "未知歌手" }));
' "$PAGE") || exit 1

BVID=$(printf '%s' "$META" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).bvid')
CID=$(printf '%s' "$META" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).cid')
TITLE=$(printf '%s' "$META" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).title')
AUTHOR=$(printf '%s' "$META" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).author')
echo ">> $TITLE — $AUTHOR"

# --- playurl API：拿 DASH 音轨（匿名可得 64k~192k，高码率/Hi-Res 需登录，这里不碰） ---
PLAY=$(curl -sfS -H "Referer: https://www.bilibili.com/" \
  "https://api.bilibili.com/x/player/playurl?bvid=$BVID&cid=$CID&fnval=16&fnver=0&fourk=1") \
  || { echo "ERROR: playurl API 请求失败" >&2; exit 1; }

AUDIO=$(printf '%s' "$PLAY" | node -e '
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
if (d.code !== 0) { console.error("ERROR: playurl API code=" + d.code + " " + (d.message||"")); process.exit(1); }
const auds = (d.data.dash && d.data.dash.audio) || [];
if (auds.length) { console.log(auds.reduce((a, b) => a.bandwidth > b.bandwidth ? a : b).baseUrl); }
else if (d.data.durl && d.data.durl.length) { console.log(d.data.durl[0].url); }  // 老视频无 DASH 时回退 mp4
else { console.error("ERROR: 没有可用音轨（可能是付费/会员专享视频）"); process.exit(1); }
') || exit 1

# 交给共用下载转码脚本（带 Referer，CDN 必需）
"$(dirname "$0")/media2mp3.sh" "$AUDIO" "https://www.bilibili.com/" "$TITLE" "$AUTHOR" "$OUTDIR"
