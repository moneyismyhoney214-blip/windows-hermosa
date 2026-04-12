#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/nearpay_full_flow_test"
mkdir -p "$TMP_DIR"

EMAIL="${1:-${NEARPAY_TEST_EMAIL:-}}"
PASSWORD="${2:-${NEARPAY_TEST_PASSWORD:-}}"
BASE_URL="${NEARPAY_BASE_URL:-https://api.hermosaapp.com}"
BRANCH_ID="${NEARPAY_BRANCH_ID:-}"

if [[ -z "${EMAIL}" || -z "${PASSWORD}" ]]; then
  echo "Usage: $0 <email> <password>"
  echo "Or set NEARPAY_TEST_EMAIL / NEARPAY_TEST_PASSWORD."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed."
  exit 1
fi

login_file="$TMP_DIR/login.json"
terminal_file="$TMP_DIR/terminal_config.json"
jwt_file="$TMP_DIR/jwt.json"

echo "1) Seller login..."
login_code="$(
  curl -sS --connect-timeout 20 --max-time 90 \
    -o "$login_file" -w "%{http_code}" \
    -X POST "${BASE_URL}/seller/login" \
    -H "Accept: application/json" \
    -H "Accept-Language: ar" \
    -H "Accept-Platform: dashboard" \
    -H "Accept-ISO: SAU" \
    -F "email=${EMAIL}" \
    -F "password=${PASSWORD}"
)"

if [[ "$login_code" != "200" ]]; then
  echo "Login failed with HTTP $login_code"
  cat "$login_file"
  exit 1
fi

token="$(jq -r '.data.token // empty' "$login_file")"
if [[ -z "$token" ]]; then
  echo "Login succeeded but no bearer token was returned."
  cat "$login_file"
  exit 1
fi

if [[ -z "$BRANCH_ID" ]]; then
  BRANCH_ID="$(jq -r '.data.branches[0].id // empty' "$login_file")"
fi
if [[ -z "$BRANCH_ID" ]]; then
  echo "Could not determine branch_id from account. Set NEARPAY_BRANCH_ID."
  exit 1
fi

echo "2) Fetch terminal config for branch ${BRANCH_ID}..."
terminal_code="$(
  curl -sS --connect-timeout 20 --max-time 90 \
    -o "$terminal_file" -w "%{http_code}" \
    "${BASE_URL}/seller/nearpay/terminal/config?branch_id=${BRANCH_ID}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token}"
)"

if [[ "$terminal_code" != "200" ]]; then
  echo "Terminal config failed with HTTP $terminal_code"
  cat "$terminal_file"
  exit 1
fi

terminal_tid="$(jq -r '.data.terminal_tid // empty' "$terminal_file")"
terminal_id="$(jq -r '.data.terminal_id // empty' "$terminal_file")"
if [[ -z "$terminal_tid" || -z "$terminal_id" ]]; then
  echo "Terminal config response is missing terminal_tid or terminal_id."
  cat "$terminal_file"
  exit 1
fi

echo "3) Fetch NearPay JWT..."
jwt_code="$(
  curl -sS --connect-timeout 20 --max-time 90 \
    -o "$jwt_file" -w "%{http_code}" \
    -X POST "${BASE_URL}/seller/nearpay/auth/token" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    --data "{\"branch_id\":${BRANCH_ID},\"terminal_tid\":\"${terminal_tid}\",\"terminal_id\":\"${terminal_id}\"}"
)"

if [[ "$jwt_code" != "200" ]]; then
  echo "JWT fetch failed with HTTP $jwt_code"
  cat "$jwt_file"
  exit 1
fi

jwt_token="$(jq -r '.data.token // empty' "$jwt_file")"
if [[ -z "$jwt_token" ]]; then
  echo "JWT response does not include data.token."
  cat "$jwt_file"
  exit 1
fi

repo_token="$(
  (
    rg '^nearpayPosGitlabReadToken=' "$ROOT_DIR/local.properties" 2>/dev/null ||
      rg '^nearpayPosGitlabReadToken=' "$ROOT_DIR/../../../android/gradle.properties" 2>/dev/null
  ) | head -n 1 | sed 's/^[^=]*=//'
)"

if [[ -z "$repo_token" ]]; then
  echo "NearPay GitLab Maven token is missing in local.properties and app gradle.properties."
  echo "Set nearpayPosGitlabReadToken before running tests."
  exit 1
fi

echo "4) Run Robolectric + Mockito full flow test..."
(
  cd "$ROOT_DIR"
  ./gradlew testDebugUnitTest \
    -PnearpayPosGitlabReadToken="${repo_token}" \
    -Dnearpay.test.jwt="${jwt_token}"
)

echo "Done. Full NearPay flow unit test passed."
echo "JWT length used: ${#jwt_token} (token value not printed)"
