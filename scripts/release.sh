#!/bin/bash
# Build, Developer ID-sign, notarize, and package KubeCompass for macOS.
#
# This script intentionally has no Sparkle/appcast step: KubeCompass does not
# reuse the upstream K-Dex update feed or signing keys.
set -euo pipefail
cd "$(dirname "$0")/.."

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

if [ -x "$app/Contents/Helpers/kubectl" ]; then
    codesign --force --timestamp --options runtime --sign "$identity" \
        "$app/Contents/Helpers/kubectl"
fi
codesign --force --timestamp --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/KubeCompass.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname KubeCompass -srcfolder "$stage" -ov -format UDZO "$dmg" -quiet
codesign --force --timestamp --sign "$identity" "$dmg"

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
    profile=${KUBECOMPASS_NOTARY_PROFILE:-kubecompass-notary}
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$dmg"
fi

sha256=$(shasum -a 256 "$dmg" | awk '{print $1}')
printf '%s  %s\n' "$sha256" "$dmg"
echo "==> Done: $dmg"
