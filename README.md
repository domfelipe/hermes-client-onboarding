# Hermes Client Onboarding (DomHubs)

One-liner + skill conversacional para deixar o **Hermes Agent** pronto no cliente em minutos:

- OpenRouter + `deepseek/deepseek-v4-flash`
- Telegram (gateway como serviço)
- Personalidade em `SOUL.md`
- Setup guiado por LLM (Codex ou Hermes)

## One-liner (produção)

```bash
curl -fsSL https://setup.domhubs.com.br/hermes | bash
```

Variantes:

```bash
# só instalar skill + Hermes, sem abrir agente
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --no-launch

# forçar condutor
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --conductor hermes
curl -fsSL https://setup.domhubs.com.br/hermes | bash -s -- --conductor codex
```

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

O `install.sh` baixa a skill de `HERMES_ONBOARD_BASE` (default `https://setup.domhubs.com.br/hermes`) quando **não** está rodando a partir de um checkout com `skill/`.

### Opção A — Domínio próprio (recomendado)

Publique arquivos estáticos:

| URL | Arquivo |
|-----|---------|
| `https://setup.domhubs.com.br/hermes` | `install.sh` (Content-Type: text/plain) |
| `https://setup.domhubs.com.br/hermes/skill/hermes-client-onboarding/SKILL.md` | skill |
| `.../references/troubleshooting.md` | ref |
| `.../scripts/apply-core-config.sh` | script |

Nginx/Caddy exemplo (path prefix `/hermes` → root do repo, com rewrite de `/hermes` → `install.sh`).

### Opção B — GitHub raw

```bash
export HERMES_ONBOARD_BASE="https://raw.githubusercontent.com/<org>/hermes-client-onboarding/main"
curl -fsSL "$HERMES_ONBOARD_BASE/install.sh" | bash
```

Ou grave esse `BASE` no topo do `install.sh` antes de publicar.

### Opção C — Gist

Gist single-file só serve se a skill for embutida. Prefira repo/GitHub raw.

## Stack padrão (decisões)

| Item | Valor |
|------|--------|
| Modelo | `deepseek/deepseek-v4-flash` via OpenRouter |
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

# 4. onboarding interativo
hermes chat -s hermes-client-onboarding
# completar fases 1–6 com chaves reais de teste

# 5. smoke telegram
hermes gateway status
# enviar "oi" no bot
```

## Helper de config

```bash
~/.hermes/skills/hermes-client-onboarding/scripts/apply-core-config.sh \
  --openrouter-key "$OPENROUTER_API_KEY" \
  --telegram-token "$TELEGRAM_BOT_TOKEN" \
  --allowed-users "123456789"
```

Não imprime secrets.

## Licença

MIT (skill + bootstrap DomHubs). Hermes Agent em si: licença do projeto Nous Research.
