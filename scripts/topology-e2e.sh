#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir="$repo_root/fixtures/topology"
namespace="kc-topology"
kind_version="${KUBECOMPASS_KIND_VERSION:-v0.29.0}"
node_image="${KUBECOMPASS_KIND_NODE_IMAGE:-kindest/node:v1.31.4}"
run_requested=0

usage() {
  cat <<'EOF'
KubeCompass disposable topology E2E fixture

Usage:
  scripts/topology-e2e.sh --help
  scripts/topology-e2e.sh --run

The runner downloads a pinned official kind binary into a private temporary
directory, creates a unique disposable cluster with an explicit temporary
KUBECONFIG, applies fixtures, performs semantic assertions, optionally runs
the assertions, and always deletes the cluster on exit.

Environment:
  KUBECOMPASS_KIND_VERSION      kind release (default: v0.29.0)
  KUBECOMPASS_KIND_NODE_IMAGE   kind node image (default: kindest/node:v1.31.4)
  KUBECOMPASS_RUN_TOPOLOGY_E2E  set to 1 to allow a run without --run
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--run" ]]; then
  run_requested=1
fi
if [[ "${KUBECOMPASS_RUN_TOPOLOGY_E2E:-0}" == "1" ]]; then
  run_requested=1
fi
if (( run_requested == 0 )); then
  echo "topology-e2e: refusing to create a cluster; pass --run (see --help)" >&2
  exit 2
fi
if [[ "${1:-}" != "--run" && "${KUBECOMPASS_RUN_TOPOLOGY_E2E:-0}" != "1" ]]; then
  echo "topology-e2e: unknown argument '${1:-}'" >&2
  exit 2
fi

command -v curl >/dev/null 2>&1 || { echo "topology-e2e: curl is required" >&2; exit 2; }
command -v kubectl >/dev/null 2>&1 || { echo "topology-e2e: kubectl is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "topology-e2e: python3 is required" >&2; exit 2; }

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/kubecompass-topology.XXXXXX")
kubeconfig_path="$work_dir/kubeconfig"
kind_bin="$work_dir/kind"
cluster_name="kc-topology-${RANDOM}-$$"
cluster_created=0

cleanup() {
  local status=$?
  if (( cluster_created == 1 )); then
    KUBECONFIG="$kubeconfig_path" "$kind_bin" delete cluster --name "$cluster_name" >/dev/null 2>&1 || \
      echo "topology-e2e: warning: kind cleanup failed for $cluster_name" >&2
  fi
  rm -rf "$work_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

host_os=$(uname -s | tr '[:upper:]' '[:lower:]')
host_arch=$(uname -m)
case "$host_os" in
  darwin|linux) ;;
  *) echo "topology-e2e: unsupported host OS: $host_os" >&2; exit 2 ;;
esac
case "$host_arch" in
  arm64|aarch64) host_arch=arm64 ;;
  amd64|x86_64) host_arch=amd64 ;;
  *) echo "topology-e2e: unsupported host architecture: $host_arch" >&2; exit 2 ;;
esac

