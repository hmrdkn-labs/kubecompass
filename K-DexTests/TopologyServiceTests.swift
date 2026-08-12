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
    ProcessResult(stdout: Data("{\"apiVersion\":\"v1\",\"items\":[\(items)]}".utf8), stderr: Data(), exitCode: 0)
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
}
