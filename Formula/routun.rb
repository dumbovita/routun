class Routun < Formula
  desc "Transparent TUN-based network routing for macOS"
  homepage "https://github.com/dumbovita/routun"
  url "https://github.com/dumbovita/routun/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "bc17f020345d30ffb04396763464679cf3852689eb81bba15de2bf5c68f8603d"
  license "MIT"
  head "https://github.com/dumbovita/routun.git", branch: "main"

  depends_on :macos
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
    system "swiftc", "-O", *Dir["Sources/*.swift"], "-o", "routun"
    bin.install "routun"

    # Install configuration files into etc/routun (preserved on upgrades)
    (etc/"routun").install "config/singbox.json", "config/routun.json"

    # Ensure log and runtime directories exist under HOMEBREW_PREFIX/var
    (var/"log/routun").mkpath
    (var/"run").mkpath
  end

  post_install_steps do
    mkdir_p "log/routun", base: :var
    mkdir_p "run", base: :var
  end

  service do
    run [opt_bin/"routun", "daemon"]
    require_root true
    keep_alive successful_exit: false
    log_path var/"log/routun/daemon.log"
    error_log_path var/"log/routun/daemon.err"
    working_dir var
  end

  def caveats
    <<~EOS
      routun requires root privileges to manage virtual TUN interfaces:
        sudo brew services start routun

      To verify operation:
        routun status
    EOS
  end

  test do
    assert_match "routun version", shell_output("#{bin}/routun --version")
    assert_match "Usage:", shell_output("#{bin}/routun --help")
  end
end
