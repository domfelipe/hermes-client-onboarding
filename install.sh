#!/usr/bin/env bash
# DomHubs — Hermes Client Onboarding bootstrap
#
# Run ON the client VPS (after SSH). Not on the operator laptop alone.
#
# Enter VPS:
#   ssh root@IP_DA_VPS
#   # DomHubs ops alias: ssh domhubs-vps   (169.58.116.28, key ~/.ssh/domhubs_vps)
#
# Then one-liner (inside the VPS) — SHARED host multi-tenant:
#   curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --client flavia
#
# Each --client creates an isolated Hermes profile + gateway unit.
# Local checkout: ./install.sh --client SLUG [--conductor hermes|skip] [--no-launch]
set -euo pipefail

SKILL_NAME="hermes-client-onboarding"
DEFAULT_BASE="${HERMES_ONBOARD_BASE:-https://setup.domhubs.com.br/hermes}"
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://hermes-agent.nousresearch.com/install.sh}"
KICKOFF_MSG="${HERMES_ONBOARD_KICKOFF:-}"

CONDUCTOR="${HERMES_ONBOARD_CONDUCTOR:-hermes}"
CLIENT_SLUG="${HERMES_CLIENT_SLUG:-}"
NO_LAUNCH=0
NONINTERACTIVE=0
REQUIRE_CLIENT="${HERMES_REQUIRE_CLIENT:-1}"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  Shared DomHubs VPS — one host, many isolated Hermes clients (profiles):

    ssh domhubs-vps
    curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --client flavia

  --client SLUG                   Required. Isolated profile name (a-z0-9-)
  --conductor codex|hermes|skip   Who runs onboarding (default: hermes)
  --no-launch                     Install + provision only; do not start conductor
  --base URL                      Asset base for skill files (or HERMES_ONBOARD_BASE)
  --non-interactive               No prompts
  --ask-conductor                 Prompt for conductor even when default is hermes
  --allow-default                 Allow missing --client (single-tenant / laptop only)
  -h, --help                      Show help

Env:
  HERMES_CLIENT_SLUG, HERMES_ONBOARD_BASE, HERMES_ONBOARD_CONDUCTOR
  HERMES_ONBOARD_KICKOFF, HERMES_INSTALL_URL, HERMES_ONBOARD_NO_LAUNCH=1
  HERMES_REQUIRE_CLIENT=0         Same as --allow-default
EOF
}

ASK_CONDUCTOR=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --client) CLIENT_SLUG="${2:-}"; shift 2 ;;
    --conductor) CONDUCTOR="${2:-}"; shift 2 ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    --base) DEFAULT_BASE="${2:-}"; shift 2 ;;
    --non-interactive) NONINTERACTIVE=1; shift ;;
    --ask-conductor) ASK_CONDUCTOR=1; shift ;;
    --allow-default) REQUIRE_CLIENT=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ "${HERMES_ONBOARD_NO_LAUNCH:-0}" == "1" ]] && NO_LAUNCH=1
[[ "${HERMES_REQUIRE_CLIENT:-1}" == "0" ]] && REQUIRE_CLIENT=0

# ---------------------------------------------------------------------------
# Resolve skill source: local checkout vs remote base URL
# ---------------------------------------------------------------------------
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
fi

LOCAL_SKILL=""
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/skill/${SKILL_NAME}/SKILL.md" ]]; then
  LOCAL_SKILL="$SCRIPT_DIR/skill/${SKILL_NAME}"
fi

need_cmd() { command -v "$1" >/dev/null 2>&1; }

os_name="$(uname -s 2>/dev/null || echo unknown)"
case "$os_name" in
  Linux|Darwin) ;;
  *) warn "untested OS: $os_name (expected Linux Ubuntu/Debian for production demos)" ;;
esac

if [[ "$os_name" == "Darwin" ]]; then
  warn "macOS detected — gateway uses launchd; production clients should be Ubuntu/Debian VMs"
fi

export PATH="${HOME}/.local/bin:${PATH}"

