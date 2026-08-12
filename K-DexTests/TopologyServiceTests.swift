import Foundation
import Testing
import KubeCompassCore
@testable import K_Dex

private final class TopologyFixtureRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let responder: @Sendable ([String]) -> ProcessResult

    init(_ responder: @escaping @Sendable ([String]) -> ProcessResult) { self.responder = responder }
    func run(_ executable: String, _ arguments: [String], stdin: Data?) async throws -> ProcessResult {
        record([executable] + arguments)
        return responder(arguments)
    }
    private func record(_ call: [String]) { lock.lock(); recorded.append(call); lock.unlock() }
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
}

private func fixtureJSON(_ items: String) -> ProcessResult {
    let normalizedItems = items.replacingOccurrences(of: "}{", with: "},{")
    return ProcessResult(stdout: Data("{\"apiVersion\":\"v1\",\"items\":[\(normalizedItems)]}".utf8), stderr: Data(), exitCode: 0)
}

@Suite(.serialized)
struct TopologyServiceTests {
    @Test func buildsReadOnlyServiceSelectorGraphAndSkipsPayloadKinds() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : ""
            switch kind {
            case "pods":
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"metadata\":{\"name\":\"web-1\",\"namespace\":\"demo\",\"uid\":\"pod-1\",\"labels\":{\"app\":\"web\"},\"annotations\":{\"note\":\"secret-literal-should-not-escape\"}},\"spec\":{\"nodeName\":\"node-a\",\"containers\":[{\"name\":\"web\",\"env\":[{\"name\":\"TOKEN\",\"value\":\"secret-literal-should-not-escape\"}]}]},\"status\":{\"phase\":\"Running\"}}")
            case "services":
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"name\":\"web\",\"namespace\":\"demo\",\"uid\":\"svc-1\"},\"spec\":{\"selector\":{\"app\":\"web\"},\"type\":\"ClusterIP\",\"clusterIP\":\"10.0.0.5\"}}")
            case "nodes":
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Node\",\"metadata\":{\"name\":\"node-a\",\"uid\":\"node-1\"},\"spec\":{},\"status\":{\"nodeInfo\":{\"kubeletVersion\":\"v1.30\"}}}")
            case let value where value.contains("networkpolicies"):
                return ProcessResult(stdout: Data(), stderr: Data("forbidden".utf8), exitCode: 1)
            default:
                if kind.contains("jobs") { return ProcessResult(stdout: Data(), stderr: Data("forbidden".utf8), exitCode: 1) }
                return fixtureJSON("")
            }
        }
        let result = try await TopologyService.load(
            context: "dev",
            namespace: "demo",
            generation: 4,
            runner: runner
        )
        #expect(result.graph.completeness == .partial)
        #expect(result.graph.nodes.contains { $0.kind == "Service" && $0.name == "web" })
        #expect(result.graph.edges.contains { $0.relationship == .selects && $0.evidence.level == .inferred })
        #expect(result.graph.inputs.contains { $0.resourceKind == "networkpolicies" && $0.availability == .forbidden })
        #expect(!runner.calls.contains { $0.contains("secrets") || $0.contains("configmaps") })
        let encoded = String(data: try JSONEncoder().encode(result.graph), encoding: .utf8) ?? ""
        #expect(!encoded.contains("secret-literal-should-not-escape"))
        #expect(runner.calls.contains { $0 == ["kubectl", "get", "pods", "-o", "json", "--context", "dev", "-n", "demo"] })
        #expect(runner.calls.contains { $0 == ["kubectl", "get", "nodes", "-o", "json", "--context", "dev"] })
    }

    @Test func allForbiddenInputsRemainExplicitAndDoNotClaimComplete() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : "kind"
            return ProcessResult(stdout: Data(), stderr: Data("forbidden: \(kind)".utf8), exitCode: 1)
        }
        let result = try await TopologyService.load(
            context: "locked",
            namespace: nil,
            runner: runner
        )
        #expect(result.graph.completeness == .unavailable)
        #expect(result.fatalMessage?.contains("cannot read topology") == true)
        #expect(result.fatalMessage?.contains("pods") == true)
        #expect(result.graph.inputs.contains { $0.resourceKind == "pods" && $0.availability == .forbidden })
        #expect(result.graph.nodes.count == 1) // virtual control-plane boundary only
    }

    @Test func emptyScopeIsDistinctFromDeniedScope() async throws {
        let runner = TopologyFixtureRunner { _ in fixtureJSON("") }
        let result = try await TopologyService.load(
            context: "empty",
            namespace: "nothing-here",
            runner: runner
        )

        #expect(result.graph.completeness == .complete)
        #expect(result.graph.inputs.allSatisfy { $0.availability == .available })
        #expect(result.fatalMessage?.contains("No topology resources exist") == true)
        #expect(result.fatalMessage?.contains("denied") == false)
    }

    @Test func allUnsupportedInputsNameKindsAndReasons() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : "kind"
            return ProcessResult(
                stdout: Data(),
                stderr: Data("the server could not find the requested resource: \(kind)".utf8),
                exitCode: 1
            )
        }
        let result = try await TopologyService.load(context: "old-api", namespace: nil, runner: runner)

        #expect(result.graph.completeness == .unavailable)
        #expect(result.fatalMessage?.contains("Affected inputs:") == true)
        #expect(result.fatalMessage?.contains("pods:") == true)
        #expect(result.fatalMessage?.contains("The cluster does not expose pods.") == true)
        #expect(result.fatalMessage?.contains("endpointslices:") == true)
        #expect(result.fatalMessage?.contains("Topology inputs are unavailable") == true)
    }

    @Test func networkPolicyEmptySelectorAndDefaultPolicyTypesFollowKubernetesSemantics() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : ""
            switch kind {
            case "pods":
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"metadata\":{\"name\":\"web-1\",\"namespace\":\"demo\",\"uid\":\"pod-1\",\"labels\":{\"app\":\"web\"}}}")
            case let value where value.contains("networkpolicies"):
                return fixtureJSON("{\"apiVersion\":\"networking.k8s.io/v1\",\"kind\":\"NetworkPolicy\",\"metadata\":{\"name\":\"deny-ingress\",\"namespace\":\"demo\",\"uid\":\"policy-1\"},\"spec\":{\"podSelector\":{\"matchLabels\":{},\"matchExpressions\":[]},\"ingress\":[]}}")
            default:
                return fixtureJSON("")
            }
        }
        let result = try await TopologyService.load(
            context: "dev",
            namespace: "demo",
            runner: runner
        )

        #expect(result.graph.edges.contains {
            $0.relationship == .selects
                && $0.from.contains("policy-1")
                && $0.to.contains("pod-1")
        })
        let policy = result.graph.nodes.first { $0.uid == "policy-1" }
        #expect(policy?.facts.contains { $0.key == "policy-types" && $0.value == "INGRESS" } == true)
        #expect(policy?.facts.contains { $0.key == "default-deny" && $0.value == "ingress" } == true)
    }

    @Test func typedNamedPortPathPreservesServiceEndpointAndContainerPorts() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : ""
            if kind.contains("ingresses") {
                return fixtureJSON("{\"apiVersion\":\"networking.k8s.io/v1\",\"kind\":\"Ingress\",\"metadata\":{\"name\":\"web-route\",\"namespace\":\"demo\",\"uid\":\"ing-1\"},\"spec\":{\"ingressClassName\":\"nginx\",\"rules\":[{\"host\":\"demo.example\",\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"web\",\"port\":{\"name\":\"http\"}}}}]}}]}}")
            }
            if kind == "services" {
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"name\":\"web\",\"namespace\":\"demo\",\"uid\":\"svc-1\"},\"spec\":{\"selector\":{\"app\":\"web\"},\"type\":\"ClusterIP\",\"clusterIP\":\"10.0.0.5\",\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":\"http\",\"protocol\":\"TCP\",\"appProtocol\":\"http\"}]}}")
            }
            if kind.contains("endpointslices") {
                return fixtureJSON("{\"apiVersion\":\"discovery.k8s.io/v1\",\"kind\":\"EndpointSlice\",\"metadata\":{\"name\":\"web-1\",\"namespace\":\"demo\",\"uid\":\"slice-1\",\"labels\":{\"kubernetes.io/service-name\":\"web\"}},\"addressType\":\"IPv4\",\"ports\":[{\"name\":\"http\",\"port\":8080,\"protocol\":\"TCP\"}],\"endpoints\":[{\"addresses\":[\"10.42.0.7\"],\"conditions\":{\"ready\":true,\"serving\":true,\"terminating\":false},\"nodeName\":\"node-a\",\"zone\":\"zone-a\",\"targetRef\":{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"name\":\"web-1\",\"namespace\":\"demo\",\"uid\":\"pod-1\"}}]}")
            }
            if kind == "pods" {
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"metadata\":{\"name\":\"web-1\",\"namespace\":\"demo\",\"uid\":\"pod-1\",\"labels\":{\"app\":\"web\"}},\"spec\":{\"nodeName\":\"node-a\",\"containers\":[{\"name\":\"api\",\"ports\":[{\"name\":\"http\",\"containerPort\":8080,\"protocol\":\"TCP\"}]}]},\"status\":{\"phase\":\"Running\",\"conditions\":[{\"type\":\"Ready\",\"status\":\"True\"}]}}")
            }
            if kind == "nodes" {
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Node\",\"metadata\":{\"name\":\"node-a\",\"uid\":\"node-1\"}}")
            }
            return fixtureJSON("")
        }
        let result = try await TopologyService.load(context: "dev", namespace: "demo", runner: runner)
        #expect(result.graph.portPaths.count == 1)
        let path = try #require(result.graph.portPaths.first)
        #expect(path.status == .complete)
        #expect(path.hops.contains { $0.role == "service-port" && $0.portName == "http" && $0.portNumber == 80 })
        #expect(path.hops.contains { $0.role == "endpoint-port" && $0.portNumber == 8080 && $0.protocolName == "TCP" })
        #expect(path.hops.contains { $0.role == "container-port" && $0.containerName == "api" && $0.portNumber == 8080 })
        #expect(path.hops.contains { $0.role == "endpoint" && $0.addresses == ["10.42.0.7"] })
        let serviceID = try #require(result.graph.nodes.first { $0.uid == "svc-1" }?.id)
        let podID = try #require(result.graph.nodes.first { $0.uid == "pod-1" }?.id)
        #expect(result.graph.details[serviceID]?.serviceMode == .standard)
        #expect(result.graph.details[serviceID]?.servicePorts.first?.targetPort.name == "http")
        #expect(result.graph.details[podID]?.containerPorts.first?.port == 8080)
    }

    @Test func serviceModesAndNumericDefaultTargetPortAreTyped() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : ""
            guard kind == "services" else { return fixtureJSON("") }
            return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"name\":\"nodeport\",\"namespace\":\"demo\",\"uid\":\"svc-2\"},\"spec\":{\"type\":\"NodePort\",\"selector\":{},\"ports\":[{\"port\":80,\"nodePort\":30080,\"protocol\":\"TCP\"}]}}")
        }
        let result = try await TopologyService.load(context: "dev", namespace: "demo", runner: runner)
        let nodePort = try #require(result.graph.nodes.first { $0.uid == "svc-2" })
        #expect(nodePort.facts.contains { $0.key.hasPrefix("service-port-") && $0.value.contains("80/TCP") && $0.value.contains("port") })
    }

    @Test func networkPolicyPeersPortsAndGatewayUnsupportedRemainExplicit() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : ""
            if kind.contains("networkpolicies") {
                return fixtureJSON("{\"apiVersion\":\"networking.k8s.io/v1\",\"kind\":\"NetworkPolicy\",\"metadata\":{\"name\":\"allow\",\"namespace\":\"demo\",\"uid\":\"np-1\"},\"spec\":{\"podSelector\":{\"matchLabels\":{\"app\":\"web\"}},\"policyTypes\":[\"Ingress\"],\"ingress\":[{\"from\":[{\"ipBlock\":{\"cidr\":\"10.0.0.0/8\",\"except\":[\"10.1.0.0/16\"]}}],\"ports\":[{\"protocol\":\"TCP\",\"port\":80,\"endPort\":90}]}]}}")
            }
            if kind.contains("gateway") || kind.contains("httproute") { return ProcessResult(stdout: Data(), stderr: Data("the server could not find the requested resource".utf8), exitCode: 1) }
            return fixtureJSON("")
        }
        let result = try await TopologyService.load(context: "old", namespace: "demo", runner: runner)
        let policy = try #require(result.graph.nodes.first { $0.uid == "np-1" })
        #expect(result.graph.inputs.contains { $0.resourceKind.contains("gateway") && $0.availability == .unsupported })
        #expect(policy.facts.contains { $0.key == "policy-types" })
        let policyDetails = try #require(result.graph.details[policy.id]?.networkPolicy)
        #expect(policyDetails.rules.first?.peers.first?.ipBlockCIDR == "10.0.0.0/8")
        #expect(policyDetails.rules.first?.ports.first?.number == 80)
        #expect(policyDetails.rules.first?.ports.first?.endPort == 90)
    }

    @Test func gatewayApiObjectsAreTypedWhenTheClusterServesThem() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : ""
            if kind.contains("gatewayclasses") {
                return fixtureJSON("{\"apiVersion\":\"gateway.networking.k8s.io/v1\",\"kind\":\"GatewayClass\",\"metadata\":{\"name\":\"istio\",\"uid\":\"gc-1\"},\"spec\":{\"controllerName\":\"istio.io/gateway-controller\"},\"status\":{\"conditions\":[{\"type\":\"Accepted\",\"status\":\"True\"}]}}")
            }
            if kind.contains("gateways") {
                return fixtureJSON("{\"apiVersion\":\"gateway.networking.k8s.io/v1\",\"kind\":\"Gateway\",\"metadata\":{\"name\":\"edge\",\"namespace\":\"demo\",\"uid\":\"gw-1\"},\"spec\":{\"gatewayClassName\":\"istio\",\"listeners\":[{\"name\":\"https\",\"protocol\":\"HTTPS\",\"port\":443,\"hostname\":\"demo.example\"}]},\"status\":{\"conditions\":[{\"type\":\"Programmed\",\"status\":\"True\"}]}}")
            }
            if kind.contains("httproutes") {
                return fixtureJSON("{\"apiVersion\":\"gateway.networking.k8s.io/v1\",\"kind\":\"HTTPRoute\",\"metadata\":{\"name\":\"web\",\"namespace\":\"demo\",\"uid\":\"hr-1\"},\"spec\":{\"parentRefs\":[{\"name\":\"edge\",\"sectionName\":\"https\"},{\"name\":\"edge\",\"sectionName\":\"http\"}],\"rules\":[{\"backendRefs\":[{\"name\":\"web\",\"port\":80}]}]},\"status\":{\"parents\":[{\"parentRef\":{\"name\":\"edge\",\"sectionName\":\"https\",\"group\":\"other.example\",\"kind\":\"Other\",\"namespace\":\"demo\"},\"conditions\":[{\"type\":\"Accepted\",\"status\":\"False\"},{\"type\":\"ResolvedRefs\",\"status\":\"False\"}]},{\"parentRef\":{\"name\":\"edge\",\"sectionName\":\"http\",\"group\":\"gateway.networking.k8s.io\",\"kind\":\"Gateway\",\"namespace\":\"other\"},\"conditions\":[{\"type\":\"Accepted\",\"status\":\"True\"},{\"type\":\"ResolvedRefs\",\"status\":\"True\"}]},{\"parentRef\":{\"name\":\"edge\",\"sectionName\":\"http\",\"group\":\"gateway.networking.k8s.io\",\"kind\":\"Gateway\"},\"conditions\":[{\"type\":\"Accepted\",\"status\":\"False\"},{\"type\":\"ResolvedRefs\",\"status\":\"False\"}]},{\"parentRef\":{\"name\":\"edge\",\"sectionName\":\"https\",\"group\":\"gateway.networking.k8s.io\",\"kind\":\"Gateway\"},\"conditions\":[{\"type\":\"Accepted\",\"status\":\"True\"},{\"type\":\"ResolvedRefs\",\"status\":\"True\"}]}]}}")
            }
            return fixtureJSON("")
        }
        let result = try await TopologyService.load(context: "gateway", namespace: "demo", runner: runner)
        #expect(result.graph.nodes.contains { $0.kind == "GatewayClass" && $0.name == "istio" })
        #expect(result.graph.nodes.contains { $0.kind == "Gateway" && $0.name == "edge" })
        #expect(result.graph.nodes.contains { $0.kind == "HTTPRoute" && $0.name == "web" })
        let routeID = try #require(result.graph.nodes.first { $0.uid == "hr-1" }?.id)
        let parents = try #require(result.graph.details[routeID]?.httpRoute?.parents)
        let https = try #require(parents.first { $0.sectionName == "https" })
        let http = try #require(parents.first { $0.sectionName == "http" })
        #expect(https.accepted == true)
        #expect(https.resolvedRefs == true)
        #expect(http.accepted == false)
        #expect(http.resolvedRefs == false)
        #expect(result.graph.edges.contains { $0.relationship == .routesTo && $0.from.contains("hr-1") && $0.to.contains("gw-1") })
        let gatewayID = try #require(result.graph.nodes.first { $0.uid == "gw-1" }?.id)
        #expect(result.graph.details[gatewayID]?.gateway?.listeners.first?.port == 443)
        #expect(runner.calls.contains { $0 == ["kubectl", "get", "gatewayclasses.gateway.networking.k8s.io", "-o", "json", "--context", "gateway"] })
        #expect(runner.calls.contains { $0 == ["kubectl", "get", "gateways.gateway.networking.k8s.io", "-o", "json", "--context", "gateway", "-n", "demo"] })
        #expect(runner.calls.contains { $0 == ["kubectl", "get", "httproutes.gateway.networking.k8s.io", "-o", "json", "--context", "gateway", "-n", "demo"] })
        #expect(!runner.calls.contains { $0.contains("secrets") || $0.contains("configmaps") })
    }

    @Test func externalEndpointAddressesAndDuplicateIngressRoutesRemainVisible() async throws {
        let runner = TopologyFixtureRunner { args in
            let kind = args.count > 1 ? args[1] : ""
            if kind.contains("ingresses") {
                return fixtureJSON("{\"apiVersion\":\"networking.k8s.io/v1\",\"kind\":\"Ingress\",\"metadata\":{\"name\":\"route-a\",\"namespace\":\"demo\",\"uid\":\"ing-a\"},\"spec\":{\"rules\":[{\"host\":\"demo.example\",\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"external\",\"port\":{\"number\":80}}}}]}}]}},{\"apiVersion\":\"networking.k8s.io/v1\",\"kind\":\"Ingress\",\"metadata\":{\"name\":\"route-b\",\"namespace\":\"demo\",\"uid\":\"ing-b\"},\"spec\":{\"rules\":[{\"host\":\"demo.example\",\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"external\",\"port\":{\"number\":80}}}}]}}]}}")
            }
            if kind == "services" {
                return fixtureJSON("{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"name\":\"external\",\"namespace\":\"demo\",\"uid\":\"svc-ext\"},\"spec\":{\"type\":\"ClusterIP\",\"clusterIP\":\"None\",\"ports\":[{\"port\":80,\"targetPort\":8080}]}}")
            }
            if kind.contains("endpointslices") {
                return fixtureJSON("{\"apiVersion\":\"discovery.k8s.io/v1\",\"kind\":\"EndpointSlice\",\"metadata\":{\"name\":\"external-a\",\"namespace\":\"demo\",\"uid\":\"slice-a\",\"labels\":{\"kubernetes.io/service-name\":\"external\"}},\"addressType\":\"IPv4\",\"ports\":[{\"port\":8080,\"protocol\":\"TCP\"}],\"endpoints\":[{\"addresses\":[\"192.0.2.10\"],\"conditions\":{\"ready\":false}}]}{\"apiVersion\":\"discovery.k8s.io/v1\",\"kind\":\"EndpointSlice\",\"metadata\":{\"name\":\"external-b\",\"namespace\":\"demo\",\"uid\":\"slice-b\",\"labels\":{\"kubernetes.io/service-name\":\"external\"}},\"addressType\":\"IPv4\",\"ports\":[{\"port\":8080,\"protocol\":\"TCP\"}],\"endpoints\":[{\"addresses\":[\"192.0.2.11\"]}]}" )
            }
            return fixtureJSON("")
        }
        let result = try await TopologyService.load(context: "external", namespace: "demo", runner: runner)
        #expect(result.graph.portPaths.count == 2)
        #expect(result.graph.portPaths.allSatisfy { $0.hops.contains { $0.role == "endpoint" && $0.addresses.contains("192.0.2.11") } })
        #expect(result.graph.nodes.contains { $0.uid == "svc-ext" && $0.facts.contains { $0.key == "selector-none" } })
    }
}
