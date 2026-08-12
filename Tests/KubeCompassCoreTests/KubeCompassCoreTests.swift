import XCTest
@testable import KubeCompassCore

final class KubeCompassCoreTests: XCTestCase {
    private func loadedState(kind: ResourceKind = ResourceKind(id: "pods", displayName: "Pods", supportsDelete: true, supportsRestart: false)) -> CompassState {
        var state = CompassState()
        state.contexts = [KubeContext(id: "dev", name: "dev", cluster: "cluster", user: "user", isCurrent: true, defaultNamespace: "platform")]
        state.selectedContextID = "dev"; state.namespaces = ["default", "platform"]; state.selectedNamespace = "default"; state.selectedListScope = .namespace("default")
        state.resourceKinds = [kind]; state.selectedKindID = kind.id
        let resource = KubeResource(id: "ui-row-1", kindID: kind.id, name: "api-0", namespace: kind.namespaced ? "default" : nil, status: "Running", apiVersion: "apps/v1", group: "apps", resourcePlural: kind.id, kindName: kind.displayName, uid: "uid-1", resourceVersion: "rv-1")
        state.resourcesByKind[kind.id] = [resource]; state.selectedResourceID = resource.id
        return state
    }

    func testDeterministicContextNamespaceResourceDetailLogsReconnectTrace() {
        let first = CompassTrace.run(); XCTAssertEqual(first, CompassTrace.run())
        XCTAssertEqual(first.map(\.label), ["bootstrap", "contexts", "context-dev", "namespace-list", "namespace-default", "kind-pods", "resource-list", "resource-detail", "logs-tab", "log-1", "log-2", "reconnect", "reconnect-failed", "reconnect-again", "reconnect-success"])
        XCTAssertEqual(first[7].selectedResourceID, "pods/default/api-0"); XCTAssertEqual(first[8].detailTab, .logs); XCTAssertEqual(first.last?.connectivity, .connected)
        XCTAssertFalse(first.map(\.safeState).joined(separator: " ").contains("request complete"))
    }

    func testTypedScopesAndExactArgvNeverUseAllNamespacesForObjects() throws {
        let podKind = ResourceKind(id: "pods", displayName: "Pods", supportsDelete: true)
        XCTAssertEqual(try KubectlCommand.list(contextID: "dev", kind: podKind, scope: .current).argv, ["kubectl", "get", "pods", "--context", "dev", "--output", "json"])
        XCTAssertEqual(try KubectlCommand.list(contextID: "dev", kind: podKind, scope: .namespace("default")).argv, ["kubectl", "get", "pods", "--context", "dev", "--namespace", "default", "--output", "json"])
        XCTAssertEqual(try KubectlCommand.list(contextID: "dev", kind: podKind, scope: .allNamespaces).argv, ["kubectl", "get", "pods", "--context", "dev", "--all-namespaces", "--output", "json"])
        XCTAssertThrowsError(try KubectlCommand.list(contextID: "dev", kind: ResourceKind(id: "nodes", displayName: "Nodes", namespaced: false), scope: .allNamespaces))
        let detail = KubectlCommand.detail(contextID: "dev", kindID: "pods", resourceName: "api-0", scope: .namespaced(namespace: "default"))
        let logs = KubectlCommand.logs(contextID: "dev", resourceName: "api-0", scope: .namespaced(namespace: "default"))
        XCTAssertFalse(detail.argv.contains("--all-namespaces")); XCTAssertFalse(logs.argv.contains("--all-namespaces"))
        XCTAssertEqual(detail.argv[3], "api-0"); XCTAssertEqual(logs.argv[2], "api-0")
    }

    func testContextDefaultNamespaceWinsOverLexicographicFallback() {
        var state = CompassState(); state.contexts = [KubeContext(id: "dev", name: "dev", cluster: "c", user: "u", defaultNamespace: "platform")]; state.selectedContextID = "dev"
        let transition = CompassReducer.reduce(state, .namespacesLoaded(["default", "platform", "zzz"]))
        XCTAssertEqual(transition.state.selectedNamespace, "platform"); XCTAssertEqual(transition.state.selectedListScope, .namespace("platform"))
        let fallback = CompassReducer.reduce(state, .namespacesLoaded(["default", "zzz"]))
        XCTAssertEqual(fallback.state.selectedNamespace, "default")
        let noCurrent = CompassState(); let picker = CompassReducer.reduce(noCurrent, .contextsLoaded([KubeContext(id: "a", name: "a", cluster: "c", user: "u"), KubeContext(id: "b", name: "b", cluster: "c", user: "u")]))
        XCTAssertNil(picker.state.selectedContextID); XCTAssertTrue(picker.events.contains(.contextPickerRequired)); XCTAssertTrue(picker.effects.isEmpty)
        let oneCurrent = CompassState(); let connected = CompassReducer.reduce(oneCurrent, .contextsLoaded([KubeContext(id: "a", name: "a", cluster: "c", user: "u", isCurrent: true)])); XCTAssertEqual(connected.state.selectedContextID, "a"); XCTAssertEqual(connected.effects, [.loadNamespaces(contextID: "a")])
    }

