# KubeCompass landing page: notes

Live: https://kubecompass.hamardikan.com/ · Worker `kubecompass-site` (static assets only). v3 (search) deployed 2026-11-25, version `6b6b6de7-e9ef-4796-a6f2-c701f6c94bbf` (footer sha 3ec7055); v2 was `8e99441b-e789-472f-9287-487727c82325`.
Planned 2026-11-25 from `~/workspace/sandbox/showcase-scan/research/kubecompass.md`, the card, and
the public repo at `origin/main` 0e10edb. The local checkout `~/workspace/labs/kubecompass` and its
48 uncommitted paths are not a source for anything on this page.

## Concept (v2)

Owner verdict on v1 (2026-11-25): "those are all really bad". v2 throws away the chart-paper look and
keeps the facts, the demo graph pipeline and the deploy plumbing. Rule book:
`~/workspace/sandbox/showcase-scan/build/v2/SKILL-gemini-frontend-design.md`; spec:
`~/workspace/sandbox/showcase-scan/build/v2/kubecompass/DIRECTION.md`.

One idea, unchanged: the map says how it knows each line (Observed, Declared, Inferred, Unavailable)
and leaves unknown water unknown. v2 puts that idea in a container terminal at blue hour.

- **Materials and colour:** deep marine water, cold steel, sodium-amber quay lights. One dark theme.
  Tokens in `src/style.css`: `--bg #071a24`, `--surface #0e2a38`, `--text #e6f0f2` (15.3:1 on bg),
  `--muted #93adb8` (7.5:1), `--accent #f2b33d` (9.6:1; button text on it is `#071a24`, 9.6:1),
  `--declared #78c6ea` (9.4:1), `--hatch #5e7a87` (3.9:1, decoration only; the word sits beside it).
  No beige, no purple, no glow.
- **Type:** Bricolage Grotesque (variable 600 to 800, display, wordmark) and Atkinson Hyperlegible Next
  (400, 600, everything else, tabular numerals). No monospace. Sizes below the hero: h2 `clamp(2rem, 4vw, 3.25rem)`,
  body 18 px, small 15 px. h3, labels and buttons differ by weight only. Hero h1 `clamp(3.5rem, 7.5vw, 8rem)`.
- **Hero:** centred monumental headline over a full-bleed generated harbour image from y = 0, borderless header
  (surface and 1 px rule once scrolled), one amber button. The demo graph rises from the lower third as the stage.
- **Stage:** the real demo graph (`data/demo-graph.json`) as inline SVG on a surface panel. Legend is one connected
  segmented control of four `aria-pressed` toggles. Line language is unchanged: solid, long dash (blue), dots (amber),
  hatched area; never colour alone. Readout and the full 18-row list sit under the map. Phone: the list is the object
  and the map is behind "Show the map".
- **Motion:** h1 words rise once (400 ms stagger); edges ink in by evidence level once (under 1.6 s). Both gated on `.js`
  and `prefers-reduced-motion: no-preference`; the finished state is the default markup.
- **Images** (generate_image, illustration only, never captioned as product or data; originals in `src/img-src/`,
  gitignored): `hero-harbour` 16:9, `fog-channel` 3:2, `drydock` 3:2. AVIF and WebP, `srcset`, explicit width and height.
  The drydock sky was desaturated 20 % to keep pink out of the set. Real captures (`topology-*.webp`) are unchanged.

## Copy

Every sentence maps to a claims row below. Hero: "A cluster map that tells you how it knows." and one line
(rows 1, 2). Sections: Each line says how it was found (24, 23, 27); The same map in the app (17, 25); What the map will
not guess (4, 5, 6, 7); Runs on the access you already have (8, 10, 11, 14, 22); Build it yourself (9, 12, 13, 21, 28);
footer (15, 18, 20).

## Claims table

Every row checked against `origin/main` 0e10edb on 2026-11-25.

