import SwiftUI
import KubeCompassCore

private struct TopologyPresentationRequestKey: Hashable, Sendable {
    let generation: Int
    let contextID: String
    let surface: TopologyExplorerSurface
    let selectedRootID: String?
    let maxHops: Int
    let search: String?
    let namespace: String?
    let kind: String?
    let evidence: TopologyEvidenceLevel?
    let unresolvedOnly: Bool
}

/// Read-only, evidence-aware cluster exploration. The view deliberately
/// presents a semantic level at a time instead of drawing one undifferentiated
/// resource graph. It never claims packet reachability or executes actions.
struct TopologyExplorerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var inspectorTab: InspectorTab = .fundamentals
    @State private var filtersPresented = false
    @State private var preparedPresentation: TopologyExplorerPresentation?
    @State private var preparedPresentationKey: TopologyPresentationRequestKey?
    @State private var presentationBuildTask: Task<TopologyExplorerPresentation, Never>?
    @State private var presentationBuildSequence = 0

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

    private var presentationRequestKey: TopologyPresentationRequestKey? {
        guard let graph else { return nil }
        return TopologyPresentationRequestKey(
            generation: graph.freshness.generation,
            contextID: graph.contextID,
            surface: model.topologySurface,
            // Outline and Paths are scope-wide surfaces. Only Map is rooted
            // in the selected resource; selection alone must not rebuild or
            // unexpectedly empty the other surfaces.
            selectedRootID: model.topologySurface == .map ? model.selectedTopologyNodeID : nil,
            maxHops: model.topologyMapExpansionHops,
            search: querySearch,
            namespace: model.selectedNamespace,
            kind: model.topologyKindFilter,
            evidence: model.topologyEvidenceFilter,
            unresolvedOnly: model.topologyShowUnresolvedOnly
        )
    }

    private var presentationModel: TopologyExplorerPresentation? {
        guard let key = presentationRequestKey, preparedPresentationKey == key else { return nil }
        return preparedPresentation
    }

    private var querySearch: String? { trimmed(model.topologySearchText) }

    private var scopedNodes: [TopologyNode] {
        guard query != nil else { return [] }
        let query = TopologyGraphQuery(graph: graph!)
        return query.nodes(
            level: nil,
            search: nil,
            kind: model.topologyKindFilter,
            namespace: model.selectedNamespace,
            evidence: model.topologyEvidenceFilter
        )
    }

    private var filteredNodes: [TopologyNode] {
        var nodes = scopedNodes.filter(matchesSearch)
        if model.topologyShowUnresolvedOnly, let graph {
            let unresolvedIDs = Set(graph.unresolvedReferences.compactMap(\.sourceNodeID))
            nodes = nodes.filter { unresolvedIDs.contains($0.id) || $0.evidence.level == .unavailable }
        }
        return nodes
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
        guard let graph else { return [] }
        return applyPathControls(to: graph.portPaths.filter(pathMatchesScope))
    }

    private func preparedPortPaths(_ presentation: TopologyExplorerPresentation?) -> [TopologyPortPath] {
        guard let presentation else { return [] }
        return applyPathControls(to: presentation.paths.map(\.path))
    }

    private func applyPathControls(to basePaths: [TopologyPortPath]) -> [TopologyPortPath] {
        let port = Int32(model.topologyPortFilter.trimmingCharacters(in: .whitespacesAndNewlines))
        let protocolFilter = trimmed(model.topologyProtocolFilter)
        var paths = basePaths
        if let protocolFilter {
            paths = paths.filter { path in
                path.hops.contains { $0.protocolName?.caseInsensitiveCompare(protocolFilter) == .orderedSame }
            }
        }
        if let port {
            paths = paths.filter { path in path.hops.contains { $0.portNumber == port } }
        }
        paths = paths.filter(pathMatchesSearch)
        switch model.topologyReadinessFilter {
        case .all: break
        case .ready:
            if let graph {
                let readyPathIDs = Set(TopologyGraphQuery(graph: graph).portPaths(readiness: true).map(\.id))
                paths = paths.filter { readyPathIDs.contains($0.id) }
            } else {
                paths = []
            }
        case .notReady:
            if let graph {
                let notReadyPathIDs = Set(TopologyGraphQuery(graph: graph).portPaths(readiness: false).map(\.id))
                paths = paths.filter { $0.status == .noReadyEndpoint || notReadyPathIDs.contains($0.id) }
            } else {
                paths = []
            }
        case .unknown:
            paths = paths.filter { $0.status == .partial || $0.status == .unresolved || $0.status == .noEndpoint || $0.status == .external }
        }
        return paths.sorted { $0.id < $1.id }
    }

    private func pathMatchesScope(_ path: TopologyPortPath) -> Bool {
        if let namespace = model.selectedNamespace, path.source.namespace != namespace { return false }
        if let kind = model.topologyKindFilter,
           path.source.kind.caseInsensitiveCompare(kind) != .orderedSame { return false }
        if model.topologyShowUnresolvedOnly,
           ![.partial, .unresolved, .noEndpoint, .noReadyEndpoint].contains(path.status) { return false }
        if let evidence = model.topologyEvidenceFilter {
            let levels = path.hops.map(\.evidence.level) + path.provenance.map(\.level)
            if !levels.contains(evidence) { return false }
        }
        return true
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
            terms.append(hop.reference?.kind ?? "")
            terms.append(hop.reference?.name ?? "")
            terms.append(hop.reference?.namespace ?? "")
        }
        return terms.joined(separator: " ").localizedCaseInsensitiveContains(search)
    }

    private var visibleNodes: [TopologyNode] {
        filteredNodes
    }

    private var visibleEdges: [TopologyEdge] {
        guard let query else { return [] }
        let allowed = Set(visibleNodes.map(\.id))
        return query.edges(level: nil, evidence: model.topologyEvidenceFilter)
            .filter { allowed.contains($0.from) && allowed.contains($0.to) }
    }

    var body: some View {
        let presentation = presentationModel
        VStack(spacing: 0) {
            header
            if let graph {
                freshnessStrip(graph)
            }
            GeometryReader { geometry in
                if geometry.size.width >= 1_000 {
                    wideWorkspace(presentation: presentation)
                } else {
                    narrowWorkspace(presentation: presentation)
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
        .task(id: presentationRequestKey) {
            await preparePresentation(for: presentationRequestKey)
        }
        .onChange(of: model.topologySurface) { _, _ in validateTopologySelection() }
        .onChange(of: model.topologySearchText) { _, _ in validateTopologySelection() }
        .onChange(of: model.topologyKindFilter) { _, _ in validateTopologySelection() }
        .onChange(of: model.topologyEvidenceFilter) { _, _ in validateTopologySelection() }
        .onChange(of: model.topologyShowUnresolvedOnly) { _, _ in validateTopologySelection() }
        .onChange(of: model.topologyProtocolFilter) { _, _ in validateTopologySelection() }
        .onChange(of: model.topologyPortFilter) { _, _ in validateTopologySelection() }
        .onChange(of: model.topologyReadinessFilter) { _, _ in validateTopologySelection() }
        .onChange(of: model.selectedNamespace) { _, _ in validateTopologySelection() }
        .onChange(of: model.selectedContext) { _, _ in
            clearTopologySelection()
        }
        .onChange(of: model.topologyGraph?.freshness.generation) { _, _ in
            validateTopologySelection()
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.topologySurface)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.selectedTopologyNodeID)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.selectedTopologyEdgeID)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: model.selectedTopologyPortPathID)
    }

    private func preparePresentation(for key: TopologyPresentationRequestKey?) async {
        presentationBuildTask?.cancel()
        presentationBuildTask = nil
        presentationBuildSequence += 1
        let sequence = presentationBuildSequence
        do {
            try await Task.sleep(for: .milliseconds(120))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        guard let key, let graph else {
            preparedPresentation = nil
            preparedPresentationKey = nil
            return
        }
        let filter = TopologyExplorerFilter(
            search: key.search,
            namespace: key.namespace,
            kind: key.kind,
            evidence: key.evidence,
            unresolvedOnly: key.unresolvedOnly
        )
        let buildTask = Task.detached(priority: .userInitiated) {
            TopologyExplorerPresentation.build(
                graph: graph,
                surface: key.surface,
                selectedRootID: key.selectedRootID,
                filter: filter,
                maxHops: key.maxHops
            )
        }
        presentationBuildTask = buildTask
        let result = await withTaskCancellationHandler {
            await buildTask.value
        } onCancel: {
            buildTask.cancel()
        }
        guard !Task.isCancelled, !buildTask.isCancelled, presentationBuildSequence == sequence else { return }
        guard presentationRequestKey == key else { return }
        preparedPresentation = result
        preparedPresentationKey = key
        if presentationBuildSequence == sequence { presentationBuildTask = nil }
    }

    private var header: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                Label("Topology", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.title3.weight(.semibold))
                Text(contextScopeLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                compactStatusSummary
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
                .frame(minWidth: 190, maxWidth: 360)
                surfacePicker
                Button {
                    filtersPresented.toggle()
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $filtersPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Topology filters").font(.headline)
                        filters
                    }
                    .padding(14)
                    .frame(width: 320)
                }
                Spacer(minLength: 0)
            }
            breadcrumb
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            }
            if model.topologySurface == .paths {
                HStack(spacing: 7) {
                    TextField("Protocol", text: Binding(
                        get: { model.topologyProtocolFilter },
                        set: { model.topologyProtocolFilter = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .accessibilityLabel("Path protocol")
                    TextField("Port", text: Binding(
                        get: { model.topologyPortFilter },
                        set: { model.topologyPortFilter = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .accessibilityLabel("Path port")
                    Picker("Endpoint evidence", selection: Binding(
                        get: { model.topologyReadinessFilter },
                        set: { model.topologyReadinessFilter = $0 }
                    )) {
                        ForEach(AppModel.TopologyReadinessFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("Endpoint readiness")
                }
                Toggle("Unresolved paths only", isOn: Binding(
                    get: { model.topologyShowUnresolvedOnly },
                    set: { model.topologyShowUnresolvedOnly = $0 }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .font(.caption)
    }

    private var surfacePicker: some View {
        Picker("Topology view", selection: Binding(
            get: { model.topologySurface },
            set: { model.setTopologySurface($0) }
        )) {
            ForEach(TopologyExplorerSurface.allCases, id: \.self) { surface in
                Label(surface.title, systemImage: surface.icon).tag(surface)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Topology view")
        .frame(width: 245)
    }

    private var contextScopeLabel: String {
        let namespace = model.selectedNamespace.map { " · namespace \($0)" } ?? " · all namespaces"
        return "context \(model.selectedContext.isEmpty ? "unknown" : model.selectedContext)\(namespace)"
    }

    private var compactStatusSummary: some View {
        HStack(spacing: 8) {
            if let graph {
                Text("\(scopedNodes.count) resources")
                Text("·")
                Text("\(graph.portPaths.count) paths")
                Text("·")
                Text(graph.completeness == .complete ? "snapshot complete" : "snapshot partial")
            } else {
                Text("no snapshot")
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel("Topology status summary")
    }

    private var kindOptions: [String] {
        if model.topologySurface == .paths, let graph {
            return Array(Set(graph.portPaths.compactMap { path in
                guard model.selectedNamespace == nil || path.source.namespace == model.selectedNamespace else { return nil }
                return path.source.kind
            })).sorted()
        }
        guard let query else { return [] }
        let nodes = query.nodes(level: nil, search: nil, kind: nil, namespace: model.selectedNamespace, evidence: model.topologyEvidenceFilter)
        return Array(Set(nodes.map(\.kind))).sorted()
    }

    private var breadcrumb: some View {
        HStack(spacing: 5) {
            Text("Selection").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            Text(model.selectedContext.isEmpty ? "cluster" : model.selectedContext)
            if let namespace = model.selectedNamespace {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Text(namespace)
            }
            if let graph, let node = selectedNode(in: graph) {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Text(node.kind)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Text(node.name).fontWeight(.semibold)
            }
            Spacer()
            Text(surfaceContextLabel).font(.caption2).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private var surfaceContextLabel: String {
        switch model.topologySurface {
        case .outline: return "Deterministic hierarchy"
        case .map: return "Scoped neighbors only"
        case .paths: return "Declared route diagnostics"
        }
    }

    private func wideWorkspace(presentation: TopologyExplorerPresentation?) -> some View {
        HStack(spacing: 0) {
            workspace(presentation: presentation)
            Divider()
            inspector.frame(width: 335)
        }
    }

    private func narrowWorkspace(presentation: TopologyExplorerPresentation?) -> some View {
        NavigationStack {
            Group {
                if model.topologyNarrowDetailVisible {
                    inspector
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button {
                                    model.topologyNarrowDetailVisible = false
                                } label: {
                                    Label("Results", systemImage: "chevron.left")
                                }
                            }
                        }
                } else {
                    workspace(presentation: presentation).frame(minHeight: 370)
                }
            }
            .navigationTitle(model.topologySurface.title)
        }
    }

    private func workspace(presentation: TopologyExplorerPresentation?) -> some View {
        Group {
            if graph == nil && (model.topologyIsBuilding || model.isLoading) {
                ContentUnavailableView("Building topology", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Reading safe metadata through kubectl. The cluster is not modified."))
            } else if graph == nil && model.topologyError != nil {
                ContentUnavailableView("Topology unavailable", systemImage: "exclamationmark.triangle", description: Text(model.topologyError ?? "The snapshot could not be loaded. Check access and retry."))
            } else if graph == nil {
                ContentUnavailableView("No topology resources", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Choose another namespace or refresh to read safe Kubernetes metadata."))
            } else if graph != nil && presentation == nil {
                ContentUnavailableView("Preparing topology", systemImage: "circle.dotted", description: Text("Preparing the selected Outline, Map, or Paths view…"))
            } else if let graph {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        topologyStatusCard(graph, presentation: presentation)
                        switch model.topologySurface {
                        case .outline: outlineWorkspace(graph, presentation: presentation)
                        case .map: scopedMapWorkspace(graph, presentation: presentation)
                        case .paths: pathsWorkspace(graph, presentation: presentation)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func topologyStatusCard(_ graph: TopologyGraph, presentation: TopologyExplorerPresentation?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.topologySurface.title).font(.title2.weight(.semibold))
                Text(surfaceContextLabel).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(presentation?.statusSummary ?? "\(scopedNodes.count) resources")
                    .font(.caption.monospacedDigit())
                Text(graph.completeness == .complete ? "Snapshot complete" : "Snapshot partial")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(graph.completeness == .complete ? Color.secondary : Color.orange)
            }
        }
    }

    private func outlineWorkspace(_ graph: TopologyGraph, presentation: TopologyExplorerPresentation?) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Resource outline", systemImage: "list.bullet.indent")
                    .font(.headline)
                Spacer()
                Text("sorted by scope, kind, name")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if presentation == nil {
                ProgressView("Preparing topology…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if presentation?.outline.isEmpty == true {
                ContentUnavailableView("No matching resources", systemImage: "magnifyingglass", description: Text("Clear the search or namespace filter to restore the hierarchy."))
                    .frame(minHeight: 260)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let presentation {
                        ForEach(presentation.outline) { namespace in
                            Text(namespace.namespace)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                            ForEach(namespace.controllers) { controller in
                                outlineControllerRow(controller, graph: graph)
                                if model.topologyOutlineExpandedIDs.contains(controller.id) {
                                    ForEach(controller.dependents) { dependent in
                                        presentationSummaryRow(dependent, graph: graph, depth: 1, childCount: 0)
                                    }
                                    ForEach(controller.related) { related in
                                        presentationSummaryRow(related, graph: graph, depth: 1, childCount: 0)
                                    }
                                }
                            }
                            ForEach(namespace.unattached) { unattached in
                                presentationSummaryRow(unattached, graph: graph, depth: 0, childCount: 0)
                            }
                        }
                    }
                }
            }
            Text("The outline is derived from Kubernetes API declarations and observations. It does not imply packet reachability.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func outlineControllerRow(_ controller: TopologyOutlineController, graph: TopologyGraph) -> some View {
        let childCount = controller.dependents.count + controller.related.count
        let expanded = model.topologyOutlineExpandedIDs.contains(controller.id)
        return HStack(spacing: 4) {
            Button {
                if expanded {
                    model.topologyOutlineExpandedIDs.remove(controller.id)
                } else {
                    model.topologyOutlineExpandedIDs.insert(controller.id)
                }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .frame(width: 18, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(controller.primary.kind) \(controller.primary.name)")
            .accessibilityValue("\(childCount) child resources")
            presentationSummaryRow(controller.primary, graph: graph, depth: 0, childCount: childCount)
        }
        .accessibilityElement(children: .contain)
    }

    private func presentationSummaryRow(_ summary: TopologyExplorerNodeSummary, graph: TopologyGraph, depth: Int, childCount: Int) -> some View {
        resourceRow(summary.node, graph: graph, childCount: childCount)
            .padding(.leading, CGFloat(depth) * 22)
            .background(summary.id == model.selectedTopologyNodeID ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func scopedMapWorkspace(_ graph: TopologyGraph, presentation: TopologyExplorerPresentation?) -> some View {
        let map = ScopedMapLayout(presentationMap: presentation?.map)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Scoped map", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
                Spacer()
                Picker("Expansion", selection: Binding(get: { model.topologyMapExpansionHops }, set: { model.topologyMapExpansionHops = $0 })) {
                    Text("1 hop").tag(1)
                    Text("2 hops").tag(2)
                }
                .pickerStyle(.segmented).frame(width: 126)
                Text("\(map.nodes.count) nodes · \(map.edges.count) edges").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if map.isTruncated {
                Label("Showing \(map.nodes.count) of \(map.totalNodeCount); \(map.omittedNodeCount) omitted. Refine the filter, choose another root, or return to Outline.", systemImage: "rectangle.stack.badge.minus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Map is bounded. Showing \(map.nodes.count) of \(map.totalNodeCount) nodes; \(map.omittedNodeCount) omitted. Refine the filter, choose another root, or return to Outline.")
            }
            if presentation == nil {
                ProgressView("Preparing map…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if model.selectedTopologyNodeID == nil {
                Text("Select a resource in Outline, then open Map to inspect only that root and its nearby relationships.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if presentation == nil {
                EmptyView()
            } else if map.nodes.isEmpty {
                ContentUnavailableView("Choose a map root", systemImage: "scope", description: Text("Select a resource from the Outline first."))
                    .frame(minHeight: 250)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            for edge in map.edges {
                                guard let (from, to) = map.edgePoints(for: edge) else { continue }
                                var line = Path()
                                line.move(to: from)
                                line.addLine(to: to)
                                context.stroke(line, with: .color(Color.secondary.opacity(0.48)), style: StrokeStyle(lineWidth: edge.id == model.selectedTopologyEdgeID ? 3 : 1.2))
                                let arrow = Path { path in
                                    let tip = to
                                    let direction = CGVector(dx: to.x - from.x, dy: to.y - from.y)
                                    let length = max(1, sqrt(direction.dx * direction.dx + direction.dy * direction.dy))
                                    let unit = CGVector(dx: direction.dx / length, dy: direction.dy / length)
                                    let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)
                                    path.move(to: tip)
                                    path.addLine(to: CGPoint(x: tip.x - unit.dx * 9 + perpendicular.dx * 4, y: tip.y - unit.dy * 9 + perpendicular.dy * 4))
                                    path.addLine(to: CGPoint(x: tip.x - unit.dx * 9 - perpendicular.dx * 4, y: tip.y - unit.dy * 9 - perpendicular.dy * 4))
                                    path.closeSubpath()
                                }
                                context.fill(arrow, with: .color(Color.secondary.opacity(0.68)))
                            }
                        }
                        .frame(width: map.width, height: map.height)
                        ForEach(Array(map.labelEdges.enumerated()), id: \.element.id) { index, edge in
                            if let (from, to) = map.edgePoints(for: edge) {
                                Button {
                                    model.selectedTopologyEdgeID = edge.id
                                    model.selectedTopologyNodeID = nil
                                    model.selectedTopologyPortPathID = nil
                                    model.topologyNarrowDetailVisible = true
                                } label: {
                                    Text(relationshipTitle(edge.relationship))
                                        .font(.caption2.weight(.medium))
                                        .lineLimit(1)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .frame(minWidth: 78, minHeight: 28)
                                        .background(.thinMaterial, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .position(map.labelPoint(from: from, to: to, index: index))
                                .accessibilityLabel("Relationship: \(relationshipTitle(edge.relationship))")
                                .accessibilityHint("Selects this relationship in the inspector")
                            }
                        }
                        ForEach(map.nodes) { node in
                            if let point = map.positions[node.id] {
                                Button { select(node) } label: {
                                    scopedMapCard(node, depth: map.depths[node.id] ?? 0, isRoot: node.id == map.rootID)
                                }
                                .buttonStyle(.plain)
                                .position(x: point.x + ScopedMapLayout.cardWidth / 2, y: point.y + ScopedMapLayout.cardHeight / 2)
                                .accessibilityLabel("\(node.kind) \(node.name), \(nodeStatus(node))")
                                .accessibilityHint(node.id == map.rootID ? "Selected map root" : "Selects this map resource")
                            }
                        }
                    }
                    .frame(width: map.width, height: map.height)
                    .padding(30)
                }
                .frame(minHeight: 310)
            }
            HStack(spacing: 10) {
                Label("Root", systemImage: "scope")
                Text("Cards show only the selected root and the presentation's bounded hops.")
                if !map.edges.isEmpty { Text("Select an edge badge to inspect the relationship.") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func scopedMapCard(_ node: TopologyNode, depth: Int, isRoot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: node.kind))
                Text("Depth \(depth)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if isRoot { Image(systemName: "scope").accessibilityHidden(true) }
            }
            Text(node.name).font(.callout.weight(.semibold)).lineLimit(1)
            Text(node.kind).font(.caption2).foregroundStyle(.secondary)
            Text(nodeStatus(node)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: ScopedMapLayout.cardWidth, height: ScopedMapLayout.cardHeight, alignment: .leading)
        .background(isRoot ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isRoot ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isRoot ? 2 : 1))
    }

    private func pathsWorkspace(_ graph: TopologyGraph, presentation: TopologyExplorerPresentation?) -> some View {
        let paths = preparedPortPaths(presentation)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Network paths", systemImage: "arrow.triangle.branch").font(.headline)
                Spacer()
                Text("\(paths.count) declared paths").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("Diagnostic joins are shown as typed hops and ports. A complete path remains API evidence, not a packet-capture claim.")
                .font(.caption).foregroundStyle(.secondary)
            if presentation == nil {
                ProgressView("Preparing paths…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if paths.isEmpty {
                ContentUnavailableView("No paths match", systemImage: "line.3.horizontal.decrease.circle", description: Text("Adjust search or use the namespace picker."))
                    .frame(minHeight: 260)
            } else {
                ForEach(paths) { path in
                    Button {
                        model.selectedTopologyPortPathID = path.id
                        model.selectedTopologyNodeID = nil
                        model.selectedTopologyEdgeID = nil
                        model.topologyNarrowDetailVisible = true
                    } label: {
                        portPathRow(path, graph: graph)
                    }.buttonStyle(.plain)
                }
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
            if node.facts.isEmpty || graph.details[node.id] == nil {
                relationshipFallback(node, graph: graph)
            }
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

    private func relationshipFallback(_ node: TopologyNode, graph: TopologyGraph) -> some View {
        let edges = graph.edges.filter { $0.from == node.id || $0.to == node.id }.sorted { $0.id < $1.id }
        let dependentIDs = Set(edges.compactMap { edge -> String? in
            guard edge.from == node.id else { return nil }
            return edge.to
        })
        let dependents = graph.nodes.filter { dependentIDs.contains($0.id) }.sorted(by: outlineSort)
        let readySignals = dependents.filter { nodeHasReadySignal($0) }.count
        let notReadySignals = dependents.filter { nodeHasNotReadySignal($0) }.count
        return VStack(alignment: .leading, spacing: 7) {
            Text("Observed relationships").font(.headline)
            if edges.isEmpty {
                Text("No typed relationships were observed for this resource in the current snapshot.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                statusLine("Relationships", value: "\(edges.count)")
                statusLine("Observed dependents", value: "\(dependents.count)")
                if readySignals + notReadySignals > 0 {
                    statusLine("Ready signals", value: "\(readySignals) ready · \(notReadySignals) not ready")
                }
                Text("This fallback is derived only from graph edges and child facts present in the snapshot; it does not infer controller reconciliation or health.")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(dependents.prefix(8)) { dependent in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: dependent.kind)).accessibilityHidden(true)
                        Text("\(dependent.kind) \(dependent.name)").font(.caption)
                        Spacer()
                        Text(nodeStatus(dependent)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func nodeHasReadySignal(_ node: TopologyNode) -> Bool {
        let terms = node.facts.map { "\($0.title) \($0.value)".lowercased() }.joined(separator: " ")
        return terms.contains("ready") || terms.contains("available") || terms.contains("running")
    }

    private func nodeHasNotReadySignal(_ node: TopologyNode) -> Bool {
        let terms = node.facts.map { "\($0.title) \($0.value)".lowercased() }.joined(separator: " ")
        return terms.contains("not ready") || terms.contains("failed") || terms.contains("unavailable")
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
            Text("Select a resource, relationship, or path row. The same selection is retained when you switch Outline, Map, and Paths.")
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
                let unavailable = graph.inputs.filter { $0.availability != .available }
                let unavailableDetail = unavailable.map { "\($0.resourceKind): \($0.message ?? inputAvailabilityTitle($0.availability))" }.joined(separator: " · ")
                let stateText = stale
                    ? "Showing previous snapshot — refresh failed"
                    : (graph.completeness == .complete
                        ? "Complete for requested API inputs"
                        : "Partial snapshot — \(unavailable.count) input\(unavailable.count == 1 ? "" : "s") unavailable")
                Image(systemName: stale ? "clock.badge.exclamationmark" : (graph.completeness == .complete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"))
                    .foregroundStyle(stale ? .orange : (graph.completeness == .complete ? .green : .orange))
                Text(stateText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .help(unavailableDetail.isEmpty ? stateText : unavailableDetail)
                    .accessibilityLabel(unavailableDetail.isEmpty ? stateText : "\(stateText). \(unavailableDetail)")
                Text("Updated \(Fmt.age(graph.freshness.capturedAt, relativeTo: Date())) ago")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let error = model.topologyError { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1) }
                Button("Retry") { model.requestRefresh() }.controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35))
    }

    private func outlineSort(_ lhs: TopologyNode, _ rhs: TopologyNode) -> Bool {
        let left = [lhs.namespace ?? "", lhs.kind.lowercased(), lhs.name.lowercased(), lhs.id]
        let right = [rhs.namespace ?? "", rhs.kind.lowercased(), rhs.name.lowercased(), rhs.id]
        return left.lexicographicallyPrecedes(right)
    }

    private func resourceRow(_ node: TopologyNode, graph: TopologyGraph? = nil, childCount: Int = 0) -> some View {
        HStack(spacing: 9) {
            Button { select(node) } label: {
                Image(systemName: icon(for: node.kind)).frame(width: 20)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1)
                Text("\(node.kind)\(node.namespace.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(nodeStatus(node)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            if childCount > 0 { Text("\(childCount)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            Menu {
                Button("Focus neighbors") { focusNeighbors(node) }
                if !portPaths(relatedTo: node, graph: graph ?? self.graph!).isEmpty {
                    Button("Show path") { showPath(for: node, graph: graph ?? self.graph!) }
                }
                if let kind = resourceKind(for: node) {
                    Button("Open resource") { model.jumpTo(kind: kind, namespace: node.namespace ?? "", name: node.name) }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.caption)
            }.menuStyle(.borderlessButton)
        }
        .contentShape(Rectangle())
        .onTapGesture { select(node) }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.kind) \(node.name), \(nodeStatus(node))\(childCount > 0 ? ", \(childCount) children" : "")")
        .accessibilityHint("Selects this resource. Additional actions are available in the actions menu.")
    }

    private func select(_ node: TopologyNode) {
        model.selectedTopologyNodeID = node.id
        model.selectedTopologyEdgeID = nil
        model.selectedTopologyPortPathID = nil
        model.topologyNarrowDetailVisible = true
    }

    private func focusNeighbors(_ node: TopologyNode) {
        select(node)
        model.topologyMapExpansionHops = 1
        model.setTopologySurface(.map)
    }

    private func showPath(for node: TopologyNode, graph: TopologyGraph) {
        guard let path = portPaths(relatedTo: node, graph: graph).sorted(by: { $0.id < $1.id }).first else { return }
        model.selectedTopologyNodeID = nil
        model.selectedTopologyPortPathID = path.id
        model.selectedTopologyEdgeID = nil
        model.setTopologySurface(.paths)
        model.topologyNarrowDetailVisible = true
    }

    private func nodeStatus(_ node: TopologyNode) -> String {
        let terms = node.facts.flatMap { [$0.title.lowercased(), $0.value.lowercased()] }.joined(separator: " ")
        if terms.contains("failed") || terms.contains("not ready") || terms.contains("unhealthy") { return "Needs attention" }
        if terms.contains("ready") || terms.contains("available") || terms.contains("active") || terms.contains("running") { return "Ready" }
        if node.evidence.level == .unavailable { return "Unavailable" }
        if node.evidence.level == .inferred { return "Inferred" }
        return "Observed"
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
                Text(learnerPathSummary(path, graph: graph))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let note = path.note { Text(note).font(.caption2).foregroundStyle(.orange).lineLimit(2) }
                DisclosureGroup("Raw evidence hops (\(path.hops.count))") {
                    ForEach(path.hops) { hop in
                        Text(rawHopLabel(hop))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(path.source.kind) \(path.source.name), \(learnerPathSummary(path, graph: graph)), \(path.status.title)")
    }

    private func learnerPathSummary(_ path: TopologyPortPath, graph: TopologyGraph?) -> String {
        let route = path.hops.first(where: { $0.role == "route" })
        let service = path.hops.first(where: { $0.role == "service" })
        let servicePort = path.hops.first(where: { $0.role == "service-port" })
        let endpointPort = path.hops.first(where: { $0.role == "endpoint-port" })
        let endpoints = path.hops.filter { $0.role == "endpoint" }
        let containers = path.hops.filter { $0.role == "container-port" }
        var parts: [String] = []
        if let route {
            let routeName = route.reference.map { "\($0.kind) \($0.name)" } ?? "Route"
            let port = route.portName ?? route.portNumber.map(String.init)
            var routeDetail = "\(routeName)\(port.map { " · backend \($0)" } ?? "")"
            if let graph, let routeNode = graph.nodes.first(where: { node in
                if let uid = route.reference?.uid, let nodeUID = node.uid, !uid.isEmpty { return uid == nodeUID }
                return node.kind == route.reference?.kind && node.name == route.reference?.name && node.namespace == route.reference?.namespace
            }), let details = graph.details[routeNode.id] {
                if let ingress = details.ingressRoutes.first {
                    let host = ingress.host ?? "any host"
                    let path = ingress.path ?? "/"
                    routeDetail += " · \(host)\(path)"
                } else if let hostname = details.httpRoute?.hostnames.first {
                    routeDetail += " · \(hostname)"
                }
            }
            parts.append(routeDetail)
        }
        if let service {
            parts.append("Service \(service.reference?.name ?? "unresolved")")
        }
        if let servicePort {
            var detail = "port \(servicePort.portNumber.map(String.init) ?? "?")/\(servicePort.protocolName ?? "?")"
            if let target = servicePort.targetPort {
                let targetValue = target.name ?? target.number.map(String.init) ?? (target.usesServicePortByDefault ? "same port" : "unspecified")
                detail += " · targetPort \(targetValue)"
            }
            parts.append(detail)
        }
        if let endpointPort {
            parts.append("EndpointSlice \(endpointPort.portNumber.map(String.init) ?? "?")/\(endpointPort.protocolName ?? "?")")
        }
        if !endpoints.isEmpty {
            let ready = endpoints.filter { effectiveEndpointReady($0) }.count
            let addresses = Set(endpoints.flatMap(\.addresses)).count
            parts.append("\(endpoints.count) endpoint\(endpoints.count == 1 ? "" : "s") · \(ready) ready · \(addresses) destination\(addresses == 1 ? "" : "s")")
        }
        if !containers.isEmpty {
            let names = Array(Set(containers.compactMap(\.containerName))).sorted()
            parts.append("Pod container\(names.count == 1 ? "" : "s"): \(names.isEmpty ? "declared port" : names.joined(separator: ", "))")
        } else if !endpoints.isEmpty {
            parts.append("Pod container declaration unavailable")
        }
        if parts.isEmpty { return "No typed route joins available in this snapshot" }
        return parts.joined(separator: "  →  ")
    }

    private func rawHopLabel(_ hop: TopologyPortHop) -> String {
        let reference = hop.reference.map { "\($0.kind) \($0.name)\($0.namespace.map { " · \($0)" } ?? "")" } ?? "unresolved reference"
        let port = [hop.portName, hop.portNumber.map(String.init)].compactMap { $0 }.joined(separator: ":")
        let endpoint = hop.addresses.isEmpty ? "" : " · \(hop.addresses.joined(separator: ", "))"
        return "\(hop.role): \(reference)\(port.isEmpty ? "" : " · \(port)")\(endpoint)"
    }

    private func effectiveEndpointReady(_ hop: TopologyPortHop) -> Bool {
        hop.ready != false && !(hop.terminating == true && hop.serving == false)
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

    /// Filters change the semantic result set; never leave an inspector
    /// pointing at an object that is no longer represented by that scope.
    private func validateTopologySelection() {
        guard graph != nil else {
            clearTopologySelection()
            return
        }
        let scopedNodeIDs = Set(filteredNodes.map(\.id))
        let scopedEdgeIDs = Set(visibleEdges.map(\.id))
        let scopedPathIDs = Set(filteredPortPaths.map(\.id))
        if let selected = model.selectedTopologyNodeID, !scopedNodeIDs.contains(selected) {
            model.selectedTopologyNodeID = nil
        }
        if let selected = model.selectedTopologyEdgeID, !scopedEdgeIDs.contains(selected) {
            model.selectedTopologyEdgeID = nil
        }
        if let selected = model.selectedTopologyPortPathID, !scopedPathIDs.contains(selected) {
            model.selectedTopologyPortPathID = nil
        }
        if model.selectedTopologyNodeID == nil && model.selectedTopologyEdgeID == nil && model.selectedTopologyPortPathID == nil {
            model.topologyNarrowDetailVisible = false
        }
    }

    private func clearTopologySelection() {
            model.selectedTopologyNodeID = nil
            model.selectedTopologyEdgeID = nil
            model.selectedTopologyPortPathID = nil
            model.topologyNarrowDetailVisible = false
    }

    private func portPaths(relatedTo node: TopologyNode, graph: TopologyGraph) -> [TopologyPortPath] {
        graph.portPaths.filter { path in
            referenceMatches(path.source, node: node) || path.hops.contains { hop in
                guard let reference = hop.reference else { return false }
                return referenceMatches(reference, node: node)
            }
        }
    }

    private func referenceMatches(_ reference: TopologyObjectReference, node: TopologyNode) -> Bool {
        if let referenceUID = reference.uid, let nodeUID = node.uid { return referenceUID == nodeUID }
        return reference.kind.caseInsensitiveCompare(node.kind) == .orderedSame
            && reference.name == node.name
            && reference.namespace == node.namespace
    }

    private func resourceKind(for node: TopologyNode) -> ResourceKind? {
        model.kindCatalog.first { $0.kindName.caseInsensitiveCompare(node.kind) == .orderedSame && $0.defaultAPIVersion == node.apiVersion }
            ?? model.kindCatalog.first { $0.kindName.caseInsensitiveCompare(node.kind) == .orderedSame }
    }

    private func count(kind: String, in graph: TopologyGraph) -> Int { graph.nodes.filter { $0.kind.caseInsensitiveCompare(kind) == .orderedSame }.count }
    private func trimmed(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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

private struct ScopedMapLayout {
    static let cardWidth: CGFloat = 210
    static let cardHeight: CGFloat = 104
    let rootID: String?
    let nodes: [TopologyNode]
    let edges: [TopologyEdge]
    let depths: [String: Int]
    let positions: [String: CGPoint]
    let width: CGFloat
    let height: CGFloat
    let totalNodeCount: Int
    let isTruncated: Bool
    let omittedNodeCount: Int

    var labelEdges: [TopologyEdge] {
        var seen = Set<String>()
        return edges.filter { edge in
            let key = "\(edge.from)|\(edge.to)|\(edge.relationship)"
            return seen.insert(key).inserted
        }
    }

    init(presentationMap: TopologyExplorerMap?) {
        self.rootID = presentationMap?.rootID
        guard let presentationMap else {
            nodes = []
            edges = []
            depths = [:]
            positions = [:]
            width = 640
            height = 300
            totalNodeCount = 0
            isTruncated = false
            omittedNodeCount = 0
            return
        }
        totalNodeCount = presentationMap.totalNodeCount
        isTruncated = presentationMap.isTruncated
        omittedNodeCount = presentationMap.omittedNodeCount
        let byID = Dictionary(uniqueKeysWithValues: presentationMap.nodes.map { ($0.id, $0.node) })
        var depthMap: [String: Int] = [presentationMap.rootID: 0]
        var sideMap: [String: Int] = [presentationMap.rootID: 0]
        var frontier: Set<String> = [presentationMap.rootID]
        for depth in 1...max(1, presentationMap.maxHops) {
            let candidates = presentationMap.edges.filter { frontier.contains($0.from) || frontier.contains($0.to) }
            var next: Set<String> = []
            for edge in candidates {
                let sourceIsFrontier = frontier.contains(edge.from)
                let target = sourceIsFrontier ? edge.to : edge.from
                guard depthMap[target] == nil else { continue }
                next.insert(target)
                depthMap[target] = depth
                if depth == 1 {
                    // Inbound declarations sit left of the root; outbound
                    // targets sit right. Ambiguous edges use the right side.
                    sideMap[target] = edge.to == presentationMap.rootID ? -1 : 1
                } else {
                    sideMap[target] = sideMap[sourceIsFrontier ? edge.from : edge.to] ?? 1
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        let selectedIDs = Set(depthMap.keys)
        nodes = selectedIDs.compactMap { byID[$0] }.sorted(by: { (lhs: TopologyNode, rhs: TopologyNode) in
            let leftDepth = depthMap[lhs.id] ?? 0
            let rightDepth = depthMap[rhs.id] ?? 0
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            let left = [lhs.kind.lowercased(), lhs.name.lowercased(), lhs.id]
            let right = [rhs.kind.lowercased(), rhs.name.lowercased(), rhs.id]
            return left.lexicographicallyPrecedes(right)
        })
        edges = presentationMap.edges.filter { selectedIDs.contains($0.from) && selectedIDs.contains($0.to) }.sorted { $0.id < $1.id }
        depths = depthMap
        var positionMap: [String: CGPoint] = [:]
        let columns = Dictionary(grouping: nodes) { node in
            let depth = depthMap[node.id] ?? 0
            let side = sideMap[node.id] ?? 1
            return depth == 0 ? 0 : side * depth
        }
        let maxRows = max(1, columns.values.map(\.count).max() ?? 1)
        let minimumColumn = columns.keys.min() ?? 0
        let maximumColumn = columns.keys.max() ?? 0
        // Keep the selected root in the visual center even when all one-hop
        // relationships point in the same direction.
        let sideSpan = max(1, abs(minimumColumn), abs(maximumColumn))
        for column in columns.keys.sorted() {
            let members = columns[column] ?? []
            for (row, node) in members.enumerated() {
                positionMap[node.id] = CGPoint(x: CGFloat(column + sideSpan) * 270, y: CGFloat(row) * 132 + (column == 0 ? CGFloat(maxRows - 1) * 66 : 0))
            }
        }
        positions = positionMap
        width = max(620, CGFloat(sideSpan * 2 + 1) * 270 + 80)
        height = max(260, CGFloat(maxRows) * 132 + 70)
    }

    func edgePoints(for edge: TopologyEdge) -> (CGPoint, CGPoint)? {
        guard let fromTopLeft = positions[edge.from], let toTopLeft = positions[edge.to] else { return nil }
        let fromCenter = CGPoint(x: fromTopLeft.x + Self.cardWidth / 2, y: fromTopLeft.y + Self.cardHeight / 2)
        let toCenter = CGPoint(x: toTopLeft.x + Self.cardWidth / 2, y: toTopLeft.y + Self.cardHeight / 2)
        let vector = CGVector(dx: toCenter.x - fromCenter.x, dy: toCenter.y - fromCenter.y)
        let horizontal = abs(vector.dx) >= abs(vector.dy)
        if horizontal {
            let sign = vector.dx >= 0 ? 1.0 : -1.0
            return (
                CGPoint(x: fromCenter.x + sign * Self.cardWidth / 2, y: fromCenter.y),
                CGPoint(x: toCenter.x - sign * Self.cardWidth / 2, y: toCenter.y)
            )
        }
        let sign = vector.dy >= 0 ? 1.0 : -1.0
        return (
            CGPoint(x: fromCenter.x, y: fromCenter.y + sign * Self.cardHeight / 2),
            CGPoint(x: toCenter.x, y: toCenter.y - sign * Self.cardHeight / 2)
        )
    }

    func labelPoint(from: CGPoint, to: CGPoint, index: Int) -> CGPoint {
        let midpoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let horizontal = abs(to.x - from.x) >= abs(to.y - from.y)
        let laneOffset = CGFloat((index % 3) - 1) * 30
        if horizontal {
            return CGPoint(x: midpoint.x, y: midpoint.y + laneOffset)
        }
        return CGPoint(x: midpoint.x + laneOffset, y: midpoint.y)
    }
}

private extension TopologyExplorerSurface {
    var title: String {
        switch self {
        case .outline: return "Outline"
        case .map: return "Map"
        case .paths: return "Paths"
        }
    }
    var icon: String {
        switch self {
        case .outline: return "list.bullet.indent"
        case .map: return "point.3.connected.trianglepath.dotted"
        case .paths: return "arrow.triangle.branch"
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
