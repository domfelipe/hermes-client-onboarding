# Troubleshooting — Hermes Client Onboarding

## Cannot reach the machine / “where do I run this?”

Onboarding runs **on the VPS**. From the laptop:

```bash
ssh root@IP_DA_VPS
# DomHubs ops: ssh domhubs-vps

curl -fsSL https://setup.domhubs.com.br/hermes | bash
```

If SSH fails: check IP, user (`root` vs `ubuntu`), key (`-i ~/.ssh/…`), and provider firewall (port 22).

## PATH / `hermes: command not found`

```bash
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
# persist
grep -q '.local/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"' >> ~/.bashrc
hash -r
hermes --version
```

Re-run install if still missing:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
```

## DeepSeek auth errors

1. Confirm key is from https://platform.deepseek.com/ (do not paste full key into chat).
2. Re-set:

```bash
hermes config set DEEPSEEK_API_KEY "THE_KEY"
hermes config set model.provider deepseek
hermes config set model.default deepseek-v4-flash
hermes config set model.base_url "https://api.deepseek.com/v1"
```

3. Check:

```bash
hermes config get model.default
hermes config get model.provider
hermes config get model.base_url
# key lives in ~/.hermes/.env — never cat full file in front of client
```

If HTTP 401 "Missing Authentication header" with a valid key: `model.base_url` is probably still OpenRouter. Force DeepSeek:

```bash
hermes config set model.base_url "https://api.deepseek.com/v1"
```

4. Test connectivity: `curl -sI https://api.deepseek.com | head -1`

5. If the model name is rejected, stick to Hermes-supported IDs: `deepseek-v4-flash` or `deepseek-v4-pro` (legacy `deepseek-chat` / `deepseek-reasoner` were retired).

## Telegram bot does not reply

### Log signature: `Blocked unauthorized user`

The gateway **ignores** the sender because `TELEGRAM_ALLOWED_USERS` in **`~/.hermes/.env`** does not include their numeric ID.

**Root cause seen in production:** `hermes config set TELEGRAM_ALLOWED_USERS "..."` may leave a **stale** line in `.env` (or write somewhere the gateway does not use). Gateway loads allowlist from **`.env`**, not from a yaml-only mirror.

**Fix:**

```bash
# See what gateway will actually load (do not paste tokens into chat)
grep -E '^TELEGRAM_(BOT_TOKEN|ALLOWED_USERS)=' ~/.hermes/.env

# Set again, then re-grep until ALLOWED_USERS is exactly the new IDs
hermes config set TELEGRAM_ALLOWED_USERS "ID1,ID2"
grep -E '^TELEGRAM_ALLOWED_USERS=' ~/.hermes/.env

# If still stale, rewrite the line (example):
# sed -i.bak '/^TELEGRAM_ALLOWED_USERS=/d' ~/.hermes/.env
# echo 'TELEGRAM_ALLOWED_USERS=ID1,ID2' >> ~/.hermes/.env
chmod 600 ~/.hermes/.env

hermes gateway restart
# Linux (user service): journalctl --user -u hermes-gateway -n 50 --no-pager
# macOS: tail -n 50 ~/.hermes/logs/gateway.log
```

### Other checks

1. Token validity:

```bash
source ~/.hermes/.env 2>/dev/null || true
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | head -c 200
```

2. Allowed users must be **numeric** IDs only (@userinfobot / @get_id_bot), comma-separated.

3. Common mistakes:
   - Username string instead of numeric ID
   - Stale ALLOWED_USERS in `.env` after a previous client on the same machine
   - Gateway not running / not restarted after env change
   - Bot blocked by user / wrong bot

## Gateway service won't start

```bash
hermes gateway status
hermes gateway logs
# Linux
journalctl -u 'hermes*' -n 80 --no-pager
# macOS
# check launchd labels from hermes gateway status
```

Fixes:
- Ensure `~/.hermes/.env` readable by the service user
- Ensure `hermes` on PATH for the service unit (re-run `hermes gateway install`)
- Free port conflicts if any webhook mode is misconfigured

## `hermes config set` fails

```bash
ls -la ~/.hermes/.env ~/.hermes/config.yaml
# fix ownership if needed
chown "$USER" ~/.hermes/.env ~/.hermes/config.yaml
chmod 600 ~/.hermes/.env
```

## `hermes doctor` critical errors

Run `hermes doctor` and fix top critical items first (keys, model, gateway). Warnings about optional tools (browser, extra MCP) can wait until after Telegram works.

## Half-configured state recovery

If onboarding aborted mid-way:

1. `hermes config show` — see what's set
2. Finish remaining phases from the skill (do not reinstall unless broken)
3. `hermes gateway restart && hermes doctor`
