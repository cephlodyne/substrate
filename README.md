# Substrate — Zero-Trust Portable Dev Environment (macOS ARM64)

A deterministic, cryptographically verified, offline-capable development environment for Apple Silicon Macs. Substrate installs all compilers, runtimes, linters, infrastructure CLIs, container orchestration, and a pre-configured Neovim/Alacritty IDE directly into `~/.local`

---

## Architecture & Security Model

* **Single Source of Truth (`versions.env`):** Every runtime, CLI binary, and plugin is pinned by version and verified against SHA256 checksums before extraction.
* **Strict Isolation (`~/.local`):** No `sudo` required (except optional `/Applications/Alacritty.app` copy). All binaries use relative symlinks inside `~/.local/bin`, making the installation 100% relocatable across machines and usernames.
* **Supply-Chain Hardening:**
  * **Go:** Enforces `GOTOOLCHAIN=local` (blocks automatic binary downloads), `GOPROXY=https://proxy.golang.org,direct`, and `GOSUMDB=sum.golang.org`.
  * **Node / NPM:** Globally enforces `ignore-scripts=true` to block malicious `postinstall` lifecycle scripts, using explicit `--allow-scripts=pnpm` only where required.
  * **Google Cloud SDK:** Bound to the isolated standalone Python 3.10 runtime (`CLOUDSDK_PYTHON`) with internal component auto-updaters and telemetry disabled.
  * **Neovim (`LazyVim`):** Uses `+Lazy! restore` against a committed `configs/nvim/lazy-lock.json` and disables `mason.nvim` network installers so all LSPs/formatters resolve strictly from `~/.local/bin`.
  * **Git Secret Scanning:** Automatically configures global Git pre-commit hooks powered by `trufflehog`.
  * **Zero-Trust Containers:** Colima runs on Apple's native Virtualization.framework (`vz`) with `virtiofs` and `network.address: false` (disabling reachable bridge IPs in favor of strict localhost port forwarding).

---

## Repository Structure

```text
substrate/
├── versions.env               # Master ledger of pinned versions, URLs, and SHA256 hashes
├── setup-macarm.sh            # Bootstrapper, config syncer, and portable tarball builder
├── uninstall-arm.sh           # Full or VM-preserving teardown script
├── chrome-settings.sh         # Enterprise policy hardening script for Google Chrome
├── configs/
│   ├── alacritty/
│   │   └── alacritty.toml     # Enforced Alacritty terminal configuration
│   └── nvim/                  # Complete LazyVim configuration + pinned lazy-lock.json
├── scripts/
│   ├── check-updates.sh       # Checks upstream releases & auto-updates versions.env
│   ├── consolidate.sh         # Exports repository into substrate-context.xml for LLM review
│   ├── hog-setup.sh           # Installs global TruffleHog Git hooks
│   └── hog-uninstall.sh       # Removes global TruffleHog Git hooks
└── src/                       # Custom local Go utilities (compiled with -ldflags="-s -w")
