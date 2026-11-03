#!/usr/bin/env bash
# Run swift/swift-build/swift-test inside the WSL toolchain with a clean, deterministic PATH.
# Usage (from Windows / PowerShell):
#   wsl -d Ubuntu -- bash /mnt/d/code/vscode/legado-ios/Scripts/sw.sh build
#   wsl -d Ubuntu -- bash /mnt/d/code/vscode/legado-ios/Scripts/sw.sh test
#   wsl -d Ubuntu -- bash /mnt/d/code/vscode/legado-ios/Scripts/sw.sh --version
# Environment overrides:
#   SWIFT_REPO    path (inside WSL) of the SwiftPM package (default /mnt/d/code/vscode/legado-ios)
#   SWIFT_SCRATCH build scratch dir                          (default /tmp/legado-swift-build)
set -euo pipefail

export PATH="$HOME/swift/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

SWIFT_REPO="${SWIFT_REPO:-/mnt/d/code/vscode/legado-ios}"
# NOTE: keep the scratch dir on the persistent ext4 volume (/home) — WSL wipes
# /tmp on every shutdown, which would force a re-fetch of SwiftSoup and a full
# rebuild each time.
SWIFT_SCRATCH="${SWIFT_SCRATCH:-/home/shupian/.cache/legado-swift-build}"

if [ "$#" -eq 0 ]; then
  exec swift --version
fi

case "$1" in
  build|test|run|package|plugin|resolve|update|clean)
    cd "$SWIFT_REPO"
    exec swift "$@" --scratch-path "$SWIFT_SCRATCH"
    ;;
  *)
    exec swift "$@"
    ;;
esac
