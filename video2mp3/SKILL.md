---
name: video2mp3
description: Use when the user shares a Douyin (抖音) or Xiaohongshu (小红书) video link/share text and wants to listen to it as music — extract the audio to a local mp3 and play it in a local music app (QQ音乐 / 网易云音乐). Triggers on v.douyin.com, douyin.com/video/, xiaohongshu.com/explore, xhslink.com links, or requests like "把这个视频转成mp3用QQ音乐听".
---

# video2mp3 — 视频链接 → 本地 mp3 → QQ 音乐/网易云播放

把抖音/小红书视频的音频保存为本地 mp3（带标题/歌手元数据），并用本地音乐 App 打开播放。

## 前提

- macOS；`node`(18+) 和 `ffmpeg` 必需，`yt-dlp` 可选（`brew install node ffmpeg yt-dlp`）
- 播放器：检测顺序 QQ音乐 → 网易云 → 系统默认。可用 `VIDEO2MP3_PLAYER=<App名>` 覆盖
- 输出目录默认 `~/Music/video2mp3`，可用 `VIDEO2MP3_DIR` 覆盖
- **一次性设置**：在 QQ音乐「本地歌曲」（或「本地与下载」）里选「手动添加 / 添加本地歌曲文件夹」，把 `~/Music/video2mp3` 加进去。之后转换的歌自动进曲库

## 播放行为（VIDEO2MP3_ACTION）

| 值 | 行为 |
|---|---|
| `open`（默认） | 只激活音乐 App 窗口 + 系统通知，**不动当前播放队列**；用户在「本地歌曲」里点播 |
| `play` | 自动播放。注意：QQ音乐会用这首歌**替换当前播放队列** |
| `none` | 只保存文件 |

## 流程

### Step 1: 提取 URL

分享文本中内嵌链接，取第一个 `https?://` URL（脚本已内置此逻辑）。短链（v.douyin.com / xhslink.com）无需手动展开。

### Step 2: 先试 yt-dlp 快路径

```bash
scripts/video2mp3.sh '<用户粘贴的分享文本或链接>'
```

- 成功即完成（自动转 mp3、嵌入封面/歌手、打开播放器）。
- **抖音目前报 "Fresh cookies are needed"、小红书报 "No video formats found" 均属预期**——yt-dlp 提取器对这两个站基本失效，直接走 Step 3，不要反复重试或升级 yt-dlp。

### Step 3: 浏览器抓包（抖音/小红书的主路径）

**首选：skill 自带抓包脚本，零 MCP 依赖**，模型只要能跑 node 即可（首次运行自动 `npm install playwright` + 下载 chromium，约 1-2 分钟）：

```bash
node scripts/capture_media.mjs '<视频页URL>'
# 输出 JSON: {"mediaUrl":"...","title":"...","author":"...","referer":"..."}
```

- 抖音：无头模式直接返回
- 小红书：未登录时页面渲染"安全限制"，但带 `xsec_token` 的分享链接通常仍能抓到媒体流——此时 JSON 带 `warning` 字段，title/author 不可信，**改用用户分享文本里的标题**。实在抓不到流时脚本才会弹出有头浏览器请用户扫码（最多等 10 分钟；持久 profile 在 `~/.video2mp3/browser-profile`，登录一次长期有效）

拿到 JSON 后下载转码（**Referer 必需，否则 CDN 403**）：

```bash
scripts/media2mp3.sh '<mediaUrl>' '<referer>' '<title>' '<author>'
```

**备用**：若 agent 自带浏览器工具（Playwright MCP / CDP）也可自己抓，要点：

- 监听 `resourceType === 'media'` 的网络请求；过滤 `douyinstatic.com` 等静态资源（页面素材也是 .mp4）
- 抖音还可读 `document.querySelector('video').currentSrc`；小红书是 `blob:` MSE，**只能走网络监听**（形如 `sns-video-*.xhscdn.com/...mp4?sign=...`）
- 小红书笔记 URL 必须带 `xsec_token`；登录墙也可用 CDP 接管用户日常浏览器（`Google Chrome --remote-debugging-port=9222`）
- 打开页面后若出现登录遮罩/404，停下请用户登录，等确认后再抓

## 脚本速查

| 脚本 | 用途 |
|---|---|
| `scripts/capture_media.mjs <视频页URL>` | 浏览器抓包：自举安装 playwright，输出 mediaUrl/title/referer JSON |
| `scripts/video2mp3.sh <分享文本\|URL> [目录]` | yt-dlp 快路径：解析→下载→mp3 |
| `scripts/media2mp3.sh <流URL> <referer> <标题> <作者> [目录]` | 抓包路径：curl→mp3 |
| `scripts/open_in_player.sh <file.mp3>` | 共用收尾：按 VIDEO2MP3_ACTION 激活/播放/仅保存（前两个脚本自动调用） |

## 常见坑

- **`open -a QQMusic file.mp3` 会用该文件替换当前播放队列**（QQ音乐无 AppleScript 字典、无追加队列接口，UI 元素匿名无法可靠自动化）。所以默认 ACTION=open 只激活窗口；只有用户明确要"直接播放"时才用 play
- **aria2c/wget 下 CDN 会 403**——必须 curl + Referer 头（media2mp3.sh 已处理）
- 流地址带签名会过期，抓到后立刻下载
- 抖音页面可能重定向到无关视频：核对 `page.url()` 里的 video ID 与目标一致再取流
- **小红书笔记 URL 必须带 `xsec_token` 参数**（App 分享链接自带）；裸 `/explore/<id>` 即使已登录也会 404（error_code=300031）
- 笔记是图文（无 `<video>` 元素）时没有音频可提取，告知用户
