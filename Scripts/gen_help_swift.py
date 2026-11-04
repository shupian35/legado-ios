#!/usr/bin/env python3
"""Generates Sources/LegadoUI/SourceEditorHelp.swift with the upstream's
jsHelp.md and regexHelp.md embedded verbatim.

The upstream files live in app/src/main/assets/web/help/md/.
"""
import pathlib
import sys

ROOT = pathlib.Path("/mnt/d/code/vscode/legado")
UPSTREAM = ROOT / "app/src/main/assets/web/help/md"
TARGET = pathlib.Path("/mnt/d/code/vscode/legado-ios/Sources/LegadoUI/SourceEditorHelp.swift")


def swift_literal(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    # A multi-line string literal must not end with a backslash before the
    # closing delimiter.
    if escaped.endswith("\\"):
        escaped = escaped[:-1] + "\\\\"
    # Every line is indented by eight spaces so that the closing delimiter can
    # keep the same indentation (Swift strips the common prefix).
    lines = escaped.split("\n")
    body = "\n".join(("        " + line) if line else "" for line in lines)
    return '        """\n' + body + '\n        """'


def main() -> int:
    js = (UPSTREAM / "jsHelp.md").read_text(encoding="utf-8")
    regex = (UPSTREAM / "regexHelp.md").read_text(encoding="utf-8")
    rule = (UPSTREAM / "ruleHelp.md").read_text(encoding="utf-8")
    body = f'''//
//  SourceEditorHelp.swift
//  LegadoUI
//
//  The help documents of the source editor.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/source/edit/BookSourceEditActivity.kt:587-624
//  app/src/main/java/io/legado/app/ui/widget/dialog/UrlOptionDialog.kt
//  app/src/main/assets/web/help/md/ruleHelp.md
//  app/src/main/assets/web/help/md/jsHelp.md
//  app/src/main/assets/web/help/md/regexHelp.md
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The help documents of the source editor — upstream
/// `BookSourceEditActivity.helpActions()`.
public enum SourceEditorHelp {{

    /// The rule syntax reference — upstream `assets/web/help/md/ruleHelp.md`.
    public static let ruleHelp = {swift_literal(rule)}

    /// The JavaScript tutorial — upstream `assets/web/help/md/jsHelp.md`.
    public static let jsHelp = {swift_literal(js)}

    /// The regular expression tutorial — upstream
    /// `assets/web/help/md/regexHelp.md`.
    public static let regexHelp = {swift_literal(regex)}
}}
'''
    TARGET.write_text(body, encoding="utf-8")
    print("written", TARGET, len(body))
    return 0


if __name__ == "__main__":
    sys.exit(main())
