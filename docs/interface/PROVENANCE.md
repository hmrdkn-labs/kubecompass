# K-Dex interface provenance and Linux coverage

This table is the evidence boundary for the Interface IR. “Observed” means the
current K-Dex source directly contains the behavior. Linux status describes the
pinned Makoni/Swift Adwaita adapter and its evidence boundary. The Ubuntu 24.04
/ Swift 6.3 / libadwaita 1.5 slice builds, packages, installs, and launches on
Linux amd64 and arm64; this is not evidence that full live-cluster route parity
or an accessibility review exists.

## Coverage evidence summary

| Evidence | Result | Scope |
| --- | --- | --- |
| Makoni/Swift Adwaita commit `e725f39c4308138da251a8181beb0a40d86efea9` | pinned | Native GTK4/libadwaita view adapter; SwiftUI source compatibility absent. |
| Ubuntu 24.04 / Swift 6.3 / libadwaita 1.5 slice | amd64 + arm64 build/window smoke passed | Fixture-only adapter evidence; full routes/states remain pending. |
| macOS Swift 6.3.3 shared package | Current suite result is recorded in the verification receipt; refresh after final source compilation | No live-cluster validation; do not infer GUI parity. |
| Topology graph performance | Current Release synthetic run built 10,001 nodes and 94,950 edges in about 3.56s; level/search/focus/port queries stayed below 73ms | Graph/query fixture only; not SwiftUI frame time, RSS, or API latency. |
| Linux amd64 and arm64 Swift 6.3.3 | Prior fixture runs covered package/build/window smoke; exact current suite result belongs in the verification receipt | Shared package/GTK fixture evidence only; topology UI parity remains pending. |
| Debian packages | both architectures passed metadata, fresh install, `/usr/bin/kc`, and Xvfb/DBus launch smoke | Packaging/install evidence; kubectl intentionally disabled. |
| 10k-row table benchmark | observed local p95 37.98–100.67ms, under 150ms | Shared index/filter/sort only; not GUI render performance. |

