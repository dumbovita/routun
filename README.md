<div align="center">

# routun

**Transparent TUN-based network routing for macOS.**

A lightweight background service coordinating ByeDPI (`ciadpi`) and Sing-box (`utun`) under native macOS `launchd`.

> Use at your own risk.

</div>

---

## Requirements

- macOS 14.0 (Sonoma) or later (Apple Silicon & Intel)
- Root / administrator privileges (`sudo` is required to create virtual `utun` interfaces and manage kernel routing tables)
- [Homebrew](https://brew.sh) (recommended for distribution and upgrades)
- [`sing-box`](https://github.com/SagerNet/sing-box) (installed automatically as a dependency by Homebrew)
- [`ciadpi`](https://github.com/hufrea/byedpi) (ByeDPI — built and installed automatically from source by Homebrew / `install.sh`)

## Installation

### Homebrew (Recommended)

```bash
# Trust the repository (required by Homebrew 6.0+)
brew trust https://github.com/dumbovita/routun

# Tap and install
brew tap dumbovita/routun https://github.com/dumbovita/routun
brew install routun
sudo routun install
```

`routun install` copies the daemon and its two runtime dependencies into the root-owned payload directory `/usr/local/libexec/routun`, stores root-owned configuration under `/Library/Application Support/routun`, then registers the one system LaunchDaemon. Homebrew does not manage the service.

### Manual Installation

If you prefer not to use Homebrew, you can build and install directly from source:

```bash
git clone https://github.com/dumbovita/routun.git
cd routun
./install.sh
```

*(Alternatively, run `make install`; it requests `sudo` only for the protected installation steps.)*

The GitHub release archive contains the same Universal 2 executable and its
configuration templates. Extract it, install `sing-box` and `ciadpi` in
`/opt/homebrew/bin` or `/usr/local/bin`, then run `sudo ./routun install` from
the extracted directory.

## Usage

### Service Management

Both installation methods use these same commands:

```bash
sudo routun start
sudo routun stop
sudo routun restart
```

After `brew upgrade routun`, run `sudo routun install` again. This updates the protected payload and restarts the existing `com.routun.routund` LaunchDaemon; it does not create a second service.

### CLI Utilities

`routun` includes built-in commands for status inspection, diagnostics, and log monitoring:

```bash
# View live service status, child PIDs, listening ports, and TUN health
routun status

# Run system environment diagnostics and verify dependencies
routun doctor

# View and follow real-time service logs
routun logs -f
```

### Selective Routing & Service Groups

Routun defaults to **selective routing** mode: only designated service groups and explicit domain overrides are routed through ByeDPI, while ordinary traffic, local LAN, and private IP ranges remain completely direct.

```bash
# Inspect active routing policy, QUIC mode, and target counts
routun policy show

# Manage built-in offline service groups (6 curated groups)
routun group list
routun group enable social
routun group disable social

# Add custom domain includes or overrides
routun policy include subscene.best
routun policy exclude internal.corp.net

# Switch routing mode (selective vs global)
routun policy mode selective
routun policy mode global

# Configure QUIC / HTTP/3 handling (scoped, blocked, or direct)
routun policy quic scoped
```

#### Built-in Service Groups

| Group ID | Description | Default Status |
| :--- | :--- | :--- |
| `general` | General web services and repositories affected by regional censorship | **Enabled** |
| `social` | Social networks and messaging (Instagram, X/Twitter, Facebook, etc.) | Disabled |
| `turkiye` | Services blocked by regional administrative/court orders (Roblox, Wattpad, etc.) | **Enabled** |
| `youtube` | YouTube playback, thumbnails, and streaming infrastructure | **Enabled** |
| `telegram` | Telegram Web and official messaging domains | Disabled |
| `cloudflare` | Cloudflare edge endpoints and Encrypted ClientHello (ECH) | Disabled |

### Scoped QUIC / HTTP/3 Handling

Unlike legacy tools that globally drop all outbound UDP/443 (breaking HTTP/3 performance for the entire operating system), Routun features **scoped QUIC rejection**:
- UDP/443 is rejected **only** for domains targeted for DPI bypass, prompting browsers to seamlessly fall back to TCP TLS where ByeDPI evasion operates.
- Legitimate HTTP/3 and QUIC traffic to all other destinations continues without interruption.

### Strategy Optimization (Blockcheck)

Routun includes an automated strategy optimizer inspired by Zapret's `blockcheck`. It tests a comprehensive matrix of **51 unique macOS-supported parameter combinations** (pure splits, dual splits, SNI disorders, TLS record segmentation, OOB urgent bytes, and DISOOB) against a curated multi-platform target set.

> [!NOTE]
> **Darwin ByeDPI Capabilities**: In upstream ByeDPI (`ciadpi`), fake TCP packet injection (`-f`, `-t`, `-Q`) and TCP timeouts (`-T`) are compiled exclusively for Linux and Windows. On macOS, `-t` (TTL) and `-Q` (fake TLS ClientHello) are parsed by the CLI but inert in TCP handling. Routun actively detects Darwin capabilities, purges inert flags, and evaluates only genuine macOS-supported evasion techniques (`-s`, `-d`, `-o`, `-q`, `-r`, `-A`, `-M`, `-m`).

```bash
# Auto-detect the best evasion strategy across 51 macOS combinations
routun optimize

# Include custom target domains to verify they are not broken by DPI evasion
routun optimize anadolu.edu.tr saglik.gov.tr

# Fast screening mode (evaluates 7 canonical profiles first)
routun optimize --quick -t anadolu.edu.tr

# Verbose mode with per-target connection and latency diagnostics
routun optimize -v

# View curated canonical strategy profiles (7 profiles)
routun profile list

# Inspect all 51 supported parameter combinations
routun profile list --all

# Manually switch to any profile or combination
routun profile set disorder-split-sni

# Inspect active profile and underlying ByeDPI arguments
routun profile show
```

## Uninstallation

### Via Homebrew

```bash
sudo routun uninstall
brew uninstall routun
```

### Standalone Uninstallation

```bash
sudo routun uninstall
```

*(Alternatively, run `./uninstall.sh` if you still have the repository folder, or `make uninstall`.)*

This safely stops the running daemon, removes only routun-owned service files, and restores default macOS routing through the daemon's ordered shutdown. `routun uninstall` deliberately does not remove Homebrew-managed files; use `brew uninstall` for those.

## AI Disclaimer

AI-assisted tools were used during parts of development. The codebase has been manually reviewed, tested, and maintained as a real software project. Issues, feedback, and contributions are welcome.

## Releases

Releases and Homebrew formula updates are fully automated via GitHub Actions:

1. Navigate to **Actions** → **Release & Homebrew Distribution** → **Run workflow**.
2. Select the version bump (`patch`, `minor`, `major`) or specify an explicit version.
3. CI automatically validates the code, compiles universal binaries, creates the GitHub release, calculates SHA-256 checksums, and updates `Formula/routun.rb`.

*(Alternatively, push a Git tag: `git tag v1.2.0 && git push origin v1.2.0`.)*

## Contributing

Contributions, bug reports, and suggestions are welcome. Feel free to open an issue or submit a pull request on [GitHub](https://github.com/dumbovita/routun).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  If you find this project useful, consider leaving a ⭐ on the repository.
</p>
