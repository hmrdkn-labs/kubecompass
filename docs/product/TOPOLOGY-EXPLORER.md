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
5. **What should I inspect next?** — a bounded Focus, Trace, or Inventory
   action, or an existing resource view.

The copy labels these blocks **Fundamentals**. The product must not require a
learner to infer the claim boundary from color, line style, or Kubernetes
jargon.

## Approved Explorer Levels

Explorer Levels are semantic navigation scales, not Kubernetes labels or
implementation “tiers.” Each level has a default aggregation, a question, and
an equivalent Map, List, and Port Table surface.

| Level | Primary question | Default content |
| --- | --- | --- |
| **Cluster** | What is in this snapshot, and how complete is it? | Context, snapshot status, namespaces, control-plane boundary, nodes/zones, entry points, cluster-scoped resources, denied inputs. |
| **Infrastructure** | Where can workloads run, and what is observable about the substrate? | Current: Nodes, roles, addresses, zones, Pod CIDRs, kubelet/runtime/OS/architecture, Pod scheduling, and storage classes. Planned facts: complete Node conditions, capacity/allocatable, and taints. |
| **Workloads** | Which workloads own, create, and run these Pods? | Current: Deployment → ReplicaSet → Pod, StatefulSet, DaemonSet, Job, CronJob, containers, phase/readiness/restarts, replica counts, and unresolved ownership. Planned facts: workload conditions and probe declarations. |
| **Network** | How is an application exposed or selected? | Ingress/Gateway/Route → Service port → targetPort → EndpointSlice port/address → Pod/container port. Selectorless, headless, NodePort, LoadBalancer, and ExternalName semantics remain distinct. |
| **Policy & Dependencies** | What declares access and what does the workload depend on? | Current: NetworkPolicy peers/ports and policy types, storage, ConfigMap/Secret references by name, and unresolved references. Planned inputs: ServiceAccounts/RBAC, quotas, disruption budgets, and autoscaling. |
| **Evidence** | What exactly supports each claim? | Source field, join rule, resource version, snapshot time, assumptions, unavailable inputs, unresolved references, and “what this proves / does not prove.” |

Drilling down changes aggregation and focus; it does not discard the selected
object. Breadcrumbs always show `Cluster / Level / Scope / Selection` and allow
one-step return without resetting filters.

## Three-pane desktop shell

The approved desktop shell is a stable three-pane layout:

1. **Scope rail** — context, namespace, Explorer Level, Snapshot Status,
   search, filters, and the breadcrumb.
2. **Exploration canvas** — Map, List, or Port Table for the current level and
   Focus/Trace/Inventory mode.
3. **Evidence inspector** — Fundamentals, selected object or relationship,
   port hops, status, provenance, unavailable inputs, and safe next actions.

The panes may collapse at narrow widths, but the information order remains the
same. A narrow layout must expose a single-pane equivalent with a clear back
path; it must not remove the inspector or make the map the only route.

### View parity

| View | Purpose | Required parity |
| --- | --- | --- |
| **Map** | Show nested semantic groups and bounded relationships. | Selectable objects and relationships; compound groups; bundled/orthogonal edges; selected Focus preserved; no physics implying traffic. |
| **List** | Provide the semantic and accessibility fallback. | Same objects, relationships, evidence labels, status, filters, ordering, selection, and handoff as Map. |
| **Port Table** | Make typed port semantics inspectable at a glance. | Same selected Route/Service/EndpointSlice/Pod set; protocol, names, numbers, targetPort resolution, readiness, and Evidence Levels are explicit. |

The current macOS implementation now contains the approved Explorer Level
navigation, breadcrumb, Focus/Trace/Inventory modes, Map/List/Port Table
switching, typed Port Path rows, a Fundamentals/evidence inspector, and a
wide three-pane or narrow stacked layout. A fresh deterministic wide fixture
review confirms the hierarchy and full Ingress → Service → EndpointSlice → Pod
container-port evidence in the Port Table and inspector. Narrow-state parity,
human VoiceOver review, and GUI frame/RSS smoothness remain unverified.

The Linux adapter contains a fixture-only GTK topology route with Explorer
Level, mode, presentation, search, grouped-map fallback, List, Port Table, and
Fundamentals/evidence surfaces. It is useful for proving shared vocabulary and
fixture wiring, but it is not live-cluster evidence or full GTK route parity.

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
kind, scope, reason, and timestamp for every unavailable input.

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

- Focus mode shows the selected object and directly relevant neighbors; the
  user can expand one additional hop without losing selection.
- Trace mode walks one Route, Port Path, policy, or dependency hop at a time;
  each step updates the inspector and the equivalent List/Port Table row.
- Inventory mode is searchable, deterministically ordered, virtualized by the
  native List, and complete for the selected scope, with an explicit aggregate
  count rather than a silent cap. User-controlled sort remains future work.
- Map edges are bundled, routed, and selectable. Edge geometry is not the only
  carrier of meaning.
- Loading renders shell and scope first, then progressively fills resources,
  relationships, and details. Refresh cancellation cannot overwrite a newer
  generation.
- Selection, filter, and breadcrumb changes preserve context across Map, List,
  and Port Table.
- Motion is short and comprehension-oriented for selection, focus, and level
  changes. Reduced Motion removes travel/physics while preserving state,
  selection, and status updates.
- Keyboard traversal, screen-reader labels, focus order, contrast, and narrow
  layouts must expose the same task outcomes as the Map.

Provisional performance gates are recorded in the interface review. They are
targets to measure, not claims that the current implementation passes. The
current Map uses an explicit page size and offers a List handoff instead of a
silent truncation; this is a bounded usability safeguard, not a frame-time
benchmark.

## Security and provider boundary

Managed Kubernetes providers commonly hide control-plane machines, etcd,
provider load-balancer internals, VPC routes, security groups, and firewall
rules from the Kubernetes API. KubeCompass displays a virtual Control-plane
Boundary and marks those internals Unavailable unless a separate, explicitly
permissioned adapter supplies evidence. Kubernetes networking concepts are
documented at [Services and networking](https://kubernetes.io/docs/concepts/services-networking/).

## Current implementation and later work

Observed now: the macOS SwiftUI route and portable graph implement the semantic
Explorer Levels, Focus/Trace/Inventory modes, Map/List/Port Table surfaces,
typed Route → Service → EndpointSlice → endpoint → declared-container Port
Paths, unresolved/no-endpoint/no-ready/external statuses, Fundamentals copy,
and partial-input retention. The current source and fixture tests cover these
contracts. A disposable kind run also verifies the fixture API shapes and RBAC
denial, while a deterministic desktop fixture records the tiered Port Table
hierarchy. No claim is made for arbitrary production-cluster fidelity, runtime
traffic, frame/RSS performance, complete VoiceOver coverage, or the untested
narrow/state scenarios.

Observed in the Linux fixture slice: a GTK topology route is wired to the
shared graph and renders the same level/mode/presentation vocabulary, grouped
map fallback, List, Port Table, and Fundamentals/evidence copy. This remains
fixture-only: live kubectl behavior, full route/state parity, accessibility,
startup/RSS, and visual parity are open.

Planned next: fresh narrow and remaining state screenshots, GUI smoothness and
memory measurements, human accessibility review, broader provider/controller
conformance, and full live GTK route parity.

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
