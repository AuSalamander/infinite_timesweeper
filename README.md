# Infinite TimeSweeper

**Infinite TimeSweeper** - a simple, configurable and beautiful implementation of Minesweeper with an _infinite world_. Play forever - new tiles are generated as you explore.



## Features

- Infinite, procedurally-generated board.
- Daubletap to open.
- Hold to flag.
- Doubletap solved hint to autoopen.



## Get the app (Pre-releases)

A stable release is not ready yet, but you can help test prereleases.

You can obtain builds from the repository releases (GitHub), but the recommended way to install and keep prereleases updated is via **Obtainium** - a small app that installs and updates apps directly from their release pages. ([obtainium.imranr.dev](https://obtainium.imranr.dev))

[![Get it on Obtainium](https://raw.githubusercontent.com/ImranR98/Obtainium/main/assets/graphics/badge_obtainium.png)](http://apps.obtainium.imranr.dev/redirect.html?r=obtainium%3A%2F%2Fapp%2F%257B%2522id%2522%253A%2522com.au.salamander.infinite_timesweeper%2522%252C%2522url%2522%253A%2522https%253A%252F%252Fgithub.com%252FAuSalamander%252Finfinite_timesweeper%2522%252C%2522author%2522%253A%2522AuSalamander%2522%252C%2522name%2522%253A%2522Infinite%2520TimeSweeper%2522%252C%2522preferredApkIndex%2522%253A0%252C%2522additionalSettings%2522%253A%2522%257B%255C%2522includePrereleases%255C%2522%253A%2520true%257D%2522%257D)

(If you prefer manual installs: grab the APK from this repo's **Releases** page on GitHub.)

SHA256: 57:00:E7:A0:BE:90:0B:91:F5:A1:59:B7:3C:78:59:CA:19:AF:95:24:1E:73:53:B7:37:00:C7:7E:08:30:92:23

> **Signing migration:** builds from the `0.0.6` beta series onward use a new signing certificate. Uninstall the previous app before installing these builds; Android and Obtainium cannot update across different signatures. Later updates signed by CI will work normally.



## Step - by step installation guide

1. Clic badge higer, it will redirect you to Obtainium app. (If you don’t have Obtainium - scroll to "If you don’t have Obtainium")
2. Tap **confirm**. Obtainium will read the releases and add the app to your list.
3. If download didn`t start ore stopped, tap the app entry, then tap **Install**.
4. When Android asks for permission to install the APK, confirm/agree - tap **Install**.
5. If Android blocks the install, it will usually show a prompt like **"Install unknown apps"** - tap to allow installs from the browser or Obtainium, then retry the installation.

**What Obtainium does:** it watches a project’s release page (GitHub/GitLab/etc.), downloads APKs, and helps you install/update them from a single app. ([obtainium.imranr.dev](https://obtainium.imranr.dev))



## If you don’t have Obtainium

You can install Obtainium itself from several sources:

- **F-Droid (recommended if you use F-Droid)** - Obtainium is available on F-Droid. ([F-Droid](https://f-droid.org/en/packages/dev.imranr.obtainium.fdroid))
- **Official Obtainium website** - see the Obtainium website and wiki for downloads and documentation. ([obtainium.imranr.dev](https://obtainium.imranr.dev))
- **GitHub releases** - you can download the Obtainium APK from the project's GitHub releases page and install it manually. ([GitHub](https://github.com/ImranR98/Obtainium/releases))

##### Basic steps to install Obtainium (manual APK install)
1. Download the Obtainium APK from a trusted source (F-Droid, official site, or GitHub).
2. Open the downloaded file (or open your Downloads folder) and tap the APK.
3. If Android warns about unknown sources, follow the prompt to allow installs from your browser or file manager.
4. Confirm the install.



## Manual install (no Obtainium)

1. Download the APK from this repository’s **Releases** page on GitHub.
2. On your device, open the APK file to install.
3. Allow **Install unknown apps** if Android requests it.
4. Confirm **Install**.



## Android CI releases

The Android workflow builds and signs an APK on GitHub, then publishes it to GitHub Releases. No local Flutter or Android SDK is needed to publish a build.

### One-time setup

1. Install and authenticate the [GitHub CLI](https://cli.github.com/) with an account that can edit this repository's secrets and run workflows: `gh auth login`.
2. Keep the existing signing files at `android/key.properties` and the keystore path referenced by it, then run:

   ```sh
   ./scripts/setup-release-secrets.sh
   ```

   This uploads the signing configuration as repository secrets without printing any passwords.

### Publish

Commit and push the code first, then run:

```sh
./scripts/publish.sh --beta     # APK + prerelease, tagged vX.Y.Z-beta.N
./scripts/publish.sh --release  # APK + stable release, tagged vX.Y.Z
```

The version comes from `pubspec.yaml`; `N` uses the GitHub workflow run number. The Android `versionCode` is derived from the build time so it increases automatically and stays above legacy builds. Publishing is supported from the default branch only. After a stable release, bump `version:` in `pubspec.yaml` before publishing either channel. Obtainium configurations with **Include prereleases** enabled can discover beta builds automatically.



## Performance benchmarks

Run `./scripts/benchmark.sh` for an unattended profile-mode Linux benchmark of
large and zoomed-out worlds in both light and dark mode. See
[docs/performance.md](docs/performance.md) for metrics, JSON reports,
repeatable baselines, regression comparisons, and visual reference screenshots.
The benchmark is manual; it is not run in CI.

## Contributing & Feedback

If you find bugs or want to suggest features, please open an issue or PR on the GitHub repository. Your feedback - especially from prerelease testing - is very welcome.
