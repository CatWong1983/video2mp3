#!/bin/bash
# setup_qqmusic_monitor.sh — 把输出目录写进 QQ音乐「本地歌曲」自动扫描配置（幂等）
#
# Usage: setup_qqmusic_monitor.sh [目录]   (默认 ${VIDEO2MP3_DIR:-~/Music/video2mp3})
#
# 原理：QQ音乐把监控目录存在偏好 LocalMusicMonitorConfig（NSKeyedArchiver blob）：
#   {supportType:1, durationType:0, pathWtihBookData: {路径: app-scope bookmark}}
# 本脚本用 swift 生成安全书签、python plistlib 改写 blob，defaults 写回。
# 已有其它目录会保留；QQ音乐运行中会先退出再写（否则偏好缓存会覆盖写入），写完自动重启。
#
# Env:
#   VIDEO2MP3_QQM_DOMAIN  偏好域（默认 com.tencent.QQMusicMac；测试时改成别的避免动真配置）

set -euo pipefail

DIR="${1:-${VIDEO2MP3_DIR:-$HOME/Music/video2mp3}}"
DOMAIN="${VIDEO2MP3_QQM_DOMAIN:-com.tencent.QQMusicMac}"
CACHE_DIR="$HOME/.video2mp3"
BM_BIN="$CACHE_DIR/bin/make_bookmark"

[ -d "/Applications/QQMusic.app" ] || { echo ">> 未安装 QQ音乐，跳过监控目录配置"; exit 0; }
mkdir -p "$DIR" "$CACHE_DIR/bin"

PLIST="$HOME/Library/Containers/$DOMAIN/Data/Library/Preferences/$DOMAIN.plist"
[ -f "$PLIST" ] || PLIST="$HOME/Library/Preferences/$DOMAIN.plist"

# --- 1. 已配置则直接返回 ---
if [ -f "$PLIST" ] && python3 - "$PLIST" "$DIR" <<'PYEOF'; then
import plistlib, sys
try:
    blob = plistlib.load(open(sys.argv[1], "rb")).get("LocalMusicMonitorConfig")
    if not blob: sys.exit(1)
    objs = plistlib.loads(blob)["$objects"]
    sys.exit(0 if sys.argv[2] in [o for o in objs if isinstance(o, str)] else 1)
except Exception:
    sys.exit(1)
PYEOF
  echo ">> QQ音乐本地歌曲监控目录已包含 ${DIR}，无需配置"
  exit 0
fi

echo ">> 首次配置：把 $DIR 写入 QQ音乐「本地歌曲」自动扫描..."

# --- 2. swift 生成 app-scope 安全书签（编译一次缓存到 ~/.video2mp3/bin） ---
if [ ! -x "$BM_BIN" ]; then
  cat > "$CACHE_DIR/make_bookmark.swift" <<'SWEOF'
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let d = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
FileHandle.standardOutput.write(d.base64EncodedData())
SWEOF
  swiftc -O -o "$BM_BIN" "$CACHE_DIR/make_bookmark.swift" 2>/dev/null || {
    echo ">> swiftc 不可用（需 Xcode CLT: xcode-select --install），跳过自动配置" >&2
    echo ">> 请手动：QQ音乐「本地歌曲」→「添加本地歌曲文件夹」→ 选 $DIR" >&2
    exit 0
  }
fi
BOOKMARK=$("$BM_BIN" "$DIR")

# --- 3. 改写 blob：保留已有目录，追加新 {路径: 书签} ---
HEX=$(python3 - "$PLIST" "$DIR" "$BOOKMARK" <<'PYEOF'
import plistlib, sys, os, base64
plist_path, path, bm = sys.argv[1], sys.argv[2], base64.b64decode(sys.argv[3])
blob = None
if os.path.exists(plist_path):
    blob = plistlib.load(open(plist_path, "rb")).get("LocalMusicMonitorConfig")
if blob:
    pl = plistlib.loads(blob)
else:
    # QQ音乐从未配置过监控目录：从零构建 NSKeyedArchiver 骨架（与原生结构同构）
    U = plistlib.UID
    pl = {"$archiver": "NSKeyedArchiver", "$version": 100000, "$top": {"root": U(1)},
          "$objects": ["$null",
            {"$class": U(4), "durationType": 0, "pathWtihBookData": U(2), "supportType": 1},
            {"$class": U(3), "NS.keys": [], "NS.objects": []},
            {"$classes": ["NSMutableDictionary", "NSDictionary", "NSObject"], "$classname": "NSMutableDictionary"},
            {"$classes": ["LocalMusicMonitorConfig", "NSObject"], "$classname": "LocalMusicMonitorConfig"}]}
objs = pl["$objects"]
d = next(o for o in objs if isinstance(o, dict) and "NS.keys" in o)
objs.append(path)
objs.append(bm)
d["NS.keys"].append(plistlib.UID(len(objs) - 2))
d["NS.objects"].append(plistlib.UID(len(objs) - 1))
print(plistlib.dumps(pl, fmt=plistlib.FMT_BINARY).hex())
PYEOF
) || { echo ">> 配置解析失败，跳过自动配置（不影响听歌）" >&2; exit 0; }

# --- 4. 写回偏好。QQ音乐运行中必须先退出，否则退出时缓存回写会覆盖本次修改 ---
WAS_RUNNING=0
if [ "$DOMAIN" = "com.tencent.QQMusicMac" ] && pgrep -f "/Applications/QQMusic.app" >/dev/null 2>&1; then
  echo ">> 重启 QQ音乐以使配置生效（约几秒）..."
  osascript -e 'quit app "QQMusic"' 2>/dev/null || true
  for i in $(seq 1 20); do pgrep -f "/Applications/QQMusic.app" >/dev/null 2>&1 || break; sleep 0.5; done
  WAS_RUNNING=1
fi

# 写之前备份原 plist：万一 QQ音乐读不懂改后的结构，
# 可用 cp 备份文件还原（QQ音乐未运行时覆盖回去即可）
if [ -f "$PLIST" ]; then
  mkdir -p "$CACHE_DIR/backups"
  cp "$PLIST" "$CACHE_DIR/backups/$DOMAIN.plist.$(date +%Y%m%d%H%M%S)"
fi

defaults write "$DOMAIN" LocalMusicMonitorConfig -data "$HEX"
echo ">> 已配置：QQ音乐会自动扫描 ${DIR}，新歌直接出现在「本地歌曲」"

[ "$WAS_RUNNING" = 1 ] && open -a QQMusic
exit 0
