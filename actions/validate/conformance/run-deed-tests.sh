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

ok()   { local msg="$1"; echo "  PASS: $msg"; return 0; }
fail() { local msg="$1"; echo "  FAIL: $msg" >&2; FAILURES=$((FAILURES + 1)); return 0; }

# The two diagnostics under test, named once so a wording change cannot leave
# an assertion quietly matching nothing.
NO_IDENTITY='No identity found'
NO_VERSION='Missing version or schema_version field'

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

# assert_ann <severity> <fixture-regex> <message-substring>
# Anchored on the fixture AND the message: "the filename appears somewhere in
# the output" was satisfiable by any annotation at all, so a broken version
# check still passed. `file=[^,]*` keeps the path free but stops the regex
# wandering into the next annotation.
assert_ann() {
    local severity="$1" fixture="$2" message="$3"
    grep -qE "::$severity file=[^,]*$fixture,line=[0-9]+::.*$message" <<<"$out" \
        && ok "$fixture -> ::$severity ($message)" \
        || fail "$fixture: expected ::$severity matching '$message'"
    return 0
}

echo "3. invalid deeds — non-strict: every diagnostic, per fixture"
out="$(INPUT_PATH="$WORK/invalid" bash "$VALIDATOR" 2>&1)"; rc=$?
grep -q 'Found 5 ' <<<"$out" && ok "discovered 5 deed files" \
    || fail "discovery: '$(grep -o 'Found [0-9]* [^ ]* file(s)' <<<"$out")' (expected 5)"
[[ $rc -eq 0 ]] && ok "exit 0 (identity and version are warnings here)" \
    || fail "exit $rc non-strict (expected 0)"
assert_ann warning 'deed-missing-head\.deed'          "$NO_IDENTITY"
assert_ann warning 'deed-missing-head\.deed'          "$NO_VERSION"
assert_ann warning 'deed-missing-version\.deed'       "$NO_VERSION"
# :registry-version is optional atlas metadata, never a schema version.
assert_ann warning 'deed-registry-version-only\.deed' "$NO_VERSION"
# A head that is not the FIRST form does not identify the document.
assert_ann warning 'deed-head-not-first\.deed'        "$NO_IDENTITY"
# The AI-MANIFEST exemption is for .a2ml prose; a .deed is still a deed.
assert_ann warning 'example-AI-MANIFEST\.deed'        "$NO_IDENTITY"
assert_ann warning 'example-AI-MANIFEST\.deed'        "$NO_VERSION"
# Negative control: a diagnostic naming a fixture that has none would mean the
# anchoring above is matching across annotation boundaries.
grep -qE "::warning file=[^,]*deed-registry-version-only\.deed,line=[0-9]+::$NO_IDENTITY" <<<"$out" \
    && fail "atlas head wrongly reported identity-less" || ok "atlas head still identifies"

echo "4. invalid deeds — strict promotes every warning to an error"
out="$(INPUT_PATH="$WORK/invalid" INPUT_STRICT=true bash "$VALIDATOR" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && ok "non-zero exit under strict" || fail "exit 0 under strict (expected non-zero)"
assert_ann error 'deed-missing-head\.deed'          "$NO_IDENTITY"
assert_ann error 'deed-missing-version\.deed'       "$NO_VERSION"
assert_ann error 'deed-registry-version-only\.deed' "$NO_VERSION"
assert_ann error 'deed-head-not-first\.deed'        "$NO_IDENTITY"
assert_ann error 'example-AI-MANIFEST\.deed'        "$NO_VERSION"
grep -q '::warning' <<<"$out" && fail "::warning survived strict" || ok "no ::warning survives strict"

echo
if [[ $FAILURES -eq 0 ]]; then
    echo "All deed validator tests passed."
else
    echo "${FAILURES} deed validator test(s) failed." >&2
    exit 1
fi
