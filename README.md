# update-craftapps-clis

Update the standalone command-line tools (CLIs) of the [Craft App Suite](https://github.com/storytold) on macOS with a single command.

> **Unofficial.** This project is not affiliated with, endorsed by, or maintained by ArtCraft or storytold. It only downloads the public release assets those projects publish on GitHub.

## Why

On macOS the app installer (`.dmg`) does **not** include the CLI. Each app publishes it as a separate zip (`<app>-cli-<version>-macos-universal.zip`) on every release, so updating means downloading and replacing each one by hand.

This script does that for you:

1. finds which CLIs you already have;
2. compares them with the latest GitHub release of each app;
3. downloads the new zip and **verifies its SHA-256** against the release's `SHA256SUMS.txt`;
4. keeps a backup (`<cli>.bak`), replaces the binary, and runs `--version` on the new one;
5. if the new binary does not run, it restores the backup.

## What it does not do

It does not install or update the **apps themselves**. For that, use the official [ArtCraft Launcher](https://github.com/storytold/craft-launcher) or the app's own updater. As far as I could tell, neither of them updates the standalone macOS CLI.

## Supported apps

CADCraft, Craft Anything, DeckCraft, DesignCraft, FigCraft, GridCraft, LightCraft, PDFCraft, PhotoCraft, VectorCraft, WordCraft.

## Requirements

- macOS (Linux and Windows are not supported yet)
- `curl`, `unzip`, `install` and `shasum` (all included with macOS)

## Usage

```bash
chmod +x update-craftapps-clis.sh

./update-craftapps-clis.sh --list      # what is installed on this Mac (no network)
./update-craftapps-clis.sh --check     # compare with the latest releases, install nothing
./update-craftapps-clis.sh             # update the installed CLIs (asks before applying)
./update-craftapps-clis.sh figcraft pdfcraft   # only these apps
./update-craftapps-clis.sh --install   # also install CLIs you do not have yet
./update-craftapps-clis.sh --yes       # no confirmation prompt
```

Apps are named by their GitHub repository (`figcraft`, `craft-anything`, ...).

Example:

```
APP              STATE      DETAIL
figcraft         UPDATE     0.16.0 -> 0.17.0
pdfcraft         OK         0.20.0
wordcraft        SKIP       CLI not installed (use --install to add it)
```

Environment variables:

| Variable | Purpose |
|---|---|
| `GITHUB_TOKEN` | Optional. Avoids the 60 requests/hour limit of the anonymous GitHub API. |
| `DEST` | Where new CLIs go with `--install` (default `/usr/local/bin`). |

The script asks for your password (`sudo`) only when a CLI lives in a folder you cannot write to, such as `/usr/local/bin`.

## Safety

- **Checksum is mandatory.** A release without `SHA256SUMS.txt`, or with a mismatch, is never installed.
- **Limit of that check:** the checksum file comes from the same release as the binary. It protects against corrupted downloads, not against a compromised release. Signature verification is not implemented yet.
- **Backups:** the previous binary is kept next to the new one as `<cli>.bak` (one backup, overwritten on the next update).
- **Why `rm` + `install` instead of `cp`:** on macOS, overwriting a signed binary in place makes the system kill it (`Killed: 9`, exit code 137) because of the cached code signature. Removing the file first avoids that.
- Read the script before running it, especially if you use `sudo`. It is a single file.

## How it finds the CLI

For each app `X` it looks for `X-cli` in your `PATH` and in `/usr/local/bin`, then reads the version from `X-cli --version`. The release asset is the first one matching `*-cli-*-macos-universal.zip`.

The `.app` column in `--list` is only a best-effort match by name in `/Applications` and `~/Applications`.

## Known limitations

- macOS only. Linux and Windows packages ship the CLI inside the full app archive, which needs a different approach.
- Assumes every app follows the same release naming. If an app changes its asset names, it will show as `ERROR` until the script is updated.
- Pre-releases are ignored (GitHub's "latest release" only).

## Development

Built by Rick Benetti with the help of [Claude](https://claude.ai) (Anthropic), which drafted the script and this README under my direction. Tested on macOS (Apple Silicon) against the real releases of all 11 supported apps. Please read the script before you run it.

## License

[MIT](LICENSE)
