import XCTest
@testable import KubeCompassCore

final class TopologyGraphTests: XCTestCase {
    private let freshness = TopologyFreshness(capturedAt: Date(timeIntervalSince1970: 1_700_000_000), generation: 7)

    private func identity(_ kind: String, _ name: String, namespace: String? = "demo", uid: String, labels: [String: String] = [:]) -> TopologyResourceIdentity {
        TopologyResourceIdentity(apiVersion: kind.lowercased().contains("deployment") ? "apps/v1" : "v1", kind: kind, name: name, namespace: namespace, uid: uid, labels: labels)
    }

    private func node(_ kind: String, _ name: String, namespace: String? = "demo", uid: String, labels: [String: String] = [:], owners: [TopologyOwnerReference] = [], podNodeName: String? = nil, selector: [String: String] = [:], selectorExpressions: [TopologySelectorRequirement] = [], ingress: [TopologyServiceReference] = [], endpoint: TopologyEndpointSliceSnapshot? = nil, volumes: [TopologyObjectReference] = [], configs: [TopologyNamedReference] = [], networkPolicy: TopologyNetworkPolicySnapshot? = nil, facts: [TopologyFact] = []) -> TopologyResourceSnapshot {
        TopologyResourceSnapshot(identity: identity(kind, name, namespace: namespace, uid: uid, labels: labels), ownerReferences: owners, podNodeName: podNodeName, selector: selector, selectorExpressions: selectorExpressions, ingressBackends: ingress, endpointSlice: endpoint, volumeReferences: volumes, configReferences: configs, networkPolicy: networkPolicy, facts: facts)
    }

    private func graph(_ resources: [TopologyResourceSnapshot], inputs: [TopologyInputStatus] = []) -> TopologyGraph {
        TopologyGraphBuilder.build(contextID: "dev", resources: resources, inputs: inputs, freshness: freshness)
    }

