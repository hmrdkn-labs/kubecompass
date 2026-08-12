# KubeCompass

KubeCompass is a native Kubernetes workspace that explains cluster state
without presenting derived relationships as stronger evidence than the API
provides.

## Cluster exploration

**Topology Explorer**:
The read-only workspace for navigating Kubernetes resources and the
relationships between them.
_Avoid_: Network map, cluster truth, packet map

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
