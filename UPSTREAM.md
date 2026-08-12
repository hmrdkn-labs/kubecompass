# Upstream provenance

KubeCompass was created from
[irfancen/k-dex](https://github.com/irfancen/k-dex) at commit
`12094525dcf12eb2b26c0b8bca0857362f2b4a95` on 2026-08-12. The local tag
`kubecompass-upstream-baseline-2026-08-12` records that boundary.

The inherited source is MIT licensed and retains the original 2026 irfancen
copyright notice in `LICENSE`. KubeCompass changes the product name, disables
the upstream Sparkle update feed, introduces a portable Swift package, and adds
a separately implemented native Linux GTK/libadwaita adapter.

The macOS distribution may bundle the upstream project's pinned `kubectl`
binary. `kubectl` is Apache-2.0 licensed; its complete notice is retained at
`packaging/kubectl-LICENSE`. Linux fixture packages do not bundle kubectl.
They do include the pinned Swift Adwaita MIT notice at
`packaging/linux/swift-adwaita-LICENSE`.

KubeCompass is an independent derivative project. It does not imply endorsement
by the K-Dex author, Kubernetes, or the Cloud Native Computing Foundation.