# ---------------------------------------------------------------------------
# Ensure Hermes
# ---------------------------------------------------------------------------
ensure_hermes() {
  if need_cmd hermes; then
    log "Hermes already installed: $(hermes --version 2>/dev/null | head -1 || echo ok)"
    return 0
  fi
  log "Installing Hermes (--skip-browser)..."
  need_cmd curl || die "curl is required"
  curl -fsSL "$HERMES_INSTALL_URL" | bash -s -- --skip-browser
  export PATH="${HOME}/.local/bin:${PATH}"
  # shellcheck disable=SC1090
  source "${HOME}/.bashrc" 2>/dev/null || true
  need_cmd hermes || die "Hermes install finished but 'hermes' not on PATH. Open a new shell or: export PATH=\"\$HOME/.local/bin:\$PATH\""
  log "Hermes installed: $(hermes --version 2>/dev/null | head -1 || echo ok)"
}

# ---------------------------------------------------------------------------
# Install skill into Hermes (+ Codex/agents if present)
# ---------------------------------------------------------------------------
copy_tree() {
  local src="$1" dest="$2"
  mkdir -p "$dest"
  # portable: prefer cp -R then fix modes
  rm -rf "${dest:?}/"*
  cp -R "$src"/. "$dest"/
  if [[ -f "$dest/scripts/apply-core-config.sh" ]]; then
    chmod +x "$dest/scripts/apply-core-config.sh"
  fi
  if [[ -f "$dest/scripts/provision-client-instance.sh" ]]; then
    chmod +x "$dest/scripts/provision-client-instance.sh"
  fi
  if [[ -f "$dest/scripts/start-onboarding.sh" ]]; then
    chmod +x "$dest/scripts/start-onboarding.sh"
  fi
  if [[ -f "$dest/scripts/auto_kickoff_cli.py" ]]; then
    chmod +x "$dest/scripts/auto_kickoff_cli.py"
  fi
}

fetch_skill_to() {
  local dest="$1"
  local base="$DEFAULT_BASE"
  need_cmd curl || die "curl is required to download skill assets"
  mkdir -p "$dest/references" "$dest/scripts"
  log "Downloading skill from ${base}/skill/${SKILL_NAME}/ ..."
  curl -fsSL "${base}/skill/${SKILL_NAME}/SKILL.md" -o "$dest/SKILL.md"
  curl -fsSL "${base}/skill/${SKILL_NAME}/references/troubleshooting.md" -o "$dest/references/troubleshooting.md"
  curl -fsSL "${base}/skill/${SKILL_NAME}/scripts/apply-core-config.sh" -o "$dest/scripts/apply-core-config.sh"
  curl -fsSL "${base}/skill/${SKILL_NAME}/scripts/provision-client-instance.sh" -o "$dest/scripts/provision-client-instance.sh" || true
  curl -fsSL "${base}/skill/${SKILL_NAME}/scripts/start-onboarding.sh" -o "$dest/scripts/start-onboarding.sh" || true
  curl -fsSL "${base}/skill/${SKILL_NAME}/scripts/auto_kickoff_cli.py" -o "$dest/scripts/auto_kickoff_cli.py" || true
  chmod +x "$dest/scripts/apply-core-config.sh"
  [[ -f "$dest/scripts/provision-client-instance.sh" ]] && chmod +x "$dest/scripts/provision-client-instance.sh"
  [[ -f "$dest/scripts/start-onboarding.sh" ]] && chmod +x "$dest/scripts/start-onboarding.sh"
  [[ -f "$dest/scripts/auto_kickoff_cli.py" ]] && chmod +x "$dest/scripts/auto_kickoff_cli.py"
  [[ -s "$dest/SKILL.md" ]] || die "failed to download SKILL.md from $base"
}