    func testOwnerChainPlacementServiceEndpointIngressStorageAndConfigEdges() {
        let namespace = node("Namespace", "demo", namespace: nil, uid: "ns-1")
        let worker = node("Node", "worker-a", namespace: nil, uid: "node-1")
        let deployment = node("Deployment", "web", uid: "deploy-1", selector: ["app": "web"])
        let replicaSet = node("ReplicaSet", "web-abc", uid: "rs-1", labels: ["app": "web"], owners: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "Deployment", name: "web", uid: "deploy-1")])
        let pod = node("Pod", "web-0", uid: "pod-1", labels: ["app": "web"], owners: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "ReplicaSet", name: "web-abc", uid: "rs-1")], podNodeName: "worker-a", volumes: [TopologyObjectReference(kind: "PersistentVolumeClaim", name: "web-data", namespace: "demo")], configs: [TopologyNamedReference(kind: "ConfigMap", name: "web-config"), TopologyNamedReference(kind: "Secret", name: "web-credentials")])
        let service = node("Service", "web", uid: "svc-1", selector: ["app": "web"])
        let slice = node("EndpointSlice", "web-1", uid: "slice-1", endpoint: TopologyEndpointSliceSnapshot(serviceName: "web", endpoints: [TopologyEndpointTarget(reference: TopologyObjectReference(kind: "Pod", name: "web-0", namespace: "demo", uid: "pod-1"), ready: true)]))
        let ingress = node("Ingress", "web", uid: "ing-1", ingress: [TopologyServiceReference(name: "web", port: 443)])
        let pvc = node("PersistentVolumeClaim", "web-data", uid: "pvc-1", volumes: [TopologyObjectReference(kind: "PersistentVolume", name: "pv-web", uid: "pv-1")])
        let pv = node("PersistentVolume", "pv-web", namespace: nil, uid: "pv-1", volumes: [TopologyObjectReference(kind: "StorageClass", name: "fast", uid: "sc-1")])
        let storage = node("StorageClass", "fast", namespace: nil, uid: "sc-1")

        let result = graph([namespace, worker, deployment, replicaSet, pod, service, slice, ingress, pvc, pv, storage])
        XCTAssertTrue(result.edges.contains { $0.relationship == .ownedBy && $0.from.contains("pod-1") && $0.to.contains("rs-1") })
        XCTAssertTrue(result.edges.contains { $0.relationship == .ownedBy && $0.from.contains("rs-1") && $0.to.contains("deploy-1") })
        XCTAssertTrue(result.edges.contains { $0.relationship == .scheduledOn && $0.from.contains("pod-1") && $0.to.contains("node-1") })
        XCTAssertTrue(result.edges.contains { $0.relationship == .selects && $0.from.contains("svc-1") && $0.to.contains("pod-1") && $0.evidence.level == .inferred })
        XCTAssertTrue(result.edges.contains { $0.relationship == .publishesEndpoints && $0.from.contains("slice-1") && $0.to.contains("svc-1") })
        XCTAssertTrue(result.edges.contains { $0.relationship == .endpointTarget && $0.from.contains("slice-1") && $0.to.contains("pod-1") && $0.attributes["ready"] == "true" })
        XCTAssertTrue(result.edges.contains { $0.relationship == .routesTo && $0.from.contains("ing-1") && $0.to.contains("svc-1") && $0.attributes["port"] == "443" && $0.evidence.level == .declared })
        XCTAssertTrue(result.edges.contains { $0.relationship == .backedBy && $0.from.contains("pvc-1") && $0.to.contains("pv-1") })
        XCTAssertTrue(result.edges.contains { $0.relationship == .backedBy && $0.from.contains("pod-1") && $0.to.contains("pvc-1") })
        XCTAssertTrue(result.edges.contains { $0.relationship == .usesStorageClass && $0.from.contains("pv-1") && $0.to.contains("sc-1") })
        XCTAssertEqual(result.unresolvedReferences.filter { $0.relation == .references && $0.sourceNodeID?.contains("pod-1") == true }.count, 2)
        XCTAssertTrue(result.edges.contains { $0.relationship == .containedIn && $0.to.contains("ns-1") })
        XCTAssertTrue(result.nodes.contains { $0.isVirtual && $0.virtualKind == "control-plane-boundary" && $0.evidence.level == .unavailable })
    }

    func testNameOnlyStorageReferencesResolveAcrossNamespacedToClusterScope() {
        let claim = node(
            "PersistentVolumeClaim",
            "web-data",
            uid: "pvc-name-only",
            volumes: [
                TopologyObjectReference(kind: "PersistentVolume", name: "pv-name-only"),
                TopologyObjectReference(kind: "StorageClass", name: "fast-name-only"),
            ]
        )
        let volume = node("PersistentVolume", "pv-name-only", namespace: nil, uid: "pv-name-only")
        let storageClass = node("StorageClass", "fast-name-only", namespace: nil, uid: "sc-name-only")
        let result = graph([claim, volume, storageClass])

        XCTAssertTrue(result.edges.contains {
            $0.relationship == .backedBy
                && $0.from.contains("pvc-name-only")
                && $0.to.contains("pv-name-only")
        })
        XCTAssertTrue(result.edges.contains {
            $0.relationship == .usesStorageClass
                && $0.from.contains("pvc-name-only")
                && $0.to.contains("sc-name-only")
        })
        XCTAssertFalse(result.unresolvedReferences.contains {
            $0.target.name == "pv-name-only" || $0.target.name == "fast-name-only"
        })
    }

    func testNodeRoleLabelsBecomeSafeInspectorFacts() {
        let worker = TopologyResourceSnapshot(
            identity: identity("Node", "worker-a", namespace: nil, uid: "node-role"),
            roleLabels: ["node-role.kubernetes.io/worker": ""]
        )
        let result = graph([worker])
        let node = result.nodes.first { $0.uid == "node-role" }

        XCTAssertTrue(node?.facts.contains { $0.key == "roles" && $0.value == "worker" } == true)

        let custom = TopologyResourceSnapshot(
            identity: identity("Node", "custom", namespace: nil, uid: "node-custom"),
            roleLabels: ["kubernetes.io/role": "credential-looking-private-role"]
        )
        let customResult = graph([custom])
        let encoded = String(data: try! JSONEncoder().encode(customResult), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains("credential-looking-private-role"))
        XCTAssertTrue(customResult.nodes.first { $0.uid == "node-custom" }?.facts.contains {
            $0.key == "roles" && $0.value == "custom"
        } == true)
    }

    func testIngressBackendPortVariantsAndUnresolvedReferences() {
        let ingress = node("Ingress", "gateway", uid: "ing-1", ingress: [TopologyServiceReference(name: "api", port: 80), TopologyServiceReference(name: "api", portName: "https"), TopologyServiceReference(name: "api", port: nil), TopologyServiceReference(name: "missing", port: 8443)])
        let api = node("Service", "api", uid: "svc-1")
        let result = graph([ingress, api])
        XCTAssertEqual(result.edges.filter { $0.relationship == .routesTo }.count, 3)
        XCTAssertTrue(result.edges.contains { $0.attributes["port"] == "80" })
        XCTAssertTrue(result.edges.contains { $0.attributes["portName"] == "https" })
        XCTAssertTrue(result.edges.contains { $0.attributes.isEmpty })
        XCTAssertTrue(result.unresolvedReferences.contains { $0.relation == .routesTo && $0.target.name == "missing" })
    }

    func testSelectorAndExpressionOperatorsAndNetworkPolicyDefaultDenyMetadata() {
        let podA = node("Pod", "a", uid: "pod-a", labels: ["app": "web", "tier": "frontend"])
        let podB = node("Pod", "b", uid: "pod-b", labels: ["app": "web", "tier": "backend"])
        let policySelector = TopologyLabelSelector(matchLabels: ["app": "web"], matchExpressions: [TopologySelectorRequirement(key: "tier", op: .in, values: ["frontend"]), TopologySelectorRequirement(key: "zone", op: .doesNotExist)])
        let policy = node("NetworkPolicy", "default-deny", uid: "np-1", networkPolicy: TopologyNetworkPolicySnapshot(podSelector: policySelector, policyTypes: ["Ingress", "Egress"], ingressRuleCount: 0, egressRuleCount: 0))
        let result = graph([podA, podB, policy])
        let selected = result.edges.filter { $0.relationship == .selects && $0.from.contains("np-1") }
        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(selected[0].to.contains("pod-a"))
        XCTAssertEqual(selected[0].evidence.level, .inferred)
        XCTAssertEqual(policy.networkPolicy?.policyTypes, ["EGRESS", "INGRESS"])
        XCTAssertEqual(policy.networkPolicy?.ingressRuleCount, 0)
        XCTAssertEqual(policy.networkPolicy?.egressRuleCount, 0)
        XCTAssertTrue(TopologyLabelSelector(matchExpressions: [TopologySelectorRequirement(key: "app", op: .notIn, values: ["api"])]).matches(["app": "web"]))
        XCTAssertFalse(TopologyLabelSelector(matchExpressions: [TopologySelectorRequirement(key: "app", op: .exists)]).matches([:]))
        XCTAssertTrue(TopologyLabelSelector(matchExpressions: [TopologySelectorRequirement(key: "app", op: .doesNotExist)]).matches([:]))

        let expressionWorkload = node("Deployment", "expression-only", uid: "deploy-expression", selectorExpressions: [TopologySelectorRequirement(key: "tier", op: .in, values: ["frontend"])])
        let expressionResult = graph([podA, podB, expressionWorkload])
        XCTAssertTrue(expressionResult.edges.contains { $0.relationship == .selects && $0.from.contains("deploy-expression") && $0.to.contains("pod-a") })
    }

    func testPartialRBACInputAndFreshnessAreExplicit() {
        let input = TopologyInputStatus(resourceKind: "networkpolicies", availability: .forbidden, message: "forbidden: annotations=hidden", freshness: freshness)
        let result = graph([], inputs: [input])
        XCTAssertEqual(result.completeness, .unavailable)
        XCTAssertEqual(result.freshness, freshness)
        XCTAssertEqual(result.inputs.first?.freshness, freshness)
        XCTAssertTrue(result.unresolvedReferences.contains { $0.relation == .inputUnavailable && $0.evidence.level == .unavailable })
        XCTAssertFalse(result.unresolvedReferences.first?.reason.contains("annotations=hidden") ?? false)
    }

    func testAvailableSnapshotWithUnresolvedReferenceIsPartial() {
        let pod = node(
            "Pod",
            "consumer",
            uid: "consumer-pod",
            volumes: [TopologyObjectReference(kind: "PersistentVolumeClaim", name: "missing", namespace: "demo")]
        )
        let result = graph([pod], inputs: [TopologyInputStatus(resourceKind: "pods", availability: .available, observedCount: 1)])

        XCTAssertFalse(result.unresolvedReferences.isEmpty)
        XCTAssertEqual(result.completeness, .partial)
    }

    func testAvailableSnapshotWithIncompletePortPathIsPartialButExternalIsComplete() {
        let service = TopologyResourceSnapshot(
            identity: identity("Service", "empty", uid: "empty-service"),
            servicePorts: [TopologyServicePort(port: 80)]
        )
        let noEndpointIngress = TopologyResourceSnapshot(
            identity: identity("Ingress", "empty", uid: "empty-ingress"),
            ingressRoutes: [TopologyIngressRoute(backendName: "empty", backendPort: 80)]
        )
        let partialResult = graph([service, noEndpointIngress])
        XCTAssertTrue(partialResult.portPaths.contains { $0.status == .noEndpoint })
        XCTAssertEqual(partialResult.completeness, .partial)

        let externalIngress = TopologyResourceSnapshot(
            identity: identity("Ingress", "external", uid: "external-ingress"),
            ingressRoutes: [TopologyIngressRoute(backendKind: "ExternalName", backendName: "outside", backendPort: 443)]
        )
        let externalResult = graph([externalIngress])
        XCTAssertEqual(externalResult.portPaths.first?.status, .external)
        XCTAssertEqual(externalResult.completeness, .complete)
    }

    func testEveryNonExternalPortPathStatusMakesSnapshotPartial() {
        let readyService = TopologyResourceSnapshot(
            identity: identity("Service", "ready", uid: "ready-service"),
            servicePorts: [TopologyServicePort(port: 80)]
        )
        let noReadySlice = TopologyResourceSnapshot(
            identity: identity("EndpointSlice", "ready-1", uid: "ready-slice"),
            endpointSlice: TopologyEndpointSliceSnapshot(
                serviceName: "ready",
                ports: [TopologyEndpointPort(port: 8080)],
                endpoints: [TopologyEndpointTarget(ready: false)]
            )
        )
        let noReadyIngress = TopologyResourceSnapshot(
            identity: identity("Ingress", "ready", uid: "ready-ingress"),
            ingressRoutes: [TopologyIngressRoute(backendName: "ready", backendPort: 80)]
        )
        let unresolvedIngress = TopologyResourceSnapshot(
            identity: identity("Ingress", "unresolved", uid: "unresolved-ingress"),
            ingressRoutes: [TopologyIngressRoute(backendName: "missing", backendPort: 80)]
        )
        let partialRoute = TopologyResourceSnapshot(
            identity: identity("HTTPRoute", "partial", uid: "partial-route"),
            httpRoute: TopologyHTTPRouteSnapshot(
                parents: [TopologyGatewayParentReference(name: "unknown")],
                backends: [TopologyGatewayBackendReference(name: "ready", port: 80)]
            )
        )

        let result = graph([readyService, noReadySlice, noReadyIngress, unresolvedIngress, partialRoute])
        XCTAssertTrue(result.portPaths.contains { $0.status == .noReadyEndpoint })
        XCTAssertTrue(result.portPaths.contains { $0.status == .unresolved })
        XCTAssertTrue(result.portPaths.contains { $0.status == .partial })
        XCTAssertEqual(result.completeness, .partial)
    }

    func testAvailableEmptySnapshotIsComplete() {
        let result = graph([], inputs: [
            TopologyInputStatus(resourceKind: "services", availability: .available, observedCount: 0),
            TopologyInputStatus(resourceKind: "endpointslices", availability: .available, observedCount: 0),
        ])

        XCTAssertTrue(result.unresolvedReferences.isEmpty)
        XCTAssertTrue(result.portPaths.isEmpty)
        XCTAssertEqual(result.completeness, .complete)
    }

    func testStableDeterministicOutputAndSafeFactsNeverCarryValues() throws {
        let fact = TopologyFact(key: "kubelet", title: "Kubelet", value: "v1\u{0000}")
        let sensitive = TopologyFact(key: "token", title: "Token", value: "secret-value")
        let one = graph([node("Pod", "z", uid: "z", facts: [sensitive, fact]), node("Pod", "a", uid: "a")])
        let two = graph([node("Pod", "a", uid: "a"), node("Pod", "z", uid: "z", facts: [fact, sensitive])])
        XCTAssertEqual(one, two)
        XCTAssertTrue(one.nodes.contains { $0.id.contains("dev") && $0.id.contains("v1") && $0.id.contains("uid:a") })
        XCTAssertFalse(String(data: try JSONEncoder().encode(one), encoding: .utf8)?.contains("secret-value") ?? true)
        XCTAssertFalse(String(data: try JSONEncoder().encode(one), encoding: .utf8)?.contains("\u{0000}") ?? true)
    }

    func testLabelTokensHideOriginalKeysAndValuesWhileSelectorsStillMatch() throws {
        let secretKey = "team.example/secret-label"
        let secretValue = "innocuous-looking-secret-value"
        let pod = node("Pod", "secure", uid: "pod-secure", labels: [secretKey: secretValue])
        let service = node("Service", "secure", uid: "svc-secure", selector: [secretKey: secretValue])
        let result = graph([pod, service])
        let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains(secretKey))
        XCTAssertFalse(encoded.contains(secretValue))
        XCTAssertTrue(result.edges.contains { $0.relationship == .selects && $0.from.contains("svc-secure") && $0.to.contains("pod-secure") })
    }

    func testTenThousandNodeGraphBuildWithinDebugBudget() {
        let pods = (0..<10_000).map { index in
            node("Pod", "pod-\(index)", uid: "uid-\(index)", labels: ["app": index.isMultiple(of: 2) ? "even" : "odd"])
        }
        let resources = [node("Service", "all-even", uid: "svc-perf", selector: ["app": "even"])] + pods
        let start = DispatchTime.now().uptimeNanoseconds
        let result = graph(resources)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        XCTAssertEqual(result.nodes.count, 10_002) // includes Service and typed control-plane boundary
        XCTAssertEqual(result.edges.count, 5_000)
        XCTAssertLessThan(elapsed, 10.0, "10k topology build should remain usable in debug CI")
    }

    func testNotInMatchesMissingLabelKey() {
        let selector = TopologyLabelSelector(matchExpressions: [TopologySelectorRequirement(key: "zone", op: .notIn, values: ["blocked"])])
        XCTAssertTrue(selector.matches([:]))
        XCTAssertFalse(selector.matches(["zone": "blocked"]))
        XCTAssertTrue(selector.matches(["zone": "east"]))
    }

    func testTypedServicePortPathResolvesNamedTargetThroughEndpointSliceAndContainer() {
        let pod = TopologyResourceSnapshot(
            identity: identity("Pod", "api-0", uid: "pod-port"),
            containerPorts: [TopologyContainerPort(containerName: "api", name: "web", port: 8443, protocolName: "TCP")]
        )
        let service = TopologyResourceSnapshot(
            identity: identity("Service", "api", uid: "svc-port"),
            servicePorts: [TopologyServicePort(name: "https", port: 443, targetPort: TopologyPortTarget(name: "web"), protocolName: "TCP", appProtocol: "https", nodePort: 30443)]
        )
        let slice = TopologyResourceSnapshot(
            identity: identity("EndpointSlice", "api-1", uid: "slice-port"),
            endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "api", addressType: "IPv4", ports: [TopologyEndpointPort(name: "https", port: 8443, appProtocol: "https")], endpoints: [TopologyEndpointTarget(reference: TopologyObjectReference(kind: "Pod", name: "api-0", namespace: "demo", uid: "pod-port"), ready: true, serving: true, addresses: ["10.0.0.8"], nodeName: "worker-a", zone: "zone-a")])
        )
        let ingress = TopologyResourceSnapshot(
            identity: identity("Ingress", "api", uid: "ing-port"),
            ingressRoutes: [TopologyIngressRoute(host: "api.example.test", path: "/", pathType: "Prefix", backendName: "api", backendNamespace: "demo", backendPortName: "https")]
        )
        let result = graph([pod, service, slice, ingress])
        let path = try! XCTUnwrap(result.portPaths.first)
        XCTAssertEqual(path.status, .complete)
        XCTAssertTrue(path.hops.contains { $0.role == "service-port" && $0.portNumber == 443 && $0.portName == "https" && $0.targetPort?.name == "web" && $0.nodePort == 30443 && $0.appProtocol == "https" })
        XCTAssertTrue(path.hops.contains { $0.role == "endpoint-port" && $0.portNumber == 8443 && $0.portName == "https" && $0.appProtocol == "https" })
        XCTAssertTrue(path.hops.contains { $0.role == "endpoint" && $0.addresses == ["10.0.0.8"] })
        XCTAssertTrue(path.hops.contains { $0.role == "container-port" && $0.portNumber == 8443 })
        XCTAssertEqual(slice.endpointSlice?.addressType, "IPv4")
    }

    func testPortHopDecodesLegacyPayloadWithoutNewPortMetadata() throws {
        let evidence = TopologyEvidence(level: .observed, source: .api(kind: "Service"), freshness: freshness)
        let hop = TopologyPortHop(role: "service-port", portNumber: 80, evidence: evidence)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(hop)) as? [String: Any])
        legacyObject.removeValue(forKey: "targetPort")
        legacyObject.removeValue(forKey: "nodePort")
        legacyObject.removeValue(forKey: "appProtocol")

        let decoded = try JSONDecoder().decode(TopologyPortHop.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertNil(decoded.targetPort)
        XCTAssertNil(decoded.nodePort)
        XCTAssertNil(decoded.appProtocol)
    }

    func testPortPathStatusesCoverNoEndpointExternalAndAmbiguousTarget() {
        let noEndpointService = TopologyResourceSnapshot(identity: identity("Service", "empty", uid: "svc-empty"), servicePorts: [TopologyServicePort(port: 80)])
        let noEndpointIngress = TopologyResourceSnapshot(identity: identity("Ingress", "empty", uid: "ing-empty"), ingressRoutes: [TopologyIngressRoute(backendName: "empty", backendPort: 80)])
        let externalIngress = TopologyResourceSnapshot(identity: identity("Ingress", "external", uid: "ing-external"), ingressRoutes: [TopologyIngressRoute(backendKind: "ExternalName", backendName: "outside", backendPort: 443)])
        let ambiguousService = TopologyResourceSnapshot(identity: identity("Service", "ambiguous", uid: "svc-ambiguous"), servicePorts: [TopologyServicePort(name: "one", port: 80), TopologyServicePort(name: "two", port: 80)])
        let ambiguousIngress = TopologyResourceSnapshot(identity: identity("Ingress", "ambiguous", uid: "ing-ambiguous"), ingressRoutes: [TopologyIngressRoute(backendName: "ambiguous", backendPort: 80)])
        let result = graph([noEndpointService, noEndpointIngress, externalIngress, ambiguousService, ambiguousIngress])
        XCTAssertTrue(result.portPaths.contains { $0.status == .noEndpoint })
        XCTAssertTrue(result.portPaths.contains { $0.status == .external })
        XCTAssertTrue(result.portPaths.contains { $0.status == .unresolved && $0.note?.contains("ambiguous") == true })
    }

    func testGatewayRouteAndDuplicateIngressPathsRemainDistinct() throws {
        let gateway = TopologyResourceSnapshot(identity: identity("Gateway", "edge", uid: "gw-1"), gateway: TopologyGatewaySnapshot(gatewayClassName: "istio", listeners: [TopologyGatewayListener(name: "https", protocolName: "HTTPS", port: 443, hostname: "example.test")]))
        let service = TopologyResourceSnapshot(identity: identity("Service", "api", uid: "svc-gw"), servicePorts: [TopologyServicePort(port: 8080)])
        let route = TopologyResourceSnapshot(identity: identity("HTTPRoute", "api", uid: "route-1"), httpRoute: TopologyHTTPRouteSnapshot(hostnames: ["example.test"], parents: [TopologyGatewayParentReference(name: "edge", namespace: "demo", sectionName: "https", accepted: true, resolvedRefs: true)], backends: [TopologyGatewayBackendReference(name: "api", port: 8080, resolvedRefs: true)]))
        let ingress = TopologyResourceSnapshot(identity: identity("Ingress", "dup", uid: "ing-dup"), ingressRoutes: [TopologyIngressRoute(ruleIndex: 0, pathIndex: 0, host: "example.test", path: "/", pathType: "Prefix", backendName: "api", backendPort: 8080), TopologyIngressRoute(ruleIndex: 1, pathIndex: 0, host: "example.test", path: "/", pathType: "Prefix", backendName: "api", backendPort: 8080)])
        let result = graph([gateway, service, route, ingress])
        XCTAssertEqual(result.edges.filter { $0.relationship == .routesTo && $0.from.contains("ing-dup") }.count, 2)
        XCTAssertEqual(Set(result.edges.filter { $0.relationship == .routesTo && $0.from.contains("ing-dup") }.map(\.id)).count, 2)
        XCTAssertTrue(result.edges.contains { $0.relationship == .routesTo && $0.from.contains("route-1") && $0.to.contains("gw-1") })
        XCTAssertTrue(result.edges.contains { $0.relationship == .routesTo && $0.from.contains("route-1") && $0.to.contains("svc-gw") })
    }

    func testNetworkPolicyRetainsPeersPortsAndDerivedTypes() throws {
        let policy = TopologyNetworkPolicySnapshot(
            podSelector: TopologyLabelSelector(matchLabels: ["app": "api"]),
            ingressRuleCount: 1,
            rules: [TopologyNetworkPolicyRule(direction: .ingress, peers: [TopologyNetworkPolicyPeer(ipBlockCIDR: "10.0.0.0/8", exceptCIDRs: ["10.1.0.0/16"])], ports: [TopologyNetworkPolicyPort(number: 443, protocolName: "TCP", endPort: 445)])]
        )
        XCTAssertEqual(policy.policyTypes, ["INGRESS"])
        XCTAssertEqual(policy.rules.first?.peers.first?.ipBlockCIDR, "10.0.0.0/8")
        XCTAssertEqual(policy.rules.first?.ports.first?.endPort, 445)
        let resource = TopologyResourceSnapshot(identity: identity("NetworkPolicy", "api", uid: "np-rich"), networkPolicy: policy)
        let encoded = String(data: try JSONEncoder().encode(resource), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains("raw"))
        let omitted = TopologyNetworkPolicySnapshot(egressRuleCount: 1)
        XCTAssertEqual(omitted.policyTypes, ["EGRESS", "INGRESS"])
    }

    func testTypedTopologyEncodingIsDeterministic() throws {
        let resource = TopologyResourceSnapshot(identity: identity("Service", "stable", uid: "svc-stable"), ingressRoutes: [TopologyIngressRoute(ruleIndex: 0, pathIndex: 0, host: "stable.test", path: "/", backendName: "stable", backendPortName: "https")], servicePorts: [TopologyServicePort(name: "https", port: 443, targetPort: TopologyPortTarget(name: "web"))])
        let first = graph([resource])
        let second = graph([resource])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(first), try encoder.encode(second))
    }

    func testExplorerQueryProvidesSharedLevelsFiltersAndOneHopFocus() throws {
        let pod = node("Pod", "api-0", uid: "query-pod")
        let service = TopologyResourceSnapshot(identity: identity("Service", "api", uid: "query-service"), servicePorts: [TopologyServicePort(name: "https", port: 443, protocolName: "TCP")])
        let ingress = TopologyResourceSnapshot(identity: identity("Ingress", "api", uid: "query-ingress"), ingressRoutes: [TopologyIngressRoute(host: "api.test", path: "/", backendName: "api", backendPort: 443)])
        let result = graph([pod, service, ingress])
        let query = TopologyGraphQuery(graph: result)
        XCTAssertEqual(TopologyGraphQuery.level(for: "Pod"), .workloads)
        XCTAssertEqual(query.nodes(level: .network).filter { $0.kind == "Service" || $0.kind == "Ingress" }.count, 2)
        XCTAssertGreaterThanOrEqual(query.nodes(search: "api").count, 3)
        XCTAssertFalse(query.edges(level: .network).isEmpty)
        let serviceNodeID = try XCTUnwrap(result.nodes.first { $0.uid == "query-service" }?.id)
        let ingressNodeID = try XCTUnwrap(result.nodes.first { $0.uid == "query-ingress" }?.id)
        let focused = query.oneHopFocus(nodeIDs: [serviceNodeID])
        XCTAssertTrue(focused.contains(serviceNodeID))
        XCTAssertTrue(focused.contains(ingressNodeID))
        XCTAssertEqual(query.portPaths(level: .network, port: 443).count, 1)
        XCTAssertTrue(query.portPaths(level: .policyDependencies).isEmpty)
    }

    func testGraphRetainsSanitizedTypedDetailsAndOldGraphDecodeDefaults() throws {
        let service = TopologyResourceSnapshot(identity: identity("Service", "details", uid: "details-service"), servicePorts: [TopologyServicePort(name: "web", port: 80)], serviceMode: .headless, facts: [TopologyFact(key: "type", title: "Type", value: "ClusterIP")])
        let result = graph([service])
        let nodeID = try XCTUnwrap(result.nodes.first { $0.uid == "details-service" }?.id)
        XCTAssertEqual(result.details[nodeID]?.serviceMode, .headless)
        XCTAssertEqual(result.details[nodeID]?.servicePorts.first?.name, "web")

        let oldJSON = #"{"contextID":"dev","freshness":{"capturedAt":0,"generation":1},"completeness":"complete","nodes":[],"edges":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TopologyGraph.self, from: oldJSON)
        XCTAssertTrue(decoded.portPaths.isEmpty)
        XCTAssertTrue(decoded.details.isEmpty)
        XCTAssertTrue(decoded.inputs.isEmpty)
    }

    func testNotReadyEndpointIsRetainedAndReadinessQueryUsesConditions() {
        let service = TopologyResourceSnapshot(identity: identity("Service", "ready", uid: "ready-service"), servicePorts: [TopologyServicePort(name: "web", port: 80, targetPort: TopologyPortTarget(name: "web"))])
        let slice = TopologyResourceSnapshot(identity: identity("EndpointSlice", "ready-1", uid: "ready-slice"), endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "ready", ports: [TopologyEndpointPort(name: "web", port: 8080)], endpoints: [TopologyEndpointTarget(ready: false, serving: false, terminating: true, addresses: ["10.0.0.9"], nodeName: "worker", zone: "zone-a")]))
        let ingress = TopologyResourceSnapshot(identity: identity("Ingress", "ready", uid: "ready-ingress"), ingressRoutes: [TopologyIngressRoute(backendName: "ready", backendPort: 80)])
        let result = graph([service, slice, ingress])
        let path = result.portPaths[0]
        XCTAssertEqual(path.status, .noReadyEndpoint)
        XCTAssertEqual(path.totalEndpointCount, 1)
        XCTAssertEqual(path.readyEndpointCount, 0)
        XCTAssertEqual(path.hops.first(where: { $0.role == "endpoint" })?.terminating, true)
        XCTAssertEqual(TopologyGraphQuery(graph: result).portPaths(readiness: false).count, 1)
        XCTAssertTrue(TopologyGraphQuery(graph: result).portPaths(readiness: true).isEmpty)
    }

    func testWrongEndpointSlicePortDoesNotPoisonValidSlice() {
        let service = TopologyResourceSnapshot(identity: identity("Service", "partitioned", uid: "partitioned-service"), servicePorts: [TopologyServicePort(name: "web", port: 80)])
        let wrong = TopologyResourceSnapshot(identity: identity("EndpointSlice", "wrong", uid: "wrong-slice"), endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "partitioned", ports: [TopologyEndpointPort(name: "other", port: 9000)], endpoints: [TopologyEndpointTarget(ready: true, addresses: ["10.0.0.1"])]))
        let right = TopologyResourceSnapshot(identity: identity("EndpointSlice", "right", uid: "right-slice"), endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "partitioned", ports: [TopologyEndpointPort(name: "web", port: 8080)], endpoints: [TopologyEndpointTarget(ready: true, addresses: ["10.0.0.2"])]))
        let ingress = TopologyResourceSnapshot(identity: identity("Ingress", "partitioned", uid: "partitioned-ingress"), ingressRoutes: [TopologyIngressRoute(backendName: "partitioned", backendPort: 80)])
        let result = graph([service, wrong, right, ingress])
        XCTAssertEqual(result.portPaths.first?.status, .complete)
        XCTAssertEqual(result.portPaths.first?.totalEndpointCount, 1)
        XCTAssertEqual(result.portPaths.first?.note, "Pod container port declaration unavailable")
    }

    func testGatewayRejectedReferenceProducesBlockedUnresolvedPath() {
        let service = TopologyResourceSnapshot(identity: identity("Service", "blocked", uid: "blocked-service"), servicePorts: [TopologyServicePort(port: 80)])
        let route = TopologyResourceSnapshot(identity: identity("HTTPRoute", "blocked", uid: "blocked-route"), httpRoute: TopologyHTTPRouteSnapshot(parents: [TopologyGatewayParentReference(name: "edge", accepted: false, resolvedRefs: false)], backends: [TopologyGatewayBackendReference(name: "blocked", port: 80)]))
        let path = graph([service, route]).portPaths.first
        XCTAssertEqual(path?.status, .unresolved)
        XCTAssertTrue(path?.note?.contains("rejected") == true)
    }

    func testSelectorSummaryAllowlistsNamesAndNeverLeaksArbitraryValues() {
        let selector = TopologyLabelSelector(matchLabels: ["app": "payments", "credential.example/token": "secret-value"])
        XCTAssertTrue(selector.summary.contains("app=value"))
        XCTAssertFalse(selector.summary.contains("secret-value"))
        XCTAssertFalse(selector.summary.contains("credential.example/token"))
    }

    func testExplorerRawValuesAreStableSnakeCase() {
        XCTAssertEqual(ExplorerLevel.policyDependencies.rawValue, "policy_dependencies")
        XCTAssertEqual(ExplorerPresentation.portTable.rawValue, "port_table")
    }

    func testOmittedEndpointReadyIsEffectiveReadyButRawNilIsPreserved() {
        let service = TopologyResourceSnapshot(identity: identity("Service", "implicit", uid: "implicit-service"), servicePorts: [TopologyServicePort(name: "web", port: 80)])
        let slice = TopologyResourceSnapshot(identity: identity("EndpointSlice", "implicit", uid: "implicit-slice"), endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "implicit", ports: [TopologyEndpointPort(name: "web", port: 8080)], endpoints: [TopologyEndpointTarget(addresses: ["10.0.0.1"]) ]))
        let ingress = TopologyResourceSnapshot(identity: identity("Ingress", "implicit", uid: "implicit-ingress"), ingressRoutes: [TopologyIngressRoute(backendName: "implicit", backendPort: 80)])
        let path = graph([service, slice, ingress]).portPaths[0]
        XCTAssertEqual(path.readyEndpointCount, 1)
        XCTAssertEqual(path.status, .complete)
        XCTAssertNil(path.hops.first(where: { $0.role == "endpoint" })?.ready)
        XCTAssertTrue(TopologyGraphQuery(graph: graph([service, slice, ingress])).portPaths(readiness: true).count == 1)
    }

    func testContainerResolutionRequiresProtocolMatch() {
        let pod = TopologyResourceSnapshot(identity: identity("Pod", "protocol", uid: "protocol-pod"), containerPorts: [TopologyContainerPort(containerName: "api", name: "web", port: 8080, protocolName: "UDP"), TopologyContainerPort(containerName: "api", name: "web", port: 8080, protocolName: "TCP")])
        let service = TopologyResourceSnapshot(identity: identity("Service", "protocol", uid: "protocol-service"), servicePorts: [TopologyServicePort(name: "web", port: 80, targetPort: TopologyPortTarget(name: "web"), protocolName: "TCP")])
        let slice = TopologyResourceSnapshot(identity: identity("EndpointSlice", "protocol", uid: "protocol-slice"), endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "protocol", ports: [TopologyEndpointPort(name: "web", port: 8080, protocolName: "TCP")], endpoints: [TopologyEndpointTarget(reference: TopologyObjectReference(kind: "Pod", name: "protocol", namespace: "demo", uid: "protocol-pod"), ready: true)]))
        let ingress = TopologyResourceSnapshot(identity: identity("Ingress", "protocol", uid: "protocol-ingress"), ingressRoutes: [TopologyIngressRoute(backendName: "protocol", backendPort: 80)])
        let path = graph([pod, service, slice, ingress]).portPaths[0]
        XCTAssertEqual(path.hops.filter { $0.role == "container-port" }.count, 1)
        XCTAssertEqual(path.hops.first(where: { $0.role == "container-port" })?.protocolName, "TCP")
    }

    func testHTTPRouteAcceptedParentAllowsPathWhenAnotherParentRejected() {
        let service = TopologyResourceSnapshot(identity: identity("Service", "multi-parent", uid: "multi-service"), servicePorts: [TopologyServicePort(port: 80)])
        let route = TopologyResourceSnapshot(identity: identity("HTTPRoute", "multi-parent", uid: "multi-route"), httpRoute: TopologyHTTPRouteSnapshot(parents: [TopologyGatewayParentReference(name: "bad", accepted: false, resolvedRefs: false), TopologyGatewayParentReference(name: "good", accepted: true, resolvedRefs: true)], backends: [TopologyGatewayBackendReference(name: "multi-parent", port: 80)]))
        XCTAssertNotEqual(graph([service, route]).portPaths.first?.status, .unresolved)
    }

    func testHTTPRouteParentWrappingRetainsTruncationMetadataAndNotes() {
        let endpoints = (0..<900).map { index in
            TopologyEndpointTarget(
                reference: TopologyObjectReference(kind: "Pod", name: "route-fanout-\(index)", namespace: "demo", uid: "route-fanout-pod-\(index)"),
                ready: true,
                addresses: ["10.43.\(index / 255).\(index % 255)"]
            )
        }
        let service = TopologyResourceSnapshot(
            identity: identity("Service", "route-fanout", uid: "route-fanout-service"),
            servicePorts: [TopologyServicePort(name: "web", port: 80)]
        )
        let slice = TopologyResourceSnapshot(
            identity: identity("EndpointSlice", "route-fanout", uid: "route-fanout-slice"),
            endpointSlice: TopologyEndpointSliceSnapshot(
                serviceName: "route-fanout",
                ports: [TopologyEndpointPort(name: "web", port: 8080)],
                endpoints: endpoints
            )
        )
        let route = TopologyResourceSnapshot(
            identity: identity("HTTPRoute", "route-fanout", uid: "route-fanout-http"),
            httpRoute: TopologyHTTPRouteSnapshot(
                // Unknown parent state wraps the resolved path as partial.
                parents: [TopologyGatewayParentReference(name: "edge")],
                backends: [TopologyGatewayBackendReference(name: "route-fanout", port: 80, resolvedRefs: true)]
            )
        )

        let path = try! XCTUnwrap(graph([service, slice, route]).portPaths.first)

        XCTAssertEqual(path.status, .partial)
        XCTAssertTrue(path.isTruncated)
        XCTAssertEqual(path.totalEndpointCount, 900)
        XCTAssertEqual(path.readyEndpointCount, 900)
        XCTAssertEqual(path.omittedEndpointPortCount, 0)
        XCTAssertGreaterThan(path.omittedEndpointCount, 0)
        XCTAssertGreaterThan(path.omittedHopCount, 0)
        XCTAssertTrue(path.note?.contains("HTTPRoute parent acceptance or reference resolution is not yet observed") == true)
        XCTAssertTrue(path.note?.contains("Endpoint fanout truncated") == true)
        XCTAssertTrue(path.provenance.contains { $0.source.sourceField == "EndpointSlice.endpoints[]" && $0.source.assumption?.contains("bounded") == true })
    }

    func testQuerySearchIncludesTypedPortAndEvidenceFields() {
        let service = TopologyResourceSnapshot(identity: identity("Service", "searchable", uid: "search-service"), servicePorts: [TopologyServicePort(name: "metrics", port: 9100, protocolName: "TCP", appProtocol: "http")])
        let ingress = TopologyResourceSnapshot(identity: identity("Ingress", "searchable", uid: "search-ingress"), ingressRoutes: [TopologyIngressRoute(backendName: "searchable", backendPort: 9100)])
        let result = graph([service, ingress])
        XCTAssertEqual(TopologyGraphQuery(graph: result).nodes(search: "metrics").count, 1)
        XCTAssertEqual(TopologyGraphQuery(graph: result).portPaths(search: "spec.route.backend").count, 1)
        XCTAssertEqual(TopologyGraphQuery(graph: result).portPaths(search: "9100").count, 1)
    }

    func testIndexedNamespaceSelectorExpansionHandlesManySelectors() {
        let pods = (0..<2_000).map { index in node("Pod", "indexed-" + String(index), uid: "indexed-" + String(index), labels: ["app": "app-" + String(index % 20)]) }
        let services = (0..<40).map { index in node("Service", "selector-" + String(index), uid: "selector-" + String(index), selector: ["app": "app-" + String(index % 20)]) }
        let start = DispatchTime.now().uptimeNanoseconds
        let result = graph(pods + services)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        XCTAssertEqual(result.edges.filter { $0.relationship == .selects }.count, 4_000)
        XCTAssertLessThan(elapsed, 5.0)
    }

    func testEndpointFanoutIsBoundedAndExplicitlyMarkedTruncated() {
        let endpoints = (0..<900).map { index in
            TopologyEndpointTarget(
                reference: TopologyObjectReference(kind: "Pod", name: "fanout-\(index)", namespace: "demo", uid: "fanout-pod-\(index)"),
                ready: true,
                addresses: ["10.42.\(index / 255).\(index % 255)"]
            )
        }
        let pods = (0..<900).map { index in
            node("Pod", "fanout-\(index)", uid: "fanout-pod-\(index)")
        }
        let service = TopologyResourceSnapshot(
            identity: identity("Service", "fanout", uid: "fanout-service"),
            servicePorts: [TopologyServicePort(name: "web", port: 80)]
        )
        let slice = TopologyResourceSnapshot(
            identity: identity("EndpointSlice", "fanout", uid: "fanout-slice"),
            endpointSlice: TopologyEndpointSliceSnapshot(
                serviceName: "fanout",
                ports: [TopologyEndpointPort(name: "web", port: 8080)],
                endpoints: endpoints
            )
        )
        let ingress = TopologyResourceSnapshot(
            identity: identity("Ingress", "fanout", uid: "fanout-ingress"),
            ingressRoutes: [TopologyIngressRoute(backendName: "fanout", backendPort: 80)]
        )

        let first = graph(pods + [service, slice, ingress])
        let second = graph(pods.reversed() + [service, TopologyResourceSnapshot(
            identity: identity("EndpointSlice", "fanout", uid: "fanout-slice"),
            endpointSlice: TopologyEndpointSliceSnapshot(
                serviceName: "fanout",
                ports: [TopologyEndpointPort(name: "web", port: 8080)],
                endpoints: endpoints.reversed()
            )
        ), ingress])
        let path = try! XCTUnwrap(first.portPaths.first)

        XCTAssertEqual(first, second)
        XCTAssertEqual(path.status, .partial)
        XCTAssertTrue(path.isTruncated)
        XCTAssertEqual(path.totalEndpointCount, 900)
        XCTAssertEqual(path.readyEndpointCount, 900)
        XCTAssertEqual(path.omittedEndpointPortCount, 0)
        XCTAssertGreaterThan(path.omittedEndpointCount, 0)
        XCTAssertGreaterThan(path.omittedHopCount, 0)
        XCTAssertLessThanOrEqual(path.hops.count, 512)
        XCTAssertTrue(path.note?.contains("Endpoint fanout truncated") == true)
        XCTAssertTrue(path.provenance.contains { $0.source.sourceField == "EndpointSlice.endpoints[]" && $0.source.assumption?.contains("bounded") == true })
        XCTAssertEqual(TopologyGraphQuery(graph: first).portPaths(search: "truncated").count, 1)
    }
}
