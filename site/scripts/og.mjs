// Draws src/og.png (1200x630, from a real capture) and src/apple-touch-icon.png.
// Needs Playwright: PW_MODULES=/path/to/node_modules node scripts/og.mjs
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(join(process.env.PW_MODULES ?? "/tmp/pw/node_modules", "x.js"));
const { chromium } = require("playwright");
const b64 = (p) => readFileSync(p).toString("base64");
const font = (f) => `data:font/woff2;base64,${b64(join(root, "src/assets/fonts", f))}`;
const shot = `data:image/jpeg;base64,${b64(join(root, "..", "docs/interface/evidence/topology-map-control-plane.jpeg"))}`;

const html = `<!doctype html><meta charset="utf-8"><style>
@font-face{font-family:L;font-weight:600;src:url(${font("literata-latin-600-normal.woff2")})}
@font-face{font-family:L;font-weight:400;src:url(${font("literata-latin-400-normal.woff2")})}
@font-face{font-family:M;font-weight:400;src:url(${font("atkinson-hyperlegible-mono-latin-400-normal.woff2")})}
*{box-sizing:border-box;margin:0}
body{width:1200px;height:630px;background:#f6f2e7;color:#16130f;position:relative;overflow:hidden}
.frame{position:absolute;inset:14px;border:2px solid #16130f}
.edge{position:absolute;inset:6px;border:1px solid #16130f}
.t{position:absolute;left:62px;top:50px;width:1076px}
.l{font:400 20px/1 M;letter-spacing:.06em;text-transform:uppercase;color:#4b443a}
h1{font:600 104px/1 L;letter-spacing:-.015em;margin:20px 0 14px}
p{font:400 30px/1.3 L;max-width:900px}
.img{position:absolute;left:62px;right:62px;bottom:50px;height:252px;border:2px solid #16130f;background:url(${shot}) -274px -325px/1403px auto no-repeat}
</style><div class="edge"></div><div class="frame"></div>
<div class="t"><div class="l">A Hamardikan Labs project</div><h1>KubeCompass</h1><p>A Kubernetes client for the Mac. Its topology map says how it knows each line it draws.</p></div>
<div class="img"></div>`;

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
