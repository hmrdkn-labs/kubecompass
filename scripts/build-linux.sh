#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
container_arch=${KUBECOMPASS_CONTAINER_ARCH:-$(uname -m)}
case "$container_arch" in
  arm64|aarch64) container_arch=arm64 ;;
  amd64|x86_64) container_arch=amd64 ;;
  *) echo "unsupported container architecture: $container_arch" >&2; exit 2 ;;
esac

image=${KUBECOMPASS_SWIFT_IMAGE:-swift:6.3-noble}
mkdir -p "$repo_root/dist/linux/$container_arch"

docker run --rm --platform "linux/$container_arch" \
  -e KUBECOMPASS_CONTAINER_ARCH="$container_arch" \
  -v "$repo_root:/src" -w /src "$image" bash -eu -o pipefail -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends pkg-config libadwaita-1-dev libgtksourceview-5-dev xvfb dpkg-dev
    scratch=/tmp/kubecompass-swiftpm
    rm -rf "$scratch"
    swift package --scratch-path "$scratch" resolve
    swift test --disable-sandbox --scratch-path "$scratch"
    swift build -c release --product kubecompass-linux --static-swift-stdlib --scratch-path "$scratch"
    built_binary=$(find "$scratch" -type f -path "*/release/kubecompass-linux" -print -quit)
    test -n "$built_binary" -a -x "$built_binary"
    install -Dm755 "$built_binary" "dist/linux/$KUBECOMPASS_CONTAINER_ARCH/kubecompass-linux"
    ldd "dist/linux/$KUBECOMPASS_CONTAINER_ARCH/kubecompass-linux" | tee "dist/linux/$KUBECOMPASS_CONTAINER_ARCH/ldd.txt"
    if grep -q "libswift" "dist/linux/$KUBECOMPASS_CONTAINER_ARCH/ldd.txt"; then
      echo "error: static Swift stdlib verification failed" >&2
      exit 1
    fi
    mkdir -p /tmp/kubecompass-runtime
    chmod 700 /tmp/kubecompass-runtime
    dbus-run-session -- xvfb-run -a env GDK_BACKEND=x11 XDG_RUNTIME_DIR=/tmp/kubecompass-runtime \
      "$built_binary" --smoke
    KUBECOMPASS_DEB_ARCH="$KUBECOMPASS_CONTAINER_ARCH" \
      KUBECOMPASS_BINARY="/src/dist/linux/$KUBECOMPASS_CONTAINER_ARCH/kubecompass-linux" \
      scripts/package-linux.sh
  '

echo "built dist/linux/$container_arch/kubecompass-linux"
