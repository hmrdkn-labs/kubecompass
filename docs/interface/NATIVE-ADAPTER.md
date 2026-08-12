# Native adapter contract

The Interface IR uses `platform: "webapp"` only because the v1 schema has no
native-desktop enum. This is the nearest application-platform value, not a
claim that KubeCompass is a browser app. The runtime targets are explicitly:

| Runtime | Adapter | Status | Boundary |
| --- | --- | --- | --- |
| macOS | SwiftUI/AppKit | observed reference | Preserve the existing K-Dex shell and controls. |
| Linux | Makoni / Swift Adwaita, pinned `e725f39c4308138da251a8181beb0a40d86efea9` | fixture slice packages and launches; full route parity pending | Native GTK4/libadwaita view adapter on Ubuntu 24.04, Swift 6.3, libadwaita 1.5. SwiftUI source compatibility is absent. |
| headless/SSH | optional CLI/TUI companion | not MVP | Share commands and state where useful; do not target k9s parity. |

Topology Explorer follows the same boundary: the current SwiftUI Map/List
route is macOS-only. Linux can consume the portable evidence graph and input
status contracts, but it has no implemented GTK topology view or parity proof.

## ADR-001: choose native GTK4/libadwaita for Linux

**Decision (2026-08-12):** use Makoni/Swift Adwaita at commit
`e725f39c4308138da251a8181beb0a40d86efea9` as the Linux view-adapter
baseline. The Ubuntu 24.04 / Swift 6.3 / libadwaita 1.5 fixture slice passed
dual-architecture build, package, install, and launch gates, proving the native
GTK4/libadwaita integration path. This decision does not claim that
SwiftUI view source compiles on Linux, nor that the complete Linux GUI or
live-cluster workflow parity is finished.

**Why:** a native GTK4/libadwaita surface is available on Linux and keeps the
platform boundary honest. SwiftCrossUI GTK remains a rejected baseline for this
milestone because its pre-1.0 table and shortcut gaps were not the selected
evidence path. The shared Foundation core remains the parity anchor; adapter
views may be rewritten.

**Evidence boundary:** the current macOS Swift 6.3.3 `swift test` run passed 23
tests (11 existing core, 3 Linux launch-option, and 9 topology graph tests).
The deterministic trace remains a shared-core fixture, and observed macOS
debug runs built the 10,000-node topology fixture in about 1.6–5.36s under the
10s gate. These are not live-cluster or GUI-render measurements. Fresh Linux
amd64 and arm64 runs passed the same 23 package tests, built the GTK fixture
app, launched its 10-surface smoke window, and produced Debian packages. Full
Linux topology route/state coverage, accessibility/keyboard review, startup,
RSS, and live-cluster behavior remain pending.

## 1:1 definition

- **Functional parity:** identical Kubernetes workflows, command semantics,
  fixture outcomes, loading/error/reconnect behavior, and destructive-action
  safety.
- **Interaction parity:** identical information architecture, focus order,
  keyboard command map, selection/filter semantics, tab routing, and retry or
  cancellation behavior. Platform idioms may differ.
- **Visual parity:** shared tokens, density, hierarchy, icon intent, and
  responsive states. Native GTK and SwiftUI widgets are allowed to render
  differently; pixel-identical controls are explicitly out of scope.
- **Source parity:** shared domain, transport, stores/view models, command
  registry, fixtures, and tokens. Keep adapter-specific view code isolated.
  The spike target is at least 80% shared non-UI behavior and 50% shared
  view-model code, measured from the changed surface.

## Adapter validation and remaining gates

The toolkit choice is no longer pending. Validate the pinned adapter with the
same fixture-backed probes:

1. Sidebar/context switching and detail routing.
2. Resource table sort/filter/select plus loading, empty, and error states.
3. Streaming logs/events with cancel and reconnect.
4. Keyboard shortcuts and focus traversal, including the resource palette.
5. Clean Linux packaging/startup and watch-state resilience.

Record functional, interaction, visual-token, accessibility/keyboard,
startup/RSS, and packaging results. The current fixture slice is evidence for the
native adapter and package path only; it is not evidence that every
screen/state is built.

## Gates and stop line

- Current macOS, Linux amd64, and Linux arm64 `swift test` runs each pass 23
  tests, including the nine topology graph tests. The Linux smoke remains a
  fixture app; run GTK topology UI gates before claiming route parity.
- A deterministic 15-step context-to-logs/reconnect trace is stable, and the
  observed local 10k-row table p95 range is 37.98–100.67ms under the 150ms budget.
- Ubuntu 24.04 Swift 6.3/libadwaita 1.5 builds, native window smoke, Debian
  packaging, and fresh-container installation pass on amd64 and arm64.
- Full Linux GUI routes/states, accessibility/keyboard review, startup/RSS,
  and live-cluster behavior remain pending. Do not infer them from the
  fixture-only package.
- Topology Explorer's Map/List route is a macOS SwiftUI implementation. Linux
  currently has only the shared graph/core contracts; no GTK topology screen or
  live-cluster route validation is evidenced.
- Every probe has a traceable result and a screenshot/state review for
  hierarchy—not pixel identity.
- If the pinned adapter fails a remaining gate, retain macOS SwiftUI and defer
  the affected Linux surface. A small shared CLI may ship for diagnostics, but
  do not start a full TUI clone.
