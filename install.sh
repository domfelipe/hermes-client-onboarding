#!/usr/bin/env bash
# DomHubs — Hermes Client Onboarding bootstrap
#
# Run ON the client VPS (after SSH). Not on the operator laptop alone.
#
# Enter VPS:
#   ssh root@IP_DA_VPS
#   # DomHubs ops alias: ssh domhubs-vps   (169.58.116.28, key ~/.ssh/domhubs_vps)
#
# Then one-liner (inside the VPS):
#   curl -fsSL https://setup.domhubs.com.br/hermes | bash
#
# Local checkout: ./install.sh [--conductor codex|hermes|skip] [--no-launch]
set -euo pipefail

SKILL_NAME="hermes-client-onboarding"
DEFAULT_BASE="${HERMES_ONBOARD_BASE:-https://setup.domhubs.com.br/hermes}"
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://hermes-agent.nousresearch.com/install.sh}"
KICKOFF_MSG="${HERMES_ONBOARD_KICKOFF:-Inicie o onboarding agora. Skill hermes-client-onboarding. Pre-flight silencioso e Phase 1 (voce fala primeiro).}"

CONDUCTOR="${HERMES_ONBOARD_CONDUCTOR:-hermes}"
NO_LAUNCH=0
NONINTERACTIVE=0

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  Run this ON the Linux VPS after SSH:
    ssh root@IP_DA_VPS
    curl -fsSL https://setup.domhubs.com.br/hermes | bash

  DomHubs ops (Mac alias):
    ssh domhubs-vps

  --conductor codex|hermes|skip   Who runs onboarding (default: hermes; use skip for install-only)
  --no-launch                     Install only; do not start the conductor
  --base URL                      Asset base for skill files (or HERMES_ONBOARD_BASE)
  --non-interactive               No prompts
  --ask-conductor                 Prompt for conductor even when default is hermes
  -h, --help                      Show help

Env:
  HERMES_ONBOARD_BASE, HERMES_ONBOARD_CONDUCTOR, HERMES_ONBOARD_KICKOFF
  HERMES_INSTALL_URL, HERMES_ONBOARD_NO_LAUNCH=1
EOF
}

ASK_CONDUCTOR=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --conductor) CONDUCTOR="${2:-}"; shift 2 ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    --base) DEFAULT_BASE="${2:-}"; shift 2 ;;
    --non-interactive) NONINTERACTIVE=1; shift ;;
    --ask-conductor) ASK_CONDUCTOR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ "${HERMES_ONBOARD_NO_LAUNCH:-0}" == "1" ]] && NO_LAUNCH=1

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
  curl -fsSL "${base}/skill/${SKILL_NAME}/scripts/start-onboarding.sh" -o "$dest/scripts/start-onboarding.sh" || true
  curl -fsSL "${base}/skill/${SKILL_NAME}/scripts/auto_kickoff_cli.py" -o "$dest/scripts/auto_kickoff_cli.py" || true
  chmod +x "$dest/scripts/apply-core-config.sh"
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

  # Launcher: auto-starts Phase 1 (agent speaks first via CLI PTY inject)
  mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share/hermes-client-onboarding"
  if [[ -f "$staging/scripts/start-onboarding.sh" ]]; then
    cp -f "$staging/scripts/start-onboarding.sh" "${HOME}/.local/bin/hermes-client-onboarding"
    chmod +x "${HOME}/.local/bin/hermes-client-onboarding"
    log "Launcher → ~/.local/bin/hermes-client-onboarding (agent fala primeiro)"
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
  export HERMES_ONBOARD_KICKOFF="$KICKOFF_MSG"
  export HERMES_ONBOARD_SKILL="$SKILL_NAME"
  export HERMES_TUI_QUERY="$KICKOFF_MSG"
  export HERMES_TUI_SKILLS="$SKILL_NAME"
  if [[ -x "${HOME}/.local/bin/hermes-client-onboarding" ]]; then
    if [[ -r /dev/tty ]]; then
      exec "${HOME}/.local/bin/hermes-client-onboarding" </dev/tty >/dev/tty 2>/dev/tty
    else
      exec "${HOME}/.local/bin/hermes-client-onboarding"
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
  die "launcher missing — re-run install or: hermes chat --cli -s ${SKILL_NAME}"
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
main() {
  log "DomHubs Hermes Client Onboarding"
  log "Target: this machine (run via SSH on the client VPS)"
  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
    warn "You appear to be on macOS. Production onboarding expects Ubuntu/Debian VPS:"
    warn "  ssh root@IP_DA_VPS"
    warn "  curl -fsSL https://setup.domhubs.com.br/hermes | bash"
  fi
  ensure_hermes
  install_skill

  if [[ "$NO_LAUNCH" -eq 1 ]]; then
    log "Done (--no-launch). Re-enter VPS later with: ssh root@IP_DA_VPS  (or ssh domhubs-vps)"
    log "Start with (agent speaks first):"
    echo "  hermes-client-onboarding"
    echo "  # ou: hermes chat --tui -s ${SKILL_NAME} -q \"…\""
    exit 0
  fi

  local c
  c="$(pick_conductor)"
  log "Conductor: $c"
  launch_conductor "$c"
}

main "$@"