install_skill() {
  local staging
  staging="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$staging'" RETURN

  if [[ -n "$LOCAL_SKILL" ]]; then
    log "Using local skill: $LOCAL_SKILL"
    copy_tree "$LOCAL_SKILL" "$staging"
  else
    fetch_skill_to "$staging"
  fi

  local hermes_dest="${HOME}/.hermes/skills/${SKILL_NAME}"
  mkdir -p "${HOME}/.hermes/skills"
  copy_tree "$staging" "$hermes_dest"
  log "Skill installed for Hermes → $hermes_dest"

  # Launcher + provisioner
  mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share/hermes-client-onboarding"
  if [[ -f "$staging/scripts/start-onboarding.sh" ]]; then
    cp -f "$staging/scripts/start-onboarding.sh" "${HOME}/.local/bin/hermes-client-onboarding"
    chmod +x "${HOME}/.local/bin/hermes-client-onboarding"
    log "Launcher → ~/.local/bin/hermes-client-onboarding [--client SLUG]"
  fi
  if [[ -f "$staging/scripts/provision-client-instance.sh" ]]; then
    cp -f "$staging/scripts/provision-client-instance.sh" "${HOME}/.local/bin/hermes-client-provision"
    chmod +x "${HOME}/.local/bin/hermes-client-provision"
    log "Provisioner → ~/.local/bin/hermes-client-provision --client SLUG"
  fi
  if [[ -f "$staging/scripts/auto_kickoff_cli.py" ]]; then
    cp -f "$staging/scripts/auto_kickoff_cli.py" "${HOME}/.local/share/hermes-client-onboarding/auto_kickoff_cli.py"
    cp -f "$staging/scripts/auto_kickoff_cli.py" "${HOME}/.hermes/skills/${SKILL_NAME}/scripts/auto_kickoff_cli.py"
    chmod +x "${HOME}/.local/share/hermes-client-onboarding/auto_kickoff_cli.py"
  fi

  # Codex / agents (optional)
  if [[ -d "${HOME}/.codex" ]] || need_cmd codex; then
    mkdir -p "${HOME}/.codex/skills"
    copy_tree "$staging" "${HOME}/.codex/skills/${SKILL_NAME}"
    log "Skill installed for Codex → ~/.codex/skills/${SKILL_NAME}"
  fi
  if [[ -d "${HOME}/.agents/skills" ]]; then
    copy_tree "$staging" "${HOME}/.agents/skills/${SKILL_NAME}"
    log "Skill installed for agents → ~/.agents/skills/${SKILL_NAME}"
  fi
}

# ---------------------------------------------------------------------------
# Conductor selection + launch
# ---------------------------------------------------------------------------
pick_conductor() {
  # Default path for one-liner demos: hermes (set above). Only prompt if asked.
  if [[ "$ASK_CONDUCTOR" -eq 0 && -n "$CONDUCTOR" ]]; then
    echo "$CONDUCTOR"
    return
  fi
  if [[ "$NONINTERACTIVE" -eq 1 ]]; then
    echo "${CONDUCTOR:-hermes}"
    return
  fi
  local tty_in="/dev/tty"
  if [[ ! -r "$tty_in" ]]; then
    echo "${CONDUCTOR:-hermes}"
    return
  fi

  local has_codex=0
  need_cmd codex && has_codex=1

  echo "" >&2
  echo "Quem deve conduzir o onboarding conversacional?" >&2
  if [[ "$has_codex" -eq 1 ]]; then
    echo "  1) Hermes (default — DeepSeek barato)" >&2
    echo "  2) Codex" >&2
    echo "  3) Só instalar skill — não abrir agente" >&2
    printf "Escolha [1]: " >&2
    read -r ans <"$tty_in" || ans=1
    case "${ans:-1}" in
      2|codex|c) echo codex ;;
      3|skip|s)  echo skip ;;
      *)         echo hermes ;;
    esac
  else
    echo "  1) Hermes" >&2
    echo "  2) Só instalar skill — não abrir agente" >&2
    printf "Escolha [1]: " >&2
    read -r ans <"$tty_in" || ans=1
    case "${ans:-1}" in
      2|skip|s) echo skip ;;
      *)         echo hermes ;;
    esac
  fi
}

