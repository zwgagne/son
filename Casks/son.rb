cask "son" do
  version "0.1.0"
  sha256 "b0380192b68626834aa1ed1919a54ab16b7ccf9a4736d1866be565a4cdf5d2d5"

  url "https://github.com/zwgagne/son/releases/download/v#{version}/Son-#{version}.zip"
  name "Son"
  desc "Minimal per-application audio mixer"
  homepage "https://github.com/zwgagne/son"

  depends_on macos: :sonoma

  app "Son.app"

  zap trash: "~/Library/Preferences/com.zwgagne.Son.plist"
end
