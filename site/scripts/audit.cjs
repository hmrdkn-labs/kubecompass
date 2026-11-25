// v2 audit and screenshots for the built page. One Chromium at a time: run under the lock.
// Usage:
//   flock ~/.cache/kubecompass-pw/chromium.lock \
//     env NODE_PATH=~/.cache/kubecompass-pw/node_modules node scripts/audit.cjs <base-url> <shots-dir>
// Writes <shots-dir>/audit.json and screenshots, prints one PASS/FAIL/WARN line per check,
// exits 1 on any FAIL. Lighthouse runs from the same cache (`.bin/lighthouse`) when present.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const { chromium } = require("playwright");

const AXE = fs.readFileSync(require.resolve("axe-core/axe.min.js"), "utf8");
const base = process.argv[2] || "http://localhost:8741/";
const shots = process.argv[3];
if (!shots) { console.error("usage: audit.cjs <base-url> <shots-dir>"); process.exit(2); }
fs.mkdirSync(shots, { recursive: true });
const origin = new URL(base).origin;
const results = [];
function record(id, name, status, detail, data) {
  results.push({ id, name, status, detail, data });
  console.log(`${status} ${String(id).padStart(2)} ${name}: ${detail}`);
}

async function open(browser, opts) {
  const ctx = await browser.newContext(opts);
  const page = await ctx.newPage();
  const net = { errors: [], external: [] };
  page.on("console", (m) => { if (m.type() === "error") net.errors.push(`console: ${m.text()}`); });
  page.on("pageerror", (e) => net.errors.push(`pageerror: ${e.message}`));
  page.on("requestfailed", (r) => net.errors.push(`requestfailed: ${r.url()}`));
  page.on("response", (r) => { if (r.status() >= 400) net.errors.push(`http ${r.status()}: ${r.url()}`); });
  page.on("request", (r) => { const u = r.url(); if (!u.startsWith(origin) && !u.startsWith("data:") && !u.startsWith("blob:")) net.external.push(u); });
  return { ctx, page, net };
}
async function load(page) {
  await page.goto(base);
  await page.waitForLoadState("networkidle");
}

// Runs in the page. Returns every visible text node with computed style facts.
function collectText() {
  const out = [];
  const hero = document.querySelector("[data-hero]") ||
    (document.querySelector("h1") && (document.querySelector("h1").closest("section, header") || document.querySelector("h1").parentElement));
  const firstHeader = document.querySelector("header");
  const h1s = [...document.querySelectorAll("h1")];
  const brand = document.querySelector("header .brand, nav .brand, [data-brand], header a[href='/'], header a[href='./'], nav a[href='/']");
  const sel = (el) => {
    const parts = [];
    for (let e = el; e && e.nodeType === 1 && parts.length < 4; e = e.parentElement) {
      let s = e.tagName.toLowerCase();
      const c = e.getAttribute("class"); if (c && typeof c === "string") s += "." + c.trim().split(/\s+/)[0];
      if (e.id) s += "#" + e.id;
      parts.unshift(s);
    }
    return parts.join(" > ");
  };
  const scale = (el) => {
    // cumulative transform scale: SVG screen matrix, or product of ancestor CSS transform scales.
    if (el instanceof SVGElement && el.getScreenCTM) { const m = el.getScreenCTM(); return m ? Math.hypot(m.a, m.b) : 1; }
    let s = 1;
    for (let e = el; e && e.nodeType === 1; e = e.parentElement) {
      const t = getComputedStyle(e).transform;
      if (t && t !== "none") { const m = new DOMMatrix(t); s *= Math.hypot(m.a, m.b); }
    }
    return s;
  };
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const t = walker.currentNode;
    const text = t.textContent.trim(); if (!text) continue;
    const el = t.parentElement; if (!el) continue;
    if (el.closest("script, style, noscript, template, [hidden]")) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === "hidden" || cs.display === "none") continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 1 || r.height <= 1) continue; // visually hidden helpers
    const px = parseFloat(cs.fontSize);
    out.push({
      text: text.slice(0, 40),
      sel: sel(el),
      family: cs.fontFamily.split(",")[0].trim().replace(/^["']|["']$/g, ""),
      size: px,
      rendered: px * scale(el),
      inHero: !!(hero && hero.contains(el)) || !!(firstHeader && firstHeader.contains(el)),
      isH1: h1s.some((h) => h.contains(el)),
      isBrand: !!(brand && brand.contains(el)),
    });
  }
  return out;
}

