# Troubleshooting — Hermes Client Onboarding

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
```

3. Check:

```bash
hermes config get model.default
hermes config get model.provider
# key lives in ~/.hermes/.env — never cat full file in front of client
```

4. Test connectivity: `curl -sI https://api.deepseek.com | head -1`

5. If the model name is rejected, stick to Hermes-supported IDs: `deepseek-v4-flash` or `deepseek-v4-pro` (legacy `deepseek-chat` / `deepseek-reasoner` were retired).

## Telegram bot does not reply

1. Token validity:

```bash
# TOKEN from env; do not log it
source ~/.hermes/.env 2>/dev/null || true
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | head -c 200
```

2. Allowed users: numeric IDs only (from @userinfobot). Restart after change:

```bash
hermes config set TELEGRAM_ALLOWED_USERS "ID1,ID2"
hermes gateway restart
hermes gateway status
hermes gateway logs
```

3. Common mistakes:
   - User ID is username string instead of numeric ID
   - Gateway not running
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
