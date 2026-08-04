#!/usr/bin/env bash
# Launch Hermes with hermes-client-onboarding; agent speaks first (Phase 1).
#
# Preferred: tmux session + send-keys (stable full-screen Hermes, no PTY freeze).
# Fallback: Python PTY inject (can be flaky with prompt_toolkit).
# Optional: HERMES_ONBOARD_USE_TUI=1 for Ink TUI (startup-query race).
set -euo pipefail

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

SKILL_NAME="${HERMES_ONBOARD_SKILL:-hermes-client-onboarding}"
# Shared VPS multi-tenant: isolate into Hermes profile
CLIENT_SLUG="${HERMES_CLIENT_SLUG:-${HERMES_PROFILE:-}}"
if [[ -n "${1:-}" && "$1" == "--client" && -n "${2:-}" ]]; then
  CLIENT_SLUG="$2"
  shift 2
fi
if [[ -n "${1:-}" && "$1" == "--profile" && -n "${2:-}" ]]; then
  CLIENT_SLUG="$2"
  shift 2
fi

# Short: long text trips Hermes paste-collapse
if [[ -n "$CLIENT_SLUG" ]]; then
  KICKOFF_DEFAULT="Inicie onboarding do cliente ${CLIENT_SLUG}. Skill hermes-client-onboarding. Multi-tenant profile ${CLIENT_SLUG} only. Pre-flight e Phase 1."
else
  KICKOFF_DEFAULT="Inicie o onboarding agora. Skill hermes-client-onboarding. Pre-flight silencioso e Phase 1 (voce fala primeiro)."
fi
KICKOFF="${HERMES_ONBOARD_KICKOFF:-$KICKOFF_DEFAULT}"
KICKOFF="$(printf '%s' "$KICKOFF" | tr '\n' ' ' | sed 's/  */ /g')"

export HERMES_ONBOARD_SKILL="$SKILL_NAME"
export HERMES_ONBOARD_KICKOFF="$KICKOFF"
export HERMES_TUI_SKILLS="$SKILL_NAME"
export HERMES_TUI_QUERY="$KICKOFF"
export HERMES_CLIENT_SLUG="${CLIENT_SLUG:-}"

if ! command -v hermes >/dev/null 2>&1; then
  echo "error: hermes not on PATH" >&2
  exit 1
fi

HERMES_BIN=(hermes)
if [[ -n "$CLIENT_SLUG" ]]; then
  HERMES_BIN=(hermes --profile "$CLIENT_SLUG")
  export HERMES_HOME="${HOME}/.hermes/profiles/${CLIENT_SLUG}"
  echo "==> Profile/client: ${CLIENT_SLUG} (HERMES_HOME=${HERMES_HOME})"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_PY=""
for candidate in \
  "${SCRIPT_DIR}/auto_kickoff_cli.py" \
  "${HOME}/.hermes/skills/${SKILL_NAME}/scripts/auto_kickoff_cli.py" \
  "${HOME}/.local/share/hermes-client-onboarding/auto_kickoff_cli.py"
do
  [[ -f "$candidate" ]] && AUTO_PY="$candidate" && break
done

use_tui="${HERMES_ONBOARD_USE_TUI:-0}"
if [[ "$use_tui" == "1" ]]; then
  if [[ -r /dev/tty ]]; then
    exec "${HERMES_BIN[@]}" chat --tui -s "$SKILL_NAME" --query "$KICKOFF" </dev/tty
  fi
  exec "${HERMES_BIN[@]}" chat --tui -s "$SKILL_NAME" --query "$KICKOFF"
fi

# --- Preferred: tmux (no frozen PTY wrapper) ---
if command -v tmux >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
  SESSION="hermes-onboard-${CLIENT_SLUG:-default}-$$"
  # Kill leftover same-name (shouldn't happen with $$)
  tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION" 2>/dev/null || true

  HERMES_CMD="${HERMES_BIN[*]} chat --cli -s ${SKILL_NAME}"
  tmux new-session -d -s "$SESSION" -x "$(tput cols 2>/dev/null || echo 120)" -y "$(tput lines 2>/dev/null || echo 40)" \
    "export PATH=\"${PATH}\"; export HERMES_CLIENT_SLUG=\"${CLIENT_SLUG:-}\"; export HERMES_HOME=\"${HERMES_HOME:-}\"; ${HERMES_CMD}; exec bash"

  # Wait until Hermes is up, then type kickoff + Enter
  for i in $(seq 1 40); do
    # capture pane; look for skill activation or welcome
    pane="$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || true)"
    if printf '%s' "$pane" | grep -qiE 'Activated skills|Welcome to Hermes|hermes-client-onboarding'; then
      sleep 0.6
      break
    fi
    sleep 0.25
  done
  sleep 0.4
  # send-keys: literal string then Enter (C-m)
  tmux send-keys -t "$SESSION" -l -- "$KICKOFF"
  sleep 0.15
  tmux send-keys -t "$SESSION" C-m

  echo "==> Sessão tmux: $SESSION (detach: Ctrl-b d | reattach: tmux attach -t $SESSION)"
  exec tmux attach -t "$SESSION"
fi

# --- Fallback: PTY inject ---
if [[ -n "$AUTO_PY" ]] && command -v python3 >/dev/null 2>&1; then
  echo "warn: tmux not found — using PTY fallback (se travar, instale: apt install -y tmux)" >&2
  if [[ -r /dev/tty ]]; then
    exec python3 "$AUTO_PY" "$@" </dev/tty >/dev/tty 2>/dev/tty
  fi
  exec python3 "$AUTO_PY" "$@"
fi

echo "warn: no tmux/python auto-kickoff — one-shot only" >&2
exec hermes chat -s "$SKILL_NAME" -Q -q "$KICKOFF" "$@"
