import Foundation

/// The three platform-neutral surfaces used by the redesigned topology
/// explorer.  `map` is a bounded relationship view; it is not a traffic map.
public enum TopologyExplorerSurface: String, Codable, Hashable, Sendable, CaseIterable {
    case outline
    case map
    case paths
}

public enum TopologyExplorerSnapshotStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case ready
    case partial
    case unavailable
    case empty

    public var title: String {
        switch self {
        case .ready: return "Ready"
        case .partial: return "Partial"
        case .unavailable: return "Unavailable"
        case .empty: return "Empty"
        }
    }
}

/// Explicit, serializable filters shared by Outline, Map and Paths.  A filter
/// never creates a relationship: it only admits nodes/edges already present
/// in `TopologyGraph`.
public struct TopologyExplorerFilter: Codable, Hashable, Sendable {
    public let search: String?
    public let level: ExplorerLevel?
    public let namespace: String?
    public let kind: String?
    public let kinds: Set<String>
    public let evidence: TopologyEvidenceLevel?
    public let relationship: TopologyRelationship?
    public let unresolvedOnly: Bool

    public init(search: String? = nil, namespace: String? = nil, kind: String? = nil, kinds: Set<String> = [], evidence: TopologyEvidenceLevel? = nil, relationship: TopologyRelationship? = nil, unresolvedOnly: Bool = false, level: ExplorerLevel? = nil) {
        func clean(_ value: String?) -> String? {
            guard let value else { return nil }
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }
        self.search = clean(search)
        self.level = level
        self.namespace = clean(namespace)
        self.kind = clean(kind)
        self.kinds = Set(kinds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        self.evidence = evidence
        self.relationship = relationship
        self.unresolvedOnly = unresolvedOnly
    }

    public var isEmpty: Bool {
        search == nil && level == nil && namespace == nil && kind == nil && kinds.isEmpty && evidence == nil && relationship == nil && !unresolvedOnly
    }

    /// Text is a convenient spelling for adapters whose controls label the
    /// search field “Filter”.
    public var text: String? { search }
}

public typealias TopologyExplorerQuery = TopologyExplorerFilter

public struct TopologyExplorerBreadcrumb: Codable, Hashable, Sendable {
    public let segments: [String]
    public let contextID: String
    public let namespace: String?
    public let selectedRootID: String?

    public init(segments: [String], contextID: String, namespace: String? = nil, selectedRootID: String? = nil) {
        self.segments = segments
        self.contextID = contextID
        self.namespace = namespace
        self.selectedRootID = selectedRootID
    }
}

/// A safe, compact node projection for native adapters.  It deliberately
/// retains no raw Kubernetes payloads; the original typed graph node remains
/// available through `node` when an inspector needs evidence.
public struct TopologyExplorerNodeSummary: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String
    public let namespace: String?
    public let evidence: TopologyEvidenceLevel
    public let isVirtual: Bool
    public let node: TopologyNode

    public init(node: TopologyNode) {
        self.id = node.id
        self.kind = node.kind
        self.name = node.name
        self.namespace = node.namespace
        self.evidence = node.evidence.level
        self.isVirtual = node.isVirtual
        self.node = node
    }
}

public struct TopologyOutlineController: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let primary: TopologyExplorerNodeSummary
    public let dependents: [TopologyExplorerNodeSummary]
    public let related: [TopologyExplorerNodeSummary]

    public init(primary: TopologyExplorerNodeSummary, dependents: [TopologyExplorerNodeSummary] = [], related: [TopologyExplorerNodeSummary] = []) {
        self.id = primary.id
        self.primary = primary
        self.dependents = dependents
        self.related = related
    }

    public var primaryWorkload: TopologyExplorerNodeSummary { primary }
}

