#!/usr/bin/env bash
# CI-13 — dependency licence compatibility.
#
# GPL-family dependencies are incompatible with distributing under Apache 2.0 and
# are rejected AT SELECTION TIME, not discovered at release (CON-11, ADR-0017).
set -uo pipefail
FAIL=0
FORBIDDEN="GPL-2.0|GPL-3.0|AGPL|LGPL|SSPL|BUSL"

for p in packages/*/pubspec.yaml app/pubspec.yaml; do
  pkg=$(dirname "$p")
  for dep in $(awk '/^dependencies:/{f=1;next} /^[a-z_]+:/{f=0} f && /^  [a-z_]+:/{gsub(/[: ]/,"");print}' "$p"); do
    case "$dep" in lw_*|flutter|sdk) continue;; esac
    if ! grep -q "^| \`$dep\`" docs/DEPENDENCY_REGISTER.md 2>/dev/null; then
      echo "  UNREGISTERED  $dep (in $pkg) — every dependency needs a written justification (NFR-MNT-02)"
      FAIL=1
    fi
  done
done

if grep -qE "$FORBIDDEN" docs/DEPENDENCY_REGISTER.md 2>/dev/null; then
  echo "  FORBIDDEN LICENCE found in dependency register (CON-11)"
  FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "CI-13 dependency licences OK"
exit $FAIL
