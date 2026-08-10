#!/usr/bin/env python3
"""Compute the rule pack integrity digest.

Implements the normative algorithm of DATA_MODEL.md section 7.2. This is the
second of two implementations; packages/lw_rulepack/lib/src/integrity.dart is
the first. CI-17 compares both against the recorded manifest value, which is
the arrangement that would have caught the drift that opened Milestone 10 --
a recorded hash describing a wider file set than it covered, with no tool that
could reproduce it.

Usage:
  compute_rulepack_hash.py [PACK_DIR]         print the computed digest
  compute_rulepack_hash.py --check [PACK_DIR] compare against the manifest
  compute_rulepack_hash.py --write [PACK_DIR] update the manifest in place
"""

from __future__ import annotations

import hashlib
import json
import os
import sys

DEFAULT_PACK = "rulepack"
MANIFEST = "manifest.json"
PREFIX = "sha256:"

# The scope rule of section 7.2, stated once. manifest.json cannot contain its
# own digest. schema/ is validation scaffolding the runtime never reads, and
# LICENSE is legal text -- hashing either would let a change that cannot affect
# behaviour invalidate a shipped pack.
EXCLUDED_FILES = {MANIFEST, "LICENSE"}
EXCLUDED_DIRS = ("schema/",)


def is_content_file(rel: str) -> bool:
    """Whether rel contributes to the digest."""
    if rel in EXCLUDED_FILES:
        return False
    return not any(rel.startswith(d) for d in EXCLUDED_DIRS)


def content_files(pack_dir: str) -> list[str]:
    """Every content file, ascending byte-wise by relative path."""
    found = []
    for dirpath, _, filenames in os.walk(pack_dir):
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, pack_dir).replace(os.sep, "/")
            if is_content_file(rel):
                found.append(rel)
    # Byte-wise on the UTF-8 path, not locale collation: a digest must never
    # depend on the machine that computed it.
    return sorted(found, key=lambda p: p.encode("utf-8"))


def compute(pack_dir: str) -> str:
    """The digest of pack_dir, as recorded in the manifest."""
    digest = hashlib.sha256()
    for rel in content_files(pack_dir):
        # The path is hashed as well as the bytes. Without it, two files whose
        # contents were exchanged would produce an identical digest.
        digest.update(rel.encode("utf-8"))
        with open(os.path.join(pack_dir, rel), "rb") as handle:
            digest.update(handle.read())
    return PREFIX + digest.hexdigest()


def recorded(pack_dir: str) -> str:
    """The digest the manifest claims."""
    with open(os.path.join(pack_dir, MANIFEST), encoding="utf-8") as handle:
        return json.load(handle)["integrityHash"]


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = {a for a in argv[1:] if a.startswith("--")}
    pack_dir = args[0] if args else DEFAULT_PACK

    if not os.path.isdir(pack_dir):
        print(f"  no such pack directory: {pack_dir}", file=sys.stderr)
        return 2

    actual = compute(pack_dir)

    if "--write" in flags:
        path = os.path.join(pack_dir, MANIFEST)
        with open(path, encoding="utf-8") as handle:
            manifest = json.load(handle)
        manifest["integrityHash"] = actual
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(manifest, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        print(f"  manifest updated: {actual}")
        return 0

    if "--check" in flags:
        claimed = recorded(pack_dir)
        if actual == claimed:
            n = len(content_files(pack_dir))
            print(f"CI-17 integrity hash matches ({n} content files)")
            return 0
        print("  CI-17 INTEGRITY HASH MISMATCH", file=sys.stderr)
        print(f"    recorded: {claimed}", file=sys.stderr)
        print(f"    computed: {actual}", file=sys.stderr)
        print("    files hashed:", file=sys.stderr)
        for rel in content_files(pack_dir):
            print(f"      {rel}", file=sys.stderr)
        print(
            "    Run tool/compute_rulepack_hash.py --write after an "
            "intentional content change.",
            file=sys.stderr,
        )
        return 1

    print(actual)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
