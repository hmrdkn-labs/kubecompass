# KubeCompass

KubeCompass is a native Kubernetes workspace that explains cluster state
without presenting derived relationships as stronger evidence than the API
provides.

## Cluster exploration

**Topology Explorer**:
The read-only learning workspace for navigating Kubernetes resources,
evidence-backed relationships, and scoped cluster questions.
_Avoid_: Network map, cluster truth, packet map

**Explorer Level**:
A semantic scale of the Topology Explorer: Cluster, Infrastructure,
Workloads, Network, Policy & Dependencies, or Evidence. Levels control what is
aggregated, what can be expanded, and which question the surface answers.
_Avoid_: Tier, when it could be confused with a Kubernetes label or platform
tier

**Fundamentals**:
The plain-language explanation attached to a selected resource, relationship,
or port path: what the API input says, what KubeCompass can prove from the
snapshot, and what it cannot prove.

**Route**:
A declared ingress or Gateway API route, including its listener or host/path
identity, backend reference, and status where available. A Route expresses
configuration intent; it is not a packet-flow observation.

**Port Path**:
An ordered, typed explanation of an exposure or backend port from a Route or
Service through Service port and targetPort resolution, EndpointSlice port and
address, and (when declared) a Pod container port.

**Port Hop**:
One typed transition inside a Port Path. A Port Hop names the source field,
protocol, port identity, target, and Evidence Level. It may be unresolved or
ambiguous.

**Exposure Status**:
The bounded status of a Route, Service, or Port Path based on fetched API
fields: Declared, Resolved, Ready endpoints, No ready endpoints, Ambiguous,
Unresolved, Partial, or Unavailable. It never means that a request was
delivered.

**Snapshot Status**:
The freshness and completeness state of a Topology Snapshot: Loading, Ready,
Empty, Partial, Stale, Offline, Reconnecting, or Error. Snapshot Status is
separate from Exposure Status.

**Focus mode**:
A bounded view centered on the selected object and its directly relevant
neighbors, with unrelated graph content de-emphasized or hidden.

**Trace mode**:
A semantic step-through of one relationship, Route, Port Path, policy, or
dependency. Trace mode shows each hop and its evidence instead of drawing an
unqualified line.

**Inventory mode**:
A tabular, searchable view of the resources or Port Hops in the current
Explorer Level. Inventory mode is the parity surface when geometry is crowded,
unavailable, or inaccessible.

**Resource Node**:
A displayed Kubernetes object identified by context, API identity, and UID.
_Avoid_: Node, when that could be confused with a Kubernetes Node object

**Relationship**:
A directional association between two Resource Nodes, supported by a named
source field or a documented join rule.
_Avoid_: Connection, traffic flow

**Evidence Level**:
The strength and origin of a Relationship: Observed, Declared, Inferred, or
Unavailable.
_Avoid_: Confidence score

**Observed Relationship**:
A Relationship backed by an explicit source field and a fetched target, such
as a Pod `spec.nodeName` that resolves to a Kubernetes Node.

**Declared Relationship**:
Configuration intent recorded in a resource spec, such as an Ingress backend
that names a Service; it does not prove runtime delivery.

**Inferred Relationship**:
A deterministic join across fetched objects, such as a Service selector that
matches a Pod; it does not prove traffic or enforcement.

**Unavailable Input**:
A kind or scope that could not be read because it is forbidden, unsupported,
offline, timed out, or stale. It is not equivalent to an empty result.
_Avoid_: Missing resource

**Unresolved Reference**:
A typed reference whose target was not present in the snapshot, with its
source and reason preserved.
_Avoid_: Broken connection

**Control-plane Boundary**:
A virtual boundary representing the Kubernetes API surface when provider
control-plane internals are not exposed as resources.
_Avoid_: Control-plane node, master node

**Topology Snapshot**:
A generation-scoped, timestamped graph assembled from allowlisted Kubernetes
metadata and relationship fields, including partial-input status.
_Avoid_: Cluster snapshot, because most object payloads are intentionally absent
