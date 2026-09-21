#!/usr/bin/env node
// capture_media.mjs — 打开抖音/小红书视频页，抓取媒体流地址，JSON 输出
//
// Usage: node capture_media.mjs <视频页URL或分享链接>
//
// 输出（stdout 最后一行 JSON）:
//   {"mediaUrl":"...","title":"...","author":"...","referer":"..."}
//   需要登录时会自动弹出有头浏览器等用户扫码（持久 profile，登录一次长期有效）
//
// 首次运行自动 npm install playwright + 下载 chromium，无需任何 MCP/手动配置。

import { execSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const PROFILE_DIR = path.join(os.homedir(), '.video2mp3', 'browser-profile');

const url = process.argv[2];
if (!url) {
  console.error('Usage: node capture_media.mjs <url>');
  process.exit(1);
}

async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch {
    console.error('>> 首次运行，安装 playwright（约 1-2 分钟）...');
    execSync('npm install --no-fund --no-audit', { cwd: scriptDir, stdio: 'inherit' });
    execSync('npx playwright install chromium', { cwd: scriptDir, stdio: 'inherit' });
    return await import('playwright');
  }
}

function refererFor(u) {
  if (/xiaohongshu\.com|xhslink\.com/.test(u)) return 'https://www.xiaohongshu.com/';
  return 'https://www.douyin.com/';
}

