import Foundation

public struct LinuxLaunchOptions: Equatable, Sendable {
    public var rows: Int
    public var smoke: Bool
    public var demo: Bool

    public init(rows: Int = 2, smoke: Bool = false, demo: Bool = true) {
        self.rows = max(1, rows)
        self.smoke = smoke
        self.demo = demo
    }

    public init(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) {
        var parsedRows: Int?
        var parsedSmoke = false
        var parsedDemo = true
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--smoke" {
                parsedSmoke = true
            } else if argument == "--no-demo" {
                parsedDemo = false
            } else if argument == "--rows", index + 1 < arguments.count {
                parsedRows = Int(arguments[index + 1])
                index += 1
            } else if argument.hasPrefix("--rows=") {
                parsedRows = Int(argument.dropFirst("--rows=".count))
            }
            index += 1
        }
        let envRows = environment["KUBECOMPASS_ROWS"].flatMap(Int.init)
        self.init(rows: parsedRows ?? envRows ?? 2, smoke: parsedSmoke, demo: parsedDemo)
    }

    public static var helpText: String {
        "KubeCompass Linux demo\n\n" +
            "Usage: kubecompass-linux [--smoke] [--rows N] [--no-demo]\n" +
            "       kc [--smoke] [--rows N]\n\n" +
            "The Linux vertical slice is fixture-only; it never executes kubectl."
    }
}

public enum LinuxSemanticLabels {
    public static let window = "KubeCompass window"
    public static let context = "context picker"
    public static let sidebar = "resource navigation sidebar"
    public static let namespace = "namespace picker"
    public static let resourceKind = "resource kind navigation"
    public static let table = "resource table"
    public static let detail = "resource detail"
    public static let logs = "resource logs"
    public static let commandPalette = "command palette"
    public static let status = "connection status"
}

public enum LinuxDemoCatalog {
    public static func resourceNames(rows: Int) -> [String] {
        (0..<max(1, rows)).map { "pod-\($0)" }
    }

    public static func status(for index: Int) -> String {
        index.isMultiple(of: 17) ? "Pending" : "Running"
    }

    public static func labels(for index: Int) -> [String: String] {
        ["app": "kubecompass-demo", "fixture": "true", "ordinal": String(index)]
    }
}