| # | Claim on the page | Source | How a reader checks it | Status |
|---|---|---|---|---|
| 1 | Kubernetes desktop client for macOS | README.md 5–6; GitHub description | Read the README | OK |
| 2 | Topology map tags each relationship Observed, Declared, Inferred or Unavailable | README 18–22; `TopologyGraph.swift` 8–13; ADR 0001 | Read the enum and the ADR | OK |
| 3 | Missing inputs are shown as missing, not drawn as complete | ADR 0001 "Consequences"; README 76–78 | Read the ADR | OK |
| 4 | Topology Explorer is read-only | README 18, 69; ADR 0001 | Read the README | OK |
| 5 | Traffic is unavailable without a telemetry adapter | README 22–23, 75–76 | Read the README | OK |
| 6 | Selectors and Ingress backends are configuration, not proof of traffic | ADR 0001; edge `assumption` fields in demo-graph.json | Run `site/scripts/demo-graph.sh` | OK |
| 7 | Secret and ConfigMap payloads are never listed for topology | README 78 | Read the README | OK |
| 8 | Uses a bundled kubectl and your kubeconfig auth | README 84–86, 95 | Read the README | OK |
| 9 | Requires macOS 26 or later | README 95 ("macOS 26+"); app target `MACOSX_DEPLOYMENT_TARGET = 26.0` in `k-dex.xcodeproj/project.pbxproj` 287, 344 | `grep -n MACOSX_DEPLOYMENT_TARGET k-dex.xcodeproj/project.pbxproj` (test target is 26.5; not a user requirement) | OK |
| 10 | App Sandbox is off, because it reads `~/.kube` and starts kubectl | README 95–97 | Read the README | OK |
| 11 | Updater is off until a release feed exists | README 79–80 | Read the README | OK |
| 12 | No published release yet; build from source | README 101; `gh release list --repo hmrdkn-labs/kubecompass` returns nothing (2026-11-25) | Run the command | OK |
| 13 | The documented build turns code signing off | README 104–106 (`CODE_SIGNING_ALLOWED=NO`) | Read the README | OK |
| 14 | Linux adapter runs on fixture data only | README 30–33 | Read the README | OK |
| 15 | Derived from K-Dex, MIT, provenance kept | README 8–9, 151–154; UPSTREAM.md; LICENSE | Read UPSTREAM.md | OK |
| 16 | Demo graph: 12 nodes, 18 edges, 12/4/2 Observed/Declared/Inferred (7 Observed are `containedIn`), boundary Unavailable, partial, 2 unresolved | `site/data/demo-graph.json`; `jq '[.edges[].level]\|group_by(.)\|map({(.[0]):length})\|add'` | Run `site/scripts/demo-graph.sh` | OK |
| 17 | Captures are the app on a synthetic fixture | `docs/interface/evidence/*.jpeg` show `topology-lab` / `fixture-cluster` / namespace `demo` | View the images | OK |
| 18 | Signals: CI "macOS stability and topology" success 2026-08-13; latest app commit 0e10edb 2026-08-13 (newest on origin/main outside `site/`); no release; MIT | `git log -1 origin/main -- . ':(exclude)site'`, `gh run list --commit <sha>`, `gh api repos/.../commits/<sha>`, `gh release list`, `gh api repos/...` at build | Re-run the commands | OK (snapshot dated) |
| 20 | "A Hamardikan Labs project" | README.md 8 | Read the README | OK |
| 21 | The README lists what is still unverified: accessibility, frame rate and memory use, live-cluster checks | README.md 27–29 ("accessibility, frame/RSS, and live-cluster gates remain unverified") | Read the README | OK |
| 22 | The Linux adapter reads no kubeconfig and runs no kubectl | README.md 30–33 | Read the README | OK |
| 23 | The seven `containedIn` relationships are drawn as the namespace boundary and listed; Node, PersistentVolume and StorageClass sit outside it | `site/data/demo-graph.json` (7 `containedIn` edges, none from those three kinds) | Run the jq count | OK |
| 24 | Level sentences: Observed = what the API reports, `spec.nodeName`, owner references; Declared = Ingress backend, volume claim, Ingress backend "request routing is not proven"; Inferred = selector match, "does not prove traffic or endpoint readiness"; Unavailable = provider-managed control-plane internals; the hatched, labelled area is the diagram's own convention and the page says "In the diagram above" | `TopologyGraph.swift` 5–13 doc comment; edge `sourceField` and `assumption` in demo-graph.json; README 76–78 | Read both | OK |
| 25 | The second capture is a larger fixture: 15 nodes, 31 relationships | Visible in `topology-relationship-list.jpeg` header bar | View the image | OK |
| 26 | The page makes no live requests; signals are a build-time snapshot | Playwright run: no request outside the origin (Verification) | Open the network panel | OK |
| 27 | Completeness partial, 2 unresolved references | `site/data/demo-graph.json` | Read the file | OK |
| 28 | The documented build line: `xcodebuild -project k-dex.xcodeproj -scheme k-dex -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` | README.md 104–106 at `origin/main` | `git show origin/main:README.md \| sed -n 99,108p` | OK |
| 29 | The harbour, fog and dry dock pictures are generated illustrations with no product claim; their alt text begins "Illustration" or is empty | `src/img-src/` originals; `generate_image` prompts in this branch's history | View the page | OK |

