# Homebrew cask

`kubecompass.rb` is updated only after the exact final DMG has been uploaded
and tagged as a GitHub release asset. The default release flow stages a cask
under `build/` and leaves this tracked path as a non-publishable marker.

After the release asset exists, run
`scripts/prepare-homebrew-cask.sh --dmg ... --version ... --receipt ...
--output packaging/homebrew/kubecompass.rb` with the staged receipt. The
helper verifies the receipt, exact DMG SHA-256, universal slices, bundle
identity, and bundled kubectl license before writing the tap cask.
An explicit output path authorizes only that local write; it does not verify
GitHub asset upload or URL reachability.

Do not publish or manually edit the generated cask. A cask generated from a
local (`SKIP_NOTARIZE=1`) DMG is not a public release artifact.
