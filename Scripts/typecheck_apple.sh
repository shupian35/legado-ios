#!/usr/bin/env bash
#
#  typecheck_apple.sh
#
#  Type-checks the **Apple-only** code paths of the port on Linux.
#
#  Why: the `#if canImport(UIKit)` (and WebKit / AVFoundation / MediaPlayer /
#  CoreImage / CoreText / PDFKit / UserNotifications) blocks are never compiled
#  by the Linux build — the Swift parser checks their *syntax* but not their
#  *types*. A type error in one of them therefore only shows up when somebody
#  opens the project in Xcode, which is exactly the kind of bug that must not
#  survive a port.
#
#  How: the stub modules under `Scripts/apple-stubs` declare the Apple API the
#  port uses, with the real signatures. Putting them on the import search path
#  makes `canImport(UIKit)` true, so the same sources are compiled with the
#  Apple branches enabled and every type error is reported here.
#
#  The stubs are never linked and never run — they exist for the type checker.
#
set -uo pipefail

REPO="${SWIFT_REPO:-/mnt/d/code/vscode/legado-ios}"
STUBS="$REPO/Scripts/apple-stubs"
SCRATCH="${SWIFT_SCRATCH:-/home/shupian/.cache/legado-swift-build}"
OUT="$SCRATCH/apple-typecheck"
PREBUILT="$SCRATCH/debug"
CZMAP="$SCRATCH/out/Intermediates.noindex/GeneratedModuleMaps-linux-x86_64"

export PATH="/home/shupian/swift/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

rm -rf "$OUT"
mkdir -p "$OUT"

FAILED=0

# Compiles one stub module.
module() {
    local name="$1"
    shift
    if ! swiftc -emit-module -emit-module-path "$OUT/$name.swiftmodule" \
        -module-name "$name" -swift-version 5 "$@" ; then
        echo "!! the stub module $name did not compile"
        FAILED=1
    fi
}

echo "== the stub modules =="
module UIKit "$STUBS/UIKit.swift"
module AVFoundation "$STUBS/AVFoundation.swift" -I "$OUT"
module WebKit "$STUBS/WebKit.swift" -I "$OUT"
module MediaPlayer "$STUBS/MediaPlayer.swift" -I "$OUT"
module CoreImage "$STUBS/CoreImage.swift" -I "$OUT"
module CoreText "$STUBS/CoreText.swift" -I "$OUT"
module PDFKit "$STUBS/PDFKit.swift" -I "$OUT"
module UserNotifications "$STUBS/UserNotifications.swift" -I "$OUT"

if [ "$FAILED" -ne 0 ]; then
    echo "!! the stub modules did not compile — the type check cannot run"
    exit 1
fi

# The third party modules the port needs (SwiftSoup) and the SwiftUI shim are
# taken from the normal build so that both stay in sync with it.
PRODUCTS=""
for candidate in \
    "$SCRATCH/out/Products/Debug-linux-x86_64" \
    "$SCRATCH/debug" \
    "$REPO/.build/debug" \
    "$REPO/.build/x86_64-unknown-linux-gnu/debug" ; do
    if [ -d "$candidate/LegadoUIShim.swiftmodule" ]; then
        PRODUCTS="$candidate"
        break
    fi
done
if [ -z "$PRODUCTS" ]; then
    echo "!! the built modules are missing — run 'sw.sh build' first"
    exit 1
fi
echo "the built modules: $PRODUCTS"
for module in SwiftSoup LegadoUIShim; do
    if [ -d "$PRODUCTS/$module.swiftmodule" ]; then
        cp -r "$PRODUCTS/$module.swiftmodule" "$OUT/"
    else
        echo "!! $module.swiftmodule is missing — run 'sw.sh build' first"
        exit 1
    fi
done

# The zlib bridge is a C target — the module map of the build points at a
# header name that only exists on a case insensitive file system, so the type
# check writes its own.
cat > "$OUT/CZlib.modulemap" <<MAP
module CZlib {
umbrella header "$REPO/Sources/CZlib/include/czlib.h"
export *
}
MAP

SEARCH="-I $OUT -Xcc -fmodule-map-file=$OUT/CZlib.modulemap"

echo "== LegadoCore (with the Apple branches enabled) =="
CORE_SOURCES=$(find "$REPO/Sources/LegadoCore" -name '*.swift' | sort)
# The Linux companions of the Darwin Foundation API (the `size()` of an
# attributed string, the `.font` key) — compiled into the module.
CORE_SOURCES="$CORE_SOURCES $STUBS/linux-foundation-compat.swift"
# shellcheck disable=SC2086
if ! swiftc -emit-module -emit-module-path "$OUT/LegadoCore.swiftmodule" \
    -module-name LegadoCore -swift-version 5 $SEARCH $CORE_SOURCES ; then
    FAILED=1
fi

echo "== LegadoUI (with the Apple branches enabled) =="
UI_SOURCES=$(find "$REPO/Sources/LegadoUI" -name '*.swift' | sort)
# shellcheck disable=SC2086
if ! swiftc -emit-module -emit-module-path "$OUT/LegadoUI.swiftmodule" \
    -module-name LegadoUI -swift-version 5 $SEARCH $UI_SOURCES ; then
    FAILED=1
fi

echo "== LegadoApp (with the Apple branches enabled) =="
APP_SOURCES=$(find "$REPO/Sources/LegadoApp" -name '*.swift' | sort)
# shellcheck disable=SC2086
if ! swiftc -typecheck -module-name LegadoApp -swift-version 5 $SEARCH $APP_SOURCES ; then
    FAILED=1
fi

# The iOS entry point — it only exists in the Xcode project, so the Linux
# build never compiles it. It is the file that must not break.
echo "== LegadoAppUI (the iOS entry point) =="
APPUI_SOURCES=$(find "$REPO/Sources/LegadoAppUI" -name '*.swift' | sort)
# shellcheck disable=SC2086
if ! swiftc -typecheck -parse-as-library -module-name LegadoAppUI -swift-version 5 $SEARCH $APPUI_SOURCES ; then
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "!! the Apple-only code paths do NOT type-check"
    exit 1
fi

echo "OK — the Apple-only code paths type-check"
