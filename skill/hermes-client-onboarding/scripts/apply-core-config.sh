#!/usr/bin/env bash
# Apply DeepSeek native + model + Telegram core config for Hermes client onboarding.
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
    --deepseek-key|--openrouter-key) DS_KEY="${2:-}"; shift 2 ;; # --openrouter-key kept as alias
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

hermes config set DEEPSEEK_API_KEY "$DS_KEY"
hermes config set model.provider "$PROVIDER"
hermes config set model.default "$MODEL"
hermes config set TELEGRAM_BOT_TOKEN "$TG_TOKEN"
hermes config set TELEGRAM_ALLOWED_USERS "$TG_USERS"

echo "ok: provider=$(hermes config get model.provider 2>/dev/null || echo "$PROVIDER")"
echo "ok: model=$(hermes config get model.default 2>/dev/null || echo "$MODEL")"
echo "ok: allowed_users=$TG_USERS"
echo "ok: secrets written (not displayed)"
