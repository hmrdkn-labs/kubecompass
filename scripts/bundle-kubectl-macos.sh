#!/bin/bash
# Assemble and validate the kubectl helper embedded in KubeCompass.app.
#
# Release builds must receive either a universal helper via KUBECOMPASS_KUBECTL
# or both thin inputs via KUBECOMPASS_KUBECTL_ARM64 and
# KUBECOMPASS_KUBECTL_X86_64. Debug builds may use a host-compatible helper,
# but the warning is intentional: a thin helper is not a universal artifact.
set -euo pipefail

usage() {
    echo "usage: $0 OUTPUT_PATH LICENSE_PATH" >&2
    exit 2
}

[ "$#" -eq 2 ] || usage
output=$1
license=$2
configuration=${CONFIGURATION:-Debug}
required_archs=${KUBECOMPASS_KUBECTL_ARCHS:-${ARCHS:-}}

if [ -z "$required_archs" ] && [ "$configuration" = "Release" ]; then
    required_archs="arm64 x86_64"
fi

if ! command -v lipo >/dev/null 2>&1; then
    echo "error: lipo is required to assemble and validate macOS kubectl helpers" >&2
    exit 1
fi

archs_for() {
    local path=$1
    lipo -archs "$path" 2>/dev/null | tr ',' ' '
}

has_arch() {
    local available=$1 wanted=$2 arch
    for arch in $available; do
        [ "$arch" = "$wanted" ] && return 0
    done
    return 1
}

validate_archs() {
    local path=$1 available=$2 wanted
    for wanted in $required_archs; do
        if ! has_arch "$available" "$wanted"; then
            return 1
        fi
    done
    return 0
}

universal_input=${KUBECOMPASS_KUBECTL:-}
arm64_input=${KUBECOMPASS_KUBECTL_ARM64:-}
x86_64_input=${KUBECOMPASS_KUBECTL_X86_64:-${KUBECOMPASS_KUBECTL_AMD64:-}}
legacy_input=${KDEX_KUBECTL:-}

if [ -z "$universal_input" ] && [ -z "$arm64_input" ] && [ -z "$x86_64_input" ] && [ -z "$legacy_input" ]; then
    legacy_input=$(command -v kubectl 2>/dev/null || true)
fi

mkdir -p "$(dirname "$output")" "$(dirname "$license")"
mkdir -p "$(dirname "$output")/../Resources"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kubecompass-kubectl.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
assembled="$tmp_dir/kubectl"
source_path=

if [ -n "$universal_input" ]; then
    source_path=$universal_input
elif [ -n "$arm64_input" ] && [ -n "$x86_64_input" ]; then
    [ -x "$arm64_input" ] || { echo "error: arm64 kubectl is not executable: $arm64_input" >&2; exit 1; }
    [ -x "$x86_64_input" ] || { echo "error: x86_64 kubectl is not executable: $x86_64_input" >&2; exit 1; }
    lipo -create "$arm64_input" "$x86_64_input" -output "$assembled"
    chmod 0755 "$assembled"
    source_path=$assembled
elif [ "$configuration" = "Release" ]; then
    echo "error: Release requires KUBECOMPASS_KUBECTL or both KUBECOMPASS_KUBECTL_ARM64 and KUBECOMPASS_KUBECTL_X86_64" >&2
    exit 1
elif [ -n "$legacy_input" ]; then
    source_path=$legacy_input
fi

if [ -z "$source_path" ] || [ ! -x "$source_path" ]; then
    if [ "$configuration" = "Release" ]; then
        echo "error: Release app is missing an executable kubectl helper" >&2
        exit 1
    fi
    echo "warning: no kubectl found; Debug builds may resolve kubectl from PATH" >&2
    exit 0
fi

available_archs=$(archs_for "$source_path" || true)
if [ -z "$available_archs" ]; then
    echo "error: kubectl helper is not a readable Mach-O binary: $source_path" >&2
    exit 1
fi

if ! validate_archs "$source_path" "$available_archs"; then
    if [ "$configuration" = "Release" ]; then
        echo "error: kubectl helper architectures [$available_archs] do not cover app ARCHS [$required_archs]" >&2
        exit 1
    fi
    host_arch=$(uname -m)
    [ "$host_arch" = "amd64" ] && host_arch=x86_64
    if ! has_arch "$available_archs" "$host_arch"; then
        echo "error: Debug kubectl helper [$available_archs] is not compatible with host [$host_arch]" >&2
        exit 1
    fi
    echo "warning: Debug app ARCHS [$required_archs] exceed kubectl helper [$available_archs]; host [$host_arch] only" >&2
fi

cp -f "$source_path" "$output"
chmod 0755 "$output"
cp -f "$license" "$(dirname "$output")/../Resources/kubectl-LICENSE"

if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ] && command -v codesign >/dev/null 2>&1; then
    codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$output"
fi

echo "kubectl helper: $output ($available_archs)"
