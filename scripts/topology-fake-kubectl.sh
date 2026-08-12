#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bundle_path="${KUBECOMPASS_TOPOLOGY_FAKE_BUNDLE:-$script_dir/fixtures/topology/fake/topology.json}"

exec python3 - "$bundle_path" "$@" <<'PY'
import json
import os
import sys
from typing import Any


bundle_path = sys.argv[1]
argv = sys.argv[2:]
with open(bundle_path, encoding="utf-8") as stream:
    bundle = json.load(stream)
resources = bundle["resources"]


ALIASES = {
    "namespace": "namespaces",
    "namespaces": "namespaces",
    "node": "nodes",
    "nodes": "nodes",
    "deployment": "deployments",
    "deployments": "deployments",
    "deployments.apps": "deployments",
    "replicaset": "replicasets",
    "replicasets": "replicasets",
    "replicasets.apps": "replicasets",
    "statefulsets.apps": "statefulsets",
    "daemonsets.apps": "daemonsets",
    "jobs.batch": "jobs",
    "cronjobs.batch": "cronjobs",
    "pod": "pods",
    "pods": "pods",
    "service": "services",
    "services": "services",
    "endpointslice": "endpointslices",
    "endpointslices": "endpointslices",
    "endpointslices.discovery.k8s.io": "endpointslices",
    "ingress": "ingresses",
    "ingresses": "ingresses",
    "ingresses.networking.k8s.io": "ingresses",
    "networkpolicy": "networkpolicies",
    "networkpolicies": "networkpolicies",
    "networkpolicies.networking.k8s.io": "networkpolicies",
    "persistentvolumeclaim": "persistentvolumeclaims",
    "persistentvolumeclaims": "persistentvolumeclaims",
    "persistentvolume": "persistentvolumes",
    "persistentvolumes": "persistentvolumes",
    "storageclass": "storageclasses",
    "storageclasses": "storageclasses",
    "storageclasses.storage.k8s.io": "storageclasses",
    "gatewayclasses.gateway.networking.k8s.io": "gatewayclasses.gateway.networking.k8s.io",
    "gateways.gateway.networking.k8s.io": "gateways.gateway.networking.k8s.io",
    "httproutes.gateway.networking.k8s.io": "httproutes.gateway.networking.k8s.io",
    "gatewayclass": "gatewayclasses.gateway.networking.k8s.io",
    "gateway": "gateways.gateway.networking.k8s.io",
    "httproute": "httproutes.gateway.networking.k8s.io",
}


def json_output(value: Any) -> None:
    sys.stdout.write(json.dumps(value, separators=(",", ":")) + "\n")


def option_value(args: list[str], names: tuple[str, ...]) -> str | None:
    for index, value in enumerate(args):
        if value in names and index + 1 < len(args):
            return args[index + 1]
        for name in names:
            prefix = name + "="
            if value.startswith(prefix):
                return value[len(prefix):]
    return None


def resource_key(kind: str) -> str:
    return ALIASES.get(kind.lower(), kind.lower())


def filtered_args(args: list[str]) -> list[str]:
    result: list[str] = []
    skip_next = False
    value_options = {
        "--context", "--kubeconfig", "-n", "--namespace", "-o", "--output",
        "--field-selector", "-l", "--selector", "--request-timeout",
    }
    for value in args:
        if skip_next:
            skip_next = False
            continue
        if value in value_options:
            skip_next = True
            continue
        if any(value.startswith(option + "=") for option in value_options):
            continue
        if value in {"--all-namespaces", "--watch", "--output-watch-events", "--ignore-not-found"}:
            continue
        result.append(value)
    return result


