// Renders site/public from site/src and site/data. No dependencies.
// The page is complete without JavaScript: the map and the relationship list are written here, from
// data/demo-graph.json, and the footer and signals from data/github.json and git.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, existsSync, copyFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { execSync } from "node:child_process";
import { dirname, join, extname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(root, "src");
const pub = join(root, "public");
const assets = join(pub, "assets");

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const read = (p) => readFileSync(p, "utf8");
const hash = (buf) => createHash("sha256").update(buf).digest("hex").slice(0, 8);

// ---- assets: content-hashed names under /assets, old hashed files removed -------------------------
rmSync(assets, { recursive: true, force: true });
mkdirSync(join(assets, "fonts"), { recursive: true });
const urls = new Map(); // "fonts/x.woff2" -> "/assets/fonts/x.<hash>.woff2"
function emit(rel, buf) {
  const ext = extname(rel);
  const out = `${rel.slice(0, -ext.length)}.${hash(buf)}${ext}`;
  mkdirSync(dirname(join(assets, out)), { recursive: true });
  writeFileSync(join(assets, out), buf);
  urls.set(rel, `/assets/${out}`);
  return `/assets/${out}`;
}
for (const f of readdirSync(join(src, "assets/fonts"))) {
  if (f.endsWith(".txt")) copyFileSync(join(src, "assets/fonts", f), join(assets, "fonts", f));
  else emit(`fonts/${f}`, readFileSync(join(src, "assets/fonts", f)));
}
for (const f of readdirSync(join(src, "assets/img"))) emit(`img/${f}`, readFileSync(join(src, "assets/img", f)));

// ---- data ---------------------------------------------------------------------------------------
const graph = JSON.parse(read(join(root, "data/demo-graph.json")));
let gh = null;
try { gh = JSON.parse(read(join(root, "data/github.json"))); } catch { gh = null; }

const LEVELS = ["observed", "declared", "inferred", "unavailable"];
const LEVEL_NAME = { observed: "Observed", declared: "Declared", inferred: "Inferred", unavailable: "Unavailable" };
const SHORT = { PersistentVolumeClaim: "PVC", PersistentVolume: "PV" };

// Short ids keep the page free of the fixture's raw identifiers.
const nodes = graph.nodes.map((n, i) => ({ ...n, key: `n${i}` }));
const byId = new Map(nodes.map((n) => [n.id, n]));
const nodeLabel = (n) => (n.virtual ? n.name : `${n.kind} ${n.name}`);

const edges = graph.edges
  .map((e) => ({ ...e, a: byId.get(e.from), b: byId.get(e.to) }))
  .sort((x, y) =>
    LEVELS.indexOf(x.level) - LEVELS.indexOf(y.level) ||
    x.relationship.localeCompare(y.relationship) ||
    nodeLabel(x.a).localeCompare(nodeLabel(y.a)));
edges.forEach((e, i) => { e.i = i; });
const defaultIndex = edges.findIndex((e) => e.relationship === "routesTo");
const litDefault = new Set([edges[defaultIndex].a.key, edges[defaultIndex].b.key]);

// ---- the chart -----------------------------------------------------------------------------------
const W = 140, H = 50;
const CX = [14, 230, 446, 662, 878, 1094];
const POS = {
  Ingress: [CX[0], 74], Service: [CX[1], 74], EndpointSlice: [CX[1], 234],
  ReplicaSet: [CX[2], 312], Deployment: [CX[2], 408], Pod: [CX[3], 234],
  PersistentVolumeClaim: [CX[4], 334],
  Node: [CX[5], 112], PersistentVolume: [CX[5], 334], StorageClass: [CX[5], 428],
};
// Where the relationship name sits when the middle of the line is the wrong place.
const LABEL = {
  "EndpointSlice>Service": { dx: -9, dy: 5, anchor: "end" },
  "ReplicaSet>Deployment": { dx: -9, dy: 5, anchor: "end" },
  "Ingress>Service": { dx: 0, dy: -26, anchor: "middle" },
  "PersistentVolumeClaim>PersistentVolume": { dx: 0, dy: -9, anchor: "middle" },
  "PersistentVolume>StorageClass": { dx: -9, dy: 5, anchor: "end" },
};
const VIEW = { w: 1248, h: 566 };
const AREA = { x: 4, y: 30, w: CX[4] + W + 10 - 4, h: 440 };
const BOUNDARY = { x: 4, y: 506, w: VIEW.w - 8, h: 54 };

for (const n of nodes) {
  if (n.virtual) { Object.assign(n, { x: BOUNDARY.x, y: BOUNDARY.y, w: BOUNDARY.w, h: BOUNDARY.h }); continue; }
  if (n.kind === "Namespace") continue; // the containing area, not a box
  const p = POS[n.kind];
  if (!p) throw new Error(`no position for kind ${n.kind}`);
  Object.assign(n, { x: p[0], y: p[1], w: W, h: H });
}
const centre = (n) => [n.x + n.w / 2, n.y + n.h / 2];
function clip(n, toward, pad) {
  const [cx, cy] = centre(n);
  const dx = toward[0] - cx, dy = toward[1] - cy;
  const sx = dx === 0 ? Infinity : (n.w / 2 + pad) / Math.abs(dx);
  const sy = dy === 0 ? Infinity : (n.h / 2 + pad) / Math.abs(dy);
  const t = Math.min(sx, sy);
  return [cx + dx * t, cy + dy * t];
}
const f1 = (v) => Math.round(v * 10) / 10;

function chart() {
  const drawn = edges.filter((e) => e.relationship !== "containedIn");
  let out = `<svg class="chart" viewBox="0 0 ${VIEW.w} ${VIEW.h}" role="group" aria-label="Map of the ${nodes.length - 1} resources in the demo graph. The relationship list below carries every line as text.">\n`;
  out += `<rect class="ns-area" x="${AREA.x}" y="${AREA.y}" width="${AREA.w}" height="${AREA.h}"/>\n`;
  const ns = nodes.find((n) => n.kind === "Namespace");
  out += `<text class="ns-label" x="${AREA.x + 12}" y="${AREA.y + 20}">Namespace ${esc(ns.name)}: the seven containedIn lines are drawn as this border</text>\n`;
  for (const e of drawn) {
    const A = centre(e.a), B = centre(e.b);
    const p1 = clip(e.a, B, 2), p2 = clip(e.b, A, 5);
    const ang = Math.atan2(p2[1] - p1[1], p2[0] - p1[0]);
    const hx = (r) => [p2[0] - 10 * Math.cos(ang + r), p2[1] - 10 * Math.sin(ang + r)];
    const l = hx(0.38), r = hx(-0.38);
    const key = `${e.a.kind}>${e.b.kind}`;
    const lab = LABEL[key] ?? { dx: 0, dy: 5, anchor: "middle" };
    const mx = (p1[0] + p2[0]) / 2 + lab.dx, my = (p1[1] + p2[1]) / 2 + lab.dy;
    const d = `M${f1(p1[0])} ${f1(p1[1])}L${f1(p2[0])} ${f1(p2[1])}`;
    out += `<g class="edge${e.i === defaultIndex ? " is-on" : ""}" data-i="${e.i}" data-level="${e.level}" aria-hidden="true">` +
      `<path class="hit" d="${d}"/><path class="line" d="${d}"/>` +
      `<polygon class="head" points="${f1(p2[0])},${f1(p2[1])} ${f1(l[0])},${f1(l[1])} ${f1(r[0])},${f1(r[1])}"/>` +
      `<text class="tag${LABEL[key] && lab.anchor === "middle" ? " off" : ""}" x="${f1(mx)}" y="${f1(my)}" text-anchor="${lab.anchor}">${esc(e.relationship)}</text></g>\n`;
  }
  for (const n of nodes) {
    if (n.kind === "Namespace") continue;
    const deg = edges.filter((e) => e.a === n || e.b === n).length;
    if (n.virtual) {
      out += `<g class="node boundary" data-id="${n.key}" tabindex="0" role="button" aria-pressed="false" aria-label="${esc(n.name)} · Unavailable · no lines into it">` +
        `<rect class="area" x="${n.x}" y="${n.y}" width="${n.w}" height="${n.h}"/>` +
        `<rect class="hatched" fill="url(#hatch)" x="${n.x}" y="${n.y}" width="${n.w}" height="${n.h}"/>` +
        `<rect class="plate" x="${n.x + n.w / 2 - 216}" y="${n.y + 8}" width="432" height="${n.h - 16}"/>` +
        `<text x="${n.x + n.w / 2}" y="${n.y + 31}" text-anchor="middle"><tspan class="nm">${esc(n.name)}</tspan> · Unavailable · no lines into it</text>` +
        `<rect class="ring" x="${n.x - 4}" y="${n.y - 4}" width="${n.w + 8}" height="${n.h + 8}"/></g>\n`;
      continue;
    }
    out += `<g class="node${litDefault.has(n.key) ? " is-on" : ""}" data-id="${n.key}" tabindex="0" role="button" aria-pressed="false" aria-label="${esc(n.name)} ${esc(SHORT[n.kind] ?? n.kind)}${SHORT[n.kind] ? ` (${esc(n.kind)})` : ""}, ${deg} relationship${deg === 1 ? "" : "s"}">` +
      `<rect class="box" x="${n.x}" y="${n.y}" width="${n.w}" height="${n.h}"/>` +
      `<text><tspan class="nm" x="${n.x + 8}" y="${n.y + 21}">${esc(n.name)}</tspan> <tspan class="kind" x="${n.x + 8}" y="${n.y + 40}">${esc(SHORT[n.kind] ?? n.kind)}</tspan></text>` +
      `<rect class="ring" x="${n.x - 5}" y="${n.y - 5}" width="${n.w + 10}" height="${n.h + 10}"/></g>\n`;
  }
  out += `</svg>`;
  return out;
}

// ---- level swatches ----------------------------------------------------------------------------
const swatch = (level, w, h, cls = "") => {
  if (level === "unavailable") return `<svg class="${cls}" viewBox="0 0 ${w} ${h}" aria-hidden="true"><rect class="hatch-swatch" fill="url(#hatch)" x="1" y="1" width="${w - 2}" height="${h - 2}"/></svg>`;
  return `<svg class="${cls}" viewBox="0 0 ${w} ${h}" aria-hidden="true"><line class="lvl-line lvl-${level}" x1="1" x2="${w - 1}" y1="${h / 2}" y2="${h / 2}"/></svg>`;
};
const HOW = { observed: "solid line", declared: "long dashes", inferred: "dotted line", unavailable: "hatched area" };
const counts = Object.fromEntries(LEVELS.map((l) => [l, edges.filter((e) => e.level === l).length]));
counts.unavailable = nodes.filter((n) => n.level === "unavailable").length;
const COUNT_WORD = (l) => (l === "unavailable" ? `${counts[l]} area` : `${counts[l]} lines`);

const legend = LEVELS.map((l) =>
  `        <button type="button" class="lg" data-level="${l}" aria-pressed="false" disabled>${swatch(l, 44, 14)}` +
  `<span><strong>${LEVEL_NAME[l]}</strong><span class="dot"> · </span><span class="n">${COUNT_WORD(l)}</span><span class="how">${HOW[l]}</span></span></button>`).join("\n");

const LEVEL_TEXT = {
  observed: "What the API reports. A Pod’s <code>spec.nodeName</code> names its Node; an owner reference names its owner.",
  declared: "A reference written into one resource that names another, such as an Ingress backend or a volume claim. An Ingress backend is a declaration only: request routing is not proven.",
  inferred: "A client-side match, such as a selector matching Pod labels. Label selection does not prove traffic or endpoint readiness.",
  unavailable: "An input the app does not have, such as provider-managed control-plane internals. In the diagram above it is a hatched, labelled area with no lines into it.",
};
const levels = LEVELS.map((l) =>
  `      <li><div class="row">${swatch(l, 56, 16)}<span class="name">${LEVEL_NAME[l]}</span></div><p>${LEVEL_TEXT[l]}</p></li>`).join("\n");

// ---- the relationship list ------------------------------------------------------------------------
const pair = (n) => (n.virtual ? `<span class="nw">${esc(n.name)}</span>` : `<span class="nw"><span class="k">${esc(n.kind)}</span> ${esc(n.name)}</span>`);
const contained = edges.filter((e) => e.relationship === "containedIn");
const nsNode = nodes.find((n) => n.kind === "Namespace");
if (contained.length && new Set(contained.map((e) => `${e.level}|${e.sourceField}|${e.joinRule}|${e.b.key}`)).size !== 1) {
  throw new Error("containedIn edges differ; cannot fold them into one row");
}
const cell = (e, rowIds, first) =>
  `          <tr data-i="${rowIds.join(" ")}"${rowIds.includes(defaultIndex) ? ' class="is-on"' : ""}>` + first +
  `<td class="mono" data-label="Relationship">${esc(e.relationship)}</td>` +
  `<td data-label="Evidence"><span class="lvl">${swatch(e.level, 30, 10)}${LEVEL_NAME[e.level]}</span></td>` +
  `<td class="mono" data-label="Source field">${esc(e.sourceField)}</td>` +
  `<td data-label="Join rule">${esc(e.joinRule)}${e.assumption ? `<span class="assume"><b>Assumption</b> ${esc(e.assumption)}</span>` : ""}</td></tr>`;
const rowParts = [];
let groupDone = false;
for (const e of edges) {
  if (e.relationship === "containedIn") {
    if (groupDone) continue;
    groupDone = true;
    const names = contained.map((c) => `<span class="nw">${esc(nodeLabel(c.a))}</span>`).join(", ");
    rowParts.push(cell(e, contained.map((c) => c.i),
      `<td class="pair" data-label="Line"><span class="nw">${contained.length} resources in namespace ${esc(nsNode.name)}</span><span class="names">${names}</span></td>`));
  } else {
    rowParts.push(cell(e, [e.i],
      `<td class="pair" data-label="Line">${pair(e.a)}<span class="arrow-t" aria-hidden="true">→</span><span class="vh"> to </span>${pair(e.b)}</td>`));
  }
}
const rows = rowParts.join("\n");

const edgeText = (e) => {
  let h = `<b>${esc(nodeLabel(e.a))} → ${esc(nodeLabel(e.b))}</b> · ${esc(e.relationship)} · <span class="sel">${LEVEL_NAME[e.level]}</span>`;
  h += `<br>Source field: ${esc(e.sourceField)}<br>Join: ${esc(e.joinRule)}`;
  if (e.assumption) h += `<br>Assumption: ${esc(e.assumption)}`;
  return h;
};

const graphJson = JSON.stringify({
  defaultSelected: defaultIndex,
  contained: contained.map((c) => c.i),
  nodes: nodes.map((n) => ({ id: n.key, kind: n.kind, name: n.name, virtual: n.virtual })),
  edges: edges.map((e) => ({ from: e.a.key, to: e.b.key, rel: e.relationship, level: e.level, field: e.sourceField, join: e.joinRule, assume: e.assumption ?? "" })),
}).replace(/</g, "\\u003c");

// ---- survey-pass timing, generated so the CSS needs no inline styles --------------------------------
const LEVEL_DELAY = { observed: 0, declared: 0.4, inferred: 0.8 };
const delays = edges.filter((e) => e.relationship !== "containedIn").map((e) => {
  const mx = (centre(e.a)[0] + centre(e.b)[0]) / 2;
  const d = (mx / VIEW.w) * 0.4 + LEVEL_DELAY[e.level];
  return `.chart.surveying .edge[data-i="${e.i}"] { --d: ${d.toFixed(2)}s; }`;
}).join("\n");

// ---- dates and signals ----------------------------------------------------------------------------
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const fmt = (iso) => {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
};
const time = (iso) => (fmt(iso) ? `<time datetime="${esc(iso)}">${fmt(iso)}</time>` : "No data");
const snapshotIso = gh?.generated_at;
const snapshotDate = fmt(snapshotIso) ?? "date unknown";
const nodata = "No data";
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);

