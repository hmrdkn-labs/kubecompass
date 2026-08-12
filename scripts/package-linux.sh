#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
arch=${KUBECOMPASS_DEB_ARCH:-$(uname -m)}
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  amd64|x86_64) arch=amd64 ;;
  *) echo "unsupported package architecture: $arch" >&2; exit 2 ;;
esac
version=${KUBECOMPASS_VERSION:-0.2.0}
binary=${KUBECOMPASS_BINARY:-$repo_root/dist/linux/$arch/kubecompass-linux}
command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required (run inside Ubuntu/Debian)" >&2; exit 2; }
[ -x "$binary" ] || { echo "missing executable: $binary (run scripts/build-linux.sh first)" >&2; exit 2; }

mkdir -p "$repo_root/dist/linux/$arch"
if ldd "$binary" | tee "$repo_root/dist/linux/$arch/ldd-package.txt" | grep -q 'libswift'; then
  echo "error: binary contains a dynamic Swift runtime; rebuild with --static-swift-stdlib" >&2
  exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
install -Dm755 "$binary" "$stage/usr/bin/kubecompass"
ln -s kubecompass "$stage/usr/bin/kc"
install -Dm644 "$repo_root/packaging/linux/com.kubecompass.KubeCompass.desktop" \
  "$stage/usr/share/applications/com.kubecompass.KubeCompass.desktop"
install -Dm644 "$repo_root/packaging/linux/com.kubecompass.KubeCompass.metainfo.xml" \
  "$stage/usr/share/metainfo/com.kubecompass.KubeCompass.metainfo.xml"
install -Dm644 "$repo_root/packaging/linux/kubecompass.svg" \
  "$stage/usr/share/icons/hicolor/scalable/apps/kubecompass.svg"
install -Dm644 "$repo_root/LICENSE" "$stage/usr/share/doc/kubecompass/copyright"
{
  printf '\n\nThird-party notice: Swift Adwaita\n\n'
  cat "$repo_root/packaging/linux/swift-adwaita-LICENSE"
} >> "$stage/usr/share/doc/kubecompass/copyright"
install -Dm644 "$repo_root/packaging/linux/swift-adwaita-LICENSE" \
  "$stage/usr/share/doc/kubecompass/swift-adwaita-LICENSE"
mkdir -p "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<EOF
Package: kubecompass
Version: $version
Section: devel
Priority: optional
Architecture: $(dpkg --print-architecture)
Depends: libadwaita-1-0 (>= 1.5), libgtk-4-1, libgtksourceview-5-0
Maintainer: KubeCompass contributors
Description: Native Kubernetes desktop compass
 Fixture-first Linux desktop shell for KubeCompass. This slice is demo-only
 and never executes kubectl or mutates a cluster.
EOF

mkdir -p "$repo_root/dist"
deb="$repo_root/dist/kubecompass_${version}_$arch.deb"
dpkg-deb --build --root-owner-group "$stage" "$deb"
dpkg-deb --info "$deb"
dpkg-deb --contents "$deb"
echo "created $deb"
