#!/usr/bin/env bash
# Package a built iOS `.app` bundle into an UNSIGNED `.ipa`.
#
# An unsigned `.ipa` is just a zip with a `Payload/<Name>.app` directory in it;
# nothing in it is signed, no provisioning profile is embedded. It is the input
# for the tools that sign on the user's side (Sideloadly, AltStore, TrollStore,
# `codesign` + `xcrun devicectl`) and it is what the `Unsigned IPA` GitHub
# workflow uploads as an artifact.
#
# Usage (on macOS, after `xcodebuild build ... CODE_SIGNING_ALLOWED=NO`):
#   bash Scripts/package_ipa.sh [path/to/Legado.app] [output-dir]
#
# Defaults:
#   app        .build/xcode-ios/Build/Products/Release-iphoneos/Legado.app
#   output dir dist
#
# Environment overrides:
#   IPA_NAME   base name of the produced file (default Legado-<version>-unsigned)
set -euo pipefail

if ! command -v zip >/dev/null 2>&1; then
  printf 'error: `zip` is required (macOS ships it; on Linux: apt-get install zip)\n' >&2
  exit 1
fi

APP="${1:-.build/xcode-ios/Build/Products/Release-iphoneos/Legado.app}"
OUT_DIR="${2:-dist}"

if [ ! -d "$APP" ]; then
  printf 'error: no app bundle at %s\n' "$APP" >&2
  printf 'hint: build it first, e.g.\n' >&2
  printf '  xcodebuild build -project LegadoApp.xcodeproj -scheme LegadoApp \\\n' >&2
  printf '    -configuration Release -destination "generic/platform=iOS" \\\n' >&2
  printf '    -derivedDataPath .build/xcode-ios CODE_SIGNING_ALLOWED=NO\n' >&2
  exit 1
fi

# Absolute paths, so the subshells below cannot pick up the wrong directory.
APP="$(cd "$APP" && pwd)"
APP_NAME="$(basename "$APP")"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

PLIST="$APP/Info.plist"
plist_value() {
  # /usr/libexec/PlistBuddy ships with macOS; fall back to a silent default.
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true
}
VERSION="$(plist_value CFBundleShortVersionString)"
BUILD="$(plist_value CFBundleVersion)"
BUNDLE_ID="$(plist_value CFBundleIdentifier)"
VERSION="${VERSION:-0.0.0}"
BUILD="${BUILD:-0}"
BUNDLE_ID="${BUNDLE_ID:-unknown}"

IPA_NAME="${IPA_NAME:-Legado-${VERSION}-unsigned}"
IPA="$OUT_DIR/${IPA_NAME}.ipa"
rm -f "$IPA"

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
STAGED="$STAGE/Payload/$APP_NAME"

# An unsigned build should already be clean, but a stale `build/` directory or a
# previous signed attempt must not leak a signature into the ipa: the tools that
# re-sign reject a bundle whose `_CodeSignature` does not match its contents.
rm -rf "$STAGED/_CodeSignature"
find "$STAGED" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
find "$STAGED" -name "*.mobileprovision" -type f -delete 2>/dev/null || true

# -X strips the extra file attributes so the archive is reproducible; -y keeps
# the symlinks (framework slices) as links.
( cd "$STAGE" && zip -qry -X "$IPA" Payload )

EXECUTABLE_NAME="$(plist_value CFBundleExecutable)"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-${APP_NAME%.app}}"
EXECUTABLE="$STAGED/$EXECUTABLE_NAME"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

{
  echo "ipa:         $IPA"
  echo "bundle:      $BUNDLE_ID"
  echo "version:     $VERSION ($BUILD)"
  echo "size:        $(du -h "$IPA" | cut -f1)"
  echo "sha256:      $(sha256_of "$IPA")"
} > "$IPA.txt"

if [ -f "$EXECUTABLE" ] && command -v lipo >/dev/null 2>&1; then
  echo "architectures: $(lipo -archs "$EXECUTABLE" 2>/dev/null || echo unknown)" >> "$IPA.txt"
fi

# Sanity checks: the payload must hold the app and its executable, and the
# bundle must really be unsigned (otherwise the file is not what it claims).
if [ ! -f "$EXECUTABLE" ]; then
  printf 'error: %s has no executable at %s\n' "$APP_NAME" "$EXECUTABLE" >&2
  exit 1
fi
if [ -d "$STAGED/_CodeSignature" ]; then
  printf 'error: the bundle is signed (_CodeSignature survived)\n' >&2
  exit 1
fi

cat "$IPA.txt"
printf '\nThe ipa is UNSIGNED: it runs only after it is signed on the device side\n'
printf '(Sideloadly / AltStore / TrollStore) or from Xcode.\n'
