import SwiftUI
import KubeCompassCore

/// Read-only, evidence-aware cluster exploration. The view deliberately
/// presents a semantic level at a time instead of drawing one undifferentiated
/// resource graph. It never claims packet reachability or executes actions.
struct TopologyExplorerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var inspectorTab: InspectorTab = .fundamentals
    @State private var mapVisibleLimit = 180
    private let mapPageSize = 180

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case fundamentals = "Fundamentals"
        case status = "Status"
        case ports = "Ports & Endpoints"
        case relationships = "Relationships"
        case evidence = "Evidence"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    private var graph: TopologyGraph? { model.topologyGraph }

    private var query: TopologyGraphQuery? {
        graph.map(TopologyGraphQuery.init(graph:))
    }

    private var levelForQuery: ExplorerLevel? {
        switch model.topologyExplorerLevel {
        case .cluster: return .cluster
        case .evidence: return nil
        case .infrastructure, .workloads, .network, .policyDependencies: return model.topologyExplorerLevel
        }
    }

    private var namespaceForLevel: String? {
        switch model.topologyExplorerLevel {
        case .cluster, .infrastructure, .evidence: return nil
        case .workloads, .network, .policyDependencies: return model.selectedNamespace
        }
    }

    private var querySearch: String? { trimmed(model.topologySearchText) }

    private var scopedNodes: [TopologyNode] {
        guard let query else { return [] }
        if model.topologyExplorerLevel == .evidence {
            // Evidence is an uncertainty inventory, not a second all-resource
            // map. Unavailable/synthetic boundary nodes remain inspectable;
            // input statuses and unresolved references are shown below.
            return query.nodes(level: nil, search: nil, kind: model.topologyKindFilter, namespace: nil, evidence: .unavailable)
        }
        return query.nodes(
            level: levelForQuery,
            search: nil,
            kind: model.topologyKindFilter,
            namespace: namespaceForLevel,
            evidence: model.topologyEvidenceFilter
        )
    }

    private var filteredNodes: [TopologyNode] {
        guard let query else { return [] }
        // Trace is deliberately cross-level: a route path can include a
        // Service, EndpointSlice and Pod even while the current level is
        // Network. Inventory and Focus stay scoped to their selected level.
        if model.topologyExplorerMode == .trace && model.topologyExplorerLevel != .evidence {
            return query.nodes(
                level: nil,
                search: nil,
                kind: model.topologyKindFilter,
                namespace: nil,
                evidence: model.topologyEvidenceFilter
            ).filter(matchesSearch)
        }
        return scopedNodes.filter(matchesSearch)
    }

    private func matchesSearch(_ node: TopologyNode) -> Bool {
        guard let search = querySearch, let graph else { return true }
        let details = graph.details[node.id]
        var terms = [node.kind, node.name, node.namespace ?? ""]
        terms.append(contentsOf: node.facts.flatMap { [$0.title, $0.value] })
        if let details {
            terms.append(details.selectorSummary)
            terms.append(contentsOf: details.servicePorts.flatMap { [$0.name ?? "", String($0.port), $0.protocolName, $0.appProtocol ?? "", $0.targetPort.name ?? "", $0.targetPort.number.map(String.init) ?? ""] })
            terms.append(contentsOf: (details.containerPorts + details.initContainerPorts + details.ephemeralContainerPorts).flatMap { [$0.containerName, $0.name ?? "", String($0.port), $0.protocolName] })
            if let slice = details.endpointSlice {
                terms.append(contentsOf: [slice.addressType ?? "", slice.serviceName ?? ""])
                terms.append(contentsOf: slice.ports.flatMap { [$0.name ?? "", String($0.port), $0.protocolName] })
                terms.append(contentsOf: slice.endpoints.flatMap { $0.addresses + [$0.nodeName ?? "", $0.zone ?? ""] })
            }
            if let gateway = details.gateway { terms.append(contentsOf: gateway.statusConditions.flatMap { [$0.key, $0.value] }) }
            if let route = details.httpRoute { terms.append(contentsOf: route.hostnames + route.statusConditions.flatMap { [$0.key, $0.value] }) }
        }
        return terms.joined(separator: " ").localizedCaseInsensitiveContains(search)
    }

    private var filteredPortPaths: [TopologyPortPath] {
        guard let query else { return [] }
        let port = Int32(model.topologyPortFilter.trimmingCharacters(in: .whitespacesAndNewlines))
        var paths = query.portPaths(
            level: model.topologyExplorerLevel == .evidence ? .evidence : .network,
            protocolName: trimmed(model.topologyProtocolFilter),
            port: port,
            search: nil
        )
        paths = paths.filter(pathMatchesSearch)
        if model.topologyShowUnresolvedOnly {
            paths = paths.filter { $0.status == .unresolved || $0.status == .partial || $0.status == .noEndpoint || $0.status == .noReadyEndpoint }
        }
        switch model.topologyReadinessFilter {
        case .all: break
        case .ready:
            paths = query.portPaths(level: model.topologyExplorerLevel == .evidence ? .evidence : .network, protocolName: trimmed(model.topologyProtocolFilter), port: port, readiness: true, search: nil).filter(pathMatchesSearch)
        case .notReady:
            let conditionPaths = query.portPaths(level: model.topologyExplorerLevel == .evidence ? .evidence : .network, protocolName: trimmed(model.topologyProtocolFilter), port: port, readiness: false, search: nil).filter(pathMatchesSearch)
            paths = Array(Set(conditionPaths + paths.filter { $0.status == .noReadyEndpoint })).sorted { $0.id < $1.id }
        case .unknown:
            paths = paths.filter { $0.status == .partial || $0.status == .unresolved || $0.status == .noEndpoint || $0.status == .external }
        }
        return paths
    }

    private func pathMatchesSearch(_ path: TopologyPortPath) -> Bool {
        guard let search = querySearch else { return true }
        var terms = [path.source.kind, path.source.name]
        terms.append(path.source.namespace ?? "")
        terms.append(path.note ?? "")
        for hop in path.hops {
            terms.append(hop.role)
            terms.append(hop.portName ?? "")
            terms.append(hop.portNumber.map { String($0) } ?? "")
            terms.append(hop.protocolName ?? "")
            terms.append(hop.containerName ?? "")
            terms.append(hop.addresses.joined(separator: " "))
            terms.append(hop.nodeName ?? "")
            terms.append(hop.zone ?? "")
        }
        return terms.joined(separator: " ").localizedCaseInsensitiveContains(search)
    }

    private var focusedNodeIDs: Set<String> {
        guard let graph, let query else { return [] }
        switch model.topologyExplorerMode {
        case .inventory: return []
        case .focus:
            guard let selected = model.selectedTopologyNodeID else { return [] }
            return query.oneHopFocus(nodeIDs: [selected], level: levelForQuery)
        case .trace:
            return traceNodeIDs(graph: graph)
        }
    }

    private var visibleNodes: [TopologyNode] {
        let nodes = filteredNodes
        guard !focusedNodeIDs.isEmpty else { return nodes }
        return nodes.filter { focusedNodeIDs.contains($0.id) }
    }

    private var visibleEdges: [TopologyEdge] {
        guard let query else { return [] }
        let allowed = Set(visibleNodes.map(\.id))
        let edgeLevel: ExplorerLevel? = model.topologyExplorerMode == .trace ? nil : levelForQuery
        return query.edges(level: edgeLevel, evidence: model.topologyEvidenceFilter, focusedNodeIDs: focusedNodeIDs)
            .filter { allowed.contains($0.from) && allowed.contains($0.to) }
    }

    private func traceNodeIDs(graph: TopologyGraph) -> Set<String> {
        if let pathID = model.selectedTopologyPortPathID,
           let path = graph.portPaths.first(where: { $0.id == pathID }) {
            return traceNodeIDs(for: path, graph: graph)
        }
        if let edgeID = model.selectedTopologyEdgeID,
           let edge = graph.edges.first(where: { $0.id == edgeID }) {
            return [edge.from, edge.to]
        }
        if let nodeID = model.selectedTopologyNodeID, let query {
            return query.oneHopFocus(nodeIDs: [nodeID], level: nil)
        }
        return []
    }

    private func traceNodeIDs(for path: TopologyPortPath, graph: TopologyGraph) -> Set<String> {
        let references = [path.source] + path.hops.compactMap(\.reference)
        return Set(references.compactMap { reference in
            graph.nodes.first(where: { node in
                if let uid = reference.uid, let nodeUID = node.uid, uid == nodeUID { return true }
                return node.kind.caseInsensitiveCompare(reference.kind) == .orderedSame
                    && node.name == reference.name
                    && node.namespace == reference.namespace
            })?.id
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let graph {
                freshnessStrip(graph)
            }
            GeometryReader { geometry in
                if geometry.size.width >= 1_000 {
                    wideWorkspace
                } else {
                    narrowWorkspace
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if model.sidebarSelection == .topology,
               model.topologyGraph == nil,
               !model.topologyIsBuilding {
                model.requestRefresh()
            }
        }
        .onChange(of: model.topologyExplorerLevel) { _, _ in
            mapVisibleLimit = mapPageSize
        }
        .onChange(of: model.topologySearchText) { _, _ in mapVisibleLimit = mapPageSize }
        .onChange(of: model.topologyKindFilter) { _, _ in mapVisibleLimit = mapPageSize }
        .onChange(of: model.topologyEvidenceFilter) { _, _ in mapVisibleLimit = mapPageSize }
        .onChange(of: model.selectedNamespace) { _, _ in mapVisibleLimit = mapPageSize }
        .onChange(of: model.selectedContext) { _, _ in mapVisibleLimit = mapPageSize }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.topologyExplorerLevel)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.topologyExplorerPresentation)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.selectedTopologyNodeID)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.selectedTopologyEdgeID)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.selectedTopologyPortPathID)
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
                if model.topologyIsBuilding {
                    ProgressView().controlSize(.small).accessibilityLabel("Refreshing topology evidence")
                }
                Button { model.requestRefresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.topologyIsBuilding)
            }
            HStack(spacing: 10) {
                NamespacePicker()
                TextField("Search resources, ports, or evidence", text: Binding(
                    get: { model.topologySearchText },
                    set: { model.topologySearchText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 190, maxWidth: 290)
                filters
                Spacer(minLength: 0)
            }
            breadcrumb
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private var filters: some View {
        HStack(spacing: 7) {
            Picker("Kind", selection: Binding(
                get: { model.topologyKindFilter ?? "" },
                set: { model.topologyKindFilter = $0.isEmpty ? nil : $0 }
            )) {
                Text("All kinds").tag("")
                ForEach(kindOptions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Resource kind")
            Picker("Evidence", selection: Binding(
                get: { model.topologyEvidenceFilter?.rawValue ?? "" },
                set: { model.topologyEvidenceFilter = TopologyEvidenceLevel(rawValue: $0) }
            )) {
                Text("Any evidence").tag("")
                ForEach(TopologyEvidenceLevel.allCases, id: \.self) { Text(evidenceLevelTitle($0)).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Evidence level")
            if model.topologyExplorerLevel == .network || model.topologyExplorerLevel == .evidence {
                TextField("Protocol", text: Binding(
                    get: { model.topologyProtocolFilter },
                    set: { model.topologyProtocolFilter = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                TextField("Port", text: Binding(
                    get: { model.topologyPortFilter },
                    set: { model.topologyPortFilter = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                Picker("Endpoint evidence", selection: Binding(
                    get: { model.topologyReadinessFilter },
                    set: { model.topologyReadinessFilter = $0 }
                )) {
                    ForEach(AppModel.TopologyReadinessFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Endpoint readiness")
                Toggle("Unresolved", isOn: Binding(
                    get: { model.topologyShowUnresolvedOnly },
                    set: { model.topologyShowUnresolvedOnly = $0 }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .font(.caption)
    }

    private var kindOptions: [String] {
        guard let query else { return [] }
        let nodes = query.nodes(level: levelForQuery, search: nil, kind: nil, namespace: namespaceForLevel, evidence: model.topologyEvidenceFilter)
        return Array(Set(nodes.map(\.kind))).sorted()
    }

    private var breadcrumb: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            ForEach(Array(model.topologyFocusPath.enumerated()), id: \.offset) { _, level in
                Button(level.title) { model.setTopologyLevel(level) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(level == model.topologyExplorerLevel ? .semibold : .regular))
                    .foregroundStyle(level == model.topologyExplorerLevel ? .primary : .secondary)
                if level != model.topologyFocusPath.last {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Picker("Mode", selection: Binding(
                get: { model.topologyExplorerMode },
                set: { model.topologyExplorerMode = $0 }
            )) {
                ForEach(ExplorerMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Explorer mode")
            .frame(width: 230)
            Picker("Presentation", selection: Binding(
                get: { model.topologyExplorerPresentation },
                set: { model.topologyExplorerPresentation = $0 }
            )) {
                ForEach(ExplorerPresentation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Explorer presentation")
            .frame(width: 250)
        }
    }

    private var wideWorkspace: some View {
        HStack(spacing: 0) {
            levelRail.frame(width: 218)
            Divider()
            workspace
            Divider()
            inspector.frame(width: 335)
        }
    }

    private var narrowWorkspace: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                compactLevelRail
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(height: 58)
            Divider()
            workspace.frame(minHeight: 370)
            if model.selectedTopologyNodeID != nil || model.selectedTopologyEdgeID != nil || model.selectedTopologyPortPathID != nil {
                Divider()
                inspector.frame(maxHeight: 350)
            }
        }
    }

    private var compactLevelRail: some View {
        HStack(spacing: 7) {
            ForEach(ExplorerLevel.allCases, id: \.self) { level in
                Button {
                    model.setTopologyLevel(level)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: level.icon)
                        Text(level.title).lineLimit(1)
                        if levelCount(level) > 0 {
                            Text("\(levelCount(level))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .background(model.topologyExplorerLevel == level ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor), in: Capsule())
                .accessibilityLabel("\(level.title), \(level.question)")
                .accessibilityValue(model.topologyExplorerLevel == level ? "Selected" : "Not selected")
            }
        }
    }

    private var levelRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text("Explore").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10)
                ForEach(ExplorerLevel.allCases, id: \.self) { level in
                    Button {
                        model.setTopologyLevel(level)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: level.icon).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title).font(.callout.weight(.medium))
                                Text(level.question).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if levelCount(level) > 0 {
                                Text("\(levelCount(level))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .background(model.topologyExplorerLevel == level ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("\(level.title), \(level.question)")
                    .accessibilityValue(model.topologyExplorerLevel == level ? "Selected" : "Not selected")
                }
                Divider().padding(.vertical, 5)
                Text("Read-only evidence").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10)
                Text("Declarations, observations, joins, and unavailable inputs remain labeled. This is not packet capture.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }
            .padding(10)
        }
        .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear)
    }

    private var workspace: some View {
        Group {
            if graph == nil && (model.topologyIsBuilding || model.isLoading) {
                ContentUnavailableView("Building topology", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Reading safe metadata through kubectl. The cluster is not modified."))
            } else if graph == nil && model.topologyError != nil {
                ContentUnavailableView("Topology unavailable", systemImage: "exclamationmark.triangle", description: Text(model.topologyError ?? "The snapshot could not be loaded. Check access and retry."))
            } else if graph == nil {
                ContentUnavailableView("No topology resources", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Choose another namespace or refresh to read safe Kubernetes metadata."))
            } else if let graph {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.topologyExplorerLevel == .cluster {
                            clusterOverview(graph)
                        } else {
                            levelSummary(graph)
                        }
                        presentation(graph)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func clusterOverview(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cluster fundamentals").font(.title2.weight(.semibold))
                    Text("Start with scope and status, then follow one question at a time.").foregroundStyle(.secondary)
                }
                Spacer()
                evidenceBadge(graph.completeness == .complete ? .observed : .unavailable, label: graph.completeness == .complete ? "Snapshot complete" : "Snapshot partial")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                summaryCard("Namespaces", value: count(kind: "Namespace", in: graph), icon: "square.grid.2x2")
                summaryCard("Nodes", value: count(kind: "Node", in: graph), icon: "server.rack")
                summaryCard("Workloads", value: count(level: .workloads, in: graph), icon: "shippingbox")
                summaryCard("Network paths", value: graph.portPaths.count, icon: "point.3.connected.trianglepath.dotted")
                summaryCard("Unresolved", value: graph.unresolvedReferences.count + graph.portPaths.filter { $0.status != .complete }.count, icon: "questionmark.diamond")
            }
            HStack(alignment: .top, spacing: 12) {
                fundamentalsCard
                statusCard(graph)
            }
        }
    }

    private var fundamentalsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("What this explorer can answer", systemImage: "lightbulb")
                .font(.headline)
            Text("Where workloads run, how declared routes resolve to Services and endpoints, which objects select Pods, and what evidence is missing.")
                .font(.callout)
            Text("What it cannot prove: packet delivery, process listening, CNI enforcement, cloud load-balancer behavior, or application health beyond the API fields observed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusCard(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Snapshot status", systemImage: "waveform.path.ecg")
                .font(.headline)
            statusLine("Captured", value: Fmt.age(graph.freshness.capturedAt, relativeTo: Date()) + " ago")
            statusLine("Generation", value: "\(graph.freshness.generation)")
            statusLine("Inputs unavailable", value: "\(graph.inputs.filter { $0.availability != .available }.count)")
            if let error = model.topologyError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(minWidth: 230, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func levelSummary(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.topologyExplorerLevel.title).font(.title2.weight(.semibold))
            Text(model.topologyExplorerLevel.question).foregroundStyle(.secondary)
            if model.topologyExplorerLevel == .network {
                Text("Port paths are structured evidence joins: route → Service port → EndpointSlice → endpoint → declared container port. A complete path still does not prove traffic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !graph.inputs.filter({ $0.availability != .available }).isEmpty {
                Text("Some inputs are unavailable or partial; the affected scope remains visible in Evidence.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            if model.topologyExplorerLevel == .evidence {
                evidenceSummary(graph)
            }
        }
    }

    private func evidenceSummary(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unavailable inputs").font(.headline)
            if graph.inputs.filter({ $0.availability != .available }).isEmpty {
                Text("No unavailable inputs in this snapshot.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(graph.inputs.filter { $0.availability != .available }) { input in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(input.resourceKind).font(.caption.weight(.medium))
                            Text(input.message ?? inputAvailabilityTitle(input.availability)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Unresolved references: \(graph.unresolvedReferences.count)").font(.caption.weight(.medium))
            Text("Unavailable evidence means the API input was denied, unsupported, partial, or absent—not that the resource is unhealthy.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.orange.opacity(0.3)))
    }

    @ViewBuilder
    private func presentation(_ graph: TopologyGraph) -> some View {
        switch model.topologyExplorerPresentation {
        case .map: semanticMap(graph)
        case .list: relationshipList(graph)
        case .portTable: portTable(graph)
        }
    }

    private func semanticMap(_ graph: TopologyGraph) -> some View {
        let allNodes = visibleNodes
        let nodes = Array(allNodes.prefix(mapVisibleLimit))
        let layout = Layout(nodes: nodes, level: model.topologyExplorerLevel)
        let width = max(720, CGFloat(layout.columnCount) * 220)
        let height = max(430, CGFloat(layout.rowCount) * 82 + 75)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Semantic map", systemImage: "square.3.layers.3d")
                    .font(.headline)
                Spacer()
                Text("\(allNodes.count) resources · \(visibleEdges.count) relationships")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if allNodes.count > mapVisibleLimit {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus").foregroundStyle(.orange)
                    Text("Showing \(nodes.count) of \(allNodes.count) resources to keep the map responsive.")
                    Button("Show \(min(mapPageSize, allNodes.count - mapVisibleLimit)) more") {
                        mapVisibleLimit = min(allNodes.count, mapVisibleLimit + mapPageSize)
                    }
                    Button("Use List") { model.topologyExplorerPresentation = .list }
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(9)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if nodes.isEmpty {
                ContentUnavailableView("No resources in this level", systemImage: "line.3.horizontal.decrease.circle", description: Text("Clear a filter or choose another Explorer Level."))
                    .frame(minHeight: 260)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            for edge in visibleEdges {
                                guard let from = layout.positions[edge.from], let to = layout.positions[edge.to] else { continue }
                                var path = Path()
                                let start = CGPoint(x: from.x + 178, y: from.y + 32)
                                let end = CGPoint(x: to.x, y: to.y + 32)
                                path.move(to: start)
                                let midX = (start.x + end.x) / 2
                                path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
                                context.stroke(path, with: .color(levelColor(edge.evidence.level).opacity(0.66)), style: StrokeStyle(lineWidth: edge.id == model.selectedTopologyEdgeID ? 3 : 1.3, dash: edge.evidence.level == .inferred ? [5, 4] : []))
                            }
                        }
                        .frame(width: width, height: height)
                        ForEach(layout.lanes, id: \.index) { lane in
                            Text(lane.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).position(x: CGFloat(lane.index) * 220 + 90, y: 18)
                        }
                        ForEach(nodes) { node in
                            if let point = layout.positions[node.id] {
                                Button {
                                    model.selectedTopologyNodeID = node.id
                                    model.selectedTopologyEdgeID = nil
                                    model.selectedTopologyPortPathID = nil
                                    inspectorTab = .fundamentals
                                } label: {
                                    nodeCard(node)
                                }
                                .buttonStyle(.plain)
                                .position(x: point.x + 90, y: point.y + 48)
                                .accessibilityLabel("\(node.kind) \(node.name)")
                                .accessibilityHint("Selects this resource and updates the inspector")
                            }
                        }
                    }
                    .frame(width: width, height: height)
                    .padding(26)
                }
                .frame(minHeight: 360)
            }
            traceSelectionStrip(graph)
            Text("Lines show declared, observed, or inferred API relationships. They are not network traffic.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func traceSelectionStrip(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Focused trace", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                Spacer()
                if model.selectedTopologyPortPathID == nil && model.selectedTopologyEdgeID == nil && model.selectedTopologyNodeID == nil {
                    Text("Select a path, relationship, or resource").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(graph.portPaths.prefix(24)) { path in
                        Button {
                            model.topologyExplorerMode = .trace
                            model.selectedTopologyPortPathID = path.id
                            model.selectedTopologyNodeID = nil
                            model.selectedTopologyEdgeID = nil
                            inspectorTab = .ports
                        } label: {
                            Label("\(path.source.name) · \(path.status.title)", systemImage: path.status.icon)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ForEach(visibleEdges.prefix(24)) { edge in
                        Button {
                            model.topologyExplorerMode = .trace
                            model.selectedTopologyEdgeID = edge.id
                            model.selectedTopologyNodeID = nil
                            model.selectedTopologyPortPathID = nil
                            inspectorTab = .relationships
                        } label: {
                            Label(relationshipTitle(edge.relationship), systemImage: "arrow.left.and.right")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func relationshipList(_ graph: TopologyGraph) -> some View {
        let nodeMap = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Inventory and relationships", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(visibleNodes.count) resources · \(visibleEdges.count) relationships")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            traceSelectionStrip(graph)
            List {
                Section("Resources") {
                    ForEach(visibleNodes) { node in
                        Button {
                            model.selectedTopologyNodeID = node.id
                            model.selectedTopologyEdgeID = nil
                            model.selectedTopologyPortPathID = nil
                            inspectorTab = .fundamentals
                        } label: {
                            resourceRow(node)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(node.kind) \(node.name)")
                    }
                }
                Section("Relationships") {
                    ForEach(visibleEdges) { edge in
                        Button {
                            model.selectedTopologyEdgeID = edge.id
                            model.selectedTopologyNodeID = nil
                            model.selectedTopologyPortPathID = nil
                            inspectorTab = .relationships
                        } label: {
                            edgeRow(edge, nodeMap: nodeMap)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 430)
        }
    }

    private func portTable(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Port paths", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Text("\(filteredPortPaths.count) paths")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if filteredPortPaths.isEmpty {
                ContentUnavailableView("No port paths", systemImage: "rectangle.connected.to.line.below", description: Text("No route-to-Service paths match the current filters, or the cluster exposes no declared routes in this snapshot."))
                    .frame(minHeight: 270)
            } else {
                List(filteredPortPaths) { path in
                    Button {
                        if model.topologyExplorerLevel != .network && model.topologyExplorerLevel != .evidence {
                            model.setTopologyLevel(.network)
                        }
                        model.selectedTopologyPortPathID = path.id
                        model.selectedTopologyNodeID = nil
                        model.selectedTopologyEdgeID = nil
                        inspectorTab = .ports
                    } label: {
                        portPathRow(path, graph: graph)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(path.source.kind) \(path.source.name), \(path.status.title) port path")
                }
                .listStyle(.inset)
                .frame(minHeight: 430)
            }
        }
    }

    private var inspector: some View {
        Group {
            if let graph {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        inspectorHeader(graph)
                        Picker("Inspector section", selection: $inspectorTab) {
                            ForEach(InspectorTab.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        inspectorContent(graph)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No snapshot", systemImage: "doc.questionmark", description: Text("Refresh the topology to inspect evidence."))
            }
        }
        .background(.background)
    }

    @ViewBuilder
    private func inspectorHeader(_ graph: TopologyGraph) -> some View {
        if let pathID = model.selectedTopologyPortPathID,
           let path = graph.portPaths.first(where: { $0.id == pathID }) {
            Text(path.source.name).font(.title3.weight(.semibold))
            Text("\(path.source.kind) · port path").font(.caption).foregroundStyle(.secondary)
            statusBadge(path.status)
        } else if let node = selectedNode(in: graph) {
            Text(node.name).font(.title3.weight(.semibold))
            Text("\(node.kind)\(node.namespace.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
            evidenceBadge(node.evidence.level)
        } else if let edge = selectedEdge(in: graph) {
            let from = graph.nodes.first { $0.id == edge.from }?.name ?? "Unknown"
            let to = graph.nodes.first { $0.id == edge.to }?.name ?? "Unknown"
            Text(relationshipTitle(edge.relationship)).font(.title3.weight(.semibold))
            Text("\(from) → \(to)").font(.caption).foregroundStyle(.secondary)
            evidenceBadge(edge.evidence.level)
        } else {
            Text("Inspector").font(.title3.weight(.semibold))
            Text("Select a resource, relationship, or port path.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func inspectorContent(_ graph: TopologyGraph) -> some View {
        if let pathID = model.selectedTopologyPortPathID,
           let path = graph.portPaths.first(where: { $0.id == pathID }) {
            portPathInspector(path, graph: graph)
        } else if let node = selectedNode(in: graph) {
            nodeInspector(node, graph: graph)
        } else if let edge = selectedEdge(in: graph) {
            edgeInspector(edge, graph: graph)
        } else {
            emptyInspector(graph)
        }
    }

    @ViewBuilder
    private func nodeInspector(_ node: TopologyNode, graph: TopologyGraph) -> some View {
        switch inspectorTab {
        case .fundamentals:
            factsSection(node.facts, title: "Fundamentals")
            if !node.isVirtual, let kind = resourceKind(for: node) {
                Button("Show in Resources") { model.jumpTo(kind: kind, namespace: node.namespace ?? "", name: node.name) }
                    .buttonStyle(.bordered)
            }
            whatItProves(node.evidence)
        case .status:
            let details = graph.details[node.id]
            let facts = (details?.facts ?? node.facts).filter { fact in
                let title = fact.title.lowercased()
                return title.contains("status") || title.contains("ready") || title.contains("condition") || title.contains("phase") || title.contains("restart")
            }
            factsSection(facts, title: "Status")
            if node.kind.caseInsensitiveCompare("Pod") == .orderedSame {
                let podFacts = (details?.facts ?? node.facts).filter { fact in
                    ["phase", "ready", "restarts"].contains(fact.key.lowercased())
                }
                factsSection(podFacts, title: "Pod health")
            }
            if let gateway = details?.gateway {
                conditionsSection(gateway.statusConditions, title: "Gateway conditions")
            }
            if let route = details?.httpRoute {
                conditionsSection(route.statusConditions, title: "HTTPRoute conditions")
            }
            if let gatewayClass = details?.gatewayClass {
                conditionsSection(gatewayClass.statusConditions, title: "GatewayClass conditions")
            }
            if let details = graph.details[node.id], let endpointSlice = details.endpointSlice {
                statusLine("Address type", value: endpointSlice.addressType ?? "Unknown")
                statusLine("Endpoints", value: "\(endpointSlice.endpoints.count)")
                // EndpointSlice omits `ready` for an effective-ready endpoint.
                // A terminating endpoint that is no longer serving is the one
                // explicit exception; keep this count aligned with the graph's
                // path resolution semantics.
                let effectiveReady = endpointSlice.endpoints.filter { endpoint in
                    endpoint.ready != false && !(endpoint.terminating == true && endpoint.serving == false)
                }.count
                statusLine("Ready (effective)", value: "\(effectiveReady)")
                statusLine("Serving", value: "\(endpointSlice.endpoints.filter { $0.serving == true }.count)")
                statusLine("Terminating", value: "\(endpointSlice.endpoints.filter { $0.terminating == true }.count)")
            }
            if let details = graph.details[node.id], let route = details.httpRoute {
                httpRouteBackends(route)
            }
            Text("Status is limited to fields present in this API snapshot.").font(.caption).foregroundStyle(.secondary)
        case .ports:
            if let details = graph.details[node.id] {
                typedPorts(details)
            }
            let paths = portPaths(relatedTo: node, graph: graph)
            if paths.isEmpty { Text("No structured port path references this resource.").font(.caption).foregroundStyle(.secondary) }
            ForEach(paths) { portPathRow($0, graph: graph) }
        case .relationships:
            adjacent(node, graph: graph)
        case .evidence:
            evidenceDetail(node.evidence)
            whatItProves(node.evidence)
        }
    }

    private func edgeInspector(_ edge: TopologyEdge, graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            evidenceDetail(edge.evidence)
            if !edge.attributes.isEmpty {
                factsSection(edge.attributes.sorted { $0.key < $1.key }.map { TopologyFact(key: $0.key, title: $0.key, value: $0.value) }, title: "Relationship details")
            }
            Text("What this proves").font(.headline)
            Text("The Kubernetes API exposed this relationship or the graph derived it using the evidence shown above.").font(.caption)
            Text("What this does not prove").font(.headline)
            Text("It does not prove packet delivery, controller success, or application health.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func portPathInspector(_ path: TopologyPortPath, graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resolution chain").font(.headline)
            ForEach(path.hops) { hop in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.down").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hop.role.replacingOccurrences(of: "-", with: " ").capitalized).font(.callout.weight(.medium))
                        Text(hop.reference.map { "\($0.kind) \($0.name)" } ?? "No object reference")
                            .font(.caption).foregroundStyle(.secondary)
                        let port = [hop.portName, hop.portNumber.map(String.init)].compactMap { $0 }.joined(separator: ":")
                        if !port.isEmpty || hop.protocolName != nil { Text("\(port.isEmpty ? "Port unspecified" : port)\(hop.protocolName.map { " · \($0)" } ?? "")").font(.caption.monospaced()) }
                        if !hop.addresses.isEmpty { Text(hop.addresses.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary) }
                        if hop.role == "endpoint" {
                            Text(endpointConditionLabel(hop)).font(.caption2.weight(.medium)).foregroundStyle(endpointConditionColor(hop))
                            if let node = hop.nodeName { Text("Node: \(node)").font(.caption2).foregroundStyle(.secondary) }
                            if let zone = hop.zone { Text("Zone: \(zone)").font(.caption2).foregroundStyle(.secondary) }
                        }
                        if let container = hop.containerName { Text("Container: \(container)").font(.caption2).foregroundStyle(.secondary) }
                        if let detail = pathHopPortDetail(hop, path: path, graph: graph) {
                            Text(detail)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        evidenceBadge(hop.evidence.level)
                    }
                }
            }
            if let note = path.note { Text(note).font(.caption).foregroundStyle(.orange) }
            statusLine("Ready endpoints", value: "\(path.readyEndpointCount) / \(path.totalEndpointCount)")
            Text("What this proves").font(.headline)
            Text("The displayed hops matched the declared and observed fields in this snapshot.").font(.caption)
            Text("What this does not prove").font(.headline)
            Text("A complete path does not prove that a process is listening, that a CNI or proxy accepted the packet, or that an application returned a healthy response.").font(.caption).foregroundStyle(.secondary)
            if !path.provenance.isEmpty {
                Text("Provenance").font(.headline)
                ForEach(Array(path.provenance.prefix(12).enumerated()), id: \.offset) { _, evidence in evidenceDetail(evidence) }
            }
        }
    }

    private func emptyInspector(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a focus").font(.headline)
            Text("Select a card, relationship, or Port Table row. The same selection is retained when you switch Map, List, and Port Table.")
                .font(.caption).foregroundStyle(.secondary)
            if !graph.unresolvedReferences.isEmpty {
                Text("Unresolved references").font(.headline)
                ForEach(graph.unresolvedReferences.prefix(12)) { unresolved in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(relationshipTitle(unresolved.relation)).font(.caption.weight(.medium))
                        Text(unresolved.reason).font(.caption2).foregroundStyle(.secondary)
                        evidenceBadge(unresolved.evidence.level)
                    }
                }
            }
        }
    }

    private func adjacent(_ node: TopologyNode, graph: TopologyGraph) -> some View {
        let edges = graph.edges.filter { $0.from == node.id || $0.to == node.id }
        return VStack(alignment: .leading, spacing: 7) {
            Text("Adjacent relationships").font(.headline)
            if edges.isEmpty { Text("None in this snapshot").font(.caption).foregroundStyle(.secondary) }
            ForEach(edges) { edge in
                let target = graph.nodes.first { $0.id == (edge.from == node.id ? edge.to : edge.from) }
                Button {
                    model.selectedTopologyEdgeID = edge.id
                    model.selectedTopologyNodeID = nil
                    model.selectedTopologyPortPathID = nil
                    inspectorTab = .relationships
                } label: {
                    HStack(spacing: 6) {
                        Text(relationshipTitle(edge.relationship))
                        Text(target?.name ?? "Unresolved").foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        evidenceBadge(edge.evidence.level)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func freshnessStrip(_ graph: TopologyGraph) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                let stale = model.topologyError != nil
                Image(systemName: stale ? "clock.badge.exclamationmark" : (graph.completeness == .complete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"))
                    .foregroundStyle(stale ? .orange : (graph.completeness == .complete ? .green : .orange))
                Text(stale ? "Showing previous snapshot — refresh failed" : (graph.completeness == .complete ? "Complete for requested API inputs" : "Partial snapshot — unavailable inputs stay visible"))
                    .font(.caption.weight(.medium))
                Text("Updated \(Fmt.age(graph.freshness.capturedAt, relativeTo: Date())) ago")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let error = model.topologyError { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1) }
                Button("Retry") { model.requestRefresh() }.controlSize(.small)
            }
            if !graph.inputs.filter({ $0.availability != .available }).isEmpty {
                Text(graph.inputs.filter { $0.availability != .available }.map { "\($0.resourceKind): \($0.message ?? inputAvailabilityTitle($0.availability))" }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35))
    }

    private func resourceRow(_ node: TopologyNode) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon(for: node.kind)).foregroundStyle(levelColor(node.evidence.level))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1)
                Text("\(node.kind)\(node.namespace.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            evidenceBadge(node.evidence.level)
        }
        .padding(.vertical, 3)
    }

    private func edgeRow(_ edge: TopologyEdge, nodeMap: [String: TopologyNode]) -> some View {
        HStack(spacing: 7) {
            Text(nodeMap[edge.from]?.name ?? "Unknown").lineLimit(1)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Text(nodeMap[edge.to]?.name ?? "Unknown").lineLimit(1)
            Spacer(minLength: 6)
            Text(relationshipTitle(edge.relationship)).font(.caption).foregroundStyle(.secondary)
            evidenceBadge(edge.evidence.level)
        }
        .padding(.vertical, 3)
    }

    private func portPathRow(_ path: TopologyPortPath, graph: TopologyGraph? = nil) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: path.status.icon).foregroundStyle(path.status.color)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(path.source.name).font(.callout.weight(.medium))
                    Text(path.source.kind).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(path.status)
                }
                Text(path.hops.map(hopLabel).joined(separator: "  →  "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let graph, let summary = pathPortResolutionSummary(path, graph: graph) {
                    Text(summary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let note = path.note { Text(note).font(.caption2).foregroundStyle(.orange).lineLimit(2) }
            }
        }
        .padding(.vertical, 5)
    }

    private func nodeCard(_ node: TopologyNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: node.kind)).foregroundStyle(levelColor(node.evidence.level))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1)
                Text(node.kind).font(.caption2).foregroundStyle(.secondary)
                if let namespace = node.namespace { Text(namespace).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 180, height: 64, alignment: .leading)
        .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(levelColor(node.evidence.level).opacity(0.45), lineWidth: node.id == model.selectedTopologyNodeID ? 2 : 1))
    }

    private func factsSection(_ facts: [TopologyFact], title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if facts.isEmpty {
                Text("No fields were available for this section.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(facts) { fact in
                    HStack(alignment: .top) {
                        Text(fact.title)
                        Spacer(minLength: 8)
                        Text(fact.value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func conditionsSection(_ conditions: [String: String], title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if conditions.isEmpty {
                Text("No status conditions were available.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(conditions.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(conditions[key] ?? "Unknown").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func typedPorts(_ details: TopologyNodeDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !details.servicePorts.isEmpty {
                Text("Service ports").font(.headline)
                ForEach(details.servicePorts) { port in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(port.name ?? "Unnamed") · \(port.port)/\(port.protocolName)")
                            .font(.caption.monospaced())
                        Text(servicePortDetail(port))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if let mode = details.serviceMode {
                    Text("Service mode: \(serviceModeTitle(mode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            let containers = details.containerPorts + details.initContainerPorts + details.ephemeralContainerPorts
            if !containers.isEmpty {
                Text("Declared container ports").font(.headline)
                ForEach(containers) { port in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(port.containerName) · \(port.name ?? "Unnamed") · \(port.port)/\(port.protocolName)")
                            .font(.caption.monospaced())
                        if let host = hostPortDetail(port) {
                            Text(host).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let endpointSlice = details.endpointSlice, !endpointSlice.ports.isEmpty {
                Text("EndpointSlice ports").font(.headline)
                ForEach(endpointSlice.ports) { port in
                    Text("\(port.name ?? "Unnamed") · \(port.port)/\(port.protocolName)\(port.appProtocol.map { " · app \($0)" } ?? "")")
                        .font(.caption.monospaced())
                }
            }
            if let gateway = details.gateway, !gateway.listeners.isEmpty {
                gatewayListeners(gateway)
            }
            if let policy = details.networkPolicy {
                networkPolicyRules(policy)
            }
            if details.servicePorts.isEmpty && containers.isEmpty && (details.endpointSlice?.ports.isEmpty ?? true) && (details.gateway?.listeners.isEmpty ?? true) && details.networkPolicy == nil {
                Text("No typed port declarations were available for this resource.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func servicePortDetail(_ port: TopologyServicePort) -> String {
        let target: String
        if let name = port.targetPort.name {
            target = "targetPort \(name)"
        } else if let number = port.targetPort.number {
            target = "targetPort \(number)"
        } else if port.targetPort.usesServicePortByDefault {
            target = "targetPort same as Service port"
        } else {
            target = "targetPort unspecified"
        }
        var details = [target]
        if let appProtocol = port.appProtocol, !appProtocol.isEmpty { details.append("app \(appProtocol)") }
        if let nodePort = port.nodePort { details.append("nodePort \(nodePort)") }
        return details.joined(separator: " · ")
    }

    private func hostPortDetail(_ port: TopologyContainerPort) -> String? {
        var details: [String] = []
        if let hostPort = port.hostPort { details.append("hostPort \(hostPort)") }
        if let hostIP = port.hostIP, !hostIP.isEmpty { details.append("hostIP \(hostIP)") }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private func serviceModeTitle(_ mode: TopologyServiceMode) -> String {
        switch mode {
        case .standard: return "ClusterIP"
        case .headless: return "Headless (clusterIP None)"
        case .selectorless: return "Selectorless"
        case .externalName: return "ExternalName"
        case .nodePort: return "NodePort"
        case .loadBalancer: return "LoadBalancer"
        }
    }

    private func gatewayListeners(_ gateway: TopologyGatewaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gateway listeners").font(.headline)
            ForEach(gateway.listeners) { listener in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(listener.name ?? "Unnamed") · \(listener.port)/\(listener.protocolName)")
                        .font(.caption.monospaced())
                    let hostname = listener.hostname ?? "All hostnames"
                    let kinds = listener.allowedRouteKinds.isEmpty ? "All route kinds" : listener.allowedRouteKinds.joined(separator: ", ")
                    Text("hostname \(hostname) · \(kinds)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func networkPolicyRules(_ policy: TopologyNetworkPolicySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NetworkPolicy rules").font(.headline)
            Text("Applies \(policy.policyTypes.joined(separator: ", ")) · pod selector \(policy.podSelector.summary)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if policy.rules.isEmpty {
                Text("No rule details were observed.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(policy.rules) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.direction == .ingress ? "Ingress rule" : "Egress rule")
                            .font(.caption.weight(.semibold))
                        Text(rule.peers.isEmpty ? "Peers: any" : "Peers: " + rule.peers.map(networkPolicyPeerLabel).joined(separator: "; "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(rule.ports.isEmpty ? "Ports: all" : "Ports: " + rule.ports.map(networkPolicyPortLabel).joined(separator: ", "))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            Text("Policy rules are declarations; this view does not evaluate CNI enforcement or packet reachability.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func networkPolicyPeerLabel(_ peer: TopologyNetworkPolicyPeer) -> String {
        var parts: [String] = []
        if let cidr = peer.ipBlockCIDR {
            parts.append(cidr)
            if !peer.exceptCIDRs.isEmpty { parts.append("except " + peer.exceptCIDRs.joined(separator: ", ")) }
        }
        if let pod = peer.podSelector { parts.append("pods[\(pod.summary)]") }
        if let namespace = peer.namespaceSelector { parts.append("namespaces[\(namespace.summary)]") }
        return parts.isEmpty ? "any" : parts.joined(separator: " · ")
    }

    private func networkPolicyPortLabel(_ port: TopologyNetworkPolicyPort) -> String {
        let number = port.number.map(String.init) ?? port.name ?? "named"
        let range = port.endPort.map { "-\($0)" } ?? ""
        return "\(number)\(range)/\(port.protocolName)"
    }

    private func httpRouteBackends(_ route: TopologyHTTPRouteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HTTPRoute backends").font(.headline)
            if route.hostnames.isEmpty == false {
                Text("Hosts: \(route.hostnames.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if route.backends.isEmpty {
                Text("No backend references were observed.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(route.backends) { backend in
                    let target = "\(backend.kind) \(backend.name)\(backend.port.map { ":\($0)" } ?? "")"
                    let status = backend.resolvedRefs == true ? "Resolved references" : (backend.resolvedRefs == false ? "References unresolved" : "Reference status unknown")
                    Text("\(target) · \(status)")
                        .font(.caption2)
                        .foregroundStyle(backend.resolvedRefs == false ? .orange : .secondary)
                }
            }
            if !route.parents.isEmpty {
                Text("Parents: " + route.parents.map { parent in
                    let accepted = parent.accepted == true ? "accepted" : (parent.accepted == false ? "not accepted" : "acceptance unknown")
                    return "\(parent.kind) \(parent.name) · \(accepted)"
                }.joined(separator: "; "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pathPortResolutionSummary(_ path: TopologyPortPath, graph: TopologyGraph) -> String? {
        var fragments: [String] = []
        if let serviceHop = path.hops.first(where: { $0.role == "service-port" }),
           let reference = serviceHop.reference,
           let details = details(for: reference, graph: graph),
           let service = details.servicePorts.first(where: { port in
               (serviceHop.portNumber == nil || port.port == serviceHop.portNumber) &&
               (serviceHop.portName == nil || port.name == serviceHop.portName) &&
               (serviceHop.protocolName == nil || port.protocolName == serviceHop.protocolName)
           }) {
            fragments.append(servicePortDetail(service))
        }
        if let endpointHop = path.hops.first(where: { $0.role == "endpoint-port" }),
           let reference = endpointHop.reference,
           let details = details(for: reference, graph: graph),
           let endpointPort = details.endpointSlice?.ports.first(where: { port in
               (endpointHop.portNumber == nil || port.port == endpointHop.portNumber) &&
               (endpointHop.portName == nil || port.name == endpointHop.portName)
           }), let appProtocol = endpointPort.appProtocol, !appProtocol.isEmpty {
            fragments.append("endpoint app \(appProtocol)")
        }
        if let containerHop = path.hops.first(where: { $0.role == "container-port" }),
           let reference = containerHop.reference,
           let details = details(for: reference, graph: graph),
           let container = (details.containerPorts + details.initContainerPorts + details.ephemeralContainerPorts).first(where: { port in
               (containerHop.containerName == nil || port.containerName == containerHop.containerName) &&
               (containerHop.portNumber == nil || port.port == containerHop.portNumber)
           }), let host = hostPortDetail(container) {
            fragments.append(host)
        }
        return fragments.isEmpty ? nil : fragments.joined(separator: " · ")
    }

    private func pathHopPortDetail(_ hop: TopologyPortHop, path: TopologyPortPath, graph: TopologyGraph) -> String? {
        guard let reference = hop.reference, let details = details(for: reference, graph: graph) else { return nil }
        switch hop.role {
        case "service-port":
            guard let service = details.servicePorts.first(where: { port in
                (hop.portNumber == nil || port.port == hop.portNumber) &&
                (hop.portName == nil || port.name == hop.portName) &&
                (hop.protocolName == nil || port.protocolName == hop.protocolName)
            }) else { return nil }
            return servicePortDetail(service)
        case "endpoint-port":
            guard let endpoint = details.endpointSlice?.ports.first(where: { port in
                (hop.portNumber == nil || port.port == hop.portNumber) &&
                (hop.portName == nil || port.name == hop.portName)
            }) else { return nil }
            return endpoint.appProtocol.map { "Endpoint appProtocol \($0)" }
        case "container-port":
            let ports = details.containerPorts + details.initContainerPorts + details.ephemeralContainerPorts
            guard let container = ports.first(where: { port in
                (hop.containerName == nil || port.containerName == hop.containerName) &&
                (hop.portNumber == nil || port.port == hop.portNumber)
            }) else { return nil }
            return hostPortDetail(container)
        default:
            return nil
        }
    }

    private func details(for reference: TopologyObjectReference, graph: TopologyGraph) -> TopologyNodeDetails? {
        guard let node = graph.nodes.first(where: { node in
            if let uid = reference.uid, let nodeUID = node.uid, !uid.isEmpty, uid == nodeUID { return true }
            return node.kind.caseInsensitiveCompare(reference.kind) == .orderedSame &&
                node.name == reference.name && node.namespace == reference.namespace
        }) else { return nil }
        return graph.details[node.id]
    }

    private func evidenceDetail(_ evidence: TopologyEvidence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            evidenceBadge(evidence.level)
            Text(evidence.source.note ?? evidence.source.sourceField ?? "Kubernetes API evidence")
                .font(.caption).foregroundStyle(.secondary)
            if let join = evidence.source.joinRule { Text("Join: \(join)").font(.caption2).foregroundStyle(.secondary) }
            if let assumption = evidence.source.assumption { Text("Assumption: \(assumption)").font(.caption2).foregroundStyle(.orange) }
        }
    }

    private func whatItProves(_ evidence: TopologyEvidence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("What this proves").font(.headline)
            Text("This section reflects the \(evidenceLevelTitle(evidence.level).lowercased()) fields shown in the Kubernetes API snapshot.").font(.caption)
            Text("What this does not prove").font(.headline)
            Text("It does not prove packet reachability, controller reconciliation, process listening, or application health.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func summaryCard(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text("\(value)").font(.title2.monospacedDigit().weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11))
    }

    private func statusLine(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }.font(.caption)
    }

    private func selectedNode(in graph: TopologyGraph) -> TopologyNode? {
        guard let id = model.selectedTopologyNodeID else { return nil }
        return graph.nodes.first { $0.id == id }
    }

    private func selectedEdge(in graph: TopologyGraph) -> TopologyEdge? {
        guard let id = model.selectedTopologyEdgeID else { return nil }
        return graph.edges.first { $0.id == id }
    }

    private func portPaths(relatedTo node: TopologyNode, graph: TopologyGraph) -> [TopologyPortPath] {
        graph.portPaths.filter { path in
            path.source.uid == node.uid || path.source.name == node.name && path.source.namespace == node.namespace || path.hops.contains { $0.reference?.uid == node.uid || ($0.reference?.name == node.name && $0.reference?.namespace == node.namespace) }
        }
    }

    private func resourceKind(for node: TopologyNode) -> ResourceKind? {
        model.kindCatalog.first { $0.kindName.caseInsensitiveCompare(node.kind) == .orderedSame && $0.defaultAPIVersion == node.apiVersion }
            ?? model.kindCatalog.first { $0.kindName.caseInsensitiveCompare(node.kind) == .orderedSame }
    }

    private func count(kind: String, in graph: TopologyGraph) -> Int { graph.nodes.filter { $0.kind.caseInsensitiveCompare(kind) == .orderedSame }.count }
    private func count(level: ExplorerLevel, in graph: TopologyGraph) -> Int { graph.nodes.filter { TopologyGraphQuery.level(for: $0.kind) == level }.count }
    private func levelCount(_ level: ExplorerLevel) -> Int {
        guard let graph else { return 0 }
        if level == .network { return graph.portPaths.count }
        if level == .evidence { return graph.unresolvedReferences.count + graph.inputs.filter { $0.availability != .available }.count }
        return graph.nodes.filter { TopologyGraphQuery.level(for: $0.kind) == level }.count
    }
    private func trimmed(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    private func hopLabel(_ hop: TopologyPortHop) -> String {
        let reference = hop.reference?.name ?? hop.role
        let port = [hop.portName, hop.portNumber.map(String.init)].compactMap { $0 }.joined(separator: ":")
        return port.isEmpty ? reference : "\(reference):\(port)"
    }
    private func evidenceBadge(_ level: TopologyEvidenceLevel, label: String? = nil) -> some View {
        Text(label ?? evidenceLevelTitle(level))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(levelColor(level).opacity(0.16), in: Capsule())
            .foregroundStyle(levelColor(level))
    }
    private func statusBadge(_ status: TopologyPortPathStatus) -> some View {
        Text(status.title).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 3).background(status.color.opacity(0.16), in: Capsule()).foregroundStyle(status.color)
    }
    private func icon(for kind: String) -> String {
        switch kind.lowercased() {
        case "pod": return "circle.fill"
        case "node": return "server.rack"
        case "service": return "network"
        case "ingress", "gateway", "httproute", "grpcroute", "tcproute", "udproute": return "arrow.triangle.branch"
        case "endpointslice": return "point.3.connected.trianglepath.dotted"
        case "networkpolicy": return "lock.shield"
        case "namespace": return "square.grid.2x2"
        default: return "cube"
        }
    }
    private func relationshipTitle(_ relationship: TopologyRelationship) -> String {
        switch relationship {
        case .containedIn: return "Contained in"
        case .ownedBy: return "Owned by"
        case .scheduledOn: return "Scheduled on"
        case .selects: return "Selects"
        case .publishesEndpoints: return "Publishes endpoints"
        case .endpointTarget: return "Endpoint target"
        case .routesTo: return "Declared route to"
        case .references: return "References"
        case .backedBy: return "Backed by"
        case .usesStorageClass: return "Uses storage class"
        case .inputUnavailable: return "Input unavailable"
        }
    }
    private func levelColor(_ level: TopologyEvidenceLevel) -> Color {
        switch level {
        case .observed: return .green
        case .declared: return .blue
        case .inferred: return .orange
        case .unavailable: return .secondary
        }
    }
}

private struct Layout {
    struct Lane: Hashable { let index: Int; let title: String }
    let positions: [String: CGPoint]
    let lanes: [Lane]
    let columnCount: Int
    let rowCount: Int

    init(nodes: [TopologyNode], level: ExplorerLevel) {
        let grouped = Dictionary(grouping: nodes) { Layout.lane(for: $0, level: level) }
        let sortedKeys = grouped.keys.sorted()
        lanes = sortedKeys.enumerated().map { Lane(index: $0.offset, title: $0.element) }
        columnCount = max(1, sortedKeys.count)
        rowCount = max(1, grouped.values.map(\.count).max() ?? 1)
        var positions: [String: CGPoint] = [:]
        for (column, key) in sortedKeys.enumerated() {
            let members = (grouped[key] ?? []).sorted { $0.id < $1.id }
            for (row, node) in members.enumerated() {
                positions[node.id] = CGPoint(x: CGFloat(column) * 220, y: CGFloat(row) * 82 + 28)
            }
        }
        self.positions = positions
    }

    private static func lane(for node: TopologyNode, level: ExplorerLevel) -> String {
        let kind = node.kind.lowercased()
        switch level {
        case .cluster: return node.isVirtual ? "Control-plane boundary" : (node.namespace ?? "Cluster scope")
        case .infrastructure: return kind == "node" ? "Nodes" : "Cluster resources"
        case .workloads: return kind == "pod" ? "Pods" : "Controllers"
        case .network: return ["ingress", "gateway", "httproute", "grpcroute", "tcproute", "udproute"].contains(kind) ? "Routes" : (kind == "service" || kind == "endpointslice" ? "Services and endpoints" : "Network resources")
        case .policyDependencies: return kind == "networkpolicy" ? "Policy" : "Dependencies"
        case .evidence: return evidenceLevelTitle(node.evidence.level)
        }
    }
}

private extension ExplorerLevel {
    var title: String {
        switch self {
        case .cluster: return "Cluster"
        case .infrastructure: return "Infrastructure"
        case .workloads: return "Workloads"
        case .network: return "Network"
        case .policyDependencies: return "Policy & Dependencies"
        case .evidence: return "Evidence"
        }
    }
    var question: String {
        switch self {
        case .cluster: return "What exists and can be proven?"
        case .infrastructure: return "Where can workloads run?"
        case .workloads: return "What is running and owned?"
        case .network: return "How are services exposed?"
        case .policyDependencies: return "What constrains or supports it?"
        case .evidence: return "What is missing or uncertain?"
        }
    }
    var icon: String {
        switch self {
        case .cluster: return "circle.grid.3x3.fill"
        case .infrastructure: return "server.rack"
        case .workloads: return "shippingbox"
        case .network: return "network"
        case .policyDependencies: return "lock.shield"
        case .evidence: return "checkmark.seal"
        }
    }
}

private extension ExplorerMode {
    var title: String {
        switch self {
        case .inventory: return "Inventory"
        case .focus: return "Focus"
        case .trace: return "Trace"
        }
    }
}

private extension ExplorerPresentation {
    var title: String {
        switch self {
        case .map: return "Map"
        case .list: return "List"
        case .portTable: return "Port Table"
        }
    }
}

private extension TopologyPortPathStatus {
    var title: String {
        switch self {
        case .complete: return "Complete"
        case .partial: return "Partial"
        case .unresolved: return "Unresolved"
        case .external: return "External"
        case .noEndpoint: return "No endpoint"
        case .noReadyEndpoint: return "No ready endpoint"
        }
    }
    var icon: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .partial: return "circle.dotted"
        case .unresolved: return "questionmark.circle.fill"
        case .external: return "arrow.up.right.circle"
        case .noEndpoint: return "minus.circle"
        case .noReadyEndpoint: return "exclamationmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .complete: return .green
        case .partial: return .orange
        case .unresolved: return .red
        case .external: return .blue
        case .noEndpoint: return .secondary
        case .noReadyEndpoint: return .orange
        }
    }
}

private func endpointConditionLabel(_ hop: TopologyPortHop) -> String {
    if hop.terminating == true && hop.serving == false { return "Terminating · not serving" }
    if hop.ready == true { return hop.serving == false ? "Ready, not serving" : "Ready" }
    if hop.serving == true { return "Serving, not ready" }
    if hop.ready == false { return "Not ready" }
    // EndpointSlice treats an omitted ready condition as effective-ready.
    // Keep the raw-state nuance visible without downgrading the semantic state.
    return hop.terminating == true ? "Ready (terminating; ready field omitted)" : "Ready (ready field omitted)"
}

private func evidenceLevelTitle(_ level: TopologyEvidenceLevel) -> String {
    switch level {
    case .observed: return "Observed"
    case .declared: return "Declared"
    case .inferred: return "Inferred"
    case .unavailable: return "Unavailable"
    }
}

private func inputAvailabilityTitle(_ availability: TopologyInputAvailability) -> String {
    switch availability {
    case .available: return "Available"
    case .partial: return "Partial"
    case .forbidden: return "Access denied"
    case .unsupported: return "Unsupported"
    case .unavailable: return "Unavailable"
    }
}

private func endpointConditionColor(_ hop: TopologyPortHop) -> Color {
    let effectiveReady = hop.ready != false && !(hop.terminating == true && hop.serving == false)
    if effectiveReady { return .green }
    if hop.terminating == true || hop.ready == false { return .orange }
    return .secondary
}
