# KubeCompass topology fixture

This directory is a deterministic, disposable cluster scenario for validating
the tiered Topology Explorer. It is intentionally read-only from the app's
perspective and contains no `Secret` or `ConfigMap` payloads.

The fixture demonstrates:

- Deployment → ReplicaSet → Pod ownership, a named `web:8443` container port,
  and a deliberately not-ready Pod.
- A named Service port (`https:443 → targetPort: web`), numeric target ports,
  NodePort, headless and selectorless Services.
- A manually managed external EndpointSlice at `192.0.2.10:15443`.
- Duplicate Ingress host/path declarations, NetworkPolicy peer selectors,
  CIDR exceptions and a TCP `endPort` range.
- A PVC that is applied only when the disposable cluster advertises a
  StorageClass, and a ServiceAccount that may list Pods but not Services.
- Optional Gateway API objects. They are applied only when the selected cluster
  exposes Gateway API resources; absence is a useful unsupported-input state.

## Safety contract

`scripts/topology-e2e.sh` downloads a pinned official `kind` release into a
private temporary directory, creates a unique cluster, and sets an explicit
temporary `KUBECONFIG`. It never writes the user's default kubeconfig or
changes the current context. A trap deletes the disposable cluster and removes
all temporary files on success, failure, or interruption.

The script does not run by itself in CI. A caller must opt in with
`KUBECOMPASS_RUN_TOPOLOGY_E2E=1` (or pass `--run`) and must have Docker or
Podman-compatible kind prerequisites. Do not pass a production kubeconfig.

## Run the real fixture

```sh
cd /Users/hamardikan-mac/repos/kubecompass
scripts/topology-e2e.sh --help
scripts/topology-e2e.sh --run
```

Useful options:

```sh
KUBECOMPASS_KIND_VERSION=v0.29.0 scripts/topology-e2e.sh --run
```

The runner validates the Kubernetes semantics consumed by the app. It does not
launch KubeCompass or define a hidden app CLI contract.

## Run the deterministic fake backend

The fake backend validates KubeCompass's kubectl command seam without executing
`kubectl`, contacting a cluster, or mutating files:

```sh
scripts/topology-fake-kubectl.sh --self-test
```

It returns the same sanitized JSON for discovery and topology list calls. The
fixture uses stable UIDs, addresses and resource names so screenshots and
semantic assertions are reproducible. macOS UI fixture runs use a temporary
copy of the app bundle whose bundled kubectl helper is replaced with this
script; the installed app is never modified for fixture capture.

## Expected learning paths

1. `kc-edge`/`kc-orders` or the duplicate Ingresses → `kc-web:443`.
2. Service `targetPort: web` → EndpointSlice port `8443` → Pod container `web`.
3. `kc-nodeport:30080` and `kc-headless` as different exposure semantics.
4. `kc-not-ready` and its EndpointSlice `ready=false` evidence.
5. `kc-web-policy` peers and port range without claiming packet reachability.
6. `kc-topology-denied` showing an explicit permission-limited topology.
