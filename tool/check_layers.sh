#!/usr/bin/env bash
# CI-01 / CI-02 / CI-03 — architectural boundary enforcement.
#
# Discipline does not survive a deadline. These checks make layer violations
# impossible rather than discouraged (ARCHITECTURE.md section 2.3, ADR-0007).
set -uo pipefail
FAIL=0
say() { printf '%-6s %s\n' "$1" "$2"; }
fail(){ FAIL=1; say "FAIL" "$1"; }
pass(){ say "ok" "$1"; }

DOMAIN="packages/lw_domain"

# --- CI-01: lw_domain declares zero dependencies -----------------------------
if awk '/^dependencies:/{f=1;next} /^[a-z_]+:/{f=0} f && NF && $0 !~ /^[[:space:]]*#/' \
     "$DOMAIN/pubspec.yaml" | grep -q .; then
  fail "CI-01 lw_domain declares dependencies. It must declare none (E1, NFR-MNT-01)."
else
  pass "CI-01 lw_domain has zero dependencies"
fi

# --- CI-02: no forbidden imports in the domain -------------------------------
if grep -rEn "^import .*(package:flutter|dart:io|dart:ui|package:lw_ports|package:lw_application|package:lw_infrastructure)" \
     "$DOMAIN/lib" 2>/dev/null; then
  fail "CI-02 forbidden import in lw_domain (dependencies point inward only)."
else
  pass "CI-02 no outward imports from lw_domain"
fi

# Presentation must not reach past the application layer.
if grep -rEn "^import .*package:lw_infrastructure" app/lib 2>/dev/null; then
  fail "CI-02 app imports lw_infrastructure directly. Go through lw_application."
else
  pass "CI-02 app does not touch infrastructure directly"
fi

# --- CI-03: determinism — no ambient state in the domain ---------------------
# A single DateTime.now() makes tests non-reproducible intermittently, which is
# the worst failure mode there is. Time enters via P-CLOCK only (P4, MI-07).
if grep -rEn "DateTime\.now|Random\(|Platform\.|Locale\(|Intl\." "$DOMAIN/lib" 2>/dev/null; then
  fail "CI-03 non-deterministic construct in lw_domain (P4, MI-07)."
else
  pass "CI-03 domain is free of clock, randomness, platform and locale"
fi

# --- CI-10: no user-facing literals outside the message catalogue ------------
# The domain emits message IDs, never display text (M5, FR-LOC-01).
if grep -rEn "^[^/]*(Text\(|label:|title:)[[:space:]]*'[^']{3,}'" "$DOMAIN/lib" 2>/dev/null; then
  fail "CI-10 display text in lw_domain. Emit a messageId instead (FR-LOC-01)."
else
  pass "CI-10 no display text in domain"
fi

# --- CI-12: no INTERNET permission -------------------------------------------
# Offline operation is OS-enforced, not merely claimed (ADR-0016).

if [ ! -d "app/android" ]; then
  fail "CI-12 Android project not found. Cannot verify INTERNET permission."
elif grep -rq "android.permission.INTERNET" app/android 2>/dev/null; then
  fail "CI-12 INTERNET permission present. The MVP ships without it (NFR-OFF-02)."
else
  pass "CI-12 no INTERNET permission"
fi

exit $FAIL
