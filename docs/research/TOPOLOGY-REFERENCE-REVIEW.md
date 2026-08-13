# Topology reference review

## Decision

KubeCompass uses a hybrid topology surface with an evidence-first outline as
the default:

1. **Outline (default):** a deterministic semantic hierarchy for cluster,
   namespace, workload ownership, network declarations, policy/dependencies,
   and evidence. This is the first answer to “what is here and why?”.
2. **Scoped Map (secondary):** a node/fanout-bounded graph for a selected root
   and one or two relationship hops. Nodes have stable typed IDs, visible
   truncation status, and an explicit handoff back to Outline; selection opens
   the same detail/evidence inspector as Outline.
3. **Paths (diagnostic):** a step-through view for one declared or inferred
   Port Path. It shows typed hops, resolution, readiness, and provenance; it
   does not claim packet delivery.
4. **Traffic (unavailable by default):** no traffic graph is rendered unless a
   separately permissioned telemetry adapter supplies flow evidence. Selectors,
   owner references, Routes, and EndpointSlices are not traffic evidence.

The exact original KubeCompass capture contract is the planning manifest at
[`docs/interface/reference-topology-v2/reference-coverage.json`](../interface/reference-topology-v2/reference-coverage.json).
It requires wide and narrow captures for outline-ready, selected-workload
detail, scoped map, path details, partial RBAC, loading, empty, and error.

## Method and evidence boundary

This is a focused reference review, not a claim that KubeCompass implements
every behavior below. Each conclusion is tagged:

- **Observed:** the behavior is explicit in an official product document or
  official source.
- **Inferred:** the behavior is a transferable design rule derived from the
  observed reference and KubeCompass's evidence contract.
- **Unknown:** the behavior needs a fresh KubeCompass capture, accessibility
  review, or runtime measurement before it can be claimed.

Official links are retained for auditability. Reference images remain links or
research notes; do not copy third-party images, logos, or screenshots into the
KubeCompass production artifact.

## Reference findings

