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
  Topology Explorer
  whose relationships are labeled Observed, Declared, Inferred, or Unavailable.
  It intentionally does not claim packet flow, CNI enforcement, provider
  control-plane internals, or cloud-network topology. The Map/List and evidence
  inspector have been interaction-reviewed against a synthetic read-only
  fixture; live-cluster validation and a Linux GTK topology route remain open.
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
evidence currently includes 23/23 package tests on macOS, Linux amd64, and
Linux arm64, a deterministic 15-step trace, and a final local 10k-row p95 of
37.98–100.67ms across verification runs. Both Debian packages passed fresh Ubuntu install-and-launch smoke;
route parity, accessibility/keyboard review, startup, and RSS remain unknown.
Topology's differentiated learning value must be validated with real users;
the evidence model and native macOS slice alone do not prove that wedge.
