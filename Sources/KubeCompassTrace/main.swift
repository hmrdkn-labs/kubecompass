import Foundation
import KubeCompassCore

struct BenchmarkReport: Codable {
    let rows: Int
    let runs: Int
    let p95Milliseconds: Double
    let rssBytes: Int?
}

@main
struct KubeCompassTraceMain {
    static func main() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if CommandLine.arguments.contains("--benchmark") {
            let rows = (0..<10_000).map { KubeResource(id: "pods/default/pod-\($0)", kindID: "pods", name: "pod-\($0)", namespace: "default", status: $0.isMultiple(of: 2) ? "Running" : "Pending") }
            let index = ResourceTableIndex(resources: rows); var samples: [Double] = []
            for _ in 0..<20 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = index.filteredSorted(query: "pod-9", by: .name)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            samples.sort(); let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
            let report = BenchmarkReport(rows: index.count, runs: samples.count, p95Milliseconds: p95, rssBytes: nil)
            print(String(data: try! encoder.encode(report), encoding: .utf8)!)
        } else {
            print(String(data: try! encoder.encode(CompassTrace.run()), encoding: .utf8)!)
        }
    }
}
