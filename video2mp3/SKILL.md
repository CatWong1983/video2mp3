---
name: video2mp3
description: Use when the user shares a Douyin (抖音), Xiaohongshu (小红书) or Bilibili (哔哩哔哩/B站) video link/share text and wants to listen to it as music — extract the audio to a local mp3 and play it in a local music app (QQ音乐 / 网易云音乐). Triggers on v.douyin.com, douyin.com/video/, xiaohongshu.com/explore, xhslink.com, bilibili.com/video/, b23.tv links, bare BV号 (BVxxxxxxxxxx), or requests like "把这个视频转成mp3用QQ音乐听".
---

# video2mp3 — 视频链接 → 本地 mp3 → QQ 音乐/网易云播放

把抖音/小红书/B站视频的音频保存为本地 mp3（带标题/歌手元数据），并用本地音乐 App 打开播放。

## 前提

- macOS；`node`(18+) 和 `ffmpeg` 必需，`yt-dlp` 可选（`brew install node ffmpeg yt-dlp`）
- 歌词：`whisper-cli` 可选（`brew install whisper-cpp`）。装了就会用 whisper 转录生成同名 `.lrc` 滚动歌词——**QQ音乐已实测自动加载；网易云实测不认本地同名 .lrc（歌词区显示"纯音乐"），无解，属 App 限制**。没装 whisper-cli 则跳过。模型默认 `~/.video2mp3/models/ggml-small.bin`（缺失自动下载，约 460MB），可用 `VIDEO2MP3_WHISPER_MODEL` 指向已有模型；`VIDEO2MP3_LYRICS=0` 关闭
- 播放器：检测顺序 QQ音乐 → 网易云 → 系统默认。可用 `VIDEO2MP3_PLAYER=<App名>` 覆盖
- 输出目录默认 `~/Music/video2mp3`，可用 `VIDEO2MP3_DIR` 覆盖。**无论用哪个播放器，转换的 mp3 都会保存在这里**

## 曲库入库（按播放器）

文件始终在输出目录里，不入库也不影响"转换完立刻听"。

- **QQ音乐**：`setup_qqmusic_monitor.sh` 会在每次转换时自动把输出目录写进 QQ音乐「本地歌曲」自动扫描配置（幂等；首次配置会重启一次 QQ音乐）——**任何模式下新歌都自动出现在「本地歌曲」，用户零手动设置**。自动配置依赖 Xcode CLT 的 `swiftc` 生成安全书签；缺失时脚本会提示手动：「本地歌曲」→「添加本地歌曲文件夹」→ 选 `~/Music/video2mp3`
- **网易云**：临时听什么都不用做（默认直接播放）。想入库 → 在网易云「本地音乐」里手动添加 `~/Music/video2mp3` 文件夹（纯临时听可跳过）

## 播放行为（VIDEO2MP3_ACTION）

| 值 | 行为 |
|---|---|
| `auto`（默认） | 智能模式。QQ音乐**没在运行** → 自动播放（队列本来是空的）；QQ音乐**正在运行** → 弹窗让用户当场决定：「直接播放」= 替换队列立刻听，「稍后听」（回车默认值，45秒无操作同）= 不动队列，歌已自动进「本地歌曲」。网易云两种情形都不清队列，总是直接播 |
| `play` | 总是自动播放。注意：QQ音乐**会用新歌替换当前播放队列** |
| `open` | 不动当前播放队列。QQ音乐同样弹上面那个选择窗；其它播放器只激活窗口+系统通知。无论选什么，歌都已在「本地歌曲」（监控目录自动导入） |
| `none` | 只保存文件 |

## 流程

### Step 1: 提取 URL

分享文本中内嵌链接，取第一个 `https?://` URL（脚本已内置此逻辑）。短链（v.douyin.com / xhslink.com / b23.tv）无需手动展开。B 站也接受裸 BV 号。

### Step 2: 快路径（B 站=官方 API；其余=先试 yt-dlp）

```bash
scripts/video2mp3.sh '<用户粘贴的分享文本或链接>'
```

- 成功即完成（自动转 mp3、嵌入封面/歌手、打开播放器）。
- **B 站链接自动分流到 `scripts/bilibili2mp3.sh`**（官方 view+playurl API 匿名取 DASH 音轨，稳定可用，支持 `?p=N` 选集），不经过 yt-dlp——yt-dlp 对 B 站会 HTTP 412，属预期，不要重试或升级 yt-dlp。
- **抖音目前报 "Fresh cookies are needed"、小红书报 "No video formats found" 均属预期**——yt-dlp 提取器对这两个站基本失效，直接走 Step 3，不要反复重试或升级 yt-dlp。

