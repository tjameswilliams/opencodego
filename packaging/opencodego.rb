# Homebrew cask for the Go for OpenCode Mac companion.
#
# Lives here as the source of truth; stamp the version and sha256 after a
# release, then copy the file into the tap repo
# (tjameswilliams/homebrew-tap → Casks/opencodego.rb), which is what
# `brew install --cask tjameswilliams/tap/opencodego` reads.
#
# auto_updates true tells brew this app updates itself (via Sparkle), so
# `brew upgrade` leaves it alone rather than fighting the in-app updater.
cask "opencodego" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://goforopencode.com/downloads/GoForOpenCode.dmg"
  name "Go for OpenCode"
  desc "Drive the OpenCode coding agent on your Mac from your iPhone"
  homepage "https://goforopencode.com"

  auto_updates true
  depends_on macos: ">= :sonoma"
  # The companion drives the OpenCode CLI; without it there's nothing to run.
  depends_on formula: "opencode"

  app "Go for OpenCode.app"

  zap trash: [
    "~/Library/Application Support/OpenCodeGo",
    "~/Library/Caches/com.timwilliams.opencodego.mac",
    "~/Library/Preferences/com.timwilliams.opencodego.mac.plist",
  ]
end
