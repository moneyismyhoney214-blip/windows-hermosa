#!/usr/bin/env bash
# check-print-untouched.sh
#
# Code-level enforcement of CLAUDE.md hard constraint #1:
#   "Never modify printing/receipt code without explicit user permission."
#
# CLAUDE.md is process documentation, not a compile-time guard. This script
# is the runtime gate: CI runs it on every push, and it fails the build if a
# commit changed any off-limits print/receipt file UNLESS the most recent
# commit message contains the marker `ALLOW-PRINT-EDIT`.
#
# That marker is a deliberate, reviewable signal — a human typed it on
# purpose, knowing the file is revenue-critical. Future agents/automation
# can't sneak edits through because the marker has to live in commit text,
# which shows up in `git log` and the PR diff.
#
# Off-limits paths (kept in sync with CLAUDE.md "Hard constraints" §1):
#   lib/services/receipt_builder_service.dart
#   lib/services/invoice_html_pdf_service.dart
#   lib/widgets/print_listener.dart
#   *_print_dispatcher.dart   (any file matching this glob)
#
# Usage:
#   bash scripts/check-print-untouched.sh                  # CI mode: HEAD vs origin/main
#   bash scripts/check-print-untouched.sh --since <ref>    # explicit base ref
#
# Exit codes:
#   0  no off-limits changes OR commit has ALLOW-PRINT-EDIT marker
#   1  off-limits change detected without marker
#   2  git misconfiguration / unable to determine base ref

set -euo pipefail

BASE_REF="origin/main"
if [ "${1:-}" = "--since" ] && [ -n "${2:-}" ]; then
  BASE_REF="$2"
fi

# In Codemagic + most CI environments the default branch is fetched; locally
# users may have a stale or missing origin/main. Fall back to the merge-base
# with `main` if origin/main is unreachable.
if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  if git rev-parse --verify main >/dev/null 2>&1; then
    BASE_REF="main"
  else
    echo "❌ Cannot resolve base ref (tried 'origin/main' and 'main')." >&2
    echo "   Pass --since <ref> explicitly." >&2
    exit 2
  fi
fi

# Files changed in this push/PR range. `...` = symmetric difference, so
# we see only the commits unique to HEAD relative to the base.
CHANGED=$(git diff --name-only "${BASE_REF}...HEAD" || true)

# Match the off-limits paths. Glob `*_print_dispatcher.dart` is handled by
# the trailing pattern in the egrep.
OFFLIMITS=$(echo "$CHANGED" | grep -E '^(lib/services/receipt_builder_service\.dart|lib/services/invoice_html_pdf_service\.dart|lib/widgets/print_listener\.dart|.*_print_dispatcher\.dart)$' || true)

if [ -z "$OFFLIMITS" ]; then
  echo "✅ check-print-untouched: no off-limits print/receipt files changed."
  exit 0
fi

# Off-limits files were touched. Check every commit in the range for the
# allow marker — finding it on ANY commit in the range counts as approval.
COMMITS=$(git log --format='%H' "${BASE_REF}..HEAD" || true)
HAS_MARKER=0
for sha in $COMMITS; do
  if git log -1 --format='%B' "$sha" | grep -q 'ALLOW-PRINT-EDIT'; then
    HAS_MARKER=1
    break
  fi
done

if [ "$HAS_MARKER" -eq 1 ]; then
  echo "✅ check-print-untouched: off-limits files changed, but commit range carries the ALLOW-PRINT-EDIT marker."
  echo "   Changed off-limits files:"
  echo "$OFFLIMITS" | sed 's/^/     - /'
  exit 0
fi

cat >&2 <<EOF
❌ check-print-untouched: off-limits print/receipt files were modified
   without the required ALLOW-PRINT-EDIT marker in any commit message.

Changed off-limits files:
EOF
echo "$OFFLIMITS" | sed 's/^/     - /' >&2

cat >&2 <<EOF

To proceed: amend or add a commit whose message contains the literal
string

    ALLOW-PRINT-EDIT

on its own line, e.g.

    fix(receipt): correct VAT rounding for Saudi 15% rate

    ALLOW-PRINT-EDIT
    Verified: existing 99 receipt-flow tests pass + manual reprint
    of invoices #4421, #4422 on a Sunmi V2s.

The marker is intentionally noisy so reviewers see the print/receipt
change is deliberate (CLAUDE.md hard constraint §1).
EOF
exit 1
