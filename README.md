# KubeCompass

A native Kubernetes desktop client: SwiftUI on macOS, with a Swift +
GTK/libadwaita Linux adapter under active development.

## Current status

- **macOS:** the full inherited K-Dex workflow is branded as KubeCompass,
  regression-tested, and locally installable as `KubeCompass.app`.
- **Shared Swift core:** deterministic state, command, safety, and 10,000-row
  fixture contracts compile and test on macOS and Linux.
- **Topology Explorer:** a read-only macOS SwiftUI route
  builds an evidence-aware snapshot from allowlisted `kubectl get -o json`
  inputs. Current macOS, Linux amd64, and Linux arm64 package runs each passed
  23 tests; nine topology tests include a 10,000-node graph build observed at
  about 1.6–5.36s on macOS, under its 10s debug gate.
  A synthetic read-only fixture has also passed rendered Map/List, inspector,
  and keyboard-selection review. This is not live-cluster validation.
- **Linux:** the first native GTK vertical slice is deliberately fixture-only.
  It demonstrates navigation, a virtualized resource table, details, states,
  confirmations, and packaging without reading kubeconfig or running kubectl.
- **`kc`:** on macOS, the installed helper opens the desktop app. A complete
  headless Kubernetes CLI is not shipped yet.

## macOS feature reference

- **Cluster browsing** — switch between kubeconfig contexts; filter by namespace.
- **Live updates** — each list is fed by a Kubernetes watch stream, so changes
  appear the moment they happen; polling only reconciles and refreshes metrics.
- **Every resource kind** — 30+ built-in kinds with kind-specific columns and
  status badges; everything else the cluster serves (aggregated APIs, any CRD)
  is discovered at connect time and reachable via the **⌘K palette**. Installed
  CRDs get their own per-API-group sidebar sections; sidebar sections and items
  are reorderable and hideable.
- **Detail inspector** — overview (metadata, containers, conditions, labels,
  secret/configmap data with reveal), live YAML, per-object events, and the
  pods of a workload or node.
- **Pod & workload logs** — streamed with follow, container picker, filtering,
  wrap/timestamps, aggregated multi-pod logs with color-coded prefixes, and
  crash awareness: a banner on crashed containers with one-click access to the
  previous instance's logs.
- **Overview dashboard** — workload status cards, recent warnings, recent
  restarts, pods running near their limits.
- **Actions** — delete, rollout restart, scale — all confirmed, with namespace
  and context named in the dialog.
- **Create & edit YAML** — per-kind creation templates and an in-app editor
  with syntax highlighting, backed by `kubectl apply`.
- **Port forwarding** — pods, services, and workloads (deployments, stateful
  sets, daemon sets, replica sets), managed from a toolbar popover.
- **Helm releases** — read directly from release Secrets (no helm CLI needed):
  chart, status, values, manifest, notes, history — values and manifest behind
  an explicit reveal, since they often contain credentials.
- **Metrics** — pod/node CPU & memory usage bars via metrics-server. Bars run
  to the limit with a tick marking the request; exact numbers on hover. When
  metrics are missing, the app says why (not installed, RBAC, unreachable
  kubelets) and shows the spec'd requests/limits dimmed instead.
- **Topology Explorer (read-only)** — the macOS SwiftUI route
  shows Kubernetes object relationships as Observed, Declared, Inferred, or
  Unavailable evidence. It uses a map plus a keyboard-navigable List fallback;
  partial RBAC and unsupported inputs stay visible as incomplete evidence. A
  virtual control-plane boundary marks provider-managed internals that the API
  does not expose. The route does not list Secret or ConfigMap payloads, and
  it does not claim traffic flow, CNI enforcement, or provider-network truth.
- **Direct distribution** — updater integration is disabled until a dedicated
  KubeCompass release feed exists.

## How the macOS app works

The app drives a bundled `kubectl` (or your own — path configurable in
Settings), so every auth mechanism your kubeconfig supports (EKS/GKE/AKS exec
plugins, certs, tokens) works untouched. Responses are parsed as raw JSON into
a dynamic `JSONValue` tree; kind identity is discovered from the cluster's API,
while columns and status logic are curated per kind. Lists stay current through
`kubectl get --watch` streams, with polling demoted to metrics and periodic
reconciliation.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and
[LIMITATIONS.md](LIMITATIONS.md) for known trade-offs.

Requirements: macOS 26+. kubectl is bundled with the app. App Sandbox is
disabled because the app must read `~/.kube` and spawn kubectl and your auth
plugins.

## Install

There is no published or notarized KubeCompass release yet. Build locally:

```sh
xcodebuild -project k-dex.xcodeproj -scheme k-dex \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

The local `kc` helper supports `kc`, `kc path`, `kc version`, and `kc help`.
It intentionally does not masquerade as a full cluster CLI.

The locally installed GUI and TUI alternatives, their safe launch commands,
and a concrete evaluation checklist are recorded in
[docs/product/COMPARISON-LAB.md](docs/product/COMPARISON-LAB.md).

Topology Explorer's relationship vocabulary, unavailable-input behavior, and
data-safety boundary are recorded in
[docs/product/TOPOLOGY-EXPLORER.md](docs/product/TOPOLOGY-EXPLORER.md).

Synthetic fixture preview:

![Topology Explorer with the virtual control-plane boundary selected](docs/interface/evidence/topology-map-control-plane.jpeg)

For the Linux fixture slice, use `scripts/build-linux.sh`; the verified package
script writes an architecture-specific Debian artifact under `dist/`.

## Roadmap ideas

- Exec shell into containers
- Helm uninstall/rollback
- Multi-cluster simultaneous views
- Mac App Store edition with native cloud auth

## License

MIT — see [LICENSE](LICENSE). KubeCompass is derived from
[K-Dex](https://github.com/irfancen/k-dex); the inherited copyright and license
notice remain intact. See [UPSTREAM.md](UPSTREAM.md) for the exact baseline and
third-party distribution notes.
