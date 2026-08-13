#!/usr/bin/env bash
# Build, Developer ID-sign, notarize, and package KubeCompass for macOS.
#
# This script intentionally has no Sparkle/appcast step: KubeCompass does not
# reuse the upstream K-Dex update feed or signing keys.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "${KUBECOMPASS_HOMEBREW_CASK_PATH:-}" ]; then
    echo "error: KUBECOMPASS_HOMEBREW_CASK_PATH is not accepted by release.sh; update a tap only with the standalone helper after upload" >&2
    exit 1
fi

version=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' k-dex.xcodeproj/project.pbxproj | head -1)
identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)
if [ -z "$identity" ]; then
    echo "error: no Developer ID Application certificate found" >&2
    exit 1
fi

build_dir="$PWD/build/release"
app="$build_dir/KubeCompass.app"
dmg="$PWD/build/KubeCompass-$version.dmg"
rm -rf "$build_dir"
mkdir -p "$build_dir"

echo "==> Building KubeCompass $version"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -project k-dex.xcodeproj -scheme k-dex -configuration Release \
    -destination 'platform=macOS' CONFIGURATION_BUILD_DIR="$build_dir" build
test -d "$app" || { echo "error: build product missing: $app" >&2; exit 1; }
kubectl_helper="$app/Contents/Helpers/kubectl"
if [ ! -x "$kubectl_helper" ]; then
    echo "error: Release app is missing bundled executable: $kubectl_helper" >&2
    exit 1
fi
app_binary="$app/Contents/MacOS/KubeCompass"
if [ ! -x "$app_binary" ]; then
    echo "error: Release app is missing its executable: $app_binary" >&2
    exit 1
fi
archs_for() {
    lipo -archs "$1" 2>/dev/null | tr ',' ' '
}
has_arch() {
    local available=$1 wanted=$2 arch
    for arch in $available; do
        [ "$arch" = "$wanted" ] && return 0
    done
    return 1
}
validate_release_dmg() (
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
    mounted_app_binary="$mounted_app/Contents/MacOS/KubeCompass"
    mounted_kubectl_binary="$mounted_app/Contents/Helpers/kubectl"
    kubectl_license="$mounted_app/Contents/Resources/kubectl-LICENSE"
    info_plist="$mounted_app/Contents/Info.plist"
    [ -d "$mounted_app" ] || { echo "error: DMG is missing KubeCompass.app" >&2; exit 1; }
    [ -x "$mounted_app_binary" ] || { echo "error: DMG app executable is missing" >&2; exit 1; }
    [ -x "$mounted_kubectl_binary" ] || { echo "error: DMG bundled kubectl is missing" >&2; exit 1; }
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
    inspected_app_arches=$(archs_for "$mounted_app_binary")
    inspected_helper_arches=$(archs_for "$mounted_kubectl_binary")
    for arch in $required_archs; do
        has_arch "$inspected_app_arches" "$arch" || {
            echo "error: DMG app is missing universal slice: $arch" >&2
            exit 1
        }
        has_arch "$inspected_helper_arches" "$arch" || {
            echo "error: DMG kubectl is missing universal slice: $arch" >&2
            exit 1
        }
    done
    printf '%s\t%s\t%s\ttrue\n' \
        "$bundle_identifier" "$inspected_app_arches" "$inspected_helper_arches"
)
required_archs="arm64 x86_64"
app_archs=$(archs_for "$app_binary")
for arch in $required_archs; do
    if ! has_arch "$app_archs" "$arch"; then
        echo "error: Release app must contain $required_archs slices; found [$app_archs]" >&2
        exit 1
    fi
done
helper_archs=$(archs_for "$kubectl_helper")
for arch in $required_archs; do
    case " $helper_archs " in
        *" $arch "*) ;;
        *)
            echo "error: bundled kubectl [$helper_archs] does not cover app slice [$arch] ($app_archs)" >&2
            exit 1
            ;;
    esac
done
echo "==> Universal slices: app [$app_archs], kubectl [$helper_archs]"
codesign --force --timestamp --options runtime --sign "$identity" "$kubectl_helper"
codesign --force --timestamp --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/KubeCompass.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname KubeCompass -srcfolder "$stage" -ov -format UDZO "$dmg" -quiet
dmg_facts=$(validate_release_dmg)
IFS=$'\t' read -r bundle_identifier inspected_app_arches inspected_helper_arches kubectl_license_ok <<< "$dmg_facts"
codesign --force --timestamp --sign "$identity" "$dmg"

notarized=false
stapler_validated=false
spctl_assessed=false
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    profile=${KUBECOMPASS_NOTARY_PROFILE:-kubecompass-notary}
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    command -v spctl >/dev/null 2>&1 || {
        echo "error: spctl is required for post-notary Gatekeeper assessment" >&2
        exit 1
    }
    spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
    notarized=true
    stapler_validated=true
    spctl_assessed=true
else
    echo "==> Notarization skipped; no public Homebrew cask will be generated" >&2
fi

sha256=$(shasum -a 256 "$dmg" | awk '{print $1}')
checksum_file="$dmg.sha256"
printf '%s  %s\n' "$sha256" "$(basename "$dmg")" > "$checksum_file"

receipt="$build_dir/KubeCompass-$version.release.json"
cask_path=
if [ "$notarized" = true ]; then
    cask_output="$PWD/build/KubeCompass-$version.cask.rb"
    cask_path=${cask_output#"$PWD/"}
fi
command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 is required to write and validate the release receipt" >&2
    exit 1
}
python3 - "$receipt" "$(basename "$dmg")" "$version" "$sha256" \
    "$checksum_file" "$inspected_app_arches" "$inspected_helper_arches" \
    "$bundle_identifier" "$kubectl_license_ok" "$notarized" \
    "$stapler_validated" "$spctl_assessed" "$cask_path" <<'PY'
import json
import pathlib
import sys

(
    receipt_path,
    artifact,
    version,
    sha256,
    checksum_file,
    app_arches,
    kubectl_arches,
    bundle_identifier,
    kubectl_license,
    notarized,
    stapler_validated,
    spctl_assessed,
    cask_path,
) = sys.argv[1:]
receipt = {
    "schema_version": 1,
    "product": "KubeCompass",
    "version": version,
    "artifact": artifact,
    "sha256": sha256,
    "checksum_file": pathlib.Path(checksum_file).name,
    "app_arches": app_arches,
    "kubectl_arches": kubectl_arches,
    "bundle_identifier": bundle_identifier,
    "kubectl_license": kubectl_license == "true",
    "notarized": notarized == "true",
    "stapler_validated": stapler_validated == "true",
    "spctl_assessed": spctl_assessed == "true",
    "homebrew_cask": cask_path or None,
}
with open(receipt_path, "w", encoding="utf-8") as handle:
    json.dump(receipt, handle, indent=2, sort_keys=True)
    handle.write("\n")
with open(receipt_path, encoding="utf-8") as handle:
    parsed = json.load(handle)
if parsed != receipt:
    raise SystemExit("error: release receipt failed JSON round-trip validation")
PY

if [ "$notarized" = true ]; then
    scripts/prepare-homebrew-cask.sh \
        --dmg "$dmg" --version "$version" --receipt "$receipt" \
        --output "$cask_output" >/dev/null
fi
printf '%s  %s\n' "$sha256" "$dmg"
echo "==> Receipt: $receipt"
echo "==> Done: $dmg"
