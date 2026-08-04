---
name: hermes-client-onboarding
description: Use when setting up Hermes for a client, install Hermes + Telegram + DeepSeek, run a demo setup, or launch client onboarding. Conducts guided conversational onboarding on a clean Linux VM (deepseek-v4-flash, Telegram gateway, systemd, SOUL.md).
version: 1.4.0
author: DomHubs
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [onboarding, client, telegram, deepseek, gateway, demo, vps, multi-tenant]
    related_skills: []
---

# Hermes Client Onboarding

## Overview

You are conducting a professional, step-by-step onboarding of Hermes Agent on the **shared DomHubs Ubuntu/Debian VPS** so a client can start using it immediately (primarily via Telegram). DomHubs does **not** give each client a new VM — many clients share one host.

**Isolation model (required):** one client = one Hermes **profile** (`~/.hermes/profiles/<slug>/`) + its own gateway unit (`hermes-gateway-<slug>.service`) + its own bot token, allowlist, SOUL, and `state.db`. Never put a client bot on the default `~/.hermes` home.

Containers are optional later (OS sandbox for untrusted tools). Profiles already prevent secret/history/gateway conflicts for Telegram bots.

Goal: working agent in minutes, native DeepSeek (`DEEPSEEK_API_KEY`, provider `deepseek`), model **`deepseek-v4-flash`**, Telegram primary, gateway as systemd user service **for that profile only**.

Be clear, structured, and efficient. Always confirm critical values before applying them.

## When to Use

- User asks to set up Hermes for a client
- Demo setup of Hermes + Telegram + DeepSeek
- Launch of the DomHubs client onboarding flow
- Fresh VM/VPS that needs Hermes ready end-to-end

Don't use for: day-to-day Hermes coding tasks after onboarding is done; multi-tenant fleet orchestration; non-Hermes agent installs.

## Success Criteria

The onboarding is complete only when all of the following are true:

- Operator can **SSH into the shared DomHubs VPS**
- Client has a dedicated **profile slug** (not default `~/.hermes`)
- Hermes is installed; `hermes --profile <slug> …` works
- Model is set to `deepseek-v4-flash` with provider `deepseek` **inside that profile**
- `DEEPSEEK_API_KEY` is configured **in the profile `.env`**
- Telegram bot token (unique to this client) and allowlist are set **in the profile**
- Gateway unit `hermes-gateway-<slug>` is installed and running
- No other profile uses the same Telegram bot token
- A test message to the bot receives a coherent reply
- `hermes --profile <slug> doctor` has no critical errors
- SOUL.md personalized under the profile home (or user skipped)

## Phase 0 — Entrar na VPS + escolher instância (antes de tudo)

Onboarding runs **inside** the shared DomHubs VPS. First step is always SSH; second is a **client slug**.

**DomHubs ops (operator Mac):**

```bash
ssh domhubs-vps
# Host: 169.58.116.28  User: root  Key: ~/.ssh/domhubs_vps
```

**On the VPS — provision + onboarding for ONE client (required):**

```bash
# slug = stable id (flavia, acme, joao-silva). Never reuse across clients.
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --client SLUG
```

Examples:

```bash
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --client flavia
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --client acme --no-launch
```

This creates/reuses:

| Piece | Path / unit |
|-------|-------------|
| Home | `~/.hermes/profiles/<slug>/` |
| Secrets | `…/profiles/<slug>/.env` |
| Soul | `…/profiles/<slug>/SOUL.md` |
| History | `…/profiles/<slug>/state.db` |
| Gateway | `hermes-gateway-<slug>.service` |

**Re-enter later:**

```bash
ssh domhubs-vps
hermes --profile SLUG gateway status
hermes-client-onboarding --client SLUG
# tmux: tmux ls && tmux attach -t hermes-onboard-SLUG-…
```

**Hard isolation rules (never break these):**

1. One Telegram bot token → exactly one profile/gateway.
2. All `hermes config set` / doctor / gateway for a client use `--profile SLUG` (or `HERMES_HOME=~/.hermes/profiles/SLUG`).
3. Do not start client bots on the default `hermes-gateway.service` (host default is for tooling/setup only).
4. Do not enable heavy shared MCP servers on client profiles (leaks tokens + RAM).
5. `kanban.dispatch_in_gateway: false` on client profiles (shared host).

