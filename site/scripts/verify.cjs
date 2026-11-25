// Playwright checks and screenshots for the built page. One Chromium at a time.
// Usage: NODE_PATH=/tmp/pw/node_modules node scripts/verify.cjs <base-url> <shots-dir>
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");
const AXE = fs.readFileSync(require.resolve("axe-core/axe.min.js"), "utf8");

const base = process.argv[2] || "http://localhost:8741/";
const shots = process.argv[3];
fs.mkdirSync(shots, { recursive: true });
const report = { problems: [], axe: {}, scroll: {}, sizes: {}, keyboard: {}, transfer: {} };
const bad = (m) => { report.problems.push(m); console.log("PROBLEM", m); };

async function open(browser, opts) {
  const ctx = await browser.newContext(opts);
  const page = await ctx.newPage();
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(`console: ${m.text()}`); });
  page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
  page.on("requestfailed", (r) => errors.push(`requestfailed: ${r.url()}`));
  page.on("response", (r) => { if (r.status() >= 400) errors.push(`http ${r.status()}: ${r.url()}`); });
  const external = [];
  page.on("request", (r) => { if (!r.url().startsWith(new URL(base).origin) && !r.url().startsWith("data:")) external.push(r.url()); });
  return { ctx, page, errors, external };
}

(async () => {
  const browser = await chromium.launch();

  console.log("step 1 Shots: viewport x scheme, first screen and full page.");
  const matrix = [
    ["desktop-light", 1440, 900, "light"], ["desktop-dark", 1440, 900, "dark"],
    ["phone-light", 375, 812, "light"], ["phone-dark", 375, 812, "dark"],
    ["w320-light", 320, 700, "light"], ["w820-light", 820, 1100, "light"],
  ];
  for (const [name, w, h, scheme] of matrix) {
    const { ctx, page, errors, external } = await open(browser, { viewport: { width: w, height: h }, colorScheme: scheme, reducedMotion: "reduce", deviceScaleFactor: 1 });
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    await page.screenshot({ path: path.join(shots, `${name}-first.png`) });
    // lazy images need scrolling before a full-page shot.
    await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 600) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 40)); } window.scrollTo(0, 0); });
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(shots, `${name}-full.png`), fullPage: true });
    if (errors.length) bad(`${name}: ${errors.join(" | ")}`);
    if (external.length) bad(`${name}: external requests ${external.join(" ")}`);
    await ctx.close();
  }

  console.log("step 2 axe: light, dark, phone, desktop.");
  for (const [name, w, h, scheme] of [["desktop-light", 1440, 900, "light"], ["desktop-dark", 1440, 900, "dark"], ["phone-light", 375, 812, "light"], ["phone-dark", 375, 812, "dark"]]) {
    const { ctx, page } = await open(browser, { viewport: { width: w, height: h }, colorScheme: scheme, reducedMotion: "reduce" });
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    await page.evaluate(AXE);
    const res = await page.evaluate(() => axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"] } }));
    report.axe[name] = { violations: res.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, sample: v.nodes[0]?.html.slice(0, 120) })), incomplete: res.incomplete.map((v) => v.id) };
    if (res.violations.length) bad(`axe ${name}: ${res.violations.map((v) => v.id).join(",")}`);
    await ctx.close();
  }

  console.log("step 3 Horizontal scroll, text sizes, targets.");
  for (const w of [320, 360, 375, 820, 1440]) {
    const { ctx, page } = await open(browser, { viewport: { width: w, height: 800 }, reducedMotion: "reduce" });
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    const sw = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
    report.scroll[w] = sw;
    if (sw[0] > sw[1]) bad(`horizontal scroll at ${w}: ${sw}`);
    if (w === 375 || w === 1440) {
      const sizes = await page.evaluate(() => {
        const out = { body: parseFloat(getComputedStyle(document.body).fontSize), small: [], targets: [] };
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) {
          const t = walker.currentNode; if (!t.textContent.trim()) continue;
          const el = t.parentElement; const r = el.getBoundingClientRect();
          if (!r.width || !r.height || getComputedStyle(el).visibility === "hidden") continue;
          if (el.closest(".vh, [hidden], noscript, script, style")) continue;
          let px = parseFloat(getComputedStyle(el).fontSize);
          if (el instanceof SVGElement && el.getScreenCTM) px *= el.getScreenCTM().a;
          if (px < 14) out.small.push(`${px.toFixed(1)} ${el.className?.baseVal ?? el.className} ${t.textContent.trim().slice(0, 30)}`);
        }
        for (const el of document.querySelectorAll("button, summary, .btn, .foot a, .skip, [role=button]")) {
          const r = el.getBoundingClientRect(); if (!r.width) continue;
          if (r.height < 43.5 || r.width < 43.5) out.targets.push(`${Math.round(r.width)}x${Math.round(r.height)} ${el.className?.baseVal ?? el.className} ${el.textContent.trim().slice(0, 24)}`);
        }
        return out;
      });
      report.sizes[w] = sizes;
      if (sizes.body < 17 || sizes.body > 19) bad(`body ${sizes.body}px at ${w}`);
      if (sizes.small.length) bad(`text under 14px at ${w}: ${[...new Set(sizes.small)].slice(0, 8).join(" | ")}`);
      if (sizes.targets.length) bad(`targets under 44px at ${w}: ${sizes.targets.slice(0, 8).join(" | ")}`);
    }
    await ctx.close();
  }

  console.log("step 4 First load on phone: transfer size, cold cache.");
  {
    const { ctx, page } = await open(browser, { viewport: { width: 375, height: 812 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
    const cdp = await ctx.newCDPSession(page);
    await cdp.send("Network.enable");
    let total = 0; const files = [];
    cdp.on("Network.loadingFinished", (e) => { total += e.encodedDataLength; });
    cdp.on("Network.responseReceived", (e) => files.push(e.response.url));
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(500);
    report.transfer = { kb: Math.round(total / 102.4) / 10, files: files.map((f) => f.replace(new URL(base).origin, "")) };
    if (total > 300 * 1024) bad(`phone first load ${report.transfer.kb} KB`);
    await ctx.close();
  }

  console.log("step 5 Keyboard pass.");
  for (const [name, w, h, scheme] of [["desktop-light", 1440, 900, "light"], ["phone-light", 375, 812, "light"]]) {
    const { ctx, page } = await open(browser, { viewport: { width: w, height: h }, colorScheme: scheme, reducedMotion: "reduce" });
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    const stops = [];
    for (let i = 0; i < 80; i++) {
      await page.keyboard.press("Tab");
      const s = await page.evaluate(() => {
        const el = document.activeElement; if (!el || el === document.body) return null;
        const cs = getComputedStyle(el);
        const ring = el.querySelector?.(".ring");
        const ringOn = ring ? parseFloat(getComputedStyle(ring).opacity) === 1 : false;
        const visible = (cs.outlineStyle !== "none" && parseFloat(cs.outlineWidth) >= 2) || ringOn;
        const r = el.getBoundingClientRect();
        const label = (el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 36);
        return { tag: el.tagName.toLowerCase(), cls: el.getAttribute("class") || "", label, visible, offscreen: r.bottom < 0 || r.top > innerHeight };
      });
      if (!s) break;
      stops.push(s);
      if (!s.visible) bad(`${name} focus not visible: ${s.tag}.${s.cls} ${s.label}`);
      if (stops.length === 1 || stops.length === 3 || stops.length === 7 || stops.length === 13 || stops.length === 20 || stops.length === 30) {
        await page.screenshot({ path: path.join(shots, `keyboard-${name}-${String(stops.length).padStart(2, "0")}.png`) });
      }
      if (stops.length > 1 && s.tag === "a" && s.label.startsWith("hamardikan")) break;
    }
    report.keyboard[name] = { stops: stops.length, unseen: stops.filter((s) => !s.visible).length };
    await ctx.close();
  }

  console.log("step 6 JS off.");
  for (const [name, w, h] of [["desktop", 1440, 900], ["phone", 375, 812]]) {
    const { ctx, page, errors } = await open(browser, { viewport: { width: w, height: h }, javaScriptEnabled: false });
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    await page.screenshot({ path: path.join(shots, `nojs-${name}-first.png`) });
    await page.screenshot({ path: path.join(shots, `nojs-${name}-full.png`), fullPage: true });
    const png = fs.readFileSync(path.join(shots, `nojs-${name}-full.png`));
    const sw = [png.readUInt32BE(16), w]; // a full-page capture is as wide as the scroll width
    report.scroll[`nojs-${name}`] = sw;
    if (sw[0] > sw[1]) bad(`nojs ${name} horizontal scroll ${sw}`);
    if (errors.length) bad(`nojs ${name}: ${errors.join(" | ")}`);
    await ctx.close();
  }

  console.log("step 7 Interaction proof: filter and node focus on desktop (screens), then the recording.");
  {
    const { ctx, page, errors } = await open(browser, { viewport: { width: 1440, height: 900 }, reducedMotion: "reduce" });
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    await page.locator(".mapscroll").scrollIntoViewIfNeeded();
    await page.click('.lg[data-level="inferred"]');
    const state = await page.evaluate(() => ({
      pressed: document.querySelector('.lg[data-level="inferred"]').getAttribute("aria-pressed"),
      rows: [...document.querySelectorAll(".rels tbody tr")].filter((r) => !r.hidden).length,
      off: document.querySelectorAll(".chart .edge.is-off").length,
      count: document.getElementById("count").textContent,
    }));
    report.filter = state;
    if (state.rows !== 2) bad(`inferred filter shows ${state.rows} rows, want 2`);
    await page.screenshot({ path: path.join(shots, "interaction-filter-inferred.png") });
    await page.click('.lg[data-level="inferred"]');
    await page.focus('.node[data-id="n7"]');
    await page.screenshot({ path: path.join(shots, "interaction-node-focus.png") });
    if (errors.length) bad(`interaction: ${errors.join(" | ")}`);
    await ctx.close();
  }
  {
    const vdir = path.join(shots, ".video");
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, recordVideo: { dir: vdir, size: { width: 1440, height: 900 } } });
    const page = await ctx.newPage();
    await page.goto(base);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(800);
    await page.evaluate(() => document.querySelector("#chart").scrollIntoView({ behavior: "instant" }));
    await page.mouse.wheel(0, 380);
    await page.waitForTimeout(3200);
    await page.click('.lg[data-level="declared"]');
    await page.waitForTimeout(1600);
    await page.click('.lg[data-level="declared"]');
    await page.waitForTimeout(900);
    const v = page.video();
    await ctx.close();
    fs.copyFileSync(await v.path(), path.join(shots, "demo.webm"));
    fs.rmSync(vdir, { recursive: true, force: true });
  }

  console.log("step 8 Survey pass timing: it must start only with motion allowed, and end inside 2.2 s.");
  {
    const { ctx, page } = await open(browser, { viewport: { width: 1440, height: 900 } });
    await page.goto(base);
    await page.evaluate(() => document.querySelector("#chart").scrollIntoView({ behavior: "instant" }));
    await page.waitForTimeout(200);
    const during = await page.evaluate(() => document.querySelector(".chart").className.baseVal);
    await page.waitForTimeout(2300);
    const after = await page.evaluate(() => document.querySelector(".chart").className.baseVal);
    report.survey = { during, after };
    if (!during.includes("surveying") || after.includes("surveying")) bad(`survey class: during=${during} after=${after}`);
    await ctx.close();
  }
  {
    const { ctx, page } = await open(browser, { viewport: { width: 1440, height: 900 }, reducedMotion: "reduce" });
    await page.goto(base);
    const cls = await page.evaluate(() => document.querySelector(".chart").className.baseVal);
    report.reducedMotionClasses = cls;
    if (/survey/.test(cls)) bad(`reduced motion still has ${cls}`);
    await ctx.close();
  }

  await browser.close();
  fs.writeFileSync(path.join(shots, "verify-report.json"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ axe: Object.fromEntries(Object.entries(report.axe).map(([k, v]) => [k, v.violations.length])), scroll: report.scroll, transfer: report.transfer.kb, keyboard: report.keyboard, filter: report.filter, survey: report.survey, problems: report.problems.length }, null, 1));
  process.exit(report.problems.length ? 1 : 0);
})();
