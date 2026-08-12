import Adwaita
import Foundation
import KubeCompassCore
import KubeCompassLinuxSupport

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
        return sidebar
    }

    private func makeMainContent() -> Box {
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
        state = CompassReducer.reduce(state, .selectContext(id)).state
        state = CompassReducer.reduce(state, .namespacesLoaded(CompassFixtures.namespaces)).state
        updateStatus()
    }

    private func selectNamespace(_ namespace: String) {
        state = CompassReducer.reduce(state, .selectNamespace(namespace)).state
        updateStatus()
    }

    private func selectKind(_ id: String) {
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
        let ok = window != nil && surfaces.allSatisfy { !$0.isEmpty } && model.store.count == model.visibleResources.count
        return "KUBECOMPASS_SMOKE=\(ok ? "pass" : "fail") window=\(window != nil) semantic_surfaces=\(surfaces.count) rows=\(model.store.count) kubectl=disabled"
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
