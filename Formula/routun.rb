class Routun < Formula
  desc "Transparent TUN-based network routing for macOS"
  homepage "https://github.com/dumbovita/routun"
  url "https://github.com/dumbovita/routun/archive/refs/tags/v1.3.1.tar.gz"
  sha256 "8ef9338951c8c8aa5377925e9c63b9b034e4a25662b762efab3a1d58c5a19527"
  license "MIT"
  head "https://github.com/dumbovita/routun.git", branch: "main"

  depends_on macos: :sonoma
  depends_on "sing-box"
  uses_from_macos "swift" => :build

  resource "byedpi" do
    url "https://github.com/hufrea/byedpi/archive/refs/tags/v0.17.3.tar.gz"
    sha256 "0a9cb8585554c68c3e2be88c33c9bf6f99f8e8c7f54b362285adab99e262566c"
  end

  def install
    # Build and install ByeDPI (ciadpi) from official source
    resource("byedpi").stage do
      system "make"
      bin.install "ciadpi"
    end

    # Build and install routun
    architecture = Hardware::CPU.arm? ? "arm64" : "x86_64"
    system "swiftc", "-O", "-target", "#{architecture}-apple-macos14.0", *Dir["Sources/*.swift"], "-o", "routun"
    bin.install "routun"

    pkgshare.install "config/singbox.json", "config/routun.json"
  end

  def caveats
    <<~EOS
      routun uses its own system LaunchDaemon so Homebrew remains a
      distribution and upgrade mechanism only. After installation, run:
        sudo routun install

      After every brew upgrade, run the same command to copy the new,
      root-owned service payload and restart the existing LaunchDaemon.

      To verify operation:
        routun status
    EOS
  end

  test do
    assert_match "routun version", shell_output("#{bin}/routun --version")
    assert_match "Usage:", shell_output("#{bin}/routun --help")
  end
end
