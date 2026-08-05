#!/usr/bin/env bash
# CI-15 — every P0-v0.1 requirement maps to at least one test.
#
# Without this, 152 P0 requirements quietly become documentation rather than
# specification, and nobody discovers which were never verified until something
# breaks in the field (NFR-TST-05).
#
# Convention: a test that verifies a requirement names it in its description,
# e.g. test('FR-CNF-05 a failed invariant caps confidence below HIGH', ...)
set -uo pipefail

REQ_DOC="docs/REQUIREMENTS.md"
MISSING=0

P0=$(grep -oE '^\| ((FR|NFR)-[A-Z]+[0-9]?-[0-9]+) \| .* \| P0-v0\.1 \|' "$REQ_DOC" \
     | grep -oE '(FR|NFR)-[A-Z]+[0-9]?-[0-9]+' | sort -u)
TOTAL=$(echo "$P0" | grep -c . || true)

COVERED=$(grep -rhoE '(FR|NFR)-[A-Z]+[0-9]?-[0-9]+' \
          packages/*/test app/test 2>/dev/null | sort -u || true)

for r in $P0; do
  if ! echo "$COVERED" | grep -qx "$r"; then
    echo "  UNCOVERED  $r"
    MISSING=$((MISSING+1))
  fi
done

echo "CI-15  P0-v0.1 requirements: $TOTAL | uncovered: $MISSING"
[ "$MISSING" -eq 0 ] || { echo "CI-15 FAILED"; exit 1; }
