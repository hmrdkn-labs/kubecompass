// Draws src/og.png (1200x630: hero illustration and wordmark) and src/apple-touch-icon.png.
// Needs Playwright: PW_MODULES=/path/to/node_modules node scripts/og.mjs
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(join(process.env.PW_MODULES ?? "/tmp/pw/node_modules", "x.js"));
const { chromium } = require("playwright");
const b64 = (p) => readFileSync(p).toString("base64");
const font = `data:font/woff2;base64,${b64(join(root, "src/assets/fonts/bricolage-grotesque-latin-wght-normal.woff2"))}`;
const body = `data:font/woff2;base64,${b64(join(root, "src/assets/fonts/atkinson-hyperlegible-next-latin-400-normal.woff2"))}`;
const hero = `data:image/webp;base64,${b64(join(root, "src/assets/img/hero-harbour-1440.webp"))}`;

const html = `<!doctype html><meta charset="utf-8"><style>
@font-face{font-family:B;font-weight:600 800;src:url(${font})}
@font-face{font-family:A;font-weight:400;src:url(${body})}
*{box-sizing:border-box;margin:0}
body{width:1200px;height:630px;background:#071a24 url(${hero}) center bottom/cover no-repeat;color:#e6f0f2;position:relative;overflow:hidden}
.t{position:absolute;left:64px;right:64px;top:70px}
h1{font:800 168px/0.9 B;letter-spacing:-.045em}
p{font:400 38px/1.3 A;margin-top:28px;max-width:860px}
</style><div class="t"><h1>KubeCompass</h1><p>A cluster map that tells you how it knows.</p></div>`;

const icon = readFileSync(join(root, "src/favicon.svg"), "utf8");
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
await page.setContent(html);
await page.waitForTimeout(300);
await page.screenshot({ path: join(root, "src/og.png") });
const ip = await browser.newPage({ viewport: { width: 180, height: 180 } });
await ip.setContent(`<body style="margin:0">${icon.replace("<svg ", '<svg width="180" height="180" ')}</body>`);
await ip.screenshot({ path: join(root, "src/apple-touch-icon.png") });
await browser.close();