public struct TopologyOutlineNamespace: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let namespace: String
    public let controllers: [TopologyOutlineController]
    public let unattached: [TopologyExplorerNodeSummary]

    public init(namespace: String, controllers: [TopologyOutlineController] = [], unattached: [TopologyExplorerNodeSummary] = []) {
        self.id = namespace
        self.namespace = namespace
        self.controllers = controllers
        self.unattached = unattached
    }

    /// Alias useful to adapters that call the second outline tier “groups”.
    public var groups: [TopologyOutlineController] { controllers }
}

public struct TopologyExplorerMap: Codable, Hashable, Sendable {
    public let rootID: String
    public let maxHops: Int
    public let nodes: [TopologyExplorerNodeSummary]
    public let edges: [TopologyEdge]
    public let totalNodeCount: Int
    public let isTruncated: Bool
    public let omittedNodeCount: Int

    public init(rootID: String, maxHops: Int, nodes: [TopologyExplorerNodeSummary], edges: [TopologyEdge], totalNodeCount: Int? = nil, isTruncated: Bool? = nil, omittedNodeCount: Int? = nil) {
        self.rootID = rootID
        self.maxHops = maxHops
        self.nodes = nodes
        self.edges = edges
        let total = max(nodes.count, totalNodeCount ?? nodes.count)
        let omitted = max(0, omittedNodeCount ?? (total - nodes.count))
        self.totalNodeCount = total
        self.isTruncated = isTruncated ?? (omitted > 0)
        self.omittedNodeCount = omitted
    }

    public var hopLimit: Int { maxHops }
}

public struct TopologyExplorerPathDiagnostic: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let source: TopologyObjectReference
    public let status: TopologyPortPathStatus
    public let hops: [TopologyPortHop]
    public let note: String?
    public let isTruncated: Bool
    public let path: TopologyPortPath

    public init(path: TopologyPortPath) {
        self.id = path.id
        self.source = path.source
        self.status = path.status
        self.hops = path.hops
        self.note = path.note
        self.isTruncated = path.isTruncated
        self.path = path
    }

    public var summary: String {
        let endpointCount = "\(path.readyEndpointCount)/\(path.totalEndpointCount) ready endpoints"
        return "\(source.kind) \(source.name) · \(status.rawValue) · \(endpointCount)"
    }
}

/// Deterministic presentation model for the redesigned topology route.
///
/// Outline is the default surface and groups resources as
/// namespace → primary workload/controller → dependents.  Map is selected-root
/// only and capped at one or two graph hops.  Paths exposes typed
/// `TopologyPortPath` diagnostics.  None of these surfaces model traffic or
/// reachability.
public struct TopologyExplorerPresentation: Codable, Hashable, Sendable {
    public let surface: TopologyExplorerSurface
    public let title: String
    public let scopeSummary: String
    public let status: TopologyExplorerSnapshotStatus
    public let statusSummary: String
    public let breadcrumb: TopologyExplorerBreadcrumb
    public let filter: TopologyExplorerFilter
    public let selectedRootID: String?
    public let outline: [TopologyOutlineNamespace]
    public let map: TopologyExplorerMap?
    public let paths: [TopologyExplorerPathDiagnostic]

    public init(graph: TopologyGraph, surface: TopologyExplorerSurface = .outline, selectedRootID: String? = nil, filter: TopologyExplorerFilter = TopologyExplorerFilter(), maxHops: Int = 1) {
        let builder = TopologyExplorerPresentationBuilder(graph: graph, filter: filter, selectedRootID: selectedRootID, maxHops: maxHops)
        let result = builder.build(surface: surface)
        self = result
    }

    public static func build(graph: TopologyGraph, surface: TopologyExplorerSurface = .outline, selectedRootID: String? = nil, filter: TopologyExplorerFilter = TopologyExplorerFilter(), maxHops: Int = 1) -> TopologyExplorerPresentation {
        TopologyExplorerPresentation(graph: graph, surface: surface, selectedRootID: selectedRootID, filter: filter, maxHops: maxHops)
    }

    public var view: TopologyExplorerSurface { surface }
}

public typealias TopologyExplorerViewModel = TopologyExplorerPresentation

