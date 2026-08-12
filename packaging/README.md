# Packaging KubeCompass

## macOS

The macOS target builds `KubeCompass.app`. Local development builds can disable
code signing; public distribution requires a Developer ID Application identity
and notarization profile:

```sh
xcrun notarytool store-credentials kubecompass-notary \
  --apple-id <apple-id> --team-id <team-id> --password <app-password>
scripts/release.sh
```

Set `KUBECOMPASS_NOTARY_PROFILE` to use another profile. `SKIP_NOTARIZE=1`
creates a signed local DMG but not a public release artifact. KubeCompass has no
update feed yet; the upstream K-Dex Sparkle feed and keys are intentionally not
used.

The app bundles a local `kubectl` when available. Set `KUBECOMPASS_KUBECTL` to
an explicit binary; `KDEX_KUBECTL` remains a temporary compatibility fallback.
The Apache-2.0 kubectl license is copied into the bundle.

## Linux

`scripts/build-linux.sh` builds and tests the native GTK/libadwaita fixture
slice in an official Swift 6.3 Ubuntu 24.04 container. The package script emits
an architecture-specific Debian package under `dist/` and verifies its content.

The Linux slice is visibly fixture-only. It does not bundle or execute kubectl,
read kubeconfig, load auth plugins, or claim full macOS feature parity.
The package ships both the inherited KubeCompass MIT notice and the pinned
Swift Adwaita MIT notice under `/usr/share/doc/kubecompass/`. Both notices are
also combined in Debian's retained `copyright` file because minimal container
images commonly exclude other documentation paths during installation.

## Homebrew

`packaging/homebrew/kubecompass.rb` is a release template only. Do not publish
it until a notarized KubeCompass DMG exists and its exact version, URL, and
SHA-256 have been inserted.
