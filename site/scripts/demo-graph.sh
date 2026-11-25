#!/usr/bin/env bash
# Rebuilds site/data/demo-graph.json from KubeCompassCore itself: compiles
# site/tools/demo-graph/main.swift together with Sources/KubeCompassCore and runs it.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
out="$root/site/data/demo-graph.json"
bin="${XDG_CACHE_HOME:-$HOME/.cache}/kubecompass-site/demo-graph"
mkdir -p "$(dirname "$bin")" "$(dirname "$out")"
swiftc -O -module-name DemoGraph "$root"/Sources/KubeCompassCore/*.swift "$root/site/tools/demo-graph/main.swift" -o "$bin"
tmp="$(mktemp)"
"$bin" > "$tmp"
jq -e '.nodes | length > 0' "$tmp" > /dev/null
mv "$tmp" "$out"
echo "wrote $out"
