import Foundation

// MARK: - Evidence-aware topology domain

/// Confidence in a relationship. The graph deliberately distinguishes what
/// the API reports from what is only a declaration (for example a Service
/// selector) or a client-side match. It never claims packet reachability.
public enum TopologyEvidenceLevel: String, Codable, Hashable, Sendable, CaseIterable {
    case observed
    case declared
    case inferred
    case unavailable
}

public struct TopologyEvidenceSource: Codable, Hashable, Sendable {
    public let id: String
    public let contextID: String?
    public let apiVersion: String?
    public let kind: String
    public let name: String?
    public let namespace: String?
    public let uid: String?
    public let resourceVersion: String?
    public let sourceField: String?
    public let joinRule: String?
    public let assumption: String?
    public let note: String?

    public init(id: String, contextID: String? = nil, apiVersion: String? = nil, kind: String, name: String? = nil, namespace: String? = nil, uid: String? = nil, resourceVersion: String? = nil, sourceField: String? = nil, joinRule: String? = nil, assumption: String? = nil, note: String? = nil) {
        self.id = TopologySanitizer.clean(id)
        self.contextID = contextID.map { TopologySanitizer.clean($0) }
        self.apiVersion = apiVersion.map { TopologySanitizer.clean($0) }
        self.kind = TopologySanitizer.clean(kind)
        self.name = name.map { TopologySanitizer.clean($0) }
        self.namespace = namespace.map { TopologySanitizer.clean($0) }
        self.uid = uid.map { TopologySanitizer.clean($0) }
        self.resourceVersion = resourceVersion.map { TopologySanitizer.clean($0) }
        self.sourceField = sourceField.map { TopologySanitizer.clean($0) }
        self.joinRule = joinRule.map { TopologySanitizer.clean($0) }
        self.assumption = assumption.map { TopologySanitizer.clean($0) }
        self.note = note.map(TopologySanitizer.clean)
    }

    public static func api(kind: String) -> TopologyEvidenceSource {
        TopologyEvidenceSource(id: "kubernetes-api/\(kind)", kind: "kubernetes-api")
    }

    public static func object(contextID: String, identity: TopologyResourceIdentity, sourceField: String? = nil, joinRule: String? = nil, assumption: String? = nil) -> TopologyEvidenceSource {
        let id = [contextID, identity.apiVersion, identity.kind, identity.namespace ?? "", identity.name, identity.uid, identity.resourceVersion].map(TopologySanitizer.idPart).joined(separator: "|")
        return TopologyEvidenceSource(id: id, contextID: contextID, apiVersion: identity.apiVersion, kind: identity.kind, name: identity.name, namespace: identity.namespace, uid: identity.uid.isEmpty ? nil : identity.uid, resourceVersion: identity.resourceVersion.isEmpty ? nil : identity.resourceVersion, sourceField: sourceField, joinRule: joinRule, assumption: assumption)
    }

    public static func inputStatus(_ status: TopologyInputStatus) -> TopologyEvidenceSource {
        TopologyEvidenceSource(id: "input-status|\(status.resourceKind)", kind: "input-status", sourceField: "input.\(status.resourceKind)", joinRule: "input availability", assumption: status.message)
    }
}

public struct TopologyFreshness: Codable, Hashable, Sendable {
    public let capturedAt: Date
    public let generation: Int

    public init(capturedAt: Date = Date(), generation: Int = 0) {
        self.capturedAt = capturedAt
        self.generation = max(0, generation)
    }
}

public struct TopologyEvidence: Codable, Hashable, Sendable {
    public let level: TopologyEvidenceLevel
    public let source: TopologyEvidenceSource
    public let freshness: TopologyFreshness

    public init(level: TopologyEvidenceLevel, source: TopologyEvidenceSource, freshness: TopologyFreshness) {
        self.level = level
        self.source = source
        self.freshness = freshness
    }
}

public enum TopologyInputAvailability: String, Codable, Hashable, Sendable {
    case available
    case partial
    case forbidden
    case unsupported
    case unavailable
}

public struct TopologyInputStatus: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let resourceKind: String
    public let availability: TopologyInputAvailability
    public let observedCount: Int
    public let message: String?
    public let source: TopologyEvidenceSource
    public let freshness: TopologyFreshness

    public init(resourceKind: String, availability: TopologyInputAvailability = .available, observedCount: Int = 0, message: String? = nil, source: TopologyEvidenceSource? = nil, freshness: TopologyFreshness = TopologyFreshness()) {
        self.resourceKind = TopologySanitizer.clean(resourceKind)
        self.id = self.resourceKind
        self.availability = availability
        self.observedCount = max(0, observedCount)
        self.message = message.map(TopologySanitizer.clean)
        self.source = source ?? .api(kind: resourceKind)
        self.freshness = freshness
    }
}

public enum TopologySnapshotCompleteness: String, Codable, Hashable, Sendable {
    case complete
    case partial
    case unavailable
}

public struct TopologyResourceIdentity: Codable, Hashable, Sendable {
    public let apiVersion: String
    public let kind: String
    public let name: String
    public let namespace: String?
    public let uid: String
    public let resourceVersion: String
    public let labels: [String: String]

    public init(apiVersion: String, kind: String, name: String, namespace: String? = nil, uid: String, resourceVersion: String = "", labels: [String: String] = [:]) {
        self.apiVersion = TopologySanitizer.clean(apiVersion)
        self.kind = TopologySanitizer.clean(kind)
        self.name = TopologySanitizer.clean(name)
        self.namespace = namespace.map(TopologySanitizer.clean)
        self.uid = TopologySanitizer.clean(uid)
        self.resourceVersion = TopologySanitizer.clean(resourceVersion)
        self.labels = TopologySanitizer.labels(labels)
    }

    /// UID-backed IDs survive renames and list ordering changes. A name
    /// fallback keeps fixture/partial data inspectable while remaining
    /// explicitly different from a UID identity.
    public func stableNodeID(contextID: String) -> String {
        let identity = uid.isEmpty ? "name:\(namespace ?? "_")/\(name)" : "uid:\(uid)"
        return [TopologySanitizer.clean(contextID), apiVersion, kind, identity].map(TopologySanitizer.idPart).joined(separator: "|")
    }
}

public struct TopologyOwnerReference: Codable, Hashable, Sendable {
    public let apiVersion: String
    public let kind: String
    public let name: String
    public let uid: String?

    public init(apiVersion: String, kind: String, name: String, uid: String? = nil) {
        self.apiVersion = TopologySanitizer.clean(apiVersion)
        self.kind = TopologySanitizer.clean(kind)
        self.name = TopologySanitizer.clean(name)
        self.uid = uid.map { TopologySanitizer.clean($0) }
    }
}

public struct TopologyObjectReference: Codable, Hashable, Sendable {
    public let apiVersion: String?
    public let kind: String
    public let name: String
    public let namespace: String?
    public let uid: String?

    public init(apiVersion: String? = nil, kind: String, name: String, namespace: String? = nil, uid: String? = nil) {
        self.apiVersion = apiVersion.map { TopologySanitizer.clean($0) }
        self.kind = TopologySanitizer.clean(kind)
        self.name = TopologySanitizer.clean(name)
        self.namespace = namespace.map { TopologySanitizer.clean($0) }
        self.uid = uid.map { TopologySanitizer.clean($0) }
    }
}

public struct TopologyServiceReference: Codable, Hashable, Sendable {
    public let name: String
    public let namespace: String?
    public let port: Int32?
    public let portName: String?

    public init(name: String, namespace: String? = nil, port: Int32? = nil, portName: String? = nil) {
        self.name = TopologySanitizer.clean(name)
        self.namespace = namespace.map { TopologySanitizer.clean($0) }
        self.port = port
        self.portName = portName.map { TopologySanitizer.clean($0) }
    }
}

/// The two forms accepted by Service.spec.ports[].targetPort. An omitted
/// targetPort is represented explicitly so consumers can explain the default
/// (targetPort == port) without guessing from a missing field.
public struct TopologyPortTarget: Codable, Hashable, Sendable {
    public let number: Int32?
    public let name: String?
    public let usesServicePortByDefault: Bool

    public init(number: Int32) {
        self.number = number
        self.name = nil
        self.usesServicePortByDefault = false
    }

    public init(name: String) {
        self.number = nil
        self.name = TopologySanitizer.clean(name)
        self.usesServicePortByDefault = false
    }

    public init(defaultPort: Bool = true) {
        self.number = nil
        self.name = nil
        self.usesServicePortByDefault = defaultPort
    }
}

public struct TopologyServicePort: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let port: Int32
    public let targetPort: TopologyPortTarget
    public let protocolName: String
    public let appProtocol: String?
    public let nodePort: Int32?

    public init(name: String? = nil, port: Int32, targetPort: TopologyPortTarget? = nil, protocolName: String = "TCP", appProtocol: String? = nil, nodePort: Int32? = nil) {
        self.name = name.map(TopologySanitizer.clean)
        self.port = port
        self.targetPort = targetPort ?? TopologyPortTarget(defaultPort: true)
        self.protocolName = TopologySanitizer.clean(protocolName).uppercased()
        self.appProtocol = appProtocol.map(TopologySanitizer.clean)
        self.nodePort = nodePort
        self.id = TopologyHash.id([self.name ?? "", String(port), self.targetPort.name ?? "", self.targetPort.number.map(String.init) ?? "default", self.protocolName, self.nodePort.map(String.init) ?? ""].joined(separator: "|"))
    }

    public var `protocol`: String { protocolName }
}

public struct TopologyContainerPort: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let containerName: String
    public let name: String?
    public let port: Int32
    public let protocolName: String
    public let hostPort: Int32?
    public let hostIP: String?

    public init(containerName: String, name: String? = nil, port: Int32, protocolName: String = "TCP", hostPort: Int32? = nil, hostIP: String? = nil) {
        self.containerName = TopologySanitizer.clean(containerName)
        self.name = name.map(TopologySanitizer.clean)
        self.port = port
        self.protocolName = TopologySanitizer.clean(protocolName).uppercased()
        self.hostPort = hostPort
        self.hostIP = hostIP.map(TopologySanitizer.clean)
        self.id = TopologyHash.id([self.containerName, self.name ?? "", String(port), self.protocolName, self.hostPort.map(String.init) ?? "", self.hostIP ?? ""].joined(separator: "|"))
    }

    public var `protocol`: String { protocolName }
}

public struct TopologyEndpointPort: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let port: Int32
    public let protocolName: String
    public let appProtocol: String?

    public init(name: String? = nil, port: Int32, protocolName: String = "TCP", appProtocol: String? = nil) {
        self.name = name.map(TopologySanitizer.clean)
        self.port = port
        self.protocolName = TopologySanitizer.clean(protocolName).uppercased()
        self.appProtocol = appProtocol.map(TopologySanitizer.clean)
        self.id = TopologyHash.id([self.name ?? "", String(port), self.protocolName, self.appProtocol ?? ""].joined(separator: "|"))
    }

    public var `protocol`: String { protocolName }
}

public struct TopologyEndpointTarget: Codable, Hashable, Sendable {
    public let reference: TopologyObjectReference?
    public let ready: Bool?
    public let serving: Bool?
    public let terminating: Bool?
    public let addresses: [String]
    public let nodeName: String?
    public let zone: String?

    public init(reference: TopologyObjectReference? = nil, ready: Bool? = nil, serving: Bool? = nil, terminating: Bool? = nil, addresses: [String] = [], nodeName: String? = nil, zone: String? = nil) {
        self.reference = reference
        self.ready = ready
        self.serving = serving
        self.terminating = terminating
        self.addresses = addresses.map(TopologySanitizer.clean).sorted()
        self.nodeName = nodeName.map(TopologySanitizer.clean)
        self.zone = zone.map(TopologySanitizer.clean)
    }

    private enum CodingKeys: String, CodingKey { case reference, ready, serving, terminating, addresses, nodeName, zone }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(reference: try c.decodeIfPresent(TopologyObjectReference.self, forKey: .reference), ready: try c.decodeIfPresent(Bool.self, forKey: .ready), serving: try c.decodeIfPresent(Bool.self, forKey: .serving), terminating: try c.decodeIfPresent(Bool.self, forKey: .terminating), addresses: try c.decodeIfPresent([String].self, forKey: .addresses) ?? [], nodeName: try c.decodeIfPresent(String.self, forKey: .nodeName), zone: try c.decodeIfPresent(String.self, forKey: .zone))
    }
}

public struct TopologyEndpointSliceSnapshot: Codable, Hashable, Sendable {
    public let serviceName: String?
    public let addressType: String?
    public let ports: [TopologyEndpointPort]
    public let endpoints: [TopologyEndpointTarget]