private var presentationBuildCancelled: Bool {
#if os(macOS)
    if #available(macOS 10.15, *) { return Task.isCancelled }
    return false
#else
    return Task.isCancelled
#endif
}

private struct TopologyExplorerPresentationBuilder {
    private static let mapNodeLimit = 180
    let graph: TopologyGraph
    let filter: TopologyExplorerFilter
    let selectedRootID: String?
    let maxHops: Int
    private let nodeByID: [String: TopologyNode]
    private let edgesByNodeID: [String: [TopologyEdge]]

    private var query: TopologyGraphQuery { TopologyGraphQuery(graph: graph) }

    init(graph: TopologyGraph, filter: TopologyExplorerFilter, selectedRootID: String?, maxHops: Int) {
        self.graph = graph
        self.filter = filter
        self.selectedRootID = selectedRootID
        self.maxHops = maxHops
        self.nodeByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var adjacency: [String: [TopologyEdge]] = [:]
        adjacency.reserveCapacity(graph.nodes.count)
        for edge in graph.edges.sorted(by: { $0.id < $1.id }) {
            adjacency[edge.from, default: []].append(edge)
            adjacency[edge.to, default: []].append(edge)
        }
        self.edgesByNodeID = adjacency
    }

    func build(surface: TopologyExplorerSurface) -> TopologyExplorerPresentation {
        let nodes = filteredNodes()
        let visibleIDs = Set(nodes.map(\.id))
        let root: TopologyNode? = selectedRootID.flatMap { id in
            guard visibleIDs.contains(id) else { return nil }
            return nodeByID[id]
        }
        let namespace = root?.namespace ?? filter.namespace
        let scope = namespace ?? "All namespaces"
        let status = snapshotStatus(nodes: nodes)
        let title = root.map { "Topology · \($0.kind) \($0.name)" } ?? "Topology Explorer"
        let breadcrumbSegments = ["Cluster", graph.contextID, namespace, root?.name].compactMap { $0 }
        let breadcrumb = TopologyExplorerBreadcrumb(segments: breadcrumbSegments, contextID: graph.contextID, namespace: namespace, selectedRootID: root?.id)
        // Outline materializes the expensive hierarchy only when active. Map
        // and Paths intentionally leave inactive payloads empty/nil so a
        // scoped diagnostic never pays for cluster-wide outline assembly.
        let outline = surface == .outline ? makeOutline(nodes: nodes, visibleIDs: visibleIDs) : []
        let map = surface == .map ? root.map { makeMap(root: $0, visibleIDs: visibleIDs) } : nil
        let paths = surface == .paths ? makePaths(root: root) : []
        let resourceCount = nodes.count
        let relationshipCount = graph.edges.filter { visibleIDs.contains($0.from) && visibleIDs.contains($0.to) }.count
        let statusSummary = "\(status.title) · \(resourceCount) resources · \(relationshipCount) typed relationships"
        return TopologyExplorerPresentation(surface: surface, title: title, scopeSummary: scope, status: status, statusSummary: statusSummary, breadcrumb: breadcrumb, filter: filter, selectedRootID: root?.id, outline: outline, map: map, paths: paths)
    }

    private func snapshotStatus(nodes: [TopologyNode]) -> TopologyExplorerSnapshotStatus {
        if graph.completeness == .unavailable { return .unavailable }
        if graph.completeness == .partial { return .partial }
        if nodes.isEmpty { return .empty }
        return .ready
    }

