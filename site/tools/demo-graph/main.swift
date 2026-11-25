// Builds the evidence graph that KubeCompassCore produces for the demo fixture in
// Tests/KubeCompassCoreTests/TopologyGraphTests.swift
// (testOwnerChainPlacementServiceEndpointIngressStorageAndConfigEdges) and prints
// the nodes and edges the landing page draws. Run through site/scripts/demo-graph.sh,
// which compiles this file together with Sources/KubeCompassCore.
import Foundation

let freshness = TopologyFreshness(capturedAt: Date(timeIntervalSince1970: 1_700_000_000), generation: 7)

func identity(_ kind: String, _ name: String, namespace: String? = "demo", uid: String, labels: [String: String] = [:]) -> TopologyResourceIdentity {
    TopologyResourceIdentity(apiVersion: kind.lowercased().contains("deployment") ? "apps/v1" : "v1", kind: kind, name: name, namespace: namespace, uid: uid, labels: labels)
}

func node(_ kind: String, _ name: String, namespace: String? = "demo", uid: String, labels: [String: String] = [:], owners: [TopologyOwnerReference] = [], podNodeName: String? = nil, selector: [String: String] = [:], ingress: [TopologyServiceReference] = [], endpoint: TopologyEndpointSliceSnapshot? = nil, volumes: [TopologyObjectReference] = [], configs: [TopologyNamedReference] = []) -> TopologyResourceSnapshot {
    TopologyResourceSnapshot(identity: identity(kind, name, namespace: namespace, uid: uid, labels: labels), ownerReferences: owners, podNodeName: podNodeName, selector: selector, ingressBackends: ingress, endpointSlice: endpoint, volumeReferences: volumes, configReferences: configs)
}

let resources = [
    node("Namespace", "demo", namespace: nil, uid: "ns-1"),
    node("Node", "worker-a", namespace: nil, uid: "node-1"),
    node("Deployment", "web", uid: "deploy-1", selector: ["app": "web"]),
    node("ReplicaSet", "web-abc", uid: "rs-1", labels: ["app": "web"], owners: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "Deployment", name: "web", uid: "deploy-1")]),
    node("Pod", "web-0", uid: "pod-1", labels: ["app": "web"], owners: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "ReplicaSet", name: "web-abc", uid: "rs-1")], podNodeName: "worker-a", volumes: [TopologyObjectReference(kind: "PersistentVolumeClaim", name: "web-data", namespace: "demo")], configs: [TopologyNamedReference(kind: "ConfigMap", name: "web-config"), TopologyNamedReference(kind: "Secret", name: "web-credentials")]),
    node("Service", "web", uid: "svc-1", selector: ["app": "web"]),
    node("EndpointSlice", "web-1", uid: "slice-1", endpoint: TopologyEndpointSliceSnapshot(serviceName: "web", endpoints: [TopologyEndpointTarget(reference: TopologyObjectReference(kind: "Pod", name: "web-0", namespace: "demo", uid: "pod-1"), ready: true)])),
    node("Ingress", "web", uid: "ing-1", ingress: [TopologyServiceReference(name: "web", port: 443)]),
    node("PersistentVolumeClaim", "web-data", uid: "pvc-1", volumes: [TopologyObjectReference(kind: "PersistentVolume", name: "pv-web", uid: "pv-1")]),
    node("PersistentVolume", "pv-web", namespace: nil, uid: "pv-1", volumes: [TopologyObjectReference(kind: "StorageClass", name: "fast", uid: "sc-1")]),
    node("StorageClass", "fast", namespace: nil, uid: "sc-1"),
]

let graph = TopologyGraphBuilder.build(contextID: "dev", resources: resources, freshness: freshness)

// Only typed, allowlisted fields leave this tool: kind, name, relationship,
// evidence level, source field, join rule and assumption. Unresolved references
// are counted, not named.
struct OutNode: Encodable { let id: String; let kind: String; let name: String; let level: String; let virtual: Bool }
struct OutEdge: Encodable { let from: String; let to: String; let relationship: String; let level: String; let sourceField: String?; let joinRule: String?; let assumption: String? }
struct Out: Encodable { let source: String; let completeness: String; let nodes: [OutNode]; let edges: [OutEdge]; let unresolvedReferences: Int }

let out = Out(
    source: "Tests/KubeCompassCoreTests/TopologyGraphTests.swift testOwnerChainPlacementServiceEndpointIngressStorageAndConfigEdges, built by TopologyGraphBuilder",
    completeness: graph.completeness.rawValue,
    nodes: graph.nodes.map { OutNode(id: $0.id, kind: $0.kind, name: $0.name, level: $0.evidence.level.rawValue, virtual: $0.isVirtual) },
    edges: graph.edges.map { OutEdge(from: $0.from, to: $0.to, relationship: $0.relationship.rawValue, level: $0.evidence.level.rawValue, sourceField: $0.evidence.source.sourceField, joinRule: $0.evidence.source.joinRule, assumption: $0.evidence.source.assumption) },
    unresolvedReferences: graph.unresolvedReferences.count
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(data: try! encoder.encode(out), encoding: .utf8)!)