def run(command: list[str]) -> tuple[int, str, str]:
    if command[:2] == ["config", "view"]:
        return 0, json.dumps({
            "apiVersion": "v1",
            "kind": "Config",
            "current-context": "kc-fixture",
            "clusters": [{"name": "kc-fixture", "cluster": {"server": "https://fixture.invalid"}}],
            "users": [{"name": "kc-fixture", "user": {}}],
            "contexts": [{"name": "kc-fixture", "context": {
                "cluster": "kc-fixture",
                "user": "kc-fixture",
                "namespace": "kc-topology",
            }}],
        }, separators=(",", ":")) + "\n", ""
    if command[:2] == ["config", "get-contexts"]:
        return 0, "\n".join(bundle["contexts"]) + "\n", ""
    if command[:1] == ["version"]:
        return 0, "Client Version: v1.31.0-kubecompass-fixture\n", ""
    if command[:1] == ["api-resources"]:
        return 0, "NAME\nservices\ningresses\nendpointslices\n", ""
    if command[:2] == ["auth", "can-i"]:
        # This fixture intentionally represents the restricted ServiceAccount.
        return 0, "no\n", ""
    if command[:1] != ["get"] or len(command) < 2:
        return 2, "", "fake-kubectl only supports config, version, api-resources, auth can-i and get\n"

    kind = command[1]
    key = resource_key(kind)
    if key.startswith(("gatewayclasses", "gateways.", "httproutes.")) and os.environ.get("KUBECOMPASS_FAKE_GATEWAY_UNAVAILABLE") == "1":
        return 1, "", "the server could not find the requested resource: " + kind + "\n"
    if key not in resources:
        return 1, "", "the server could not find the requested resource: " + kind + "\n"

    items = list(resources[key])
    selectors = option_value(command, ("-l", "--selector"))
    if selectors:
        pairs = [part.split("=", 1) for part in selectors.split(",") if "=" in part]
        items = [item for item in items if all(item.get("metadata", {}).get("labels", {}).get(k) == v for k, v in pairs)]
    names = [value for value in filtered_args(command[2:]) if not value.startswith("-")]
    if names:
        requested = names[0]
        items = [item for item in items if item.get("metadata", {}).get("name") == requested]

    if names and len(items) == 1:
        return 0, json.dumps(items[0], separators=(",", ":")) + "\n", ""
    api_version = items[0].get("apiVersion", "v1") if items else "v1"
    kind_name = items[0].get("kind", kind.title()) + "List" if items else "List"
    return 0, json.dumps({"apiVersion": api_version, "kind": kind_name, "items": items}, separators=(",", ":")) + "\n", ""


def self_test() -> int:
    checks = [
        (["config", "view", "--output", "json"], 0, lambda out: '"current-context":"kc-fixture"' in out and '"namespace":"kc-topology"' in out),
        (["config", "get-contexts", "--output", "name"], 0, lambda out: out.strip() == "kc-fixture"),
        (["get", "services", "-o", "json", "--context", "kc-fixture", "-n", "kc-topology"], 0, lambda out: "kc-web" in out and "kc-nodeport" in out),
        (["get", "deployments.apps", "-o", "json", "-n", "kc-topology"], 0, lambda out: "kc-web" in out),
        (["get", "endpointslices.discovery.k8s.io", "-o", "json", "-n", "kc-topology"], 0, lambda out: "192.0.2.10" in out and '"ready":false' in out),
        (["get", "networkpolicies", "-o", "json", "-n", "kc-topology"], 0, lambda out: '"endPort":8450' in out),
        (["get", "httproutes.gateway.networking.k8s.io", "-o", "json", "-n", "kc-topology"], 0, lambda out: "kc-orders" in out),
        (["auth", "can-i", "list", "services", "-n", "kc-topology"], 0, lambda out: out.strip() == "no"),
    ]
    forbidden = ("secret-literal", "password", "token", "api_key")
    for command, expected_code, predicate in checks:
        code, stdout, stderr = run(command)
        if code != expected_code or not predicate(stdout) or any(value in stdout.lower() for value in forbidden):
            sys.stderr.write("fake-kubectl self-test failed: " + " ".join(command) + "\n")
            return 1
    print(f"topology-fake-kubectl: self-test passed ({len(checks)} checks)")
    return 0


if argv == ["--self-test"]:
    raise SystemExit(self_test())

exit_code, stdout, stderr = run(argv)
sys.stdout.write(stdout)
sys.stderr.write(stderr)
raise SystemExit(exit_code)
PY
