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

Homebrew is the preferred distribution path after a public macOS release. The
release script requires `arm64` and `x86_64` app slices, notarizes the DMG,
staples and validates it, and runs a Gatekeeper assessment before staging
`build/KubeCompass-<version>.cask.rb` with the exact artifact SHA-256. The
release receipt also records the inspected bundle identifier, universal
slices, and bundled kubectl license. The tracked tap path is deliberately not
populated between releases rather than committed with fake version or
checksum values.

`scripts/prepare-homebrew-cask.sh` can regenerate the cask for a final DMG and
its required receipt must tie the exact DMG SHA-256 to successful notarization,
stapler/Gatekeeper checks, universal app/helper slices, `dev.kubecompass.app`,
and the Apache-2.0 kubectl license. It refuses local `SKIP_NOTARIZE=1`
artifacts because those are not public release artifacts. The machine-readable
release receipt is written under `build/release/` as
`KubeCompass-<version>.release.json`; the checksum is also emitted beside the
DMG as
`build/KubeCompass-<version>.dmg.sha256`.

Upload and tag the exact DMG as a GitHub release asset before updating a tap.
`scripts/release.sh` always stages under `build/` and rejects
`KUBECOMPASS_HOMEBREW_CASK_PATH`; it cannot rewrite the tracked marker. Only
after upload/tag, invoke the standalone helper with an explicit `--output`
tap path. An explicit output path only authorizes a local file write; it does
not prove that the GitHub asset exists or is reachable.