const sig = (name, value) => `      <div><dt>${name}</dt><dd>${value}</dd></div>`;
const signals = [
  sig("Latest commit on main", gh?.commit?.sha ? `<span class="mono">${esc(gh.commit.sha)}</span> · ${time(gh.commit.date)}` : nodata),
  sig("CI on main", gh?.ci?.conclusion
    ? `${esc(cap(gh.ci.conclusion))}, <a href="${esc(gh.ci.url)}">${esc(gh.ci.name)}</a> · ${time(gh.ci.created_at)}`
    : nodata),
  sig("Release", gh?.release ? (gh.release.tag ? `${esc(gh.release.tag)} · ${time(gh.release.published_at)}` : `No release yet · checked ${time(snapshotIso)}`) : nodata),
  sig("Licence", gh?.license ? `${esc(gh.license)} · checked ${time(snapshotIso)}` : nodata),
].join("\n");

let deploySha = "No data";
try { deploySha = execSync("git rev-parse --short HEAD", { cwd: root, encoding: "utf8" }).trim() || deploySha; } catch { /* keep No data */ }
const buildDate = fmt(new Date().toISOString());

// ---- shared defs ------------------------------------------------------------------------------------
const defs = `<svg class="defs" width="0" height="0" aria-hidden="true" focusable="false"><defs>
<pattern id="hatch" width="9" height="9" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line class="hatch-line" x1="0" y1="0" x2="0" y2="9"/></pattern>
</defs></svg>`;

