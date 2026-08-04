#!/usr/bin/env bash
# DomHubs — provision an isolated Hermes client instance on a SHARED VPS.
#
# Model: one Linux host, many clients = many Hermes *profiles*
#   ~/.hermes/profiles/<slug>/   → own .env, SOUL, state.db, gateway unit
#   systemd: hermes-gateway-<slug>.service
#   Telegram: one bot token per profile (never share tokens)
#
# Why not Docker first: Hermes already isolates via HERMES_HOME + multi-gateway.
# Containers later only if you need OS-level sandbox for untrusted tool use.
#
# Usage (on the VPS as root/deploy user):
#   provision-client-instance.sh --client flavia
#   provision-client-instance.sh --client acme --description "Acme assistant"
#   provision-client-instance.sh --client flavia --clone-from edwiges
#
set -euo pipefail

SLUG=""
DESCRIPTION=""
CLONE_FROM=""
START_GATEWAY=1
INSTALL_GATEWAY=1
LEAN_MCP=1

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: provision-client-instance.sh --client SLUG [options]

  --client SLUG           Required. lowercase [a-z0-9-] (e.g. flavia, acme-corp)
  --description TEXT      Stored on the profile
  --clone-from PROFILE    Clone config skeleton from another profile (not secrets by default uses --clone)
  --no-gateway-install    Create profile only
  --no-start              Install unit but do not start
  --keep-mcp              Do not force mcp_servers: {}
  -h, --help

Env:
  HERMES_CLIENT_SLUG      Same as --client
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client) SLUG="${2:-}"; shift 2 ;;
    --description) DESCRIPTION="${2:-}"; shift 2 ;;
    --clone-from) CLONE_FROM="${2:-}"; shift 2 ;;
    --no-gateway-install) INSTALL_GATEWAY=0; shift ;;
    --no-start) START_GATEWAY=0; shift ;;
    --keep-mcp) LEAN_MCP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

SLUG="${SLUG:-${HERMES_CLIENT_SLUG:-}}"
[[ -n "$SLUG" ]] || die "--client SLUG is required (shared VPS multi-tenant)"

# normalize: lowercase, allow a-z0-9-
SLUG="$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
SLUG="$(printf '%s' "$SLUG" | sed -E 's/-+/-/g; s/^-|-$//g')"
[[ "$SLUG" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "invalid slug after normalize: $SLUG"
[[ "$SLUG" != "default" && "$SLUG" != "root" && "$SLUG" != "main" ]] || die "reserved slug: $SLUG"

command -v hermes >/dev/null 2>&1 || die "hermes not on PATH"
export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

PROFILE_HOME="${HERMES_ROOT:-${HOME}/.hermes}/profiles/${SLUG}"
DESCRIPTION="${DESCRIPTION:-DomHubs client instance: ${SLUG}}"

log "Provisioning isolated client instance: ${SLUG}"
log "Profile home: ${PROFILE_HOME}"

if [[ -d "$PROFILE_HOME" && -f "$PROFILE_HOME/config.yaml" ]]; then
  log "Profile already exists — reusing ${SLUG}"
else
  create_args=(profile create "$SLUG" --description "$DESCRIPTION" --no-skills)
  if [[ -n "$CLONE_FROM" ]]; then
    create_args+=(--clone-from "$CLONE_FROM")
  fi
  hermes "${create_args[@]}"
fi

[[ -d "$PROFILE_HOME" ]] || die "profile home missing after create: $PROFILE_HOME"
chmod 700 "$PROFILE_HOME" 2>/dev/null || true

# Lean production defaults for multi-tenant bots
python3 - "$PROFILE_HOME" "$LEAN_MCP" <<'PY'
import sys, re
from pathlib import Path
home = Path(sys.argv[1])
lean = sys.argv[2] == "1"
cfg = home / "config.yaml"
if not cfg.exists():
    sys.exit(0)
text = cfg.read_text()
# kanban: only default should dispatch on shared host
if re.search(r"^kanban:\s*$", text, re.M):
    if "dispatch_in_gateway" not in text:
        text = re.sub(r"^kanban:\s*$", "kanban:\n  dispatch_in_gateway: false", text, count=1, flags=re.M)
elif "dispatch_in_gateway" not in text:
    text = text.rstrip() + "\n\nkanban:\n  dispatch_in_gateway: false\n"
if lean:
    if re.search(r"^mcp_servers:\s*$", text, re.M):
        text = re.sub(r"^mcp_servers:\n(?:  .*\n)*", "mcp_servers: {}\n", text, count=1, flags=re.M)
    elif re.search(r"^mcp_servers:\s*\{\s*\}\s*$", text, re.M):
        pass
    elif re.search(r"^mcp_servers:", text, re.M):
        text = re.sub(r"^mcp_servers:\n(?:  .*\n)*", "mcp_servers: {}\n", text, count=1, flags=re.M)
    else:
        text = text.rstrip() + "\nmcp_servers: {}\n"
cfg.write_text(text)
print("config hardened (kanban dispatch off, lean mcp)" if lean else "config hardened (kanban dispatch off)")
PY

# Ensure empty secrets file exists with safe perms
touch "${PROFILE_HOME}/.env"
chmod 600 "${PROFILE_HOME}/.env"

if [[ "$INSTALL_GATEWAY" -eq 1 ]]; then
  log "Installing systemd user unit: hermes-gateway-${SLUG}"
  hermes --profile "$SLUG" gateway install
  if [[ "$START_GATEWAY" -eq 1 ]]; then
    # Do not start if no bot token yet — gateway can still run but wasteful
    if grep -qE '^TELEGRAM_BOT_TOKEN=.+' "${PROFILE_HOME}/.env" 2>/dev/null; then
      hermes --profile "$SLUG" gateway restart || hermes --profile "$SLUG" gateway start
      log "Gateway started for ${SLUG}"
    else
      warn "No TELEGRAM_BOT_TOKEN in profile .env yet — unit installed, not started"
      warn "After onboarding secrets: hermes --profile ${SLUG} gateway start"
    fi
  fi
fi

# Mark instance metadata (no secrets)
mkdir -p "${PROFILE_HOME}/domhubs"
cat > "${PROFILE_HOME}/domhubs/instance.json" <<EOF
{
  "slug": "${SLUG}",
  "profile_home": "${PROFILE_HOME}",
  "gateway_unit": "hermes-gateway-${SLUG}.service",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "isolation": "hermes-profile"
}
EOF
chmod 644 "${PROFILE_HOME}/domhubs/instance.json"

cat <<EOF

✓ Instance ready: ${SLUG}

  Home:     ${PROFILE_HOME}
  Unit:     hermes-gateway-${SLUG}.service
  Commands:
    hermes --profile ${SLUG} doctor
    hermes --profile ${SLUG} gateway status
    hermes --profile ${SLUG} chat --cli -s hermes-client-onboarding
    journalctl --user -u hermes-gateway-${SLUG} -n 50 --no-pager

  Isolation rules:
    • One Telegram bot token per profile (never reuse)
    • TELEGRAM_ALLOWED_USERS only for that client
    • Do not run gateway on default ~/.hermes for client bots
    • Default host profile: setup/tooling only

Next: run onboarding against this profile (apply secrets, SOUL, start gateway).
EOF
