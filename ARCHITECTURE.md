# K-Dex Architecture

> This document describes the inherited macOS K-Dex runtime. The new portable
> state/command contracts live under `Sources/KubeCompassCore`; the native Linux
> adapter is documented in `docs/interface/NATIVE-ADAPTER.md`.

How K-Dex works behind the scenes, and how that differs from Aptakube.

## The one-line answer

**K-Dex never talks to a Kubernetes cluster directly.** Every piece of data on
screen is the output of a `kubectl` subprocess, parsed into a dynamic JSON tree
and rendered by SwiftUI: one-shot `get -o json` commands for lists and actions,
plus a long-lived `kubectl get --watch` per visible list that streams changes
in real time. Aptakube makes the same "delegate auth to kubectl" choice but
cashes it in at the connection level (`kubectl proxy`, then direct REST);
K-Dex cashes it in at the command level.

## Data flow

```text
SwiftUI views (Table, detail panel, log view)
      │ observe
      ▼
AppModel  (@Observable, MainActor)  ◄── watch events / metrics ticks / ⌘R
      │ async calls
      ▼
Kubectl / KubectlWatcher / HelmService / LogStreamer / PortForwardManager
      │ argv
      ▼
ProcessRunner ── fork/exec ──► kubectl ── HTTPS ──► API server
      ▲                          (auth: whatever the kubeconfig says)
      └────── stdout (JSON) ◄────┘
      ▼
KubeJSON.decode → JSONValue tree → [KubeObject] → ColumnSpec extractors → cells
```

There is no cache, no database, and no Kubernetes client library. A view's
data is a fresh `kubectl get <kind> -o json` list kept current by a stream of
watch deltas; nothing persists between views or launches.

## Topology Explorer read-only path

Topology Explorer is a separate, evidence-aware snapshot path in the macOS
SwiftUI shell. `k-dex/Services/TopologyService.swift` runs a bounded fan-out of
read-only `kubectl get -o json` calls for 19 approved inputs: namespaces,
nodes, workloads, Pods, Services, EndpointSlices, Ingresses, NetworkPolicies,
PVCs, PVs, StorageClasses, and feature-detected Gateway API resources. It
deliberately does not list Secret or ConfigMap resources or read their
payloads. Pod references to those kinds are retained only as sanitized
name/kind references.

The adapter converts each raw response immediately into typed identities,
owner references, selectors, placement/storage references, Service and
container ports, Ingress and HTTPRoute paths, EndpointSlice addresses and
conditions, policy rules, and a small allowlist of safe facts.
`Sources/KubeCompassCore` then builds a deterministic graph with generation and
capture time. Every relationship and Port Hop is labeled **Observed**,
**Declared**, **Inferred**, or **Unavailable** and keeps its source field, join
rule, and assumptions. Forbidden, unsupported, failed, or cancelled list
inputs become explicit partial/unavailable input status; they are never treated
as an empty successful list.

The graph always includes a virtual **control-plane boundary** with
`Unavailable` evidence when provider-managed control-plane internals are not
represented by the Kubernetes API. This is a boundary marker, not a provider
topology claim. Service selector matches and NetworkPolicy selection are
deterministic joins over the fetched snapshot; neither proves packet delivery
or CNI enforcement. Ingress and Gateway API edges describe declared routing
intent only. A resolved Port Path explains API-level joins from route to
Service port, targetPort, EndpointSlice port/address/readiness, and declared
container port; it does not assert that a packet can traverse the path.

`k-dex/Views/TopologyExplorerView.swift` is the current macOS SwiftUI adapter.
The chosen interaction contract is Outline by default, a selected-root Map
bounded to one or two hops, and typed Paths diagnostics. A persistent evidence
inspector follows the same stable selection through each surface; narrow
navigation pushes that detail surface with an explicit back path. Map geometry
is never a traffic claim, and Traffic is unavailable without telemetry.
Refreshes are generation- and token-guarded so superseded work cannot clear or
strand newer progress state. Legacy semantic grouping metadata remains an
internal implementation detail, not the product default.

The Linux GTK adapter currently remains a deterministic, pre-parity fixture
route: it does not read kubeconfig or invoke kubectl. Its observed topology
controls still use the historical `ExplorerLevel` (`Cluster`,
`Infrastructure`, `Workloads`, `Network`, `Policy & Dependencies`, `Evidence`),
`ExplorerMode` (`Focus`, `Trace`, `Inventory`), and
`ExplorerPresentation` (`Map fallback`, `List`, `Port table`) vocabulary. That
route is wired to the shared graph, but it is not the current macOS
Outline/selected-root Map/Paths interaction contract. Migrating the fixture to
the canonical contract, then proving live-route, accessibility, frame-time,
startup, and RSS parity, remains pending.

