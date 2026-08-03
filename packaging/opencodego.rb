# Homebrew cask for the OpenCode Go Mac companion.
#
# Lives here as the source of truth; scripts/publish.sh stamps the version
# and checksum, and the file is then copied into the tap repo
# (tjameswilliams/homebrew-tap → Casks/opencodego.rb), which is what
# `brew install --cask tjameswilliams/tap/opencodego` reads.
#
# auto_updates true tells brew this app updates itself (via Sparkle), so
# `brew upgrade` leaves it alone rather than fighting the in-app updater.
cask "opencodego" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/tjameswilliams/opencodego/releases/download/v#{version}/OpenCodeGo.dmg"
  name "OpenCode Go"
  desc "Drive the OpenCode coding agent on your Mac from your iPhone"
  homepage "https://github.com/tjameswilliams/opencodego"

  auto_updates true
  depends_on macos: ">= :sonoma"
  # The companion drives the OpenCode CLI; without it there's nothing to run.
  depends_on formula: "opencode"

  app "OpenCode Go.app"

  zap trash: [
    "~/Library/Application Support/OpenCodeGo",
    "~/Library/Caches/com.timwilliams.opencodego.mac",
    "~/Library/Preferences/com.timwilliams.opencodego.mac.plist",
  ]
end
