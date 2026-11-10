#!/usr/bin/env bash
#
# update-craftapps-clis — update the standalone command-line tools (CLIs) of the
# Craft App Suite (github.com/storytold) on macOS, from each app's latest GitHub release.
#
# Unofficial. Not affiliated with ArtCraft or storytold.
# Compatible with the bash 3.2 that ships with macOS.

set -uo pipefail

VERSION="0.1.0"
ORG="storytold"
DEFAULT_DEST="/usr/local/bin"

# GitHub repository name | display name (used to look for the .app bundle)
APP_LIST='cadcraft|CADCraft
craft-anything|Craft Anything
deckcraft|DeckCraft
designcraft|DesignCraft
figcraft|FigCraft
gridcraft|GridCraft
lightcraft|LightCraft
pdfcraft|PDFCraft
photocraft|PhotoCraft
vectorcraft|VectorCraft
wordcraft|WordCraft'

usage() {
  cat <<'EOF'
Usage: update-craftapps-clis.sh [options] [app ...]

Updates the CLIs that are already installed. Apps are named by repository
(figcraft, pdfcraft, craft-anything, ...). With no app names, all are considered.

Options:
  -l, --list      Show what is installed on this Mac (CLI and .app). No network.
  -c, --check     Compare installed versions with the latest releases. Installs nothing.
  -i, --install   Also install CLIs that are not installed yet.
  -y, --yes       Do not ask for confirmation.
  -V, --version   Print the version of this script.
  -h, --help      Show this help.

Environment:
  GITHUB_TOKEN    Optional. Avoids the 60 requests/hour limit of the anonymous GitHub API.
  DEST            Where new CLIs go with --install (default: /usr/local/bin).
EOF
}

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { warn "Error: $*"; exit 1; }

MODE="update"
INSTALL_MISSING=0
ASSUME_YES=0
SELECTED=""
DEST="${DEST:-$DEFAULT_DEST}"

for arg in "$@"; do
  case "$arg" in
    -l|--list)    MODE="list" ;;
    -c|--check)   MODE="check" ;;
    -i|--install) INSTALL_MISSING=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -V|--version) say "$VERSION"; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           die "unknown option: $arg (see --help)" ;;
    *)            SELECTED="$SELECTED $arg" ;;
  esac
done

# Set CRAFT_SKIP_OS_CHECK=1 only to test the script on another OS.
if [ "$(uname -s)" != "Darwin" ] && [ "${CRAFT_SKIP_OS_CHECK:-0}" != "1" ]; then
  die "this version supports macOS only."
fi

for cmd in curl unzip install; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

curl_api() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$1"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "$1"
  fi
}

# --- app table ---------------------------------------------------------------

is_selected() {
  [ -z "$SELECTED" ] && return 0
  case " $SELECTED " in *" $1 "*) return 0 ;; esac
  return 1
}

# Reject unknown app names early.
for want in $SELECTED; do
  case "
$APP_LIST" in
    *"
$want|"*) ;;
    *) die "unknown app: $want" ;;
  esac
done

A_SLUG=(); A_DISPLAY=(); A_BIN=(); A_INST=(); A_LATEST=(); A_CLI_URL=(); A_SUMS_URL=(); A_STATE=(); A_NOTE=()
N=0
while IFS='|' read -r slug display; do
  [ -z "$slug" ] && continue
  is_selected "$slug" || continue
  A_SLUG[$N]="$slug"; A_DISPLAY[$N]="$display"
  A_BIN[$N]=""; A_INST[$N]=""; A_LATEST[$N]=""; A_CLI_URL[$N]=""; A_SUMS_URL[$N]=""; A_STATE[$N]=""; A_NOTE[$N]=""
  N=$((N + 1))
done <<EOF
$APP_LIST
EOF
[ "$N" -gt 0 ] || die "no apps selected."

# --- local detection ---------------------------------------------------------

version_of() {
  "$1" --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | sed -n 1p
}

find_cli() {  # $1 = binary name; prints its path if installed
  local p
  p="$(command -v "$1" 2>/dev/null || true)"
  if [ -z "$p" ] && [ -x "$DEST/$1" ]; then p="$DEST/$1"; fi
  printf '%s' "$p"
}

normalize() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'; }

