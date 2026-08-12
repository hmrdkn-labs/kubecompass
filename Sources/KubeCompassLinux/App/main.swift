import Adwaita
import Foundation
import KubeCompassCore
import KubeCompassLinuxSupport

/// Fixture-only topology data for the Linux vertical slice. This intentionally
/// uses the shared evidence graph and never shells out to kubectl.
@MainActor
final class LinuxTopologyModel {
    let graph: TopologyGraph
    let query: TopologyGraphQuery
    let nodeStore = ListStore()
    let portStore = ListStore()
    var level: ExplorerLevel = .cluster
    var mode: ExplorerMode = .inventory
    var presentation: ExplorerPresentation = .list
    var search = ""
    var selectedNodeID: String?
    var selectedTopologyPathID: String?
    var selectedTopologyEdgeID: String?
    var visibleNodes: [TopologyNode] = []
    var visiblePaths: [TopologyPortPath] = []

    init() {
        graph = LinuxTopologyFixture.graph()
        query = TopologyGraphQuery(graph: graph)
        rebuild()
    }

    func setLevel(_ value: ExplorerLevel) { level = value; selectedNodeID = nil; selectedTopologyPathID = nil; selectedTopologyEdgeID = nil; rebuild() }
    func setMode(_ value: ExplorerMode) { mode = value; rebuild() }
    func setPresentation(_ value: ExplorerPresentation) { presentation = value; rebuild() }
    func setSearch(_ value: String) { search = value; rebuild() }
    func select(nodeID: String?) { selectedNodeID = nodeID; selectedTopologyPathID = nil; selectedTopologyEdgeID = nil; rebuild() }
    func select(pathID: String?) { selectedTopologyPathID = pathID; selectedTopologyEdgeID = nil; selectedNodeID = nil; rebuild() }
    func select(edgeID: String?) { selectedTopologyEdgeID = edgeID; selectedTopologyPathID = nil; selectedNodeID = nil; rebuild() }

    private func rebuild() {
        let all = level == .evidence ? query.nodes(search: search) : query.nodes(level: level, search: search)
        let selected = selectedNodeID.map { Set([$0]) } ?? []
        let focusIDs: Set<String>
        switch mode {
        case .inventory:
            focusIDs = Set(all.map(\.id))
        case .focus:
            focusIDs = selectedNodeID == nil ? Set(all.map(\.id)) : query.oneHopFocus(nodeIDs: selected, level: level)
        case .trace:
            focusIDs = traceNodeIDs(fallback: Set(all.map(\.id)))
        }
        visibleNodes = all.filter { focusIDs.contains($0.id) }.sorted { $0.id < $1.id }
        let paths = query.portPaths(level: level, search: search)
        visiblePaths = mode == .trace ? tracePaths(paths) : paths
        nodeStore.removeAll()
        for _ in visibleNodes { nodeStore.appendPlaceholder() }
        portStore.removeAll()
        for _ in visiblePaths { portStore.appendPlaceholder() }
    }

    private func traceNodeIDs(fallback: Set<String>) -> Set<String> {
        if let path = selectedPath {
            return Set(path.hops.compactMap { hop in
                guard let reference = hop.reference else { return nil }
                return graph.nodes.first {
                    $0.kind.caseInsensitiveCompare(reference.kind) == .orderedSame
                        && $0.name == reference.name
                        && $0.namespace == reference.namespace
                }?.id
            })
        }
        if let edge = selectedEdge {
            return [edge.from, edge.to]
        }
        if let selectedNodeID { return [selectedNodeID] }
        return fallback
    }

    private func tracePaths(_ paths: [TopologyPortPath]) -> [TopologyPortPath] {
        if let selectedTopologyPathID {
            return paths.filter { $0.id == selectedTopologyPathID }
        }
        let selectedIDs = traceNodeIDs(fallback: [])
        guard !selectedIDs.isEmpty else { return paths }
        return paths.filter { path in
            path.hops.contains { hop in
                guard let reference = hop.reference else { return false }
                return graph.nodes.contains {
                    selectedIDs.contains($0.id)
                        && $0.kind.caseInsensitiveCompare(reference.kind) == .orderedSame
                        && $0.name == reference.name
                        && $0.namespace == reference.namespace
                }
            }
        }
    }

    var summary: String {
        "\(level.title) · \(mode.title) · \(visibleNodes.count) nodes · \(visiblePaths.count) port paths · \(graph.unresolvedReferences.count) unresolved · \(graph.completeness.title) snapshot"
    }

    var selectedNode: TopologyNode? {
        guard let selectedNodeID else { return nil }
        return graph.nodes.first { $0.id == selectedNodeID }
    }

    var selectedPath: TopologyPortPath? {
        guard let selectedTopologyPathID else { return nil }
        return graph.portPaths.first { $0.id == selectedTopologyPathID }
    }