// ---- render ---------------------------------------------------------------------------------------
const css = read(join(src, "style.css")).replace(/@asset\/([^)\s]+)/g, (_, p) => {
  if (!urls.has(p)) throw new Error(`missing asset ${p}`);
  return urls.get(p);
}) + `\n/* survey-pass delays, generated by scripts/build.mjs */\n${delays}\n`;
const cssUrl = emit("style.css", Buffer.from(css));
const bootUrl = emit("boot.js", readFileSync(join(src, "boot.js")));
const appUrl = emit("app.js", readFileSync(join(src, "app.js")));

const mapnote = `The seven containedIn relationships are drawn as the dotted namespace boundary, not as lines. All seven are in the list. Completeness: ${graph.completeness}, with ${graph.unresolvedReferences} unresolved references.`;

const SITE = "https://kubecompass.hamardikan.com/";
const REPO = "https://github.com/hmrdkn-labs/kubecompass";
const DESC = "KubeCompass is a Kubernetes GUI for macOS. Its topology map tags each relationship Observed, Declared, Inferred or Unavailable. Build it from source.";
const person = { "@type": "Person", name: "Azzam Muhammadi Rizqun Karima", url: "https://hamardikan.com/" };
const jsonld = JSON.stringify({
  "@context": "https://schema.org",
  "@graph": [
    { "@type": "WebSite", "@id": `${SITE}#website`, name: "KubeCompass", url: SITE, inLanguage: "en", publisher: person },
    { "@type": "SoftwareApplication", "@id": `${SITE}#app`, name: "KubeCompass", description: DESC, url: SITE,
      applicationCategory: "DeveloperApplication", operatingSystem: "macOS 26 or later", codeRepository: REPO,
      sameAs: [REPO], author: person, publisher: person, isPartOf: { "@id": `${SITE}#website` } },
  ],
}).replace(/</g, "\\u003c");

