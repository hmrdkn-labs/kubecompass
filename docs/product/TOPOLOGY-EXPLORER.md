# Topology Explorer

Topology Explorer is KubeCompass's read-only Kubernetes learning workspace.
It helps an operator, developer, or learner answer fundamental questions about
cluster state without presenting a derived relationship as stronger evidence
than the API provides.

It is deliberately not a network map. Kubernetes objects explain intent,
ownership, scheduling, service selection, declared routing, policy scope, and
storage binding. They do not, by themselves, prove packet flow, policy
enforcement, process listening, or provider-network behavior.

## The fundamental questions

Every selected object, relationship, Route, and Port Path must answer these
questions in plain language:

1. **What is this?** — identity, namespace, scope, status, and safe fields.
2. **Why is it here?** — owner, selector, placement, reference, or join rule.
3. **What does the snapshot prove?** — explicit source fields and fetched
   targets, with an Evidence Level.
4. **What does it not prove?** — unknown runtime behavior, missing API input,
   provider internals, or a declaration that has not been observed as ready.
5. **What should I inspect next?** — an Outline expansion, a selected-root Map
   (one or two hops), a typed Paths diagnostic, or an existing resource view.

The copy labels these blocks **Fundamentals**. The product must not require a
learner to infer the claim boundary from color, line style, or Kubernetes
jargon.

## Approved topology surfaces

| Surface | Primary question | Contract |
| --- | --- | --- |
| **Outline (default)** | What is here, and why is it grouped this way? | Deterministic namespace → primary workload/controller → dependents grouping, plus unattached resources and explicit evidence gaps. |
| **Scoped Map** | Which nearby objects explain this selected root? | Selected root plus one or two typed relationship hops; node/fanout-bounded output with visible truncation status and an explicit Outline handoff, never a traffic or physical-topology implication. |
| **Paths** | How does one declared or inferred path resolve? | Typed Route/Service/EndpointSlice/Pod-container, policy, or dependency hops with status, source field, resolution, readiness, and Evidence Level. |
| **Persistent inspector** | What does the selection prove? | Fundamentals, provenance, unavailable inputs, safe next actions, and “what this proves / does not prove” remain available across all surfaces. |

Outline is the canonical keyboard semantic hierarchy. Map and Paths share its
selection, filters, breadcrumbs, and evidence model. Paths is the canonical
typed diagnostic list, and every selected item opens the persistent inspector;
there is no separate List or Port Table fallback surface. At narrow widths,
selecting a root or diagnostic uses push navigation with an explicit back path;
the inspector is not removed.

Traffic is unavailable unless a separately permissioned telemetry adapter
supplies flow evidence. Kubernetes selectors, owner references, Routes, and
EndpointSlices never become traffic claims.

The new macOS shell has been launched against a deterministic fixture. This is
runtime truth for the shell/fixture path only: the original wide/narrow
reference coverage matrix is incomplete, and state, accessibility, GUI
frame/RSS, and live-cluster gates remain unverified. The Linux adapter remains
a fixture-only GTK route using the historical ExplorerLevel/ExplorerMode/
ExplorerPresentation controls (including Map fallback, List, and Port table),
not the current Outline/selected-root Map/Paths contract and not live-cluster
or full parity evidence. Migration is pending.

## Port Path contract

Ports are typed data and must never be reduced to a comma-separated fact.
Where available, KubeCompass retains:

- Route host/path, listener, protocol, port, backend name/port, TLS and status.
- Gateway listener hostname, protocol, port, attachment, backend reference and
  status.
- Service type, cluster IP, external ingress, port name, `port`, protocol,
  `targetPort`, `nodePort`, and `appProtocol`.
- EndpointSlice address type, addresses, port name/number, protocol, ready,
  serving, terminating, node and zone.
- Pod/container name, declared `containerPort`, protocol, `hostPort`, and
  `hostIP`.

The canonical presentation is a sequence of Port Hops. For example:

```text
api.example.test /orders
  → HTTPS listener :443
  → Service orders / https :443 TCP
  → targetPort "web"
  → EndpointSlice 10.42.1.8 :8443 ready
  → Pod orders-abc / api / web :8443 TCP (declared)
```