launch_hermes_onboarding() {
  if [[ -n "$CLIENT_SLUG" ]]; then
    export HERMES_CLIENT_SLUG="$CLIENT_SLUG"
    export HERMES_HOME="${HOME}/.hermes/profiles/${CLIENT_SLUG}"
    if [[ -z "$KICKOFF_MSG" ]]; then
      KICKOFF_MSG="Inicie onboarding do cliente ${CLIENT_SLUG}. Skill hermes-client-onboarding. Multi-tenant profile ${CLIENT_SLUG} only. Pre-flight e Phase 1."
    fi
  elif [[ -z "$KICKOFF_MSG" ]]; then
    KICKOFF_MSG="Inicie o onboarding agora. Skill hermes-client-onboarding. Pre-flight silencioso e Phase 1 (voce fala primeiro)."
  fi
  export HERMES_ONBOARD_KICKOFF="$KICKOFF_MSG"
  export HERMES_ONBOARD_SKILL="$SKILL_NAME"
  export HERMES_TUI_QUERY="$KICKOFF_MSG"
  export HERMES_TUI_SKILLS="$SKILL_NAME"
  if [[ -x "${HOME}/.local/bin/hermes-client-onboarding" ]]; then
    local launch_args=()
    [[ -n "$CLIENT_SLUG" ]] && launch_args=(--client "$CLIENT_SLUG")
    if [[ -r /dev/tty ]]; then
      exec "${HOME}/.local/bin/hermes-client-onboarding" "${launch_args[@]}" </dev/tty >/dev/tty 2>/dev/tty
    else
      exec "${HOME}/.local/bin/hermes-client-onboarding" "${launch_args[@]}"
    fi
  fi
  # Fallback: classic CLI + PTY inject script if present
  local auto_py="${HOME}/.hermes/skills/${SKILL_NAME}/scripts/auto_kickoff_cli.py"
  if [[ -f "$auto_py" ]] && command -v python3 >/dev/null 2>&1; then
    if [[ -r /dev/tty ]]; then
      exec python3 "$auto_py" </dev/tty >/dev/tty 2>/dev/tty
    fi
    exec python3 "$auto_py"
  fi
  die "launcher missing — re-run install or: hermes --profile ${CLIENT_SLUG:-default} chat --cli -s ${SKILL_NAME}"
}

launch_conductor() {
  local c="$1"
  case "$c" in
    skip)
      log "Skill pronta. Rode depois (agente fala primeiro):"
      echo "  hermes-client-onboarding"
      echo "  # ou: hermes chat --tui -s ${SKILL_NAME} -q \"…\""
      need_cmd codex && echo "  codex \"${KICKOFF_MSG}\""
      return 0
      ;;
    hermes)
      need_cmd hermes || die "hermes missing"
      log "Abrindo Hermes (auto-start Phase 1)..."
      launch_hermes_onboarding
      ;;
    codex)
      need_cmd codex || die "codex not found — install Codex or use --conductor hermes"
      log "Abrindo Codex com kickoff de onboarding..."
      if [[ -r /dev/tty ]]; then
        exec codex --sandbox danger-full-access "$KICKOFF_MSG" </dev/tty
      else
        exec codex --sandbox danger-full-access "$KICKOFF_MSG"
      fi
      ;;
    *)
      die "unknown conductor: $c"
      ;;
  esac
}

# ---------------------------------------------------------------------------
provision_client_if_needed() {
  if [[ -z "$CLIENT_SLUG" ]]; then
    if [[ "$REQUIRE_CLIENT" == "1" ]]; then
      die "missing --client SLUG (shared VPS multi-tenant). Example: bash -s -- --client flavia  |  or HERMES_REQUIRE_CLIENT=0 for laptop"
    fi
    warn "No --client: using default ~/.hermes (not multi-tenant safe on shared host)"
    return 0
  fi
  # normalize slug early
  CLIENT_SLUG="$(printf '%s' "$CLIENT_SLUG" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed -E 's/-+/-/g; s/^-|-$//g')"
  export HERMES_CLIENT_SLUG="$CLIENT_SLUG"
  local prov="${HOME}/.local/bin/hermes-client-provision"
  [[ -x "$prov" ]] || prov="${HOME}/.hermes/skills/${SKILL_NAME}/scripts/provision-client-instance.sh"
  [[ -x "$prov" ]] || die "provision script missing after skill install"
  log "Provisioning isolated instance: ${CLIENT_SLUG}"
  "$prov" --client "$CLIENT_SLUG" --no-start
}

main() {
  log "DomHubs Hermes Client Onboarding (shared VPS multi-tenant)"
  log "Target: this machine (run via SSH on the DomHubs VPS)"
  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
    warn "You appear to be on macOS. Production onboarding expects the DomHubs VPS:"
    warn "  ssh domhubs-vps"
    warn "  curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --client SLUG"
  fi
  ensure_hermes
  install_skill
  provision_client_if_needed

  if [[ "$NO_LAUNCH" -eq 1 ]]; then
    log "Done (--no-launch). Re-enter: ssh domhubs-vps"
    if [[ -n "$CLIENT_SLUG" ]]; then
      echo "  hermes-client-onboarding --client ${CLIENT_SLUG}"
      echo "  hermes --profile ${CLIENT_SLUG} gateway status"
    else
      echo "  hermes-client-onboarding"
    fi
    exit 0
  fi

  local c
  c="$(pick_conductor)"
  log "Conductor: $c"
  launch_conductor "$c"
}

main "$@"
