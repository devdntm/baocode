#!/bin/bash
# Builds the fork and installs it beside BaoCode as "BaoCode Dev", an app
# of its own with a data folder of its own (docs/fork.md):
#
#   tool/dev_app/build_dev_app.sh              build, then install
#   tool/dev_app/build_dev_app.sh --skip-build install what is built
#
#   FLUTTER=/path/to/flutter tool/dev_app/build_dev_app.sh
#                                              with another Flutter than
#                                              the one on PATH
#
# The app is BaoCode's release build with another bundle id and name, and
# BAOCODE_DATA_DIR set in its Info.plist's LSEnvironment: the Dart code
# takes the data folder from there (resolveDataDirectory, lib/platform/
# data_dir.dart), so nothing in it changes. The first time, the user's
# BaoCode data is copied to that folder, before the app first opens: the
# app does not make the folder BAOCODE_DATA_DIR names, it reports it
# missing. BaoCode's own folder is only read.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
flutter="${FLUTTER:-flutter}"

built="$repo/build/macos/Build/Products/Release/BaoCode.app"
app="/Applications/BaoCode Dev.app"
bundle_id="dev.baocode.desktop.dev"
name="BaoCode Dev"

support="$HOME/Library/Application Support"
source_data="$support/baocode"
data="$support/baocode-dev"

# What settings.json in the Dev folder is given. update.mode always: an
# update would replace the fork with upstream's release. The others only
# where the user has not set them in Dev, as each feature lands.
forced_settings='{"update.mode": "none"}'
default_settings='{"workbench.ide.layout": "cursor", "chat.look": "cursor", "workbench.scroll.momentum": "system"}'

skip_build=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) skip_build=true ;;
    -h | --help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 64
      ;;
  esac
done

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

if [[ "$(uname)" != Darwin ]]; then
  echo "BaoCode Dev is a macOS app." >&2
  exit 1
fi

if pgrep -f "$app/Contents/MacOS/" >/dev/null; then
  echo "$name is open: quit it first." >&2
  exit 1
fi

# The app.
if ! $skip_build; then
  say "flutter build macos --release"
  (cd "$repo" && "$flutter" build macos --release)
fi
if [[ ! -d "$built" ]]; then
  echo "No build at $built: run without --skip-build." >&2
  exit 1
fi

plist="$app/Contents/Info.plist"
if [[ -d "$app" ]]; then
  # Only ever replace an app this script made.
  existing="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  if [[ "$existing" != "$bundle_id" ]]; then
    echo "$app is not $name ($existing): not replacing it." >&2
    exit 1
  fi
  rm -rf "$app"
fi

say "Installing $app"
ditto "$built" "$app"

buddy() { /usr/libexec/PlistBuddy -c "$1" "$plist"; }
buddy "Set :CFBundleIdentifier $bundle_id"
buddy "Set :CFBundleName $name"
buddy "Delete :CFBundleDisplayName" 2>/dev/null || true
buddy "Add :CFBundleDisplayName string $name"
buddy "Delete :LSEnvironment" 2>/dev/null || true
buddy "Add :LSEnvironment dict"
buddy "Add :LSEnvironment:BAOCODE_DATA_DIR string $data"
# baocode:// stays BaoCode's: with two apps claiming it, the system picks
# either.
buddy "Delete :CFBundleURLTypes" 2>/dev/null || true
# The Finder extension has BaoCode's id: a second one would stand in for
# it.
rm -rf "$app/Contents/PlugIns/FinderExtension.appex"

say "Signing ad hoc"
codesign --force --deep --preserve-metadata=entitlements --sign - "$app"
codesign --verify --deep --strict "$app"
# For Launch Services to read the new Info.plist (LSEnvironment among it),
# not what it kept of the build it was copied from.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"

# The data.
if [[ ! -d "$data" ]]; then
  if [[ ! -d "$source_data" ]]; then
    say "No $source_data: $name starts with an empty folder"
    mkdir -p "$data/User"
  else
    say "Copying $source_data to $data"
    partial="$data.partial-$$"
    rm -rf "$partial"
    trap 'rm -rf "$partial"' EXIT
    # Clones on APFS (cp -c), which take next to no room; a plain copy
    # elsewhere.
    cp -cR "$source_data" "$partial" 2>/dev/null || {
      rm -rf "$partial"
      cp -R "$source_data" "$partial"
    }
    # What only BaoCode's run means: the processes it started, and the
    # updates it downloaded. And the launcher of its Claude Code, which
    # names its folder: the app writes Dev's own.
    rm -f "$partial"/state/*-processes.json
    rm -rf "$partial/updates" "$partial/claude/bin/claude"
    mkdir -p "$partial/User"
    mv "$partial" "$data"
    trap - EXIT
  fi
fi

say "Settings in $data/User/settings.json"
mkdir -p "$data/User"
python3 -I - "$data/User/settings.json" "$forced_settings" "$default_settings" <<'PY'
import json, os, sys

path, forced, defaults = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3])
settings = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as file:
        text = file.read()
    if text.strip():
        try:
            settings = json.loads(text)
        except json.JSONDecodeError as error:
            sys.exit(f"{path} is not plain JSON ({error}): set {forced} by hand.")
for key, value in defaults.items():
    settings.setdefault(key, value)
settings.update(forced)
aside = f"{path}.{os.getpid()}.tmp"
with open(aside, "w", encoding="utf-8") as file:
    json.dump(settings, file, indent=4, ensure_ascii=False)
    file.write("\n")
os.replace(aside, path)
PY

say "Done: open $name from /Applications"