    public init(serviceName: String? = nil, addressType: String? = nil, ports: [TopologyEndpointPort] = [], endpoints: [TopologyEndpointTarget] = []) {
        self.serviceName = serviceName.map { TopologySanitizer.clean($0) }
        self.addressType = addressType.map(TopologySanitizer.clean)
        self.ports = ports.sorted { $0.id < $1.id }
        self.endpoints = endpoints.sorted { lhs, rhs in
            let l = [lhs.reference?.namespace ?? "", lhs.reference?.name ?? "", lhs.reference?.uid ?? "", lhs.addresses.joined(separator: ","), lhs.nodeName ?? "", lhs.zone ?? "", lhs.ready.map(String.init) ?? "", lhs.serving.map(String.init) ?? "", lhs.terminating.map(String.init) ?? ""].joined(separator: "|")
            let r = [rhs.reference?.namespace ?? "", rhs.reference?.name ?? "", rhs.reference?.uid ?? "", rhs.addresses.joined(separator: ","), rhs.nodeName ?? "", rhs.zone ?? "", rhs.ready.map(String.init) ?? "", rhs.serving.map(String.init) ?? "", rhs.terminating.map(String.init) ?? ""].joined(separator: "|")
            return l < r
        }
    }

    private enum CodingKeys: String, CodingKey { case serviceName, addressType, ports, endpoints }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(serviceName: try c.decodeIfPresent(String.self, forKey: .serviceName), addressType: try c.decodeIfPresent(String.self, forKey: .addressType), ports: try c.decodeIfPresent([TopologyEndpointPort].self, forKey: .ports) ?? [], endpoints: try c.decodeIfPresent([TopologyEndpointTarget].self, forKey: .endpoints) ?? [])
    }
}

public struct TopologyNamedReference: Codable, Hashable, Sendable {
    public let kind: String
    public let name: String
    public let namespace: String?

    public init(kind: String, name: String, namespace: String? = nil) {
        self.kind = TopologySanitizer.clean(kind)
        self.name = TopologySanitizer.clean(name)
        self.namespace = namespace.map { TopologySanitizer.clean($0) }
    }
}

public enum TopologySelectorOperator: String, Codable, Hashable, Sendable {
    case `in` = "In"
    case notIn = "NotIn"
    case exists = "Exists"
    case doesNotExist = "DoesNotExist"
}

public struct TopologySelectorRequirement: Codable, Hashable, Sendable {
    public let key: String
    public let op: TopologySelectorOperator
    public let values: [String]

    public init(key: String, op: TopologySelectorOperator, values: [String] = []) {
        self.key = TopologySanitizer.labelToken(key)
        self.op = op
        self.values = values.map { TopologySanitizer.labelToken($0) }.sorted()
    }
}

public struct TopologyLabelSelector: Codable, Hashable, Sendable {
    public let matchLabels: [String: String]
    public let matchExpressions: [TopologySelectorRequirement]
    public let summary: String

    public init(matchLabels: [String: String] = [:], matchExpressions: [TopologySelectorRequirement] = []) {
        self.matchLabels = TopologySanitizer.labels(matchLabels)
        self.matchExpressions = matchExpressions.sorted { lhs, rhs in
            lhs.key == rhs.key ? lhs.op.rawValue < rhs.op.rawValue : lhs.key < rhs.key
        }
        self.summary = TopologySanitizer.selectorSummary(rawLabels: matchLabels, expressions: self.matchExpressions)
    }

    fileprivate init(tokenizedMatchLabels: [String: String], tokenizedExpressions: [TopologySelectorRequirement]) {
        self.matchLabels = tokenizedMatchLabels
        self.matchExpressions = tokenizedExpressions
        self.summary = TopologySanitizer.selectorSummary(tokenizedLabels: tokenizedMatchLabels, expressions: tokenizedExpressions)
    }

    private enum CodingKeys: String, CodingKey { case matchLabels, matchExpressions, summary }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let labels = try c.decodeIfPresent([String: String].self, forKey: .matchLabels) ?? [:]
        let expressions = try c.decodeIfPresent([TopologySelectorRequirement].self, forKey: .matchExpressions) ?? []
        self.matchLabels = labels
        self.matchExpressions = expressions
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? TopologySanitizer.selectorSummary(tokenizedLabels: labels, expressions: expressions)
    }

    public func matches(_ labels: [String: String]) -> Bool {
        return matchesTokenized(TopologySanitizer.labels(labels))
    }

    fileprivate func matchesTokenized(_ safeLabels: [String: String]) -> Bool {
        guard matchLabels.allSatisfy({ safeLabels[$0.key] == $0.value }) else { return false }
        return matchExpressions.allSatisfy { requirement in
            let value = safeLabels[requirement.key]
            switch requirement.op {
            case .in: return value.map { requirement.values.contains($0) } ?? false
            // Kubernetes treats a missing label as satisfying NotIn. This is
            // distinct from In/Exists, which require the key to be present.
            case .notIn: return value.map { !requirement.values.contains($0) } ?? true
            case .exists: return value != nil
            case .doesNotExist: return value == nil
            }
        }
    }
}

/// A bounded policy summary. It carries enough metadata to teach policy
/// selection without evaluating peer reachability or effective connectivity.
public struct TopologyNetworkPolicySnapshot: Codable, Hashable, Sendable {
    public let podSelector: TopologyLabelSelector
    public let policyTypes: [String]
    public let ingressRuleCount: Int
    public let egressRuleCount: Int
    public let rules: [TopologyNetworkPolicyRule]

    public init(podSelector: TopologyLabelSelector = TopologyLabelSelector(), policyTypes: [String] = [], ingressRuleCount: Int = 0, egressRuleCount: Int = 0, rules: [TopologyNetworkPolicyRule] = []) {
        self.podSelector = podSelector
        let normalized = policyTypes.map { TopologySanitizer.clean($0).uppercased() }.filter { !$0.isEmpty }
        var derived = normalized
        if derived.isEmpty {
            derived.append("INGRESS")
            if egressRuleCount > 0 || !rules.filter({ $0.direction == .egress }).isEmpty { derived.append("EGRESS") }
        }
        self.policyTypes = Array(Set(derived)).sorted()
        self.ingressRuleCount = max(0, ingressRuleCount)
        self.egressRuleCount = max(0, egressRuleCount)
        self.rules = rules.sorted { $0.id < $1.id }
    }
}

public enum TopologyNetworkPolicyDirection: String, Codable, Hashable, Sendable { case ingress, egress }

public struct TopologyNetworkPolicyPeer: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let podSelector: TopologyLabelSelector?
    public let namespaceSelector: TopologyLabelSelector?
    public let ipBlockCIDR: String?
    public let exceptCIDRs: [String]

    public init(podSelector: TopologyLabelSelector? = nil, namespaceSelector: TopologyLabelSelector? = nil, ipBlockCIDR: String? = nil, exceptCIDRs: [String] = []) {
        self.podSelector = podSelector
        self.namespaceSelector = namespaceSelector
        self.ipBlockCIDR = ipBlockCIDR.map(TopologySanitizer.clean)
        self.exceptCIDRs = exceptCIDRs.map(TopologySanitizer.clean).sorted()
        self.id = TopologyHash.id([ipBlockCIDR ?? "", self.exceptCIDRs.joined(separator: ","), podSelector.map(TopologySort.selectorMaterial) ?? "", namespaceSelector.map(TopologySort.selectorMaterial) ?? ""].joined(separator: "|"))
    }
}

public struct TopologyNetworkPolicyPort: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let number: Int32?
    public let protocolName: String
    public let endPort: Int32?

    public init(name: String? = nil, number: Int32? = nil, protocolName: String = "TCP", endPort: Int32? = nil) {
        self.name = name.map(TopologySanitizer.clean)
        self.number = number
        self.protocolName = TopologySanitizer.clean(protocolName).uppercased()
        self.endPort = endPort
        self.id = TopologyHash.id([name ?? "", number.map(String.init) ?? "", self.protocolName, endPort.map(String.init) ?? ""].joined(separator: "|"))
    }

    public var `protocol`: String { protocolName }
}

public struct TopologyNetworkPolicyRule: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let direction: TopologyNetworkPolicyDirection
    public let peers: [TopologyNetworkPolicyPeer]
    public let ports: [TopologyNetworkPolicyPort]

    public init(direction: TopologyNetworkPolicyDirection, peers: [TopologyNetworkPolicyPeer] = [], ports: [TopologyNetworkPolicyPort] = []) {
        self.direction = direction
        self.peers = peers.sorted { $0.id < $1.id }
        self.ports = ports.sorted { $0.id < $1.id }
        self.id = TopologyHash.id([direction.rawValue, self.peers.map(\.id).joined(separator: ","), self.ports.map(\.id).joined(separator: ",")].joined(separator: "|"))
    }
}

public struct TopologyIngressRoute: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let isDefault: Bool
    public let ruleIndex: Int?
    public let pathIndex: Int?
    public let host: String?
    public let path: String?
    public let pathType: String?
    public let ingressClass: String?
    public let tlsSecretNames: [String]
    public let backendKind: String
    public let backendName: String
    public let backendNamespace: String?
    public let backendPort: Int32?
    public let backendPortName: String?

    public init(isDefault: Bool = false, ruleIndex: Int? = nil, pathIndex: Int? = nil, host: String? = nil, path: String? = nil, pathType: String? = nil, ingressClass: String? = nil, tlsSecretNames: [String] = [], backendKind: String = "Service", backendName: String, backendNamespace: String? = nil, backendPort: Int32? = nil, backendPortName: String? = nil, id: String? = nil) {
        self.isDefault = isDefault
        self.ruleIndex = ruleIndex
        self.pathIndex = pathIndex
        self.host = host.map(TopologySanitizer.clean)
        self.path = path.map(TopologySanitizer.clean)
        self.pathType = pathType.map(TopologySanitizer.clean)
        self.ingressClass = ingressClass.map(TopologySanitizer.clean)
        self.tlsSecretNames = tlsSecretNames.map(TopologySanitizer.clean).sorted()
        self.backendKind = TopologySanitizer.clean(backendKind)
        self.backendName = TopologySanitizer.clean(backendName)
        self.backendNamespace = backendNamespace.map(TopologySanitizer.clean)
        self.backendPort = backendPort
        self.backendPortName = backendPortName.map(TopologySanitizer.clean)
        self.id = id.map(TopologySanitizer.clean) ?? TopologyHash.id([isDefault ? "default" : "rule", String(ruleIndex ?? -1), String(pathIndex ?? -1), host ?? "", path ?? "", backendKind, backendName, backendNamespace ?? "", String(backendPort ?? -1), backendPortName ?? ""].joined(separator: "|"))
    }

    public var serviceReference: TopologyServiceReference { TopologyServiceReference(name: backendName, namespace: backendNamespace, port: backendPort, portName: backendPortName) }
}

public struct TopologyGatewayClassSnapshot: Codable, Hashable, Sendable {
    public let controllerName: String?
    public let parametersRef: TopologyObjectReference?
    public let statusConditions: [String: String]
    public init(controllerName: String? = nil, parametersRef: TopologyObjectReference? = nil, statusConditions: [String: String] = [:]) { self.controllerName = controllerName.map(TopologySanitizer.clean); self.parametersRef = parametersRef; self.statusConditions = TopologySanitizer.attributes(statusConditions) }
}

public struct TopologyGatewayListener: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let protocolName: String
    public let port: Int32
    public let hostname: String?
    public let allowedRouteKinds: [String]
    public init(name: String? = nil, protocolName: String, port: Int32, hostname: String? = nil, allowedRouteKinds: [String] = []) { self.name = name.map(TopologySanitizer.clean); self.protocolName = TopologySanitizer.clean(protocolName).uppercased(); self.port = port; self.hostname = hostname.map(TopologySanitizer.clean); self.allowedRouteKinds = allowedRouteKinds.map(TopologySanitizer.clean).sorted(); self.id = TopologyHash.id([name ?? "", self.protocolName, String(port), hostname ?? ""].joined(separator: "|")) }
}

public struct TopologyGatewayParentReference: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String
    public let namespace: String?
    public let sectionName: String?
    public let accepted: Bool?
    public let resolvedRefs: Bool?
    public init(kind: String = "Gateway", name: String, namespace: String? = nil, sectionName: String? = nil, accepted: Bool? = nil, resolvedRefs: Bool? = nil) { self.kind = TopologySanitizer.clean(kind); self.name = TopologySanitizer.clean(name); self.namespace = namespace.map(TopologySanitizer.clean); self.sectionName = sectionName.map(TopologySanitizer.clean); self.accepted = accepted; self.resolvedRefs = resolvedRefs; self.id = TopologyHash.id([kind, name, namespace ?? "", sectionName ?? ""].joined(separator: "|")) }
}

public struct TopologyGatewayBackendReference: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let name: String
    public let namespace: String?
    public let port: Int32?
    public let weight: Int32?
    public let resolvedRefs: Bool?
    public init(kind: String = "Service", name: String, namespace: String? = nil, port: Int32? = nil, weight: Int32? = nil, resolvedRefs: Bool? = nil) { self.kind = TopologySanitizer.clean(kind); self.name = TopologySanitizer.clean(name); self.namespace = namespace.map(TopologySanitizer.clean); self.port = port; self.weight = weight; self.resolvedRefs = resolvedRefs; self.id = TopologyHash.id([kind, name, namespace ?? "", String(port ?? -1), String(weight ?? -1)].joined(separator: "|")) }
}

public struct TopologyGatewaySnapshot: Codable, Hashable, Sendable {
    public let gatewayClassName: String?
    public let listeners: [TopologyGatewayListener]
    public let statusConditions: [String: String]
    public init(gatewayClassName: String? = nil, listeners: [TopologyGatewayListener] = [], statusConditions: [String: String] = [:]) { self.gatewayClassName = gatewayClassName.map(TopologySanitizer.clean); self.listeners = listeners.sorted { $0.id < $1.id }; self.statusConditions = TopologySanitizer.attributes(statusConditions) }
}

