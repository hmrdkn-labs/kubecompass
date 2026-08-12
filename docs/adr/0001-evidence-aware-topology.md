# Build topology as an evidence graph

KubeCompass will model cluster exploration as a portable, read-only evidence
graph before rendering it in SwiftUI or GTK. Every relationship records its
source and Evidence Level, partial RBAC or unavailable APIs remain visible,
and provider control-plane, CNI, or packet paths are never invented. This
trades a simpler decorative diagram for a trustworthy learning surface that
can be tested once and adapted across desktop platforms.

## Consequences

- The Topology Explorer may say that an input is unavailable instead of
  drawing a complete-looking graph.
- Service selectors, Ingress backends, and NetworkPolicy declarations are
  configuration evidence, not proof of traffic or enforcement.
- Shared graph state contains typed, allowlisted relationship fields only;
  raw YAML, annotations, Secret values, ConfigMap values, command diagnostics,
  and kubeconfig data stay outside the graph boundary.
- The first release is read-only. Mutations, port forwarding, provider APIs,
  service-mesh telemetry, and packet-flow claims are outside this workspace.
