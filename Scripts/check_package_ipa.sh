#!/usr/bin/env bash
# Local check of the packaging script + the workflow YAML (no macOS needed).
set -euo pipefail
cd "$(dirname "$0")/.."

bash -n Scripts/package_ipa.sh
echo "bash -n: OK"

python3 - <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("PyYAML missing - skipping the YAML parse")
    sys.exit(0)
for path in (".github/workflows/unsigned-ipa.yml", ".github/workflows/ios.yml"):
    with open(path, encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)
    jobs = doc.get("jobs", {})
    print(f"{path}: OK, jobs={sorted(jobs)}")
PY

# A fake bundle exercises staging, the signature cleanup and the zip layout.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Legado.app/PlugIns/LegadoShare.appex/_CodeSignature"
printf '#!/bin/sh\n' > "$work/Legado.app/Legado"
printf 'x' > "$work/Legado.app/PlugIns/LegadoShare.appex/LegadoShare"
printf 'x' > "$work/Legado.app/PlugIns/LegadoShare.appex/_CodeSignature/CodeResources"
printf 'x' > "$work/Legado.app/embedded.mobileprovision"
bash Scripts/package_ipa.sh "$work/Legado.app" "$work/dist"
python3 - "$work/dist" <<'PY'
import sys, zipfile, pathlib
out = pathlib.Path(sys.argv[1])
ipa = next(out.glob("*.ipa"))
names = zipfile.ZipFile(ipa).namelist()
assert "Payload/Legado.app/Legado" in names, names[:5]
assert not any("_CodeSignature" in n for n in names), [n for n in names if "_CodeSignature" in n]
assert not any("mobileprovision" in n for n in names)
assert "Payload/Legado.app/PlugIns/LegadoShare.appex/LegadoShare" in names
print(f"ipa layout: OK ({len(names)} entries, {ipa.stat().st_size} bytes)")
PY