public struct TopologyHTTPRouteSnapshot: Codable, Hashable, Sendable {
    public let hostnames: [String]
    public let parents: [TopologyGatewayParentReference]
    public let backends: [TopologyGatewayBackendReference]
    public let statusConditions: [String: String]
    public init(hostnames: [String] = [], parents: [TopologyGatewayParentReference] = [], backends: [TopologyGatewayBackendReference] = [], statusConditions: [String: String] = [:]) { self.hostnames = hostnames.map(TopologySanitizer.clean).sorted(); self.parents = parents.sorted { $0.id < $1.id }; self.backends = backends.sorted { $0.id < $1.id }; self.statusConditions = TopologySanitizer.attributes(statusConditions) }
}

public enum TopologyServiceMode: String, Codable, Hashable, Sendable, CaseIterable {
    case standard
    case headless
    case selectorless
    case externalName
    case nodePort
    case loadBalancer
}

public struct TopologyResourceSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let identity: TopologyResourceIdentity
    public let ownerReferences: [TopologyOwnerReference]
    public let podNodeName: String?
    public let selector: [String: String]
    public let selectorExpressions: [TopologySelectorRequirement]
    public let ingressBackends: [TopologyServiceReference]
    public let ingressRoutes: [TopologyIngressRoute]
    public let endpointSlice: TopologyEndpointSliceSnapshot?
    public let servicePorts: [TopologyServicePort]
    public let serviceMode: TopologyServiceMode?
    public let containerPorts: [TopologyContainerPort]
    public let initContainerPorts: [TopologyContainerPort]
    public let ephemeralContainerPorts: [TopologyContainerPort]
    public let gatewayClass: TopologyGatewayClassSnapshot?
    public let gateway: TopologyGatewaySnapshot?
    public let httpRoute: TopologyHTTPRouteSnapshot?
    public let volumeReferences: [TopologyObjectReference]
    public let configReferences: [TopologyNamedReference]
    public let roleLabels: [String: String]
    public let networkPolicy: TopologyNetworkPolicySnapshot?
    public let facts: [TopologyFact]

    public init(identity: TopologyResourceIdentity, ownerReferences: [TopologyOwnerReference] = [], podNodeName: String? = nil, selector: [String: String] = [:], selectorExpressions: [TopologySelectorRequirement] = [], ingressBackends: [TopologyServiceReference] = [], ingressRoutes: [TopologyIngressRoute] = [], endpointSlice: TopologyEndpointSliceSnapshot? = nil, servicePorts: [TopologyServicePort] = [], serviceMode: TopologyServiceMode? = nil, containerPorts: [TopologyContainerPort] = [], initContainerPorts: [TopologyContainerPort] = [], ephemeralContainerPorts: [TopologyContainerPort] = [], gatewayClass: TopologyGatewayClassSnapshot? = nil, gateway: TopologyGatewaySnapshot? = nil, httpRoute: TopologyHTTPRouteSnapshot? = nil, volumeReferences: [TopologyObjectReference] = [], configReferences: [TopologyNamedReference] = [], roleLabels: [String: String] = [:], networkPolicy: TopologyNetworkPolicySnapshot? = nil, facts: [TopologyFact] = []) {
        self.identity = identity
        self.id = identity.stableNodeID(contextID: "snapshot")
        self.ownerReferences = ownerReferences.sorted(by: TopologySort.owner)
        self.podNodeName = podNodeName.map(TopologySanitizer.clean)
        self.selector = TopologySanitizer.labels(selector)
        self.selectorExpressions = selectorExpressions.sorted { lhs, rhs in lhs.key == rhs.key ? lhs.op.rawValue < rhs.op.rawValue : lhs.key < rhs.key }
        self.ingressBackends = ingressBackends.sorted(by: TopologySort.service)
        self.ingressRoutes = ingressRoutes.sorted { $0.id < $1.id }
        self.endpointSlice = endpointSlice
        self.servicePorts = servicePorts.sorted { $0.id < $1.id }
        self.serviceMode = serviceMode
        self.containerPorts = containerPorts.sorted { $0.id < $1.id }
        self.initContainerPorts = initContainerPorts.sorted { $0.id < $1.id }
        self.ephemeralContainerPorts = ephemeralContainerPorts.sorted { $0.id < $1.id }
        self.gatewayClass = gatewayClass
        self.gateway = gateway
        self.httpRoute = httpRoute
        self.volumeReferences = volumeReferences.sorted(by: TopologySort.reference)
        self.configReferences = configReferences.sorted(by: TopologySort.namedReference)
        self.roleLabels = TopologySanitizer.labels(roleLabels)
        self.networkPolicy = networkPolicy
        var safeFacts = facts
        let roleNames = Set(roleLabels.compactMap { key, value -> String? in
            if key.hasPrefix("node-role.kubernetes.io/") {
                let role = String(key.dropFirst("node-role.kubernetes.io/".count))
                return role.isEmpty ? "worker" : role
            }
            if key == "kubernetes.io/role" {
                let allowed = Set(["control-plane", "master", "worker"])
                let normalized = value.lowercased()
                return allowed.contains(normalized) ? normalized : "custom"
            }
            return nil
        })
        if !roleNames.isEmpty {
            safeFacts.append(TopologyFact(key: "roles", title: "Roles", value: roleNames.sorted().joined(separator: ", ")))
        }
        self.facts = safeFacts.sorted { $0.key == $1.key ? $0.title < $1.title : $0.key < $1.key }
    }

    private enum CodingKeys: String, CodingKey { case identity, ownerReferences, podNodeName, selector, selectorExpressions, ingressBackends, ingressRoutes, endpointSlice, servicePorts, serviceMode, containerPorts, initContainerPorts, ephemeralContainerPorts, gatewayClass, gateway, httpRoute, volumeReferences, configReferences, roleLabels, networkPolicy, facts }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(identity: try c.decode(TopologyResourceIdentity.self, forKey: .identity), ownerReferences: try c.decodeIfPresent([TopologyOwnerReference].self, forKey: .ownerReferences) ?? [], podNodeName: try c.decodeIfPresent(String.self, forKey: .podNodeName), selector: try c.decodeIfPresent([String: String].self, forKey: .selector) ?? [:], selectorExpressions: try c.decodeIfPresent([TopologySelectorRequirement].self, forKey: .selectorExpressions) ?? [], ingressBackends: try c.decodeIfPresent([TopologyServiceReference].self, forKey: .ingressBackends) ?? [], ingressRoutes: try c.decodeIfPresent([TopologyIngressRoute].self, forKey: .ingressRoutes) ?? [], endpointSlice: try c.decodeIfPresent(TopologyEndpointSliceSnapshot.self, forKey: .endpointSlice), servicePorts: try c.decodeIfPresent([TopologyServicePort].self, forKey: .servicePorts) ?? [], serviceMode: try c.decodeIfPresent(TopologyServiceMode.self, forKey: .serviceMode), containerPorts: try c.decodeIfPresent([TopologyContainerPort].self, forKey: .containerPorts) ?? [], initContainerPorts: try c.decodeIfPresent([TopologyContainerPort].self, forKey: .initContainerPorts) ?? [], ephemeralContainerPorts: try c.decodeIfPresent([TopologyContainerPort].self, forKey: .ephemeralContainerPorts) ?? [], gatewayClass: try c.decodeIfPresent(TopologyGatewayClassSnapshot.self, forKey: .gatewayClass), gateway: try c.decodeIfPresent(TopologyGatewaySnapshot.self, forKey: .gateway), httpRoute: try c.decodeIfPresent(TopologyHTTPRouteSnapshot.self, forKey: .httpRoute), volumeReferences: try c.decodeIfPresent([TopologyObjectReference].self, forKey: .volumeReferences) ?? [], configReferences: try c.decodeIfPresent([TopologyNamedReference].self, forKey: .configReferences) ?? [], roleLabels: try c.decodeIfPresent([String: String].self, forKey: .roleLabels) ?? [:], networkPolicy: try c.decodeIfPresent(TopologyNetworkPolicySnapshot.self, forKey: .networkPolicy), facts: try c.decodeIfPresent([TopologyFact].self, forKey: .facts) ?? [])
    }
}

public enum TopologyRelationship: String, Codable, Hashable, Sendable, CaseIterable {
    case containedIn
    case ownedBy
    case scheduledOn
    case selects
    case publishesEndpoints
    case endpointTarget
    case routesTo
    case references
    case backedBy
    case usesStorageClass
    case inputUnavailable
}

public struct TopologyFact: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let key: String
    public let title: String
    public let value: String

    public init(key: String, title: String, value: String) {
        self.key = TopologySanitizer.clean(key)
        self.title = TopologySanitizer.clean(title)
        self.value = TopologySanitizer.looksSensitive(key) || TopologySanitizer.looksSensitive(title) ? "[REDACTED]" : TopologySanitizer.clean(value)
        self.id = TopologyHash.id([self.key, self.title, self.value].joined(separator: "|"))
    }
}

public struct TopologyNode: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let contextID: String
    public let apiVersion: String
    public let kind: String
    public let name: String
    public let namespace: String?
    public let uid: String?
    public let resourceVersion: String?
    public let isVirtual: Bool
    public let virtualKind: String?
    public let evidence: TopologyEvidence
    public let facts: [TopologyFact]

    public init(id: String, contextID: String, apiVersion: String, kind: String, name: String, namespace: String? = nil, uid: String? = nil, resourceVersion: String? = nil, isVirtual: Bool = false, virtualKind: String? = nil, evidence: TopologyEvidence, facts: [TopologyFact] = []) {
        self.id = TopologySanitizer.clean(id)
        self.contextID = TopologySanitizer.clean(contextID)
        self.apiVersion = TopologySanitizer.clean(apiVersion)
        self.kind = TopologySanitizer.clean(kind)
        self.name = TopologySanitizer.clean(name)
        self.namespace = namespace.map { TopologySanitizer.clean($0) }
        self.uid = uid.map { TopologySanitizer.clean($0) }
        self.resourceVersion = resourceVersion.map { TopologySanitizer.clean($0) }
        self.isVirtual = isVirtual
        self.virtualKind = virtualKind.map { TopologySanitizer.clean($0) }
        self.evidence = evidence
        self.facts = facts.sorted { $0.key == $1.key ? $0.title < $1.title : $0.key < $1.key }
    }
}

public struct TopologyEdge: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let from: String
    public let to: String
    public let relationship: TopologyRelationship
    public let evidence: TopologyEvidence
    public let attributes: [String: String]

    public init(from: String, to: String, relationship: TopologyRelationship, evidence: TopologyEvidence, attributes: [String: String] = [:]) {
        self.from = from
        self.to = to
        self.relationship = relationship
        self.evidence = evidence
        self.attributes = TopologySanitizer.attributes(attributes)
        let material = [from, to, relationship.rawValue, self.attributes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "&")].joined(separator: "|")
        self.id = TopologyHash.id(material)
    }
}

public struct TopologyUnresolvedReference: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let relation: TopologyRelationship
    public let sourceNodeID: String?
    public let target: TopologyObjectReference
    public let reason: String
    public let evidence: TopologyEvidence

    public init(relation: TopologyRelationship, sourceNodeID: String?, target: TopologyObjectReference, reason: String, evidence: TopologyEvidence) {
        self.relation = relation
        self.sourceNodeID = sourceNodeID
        self.target = target
        self.reason = TopologySanitizer.clean(reason)
        self.evidence = evidence
        self.id = TopologyHash.id([relation.rawValue, sourceNodeID ?? "", target.kind, target.namespace ?? "", target.name, target.uid ?? ""].joined(separator: "|"))
    }
}

public enum TopologyPortPathStatus: String, Codable, Hashable, Sendable { case complete, partial, unresolved, external, noEndpoint, noReadyEndpoint }