| Screen/state or workflow | Direct source evidence | Status | Linux counterpart |
| --- | --- | --- | --- |
| Boot loading / connecting | `k-dex/ContentView.swift:10-15`; `k-dex/State/AppModel.swift:7-19` | observed | partial — shared boot state; Makoni GTK progress surface pending |
| Missing kubectl | `k-dex/State/AppModel.swift:151-157`; `k-dex/Views/WelcomeView.swift:31-45` | observed | partial — GTK welcome/retry/settings mapping pending |
| No kubeconfig contexts | `k-dex/State/AppModel.swift:159-166`; `k-dex/Views/WelcomeView.swift:34-45` | observed | partial — same copy/state contract, native layout pending |
| Bootstrap failure | `k-dex/State/AppModel.swift:166-169`; `k-dex/Views/WelcomeView.swift:35-47` | observed | partial — GTK error presentation pending |
| Cluster picker, filter, reload | `k-dex/Views/ClusterPickerView.swift:18-97` | observed | partial — GTK picker POC required |
| Connected main shell | `k-dex/ContentView.swift:54-91` | observed | partial — Makoni adapter path sketched; full Linux shell remains pending |
| Sidebar sections, visibility, reorder | `k-dex/Views/SidebarView.swift:19-65`; `:113-181` | observed | partial — GTK tree/list and persistence POC required |
| Resource palette (`⌘K`) | `k-dex/Views/SidebarView.swift:43-64`; `k-dex/Views/KindSearchSheet.swift:6-112` | observed | missing — keyboard/focus parity POC required |
| Context switch/disconnect | `k-dex/State/AppModel.swift:190-225`; `k-dex/Views/SidebarView.swift:280-327` | observed | partial — shared command/state, GTK control pending |
| Overview ready dashboard | `k-dex/Views/OverviewView.swift:45-73`; `:212-239` | observed | missing — GTK cards/grid pending |
| Overview loading | `k-dex/Views/OverviewView.swift:8-15` | observed | partial — shared state, native progress pending |
| Overview empty warnings/restarts/usage | `k-dex/Views/OverviewView.swift:83-205` | observed | partial — state copy shared; GTK layout pending |
| Overview unavailable/error with stale data | `k-dex/Views/OverviewView.swift:15-32` | observed | partial — error banner and stale-data rule pending |
| Resource table ready/sort/filter/select | `k-dex/Views/ResourceListView.swift:35-82`; `:327-418` | observed | partial — shared index passes 10k p95; full Makoni table UX pending |
| Resource table loading/empty/error | `k-dex/Views/ResourceListView.swift:104-140`; `:227-234` | observed | partial — GTK state surfaces pending |
| Resource actions: create/delete/restart/scale/forward | `k-dex/Views/ResourceListView.swift:170-234` | observed | missing — mutation adapters pending |
| Resource detail overview | `k-dex/Views/ResourceDetailView.swift:31-70`; `:151-416` | observed | missing — Linux detail view pending |
| Detail Pods tab loading/empty/error | `k-dex/Views/ResourceDetailView.swift:417-564` | observed | partial — shared fetch/state; GTK list pending |
| Detail YAML loading/apply/error/success | `k-dex/Views/ResourceDetailView.swift:570-709`; `k-dex/Views/YAMLViews.swift:5-82` | observed | missing — GTK editor and apply affordance pending |
| Detail Logs waiting/stream/filter/copy/ended | `k-dex/Views/LogView.swift:51-99`; `:223-311`; `k-dex/Services/LogStreamer.swift:7-126` | observed | partial — shared log state/trace exists; Makoni streaming text view pending |
| Detail Events loading/empty/error | `k-dex/Views/ResourceDetailView.swift:715-784` | observed | partial — GTK event list pending |
| Helm releases table/empty/error/detail | `k-dex/Views/HelmViews.swift:3-118`; `:130-263` | observed | missing — Linux Helm adapter pending |
| Port forwards empty/starting/active/failed/stop | `k-dex/Views/PortForwardViews.swift:33-103`; `:140-195`; `k-dex/Services/PortForwardManager.swift:7-82` | observed | partial — shared manager; GTK popover/dialog pending |
| Create resource template/loading/error/success | `k-dex/Views/CreateResourceSheet.swift:3-139` | observed | missing — GTK form/editor pending |
| Settings paths, PATH, log tail | `k-dex/Views/SettingsView.swift:3-30` | observed | partial — GTK settings form pending |
| Permission/auth-plugin denial | `k-dex/Views/WelcomeView.swift:40-47`; `k-dex/Views/ResourceListView.swift:227-234`; `k-dex/Services/KubectlService.swift:226-267` | partial — error text is observed; RBAC-specific copy is not | missing — must be probed against fake denied API |
| Offline/reconnecting/watch recovery | `k-dex/State/AppModel.swift:55-64`; `:172-209`; `k-dex/Services/WatchService.swift:8-102` | observed/inferred | partial — shared reducer trace covers reconnect; Linux GUI watch UX pending |
| Topology Explorer macOS route | `k-dex/Views/TopologyExplorerView.swift:31-181`; `k-dex/Views/TopologyExplorerView.swift:279-858`; `k-dex/Services/TopologyService.swift:34-150` | observed source: Explorer Levels, modes, Map/List/Port Table, typed Port Paths, inspector, partial-input status | Linux fixture route exists; live-cluster and full parity pending |
| Topology evidence levels and virtual boundary | `Sources/KubeCompassCore/TopologyGraph.swift:8-112`; `:448-510` | observed source | shared core only; no Linux UI evidence |
| Topology partial RBAC/unavailable inputs | `k-dex/Services/TopologyService.swift`; `Sources/KubeCompassCore/TopologyGraph.swift`; `scripts/topology-e2e.sh` | fixture-tested; disposable kind fixture and RBAC denial passed | no arbitrary production-cluster claim |
| Topology Map/List/Port Table | `k-dex/Views/TopologyExplorerView.swift`; `docs/interface/TOPOLOGY-HIERARCHY-REVIEW.json` | observed source; wide Port Table runtime-reviewed; narrow/full state matrix and human accessibility review pending | Linux fixture has grouped-map fallback, List, and Port Table; full parity missing |
| Typed Port Paths and Fundamentals | `Sources/KubeCompassCore/TopologyGraph.swift`; `k-dex/Views/TopologyExplorerView.swift`; `docs/interface/evidence/topology-tiered-port-path.jpeg` | observed source, fixture-test, wide rendered evidence, and disposable fixture conformance | Linux fixture consumes shared graph; live route behavior missing |
| Topology Secret/ConfigMap boundary | `k-dex/Services/TopologyService.swift:34-51`; `:273-295`; `Sources/KubeCompassCore/TopologyGraph.swift:448-450` | observed source; payload listing absent | shared safety contract; no Linux UI |

