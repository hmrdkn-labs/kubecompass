# KubeCompass repository rules

## Product boundary

KubeCompass is the planned cross-platform successor to K-Dex. The current
macOS SwiftUI application is the observed product reference; this repository's
interface contract must preserve its workflows before adding Linux support.

## Platform boundary

- Keep Kubernetes domain models, transport/`kubectl` orchestration, async state,
  command definitions, fixtures, and design tokens platform-neutral.
- Keep the existing macOS SwiftUI shell as one adapter.
- Add Linux through the pinned native GTK4/libadwaita adapter: Makoni/Swift
  Adwaita at commit `e725f39c4308138da251a8181beb0a40d86efea9`. SwiftUI source
  compatibility is explicitly absent; do not assume SwiftUI itself is
  available on Linux. The Ubuntu 24.04 / Swift 6.3 / libadwaita 1.5 vertical
  slice builds, packages, installs, and launches on amd64 and arm64, but this
  is not full Linux route or workflow parity.
- Native controls may differ. "1:1" means functional, interaction, visual
  hierarchy/token, and source-sharing parity as defined in
  `docs/interface/NATIVE-ADAPTER.md`; it never means pixel-identical controls.

## Evidence and content

- Treat `docs/interface/PROVENANCE.md` and the Interface IR as the evidence
  boundary. Mark gaps `partial` or `missing`; do not turn inference into a
  product claim.
- Product wording and claim limits live in `docs/product/PRODUCT-TRUTH.md`.
- Topology language, evidence levels, state copy, and sensitive-data boundary
  live in `docs/product/TOPOLOGY-EXPLORER.md` and `CONTEXT.md`. Do not describe
  selectors or object references as traffic, connectivity, or packet truth.
- Every major route must cover loading, empty, error, offline/reconnecting,
  permission, confirmation, and success states where applicable.

## Verification gates

Run `bash scripts/validate-interface.sh` after interface edits. It must invoke
the canonical `engineer-interfaces` validator. Also parse both JSON documents
with Python's standard library. The shared package passes 23/23 tests on macOS,
Linux amd64, and Linux arm64; the deterministic trace has 15 steps and the
observed local 10k-row p95 range was 37.98–100.67ms under the 150ms budget. Both Debian
packages build and launch after fresh-container installation. Full Linux route
parity, accessibility/keyboard review, startup, and RSS remain pending.

## Scope and safety

Do not print kubeconfig contents, tokens, secret manifests, private keys, or
cluster dumps. Keep CLI/TUI work optional and companion-only; it is not a
replacement for the desktop GUI or a k9s clone.

Topology shared state may contain only typed, allowlisted relationship fields.
Never retain raw YAML/JSON, annotations, Secret or ConfigMap values, raw command
diagnostics, or provider credentials in the graph. Forbidden and unsupported
inputs are explicit partial state, not empty data.
