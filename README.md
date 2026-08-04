# Hermes Client Onboarding (DomHubs)

One-liner + skill conversacional para deixar o **Hermes Agent** pronto no cliente em minutos:

- DeepSeek nativo + `deepseek-v4-flash` (V4 Flash 0731)
- Telegram (gateway como serviço)
- Personalidade em `SOUL.md`
- Setup guiado por LLM (Codex ou Hermes)

## One-liner (produção) — comando único

```bash
curl -fsSL https://setup.domhubs.com.br/hermes | bash
```

Instala/atualiza Hermes + skill + launcher e **abre o onboarding** (condutor Hermes por padrão).

Variantes:

```bash
# só instalar, sem abrir agente
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --no-launch

# perguntar Codex vs Hermes
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --ask-conductor
```

Espelho GitHub (fallback):

```bash
curl -fsSL https://raw.githubusercontent.com/domfelipe/hermes-client-onboarding/main/install.sh | bash
# se usar o raw, force o BASE da skill se precisar:
# HERMES_ONBOARD_BASE=https://setup.domhubs.com.br/hermes bash
```

Repo: https://github.com/domfelipe/hermes-client-onboarding

## Layout

```
install.sh                          # bootstrap
skill/hermes-client-onboarding/
  SKILL.md
  references/troubleshooting.md
  scripts/apply-core-config.sh
```

O bootstrap:

1. Instala Hermes se faltar (`--skip-browser`)
2. Copia a skill para `~/.hermes/skills/hermes-client-onboarding/`
3. Copia também para `~/.codex/skills/` e `~/.agents/skills/` se existirem
4. Pergunta o condutor (Codex / Hermes / skip) e abre o chat com a skill

## Uso local (dev)

```bash
cd hermes-client-onboarding
chmod +x install.sh skill/hermes-client-onboarding/scripts/apply-core-config.sh
./install.sh --no-launch          # instala skill local sem abrir TUI
./install.sh --conductor hermes   # abre Hermes com skill
```

## Hospedagem do one-liner

O `install.sh` baixa a skill de `HERMES_ONBOARD_BASE` quando **não** está rodando a partir de um checkout com `skill/`.

**Default atual:** `https://setup.domhubs.com.br/hermes` (VPS `169.58.116.28`, Caddy + Let’s Encrypt)

### Opção A — GitHub raw (já no ar)

Funciona sem infra extra. URLs:

| Path | Uso |
|------|-----|
| `.../main/install.sh` | bootstrap |
| `.../main/skill/hermes-client-onboarding/SKILL.md` | skill |
| `.../main/skill/.../references/troubleshooting.md` | ref |
| `.../main/skill/.../scripts/apply-core-config.sh` | helper |

### Opção B — Domínio próprio (VPS / Coolify)

Proxy reverso para raw do GitHub ou serve o clone estático:

| URL | Arquivo |
|-----|---------|
| `https://setup.domhubs.com.br/hermes` | `install.sh` |
| `https://setup.domhubs.com.br/hermes/skill/...` | skill tree |

Nginx/Caddy: path `/hermes` → root do repo (rewrite `/hermes` → `install.sh`).

### Opção C — Gist

Só se embutir a skill no script. Prefira GitHub raw.

## Stack padrão (decisões)

| Item | Valor |
|------|--------|
| Provider | `deepseek` (API nativa) |
| Modelo | `deepseek-v4-flash` (V4 Flash 0731) |
| Secret | `DEEPSEEK_API_KEY` |
| Canal | Telegram |
| Gateway | `hermes gateway install` (systemd/launchd) |
| Soul | `~/.hermes/SOUL.md` |
| Alvo | Ubuntu/Debian VM limpa |

## Validação manual (VM limpa)

```bash
# 1. bootstrap
./install.sh --no-launch

# 2. skill presente
test -f ~/.hermes/skills/hermes-client-onboarding/SKILL.md && echo skill_ok

# 3. hermes ok
hermes --version
hermes doctor

# 4. onboarding interativo (agente fala primeiro — Phase 1)
hermes-client-onboarding
# ou: hermes chat --tui -s hermes-client-onboarding -q "Inicie AGORA o onboarding…"
# completar fases 1–6 com chaves reais de teste

# 5. smoke telegram
hermes gateway status
# enviar "oi" no bot
```

## Helper de config

```bash
~/.hermes/skills/hermes-client-onboarding/scripts/apply-core-config.sh \
  --deepseek-key "$DEEPSEEK_API_KEY" \
  --telegram-token "$TELEGRAM_BOT_TOKEN" \
  --allowed-users "123456789"
```

Equivalente manual:

```bash
hermes config set DEEPSEEK_API_KEY "sk-..."
hermes config set model.provider deepseek
hermes config set model.default deepseek-v4-flash
hermes config set model.base_url "https://api.deepseek.com/v1"
```

Não imprime secrets.

## Launcher (agente fala primeiro)

O bootstrap instala `~/.local/bin/hermes-client-onboarding`:

```bash
hermes-client-onboarding
```

Por padrão usa **tmux** (Hermes em sessão dedicada + `send-keys` do kickoff). Isso evita o freeze do wrapper PTY com prompt_toolkit.

```bash
# se pedir tmux e não tiver:
# apt install -y tmux

hermes-client-onboarding
# detach: Ctrl-b d
# reattach: tmux ls && tmux attach -t hermes-onboard-<pid>

# TUI Ink (opcional, kickoff frágil)
HERMES_ONBOARD_USE_TUI=1 hermes-client-onboarding
```

## Licença

MIT (skill + bootstrap DomHubs). Hermes Agent em si: licença do projeto Nous Research.