public struct TopologyPortHop: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let role: String
    public let reference: TopologyObjectReference?
    public let portName: String?
    public let portNumber: Int32?
    public let protocolName: String?
    /// Service-level target resolution metadata. This is populated on a
    /// `service-port` hop so portable clients can explain the hop without
    /// reaching back into a platform-specific detail model.
    public let targetPort: TopologyPortTarget?
    public let nodePort: Int32?
    public let appProtocol: String?
    public let addresses: [String]
    public let ready: Bool?
    public let serving: Bool?
    public let terminating: Bool?
    public let nodeName: String?
    public let zone: String?
    public let containerName: String?
    public let evidence: TopologyEvidence

    // Keep the original positional argument order intact; new metadata is
    // appended after the required evidence argument for source compatibility.
    public init(role: String, reference: TopologyObjectReference? = nil, portName: String? = nil, portNumber: Int32? = nil, protocolName: String? = nil, addresses: [String] = [], ready: Bool? = nil, serving: Bool? = nil, terminating: Bool? = nil, nodeName: String? = nil, zone: String? = nil, containerName: String? = nil, evidence: TopologyEvidence, targetPort: TopologyPortTarget? = nil, nodePort: Int32? = nil, appProtocol: String? = nil) {
        self.role = TopologySanitizer.clean(role)
        self.reference = reference
        self.portName = portName.map(TopologySanitizer.clean)
        self.portNumber = portNumber
        self.protocolName = protocolName.map { TopologySanitizer.clean($0).uppercased() }
        self.targetPort = targetPort
        self.nodePort = nodePort
        self.appProtocol = appProtocol.map(TopologySanitizer.clean)
        self.addresses = addresses.map(TopologySanitizer.clean).sorted()
        self.ready = ready
        self.serving = serving
        self.terminating = terminating
        self.nodeName = nodeName.map(TopologySanitizer.clean)
        self.zone = zone.map(TopologySanitizer.clean)
        self.containerName = containerName.map(TopologySanitizer.clean)
        self.evidence = evidence
        var idParts: [String] = [self.role]
        idParts.append(contentsOf: [reference?.apiVersion ?? "", reference?.kind ?? "", reference?.namespace ?? "", reference?.name ?? "", reference?.uid ?? ""])
        idParts.append(contentsOf: [self.portName ?? "", String(self.portNumber ?? -1), targetPort?.name ?? "", targetPort?.number.map { String($0) } ?? "", String(nodePort ?? -1)])
        idParts.append(contentsOf: [self.protocolName ?? "", self.appProtocol ?? "", self.addresses.joined(separator: ",")])
        idParts.append(contentsOf: [self.ready.map { String($0) } ?? "", self.serving.map { String($0) } ?? "", self.terminating.map { String($0) } ?? "", self.nodeName ?? "", self.zone ?? "", self.containerName ?? ""])
        self.id = TopologyHash.id(idParts.joined(separator: "|"))
    }

    private enum CodingKeys: String, CodingKey { case role, reference, portName, portNumber, protocolName, targetPort, nodePort, appProtocol, addresses, ready, serving, terminating, nodeName, zone, containerName, evidence }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(role: try c.decode(String.self, forKey: .role), reference: try c.decodeIfPresent(TopologyObjectReference.self, forKey: .reference), portName: try c.decodeIfPresent(String.self, forKey: .portName), portNumber: try c.decodeIfPresent(Int32.self, forKey: .portNumber), protocolName: try c.decodeIfPresent(String.self, forKey: .protocolName), addresses: try c.decodeIfPresent([String].self, forKey: .addresses) ?? [], ready: try c.decodeIfPresent(Bool.self, forKey: .ready), serving: try c.decodeIfPresent(Bool.self, forKey: .serving), terminating: try c.decodeIfPresent(Bool.self, forKey: .terminating), nodeName: try c.decodeIfPresent(String.self, forKey: .nodeName), zone: try c.decodeIfPresent(String.self, forKey: .zone), containerName: try c.decodeIfPresent(String.self, forKey: .containerName), evidence: try c.decode(TopologyEvidence.self, forKey: .evidence), targetPort: try c.decodeIfPresent(TopologyPortTarget.self, forKey: .targetPort), nodePort: try c.decodeIfPresent(Int32.self, forKey: .nodePort), appProtocol: try c.decodeIfPresent(String.self, forKey: .appProtocol))
    }
}

public struct TopologyPortPath: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let source: TopologyObjectReference
    public let status: TopologyPortPathStatus
    public let hops: [TopologyPortHop]
    public let provenance: [TopologyEvidence]
    public let note: String?
    public let readyEndpointCount: Int
    public let totalEndpointCount: Int
    /// True when the bounded path representation omitted one or more
    /// EndpointSlice/endpoint observations. A truncated path is always
    /// partial; consumers must not interpret the visible hops as exhaustive.
    public let isTruncated: Bool
    public let omittedHopCount: Int
    public let omittedEndpointCount: Int
    public let omittedEndpointPortCount: Int

    public init(source: TopologyObjectReference, status: TopologyPortPathStatus, hops: [TopologyPortHop] = [], provenance: [TopologyEvidence] = [], note: String? = nil, readyEndpointCount: Int = 0, totalEndpointCount: Int = 0, id: String? = nil, isTruncated: Bool = false, omittedHopCount: Int = 0, omittedEndpointCount: Int = 0, omittedEndpointPortCount: Int = 0) {
        self.source = source
        self.status = status
        self.hops = hops
        self.provenance = provenance
        self.note = note.map(TopologySanitizer.clean)
        self.readyEndpointCount = max(0, readyEndpointCount)
        self.totalEndpointCount = max(0, totalEndpointCount)
        self.isTruncated = isTruncated
        self.omittedHopCount = max(0, omittedHopCount)
        self.omittedEndpointCount = max(0, omittedEndpointCount)
        self.omittedEndpointPortCount = max(0, omittedEndpointPortCount)
        self.id = id.map(TopologySanitizer.clean) ?? TopologyHash.id([source.kind, source.namespace ?? "", source.name, status.rawValue, hops.map(\.id).joined(separator: ",")].joined(separator: "|"))
    }

    private enum CodingKeys: String, CodingKey { case source, status, hops, provenance, note, readyEndpointCount, totalEndpointCount, id, isTruncated, omittedHopCount, omittedEndpointCount, omittedEndpointPortCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(source: try c.decode(TopologyObjectReference.self, forKey: .source), status: try c.decode(TopologyPortPathStatus.self, forKey: .status), hops: try c.decodeIfPresent([TopologyPortHop].self, forKey: .hops) ?? [], provenance: try c.decodeIfPresent([TopologyEvidence].self, forKey: .provenance) ?? [], note: try c.decodeIfPresent(String.self, forKey: .note), readyEndpointCount: try c.decodeIfPresent(Int.self, forKey: .readyEndpointCount) ?? 0, totalEndpointCount: try c.decodeIfPresent(Int.self, forKey: .totalEndpointCount) ?? 0, id: try c.decodeIfPresent(String.self, forKey: .id), isTruncated: try c.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false, omittedHopCount: try c.decodeIfPresent(Int.self, forKey: .omittedHopCount) ?? 0, omittedEndpointCount: try c.decodeIfPresent(Int.self, forKey: .omittedEndpointCount) ?? 0, omittedEndpointPortCount: try c.decodeIfPresent(Int.self, forKey: .omittedEndpointPortCount) ?? 0)
    }
}

/// Sanitized, typed detail retained beside each graph node. This intentionally
/// excludes raw Kubernetes payloads while allowing a detail inspector to
/// explain ports, routes, selectors, policies and evidence after graph build.
public struct TopologyNodeDetails: Codable, Hashable, Sendable {
    public let selector: [String: String]
    public let selectorExpressions: [TopologySelectorRequirement]
    public let selectorSummary: String
    public let ingressRoutes: [TopologyIngressRoute]
    public let servicePorts: [TopologyServicePort]
    public let serviceMode: TopologyServiceMode?
    public let containerPorts: [TopologyContainerPort]
    public let initContainerPorts: [TopologyContainerPort]
    public let ephemeralContainerPorts: [TopologyContainerPort]
    public let endpointSlice: TopologyEndpointSliceSnapshot?
    public let gatewayClass: TopologyGatewayClassSnapshot?
    public let gateway: TopologyGatewaySnapshot?
    public let httpRoute: TopologyHTTPRouteSnapshot?
    public let networkPolicy: TopologyNetworkPolicySnapshot?
    public let facts: [TopologyFact]

    public init(resource: TopologyResourceSnapshot) {
        self.selector = resource.selector
        self.selectorExpressions = resource.selectorExpressions
        self.selectorSummary = TopologySanitizer.selectorSummary(tokenizedLabels: resource.selector, expressions: resource.selectorExpressions)
        self.ingressRoutes = resource.ingressRoutes
        self.servicePorts = resource.servicePorts
        self.serviceMode = resource.serviceMode
        self.containerPorts = resource.containerPorts
        self.initContainerPorts = resource.initContainerPorts
        self.ephemeralContainerPorts = resource.ephemeralContainerPorts
        self.endpointSlice = resource.endpointSlice
        self.gatewayClass = resource.gatewayClass
        self.gateway = resource.gateway
        self.httpRoute = resource.httpRoute
        self.networkPolicy = resource.networkPolicy
        self.facts = resource.facts
    }

    private enum CodingKeys: String, CodingKey { case selector, selectorExpressions, selectorSummary, ingressRoutes, servicePorts, serviceMode, containerPorts, initContainerPorts, ephemeralContainerPorts, endpointSlice, gatewayClass, gateway, httpRoute, networkPolicy, facts }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let selector = try c.decodeIfPresent([String: String].self, forKey: .selector) ?? [:]
        let expressions = try c.decodeIfPresent([TopologySelectorRequirement].self, forKey: .selectorExpressions) ?? []
        self.selector = selector
        self.selectorExpressions = expressions
        self.selectorSummary = try c.decodeIfPresent(String.self, forKey: .selectorSummary) ?? TopologySanitizer.selectorSummary(tokenizedLabels: selector, expressions: expressions)
        self.ingressRoutes = try c.decodeIfPresent([TopologyIngressRoute].self, forKey: .ingressRoutes) ?? []
        self.servicePorts = try c.decodeIfPresent([TopologyServicePort].self, forKey: .servicePorts) ?? []
        self.serviceMode = try c.decodeIfPresent(TopologyServiceMode.self, forKey: .serviceMode)
        self.containerPorts = try c.decodeIfPresent([TopologyContainerPort].self, forKey: .containerPorts) ?? []
        self.initContainerPorts = try c.decodeIfPresent([TopologyContainerPort].self, forKey: .initContainerPorts) ?? []
        self.ephemeralContainerPorts = try c.decodeIfPresent([TopologyContainerPort].self, forKey: .ephemeralContainerPorts) ?? []
        self.endpointSlice = try c.decodeIfPresent(TopologyEndpointSliceSnapshot.self, forKey: .endpointSlice)
        self.gatewayClass = try c.decodeIfPresent(TopologyGatewayClassSnapshot.self, forKey: .gatewayClass)
        self.gateway = try c.decodeIfPresent(TopologyGatewaySnapshot.self, forKey: .gateway)
        self.httpRoute = try c.decodeIfPresent(TopologyHTTPRouteSnapshot.self, forKey: .httpRoute)
        self.networkPolicy = try c.decodeIfPresent(TopologyNetworkPolicySnapshot.self, forKey: .networkPolicy)
        self.facts = try c.decodeIfPresent([TopologyFact].self, forKey: .facts) ?? []
    }
}

public struct TopologyGraph: Codable, Hashable, Sendable {
    public let contextID: String
    public let freshness: TopologyFreshness
    public let completeness: TopologySnapshotCompleteness
    public let nodes: [TopologyNode]
    public let edges: [TopologyEdge]
    public let unresolvedReferences: [TopologyUnresolvedReference]
    public let inputs: [TopologyInputStatus]
    public let portPaths: [TopologyPortPath]
    public let details: [String: TopologyNodeDetails]

    public init(contextID: String, freshness: TopologyFreshness, completeness: TopologySnapshotCompleteness, nodes: [TopologyNode], edges: [TopologyEdge], unresolvedReferences: [TopologyUnresolvedReference] = [], inputs: [TopologyInputStatus] = [], portPaths: [TopologyPortPath] = [], details: [String: TopologyNodeDetails] = [:]) {
        self.contextID = TopologySanitizer.clean(contextID)
        self.freshness = freshness
        self.completeness = completeness
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
        self.unresolvedReferences = unresolvedReferences.sorted { $0.id < $1.id }
        self.inputs = inputs.sorted { $0.id < $1.id }
        self.portPaths = portPaths.sorted { $0.id < $1.id }
        self.details = details
    }

    private enum CodingKeys: String, CodingKey { case contextID, freshness, completeness, nodes, edges, unresolvedReferences, inputs, portPaths, details }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(contextID: try c.decode(String.self, forKey: .contextID), freshness: try c.decode(TopologyFreshness.self, forKey: .freshness), completeness: try c.decode(TopologySnapshotCompleteness.self, forKey: .completeness), nodes: try c.decode([TopologyNode].self, forKey: .nodes), edges: try c.decode([TopologyEdge].self, forKey: .edges), unresolvedReferences: try c.decodeIfPresent([TopologyUnresolvedReference].self, forKey: .unresolvedReferences) ?? [], inputs: try c.decodeIfPresent([TopologyInputStatus].self, forKey: .inputs) ?? [], portPaths: try c.decodeIfPresent([TopologyPortPath].self, forKey: .portPaths) ?? [], details: try c.decodeIfPresent([String: TopologyNodeDetails].self, forKey: .details) ?? [:])
    }
}

/// Shared semantic navigation vocabulary used by both native front ends.
/// Levels describe learning scope; they are not Kubernetes labels or network
/// zones.
public enum ExplorerLevel: String, Codable, Hashable, Sendable, CaseIterable {
    case cluster
    case infrastructure
    case workloads
    case network
    case policyDependencies = "policy_dependencies"
    case evidence
}

public enum ExplorerMode: String, Codable, Hashable, Sendable, CaseIterable { case focus, trace, inventory }
public enum ExplorerPresentation: String, Codable, Hashable, Sendable, CaseIterable { case map, list, portTable = "port_table" }

/// Deterministic, UI-free queries over a topology snapshot. Consumers can use
/// the same filtering and one-hop focus behavior on macOS, Linux and TUI.
public struct TopologyGraphQuery: Codable, Hashable, Sendable {
    public let graph: TopologyGraph

