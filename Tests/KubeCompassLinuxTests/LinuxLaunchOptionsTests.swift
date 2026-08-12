import XCTest
@testable import KubeCompassLinuxSupport
@testable import KubeCompassCore

final class LinuxLaunchOptionsTests: XCTestCase {
    func testRowsAndSmokeArgumentsOverrideEnvironment() {
        let options = LinuxLaunchOptions(
            arguments: ["--smoke", "--rows", "10000"],
            environment: ["KUBECOMPASS_ROWS": "12"]
        )
        XCTAssertEqual(options.rows, 10_000)
        XCTAssertTrue(options.smoke)
        XCTAssertTrue(options.demo)
    }

    func testEnvironmentRowsAndInvalidValuesUseSafeDefaults() {
        XCTAssertEqual(
            LinuxLaunchOptions(arguments: [], environment: ["KUBECOMPASS_ROWS": "42"]).rows,
            42
        )
        XCTAssertEqual(
            LinuxLaunchOptions(arguments: ["--rows", "not-a-number"], environment: [:]).rows,
            2
        )
        XCTAssertEqual(
            LinuxLaunchOptions(arguments: ["--rows", "0"], environment: [:]).rows,
            1
        )
    }

    func testSemanticLabelsAndCatalogAreStable() {
        XCTAssertEqual(LinuxSemanticLabels.table, "resource table")
        XCTAssertEqual(LinuxDemoCatalog.resourceNames(rows: 3), ["pod-0", "pod-1", "pod-2"])
        XCTAssertEqual(LinuxDemoCatalog.status(for: 17), "Pending")
        XCTAssertEqual(LinuxDemoCatalog.labels(for: 4)["fixture"], "true")
    }

    func testTieredTopologySemanticVocabularyIsStable() {
        XCTAssertEqual(ExplorerLevel.allCases.map(\.rawValue), ["cluster", "infrastructure", "workloads", "network", "policy_dependencies", "evidence"])
        XCTAssertEqual(ExplorerMode.allCases.map(\.rawValue), ["focus", "trace", "inventory"])
        XCTAssertEqual(ExplorerPresentation.allCases.map(\.rawValue), ["map", "list", "port_table"])
        XCTAssertEqual(TopologyGraphQuery.level(for: "Service"), .network)
        XCTAssertEqual(TopologyGraphQuery.level(for: "NetworkPolicy"), .policyDependencies)
        XCTAssertEqual(TopologyGraphQuery.level(for: "Pod"), .workloads)
    }

    func testHumanFacingTopologyCopyDoesNotExposeWireValues() {
        let humanTitles = [
            "Policy & Dependencies", "Port table", "Port details", "Service port", "targetPort", "app protocol", "node port", "host port", "host IP",
            "No endpoint", "No ready endpoint",
            "Observed", "Declared", "Inferred", "Unavailable"
        ]
        XCTAssertTrue(humanTitles.allSatisfy { !$0.contains("_") })
        XCTAssertFalse(humanTitles.contains("policy_dependencies"))
        XCTAssertFalse(humanTitles.contains("port_table"))
        XCTAssertFalse(humanTitles.contains("no_endpoint"))
        XCTAssertFalse(humanTitles.contains("no_ready_endpoint"))
    }

