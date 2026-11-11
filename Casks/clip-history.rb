cask "clip-history" do
  version "1.7.0"
  sha256 "4843929db6c64d366a67f886d2cd548f0da0dd81b8df53f770f4a7a87f209fe5"

  url "https://github.com/yahyahouse/copy-paste-history/releases/download/v#{version}/ClipHistory-#{version}.dmg"
  name "Clip History"
  desc "Lightweight clipboard history for the menu bar"
  homepage "https://github.com/yahyahouse/copy-paste-history"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "ClipHistory.app"

  # Not notarized yet, so clear the quarantine flag to avoid the Gatekeeper prompt
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/ClipHistory.app"]
  end

  uninstall quit: "com.yahyawijaya.cliphistory"

  zap trash: "~/Library/Application Support/ClipHistory"
end
