#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT_DIR/dist/licenses/relaytv-THIRD_PARTY_LICENSES.md}"

mkdir -p "$(dirname "$OUT")"

{
  cat <<'EOF'
# RelayTV Third-Party License Inventory

Generated inventory for a RelayTV build/runtime environment.

This file supplements the source repository overview in `THIRD_PARTY_LICENSES.md`.
It is generated from installed package metadata where available. Package
metadata can be incomplete; verify important license obligations against
upstream package sources before redistribution.

EOF

  printf 'Generated at: `%s`\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Source revision: `%s`\n\n' "$(git -C "$ROOT_DIR" rev-parse HEAD)"
  fi

  cat <<'EOF'
## Python Packages

| Name | Version | License metadata |
| --- | --- | --- |
EOF

  python3 - <<'PY'
from importlib import metadata

rows = []
for dist in metadata.distributions():
    meta = dist.metadata
    name = meta.get("Name") or dist.metadata.get("Summary") or "unknown"
    version = dist.version or ""
    license_value = meta.get("License-Expression") or meta.get("License") or ""
    classifiers = [
        value.removeprefix("License :: ").strip()
        for value in meta.get_all("Classifier", [])
        if value.startswith("License :: ")
    ]
    if not license_value and classifiers:
        license_value = "; ".join(classifiers)
    rows.append((name, version, license_value or "unknown"))

for name, version, license_value in sorted(rows, key=lambda row: row[0].lower()):
    safe = [str(part).replace("|", "\\|").replace("\n", " ") for part in (name, version, license_value)]
    print(f"| {safe[0]} | {safe[1]} | {safe[2]} |")
PY

  cat <<'EOF'

## Debian Packages

EOF

  if command -v dpkg-query >/dev/null 2>&1; then
    cat <<'EOF'
| Package | Version |
| --- | --- |
EOF
    dpkg-query -W -f='| ${binary:Package} | ${Version} |\n' | sort -f
  else
    cat <<'EOF'
Debian package metadata is unavailable because `dpkg-query` was not found in
this environment.
EOF
  fi

  cat <<'EOF'

## Bundled RelayTV Assets

RelayTV bundles project artwork, screenshots, and weather/UI assets. See
`ASSETS.md` for project mark and bundled asset usage rules.

EOF
} > "$OUT"

printf 'Wrote %s\n' "$OUT"
