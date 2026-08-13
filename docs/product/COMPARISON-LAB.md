# KubeCompass comparison lab

These tools are installed locally so the desktop and terminal approaches can
be compared against the same kubeconfig. Prefer a read-only RBAC context or a
disposable cluster while exploring.

## Launchers

| Product | Surface | Safe starting command | Installed version |
| --- | --- | --- | --- |
| KubeCompass | Native macOS SwiftUI desktop | `kc` | 1.4.0 |
| Headlamp | Cross-platform desktop/web GUI | `open -a Headlamp` | 0.44.0 |
| k9s | Go terminal UI | `k9s --readonly` | 0.51.0 |
| LFK | Go terminal UI | `lfk --read-only` | 0.16.1 |
| KDash | Rust terminal UI | `kdash` | 2.1.1 |

KDash has no command-line read-only switch in this installed version. Run it
only with a read-only Kubernetes identity or against a disposable cluster.
Headlamp and the full macOS KubeCompass app expose guarded mutations, so the
same context caution applies to them.

## What to compare

1. Time to find a context, namespace, and unfamiliar CRD without knowing a
   shortcut first.
2. Resource-table density, sorting, filtering, and detail navigation.
3. Logs, YAML, events, metrics degradation, and reconnect/error feedback.
4. How clearly the current context and mutation target are shown before an
   action.
5. Keyboard-only speed after ten minutes versus first-use discoverability.
6. In Topology Explorer, whether each relationship is clearly labeled
   Observed, Declared, Inferred, or Unavailable, and whether partial RBAC is
   distinguishable from an empty scope.
7. Whether Outline starts with a readable namespace/workload hierarchy, a
   selected root opens a bounded one/two-hop Map, typed Paths expose Port Hops,
   and the persistent inspector plus semantic text fallback retain the same
   evidence at wide and narrow sizes. Traffic remains unavailable unless an
   explicit telemetry source is present.

## Product boundary

KubeCompass is intentionally a desktop product, not another k9s clone. The
macOS surface remains SwiftUI. The Linux surface is native Swift with
GTK4/libadwaita and shares portable state, command, safety, and fixture
contracts; Apple does not provide a SwiftUI Linux backend. The current Linux
package is a fixture-backed vertical slice and does not read kubeconfig or run
kubectl yet. Its topology screen still exposes the historical
ExplorerLevel/ExplorerMode/ExplorerPresentation controls (including Map
fallback, List, and Port table); it has not migrated to the macOS
Outline/selected-root Map/Paths contract.

The macOS Topology Explorer route is read-only and available in the local
1.4.0 build. It builds a sanitized snapshot from allowlisted `kubectl get -o
json` inputs, exposes a virtual control-plane boundary when provider internals
are not represented by the API, and keeps forbidden/unsupported inputs
explicitly partial. Outline is the default surface; selecting a workload or
service opens a bounded one/two-hop Map, and typed Paths provide diagnostic
Port Hop details. A persistent Fundamentals/evidence inspector and semantic
text fallback preserve the same evidence for keyboard and narrow layouts.
Traffic is unavailable without explicit telemetry, and selectors, owner refs,
Routes, and EndpointSlices are not treated as traffic proof. The route does
not list Secret or ConfigMap payloads and does not claim packet flow, CNI
enforcement, provider-network internals, arbitrary production-cluster fidelity,
frame/RSS, or complete VoiceOver coverage. A new macOS shell launch against a
deterministic fixture is observed, but the original wide/narrow reference
matrix and state, accessibility, frame/RSS, and live-cluster gates remain
unverified.
Linux has a fixture-only GTK topology route wired to the shared graph; full
route/state, live-cluster, accessibility, and visual parity remain pending.

The exact current package/test result belongs in the verification receipt.
Earlier graph/table benchmarks remain fixture/core evidence rather than GUI
render or live-cluster performance evidence.

The Linux fixture package has its own pre-parity version line (`0.2.x`). It is
not the macOS product version and should not be read as feature parity.

k9s, KDash, and LFK are stronger choices today for SSH and keyboard-first
terminal work. Headlamp is the closest installed GUI benchmark. A future `kc`
headless CLI can complement the desktop app, but a full TUI is outside the
current MVP unless it demonstrates a workflow those tools do not already
serve.
