# video2mp3

抖音 / 小红书 / 哔哩哔哩视频链接 → 本地 mp3 → QQ 音乐 / 网易云音乐播放。

一个跨 AI agent 的 [Agent Skill](https://agentskills.io)：在抖音、小红书、B站刷到博主唱了好听的歌，把链接丢给 AI，几秒后变成本地 mp3，用音乐 App 边工作边听、接音响放——手机不用一直停留在视频软件里。

支持 Kimi Code、Claude Code、Codex、Copilot CLI、Gemini CLI 等所有兼容 Agent Skills 规范的 AI agent。

## 工作原理

```
分享链接/分享文本
      │
      ├─ B站：官方 API 匿名取音轨（bilibili2mp3.sh，最稳最快）
      │   view API 拿标题/UP主/cid → playurl API 拿 DASH 音轨地址
      │
      ├─ 快路径：yt-dlp 直接下载（video2mp3.sh）
      │   └─ 目前对抖音/小红书均失效，自动落到主路径 ↓
      │
      └─ 主路径：浏览器抓包（capture_media.mjs，自举零配置）
          ├─ 无头模式打开视频页，监听 media 网络请求
          ├─ 需要登录时自动弹有头浏览器，扫码一次永久有效
          └─ 输出真实 CDN 流地址（JSON）
                    │
          curl 下载（带 Referer）→ ffmpeg 转 mp3（media2mp3.sh）
          写入标题/歌手元数据，文件名「歌手 - 标题.mp3」
                    │
          whisper 转录生成同名 .lrc 滚动歌词（make_lyrics.sh，可选）
                    │
          存入 ~/Music/video2mp3 → 交给音乐 App（open_in_player.sh）
```

关键设计：

- **零 MCP 依赖**：抓包脚本首次运行自动 `npm install playwright` + 下载 chromium，任何能跑 node 的 agent 开箱即用，不需要用户配置任何 MCP server
- **B站免登录免浏览器**：走官方 view+playurl API 匿名取 DASH 音轨（约 192k），支持 `?p=N` 选集、b23.tv 短链、裸 BV 号；不依赖 yt-dlp（其对 B 站会 412）
- **抖音免登录**：无头浏览器直接抓
- **小红书**：带 `xsec_token` 的分享链接（App 复制出来的自带）未登录通常也能抓到流；抓不到才弹浏览器请用户扫码，登录态持久保存
- **智能播放（ACTION=auto）**：QQ 音乐没在运行 → 自动播放（队列本来是空的）；QQ 音乐正在运行 → **不擅自替掉你排好的队列**，而是弹窗让你当场决定：「直接播放」立刻听，「稍后听」歌已自动进「本地歌曲」。网易云两种情形都不清队列，总是直接播。想强制自动播放设 `VIDEO2MP3_ACTION=play`
- **QQ音乐曲库零配置**：脚本自动把输出目录写进 QQ音乐「本地歌曲」自动扫描（直接改写其偏好里的监控配置，幂等）——无论播不播，新歌都自动出现在「本地歌曲」，用户不用知道那个隐藏设置的存在
- **滚动歌词**（可选）：装了 `whisper-cli` 就用 whisper 把音频转录成同名 `.lrc`，QQ 音乐播放时自动加载滚动歌词（已实测）；没装则自动跳过

## 安装

```bash
# 依赖
brew install node ffmpeg yt-dlp
brew install whisper-cpp   # 可选：滚动歌词（首次生成时自动下载 ~460MB 模型）

# 克隆并链接到各 agent 的技能目录（任选一个或多个）
git clone https://github.com/CatWong1983/video2mp3.git && cd video2mp3
ln -s "$PWD/video2mp3" ~/.agents/skills/video2mp3   # Kimi Code / Codex / Copilot CLI / Gemini CLI
ln -s "$PWD/video2mp3" ~/.claude/skills/video2mp3   # Claude Code
```

## 使用

在 agent 里直接说：

> 帮我转成 mp3 用 QQ 音乐听：https://v.douyin.com/xxxx/

B站链接、b23.tv 短链、裸 BV 号同样直接丢过来即可（分 P 视频带 `?p=N`）。

或直接粘贴 App 里复制的完整分享文本（含中文描述和链接），都可以。

转换的 mp3 **永远保存在 `~/Music/video2mp3/`**，与用哪个播放器无关。

## 两个播放器的差异（已实测）

| | QQ 音乐 | 网易云音乐 |
|---|---|---|
| 打开 mp3 自动播放 | ✅ | ✅ |
| 替换当前播放队列 | ⚠️ 直接 open 会清；默认 `ACTION=auto` 在 QQ音乐运行中弹窗让你选 | ✅ 不清 |
| 自动入本地曲库 | ✅（输出目录自动写入「本地歌曲」监控配置，任何模式都入库） | ❌ 需手动添加文件夹 |
| 滚动歌词（同名 .lrc） | ✅ 自动加载（已实测） | ❌ 不认，显示"纯音乐"（已实测，App 限制无解） |

### 曲库入库

文件始终在输出目录（`~/Music/video2mp3`），不入库也不影响"转换完立刻听"。

- **QQ 音乐**：脚本自动把输出目录写进「本地歌曲」自动扫描配置（`setup_qqmusic_monitor.sh`，幂等；首次配置会重启一次 QQ音乐），**任何模式下新歌都自动入库，零手动设置**。万一自动配置失败（缺 Xcode CLT 的 swiftc）会提示手动兜底：「本地歌曲」→「添加本地歌曲文件夹」→ 选 `~/Music/video2mp3`
- **网易云**：想入库在「本地音乐」里手动添加 `~/Music/video2mp3` 文件夹（纯临时听可跳过）

## 环境变量

| 变量 | 取值 | 说明 |
|---|---|---|
| `VIDEO2MP3_ACTION` | `auto`（默认）/ `play` / `open` / `none` | auto：QQ音乐没在运行→自动播放，正在运行→弹窗让你选（直接播=替换队列 / 稍后听=进「本地歌曲」）；play：总是自动播放（QQ音乐会替换队列）；open：不动队列（QQ音乐同弹选择窗）；none：只保存文件 |
| `VIDEO2MP3_PLAYER` | App 名 | 强制播放器，如 `QQMusic` / `NeteaseMusic`（默认检测 QQ音乐 → 网易云 → 系统默认） |
| `VIDEO2MP3_DIR` | 路径 | 输出目录（默认 `~/Music/video2mp3`） |
| `VIDEO2MP3_LYRICS` | `1`（默认）/ `0` | 是否生成 whisper 滚动歌词 |
| `VIDEO2MP3_WHISPER_MODEL` | 路径 | whisper 模型（默认 `~/.video2mp3/models/ggml-small.bin`，缺失自动下载） |
| `VIDEO2MP3_WHISPER_LANG` | 语言码 | 识别语言（默认 `zh`） |

## 项目结构

```
video2mp3/
├── SKILL.md                    # Skill 主文档（AI 读这个）
└── scripts/
    ├── capture_media.mjs       # 浏览器抓包（抖音/小红书主路径，自举安装 playwright）
    ├── bilibili2mp3.sh         # B站官方 API 路径（view+playurl 取 DASH 音轨）
    ├── video2mp3.sh            # 统一入口：B站自动分流，其余走 yt-dlp 快路径
    ├── media2mp3.sh            # 流地址 → curl 下载 → ffmpeg 转 mp3
    ├── make_lyrics.sh          # whisper 转录 → 同名 .lrc 滚动歌词（可选）
    ├── open_in_player.sh       # 收尾：播放/弹窗选择/仅保存（auto/play/open/none）
    └── setup_qqmusic_monitor.sh # 把输出目录写进 QQ音乐「本地歌曲」自动扫描（幂等）
```

## FAQ

**Q: 抖音需要登录吗？**
不需要，无头浏览器直接抓。登录后更稳（防风控），可选。注意：免登录 ≠ 免风控——同一 profile 短时间高频抓取会触发"验证码中间页"（滑块），在弹出的窗口里手动过一次即可，脚本会自动继续。

**Q: 小红书需要登录吗？**
App 复制的分享链接自带 `xsec_token`，未登录通常也能抓到流。个别抓不到时脚本会弹浏览器让你扫码，登录一次永久有效（profile 存在 `~/.video2mp3/browser-profile`）。

**Q: B站需要登录吗？**
不需要。官方 view+playurl API 匿名即可取到 DASH 音轨（音质上限约 192k；高码率/Hi-Res 要登录，暂不支持）。付费/会员专享视频没有匿名音轨，会明确报错。多分 P 视频在链接里带 `?p=N` 选集。

**Q: 为什么不用 yt-dlp？**
试了。抖音要 fresh cookies、小红书报 No video formats、B站直接 HTTP 412（api.bilibili.com 按 TLS 指纹风控，浏览器 UA + curl 指纹必被拦）——yt-dlp 提取器对这三个站目前基本失效。所以抖音/小红书走浏览器抓包，B站走官方 API；yt-dlp 路径保留为快路径，哪天修复了自动受益。

**Q: 图文笔记能转吗？**
不能，没有音频流。AI 会告知。

**Q: 歌词哪来的？准吗？**
whisper.cpp 本地语音识别（ASR）转录的，不是网上匹配的原版歌词——所以翻唱、清唱、直播切片都有词。small 模型偶尔有错字，想更准设 `VIDEO2MP3_WHISPER_MODEL` 换 medium/large 模型。

**Q: 支持 Windows / Linux 吗？**
暂不支持。播放环节依赖 macOS 的 `open` 和 QQ音乐/网易云 Mac 版行为；抓包和转码环节理论可移植。

## License

MIT
