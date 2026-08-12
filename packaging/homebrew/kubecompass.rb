# Release template. Replace VERSION and SHA256 only after producing and
# publishing one notarized KubeCompass DMG from the same release run.
cask "kubecompass" do
  version "VERSION"
  sha256 "SHA256"

  url "https://github.com/OWNER/kubecompass/releases/download/v#{version}/KubeCompass-#{version}.dmg"
  name "KubeCompass"
  desc "Native Kubernetes desktop client"
  homepage "https://github.com/OWNER/kubecompass"

  depends_on macos: ">= :tahoe"
  app "KubeCompass.app"

  zap trash: [
    "~/Library/Preferences/dev.kubecompass.app.plist",
    "~/Library/Saved Application State/dev.kubecompass.app.savedState",
  ]
end
