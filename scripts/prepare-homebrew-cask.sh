#!/usr/bin/env bash
# Generate a Homebrew cask from one final DMG and its release receipt.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${KUBECOMPASS_HOMEBREW_CASK_PATH:-}
repository=${KUBECOMPASS_HOMEBREW_REPOSITORY:-hmrdkn-labs/kubecompass}

usage() {
    cat >&2 <<'USAGE'
usage: prepare-homebrew-cask.sh --dmg PATH --version VERSION --receipt PATH [--output PATH]

The receipt must be produced by the release flow and tie this exact DMG to
notarization, Gatekeeper/stapler checks, universal slices, bundle identity,
and the bundled kubectl license. The DMG validation checks are repeated before
the cask is written.
USAGE
    exit 2
}

dmg=
version=
receipt=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dmg)
            [ "$#" -ge 2 ] || usage
            dmg=$2
            shift 2
            ;;
        --version)
            [ "$#" -ge 2 ] || usage
            version=$2
            shift 2
            ;;
        --receipt)
            [ "$#" -ge 2 ] || usage
            receipt=$2
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] || usage
            output=$2
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage
            ;;
    esac
done

[ -n "$dmg" ] || usage
[ -n "$version" ] || usage
[ -n "$receipt" ] || usage
if [ -z "$output" ]; then
    output="$repo_root/build/KubeCompass-$version.cask.rb"
fi
case "$version" in
    *[!A-Za-z0-9._-]*|"")
        echo "error: version contains unsupported characters: $version" >&2
        exit 1
        ;;
esac
if [[ "$repository" != */* || "$repository" == */*/* ]]; then
    echo "error: KUBECOMPASS_HOMEBREW_REPOSITORY must be exactly owner/repo" >&2
    exit 1
fi
repository_owner=${repository%%/*}
repository_name=${repository#*/}
case "$repository_owner" in
    ""|*[!A-Za-z0-9._-]*)
        echo "error: invalid GitHub repository owner" >&2
        exit 1
        ;;
esac
case "$repository_name" in
    ""|*[!A-Za-z0-9._-]*)
        echo "error: invalid GitHub repository name" >&2
        exit 1
        ;;
esac

[ -f "$dmg" ] || { echo "error: DMG not found: $dmg" >&2; exit 1; }
[ -f "$receipt" ] || { echo "error: release receipt not found: $receipt" >&2; exit 1; }
expected_name="KubeCompass-$version.dmg"
[ "$(basename "$dmg")" = "$expected_name" ] || {
    echo "error: DMG must be named $expected_name: $dmg" >&2
    exit 1
}

command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 is required to verify the release receipt" >&2
    exit 1
}

realpath_for() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}
dmg_realpath=$(realpath_for "$dmg")
output_realpath=$(realpath_for "$output")
receipt_realpath=$(realpath_for "$receipt")
if [ "$dmg_realpath" = "$output_realpath" ] || [ "$dmg_realpath" = "$receipt_realpath" ]; then
    echo "error: cask output/receipt must not overwrite the DMG" >&2
    exit 1
fi
if [ "$output_realpath" = "$receipt_realpath" ]; then
    echo "error: cask output must not overwrite the release receipt" >&2
    exit 1
fi
command -v xcrun >/dev/null 2>&1 || {
    echo "error: xcrun is required to validate a notarized DMG" >&2
    exit 1
}
command -v spctl >/dev/null 2>&1 || {
    echo "error: spctl is required to assess a notarized DMG" >&2
    exit 1
}
command -v hdiutil >/dev/null 2>&1 || {
    echo "error: hdiutil is required to inspect the release DMG" >&2
    exit 1
}
command -v lipo >/dev/null 2>&1 || {
    echo "error: lipo is required to inspect universal release binaries" >&2
    exit 1
}
command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 || {
    echo "error: PlistBuddy is required to inspect the app bundle" >&2
    exit 1
}

