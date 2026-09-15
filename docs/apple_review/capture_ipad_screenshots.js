// Captures 13-inch iPad (2064x2752) screenshots of the Flutter web build.
// usage: node shots.js <lang> <token> <outdir> [route=name ...]
const puppeteer = require('puppeteer-core');
const path = require('path');
const fs = require('fs');

const [lang, token, outdir, ...routeArgs] = process.argv.slice(2);
const BASE = 'http://localhost/merr/build/web/';
const routes = routeArgs.length
  ? routeArgs.map(r => { const [route, name] = r.split('='); return { route, name }; })
  : [
      { route: '/club/dashboard', name: '01_dashboard' },
      { route: '/club/players', name: '02_players' },
      { route: '/club/sessions', name: '03_sessions' },
      { route: '/club/reports', name: '04_reports' },
      { route: '/club/settings', name: '05_settings' },
    ];

const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  fs.mkdirSync(outdir, { recursive: true });
  const browser = await puppeteer.launch({
    executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: 'new',
    args: ['--no-sandbox', '--hide-scrollbars', '--lang=' + (lang === 'ar' ? 'ar' : 'en-US')],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1032, height: 1376, deviceScaleFactor: 2 });
  page.on('console', m => { if (/error/i.test(m.type())) console.log('[console]', m.text().slice(0, 200)); });

  await page.goto(BASE, { waitUntil: 'load' });
  await page.evaluate((lang, token, u) => {
    localStorage.clear();
    localStorage['ssot.onboarded'] = '1';
    localStorage['ssot.language'] = lang;
    localStorage['ssot.token'] = token;
    localStorage['ssot.userName'] = u.name;
    localStorage['ssot.userRole'] = u.role;
    localStorage['ssot.orgRole'] = u.orgRole;
    localStorage['ssot.userId'] = u.id;
  }, lang, token, {
    name: process.env.SHOT_USER_NAME || 'Al Merrikh Demo Coach',
    role: process.env.SHOT_USER_ROLE || 'club',
    orgRole: process.env.SHOT_ORG_ROLE || 'owner',
    id: process.env.SHOT_USER_ID || '30',
  });

  for (const { route, name } of routes) {
    if (route === 'home') {
      await page.goto(BASE, { waitUntil: 'load' });
      await sleep(10000);
    } else if (route.startsWith('click:')) {
      const [x, y] = route.slice(6).split(',').map(Number);
      await page.mouse.click(x, y);
      await sleep(5000);
    } else if (route.startsWith('type:')) {
      await page.keyboard.type(route.slice(5), { delay: 40 });
      await sleep(1000);
    } else if (route.startsWith('scroll:')) {
      const dy = Number(route.slice(7));
      await page.mouse.move(516, 700);
      await page.mouse.wheel({ deltaY: dy });
      await sleep(2500);
    } else {
      await page.evaluate(r => { location.hash = r; }, route);
      await sleep(6000);
    }
    const file = path.join(outdir, `${name}_${lang}.png`);
    await page.screenshot({ path: file });
    console.log('saved', file);
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
