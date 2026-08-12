#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="${ENGINEER_INTERFACES_VALIDATOR:-/Users/hamardikan-mac/.codex/skills/engineer-interfaces/scripts/validate_interface.py}"
interface_file="$repo_root/docs/interface/kubecompass.interface.json"

if [[ ! -f "$validator" ]]; then
  echo "ERROR: canonical engineer-interfaces validator not found: $validator" >&2
  exit 2
fi
if [[ ! -f "$interface_file" ]]; then
  echo "ERROR: Interface IR not found: $interface_file" >&2
  exit 2
fi

exec python3 "$validator" "$interface_file"
