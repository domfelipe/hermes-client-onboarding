---
name: hermes-client-onboarding
description: Use when setting up Hermes for a client, install Hermes + Telegram + DeepSeek, run a demo setup, or launch client onboarding. Conducts guided conversational onboarding on a clean Linux VM (deepseek-v4-flash, Telegram gateway, systemd, SOUL.md).
version: 1.1.0
author: DomHubs
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [onboarding, client, telegram, deepseek, gateway, demo]
    related_skills: []
---

# Hermes Client Onboarding

## Overview

You are conducting a professional, step-by-step onboarding of Hermes Agent on a clean Ubuntu/Debian VM so a client can start using it immediately (primarily via Telegram). The goal is a working agent in minutes, with **native DeepSeek** (`DEEPSEEK_API_KEY`, provider `deepseek`) and model **`deepseek-v4-flash`** (V4 Flash 0731 family) as the default, Telegram as the primary channel, and the gateway running as a persistent service.

This skill is designed for live demos in front of the client and for commercial handoff. Be clear, structured, and efficient. Always confirm critical values before applying them.

## When to Use

- User asks to set up Hermes for a client
- Demo setup of Hermes + Telegram + DeepSeek
- Launch of the DomHubs client onboarding flow
- Fresh VM that needs Hermes ready end-to-end

Don't use for: day-to-day Hermes coding tasks after onboarding is done; multi-tenant fleet orchestration; non-Hermes agent installs.

## Success Criteria

The onboarding is complete only when all of the following are true:

- Hermes is installed and `hermes` command works
- Model is set to `deepseek-v4-flash` with provider `deepseek`
- `DEEPSEEK_API_KEY` is configured
- Telegram bot token and at least one allowed user ID are set
- Gateway is installed as a systemd service and is running
- A test message sent to the Telegram bot receives a coherent reply
- `hermes doctor` reports no critical errors
- SOUL.md has been personalized (or the user explicitly skipped it)

## Pre-flight Checks (do these first)

Run these checks silently or with minimal output before starting the dialogue:

1. Confirm you are on Linux (preferably Ubuntu 22.04/24.04 or Debian). On macOS, warn that gateway persistence differs (launchd) and demos still work.
2. Check if `hermes` is already in PATH. If yes, note the version with `hermes --version`.
3. Check available disk space and RAM (`df -h /` and `free -h`). Warn if RAM < 2 GB or free disk < 5 GB.
4. Verify internet connectivity (can reach `https://hermes-agent.nousresearch.com` and `https://api.deepseek.com`).