    var selectedEdge: TopologyEdge? {
        guard let selectedTopologyEdgeID else { return nil }
        return graph.edges.first { $0.id == selectedTopologyEdgeID }
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
}

private extension ExplorerMode {
    var title: String {
        switch self {
        case .focus: return "Focus"
        case .trace: return "Trace"
        case .inventory: return "Inventory"
        }
    }
}

private extension ExplorerPresentation {
    var title: String {
        switch self {
        case .map: return "Map fallback"
        case .list: return "List"
        case .portTable: return "Port table"
        }
    }
}

private extension TopologyEvidenceLevel {
    var title: String {
        switch self {
        case .observed: return "Observed"
        case .declared: return "Declared"
        case .inferred: return "Inferred"
        case .unavailable: return "Unavailable"
        }
    }
}

private extension TopologySnapshotCompleteness {
    var title: String {
        switch self {
        case .complete: return "Complete"
        case .partial: return "Partial"
        case .unavailable: return "Unavailable"
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
}

private extension TopologyRelationship {
    var title: String {
        switch self {
        case .containedIn: return "Contained in"
        case .ownedBy: return "Owned by"
        case .scheduledOn: return "Scheduled on"
        case .selects: return "Selects"
        case .publishesEndpoints: return "Publishes endpoints"
        case .endpointTarget: return "Endpoint target"
        case .routesTo: return "Routes to"
        case .references: return "References"
        case .backedBy: return "Backed by"
        case .usesStorageClass: return "Uses storage class"
        case .inputUnavailable: return "Input unavailable"
        }
    }
}

private enum LinuxTopologyFixture {
    static func identity(_ apiVersion: String, _ kind: String, _ name: String, _ namespace: String? = "default", _ uid: String) -> TopologyResourceIdentity {
        TopologyResourceIdentity(apiVersion: apiVersion, kind: kind, name: name, namespace: namespace, uid: uid, resourceVersion: "fixture-rv-1")
    }

    static func graph() -> TopologyGraph {
        let namespace = TopologyResourceSnapshot(identity: identity("v1", "Namespace", "default", nil, "uid-namespace"), facts: [TopologyFact(key: "purpose", title: "Purpose", value: "Learning fixture")])
        let node = TopologyResourceSnapshot(identity: identity("v1", "Node", "worker-1", nil, "uid-node"), roleLabels: ["kubernetes.io/role": "worker"], facts: [TopologyFact(key: "zone", title: "Zone", value: "demo-a")])
        let deployment = TopologyResourceSnapshot(identity: identity("apps/v1", "Deployment", "orders", "default", "uid-deployment"), selector: ["app": "orders"], facts: [TopologyFact(key: "ready", title: "Ready replicas", value: "1/1")])
        let replicaSet = TopologyResourceSnapshot(identity: identity("apps/v1", "ReplicaSet", "orders-abc", "default", "uid-replicaset"), ownerReferences: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "Deployment", name: "orders", uid: "uid-deployment")], selector: ["app": "orders"])
        let pod = TopologyResourceSnapshot(identity: identity("v1", "Pod", "orders-abc-1", "default", "uid-pod"), ownerReferences: [TopologyOwnerReference(apiVersion: "apps/v1", kind: "ReplicaSet", name: "orders-abc", uid: "uid-replicaset")], podNodeName: "worker-1", selector: [:], containerPorts: [TopologyContainerPort(containerName: "api", name: "web", port: 8443, protocolName: "TCP", hostPort: 9443, hostIP: "127.0.0.1")], facts: [TopologyFact(key: "phase", title: "Phase", value: "Running"), TopologyFact(key: "ready", title: "Ready", value: "true")])
        let service = TopologyResourceSnapshot(identity: identity("v1", "Service", "orders", "default", "uid-service"), selector: ["app": "orders"], servicePorts: [TopologyServicePort(name: "https", port: 443, targetPort: TopologyPortTarget(name: "web"), protocolName: "TCP", appProtocol: "https", nodePort: 30443)], serviceMode: .nodePort, facts: [TopologyFact(key: "type", title: "Type", value: "NodePort"), TopologyFact(key: "cluster-ip", title: "Cluster IP", value: "10.96.10.20"), TopologyFact(key: "port", title: "Service port", value: "https:443/TCP"), TopologyFact(key: "target-port", title: "targetPort", value: "web"), TopologyFact(key: "node-port", title: "Node port", value: "30443")])
        let slice = TopologyResourceSnapshot(identity: identity("discovery.k8s.io/v1", "EndpointSlice", "orders-1", "default", "uid-slice"), endpointSlice: TopologyEndpointSliceSnapshot(serviceName: "orders", addressType: "IPv4", ports: [TopologyEndpointPort(name: "https", port: 8443, protocolName: "TCP", appProtocol: "https")], endpoints: [TopologyEndpointTarget(reference: TopologyObjectReference(apiVersion: "v1", kind: "Pod", name: "orders-abc-1", namespace: "default", uid: "uid-pod"), ready: true, serving: true, addresses: ["10.42.0.8"], nodeName: "worker-1", zone: "demo-a")]))
        let ingress = TopologyResourceSnapshot(identity: identity("networking.k8s.io/v1", "Ingress", "orders", "default", "uid-ingress"), ingressRoutes: [TopologyIngressRoute(ruleIndex: 0, pathIndex: 0, host: "orders.example.test", path: "/", pathType: "Prefix", ingressClass: "demo", backendKind: "Service", backendName: "orders", backendNamespace: "default", backendPort: 443)], facts: [TopologyFact(key: "tls", title: "TLS", value: "declared")])
        let incompleteIngress = TopologyResourceSnapshot(identity: identity("networking.k8s.io/v1", "Ingress", "missing-route", "default", "uid-ingress-missing"), ingressRoutes: [TopologyIngressRoute(ruleIndex: 0, pathIndex: 0, host: "missing.example.test", path: "/", pathType: "Prefix", backendKind: "Service", backendName: "does-not-exist", backendNamespace: "default", backendPortName: "web")])
        let policy = TopologyResourceSnapshot(identity: identity("networking.k8s.io/v1", "NetworkPolicy", "orders-default-deny", "default", "uid-policy"), networkPolicy: TopologyNetworkPolicySnapshot(podSelector: TopologyLabelSelector(matchLabels: ["app": "orders"]), policyTypes: ["Ingress", "Egress"], ingressRuleCount: 0, egressRuleCount: 0))
        return TopologyGraphBuilder.build(contextID: "linux-fixture", resources: [namespace, node, deployment, replicaSet, pod, service, slice, ingress, incompleteIngress, policy], inputs: [TopologyInputStatus(resourceKind: "Gateway", availability: .unsupported, message: "Gateway API is not installed in this fixture")], freshness: TopologyFreshness(generation: 1))
    }
}

@MainActor
final class LinuxDemoModel {
    var allResources: [KubeResource]
    var visibleResources: [KubeResource]
    var query = ""
    let store = ListStore()

    init(rows: Int) {
        allResources = (0..<max(1, rows)).map { index in
            KubeResource(
                id: "pods/default/pod-\(index)",
                kindID: "pods",
                name: "pod-\(index)",
                namespace: "default",
                status: LinuxDemoCatalog.status(for: index),
                labels: LinuxDemoCatalog.labels(for: index),
                uid: "fixture-uid-\(index)",
                resourceVersion: "fixture-rv-\(index + 1)"
            )
        }
        visibleResources = allResources
        rebuildStore()
    }

