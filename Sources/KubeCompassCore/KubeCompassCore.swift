import Foundation

// MARK: - Domain values

public struct KubeContext: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let cluster: String
    public let user: String
    public let isCurrent: Bool
    public let defaultNamespace: String?

    public init(id: String, name: String, cluster: String, user: String, isCurrent: Bool = false, defaultNamespace: String? = nil) {
        self.id = id; self.name = name; self.cluster = cluster; self.user = user; self.isCurrent = isCurrent; self.defaultNamespace = defaultNamespace
    }
}

public typealias Context = KubeContext

public struct ResourceKind: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let namespaced: Bool
    public let supportsDelete: Bool
    public let supportsRestart: Bool

    public init(id: String, displayName: String, namespaced: Bool = true, supportsDelete: Bool = false, supportsRestart: Bool? = nil) {
        self.id = id; self.displayName = displayName; self.namespaced = namespaced; self.supportsDelete = supportsDelete
        self.supportsRestart = supportsRestart ?? ["deployments", "statefulsets", "daemonsets"].contains(id.lowercased())
    }
}

/// A deliberately sanitized resource value. Raw Kubernetes payloads never
/// enter this type; Secret values are represented only by their key names.
public struct KubeResource: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kindID: String
    public let name: String
    public let namespace: String?
    public let status: String
    public let labels: [String: String]
    public let secretDataKeys: [String]
    public let apiVersion: String
    public let group: String
    public let resourcePlural: String
    public let kindName: String
    public let uid: String
    public let resourceVersion: String

    public init(id: String, kindID: String, name: String, namespace: String? = nil, status: String = "", labels: [String: String] = [:], rawData: [String: String] = [:], apiVersion: String = "v1", group: String = "", resourcePlural: String? = nil, kindName: String? = nil, uid: String = "", resourceVersion: String = "") {
        self.id = id; self.kindID = kindID; self.name = name; self.namespace = namespace; self.status = CompassSanitizer.clean(status)
        self.labels = kindID.lowercased() == "secrets" ? [:] : labels
        self.secretDataKeys = kindID.lowercased() == "secrets" ? rawData.keys.sorted() : []
        self.apiVersion = apiVersion; self.group = group; self.resourcePlural = resourcePlural ?? kindID; self.kindName = kindName ?? kindID
        self.uid = uid; self.resourceVersion = resourceVersion
    }

    public var isSecret: Bool { kindID.lowercased() == "secrets" }
    public var safeDescription: String {
        let scope = namespace.map { "\($0)/" } ?? ""
        let suffix = isSecret && !secretDataKeys.isEmpty ? " (secret keys: \(secretDataKeys.joined(separator: ",")))" : ""
        return "\(kindID)/\(scope)\(name)\(suffix)"
    }

    public func mutationTarget(contextID: String, namespaced: Bool) -> MutationTarget? {
        guard !contextID.isEmpty, !name.isEmpty, !resourcePlural.isEmpty, !uid.isEmpty, !resourceVersion.isEmpty else { return nil }
        guard !namespaced || namespace != nil else { return nil }
        return MutationTarget(contextID: contextID, apiVersion: apiVersion, group: group, resourcePlural: resourcePlural, kindName: kindName, name: name, namespace: namespaced ? namespace : nil, uid: uid, resourceVersion: resourceVersion, sourceID: id)
    }
}

public typealias Resource = KubeResource

public enum CompassSemanticID {
    public static let context = "context"; public static let sidebar = "sidebar"; public static let table = "table"; public static let detail = "detail"; public static let logs = "logs"; public static let commandPalette = "command-palette"; public static let status = "status"
}

// MARK: - Safe diagnostics

public enum CompassProblemCode: String, Codable, Hashable, Sendable { case permission, offline, notFound, expired, invalid, cancelled, unsupported, unknown }

enum CompassSanitizer {
    static func clean(_ input: String) -> String {
        var text = input
        if let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]", options: []) { text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "") }
        text = text.unicodeScalars.map { $0.value < 0x20 && $0.value != 0x09 ? " " : String($0) }.joined()
        let patterns: [(String, String)] = [
            ("(?i)(bearer\\s+)[^\\s,;\"]+", "$1[REDACTED]"),
            ("(?i)(authorization|cookie|credential|password|token|client[-_ ]?secret|secret|key|value|certificate[-_ ]?data|annotations?)(\\s*[:=]\\s*)\\{[^}]*\\}", "$1$2[REDACTED]"),
            ("(?i)(\\\"(?:authorization|cookie|credential|password|token|client[-_ ]?secret|secret|key|value|certificate[-_ ]?data|annotations?)\\\"\\s*:\\s*)(?:\\{[^}]*\\}|\\[[^]]*\\]|\\\"[^\\\"]*\\\")", "$1[REDACTED]"),
            ("(?i)(authorization|cookie|credential|password|token|client[-_ ]?secret|secret|key|value|certificate[-_ ]?data|annotations?)(\\s*[:=]\\s*)[^\\s,;}\"]+", "$1$2[REDACTED]"),
            ("(?i)(\\\"(?:authorization|cookie|credential|password|token|client[-_ ]?secret|secret|key|value|certificate[-_ ]?data|annotations?)\\\"\\s*:\\s*)\\\"[^\\\"]*\\\"", "$1\\\"[REDACTED]\\\"")
        ]
        for (pattern, replacement) in patterns { if let regex = try? NSRegularExpression(pattern: pattern, options: []) { text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement) } }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct CompassProblem: Codable, Hashable, Sendable, CustomStringConvertible {
    public let code: CompassProblemCode
    public let message: String
    public init(code: CompassProblemCode, message: String) { self.code = code; self.message = CompassSanitizer.clean(message) }
    public static func classify(_ raw: String) -> CompassProblem {
        let clean = CompassSanitizer.clean(raw); let lower = clean.lowercased()
        let code: CompassProblemCode = lower.contains("forbidden") || lower.contains("permission") || lower.contains("unauthorized") ? .permission : lower.contains("410") || lower.contains("expired") ? .expired : lower.contains("not found") ? .notFound : lower.contains("offline") || lower.contains("timed out") || lower.contains("timeout") || lower.contains("connection") ? .offline : lower.contains("cancel") ? .cancelled : lower.contains("invalid") ? .invalid : .unknown
        return CompassProblem(code: code, message: clean)
    }
    public var description: String { "\(code.rawValue): \(message)" }
}