| Reference | Observed behavior | Transferable rule | Status and boundary |
| --- | --- | --- | --- |
| [Headlamp Map](https://headlamp.dev/docs/latest/development/plugins/functionality/extending-the-map/), [Projects](https://headlamp.dev/docs/latest/learn/projects/), [official source](https://github.com/kubernetes-sigs/headlamp), and [releases/performance evidence](https://github.com/kubernetes-sigs/headlamp/releases) | Resource graph sources, stable node/edge IDs, source picker, namespace/project scoping, hover glance, selected-node side details, and relationship-focused maps. The official implementation is React-based; the upstream graph implementation uses React Flow + ELK. Headlamp's release evidence reports 20k+ scale and related 59%/86% performance figures. | Use stable IDs, explicit scope/filter controls, bounded graph queries, and click for the full evidence panel. Keep the map a scoped answer rather than a cluster-wide default. | **Observed** from official docs/source; the performance figures are upstream reference evidence, not a KubeCompass benchmark. Exact layout and resource coverage remain **unknown** for KubeCompass. |
| [Argo CD ApplicationSet resource tree](https://argo-cd.readthedocs.io/en/latest/user-guide/application-set-ui/), [resource hierarchy command](https://argo-cd.readthedocs.io/en/latest/user-guide/commands/argocd_app_resources/), and [resource health](https://argo-cd.readthedocs.io/en/release-3.1/operator-manual/health/) | Deterministic parent/child ownership tree; health and sync status are visible on nodes; fit/zoom supports tree orientation; selection opens a right/slide-out detail surface; hierarchy supports focused application inspection. | Make ownership/declared relationships the stable outline. Put health, sync, status, and evidence in badges or the inspector without relying on edge geometry. | **Observed** reference behavior. Argo's tree is application/GitOps ownership, not a generic Kubernetes resource graph; extending it to KubeCompass relationships is **inferred** and must preserve evidence levels. |
| [Kiali](https://github.com/kiali/kiali) | Graph is an Istio service-mesh management/observability surface and can expose graph telemetry. | Treat telemetry-backed service graphs as a separate diagnostic adapter and label their source and time range. | **Observed** telemetry boundary. Kiali is not evidence for an API-only resource map; use is **unavailable** without the relevant mesh/telemetry input. |
| [Hubble UI](https://docs.cilium.io/en/stable/observability/hubble/hubble-ui/) | Service map discovers L3/L4/L7 service dependencies from Hubble flow events and supports filtering and recent-flow inspection. | Reserve “Traffic” for explicit flow evidence with source, timestamp, direction, and sampling/coverage details. | **Observed** telemetry boundary. Hubble requires Cilium/Hubble telemetry; no traffic claim is made from KubeCompass API snapshots. |
| [KubeView](https://github.com/benc-uk/kubeview) | Lightweight read-only logical graph of resource relationships with status coloring, filtering, search, and a side information panel. | Keep a small logical graph available for a bounded scope, but pair it with the canonical Outline hierarchy, typed Paths, and persistent inspector so the graph is never the only carrier of meaning. | **Observed** from the official repository. “Minimal logical graph” is the review's characterization; scale, accessibility, and evidence semantics for KubeCompass are **unknown**. |
| [KubeDiagrams](https://github.com/philippemerle/KubeDiagrams) | Generates architecture diagrams from manifests, Helm/kustomization inputs, or cluster state, with export and teaching/architecture use cases. | Use static diagrams as explanatory fixtures or onboarding material, not as the live interaction model or status authority. | **Observed** generator boundary. It does not establish live selection, RBAC partiality, or current traffic truth for KubeCompass. |
| [Lens](https://github.com/lensapp/lens), [Lens extensions](https://github.com/lensapp/lens-extensions), and the [resource-map extension/demo](https://github.com/nevalla/lens-resource-map-extension) | Resource-map behavior is delivered as an extension/demo force-directed graph rather than a stable core product contract. | Do not make a force-directed resource map the default. If a map is offered, scope it, preserve stable selection, and provide an explicit handoff to Outline. | **Observed** extension/demo boundary. Lens map behavior and current extension compatibility are **unknown** for KubeCompass and are not a design dependency. |

### Synthesis

The strongest complementary evidence is Headlamp's scoped, source-driven map
and Argo CD's deterministic ownership tree. KubeCompass therefore adopts the
following inferred rules:

- **Hierarchy before geometry.** Outline answers ownership and semantic scope
  without requiring the user to decode crossing edges.
- **Map only for a question.** A map is entered from a selected root, bounded
  to one or two hops and a node/fanout budget, reports visible truncation, and
  offers an explicit handoff back to Outline.
- **Selection is shared.** Outline, Scoped Map, and Paths share stable IDs and
  open the same Fundamentals/evidence inspector; Outline is the canonical
  keyboard hierarchy and Paths the canonical typed diagnostic list.
- **Evidence is visible.** Every relationship and Port Hop exposes Observed,
  Declared, Inferred, or Unavailable status plus “what this proves / does not
  prove”.
- **Telemetry is opt-in.** Traffic is unavailable unless a telemetry adapter
  provides the required flow evidence; it is never inferred from object
  references or selectors.

## KubeCompass state and capture contract

The capture matrix is intentionally planning-only until each image is freshly
captured from the original KubeCompass route. Each scenario has wide (`1440 ×
900`) and narrow (`900 × 700`) desktop frames:

| Scenario | Required result |
| --- | --- |
| Outline ready | Default Outline, current context/namespace, semantic hierarchy, status, and next-step affordances. |
| Selected workload detail | A workload selected from Outline; detail/evidence inspector is visible and selection is retained. |
| Scoped map | A selected-root node/fanout-bounded map with one/two-hop scope, visible truncation status, and an Outline handoff. |
| Path details | One Port Path selected; typed hops, resolution, readiness, and proof/non-proof copy are visible. |
| Partial RBAC | Forbidden input remains Partial/Unavailable with readable evidence; it is not rendered as Empty or complete. |
| Loading | Shell, context, scope, and progress appear before graph data; selection cannot be fabricated. |
| Empty | Scope completed with no matching resources; context remains visible and the next scope action is explicit. |
| Error | Failed refresh names the failed input, retains safe prior evidence when available, and offers read-only retry. |

The manifest records trigger/result pairs and ordered flows so a ready image
cannot substitute for state coverage. Captures must be local PNGs generated
from KubeCompass; third-party media is reference-only and must not enter
production.

## Open questions

- Does the native wide and narrow route preserve the same selection, breadcrumb,
  keyboard order, and evidence inspector semantics across Outline, Map, and
  Paths? **Unknown** until the manifest is captured and reviewed.
- What is the measured KubeCompass graph/query/frame/RSS envelope at the
  reference's 20k+ scale? **Unknown**; Headlamp's upstream claim is not a
  KubeCompass performance result.
- Which telemetry adapter, permissions, time range, and sampling contract
  would be required before Traffic can become available? **Unknown** and
  outside this read-only topology decision.
