#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath)
# SPDX-License-Identifier: MPL-2.0
#
# Behavioural test for .deed support in validate-action/validate-a2ml.sh.
#
# This exists because the gap it guards was invisible to every source-level
# survey. The discovery glob matched only '*.a2ml', so .deed files were never
# opened at all: the validator reported "no errors" and exited 0 having
# validated nothing. String presence of a regex is not behavioural acceptance —
# only running it settles it. So this runs the validator, and it asserts on the
# discovery COUNT, because "exit 0" is exactly what the bug produced.
#
# The four valid fixtures are one per ruled deed head (DEED-GRAMMAR-SPEC
# <<document-forms>>): estate-deed, repo-deed, praxis-deed, estate-atlas-deed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="${HERE}/../validate-a2ml.sh"
FAILURES=0

ok()   { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# The conformance directories hold .a2ml fixtures too. Isolate the .deed ones
# so the discovery count is exact rather than incidental.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/valid" "$WORK/invalid"
cp "$HERE"/valid/*.deed   "$WORK/valid/"
cp "$HERE"/invalid/*.deed "$WORK/invalid/"

echo "1. valid deeds — all four ruled heads, non-strict"
out="$(INPUT_PATH="$WORK/valid" bash "$VALIDATOR" 2>&1)"; rc=$?
grep -q 'Found 4 ' <<<"$out" && ok "discovered 4 deed files" \
    || fail "discovery: '$(grep -o 'Found [0-9]* [^ ]* file(s)' <<<"$out")' (expected 4)"
[[ $rc -eq 0 ]] && ok "exit 0" || fail "exit $rc (expected 0)"
grep -q '::error' <<<"$out" && fail "unexpected error annotation" || ok "no errors"

echo "2. valid deeds — strict"
out="$(INPUT_PATH="$WORK/valid" INPUT_STRICT=true bash "$VALIDATOR" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "exit 0 under strict" || fail "exit $rc under strict (expected 0)"

echo "3. deed-missing-head.deed — identity must be flagged"
out="$(INPUT_PATH="$WORK/invalid" bash "$VALIDATOR" 2>&1)"
grep -q 'Found 2 ' <<<"$out" && ok "discovered 2 deed files" || fail "invalid set not discovered"
grep -qi 'deed-missing-head\.deed.*identity' <<<"$out" \
    && ok "identity flagged" || fail "no identity annotation for deed-missing-head.deed"

echo "4. deed-missing-version.deed — version must be flagged"
grep -q 'deed-missing-version\.deed' <<<"$out" \
    && ok "flagged non-strict" || fail "no annotation for deed-missing-version.deed"
out="$(INPUT_PATH="$WORK/invalid" INPUT_STRICT=true bash "$VALIDATOR" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && ok "non-zero exit under strict" || fail "exit 0 under strict (expected non-zero)"

echo
if [[ $FAILURES -eq 0 ]]; then
    echo "All deed validator tests passed."
else
    echo "${FAILURES} deed validator test(s) failed."
    exit 1
fi