    func testTypedPortForwardValidatesTargetNamespacePortsAndLoopback() throws {
        let pod = ResourceKind(id: "pods", displayName: "Pod", namespaced: true, supportsDelete: true)
        let command = try KubectlCommand.portForward(contextID: "dev", targetKind: pod, targetName: "api-0", scope: .namespaced(namespace: "default"), localPort: 8080, remotePort: 80)
        XCTAssertEqual(command.argv, ["kubectl", "port-forward", "--context", "dev", "--namespace", "default", "pods/api-0", "8080:80", "--address", "127.0.0.1,::1"])
        XCTAssertThrowsError(try KubectlCommand.portForward(contextID: "dev", targetKind: pod, targetName: "api/0", scope: .namespaced(namespace: "default"), localPort: 8080, remotePort: 80))
        XCTAssertThrowsError(try KubectlCommand.portForward(contextID: "dev", targetKind: pod, targetName: "api-0", scope: .cluster, localPort: 8080, remotePort: 80)) { XCTAssertEqual($0 as? KubectlCommand.CommandError, .namespaceRequired) }
        XCTAssertThrowsError(try KubectlCommand.portForward(contextID: "dev", targetKind: pod, targetName: "api-0", scope: .namespaced(namespace: "default"), localPort: 0, remotePort: 80))
    }