kind_asset="kind-${host_os}-${host_arch}"
kind_url="https://github.com/kubernetes-sigs/kind/releases/download/${kind_version}/${kind_asset}"
echo "topology-e2e: downloading ${kind_version} (${host_os}/${host_arch}) into a temporary directory"
curl -fsSL --retry 3 "$kind_url" -o "$kind_bin"
checksums_url="https://github.com/kubernetes-sigs/kind/releases/download/${kind_version}/${kind_asset}.sha256sum"
curl -fsSL --retry 3 "$checksums_url" -o "$work_dir/checksum.txt"
expected_sha=$(awk 'NF {print $1; exit}' "$work_dir/checksum.txt")
[[ "$expected_sha" =~ ^[[:xdigit:]]{64}$ ]] || {
  echo "topology-e2e: no valid checksum found for $kind_asset" >&2
  exit 1
}
if command -v sha256sum >/dev/null 2>&1; then
  actual_sha=$(sha256sum "$kind_bin" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  actual_sha=$(shasum -a 256 "$kind_bin" | awk '{print $1}')
else
  echo "topology-e2e: sha256sum or shasum is required" >&2
  exit 2
fi
[[ "$actual_sha" == "$expected_sha" ]] || {
  echo "topology-e2e: checksum mismatch for $kind_asset" >&2
  exit 1
}
chmod 700 "$kind_bin"

echo "topology-e2e: creating disposable cluster $cluster_name"
cluster_created=1
KUBECONFIG="$kubeconfig_path" "$kind_bin" create cluster \
  --name "$cluster_name" \
  --image "$node_image" \
  --kubeconfig "$kubeconfig_path" \
  --wait 90s

kubectl_fixture() {
  kubectl --kubeconfig "$kubeconfig_path" "$@"
}
apply_fixture() {
  kubectl_fixture apply --filename "$1" >/dev/null
}
assert_eq() {
  local label=$1 expected=$2 actual=$3
  if [[ "$actual" != "$expected" ]]; then
    echo "topology-e2e: assertion failed: $label (expected '$expected', got '$actual')" >&2
    exit 1
  fi
  echo "topology-e2e: PASS $label"
}

apply_fixture "$fixture_dir/00-namespace.yaml"
apply_fixture "$fixture_dir/10-workloads.yaml"
apply_fixture "$fixture_dir/20-services.yaml"
apply_fixture "$fixture_dir/30-networking.yaml"
apply_fixture "$fixture_dir/40-endpoints.yaml"
apply_fixture "$fixture_dir/60-rbac.yaml"

if kubectl_fixture get storageclass -o name 2>/dev/null | grep -q .; then
  apply_fixture "$fixture_dir/50-storage.yaml"
  echo "topology-e2e: StorageClass detected; PVC fixture applied"
else
  echo "topology-e2e: no StorageClass detected; PVC fixture skipped"
fi

if kubectl_fixture api-resources --api-group=gateway.networking.k8s.io -o name 2>/dev/null | grep -Eq 'gatewayclasses|gateways|httproutes'; then
  apply_fixture "$fixture_dir/70-gateway-api.yaml"
  echo "topology-e2e: Gateway API detected; Gateway fixtures applied"
else
  echo "topology-e2e: Gateway API unavailable; Gateway fixtures skipped"
fi

kubectl_fixture wait --for=condition=available deployment/kc-web -n "$namespace" --timeout=120s >/dev/null
kubectl_fixture wait --for=jsonpath='{.status.readyReplicas}'=2 deployment/kc-web -n "$namespace" --timeout=120s >/dev/null

assert_eq "namespace" "$namespace" "$(kubectl_fixture get namespace "$namespace" -o jsonpath='{.metadata.name}')"
assert_eq "named Service port" "https" "$(kubectl_fixture get service kc-web -n "$namespace" -o jsonpath='{.spec.ports[0].name}')"
assert_eq "Service targetPort" "web" "$(kubectl_fixture get service kc-web -n "$namespace" -o jsonpath='{.spec.ports[0].targetPort}')"
assert_eq "Service port" "443" "$(kubectl_fixture get service kc-web -n "$namespace" -o jsonpath='{.spec.ports[0].port}')"
assert_eq "NodePort" "30080" "$(kubectl_fixture get service kc-nodeport -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}')"
assert_eq "headless Service" "None" "$(kubectl_fixture get service kc-headless -n "$namespace" -o jsonpath='{.spec.clusterIP}')"
assert_eq "selectorless Service selector" "" "$(kubectl_fixture get service kc-external -n "$namespace" -o jsonpath='{.spec.selector}')"
assert_eq "manual external endpoint" "192.0.2.10" "$(kubectl_fixture get endpointslice kc-external-manual -n "$namespace" -o jsonpath='{.endpoints[0].addresses[0]}')"
assert_eq "duplicate Ingress route count" "2" "$(kubectl_fixture get ingress -n "$namespace" -o jsonpath='{range .items[*]}{.spec.rules[0].host}{"/"}{.spec.rules[0].http.paths[0].path}{"\n"}{end}' | grep -c '^demo.kubecompass.test//orders$')"
assert_eq "NetworkPolicy endPort" "8450" "$(kubectl_fixture get networkpolicy kc-web-policy -n "$namespace" -o jsonpath='{.spec.ingress[0].ports[0].endPort}')"

not_ready_slice=$(kubectl_fixture get endpointslice -n "$namespace" -l kubernetes.io/service-name=kc-not-ready -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -Fx 'false' | head -n 1 || true)
assert_eq "not-ready EndpointSlice evidence" "false" "$not_ready_slice"

if token=$(kubectl_fixture -n "$namespace" create token kc-topology-denied --duration=10m 2>/dev/null); then
  server=$(kubectl_fixture config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  ca_data=$(kubectl_fixture config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
  denied_kubeconfig="$work_dir/denied-kubeconfig"
  printf '%s' "$token" | python3 -c '
import json, sys
path, server, ca_data, namespace = sys.argv[1:]
token = sys.stdin.read()
config = {
    "apiVersion": "v1",
    "kind": "Config",
    "current-context": "denied",
    "clusters": [{"name": "kc-topology", "cluster": {"server": server, "certificate-authority-data": ca_data}}],
    "users": [{"name": "kc-topology-denied", "user": {"token": token}}],
    "contexts": [{"name": "denied", "context": {"cluster": "kc-topology", "user": "kc-topology-denied", "namespace": namespace}}],
}
with open(path, "w", encoding="utf-8") as output:
    json.dump(config, output)
' "$denied_kubeconfig" "$server" "$ca_data" "$namespace"
  chmod 600 "$denied_kubeconfig"
  denied_result=$(KUBECONFIG="$denied_kubeconfig" kubectl auth can-i list services -n "$namespace" || true)
  assert_eq "RBAC-denied Service list" "no" "$denied_result"
else
  echo "topology-e2e: SKIP RBAC token assertion (cluster does not support ServiceAccount token creation)"
fi

echo "topology-e2e: all semantic assertions passed; cleanup will now delete $cluster_name"
