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
- [Homebrew](https://brew.sh) (recommended for package and service management)
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
sudo brew services start routun
```

> **Note:** `sudo` is required because creating macOS virtual TUN interfaces and modifying system routes require root privileges (`require_root true`).

### Manual Installation

If you prefer not to use Homebrew, you can build and install directly from source:

```bash
git clone https://github.com/dumbovita/routun.git
cd routun
./install.sh
```

*(Alternatively, run `sudo make install`.)*

## Usage

### Service Management

With Homebrew:

```bash
# Start service
sudo brew services start routun

# Stop service
sudo brew services stop routun

# Restart service
sudo brew services restart routun
```

With standalone installation:

```bash
sudo routun start
sudo routun stop
sudo routun restart
```

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

### Strategy Optimization (Blockcheck)

`routun` includes an automated strategy detector inspired by Zapret's `blockcheck`. It tests a comprehensive matrix of parameter combinations (pure splits, dual splits, SNI disorders, TLS record segmentation, fake TTL sweeps, and OOB data) against curated global targets and daily use services, cross-referencing contenders across two verification rounds:

```bash
# Auto-detect optimal strategy across 59 combinations with cross-referencing
routun optimize

# Include custom target domains to verify they are not broken by DPI evasion
routun optimize anadolu.edu.tr saglik.gov.tr

# Fast screening mode with custom targets
routun optimize --quick -t anadolu.edu.tr

# Verbose mode with per-target connection and latency diagnostics
routun optimize -v

# View curated strategy profiles
routun profile list

# Inspect all 59 supported parameter combinations
routun profile list --all

# Manually switch to any profile or combination
routun profile set fake-ttl3-disorder-2s

# Inspect active profile and underlying ByeDPI arguments
routun profile show
```

## Uninstallation

### Via Homebrew

```bash
sudo brew services stop routun
brew uninstall routun
```

### Standalone Uninstallation

```bash
sudo routun uninstall
```

*(Alternatively, run `./uninstall.sh` if you still have the repository folder, or `sudo make uninstall`.)*

This safely stops the running daemon, removes LaunchDaemon plists and configuration files, and restores default macOS network routing.

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

---

<p align="center">
  If you find this project useful, consider leaving a ⭐ on the repository.
</p>