Each hop shows its source field, resolution rule, Evidence Level, and status.
Named or numeric `targetPort` values may be unresolved, ambiguous, or absent.
EndpointSlice readiness is an observed API condition; a declared container port
does not prove that a process listens. See [Services](https://kubernetes.io/docs/concepts/services-networking/service/),
[EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/),
and the [Pod API](https://kubernetes.io/docs/reference/kubernetes-api/core/pod-v1/).

Exposure Status is bounded to API evidence: Declared, Resolved, Ready
endpoints, No ready endpoints, Ambiguous, Unresolved, Partial, or Unavailable.
It must not be copied as “reachable,” “healthy traffic,” or “request
delivered.”

## Evidence and status model

Every relationship and Port Hop carries one Evidence Level:

| Level | Meaning |
| --- | --- |
| **Observed** | An explicit source field resolves to fetched data, such as `spec.nodeName` resolving to a Node or an EndpointSlice address and condition. |
| **Declared** | A resource spec records intent, such as an Ingress backend naming a Service. |
| **Inferred** | KubeCompass performs a deterministic join, such as a Service selector matching Pod labels. |
| **Unavailable** | Required input was forbidden, unsupported, offline, timed out, stale, or absent. |

Snapshot Status is separate from Exposure Status:

| Snapshot Status | Required meaning |
| --- | --- |
| Loading | Read the requested scope; retain context and scope. |
| Ready | Requested inputs completed without known gaps. |
| Empty | Inputs completed and no matching resources exist. |
| Partial | Some inputs are unavailable, references are unresolved, or a declared path has unresolved/no-endpoint/no-ready evidence; readable evidence remains visible. |
| Stale | Last snapshot is shown with an explicit timestamp and failed refresh. |
| Offline | No fresh API connection; never imply current state. |
| Reconnecting | Refresh/watch is pending; preserve safe selection. |
| Error | Identify the failed input and offer a read-only retry. |

Partial and Unavailable are never represented as Empty. The inspector lists the
kind, scope, reason, and timestamp for every unavailable input. A single Port
Path materializes at most 512 deterministic hops; larger EndpointSlice fan-out
remains Partial and reports the omitted hop, endpoint, and port counts rather
than silently implying that the visible path is exhaustive.

## Policy and dependency boundaries

NetworkPolicy display includes selected Pods, ingress/egress direction, peers,
namespace selectors, IP blocks, ports, protocols, ranges, and default policy
types. It explains declaration and combination semantics, but never claims that
the CNI enforces the policy or that a request can or cannot reach a target. See
the [NetworkPolicy API](https://kubernetes.io/docs/reference/kubernetes-api/networking/network-policy-v1/)
and [network policy concepts](https://kubernetes.io/docs/concepts/services-networking/network-policies/).

Gateway API routes include listener/parent attachment, backend references, and
status. Cross-namespace ReferenceGrant evaluation is not yet modeled and must
remain unresolved rather than inferred. See
the [Gateway API overview](https://gateway-api.sigs.k8s.io/docs/concepts/api-overview/)
and [HTTPRoute reference](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/).

ConfigMap and Secret dependencies retain resource names only. Referenced keys
and raw payloads, annotations, arbitrary label values, kubeconfig material,
auth-plugin output, command argv, and stderr remain outside the graph.

## Interaction quality contract

- Outline expansion reveals the selected root and directly relevant dependents
  without losing selection.
- Scoped Map starts only from a selected root, is capped at one or two
  relationship hops and a node/fanout budget, and exposes visible truncation
  status plus an explicit handoff back to Outline.
- Paths walks one Route, Port Path, policy, or dependency hop at a time; each
  step updates the persistent inspector and typed diagnostic list.
- Map edges are selectable, but edge geometry is never the only carrier of
  meaning and never implies traffic.
- Loading renders shell and scope first, then progressively fills resources,
  relationships, and details. Refresh cancellation cannot overwrite a newer
  generation.
- Selection, filter, and breadcrumb changes preserve context across Outline,
  Map, and Paths.
- Motion is short and comprehension-oriented for selection, scope, and path
  changes. Reduced Motion removes travel/physics while preserving state,
  selection, and status updates.
- Keyboard traversal, screen-reader labels, focus order, contrast, and narrow
  layouts must expose the same task outcomes as Outline, Map, and Paths.

Provisional performance gates are recorded in the interface review. They are
targets to measure, not claims that the current implementation passes. The
current selected-root Map has an explicit hop limit and a core 180-node cap;
the macOS surface reports visible truncation and offers an explicit handoff to
Outline. This is correctness evidence, not frame-time evidence.

## Security and provider boundary

Managed Kubernetes providers commonly hide control-plane machines, etcd,
provider load-balancer internals, VPC routes, security groups, and firewall
rules from the Kubernetes API. KubeCompass displays a virtual Control-plane
Boundary and marks those internals Unavailable unless a separate, explicitly
permissioned adapter supplies evidence. Kubernetes networking concepts are
documented at [Services and networking](https://kubernetes.io/docs/concepts/services-networking/).

## Current implementation and later work

Observed now: the macOS SwiftUI route and portable graph expose the chosen
Outline/selected-root Map/typed Paths intent, typed Route → Service →
EndpointSlice → endpoint → declared-container Port Paths, unresolved/no-
endpoint/no-ready/external statuses, persistent Fundamentals copy, and
partial-input retention. A new macOS shell launch against a deterministic
fixture is observed. The current source and fixture tests cover these
contracts. An opt-in disposable kind harness covers fixture API shapes and
RBAC denial, but it was not run by the current redesign gate. No claim is made
for arbitrary production-cluster fidelity, runtime
traffic, frame/RSS performance, complete accessibility coverage, or the
original wide/narrow/state scenarios.

Observed in the Linux fixture slice: a GTK topology route is wired to the
shared graph and exposes the historical ExplorerLevel/ExplorerMode/
ExplorerPresentation controls and evidence inspector against fixture data.
This remains fixture-only: migration to the canonical Outline/selected-root
Map/Paths contract, live kubectl behavior, full route/state parity,
accessibility, startup/RSS, and visual parity are open.

Planned next: capture the 16 original wide/narrow reference scenarios, review
the generated design-direction target
(`docs/interface/reference-topology-v2/topology-outline-design-target.png`),
measure GUI smoothness and memory, complete human accessibility review, and
validate broader provider/controller conformance and full live GTK route
parity.

## Existing Kubernetes references

- [Owners and dependents](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/)
- [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secrets good practices](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
