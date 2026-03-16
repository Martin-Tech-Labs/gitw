#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build

BIN="$ROOT_DIR/.build/debug/gitw"
if [[ ! -x "$BIN" ]]; then
  echo "error: gitw binary not found at: $BIN" >&2
  exit 1
fi

echo "[acceptance] gitw binary: $BIN"

# 1) Missing --as should fail closed
set +e
OUT="$($BIN whoami 2>&1)"
CODE=$?
set -e
if [[ $CODE -eq 0 ]]; then
  echo "[acceptance] expected whoami without --as to fail, got exit 0" >&2
  echo "$OUT" >&2
  exit 1
fi
if ! echo "$OUT" | grep -qi "Missing --as"; then
  echo "[acceptance] expected 'Missing --as' message" >&2
  echo "$OUT" >&2
  exit 1
fi

echo "[acceptance] ok: missing --as fails"

# 2) Missing --as for git invocation should fail closed
set +e
OUT="$($BIN status 2>&1)"
CODE=$?
set -e
if [[ $CODE -eq 0 ]]; then
  echo "[acceptance] expected git invocation without --as to fail, got exit 0" >&2
  echo "$OUT" >&2
  exit 1
fi
if ! echo "$OUT" | grep -qi "Missing --as"; then
  echo "[acceptance] expected 'Missing --as' message (git invocation)" >&2
  echo "$OUT" >&2
  exit 1
fi

echo "[acceptance] ok: git invocation missing --as fails"