    private func filteredNodes() -> [TopologyNode] {
        guard !presentationBuildCancelled else { return [] }
        var result = query.nodes(level: filter.level, search: filter.search, kind: filter.kind, namespace: filter.namespace, evidence: filter.evidence)
        if !filter.kinds.isEmpty {
            result = result.filter { filter.kinds.contains($0.kind.lowercased()) }
        }
        if filter.unresolvedOnly {
            let unresolvedIDs = Set(graph.unresolvedReferences.compactMap(\.sourceNodeID))
            result = result.filter { unresolvedIDs.contains($0.id) || $0.evidence.level == .unavailable }
        }
        if let relationship = filter.relationship {
            result = result.filter { node in
                edgesByNodeID[node.id, default: []].contains { $0.relationship == relationship }
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    private func makeOutline(nodes: [TopologyNode], visibleIDs: Set<String>) -> [TopologyOutlineNamespace] {
        guard !presentationBuildCancelled else { return [] }
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        func scope(for node: TopologyNode) -> String {
            node.namespace ?? ((node.kind.lowercased() == "namespace") ? node.name : "Cluster")
        }
        let nodesByScope = Dictionary(grouping: nodes, by: scope)
        let names = Set(nodesByScope.keys)
        let controllers = nodes.filter { Self.isPrimaryKind($0.kind) && isPrimary($0, visibleIDs: visibleIDs) }
        let controllerIDs = Set(controllers.map(\.id))
        let controllersByScope = Dictionary(grouping: controllers, by: scope)

        // Related resources (Service, Ingress, PVC, config, HPA) can be
        // shared by many ownerless Pods. Compute connected components of the
        // related-only subgraph once, then attach a component to the first
        // primary whose lineage touches it. This avoids repeating a related
        // BFS for every primary while preserving all typed edges in Map.
        var relatedComponents: [String: Set<String>] = [:]
        var visitedRelated = Set<String>()
        for relatedNode in nodes where Self.isRelatedKind(relatedNode.kind) {
            if presentationBuildCancelled { return [] }
            guard visibleIDs.contains(relatedNode.id), !visitedRelated.contains(relatedNode.id) else { continue }
            var component: Set<String> = [relatedNode.id]
            var queue = [relatedNode.id]
            var head = 0
            visitedRelated.insert(relatedNode.id)
            while head < queue.count {
                if presentationBuildCancelled { return [] }
                let source = queue[head]
                head += 1
                for edge in edgesByNodeID[source] ?? [] {
                    guard visibleIDs.contains(edge.from), visibleIDs.contains(edge.to) else { continue }
                    let target = edge.from == source ? edge.to : edge.to == source ? edge.from : nil
                    guard let target, let targetNode = nodeByID[target], Self.isRelatedKind(targetNode.kind), visitedRelated.insert(target).inserted else { continue }
                    component.insert(target)
                    queue.append(target)
                }
            }
            for id in component { relatedComponents[id] = component }
        }

        return names.sorted().map { namespace in
            if presentationBuildCancelled { return TopologyOutlineNamespace(namespace: namespace) }
            let scopedControllers = (controllersByScope[namespace] ?? []).sorted { $0.id < $1.id }
            let scopedNodes = nodesByScope[namespace] ?? []
            var assigned = Set<String>()
            var claimedRelated = Set<String>()
            let groups = scopedControllers.map { controller in
                let lineage = lineageIDs(from: controller.id, visibleIDs: visibleIDs)
                assigned.formUnion(lineage)
                let dependents = lineage.subtracting([controller.id]).compactMap { nodesByID[$0] }.filter { !Self.isRelatedKind($0.kind) }.sorted { $0.id < $1.id }.map(TopologyExplorerNodeSummary.init)
                // A Service may select Pods belonging to several ownerless
                // primaries. Keep one deterministic Outline placement (the
                // lexicographically first primary) while Map/inspector still
                // exposes every typed edge and therefore the many-to-many
                // relationship truth.
                var touchedComponents = Set<String>()
                for lineageID in lineage {
                    for edge in edgesByNodeID[lineageID] ?? [] {
                        guard visibleIDs.contains(edge.from), visibleIDs.contains(edge.to) else { continue }
                        let target = edge.from == lineageID ? edge.to : edge.to == lineageID ? edge.from : nil
                        guard let target, let targetNode = nodeByID[target], Self.isRelatedKind(targetNode.kind) else { continue }
                        touchedComponents.insert(target)
                    }
                }
                let relatedIDs = touchedComponents.flatMap { relatedComponents[$0] ?? [$0] }
                let related = Set(relatedIDs)
                    .subtracting(lineage)
                    .subtracting(claimedRelated)
                    .compactMap { nodesByID[$0] }
                    .sorted { $0.id < $1.id }
                    .map(TopologyExplorerNodeSummary.init)
                claimedRelated.formUnion(related.map(\.id))
                assigned.formUnion(related.map(\.id))
                return TopologyOutlineController(primary: TopologyExplorerNodeSummary(node: controller), dependents: dependents, related: related)
            }
            let unattached = scopedNodes.filter { node in
                !assigned.contains(node.id) && !controllerIDs.contains(node.id)
            }.sorted { $0.id < $1.id }.map(TopologyExplorerNodeSummary.init)
            return TopologyOutlineNamespace(namespace: namespace, controllers: groups, unattached: unattached)
        }
    }

    private func isPrimary(_ node: TopologyNode, visibleIDs: Set<String>) -> Bool {
        !(edgesByNodeID[node.id] ?? []).contains { edge in
            edge.relationship == .ownedBy && edge.from == node.id && visibleIDs.contains(edge.to)
        }
    }

    private func lineageIDs(from rootID: String, visibleIDs: Set<String>) -> Set<String> {
        var ids: Set<String> = [rootID]
        var queue = [rootID]
        var head = 0
        while head < queue.count {
            if presentationBuildCancelled { return [] }
            let source = queue[head]
            head += 1
            for edge in edgesByNodeID[source] ?? [] {
                guard visibleIDs.contains(edge.from), visibleIDs.contains(edge.to) else { continue }
                let candidate: String?
                switch edge.relationship {
                case .ownedBy where edge.to == source: candidate = edge.from
                case .ownedBy where edge.from == source: candidate = edge.to
                case .selects where edge.from == source: candidate = edge.to
                default: candidate = nil
                }
                if let candidate, ids.insert(candidate).inserted { queue.append(candidate) }
            }
        }
        return ids
    }

    private func relatedIDs(lineage: Set<String>, visibleIDs: Set<String>) -> Set<String> {
        var related: Set<String> = []
        var frontier = Array(lineage).sorted()
        var visited = lineage
        var head = 0
        while head < frontier.count {
            let source = frontier[head]
            head += 1
            for edge in edgesByNodeID[source] ?? [] {
                guard visibleIDs.contains(edge.from), visibleIDs.contains(edge.to) else { continue }
                let target = edge.from == source ? edge.to : (edge.to == source ? edge.from : nil)
                guard let target, let node = nodeByID[target], Self.isRelatedKind(node.kind), !visited.contains(target) else { continue }
                visited.insert(target)
                related.insert(target)
                frontier.append(target)
            }
        }
        return related
    }

    private func makeMap(root: TopologyNode, visibleIDs: Set<String>) -> TopologyExplorerMap {
        let bound = min(2, max(1, maxHops))
        var distances: [String: Int] = [root.id: 0]
        var frontier = [root.id]
        var head = 0
        while head < frontier.count {
            if presentationBuildCancelled { break }
            let source = frontier[head]
            head += 1
            guard let distance = distances[source], distance < bound else { continue }
            for edge in edgesByNodeID[source] ?? [] where edge.relationship != .containedIn && visibleIDs.contains(edge.from) && visibleIDs.contains(edge.to) {
                let target = edge.from == source ? edge.to : edge.from
                if distances[target] == nil { distances[target] = distance + 1; frontier.append(target) }
            }
        }
        let ids = Set(distances.keys)
        let orderedIDs = [root.id] + ids.filter { $0 != root.id }.sorted()
        let retainedIDs = Set(orderedIDs.prefix(Self.mapNodeLimit))
        let mapNodes = orderedIDs.prefix(Self.mapNodeLimit).compactMap { nodeByID[$0] }.map(TopologyExplorerNodeSummary.init)
        let mapEdges = retainedIDs.flatMap { edgesByNodeID[$0] ?? [] }
            .filter { $0.relationship != .containedIn && retainedIDs.contains($0.from) && retainedIDs.contains($0.to) }
            .reduce(into: [:]) { $0[$1.id] = $1 }.values.sorted { $0.id < $1.id }
        return TopologyExplorerMap(rootID: root.id, maxHops: bound, nodes: mapNodes, edges: Array(mapEdges), totalNodeCount: ids.count, isTruncated: ids.count > mapNodes.count, omittedNodeCount: ids.count - mapNodes.count)
    }

    private func makePaths(root: TopologyNode?) -> [TopologyExplorerPathDiagnostic] {
        guard !presentationBuildCancelled else { return [] }
        return graph.portPaths.filter { path in
            guard !presentationBuildCancelled else { return false }
            guard let root else { return true }
            return reference(path.source, matches: root)
        }.filter { path in
            if let namespace = filter.namespace, path.source.namespace != namespace { return false }
            if let level = filter.level, TopologyGraphQuery.level(for: path.source.kind) != level { return false }
            if let kind = filter.kind, path.source.kind.caseInsensitiveCompare(kind) != .orderedSame { return false }
            if !filter.kinds.isEmpty && !filter.kinds.contains(path.source.kind.lowercased()) { return false }
            if filter.unresolvedOnly && ![.partial, .unresolved, .noEndpoint, .noReadyEndpoint].contains(path.status) { return false }
            if let evidence = filter.evidence {
                let levels = path.hops.map(\.evidence.level) + path.provenance.map(\.level)
                if !levels.contains(evidence) { return false }
            }
            guard let search = filter.search?.lowercased() else { return true }
            var terms = [path.source.kind, path.source.name, path.source.namespace ?? "", path.status.rawValue, path.note ?? ""]
            terms.append(contentsOf: path.hops.flatMap { hop -> [String] in
                [hop.role, hop.portName ?? "", hop.portNumber.map(String.init) ?? "", hop.protocolName ?? "", hop.containerName ?? "", hop.reference?.kind ?? "", hop.reference?.name ?? "", hop.reference?.namespace ?? ""]
            })
            return terms.joined(separator: " ").lowercased().contains(search)
        }.sorted { $0.id < $1.id }.map(TopologyExplorerPathDiagnostic.init)
    }

    private func reference(_ reference: TopologyObjectReference, matches node: TopologyNode) -> Bool {
        if let uid = reference.uid, let nodeUID = node.uid { return uid == nodeUID }
        return reference.kind.caseInsensitiveCompare(node.kind) == .orderedSame && reference.name == node.name && reference.namespace == node.namespace
    }

    private static func isPrimaryKind(_ kind: String) -> Bool {
        ["deployment", "statefulset", "daemonset", "replicaset", "job", "cronjob", "pod"].contains(kind.lowercased())
    }

    private static func isRelatedKind(_ kind: String) -> Bool {
        let normalized = kind.lowercased()
        return normalized == "service" || normalized == "ingress" || normalized == "persistentvolumeclaim" || normalized == "hpa" || normalized == "horizontalpodautoscaler" || normalized == "configmap" || normalized == "secret"
    }
}

private extension TopologyExplorerPresentation {
    init(surface: TopologyExplorerSurface, title: String, scopeSummary: String, status: TopologyExplorerSnapshotStatus, statusSummary: String, breadcrumb: TopologyExplorerBreadcrumb, filter: TopologyExplorerFilter, selectedRootID: String?, outline: [TopologyOutlineNamespace], map: TopologyExplorerMap?, paths: [TopologyExplorerPathDiagnostic]) {
        self.surface = surface
        self.title = title
        self.scopeSummary = scopeSummary
        self.status = status
        self.statusSummary = statusSummary
        self.breadcrumb = breadcrumb
        self.filter = filter
        self.selectedRootID = selectedRootID
        self.outline = outline
        self.map = map
        self.paths = paths
    }
}