required_archs='arm64 x86_64'
inspect_dmg() (
    set -euo pipefail
    mount_dir=$(mktemp -d)
    mounted=false
    # shellcheck disable=SC2329
    cleanup_mount() {
        if [ "$mounted" = true ]; then
            hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
        fi
        rm -rf "$mount_dir"
    }
    trap cleanup_mount EXIT
    hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
    mounted=true
    mounted_app="$mount_dir/KubeCompass.app"
    app_binary="$mounted_app/Contents/MacOS/KubeCompass"
    kubectl_binary="$mounted_app/Contents/Helpers/kubectl"
    kubectl_license="$mounted_app/Contents/Resources/kubectl-LICENSE"
    info_plist="$mounted_app/Contents/Info.plist"
    [ -d "$mounted_app" ] || { echo "error: DMG is missing KubeCompass.app" >&2; exit 1; }
    [ -x "$app_binary" ] || { echo "error: DMG app executable is missing" >&2; exit 1; }
    [ -x "$kubectl_binary" ] || { echo "error: DMG bundled kubectl is missing" >&2; exit 1; }
    [ -f "$kubectl_license" ] || { echo "error: DMG bundled kubectl license is missing" >&2; exit 1; }
    grep -Fq 'Apache License' "$kubectl_license" || {
        echo "error: DMG kubectl license is not Apache-2.0 text" >&2
        exit 1
    }
    bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")
    [ "$bundle_identifier" = 'dev.kubecompass.app' ] || {
        echo "error: unexpected DMG bundle identifier: $bundle_identifier" >&2
        exit 1
    }
    app_arches=$(lipo -archs "$app_binary" 2>/dev/null | tr ',' ' ')
    kubectl_arches=$(lipo -archs "$kubectl_binary" 2>/dev/null | tr ',' ' ')
    for arch in $required_archs; do
        case " $app_arches " in *" $arch "*) ;; *) echo "error: DMG app is missing universal slice: $arch" >&2; exit 1 ;; esac
        case " $kubectl_arches " in *" $arch "*) ;; *) echo "error: DMG kubectl is missing universal slice: $arch" >&2; exit 1 ;; esac
    done
    printf '%s\t%s\t%s\ttrue\n' "$bundle_identifier" "$app_arches" "$kubectl_arches"
)

dmg_facts=$(inspect_dmg)
IFS=$'\t' read -r inspected_bundle_identifier inspected_app_arches inspected_kubectl_arches inspected_kubectl_license <<< "$dmg_facts"

sha256=$(shasum -a 256 "$dmg" | awk '{print $1}')
python3 - "$receipt" "$dmg" "$version" "$sha256" \
    "$inspected_bundle_identifier" "$inspected_app_arches" \
    "$inspected_kubectl_arches" "$inspected_kubectl_license" <<'PY'
import hashlib
import json
import pathlib
import sys

(
    receipt_path,
    dmg_path,
    version,
    sha256,
    inspected_bundle_identifier,
    inspected_app_arches,
    inspected_kubectl_arches,
    inspected_kubectl_license,
) = sys.argv[1:]
try:
    with open(receipt_path, encoding="utf-8") as handle:
        receipt = json.load(handle)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"error: invalid release receipt: {error}")

expected = {
    "artifact": pathlib.Path(dmg_path).name,
    "version": version,
    "sha256": sha256,
    "notarized": True,
    "stapler_validated": True,
    "spctl_assessed": True,
    "bundle_identifier": inspected_bundle_identifier,
    "kubectl_license": inspected_kubectl_license == "true",
}
for key, value in expected.items():
    if receipt.get(key) != value:
        raise SystemExit(f"error: release receipt mismatch for {key}")

for key in ("app_arches", "kubectl_arches"):
    available = set(str(receipt.get(key, "")).replace(",", " ").split())
    inspected = inspected_app_arches if key == "app_arches" else inspected_kubectl_arches
    if available != set(inspected.replace(",", " ").split()):
        raise SystemExit(f"error: release receipt does not match inspected {key}")

with open(dmg_path, "rb") as handle:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != sha256:
    raise SystemExit("error: DMG changed after receipt generation")
PY

xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"

mkdir -p "$(dirname "$output")"
tmp=$(mktemp "${output}.tmp.XXXXXX")
cleanup() {
    rm -f "$tmp"
}
trap cleanup EXIT
cat > "$tmp" <<EOF
# Generated by scripts/prepare-homebrew-cask.sh from a validated release DMG.
cask "kubecompass" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/$repository/releases/download/v#{version}/KubeCompass-#{version}.dmg"
  name "KubeCompass"
  desc "Native Kubernetes desktop client"
  homepage "https://github.com/$repository"

  depends_on macos: ">= :tahoe"
  app "KubeCompass.app"

  zap trash: [
    "~/Library/Preferences/dev.kubecompass.app.plist",
    "~/Library/Saved Application State/dev.kubecompass.app.savedState",
  ]
end
EOF
chmod 0644 "$tmp"
if [ -f "$output" ] && cmp -s "$tmp" "$output"; then
    rm -f "$tmp"
    trap - EXIT
else
    mv -f "$tmp" "$output"
    trap - EXIT
fi
printf 'homebrew_cask=%s\nsha256=%s\n' "$output" "$sha256"
