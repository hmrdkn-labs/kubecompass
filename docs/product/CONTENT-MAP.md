# Product content map

## Navigation and actions

| Surface | Primary content | Actions |
| --- | --- | --- |
| Boot/welcome | kubectl and kubeconfig readiness | Retry; open settings. |
| Cluster picker | contexts, current-context badge, filter | Connect; reload; open settings. |
| Sidebar shell | context switcher, Overview, Topology, resource categories, Helm | Open a workspace; expand/collapse/reorder; hide kinds; go to resource (`⌘K` on macOS). |
| Overview | workload cards, warnings, restarts, abnormal usage | Jump to resource/events/pod; choose namespace; refresh; inspect port forwards. |
| Topology Explorer | Outline default, selected-root Map (one or two hops), typed Paths diagnostics, persistent Fundamentals/evidence inspector, Snapshot Status, and unavailable-input notices | Choose context and namespace; expand Outline; select a workload/root or relationship; open Map or Paths; search/filter; refresh; jump to its resource list. Narrow selection uses push navigation with a back path. Read-only; Traffic is unavailable without telemetry. |
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

| Surface | Primary content | Learner prompt |
| --- | --- | --- |
| Outline (default) | Namespace groups, primary workload/controller, dependents, unattached resources, Snapshot Status, and evidence gaps | “What is here, and why is it grouped this way?” |
| Scoped Map | Selected root plus one or two typed relationship hops, explicit scope/filter/source controls, and stable selection | “Which nearby objects explain this selection?” |
| Paths | One typed Route/Service/EndpointSlice/Pod-container, policy, or dependency diagnostic with hop-level evidence | “How does this declared path resolve, and what remains unknown?” |
| Persistent inspector | Fundamentals, status, provenance, unavailable inputs, safe next actions, and proof/non-proof copy | “What does this selection prove?” |

Outline is the canonical keyboard semantic hierarchy; Map and Paths share its
selection, filters, evidence, and handoff. Paths is the canonical typed
diagnostic list, and the persistent inspector carries detail across surfaces.
There is no separate List or Port Table fallback surface. Traffic is not a
fourth surface: it is unavailable unless an explicit telemetry adapter supplies
flow evidence.

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