    public init(graph: TopologyGraph) { self.graph = graph }

    private static func detailSearch(_ item: TopologyNodeDetails) -> String {
        var parts = [item.selectorSummary]
        let servicePortTerms = item.servicePorts.map { port -> String in
            let nodePort = port.nodePort.map { String($0) } ?? ""
            return [port.name ?? "", String(port.port), port.protocolName, port.appProtocol ?? "", nodePort]
                .joined(separator: " ")
        }
        parts.append(servicePortTerms.joined(separator: " "))
        let containers = item.containerPorts + item.initContainerPorts + item.ephemeralContainerPorts
        parts.append(containers.map { port in
            [port.containerName, port.name ?? "", String(port.port), port.protocolName, port.hostPort.map(String.init) ?? "", port.hostIP ?? ""].joined(separator: " ")
        }.joined(separator: " "))
        if let slice = item.endpointSlice {
            let endpointPortTerms = slice.ports.map { port -> String in
                [port.name ?? "", String(port.port), port.protocolName, port.appProtocol ?? ""]
                    .joined(separator: " ")
            }
            let endpointAddresses = slice.endpoints.flatMap(\.addresses).joined(separator: " ")
            parts.append([
                slice.addressType ?? "",
                slice.serviceName ?? "",
                endpointPortTerms.joined(separator: " "),
                endpointAddresses,
            ].joined(separator: " "))
        }
        parts.append(item.ingressRoutes.map { route in
            [route.host ?? "", route.path ?? "", route.backendName, route.backendPort.map(String.init) ?? "", route.backendPortName ?? "", route.ingressClass ?? ""].joined(separator: " ")
        }.joined(separator: " "))
        if let gateway = item.gateway {
            let listenerTerms = gateway.listeners.map { listener -> String in
                [listener.name ?? "", listener.protocolName, String(listener.port), listener.hostname ?? ""]
                    .joined(separator: " ")
            }
            let conditionTerms = gateway.statusConditions
                .map { "\($0.key) \($0.value)" }
                .joined(separator: " ")
            parts.append([gateway.gatewayClassName ?? "", listenerTerms.joined(separator: " "), conditionTerms]
                .joined(separator: " "))
        }
        if let route = item.httpRoute {
            let backendTerms = route.backends.map { backend -> String in
                let port = backend.port.map { String($0) } ?? ""
                return "\(backend.name) \(port)"
            }
            let conditionTerms = route.statusConditions
                .map { "\($0.key) \($0.value)" }
                .joined(separator: " ")
            parts.append([
                route.hostnames.joined(separator: " "),
                route.parents.map(\.name).joined(separator: " "),
                backendTerms.joined(separator: " "),
                conditionTerms,
            ].joined(separator: " "))
        }
        if let policy = item.networkPolicy {
            parts.append([policy.podSelector.summary, policy.policyTypes.joined(separator: " "), policy.rules.map { rule in
                [rule.direction.rawValue, rule.ports.map { port in
                    [port.name ?? "", port.number.map(String.init) ?? "", port.protocolName, port.endPort.map(String.init) ?? ""].joined(separator: " ")
                }.joined(separator: " ")].joined(separator: " ")
            }.joined(separator: " ")].joined(separator: " "))
        }
        return parts.joined(separator: " ")
    }

    private static func pathSearch(_ path: TopologyPortPath) -> String {
        var parts = [path.source.kind, path.source.name, path.source.namespace ?? "", path.status.rawValue, path.note ?? "", path.isTruncated ? "truncated" : "", String(path.omittedHopCount), String(path.omittedEndpointCount), String(path.omittedEndpointPortCount)]
        parts.append(contentsOf: path.hops.map { hop in
            let target = hop.targetPort.map { [$0.name ?? "", $0.number.map(String.init) ?? "", $0.usesServicePortByDefault ? "default" : ""].joined(separator: " ") } ?? ""
            return [hop.role, hop.portName ?? "", hop.portNumber.map(String.init) ?? "", hop.protocolName ?? "", target, hop.nodePort.map(String.init) ?? "", hop.appProtocol ?? "", hop.addresses.joined(separator: " "), hop.containerName ?? "", hop.evidence.level.rawValue, hop.evidence.source.sourceField ?? "", hop.evidence.source.joinRule ?? "", hop.evidence.source.assumption ?? ""].joined(separator: " ")
        })
        parts.append(contentsOf: path.provenance.map { evidence in
            [evidence.level.rawValue, evidence.source.sourceField ?? "", evidence.source.joinRule ?? "", evidence.source.assumption ?? "", evidence.source.note ?? ""].joined(separator: " ")
        })
        return parts.joined(separator: " ")
    }

    public func nodes(level: ExplorerLevel? = nil, search: String? = nil, kind: String? = nil, namespace: String? = nil, evidence: TopologyEvidenceLevel? = nil) -> [TopologyNode] {
        graph.nodes.filter { node in
            guard level == nil || Self.level(for: node.kind) == level else { return false }
            guard kind == nil || node.kind.caseInsensitiveCompare(kind!) == .orderedSame else { return false }
            guard namespace == nil || node.namespace == namespace else { return false }
            guard evidence == nil || node.evidence.level == evidence else { return false }
            guard let search, !search.isEmpty else { return true }
            let typedDetail = graph.details[node.id].map(Self.detailSearch) ?? ""
            let haystack = [node.kind, node.name, node.namespace ?? "", node.facts.map { "\($0.title) \($0.value)" }.joined(separator: " "), typedDetail].joined(separator: " ").lowercased()
            return haystack.contains(search.lowercased())
        }.sorted { $0.id < $1.id }
    }

    public func edges(level: ExplorerLevel? = nil, evidence: TopologyEvidenceLevel? = nil, focusedNodeIDs: Set<String> = []) -> [TopologyEdge] {
        let allowed = level.map { Set(nodes(level: $0).map(\.id)) }
        return graph.edges.filter { edge in
            guard allowed == nil || allowed!.contains(edge.from) || allowed!.contains(edge.to) else { return false }
            guard evidence == nil || edge.evidence.level == evidence else { return false }
            guard focusedNodeIDs.isEmpty || focusedNodeIDs.contains(edge.from) || focusedNodeIDs.contains(edge.to) else { return false }
            return true
        }.sorted { $0.id < $1.id }
    }

    public func portPaths(level: ExplorerLevel? = nil, protocolName: String? = nil, port: Int32? = nil, readiness: Bool? = nil, search: String? = nil) -> [TopologyPortPath] {
        guard level == nil || level == .network || level == .evidence else { return [] }
        return graph.portPaths.filter { path in
            guard let protocolName else { _ = () ; return true }
            return path.hops.contains { $0.protocolName?.caseInsensitiveCompare(protocolName) == .orderedSame }
        }.filter { path in
            guard let port else { return true }
            return path.hops.contains { $0.portNumber == port }
        }.filter { path in
            guard let readiness else { return true }
            let endpointHops = path.hops.filter { $0.role == "endpoint" }
            return readiness ? endpointHops.contains { $0.ready != false && !($0.terminating == true && $0.serving == false) } : endpointHops.contains { $0.ready == false || ($0.terminating == true && $0.serving == false) }
        }.filter { path in
            guard let search, !search.isEmpty else { return true }
            let haystack = Self.pathSearch(path).lowercased()
            return haystack.contains(search.lowercased())
        }.sorted { $0.id < $1.id }
    }

    /// Returns the selected nodes plus their directly related neighbors.
    public func oneHopFocus(nodeIDs: Set<String>, level: ExplorerLevel? = nil) -> Set<String> {
        var result = nodeIDs
        for edge in edges(level: level) where nodeIDs.contains(edge.from) || nodeIDs.contains(edge.to) {
            result.insert(edge.from)
            result.insert(edge.to)
        }
        return result
    }

    public static func level(for kind: String) -> ExplorerLevel {
        switch kind.lowercased() {
        case "namespace", "namespaces", "controlplaneboundary": return .cluster
        case "node", "nodes", "persistentvolume", "persistentvolumes", "storageclass", "storageclasses", "gatewayclass", "gatewayclasses", "ingressclass", "ingressclasses": return .infrastructure
        case "deployment", "deployments", "statefulset", "statefulsets", "daemonset", "daemonsets", "replicaset", "replicasets", "job", "jobs", "cronjob", "cronjobs", "pod", "pods": return .workloads
        case "service", "services", "endpointslice", "endpointslices", "ingress", "ingresses", "gateway", "gateways", "httproute", "httproutes", "grpcroute", "grpcroutes", "tcproute", "tcproutes", "udproute", "udproutes": return .network
        case "networkpolicy", "networkpolicies", "persistentvolumeclaim", "persistentvolumeclaims", "configmap", "configmaps", "secret", "secrets", "serviceaccount", "serviceaccounts", "resourcequota", "resourcequotas", "limitrange", "limitranges": return .policyDependencies
        default: return .evidence
        }
    }
}

public struct TopologyBuildInput: Codable, Hashable, Sendable {
    public let contextID: String
    public let resources: [TopologyResourceSnapshot]
    public let inputs: [TopologyInputStatus]
    public let freshness: TopologyFreshness

    public init(contextID: String, resources: [TopologyResourceSnapshot], inputs: [TopologyInputStatus] = [], freshness: TopologyFreshness = TopologyFreshness()) {
        self.contextID = TopologySanitizer.clean(contextID)
        self.resources = resources
        self.inputs = inputs
        self.freshness = freshness
    }
}

/// Converts sanitized Kubernetes observations into a deterministic evidence
/// graph. No raw payloads, annotations, Secret values, or ConfigMap values are
/// accepted by this boundary.
public enum TopologyGraphBuilder {
    /// Hard cap on materialized hops for one route path. Counts route/service,
    /// EndpointSlice ports, endpoints and optional container declarations.
    /// Counts and evidence remain explicit when this bound is reached.
    private static let maxPortPathHops = 512

    public static func build(_ input: TopologyBuildInput) -> TopologyGraph {
        build(contextID: input.contextID, resources: input.resources, inputs: input.inputs, freshness: input.freshness)
    }

