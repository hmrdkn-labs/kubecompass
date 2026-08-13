# Use an outline-first hybrid topology interaction model

## Status

Accepted for the next Topology Explorer interaction slice. This decision
complements [ADR 0001](0001-evidence-aware-topology.md) and [ADR 0002](0002-semantic-explorer-levels.md).
It is a product interaction contract, not evidence that every state or
platform adapter is already implemented.

## Context

Reference review found two useful but different patterns:

- Headlamp provides a scoped, source-driven resource map with stable IDs,
  namespace/project grouping, hover glance, and selected-node details.
- Argo CD provides a deterministic ownership/resource tree with health and
  sync badges and a detail surface.
- Kiali and Hubble visualize telemetry-backed service dependencies or flows,
  not API-only Kubernetes relationships.
- KubeView is a lightweight logical graph; KubeDiagrams is primarily a static
  architecture/teaching generator; Lens's resource map is extension/experimental.

KubeCompass already has an evidence graph and semantic resource groupings. A
cluster-wide graph as the default would over-prioritize geometry, hide partial
RBAC, and invite unsupported traffic interpretations. A tree alone would make
bounded dependency/path inspection awkward.

## Decision

KubeCompass exposes one shared selection model through three active surfaces;
Traffic is an unavailable capability unless telemetry is explicitly supplied:

1. **Outline (default):** deterministic namespace/workload/dependent hierarchy.
   It is the canonical keyboard semantic surface; ownership, scope, and
   evidence state are readable without traversing edges.
2. **Scoped Map (secondary):** a node/fanout-bounded graph entered from an
   Outline or selected root. It uses stable typed IDs, one/two-hop bounds,
   visible truncation status, an explicit Outline handoff, and the same
   inspector as Outline.
3. **Paths (diagnostic):** the canonical typed diagnostic list for one Route,
   Service, EndpointSlice, Pod/container, policy, or dependency path. Typed
   hops retain source fields, resolution, readiness, and Evidence Level.
4. **Traffic (unavailable):** hidden or explicitly unavailable unless an
   independent telemetry adapter supplies flow evidence with source, time
   range, direction, and coverage. API references never become traffic claims.

The canonical capture scenarios are maintained in
[`docs/interface/reference-topology-v2/reference-coverage.json`](../interface/reference-topology-v2/reference-coverage.json): outline-ready,
selected-workload detail, scoped map, path details, partial RBAC, loading,
empty, and error, each at wide and narrow desktop sizes.

## Provenance contract

| Statement | Provenance |
| --- | --- |
| Headlamp source-driven map, stable IDs, side details, and glance | **Observed** in [official map documentation](https://headlamp.dev/docs/latest/development/plugins/functionality/extending-the-map/) and the [official source](https://github.com/kubernetes-sigs/headlamp). |
| Argo CD ownership/resource tree and health/sync status | **Observed** in [official ApplicationSet UI docs](https://argo-cd.readthedocs.io/en/latest/user-guide/application-set-ui/) and [health docs](https://argo-cd.readthedocs.io/en/release-3.1/operator-manual/health/). |
| Kiali/Hubble graphs require telemetry | **Observed** in [Kiali's official repository](https://github.com/kiali/kiali) and [Hubble UI docs](https://docs.cilium.io/en/stable/observability/hubble/hubble-ui/). |
| Outline-first hybrid is the KubeCompass interaction | **Inferred** from the reference review and KubeCompass's evidence-aware graph contract. |
| Native wide/narrow parity, 20k+ KubeCompass scale, and Traffic adapter readiness | **Unknown** until fresh captures and runtime/telemetry gates pass. |

## Consequences

- Outline remains the complete semantic/accessibility hierarchy and Paths is
  the typed diagnostic list; the Map is not the only way to understand a
  relationship.
- Scoped Map layout must be deterministic, node/fanout bounded, and visibly
  truncated when its core 180-node cap is reached, with an Outline handoff. No
  force-directed physics may imply traffic or physical topology.
- Paths reuse the existing typed Port Path and evidence language. A declared
  or inferred path may still be unresolved, partial, or unavailable.
- Partial RBAC and unsupported inputs remain visible as Partial/Unavailable,
  never Empty.
- Traffic requires a separately permissioned telemetry adapter and cannot be
  enabled by reference, selector, owner, or EndpointSlice data alone.
- Third-party screenshots, logos, and images remain external research
  references. They are not copied into KubeCompass production assets.

## Rejected alternatives

- **Map-first:** makes geometry the default explanation and does not provide a
  stable answer for ownership, evidence gaps, or accessibility.
- **Traffic-like graph from Kubernetes objects:** unsupported by the API-only
  evidence contract.
- **Static diagram as the product view:** useful for teaching, but cannot
  represent live selection, state transitions, RBAC gaps, or current evidence.
- **Force-directed map as canonical:** unstable at scale and too easy to read
  as physical connectivity.