    func testResourceTableDropsMalformedDuplicatesAndP95UsesGenerousDebugCeiling() {
        let rows = [KubeResource(id: "2", kindID: "pods", name: "Zulu"), KubeResource(id: "1", kindID: "pods", name: "alpha"), KubeResource(id: "1", kindID: "pods", name: "duplicate"), KubeResource(id: "", kindID: "pods", name: "malformed"), KubeResource(id: "3", kindID: "pods", name: "Beta")]
        let index = ResourceTableIndex(resources: rows); XCTAssertEqual(index.count, 3); XCTAssertEqual(index.filteredSorted().map(\.name), ["alpha", "Beta", "Zulu"]); XCTAssertEqual(index.validSelection(["1", "missing"]), ["1"])
        let many = ResourceTableIndex(resources: (0..<10_000).map { KubeResource(id: "pods/\($0)", kindID: "pods", name: "pod-\($0)", namespace: "default") }); var samples: [Double] = []
        for _ in 0..<20 { let start = DispatchTime.now().uptimeNanoseconds; XCTAssertEqual(many.filteredSorted(query: "pod-9").count, 1_111); samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) }
        samples.sort(); XCTAssertLessThanOrEqual(samples[Int(Double(samples.count - 1) * 0.95)], 500.0) // trace benchmark owns the 150ms external gate
    }

    func testMutationUsesCanonicalNameAndRequiresRefetchIdentityDryRunAuthorization() {
        let state = loadedState(); let target = state.resourcesByKind["pods"]!.first!.mutationTarget(contextID: "dev", namespaced: true)!; let request = MutationRequest(operation: .delete, targets: [target])
        let pending = CompassReducer.reduce(state, .requestMutation(request)); XCTAssertEqual(pending.effects, [.refetchMutation(request)]); XCTAssertEqual(pending.events, [.mutationConfirmationRequired, .mutationValidation(.refetch)])
        let verified = CompassReducer.reduce(pending.state, .mutationRefetched([target])); XCTAssertEqual(verified.effects, [.dryRunMutation(request)]); XCTAssertEqual(verified.events, [.mutationValidation(.identityVerified)])
        let preview = CompassReducer.reduce(verified.state, .mutationDryRunFinished(success: true, problem: nil)); XCTAssertTrue(preview.effects.isEmpty); guard case .validated(let storedPreview) = preview.state.confirmation else { return XCTFail("expected immutable validated preview") }; XCTAssertEqual(storedPreview.request, request); XCTAssertEqual(storedPreview.targetDigest, ValidatedMutationPreview(request: request).targetDigest)
        let description = MutationPreviewDescription(operation: .delete, target: target)
        XCTAssertEqual(description.target.name, "api-0"); XCTAssertEqual(description.target.resourceVersion, "rv-1")
    }

    func testMutationRejectsStaleUIDResourceVersionDryRunAndUnsupportedRestart() {
        let state = loadedState(); let target = state.resourcesByKind["pods"]!.first!.mutationTarget(contextID: "dev", namespaced: true)!; let request = MutationRequest(operation: .delete, targets: [target]); let pending = CompassReducer.reduce(state, .requestMutation(request))
        let stale = MutationTarget(contextID: target.contextID, apiVersion: target.apiVersion, group: target.group, resourcePlural: target.resourcePlural, kindName: target.kindName, name: target.name, namespace: target.namespace, uid: target.uid, resourceVersion: "rv-new", sourceID: target.sourceID)
        let rejected = CompassReducer.reduce(pending.state, .mutationRefetched([stale])); XCTAssertTrue(rejected.effects.isEmpty); XCTAssertEqual(rejected.events, [.mutationValidation(.rejected)])
        let failedDryRun = CompassReducer.reduce(CompassReducer.reduce(pending.state, .mutationRefetched([target])).state, .mutationDryRunFinished(success: false, problem: CompassProblem(code: .permission, message: "forbidden"))); XCTAssertTrue(failedDryRun.effects.isEmpty)
        let restart = CompassReducer.reduce(loadedState(), .requestRestart(["ui-row-1"])); XCTAssertTrue(restart.effects.isEmpty); XCTAssertTrue(restart.events.isEmpty)
        let undeclaredDelete = CompassReducer.reduce(loadedState(kind: ResourceKind(id: "custom", displayName: "Custom")), .requestDelete(["ui-row-1"])); XCTAssertTrue(undeclaredDelete.effects.isEmpty)
        let restartTarget = loadedState(kind: ResourceKind(id: "deployments", displayName: "Deployments", supportsDelete: true, supportsRestart: true)).resourcesByKind["deployments"]!.first!.mutationTarget(contextID: "dev", namespaced: true)!
        let restartDescription = MutationPreviewDescription(operation: .restart, target: restartTarget)
        XCTAssertEqual(restartDescription.operation, .restart); XCTAssertEqual(restartDescription.target.name, "api-0")
    }

    func testSafeProblemAndStateEncodingRedactANSIControlAndSecrets() throws {
        let raw = "\u{001B}[31mforbidden\u{001B}[0m password=s3cr3t bearer abc.token cookie=c credential=d certificate-data=e annotations=foo \"token\":\"json-secret\"\nclient-secret=hide\u{0007}"
        let problem = CompassProblem.classify(raw); XCTAssertEqual(problem.code, .permission); XCTAssertFalse(problem.message.contains("s3cr3t")); XCTAssertFalse(problem.message.contains("abc.token")); XCTAssertFalse(problem.message.contains("\u{001B}")); XCTAssertFalse(problem.message.contains("\u{0007}"))
        let state = CompassReducer.reduce(CompassState(), .permissionDenied(raw)).state; let data = try JSONEncoder().encode(state); let encoded = String(decoding: data, as: UTF8.self); XCTAssertFalse(encoded.contains("s3cr3t")); XCTAssertFalse(encoded.contains("abc.token")); XCTAssertFalse(encoded.contains("json-secret")); XCTAssertFalse(encoded.contains("\u{001B}")); XCTAssertFalse(encoded.contains("\u{0007}"))
        XCTAssertFalse(try! KubectlCommand.list(contextID: "dev", kind: ResourceKind(id: "secrets", displayName: "Secrets", supportsDelete: true), scope: .namespace("default")).safeDescription.contains("--namespace"))
    }

    func testWatchStartHealthBookmarkExpiredBackoffAndIdempotentCancel() {
        var state = loadedState(); state = CompassReducer.reduce(state, .resourcesLoaded(kindID: "pods", resources: state.resourcesByKind["pods"]!)).state; XCTAssertEqual(state.watchHealth, .starting); XCTAssertFalse(state.isWatching)
        let healthy = CompassReducer.reduce(state, .watchStarted(kindID: "pods", resourceVersion: "rv-1")); XCTAssertEqual(healthy.state.watchHealth, .healthy(resourceVersion: "rv-1")); XCTAssertTrue(healthy.state.isWatching)
        let bookmark = CompassReducer.reduce(healthy.state, .watchEvent(kindID: "pods", event: .bookmark(resourceVersion: "rv-2"))); XCTAssertEqual(bookmark.state.watchHealth, .healthy(resourceVersion: "rv-2"))
        let expired = CompassReducer.reduce(bookmark.state, .watchEvent(kindID: "pods", event: .expired(resourceVersion: "rv-2"))); XCTAssertEqual(expired.effects.count, 2); XCTAssertEqual(expired.state.watchHealth, .retrying(attempt: 1, delayMilliseconds: 100))
        let jitteredState = CompassReducer.reduce(expired.state, .watchRetryPolicy(WatchRetryPolicy(baseDelayMilliseconds: 100, capDelayMilliseconds: 5000, maxAttempts: 3, jitterMilliseconds: 37))).state
        let retryExpired = CompassReducer.reduce(jitteredState, .watchEvent(kindID: "pods", event: .expired(resourceVersion: "rv-2"))); XCTAssertTrue(retryExpired.effects.isEmpty)
        XCTAssertTrue(CompassReducer.reduce(expired.state, .watchEvent(kindID: "pods", event: .expired(resourceVersion: "rv-2"))).effects.isEmpty)
        let retry = CompassReducer.reduce(jitteredState, .watchRetryReady(kindID: "pods")); XCTAssertEqual(retry.effects.count, 1)
        let secondExpired = CompassReducer.reduce(retry.state, .watchEvent(kindID: "pods", event: .expired(resourceVersion: "rv-2"))); XCTAssertEqual(secondExpired.state.watchHealth, .retrying(attempt: 2, delayMilliseconds: 237)); XCTAssertLessThanOrEqual(secondExpired.state.watchRetryPolicy.delay(forAttempt: 3), 5000)
        let cancelled = CompassReducer.reduce(healthy.state, .cancelWatch); XCTAssertEqual(cancelled.effects, [.cancel(requestID: "watch")]); XCTAssertTrue(CompassReducer.reduce(cancelled.state, .cancelWatch).effects.isEmpty)
        let fallback = CompassReducer.reduce(healthy.state, .watchUnavailable(kindID: "pods", problem: CompassProblem(code: .unsupported, message: "watch unsupported"))); XCTAssertEqual(fallback.state.watchHealth, .pollingFallback(CompassProblem(code: .unsupported, message: "watch unsupported"))); XCTAssertEqual(fallback.effects, [.poll(contextID: "dev", kindID: "pods", scope: .namespace("default"))])
    }

    func testWatchRetryPolicyClampsAndAvoidsIntegerOverflow() {
        let policy = WatchRetryPolicy(baseDelayMilliseconds: Int.max, capDelayMilliseconds: 7, maxAttempts: Int.max, jitterMilliseconds: Int.max)
        XCTAssertEqual(policy.baseDelayMilliseconds, 7); XCTAssertEqual(policy.capDelayMilliseconds, 7); XCTAssertEqual(policy.jitterMilliseconds, 6)
        XCTAssertEqual(policy.delay(forAttempt: Int.min), 7); XCTAssertEqual(policy.delay(forAttempt: Int.max), 7)
        let huge = WatchRetryPolicy(baseDelayMilliseconds: Int.max, capDelayMilliseconds: Int.max, jitterMilliseconds: Int.max)
        XCTAssertEqual(huge.delay(forAttempt: Int.max), Int.max)
    }

    func testMultiTargetValidationRequiresEveryUniqueMatchingSnapshot() {
        var state = loadedState(); let first = state.resourcesByKind["pods"]!.first!; let second = KubeResource(id: "ui-row-2", kindID: "pods", name: "web-0", namespace: "default", apiVersion: "apps/v1", group: "apps", resourcePlural: "pods", kindName: "Pods", uid: "uid-2", resourceVersion: "rv-2"); state.resourcesByKind["pods"]!.append(second)
        let a = first.mutationTarget(contextID: "dev", namespaced: true)!; let b = second.mutationTarget(contextID: "dev", namespaced: true)!; let request = MutationRequest(operation: .delete, targets: [a, b]); let pending = CompassReducer.reduce(state, .requestMutation(request))
        XCTAssertEqual(CompassReducer.reduce(pending.state, .mutationRefetched([a])).events, [.mutationValidation(.rejected)])
        XCTAssertEqual(CompassReducer.reduce(pending.state, .mutationRefetched([a, a])).events, [.mutationValidation(.rejected)])
        XCTAssertEqual(CompassReducer.reduce(pending.state, .mutationRefetched([a, b])).effects, [.dryRunMutation(request)])
    }
}
