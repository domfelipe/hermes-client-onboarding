#!/usr/bin/env bash
# Launch Hermes with hermes-client-onboarding; agent speaks first (Phase 1).
#
# Default: classic CLI + PTY auto-kickoff (reliable).
# Optional: HERMES_ONBOARD_USE_TUI=1 for Ink TUI (env HERMES_TUI_QUERY; may race).
set -euo pipefail

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

SKILL_NAME="${HERMES_ONBOARD_SKILL:-hermes-client-onboarding}"
# Short on purpose: long kickoffs hit Hermes paste-collapse (≥5 lines / 2000 chars)
# and leave a stuck [Pasted text #N] instead of submitting.
KICKOFF="${HERMES_ONBOARD_KICKOFF:-Inicie o onboarding agora. Skill hermes-client-onboarding. Pre-flight silencioso e Phase 1 (voce fala primeiro).}"

export HERMES_ONBOARD_SKILL="$SKILL_NAME"
export HERMES_ONBOARD_KICKOFF="$KICKOFF"
# TUI path (also set so HERMES_TUI=1 launches pick up kickoff)
export HERMES_TUI_SKILLS="$SKILL_NAME"
export HERMES_TUI_QUERY="$KICKOFF"

if ! command -v hermes >/dev/null 2>&1; then
  echo "error: hermes not on PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# When installed as ~/.local/bin/hermes-client-onboarding, companion lives with skill
AUTO_PY=""
for candidate in \
  "${SCRIPT_DIR}/auto_kickoff_cli.py" \
  "${HOME}/.hermes/skills/${SKILL_NAME}/scripts/auto_kickoff_cli.py" \
  "${HOME}/.local/share/hermes-client-onboarding/auto_kickoff_cli.py"
do
  if [[ -f "$candidate" ]]; then
    AUTO_PY="$candidate"
    break
  fi
done

use_tui="${HERMES_ONBOARD_USE_TUI:-0}"

if [[ "$use_tui" == "1" ]]; then
  # Explicit env + --query (TUI maps -q → HERMES_TUI_QUERY; keep both)
  if [[ -r /dev/tty ]]; then
    exec hermes chat --tui -s "$SKILL_NAME" --query "$KICKOFF" </dev/tty
  fi
  exec hermes chat --tui -s "$SKILL_NAME" --query "$KICKOFF"
fi

# Reliable path: classic CLI + inject first user message
if [[ -n "$AUTO_PY" ]] && command -v python3 >/dev/null 2>&1; then
  if [[ -r /dev/tty ]]; then
    exec python3 "$AUTO_PY" "$@" </dev/tty >/dev/tty 2>/dev/tty
  fi
  exec python3 "$AUTO_PY" "$@"
fi

# Last resort: one-shot (not interactive after)
echo "warn: auto_kickoff_cli.py missing — running one-shot kickoff only" >&2
exec hermes chat -s "$SKILL_NAME" -Q -q "$KICKOFF" "$@"