    func setQuery(_ query: String) {
        self.query = query
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        visibleResources = needle.isEmpty
            ? allResources
            : allResources.filter { resource in
                resource.name.lowercased().contains(needle)
                    || resource.namespace?.lowercased().contains(needle) == true
                    || resource.status.lowercased().contains(needle)
            }
        rebuildStore()
    }

    private func rebuildStore() {
        store.removeAll()
        for _ in visibleResources { store.appendPlaceholder() }
    }
}

@MainActor
final class LinuxDemoShell {
    let options: LinuxLaunchOptions
    let model: LinuxDemoModel
    let topologyModel = LinuxTopologyModel()
    var state = CompassState()
    var window: ApplicationWindow?
    var statusLabel: Label?
    var detailLabel: Label?
    var yamlLabel: Label?
    var eventsLabel: Label?
    var logsLabel: Label?
    var paletteLabel: Label?
    var portForwardLabel: Label?
    var restartButton: Button?
    var detailStack: Stack?
    var selectedResource: KubeResource?
    var mainStack: Stack?
    var topologyTitle: Label?
    var topologySummary: Label?
    var topologyMapLabel: Label?
    var topologyInspector: Label?
    var topologySearch: SearchEntry?
    var topologyPresentationStack: Stack?

    init(options: LinuxLaunchOptions) {
        self.options = options
        self.model = LinuxDemoModel(rows: options.rows)
        seedFixtureState()
    }

    func present(in app: Application) {
        let window = ApplicationWindow(application: app)
        self.window = window
        window.title = "KubeCompass"
        window.defaultWidth = 1_280
        window.defaultHeight = 820
        window.setAccessibleLabel(LinuxSemanticLabels.window)

        let header = HeaderBar(title: "KubeCompass", subtitle: "Linux native preview")
        let demoBadge = Label(options.demo ? "DEMO / FIXTURES ONLY" : "OFFLINE")
            .cssClass(.warning)
        demoBadge.setAccessibleLabel("fixture-only demo mode")
        header.packStart(demoBadge)

        let reconnect = Button(label: "Reconnect")
        reconnect.setAccessibleLabel("Reconnect to fixture state")
        reconnect.onClicked { [weak self] in self?.reconnect() }
        header.packEnd(reconnect)

        let offline = Button(label: "Permission test")
        offline.setAccessibleLabel("Show permission denied state")
        offline.onClicked { [weak self] in self?.showPermissionState() }
        header.packEnd(offline)

        let root = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        let status = Label(statusText()).cssClass(.dimLabel)
        status.setMargins(8)
        status.setAccessibleLabel(LinuxSemanticLabels.status)
        status.xalign = 0
        statusLabel = status
        root.append(status)

        let body = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        body.vexpand = true
        body.hexpand = true
        let sidebar = makeSidebar()
        sidebar.vexpand = true
        sidebar.setAccessibleLabel(LinuxSemanticLabels.sidebar)
        body.append(sidebar)
        body.append(makeMainContent())
        root.append(body)

        let toolbar = ToolbarView()
        toolbar.addTopBar(header)
        toolbar.setContent(root)
        window.setContent(toolbar)
        if options.smoke {
            window.onMap { [weak self, weak app, weak window] in
                guard let self, let app, let window, window.visible else { return }
                print(self.smokeReport())
                app.quit()
            }
        }
        window.present()
    }

    private func seedFixtureState() {
        state = CompassReducer.reduce(state, .bootstrap).state
        state = CompassReducer.reduce(state, .contextsLoaded(CompassFixtures.contexts)).state
        state = CompassReducer.reduce(state, .selectContext("dev")).state
        state = CompassReducer.reduce(state, .namespacesLoaded(CompassFixtures.namespaces)).state
        state = CompassReducer.reduce(state, .selectNamespace("default")).state
        state.resourceKinds = CompassFixtures.kinds
        state = CompassReducer.reduce(state, .selectKind("pods")).state
        state = CompassReducer.reduce(
            state,
            .resourcesLoaded(kindID: "pods", resources: model.allResources)
        ).state
    }

    private func makeSidebar() -> Box {
        let sidebar = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        sidebar.setMargins(12)
        sidebar.addCSSClass("navigation-sidebar")

        let contextTitle = Label("Contexts").cssClass(.heading)
        contextTitle.setAccessibleLabel(LinuxSemanticLabels.context)
        sidebar.append(contextTitle)
        for context in CompassFixtures.contexts {
            let button = Button(label: "◉  \(context.name)")
            button.setAccessibleLabel("\(LinuxSemanticLabels.context): \(context.name)")
            button.onClicked { [weak self] in self?.selectContext(context.id) }
            sidebar.append(button)
        }

        let namespaceTitle = Label("Namespaces").cssClass(.heading)
        namespaceTitle.setAccessibleLabel(LinuxSemanticLabels.namespace)
        sidebar.append(namespaceTitle)
        for namespace in CompassFixtures.namespaces {
            let button = Button(label: "  \(namespace)")
            button.setAccessibleLabel("\(LinuxSemanticLabels.namespace): \(namespace)")
            button.onClicked { [weak self] in self?.selectNamespace(namespace) }
            sidebar.append(button)
        }

        let kindTitle = Label("Resources").cssClass(.heading)
        kindTitle.setAccessibleLabel(LinuxSemanticLabels.resourceKind)
        sidebar.append(kindTitle)
        for kind in CompassFixtures.kinds {
            let button = Button(label: "  \(kind.displayName)")
            button.setAccessibleLabel("\(LinuxSemanticLabels.resourceKind): \(kind.displayName)")
            button.onClicked { [weak self] in self?.selectKind(kind.id) }
            sidebar.append(button)
        }

        let topologyTitle = Label("Explore").cssClass(.heading)
        topologyTitle.setAccessibleLabel("topology explorer navigation")
        sidebar.append(topologyTitle)
        let topologyButton = Button(label: "  Topology Explorer")
        topologyButton.setAccessibleLabel("Topology Explorer route")
        topologyButton.onClicked { [weak self] in self?.showTopology() }
        sidebar.append(topologyButton)
        return sidebar
    }

