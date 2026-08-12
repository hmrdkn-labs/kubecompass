# KubeCompass comparison lab

These tools are installed locally so the desktop and terminal approaches can
be compared against the same kubeconfig. Prefer a read-only RBAC context or a
disposable cluster while exploring.

## Launchers

| Product | Surface | Safe starting command | Installed version |
| --- | --- | --- | --- |
| KubeCompass | Native macOS SwiftUI desktop | `kc` | 1.2.0 |
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

## Product boundary

KubeCompass is intentionally a desktop product, not another k9s clone. The
macOS surface remains SwiftUI. The Linux surface is native Swift with
GTK4/libadwaita and shares portable state, command, safety, and fixture
contracts; Apple does not provide a SwiftUI Linux backend. The current Linux
package is a fixture-backed vertical slice and does not read kubeconfig or run
kubectl yet.

k9s, KDash, and LFK are stronger choices today for SSH and keyboard-first
terminal work. Headlamp is the closest installed GUI benchmark. A future `kc`
headless CLI can complement the desktop app, but a full TUI is outside the
current MVP unless it demonstrates a workflow those tools do not already
serve.