public enum LoadingState: Codable, Hashable, Sendable { case idle, loading, ready, empty, stale, failed(CompassProblem) }
public enum ConnectivityState: String, Codable, Hashable, Sendable { case offline, connecting, connected, reconnecting, cancelled }
public enum DetailTab: String, Codable, Hashable, Sendable, CaseIterable { case overview, pods, yaml, logs, events }
public enum ListWatchScope: Codable, Hashable, Sendable { case current, namespace(String), allNamespaces }
public enum ObjectScope: Codable, Hashable, Sendable { case namespaced(namespace: String), cluster }
public enum WatchHealth: Codable, Hashable, Sendable { case notStarted, starting, healthy(resourceVersion: String?), retrying(attempt: Int, delayMilliseconds: Int), expired(resourceVersion: String?), pollingFallback(CompassProblem), failed(CompassProblem), cancelled }

public struct LogLine: Codable, Hashable, Sendable, Identifiable {
    public let id: Int; public let text: String; public let stream: String
    public init(id: Int, text: String, stream: String = "stdout") { self.id = id; self.text = CompassSanitizer.clean(text); self.stream = CompassSanitizer.clean(stream) }
    public var safeDescription: String { "line \(id) [\(stream)]" }
}

public struct MutationTarget: Codable, Hashable, Sendable, Identifiable {
    public let contextID: String; public let apiVersion: String; public let group: String; public let resourcePlural: String; public let kindName: String; public let name: String; public let namespace: String?; public let uid: String; public let resourceVersion: String; public let sourceID: String?
    public var id: String { sourceID ?? "\(resourcePlural)/\(name)" }
    public init(contextID: String, apiVersion: String, group: String = "", resourcePlural: String, kindName: String, name: String, namespace: String?, uid: String, resourceVersion: String, sourceID: String? = nil) {
        self.contextID = contextID; self.apiVersion = apiVersion; self.group = group; self.resourcePlural = resourcePlural; self.kindName = kindName; self.name = name; self.namespace = namespace; self.uid = uid; self.resourceVersion = resourceVersion; self.sourceID = sourceID
    }
}

public enum MutationOperation: String, Codable, Hashable, Sendable { case delete, restart }
public struct MutationRequest: Codable, Hashable, Sendable { public let operation: MutationOperation; public let targets: [MutationTarget]; public init(operation: MutationOperation, targets: [MutationTarget]) { self.operation = operation; self.targets = targets } }
public enum MutationValidationStage: String, Codable, Hashable, Sendable { case refetch, identityVerified, serverDryRun, accepted, rejected }
/// Immutable server dry-run evidence. It is a preview record, never an
/// authorization or executable command.
public struct ValidatedMutationPreview: Codable, Hashable, Sendable {
    public let request: MutationRequest; public let targetDigest: String; public let stage: MutationValidationStage
    public init(request: MutationRequest, stage: MutationValidationStage = .serverDryRun) { self.request = request; self.targetDigest = MutationDigest.make(request.targets); self.stage = stage }
}
public struct MutationPreviewDescription: Codable, Hashable, Sendable {
    public let operation: MutationOperation; public let target: MutationTarget
    public init(operation: MutationOperation, target: MutationTarget) { self.operation = operation; self.target = target }
}
private enum MutationDigest {
    static func make(_ targets: [MutationTarget]) -> String {
        let material = targets.map { "\($0.contextID)|\($0.apiVersion)|\($0.group)|\($0.resourcePlural)|\($0.kindName)|\($0.name)|\($0.namespace ?? "")|\($0.uid)|\($0.resourceVersion)" }.sorted().joined(separator: "\n")
        var hash: UInt64 = 14695981039346656037
        for byte in material.utf8 { hash ^= UInt64(byte); hash &*= 1099511628211 }
        return String(format: "%016llx", hash)
    }
}
public enum ConfirmationState: Codable, Hashable, Sendable { case none, pending(MutationRequest), validated(ValidatedMutationPreview) }

