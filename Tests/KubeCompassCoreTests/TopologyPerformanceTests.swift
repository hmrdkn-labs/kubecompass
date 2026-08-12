import Foundation
import XCTest
@testable import KubeCompassCore

/// Deterministic, UI-free performance evidence for the tiered topology model.
///
/// This intentionally measures the shared model/query layer rather than a
/// particular native adapter. It emits one JSON line prefixed with
/// `KUBECOMPASS_TOPOLOGY_BENCHMARK_JSON=` so scripts can consume the report
/// without depending on XCTest's human-readable output format.
final class TopologyPerformanceTests: XCTestCase {
    func testTopologyBenchmarkEmitsJSON() throws {
        let environment = ProcessInfo.processInfo.environment
        let samples = max(1, min(25, Int(environment["KUBECOMPASS_BENCHMARK_SAMPLES"] ?? "3") ?? 3))
        let profile = environment["KUBECOMPASS_BENCHMARK_PROFILE"] == "full" ? "full" : "smoke"
        let report = TopologyBenchmarkRunner(samples: samples, profile: profile).run()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        print("KUBECOMPASS_TOPOLOGY_BENCHMARK_JSON=\(json)")

        // These are deliberately generous safety bounds. The benchmark JSON
        // is the evidence artifact; this guard only catches an accidental
        // algorithmic regression or an unusable local build.
        for benchmarkCase in report.cases {
            XCTAssertLessThan(benchmarkCase.wallTimeMilliseconds, 120_000, "benchmark case exceeded 120 second safety bound for \(benchmarkCase.objectCount) objects")
            XCTAssertLessThan(benchmarkCase.metrics.graphBuild.maxMilliseconds, 30_000, "graph build exceeded safety bound for \(benchmarkCase.objectCount) objects")
            XCTAssertLessThan(benchmarkCase.metrics.explorerLevelQuery.maxMilliseconds, 10_000, "level query exceeded safety bound for \(benchmarkCase.objectCount) objects")
            XCTAssertLessThan(benchmarkCase.metrics.searchFilter.maxMilliseconds, 10_000, "search exceeded safety bound for \(benchmarkCase.objectCount) objects")
            XCTAssertLessThan(benchmarkCase.metrics.oneHopFocus.maxMilliseconds, 10_000, "focus exceeded safety bound for \(benchmarkCase.objectCount) objects")
            XCTAssertLessThan(benchmarkCase.metrics.portPathFilter.maxMilliseconds, 10_000, "port filter exceeded safety bound for \(benchmarkCase.objectCount) objects")
        }
    }
}

struct TopologyBenchmarkReport: Codable, Sendable {
    let schemaVersion: Int
    let platform: String
    let profile: String
    let sampleCount: Int
    let rssBytes: Int?
    let rssMeasurementReason: String
    let cases: [TopologyBenchmarkCase]
}

struct TopologyBenchmarkCase: Codable, Sendable {
    let objectCount: Int
    let wallTimeMilliseconds: Double
    let nodeCount: Int
    let edgeCount: Int
    let portPathCount: Int
    let selectorCount: Int
    let metrics: TopologyBenchmarkMetrics
}

struct TopologyBenchmarkMetrics: Codable, Sendable {
    let graphBuild: TopologyBenchmarkMetric
    let explorerLevelQuery: TopologyBenchmarkMetric
    let searchFilter: TopologyBenchmarkMetric
    let oneHopFocus: TopologyBenchmarkMetric
    let portPathFilter: TopologyBenchmarkMetric
}

struct TopologyBenchmarkMetric: Codable, Sendable {
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let maxMilliseconds: Double
    let sampleCount: Int
}

private struct TopologyBenchmarkRunner {
    let samples: Int
    let profile: String

