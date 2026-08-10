#!/usr/bin/env bash
# CI-07 / CI-08 / CI-09 — rule pack validation.
#
# CI is the authority. The runtime performs an integrity check only; re-validating
# on device would cost startup budget to re-prove what CI already proved
# (ARCHITECTURE.md section 9.3, FR-KB-03).
set -uo pipefail
FAIL=0

command -v check-jsonschema >/dev/null 2>&1 || {
  echo "check-jsonschema not installed (pip install check-jsonschema)"; exit 2; }

# --- CI-07: schema validation ------------------------------------------------
declare -A MAP=(
  ["rulepack/manifest.json"]="rulepack/schema/manifest.schema.json"
  ["rulepack/sources.json"]="rulepack/schema/sources.schema.json"
  ["rulepack/nutrients/synonyms.json"]="rulepack/schema/synonyms.schema.json"
  ["rulepack/nutrients/rda.json"]="rulepack/schema/rda.schema.json"
  ["rulepack/rules/thresholds.json"]="rulepack/schema/thresholds.schema.json"
  ["rulepack/rules/confidence.json"]="rulepack/schema/confidence.schema.json"
  ["rulepack/additives/ins.json"]="rulepack/schema/ins.schema.json"
  ["rulepack/categories/categories.json"]="rulepack/schema/categories.schema.json"
)
for f in "${!MAP[@]}"; do
  [ -f "$f" ] || { echo "  MISSING $f"; FAIL=1; continue; }
  check-jsonschema --schemafile "${MAP[$f]}" "$f" || FAIL=1
done
for m in rulepack/messages/*.json; do
  [ -f "$m" ] || continue
  check-jsonschema --schemafile rulepack/schema/messages.schema.json "$m" || FAIL=1
done

# --- CI-08 / CI-09: referential integrity ------------------------------------
# A dangling reference must fail the build, not a user's scan (FR-EXP-04, MI-05).
python3 - <<'PY' || FAIL=1
import json, sys, glob, os
def load(p):
    return json.load(open(p)) if os.path.exists(p) else None

bad = []
srcs = load("rulepack/sources.json")
source_ids = {s["sourceId"] for s in srcs["sources"]} if srcs else set()

msgs = set()
for m in glob.glob("rulepack/messages/*.json"):
    msgs |= set(load(m)["messages"].keys())

th = load("rulepack/rules/thresholds.json")
if th:
    for r in th["rules"]:
        # CI-09: every advisory rule cites at least one source.
        if not r.get("sourceRefs"):
            bad.append(f"CI-09 rule {r['ruleId']} has no citation")
        for s in r.get("sourceRefs", []):
            if s not in source_ids:
                bad.append(f"CI-08 rule {r['ruleId']} -> unknown source {s}")
        if r["messageId"] not in msgs:
            bad.append(f"CI-08 rule {r['ruleId']} -> unknown message {r['messageId']}")

ins = load("rulepack/additives/ins.json")
if ins:
    for a in ins["additives"]:
        for s in a.get("sourceRefs", []):
            if s not in source_ids:
                bad.append(f"CI-08 INS {a['insNumber']} -> unknown source {s}")
        if a["descriptionMessageId"] not in msgs:
            bad.append(f"CI-08 INS {a['insNumber']} -> unknown message")

for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
PY

# --- CI-16: canonical serialised form -----------------------------------------
# An absent qualifier MEANS EXACT. Emitting it explicitly produces byte-different
# output for identical data, which breaks the integrity hash, FR-PAR-02 determinism
# and golden-corpus comparison (ADR-0027 decision 5).
if grep -rn '"qualifier"[[:space:]]*:[[:space:]]*"EXACT"' rulepack/ corpus/ 2>/dev/null; then
  echo "  CI-16 non-canonical serialisation: omit the qualifier when EXACT"
  FAIL=1
else
  echo "CI-16 canonical serialisation OK"
fi

# --- CI-17: integrity hash ----------------------------------------------------
# The algorithm is normative in DATA_MODEL.md section 7.2. Before this check the
# recorded hash described a wider file set than it covered and nothing noticed,
# because no tool recomputed it. A checksum nobody can reproduce is not
# integrity verification.
python3 tool/compute_rulepack_hash.py --check rulepack || FAIL=1

# --- CI-19: the bundled copy is the authored pack -----------------------------
# app/assets/rulepack/ is what actually ships. It is a copy of rulepack/, and a
# copy that nothing compares is a copy that silently goes stale — the app would
# ship knowledge the repository does not contain, and every review would look at
# the wrong file. Found during Milestone 10, when an edit to rulepack/ left the
# bundled copy behind.
if [ -d app/assets/rulepack ]; then
  if diff -rq rulepack app/assets/rulepack >/dev/null 2>&1; then
    echo "CI-19 bundled rule pack matches the authored pack"
  else
    echo "  CI-19 app/assets/rulepack differs from rulepack/:"
    diff -rq rulepack app/assets/rulepack 2>&1 | sed 's/^/    /'
    echo "    Run: rm -rf app/assets/rulepack && cp -r rulepack app/assets/rulepack"
    FAIL=1
  fi
  python3 tool/compute_rulepack_hash.py --check app/assets/rulepack || FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "CI-07/08/09/16/17 rule pack valid" || echo "rule pack validation FAILED"
exit $FAIL