public struct WatchRetryPolicy: Codable, Hashable, Sendable {
    public let baseDelayMilliseconds: Int; public let capDelayMilliseconds: Int; public let maxAttempts: Int; public let jitterMilliseconds: Int
    public init(baseDelayMilliseconds: Int = 100, capDelayMilliseconds: Int = 5_000, maxAttempts: Int = 3, jitterMilliseconds: Int = 0) {
        let cap = max(1, capDelayMilliseconds); let base = min(cap, max(1, baseDelayMilliseconds)); self.baseDelayMilliseconds = base; self.capDelayMilliseconds = cap; self.maxAttempts = max(1, maxAttempts); self.jitterMilliseconds = max(0, min(jitterMilliseconds, cap - 1))
    }
    public func delay(forAttempt attempt: Int) -> Int { let safeAttempt = max(1, attempt); let exponent = min(max(0, safeAttempt - 1), Int.bitWidth - 2); let exponential = baseDelayMilliseconds > capDelayMilliseconds >> exponent ? capDelayMilliseconds : baseDelayMilliseconds << exponent; return exponential > capDelayMilliseconds - jitterMilliseconds ? capDelayMilliseconds : exponential + jitterMilliseconds }
}

public enum PortForwardState: Codable, Hashable, Sendable { case starting, active, failed(CompassProblem), stopped }
public struct PortForward: Codable, Hashable, Sendable, Identifiable {
    public let id: String; public let contextID: String; public let namespace: String?; public let target: String; public let localPort: Int; public let remotePort: Int; public var state: PortForwardState
    public init(id: String, contextID: String, namespace: String?, target: String, localPort: Int, remotePort: Int, state: PortForwardState = .starting) { self.id = id; self.contextID = contextID; self.namespace = namespace; self.target = target; self.localPort = localPort; self.remotePort = remotePort; self.state = state }
}

// MARK: - State, intents, events, effects

public struct CompassState: Codable, Hashable, Sendable {
    public var contexts: [KubeContext] = []; public var selectedContextID: String?; public var namespaces: [String] = []; public var selectedNamespace: String?
    public var selectedListScope: ListWatchScope = .current; public var resourceKinds: [ResourceKind] = []; public var selectedKindID: String?; public var resourcesByKind: [String: [KubeResource]] = [:]; public var selectedResourceID: String?
    public var detailTab: DetailTab = .overview; public var logs: [LogLine] = []; public var loading: LoadingState = .idle; public var connectivity: ConnectivityState = .offline
    public var confirmation: ConfirmationState = .none; public var portForwards: [PortForward] = []; public var lastError: CompassProblem?; public var permissionMessage: CompassProblem?
    public var isWatching = false; public var reconnectGeneration = 0; public var watchHealth: WatchHealth = .notStarted; public var watchRetryCount = 0; public var watchRetryPolicy = WatchRetryPolicy()
    public init() {}
    public var selectedResources: [KubeResource] { guard let kind = selectedKindID, let id = selectedResourceID else { return [] }; return resourcesByKind[kind, default: []].filter { $0.id == id } }
    public var safeDescription: String { "context=\(selectedContextID ?? "none") namespace=\(selectedNamespace ?? "current") resource=\(selectedResources.first?.safeDescription ?? "none") logs=\(logs.count) problem=\(lastError?.code.rawValue ?? "none")" }
}

public enum CompassIntent: Sendable {
    case bootstrap; case contextsLoaded([KubeContext]); case contextsFailed(String); case selectContext(String); case namespacesLoaded([String]); case selectNamespace(String?); case selectKind(String); case resourcesLoaded(kindID: String, resources: [KubeResource]); case resourcesFailed(String); case permissionDenied(String); case selectResource(String?); case selectDetailTab(DetailTab); case appendLog(LogLine); case clearLogs
    case watchEvent(kindID: String, event: WatchEvent); case watchStarted(kindID: String, resourceVersion: String?); case watchRetryJitter(milliseconds: Int); case watchRetryPolicy(WatchRetryPolicy); case watchRetryReady(kindID: String); case watchUnavailable(kindID: String, problem: CompassProblem); case cancelWatch
    case beginReconnect; case finishReconnect(success: Bool); case cancelReconnect
    case requestMutation(MutationRequest)
    /// Compatibility intent for UI selection IDs. The reducer resolves IDs
    /// against loaded resources before creating a typed MutationTarget; IDs
    /// never enter argv or become kubectl object names.
    case requestDelete([String]); case requestRestart([String]); case confirmMutation; case denyMutation; case mutationRefetched([MutationTarget]); case mutationDryRunFinished(success: Bool, problem: CompassProblem?); case mutationFinished(success: Bool, message: String?)
    case startPortForward(PortForward); case portForwardState(id: String, state: PortForwardState); case stopPortForward(String)
}

public enum CompassEvent: Codable, Hashable, Sendable { case stateChanged; case contextsAvailable(Int); case contextSelected(String); case contextPickerRequired; case namespaceSelected(String?); case resourcesReplaced(kindID: String, count: Int); case resourceSelected(String?); case detailTabSelected(DetailTab); case logAppended(Int); case watchApplied(WatchEvent.Kind); case watchBecameHealthy(String?); case watchRetryScheduled(Int); case watchFallback; case reconnectStarted(Int); case reconnectFinished(Bool); case mutationValidation(MutationValidationStage); case mutationConfirmationRequired; case mutationDenied; case mutationFinished(Bool); case portForwardChanged(String) }