## Open coverage questions

- Which Makoni/Swift Adwaita view implementations cover every required table,
  detail, log, YAML, Helm, port-forward, and settings state? The toolkit choice
  is settled; route-level evidence is not.
- What GTK-specific permissions, filesystem portals, and browser-open behavior
  are required? Do not claim parity until fake-server and local-process probes
  answer these.
- A CLI/TUI counterpart is intentionally not mapped as a complete screen set;
  it is optional headless support, not the desktop acceptance surface.
- Topology Explorer has disposable kind fixture evidence and a deterministic
  wide Port Table runtime review. It still has no packet-traffic, CNI,
  provider-internal, production-provider, frame/RSS, complete VoiceOver, narrow
  state-matrix, or full Linux parity evidence. Linux topology remains
  fixture-only.

## Approved topology contract evidence boundary

The following is the acceptance matrix for the integrated implementation. A
`planned` or `unverified` row defines what must still be measured; it does not
report a passed runtime probe.

| Contract area | Required evidence | Current status |
| --- | --- | --- |
| Explorer Levels | Cluster, Infrastructure, Workloads, Network, Policy & Dependencies, Evidence; breadcrumb and preserved selection | observed source; wide Cluster/Network transition reviewed; remaining level/state matrix unverified |
| Three-pane shell | Scope rail, exploration canvas, evidence inspector at wide and narrow sizes | wide runtime observed; narrow runtime evidence unverified |
| View parity | Map, List, and Port Table expose the same selected set, filters, statuses, and handoff | implemented source; cross-view visual/accessibility parity unverified |
| Port Paths | Route/Service → targetPort → EndpointSlice → Pod/container typed Port Hops | observed source, fixtures, wide rendered evidence, and disposable cluster API-shape conformance |
| Learner fundamentals | “What this proves” and “What this does not prove” for object, relationship, Route, and Port Path | observed source and wide visual review; complete VoiceOver review unverified |
| Snapshot states | ready, partial, empty, loading, stale, offline, reconnecting, error | source covers several states; complete matrix unverified |
| Interaction quality | Focus/Trace/Inventory, keyboard, screen reader, reduced motion, selection retention | source covers controls and reduced-motion hooks; accessibility review unverified |
| Smoothness | selection/filter/tier p95, frame time, startup, RSS, cancellation and scale results | core 10k/query benchmark and refresh completion observed; GUI frame/RSS/startup unverified |
| Platform parity | identical semantic outcomes on SwiftUI and GTK adapters | Linux fixture route partial; full parity unverified |
| Live fidelity | disposable-cluster scenarios with RBAC gaps and Service/EndpointSlice/Route variants | fixture API shapes and RBAC denial passed in disposable kind; application collector and arbitrary provider coverage remain separate |
