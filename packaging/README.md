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

Release packaging targets a universal (`arm64` + `x86_64`) macOS app. It
requires a bundled universal `kubectl`, supplied either as
`KUBECOMPASS_KUBECTL=/absolute/path/to/universal/kubectl` or as both
`KUBECOMPASS_KUBECTL_ARM64` and `KUBECOMPASS_KUBECTL_X86_64`. The build phase
uses `scripts/bundle-kubectl-macos.sh` to combine thin inputs with `lipo`, copy
the Apache-2.0 license, and validate that every app `ARCHS` slice is present.
Release packaging fails when the helper is thin or missing. `KDEX_KUBECTL`
remains a temporary compatibility fallback only for Debug builds.

The Xcode Cloud post-clone hook and GitHub Actions workflow fetch pinned
Kubernetes `v1.36.3` `darwin/arm64` and `darwin/amd64` binaries directly from
`dl.k8s.io`, verify their SHA-256 checksums, and assemble one universal helper;
neither path installs kubectl with Homebrew.

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