public enum CompassEffect: Codable, Hashable, Sendable {
    // Process spawning, stream framing, scale, and YAML apply are intentionally
    // outside this Foundation contract; runtime adapters own those boundaries.
    case loadContexts; case loadNamespaces(contextID: String); case listResources(contextID: String, kindID: String, scope: ListWatchScope); case fetchDetail(contextID: String, kindID: String, resourceName: String, scope: ObjectScope); case streamLogs(contextID: String, resourceName: String, scope: ObjectScope); case watch(contextID: String, kindID: String, scope: ListWatchScope); case relist(contextID: String, kindID: String, scope: ListWatchScope); case poll(contextID: String, kindID: String, scope: ListWatchScope); case backoff(attempt: Int, delayMilliseconds: Int); case refetchMutation(MutationRequest); case dryRunMutation(MutationRequest); case reconnect(generation: Int); case cancel(requestID: String)
}

public struct CompassTransition: Sendable { public let state: CompassState; public let events: [CompassEvent]; public let effects: [CompassEffect]; public init(state: CompassState, events: [CompassEvent] = [], effects: [CompassEffect] = []) { self.state = state; self.events = events; self.effects = effects } }

public enum WatchEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case added, modified, deleted, bookmark, expired }
    case added(KubeResource); case modified(KubeResource); case deleted(resourceID: String); case bookmark(resourceVersion: String); case expired(resourceVersion: String?)
    public var kind: Kind { switch self { case .added: return .added; case .modified: return .modified; case .deleted: return .deleted; case .bookmark: return .bookmark; case .expired: return .expired } }
    public var resourceVersion: String? { switch self { case .added(let r), .modified(let r): return r.resourceVersion.isEmpty ? nil : r.resourceVersion; case .bookmark(let rv): return rv; case .expired(let rv): return rv; case .deleted: return nil } }
}