const vars = {
  jsonld, desc: DESC,
  css: cssUrl, boot: bootUrl, app: appUrl, defs, legend, levels, rows, map: chart(), mapnote,
  readout: edgeText(edges[defaultIndex]), graphjson: graphJson, completeness: esc(graph.completeness), unresolved: String(graph.unresolvedReferences), edgecount: String(edges.length), containedcount: String(contained.length),
  snapshotdate: snapshotDate, signals, checked: snapshotDate, deploysha: esc(deploySha), builddate: buildDate,
};
let html = read(join(src, "index.template.html"));
html = html.replace(/\{\{font:([^}]+)\}\}/g, (_, f) => urls.get(`fonts/${f}`));
html = html.replace(/\{\{img:([^}]+)\}\}/g, (_, f) => { if (!urls.has(`img/${f}`)) throw new Error(`missing image ${f}`); return urls.get(`img/${f}`); });
html = html.replace(/\{\{(\w+)\}\}/g, (m, k) => { if (!(k in vars)) throw new Error(`unfilled ${m}`); return vars[k]; });
writeFileSync(join(pub, "index.html"), html);

// ---- static files that carry the build date -------------------------------------------------------
for (const f of ["404.html", "favicon.svg", "robots.txt", "_headers"]) copyFileSync(join(src, f), join(pub, f));
const iso = new Date().toISOString().slice(0, 10);
writeFileSync(join(pub, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n  <url><loc>https://kubecompass.hamardikan.com/</loc><lastmod>${iso}</lastmod></url>\n</urlset>\n`);
// IndexNow key file: src/<32 hex>.txt is copied to the site root unchanged.
for (const f of readdirSync(src)) if (/^[0-9a-f]{32}\.txt$/.test(f)) copyFileSync(join(src, f), join(pub, f));
for (const f of ["og.png", "apple-touch-icon.png"]) if (existsSync(join(src, f))) copyFileSync(join(src, f), join(pub, f));
// 404 page uses the same stylesheet.
writeFileSync(join(pub, "404.html"), read(join(pub, "404.html")).replace("{{css}}", cssUrl));
console.log(`built public/index.html (${(Buffer.byteLength(html) / 1024).toFixed(1)} KB), css ${cssUrl}`);
