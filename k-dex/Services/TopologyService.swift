import Foundation
import KubeCompassCore

/// Read-only topology aggregation for the native macOS explorer.
///
/// This adapter deliberately keeps the kubectl boundary typed and small. Raw
/// Kubernetes objects never leave this file: only identity, relationship
/// references, selector tokens, and an allowlisted set of facts are converted
/// into the portable KubeCompassCore graph.
nonisolated enum TopologyService {
    struct LoadResult: Sendable {
        let graph: TopologyGraph
        let fetchedResourceCount: Int
        let fatalMessage: String?
    }

    private struct InputSpec: Sendable {
        let key: String
        let kind: ResourceKind

        init(_ key: String, _ kind: ResourceKind) {
            self.key = key
            self.kind = kind
        }
    }

    private struct FetchResult: Sendable {
        let spec: InputSpec
        let objects: [KubeObject]
        let status: TopologyInputAvailability
        let message: String?
    }

    private static let inputs: [InputSpec] = [
        InputSpec("namespaces", .namespaces),
        InputSpec("nodes", .nodes),
        InputSpec("deployments", .deployments),
        InputSpec("statefulsets", .statefulSets),
        InputSpec("daemonsets", .daemonSets),
        InputSpec("replicasets", .replicaSets),
        InputSpec("jobs", .jobs),
        InputSpec("cronjobs", .cronJobs),
        InputSpec("pods", .pods),
        InputSpec("services", .services),
        InputSpec("endpointslices", .endpointSlices),
        InputSpec("ingresses", .ingresses),
        // Gateway API is optional. These static identities keep the adapter
        // feature-detectable: a missing CRD is reported as unsupported rather
        // than silently omitted from the snapshot.
        InputSpec("gatewayclasses.gateway.networking.k8s.io", ResourceKind(group: "gateway.networking.k8s.io", version: "v1", plural: "gatewayclasses", kindName: "GatewayClass", isNamespaced: false)),
        InputSpec("gateways.gateway.networking.k8s.io", ResourceKind(group: "gateway.networking.k8s.io", version: "v1", plural: "gateways", kindName: "Gateway", isNamespaced: true)),
        InputSpec("httproutes.gateway.networking.k8s.io", ResourceKind(group: "gateway.networking.k8s.io", version: "v1", plural: "httproutes", kindName: "HTTPRoute", isNamespaced: true)),
        InputSpec("networkpolicies", .networkPolicies),
        InputSpec("persistentvolumeclaims", .persistentVolumeClaims),
        InputSpec("persistentvolumes", .persistentVolumes),
        InputSpec("storageclasses", .storageClasses),
    ]

    static func load(
        context: String,
        namespace: String?,
        generation: Int = 0,
        runner: any CommandRunning = SystemCommandRunner()
    ) async throws -> LoadResult {
        let capturedAt = Date()
        var results: [FetchResult] = []
        await withTaskGroup(of: FetchResult.self) { group in
            var iterator = inputs.makeIterator()
            func addNext() {
                guard let spec = iterator.next() else { return }
                group.addTask {
                    do {
                        let scope = spec.kind.isNamespaced ? namespace : nil
                        let objects = try await list(
                            kind: spec.kind,
                            context: context,
                            namespace: scope,
                            runner: runner
                        )
                        return FetchResult(spec: spec, objects: objects, status: .available, message: nil)
                    } catch is CancellationError {
                        return FetchResult(spec: spec, objects: [], status: .unavailable, message: "Refresh cancelled")
                    } catch {
                        return FetchResult(spec: spec, objects: [], status: classify(error), message: safeMessage(for: error, kind: spec.key))
                    }
                }
            }
            // Each kubectl subprocess consumes several file descriptors. Keep
            // the fan-out bounded for large clusters and older macOS hosts.
            for _ in 0..<6 { addNext() }
            for await result in group {
                results.append(result)
                addNext()
            }
        }
        try Task.checkCancellation()

        results.sort { $0.spec.key < $1.spec.key }
        let allObjects = results.flatMap(\.objects)
        let allowedLabelKeys = selectorLabelKeys(in: allObjects)
        let snapshots = await Task.detached(priority: .userInitiated) {
            allObjects.map { snapshot(for: $0, allowedLabelKeys: allowedLabelKeys) }
        }.value

        let freshness = TopologyFreshness(capturedAt: capturedAt, generation: generation)
        let statuses = results.map {
            TopologyInputStatus(
                resourceKind: $0.spec.key,
                availability: $0.status,
                observedCount: $0.objects.count,
                message: $0.message,
                source: TopologyEvidenceSource(id: "input/\($0.spec.key)", kind: "kubernetes-api", sourceField: "list \($0.spec.key)", joinRule: "read-only list response"),
                freshness: freshness
            )
        }
        let buildInput = TopologyBuildInput(contextID: context, resources: snapshots, inputs: statuses, freshness: freshness)
        let graph = await Task.detached(priority: .userInitiated) {
            TopologyGraphBuilder.build(buildInput)
        }.value
        let deniedInputs = results.filter { $0.status == .forbidden }
        let unavailableInputs = results.filter { $0.status != .available }
        let unavailableSummary = unavailableInputs
            .map { "\($0.spec.key): \($0.message ?? $0.status.rawValue)" }
            .joined(separator: " · ")
        let fatalMessage: String?
        if !allObjects.isEmpty {
            fatalMessage = nil
        } else if !deniedInputs.isEmpty {
            fatalMessage = "KubeCompass cannot read topology in this scope. Affected inputs: \(unavailableSummary)."
        } else if unavailableInputs.count == results.count {
            fatalMessage = "Topology inputs are unavailable. Affected inputs: \(unavailableSummary)."
        } else if !unavailableInputs.isEmpty {
            fatalMessage = "No topology resources were returned. Affected inputs: \(unavailableSummary)."
        } else {
            fatalMessage = "No topology resources exist in this scope. Choose another namespace or refresh."
        }
        return LoadResult(graph: graph, fetchedResourceCount: allObjects.count, fatalMessage: fatalMessage)
    }

    /// A local list seam keeps topology fixture tests independent from the
    /// process-wide `Commands.runner` used by older service tests. Production
    /// still uses the same ProcessRunner-backed implementation.
    private static func list(
        kind: ResourceKind,
        context: String,
        namespace: String?,
        runner: any CommandRunning
    ) async throws -> [KubeObject] {
        var arguments = ["get", kind.cliName, "-o", "json", "--context", context]
        if kind.isNamespaced {
            arguments += namespace.map { ["-n", $0] } ?? ["--all-namespaces"]
        }
        let result = try await runner.runChecked("kubectl", arguments)
        let data = result.stdout
        return try await Task.detached(priority: .userInitiated) {
            try KubeJSON.objects(fromListData: data)
        }.value
    }

    // MARK: Typed snapshot extraction

    private static func snapshot(for object: KubeObject, allowedLabelKeys: Set<String>) -> TopologyResourceSnapshot {
        let raw = object.raw
        let kind = raw["kind"].stringValue.isEmpty ? inferredKind(for: object) : raw["kind"].stringValue
        let apiVersion = raw["apiVersion"].stringValue.isEmpty ? inferredAPIVersion(for: kind) : raw["apiVersion"].stringValue
        let namespace = object.namespace.isEmpty ? nil : object.namespace
        let identity = TopologyResourceIdentity(
            apiVersion: apiVersion,
            kind: kind,
            name: object.name,
            namespace: namespace,
            uid: object.uid,
            resourceVersion: object.resourceVersion,
            labels: filteredLabels(object.labels, allowedKeys: allowedLabelKeys)
        )
        let selectors = selector(from: raw["spec"]["selector"])
        let owners = raw["metadata"]["ownerReferences"].array.compactMap { owner -> TopologyOwnerReference? in
            let name = owner["name"].stringValue
            guard !name.isEmpty else { return nil }
            return TopologyOwnerReference(apiVersion: owner["apiVersion"].stringValue, kind: owner["kind"].stringValue, name: name, uid: owner["uid"].string)
        }
        var facts = allowlistedFacts(for: raw, kind: kind)
        var volumeReferences: [TopologyObjectReference] = []
        var configReferences: [TopologyNamedReference] = []
        extractVolumeReferences(from: raw["spec"]["volumes"].array, namespace: namespace, volumes: &volumeReferences, configs: &configReferences)
        extractContainerReferences(from: raw["spec"]["containers"].array + raw["spec"]["initContainers"].array + raw["spec"]["ephemeralContainers"].array, namespace: namespace, configs: &configReferences)
        if kind.caseInsensitiveCompare("PersistentVolumeClaim") == .orderedSame {
            if let volumeName = raw["spec"]["volumeName"].string, !volumeName.isEmpty {
                volumeReferences.append(TopologyObjectReference(apiVersion: "v1", kind: "PersistentVolume", name: volumeName))
            }
            if let storage = raw["spec"]["storageClassName"].string, !storage.isEmpty {
                volumeReferences.append(TopologyObjectReference(apiVersion: "storage.k8s.io/v1", kind: "StorageClass", name: storage))
            }
        }
        if kind.caseInsensitiveCompare("PersistentVolume") == .orderedSame {
            let claim = raw["spec"]["claimRef"]
            if !claim["name"].stringValue.isEmpty {
                volumeReferences.append(TopologyObjectReference(apiVersion: "v1", kind: "PersistentVolumeClaim", name: claim["name"].stringValue, namespace: claim["namespace"].string, uid: claim["uid"].string))
            }
            if let storage = raw["spec"]["storageClassName"].string, !storage.isEmpty {
                volumeReferences.append(TopologyObjectReference(apiVersion: "storage.k8s.io/v1", kind: "StorageClass", name: storage))
            }
        }
        let ingressData = ingressData(from: raw, namespace: namespace, facts: &facts)
        let endpointSlice = endpointSlice(from: raw, namespace: namespace, facts: &facts)
        let servicePorts = servicePorts(from: raw, kind: kind, facts: &facts)
        let serviceMode = serviceMode(from: raw, kind: kind)
        let podPorts = containerPorts(from: raw, kind: kind, namespace: namespace, facts: &facts)
        let gatewayClass = gatewayClassSnapshot(from: raw, kind: kind)
        let gateway = gatewaySnapshot(from: raw, kind: kind)
        let httpRoute = httpRouteSnapshot(from: raw, kind: kind, namespace: namespace)
        let policy = networkPolicy(from: raw)
        let podNodeName = raw["spec"]["nodeName"].string
        let roleLabels = object.labels.filter { key, _ in key.hasPrefix("node-role.kubernetes.io/") || key == "kubernetes.io/role" }
        return TopologyResourceSnapshot(
            identity: identity,
            ownerReferences: owners,
            podNodeName: podNodeName,
            selector: selectors.matchLabels,
            selectorExpressions: selectors.expressions,
            ingressBackends: ingressData.backends,
            ingressRoutes: ingressData.routes,
            endpointSlice: endpointSlice,
            servicePorts: servicePorts,
            serviceMode: serviceMode,
            containerPorts: podPorts.container,
            initContainerPorts: podPorts.initial,
            ephemeralContainerPorts: podPorts.ephemeral,
            gatewayClass: gatewayClass,
            gateway: gateway,
            httpRoute: httpRoute,
            volumeReferences: volumeReferences,
            configReferences: configReferences,
            roleLabels: filteredLabels(roleLabels, allowedKeys: allowedLabelKeys),
            networkPolicy: policy,
            facts: facts
        )
    }

    private static func selector(from value: JSONValue) -> (matchLabels: [String: String], expressions: [TopologySelectorRequirement]) {
        let fields = value.object
        // A LabelSelector object may legitimately contain an empty
        // matchLabels map; that means "match everything", not that the field
        // names themselves are labels. Service selectors, by contrast, are a
        // flat map.
        let isStructured = fields.keys.contains("matchLabels") || fields.keys.contains("matchExpressions")
        let labels = isStructured ? value["matchLabels"].stringDictionary : value.stringDictionary
        let expressions = value["matchExpressions"].array.compactMap { item -> TopologySelectorRequirement? in
            guard let op = selectorOperator(item["operator"].stringValue), !item["key"].stringValue.isEmpty else { return nil }
            return TopologySelectorRequirement(key: item["key"].stringValue, op: op, values: item["values"].array.map(\.stringValue))
        }
        return (labels, expressions)
    }

    private static func selectorOperator(_ value: String) -> TopologySelectorOperator? {
        switch value {
        case "In": return .in
        case "NotIn": return .notIn
        case "Exists": return .exists
        case "DoesNotExist": return .doesNotExist
        default: return nil
        }
    }

    private static func ingressData(from raw: JSONValue, namespace: String?, facts: inout [TopologyFact]) -> (backends: [TopologyServiceReference], routes: [TopologyIngressRoute]) {
        var backends: [TopologyServiceReference] = []
        var routes: [TopologyIngressRoute] = []
        let className = raw["spec"]["ingressClassName"].string
            ?? raw["metadata"]["annotations"]["kubernetes.io/ingress.class"].string
        let tlsNames = raw["spec"]["tls"].array.flatMap { $0["secretName"].string.map { [$0] } ?? [] }
        let ingressIdentity = raw["metadata"]["uid"].string ?? raw["metadata"]["name"].stringValue
        func add(_ service: JSONValue, isDefault: Bool, ruleIndex: Int?, pathIndex: Int?, host: String?, path: String?, pathType: String?) {
            let name = service["name"].stringValue
            guard !name.isEmpty else { return }
            let port = service["port"]["number"].int.flatMap { Int32(exactly: $0) }
            let named = service["port"]["name"].string.flatMap { $0.isEmpty ? nil : $0 }
            let backendKind = service["kind"].string ?? "Service"
            let backendNamespace = service["namespace"].string ?? namespace
            backends.append(TopologyServiceReference(name: name, namespace: backendNamespace, port: port, portName: named))
            let routeID = [ingressIdentity, isDefault ? "default" : "rule", String(ruleIndex ?? -1), String(pathIndex ?? -1), host ?? "", path ?? "", name, String(port ?? -1), named ?? ""].joined(separator: "|")
            routes.append(TopologyIngressRoute(isDefault: isDefault, ruleIndex: ruleIndex, pathIndex: pathIndex, host: host, path: path, pathType: pathType, ingressClass: className, tlsSecretNames: tlsNames, backendKind: backendKind, backendName: name, backendNamespace: backendNamespace, backendPort: port, backendPortName: named, id: routeID))
        }
        add(raw["spec"]["defaultBackend"]["service"], isDefault: true, ruleIndex: nil, pathIndex: nil, host: nil, path: nil, pathType: nil)
        for (ruleIndex, rule) in raw["spec"]["rules"].array.enumerated() {
            let host = rule["host"].string
            if let host, !host.isEmpty { facts.append(TopologyFact(key: "ingress-host-\(ruleIndex)", title: "Host", value: host)) }
            for (pathIndex, path) in rule["http"]["paths"].array.enumerated() {
                // networking.k8s.io/v1 stores service backend under
                // backend.service; older fixtures may use backend directly.
                let service = path["backend"]["service"].isNull ? path["backend"] : path["backend"]["service"]
                add(service, isDefault: false, ruleIndex: ruleIndex, pathIndex: pathIndex, host: host, path: path["path"].string, pathType: path["pathType"].string)
            }
        }
        for condition in raw["status"]["loadBalancer"]["ingress"].array {
            if let ip = condition["ip"].string { facts.append(TopologyFact(key: "load-balancer-ip", title: "Load balancer IP", value: ip)) }
            if let hostname = condition["hostname"].string { facts.append(TopologyFact(key: "load-balancer-hostname", title: "Load balancer hostname", value: hostname)) }
        }
        return (backends, routes)
    }

    private static func endpointSlice(from raw: JSONValue, namespace: String?, facts: inout [TopologyFact]) -> TopologyEndpointSliceSnapshot? {
        let serviceName = raw["metadata"]["labels"]["kubernetes.io/service-name"].string
        let addressType = raw["addressType"].string
        let ports = raw["ports"].array.compactMap { port -> TopologyEndpointPort? in
            guard let number = port["port"].int.flatMap({ Int32(exactly: $0) }) else { return nil }
            return TopologyEndpointPort(name: port["name"].string, port: number, protocolName: port["protocol"].string ?? "TCP", appProtocol: port["appProtocol"].string)
        }
        let endpoints = raw["endpoints"].array.compactMap { endpoint -> TopologyEndpointTarget? in
            let target = endpoint["targetRef"]
            let reference: TopologyObjectReference? = target["name"].stringValue.isEmpty ? nil : TopologyObjectReference(apiVersion: target["apiVersion"].string, kind: target["kind"].stringValue.isEmpty ? "Pod" : target["kind"].stringValue, name: target["name"].stringValue, namespace: target["namespace"].string ?? namespace, uid: target["uid"].string)
            return TopologyEndpointTarget(reference: reference, ready: endpoint["conditions"]["ready"].bool, serving: endpoint["conditions"]["serving"].bool, terminating: endpoint["conditions"]["terminating"].bool, addresses: endpoint["addresses"].array.map(\.stringValue), nodeName: endpoint["nodeName"].string, zone: endpoint["zone"].string)
        }
        guard serviceName != nil || !endpoints.isEmpty || !ports.isEmpty else { return nil }
        // EndpointSlice omits `ready` for an effective-ready endpoint. An
        // endpoint that is terminating and no longer serving is the one
        // exception, even when `ready` is omitted or still true.
        let ready = endpoints.filter { $0.ready != false && !($0.terminating == true && $0.serving == false) }.count
        facts.append(TopologyFact(key: "endpoint-count", title: "Endpoints", value: "\(ready) ready / \(endpoints.count) listed"))
        if let addressType { facts.append(TopologyFact(key: "endpoint-address-type", title: "Address type", value: addressType)) }
        return TopologyEndpointSliceSnapshot(serviceName: serviceName, addressType: addressType, ports: ports, endpoints: endpoints)
    }

    private static func networkPolicy(from raw: JSONValue) -> TopologyNetworkPolicySnapshot? {
        guard raw["kind"].stringValue.caseInsensitiveCompare("NetworkPolicy") == .orderedSame else { return nil }
        let policySelector = selector(from: raw["spec"]["podSelector"])
        var types = raw["spec"]["policyTypes"].array.map(\.stringValue)
        if types.isEmpty {
            // Kubernetes defaults omitted policyTypes to Ingress, plus Egress
            // when at least one egress rule is declared.
            types = ["Ingress"]
            if !raw["spec"]["egress"].array.isEmpty { types.append("Egress") }
        }
        func peers(_ values: [JSONValue]) -> [TopologyNetworkPolicyPeer] {
            values.map { peer in
                let pod = selector(from: peer["podSelector"])
                let ns = selector(from: peer["namespaceSelector"])
                let ipBlock = peer["ipBlock"]
                return TopologyNetworkPolicyPeer(
                    podSelector: peer["podSelector"].isNull ? nil : TopologyLabelSelector(matchLabels: pod.matchLabels, matchExpressions: pod.expressions),
                    namespaceSelector: peer["namespaceSelector"].isNull ? nil : TopologyLabelSelector(matchLabels: ns.matchLabels, matchExpressions: ns.expressions),
                    ipBlockCIDR: ipBlock["cidr"].string,
                    exceptCIDRs: ipBlock["except"].array.map(\.stringValue)
                )
            }
        }
        func ports(_ values: [JSONValue]) -> [TopologyNetworkPolicyPort] {
            values.compactMap { item in
                let number = item["port"].int.flatMap { Int32(exactly: $0) }
                let name = item["port"].string
                guard number != nil || name != nil else { return nil }
                return TopologyNetworkPolicyPort(name: name, number: number, protocolName: item["protocol"].string ?? "TCP", endPort: item["endPort"].int.flatMap { Int32(exactly: $0) })
            }
        }
        var rules: [TopologyNetworkPolicyRule] = []
        rules += raw["spec"]["ingress"].array.map { TopologyNetworkPolicyRule(direction: .ingress, peers: peers($0["from"].array), ports: ports($0["ports"].array)) }
        rules += raw["spec"]["egress"].array.map { TopologyNetworkPolicyRule(direction: .egress, peers: peers($0["to"].array), ports: ports($0["ports"].array)) }
        return TopologyNetworkPolicySnapshot(podSelector: TopologyLabelSelector(matchLabels: policySelector.matchLabels, matchExpressions: policySelector.expressions), policyTypes: types, ingressRuleCount: raw["spec"]["ingress"].array.count, egressRuleCount: raw["spec"]["egress"].array.count, rules: rules)
    }

    private static func servicePorts(from raw: JSONValue, kind: String, facts: inout [TopologyFact]) -> [TopologyServicePort] {
        guard kind.caseInsensitiveCompare("Service") == .orderedSame else { return [] }
        if raw["spec"]["selector"].object.isEmpty {
            facts.append(TopologyFact(key: "selector-none", title: "Selector", value: "none (external endpoints or manually managed backends)"))
        }
        let ports = raw["spec"]["ports"].array.compactMap { item -> TopologyServicePort? in
            guard let port = item["port"].int.flatMap({ Int32(exactly: $0) }) else { return nil }
            let target: TopologyPortTarget
            if let number = item["targetPort"].int.flatMap({ Int32(exactly: $0) }) {
                target = TopologyPortTarget(number: number)
            } else if let name = item["targetPort"].string, !name.isEmpty {
                target = TopologyPortTarget(name: name)
            } else {
                target = TopologyPortTarget(defaultPort: true)
            }
            return TopologyServicePort(name: item["name"].string, port: port, targetPort: target, protocolName: item["protocol"].string ?? "TCP", appProtocol: item["appProtocol"].string, nodePort: item["nodePort"].int.flatMap { Int32(exactly: $0) })
        }
        for servicePort in ports {
            let target = servicePort.targetPort.number.map(String.init) ?? servicePort.targetPort.name ?? "port"
            facts.append(TopologyFact(key: "service-port-\(servicePort.id)", title: "Port", value: "\(servicePort.name ?? "unnamed"): \(servicePort.port)/\(servicePort.protocolName) → \(target)"))
        }
        return ports
    }

    private static func serviceMode(from raw: JSONValue, kind: String) -> TopologyServiceMode? {
        guard kind.caseInsensitiveCompare("Service") == .orderedSame else { return nil }
        if raw["spec"]["externalName"].string != nil { return .externalName }
        if raw["spec"]["clusterIP"].string == "None" { return .headless }
        switch raw["spec"]["type"].stringValue {
        case "NodePort": return .nodePort
        case "LoadBalancer": return .loadBalancer
        default: return raw["spec"]["selector"].object.isEmpty ? .selectorless : .standard
        }
    }

    private static func containerPorts(from raw: JSONValue, kind: String, namespace: String?, facts: inout [TopologyFact]) -> (container: [TopologyContainerPort], initial: [TopologyContainerPort], ephemeral: [TopologyContainerPort]) {
        guard kind.caseInsensitiveCompare("Pod") == .orderedSame else { return (container: [], initial: [], ephemeral: []) }
        func parse(_ values: [JSONValue]) -> [TopologyContainerPort] {
            values.flatMap { container in
                let name = container["name"].stringValue
                return container["ports"].array.compactMap { (port: JSONValue) -> TopologyContainerPort? in
                    guard let number = port["containerPort"].int.flatMap({ Int32(exactly: $0) }) else { return nil }
                    return TopologyContainerPort(containerName: name, name: port["name"].string, port: number, protocolName: port["protocol"].string ?? "TCP", hostPort: port["hostPort"].int.flatMap { Int32(exactly: $0) }, hostIP: port["hostIP"].string)
                }
            }
        }
        let regular = parse(raw["spec"]["containers"].array)
        let initial = parse(raw["spec"]["initContainers"].array)
        let ephemeral = parse(raw["spec"]["ephemeralContainers"].array)
        if raw["spec"]["hostNetwork"].bool == true { facts.append(TopologyFact(key: "host-network", title: "Network", value: "hostNetwork enabled")) }
        let readiness = raw["status"]["conditions"].array.first(where: { $0["type"].string == "Ready" })?["status"].string
        if let readiness { facts.append(TopologyFact(key: "ready", title: "Ready", value: readiness)) }
        let restarts = raw["status"]["containerStatuses"].array.reduce(0) { $0 + ($1["restartCount"].int ?? 0) }
        if restarts > 0 { facts.append(TopologyFact(key: "restarts", title: "Restarts", value: String(restarts))) }
        return (regular, initial, ephemeral)
    }

    private static func statusConditions(_ raw: JSONValue) -> [String: String] {
        // Conditions should be unique by type, but malformed or transitional
        // API responses can contain duplicates. Preserve payload order and let
        // the last valid occurrence win instead of trapping on duplicate keys.
        var conditions: [String: String] = [:]
        for item in raw["status"]["conditions"].array {
            guard let type = item["type"].string, let status = item["status"].string else { continue }
            conditions[type] = status
        }
        return conditions
    }

    private static func gatewayClassSnapshot(from raw: JSONValue, kind: String) -> TopologyGatewayClassSnapshot? {
        guard kind.caseInsensitiveCompare("GatewayClass") == .orderedSame else { return nil }
        let refValue = raw["spec"]["parametersRef"]
        let ref: TopologyObjectReference? = refValue["name"].string.map { TopologyObjectReference(apiVersion: refValue["group"].string, kind: refValue["kind"].string ?? "Parameters", name: $0) }
        return TopologyGatewayClassSnapshot(controllerName: raw["spec"]["controllerName"].string, parametersRef: ref, statusConditions: statusConditions(raw))
    }

    private static func gatewaySnapshot(from raw: JSONValue, kind: String) -> TopologyGatewaySnapshot? {
        guard kind.caseInsensitiveCompare("Gateway") == .orderedSame else { return nil }
        let listeners = raw["spec"]["listeners"].array.compactMap { listener -> TopologyGatewayListener? in
            guard let port = listener["port"].int.flatMap({ Int32(exactly: $0) }) else { return nil }
            let kinds = listener["allowedRoutes"]["kinds"].array.compactMap { $0["kind"].string }
            return TopologyGatewayListener(name: listener["name"].string, protocolName: listener["protocol"].string ?? "TCP", port: port, hostname: listener["hostname"].string, allowedRouteKinds: kinds)
        }
        return TopologyGatewaySnapshot(gatewayClassName: raw["spec"]["gatewayClassName"].string, listeners: listeners, statusConditions: statusConditions(raw))
    }

    /// Gateway API status entries identify a parent by the complete
    /// ParentReference, not by name alone. A Gateway may expose multiple
    /// listeners (sections) under the same name, and parentRefs can also
    /// target another namespace, group, or kind. Normalize the API defaults
    /// before comparing spec and status so omitted default fields still match
    /// while distinct references cannot cross-contaminate their conditions.
    private struct HTTPRouteParentIdentity: Equatable {
        let name: String
        let namespace: String?
        let sectionName: String?
        let group: String
        let kind: String
    }

    private static func httpRouteParentIdentity(_ raw: JSONValue, namespace: String?) -> HTTPRouteParentIdentity? {
        guard let name = raw["name"].string, !name.isEmpty else { return nil }
        let group = raw["group"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "gateway.networking.k8s.io"
        let kind = raw["kind"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "Gateway"
        let parentNamespace = raw["namespace"].string.flatMap { $0.isEmpty ? nil : $0 } ?? namespace
        let sectionName = raw["sectionName"].string.flatMap { $0.isEmpty ? nil : $0 }
        return HTTPRouteParentIdentity(name: name, namespace: parentNamespace, sectionName: sectionName, group: group, kind: kind)
    }

    private static func httpRouteSnapshot(from raw: JSONValue, kind: String, namespace: String?) -> TopologyHTTPRouteSnapshot? {
        guard kind.caseInsensitiveCompare("HTTPRoute") == .orderedSame else { return nil }
        let parents = raw["spec"]["parentRefs"].array.compactMap { parent -> TopologyGatewayParentReference? in
            guard let identity = httpRouteParentIdentity(parent, namespace: namespace) else { return nil }
            let status = raw["status"]["parents"].array.first {
                guard let statusIdentity = httpRouteParentIdentity($0["parentRef"], namespace: namespace) else { return false }
                return statusIdentity == identity
            }
            let accepted = status?["conditions"].array.first(where: { $0["type"].string == "Accepted" })?["status"].string.map { $0 == "True" }
            let resolved = status?["conditions"].array.first(where: { $0["type"].string == "ResolvedRefs" })?["status"].string.map { $0 == "True" }
            return TopologyGatewayParentReference(kind: identity.kind, name: identity.name, namespace: identity.namespace, sectionName: identity.sectionName, accepted: accepted, resolvedRefs: resolved)
        }
        var backends: [TopologyGatewayBackendReference] = []
        for rule in raw["spec"]["rules"].array {
            for backend in rule["backendRefs"].array {
                guard let name = backend["name"].string else { continue }
                backends.append(TopologyGatewayBackendReference(kind: backend["kind"].string ?? "Service", name: name, namespace: backend["namespace"].string ?? namespace, port: backend["port"].int.flatMap { Int32(exactly: $0) }, weight: backend["weight"].int.flatMap { Int32(exactly: $0) }))
            }
        }
        return TopologyHTTPRouteSnapshot(hostnames: raw["spec"]["hostnames"].array.map(\.stringValue), parents: parents, backends: backends, statusConditions: statusConditions(raw))
    }

    private static func allowlistedFacts(for raw: JSONValue, kind: String) -> [TopologyFact] {
        let lower = kind.lowercased()
        var facts: [TopologyFact] = []
        func add(_ key: String, _ title: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            facts.append(TopologyFact(key: key, title: title, value: value))
        }
        if lower == "node" {
            add("pod-cidr", "Pod CIDR", raw["spec"]["podCIDR"].string)
            add("kubelet", "Kubelet", raw["status"]["nodeInfo"]["kubeletVersion"].string)
            add("runtime", "Runtime", raw["status"]["nodeInfo"]["containerRuntimeVersion"].string)
            add("os", "Operating system", raw["status"]["nodeInfo"]["operatingSystem"].string)
            add("architecture", "Architecture", raw["status"]["nodeInfo"]["architecture"].string)
            for address in raw["status"]["addresses"].array {
                add("address-\(address["type"].stringValue.lowercased())", address["type"].stringValue, address["address"].string)
            }
        } else if lower == "pod" {
            add("phase", "Phase", raw["status"]["phase"].string)
            add("pod-ip", "Pod IP", raw["status"]["podIP"].string)
        } else if ["deployment", "statefulset", "daemonset", "replicaset", "job", "cronjob"].contains(lower) {
            add("desired-replicas", "Desired replicas", raw["spec"]["replicas"].string ?? raw["spec"]["parallelism"].string)
            add("ready-replicas", "Ready replicas", raw["status"]["readyReplicas"].string ?? raw["status"]["availableReplicas"].string)
        } else if lower == "service" {
            add("type", "Service type", raw["spec"]["type"].string)
            add("cluster-ip", "Cluster IP", raw["spec"]["clusterIP"].string)
            add("external-ips", "External IPs", raw["spec"]["externalIPs"].array.map(\.stringValue).joined(separator: ", "))
            add("ports", "Ports", raw["spec"]["ports"].array.compactMap { $0["port"].int.map(String.init) }.joined(separator: ", "))
        } else if lower == "storageclass" {
            add("provisioner", "Provisioner", raw["provisioner"].string)
            add("reclaim-policy", "Reclaim policy", raw["reclaimPolicy"].string)
            add("volume-binding", "Binding mode", raw["volumeBindingMode"].string)
        } else if lower == "persistentvolumeclaim" {
            add("phase", "Phase", raw["status"]["phase"].string)
            add("requested-storage", "Requested storage", raw["spec"]["resources"]["requests"]["storage"].string)
        } else if lower == "persistentvolume" {
            add("phase", "Phase", raw["status"]["phase"].string)
            add("capacity", "Capacity", raw["spec"]["capacity"]["storage"].string)
        }
        return facts
    }

    private static func extractVolumeReferences(from volumes: [JSONValue], namespace: String?, volumes volumeRefs: inout [TopologyObjectReference], configs: inout [TopologyNamedReference]) {
        for volume in volumes {
            if let name = volume["persistentVolumeClaim"]["claimName"].string, !name.isEmpty { volumeRefs.append(TopologyObjectReference(apiVersion: "v1", kind: "PersistentVolumeClaim", name: name, namespace: namespace)) }
            if let name = volume["configMap"]["name"].string, !name.isEmpty { configs.append(TopologyNamedReference(kind: "ConfigMap", name: name, namespace: namespace)) }
            if let name = volume["secret"]["secretName"].string, !name.isEmpty { configs.append(TopologyNamedReference(kind: "Secret", name: name, namespace: namespace)) }
            for source in volume["projected"]["sources"].array {
                if let name = source["configMap"]["name"].string, !name.isEmpty { configs.append(TopologyNamedReference(kind: "ConfigMap", name: name, namespace: namespace)) }
                if let name = source["secret"]["name"].string, !name.isEmpty { configs.append(TopologyNamedReference(kind: "Secret", name: name, namespace: namespace)) }
            }
        }
    }

    private static func extractContainerReferences(from containers: [JSONValue], namespace: String?, configs: inout [TopologyNamedReference]) {
        for container in containers {
            for env in container["env"].array {
                if let ref = env["valueFrom"]["configMapKeyRef"]["name"].string, !ref.isEmpty { configs.append(TopologyNamedReference(kind: "ConfigMap", name: ref, namespace: namespace)) }
                if let ref = env["valueFrom"]["secretKeyRef"]["name"].string, !ref.isEmpty { configs.append(TopologyNamedReference(kind: "Secret", name: ref, namespace: namespace)) }
            }
            for envFrom in container["envFrom"].array {
                if let ref = envFrom["configMapRef"]["name"].string, !ref.isEmpty { configs.append(TopologyNamedReference(kind: "ConfigMap", name: ref, namespace: namespace)) }
                if let ref = envFrom["secretRef"]["name"].string, !ref.isEmpty { configs.append(TopologyNamedReference(kind: "Secret", name: ref, namespace: namespace)) }
            }
        }
    }

    private static func selectorLabelKeys(in objects: [KubeObject]) -> Set<String> {
        var keys: Set<String> = []
        for object in objects {
            let selectors = [object.raw["spec"]["selector"], object.raw["spec"]["podSelector"]]
            for selector in selectors {
                keys.formUnion(selector["matchLabels"].object.keys)
                keys.formUnion(selector.object.keys.filter { $0 != "matchLabels" && $0 != "matchExpressions" })
                for expr in selector["matchExpressions"].array { if !expr["key"].stringValue.isEmpty { keys.insert(expr["key"].stringValue) } }
            }
        }
        return keys
    }

    private static func filteredLabels(_ labels: [String: String], allowedKeys: Set<String>) -> [String: String] {
        labels.filter { key, _ in
            allowedKeys.contains(key) || key == "app" || key == "role" || key == "tier" || key == "component" || key.hasPrefix("app.kubernetes.io/") || key.hasPrefix("kubernetes.io/") || key.hasPrefix("node-role.kubernetes.io/") || key.hasPrefix("topology.kubernetes.io/")
        }
    }

    private static func inferredKind(for object: KubeObject) -> String { object.raw["metadata"]["generateName"].stringValue.isEmpty ? "Resource" : "Resource" }
    private static func inferredAPIVersion(for kind: String) -> String { ["Deployment", "StatefulSet", "DaemonSet", "ReplicaSet"].contains(kind) ? "apps/v1" : "v1" }

    private static func classify(_ error: Error) -> TopologyInputAvailability {
        let message = "\(error.localizedDescription) \(error)".lowercased()
        if message.contains("forbidden") || message.contains("unauthorized") { return .forbidden }
        if message.contains("notfound") || message.contains("not found") || message.contains("the server could not find") { return .unsupported }
        return .unavailable
    }

    private static func safeMessage(for error: Error, kind: String) -> String {
        switch classify(error) {
        case .forbidden: return "Access denied listing \(kind)."
        case .unsupported: return "The cluster does not expose \(kind)."
        default: return "Unable to list \(kind); the graph is partial."
        }
    }
}