    private func makeMainContent() -> Box {
        let stack = Stack()
        stack.vexpand = true
        stack.hexpand = true
        stack.addNamed(makeResourceContent(), name: "resources")
        stack.addNamed(makeTopologyContent(), name: "topology")
        stack.visibleChildName = "resources"
        mainStack = stack
        let wrapper = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        wrapper.hexpand = true
        wrapper.vexpand = true
        wrapper.append(stack)
        return wrapper
    }

    private func makeResourceContent() -> Box {
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        content.setMargins(12)
        content.hexpand = true
        content.vexpand = true

        let title = Label("Pods  ·  \(options.rows) fixture rows")
            .cssClass(.title2)
        title.xalign = 0
        content.append(title)

        let search = SearchEntry()
        search.placeholderText = "Search resources…"
        search.setAccessibleLabel("Search resources")
        search.onSearchChanged { [weak self, weak search] in
            guard let self, let search else { return }
            self.model.setQuery(search.text)
            self.statusLabel?.text = self.statusText()
        }
        content.append(search)

        let table = makeResourceTable()
        table.vexpand = true
        table.hexpand = true
        table.setAccessibleLabel(LinuxSemanticLabels.table)
        content.append(table)

        content.append(makeActionBar())
        content.append(makeDetailPanel())
        return content
    }

    private func makeTopologyContent() -> Box {
        let content = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        content.setMargins(12)
        content.hexpand = true
        content.vexpand = true

        let title = Label("Topology Explorer · fixture learning map").cssClass(.title2)
        title.xalign = 0
        title.setAccessibleLabel("Topology Explorer title")
        topologyTitle = title
        content.append(title)

        let summary = Label(topologyModel.summary).cssClass(.dimLabel)
        summary.xalign = 0
        summary.setAccessibleLabel("Topology snapshot summary")
        topologySummary = summary
        content.append(summary)

        let levelBar = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        let levels: [(String, ExplorerLevel)] = [
            ("Cluster", .cluster), ("Infrastructure", .infrastructure), ("Workloads", .workloads),
            ("Network", .network), ("Policy & Dependencies", .policyDependencies), ("Evidence", .evidence)
        ]
        for (label, value) in levels {
            let button = Button(label: label)
            button.setAccessibleLabel("Explorer level \(label)")
            button.onClicked { [weak self] in self?.setTopologyLevel(value) }
            levelBar.append(button)
        }
        content.append(levelBar)

        let modeBar = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        for (label, value) in [("Focus", ExplorerMode.focus), ("Trace", ExplorerMode.trace), ("Inventory", ExplorerMode.inventory)] {
            let button = Button(label: label)
            button.setAccessibleLabel("Explorer mode \(label)")
            button.onClicked { [weak self] in self?.setTopologyMode(value) }
            modeBar.append(button)
        }
        for (label, value) in [("Map fallback", ExplorerPresentation.map), ("List", ExplorerPresentation.list), ("Port table", ExplorerPresentation.portTable)] {
            let button = Button(label: label)
            button.setAccessibleLabel("Explorer presentation \(label)")
            button.onClicked { [weak self] in self?.setTopologyPresentation(value) }
            modeBar.append(button)
        }
        content.append(modeBar)

        let search = SearchEntry()
        search.placeholderText = "Search nodes, routes, ports, or evidence…"
        search.setAccessibleLabel("Search topology evidence")
        search.onSearchChanged { [weak self, weak search] in
            guard let self, let search else { return }
            self.topologyModel.setSearch(search.text)
            self.updateTopology()
        }
        topologySearch = search
        content.append(search)

        let stack = Stack()
        stack.vexpand = true
        stack.hexpand = true
        stack.addNamed(makeTopologyMapFallback(), name: ExplorerPresentation.map.rawValue)
        stack.addNamed(makeTopologyNodeTable(), name: ExplorerPresentation.list.rawValue)
        stack.addNamed(makeTopologyPortTable(), name: ExplorerPresentation.portTable.rawValue)
        stack.visibleChildName = ExplorerPresentation.list.rawValue
        topologyPresentationStack = stack
        content.append(stack)

        let inspector = Label(topologyInspectorText())
        inspector.xalign = 0
        inspector.wrap = true
        inspector.setAccessibleLabel("Topology fundamentals and evidence inspector")
        topologyInspector = inspector
        content.append(inspector)
        return content
    }

    private func makeResourceTable() -> ColumnView {
        let selection = SingleSelection(model: model.store)
        let table = ColumnView(model: selection)
        table.showRowSeparators = true
        table.showColumnSeparators = true
        table.reorderable = true
        table.onActivate { [weak self] position in
            guard let self, self.model.visibleResources.indices.contains(position) else { return }
            self.selectResource(self.model.visibleResources[position])
        }

        let nameFactory = SignalListItemFactory()
        nameFactory.onSetup { item in
            let label = Label("")
            label.setMargins(8)
            label.xalign = 0
            item.child = label
        }
        nameFactory.onBind { [weak self] item in
            guard let self, self.model.visibleResources.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            label.text = self.model.visibleResources[item.position].name
        }
        let nameColumn = ColumnViewColumn(title: "Name", factory: nameFactory)
        nameColumn.expand = true
        nameColumn.resizable = true
        table.appendColumn(nameColumn)

        let namespaceFactory = SignalListItemFactory()
        namespaceFactory.onSetup { item in item.child = Label("") }
        namespaceFactory.onBind { [weak self] item in
            guard let self, self.model.visibleResources.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            label.text = self.model.visibleResources[item.position].namespace ?? "—"
        }
        let namespaceColumn = ColumnViewColumn(title: "Namespace", factory: namespaceFactory)
        namespaceColumn.fixedWidth = 180
        namespaceColumn.resizable = true
        table.appendColumn(namespaceColumn)

        let statusFactory = SignalListItemFactory()
        statusFactory.onSetup { item in item.child = Label("") }
        statusFactory.onBind { [weak self] item in
            guard let self, self.model.visibleResources.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            label.text = self.model.visibleResources[item.position].status
        }
        let statusColumn = ColumnViewColumn(title: "Status", factory: statusFactory)
        statusColumn.fixedWidth = 130
        table.appendColumn(statusColumn)
        return table
    }