Left off the page (unresolved or out of bounds): notarisation and any peer's signing status;
VoiceOver or any accessibility claim about the app; production-provider conformance; test counts;
kubectl version pins; command limits; metrics lag; the README's verification receipt links that
404 in the local tree (the public README at 0e10edb has none of them; every README link used here
resolves at `origin/main`).
| 30 | Page is a Kubernetes GUI/client for macOS ("GUI" = desktop app, same as claim 1) | README 5–6 | Read the README | OK |
| 31 | The cluster map tags relationships; hero says "draws a cluster map" | README 18–22; claim 2 | Read the README | OK |
| 32 | JSON-LD operatingSystem "macOS 26 or later", author and publisher Azzam Muhammadi Rizqun Karima, codeRepository | claim 9; hamardikan.com owner; repo URL | Read the page source | OK |
| 33 | No softwareVersion, downloadUrl, rating, review or offers in JSON-LD | claim 12 (no release) | Read the page source | OK |
| 34 | Sibling pages named in the footer exist at their hamardikan.com subdomains | v3 STANDARD.md, Links | Open each | OK: all four returned 200 on 2026-11-25 after deploy |

## Search (v3, 2026-11-25)

Title, description, h1, OG, JSON-LD, IndexNow key and sibling links: `~/workspace/sandbox/showcase-scan/build/v3/kubecompass/SEO.md`. `og.png` is a 256-colour PNG (240 KB).
`src/<32 hex>.txt` is the IndexNow key file; `build.mjs` copies it to the site root.

## Real vs missing

