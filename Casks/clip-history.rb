cask "clip-history" do
  version "1.8.0"
  sha256 "87f5afb79f2f7ad8eb3ddd4af885114d9c6975aad38b48346c7d56d5c485a9b6"

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
