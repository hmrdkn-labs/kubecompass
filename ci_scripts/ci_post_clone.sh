#!/bin/sh
# Xcode Cloud hook (runs after clone, before the build): download both official
# kubectl slices and install one checked universal helper on PATH. The Xcode
# build phase then uses the same release contract as local and GitHub builds.
set -eu

KUBECTL_VERSION="v1.36.3"
ARM64_SHA256="fc8582acde13869a606730a79379d6515f30c68afcced0b5ac8789d5d002b7d6"
X86_64_SHA256="158b3b46cf74e8b6bd9b1d7cd30f665e3efb2bc1ec3c843ec925bcfdd2930de0"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kubecompass-kubectl.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

download() {
    arch=$1
    expected=$2
    path="$TMP/kubectl-$arch"
    curl -fsSL --retry 3 -o "$path" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/darwin/${arch}/kubectl"
    echo "${expected}  ${path}" | shasum -a 256 -c -
    chmod 0755 "$path"
}

download arm64 "$ARM64_SHA256"
download amd64 "$X86_64_SHA256"
lipo -create "$TMP/kubectl-arm64" "$TMP/kubectl-amd64" -output "$TMP/kubectl"
chmod 0755 "$TMP/kubectl"
archs=$(lipo -archs "$TMP/kubectl")
case " $archs " in *" arm64 "*) ;; *) echo "error: universal helper is missing arm64" >&2; exit 1 ;; esac
case " $archs " in *" x86_64 "*) ;; *) echo "error: universal helper is missing x86_64" >&2; exit 1 ;; esac

mkdir -p /opt/homebrew/bin
install -m 0755 "$TMP/kubectl" /opt/homebrew/bin/kubectl
/opt/homebrew/bin/kubectl version --client