- Real: the demo graph (built by the product's own core), four tracked captures, README facts,
  ADR 0001, gh signals.
- Missing: a release, a download, an install path other than building, a recording of the app.
  The page says so; it does not draw a download button.

## Open questions for Dika

1. Requirement: README says macOS 26+, app target 26.0, test target 26.5. The page says 26.
2. Notarisation sentence in LIMITATIONS.md has no source; left off the page.
3. Local-only verification docs and redesign captures: publish or drop. The page uses only tracked
   captures.
4. The README's generated "design-direction preview" image is not used: it is not a capture.

## Build log (v2)

Built 2026-11-25 on branch `landing-v2` from `origin/main`.

- `scripts/build.mjs` is the v1 pipeline: renders `public/index.html` from `src/index.template.html`, `data/demo-graph.json`
  and `data/github.json`. Map SVG, legend, readout and relationship list are static HTML (the page is complete with JS off);
  `app.js` adds the filter, node and row linking, the header rule and the one ink-in. Content-hashed `/assets`, `_headers`
  (CSP unchanged, `no-transform` kept), `wrangler.jsonc` unchanged. Removed: chart ticks, scan line, Literata, Atkinson Mono.
- Fonts: `@fontsource-variable/bricolage-grotesque` and `@fontsource/atkinson-hyperlegible-next`, Latin subset
  (`pyftsubset`, Basic Latin plus a few punctuation marks), OFL texts in `public/assets/fonts/`. 36 KB for three files.
- Images: three `generate_image` calls (one try each, none rejected), exported with `cwebp` and `avifenc`
  (hero 1672, 1440, 800 w; others 1200, 800 w). The model returned 1672 px for 16:9, so the hero's top width is 1672, not 2400.
- Deviations from DIRECTION: (1) the readout sits under the map in the stage, not in section 2, so a click on the map has
  visible feedback; section 2's right column carries the containedIn and completeness facts instead. (2) The "All 18
  relationships" disclosure is in the stage and closed by default on every width (the legend, readout and both disclosures sit above the fold on phone; with JS off the disclosure still opens), not in section 2. (3) Hero image width 1672.
  (4) Hero sub line is 20 px (the hero is exempt from the three-size rule). (5) The stage caption is shown on every width.
- Local server: wrangler 4.82 does not know `compatibility_date 2026-11-01`, so `wrangler dev --local` needs
  `--compatibility-date 2026-04-01` on the command line; `wrangler.jsonc` is untouched.
- `scripts/og.mjs` draws `og.png` (hero image and wordmark) and `apple-touch-icon.png`. The v1 `verify.cjs` is replaced by
  `scripts/audit.cjs`.

## Verification

`wrangler dev --local` on 127.0.0.1 so `_headers` applied. `node scripts/audit.cjs <url> <shots>`; shots and `audit.json`
are in `~/workspace/sandbox/showcase-scan/build/v2/kubecompass/shots/`.

| Check | Result |
|---|---|
| Font families | 2 (Atkinson Hyperlegible Next, Bricolage Grotesque) |
| Font sizes below the hero | 3 (15, 18, 52 px) |
| Smallest text | 15 px at 1440 and 390 |
| Uppercase with letter-spacing, `transition: all`, em or en dashes | none |
| h1 | one, width 1440 px of 1440; the headline text spans 78 % |
| Horizontal overflow at 320, 390, 1440, JS on and off | none |
| axe at 1440 and 390 | 0 violations |
| Console errors, failed or non-2xx requests, requests off origin | none |
| Phone first load, cold, compressed | 68.3 KB over 8 responses (hero AVIF 13.4 KB, Bricolage 22 KB) |
| Lighthouse mobile | performance 100 (one earlier run 93), accessibility 100 |
| Recon grep on `public/index.html` | no IP-shaped strings, ports or long hex ids |

Not measured: GUI frame time on a low-end phone, VoiceOver on the SVG nodes, real-device Safari.

### Live verification (https://kubecompass.hamardikan.com/)

Resolver pinned for curl and Chromium (the address is not stored here). Shots in `shots/live/`.

| Check | Result |
|---|---|
| HTTPS `/` | 200, h2; CSP as committed; `cache-control: public, max-age=0, must-revalidate, no-transform` |
| Served footer | Deploy d9342ea, matches the build |
| Font families, sizes below hero, smallest text | 2 families; 3 sizes (15, 18, 52 px); 15 px |
| Uppercase with letter-spacing, `transition: all`, em or en dashes | none |
| h1 | one, width 1440 px |
| Horizontal overflow at 320, 390, 1440, JS on and off | none |
| axe at 1440 and 390 | 0 violations |
| Console errors, failed or non-2xx requests, requests off origin | none |
| Phone first load, cold, compressed | 153 KB over 11 responses (HTML 36.2 KB, no analytics beacon) |
| Lighthouse mobile | performance 100, accessibility 100 |

## Self-critique

- The hero reads as a poster: image, one headline, one button, the map. The risk is the "dark marine plus amber" palette
  is a familiar developer-tool look; the harbour image and the line language keep it tied to the subject.
- The stage is a rounded panel on an image, the only boxed surface besides the captures band and the command block. No
  nested cards, chips or numbering.
- The levels section is a long left column beside a short sticky note. It reads as editorial, but the right column is
  quiet on a tall screen.
- The drydock picture is the loudest object on the page; it sits at the bottom, next to the button, where it carries the
  "build it yourself" message. It is an illustration and its alt text says so.
- The map layout is still a hand-placed table in `build.mjs`: it only suits this fixture.
- The two app captures are small dark windows (1220 px originals) in a surface band; they contain the app's own purple
  accent, which is real product UI and is left alone.