    func testFixtureGraphCarriesCompleteAndUnresolvedNamedPortPaths() {
        let pod = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "v1", kind: "Pod", name: "orders-1", namespace: "default", uid: "uid-pod", resourceVersion: "1"),
            containerPorts: [TopologyContainerPort(containerName: "api", name: "web", port: 8443)]
        )
        let service = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "v1", kind: "Service", name: "orders", namespace: "default", uid: "uid-service", resourceVersion: "1"),
            servicePorts: [TopologyServicePort(name: "https", port: 443, targetPort: TopologyPortTarget(name: "web"))],
            serviceMode: .standard
        )
        let slice = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "discovery.k8s.io/v1", kind: "EndpointSlice", name: "orders-1", namespace: "default", uid: "uid-slice", resourceVersion: "1"),
            endpointSlice: TopologyEndpointSliceSnapshot(
                serviceName: "orders",
                addressType: "IPv4",
                ports: [TopologyEndpointPort(name: "https", port: 8443)],
                endpoints: [TopologyEndpointTarget(reference: TopologyObjectReference(apiVersion: "v1", kind: "Pod", name: "orders-1", namespace: "default", uid: "uid-pod"), ready: true, addresses: ["10.42.0.8"])
                ]
            )
        )
        let route = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "networking.k8s.io/v1", kind: "Ingress", name: "orders", namespace: "default", uid: "uid-ingress", resourceVersion: "1"),
            ingressRoutes: [TopologyIngressRoute(host: "orders.example.test", path: "/", backendName: "orders", backendNamespace: "default", backendPort: 443)]
        )
        let missingRoute = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "networking.k8s.io/v1", kind: "Ingress", name: "missing", namespace: "default", uid: "uid-missing", resourceVersion: "1"),
            ingressRoutes: [TopologyIngressRoute(host: "missing.example.test", path: "/", backendName: "unknown", backendNamespace: "default", backendPortName: "web")]
        )

        let graph = TopologyGraphBuilder.build(contextID: "linux-fixture", resources: [pod, service, slice, route, missingRoute])
        let query = TopologyGraphQuery(graph: graph)
        XCTAssertEqual(query.portPaths(level: .network).count, 2)
        XCTAssertTrue(query.portPaths(level: .network, port: 443).contains { $0.status == .complete })
        XCTAssertTrue(query.portPaths(level: .network).contains { $0.status == .unresolved })
        let complete = try! XCTUnwrap(query.portPaths(level: .network, port: 443).first { $0.status == .complete })
        XCTAssertTrue(complete.hops.contains { $0.role == "service-port" && $0.portNumber == 443 })
        XCTAssertTrue(complete.hops.contains { $0.role == "endpoint-port" && $0.portNumber == 8443 })
        XCTAssertTrue(complete.hops.contains { $0.role == "container-port" && $0.portNumber == 8443 })
        XCTAssertEqual(graph.completeness, .partial)
    }

    func testTypedPortDetailsRemainAvailableFromGraphDetails() {
        let pod = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "v1", kind: "Pod", name: "orders-1", namespace: "default", uid: "uid-pod", resourceVersion: "1"),
            containerPorts: [TopologyContainerPort(containerName: "api", name: "web", port: 8443, protocolName: "TCP", hostPort: 9443, hostIP: "127.0.0.1")]
        )
        let service = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "v1", kind: "Service", name: "orders", namespace: "default", uid: "uid-service", resourceVersion: "1"),
            servicePorts: [TopologyServicePort(name: "https", port: 443, targetPort: TopologyPortTarget(name: "web"), protocolName: "TCP", appProtocol: "https", nodePort: 30443)],
            serviceMode: .nodePort
        )
        let slice = TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: "discovery.k8s.io/v1", kind: "EndpointSlice", name: "orders-1", namespace: "default", uid: "uid-slice", resourceVersion: "1"),
            endpointSlice: TopologyEndpointSliceSnapshot(
                serviceName: "orders",
                addressType: "IPv4",
                ports: [TopologyEndpointPort(name: "https", port: 8443, protocolName: "TCP", appProtocol: "https")]
            )
        )

        let graph = TopologyGraphBuilder.build(contextID: "linux-detail-fixture", resources: [pod, service, slice])
        let serviceID = service.identity.stableNodeID(contextID: "linux-detail-fixture")
        let podID = pod.identity.stableNodeID(contextID: "linux-detail-fixture")
        let sliceID = slice.identity.stableNodeID(contextID: "linux-detail-fixture")
        let serviceDetails = try! XCTUnwrap(graph.details[serviceID])
        let podDetails = try! XCTUnwrap(graph.details[podID])
        let sliceDetails = try! XCTUnwrap(graph.details[sliceID])

        XCTAssertEqual(serviceDetails.servicePorts.first?.targetPort.name, "web")
        XCTAssertEqual(serviceDetails.servicePorts.first?.appProtocol, "https")
        XCTAssertEqual(serviceDetails.servicePorts.first?.nodePort, 30_443)
        XCTAssertEqual(sliceDetails.endpointSlice?.ports.first?.appProtocol, "https")
        XCTAssertEqual(podDetails.containerPorts.first?.hostPort, 9_443)
        XCTAssertEqual(podDetails.containerPorts.first?.hostIP, "127.0.0.1")
        XCTAssertEqual(serviceDetails.serviceMode, .nodePort)
    }
}
