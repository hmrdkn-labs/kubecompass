#!/usr/bin/env bash
# Writes site/data/github.json from read-only gh calls. The page draws from this snapshot only.
# If any call fails the old file stays in place. A value the API does not return stays null and
# the page renders "No data" for it. A release list that succeeds but is empty is
# {"tag": null}, which the page renders as "No release yet".
set -euo pipefail
repo="${KC_REPO:-hmrdkn-labs/kubecompass}"
out="$(cd "$(dirname "$0")/.." && pwd)/data/github.json"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

run="$(gh run list --repo "$repo" --branch main --event push --limit 1 --json name,conclusion,status,createdAt,url)"
commit="$(gh api "repos/$repo/commits/main")"
rel="$(gh release list --repo "$repo" --limit 1 --json tagName,publishedAt)"
meta="$(gh api "repos/$repo")"

jq -n --arg repo "$repo" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson run "$run" --argjson commit "$commit" --argjson rel "$rel" --argjson meta "$meta" '{
  generated_at: $at,
  repo: $repo,
  ci: ($run[0] // null | if . then {name, conclusion, status, created_at: .createdAt, url} else null end),
  commit: ($commit | if .sha then {sha: .sha[0:7], date: .commit.committer.date} else null end),
  release: ($rel[0] // null | if . then {tag: .tagName, published_at: .publishedAt} else {tag: null, published_at: null} end),
  license: ($meta.license.spdx_id // null)
}' > "$tmp"
jq -e '.generated_at and .repo' "$tmp" > /dev/null
mv "$tmp" "$out"
echo "wrote $out"
