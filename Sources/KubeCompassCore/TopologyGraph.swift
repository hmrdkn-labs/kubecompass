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

public struct TopologyEndpointTarget: Codable, Hashable, Sendable {
    public let reference: TopologyObjectReference
    public let ready: Bool?

    public init(reference: TopologyObjectReference, ready: Bool? = nil) {
        self.reference = reference
        self.ready = ready
    }
}

public struct TopologyEndpointSliceSnapshot: Codable, Hashable, Sendable {
    public let serviceName: String?
    public let endpoints: [TopologyEndpointTarget]

    public init(serviceName: String? = nil, endpoints: [TopologyEndpointTarget] = []) {
        self.serviceName = serviceName.map { TopologySanitizer.clean($0) }
        self.endpoints = endpoints
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

    public init(matchLabels: [String: String] = [:], matchExpressions: [TopologySelectorRequirement] = []) {
        self.matchLabels = TopologySanitizer.labels(matchLabels)
        self.matchExpressions = matchExpressions.sorted { lhs, rhs in
            lhs.key == rhs.key ? lhs.op.rawValue < rhs.op.rawValue : lhs.key < rhs.key
        }
    }

    fileprivate init(tokenizedMatchLabels: [String: String], tokenizedExpressions: [TopologySelectorRequirement]) {
        self.matchLabels = tokenizedMatchLabels
        self.matchExpressions = tokenizedExpressions
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
            case .notIn: return value.map { !requirement.values.contains($0) } ?? false
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

    public init(podSelector: TopologyLabelSelector = TopologyLabelSelector(), policyTypes: [String] = [], ingressRuleCount: Int = 0, egressRuleCount: Int = 0) {
        self.podSelector = podSelector
        self.policyTypes = policyTypes.map { TopologySanitizer.clean($0).uppercased() }.filter { !$0.isEmpty }.sorted()
        self.ingressRuleCount = max(0, ingressRuleCount)
        self.egressRuleCount = max(0, egressRuleCount)
    }
}

public struct TopologyResourceSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let identity: TopologyResourceIdentity
    public let ownerReferences: [TopologyOwnerReference]
    public let podNodeName: String?
    public let selector: [String: String]
    public let selectorExpressions: [TopologySelectorRequirement]
    public let ingressBackends: [TopologyServiceReference]
    public let endpointSlice: TopologyEndpointSliceSnapshot?
    public let volumeReferences: [TopologyObjectReference]
    public let configReferences: [TopologyNamedReference]
    public let roleLabels: [String: String]
    public let networkPolicy: TopologyNetworkPolicySnapshot?
    public let facts: [TopologyFact]

    public init(identity: TopologyResourceIdentity, ownerReferences: [TopologyOwnerReference] = [], podNodeName: String? = nil, selector: [String: String] = [:], selectorExpressions: [TopologySelectorRequirement] = [], ingressBackends: [TopologyServiceReference] = [], endpointSlice: TopologyEndpointSliceSnapshot? = nil, volumeReferences: [TopologyObjectReference] = [], configReferences: [TopologyNamedReference] = [], roleLabels: [String: String] = [:], networkPolicy: TopologyNetworkPolicySnapshot? = nil, facts: [TopologyFact] = []) {
        self.identity = identity
        self.id = identity.stableNodeID(contextID: "snapshot")
        self.ownerReferences = ownerReferences.sorted(by: TopologySort.owner)
        self.podNodeName = podNodeName.map(TopologySanitizer.clean)
        self.selector = TopologySanitizer.labels(selector)
        self.selectorExpressions = selectorExpressions.sorted { lhs, rhs in lhs.key == rhs.key ? lhs.op.rawValue < rhs.op.rawValue : lhs.key < rhs.key }
        self.ingressBackends = ingressBackends.sorted(by: TopologySort.service)
        self.endpointSlice = endpointSlice
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

public struct TopologyGraph: Codable, Hashable, Sendable {
    public let contextID: String
    public let freshness: TopologyFreshness
    public let completeness: TopologySnapshotCompleteness
    public let nodes: [TopologyNode]
    public let edges: [TopologyEdge]
    public let unresolvedReferences: [TopologyUnresolvedReference]
    public let inputs: [TopologyInputStatus]

    public init(contextID: String, freshness: TopologyFreshness, completeness: TopologySnapshotCompleteness, nodes: [TopologyNode], edges: [TopologyEdge], unresolvedReferences: [TopologyUnresolvedReference] = [], inputs: [TopologyInputStatus] = []) {
        self.contextID = TopologySanitizer.clean(contextID)
        self.freshness = freshness
        self.completeness = completeness
        self.nodes = nodes.sorted { $0.id < $1.id }
        self.edges = edges.sorted { $0.id < $1.id }
        self.unresolvedReferences = unresolvedReferences.sorted { $0.id < $1.id }
        self.inputs = inputs.sorted { $0.id < $1.id }
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
        func apiEvidence(_ resource: TopologyResourceSnapshot, level: TopologyEvidenceLevel = .observed, sourceField: String? = nil, joinRule: String? = nil, assumption: String? = nil) -> TopologyEvidence {
            TopologyEvidence(level: level, source: .object(contextID: context, identity: resource.identity, sourceField: sourceField, joinRule: joinRule, assumption: assumption), freshness: freshness)
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

        func resolve(_ reference: TopologyObjectReference, fallbackNamespace: String?) -> String? {
            if let uid = reference.uid, !uid.isEmpty {
                return nodes.values.first(where: { $0.uid == uid && (reference.namespace == nil || $0.namespace == reference.namespace) && (reference.kind.isEmpty || $0.kind.caseInsensitiveCompare(reference.kind) == .orderedSame) })?.id
            }
            let candidates = nodes.values.filter {
                $0.name == reference.name
                    && (reference.kind.isEmpty || $0.kind.caseInsensitiveCompare(reference.kind) == .orderedSame)
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

            for backend in resource.ingressBackends {
                let ref = TopologyObjectReference(apiVersion: "v1", kind: "Service", name: backend.name, namespace: backend.namespace ?? resource.identity.namespace)
                var backendAttributes: [String: String] = [:]
                if let port = backend.port { backendAttributes["port"] = String(port) }
                if let portName = backend.portName { backendAttributes["portName"] = portName }
                if let target = resolve(ref, fallbackNamespace: resource.identity.namespace) { addEdge(from: source, to: target, relation: .routesTo, level: .declared, sourceResource: resource, sourceField: "spec.rules[].http.paths[].backend.service.port", joinRule: "backend service name/namespace identifies Service; numeric or named port is descriptive", assumption: "declared backend only; request routing is not proven", attributes: backendAttributes) }
                else { addUnresolved(relation: .routesTo, source: source, target: ref, reason: "Ingress backend Service is not present in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.rules[].http.paths[].backend.service.port", joinRule: "backend service name/namespace identifies Service; numeric or named port is descriptive", assumption: "declared backend only; request routing is not proven") }
            }

            if let slice = resource.endpointSlice, let serviceName = slice.serviceName {
                let serviceRef = TopologyObjectReference(apiVersion: "v1", kind: "Service", name: serviceName, namespace: resource.identity.namespace)
                if let target = resolve(serviceRef, fallbackNamespace: resource.identity.namespace) { addEdge(from: source, to: target, relation: .publishesEndpoints, level: .observed, sourceResource: resource, sourceField: "metadata.labels[kubernetes.io/service-name]", joinRule: "EndpointSlice service label equals Service.metadata.name") }
                else { addUnresolved(relation: .publishesEndpoints, source: source, target: serviceRef, reason: "EndpointSlice service label target is not present in this snapshot", level: .observed, sourceResource: resource, sourceField: "metadata.labels[kubernetes.io/service-name]", joinRule: "EndpointSlice service label equals Service.metadata.name") }
                for endpoint in slice.endpoints {
                    if let target = resolve(endpoint.reference, fallbackNamespace: resource.identity.namespace) { addEdge(from: source, to: target, relation: .endpointTarget, level: .observed, sourceResource: resource, sourceField: "endpoints[].targetRef", joinRule: "EndpointSlice targetRef identifies Pod", attributes: endpoint.ready.map { ["ready": String($0)] } ?? [:]) }
                    else { addUnresolved(relation: .endpointTarget, source: source, target: endpoint.reference, reason: "EndpointSlice targetRef is not present in this snapshot", level: .observed, sourceResource: resource, sourceField: "endpoints[].targetRef", joinRule: "EndpointSlice targetRef identifies Pod") }
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
                let candidates = unique.filter { candidate in
                    candidate.identity.namespace == resource.identity.namespace && (candidate.identity.kind.caseInsensitiveCompare("Pod") == .orderedSame || candidate.identity.kind.caseInsensitiveCompare("Pods") == .orderedSame) && policySelector.matchesTokenized(candidate.identity.labels)
                }
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
            let candidates = unique.filter { candidate in
                guard candidate.identity.namespace == resource.identity.namespace else { return false }
                guard candidate.identity.kind.lowercased() == "pod" || candidate.identity.kind.lowercased() == "pods" else { return false }
                return selector.matchesTokenized(candidate.identity.labels)
            }
            if kind == "service" || kind == "services" {
                for candidate in candidates { addEdge(from: source, to: resourceNode(candidate), relation: .selects, level: .inferred, sourceResource: resource, sourceField: "spec.selector", joinRule: "selector matches Pod.metadata.labels", assumption: "label selection does not prove traffic or endpoint readiness") }
            } else if kind.contains("deployment") || kind.contains("statefulset") || kind.contains("daemonset") || kind.contains("replicaset") {
                for candidate in candidates { addEdge(from: source, to: resourceNode(candidate), relation: .selects, level: .inferred, sourceResource: resource, sourceField: "spec.selector", joinRule: "selector matches Pod.metadata.labels", assumption: "label selection does not prove controller reconciliation") }
            }
            if (kind == "service" || kind == "services" || kind.contains("deployment") || kind.contains("statefulset") || kind.contains("daemonset") || kind.contains("replicaset")) && candidates.isEmpty {
                addUnresolved(relation: .selects, source: source, target: TopologyObjectReference(kind: "Pod", name: "<selector>", namespace: resource.identity.namespace), reason: "selector declaration matched zero Pod resources in this snapshot", level: .declared, sourceResource: resource, sourceField: "spec.selector", joinRule: "selector matches Pod.metadata.labels", assumption: "no target node is invented")
            }
        }

        let unavailable = inputs.filter { $0.availability != .available }
        for input in unavailable {
            let target = TopologyObjectReference(kind: input.resourceKind, name: "<input>")
            addUnresolved(relation: .inputUnavailable, source: nil, target: target, reason: input.message ?? "input \(input.availability.rawValue)", level: .unavailable, sourceStatus: input, sourceField: "input.\(input.resourceKind)", joinRule: "input availability status")
        }
        let completeness: TopologySnapshotCompleteness = unavailable.isEmpty ? .complete : (unique.isEmpty ? .unavailable : .partial)
        return TopologyGraph(contextID: context, freshness: freshness, completeness: completeness, nodes: Array(nodes.values), edges: Array(edges.values), unresolvedReferences: Array(unresolved.values), inputs: inputs)
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

    static func attributes(_ input: [String: String]) -> [String: String] {
        input.keys.sorted().reduce(into: [String: String]()) { result, key in
            let safeKey = clean(key)
            guard !safeKey.isEmpty, !looksSensitive(safeKey) else { return }
            result[safeKey] = clean(input[key] ?? "")
        }
    }
    static func looksSensitive(_ input: String) -> Bool { let lower = input.lowercased(); return ["password", "token", "secret", "credential", "authorization", "cookie", "certificate", "private-key", "client-key"].contains { lower.contains($0) } }
}