function groupBy(rows, key) {
  const m = new Map();
  for (const r of rows) { const k = key(r); if (!m.has(k)) m.set(k, r); }
  return m;
}

(async () => {
  const browser = await chromium.launch({ args: (process.env.CHROME_ARGS || "").split("||").filter(Boolean) });
  const netAll = { errors: [], external: [] };
  const pools = {}; // text collections per viewport

  // ---- main desktop and phone loads: text, styles, dashes, h1, axe, network ----
  for (const [tag, w, h, extra] of [["1440", 1440, 900, {}], ["390", 390, 844, { isMobile: true, hasTouch: true }]]) {
    const { ctx, page, net } = await open(browser, { viewport: { width: w, height: h }, reducedMotion: "reduce", deviceScaleFactor: 1, ...extra });
    await load(page);
    pools[tag] = await page.evaluate(collectText);
    pools[tag + "_style"] = await page.evaluate(() => {
      const bad = { upper: [], all: [], dash: [] };
      const sel = (el) => { let s = el.tagName.toLowerCase(); const c = el.getAttribute("class"); if (c) s += "." + c.trim().split(/\s+/)[0]; return s; };
      for (const el of document.querySelectorAll("body, body *")) {
        const cs = getComputedStyle(el);
        const ls = cs.letterSpacing;
        if (cs.textTransform === "uppercase" && ls !== "normal" && parseFloat(ls) !== 0) bad.upper.push(`${sel(el)} ls=${ls}`);
        if (cs.transitionProperty.split(",").map((s) => s.trim()).includes("all") && parseFloat(cs.transitionDuration) > 0) bad.all.push(sel(el));
        for (const a of ["alt", "aria-label"]) { const v = el.getAttribute(a); if (v && /[\u2013\u2014]/.test(v)) bad.dash.push(`${sel(el)}[${a}] ${v.slice(0, 40)}`); }
      }
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      while (walker.nextNode()) {
        const t = walker.currentNode; const el = t.parentElement;
        if (!el || el.closest("script, style, noscript, template")) continue;
        if (/[\u2013\u2014]/.test(t.textContent)) bad.dash.push(`${sel(el)} "${t.textContent.trim().slice(0, 40)}"`);
      }
      // document title and meta description are visible to users too.
      if (/[\u2013\u2014]/.test(document.title)) bad.dash.push(`title "${document.title}"`);
      const h1 = [...document.querySelectorAll("h1")];
      return { ...bad, h1Count: h1.length, h1Width: h1[0] ? h1[0].getBoundingClientRect().width : 0 };
    });
    await page.evaluate(AXE);
    const ax = await page.evaluate(() => axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa", "best-practice"] } }));
    pools[tag + "_axe"] = ax.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, sample: (v.nodes[0] && v.nodes[0].html || "").slice(0, 120) }));
    netAll.errors.push(...net.errors.map((e) => `${tag}: ${e}`));
    netAll.external.push(...net.external.map((e) => `${tag}: ${e}`));
    await ctx.close();
  }
  const d = pools["1440"], m = pools["390"];

  // 1 families
  {
    const fam = groupBy(d, (r) => r.family);
    const list = [...fam].map(([k, r]) => `${k} (${r.sel})`);
    record(1, "font families", fam.size <= 2 ? "PASS" : "FAIL", `${fam.size} found: ${list.join("; ")}`, list);
  }
  // 2 sizes below the hero
  {
    const below = d.filter((r) => !r.inHero && !r.isH1 && !r.isBrand);
    const sizes = groupBy(below, (r) => r.size);
    const list = [...sizes].sort((a, b) => a[0] - b[0]).map(([k, r]) => `${k}px (${r.sel})`);
    record(2, "font sizes below hero", sizes.size <= 3 ? "PASS" : "FAIL", `${sizes.size} found: ${list.join("; ")}${document_hint(d)}`, list);
  }
  function document_hint(rows) { return rows.some((r) => r.inHero) ? "" : " [no hero marker found]"; }
  // 3 min rendered size
  {
    const worst = {};
    let ok = true;
    for (const [tag, rows] of [["1440", d], ["390", m]]) {
      const min = rows.reduce((a, r) => (r.rendered < a.rendered ? r : a), { rendered: Infinity });
      worst[tag] = min.rendered === Infinity ? "no text" : `${min.rendered.toFixed(1)}px ${min.sel} "${min.text}"`;
      if (min.rendered < 13 - 0.01) ok = false;
    }
    record(3, "min font size >= 13px", ok ? "PASS" : "FAIL", `1440: ${worst["1440"]}; 390: ${worst["390"]}`, worst);
  }
  // 4 uppercase + tracking
  {
    const b = d.length ? pools["1440_style"].upper : [];
    record(4, "uppercase with letter-spacing", b.length ? "FAIL" : "PASS", b.length ? `${b.length}: ${[...new Set(b)].slice(0, 6).join("; ")}` : "none", b);
  }
  // 5 transition: all
  {
    const b = pools["1440_style"].all;
    record(5, "transition-property all", b.length ? "FAIL" : "PASS", b.length ? `${b.length}: ${[...new Set(b)].slice(0, 6).join("; ")}` : "none", b);
  }
  // 6 dashes
  {
    const b = [...pools["1440_style"].dash, ...pools["390_style"].dash];
    record(6, "em/en dashes in text, alt, aria-label", b.length ? "FAIL" : "PASS", b.length ? `${b.length}: ${[...new Set(b)].slice(0, 5).join("; ")}` : "none", b);
  }
  // 7 h1
  {
    const s = pools["1440_style"];
    const ok = s.h1Count === 1 && s.h1Width >= 1008;
    record(7, "h1 width >= 70% and one h1", ok ? "PASS" : "FAIL", `${s.h1Count} h1, width ${Math.round(s.h1Width)}px (need 1008)`, { count: s.h1Count, width: s.h1Width });
  }
  // 8 overflow, JS on and off
  {
    const rows = [];
    for (const w of [320, 390, 1440]) {
      const { ctx, page } = await open(browser, { viewport: { width: w, height: 800 }, reducedMotion: "reduce" });
      await load(page);
      const sw = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
      rows.push({ w, js: true, scroll: sw[0], client: sw[1], bad: sw[0] > sw[1] });
      await ctx.close();
      const off = await open(browser, { viewport: { width: w, height: 800 }, javaScriptEnabled: false });
      await load(off.page);
      const tmp = path.join(os.tmpdir(), `audit-nojs-${process.pid}-${w}.png`);
      await off.page.screenshot({ path: tmp, fullPage: true });
      const pw = fs.readFileSync(tmp).readUInt32BE(16); // a full-page capture is as wide as the scroll width
      fs.rmSync(tmp, { force: true });
      rows.push({ w, js: false, scroll: pw, client: w, bad: pw > w });
      await off.ctx.close();
    }
    const bad = rows.filter((r) => r.bad);
    record(8, "no horizontal overflow (320/390/1440, JS on+off)", bad.length ? "FAIL" : "PASS",
      bad.length ? bad.map((r) => `${r.w}${r.js ? "" : " nojs"}: ${r.scroll}>${r.client}`).join("; ") : "none", rows);
  }
  // 9 axe
  {
    const parts = []; let n = 0;
    for (const tag of ["1440", "390"]) {
      const v = pools[tag + "_axe"]; n += v.length;
      parts.push(`${tag}: ${v.length ? v.map((x) => `${x.id}(${x.nodes})`).join(",") : "0"}`);
    }
    record(9, "axe violations", n ? "FAIL" : "PASS", parts.join("; "), { 1440: pools["1440_axe"], 390: pools["390_axe"] });
  }
  // 10 network
  {
    // additional phone load with JS off is not needed; the 1440 and 390 loads above are the evidence.
    const e = [...new Set(netAll.errors)], x = [...new Set(netAll.external)];
    record(10, "console/page errors, failed or >=400 responses, external requests", e.length || x.length ? "FAIL" : "PASS",
      e.length || x.length ? [...e, ...x.map((u) => `external ${u}`)].slice(0, 6).join(" | ") : "none", { errors: e, external: x });
  }
  // 11 transfer
  {
    const { ctx, page } = await open(browser, { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true });
    const cdp = await ctx.newCDPSession(page);
    await cdp.send("Network.enable");
    await cdp.send("Network.setCacheDisabled", { cacheDisabled: true });
    let total = 0; const files = new Map();
    cdp.on("Network.responseReceived", (e) => files.set(e.requestId, { url: e.response.url.replace(origin, ""), bytes: 0 }));
    cdp.on("Network.loadingFinished", (e) => { total += e.encodedDataLength; const f = files.get(e.requestId); if (f) f.bytes = e.encodedDataLength; });
    await load(page);
    await page.waitForTimeout(300);
    const kb = Math.round(total / 102.4) / 10;
    const top = [...files.values()].sort((a, b) => b.bytes - a.bytes).slice(0, 3).map((f) => `${f.url} ${(f.bytes / 1024).toFixed(1)}KB`);
    record(11, "phone first-load transfer < 300 KB", total < 300 * 1024 ? "PASS" : "FAIL", `${kb} KB over ${files.size} responses; largest: ${top.join(", ")}`, { kb, files: [...files.values()] });
    await ctx.close();
  }

  // ---- screenshots ----
  console.log("shots:");
  {
    const { ctx, page } = await open(browser, { viewport: { width: 1440, height: 900 }, reducedMotion: "reduce", deviceScaleFactor: 1 });
    await load(page);
    await page.screenshot({ path: path.join(shots, "d-00.png") });
    const files = ["d-00.png"];
    for (let i = 1; i < 40; i++) {
      const state = await page.evaluate((i) => {
        window.scrollTo(0, i * 900);
        const f = document.querySelector("footer");
        const r = f && f.getBoundingClientRect();
        return { footer: !!(r && r.top < innerHeight && r.bottom > 0), atEnd: innerHeight + scrollY >= document.documentElement.scrollHeight - 1 };
      }, i);
      await page.waitForTimeout(350);
      const name = `d-${String(i).padStart(2, "0")}.png`;
      await page.screenshot({ path: path.join(shots, name) });
      files.push(name);
      if (state.footer || state.atEnd) break;
    }
    console.log("  " + files.join(" "));
    await ctx.close();
  }
  {
    const { ctx, page } = await open(browser, { viewport: { width: 390, height: 844 }, reducedMotion: "reduce", deviceScaleFactor: 1, isMobile: true, hasTouch: true });
    await load(page);
    await page.screenshot({ path: path.join(shots, "m-first.png") });
    await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 500) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 60)); } window.scrollTo(0, 0); });
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(shots, "m-full.png"), fullPage: true });
    console.log("  m-first.png m-full.png");
    await ctx.close();
  }
  {
    const { ctx, page } = await open(browser, { viewport: { width: 1440, height: 900 }, javaScriptEnabled: false });
    await load(page);
    await page.screenshot({ path: path.join(shots, "nojs-d-first.png") });
    await ctx.close();
  }
  {
    const { ctx, page } = await open(browser, { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
    await page.goto(base);
    await page.waitForTimeout(2500);
    await page.screenshot({ path: path.join(shots, "d-00-motion.png") });
    console.log("  nojs-d-first.png d-00-motion.png");
    await ctx.close();
  }
  await browser.close();

  // 12 Lighthouse mobile
  {
    const bin = path.join(os.homedir(), ".cache/kubecompass-pw/node_modules/.bin/lighthouse");
    if (!fs.existsSync(bin)) {
      record(12, "lighthouse mobile", "WARN", `not found; run: ${bin} <url> --only-categories=performance,accessibility --output=json --output-path=lh.json --chrome-flags="--headless=new" (install: npm i lighthouse in ~/.cache/kubecompass-pw)`);
    } else {
      const out = path.join(shots, "lighthouse.json");
      const r = spawnSync(bin, [base, "--form-factor=mobile", "--only-categories=performance,accessibility", "--output=json", `--output-path=${out}`, "--quiet", "--chrome-flags=--headless=new --no-sandbox"],
        { env: { ...process.env, CHROME_PATH: chromium.executablePath() }, encoding: "utf8", timeout: 240000 });
      if (r.status !== 0 || !fs.existsSync(out)) {
        record(12, "lighthouse mobile", "FAIL", `lighthouse failed (exit ${r.status}): ${(r.stderr || r.error && r.error.message || "").toString().slice(-200)}`);
      } else {
        const j = JSON.parse(fs.readFileSync(out, "utf8"));
        const perf = Math.round(j.categories.performance.score * 100), a11y = Math.round(j.categories.accessibility.score * 100);
        record(12, "lighthouse mobile", perf >= 90 && a11y === 100 ? "PASS" : "FAIL", `performance ${perf} (need 90), accessibility ${a11y} (need 100)`, { perf, a11y });
      }
    }
  }

  fs.writeFileSync(path.join(shots, "audit.json"), JSON.stringify({ base, when: new Date().toISOString(), results }, null, 2));
  const fails = results.filter((r) => r.status === "FAIL").length;
  console.log(fails ? `${fails} check(s) FAILED` : "all checks passed");
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