find_bundle() {  # $1 = display name; prints the .app path if found (heuristic: name match)
  local want dir app
  want="$(normalize "$1")"
  for dir in /Applications "$HOME/Applications"; do
    [ -d "$dir" ] || continue
    for app in "$dir"/*.app; do
      [ -e "$app" ] || continue
      if [ "$(normalize "$(basename "$app" .app)")" = "$want" ]; then
        printf '%s' "$app"; return 0
      fi
    done
  done
  return 1
}

# True if $1 < $2 (dotted numeric versions).
ver_lt() {
  local IFS=.
  local -a a=($1) b=($2)
  local i x y
  for i in 0 1 2; do
    x="${a[$i]:-0}"; y="${b[$i]:-0}"
    x="${x//[!0-9]/}"; y="${y//[!0-9]/}"
    x=$((10#${x:-0})); y=$((10#${y:-0}))
    [ "$x" -lt "$y" ] && return 0
    [ "$x" -gt "$y" ] && return 1
  done
  return 1
}

# --- --list ------------------------------------------------------------------

if [ "$MODE" = "list" ]; then
  printf '%-16s %-10s %-34s %s\n' "APP" "CLI" "CLI PATH" ".APP BUNDLE"
  i=0
  while [ "$i" -lt "$N" ]; do
    bin="${A_SLUG[$i]}-cli"
    path="$(find_cli "$bin")"
    ver="-"; [ -n "$path" ] && ver="$(version_of "$path")"; [ -z "$ver" ] && ver="?"
    bundle="$(find_bundle "${A_DISPLAY[$i]}" || true)"
    printf '%-16s %-10s %-34s %s\n' "${A_SLUG[$i]}" "$ver" "${path:--}" "${bundle:--}"
    i=$((i + 1))
  done
  say
  say "The .app column is a best-effort match by name in /Applications and ~/Applications."
  exit 0
fi

# --- inspect (network) -------------------------------------------------------

inspect_app() {
  local i="$1" slug json tag urls
  slug="${A_SLUG[$i]}"
  A_BIN[$i]="$(find_cli "${slug}-cli")"
  [ -n "${A_BIN[$i]}" ] && A_INST[$i]="$(version_of "${A_BIN[$i]}")"

  if [ -z "${A_BIN[$i]}" ] && [ "$INSTALL_MISSING" -eq 0 ]; then
    A_STATE[$i]="SKIP"; A_NOTE[$i]="CLI not installed (use --install to add it)"
    return
  fi

  if ! json="$(curl_api "https://api.github.com/repos/$ORG/$slug/releases/latest")"; then
    A_STATE[$i]="ERROR"; A_NOTE[$i]="could not read the latest release (no release, or API rate limit)"
    return
  fi
  tag="$(grep -m1 '"tag_name"' <<<"$json" | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
  A_LATEST[$i]="${tag#v}"
  urls="$(grep -Eo '"browser_download_url": *"[^"]+"' <<<"$json" | sed -E 's/.*"(https[^"]+)"$/\1/')"
  A_CLI_URL[$i]="$(grep -m1 -E -- '-cli-.*macos-universal\.zip$' <<<"$urls")"
  [ -z "${A_CLI_URL[$i]}" ] && A_CLI_URL[$i]="$(grep -m1 -E -- '-cli-.*macos.*\.zip$' <<<"$urls")"
  A_SUMS_URL[$i]="$(grep -m1 -E '/SHA256SUMS\.txt$' <<<"$urls")"

  if [ -z "${A_LATEST[$i]}" ] || [ -z "${A_CLI_URL[$i]}" ]; then
    A_STATE[$i]="ERROR"; A_NOTE[$i]="release ${tag:-?} has no macOS CLI zip"
    return
  fi

  if [ -z "${A_BIN[$i]}" ]; then
    A_STATE[$i]="INSTALL"; A_NOTE[$i]="not installed -> ${A_LATEST[$i]}"
  elif [ -z "${A_INST[$i]}" ]; then
    A_STATE[$i]="UPDATE"; A_NOTE[$i]="installed version unknown -> ${A_LATEST[$i]}"
  elif [ "${A_INST[$i]}" = "${A_LATEST[$i]}" ]; then
    A_STATE[$i]="OK"; A_NOTE[$i]="${A_INST[$i]}"
  elif ver_lt "${A_INST[$i]}" "${A_LATEST[$i]}"; then
    A_STATE[$i]="UPDATE"; A_NOTE[$i]="${A_INST[$i]} -> ${A_LATEST[$i]}"
  else
    A_STATE[$i]="AHEAD"; A_NOTE[$i]="installed ${A_INST[$i]} is newer than latest release ${A_LATEST[$i]}"
  fi
}

print_table() {
  local i=0
  printf '%-16s %-10s %s\n' "APP" "STATE" "DETAIL"
  while [ "$i" -lt "$N" ]; do
    printf '%-16s %-10s %s\n' "${A_SLUG[$i]}" "${A_STATE[$i]}" "${A_NOTE[$i]}"
    i=$((i + 1))
  done
}

say "Checking latest releases ..."
i=0
while [ "$i" -lt "$N" ]; do
  inspect_app "$i"
  i=$((i + 1))
done
say
print_table

if [ "$MODE" = "check" ]; then
  exit 0
fi

# --- plan and confirm --------------------------------------------------------

TODO=0
i=0
while [ "$i" -lt "$N" ]; do
  case "${A_STATE[$i]}" in UPDATE|INSTALL) TODO=$((TODO + 1)) ;; esac
  i=$((i + 1))
done
if [ "$TODO" -eq 0 ]; then
  say
  say "Nothing to do."
  exit 0
fi

say
if [ "$ASSUME_YES" -ne 1 ]; then
  [ -t 0 ] || die "not running in a terminal; pass --yes to proceed."
  read -r -p "Apply $TODO change(s)? [y/N] " answer
  case "$answer" in y|Y|yes|YES) ;; *) say "Aborted."; exit 0 ;; esac
fi

# Ask for the sudo password once, only if some target folder is not writable.
need_sudo=0
i=0
while [ "$i" -lt "$N" ]; do
  case "${A_STATE[$i]}" in
    UPDATE) [ -w "$(dirname "${A_BIN[$i]}")" ] || need_sudo=1 ;;
    INSTALL) [ -w "$DEST" ] || need_sudo=1 ;;
  esac
  i=$((i + 1))
done
if [ "$need_sudo" -eq 1 ]; then
  say "Some folders need administrator rights."
  sudo -v || die "could not get administrator rights."
fi

# --- apply -------------------------------------------------------------------

WORK="$(mktemp -d "${TMPDIR:-/tmp}/update-craftapps-clis.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

apply_app() {
  local i="$1" slug dir zipname zip expected actual newbin target sudo="" now
  slug="${A_SLUG[$i]}"
  dir="$WORK/$slug"; mkdir -p "$dir/unzipped"
  zipname="$(basename "${A_CLI_URL[$i]}")"; zip="$dir/$zipname"

  say; say "=== $slug ${A_LATEST[$i]} ==="
  say "  downloading $zipname ..."
  curl -fL --progress-bar -o "$zip" "${A_CLI_URL[$i]}" || { A_STATE[$i]="FAILED"; A_NOTE[$i]="download failed"; return; }

  # The checksum is mandatory: no checksum, no install.
  if [ -z "${A_SUMS_URL[$i]}" ]; then A_STATE[$i]="FAILED"; A_NOTE[$i]="release has no SHA256SUMS.txt"; return; fi
  expected="$(curl -fsSL "${A_SUMS_URL[$i]}" | awk -v f="$zipname" '{n=$2; sub(/^\*/,"",n); if (n==f) print $1}' | sed -n 1p)"
  actual="$(sha256 "$zip")"
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    A_STATE[$i]="FAILED"; A_NOTE[$i]="SHA-256 mismatch (expected ${expected:-none})"; return
  fi
  say "  SHA-256 verified."

  unzip -q "$zip" -d "$dir/unzipped" || { A_STATE[$i]="FAILED"; A_NOTE[$i]="could not unzip"; return; }
  newbin="$(find "$dir/unzipped" -type f -name '*-cli' | sed -n 1p)"
  [ -z "$newbin" ] && newbin="$(find "$dir/unzipped" -type f -name '*cli*' ! -name '*.txt' ! -name '*.md' | sed -n 1p)"
  [ -n "$newbin" ] || { A_STATE[$i]="FAILED"; A_NOTE[$i]="no CLI binary inside the zip"; return; }
  chmod +x "$newbin"

  if [ -n "${A_BIN[$i]}" ]; then target="${A_BIN[$i]}"; else target="$DEST/$(basename "$newbin")"; fi
  [ -w "$(dirname "$target")" ] || sudo="sudo"

  if [ -e "$target" ]; then
    $sudo cp -p "$target" "$target.bak" || { A_STATE[$i]="FAILED"; A_NOTE[$i]="could not back up $target"; return; }
  fi

  # rm + install, never cp over the old file: macOS kills a binary overwritten in place
  # ("Killed: 9" / exit code 137) because of its cached code signature.
  $sudo rm -f "$target"
  if ! $sudo install -m 755 "$newbin" "$target"; then
    [ -e "$target.bak" ] && $sudo cp -p "$target.bak" "$target"
    A_STATE[$i]="FAILED"; A_NOTE[$i]="install failed (backup restored)"; return
  fi
  $sudo xattr -d com.apple.quarantine "$target" 2>/dev/null || true

  if ! now="$("$target" --version 2>&1)"; then
    if [ -e "$target.bak" ]; then $sudo rm -f "$target"; $sudo cp -p "$target.bak" "$target"; fi
    A_STATE[$i]="REVERTED"; A_NOTE[$i]="new binary did not run; previous version restored"; return
  fi
  say "  installed at $target ($(printf '%s\n' "$now" | sed -n 1p))"
  A_STATE[$i]="DONE"
  if [ -n "${A_INST[$i]}" ]; then A_NOTE[$i]="${A_INST[$i]} -> ${A_LATEST[$i]}"; else A_NOTE[$i]="installed ${A_LATEST[$i]}"; fi
}

i=0
while [ "$i" -lt "$N" ]; do
  case "${A_STATE[$i]}" in UPDATE|INSTALL) apply_app "$i" ;; esac
  i=$((i + 1))
done

say
say "================ SUMMARY ================"
print_table

i=0
while [ "$i" -lt "$N" ]; do
  case "${A_STATE[$i]}" in FAILED|REVERTED|ERROR) exit 1 ;; esac
  i=$((i + 1))
done
exit 0
