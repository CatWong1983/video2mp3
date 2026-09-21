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
    const page = ctx.pages()[0] || (await ctx.newPage());
    page.on('response', (r) => {
      const u = r.url();
      if (isAsset(u)) return;
      if (r.request().resourceType() === 'media') goodUrls.add(u);
      else if (/\.(mp3|m4a|mp4)(\?|$)/.test(u)) weakUrls.add(u);
    });
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    let lastNav = Date.now();

    const deadline = Date.now() + waitForLoginMs;
    let info = { title: '', author: '', hasVideo: false, currentSrc: '' };
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
        };
      });
      const directSrc = info.currentSrc && !info.currentSrc.startsWith('blob:') && !isAsset(info.currentSrc);
      if (goodUrls.size > 0 || directSrc) break;
      // 验证码/登录/安全限制页：用户在有头窗口里操作后，定期重新导航到目标页
      // （否则用户登录/过验证码后页面仍停在原处，永远轮询不到视频）
      // 注意必须要求 !hasVideo：info.title 是视频自己的标题，
      // 标题含"登录"等词的正常视频（如「微信登录不了怎么办」）不能误判
      const badPage = !info.hasVideo && /验证码|安全限制|不见了|登录/.test(info.title);
      if (badPage && Date.now() - lastNav > 15000) {
        try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 }); } catch {}
        lastNav = Date.now();
        continue;
      }
      // 已有 video 元素但未出流时，点击触发播放（登录等待期间不点击，避免干扰扫码）
      if (info.hasVideo) { try { await page.mouse.click(640, 400); } catch {} }
    }
    const directSrc = info.currentSrc && !info.currentSrc.startsWith('blob:') && !isAsset(info.currentSrc)
      ? info.currentSrc : '';
    const mediaUrl = [...goodUrls][0] || directSrc || [...weakUrls][0] || '';
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