public enum CompassReducer {
    public static func reduce(_ state: CompassState, _ intent: CompassIntent) -> CompassTransition {
        var next = state; var events: [CompassEvent] = []; var effects: [CompassEffect] = []
        switch intent {
        case .bootstrap: next.loading = .loading; next.connectivity = .connecting; next.lastError = nil; effects = [.loadContexts]
        case .contextsLoaded(let contexts):
            next.contexts = contexts.sorted { $0.id < $1.id }; events = [.contextsAvailable(contexts.count)]
            let current = contexts.filter(\.isCurrent)
            guard current.count == 1, let selected = current.first else { next.loading = contexts.isEmpty ? .empty : .ready; next.connectivity = contexts.isEmpty ? .offline : .connected; events.append(.contextPickerRequired); return CompassTransition(state: next, events: events) }
            next.selectedContextID = selected.id; next.loading = .loading; next.connectivity = .connecting; effects = [.loadNamespaces(contextID: selected.id)]
        case .contextsFailed(let message): let p = CompassProblem.classify(message); next.loading = .failed(p); next.connectivity = .offline; next.lastError = p
        case .selectContext(let id):
            guard next.contexts.contains(where: { $0.id == id }) else { return CompassTransition(state: state) }
            next.selectedContextID = id; next.selectedNamespace = nil; next.selectedListScope = .current; next.namespaces = []; next.selectedKindID = nil; next.selectedResourceID = nil; next.resourcesByKind = [:]; next.loading = .loading; next.connectivity = .connecting; next.lastError = nil; effects = [.loadNamespaces(contextID: id)]; events = [.contextSelected(id)]
        case .namespacesLoaded(let namespaces):
            next.namespaces = Array(Set(namespaces)).sorted(); let contextDefault = next.contexts.first(where: { $0.id == next.selectedContextID })?.defaultNamespace; next.selectedNamespace = contextDefault.flatMap { next.namespaces.contains($0) ? $0 : nil } ?? (next.namespaces.contains("default") ? "default" : next.namespaces.first); next.selectedListScope = next.selectedNamespace.map { .namespace($0) } ?? .current; next.loading = .ready; next.connectivity = .connected; events = [.namespaceSelected(next.selectedNamespace)]
        case .selectNamespace(let namespace):
            guard namespace == nil || next.namespaces.contains(namespace!) else { return CompassTransition(state: state) }; next.selectedNamespace = namespace; next.selectedListScope = namespace.map { .namespace($0) } ?? .current; next.loading = .loading
            if let contextID = next.selectedContextID, let kindID = next.selectedKindID { effects = [.listResources(contextID: contextID, kindID: kindID, scope: next.selectedListScope)] }; events = [.namespaceSelected(namespace)]
        case .selectKind(let kindID):
            guard next.resourceKinds.contains(where: { $0.id == kindID }) else { return CompassTransition(state: state) }; next.selectedKindID = kindID; next.selectedResourceID = nil; next.detailTab = .overview; next.loading = .loading
            if let contextID = next.selectedContextID { effects = [.listResources(contextID: contextID, kindID: kindID, scope: next.selectedListScope)] }
        case .resourcesLoaded(let kindID, let resources):
            let index = ResourceTableIndex(resources: resources); next.resourcesByKind[kindID] = index.resources; next.loading = index.resources.isEmpty ? .empty : .ready; next.connectivity = .connected; next.lastError = nil; next.watchHealth = .starting; next.isWatching = false; events = [.resourcesReplaced(kindID: kindID, count: index.count)]
            if let contextID = next.selectedContextID { effects = [.watch(contextID: contextID, kindID: kindID, scope: next.selectedListScope)] }
        case .resourcesFailed(let message): let p = CompassProblem.classify(message); next.loading = .failed(p); next.lastError = p
        case .permissionDenied(let message): let p = CompassProblem.classify(message); next.permissionMessage = p; next.lastError = p; next.loading = .failed(p); next.connectivity = .offline
        case .selectResource(let id):
            let valid = id.flatMap { candidate in next.resourcesByKind[next.selectedKindID ?? "", default: []].first(where: { $0.id == candidate })?.id }; next.selectedResourceID = valid; next.detailTab = .overview; events = [.resourceSelected(valid)]
            if let contextID = next.selectedContextID, let kindID = next.selectedKindID, let valid, let resource = next.resourcesByKind[kindID, default: []].first(where: { $0.id == valid }), let kind = next.resourceKinds.first(where: { $0.id == kindID }), let scope = objectScope(for: kind, namespace: next.selectedNamespace) { effects = [.fetchDetail(contextID: contextID, kindID: kindID, resourceName: resource.name, scope: scope)] }
        case .selectDetailTab(let tab):
            next.detailTab = tab; events = [.detailTabSelected(tab)]
            if tab == .logs, let contextID = next.selectedContextID, let resourceID = next.selectedResourceID, let kindID = next.selectedKindID, let resource = next.resourcesByKind[kindID, default: []].first(where: { $0.id == resourceID }), let kind = next.resourceKinds.first(where: { $0.id == kindID }), let scope = objectScope(for: kind, namespace: next.selectedNamespace) { effects = [.streamLogs(contextID: contextID, resourceName: resource.name, scope: scope)] }
        case .appendLog(let line): next.logs.append(line); events = [.logAppended(line.id)]
        case .clearLogs: next.logs.removeAll()
        case .watchStarted(_, let rv): next.watchHealth = .healthy(resourceVersion: rv); next.isWatching = true; next.watchRetryCount = 0; events = [.watchBecameHealthy(rv)]
        case .watchRetryJitter(let milliseconds): next.watchRetryPolicy = WatchRetryPolicy(baseDelayMilliseconds: next.watchRetryPolicy.baseDelayMilliseconds, capDelayMilliseconds: next.watchRetryPolicy.capDelayMilliseconds, maxAttempts: next.watchRetryPolicy.maxAttempts, jitterMilliseconds: milliseconds)
        case .watchRetryPolicy(let policy): next.watchRetryPolicy = policy
        case .watchRetryReady(let kindID):
            guard case .retrying = next.watchHealth, let contextID = next.selectedContextID else { return CompassTransition(state: state) }; next.watchHealth = .starting; effects = [.watch(contextID: contextID, kindID: kindID, scope: next.selectedListScope)]
        case .watchUnavailable(_, let problem):
            next.watchHealth = .pollingFallback(problem); next.isWatching = false; events = [.watchFallback]
            if let contextID = next.selectedContextID, let kindID = next.selectedKindID { effects = [.poll(contextID: contextID, kindID: kindID, scope: next.selectedListScope)] }
        case .cancelWatch:
            guard next.isWatching || isWatchActive(next.watchHealth) else { return CompassTransition(state: state) }; next.isWatching = false; next.watchHealth = .cancelled; effects = [.cancel(requestID: "watch")]
        case .watchEvent(let kindID, let event):
            if case .expired(let rv) = event {
                if case .retrying = next.watchHealth { return CompassTransition(state: state) }
                guard next.watchRetryCount < next.watchRetryPolicy.maxAttempts, let contextID = next.selectedContextID else { next.watchHealth = .failed(CompassProblem(code: .expired, message: "watch expired")); return CompassTransition(state: next, events: [.watchApplied(.expired)]) }
                next.watchRetryCount += 1; let delay = next.watchRetryPolicy.delay(forAttempt: next.watchRetryCount); next.watchHealth = .retrying(attempt: next.watchRetryCount, delayMilliseconds: delay); next.isWatching = false; next.lastError = CompassProblem(code: .expired, message: rv.map { "watch expired at resourceVersion=\($0)" } ?? "watch expired"); effects = [.relist(contextID: contextID, kindID: kindID, scope: next.selectedListScope), .backoff(attempt: next.watchRetryCount, delayMilliseconds: delay)]; events = [.watchApplied(.expired), .watchRetryScheduled(next.watchRetryCount)]; return CompassTransition(state: next, events: events, effects: effects)
            }
            var current = next.resourcesByKind[kindID, default: []]
            switch event { case .added(let resource): if !current.contains(where: { $0.id == resource.id }) { current.append(resource) }; case .modified(let resource): if let i = current.firstIndex(where: { $0.id == resource.id }) { current[i] = resource } else { current.append(resource) }; case .deleted(let resourceID): current.removeAll { $0.id == resourceID }; if next.selectedResourceID == resourceID { next.selectedResourceID = nil }; case .bookmark(let rv): if case .healthy = next.watchHealth { next.watchHealth = .healthy(resourceVersion: rv) }; case .expired: break }
            next.resourcesByKind[kindID] = ResourceTableIndex(resources: current).resources; events = [.watchApplied(event.kind)]
        case .beginReconnect: guard next.connectivity != .reconnecting else { return CompassTransition(state: state) }; next.reconnectGeneration += 1; next.connectivity = .reconnecting; next.isWatching = false; next.loading = next.resourcesByKind.isEmpty ? .loading : .stale; events = [.reconnectStarted(next.reconnectGeneration)]; effects = [.reconnect(generation: next.reconnectGeneration)]
        case .finishReconnect(let success): next.connectivity = success ? .connected : .offline; next.isWatching = false; next.loading = success ? .ready : .stale; events = [.reconnectFinished(success)]
        case .cancelReconnect: guard next.connectivity == .reconnecting else { return CompassTransition(state: state) }; next.connectivity = .cancelled; next.isWatching = false; effects = [.cancel(requestID: "reconnect-\(next.reconnectGeneration)")]
        case .requestDelete(let ids): return requestLegacy(state, ids: ids, operation: .delete)
        case .requestRestart(let ids): return requestLegacy(state, ids: ids, operation: .restart)
        case .requestMutation(let request):
            guard validRequest(request, in: next) else { return CompassTransition(state: state) }; next.confirmation = .pending(request); events = [.mutationConfirmationRequired, .mutationValidation(.refetch)]; effects = [.refetchMutation(request)]
        case .confirmMutation:
            guard case .pending(let request) = next.confirmation else { return CompassTransition(state: state) }; events = [.mutationValidation(.refetch)]; effects = [.refetchMutation(request)]
        case .mutationRefetched(let snapshots):
            guard case .pending(let request) = next.confirmation, snapshots.count == request.targets.count, Set(snapshots.map(\.id)).count == snapshots.count, request.targets.allSatisfy({ expected in snapshots.contains(where: { sameIdentity(expected, $0) }) }), validRequest(request, in: next) else { return reject(next, problem: CompassProblem(code: .invalid, message: "mutation snapshot set is stale or incomplete")) }
            events = [.mutationValidation(.identityVerified)]; effects = [.dryRunMutation(request)]
        case .mutationDryRunFinished(let success, let problem):
            guard success, problem == nil, case .pending(let request) = next.confirmation else { return reject(next, problem: problem ?? CompassProblem(code: .invalid, message: "server dry-run failed")) }
            let preview = ValidatedMutationPreview(request: request); next.confirmation = .validated(preview); events = [.mutationValidation(preview.stage)]
        case .denyMutation: next.confirmation = .none; events = [.mutationDenied]
        case .mutationFinished(let success, let message): let p = message.map(CompassProblem.classify); next.lastError = success ? nil : p; next.loading = success ? .ready : .failed(p ?? CompassProblem(code: .unknown, message: "mutation failed")); events = [.mutationFinished(success)]
        case .startPortForward(let forward): guard !next.portForwards.contains(where: { $0.id == forward.id }) else { return CompassTransition(state: state) }; next.portForwards.append(forward); events = [.portForwardChanged(forward.id)]
        case .portForwardState(let id, let portState): guard let index = next.portForwards.firstIndex(where: { $0.id == id }) else { return CompassTransition(state: state) }; next.portForwards[index].state = portState; events = [.portForwardChanged(id)]
        case .stopPortForward(let id): guard next.portForwards.contains(where: { $0.id == id }) else { return CompassTransition(state: state) }; next.portForwards.removeAll { $0.id == id }; effects = [.cancel(requestID: "port-forward-\(id)")]; events = [.portForwardChanged(id)]
        }
        return CompassTransition(state: next, events: events, effects: effects)
    }