    public static func build(contextID: String, resources: [TopologyResourceSnapshot], inputs: [TopologyInputStatus] = [], freshness: TopologyFreshness = TopologyFreshness()) -> TopologyGraph {
        let context = TopologySanitizer.clean(contextID)
        var byKey: [String: TopologyResourceSnapshot] = [:]
        for resource in resources where !resource.identity.name.isEmpty {
            let key = lookupKey(kind: resource.identity.kind, namespace: resource.identity.namespace, name: resource.identity.name, uid: resource.identity.uid)
            byKey[key] = resource
        }
        let unique = byKey.values.sorted { stableIdentity($0) < stableIdentity($1) }
        var nodes: [String: TopologyNode] = [:]
        nodes.reserveCapacity(unique.count + 1)
        var evidenceCache: [String: TopologyEvidence] = [:]
        evidenceCache.reserveCapacity(unique.count * 2)
        func apiEvidence(_ resource: TopologyResourceSnapshot, level: TopologyEvidenceLevel = .observed, sourceField: String? = nil, joinRule: String? = nil, assumption: String? = nil) -> TopologyEvidence {
            let key = [resource.identity.stableNodeID(contextID: context), level.rawValue, sourceField ?? "", joinRule ?? "", assumption ?? ""].joined(separator: "|")
            if let cached = evidenceCache[key] { return cached }
            let evidence = TopologyEvidence(level: level, source: .object(contextID: context, identity: resource.identity, sourceField: sourceField, joinRule: joinRule, assumption: assumption), freshness: freshness)
            evidenceCache[key] = evidence
            return evidence
        }
        let controlPlaneID = TopologyVirtualNodeID.controlPlaneBoundary(contextID: context)
        nodes[controlPlaneID] = TopologyNode(id: controlPlaneID, contextID: context, apiVersion: "virtual/v1", kind: "ControlPlaneBoundary", name: "Control plane boundary", isVirtual: true, virtualKind: "control-plane-boundary", evidence: TopologyEvidence(level: .unavailable, source: TopologyEvidenceSource(id: "client-boundary", kind: "synthetic", note: "Provider-managed control-plane internals may not be exposed"), freshness: freshness), facts: [TopologyFact(key: "visibility", title: "Visibility", value: "Not exposed by this cluster API")])
        for resource in unique {
            let identity = resource.identity
            let id = identity.stableNodeID(contextID: context)
            var facts = resource.facts
            if let policy = resource.networkPolicy {
                facts.append(TopologyFact(key: "policy-types", title: "Policy types", value: policy.policyTypes.joined(separator: ", ")))
                facts.append(TopologyFact(key: "ingress-rules", title: "Ingress rules", value: String(policy.ingressRuleCount)))
                facts.append(TopologyFact(key: "egress-rules", title: "Egress rules", value: String(policy.egressRuleCount)))
                let deniesIngress = policy.policyTypes.contains("INGRESS") && policy.ingressRuleCount == 0
                let deniesEgress = policy.policyTypes.contains("EGRESS") && policy.egressRuleCount == 0
                if deniesIngress || deniesEgress {
                    let scopes = [deniesIngress ? "ingress" : nil, deniesEgress ? "egress" : nil].compactMap { $0 }.joined(separator: "+")
                    facts.append(TopologyFact(key: "default-deny", title: "Default deny", value: scopes))
                }
            }
            nodes[id] = TopologyNode(id: id, contextID: context, apiVersion: identity.apiVersion, kind: identity.kind, name: identity.name, namespace: identity.namespace, uid: identity.uid.isEmpty ? nil : identity.uid, resourceVersion: identity.resourceVersion.isEmpty ? nil : identity.resourceVersion, evidence: apiEvidence(resource), facts: facts)
        }

        // Resolve joins through deterministic indexes. This keeps selector,
        // endpoint and route expansion linear in the snapshot size rather than
        // repeatedly scanning every node for every reference.
        let nodesByUID = Dictionary(unique.compactMap { resource -> (String, TopologyNode)? in
            guard !resource.identity.uid.isEmpty, let node = nodes[resource.identity.stableNodeID(contextID: context)] else { return nil }
            return (resource.identity.uid, node)
        }, uniquingKeysWith: { lhs, _ in lhs })
        let nodesByName = Dictionary(grouping: nodes.values) { node in
            [node.kind.lowercased(), node.namespace ?? "", node.name].joined(separator: "|")
        }
        let podsByNamespace = Dictionary(grouping: unique.filter { resource in
            let kind = resource.identity.kind.lowercased()
            return kind == "pod" || kind == "pods"
        }) { $0.identity.namespace ?? "" }
        var podsByNamespaceAndLabel: [String: [String: [TopologyResourceSnapshot]]] = [:]
        podsByNamespaceAndLabel.reserveCapacity(podsByNamespace.count)
        for (namespace, pods) in podsByNamespace {
            var labelIndex: [String: [TopologyResourceSnapshot]] = [:]
            for pod in pods {
                for (key, value) in pod.identity.labels {
                    labelIndex["\(key)=\(value)", default: []].append(pod)
                }
            }
            for key in labelIndex.keys { labelIndex[key]?.sort { stableIdentity($0) < stableIdentity($1) } }
            podsByNamespaceAndLabel[namespace] = labelIndex
        }

        func candidatePods(namespace: String?, selector: TopologyLabelSelector) -> [TopologyResourceSnapshot] {
            let namespaceKey = namespace ?? ""
            let all = podsByNamespace[namespaceKey] ?? []
            let index = podsByNamespaceAndLabel[namespaceKey] ?? [:]
            var equalityBuckets: [[TopologyResourceSnapshot]] = []
            for key in selector.matchLabels.keys.sorted() {
                if let value = selector.matchLabels[key], let bucket = index["\(key)=\(value)"] { equalityBuckets.append(bucket) }
            }
            let candidates: [TopologyResourceSnapshot]
            if let smallestEquality = equalityBuckets.min(by: { $0.count < $1.count }) {
                candidates = smallestEquality
            } else {
                var inUnion: [String: TopologyResourceSnapshot] = [:]
                for expression in selector.matchExpressions where expression.op == .in {
                    for value in expression.values {
                        for pod in index["\(expression.key)=\(value)"] ?? [] { inUnion[pod.identity.stableNodeID(contextID: "selector")] = pod }
                    }
                    if !inUnion.isEmpty { break }
                }
                candidates = inUnion.isEmpty ? all : inUnion.values.sorted { stableIdentity($0) < stableIdentity($1) }
            }
            return candidates.filter { selector.matchesTokenized($0.identity.labels) }
        }

        func resolve(_ reference: TopologyObjectReference, fallbackNamespace: String?) -> String? {
            if let uid = reference.uid, !uid.isEmpty {
                if let node = nodesByUID[uid], (reference.namespace == nil || node.namespace == reference.namespace), (reference.kind.isEmpty || node.kind.caseInsensitiveCompare(reference.kind) == .orderedSame) { return node.id }
                return nil
            }
            let candidates: [TopologyNode]
            if reference.kind.isEmpty {
                candidates = nodes.values.filter { $0.name == reference.name }
            } else {
                let exactKey = [reference.kind.lowercased(), reference.namespace ?? fallbackNamespace ?? "", reference.name].joined(separator: "|")
                let clusterKey = [reference.kind.lowercased(), "", reference.name].joined(separator: "|")
                candidates = (nodesByName[exactKey] ?? []) + (reference.namespace == nil ? (nodesByName[clusterKey] ?? []) : [])
            }
            let expectedNamespace = reference.namespace ?? fallbackNamespace
            if let exact = candidates.first(where: { $0.namespace == expectedNamespace }) {
                return exact.id
            }
            // References such as PVC.spec.volumeName and
            // spec.storageClassName originate on a namespaced object but
            // target a cluster-scoped object. If the reference itself omits a
            // namespace, allow the unique cluster-scoped candidate rather
            // than incorrectly inheriting the source namespace.
            if reference.namespace == nil {
                return candidates.first(where: { $0.namespace == nil })?.id
            }
            return nil
        }

        func resolveOwner(_ owner: TopologyOwnerReference, childNamespace: String?) -> String? {
            resolve(TopologyObjectReference(apiVersion: owner.apiVersion, kind: owner.kind, name: owner.name, namespace: childNamespace, uid: owner.uid), fallbackNamespace: childNamespace)
        }

        var edges: [String: TopologyEdge] = [:]
        var unresolved: [String: TopologyUnresolvedReference] = [:]
        var portPaths: [String: TopologyPortPath] = [:]
        edges.reserveCapacity(unique.count * 4)
        unresolved.reserveCapacity(unique.count)
        portPaths.reserveCapacity(unique.count)
        func addEdge(from: String, to: String, relation: TopologyRelationship, level: TopologyEvidenceLevel, sourceResource: TopologyResourceSnapshot, sourceField: String, joinRule: String, assumption: String? = nil, attributes: [String: String] = [:]) {
            let edge = TopologyEdge(from: from, to: to, relationship: relation, evidence: apiEvidence(sourceResource, level: level, sourceField: sourceField, joinRule: joinRule, assumption: assumption), attributes: attributes)
            edges[edge.id] = edge
        }
        func addUnresolved(relation: TopologyRelationship, source: String?, target: TopologyObjectReference, reason: String, level: TopologyEvidenceLevel, sourceResource: TopologyResourceSnapshot? = nil, sourceStatus: TopologyInputStatus? = nil, sourceField: String, joinRule: String, assumption: String? = nil) {
            let evidenceSource: TopologyEvidenceSource
            if let sourceResource { evidenceSource = .object(contextID: context, identity: sourceResource.identity, sourceField: sourceField, joinRule: joinRule, assumption: assumption) }
            else if let sourceStatus { evidenceSource = .inputStatus(sourceStatus) }
            else { evidenceSource = TopologyEvidenceSource(id: "unresolved|\(context)|\(sourceField)", contextID: context, kind: "unresolved", sourceField: sourceField, joinRule: joinRule, assumption: assumption) }
            let item = TopologyUnresolvedReference(relation: relation, sourceNodeID: source, target: target, reason: reason, evidence: TopologyEvidence(level: level, source: evidenceSource, freshness: freshness))
            unresolved[item.id] = item
        }
        func resourceNode(_ resource: TopologyResourceSnapshot) -> String { resource.identity.stableNodeID(contextID: context) }

        // Namespace containment is an API-observed metadata relationship.
        let namespaceNodes = nodes.values.filter { $0.kind.caseInsensitiveCompare("Namespace") == .orderedSame || $0.kind.caseInsensitiveCompare("namespaces") == .orderedSame }
        for resource in unique {
            guard let namespace = resource.identity.namespace, let namespaceNode = namespaceNodes.first(where: { $0.name == namespace }) else { continue }
            addEdge(from: resourceNode(resource), to: namespaceNode.id, relation: .containedIn, level: .observed, sourceResource: resource, sourceField: "metadata.namespace", joinRule: "namespace name equals Namespace.metadata.name")
        }

        for resource in unique {
            let source = resourceNode(resource)
            for owner in resource.ownerReferences {
                if let target = resolveOwner(owner, childNamespace: resource.identity.namespace) {
                    addEdge(from: source, to: target, relation: .ownedBy, level: .observed, sourceResource: resource, sourceField: "metadata.ownerReferences", joinRule: "ownerReference.uid or name identifies target")
                } else {
                    addUnresolved(relation: .ownedBy, source: source, target: TopologyObjectReference(apiVersion: owner.apiVersion, kind: owner.kind, name: owner.name, namespace: resource.identity.namespace, uid: owner.uid), reason: "owner reference is not present in this snapshot", level: .observed, sourceResource: resource, sourceField: "metadata.ownerReferences", joinRule: "ownerReference.uid or name identifies target")
                }
            }

            if resource.identity.kind.caseInsensitiveCompare("Pod") == .orderedSame || resource.identity.kind.caseInsensitiveCompare("Pods") == .orderedSame, let nodeName = resource.podNodeName, !nodeName.isEmpty {
                let nodeRef = TopologyObjectReference(apiVersion: "v1", kind: "Node", name: nodeName)
                if let target = resolve(nodeRef, fallbackNamespace: nil) { addEdge(from: source, to: target, relation: .scheduledOn, level: .observed, sourceResource: resource, sourceField: "spec.nodeName", joinRule: "Pod.spec.nodeName equals Node.metadata.name") }
                else { addUnresolved(relation: .scheduledOn, source: source, target: nodeRef, reason: "pod placement target is not present in this snapshot", level: .observed, sourceResource: resource, sourceField: "spec.nodeName", joinRule: "Pod.spec.nodeName equals Node.metadata.name") }
            }

            let routes: [TopologyIngressRoute] = resource.ingressRoutes.isEmpty
                ? resource.ingressBackends.enumerated().map { index, backend in TopologyIngressRoute(ruleIndex: nil, pathIndex: index, backendName: backend.name, backendNamespace: backend.namespace ?? resource.identity.namespace, backendPort: backend.port, backendPortName: backend.portName) }
                : resource.ingressRoutes
            for route in routes {
                let ref = TopologyObjectReference(apiVersion: "v1", kind: route.backendKind, name: route.backendName, namespace: route.backendNamespace ?? resource.identity.namespace)
                var backendAttributes: [String: String] = [:]
                if let port = route.backendPort { backendAttributes["port"] = String(port) }
                if let portName = route.backendPortName { backendAttributes["portName"] = portName }
                if !resource.ingressRoutes.isEmpty {
                    backendAttributes["routeID"] = route.id
                    if let host = route.host { backendAttributes["host"] = host }
                    if let path = route.path { backendAttributes["path"] = path }
                }
                if let target = resolve(ref, fallbackNamespace: resource.identity.namespace) {
                    addEdge(from: source, to: target, relation: .routesTo, level: .declared, sourceResource: resource, sourceField: "spec.rules[].http.paths[].backend.service.port", joinRule: "backend service name/namespace identifies Service; numeric or named port is descriptive", assumption: "backend declaration only; request routing is not proven", attributes: backendAttributes)
                } else if route.backendKind.caseInsensitiveCompare("ExternalName") != .orderedSame {
                    addUnresolved(relation: .routesTo, source: source, target: ref, reason: "Ingress backend Service is not present in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.rules[].http.paths[].backend.service.port", joinRule: "backend service name/namespace identifies Service; numeric or named port is descriptive", assumption: "backend declaration only; request routing is not proven")
                }
            }

            if let route = resource.httpRoute {
                for parent in route.parents {
                    let parentRef = TopologyObjectReference(kind: parent.kind, name: parent.name, namespace: parent.namespace ?? resource.identity.namespace)
                    if let target = resolve(parentRef, fallbackNamespace: resource.identity.namespace) {
                        addEdge(from: source, to: target, relation: .routesTo, level: .declared, sourceResource: resource, sourceField: "spec.parentRefs", joinRule: "HTTPRoute parentRef identifies Gateway", assumption: "route attachment status is reported separately", attributes: ["parentID": parent.id])
                    } else {
                        addUnresolved(relation: .routesTo, source: source, target: parentRef, reason: "HTTPRoute parent Gateway is not present in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.parentRefs", joinRule: "HTTPRoute parentRef identifies Gateway")
                    }
                }
                for backend in route.backends {
                    let backendRef = TopologyObjectReference(kind: backend.kind, name: backend.name, namespace: backend.namespace ?? resource.identity.namespace)
                    if let target = resolve(backendRef, fallbackNamespace: resource.identity.namespace) {
                        addEdge(from: source, to: target, relation: .routesTo, level: .declared, sourceResource: resource, sourceField: "spec.rules[].backendRefs", joinRule: "HTTPRoute backendRef identifies Service", assumption: "route matching and data-plane forwarding are not proven", attributes: ["backendID": backend.id, "port": backend.port.map(String.init) ?? ""])
                    } else {
                        addUnresolved(relation: .routesTo, source: source, target: backendRef, reason: "HTTPRoute backend is not present in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.rules[].backendRefs", joinRule: "HTTPRoute backendRef identifies Service")
                    }
                }
            }

            if let slice = resource.endpointSlice, let serviceName = slice.serviceName {
                let serviceRef = TopologyObjectReference(apiVersion: "v1", kind: "Service", name: serviceName, namespace: resource.identity.namespace)
                if let target = resolve(serviceRef, fallbackNamespace: resource.identity.namespace) { addEdge(from: source, to: target, relation: .publishesEndpoints, level: .observed, sourceResource: resource, sourceField: "metadata.labels[kubernetes.io/service-name]", joinRule: "EndpointSlice service label equals Service.metadata.name") }
                else { addUnresolved(relation: .publishesEndpoints, source: source, target: serviceRef, reason: "EndpointSlice service label target is not present in this snapshot", level: .observed, sourceResource: resource, sourceField: "metadata.labels[kubernetes.io/service-name]", joinRule: "EndpointSlice service label equals Service.metadata.name") }
                for endpoint in slice.endpoints {
                    if let reference = endpoint.reference {
                        if let target = resolve(reference, fallbackNamespace: resource.identity.namespace) { addEdge(from: source, to: target, relation: .endpointTarget, level: .observed, sourceResource: resource, sourceField: "endpoints[].targetRef", joinRule: "EndpointSlice targetRef identifies Pod", attributes: endpoint.ready.map { ["ready": String($0)] } ?? [:]) }
                        else { addUnresolved(relation: .endpointTarget, source: source, target: reference, reason: "EndpointSlice targetRef is not present in this snapshot", level: .observed, sourceResource: resource, sourceField: "endpoints[].targetRef", joinRule: "EndpointSlice targetRef identifies Pod") }
                    }
                }
            }

            for ref in resource.volumeReferences {
                let relation: TopologyRelationship = ref.kind.caseInsensitiveCompare("StorageClass") == .orderedSame ? .usesStorageClass : .backedBy
                let field = relation == .usesStorageClass ? "spec.storageClassName" : "spec.volumes[].persistentVolumeClaim"
                if let target = resolve(ref, fallbackNamespace: resource.identity.namespace) { addEdge(from: source, to: target, relation: relation, level: .declared, sourceResource: resource, sourceField: field, joinRule: "storage reference name/UID identifies target") }
                else { addUnresolved(relation: relation, source: source, target: ref, reason: "storage reference is not present in this snapshot", level: .declared, sourceResource: resource, sourceField: field, joinRule: "storage reference name/UID identifies target") }
            }
            for ref in resource.configReferences {
                let targetRef = TopologyObjectReference(apiVersion: "v1", kind: ref.kind, name: ref.name, namespace: ref.namespace ?? resource.identity.namespace)
                if let target = resolve(targetRef, fallbackNamespace: resource.identity.namespace) { addEdge(from: source, to: target, relation: .references, level: .declared, sourceResource: resource, sourceField: "spec.references[].name", joinRule: "reference kind/name/namespace identifies ConfigMap or Secret") }
                else { addUnresolved(relation: .references, source: source, target: targetRef, reason: "config reference is not present in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.references[].name", joinRule: "reference kind/name/namespace identifies ConfigMap or Secret") }
            }
            if let policy = resource.networkPolicy {
                let policySelector = policy.podSelector
                let candidates = candidatePods(namespace: resource.identity.namespace, selector: policySelector)
                for candidate in candidates {
                    addEdge(from: source, to: resourceNode(candidate), relation: .selects, level: .inferred, sourceResource: resource, sourceField: "spec.podSelector", joinRule: "podSelector matches Pod.metadata.labels", assumption: "policy enforcement and reachability are not proven", attributes: ["policyTypes": policy.policyTypes.joined(separator: ","), "ingressRules": String(policy.ingressRuleCount), "egressRules": String(policy.egressRuleCount)])
                }
                if candidates.isEmpty {
                    addUnresolved(relation: .selects, source: source, target: TopologyObjectReference(kind: "Pod", name: "<selector>", namespace: resource.identity.namespace), reason: "NetworkPolicy podSelector matched zero Pod resources in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.podSelector", joinRule: "podSelector matches Pod.metadata.labels", assumption: "policy enforcement and reachability are not proven")
                }
            }
        }

        // Selector matching is intentionally a separate inferred edge: a
        // selector declaration is not a claim that traffic reaches the pod.
        for resource in unique where !resource.selector.isEmpty || !resource.selectorExpressions.isEmpty {
            let source = resourceNode(resource)
            let kind = resource.identity.kind.lowercased()
            let selector = TopologyLabelSelector(tokenizedMatchLabels: resource.selector, tokenizedExpressions: resource.selectorExpressions)
            let candidates = candidatePods(namespace: resource.identity.namespace, selector: selector)
            if kind == "service" || kind == "services" {
                for candidate in candidates { addEdge(from: source, to: resourceNode(candidate), relation: .selects, level: .inferred, sourceResource: resource, sourceField: "spec.selector", joinRule: "selector matches Pod.metadata.labels", assumption: "label selection does not prove traffic or endpoint readiness") }
            } else if kind.contains("deployment") || kind.contains("statefulset") || kind.contains("daemonset") || kind.contains("replicaset") {
                for candidate in candidates { addEdge(from: source, to: resourceNode(candidate), relation: .selects, level: .inferred, sourceResource: resource, sourceField: "spec.selector", joinRule: "selector matches Pod.metadata.labels", assumption: "label selection does not prove controller reconciliation") }
            }
            if (kind == "service" || kind == "services" || kind.contains("deployment") || kind.contains("statefulset") || kind.contains("daemonset") || kind.contains("replicaset")) && candidates.isEmpty {
                addUnresolved(relation: .selects, source: source, target: TopologyObjectReference(kind: "Pod", name: "<selector>", namespace: resource.identity.namespace), reason: "selector declaration matched zero Pod resources in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.selector", joinRule: "selector matches Pod.metadata.labels", assumption: "no target node is invented")
            }
        }

        // Build structured exposure paths for the tiered UI. These are a
        // declared/intended path until EndpointSlice observations can resolve
        // it; the output deliberately never represents packet reachability.
        let resourcesByNodeID = Dictionary(unique.map { ($0.identity.stableNodeID(contextID: context), $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let slicesByService = Dictionary(grouping: unique.compactMap { resource -> (String, TopologyResourceSnapshot)? in
            guard resource.identity.kind.caseInsensitiveCompare("EndpointSlice") == .orderedSame, let name = resource.endpointSlice?.serviceName else { return nil }
            return ([resource.identity.namespace ?? "", name].joined(separator: "|"), resource)
        }) { $0.0 }.mapValues { $0.map(\.1).sorted { $0.identity.name < $1.identity.name } }
        let services = Dictionary(unique.compactMap { resource -> (String, TopologyResourceSnapshot)? in
            guard resource.identity.kind.caseInsensitiveCompare("Service") == .orderedSame else { return nil }
            return ([resource.identity.namespace ?? "", resource.identity.name].joined(separator: "|"), resource)
        }, uniquingKeysWith: { lhs, _ in lhs })
        func pathEvidence(_ resource: TopologyResourceSnapshot, level: TopologyEvidenceLevel, field: String, assumption: String? = nil) -> TopologyEvidence {
            apiEvidence(resource, level: level, sourceField: field, joinRule: "typed topology port join", assumption: assumption)
        }
        func makePath(sourceResource: TopologyResourceSnapshot, backendKind: String, backendName: String, backendNamespace: String?, backendPort: Int32?, backendPortName: String?, routeID: String) -> TopologyPortPath {
            let source = TopologyObjectReference(apiVersion: sourceResource.identity.apiVersion, kind: sourceResource.identity.kind, name: sourceResource.identity.name, namespace: sourceResource.identity.namespace, uid: sourceResource.identity.uid.isEmpty ? nil : sourceResource.identity.uid)
            let declaredEvidence = pathEvidence(sourceResource, level: .declared, field: "spec.route.backend", assumption: "declaration does not prove traffic")
            var hops: [TopologyPortHop] = []
            var fanoutTruncated = false
            var omittedHopCount = 0
            var emittedEndpointCount = 0
            var emittedEndpointPortCount = 0
            var endpointPortCount = 0
            @discardableResult
            func appendHop(_ hop: TopologyPortHop) -> Bool {
                guard hops.count < Self.maxPortPathHops else {
                    fanoutTruncated = true
                    omittedHopCount += 1
                    return false
                }
                hops.append(hop)
                if hop.role == "endpoint" { emittedEndpointCount += 1 }
                if hop.role == "endpoint-port" { emittedEndpointPortCount += 1 }
                return true
            }
            appendHop(TopologyPortHop(role: "route", reference: source, portName: backendPortName, portNumber: backendPort, evidence: declaredEvidence))
            guard backendKind.caseInsensitiveCompare("Service") == .orderedSame else {
                return TopologyPortPath(source: source, status: .external, hops: hops, provenance: [declaredEvidence], note: "Backend kind is \(TopologySanitizer.clean(backendKind)); Service port resolution is not applicable", id: routeID)
            }
            let serviceKey = [backendNamespace ?? sourceResource.identity.namespace ?? "", backendName].joined(separator: "|")
            guard let service = services[serviceKey] else {
                return TopologyPortPath(source: source, status: .unresolved, hops: hops, provenance: [declaredEvidence], note: "Service is not present in this snapshot", id: routeID)
            }
            if service.serviceMode == .externalName {
                return TopologyPortPath(source: source, status: .external, hops: hops, provenance: [declaredEvidence], note: "ExternalName Service resolves outside the EndpointSlice graph", id: routeID)
            }
            let serviceRef = TopologyObjectReference(apiVersion: service.identity.apiVersion, kind: service.identity.kind, name: service.identity.name, namespace: service.identity.namespace, uid: service.identity.uid.isEmpty ? nil : service.identity.uid)
            let serviceEvidence = pathEvidence(service, level: .observed, field: "spec.ports[]")
            appendHop(TopologyPortHop(role: "service", reference: serviceRef, evidence: serviceEvidence))
            let matchingPorts = service.servicePorts.filter { port in
                if let backendPort { return port.port == backendPort }
                if let backendPortName { return port.name == backendPortName }
                return true
            }
            guard matchingPorts.count == 1, let servicePort = matchingPorts.first else {
                let note = matchingPorts.isEmpty ? "Requested Service port is not declared" : "Service port reference is ambiguous"
                return TopologyPortPath(source: source, status: .unresolved, hops: hops, provenance: [declaredEvidence, serviceEvidence], note: note, id: routeID)
            }
            appendHop(TopologyPortHop(role: "service-port", reference: serviceRef, portName: servicePort.name, portNumber: servicePort.port, protocolName: servicePort.protocolName, evidence: serviceEvidence, targetPort: servicePort.targetPort, nodePort: servicePort.nodePort, appProtocol: servicePort.appProtocol))
            let targetNumber = servicePort.targetPort.number ?? (servicePort.targetPort.usesServicePortByDefault ? servicePort.port : nil)
            let targetName = servicePort.targetPort.name
            let slices = slicesByService[serviceKey] ?? []
            var endpointCount = 0
            var readyEndpointCount = 0
            var matchedEndpointSlice = false
            for slice in slices {
                guard let endpointSlice = slice.endpointSlice else { continue }
                let matchingEndpointPorts = endpointSlice.ports.filter { endpointPort in
                    guard endpointPort.protocolName == servicePort.protocolName else { return false }
                    // EndpointSlice port names correlate to ServicePort.name.
                    // The EndpointSlice numeric port is the already-resolved
                    // backend number; it is not the named targetPort token.
                    if let servicePortName = servicePort.name { return endpointPort.name == servicePortName }
                    return endpointPort.name == nil
                }
                if matchingEndpointPorts.isEmpty { continue }
                matchedEndpointSlice = true
                for endpointPort in matchingEndpointPorts {
                    endpointPortCount += 1
                    appendHop(TopologyPortHop(role: "endpoint-port", reference: TopologyObjectReference(apiVersion: slice.identity.apiVersion, kind: slice.identity.kind, name: slice.identity.name, namespace: slice.identity.namespace, uid: slice.identity.uid.isEmpty ? nil : slice.identity.uid), portName: endpointPort.name, portNumber: endpointPort.port, protocolName: endpointPort.protocolName, evidence: pathEvidence(slice, level: .observed, field: "ports[]"), appProtocol: endpointPort.appProtocol))
                    for endpoint in endpointSlice.endpoints {
                        endpointCount += 1
                        // Omitted ready is effective-ready per EndpointSlice
                        // semantics. Explicit false, or a terminating
                        // endpoint that is no longer serving, is not ready.
                        let effectiveReady = endpoint.ready != false && !(endpoint.terminating == true && endpoint.serving == false)
                        if effectiveReady { readyEndpointCount += 1 }
                        let endpointEvidence = pathEvidence(slice, level: .observed, field: "endpoints[]")
                        let endpointHop = TopologyPortHop(role: "endpoint", reference: endpoint.reference, portNumber: endpointPort.port, protocolName: endpointPort.protocolName, addresses: endpoint.addresses, ready: endpoint.ready, serving: endpoint.serving, terminating: endpoint.terminating, nodeName: endpoint.nodeName, zone: endpoint.zone, evidence: endpointEvidence)
                        if appendHop(endpointHop), let endpointUID = endpoint.reference?.uid, let endpointNode = nodesByUID[endpointUID], let target = resourcesByNodeID[endpointNode.id] {
                            let containerPorts = target.containerPorts + target.initContainerPorts + target.ephemeralContainerPorts
                            let matches = containerPorts.filter { port in
                                guard port.protocolName == servicePort.protocolName && port.protocolName == endpointPort.protocolName else { return false }
                                if let targetNumber { return port.port == targetNumber }
                                if let targetName { return port.name == targetName }
                                return port.port == endpointPort.port
                            }
                            if let containerPort = matches.first { appendHop(TopologyPortHop(role: "container-port", reference: endpoint.reference, portName: containerPort.name, portNumber: containerPort.port, protocolName: containerPort.protocolName, containerName: containerPort.containerName, evidence: pathEvidence(target, level: .declared, field: "spec.containers[].ports[]", assumption: "declared port does not prove process listening"))) }
                        }
                    }
                }
            }
            let missingTarget = !matchedEndpointSlice
            let status: TopologyPortPathStatus
            if fanoutTruncated { status = .partial }
            else if endpointCount == 0 { status = slices.isEmpty ? .noEndpoint : (missingTarget ? .unresolved : .noEndpoint) }
            else if readyEndpointCount == 0 { status = .noReadyEndpoint }
            else if !missingTarget { status = .complete }
            else { status = .partial }
            let omittedEndpointCount = max(0, endpointCount - emittedEndpointCount)
            let omittedEndpointPortCount = max(0, endpointPortCount - emittedEndpointPortCount)
            let truncationEvidence = pathEvidence(service, level: .observed, field: "EndpointSlice.endpoints[]", assumption: "path fan-out is bounded; omitted observations are not represented")
            let provenance = hops.map(\.evidence) + (fanoutTruncated ? [truncationEvidence] : [])
            let hasContainerDeclaration = hops.contains { $0.role == "container-port" }
            var notes: [String] = []
            if fanoutTruncated {
                notes.append("Endpoint fanout truncated at \(Self.maxPortPathHops) hops; omitted \(omittedHopCount) hops; represented \(emittedEndpointCount) of \(endpointCount) endpoint observations and \(emittedEndpointPortCount) of \(endpointPortCount) EndpointSlice port observations")
            }
            if missingTarget { notes.append("No EndpointSlice port matched the Service port name") }
            if !hasContainerDeclaration && readyEndpointCount > 0 { notes.append("Pod container port declaration unavailable") }
            return TopologyPortPath(source: source, status: status, hops: hops, provenance: provenance, note: notes.isEmpty ? nil : notes.joined(separator: "; "), readyEndpointCount: readyEndpointCount, totalEndpointCount: endpointCount, id: routeID, isTruncated: fanoutTruncated, omittedHopCount: omittedHopCount, omittedEndpointCount: omittedEndpointCount, omittedEndpointPortCount: omittedEndpointPortCount)
        }
        for resource in unique {
            let routes = resource.ingressRoutes.isEmpty
                ? resource.ingressBackends.enumerated().map { index, backend in TopologyIngressRoute(pathIndex: index, backendName: backend.name, backendNamespace: backend.namespace ?? resource.identity.namespace, backendPort: backend.port, backendPortName: backend.portName) }
                : resource.ingressRoutes
            for route in routes {
                let routeID = TopologyHash.id("\(resource.identity.apiVersion)|\(resource.identity.kind)|\(resource.identity.namespace ?? "")|\(resource.identity.name)|\(resource.identity.uid)|\(route.id)")
                let path = makePath(sourceResource: resource, backendKind: route.backendKind, backendName: route.backendName, backendNamespace: route.backendNamespace, backendPort: route.backendPort, backendPortName: route.backendPortName, routeID: routeID)
                portPaths[path.id] = path
            }
            if let route = resource.httpRoute {
                let hasAcceptedParent = route.parents.contains { $0.accepted == true && $0.resolvedRefs != false }
                let hasExplicitParentRejection = !route.parents.isEmpty && !hasAcceptedParent && route.parents.allSatisfy { $0.accepted == false || $0.resolvedRefs == false }
                let hasUnknownParent = !route.parents.isEmpty && !hasAcceptedParent && route.parents.contains { $0.accepted == nil || $0.resolvedRefs == nil }
                for backend in route.backends {
                    let routeID = TopologyHash.id("\(resource.identity.apiVersion)|\(resource.identity.kind)|\(resource.identity.namespace ?? "")|\(resource.identity.name)|\(resource.identity.uid)|\(backend.id)")
                    let resolved = makePath(sourceResource: resource, backendKind: backend.kind, backendName: backend.name, backendNamespace: backend.namespace ?? resource.identity.namespace, backendPort: backend.port, backendPortName: nil, routeID: routeID)
                    func wrap(_ status: TopologyPortPathStatus, note: String) -> TopologyPortPath {
                        let notes = [note, resolved.note].compactMap { $0 }.joined(separator: "; ")
                        return TopologyPortPath(source: resolved.source, status: status, hops: resolved.hops, provenance: resolved.provenance, note: notes, readyEndpointCount: resolved.readyEndpointCount, totalEndpointCount: resolved.totalEndpointCount, id: resolved.id, isTruncated: resolved.isTruncated, omittedHopCount: resolved.omittedHopCount, omittedEndpointCount: resolved.omittedEndpointCount, omittedEndpointPortCount: resolved.omittedEndpointPortCount)
                    }
                    let path: TopologyPortPath
                    if hasExplicitParentRejection {
                        let rejectedNames = route.parents.filter { $0.accepted == false || $0.resolvedRefs == false }.map(\.name).joined(separator: ", ")
                        path = wrap(.unresolved, note: "HTTPRoute parent references are rejected or unresolved (\(rejectedNames))")
                    } else if backend.resolvedRefs == false {
                        path = wrap(.unresolved, note: "HTTPRoute backend reference is unresolved")
                    } else if hasUnknownParent {
                        path = wrap(.partial, note: "HTTPRoute parent acceptance or reference resolution is not yet observed")
                    } else {
                        path = resolved
                    }
                    portPaths[path.id] = path
                }
            }
        }

        let unavailable = inputs.filter { $0.availability != .available }
        for input in unavailable {
            let target = TopologyObjectReference(kind: input.resourceKind, name: "<input>")
            addUnresolved(relation: .inputUnavailable, source: nil, target: target, reason: input.message ?? "input \(input.availability.rawValue)", level: .unavailable, sourceStatus: input, sourceField: "input.\(input.resourceKind)", joinRule: "input availability status")
        }
        // An available input set can still be semantically incomplete: a
        // reference may point outside the captured snapshot, a selector may
        // have no observed target, or a declared service path may lack an
        // EndpointSlice/ready endpoint. Preserve explicit external semantics
        // as complete because those paths intentionally terminate outside the
        // Kubernetes object graph.
        let hasUnresolvedPath = portPaths.values.contains { path in
            switch path.status {
            case .partial, .unresolved, .noEndpoint, .noReadyEndpoint: return true
            case .complete, .external: return false
            }
        }
        let hasSemanticGaps = !unresolved.isEmpty || hasUnresolvedPath
        let completeness: TopologySnapshotCompleteness
        if !unavailable.isEmpty {
            completeness = unique.isEmpty ? .unavailable : .partial
        } else {
            completeness = hasSemanticGaps ? .partial : .complete
        }
        let details = Dictionary(unique.map { ($0.identity.stableNodeID(contextID: context), TopologyNodeDetails(resource: $0)) }, uniquingKeysWith: { lhs, _ in lhs })
        return TopologyGraph(contextID: context, freshness: freshness, completeness: completeness, nodes: Array(nodes.values), edges: Array(edges.values), unresolvedReferences: Array(unresolved.values), inputs: inputs, portPaths: Array(portPaths.values), details: details)
    }

    private static func lookupKey(kind: String, namespace: String?, name: String, uid: String) -> String { [kind.lowercased(), namespace ?? "", uid.isEmpty ? name : uid].joined(separator: "|") }
    private static func stableIdentity(_ resource: TopologyResourceSnapshot) -> String { [resource.identity.kind, resource.identity.namespace ?? "", resource.identity.name, resource.identity.uid].joined(separator: "|") }
}

// MARK: - Deterministic/safe implementation helpers

private enum TopologySort {
    static func owner(_ lhs: TopologyOwnerReference, _ rhs: TopologyOwnerReference) -> Bool { ownerKey(lhs) < ownerKey(rhs) }
    static func ownerKey(_ item: TopologyOwnerReference) -> String { [item.kind, item.name, item.uid ?? ""].joined(separator: "|") }
    static func service(_ lhs: TopologyServiceReference, _ rhs: TopologyServiceReference) -> Bool { serviceKey(lhs) < serviceKey(rhs) }
    static func serviceKey(_ item: TopologyServiceReference) -> String { [item.namespace ?? "", item.name, item.port.map { String($0) } ?? "", item.portName ?? ""].joined(separator: "|") }
    static func reference(_ lhs: TopologyObjectReference, _ rhs: TopologyObjectReference) -> Bool { referenceKey(lhs) < referenceKey(rhs) }
    static func referenceKey(_ item: TopologyObjectReference) -> String { [item.kind, item.namespace ?? "", item.name, item.uid ?? ""].joined(separator: "|") }
    static func namedReference(_ lhs: TopologyNamedReference, _ rhs: TopologyNamedReference) -> Bool { namedReferenceKey(lhs) < namedReferenceKey(rhs) }
    static func namedReferenceKey(_ item: TopologyNamedReference) -> String { [item.kind, item.namespace ?? "", item.name].joined(separator: "|") }
    static func selectorMaterial(_ selector: TopologyLabelSelector) -> String {
        let labels = selector.matchLabels.keys.sorted().map { key in
            key + "=" + (selector.matchLabels[key] ?? "")
        }.joined(separator: ",")
        let expressions = selector.matchExpressions.map { "\($0.key):\($0.op.rawValue):\($0.values.joined(separator: ","))" }.joined(separator: ",")
        return [labels, expressions].joined(separator: "|")
    }
}

public enum TopologyVirtualNodeID {
    public static func controlPlaneBoundary(contextID: String) -> String {
        "virtual|\(TopologySanitizer.idPart(contextID))|control-plane-boundary"
    }
}

private enum TopologyHash {
    static func id(_ material: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in material.utf8 { hash ^= UInt64(byte); hash &*= 1099511628211 }
        return String(format: "%016llx", hash)
    }
}

private enum TopologySanitizer {
    private static let redactionRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "(?i)bearer\\s+[^\\s,;]+"),
        try! NSRegularExpression(pattern: "(?i)(password|token|secret|credential|authorization|cookie|annotations?|certificate[-_ ]?data)\\s*[:=]\\s*[^\\s,;]+")
    ]

    static func clean(_ input: String) -> String {
        var output = input.unicodeScalars.map { scalar -> String in scalar.value < 0x20 && scalar.value != 0x09 ? " " : String(scalar) }.joined()
        for regex in redactionRegexes {
            output = regex.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "[REDACTED]")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func idPart(_ input: String) -> String { clean(input).replacingOccurrences(of: "|", with: "%7C") }

    static func labelToken(_ input: String) -> String {
        let value = clean(input)
        return "label-\(TopologyHash.id(value))"
    }

    static func labels(_ input: [String: String]) -> [String: String] {
        let pairs: [(String, String)] = input.keys.sorted().map { key in
            (labelToken(key), labelToken(input[key] ?? ""))
        }
        return pairs.reduce(into: [String: String]()) { result, pair in result[pair.0] = pair.1 }
    }

    static func selectorSummary(rawLabels: [String: String], expressions: [TopologySelectorRequirement]) -> String {
        let allowed = Set(["app", "app.kubernetes.io/name", "app.kubernetes.io/component", "tier"])
        let labels = rawLabels.keys.sorted().map { key in
            let displayKey = allowed.contains(key) ? key : "label-" + String(TopologyHash.id(key).prefix(10))
            return "\(displayKey)=\(allowed.contains(key) ? "value" : "[REDACTED]")"
        }
        let expressionSummary = expressions.sorted { $0.key < $1.key }.map { expression in
            "\(safeSelectorKey(expression.key)) \(expression.op.rawValue)"
        }
        return (labels + expressionSummary).joined(separator: ", ")
    }

    static func selectorSummary(tokenizedLabels: [String: String], expressions: [TopologySelectorRequirement]) -> String {
        let labels = tokenizedLabels.keys.sorted().map { "\(safeSelectorKey($0))=[REDACTED]" }
        let expressionSummary = expressions.sorted { $0.key < $1.key }.map { "\(safeSelectorKey($0.key)) \($0.op.rawValue)" }
        return (labels + expressionSummary).joined(separator: ", ")
    }

    private static func safeSelectorKey(_ key: String) -> String {
        let allowlisted = Set(["app", "app.kubernetes.io/name", "app.kubernetes.io/component", "tier"])
        if allowlisted.contains(key) { return key }
        if key.hasPrefix("label-") { return String(key.prefix(16)) }
        return "label-\(TopologyHash.id(key).prefix(10))"
    }

    static func attributes(_ input: [String: String]) -> [String: String] {
        input.keys.sorted().reduce(into: [String: String]()) { result, key in
            let safeKey = clean(key)
            guard !safeKey.isEmpty, !looksSensitive(safeKey) else { return }
            result[safeKey] = clean(input[key] ?? "")
        }
    }
    static func looksSensitive(_ input: String) -> Bool { let lower = input.lowercased(); return ["password", "token", "secret", "credential", "authorization", "cookie", "certificate", "private-key", "client-key"].contains { lower.contains($0) } }
}
