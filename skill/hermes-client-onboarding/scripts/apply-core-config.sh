#!/usr/bin/env bash
# Apply DeepSeek native + model + Telegram core config for Hermes client onboarding.
# Forces Telegram secrets into ~/.hermes/.env (gateway source of truth).
# Does not print secrets. Requires: hermes on PATH.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  apply-core-config.sh \
    --deepseek-key KEY \
    --telegram-token TOKEN \
    --allowed-users ID1,ID2 \
    [--model deepseek-v4-flash] \
    [--provider deepseek]

Env fallbacks (if flags omitted):
  DEEPSEEK_API_KEY, TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS
EOF
}

MODEL="deepseek-v4-flash"
PROVIDER="deepseek"
DS_KEY="${DEEPSEEK_API_KEY:-}"
TG_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TG_USERS="${TELEGRAM_ALLOWED_USERS:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deepseek-key|--openrouter-key) DS_KEY="${2:-}"; shift 2 ;;
    --telegram-token) TG_TOKEN="${2:-}"; shift 2 ;;
    --allowed-users)  TG_USERS="${2:-}"; shift 2 ;;
    --model)          MODEL="${2:-}"; shift 2 ;;
    --provider)       PROVIDER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v hermes >/dev/null 2>&1; then
  echo "error: hermes not found on PATH" >&2
  exit 1
fi

missing=0
[[ -z "$DS_KEY" ]] && { echo "error: missing DeepSeek API key" >&2; missing=1; }
[[ -z "$TG_TOKEN" ]] && { echo "error: missing Telegram bot token" >&2; missing=1; }
[[ -z "$TG_USERS" ]] && { echo "error: missing TELEGRAM_ALLOWED_USERS" >&2; missing=1; }
[[ "$missing" -eq 1 ]] && exit 1

if [[ ! "$TG_USERS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
  echo "error: allowed users must be numeric IDs, comma-separated" >&2
  exit 1
fi

BASE_URL="https://api.deepseek.com/v1"
if [[ "$PROVIDER" == "openrouter" ]]; then
  BASE_URL="https://openrouter.ai/api/v1"
fi

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="${HERMES_HOME}/.env"
mkdir -p "$HERMES_HOME"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Upsert KEY=VALUE in .env (gateway reads this file)
env_upsert() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp)"
  if [[ -f "$ENV_FILE" ]]; then
    grep -v -E "^${key}=" "$ENV_FILE" >"$tmp" || true
  else
    : >"$tmp"
  fi
  printf '%s=%s\n' "$key" "$val" >>"$tmp"
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

hermes config set DEEPSEEK_API_KEY "$DS_KEY"
hermes config set model.provider "$PROVIDER"
hermes config set model.default "$MODEL"
hermes config set model.base_url "$BASE_URL"
hermes config set TELEGRAM_BOT_TOKEN "$TG_TOKEN"
hermes config set TELEGRAM_ALLOWED_USERS "$TG_USERS"

# Force .env — prevents stale ALLOWED_USERS silently blocking the client
env_upsert "DEEPSEEK_API_KEY" "$DS_KEY"
env_upsert "TELEGRAM_BOT_TOKEN" "$TG_TOKEN"
env_upsert "TELEGRAM_ALLOWED_USERS" "$TG_USERS"

# Verify allowlist line matches what we just wrote
got="$(grep -E '^TELEGRAM_ALLOWED_USERS=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
if [[ "$got" != "$TG_USERS" ]]; then
  echo "error: TELEGRAM_ALLOWED_USERS in $ENV_FILE is '$got', expected '$TG_USERS'" >&2
  exit 1
fi

echo "ok: provider=$(hermes config get model.provider 2>/dev/null || echo "$PROVIDER")"
echo "ok: model=$(hermes config get model.default 2>/dev/null || echo "$MODEL")"
echo "ok: base_url=$(hermes config get model.base_url 2>/dev/null || echo "$BASE_URL")"
echo "ok: allowed_users=$TG_USERS"
echo "ok: secrets written to hermes config + $ENV_FILE (not displayed)"