The final 2026-08-13 presentation-inclusive Release synthetic 10k fixture
produced 10,001 nodes and 94,950 edges: graphBuild 5488.727ms, Outline
1150.021ms, Map 188.782ms, Paths 196.633ms, level 13.646ms, search 42.085ms,
one-hop 91.238ms, and Port filter 10.37ms (one sample per metric). Any graph/query result is
distinct from GUI frame rate, API-server load, or production-cluster latency.
An opt-in disposable kind-cluster harness exists, but the current gate uses
unit fixtures and the deterministic fake backend rather than a live cluster.
A new macOS shell launch against the deterministic fixture is observed, but the original
wide/narrow capture matrix is incomplete; state, accessibility, frame/RSS, and
live-cluster gates remain unverified. Hierarchy evidence is recorded in
`docs/interface/TOPOLOGY-HIERARCHY-REVIEW.json`.

## Layer by layer

### 1. Process layer — `Services/ProcessRunner.swift`

The foundation everything sits on. It handles the unglamorous parts of
spawning CLIs from a GUI app:

- **PATH resolution.** GUI apps launched from Finder inherit launchd's minimal
  `PATH` (`/usr/bin:/bin:...`), which doesn't include Homebrew. ProcessRunner
  augments the environment with `/opt/homebrew/bin`, `/usr/local/bin`, and the
  user-configured extra path from Settings, then resolves the actual `kubectl`
  binary location.
- **Deadlock-free pipes.** stdout and stderr are drained concurrently on
  background queues. Reading them sequentially would deadlock the child the
  moment one pipe's buffer (64KB) fills while we're blocked on the other —
  easy to hit with large `-o json` dumps.
- **Error shaping.** `runChecked` throws stderr as the error message but
  filters lines starting with `warning:` so a kubeconfig deprecation warning
  doesn't mask (or masquerade as) the real error.
- **Streaming.** `stream()` attaches a `readabilityHandler` and batches
  complete lines to the caller — this is what log following rides on.

### 2. Cluster commands — `Services/KubectlService.swift`

A stateless enum of argv builders. Listing is
`kubectl get <cliName> -o json [--context X] [-n ns | --all-namespaces]`;
mutations are `kubectl delete/scale/rollout restart`; YAML editing pipes the
buffer into `kubectl apply -f -` over stdin. Because kubectl does the
authenticating, every auth mechanism a kubeconfig can express — EKS/GKE/AKS
exec plugins, OIDC, client certs, tokens — works without K-Dex containing a
single line of auth code. Kubectl owns the authentication credentials; the
app can still hold whatever requested command output a user opens in a view.

### 3. Dynamic models — `Support/JSONValue.swift`, `Models/KubeObject.swift`

There are no typed structs for Deployment, Pod, Service, etc. Every object is
kept as a raw `JSONValue` tree (a recursive enum: null/bool/number/string/
array/object) wrapped in a `KubeObject` that pre-extracts only the universal
fields: name, namespace, uid, creation date, labels, annotations. Explicit
Secret, ConfigMap, YAML, and Helm views can therefore place requested payload
values in process memory while they are displayed, edited, or decoded; those
values are not persisted by the app.

Anything kind-specific is read lazily with path subscripts at render time:

```swift
obj.raw["status"]["readyReplicas"].int ?? 0
```

This is why 24 resource kinds plus arbitrary CRDs can share one table view,
one detail panel, one YAML editor — the app doesn't need to know a kind's
schema to display it.

### 4. Kind discovery + enrichment — `Models/ResourceKind.swift`

