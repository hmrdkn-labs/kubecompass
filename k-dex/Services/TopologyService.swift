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
        let ingress = ingressBackends(from: raw, namespace: namespace, facts: &facts)
        let endpointSlice = endpointSlice(from: raw, namespace: namespace, facts: &facts)
        let policy = networkPolicy(from: raw)
        let podNodeName = raw["spec"]["nodeName"].string
        let roleLabels = object.labels.filter { key, _ in key.hasPrefix("node-role.kubernetes.io/") || key == "kubernetes.io/role" }
        return TopologyResourceSnapshot(
            identity: identity,
            ownerReferences: owners,
            podNodeName: podNodeName,
            selector: selectors.matchLabels,
            selectorExpressions: selectors.expressions,
            ingressBackends: ingress,
            endpointSlice: endpointSlice,
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

    private static func ingressBackends(from raw: JSONValue, namespace: String?, facts: inout [TopologyFact]) -> [TopologyServiceReference] {
        var backends: [TopologyServiceReference] = []
        func add(_ service: JSONValue) {
            let name = service["name"].stringValue
            guard !name.isEmpty else { return }
            let port = service["port"]["number"].int.flatMap { Int32(exactly: $0) }
            let named = service["port"]["name"].string.flatMap { $0.isEmpty ? nil : $0 }
            backends.append(TopologyServiceReference(name: name, namespace: namespace, port: port, portName: named))
        }
        add(raw["spec"]["defaultBackend"]["service"])
        for rule in raw["spec"]["rules"].array {
            if let host = rule["host"].string, !host.isEmpty { facts.append(TopologyFact(key: "ingress-host", title: "Host", value: host)) }
            for path in rule["http"]["paths"].array { add(path["backend"]["service"]) }
        }
        return backends
    }

    private static func endpointSlice(from raw: JSONValue, namespace: String?, facts: inout [TopologyFact]) -> TopologyEndpointSliceSnapshot? {
        let serviceName = raw["metadata"]["labels"]["kubernetes.io/service-name"].string
        let endpoints = raw["endpoints"].array.compactMap { endpoint -> TopologyEndpointTarget? in
            let target = endpoint["targetRef"]
            guard !target["name"].stringValue.isEmpty else { return nil }
            let reference = TopologyObjectReference(apiVersion: target["apiVersion"].string, kind: target["kind"].stringValue.isEmpty ? "Pod" : target["kind"].stringValue, name: target["name"].stringValue, namespace: target["namespace"].string ?? namespace, uid: target["uid"].string)
            return TopologyEndpointTarget(reference: reference, ready: endpoint["conditions"]["ready"].bool)
        }
        guard serviceName != nil || !endpoints.isEmpty else { return nil }
        let ready = endpoints.filter { $0.ready == true }.count
        facts.append(TopologyFact(key: "endpoint-count", title: "Endpoints", value: "\(ready) ready / \(endpoints.count) listed"))
        return TopologyEndpointSliceSnapshot(serviceName: serviceName, endpoints: endpoints)
    }

    private static func networkPolicy(from raw: JSONValue) -> TopologyNetworkPolicySnapshot? {
        guard raw["kind"].stringValue.caseInsensitiveCompare("NetworkPolicy") == .orderedSame else { return nil }
        let selector = selector(from: raw["spec"]["podSelector"])
        var types = raw["spec"]["policyTypes"].array.map(\.stringValue)
        if types.isEmpty {
            // Kubernetes defaults omitted policyTypes to Ingress, plus Egress
            // when at least one egress rule is declared.
            types = ["Ingress"]
            if !raw["spec"]["egress"].array.isEmpty { types.append("Egress") }
        }
        return TopologyNetworkPolicySnapshot(podSelector: TopologyLabelSelector(matchLabels: selector.matchLabels, matchExpressions: selector.expressions), policyTypes: types, ingressRuleCount: raw["spec"]["ingress"].array.count, egressRuleCount: raw["spec"]["egress"].array.count)
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