If Hermes is missing, install it with:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
source ~/.bashrc 2>/dev/null || true
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
```

After install, confirm with `hermes --version` and `hermes doctor`.

**Done when:** OS/resources known, Hermes on PATH, version recorded.

## Conversational Flow

Conduct the onboarding as a structured dialogue. Move phase by phase. Never skip confirmation of secrets or user IDs.

### Phase 1 — Context & Goals

Ask:

- Is this a live demo in front of the client or a setup you will hand over later?
- What is the client/company name? (used later in SOUL.md)
- Preferred language for the agent (default: Portuguese Brazilian)
- Will the client interact mainly via Telegram? (yes/no — we still set Telegram as primary)

**Done when:** demo vs handoff, company name, language, and channel intent confirmed.

### Phase 2 — DeepSeek Credentials

1. Ask for the DeepSeek API key from https://platform.deepseek.com/ (usually starts with `sk-`).
2. Confirm the key is present and looks valid (do not echo the full key back).
3. Apply it (prefer `scripts/apply-core-config.sh` when you already have Telegram values too; otherwise set now):

```bash
hermes config set DEEPSEEK_API_KEY "THE_KEY"
hermes config set model.provider deepseek
hermes config set model.default deepseek-v4-flash
hermes config set model.base_url "https://api.deepseek.com/v1"
```

Important: always set `model.base_url` to the DeepSeek API. A leftover OpenRouter URL causes HTTP 401 ("Missing Authentication header") even with a valid `DEEPSEEK_API_KEY`.

4. Verify with:

```bash
hermes config get model.default
hermes config get model.provider
hermes config get model.base_url
```

Optional: Offer fallback model `deepseek-v4-pro` if the user wants a stronger model (higher cost).

**Done when:** provider=deepseek, model=deepseek-v4-flash, key set without printing it.

### Phase 3 — Telegram Bot

1. Guide the user (or do it yourself if they give you the token) to create a bot with @BotFather if they do not have one yet.
2. Collect:
   - `TELEGRAM_BOT_TOKEN`
   - At least one numeric User ID (from @userinfobot or @get_id_bot). Multiple IDs can be comma-separated.
3. Apply:

```bash
hermes config set TELEGRAM_BOT_TOKEN "TOKEN"
hermes config set TELEGRAM_ALLOWED_USERS "ID1,ID2"
```

4. Optional advanced settings (only if requested):
   - Home channel for proactive messages
   - Group chat IDs

**Done when:** token set, at least one allowed user ID set, values repeated back (IDs only, never full token).

### Phase 4 — Agent Personality (SOUL.md)

Ask how the agent should present itself. Offer a default template and let the user customize.

Default template (adapt with company name and language):

```markdown
Você é o assistente oficial da [Nome da Empresa].
Responda sempre em português brasileiro de forma clara, profissional, objetiva e prestativa.
Você tem memória persistente e pode usar ferramentas para ajudar o usuário em tarefas reais.
```

Write the final content to `~/.hermes/SOUL.md`. Confirm before overwriting if the file already exists.

**Done when:** SOUL.md written or user explicitly skipped personalization.

### Phase 5 — Gateway & Persistence

1. Install the gateway as a system service:

```bash
hermes gateway install
```

2. Start / restart it:

```bash
hermes gateway start
# or
hermes gateway restart
```

3. Check status:

```bash
hermes gateway status
```

4. If the service fails, inspect logs (`hermes gateway logs` or `journalctl -u hermes* -n 50` / `launchctl` on macOS) and fix common issues (PATH, missing env, permissions). See `references/troubleshooting.md`.

**Done when:** gateway status shows running and service is installed for reboot persistence.

### Phase 6 — Validation & Handover

Run the full validation sequence:

```bash
hermes doctor
hermes gateway status
```

Then instruct the user to send a test message to the Telegram bot (“oi” ou “teste”). Confirm that a coherent reply arrives.

Final checklist to present to the user:

- [ ] Hermes installed and in PATH
- [ ] Model = deepseek-v4-flash via provider deepseek (native API)
- [ ] Telegram bot responding
- [ ] Gateway running as service (survives reboot)
- [ ] SOUL.md personalized
- [ ] `hermes doctor` clean

Give the user the useful commands for later:

```bash
hermes gateway status
hermes gateway logs
hermes doctor
hermes config get model.default
hermes update
```

**Done when:** checklist walked, test Telegram reply confirmed, useful commands delivered.

## Error Handling Guidelines

- If `hermes config set` fails, check file permissions on `~/.hermes/.env` and `~/.hermes/config.yaml`.
- If Telegram does not respond: verify token with a direct `getMe` call, confirm Allowed Users, restart gateway, check logs for connection errors.
- If DeepSeek returns auth errors: re-validate `DEEPSEEK_API_KEY` and model name (`deepseek-v4-flash`). See `references/troubleshooting.md`.
- Prefer fixing issues yourself when possible, then explain what was wrong in plain language.
- Never leave the system in a half-configured state. Either finish a phase or clearly roll back.

## Style & Tone While Onboarding

- Professional and calm (you are in front of a client or preparing a commercial handoff).
- Short confirmations after each successful step.
- Always repeat back critical non-secret values (model name, allowed user IDs, company name).
- Never print full API keys or bot tokens in the conversation.
- Prefer Portuguese when the user is speaking Portuguese.

## Optional Extensions (only if requested)

- Add Discord or WhatsApp after Telegram is working.
- Switch to OpenRouter later (`OPENROUTER_API_KEY` + provider `openrouter` + OpenRouter model slug).
- Enable extra tools or change terminal backend.
- Create additional allowlisted users.
- Set up a simple cron job or home channel for proactive messages.

## Supporting Resources

- `references/troubleshooting.md` — detailed fixes for the most common failures (Telegram not replying, auth errors, service problems, PATH issues).
- `scripts/apply-core-config.sh` — safe helper to apply DeepSeek key + model + Telegram token + allowed users in one go. Prefer using it when you already have all three values confirmed.

## Reference Commands (quick lookup)

```bash
# Install
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser

# Core config (or use the helper script)
hermes config set DEEPSEEK_API_KEY "sk-..."
hermes config set model.provider deepseek
hermes config set model.default deepseek-v4-flash
hermes config set model.base_url "https://api.deepseek.com/v1"
hermes config set TELEGRAM_BOT_TOKEN "..."
hermes config set TELEGRAM_ALLOWED_USERS "123456789"

# Gateway
hermes gateway install
hermes gateway start
hermes gateway status
hermes gateway logs

# Validation
hermes doctor
hermes --version
```

When the user says the onboarding is finished or the bot is responding correctly, summarize what was configured and congratulate them. Offer to make any final adjustments.
