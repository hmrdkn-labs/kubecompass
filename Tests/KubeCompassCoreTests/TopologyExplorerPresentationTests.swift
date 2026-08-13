import XCTest
@testable import KubeCompassCore

final class TopologyExplorerPresentationTests: XCTestCase {
    private let freshness = TopologyFreshness(capturedAt: Date(timeIntervalSince1970: 1_700_000_000), generation: 11)

    private func resource(_ kind: String, _ name: String, namespace: String? = "demo", uid: String, labels: [String: String] = [:], owners: [TopologyOwnerReference] = [], selector: [String: String] = [:], ingress: [TopologyIngressRoute] = [], endpoint: TopologyEndpointSliceSnapshot? = nil, volumes: [TopologyObjectReference] = [], configs: [TopologyNamedReference] = [], servicePorts: [TopologyServicePort] = [], containerPorts: [TopologyContainerPort] = []) -> TopologyResourceSnapshot {
        let apiVersion = ["Deployment", "ReplicaSet"].contains(kind) ? "apps/v1" : "v1"
        return TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: apiVersion, kind: kind, name: name, namespace: namespace, uid: uid, labels: labels),
            ownerReferences: owners,
            selector: selector,
            ingressRoutes: ingress,
            endpointSlice: endpoint,
            servicePorts: servicePorts,
            containerPorts: containerPorts,
            volumeReferences: volumes,
            configReferences: configs
        )
    }

    private func fixture() -> TopologyGraph {
        let namespace = resource("Namespace", "demo", namespace: nil, uid: "namespace-demo")
        let deployment = resource("Deployment", "web", uid: "deployment-web", labels: ["app": "web"], selector: ["app": "web"])
        let replicaSet = resource("ReplicaSet", "web-abc", uid: "replicaset-web", labels: ["app": "web"], owners: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "Deployment", name: "web", uid: "deployment-web")], selector: ["app": "web"])
        let pod = resource("Pod", "web-0", uid: "pod-web", labels: ["app": "web"], owners: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "ReplicaSet", name: "web-abc", uid: "replicaset-web")], volumes: [TopologyObjectReference(kind: "PersistentVolumeClaim", name: "web-data", namespace: "demo")], configs: [TopologyNamedReference(kind: "ConfigMap", name: "web-config")], containerPorts: [TopologyContainerPort(containerName: "web", name: "http", port: 8080)])
        let service = resource("Service", "web", uid: "service-web", selector: ["app": "web"], servicePorts: [TopologyServicePort(name: "http", port: 80, targetPort: TopologyPortTarget(name: "http"))])
        let slice = resource("EndpointSlice", "web-1", uid: "slice-web", endpoint: TopologyEndpointSliceSnapshot(serviceName: "web", ports: [TopologyEndpointPort(name: "http", port: 8080)], endpoints: [TopologyEndpointTarget(reference: TopologyObjectReference(kind: "Pod", name: "web-0", namespace: "demo", uid: "pod-web"), ready: true)]))
        let ingress = resource("Ingress", "web", uid: "ingress-web", ingress: [TopologyIngressRoute(host: "web.example.test", path: "/", backendName: "web", backendNamespace: "demo", backendPort: 80)])
        let pvc = resource("PersistentVolumeClaim", "web-data", uid: "pvc-web")
        let config = resource("ConfigMap", "web-config", uid: "config-web")
        // Same selector text, but no typed graph edge to the web lineage.
        let unrelatedService = resource("Service", "unrelated", uid: "service-unrelated", selector: ["app": "other"])
        return TopologyGraphBuilder.build(contextID: "fixture", resources: [unrelatedService, config, ingress, pod, pvc, service, slice, deployment, namespace, replicaSet], freshness: freshness)
    }

    func testOutlineGroupsNamespaceControllerDependentsAndTypedRelatedNodes() throws {
        let graph = fixture()
        let deploymentID = try XCTUnwrap(graph.nodes.first { $0.kind == "Deployment" && $0.name == "web" }?.id)
        let presentation = TopologyExplorerPresentation(graph: graph)

        XCTAssertEqual(presentation.surface, .outline)
        XCTAssertEqual(presentation.breadcrumb.segments, ["Cluster", "fixture"])
        XCTAssertEqual(presentation.scopeSummary, "All namespaces")
        let namespace = try XCTUnwrap(presentation.outline.first { $0.namespace == "demo" })
        let controller = try XCTUnwrap(namespace.controllers.first { $0.primary.id == deploymentID })
        XCTAssertEqual(controller.primary.kind, "Deployment")
        XCTAssertTrue(controller.dependents.contains { $0.kind == "ReplicaSet" })
        XCTAssertTrue(controller.dependents.contains { $0.kind == "Pod" })
        XCTAssertTrue(controller.related.contains { $0.kind == "Service" && $0.name == "web" })
        XCTAssertTrue(controller.related.contains { $0.kind == "Ingress" && $0.name == "web" })
        XCTAssertTrue(controller.related.contains { $0.kind == "PersistentVolumeClaim" && $0.name == "web-data" })
        XCTAssertTrue(controller.related.contains { $0.kind == "ConfigMap" && $0.name == "web-config" })
        XCTAssertFalse(controller.related.contains { $0.name == "unrelated" })
    }

    func testMapIsSelectedRootAndHardBoundToOneOrTwoTypedHops() throws {
        let graph = fixture()
        let deploymentID = try XCTUnwrap(graph.nodes.first { $0.kind == "Deployment" && $0.name == "web" }?.id)
        let presentation = TopologyExplorerPresentation(graph: graph, surface: .map, selectedRootID: deploymentID, maxHops: 99)
        let map = try XCTUnwrap(presentation.map)
        XCTAssertEqual(map.rootID, deploymentID)
        XCTAssertEqual(map.maxHops, 2)
        XCTAssertTrue(map.nodes.contains { $0.id == deploymentID })
        XCTAssertTrue(map.nodes.contains { $0.kind == "Pod" })
        XCTAssertTrue(map.edges.allSatisfy { edge in map.nodes.contains { node in node.id == edge.from } && map.nodes.contains { node in node.id == edge.to } })
        XCTAssertFalse(map.nodes.contains { $0.name == "unrelated" })
        XCTAssertFalse(map.nodes.contains { $0.kind == "Ingress" })
    }

    func testPathsSurfaceRetainsTypedDiagnosticsAndExplicitFilters() throws {
        let graph = fixture()
        let ingressID = try XCTUnwrap(graph.nodes.first { $0.kind == "Ingress" && $0.name == "web" }?.id)
        let ready = TopologyExplorerPresentation(graph: graph, surface: .paths, selectedRootID: ingressID, filter: TopologyExplorerFilter(search: "web", unresolvedOnly: false))
        XCTAssertEqual(ready.paths.count, 1)
        XCTAssertEqual(ready.paths.first?.status, .complete)
        XCTAssertTrue(ready.paths.first?.summary.contains("ready endpoints") == true)

        let onlyServices = TopologyExplorerPresentation(graph: graph, filter: TopologyExplorerFilter(kind: "Service"))
        XCTAssertTrue(onlyServices.outline.flatMap(\.unattached).allSatisfy { $0.kind == "Service" })
        XCTAssertEqual(onlyServices.filter.kind, "Service")

        let endpointSliceSearch = TopologyExplorerPresentation(graph: graph, surface: .paths, filter: TopologyExplorerFilter(search: "endpointslice"))
        XCTAssertEqual(endpointSliceSearch.paths.count, 1)

        XCTAssertTrue(TopologyExplorerPresentation(
            graph: graph,
            surface: .paths,
            filter: TopologyExplorerFilter(namespace: "other")
        ).paths.isEmpty)
        XCTAssertTrue(TopologyExplorerPresentation(
            graph: graph,
            surface: .paths,
            filter: TopologyExplorerFilter(kind: "Service")
        ).paths.isEmpty)
        XCTAssertTrue(TopologyExplorerPresentation(
            graph: graph,
            surface: .paths,
            filter: TopologyExplorerFilter(evidence: .unavailable)
        ).paths.isEmpty)
        XCTAssertTrue(TopologyExplorerPresentation(
            graph: graph,
            surface: .paths,
            filter: TopologyExplorerFilter(unresolvedOnly: true)
        ).paths.isEmpty)
    }

    func testPresentationOrderingIsStableForReorderedGraphCollections() {
        let graph = fixture()
        let reordered = TopologyGraph(contextID: graph.contextID, freshness: graph.freshness, completeness: graph.completeness, nodes: graph.nodes.reversed(), edges: graph.edges.reversed(), unresolvedReferences: graph.unresolvedReferences.reversed(), inputs: graph.inputs.reversed(), portPaths: graph.portPaths.reversed(), details: graph.details)
        XCTAssertEqual(TopologyExplorerPresentation(graph: graph), TopologyExplorerPresentation(graph: reordered))
    }

    func testSharedSelectorRelatedServiceHasOneCanonicalOutlinePlacement() throws {
        let podA = resource("Pod", "a", uid: "pod-a", labels: ["app": "shared"])
        let podB = resource("Pod", "b", uid: "pod-b", labels: ["app": "shared"])
        let service = resource("Service", "shared", uid: "service-shared", selector: ["app": "shared"])
        let graph = TopologyGraphBuilder.build(contextID: "shared", resources: [podB, service, podA], freshness: freshness)
        let placements = TopologyExplorerPresentation(graph: graph).outline
            .flatMap(\.controllers)
            .flatMap(\.related)
            .filter { $0.kind == "Service" && $0.name == "shared" }
        XCTAssertEqual(placements.count, 1)
    }

    func testCyclicOwnershipTerminatesAndKeepsTypedMapEdges() {
        let source = TopologyEvidence(level: .observed, source: .api(kind: "test"), freshness: freshness)
        let controller = TopologyNode(id: "deployment", contextID: "cycle", apiVersion: "apps/v1", kind: "Deployment", name: "cycle", namespace: "demo", evidence: source)
        let a = TopologyNode(id: "pod-a", contextID: "cycle", apiVersion: "v1", kind: "Pod", name: "a", namespace: "demo", evidence: source)
        let b = TopologyNode(id: "pod-b", contextID: "cycle", apiVersion: "v1", kind: "Pod", name: "b", namespace: "demo", evidence: source)
        let edges = [
            TopologyEdge(from: "pod-a", to: "deployment", relationship: .ownedBy, evidence: source),
            TopologyEdge(from: "pod-b", to: "pod-a", relationship: .ownedBy, evidence: source),
            TopologyEdge(from: "pod-a", to: "pod-b", relationship: .ownedBy, evidence: source)
        ]
        let graph = TopologyGraph(contextID: "cycle", freshness: freshness, completeness: .complete, nodes: [controller, a, b], edges: edges)
        let presentation = TopologyExplorerPresentation(graph: graph, surface: .map, selectedRootID: "deployment", maxHops: 2)
        XCTAssertEqual(presentation.map?.nodes.count, 3)
        XCTAssertEqual(presentation.map?.edges.count, 3)
    }

    func testMapHighFanoutIsBoundedStableAndCodable() throws {
        let source = TopologyEvidence(level: .observed, source: .api(kind: "test"), freshness: freshness)
        let root = TopologyNode(id: "deployment", contextID: "fanout", apiVersion: "apps/v1", kind: "Deployment", name: "fanout", namespace: "demo", evidence: source)
        let children = (0..<220).map { index in
            TopologyNode(id: "pod-\(index)", contextID: "fanout", apiVersion: "v1", kind: "Pod", name: "pod-\(index)", namespace: "demo", evidence: source)
        }
        let edges = children.map { TopologyEdge(from: $0.id, to: root.id, relationship: .ownedBy, evidence: source) }
        let graph = TopologyGraph(contextID: "fanout", freshness: freshness, completeness: .complete, nodes: [root] + children, edges: edges)
        let one = try XCTUnwrap(TopologyExplorerPresentation(graph: graph, surface: .map, selectedRootID: root.id, maxHops: 1).map)
        let two = try XCTUnwrap(TopologyExplorerPresentation(graph: graph, surface: .map, selectedRootID: root.id, maxHops: 1).map)
        XCTAssertEqual(one.nodes.count, 180)
        XCTAssertEqual(one.totalNodeCount, 221)
        XCTAssertTrue(one.isTruncated)
        XCTAssertEqual(one.omittedNodeCount, 41)
        XCTAssertEqual(one.nodes.first?.id, root.id)
        XCTAssertEqual(one, two)
        let encoded = try JSONEncoder().encode(one)
        XCTAssertEqual(try JSONDecoder().decode(TopologyExplorerMap.self, from: encoded), one)
    }

    func testPartialStatusWinsWhenFilterRemovesEveryNode() {
        let incomplete = resource("Pod", "incomplete", uid: "incomplete", volumes: [TopologyObjectReference(kind: "PersistentVolumeClaim", name: "missing", namespace: "demo")])
        let graph = TopologyGraphBuilder.build(contextID: "partial", resources: [incomplete], freshness: freshness)
        let presentation = TopologyExplorerPresentation(graph: graph, filter: TopologyExplorerFilter(kind: "NoSuchKind"))
        XCTAssertEqual(graph.completeness, .partial)
        XCTAssertTrue(presentation.outline.isEmpty)
        XCTAssertEqual(presentation.status, .partial)
    }
}