    private static func objectScope(for kind: ResourceKind, namespace: String?) -> ObjectScope? { kind.namespaced ? namespace.map { .namespaced(namespace: $0) } : .cluster }
    private static func isWatchActive(_ health: WatchHealth) -> Bool { switch health { case .starting, .healthy, .retrying: return true; default: return false } }
    private static func sameIdentity(_ a: MutationTarget, _ b: MutationTarget) -> Bool { a.contextID == b.contextID && a.apiVersion == b.apiVersion && a.group == b.group && a.resourcePlural == b.resourcePlural && a.kindName == b.kindName && a.name == b.name && a.namespace == b.namespace && a.uid == b.uid && a.resourceVersion == b.resourceVersion }
    private static func validRequest(_ request: MutationRequest, in state: CompassState) -> Bool {
        guard !request.targets.isEmpty, let context = state.selectedContextID, let kindID = state.selectedKindID, let kind = state.resourceKinds.first(where: { $0.id == kindID }), (request.operation == .delete ? kind.supportsDelete : kind.supportsRestart) else { return false }
        let targetKeys = request.targets.map { "\($0.contextID)|\($0.apiVersion)|\($0.group)|\($0.resourcePlural)|\($0.name)|\($0.namespace ?? "")|\($0.uid)|\($0.resourceVersion)" }
        guard Set(targetKeys).count == request.targets.count else { return false }
        guard request.targets.allSatisfy({ $0.contextID == context && ($0.namespace == nil || state.selectedNamespace == $0.namespace) && (kind.namespaced ? $0.namespace != nil : $0.namespace == nil) }) else { return false }
        let loaded = state.resourcesByKind[kindID, default: []]
        return request.targets.allSatisfy { target in loaded.contains { resource in (target.sourceID == nil || resource.id == target.sourceID) && resource.name == target.name && resource.namespace == target.namespace && resource.uid == target.uid && resource.resourceVersion == target.resourceVersion && resource.resourcePlural == target.resourcePlural && resource.kindName == target.kindName } }
    }
    private static func requestLegacy(_ state: CompassState, ids: [String], operation: MutationOperation) -> CompassTransition {
        guard let context = state.selectedContextID, let kindID = state.selectedKindID, let kind = state.resourceKinds.first(where: { $0.id == kindID }) else { return CompassTransition(state: state) }
        let targets = state.resourcesByKind[kindID, default: []].filter { ids.contains($0.id) }.compactMap { $0.mutationTarget(contextID: context, namespaced: kind.namespaced) }
        guard targets.count == ids.count else { return CompassTransition(state: state) }
        return reduce(state, .requestMutation(MutationRequest(operation: operation, targets: targets)))
    }
    private static func reject(_ state: CompassState, problem: CompassProblem) -> CompassTransition { var next = state; next.confirmation = .none; next.lastError = problem; next.loading = .failed(problem); return CompassTransition(state: next, events: [.mutationValidation(.rejected)]) }
}