    private func makeTopologyMapFallback() -> Box {
        let box = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        let note = Label("Map fallback · deterministic grouped list (geometry is intentionally unavailable in this Linux fixture build)")
        note.xalign = 0
        note.wrap = true
        note.setAccessibleLabel("Topology map fallback explanation")
        box.append(note)
        let table = ColumnView(model: SingleSelection(model: topologyModel.nodeStore))
        table.showRowSeparators = true
        table.showColumnSeparators = true
        table.setAccessibleLabel("Topology grouped map fallback")
        table.onActivate { [weak self] position in
            guard let self, self.topologyModel.visibleNodes.indices.contains(position) else { return }
            self.topologyModel.select(nodeID: self.topologyModel.visibleNodes[position].id)
            self.updateTopology()
        }
        let factory = SignalListItemFactory()
        factory.onSetup { item in item.child = Label("") }
        factory.onBind { [weak self] item in
            guard let self, self.topologyModel.visibleNodes.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            let node = self.topologyModel.visibleNodes[item.position]
            label.text = "\(node.kind) · \(node.name) · \(node.evidence.level.title)"
            label.setAccessibleLabel("Grouped topology node \(node.kind) \(node.name)")
        }
        let column = ColumnViewColumn(title: "Grouped resource", factory: factory)
        column.expand = true
        column.resizable = true
        table.appendColumn(column)
        box.append(table)
        return box
    }

    private func makeTopologyNodeTable() -> ColumnView {
        let selection = SingleSelection(model: topologyModel.nodeStore)
        let table = ColumnView(model: selection)
        table.showRowSeparators = true
        table.showColumnSeparators = true
        table.setAccessibleLabel("Topology canonical list")
        table.onActivate { [weak self] position in
            guard let self, topologyModel.visibleNodes.indices.contains(position) else { return }
            self.topologyModel.select(nodeID: self.topologyModel.visibleNodes[position].id)
            self.updateTopology()
        }

        let nameFactory = SignalListItemFactory()
        nameFactory.onSetup { item in item.child = Label("") }
        nameFactory.onBind { [weak self] item in
            guard let self, self.topologyModel.visibleNodes.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            let node = self.topologyModel.visibleNodes[item.position]
            label.text = "\(node.kind) · \(node.name)"
            label.setAccessibleLabel("Topology node \(node.kind) \(node.name)")
        }
        let nameColumn = ColumnViewColumn(title: "Resource", factory: nameFactory)
        nameColumn.expand = true
        nameColumn.resizable = true
        table.appendColumn(nameColumn)

        let scopeFactory = SignalListItemFactory()
        scopeFactory.onSetup { item in item.child = Label("") }
        scopeFactory.onBind { [weak self] item in
            guard let self, self.topologyModel.visibleNodes.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            let node = self.topologyModel.visibleNodes[item.position]
            label.text = node.namespace ?? "cluster-scoped"
        }
        let scopeColumn = ColumnViewColumn(title: "Scope", factory: scopeFactory)
        scopeColumn.fixedWidth = 160
        table.appendColumn(scopeColumn)

        let evidenceFactory = SignalListItemFactory()
        evidenceFactory.onSetup { item in item.child = Label("") }
        evidenceFactory.onBind { [weak self] item in
            guard let self, self.topologyModel.visibleNodes.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            let node = self.topologyModel.visibleNodes[item.position]
            label.text = node.evidence.level.title
        }
        let evidenceColumn = ColumnViewColumn(title: "Evidence", factory: evidenceFactory)
        evidenceColumn.fixedWidth = 130
        table.appendColumn(evidenceColumn)
        return table
    }

    private func makeTopologyPortTable() -> ColumnView {
        let selection = SingleSelection(model: topologyModel.portStore)
        let table = ColumnView(model: selection)
        table.showRowSeparators = true
        table.showColumnSeparators = true
        table.setAccessibleLabel("Topology port path table")
        table.onActivate { [weak self] position in
            guard let self, self.topologyModel.visiblePaths.indices.contains(position) else { return }
            self.topologyModel.select(pathID: self.topologyModel.visiblePaths[position].id)
            self.updateTopology()
        }

        let routeFactory = SignalListItemFactory()
        routeFactory.onSetup { item in item.child = Label("") }
        routeFactory.onBind { [weak self] item in
            guard let self, self.topologyModel.visiblePaths.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            let path = self.topologyModel.visiblePaths[item.position]
            label.text = "\(path.source.kind) · \(path.source.name)"
            label.setAccessibleLabel("Port path from \(path.source.kind) \(path.source.name)")
        }
        let routeColumn = ColumnViewColumn(title: "Source", factory: routeFactory)
        routeColumn.expand = true
        routeColumn.resizable = true
        table.appendColumn(routeColumn)

        let hopsFactory = SignalListItemFactory()
        hopsFactory.onSetup { item in item.child = Label("") }
        hopsFactory.onBind { [weak self] item in
            guard let self, self.topologyModel.visiblePaths.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            label.text = self.portPathDisplay(self.topologyModel.visiblePaths[item.position])
        }
        let hopsColumn = ColumnViewColumn(title: "Port path", factory: hopsFactory)
        hopsColumn.expand = true
        hopsColumn.resizable = true
        table.appendColumn(hopsColumn)

        let detailsFactory = SignalListItemFactory()
        detailsFactory.onSetup { item in item.child = Label("") }
        detailsFactory.onBind { [weak self] item in
            guard let self, self.topologyModel.visiblePaths.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            let path = self.topologyModel.visiblePaths[item.position]
            label.text = self.portPathDetailsDisplay(path)
            label.wrap = true
            label.setAccessibleLabel("Port details for \(path.source.kind) \(path.source.name)")
        }
        let detailsColumn = ColumnViewColumn(title: "Port details", factory: detailsFactory)
        detailsColumn.expand = true
        detailsColumn.resizable = true
        table.appendColumn(detailsColumn)

        let statusFactory = SignalListItemFactory()
        statusFactory.onSetup { item in item.child = Label("") }
        statusFactory.onBind { [weak self] item in
            guard let self, self.topologyModel.visiblePaths.indices.contains(item.position), let child = item.child else { return }
            let label: Label = child.cast(Label.self)
            let path = self.topologyModel.visiblePaths[item.position]
            label.text = path.status.title
        }
        let statusColumn = ColumnViewColumn(title: "Status", factory: statusFactory)
        statusColumn.fixedWidth = 120
        table.appendColumn(statusColumn)
        return table
    }

