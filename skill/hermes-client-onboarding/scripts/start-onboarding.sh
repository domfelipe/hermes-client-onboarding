#!/usr/bin/env bash
# Launch Hermes with hermes-client-onboarding and auto-start Phase 1
# (agent speaks first — does not wait for the user to say "oi").
set -euo pipefail

export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"

SKILL_NAME="${HERMES_ONBOARD_SKILL:-hermes-client-onboarding}"
KICKOFF="${HERMES_ONBOARD_KICKOFF:-Inicie AGORA o onboarding de cliente Hermes. Siga a skill hermes-client-onboarding: execute o pre-flight em silêncio e abra a Phase 1 fazendo a primeira pergunta ao usuário. Você fala primeiro — não espere eu dizer oi ou começar.}"

if ! command -v hermes >/dev/null 2>&1; then
  echo "error: hermes not on PATH" >&2
  exit 1
fi

# Must use `hermes chat` subcommand: -q is not a top-level flag.
# With --tui, -q becomes HERMES_TUI_QUERY — first turn auto-submits, session stays interactive.
if [[ -t 0 && -t 1 ]]; then
  exec hermes chat --tui -s "$SKILL_NAME" -q "$KICKOFF" "$@"
fi

# Non-TTY fallback (CI/scripts): one-shot only
exec hermes chat -s "$SKILL_NAME" -Q -q "$KICKOFF" "$@"