### Step 3: 浏览器抓包（仅抖音/小红书需要，B 站不用）

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
| `scripts/video2mp3.sh <分享文本\|URL> [目录]` | 统一入口：B 站自动分流到 bilibili2mp3.sh，其余试 yt-dlp |
| `scripts/bilibili2mp3.sh <链接\|BV号\|分享文本> [目录]` | B 站官方 API 路径：view+playurl 取 DASH 音轨 → 转 mp3 |
| `scripts/capture_media.mjs <视频页URL>` | 浏览器抓包：自举安装 playwright，输出 mediaUrl/title/referer JSON |
| `scripts/media2mp3.sh <流URL> <referer> <标题> <作者> [目录]` | 抓包路径：curl→mp3（bilibili2mp3.sh 内部也调它） |
| `scripts/make_lyrics.sh <file.mp3>` | whisper 转录生成同名 .lrc 滚动歌词（前两个脚本自动调用；失败只告警不阻塞） |
| `scripts/open_in_player.sh <file.mp3>` | 共用收尾：按 VIDEO2MP3_ACTION 激活/播放/仅保存（前两个脚本自动调用） |
| `scripts/setup_qqmusic_monitor.sh [目录]` | 把输出目录写进 QQ音乐「本地歌曲」自动扫描（幂等；open_in_player.sh 自动调用） |

## 常见坑

- **B 站（bilibili2mp3.sh 已处理，勿改）**：`api.bilibili.com` 按 TLS 指纹风控——**浏览器 UA + curl 指纹会被 412，裸 curl 默认 UA 反而稳定 200**，所以脚本请求 API 时故意不带 User-Agent（CDN 下载仍需 Referer，media2mp3.sh 已带）。匿名 API 音质上限约 192k（高码率/Hi-Res 需登录，不碰）；付费/会员专享视频 playurl 无音轨会明确报错；多分 P 视频用 URL 里的 `?p=N` 选集，默认第 1 P
- **`open -a QQMusic file.mp3` 会用该文件替换当前播放队列**（QQ音乐无 AppleScript 字典、无追加队列接口，UI 元素匿名无法可靠自动化——"追加到队列再播"在 Mac 版没有任何可编程入口，这是平台限制）。默认 ACTION=auto 已规避：检测到 QQ音乐正在运行就不擅自播放，而是**弹窗让用户当场决定**（直接播=替换队列 / 稍后听=进「本地歌曲」），45 秒无操作自动走"稍后听"安全路径；用户明确说"直接播"时再切 `VIDEO2MP3_ACTION=play`
- **QQ音乐「本地歌曲」监控目录存在偏好 `LocalMusicMonitorConfig`**（NSKeyedArchiver blob：{supportType:1, durationType:0, pathWtihBookData(原文拼写如此):{路径: app-scope 书签}}）。setup_qqmusic_monitor.sh 用 swiftc 生成书签 + plistlib 改写 blob，**QQ音乐运行中必须先退出再写**（否则退出时内存偏好回写覆盖）；其 entitlements 含 `com.apple.security.assets.music.read-write`，~/Music 下天然可读。非沙盒进程解析安全书签会报 Code=259，属正常，不影响 QQ音乐使用
- **抖音部分视频走 MSE 分片**（音视频分离：`<video>` 挂 `blob:`，真实流是 `fetch` 类型的 `.../media-audio-*/`、`.../media-video-*/` 分片）。capture_media.mjs 已处理：音轨优先匹配 `media-audio-`，纯视频轨只作兜底；media2mp3.sh 转码前有 ffprobe 音频流校验，抓错成纯视频轨会明确报错而不是产出静音 mp3
- **网易云音乐（已实测）**：`open -a NeteaseMusic file.mp3` 会自动播放，且**不清播放队列**（实测放完外部文件后自动继续队列下一首）；但**不会把文件导入「本地音乐」库**（open 后本地曲库表仍为空），入库只能在 app 内手动添加文件夹（UI 不可自动化）。即：网易云下 ACTION=play 是队列安全的，但歌不进库
- **aria2c/wget 下 CDN 会 403**——必须 curl + Referer 头（media2mp3.sh 已处理）
- 流地址带签名会过期，抓到后立刻下载
- **抖音 CDN 会中途断流**（curl 18 partial file）——media2mp3.sh 已处理：HEAD 拿 Content-Length → `curl -C -` 断点续传（最多 8 次）→ 校验字节数，不完整明确报错。不要简化掉这段逻辑，残缺文件交给 ffmpeg 会产出音频缺尾的 mp3 且不报错
- 部分视频（如直播录屏类较长视频）无头模式抓不到流，脚本自动弹有头浏览器，扫码登录后即过，属正常流程
- **"验证码中间页" = 抖音风控**（同一 profile/IP 高频抓取触发滑块）。恢复方式：无头轮连续两轮确认是验证码墙会**立刻弹有头窗口**（不干等 30 秒），手动过一次滑块即可——脚本检测到"无 video 元素 + 标题像墙页（或加载失败）"时会在**用户闲置 30 秒后**自动重新导航到目标页（正在扫码/拖滑块时不打断），过完即继续；仍被挡可删除 `~/.video2mp3/browser-profile` 重置，或 CDP 接管用户日常 Chrome。避免短时间对同一 profile 高频抓取
- 抖音页面可能重定向到无关视频：核对 `page.url()` 里的 video ID 与目标一致再取流
- **小红书笔记 URL 必须带 `xsec_token` 参数**（App 分享链接自带）；裸 `/explore/<id>` 即使已登录也会 404（error_code=300031）
- 笔记是图文（无 `<video>` 元素）时没有音频可提取，告知用户
- **歌词是 ASR 转录的**（whisper small），个别错字属正常（尤其唱词含糊/伴奏大声时）；时间轴是 whisper 的分段对齐，非逐字卡拉 OK。用户要更准可换更大模型：`VIDEO2MP3_WHISPER_MODEL=.../ggml-medium.bin`
