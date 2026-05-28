#!/usr/bin/env bash
# Refresh the leaf-cert SHA-256 pin for portal.hermosaapp.com.
#
# Let's Encrypt rotates leaf certs every ~90 days, so the value baked
# into `lib/services/security/certificate_pinning.dart` goes stale
# on a predictable cadence. Run this script before each release (or
# in CI) so a freshly built APK ships with the current pin.
#
# Usage:
#   scripts/refresh-cert-pins.sh                # prints diff, dry run
#   scripts/refresh-cert-pins.sh --apply        # writes the file in place
#
# Exit codes:
#   0 — pin is up to date (or successfully updated when --apply set)
#   1 — pin needs update (dry-run mode only)
#   2 — could not fetch the live cert

set -euo pipefail

HOSTS=(portal.hermosaapp.com)
FILE="lib/services/security/certificate_pinning.dart"
APPLY="${1:-}"

cd "$(git rev-parse --show-toplevel)"

if [[ ! -f "$FILE" ]]; then
  echo "❌ $FILE not found — run from repo root" >&2
  exit 2
fi

needs_update=0

for host in "${HOSTS[@]}"; do
  live_pin=$(
    openssl s_client \
      -connect "${host}:443" \
      -servername "$host" \
      -showcerts </dev/null 2>/dev/null \
    | openssl x509 -outform DER 2>/dev/null \
    | openssl dgst -sha256 -hex \
    | awk '{print $NF}'
  )

  if [[ -z "$live_pin" ]]; then
    echo "❌ failed to fetch live cert for $host" >&2
    exit 2
  fi

  current_pin=$(
    grep -A2 "'$host':" "$FILE" \
    | grep -oE "'[0-9a-f]{64}'" \
    | head -1 \
    | tr -d "'"
  ) || current_pin=""

  if [[ "$live_pin" == "$current_pin" ]]; then
    echo "✓ $host pin is current ($live_pin)"
    continue
  fi

  needs_update=1
  echo "⚠ $host pin is STALE"
  echo "  in file: ${current_pin:-<missing>}"
  echo "  live:    $live_pin"

  if [[ "$APPLY" == "--apply" ]]; then
    if [[ -n "$current_pin" ]]; then
      sed -i.bak "s/'$current_pin'/'$live_pin'/" "$FILE"
    fi
    rm -f "$FILE.bak"
    echo "  ✓ updated $FILE"
  fi
done

if [[ "$needs_update" == "1" && "$APPLY" != "--apply" ]]; then
  echo
  echo "Run with --apply to write the new pins:"
  echo "  scripts/refresh-cert-pins.sh --apply"
  exit 1
fi

exit 0