    func run() -> TopologyBenchmarkReport {
        let objectCounts = profile == "full" ? [100, 1_000, 10_000] : [100, 1_000]
        let cases = objectCounts.map { runCase(objectCount: $0) }
        #if os(macOS)
        let platform = "macOS"
        #elseif os(Linux)
        let platform = "Linux"
        #else
        let platform = "unknown"
        #endif
        return TopologyBenchmarkReport(
            schemaVersion: 1,
            platform: platform,
            profile: profile,
            sampleCount: samples,
            rssBytes: nil,
            rssMeasurementReason: "omitted: XCTest process RSS includes the test runtime and is not a portable graph-only measurement",
            cases: cases
        )
    }

    private func runCase(objectCount: Int) -> TopologyBenchmarkCase {
        let caseStart = DispatchTime.now().uptimeNanoseconds
        let fixture = makeFixture(objectCount: objectCount)
        // The full profile deliberately takes one sample at 10k. It is a
        // scale probe, not a routine XCTest gate; repeated 10k runs can
        // monopolize shared CI/build hosts.
        let caseSamples = objectCount >= 10_000 ? 1 : samples
        let buildSamples = measure(samples: caseSamples) { _ = TopologyGraphBuilder.build(fixture.input) }
        let graph = TopologyGraphBuilder.build(fixture.input)
        let query = TopologyGraphQuery(graph: graph)
        let selectedServiceIDs = Set(graph.nodes.filter { $0.kind == "Service" }.prefix(8).map(\.id))

        let levelSamples = measure(samples: caseSamples) {
            for level in ExplorerLevel.allCases {
                _ = query.nodes(level: level)
            }
        }
        let searchSamples = measure(samples: caseSamples) {
            _ = query.nodes(search: "app-17")
            _ = query.nodes(level: .network, search: "service-")
        }
        let focusSamples = measure(samples: caseSamples) {
            _ = query.oneHopFocus(nodeIDs: selectedServiceIDs)
        }
        let portSamples = measure(samples: caseSamples) {
            _ = query.portPaths(level: .network, protocolName: "TCP", port: 8080, readiness: true, search: "service-")
        }

        return TopologyBenchmarkCase(
            objectCount: objectCount,
            wallTimeMilliseconds: roundMilliseconds(Double(DispatchTime.now().uptimeNanoseconds - caseStart) / 1_000_000),
            nodeCount: graph.nodes.count,
            edgeCount: graph.edges.count,
            portPathCount: graph.portPaths.count,
            selectorCount: fixture.selectorCount,
            metrics: TopologyBenchmarkMetrics(
                graphBuild: summarize(buildSamples),
                explorerLevelQuery: summarize(levelSamples),
                searchFilter: summarize(searchSamples),
                oneHopFocus: summarize(focusSamples),
                portPathFilter: summarize(portSamples)
            )
        )
    }

    private func measure(samples: Int, _ operation: () -> Void) -> [Double] {
        // Warm up hashing, allocation and copy-on-write paths before sampling.
        operation()
        return (0..<samples).map { _ in
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            return Double(elapsed) / 1_000_000
        }
    }

