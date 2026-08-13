# Native adapter contract

The Interface IR uses `platform: "webapp"` only because the v1 schema has no
native-desktop enum. This is the nearest application-platform value, not a
claim that KubeCompass is a browser app. The runtime targets are explicitly:

| Runtime | Adapter | Status | Boundary |
| --- | --- | --- | --- |
| macOS | SwiftUI/AppKit | observed reference | Preserve the existing K-Dex shell and controls. |
| Linux | Makoni / Swift Adwaita, pinned `e725f39c4308138da251a8181beb0a40d86efea9` | fixture topology route/packages launch; full route parity pending | Native GTK4/libadwaita view adapter on Ubuntu 24.04, Swift 6.3, libadwaita 1.5. SwiftUI source compatibility is absent. |
| headless/SSH | optional CLI/TUI companion | not MVP | Share commands and state where useful; do not target k9s parity. |

Topology Explorer follows the same boundary, but the adapters are not yet at
parity. The macOS SwiftUI route implements the chosen Outline default,
selected-root Map, typed Paths, and persistent inspector intent. Narrow
navigation pushes detail with an explicit back path. Linux has a fixture-only
GTK route wired to shared graph data, not live-cluster or full parity evidence;
its currently observed controls still use the historical ExplorerLevel,
ExplorerMode, and ExplorerPresentation controls described below.

## Topology adapter contract (target)

The following is the migration target for both adapters. It is not a claim
that the current Linux fixture already renders this contract.

Both adapters must render the same portable topology intent:

- Outline is the default deterministic namespace/workload/dependent surface.
- Map is selected-root only and bounded to one or two relationship hops.
- Paths is the typed Route/Service/EndpointSlice/Pod-container and dependency
  diagnostic surface.
- A persistent inspector carries selection, Snapshot/Exposure Status,
  provenance, unavailable inputs, and proof/non-proof copy across surfaces.
- Outline is the canonical keyboard semantic hierarchy; Paths is the canonical
  typed diagnostic list. Both retain a persistent inspector, with no separate
  List or Port Table fallback surface.
- At narrow widths, push navigation preserves scope, selection, and an explicit
  back path.
- Port Paths: typed Port Hops from Route/Service through targetPort and
  EndpointSlice to declared container ports, preserving unresolved and
  ambiguous states.
- Learner copy: “What this proves” and “What this does not prove” for every
  selected relationship, Route, and Port Path.

## Current Linux fixture vocabulary (observed, pre-parity)

`Sources/KubeCompassLinux/App/main.swift` currently exposes six
`ExplorerLevel` buttons (Cluster, Infrastructure, Workloads, Network, Policy &
Dependencies, Evidence), three `ExplorerMode` buttons (Focus, Trace,
Inventory), and three `ExplorerPresentation` buttons (Map fallback, List, Port
table). The Map option is a deterministic grouped list because geometry is
intentionally unavailable in this fixture build. This is historical fixture
vocabulary, not a second product contract; migration to Outline, selected-root
Map, and Paths is pending. Linux smoke results must therefore be reported as
fixture/package evidence only and must not be described as current topology UI
parity.

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
6. Topology Explorer Outline, selected-root node/fanout-bounded Map with
   visible truncation and Outline handoff, typed Paths, and persistent
   inspector across ready, partial, empty, loading, stale, offline,
   reconnecting, error, narrow, and wide fixtures. The current Linux route is
   fixture-only and does not satisfy live-cluster parity.
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
- Topology Explorer's macOS SwiftUI implementation exposes Outline,
  selected-root node/fanout-bounded Map, typed Paths, persistent inspector,
  and typed Port Paths. A new macOS shell launch against a
  deterministic fixture is observed, but the original wide/narrow reference
  matrix is incomplete. Linux has a fixture-only GTK topology route using the
  pre-parity ExplorerLevel/ExplorerMode/ExplorerPresentation controls described
  above. Neither adapter has full live production-route parity,
  GUI frame/RSS evidence, complete accessibility review, or full visual/state
  matrix evidence.
- Every probe has a traceable result and a screenshot/state review for
  hierarchy—not pixel identity.
- If the pinned adapter fails a remaining gate, retain macOS SwiftUI and defer
  the affected Linux surface. A small shared CLI may ship for diagnostics, but
  do not start a full TUI clone.
