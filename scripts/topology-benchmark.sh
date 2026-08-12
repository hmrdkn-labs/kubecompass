#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sample_count="${KUBECOMPASS_BENCHMARK_SAMPLES:-3}"
wall_seconds="${KUBECOMPASS_BENCHMARK_WALL_SECONDS:-180}"
log_file="$(mktemp "${TMPDIR:-/tmp}/kubecompass-topology-benchmark.log.XXXXXX")"
build_path="$(mktemp -d "${TMPDIR:-/tmp}/kubecompass-topology-build.XXXXXX")"
trap 'rm -f "$log_file"; rm -rf "$build_path"' EXIT

if ! [[ "$sample_count" =~ ^[0-9]+$ ]] || (( sample_count < 3 || sample_count > 25 )); then
  echo "KUBECOMPASS_BENCHMARK_SAMPLES must be an integer between 3 and 25" >&2
  exit 2
fi
if ! [[ "$wall_seconds" =~ ^[0-9]+$ ]] || (( wall_seconds < 30 || wall_seconds > 900 )); then
  echo "KUBECOMPASS_BENCHMARK_WALL_SECONDS must be an integer between 30 and 900" >&2
  exit 2
fi

echo "Running full release topology benchmark (100/1k/10k; one 10k sample per metric) with $sample_count samples for smaller cases; wall cap ${wall_seconds}s..." >&2
if ! python3 - "$repo_root" "$build_path" "$log_file" "$sample_count" "$wall_seconds" <<'PY'
import os
import signal
import subprocess
import sys

repo_root, build_path, log_path, sample_count, wall_seconds = sys.argv[1:]
command = ["swift", "test", "--configuration", "release", "--build-path", build_path, "--filter", "TopologyPerformanceTests/testTopologyBenchmarkEmitsJSON"]
environment = os.environ.copy()
environment["KUBECOMPASS_BENCHMARK_PROFILE"] = "full"
environment["KUBECOMPASS_BENCHMARK_SAMPLES"] = sample_count
with open(log_path, "w", encoding="utf-8") as log:
    process = subprocess.Popen(command, cwd=repo_root, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        status = process.wait(timeout=int(wall_seconds))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        print(f"topology benchmark exceeded {wall_seconds}s and was terminated", file=sys.stderr)
        status = 124
sys.stderr.write(open(log_path, encoding="utf-8").read())
sys.exit(status)
PY
then
  echo "topology benchmark test failed; full log follows:" >&2
  sed -n '1,240p' "$log_file" >&2
  exit 1
fi

json_line="$(grep -F 'KUBECOMPASS_TOPOLOGY_BENCHMARK_JSON=' "$log_file" | tail -n 1 || true)"
if [[ -z "$json_line" ]]; then
  echo "benchmark completed without a JSON marker; full log: $log_file" >&2
  exit 1
fi

json="${json_line#KUBECOMPASS_TOPOLOGY_BENCHMARK_JSON=}"
if ! python3 -c 'import json, sys; json.load(sys.stdin)' <<<"$json"; then
  echo "benchmark emitted invalid JSON" >&2
  exit 1
fi

printf '%s\n' "$json"