    private func summarize(_ values: [Double]) -> TopologyBenchmarkMetric {
        let sorted = values.sorted()
        let p50Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.50))
        let p95Index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return TopologyBenchmarkMetric(
            p50Milliseconds: roundMilliseconds(sorted[p50Index]),
            p95Milliseconds: roundMilliseconds(sorted[p95Index]),
            maxMilliseconds: roundMilliseconds(sorted[sorted.count - 1]),
            sampleCount: sorted.count
        )
    }

    private func roundMilliseconds(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }

    private struct Fixture {
        let input: TopologyBuildInput
        let selectorCount: Int
    }

    private func makeFixture(objectCount: Int) -> Fixture {
        let nodeCount = max(4, min(64, objectCount / 200))
        let serviceCount = max(5, objectCount / 20)
        let ingressCount = serviceCount
        let sliceCount = serviceCount
        let podCount = max(1, objectCount - nodeCount - serviceCount - ingressCount - sliceCount)
        let appCount = max(20, min(50, serviceCount))

        var resources: [TopologyResourceSnapshot] = []
        resources.reserveCapacity(objectCount)

        for index in 0..<nodeCount {
            resources.append(resource(kind: "Node", name: "worker-\(index)", uid: "node-\(index)", namespace: nil, labels: ["topology.kubernetes.io/zone": "zone-\(index % 3)"], facts: [TopologyFact(key: "ready", title: "Ready", value: "true")]))
        }

        var podsByApp: [String: [TopologyResourceSnapshot]] = [:]
        for index in 0..<podCount {
            let app = "app-\(index % appCount)"
            let pod = resource(
                kind: "Pod",
                name: "pod-\(index)",
                uid: "pod-\(index)",
                labels: ["app": app],
                podNodeName: "worker-\(index % nodeCount)",
                containerPorts: [TopologyContainerPort(containerName: "api", name: "web", port: 8_080, protocolName: "TCP")],
                facts: [TopologyFact(key: "phase", title: "Phase", value: "Running")]
            )
            resources.append(pod)
            podsByApp[app, default: []].append(pod)
        }

        for index in 0..<serviceCount {
            let app = "app-\(index % appCount)"
            resources.append(resource(
                kind: "Service",
                name: "service-\(index)",
                uid: "service-\(index)",
                selector: ["app": app],
                servicePorts: [TopologyServicePort(name: "web", port: 80, targetPort: TopologyPortTarget(name: "web"), protocolName: "TCP", appProtocol: "http")],
                serviceMode: .standard,
                facts: [TopologyFact(key: "type", title: "Type", value: "ClusterIP")]
            ))
        }

        for index in 0..<sliceCount {
            let app = "app-\(index % appCount)"
            let endpointTargets = (podsByApp[app] ?? []).prefix(2).map { pod in
                TopologyEndpointTarget(reference: TopologyObjectReference(apiVersion: "v1", kind: "Pod", name: pod.identity.name, namespace: "default", uid: pod.identity.uid), ready: true, serving: true, addresses: ["10.42.\(index % 250).\((index % 200) + 1)"], nodeName: pod.podNodeName, zone: "zone-\(index % 3)")
            }
            resources.append(resource(
                kind: "EndpointSlice",
                name: "slice-\(index)",
                uid: "slice-\(index)",
                endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "service-\(index)", addressType: "IPv4", ports: [TopologyEndpointPort(name: "web", port: 8_080, protocolName: "TCP", appProtocol: "http")], endpoints: endpointTargets)
            ))
        }

        for index in 0..<ingressCount {
            resources.append(resource(
                kind: "Ingress",
                name: "ingress-\(index)",
                uid: "ingress-\(index)",
                ingressRoutes: [TopologyIngressRoute(ruleIndex: 0, pathIndex: 0, host: "service-\(index).example.test", path: "/", pathType: "Prefix", backendName: "service-\(index)", backendNamespace: "default", backendPortName: "web")]
            ))
        }

        return Fixture(input: TopologyBuildInput(contextID: "benchmark", resources: resources, freshness: TopologyFreshness(capturedAt: Date(timeIntervalSince1970: 0), generation: objectCount)), selectorCount: serviceCount)
    }

    private func resource(kind: String, name: String, uid: String, namespace: String? = "default", labels: [String: String] = [:], ownerReferences: [TopologyOwnerReference] = [], podNodeName: String? = nil, selector: [String: String] = [:], ingressRoutes: [TopologyIngressRoute] = [], endpointSlice: TopologyEndpointSliceSnapshot? = nil, servicePorts: [TopologyServicePort] = [], serviceMode: TopologyServiceMode? = nil, containerPorts: [TopologyContainerPort] = [], facts: [TopologyFact] = []) -> TopologyResourceSnapshot {
        TopologyResourceSnapshot(
            identity: TopologyResourceIdentity(apiVersion: kind == "EndpointSlice" ? "discovery.k8s.io/v1" : "v1", kind: kind, name: name, namespace: namespace, uid: uid, labels: labels),
            ownerReferences: ownerReferences,
            podNodeName: podNodeName,
            selector: selector,
            ingressRoutes: ingressRoutes,
            endpointSlice: endpointSlice,
            servicePorts: servicePorts,
            serviceMode: serviceMode,
            containerPorts: containerPorts,
            facts: facts
        )
    }
}
