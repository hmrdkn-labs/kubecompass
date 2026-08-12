# Native adapter contract

The Interface IR uses `platform: "webapp"` only because the v1 schema has no
native-desktop enum. This is the nearest application-platform value, not a
claim that KubeCompass is a browser app. The runtime targets are explicitly:

| Runtime | Adapter | Status | Boundary |
| --- | --- | --- | --- |
| macOS | SwiftUI/AppKit | observed reference | Preserve the existing K-Dex shell and controls. |
| Linux | Makoni / Swift Adwaita, pinned `e725f39c4308138da251a8181beb0a40d86efea9` | fixture topology route/packages launch; full route parity pending | Native GTK4/libadwaita view adapter on Ubuntu 24.04, Swift 6.3, libadwaita 1.5. SwiftUI source compatibility is absent. |
| headless/SSH | optional CLI/TUI companion | not MVP | Share commands and state where useful; do not target k9s parity. |

Topology Explorer follows the same boundary: the macOS SwiftUI route now
implements the semantic Explorer Level contract, typed Port Paths, and the
three-pane/narrow stacked shell. Linux has a fixture-only GTK topology route
wired to shared graph data, not live-cluster or full parity evidence.

## Topology adapter contract

Both adapters must render the same portable topology intent:

- Explorer Levels: Cluster, Infrastructure, Workloads, Network, Policy &
  Dependencies, and Evidence.
- Modes: Focus, Trace, and Inventory.
- Views: Map, List, and Port Table with equivalent selection, filtering,
  Snapshot Status, Exposure Status, and evidence copy.
- Shell: scope rail, exploration canvas, and evidence inspector. At narrow
  widths the panes may collapse, but the information order and back path stay
  intact.
- Port Paths: typed Port Hops from Route/Service through targetPort and
  EndpointSlice to declared container ports, preserving unresolved and
  ambiguous states.
- Learner copy: “What this proves” and “What this does not prove” for every
  selected relationship, Route, and Port Path.

Native widgets, map geometry, and typography may differ between SwiftUI and
GTK. Functional, interaction, semantic-token, evidence, focus, keyboard,
accessibility, and state parity may not.

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

**Evidence boundary:** the current package suite and fixture builds are
recorded in the verification receipt. The deterministic trace and earlier
shared graph/table benchmarks remain bounded fixture evidence, not live-cluster
or GUI-render measurements. Fresh Linux amd64 and arm64 fixture runs have
passed their package/build/window smoke gates and produced Debian packages.
Full Linux topology route/state coverage, accessibility/keyboard review,
startup, RSS, and live-cluster behavior remain pending.

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
6. Topology Explorer levels, breadcrumb, Focus/Trace/Inventory modes, and
   Map/List/Port Table equivalence across ready, partial, empty, loading,
   stale, offline, reconnecting, error, narrow, and wide fixtures. The current
   Linux route is fixture-only and does not satisfy live-cluster parity.
7. Port Path fixtures for numeric/named/ambiguous target ports, EndpointSlice
   readiness, multiple protocols, and declared container ports.

Record functional, interaction, visual-token, accessibility/keyboard,
startup/RSS, and packaging results. The current fixture slice is evidence for the
native adapter and package path only; it is not evidence that every
screen/state is built.

## Gates and stop line

- Current macOS, Linux amd64, and Linux arm64 package suites and fixture smoke
  are separate evidence gates; cite the verification receipt for the exact
  command result. The Linux topology route remains fixture-only.
- A deterministic context-to-logs/reconnect trace and earlier local 10k-row
  table benchmark remain bounded shared-core evidence, not GUI smoothness
  evidence.
- Ubuntu 24.04 Swift 6.3/libadwaita 1.5 builds, native window smoke, Debian
  packaging, and fresh-container installation pass on amd64 and arm64.
- Full Linux GUI routes/states, accessibility/keyboard review, startup/RSS,
  and live-cluster behavior remain pending. Do not infer them from the
  fixture-only package.
- Topology Explorer's macOS SwiftUI implementation now exposes Explorer Levels,
  Focus/Trace/Inventory, Map/List/Port Table, and typed Port Paths. A
  deterministic wide Port Table fixture has been runtime-reviewed, and the
  fixture API shapes passed a disposable kind-cluster run. Linux has a
  fixture-only GTK topology route wired to shared graph data. Neither adapter
  has full live production-route parity, GUI frame/RSS evidence, complete
  VoiceOver review, or full visual/accessibility state-matrix evidence.
- Every probe has a traceable result and a screenshot/state review for
  hierarchy—not pixel identity.
- If the pinned adapter fails a remaining gate, retain macOS SwiftUI and defer
  the affected Linux surface. A small shared CLI may ship for diagnostics, but
  do not start a full TUI clone.
