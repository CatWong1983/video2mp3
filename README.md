# video2mp3

抖音 / 小红书视频链接 → 本地 mp3 → QQ 音乐 / 网易云音乐播放。

一个跨 AI agent 的 [Agent Skill](https://agentskills.io)：把短视频平台里刷到的好歌转成音频文件，解放手机，边工作边听。

## 安装

```bash
# 依赖
brew install node ffmpeg yt-dlp

# 放到各 agent 的技能目录（任选一个或多个）
git clone <this-repo> && cd video2mp3
ln -s "$PWD/video2mp3" ~/.agents/skills/video2mp3   # Kimi Code / Codex / Copilot CLI / Gemini CLI
ln -s "$PWD/video2mp3" ~/.claude/skills/video2mp3   # Claude Code
```

一次性设置：QQ 音乐「本地歌曲」→「手动添加」→「添加本地歌曲文件夹」→ 选 `~/Music/video2mp3`。

## 使用

在 agent 里直接说：

> 帮我转成 mp3 用 QQ 音乐听：https://v.douyin.com/xxxx/ （或小红书分享文本）

agent 会自动：解析链接 → 浏览器抓包取音频流 → 转 mp3（带标题/歌手元数据）→ 存入 `~/Music/video2mp3` → 通知你。

## 环境变量

| 变量 | 说明 |
|---|---|
| `VIDEO2MP3_ACTION` | `open`(默认,只激活 App 不清播放队列) / `play`(自动播放,会替换队列) / `none`(只保存) |
| `VIDEO2MP3_PLAYER` | 强制播放器 App 名（默认检测 QQ音乐 → 网易云 → 系统默认） |
| `VIDEO2MP3_DIR` | 输出目录（默认 `~/Music/video2mp3`） |

## 说明

- 仅支持 macOS
- 抖音可直接抓包；小红书需要登录（skill 会停下来等你扫码，持久浏览器登录一次即可）
- 详见 [video2mp3/SKILL.md](video2mp3/SKILL.md)
