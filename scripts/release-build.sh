#!/usr/bin/env bash
set -euo pipefail

# Release build that pins the exact gitw-askpass SHA-256 into GitwCore.
#
# Usage:
#   ./scripts/release-build.sh
#
# Output:
#   .build/release/gitw
#   .build/release/gitw-askpass

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 1) Build askpass first
swift build -c release --product gitw-askpass

ASKPASS_BIN="$ROOT_DIR/.build/release/gitw-askpass"
if [[ ! -x "$ASKPASS_BIN" ]]; then
  echo "error: expected askpass binary at: $ASKPASS_BIN" >&2
  exit 1
fi

# 2) Compute SHA-256
if command -v shasum >/dev/null 2>&1; then
  ASKPASS_SHA256="$(shasum -a 256 "$ASKPASS_BIN" | awk '{print $1}')"
else
  echo "error: shasum not found" >&2
  exit 1
fi

# 3) Generate AskpassTrust.swift
TEMPLATE="$ROOT_DIR/Sources/GitwCore/AskpassTrust.swift.in"
OUTFILE="$ROOT_DIR/Sources/GitwCore/AskpassTrust.swift"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "error: missing template: $TEMPLATE" >&2
  exit 1
fi

# macOS sed needs -i ''
sed -e "s/@ASKPASS_SHA256@/${ASKPASS_SHA256}/g" "$TEMPLATE" > "$OUTFILE"

echo "Pinned gitw-askpass SHA-256: $ASKPASS_SHA256"

# 4) Build gitw (now embedding the hash)
swift build -c release --product gitw

# 5) Optional: sanity-check the embedded hash matches the built askpass
if [[ -x "$ROOT_DIR/.build/release/gitw" ]]; then
  echo "Release build complete."
fi