Kind *identity* is discovered, not hardcoded. At connect time the app walks
the API discovery endpoints through kubectl's transport (`kubectl get --raw
/apis`, then each group's preferred version) and builds a catalog of every
listable resource type the cluster serves — built-ins, aggregated APIs, and
CRDs alike, each a `ResourceKind` value carrying group/version/plural/Kind
and scope. A hardcoded `builtins` list exists only as the seed shown before
discovery lands and the fallback merged in if it fails.

*Presentation* stays curated: a static enrichment table keyed by resource id
supplies what discovery can't — display names, icons, sidebar category,
action capabilities (scale/restart/logs/port-forward), default visibility,
and a `[ColumnSpec]` per kind (title, layout hints, and closures extracting
text / status tone / usage fraction from a `KubeObject`). The ~36 well-known
kinds have entries; everything else gets generic treatment — Kind name,
puzzle-piece icon, best-effort status column, hidden from the sidebar by
default but always reachable via ⌘K search. The API server does serve its own
column definitions (the Table representation kubectl uses for printing), but
kubectl offers no way to fetch them as JSON, so columns remain the one
irreducibly curated layer.

### 5. Refresh model — `State/AppModel.swift` + `Services/WatchService.swift`

Live watch first, polling demoted to reconciliation:

- After a list loads, a long-lived
  `kubectl get <kind> -o json --watch --output-watch-events` subprocess
  streams ADDED/MODIFIED/DELETED events for that list. Stdout is framed into
  complete JSON documents by brace-depth scanning
  (`Support/JSONStreamFramer.swift`), decoded on a background thread, and
  applied to the in-memory array as upserts/deletes. Changes appear the
  moment the API server pushes them — the list subtitle shows "Live" while a
  watch is attached.
- While the watch is healthy, the auto-refresh timer (default 5s) only
  fetches metrics; a full re-list runs at most once a minute as
  reconciliation. If the watch dies it is restarted after a re-list; three
  fast exits in a row (RBAC without the watch verb, ancient kubectl) fall the
  view back to pure polling, which carries it exactly as before.
- A **generation counter** guards against stale writes: every refresh
  increments it, and results are discarded unless the generation still
  matches when the subprocess returns. Switching from Pods to Deployments
  mid-fetch can't paint Pods data into the Deployments table.
- Re-lists compare uid → resourceVersion before replacing the array, so an
  idle cluster doesn't churn table identity every tick.
- Auto-refresh pauses while the app is in the background and fires a
  catch-up refresh on reactivation.
- Slow-moving catalogs piggyback on the cycle with their own throttles:
  namespaces reload at most every 15s, CRDs every 60s (both immediately on
  user-initiated refreshes).
- Detail-panel data (YAML, events, a workload's pods) is fetched on demand
  when the tab opens, not kept fresh in the background.

### 6. Metrics

The metrics API is queried directly through kubectl's authenticated
transport: `kubectl get --raw /apis/metrics.k8s.io/v1beta1/...` returns real
JSON (per-container pod usage, node usage) — `--raw` is the wrapper
architecture's REST escape hatch, and it replaced an earlier version that
scraped `kubectl top`'s tabular output. Requires metrics-server in the
cluster; without it the usage columns degrade to dimmed request/limit text
from the pod spec, and the failure is classified from kubectl's stderr
(`MetricsStatus`: not installed / API registered but unavailable / forbidden /
empty response) so the UI can say *why* — a missing metrics API, a 403, and a
metrics-server that can't reach the kubelets are three different fixes, and a
bare `try?` used to render all of them identically to an idle cluster. Node
percentages are computed against each node's `status.allocatable`. Usage bars
pick a denominator in priority order: limit → request → largest consumer in
the list (the last one rendered as an unbounded blue bar rather than
green/orange/red thresholds); when the denominator is the limit, a tick on
the bar marks the request, and the exact spec'd numbers surface on hover.
Workload rows (Deployments etc.) don't have their own metrics; K-Dex fetches
pods + pod metrics and sums them per workload by matching each workload's
`matchLabels` selector against pod labels.

### 7. Helm — `Services/HelmService.swift`

The `helm` CLI is **not** required. Helm 3 stores each release revision as a
Secret of type `helm.sh/release.v1`. K-Dex lists those secrets
(`-l owner=helm`) and unwraps the payload: base64 (Kubernetes secret data) →
base64 again (Helm's own encoding) → gzip (decompressed by piping through
the Compression framework, size-bounded) → JSON containing the chart metadata, computed values,
rendered manifest, and notes. This explicit Helm view can expose requested
release values in process memory; revision history is grouped from the
per-version secrets and nothing is cached or persisted.

### 8. Long-lived subprocesses

Two features hold child processes open instead of running one-shot commands:

- **Log streaming** — `kubectl logs -f --tail N [--timestamps]`, line-batched
  into a ring buffer capped at 6,000 lines. Workload-level logs use
  `kubectl logs -l <selector> --prefix --all-containers` so one subprocess
  merges every pod, and the view color-codes the `pod/name` prefixes by hash.
- **Port forwarding** — one `kubectl port-forward` child per forward, with a
  small state machine (connecting/active/failed) fed by its output. All
  forwards are killed on app termination via `willTerminateNotification`.

### 9. Sandbox posture

App Sandbox is **disabled**. This is a hard requirement of the architecture:
the app must read `~/.kube/config`, execute arbitrary user-installed binaries
(kubectl and whatever auth plugins the kubeconfig invokes), and let those
binaries do network I/O and write their own caches. Kubectl and its plugins own
auth credentials; KubeCompass does not parse or persist those credentials. The
flip side is that explicit Secret/ConfigMap/YAML/Helm views may hold requested
sensitive values in process/app memory while open. Topology never fetches or
retains Secret/ConfigMap payloads, and KubeCompass has no cache, database, or
persistence layer for either topology or detail payloads. Its subprocesses,
not the SwiftUI process, own cluster sockets and kubectl caches.

## How Aptakube does it differently

Aptakube is a commercial, closed-source, cross-platform client, so some of
this is from its public FAQ and the developer's blog posts rather than source
code — details may have evolved.

| | K-Dex | Aptakube |
| --- | --- | --- |
| UI stack | Native SwiftUI + AppKit escape hatches | Tauri shell (Rust) + web UI (Svelte) in a WebView |
| Platforms | macOS only | macOS, Windows, Linux |
| Cluster transport | `kubectl` subprocess per operation | `kubectl proxy` per connection, then direct REST calls through the local proxy |
| Freshness | Watch stream per visible list (`kubectl get --watch`); polling as reconciliation and fallback | Watch streams — server pushes deltas in real time |
| Auth | Delegated to kubectl on every call | Also delegated to kubectl (the proxy holds the authenticated session) |
| Multi-cluster | One context at a time | Multiple clusters connected simultaneously, mergeable into one view |
| Helm | Decodes release secrets itself, no helm CLI | Same trick — helm CLI not required |
| Requires kubectl installed | No — bundled in the app (Settings can point at your own) | Yes |

The interesting part is that both apps made the *same* foundational choice —
"never reimplement Kubernetes auth, let kubectl own it" — but cashed it in at
different levels:

- **Aptakube** pays the kubectl tax once per cluster connection. `kubectl
  proxy` exposes an authenticated localhost HTTP endpoint, and from there the
  app is a real API client: it can open long-lived **watch** connections and
  receive incremental updates the moment a pod restarts, which is how it does
  real-time UI and efficient multi-cluster merging (N proxies, N watch
  streams, one merged table).
- **K-Dex** pays the tax per command — but the commands aren't all one-shots
  anymore. The visible list is fed by a long-lived `kubectl get --watch`
  subprocess (real-time, one fork/exec per view instead of per tick), while
  actions, detail tabs, Overview, and Helm stay one-shot. The app still has
  no HTTP client and no connection lifecycle of its own: if the watch dies,
  a re-list reconciles and polling carries the view. A failed call costs one
  error banner, not a broken session.

Neither approach embeds a Kubernetes client library with its own auth
implementation — that's the road official dashboards and some other clients
(Lens, k9s embed client-go/kubectl-equivalent libraries) take, trading
integration effort for independence from the kubectl binary.

## Pros and cons of each approach

### K-Dex: kubectl subprocess per operation

#### Subprocess pros

- **Zero auth code, maximum auth coverage.** Anything a kubeconfig can express
  — EKS/GKE/AKS exec plugins, OIDC refresh, client certs, proxies, `insecure-
  skip-tls-verify` — works on day one, because kubectl does it. This is the
  single hardest part of a Kubernetes client and K-Dex simply doesn't have it.
- **Terminal-faithful behavior.** Every request behaves exactly like the
  user's shell: same config resolution, same errors, same RBAC results. "Works
  in my terminal but not in the app" cannot happen.
- **Radically small failure surface.** No connections to manage, no watch
  reconnect/backoff logic, no `resourceVersion` bookkeeping, no session that
  can go stale. A failed call costs one error banner; the next poll is a
  clean slate.
- **Trivially debuggable.** Any behavior can be reproduced by running the
  same argv by hand.
- **Credential boundary stays with kubectl.** Kubectl and its plugins handle
  tokens, certificates, and exec-plugin output; explicit Secret/ConfigMap/YAML/
  Helm views may still place requested values in app memory, without caching or
  persistence.

#### Subprocess cons

- **Staleness where the watch doesn't reach.** The visible list is real-time,
  but Overview, Helm, and any view where the watch can't run (RBAC without
  the watch verb, ancient kubectl) live on the poll tick.
- **Per-call overhead on every one-shot command.** Actions, detail tabs, and
  reconciliation re-lists each pay fork/exec + kubeconfig parse + TLS
  handshake. The watch removed this from the hot path, not from the model.
- **Hard dependency on the kubectl binary** and its version quirks (a boot
  check warns when it's too old for the flags the app uses).
- **Sandbox must stay off**, so distribution through the Mac App Store is
  effectively ruled out.
- **One-shot commands can't multiplex.** Simultaneous multi-cluster would be
  cheap on the watch side (one subprocess per cluster) but N× the churn for
  everything else — and the single-cluster state model is the real blocker.

(The original cons this section listed — a 0–5s staleness window on the main
list, full re-list + re-parse + re-sort every tick, `kubectl top` text
scraping — were mitigated by the watch overlay, resourceVersion change
detection, background pausing, and metrics-API queries. What can't be
mitigated is catalogued in [LIMITATIONS.md](LIMITATIONS.md).)

### Aptakube: kubectl proxy + direct REST

#### Proxy + REST pros

- **Auth still delegated to kubectl** — same coverage win as K-Dex, paid once
  per connection instead of per call.
- **Real-time.** Watch streams push deltas the moment they happen; a
  crash-looping pod shows up immediately, with no polling cost in between.
- **Efficient at scale.** One list + incremental updates instead of repeated
  full dumps; cheap on both apiserver and client for large clusters.
- **Full API surface.** Being a real REST client enables subresources,
  server-side filtering, pagination, `exec`/`attach` upgrades — anything the
  API offers, not just what the CLI exposes.
- **Multi-cluster is natural.** N proxies, N watch streams, one merged view.

#### Proxy + REST cons

- **Connection lifecycle is now your problem.** Proxy processes to babysit,
  watches that drop and must resume from the right `resourceVersion`, session
  state that can drift from reality and needs re-sync logic.
- **A local plaintext HTTP endpoint.** `kubectl proxy` exposes the
  authenticated cluster on localhost while connected — a (modest) security
  surface kubectl one-shots don't have.
- **Still requires kubectl installed**, so it inherits the binary dependency
  without gaining terminal-identical semantics — behavior between proxy
  sessions and fresh CLI calls can diverge.
- **More moving parts** = more failure modes to handle gracefully (proxy died,
  watch stalled, event backlog), each needing UI states.

### Embedded client library (Lens, k9s, official dashboards)

#### Embedded library pros

- **No external binary at all** — self-contained install, no PATH resolution,
  no version skew against a system kubectl.
- **Everything the REST approach offers** (watches, subresources, efficiency)
  with in-process control and no proxy sidecar.
- **Typed models and compile-time safety** if the platform has a mature
  client (client-go), plus protobuf transport where supported.

#### Embedded library cons

- **You own authentication.** Exec plugin spawning, OIDC token refresh, cert
  rotation, proxy support, every cloud vendor's quirks — the exact code both
  K-Dex and Aptakube deliberately avoided writing, and the main source of
  "works in kubectl, fails in the app" bugs.
- **Client library maturity varies by language.** Swift has no client-go
  equivalent; K-Dex would be hand-rolling REST + auth from scratch.
- **Version negotiation is yours too** — API deprecations, discovery, CRD
  schema handling.

### Rule of thumb

Polling a CLI is the right trade when the priority is correctness-per-line-of-
code and clusters are small-to-medium; watches (proxied or native) win when
list sizes are large or sub-second freshness matters; embedding a client only
pays off with a mature library behind it — which Swift doesn't have.

## Where the seams are (deliberate trade-offs)

- **The watch overlay covers the visible list only.** Overview and Helm still
  poll full snapshots — watching eight kinds for a glanced-at dashboard isn't
  worth eight subprocesses.
- **Watch events carry `managedFields`.** kubectl strips them from one-shot
  `get -o json` output but not from watch envelopes, so each event parses
  2–3× more JSON than it needs. Accepted until profiling says otherwise.
- **One context at a time** is a state-model simplification (`AppModel` holds
  a single `selectedContext`), not a transport limitation — since the watch
  overlay, a second cluster would cost one idle subprocess.

Each of these, and why it stays unfixed for now, is expanded in
[LIMITATIONS.md](LIMITATIONS.md).
