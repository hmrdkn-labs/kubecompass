import SwiftUI
import KubeCompassCore

/// Evidence-aware, read-only cluster map. It visualizes API observations and
/// declarations; it never claims packet flow or network reachability.
struct TopologyExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .map
    @State private var query = ""
    @State private var showPolicies = true

    private enum Mode: String, CaseIterable, Identifiable {
        case map = "Map"
        case list = "List"
        var id: String { rawValue }
    }

    private enum ListSelection: Hashable {
        case node(String)
        case edge(String)
    }

    private var graph: TopologyGraph? { model.topologyGraph }
    private var filteredNodes: [TopologyNode] {
        guard let graph else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return graph.nodes.filter { node in
            let kind = node.kind.lowercased()
            if !showPolicies && kind == "networkpolicy" { return false }
            guard !q.isEmpty else { return true }
            return node.name.lowercased().contains(q) || kind.contains(q) || (node.namespace?.lowercased().contains(q) == true)
        }.sorted { lane(for: $0) == lane(for: $1) ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lane(for: $0) < lane(for: $1) }
    }

    private var filteredEdges: [TopologyEdge] {
        guard let graph else { return [] }
        let visible = Set(filteredNodes.map(\.id))
        return graph.edges.filter { visible.contains($0.from) && visible.contains($0.to) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let graph, graph.nodes.contains(where: { !$0.isVirtual }) {
                completenessBanner(graph)
                if let error = model.topologyError { staleBanner(error) }
                if model.topologyIsBuilding { ProgressView("Refreshing topology evidence…").padding(.vertical, 8) }
                HStack(spacing: 0) {
                    if mode == .map { map(graph) } else { relationshipList(graph) }
                    Divider()
                    inspector(graph).frame(minWidth: 260, idealWidth: 290, maxWidth: 340)
                }
            } else if model.topologyIsBuilding || model.isLoading {
                ContentUnavailableView("Building topology", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Reading safe metadata through kubectl. No changes are made to the cluster."))
            } else {
                let unavailable = graph?.inputs.filter { $0.availability != .available } ?? []
                let title = unavailable.contains { $0.availability == .forbidden }
                    ? "Topology access denied"
                    : (unavailable.isEmpty ? "No topology resources" : "Topology unavailable")
                let details = unavailable.map { "\($0.resourceKind): \($0.message ?? $0.availability.rawValue)" }.joined(separator: " · ")
                ContentUnavailableView(
                    title,
                    systemImage: unavailable.isEmpty ? "point.3.connected.trianglepath.dotted" : "exclamationmark.triangle",
                    description: Text(model.topologyError ?? (details.isEmpty ? "Choose another namespace or refresh." : details))
                )
            }
        }
        .task {
            if model.sidebarSelection == .topology,
               model.topologyGraph == nil,
               !model.topologyIsBuilding {
                model.requestRefresh()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                Label("Topology Explorer", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.title3.weight(.semibold))
                Text(model.selectedContext)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button { model.requestRefresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.topologyIsBuilding)
            }
            HStack(spacing: 12) {
                NamespacePicker()
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)
                TextField("Find resource, kind, or namespace", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Toggle("Policies", isOn: $showPolicies)
                    .toggleStyle(.checkbox)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private func staleBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption.weight(.medium))
            Spacer()
            Button("Retry") { model.requestRefresh() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.1))
    }

    private func completenessBanner(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: graph.completeness == .complete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(graph.completeness == .complete ? .green : .orange)
                Text(graph.completeness == .complete ? "Complete for requested API inputs" : "Partial API snapshot — unavailable inputs are shown explicitly")
                    .font(.caption.weight(.medium))
                if let time = model.lastTopologyAt {
                    Text("Updated \(Fmt.age(time, relativeTo: Date()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(filteredNodes.count) nodes · \(filteredEdges.count) relationships")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Text("Evidence")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                evidenceBadge(.observed)
                evidenceBadge(.declared)
                evidenceBadge(.inferred)
                evidenceBadge(.unavailable)
            }
            let unavailable = graph.inputs.filter { $0.availability != .available }
            if !unavailable.isEmpty {
                Text(unavailable.map { "\($0.resourceKind): \($0.message ?? $0.availability.rawValue)" }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35))
    }

    private func map(_ graph: TopologyGraph) -> some View {
        let nodes = Array(filteredNodes.prefix(240))
        let lanes = Dictionary(grouping: nodes, by: lane)
        let columnWidth: CGFloat = 220
        let rowHeight: CGFloat = 76
        let maxRows = max(1, lanes.values.map(\.count).max() ?? 1)
        let height = CGFloat(maxRows) * rowHeight + 50
        let positions = nodePositions(nodes: nodes, columnWidth: columnWidth, rowHeight: rowHeight)
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in filteredEdges {
                        guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
                        var path = Path(); path.move(to: CGPoint(x: from.x + 180, y: from.y + 30)); path.addLine(to: CGPoint(x: to.x, y: to.y + 30))
                        let style = edgeStyle(edge.evidence.level)
                        context.stroke(path, with: .color(style.color.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5, dash: style.dash))
                    }
                }.frame(width: CGFloat((lanes.keys.max() ?? 0) + 1) * columnWidth, height: height)
                ForEach(Array(lanes.keys.sorted()), id: \.self) { index in
                    Text(laneTitle(index)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).position(x: CGFloat(index) * columnWidth + 90, y: 18)
                }
                if filteredNodes.count > nodes.count { Text("Map capped at \(nodes.count) nodes; use search or List for the remainder.").font(.caption).foregroundStyle(.orange).padding(.horizontal, 8) }
                ForEach(nodes) { node in
                    if let point = positions[node.id] {
                        Button { model.selectedTopologyNodeID = node.id; model.selectedTopologyEdgeID = nil } label: { nodeCard(node) }.buttonStyle(.plain).position(x: point.x + 90, y: point.y + 48).accessibilityLabel("\(node.kind) \(node.name)").accessibilityHint("Shows safe facts and adjacent relationships")
                    }
                }
            }.frame(width: max(680, CGFloat((lanes.keys.max() ?? 0) + 1) * columnWidth), height: height).padding(28)
        }
    }

    private func relationshipList(_ graph: TopologyGraph) -> some View {
        List(selection: Binding<ListSelection?>(
            get: {
                if let id = model.selectedTopologyNodeID { return .node(id) }
                if let id = model.selectedTopologyEdgeID { return .edge(id) }
                return nil
            },
            set: { selection in
                switch selection {
                case .node(let id):
                    model.selectedTopologyNodeID = id
                    model.selectedTopologyEdgeID = nil
                case .edge(let id):
                    model.selectedTopologyEdgeID = id
                    model.selectedTopologyNodeID = nil
                case nil:
                    model.selectedTopologyNodeID = nil
                    model.selectedTopologyEdgeID = nil
                }
            }
        )) {
            Section("Nodes") {
                ForEach(filteredNodes.prefix(240)) { node in
                    HStack {
                        Image(systemName: icon(for: node.kind)).foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(node.name)
                            Text(node.kind + (node.namespace.map { " · \($0)" } ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        evidenceBadge(node.evidence.level)
                    }
                    .tag(ListSelection.node(node.id))
                }
                if filteredNodes.count > 240 {
                    Text("Showing 240 of \(filteredNodes.count) nodes. Refine the search to inspect the remainder.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section("Relationships") {
                ForEach(filteredEdges.prefix(500)) { edge in
                    let from = graph.nodes.first { $0.id == edge.from }
                    let to = graph.nodes.first { $0.id == edge.to }
                    HStack {
                        Text(from?.name ?? "Unknown")
                        Image(systemName: "arrow.right")
                        Text(to?.name ?? "Unknown")
                        Spacer()
                        Text(relationshipTitle(edge.relationship)).font(.caption)
                        evidenceBadge(edge.evidence.level)
                    }
                    .tag(ListSelection.edge(edge.id))
                }
                if filteredEdges.count > 500 {
                    Text("Showing 500 of \(filteredEdges.count) relationships. Refine the search to inspect the remainder.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }.frame(minWidth: 460)
    }

    private func inspector(_ graph: TopologyGraph) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let id = model.selectedTopologyNodeID, let node = graph.nodes.first(where: { $0.id == id }) {
                    Text(node.name).font(.title3.weight(.semibold))
                    Text("\(node.kind)\(node.namespace.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                    evidenceDetail(node.evidence)
                    if let kind = resourceKind(for: node), !node.isVirtual {
                        Button("Show in Resources") {
                            model.jumpTo(kind: kind, namespace: node.namespace ?? "", name: node.name)
                        }
                    }
                    factsSection(node.facts)
                    adjacent(node, graph: graph)
                } else if let id = model.selectedTopologyEdgeID, let edge = graph.edges.first(where: { $0.id == id }) {
                    let from = graph.nodes.first { $0.id == edge.from }
                    let to = graph.nodes.first { $0.id == edge.to }
                    Text(relationshipTitle(edge.relationship)).font(.title3.weight(.semibold))
                    Text("\(from?.name ?? "Unknown") → \(to?.name ?? "Unknown")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    evidenceDetail(edge.evidence)
                    if !edge.attributes.isEmpty {
                        factsSection(edge.attributes.map { TopologyFact(key: $0.key, title: $0.key, value: $0.value) })
                    }
                } else {
                    Text("Select an item").font(.title3.weight(.semibold)); Text("Click a node or relationship to inspect evidence, safe facts, and unresolved references.").foregroundStyle(.secondary)
                    if !graph.unresolvedReferences.isEmpty {
                        Text("\(graph.unresolvedReferences.count) unresolved or unavailable references").font(.caption.weight(.medium))
                        ForEach(graph.unresolvedReferences.prefix(30)) { unresolved in
                            VStack(alignment: .leading, spacing: 3) { Text(relationshipTitle(unresolved.relation)).font(.caption); Text(unresolved.reason).font(.caption2).foregroundStyle(.secondary); evidenceBadge(unresolved.evidence.level) }
                        }
                        if graph.unresolvedReferences.count > 30 {
                            Text("Showing 30 of \(graph.unresolvedReferences.count). Use search or inspect a related node for more context.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.background(.background)
    }

    private func adjacent(_ node: TopologyNode, graph: TopologyGraph) -> some View {
        let edges = graph.edges.filter { $0.from == node.id || $0.to == node.id }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Adjacent relationships").font(.headline)
            if edges.isEmpty { Text("None in this snapshot").font(.caption).foregroundStyle(.secondary) }
            ForEach(edges.prefix(30)) { edge in
                let target = graph.nodes.first { $0.id == (edge.from == node.id ? edge.to : edge.from) }
                Button { model.selectedTopologyEdgeID = edge.id; model.selectedTopologyNodeID = nil } label: { HStack { Text(relationshipTitle(edge.relationship)); Text(target?.name ?? "Unresolved").foregroundStyle(.secondary); Spacer(); evidenceBadge(edge.evidence.level) } }.buttonStyle(.plain)
            }
            if edges.count > 30 {
                Text("Showing 30 of \(edges.count) adjacent relationships.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func factsSection(_ facts: [TopologyFact]) -> some View { VStack(alignment: .leading, spacing: 6) { Text("Safe facts").font(.headline); ForEach(facts) { fact in HStack { Text(fact.title); Spacer(); Text(fact.value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }.font(.caption) } } }
    private func resourceKind(for node: TopologyNode) -> ResourceKind? { model.kindCatalog.first { $0.kindName.caseInsensitiveCompare(node.kind) == .orderedSame && $0.defaultAPIVersion == node.apiVersion } ?? model.kindCatalog.first { $0.kindName.caseInsensitiveCompare(node.kind) == .orderedSame } }
    private func evidenceDetail(_ evidence: TopologyEvidence) -> some View { VStack(alignment: .leading, spacing: 4) { evidenceBadge(evidence.level); Text(evidence.source.note ?? evidence.source.sourceField ?? "Kubernetes API evidence").font(.caption).foregroundStyle(.secondary); if let join = evidence.source.joinRule { Text("Join: \(join)").font(.caption2).foregroundStyle(.secondary) }; if let assumption = evidence.source.assumption { Text("Assumption: \(assumption)").font(.caption2).foregroundStyle(.orange) } } }
    private func evidenceBadge(_ level: TopologyEvidenceLevel) -> some View { Text(level.rawValue.capitalized).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 3).background(levelColor(level).opacity(0.16), in: Capsule()).foregroundStyle(levelColor(level)) }
    private func nodeCard(_ node: TopologyNode) -> some View { HStack(spacing: 8) { Image(systemName: icon(for: node.kind)).foregroundStyle(levelColor(node.evidence.level)); VStack(alignment: .leading, spacing: 2) { Text(node.name).lineLimit(1); Text(node.kind).font(.caption2).foregroundStyle(.secondary); if let ns = node.namespace { Text(ns).font(.caption2).foregroundStyle(.tertiary) } }; Spacer() }.padding(10).frame(width: 180, height: 60, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(levelColor(node.evidence.level).opacity(0.45))) }
    private func lane(for node: TopologyNode) -> Int { let kind = node.kind.lowercased(); if kind.contains("ingress") { return 0 }; if kind == "service" || kind == "endpointslice" { return 1 }; if ["deployment", "statefulset", "daemonset", "replicaset", "job", "cronjob"].contains(kind) { return 2 }; if kind == "pod" { return 3 }; if kind == "node" || node.isVirtual { return 4 }; if kind == "networkpolicy" { return 5 }; if ["persistentvolumeclaim", "persistentvolume", "storageclass"].contains(kind) { return 6 }; return 7 }
    private func laneTitle(_ lane: Int) -> String { ["Ingress", "Services", "Workloads", "Pods", "Nodes", "Policy", "Storage", "Scope / other"][min(lane, 7)] }
    private func nodePositions(nodes: [TopologyNode], columnWidth: CGFloat, rowHeight: CGFloat) -> [String: CGPoint] { Dictionary(nodes.enumerated().map { index, node in let laneIndex = lane(for: node); let row = nodes[..<index].filter { lane(for: $0) == laneIndex }.count; return (node.id, CGPoint(x: CGFloat(laneIndex) * columnWidth, y: CGFloat(row) * rowHeight + 28)) }, uniquingKeysWith: { first, _ in first }) }
    private func icon(for kind: String) -> String { switch kind.lowercased() { case "pod": return "circle.fill"; case "node": return "server.rack"; case "service": return "network"; case "ingress": return "arrow.triangle.branch"; case "networkpolicy": return "lock.shield"; default: return "cube" } }
    private func relationshipTitle(_ relationship: TopologyRelationship) -> String { switch relationship { case .containedIn: return "Contained in"; case .ownedBy: return "Owned by"; case .scheduledOn: return "Scheduled on"; case .selects: return "Selects"; case .publishesEndpoints: return "Publishes endpoints"; case .endpointTarget: return "Endpoint target"; case .routesTo: return "Declared route to"; case .references: return "References"; case .backedBy: return "Backed by"; case .usesStorageClass: return "Uses storage class"; case .inputUnavailable: return "Input unavailable" } }
    private func levelColor(_ level: TopologyEvidenceLevel) -> Color { switch level { case .observed: return .green; case .declared: return .blue; case .inferred: return .orange; case .unavailable: return .secondary } }
    private func edgeStyle(_ level: TopologyEvidenceLevel) -> (color: Color, dash: [CGFloat]) { (levelColor(level), level == .inferred ? [5, 4] : level == .unavailable ? [2, 4] : []) }
}