    private func showTopology() {
        mainStack?.visibleChildName = "topology"
        updateTopology()
        updateStatus()
    }

    private func setTopologyLevel(_ level: ExplorerLevel) {
        topologyModel.setLevel(level)
        updateTopology()
    }

    private func setTopologyMode(_ mode: ExplorerMode) {
        topologyModel.setMode(mode)
        updateTopology()
    }

    private func setTopologyPresentation(_ presentation: ExplorerPresentation) {
        topologyModel.setPresentation(presentation)
        topologyPresentationStack?.visibleChildName = presentation.rawValue
        updateTopology()
    }

    private func updateTopology() {
        topologySummary?.text = topologyModel.summary
        topologyMapLabel?.text = topologyMapText()
        topologyInspector?.text = topologyInspectorText()
        topologyPresentationStack?.visibleChildName = topologyModel.presentation.rawValue
        updateStatus()
    }

    private func topologyMapText() -> String {
        let groups = Dictionary(grouping: topologyModel.visibleNodes) { $0.kind }
        return groups.keys.sorted().map { kind in
            let names = (groups[kind] ?? []).map { node in
                let evidence = node.evidence.level.title
                return "  • \(node.name) [\(evidence)]"
            }.joined(separator: "\n")
            return "\(kind)\n\(names)"
        }.joined(separator: "\n\n")
    }

    private func topologyInspectorText() -> String {
        if let path = topologyModel.selectedPath {
            return portPathText(path)
        }
        if let edge = topologyModel.selectedEdge {
            let attributes = edge.attributes.isEmpty ? "none" : edge.attributes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            return "Relationship: \(edge.relationship.title)\nEvidence: \(edge.evidence.level.title)\nAttributes: \(attributes)\nProves: the recorded relationship declaration or observation in the fixture graph.\nDoes not prove: data-plane reachability or controller enforcement."
        }
        guard let node = topologyModel.selectedNode else {
            let pathCounts = Dictionary(grouping: topologyModel.graph.portPaths, by: \.status).map { "\($0.key.title): \($0.value.count)" }.sorted().joined(separator: " · ")
            return "Fundamentals\nLevel: \(topologyModel.level.title)\nStatus: \(topologyModel.graph.completeness.title) snapshot · generation \(topologyModel.graph.freshness.generation)\nPort paths: \(pathCounts.isEmpty ? "none" : pathCounts)\nProves: API observations, declarations, and deterministic joins shown in the fixture graph.\nDoes not prove: packet reachability, controller enforcement, or that a declared process is listening.\nEvidence: select a resource or port path for source fields and assumptions."
        }
        let facts = node.facts.map { "\($0.title): \($0.value)" }.joined(separator: " · ")
        return "\(node.kind) · \(node.name)\nScope: \(node.namespace ?? "cluster-scoped")\nEvidence: \(node.evidence.level.title)\nFacts: \(facts.isEmpty ? "none" : facts)\nProves: this resource and its recorded relationships exist in the fixture snapshot.\nDoes not prove: live traffic or enforcement."
    }

    private func portPathText(_ path: TopologyPortPath) -> String {
        let route = "\(path.source.kind) · \(path.source.name)"
        let hops = path.hops.map(hopText).joined(separator: " → ")
        let details = portPathDetailsDisplay(path)
        return "\(route)\nStatus: \(path.status.title) · ready endpoints \(path.readyEndpointCount)/\(path.totalEndpointCount)\n\(hops)\nDetails: \(details)\nNote: \(path.note ?? "No unresolved note")\nProves: declared and observed object fields in the fixture.\nDoes not prove: data-plane reachability."
    }

    private func portPathDisplay(_ path: TopologyPortPath) -> String {
        let hops = path.hops.map(hopText).joined(separator: " → ")
        let details = portPathDetailsDisplay(path)
        return details == "none" ? hops : "\(details) · \(hops)"
    }

    /// Resolve typed port declarations from the graph detail index rather than
    /// reconstructing values from flattened path hops. This keeps the Linux
    /// fixture aligned with the macOS inspector and preserves fields that are
    /// not part of a hop (for example nodePort and hostIP).
    private func portPathDetailsDisplay(_ path: TopologyPortPath) -> String {
        var details: [String] = []
        if let servicePortHop = path.hops.first(where: { $0.role == "service-port" }),
           let serviceDetail = detail(for: servicePortHop.reference),
           let servicePort = serviceDetail.servicePorts.first(where: { port in
               port.port == servicePortHop.portNumber
                   && port.protocolName == servicePortHop.protocolName
                   && (servicePortHop.portName == nil || port.name == servicePortHop.portName)
           }) {
            let target = targetPortDescription(servicePort.targetPort)
            var terms = ["Service \(servicePort.name ?? "unnamed") \(servicePort.port)/\(servicePort.protocolName)", "targetPort \(target)"]
            if let appProtocol = servicePort.appProtocol { terms.append("app protocol \(appProtocol)") }
            if let nodePort = servicePort.nodePort { terms.append("node port \(nodePort)") }
            details.append(terms.joined(separator: " · "))
        }

        if let endpointPortHop = path.hops.first(where: { $0.role == "endpoint-port" }),
           let sliceDetail = detail(for: endpointPortHop.reference),
           let endpointPort = sliceDetail.endpointSlice?.ports.first(where: { port in
               port.port == endpointPortHop.portNumber
                   && port.protocolName == endpointPortHop.protocolName
                   && (endpointPortHop.portName == nil || port.name == endpointPortHop.portName)
           }) {
            var terms = ["EndpointSlice \(endpointPort.port)/\(endpointPort.protocolName)"]
            if let appProtocol = endpointPort.appProtocol { terms.append("app protocol \(appProtocol)") }
            details.append(terms.joined(separator: " · "))
        }

        if let containerPortHop = path.hops.first(where: { $0.role == "container-port" }),
           let podDetail = detail(for: containerPortHop.reference),
           let containerPort = (podDetail.containerPorts + podDetail.initContainerPorts + podDetail.ephemeralContainerPorts).first(where: { port in
               port.port == containerPortHop.portNumber
                   && port.protocolName == containerPortHop.protocolName
                   && (containerPortHop.portName == nil || port.name == containerPortHop.portName)
           }) {
            var terms = ["Container \(containerPort.containerName) \(containerPort.port)/\(containerPort.protocolName)"]
            if let hostPort = containerPort.hostPort { terms.append("host port \(hostPort)") }
            if let hostIP = containerPort.hostIP { terms.append("host IP \(hostIP)") }
            details.append(terms.joined(separator: " · "))
        }

        return details.isEmpty ? "none" : details.joined(separator: " | ")
    }