// MARK: - Resource table index

public enum ResourceSortKey: String, Codable, Hashable, Sendable { case name, namespace, status }
public struct ResourceTableIndex: Sendable {
    public let resources: [KubeResource]; private let ids: Set<String>
    public init(resources: [KubeResource]) { var seen = Set<String>(); var clean: [KubeResource] = []; clean.reserveCapacity(resources.count); for resource in resources where !resource.id.isEmpty && !resource.kindID.isEmpty && !resource.name.isEmpty { if seen.insert(resource.id).inserted { clean.append(resource) } }; self.resources = clean; self.ids = seen }
    public var count: Int { resources.count }
    public func filteredSorted(query: String = "", by key: ResourceSortKey = .name, ascending: Bool = true) -> [KubeResource] { let needle = CompassSanitizer.clean(query).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")); let filtered = needle.isEmpty ? resources : resources.filter { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).contains(needle) || $0.namespace?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).contains(needle) == true }; return filtered.sorted { lhs, rhs in let left = sortValue(lhs, key: key), right = sortValue(rhs, key: key); if left == right { return lhs.id < rhs.id }; return ascending ? left < right : left > right } }
    public func validSelection(_ selection: Set<String>) -> Set<String> { selection.filter { ids.contains($0) } }
    private func sortValue(_ resource: KubeResource, key: ResourceSortKey) -> String { let value: String; switch key { case .name: value = resource.name; case .namespace: value = resource.namespace ?? ""; case .status: value = resource.status }; return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
}

// MARK: - Logical kubectl argv

public struct KubectlCommand: Codable, Hashable, Sendable {
    public let argv: [String]; public let purpose: String; public let stdin: String?
    public init(argv: [String], purpose: String, stdin: String? = nil) { precondition(!argv.isEmpty && argv[0] == "kubectl"); self.argv = argv; self.purpose = purpose; self.stdin = stdin }
    /// Deliberately excludes argv so diagnostics cannot become shell-like or leak arguments.
    public var safeDescription: String { "kubectl operation=\(CompassSanitizer.clean(purpose)) argc=\(argv.count)" }
    public static func contexts(kubeconfig: String? = nil) -> KubectlCommand { KubectlCommand(argv: (kubeconfig.map { ["kubectl", "--kubeconfig", $0] } ?? ["kubectl"]) + ["config", "get-contexts", "--output", "name"], purpose: "list contexts") }
    public static func list(contextID: String, kind: ResourceKind, scope: ListWatchScope) throws -> KubectlCommand { KubectlCommand(argv: ["kubectl", "get", kind.id] + (try listScope(contextID, kind: kind, scope: scope)) + ["--output", "json"], purpose: "list resources") }
    public static func watch(contextID: String, kind: ResourceKind, scope: ListWatchScope) throws -> KubectlCommand { KubectlCommand(argv: ["kubectl", "get", kind.id] + (try listScope(contextID, kind: kind, scope: scope)) + ["--watch", "--output-watch-events", "--output", "json"], purpose: "watch resources") }
    public static func detail(contextID: String, kindID: String, resourceName: String, scope: ObjectScope) -> KubectlCommand { KubectlCommand(argv: ["kubectl", "get", kindID, resourceName] + objectScope(contextID, scope) + ["--output", "json"], purpose: "resource detail") }
    public static func logs(contextID: String, resourceName: String, scope: ObjectScope, container: String? = nil, tail: Int = 500) -> KubectlCommand { var argv = ["kubectl", "logs", resourceName] + objectScope(contextID, scope) + ["--tail", String(max(0, tail)), "--timestamps"]; if let container, !container.isEmpty { argv += ["--container", container] }; return KubectlCommand(argv: argv, purpose: "stream logs") }
    public static func portForward(contextID: String, targetKind: ResourceKind, targetName: String, scope: ObjectScope, localPort: Int, remotePort: Int) throws -> KubectlCommand { guard validName(targetName), (1...65535).contains(localPort), (1...65535).contains(remotePort) else { throw CommandError.invalidPortOrTarget }; switch (targetKind.namespaced, scope) { case (true, .cluster): throw CommandError.namespaceRequired; case (false, .namespaced): throw CommandError.invalidScope; case (true, .namespaced(let namespace)): guard validName(namespace) else { throw CommandError.namespaceRequired }; case (false, .cluster): break }; return KubectlCommand(argv: ["kubectl", "port-forward"] + objectScope(contextID, scope) + ["\(targetKind.id)/\(targetName)", "\(localPort):\(remotePort)", "--address", "127.0.0.1,::1"], purpose: "port forward") }
    public enum CommandError: Error, Equatable, Sendable { case invalidPortOrTarget; case namespaceRequired; case invalidScope; case invalidTarget }
    private static func listScope(_ contextID: String, kind: ResourceKind, scope: ListWatchScope) throws -> [String] { switch scope { case .current: return ["--context", contextID]; case .namespace(let ns): guard kind.namespaced, validName(ns) else { throw CommandError.invalidScope }; return ["--context", contextID, "--namespace", ns]; case .allNamespaces: guard kind.namespaced else { throw CommandError.invalidScope }; return ["--context", contextID, "--all-namespaces"] } }
    private static func objectScope(_ contextID: String, _ scope: ObjectScope) -> [String] { switch scope { case .namespaced(let ns): return ["--context", contextID, "--namespace", ns]; case .cluster: return ["--context", contextID] } }
    private static func validName(_ name: String) -> Bool { !name.isEmpty && !name.contains("/") && name.unicodeScalars.allSatisfy { $0.value >= 0x21 && $0.value < 0x7F } }
}

// MARK: - Deterministic fixtures and trace

public enum CompassFixtures {
    public static let contexts = [KubeContext(id: "dev", name: "dev", cluster: "dev-cluster", user: "dev-user", isCurrent: true, defaultNamespace: "default"), KubeContext(id: "prod", name: "prod", cluster: "prod-cluster", user: "prod-user")]
    public static let namespaces = ["default", "platform"]
    public static let kinds = [ResourceKind(id: "pods", displayName: "Pods", supportsDelete: true), ResourceKind(id: "deployments", displayName: "Deployments", supportsDelete: true)]
    public static let resources = [KubeResource(id: "pods/default/api-0", kindID: "pods", name: "api-0", namespace: "default", status: "Running", uid: "uid-api", resourceVersion: "rv-1"), KubeResource(id: "pods/default/web-0", kindID: "pods", name: "web-0", namespace: "default", status: "Running", uid: "uid-web", resourceVersion: "rv-2")]
    public static let logs = [LogLine(id: 1, text: "ready", stream: "stdout"), LogLine(id: 2, text: "request complete", stream: "stdout")]
}

public struct TraceStep: Codable, Hashable, Sendable { public let label: String; public let safeState: String; public let connectivity: ConnectivityState; public let loading: LoadingState; public let selectedContextID: String?; public let selectedNamespace: String?; public let selectedKindID: String?; public let selectedResourceID: String?; public let detailTab: DetailTab; public let resourceCount: Int; public let logCount: Int; public let effectCount: Int; public init(label: String, transition: CompassTransition) { let state = transition.state; self.label = label; self.safeState = state.safeDescription; self.connectivity = state.connectivity; self.loading = state.loading; self.selectedContextID = state.selectedContextID; self.selectedNamespace = state.selectedNamespace; self.selectedKindID = state.selectedKindID; self.selectedResourceID = state.selectedResourceID; self.detailTab = state.detailTab; self.resourceCount = state.resourcesByKind.values.reduce(0) { $0 + $1.count }; self.logCount = state.logs.count; self.effectCount = transition.effects.count } }
public enum CompassTrace { public static func run() -> [TraceStep] { var state = CompassState(); var steps: [TraceStep] = []; func apply(_ label: String, _ intent: CompassIntent) { let t = CompassReducer.reduce(state, intent); state = t.state; steps.append(TraceStep(label: label, transition: t)) }; apply("bootstrap", .bootstrap); apply("contexts", .contextsLoaded(CompassFixtures.contexts)); apply("context-dev", .selectContext("dev")); apply("namespace-list", .namespacesLoaded(CompassFixtures.namespaces)); apply("namespace-default", .selectNamespace("default")); state.resourceKinds = CompassFixtures.kinds; apply("kind-pods", .selectKind("pods")); apply("resource-list", .resourcesLoaded(kindID: "pods", resources: CompassFixtures.resources)); apply("resource-detail", .selectResource("pods/default/api-0")); apply("logs-tab", .selectDetailTab(.logs)); for line in CompassFixtures.logs { apply("log-\(line.id)", .appendLog(line)) }; apply("reconnect", .beginReconnect); apply("reconnect-failed", .finishReconnect(success: false)); apply("reconnect-again", .beginReconnect); apply("reconnect-success", .finishReconnect(success: true)); return steps } }
