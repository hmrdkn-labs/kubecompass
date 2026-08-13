# Use semantic Explorer Levels instead of flat kind lanes

## Status

Superseded by [ADR 0003](0003-topology-interaction-model.md) on 2026-08-13.
This ADR records the historical ExplorerLevel/ExplorerMode/
ExplorerPresentation prototype contract. The Linux fixture still contains
that vocabulary, but it is compatibility evidence only; the current product
contract is defined by ADR 0003 and is not implemented by this ADR.

## Decision

Replace the flat kind-lane Map with semantic Explorer Levels:

1. Cluster
2. Infrastructure
3. Workloads
4. Network
5. Policy & Dependencies
6. Evidence

Each level has Focus, Trace, and Inventory modes and equivalent Map, List, and
Port Table representations. The desktop shell keeps a scope rail, exploration
canvas, and evidence inspector visible at wide sizes and supplies a single-pane
back path at narrow sizes.

## Why

The flat map places objects of different semantic roles beside one another,
encourages crossing edges, and makes a Service port or Route look like the same
kind of fact as a namespace or Node. It cannot answer the learner's next
question without requiring a global graph scan. It also has no canonical place
to show typed Service, targetPort, EndpointSlice, and container-port semantics.

Explorer Levels make the user's question explicit, progressively reveal detail,
and keep unrelated resources out of the immediate Focus. The Port Table makes
protocol, names, numbers, resolution, readiness, and Evidence Levels readable
without depending on edge geometry. List remains a semantic and accessibility
parity surface rather than a secondary fallback.

## Consequences

- The graph/core must expose typed Port Paths and Port Hops before the Network
  level can be considered complete.
- Map layout becomes compound and semantic; force-directed physics and a
  silent global node cap are not acceptable defaults.
- Snapshot Status and Exposure Status are separate contracts.
- Every selected relationship, Route, or Port Path must explain what it proves
  and does not prove.
- Existing synthetic Map/List screenshots document the old prototype and must
  not be reused as evidence that this decision is implemented.
- SwiftUI and GTK adapters may use native controls and different geometry, but
  must preserve level, mode, view, focus, evidence, state, and accessibility
  semantics.

## Rejected alternatives

- **Add more labels to the existing lanes:** retains the hierarchy and port
  ambiguity problems.
- **Force-directed “network map”:** implies physical or traffic relationships
  that Kubernetes API objects do not prove and becomes unstable at scale.
- **Ports as edge text only:** cannot represent named targetPort resolution,
  EndpointSlice readiness, ambiguity, or a declared container port honestly.
