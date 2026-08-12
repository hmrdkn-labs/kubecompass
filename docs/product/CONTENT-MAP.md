# Product content map

## Navigation and actions

| Surface | Primary content | Actions |
| --- | --- | --- |
| Boot/welcome | kubectl and kubeconfig readiness | Retry; open settings. |
| Cluster picker | contexts, current-context badge, filter | Connect; reload; open settings. |
| Sidebar shell | context switcher, Overview, resource categories, Helm | Expand/collapse/reorder; hide kinds; go to resource (`⌘K` on macOS). |
| Overview | workload cards, warnings, restarts, abnormal usage | Jump to resource/events/pod; choose namespace; refresh; inspect port forwards. |
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

The direct source/state inventory and Linux coverage status live in
`docs/interface/PROVENANCE.md`.