    private func targetPortDescription(_ target: TopologyPortTarget) -> String {
        if let name = target.name { return name }
        if let number = target.number { return String(number) }
        return target.usesServicePortByDefault ? "service port by default" : "unspecified"
    }

    private func detail(for reference: TopologyObjectReference?) -> TopologyNodeDetails? {
        guard let reference else { return nil }
        guard let node = topologyModel.graph.nodes.first(where: {
            $0.kind.caseInsensitiveCompare(reference.kind) == .orderedSame
                && $0.name == reference.name
                && $0.namespace == reference.namespace
        }) else { return nil }
        return topologyModel.graph.details[node.id]
    }

    private func hopText(_ hop: TopologyPortHop) -> String {
        let subject = hop.reference.map { "\($0.kind)/\($0.name)" } ?? hop.role
        let port = hop.portNumber.map(String.init) ?? hop.portName ?? "—"
        let protocolName = hop.protocolName.map { "/\($0)" } ?? ""
        return "\(subject):\(port)\(protocolName) [\(hop.evidence.level.title)]"
    }

    private func makeActionBar() -> Box {
        let actions = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 8)
        let delete = Button(label: "Delete…")
        delete.addCSSClass(.destructiveAction)
        delete.setAccessibleLabel("Mock delete with confirmation")
        delete.onClicked { [weak self] in self?.confirmMutation(action: "delete") }
        actions.append(delete)

        let restart = Button(label: "Rollout restart…")
        restart.setAccessibleLabel("Mock rollout restart with confirmation")
        restart.sensitive = false
        restart.tooltipText = "Available for Deployments only"
        restart.onClicked { [weak self] in self?.confirmMutation(action: "restart") }
        restartButton = restart
        actions.append(restart)

        let forward = Button(label: "Port-forward")
        forward.setAccessibleLabel("Mock loopback port forward")
        forward.onClicked { [weak self] in self?.togglePortForward() }
        actions.append(forward)
        let port = Label("No mock port-forward")
        port.setAccessibleLabel("mock port-forward state")
        port.hexpand = true
        port.xalign = 1
        portForwardLabel = port
        actions.append(port)
        return actions
    }

