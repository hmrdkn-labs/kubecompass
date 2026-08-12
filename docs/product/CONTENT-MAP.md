# Product content map

## Navigation and actions

| Surface | Primary content | Actions |
| --- | --- | --- |
| Boot/welcome | kubectl and kubeconfig readiness | Retry; open settings. |
| Cluster picker | contexts, current-context badge, filter | Connect; reload; open settings. |
| Sidebar shell | context switcher, Overview, Topology, resource categories, Helm | Open a workspace; expand/collapse/reorder; hide kinds; go to resource (`⌘K` on macOS). |
| Overview | workload cards, warnings, restarts, abnormal usage | Jump to resource/events/pod; choose namespace; refresh; inspect port forwards. |
| Topology Explorer | three-pane, evidence-aware Explorer Levels, Map/List/Port Table, Snapshot Status, selected-object Fundamentals, Port Paths, and unavailable-input notices | Choose context, namespace, Explorer Level, and Focus/Trace/Inventory mode; search/filter; select a Resource Node, Relationship, Route, or Port Hop; refresh; jump to its resource list. Read-only. |
| Resource list | sortable/customizable columns, namespace scope, selection | Filter; select one/many; create; refresh; open detail; logs; YAML; delete; scale; restart; port forward. |
| Resource detail | Overview, Pods, YAML, Logs, Events tabs | Close; switch tab; apply YAML; retry; destructive/action menu. |
| Helm | release table and release detail tabs | Select release; inspect values/manifests/notes/history; refresh. |
| Port forwards | active tunnel list and status | Start; open local URL; stop; inspect failure. |
| Settings | kubectl path, kubeconfig path, extra PATH, log tail | Edit and persist preferences. |

## State coverage contract

Every adapter must represent these states with truthful copy and an actionable
next step where one exists:

| State | Required meaning and examples |
| --- | --- |
| Loading | Boot “Connecting…”, list/detail fetch, CRD template, YAML, logs/events. Preserve context while progress is visible. |
| Empty | No contexts, no matching clusters, no resources, no warnings/restarts/hot pods, no Helm releases, no active forwards, no events, empty data section. |
| Error | Bootstrap failure, unavailable overview, list/detail/log/YAML/events failure, failed port forward, failed mutation. Show retry or safe dismissal. |
| Offline | Kubectl/cluster cannot be reached; retain stale data only when marked stale and never imply freshness. |
| Reconnecting | Watch/refresh resumes after interruption; expose reconnect status and preserve selection when safe. |
| Permission | Kubernetes RBAC or local executable/auth-plugin denial; identify the denied operation and avoid destructive retry loops. |
| Confirmation | Delete and rollout restart dialogs identify count, resource, namespace, context, and irreversible effect. |
| Success | Connected context, applied manifest, active forward, refreshed data, or completed action is visible without implying more than the command returned. |

Topology adds a **Partial** condition inside its data state: valid relationships
remain visible while each forbidden, unsupported, timed-out, or unresolved
input is named. Partial is never rendered as complete or empty. The exact
relationship language and security boundary live in
`docs/product/TOPOLOGY-EXPLORER.md`.

## Topology Explorer content contract

| Explorer Level | Primary content | Learner prompt |
| --- | --- | --- |
| Cluster | Context, namespaces, Snapshot Status, control-plane boundary, entry points, cluster-scoped resources | “What can this snapshot tell me, and what is unavailable?” |
| Infrastructure | Current: Nodes, roles, addresses, zones, Pod CIDRs, runtime/OS facts, scheduling and storage classes. Planned: complete conditions, capacity/allocatable, and taints. | “Where can workloads run?” |
| Workloads | Current: owners, replicas, Pods, containers, phase/readiness/restarts, and unresolved ownership. Planned: workload conditions and probe declarations. | “What created this workload, and where is it running?” |
| Network | Ingress/Gateway/Route, Service ports, targetPort resolution, EndpointSlices, backend Pods and container ports | “How is this application declared and exposed?” |
| Policy & Dependencies | Current: NetworkPolicy peers/ports, storage, ConfigMap/Secret resource names, and unresolved references. Planned: ServiceAccount/RBAC identity, quotas, disruption budgets, and autoscaling. | “What declares access, and what does it depend on?” |
| Evidence | Source fields, join rules, resource versions, assumptions, Exposure Status, unavailable inputs | “What does this prove, and what does it not prove?” |

Every level supports these equivalent modes:

- **Focus** — selected object plus bounded neighbors.
- **Trace** — one Route, Port Path, policy, or dependency hop at a time.
- **Inventory** — complete searchable rows for the current scope.

Map, List, and Port Table share selection, filters, evidence, and handoff. Map
and List represent resources and relationships; Port Table represents the
corresponding typed route and exposure paths. It is not a decorative legend:
it is the canonical compact
surface for protocol, name, port, targetPort resolution, endpoint readiness,
and Evidence Level.

Topology-specific copy must distinguish:

- **Snapshot Status**: Loading, Ready, Empty, Partial, Stale, Offline,
  Reconnecting, or Error.
- **Exposure Status**: Declared, Resolved, Ready endpoints, No ready endpoints,
  Ambiguous, Unresolved, Partial, or Unavailable.

“What this proves” and “What this does not prove” are required in the evidence
inspector for a selected relationship, Route, or Port Path. They must never say
“traffic flows,” “reachable,” or “enforced” without a separate telemetry or
provider evidence source.

The implementation source/state inventory and Linux coverage status live in
`docs/interface/PROVENANCE.md`. The approved interaction and runtime evidence
matrix lives in `docs/interface/TOPOLOGY-HIERARCHY-REVIEW.json`.
