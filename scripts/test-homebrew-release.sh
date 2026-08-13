#!/usr/bin/env bash
# Non-mutating probes for Homebrew release safety guards.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/scripts/prepare-homebrew-cask.sh"
release="$repo_root/scripts/release.sh"

grep -Fq 'KUBECOMPASS_HOMEBREW_CASK_PATH is not accepted by release.sh' "$release"
legacy_tap_assignment="cask_output=\${KUBECOMPASS_HOMEBREW_CASK_PATH"
if grep -Fq "$legacy_tap_assignment" "$release"; then
    echo 'error: release still permits tap-path cask output' >&2
    exit 1
fi

probe_rejected_repository() {
    local repository=$1 output rc
    if output=$(KUBECOMPASS_HOMEBREW_REPOSITORY="$repository" \
        "$helper" --dmg /tmp/kubecompass-missing.dmg --version 1.4.0 \
        --receipt /tmp/kubecompass-missing.json 2>&1); then
        echo "error: unsafe repository was accepted: $repository" >&2
        return 1
    else
        rc=$?
    fi
    [ "$rc" -ne 0 ] || return 1
    case "$output" in
        *"owner/repo"*|*"invalid GitHub repository"*) ;;
        *)
            echo "error: unsafe repository failed for the wrong reason: $repository" >&2
            printf '%s\n' "$output" >&2
            return 1
            ;;
    esac
}

probe_rejected_repository 'evil;touch/pwned'
probe_rejected_repository 'owner/repo/extra'
probe_rejected_repository 'owner/repo name'
probe_rejected_repository '/repo'

if output=$(KUBECOMPASS_HOMEBREW_REPOSITORY='hmrdkn-labs/kubecompass' \
    "$helper" --dmg /tmp/kubecompass-missing.dmg --version 1.4.0 \
    --receipt /tmp/kubecompass-missing.json 2>&1); then
    echo 'error: missing-DMG probe unexpectedly succeeded' >&2
    exit 1
else
    rc=$?
fi
[ "$rc" -ne 0 ]
case "$output" in
    *"DMG not found"*) ;;
    *)
        echo 'error: valid repository did not reach DMG guard' >&2
        printf '%s\n' "$output" >&2
        exit 1
        ;;
esac

probe_fake_mount() {
    local test_root fixture stub_bin dmg receipt output_path sha256 result
    test_root=$(mktemp -d)
    fixture="$test_root/fixture"
    stub_bin="$test_root/bin"
    dmg="$test_root/KubeCompass-1.4.0.dmg"
    receipt="$test_root/release.json"
    output_path="$test_root/generated.cask.rb"
    mkdir -p "$fixture/KubeCompass.app/Contents/MacOS" \
        "$fixture/KubeCompass.app/Contents/Helpers" \
        "$fixture/KubeCompass.app/Contents/Resources" "$stub_bin"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.kubecompass.app</string></dict></plist>' \
        > "$fixture/KubeCompass.app/Contents/Info.plist"
    printf '%s\n' 'fixture app' > "$fixture/KubeCompass.app/Contents/MacOS/KubeCompass"
    printf '%s\n' 'fixture kubectl' > "$fixture/KubeCompass.app/Contents/Helpers/kubectl"
    printf '%s\n' 'Apache License Version 2.0' > "$fixture/KubeCompass.app/Contents/Resources/kubectl-LICENSE"
    chmod 0755 "$fixture/KubeCompass.app/Contents/MacOS/KubeCompass" \
        "$fixture/KubeCompass.app/Contents/Helpers/kubectl"
    printf '%s\n' 'fixture-dmg' > "$dmg"
    cat > "$stub_bin/hdiutil" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = attach ]; then
    mountpoint=
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -mountpoint ]; then mountpoint=$2; shift 2; else shift; fi
    done
    cp -R "$KUBECOMPASS_TEST_FIXTURE/KubeCompass.app" "$mountpoint/"
fi
STUB
    cat > "$stub_bin/lipo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' 'arm64 x86_64'
STUB
    cat > "$stub_bin/xcrun" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat > "$stub_bin/spctl" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod 0755 "$stub_bin/hdiutil" "$stub_bin/lipo" "$stub_bin/xcrun" "$stub_bin/spctl"
    sha256=$(shasum -a 256 "$dmg" | awk '{print $1}')
    python3 - "$receipt" "$sha256" <<'PY'
import json
import sys

path, sha256 = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({
        "artifact": "KubeCompass-1.4.0.dmg",
        "version": "1.4.0",
        "sha256": sha256,
        "notarized": True,
        "stapler_validated": True,
        "spctl_assessed": True,
        "bundle_identifier": "dev.kubecompass.app",
        "kubectl_license": True,
        "app_arches": "arm64 x86_64",
        "kubectl_arches": "arm64 x86_64",
    }, handle)
PY
    if ! result=$(PATH="$stub_bin:$PATH" KUBECOMPASS_TEST_FIXTURE="$fixture" \
        "$helper" --dmg "$dmg" --version 1.4.0 --receipt "$receipt" \
        --output "$output_path" 2>&1); then
        printf '%s\n' "$result" >&2
        rm -rf "$test_root"
        return 1
    fi
    [ -s "$output_path" ] || { rm -rf "$test_root"; return 1; }
    if result=$(PATH="$stub_bin:$PATH" KUBECOMPASS_TEST_FIXTURE="$fixture" \
        "$helper" --dmg "$dmg" --version 1.4.0 --receipt "$receipt" \
        --output "$dmg" 2>&1); then
        echo 'error: DMG/output collision was accepted' >&2
        rm -rf "$test_root"
        return 1
    fi
    case "$result" in
        *'must not overwrite the DMG'*) ;;
        *)
            printf '%s\n' "$result" >&2
            rm -rf "$test_root"
            return 1
            ;;
    esac
    if result=$(PATH="$stub_bin:$PATH" KUBECOMPASS_TEST_FIXTURE="$fixture" \
        "$helper" --dmg "$dmg" --version 1.4.0 --receipt "$receipt" \
        --output "$receipt" 2>&1); then
        echo 'error: receipt/output collision was accepted' >&2
        rm -rf "$test_root"
        return 1
    fi
    case "$result" in
        *'must not overwrite the release receipt'*) ;;
        *)
            printf '%s\n' "$result" >&2
            rm -rf "$test_root"
            return 1
            ;;
    esac
    rm -rf "$test_root"
}

probe_fake_mount

echo 'homebrew_release_safety_probes=passed'
