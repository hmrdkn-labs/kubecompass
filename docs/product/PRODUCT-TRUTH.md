# Product truth

## Users

The evidence-backed primary user is a Kubernetes operator or developer who
already has `kubectl` and a kubeconfig, wants a native desktop workflow, and
needs to move between contexts, namespaces, resource kinds, details, logs,
events, YAML, Helm releases, and port forwards without memorizing every CLI
command. Topology Explorer also serves developers and learners who need to
understand why a workload, Service, route, policy, or volume appears where it
does without implying more runtime certainty than Kubernetes exposes.
Secondary users are reviewers who need readable state and safe, confirmable
actions; headless SSH users are a possible companion-CLI audience.

## Problem

K-Dex's current macOS surface gathers cluster discovery, resource browsing,
overview signals, detail inspection, live logs/events, YAML apply, Helm, and
port-forward management into one navigable shell. The product problem is to
preserve that workflow while making the core and a native Linux GUI maintainable
without pretending SwiftUI is a Linux runtime.

## Truthful claims

- **Observed:** K-Dex uses local `kubectl`, kubeconfig contexts, namespace
  scope, resource tables, detail tabs, live watches/logs, YAML apply, Helm
  inspection, port forwards, and confirmation/error surfaces (see provenance).
- **Observed in the macOS adapter:** KubeCompass adds a portable, read-only
  Topology Explorer whose relationships are labeled Observed, Declared,
  Inferred, or Unavailable. The chosen interaction is Outline by default,
  selected-root Map bounded to one or two hops, typed Paths diagnostics, and a
  persistent Fundamentals/evidence inspector. It intentionally does not claim
  packet flow, CNI enforcement, provider control-plane internals, cloud-network
  topology, production-cluster fidelity, frame/RSS performance, complete
  accessibility coverage, or complete visual/state-matrix parity. The new
  macOS shell launch against a deterministic fixture is observed; the original
  wide/narrow reference matrix and remaining state gates are incomplete.
- **Observed in the Linux fixture adapter:** The GTK fixture route uses the
  shared evidence graph, but its current controls are the historical
  `ExplorerLevel`/`ExplorerMode`/`ExplorerPresentation` vocabulary: Focus,
  Trace, Inventory, Map fallback, List, and Port table. It is fixture-only
  evidence, not the current macOS Outline/selected-root Map/Paths contract or
  live-cluster parity. Migration, live kubectl behavior, full route/state
  parity, accessibility, visual parity, startup/RSS, and live-cluster
  validation remain open.
- **Planned/selected:** KubeCompass shares domain/state/commands and design
  tokens across the macOS SwiftUI adapter and a native GTK4/libadwaita Linux
  adapter using Makoni/Swift Adwaita commit
  `e725f39c4308138da251a8181beb0a40d86efea9`. The Ubuntu 24.04 / Swift 6.3 /
  libadwaita 1.5 fixture slice builds, packages, installs, and launches on
  amd64 and arm64; full live-cluster route parity is still pending.
- **Acceptance claim:** 1:1 means functional, interaction, visual-token, and
  source parity; native controls need not be pixel-identical.
- **Not claimed:** a Linux SwiftUI port, universal cluster-admin capability,
  zero-permission operation, packet-level network observability, complete
  managed-provider topology, or replacement of k9s/KDash/LFK for SSH-only use.

## Differentiation and unknowns

The TUI category is already served by k9s, KDash, and LFK; Headlamp is a strong
open GUI comparator. KubeCompass must earn a wedge through the K-Dex workflow,
native macOS polish, and a validated cross-platform desktop experience—not by
claiming a generic dashboard is novel. The exact wedge, startup/RSS budget,
accessibility coverage, permission model, and route-level Linux coverage remain
unknown until the remaining Makoni GUI parity gates complete. Shared-core
evidence includes a passing current package suite in the verification receipt,
a deterministic context/state trace, and an indexed 10k-object topology
benchmark.
Both Debian packages passed fresh Ubuntu install-and-launch smoke;
route parity, accessibility/keyboard review, startup, and RSS remain unknown.
Topology's differentiated learning value must be validated with real users;
the evidence model and integrated fixture slices alone do not prove that wedge.

## Topology acceptance boundary

The feature is accepted only when the following evidence exists:

- typed Service, EndpointSlice, Route/Gateway, Pod/container port fixtures;
- numeric, named, ambiguous, missing, multi-protocol, headless, selectorless,
  NodePort, LoadBalancer, and ExternalName cases;
- NetworkPolicy peer/port semantics with explicit non-enforcement language;
- Outline default, selected-root Map one/two-hop scope, typed Paths, and
  persistent inspector with narrow push navigation;
- Outline keyboard semantics, selected-root node/fanout-bounded Map with
  visible truncation and Outline handoff, typed Paths diagnostics, and
  persistent inspector selection/filter behavior;
- ready, partial, empty, loading, stale, offline, reconnecting, error, narrow,
  and wide review scenarios;
- measurable selection, filter, scoped-map/path transition, frame-time, startup, and RSS
  results on both desktop adapters;
- disposable-cluster fixture verification plus an explicit distinction
  between collector, GUI-fixture, and production-cluster evidence.

No current source, fixture, package, or graph benchmark is sufficient by itself
to claim this acceptance boundary.
