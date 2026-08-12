# KubeCompass comparison lab

These tools are installed locally so the desktop and terminal approaches can
be compared against the same kubeconfig. Prefer a read-only RBAC context or a
disposable cluster while exploring.

## Launchers

| Product | Surface | Safe starting command | Installed version |
| --- | --- | --- | --- |
| KubeCompass | Native macOS SwiftUI desktop | `kc` | 1.3.0 |
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
7. Whether the List mode is a useful keyboard/accessibility fallback when the
   lane map is capped or visually dense.

## Product boundary

KubeCompass is intentionally a desktop product, not another k9s clone. The
macOS surface remains SwiftUI. The Linux surface is native Swift with
GTK4/libadwaita and shares portable state, command, safety, and fixture
contracts; Apple does not provide a SwiftUI Linux backend. The current Linux
package is a fixture-backed vertical slice and does not read kubeconfig or run
kubectl yet.

The macOS Topology Explorer route is read-only and available in the local
1.3.0 build. It builds a
sanitized snapshot from allowlisted `kubectl get -o json` inputs, exposes a
virtual control-plane boundary when provider internals are not represented by
the API, and keeps forbidden/unsupported inputs explicitly partial. It does
not list Secret or ConfigMap payloads and does not claim packet flow, CNI
enforcement, provider-network internals, or live-cluster validation. Its
synthetic fixture Map/List and keyboard relationship selection passed a
rendered hierarchy review. Linux
currently shares the graph/core contracts only; topology UI parity is pending.

The current macOS, Linux amd64, and Linux arm64 package runs each verify 23
tests, including nine topology graph tests. Observed macOS debug runs built the
10,000-node graph in about 1.6–5.36s under the 10s gate. Treat this as
fixture/core evidence rather than a GUI-render or live-cluster performance
result.

k9s, KDash, and LFK are stronger choices today for SSH and keyboard-first
terminal work. Headlamp is the closest installed GUI benchmark. A future `kc`
headless CLI can complement the desktop app, but a full TUI is outside the
current MVP unless it demonstrates a workflow those tools do not already
serve.