async function capture(pw, headless, waitForLoginMs) {
  const goodUrls = new Set();  // resourceType=media 且非静态资源
  const weakUrls = new Set();  // 仅 URL 形如媒体文件，可能是页面素材
  const isAsset = (u) => /douyinstatic\.com|\/obj\/|\.(png|jpg|svg|css|js)(\?|$)/.test(u);
  const ctx = await pw.chromium.launchPersistentContext(PROFILE_DIR, {
    headless,
    viewport: { width: 1280, height: 800 },
    args: ['--disable-blink-features=AutomationControlled'],
  });
  try {
    // 记录页面上最后一次真实用户操作的时间（每次导航自动重装）。
    // 用途：墙页重导航要避开用户正在扫码/拖滑块的窗口期
    await ctx.addInitScript(() => {
      const bump = () => { window.__v2mLastActive = Date.now(); };
      for (const ev of ['pointerdown', 'pointermove', 'keydown', 'wheel', 'touchstart']) {
        window.addEventListener(ev, bump, { passive: true, capture: true });
      }
    });
    const page = ctx.pages()[0] || (await ctx.newPage());
    const audioUrls = new Set();  // MSE 音轨分片（抖音音视频分离播放）
    const videoUrls = new Set();  // MSE 视频轨分片（只作兜底：直接转会出静音 mp3）
    page.on('response', (r) => {
      const u = r.url();
      if (isAsset(u)) return;
      const rt = r.request().resourceType();
      if (rt === 'media') { goodUrls.add(u); return; }
      // 抖音部分视频走 MSE（<video> 挂 blob:，fetch 分片拉流），URL 形如
      // .../media-audio-und-mp4a/?...&mime_type=video_mp4 —— resourceType 是 fetch 不是 media
      if (/\/media-audio-[a-z0-9]+/i.test(u)) { audioUrls.add(u); return; }
      if (/\/media-video-[a-z0-9]+/i.test(u) || /[?&]mime_type=video_mp4/.test(u)) { videoUrls.add(u); return; }
      if (/\.(mp3|m4a|mp4)(\?|$)/.test(u)) weakUrls.add(u);
    });
    let loadFailed = false;
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    } catch {
      loadFailed = true;
      console.error('>> 首次加载超时/失败，进入轮询等待（可能是网络抖动或风控）');
    }
    let lastNav = Date.now();

    const deadline = Date.now() + waitForLoginMs;
    let lastDiag = 0;
    let captchaStrikes = 0;
    let info = { title: '', author: '', hasVideo: false, currentSrc: '', paused: true };
    while (Date.now() < deadline) {
      await page.waitForTimeout(3000);
      info = await page.evaluate(() => {
        const v = document.querySelector('video');
        const authorEl = document.querySelector(
          '.author-container .username, .info .name, .account-name, [class*="author"] [class*="name"], [class*="nickname"]'
        );
        return {
          title: document.title.replace(/ - (抖音|小红书)$/, ''),
          author: authorEl ? authorEl.innerText.trim() : '',
          hasVideo: !!v,
          currentSrc: v ? v.currentSrc : '',
          paused: v ? v.paused : true,
        };
      });
      const directSrc = info.currentSrc && !info.currentSrc.startsWith('blob:') && !isAsset(info.currentSrc);
      if (goodUrls.size > 0 || audioUrls.size > 0 || directSrc) break;
      // 页面在播但一直没匹配到可用音轨：打诊断（MSE 形态再变时能有线索，不再静默卡死）
      if (info.hasVideo && !info.paused && Date.now() - lastDiag > 15000) {
        console.error(`>> 页面在播放但未匹配到音频流（疑似未知 MSE 形态）。候选: media=${goodUrls.size} audio=${audioUrls.size} video=${videoUrls.size} weak=${weakUrls.size}`);
        lastDiag = Date.now();
      }
      // 抖音"验证码中间页"是纯风控墙（页面不会有任何媒体流），无头轮硬抗没意义：
      // 连续两轮确认后直接退出，让主流程立刻弹有头窗口请用户过滑块/登录。
      // 注意只对"验证码"生效——小红书"安全限制"墙页仍可能出流，要留着等满 30 秒
      const captchaWall = !info.hasVideo && /验证码/.test(info.title);
      captchaStrikes = captchaWall ? captchaStrikes + 1 : 0;
      if (headless && captchaStrikes >= 2) {
        console.error('>> 检测到抖音风控验证码页，不再无头硬抗');
        break;
      }
      // 验证码/登录/安全限制页（或加载失败的错误页）：用户在有头窗口里操作后，
      // 定期重新导航到目标页（否则用户登录/过验证码后页面仍停在原处，永远轮询不到视频）
      // 注意墙页判断必须要求 !hasVideo：info.title 是视频自己的标题，
      // 标题含"登录"等词的正常视频（如「微信登录不了怎么办」）不能误判
      const badPage = !info.hasVideo && (loadFailed || /验证码|安全限制|不见了|登录/.test(info.title));
      // 只在用户闲置 30 秒后才重载：扫码/拖滑块途中重载会把二维码/滑块组件重置掉
      let lastActive = 0;
      try { lastActive = await page.evaluate(() => window.__v2mLastActive || 0); } catch {}
      if (badPage && Date.now() - Math.max(lastNav, lastActive) > 30000) {
        try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 }); loadFailed = false; } catch {}
        lastNav = Date.now();
        continue;
      }
      // 已有 video 元素但未出流时，点击触发播放（登录等待期间不点击，避免干扰扫码）
      if (info.hasVideo) { try { await page.mouse.click(640, 400); } catch {} }
    }
    const directSrc = info.currentSrc && !info.currentSrc.startsWith('blob:') && !isAsset(info.currentSrc)
      ? info.currentSrc : '';
    // 音轨最优先（MSE 常先拉一小段探测，取靠后的更可能是完整流）；
    // videoUrls 仅兜底——media2mp3.sh 有音频流校验，抓到纯视频轨会明确报错
    const mediaUrl = [...audioUrls].at(-1) || [...goodUrls][0] || directSrc || [...videoUrls].at(-1) || [...weakUrls][0] || '';
    return { mediaUrl, title: info.title, author: info.author, hasVideo: info.hasVideo };
  } finally {
    await ctx.close();
  }
}

const pw = await loadPlaywright();

// 第一轮：无头模式（已登录/无需登录时直接成功）
let r = await capture(pw, true, 30000);

// 小红书未登录时页面渲染"安全限制"，但带 xsec_token 的分享链接仍能抓到媒体流：
// 有媒体流就只警告不阻塞（标题可让用户从分享文本补充）；没媒体流才弹有头浏览器请用户登录
const badTitle = /安全限制|不见了/.test(r.title);
if (r.mediaUrl && badTitle) {
  r.warning = '页面标题为安全限制页（未登录），mediaUrl 有效但 title/author 不可信，建议改用分享文本中的标题';
} else if (!r.mediaUrl) {
  console.error('>> 未能获取媒体流（可能需要登录）。弹出浏览器窗口，请在其中登录，脚本会自动继续...');
  r = await capture(pw, false, 10 * 60 * 1000);
}

if (!r.mediaUrl) {
  console.error('ERROR: 仍未抓到媒体流。可能是图文笔记（无音频）或页面结构变化。');
  process.exit(1);
}

const out = { mediaUrl: r.mediaUrl, title: r.title, author: r.author, referer: refererFor(url) };
if (r.warning) out.warning = r.warning;
console.log(JSON.stringify(out));
