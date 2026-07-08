# Mara

[![CI](https://github.com/ai-screams/mara/actions/workflows/ci.yml/badge.svg)](https://github.com/ai-screams/mara/actions/workflows/ci.yml)
[![Secret Scan](https://github.com/ai-screams/mara/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/ai-screams/mara/actions/workflows/secret-scan.yml)
[![Latest release](https://img.shields.io/github/v/release/ai-screams/mara?label=release&color=ff9500)](https://github.com/ai-screams/mara/releases/latest)
[![License](https://img.shields.io/badge/license-Proprietary-lightgrey)](LICENSE)

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Universal](https://img.shields.io/badge/Universal-Apple%20Silicon%20%26%20Intel-000000?logo=apple&logoColor=white)](#install)
[![Notarized](https://img.shields.io/badge/Apple-Notarized-34c759?logo=apple&logoColor=white)](RELEASING.md)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/ai-screams)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=kofi&logoColor=white)](https://ko-fi.com/pignuante)

A macOS menu-bar app that keeps your Mac from sleeping. Caffeine-style, but built the honest way — no permission bypasses, no undocumented tricks. It uses only **official IOKit power assertions**, **IOKit power-source state**, **SMAppService**, and the **system routing table**.

[Website](https://ai-scream.ai/mara/) · [Latest release](https://github.com/ai-screams/mara/releases/latest) · [Release process](RELEASING.md)

> On the name: in folklore, a *mara* is a spirit that sits on a sleeper's chest and disturbs their rest — the root of *nightmare* (night + mare).

## Features

- Toggle keep-awake on and off from the menu bar
- Indefinite, or a `15m` / `1h` / `2h` / `5h` timer
- Keep the system awake only, or the display too
- Menu-bar eye icon: an open orange eye with the time remaining when active, a closed eye when off
- Low-battery auto-off: on battery, the keep-awake session ends once you drop below your threshold
- Launch at login via Apple's `SMAppService`
- Automatic triggers:
  - AC power connected
  - An external display connected
  - A watched app (by bundle ID) running
  - A specific network

The network trigger uses no location permission. It normalizes and matches the default gateway's MAC address, so there is no CoreLocation prompt.

## Install

1. Download `Mara-<version>.dmg` from the [latest release](https://github.com/ai-screams/mara/releases/latest).
2. Open the DMG and drag **Mara** into your `Applications` folder.
3. Launch Mara — an eye icon appears in the menu bar.

Requirements:

- macOS 14 or later
- Apple Silicon and Intel Macs
- Developer ID–signed and Apple-notarized DMG (opens Gatekeeper-clean, no warning)
- No Location, Accessibility, or Screen Recording permissions

## Usage

Click the menu-bar icon for:

- `Keep Awake` / `Turn Off`
- `Keep awake for…`: `15 minutes`, `1 hour`, `2 hours`, `5 hours`
- `Keep display awake`
- `Launch at Login`
- `Quit Mara`

When a session is started by an automatic trigger, the menu shows a `자동 활성 (트리거)` status. If you turn it off manually, it will not restart while the trigger is still true; it re-arms only after every trigger has cleared. Manual control always takes precedence over triggers.

## Architecture

| Area | Responsibility |
|---|---|
| `App/` | SwiftUI `MenuBarExtra`, menu-bar status icon, preferences persistence, launch-at-login, wiring of the OS adapters |
| `MaraCore/` | Swift Package. OS-free session/trigger/scheduling core behind protocols |
| `MaraCore/Sources/MaraCore/SleepEngine.swift` | Idempotent reconcile of display/system IOKit assertions |
| `MaraCore/Sources/MaraCore/SessionManager.swift` | Single session state, timer, scope changes, low-battery veto |
| `MaraCore/Sources/MaraCore/Triggers/` | Charging, external-display, app-running, and network triggers with suppression/re-arm logic |
| `MaraCore/Tests/` | Core unit tests, routing-table parser tests, and real-IOKit assertion integration tests |
| `scripts/release.sh` | XcodeGen, archive, Developer ID export, notarization, staple, DMG build and verification |
| `docs/` | Public landing page served via GitHub Pages |

Global-hotkey (Carbon) code is kept in `App/HotkeyManager.swift` but is currently disabled. Closed-lid (clamshell) keep-awake needs a privileged daemon with a lease-based recovery model and is out of scope for now.

## Development

Tooling:

- Xcode 15 or later
- Swift 5.9 or later
- XcodeGen

```bash
brew install xcodegen
```

Common commands:

```bash
# Core unit tests
make test

# Generate project.yml -> Mara.xcodeproj
make generate

# Verify an unsigned Debug build
make build
```

`Mara.xcodeproj` is generated and not committed. When exercising runtime and permission flows, use a stable Apple Development–signed build rather than an ad-hoc signature (ad-hoc rebuilds change the cdhash and break TCC-granted permissions).

## Releasing

Distribution is a Developer ID–signed, Apple-notarized, drag-to-Applications DMG.

```bash
xcrun notarytool store-credentials mara-notary \
  --apple-id "<apple-id>" \
  --team-id 7K6MK3KP9K \
  --password "<app-specific-password>"

DEVELOPMENT_TEAM=7K6MK3KP9K NOTARY_PROFILE=mara-notary make release
```

`scripts/release.sh` runs:

- `xcodegen generate`
- Release archive
- Developer ID export
- Hardened Runtime / signature verification
- App notarization and staple
- DMG creation
- DMG signing, notarization, and staple
- `spctl` and `stapler` verification

Pushing a tag runs the same release path on GitHub Actions:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release workflow runs in a protected `release` environment (requires reviewer approval before the signing/notarization secrets are exposed), builds and notarizes the DMG, and attaches it plus its `.sha256` checksum to a GitHub Release. Prerelease tags (containing `-`, e.g. `v1.0.0-rc.1`) are published as pre-releases and excluded from "latest". Full steps and required secrets are in [RELEASING.md](RELEASING.md).

## Quality gates

- CI: `swift test`, XcodeGen project generation, unsigned Debug build
- Secret Scan: TruffleHog verified/unknown results
- GitHub Actions supply-chain hardening: actions pinned to commit SHAs, kept current by Dependabot
- Release verification: `spctl -t open`, `xcrun stapler validate`

## Support

Mara is built and maintained by one person — no ads, no telemetry. If it earns a place on your Mac, you can help fund its development:

<p>
  <a href="https://github.com/sponsors/ai-screams">
    <img src="https://img.shields.io/badge/Sponsor%20on-GitHub-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor on GitHub" height="38">
  </a>
  &nbsp;
  <a href="https://ko-fi.com/pignuante">
    <img src="https://img.shields.io/badge/Support%20on-Ko--fi-ff5e5b?style=for-the-badge&logo=kofi&logoColor=white" alt="Support on Ko-fi" height="38">
  </a>
</p>

## License

Proprietary and confidential. See [LICENSE](LICENSE) for details.
