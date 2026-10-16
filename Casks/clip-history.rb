cask "clip-history" do
  version "1.6.1"
  sha256 "ff07e4908efef869a060b51837e4a9611457d47fd51757f1cb7ad477ddd884be"

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
