# video2mp3

抖音 / 小红书视频链接 → 本地 mp3 → QQ 音乐 / 网易云音乐播放。

一个跨 AI agent 的 [Agent Skill](https://agentskills.io)：在抖音、小红书刷到博主唱了好听的歌，把链接丢给 AI，几秒后变成本地 mp3，用音乐 App 边工作边听、接音响放——手机不用一直停留在视频软件里。

支持 Kimi Code、Claude Code、Codex、Copilot CLI、Gemini CLI 等所有兼容 Agent Skills 规范的 AI agent。

## 工作原理

```
分享链接/分享文本
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
          存入 ~/Music/video2mp3 → 交给音乐 App（open_in_player.sh）
```

关键设计：

- **零 MCP 依赖**：抓包脚本首次运行自动 `npm install playwright` + 下载 chromium，任何能跑 node 的 agent 开箱即用，不需要用户配置任何 MCP server
- **抖音免登录**：无头浏览器直接抓
- **小红书**：带 `xsec_token` 的分享链接（App 复制出来的自带）未登录通常也能抓到流；抓不到才弹浏览器请用户扫码，登录态持久保存
- **默认自动播放**：转换完直接在音乐 App 里开播。QQ 音乐会替换当前播放队列，但文件自动导入「本地歌曲」，零手动步骤；在意队列可设 `VIDEO2MP3_ACTION=open`。网易云实测不清队列

## 安装

```bash
# 依赖
brew install node ffmpeg yt-dlp

# 克隆并链接到各 agent 的技能目录（任选一个或多个）
git clone https://github.com/CatWong1983/video2mp3.git && cd video2mp3
ln -s "$PWD/video2mp3" ~/.agents/skills/video2mp3   # Kimi Code / Codex / Copilot CLI / Gemini CLI
ln -s "$PWD/video2mp3" ~/.claude/skills/video2mp3   # Claude Code
```

## 使用

在 agent 里直接说：

> 帮我转成 mp3 用 QQ 音乐听：https://v.douyin.com/xxxx/

或直接粘贴 App 里复制的完整分享文本（含中文描述和链接），都可以。

转换的 mp3 **永远保存在 `~/Music/video2mp3/`**，与用哪个播放器无关。

## 两个播放器的差异（已实测）

| | QQ 音乐 | 网易云音乐 |
|---|---|---|
| 打开 mp3 自动播放 | ✅ | ✅ |
| 替换当前播放队列 | ⚠️ 会清（可用 `VIDEO2MP3_ACTION=open` 避免） | ✅ 不清 |
| 自动入本地曲库 | ✅（播放过的文件自动导入，零手动步骤） | ❌ 需手动添加文件夹 |

### 曲库入库

文件始终在输出目录（`~/Music/video2mp3`），不入库也不影响"转换完立刻听"。

- **QQ 音乐**：默认 play 模式下播放过的文件自动导入「本地歌曲」，**无需任何手动设置**。只有用 open 模式保队列时，才需要「本地歌曲」→「手动添加 / 添加本地歌曲文件夹」→ 选 `~/Music/video2mp3`
- **网易云**：想入库在「本地音乐」里手动添加 `~/Music/video2mp3` 文件夹（纯临时听可跳过）

## 环境变量

| 变量 | 取值 | 说明 |
|---|---|---|
| `VIDEO2MP3_ACTION` | `play`（默认）/ `open` / `none` | play：自动播放（QQ音乐会替换队列但自动入库）；open：只激活窗口+通知，不动队列（QQ音乐此模式不入库，需手动加文件夹）；none：只保存文件 |
| `VIDEO2MP3_PLAYER` | App 名 | 强制播放器，如 `QQMusic` / `NeteaseMusic`（默认检测 QQ音乐 → 网易云 → 系统默认） |
| `VIDEO2MP3_DIR` | 路径 | 输出目录（默认 `~/Music/video2mp3`） |

## 项目结构

```
video2mp3/
├── SKILL.md                    # Skill 主文档（AI 读这个）
└── scripts/
    ├── capture_media.mjs       # 浏览器抓包（主路径，自举安装 playwright）
    ├── video2mp3.sh            # yt-dlp 快路径
    ├── media2mp3.sh            # 流地址 → curl 下载 → ffmpeg 转 mp3
    └── open_in_player.sh       # 收尾：激活/播放/仅保存（三模式）
```

## FAQ

**Q: 抖音需要登录吗？**
不需要，无头浏览器直接抓。登录后更稳（防风控），可选。

**Q: 小红书需要登录吗？**
App 复制的分享链接自带 `xsec_token`，未登录通常也能抓到流。个别抓不到时脚本会弹浏览器让你扫码，登录一次永久有效（profile 存在 `~/.video2mp3/browser-profile`）。

**Q: 为什么不用 yt-dlp？**
试了。抖音要 fresh cookies、小红书报 No video formats，加浏览器 cookies 也不行——这两个站的 yt-dlp 提取器目前基本失效，所以浏览器抓包是主路径。yt-dlp 路径保留为快路径，哪天修复了自动受益。

**Q: 图文笔记能转吗？**
不能，没有音频流。AI 会告知。

**Q: 支持 Windows / Linux 吗？**
暂不支持。播放环节依赖 macOS 的 `open` 和 QQ音乐/网易云 Mac 版行为；抓包和转码环节理论可移植。

## License

MIT