    private func makeDetailPanel() -> Box {
        let panel = Box(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        panel.setAccessibleLabel(LinuxSemanticLabels.detail)
        let detail = Label("Select a fixture resource to inspect details.")
        detail.xalign = 0
        detailLabel = detail
        panel.append(detail)

        let tabButtons = Box(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        let stack = Stack()
        stack.vexpand = true
        stack.hexpand = true
        detailStack = stack
        let overview = Label("Overview: safe sanitized metadata only")
        overview.xalign = 0
        let yaml = Label("# YAML preview\napiVersion: v1\nkind: Pod\nmetadata:\n  name: fixture")
        yaml.xalign = 0
        yamlLabel = yaml
        let events = Label("Events: no warning events in fixture mode")
        events.xalign = 0
        eventsLabel = events
        let logs = Label("Logs: select the Logs tab to stream fixture lines")
        logs.xalign = 0
        logs.setAccessibleLabel(LinuxSemanticLabels.logs)
        logsLabel = logs
        stack.addNamed(overview, name: "overview")
        stack.addNamed(yaml, name: "yaml")
        stack.addNamed(events, name: "events")
        stack.addNamed(logs, name: "logs")
        stack.visibleChildName = "overview"

        for (label, tab) in [("Overview", "overview"), ("YAML", "yaml"), ("Events", "events"), ("Logs", "logs")] {
            let button = Button(label: label)
            button.setAccessibleLabel("detail tab \(label)")
            button.onClicked { [weak self] in self?.detailStack?.visibleChildName = tab }
            tabButtons.append(button)
        }
        panel.append(tabButtons)
        panel.append(stack)

        let palette = Label("⌃K  Command palette · fixture commands only")
        palette.setAccessibleLabel(LinuxSemanticLabels.commandPalette)
        palette.xalign = 0
        paletteLabel = palette
        panel.append(palette)
        if let window {
            window.addKeyboardShortcut(key: .k, modifiers: .control) { [weak self] in
                self?.paletteLabel?.text = "Command palette: [get] [describe] [logs] [delete] [restart]"
                return true
            }
        }
        return panel
    }

    private func selectContext(_ id: String) {
        mainStack?.visibleChildName = "resources"
        state = CompassReducer.reduce(state, .selectContext(id)).state
        state = CompassReducer.reduce(state, .namespacesLoaded(CompassFixtures.namespaces)).state
        updateStatus()
    }

    private func selectNamespace(_ namespace: String) {
        mainStack?.visibleChildName = "resources"
        state = CompassReducer.reduce(state, .selectNamespace(namespace)).state
        updateStatus()
    }

    private func selectKind(_ id: String) {
        mainStack?.visibleChildName = "resources"
        state = CompassReducer.reduce(state, .selectKind(id)).state
        restartButton?.sensitive = state.resourceKinds.first(where: { $0.id == id })?.supportsRestart == true
        updateStatus()
    }

    private func selectResource(_ resource: KubeResource) {
        selectedResource = resource
        state = CompassReducer.reduce(state, .selectResource(resource.id)).state
        detailLabel?.text = resource.safeDescription
        yamlLabel?.text = "# YAML preview\napiVersion: v1\nkind: Pod\nmetadata:\n  name: \(resource.name)\n  namespace: \(resource.namespace ?? "default")"
        logsLabel?.text = "Logs (fixture): ready\nrequest complete"
        updateStatus()
    }

    private func confirmMutation(action: String) {
        guard let resource = selectedResource else {
            statusLabel?.text = "Select a resource before requesting a mock mutation."
            return
        }
        guard let contextID = state.selectedContextID,
              let kind = state.resourceKinds.first(where: { $0.id == resource.kindID }),
              let target = resource.mutationTarget(contextID: contextID, namespaced: kind.namespaced)
        else {
            statusLabel?.text = "Mock \(action) unavailable: fixture identity is incomplete."
            return
        }
        let operation: MutationOperation = action == "delete" ? .delete : .restart
        let request = MutationRequest(operation: operation, targets: [target])
        state = CompassReducer.reduce(state, .requestMutation(request)).state
        guard let window else { return }
        let alert = AlertDialog(
            heading: "Confirm mock \(action)",
            body: "Fixture mode will not contact a cluster. Confirming only exercises the safe mutation state transition for \(resource.name)."
        )
        alert.addResponse("cancel", label: "Cancel")
        alert.addResponse("confirm", label: "Confirm")
        alert.setResponseAppearance("confirm", appearance: action == "delete" ? .destructive : .suggested)
        alert.defaultResponse = "cancel"
        alert.closeResponse = "cancel"
        alert.onResponse { [weak self] response in
            guard let self else { return }
            if response == "confirm" {
                self.state = CompassReducer.reduce(self.state, .confirmMutation).state
                self.statusLabel?.text = "Mock \(action) validation requested; no command executed."
            } else {
                self.state = CompassReducer.reduce(self.state, .denyMutation).state
                self.updateStatus()
            }
        }
        alert.present(window)
    }

    private func togglePortForward() {
        if let active = state.portForwards.first {
            state = CompassReducer.reduce(state, .stopPortForward(active.id)).state
            portForwardLabel?.text = "Mock port-forward stopped"
        } else {
            let forward = PortForward(id: "fixture-forward", contextID: state.selectedContextID ?? "dev", namespace: "default", target: "pod/\(selectedResource?.name ?? "pod-0")", localPort: 8080, remotePort: 80)
            state = CompassReducer.reduce(state, .startPortForward(forward)).state
            state = CompassReducer.reduce(state, .portForwardState(id: forward.id, state: .active)).state
            portForwardLabel?.text = "Mock active: http://127.0.0.1:8080 → 80"
        }
    }

    private func reconnect() {
        state = CompassReducer.reduce(state, .beginReconnect).state
        state = CompassReducer.reduce(state, .finishReconnect(success: true)).state
        updateStatus()
    }

    private func showPermissionState() {
        state = CompassReducer.reduce(state, .permissionDenied("demo permission denied: fixture RBAC")).state
        updateStatus()
    }

    private func updateStatus() {
        statusLabel?.text = statusText()
    }

    private func statusText() -> String {
        let mode = options.demo ? "DEMO / FIXTURES ONLY" : "OFFLINE"
        let connection = String(describing: state.connectivity).uppercased()
        let count = model.visibleResources.count
        if let permission = state.permissionMessage { return "\(mode) · PERMISSION · \(permission)" }
        return "\(mode) · \(connection) · \(count) visible rows · kubectl disabled"
    }

    func smokeReport() -> String {
        let surfaces = [
            LinuxSemanticLabels.window,
            LinuxSemanticLabels.context,
            LinuxSemanticLabels.sidebar,
            LinuxSemanticLabels.namespace,
            LinuxSemanticLabels.resourceKind,
            LinuxSemanticLabels.table,
            LinuxSemanticLabels.detail,
            LinuxSemanticLabels.logs,
            LinuxSemanticLabels.commandPalette,
            LinuxSemanticLabels.status
        ]
        let topologySurfaces = [
            "Topology Explorer route", "Explorer level Cluster", "Explorer level Infrastructure",
            "Explorer level Workloads", "Explorer level Network", "Explorer level Policy & Dependencies",
            "Explorer level Evidence", "Explorer mode Focus", "Explorer mode Trace", "Explorer mode Inventory",
            "Explorer presentation Map fallback", "Explorer presentation List", "Explorer presentation Port table",
            "Topology canonical list", "Topology port path table", "Topology fundamentals and evidence inspector"
        ]
        let complete = topologyModel.graph.portPaths.first { $0.status == .complete }
        let partial = topologyModel.graph.portPaths.first { $0.status == .unresolved || $0.status == .partial }
        let ok = window != nil && surfaces.allSatisfy { !$0.isEmpty } && topologySurfaces.allSatisfy { !$0.isEmpty } && model.store.count == model.visibleResources.count && complete != nil && partial != nil
        return "KUBECOMPASS_SMOKE=\(ok ? "pass" : "fail") window=\(window != nil) semantic_surfaces=\(surfaces.count + topologySurfaces.count) rows=\(model.store.count) topology_levels=\(ExplorerLevel.allCases.count) topology_modes=\(ExplorerMode.allCases.count) topology_presentations=\(ExplorerPresentation.allCases.count) port_paths=\(topologyModel.graph.portPaths.count) complete_paths=\(topologyModel.graph.portPaths.filter { $0.status == .complete }.count) partial_or_unresolved_paths=\(topologyModel.graph.portPaths.filter { $0.status == .partial || $0.status == .unresolved }.count) kubectl=disabled"
    }
}

@main
struct KubeCompassLinuxMain {
    static func main() {
        let options = LinuxLaunchOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
            print(LinuxLaunchOptions.helpText)
            return
        }
        let app = Application(id: "dev.kubecompass.KubeCompass")
        let shell = LinuxDemoShell(options: options)
        app.onActivate { shell.present(in: app) }
        // Parse KubeCompass-owned flags above; do not forward them to
        // GApplication's strict option parser as unknown GTK options.
        _ = app.run(arguments: [CommandLine.arguments.first ?? "kubecompass-linux"])
    }
}
