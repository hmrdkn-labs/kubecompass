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
}