If the kickoff mentions a profile slug, **stay inside that profile for the entire onboarding**.

**Done when:** shell is on DomHubs VPS, client slug known, profile home exists (or will be created immediately).

## Pre-flight Checks (do these first)

Run these checks silently or with minimal output before starting the dialogue:

1. Confirm you are **already on the VPS via SSH** (Phase 0). If the user is still on a laptop UI only, give them the `ssh` command first — do not pretend Hermes can install on their phone.
2. Confirm you are on Linux (preferably Ubuntu 22.04/24.04 or Debian). On macOS, warn that gateway persistence differs (launchd) and production clients should be Ubuntu/Debian VMs.
3. Check if `hermes` is already in PATH. If yes, note the version with `hermes --version`.
4. Check available disk space and RAM (`df -h /` and `free -h`). Warn if RAM < 2 GB or free disk < 5 GB.
5. Verify internet connectivity (can reach `https://hermes-agent.nousresearch.com` and `https://api.deepseek.com`).

If Hermes is missing, install it with:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
source ~/.bashrc 2>/dev/null || true
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
```

After install, confirm with `hermes --version` and `hermes doctor`.

**Done when:** SSH session on VPS confirmed, OS/resources known, Hermes on PATH, version recorded.

## Conversational Flow

Conduct the onboarding as a structured dialogue. Move phase by phase. Never skip confirmation of secrets or user IDs.

### Auto-start (when preloaded / first turn)

When this skill is preloaded (`-s hermes-client-onboarding`) or the first user message is a kickoff like “Inicie o onboarding…”, **you speak first**:

1. Run Pre-flight Checks quietly (minimal output).
2. Immediately open **Phase 1** with the first question(s) — do **not** wait for “oi”, “olá”, or an empty prompt.
3. Do not dump the whole checklist; one short pre-flight status line is enough, then the Phase 1 questions.

Preferred launch (agent auto-starts):

```bash
hermes-client-onboarding
# uses classic CLI + auto-kickoff inject (reliable)
# TUI (optional): HERMES_ONBOARD_USE_TUI=1 hermes-client-onboarding
```

Plain `hermes chat -s hermes-client-onboarding` without kickoff waits for user input — avoid that for demos.

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

### Phase 3 — Telegram Bot (client creates their agent)

The client owns the bot — guide **them** to create it (interactive, no BotFather quota on DomHubs). Narrative: “você está criando o seu agente de IA”.

1. Ask them to open Telegram (company account preferred) and talk to @BotFather:
   - `/newbot` → choose display name + username ending in `bot`
   - Copy the **HTTP API token**
2. Collect:
   - `TELEGRAM_BOT_TOKEN`
   - At least one **numeric** User ID (from @userinfobot or @get_id_bot). Multiple IDs comma-separated.
3. Apply **and force the values into `~/.hermes/.env`** (source of truth for the gateway):

```bash
hermes config set TELEGRAM_BOT_TOKEN "TOKEN"
hermes config set TELEGRAM_ALLOWED_USERS "ID1,ID2"
```

**Critical pitfall (do not skip):** the messaging gateway reads allowlist / token from **`~/.hermes/.env`**, not from a free-form key dumped only into `config.yaml`. An **old** `TELEGRAM_ALLOWED_USERS=` line in `.env` silently wins → bot ignores the client and logs:

```text
Blocked unauthorized user
```

After every `config set` for Telegram secrets:

```bash
# Verify .env actually has the NEW ids (do not print full token)
grep -E '^TELEGRAM_ALLOWED_USERS=' ~/.hermes/.env
# If stale or missing, write explicitly:
# printf 'TELEGRAM_ALLOWED_USERS=%s\n' 'ID1,ID2' >> ~/.hermes/.env   # or edit in place
# Prefer: hermes config set again, then re-grep
```

If `.env` still shows the wrong ID after `config set`, rewrite the line yourself (sed/python) so only the new IDs remain, `chmod 600 ~/.hermes/.env`, then restart gateway (Phase 5).

4. Optional advanced settings (only if requested): home channel, group chat IDs.

**Done when:** token set, allowed user IDs confirmed in **`.env`**, values repeated back (IDs only, never full token).

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

### Phase 5 — Gateway & Persistence (per profile)

Assume client slug is `$SLUG` (from Phase 0 / kickoff).

1. Prefer the provisioner if the unit is missing:

```bash
hermes-client-provision --client "$SLUG"
# or: hermes --profile "$SLUG" gateway install
```

2. Start / restart **only this profile’s** gateway:

```bash
hermes --profile "$SLUG" gateway start
# or
hermes --profile "$SLUG" gateway restart
```

3. Check status:

```bash
hermes --profile "$SLUG" gateway status
systemctl --user is-active "hermes-gateway-${SLUG}.service"
```

4. If the service fails, inspect logs:

```bash
journalctl --user -u "hermes-gateway-${SLUG}" -n 50 --no-pager
```

Never restart the default `hermes-gateway.service` for a client bot unless you intentionally want the default home (you should not).

**Done when:** `hermes-gateway-<slug>` is active and Telegram connected for that profile only.

### Phase 6 — Validation & Handover

Run the full validation sequence (replace `$SLUG`):

```bash
hermes --profile "$SLUG" doctor
hermes --profile "$SLUG" gateway status
```

Then instruct the user to send a test message to the Telegram bot (“oi” ou “teste”). Confirm that a coherent reply arrives.

Final checklist:

- [ ] Profile `~/.hermes/profiles/<slug>/` isolated
- [ ] Model = deepseek-v4-flash via provider deepseek (in profile)
- [ ] Unique Telegram bot responding
- [ ] Unit `hermes-gateway-<slug>` running (survives reboot + linger)
- [ ] SOUL.md personalized under profile
- [ ] `hermes --profile <slug> doctor` clean
- [ ] No token collision with other profiles

Ops commands for later:

```bash
ssh domhubs-vps
hermes --profile SLUG gateway status
journalctl --user -u hermes-gateway-SLUG -n 50 --no-pager
hermes --profile SLUG doctor
hermes profile list
```

**Done when:** checklist walked, test Telegram reply confirmed, slug + SSH re-entry delivered.

## Error Handling Guidelines

- If `hermes config set` fails, check file permissions on `~/.hermes/.env` and `~/.hermes/config.yaml`.
- If Telegram does not respond: verify token with `getMe`, confirm **`TELEGRAM_ALLOWED_USERS` inside `~/.hermes/.env`** (not only yaml), restart gateway. Log signature of wrong allowlist: `Blocked unauthorized user`.
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
# Enter shared VPS
ssh domhubs-vps

# New / resume client instance (on VPS)
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --client SLUG
hermes-client-provision --client SLUG
hermes-client-onboarding --client SLUG

# Config inside profile (HERMES_HOME or --profile)
export HERMES_HOME=~/.hermes/profiles/SLUG
# or: hermes --profile SLUG config set …
hermes --profile SLUG config set DEEPSEEK_API_KEY "sk-..."
hermes --profile SLUG config set model.provider deepseek
hermes --profile SLUG config set model.default deepseek-v4-flash
hermes --profile SLUG config set model.base_url "https://api.deepseek.com/v1"
hermes --profile SLUG config set TELEGRAM_BOT_TOKEN "..."
hermes --profile SLUG config set TELEGRAM_ALLOWED_USERS "123456789"
grep -E '^TELEGRAM_ALLOWED_USERS=' ~/.hermes/profiles/SLUG/.env

# Gateway for this client only
hermes --profile SLUG gateway install
hermes --profile SLUG gateway restart
hermes --profile SLUG gateway status
journalctl --user -u hermes-gateway-SLUG -n 50 --no-pager

# Fleet
hermes profile list
systemctl --user list-units 'hermes-gateway*' --all
```

When the user says the onboarding is finished or the bot is responding correctly, summarize what was configured and congratulate them. Offer to make any final adjustments.
