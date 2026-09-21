---
name: video2mp3
description: Use when the user shares a Douyin (抖音) or Xiaohongshu (小红书) video link/share text and wants to listen to it as music — extract the audio to a local mp3 and play it in a local music app (QQ音乐 / 网易云音乐). Triggers on v.douyin.com, douyin.com/video/, xiaohongshu.com/explore, xhslink.com links, or requests like "把这个视频转成mp3用QQ音乐听".
---

# video2mp3 — 视频链接 → 本地 mp3 → QQ 音乐/网易云播放

把抖音/小红书视频的音频保存为本地 mp3（带标题/歌手元数据），并用本地音乐 App 打开播放。

## 前提

- macOS；`ffmpeg` 必需，`yt-dlp` 可选（`brew install ffmpeg yt-dlp`）
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

用当前 agent 可用的浏览器工具（Playwright MCP、CDP、或任何可执行 JS 的受控浏览器）：

1. **打开视频页，先检查登录态。** 出现登录遮罩/扫码框，或 404 页（小红书未登录访问视频笔记会 404，error_code=300031）时：**停下操作，告诉用户"浏览器已打开，请扫码登录，完成后说一声"，等用户确认后再继续**（也可轮询等 `<video>` 元素出现）。两个站都支持这种方式：
   - 抖音：不登录也能抓包，但登录后更稳
   - 小红书：视频笔记**必须登录**
   - 持久 profile 的 agent 浏览器（如 Playwright MCP 默认配置）登录一次长期有效；若 agent 浏览器不持久，改用 CDP 接管用户日常浏览器（`Google Chrome --remote-debugging-port=9222`，连 `http://localhost:9222`），直接复用已有登录态

2. 监听 media 网络请求，触发播放：

```javascript
// Playwright 风格；其他工具等价实现即可
const mediaUrls = new Set();
page.on('response', r => {
  const u = r.url();
  if (r.request().resourceType() === 'media' || /\.(mp3|m4a|mp4)(\?|$)/.test(u)) mediaUrls.add(u);
});
await page.goto(url);            // domcontentloaded 即可
await page.waitForTimeout(6000); // 等播放器加载
await page.mouse.click(400, 400); // 触发播放（如未自动播放）
```

3. 取流地址（两站不同）：
   - 抖音：`document.querySelector('video').currentSrc` 直接可用，或从 `mediaUrls` 取
   - 小红书：用 MSE 播放，`currentSrc` 是 `blob:` 无效，**必须从 network listener 的 `mediaUrls` 取**（形如 `sns-video-*.xhscdn.com/...mp4?sign=...`）

4. 同时取页面标题（`document.title`）和作者名，用作 mp3 元数据。

5. 下载转码播放（**Referer 必需，否则 CDN 403**）：

```bash
scripts/media2mp3.sh '<media_url>' '<referer>' '<标题>' '<作者>'
# referer: 抖音用 https://www.douyin.com/ ，小红书用 https://www.xiaohongshu.com/
```

## 脚本速查

| 脚本 | 用途 |
|---|---|
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
