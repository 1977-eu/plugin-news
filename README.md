# Omarchy Ecosystem News

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Notícias oficiais do omarchy.org (RSS), com badge de não-lidos e popup de
leitura; releases de Omarchy, OpenCode e Hermes e commits de novos plugins
do marketplace ficam disponíveis como fontes opcionais em settings.

Kinds: bar-widget, service

## O que mostra

| Fonte | Feed | Padrão | Exemplo |
|---|---|---|---|
| Omarchy.org | `https://omarchy.org/news/rss.xml` (RSS 2.0, fonte oficial) | **on** | "Greptile joins as a Distinguished Corporate Patron" |
| OpenCode | releases do `anomalyco/opencode` | **on** | `v2.0.32` |
| Hermes | releases do `NousResearch/Hermes-Agent` | **on** | releases estáveis (canary oculto por padrão) |
| Omarchy | releases do `omacom/omarchy` | off | `v4.0.5` |
| Marketplace | commits no `registry.json` do `omarchy-plugin-marketplace` | off | "New plugin: Luddite Scout" |

Por padrão a lista mostra **as notícias oficiais do omarchy.org + releases de
OpenCode e Hermes**. Omarchy releases e o feed de commits do marketplace
continuam disponíveis via toggles (`sourceOmarchy`, `sourceMarketplace`) em
settings. O painel agrupa por projeto: news oficiais e releases do Omarchy
caem no mesmo grupo "OMARCHY"; OpenCode e Hermes têm grupos próprios.

Os IDs canônicos dos repositórios mudaram de dono (`basecamp/omarchy` →
`omacom/omarchy`, `sst/opencode` → `anomalyco/opencode`); o plugin fixa as
URLs novas diretamente.

## Uso

- **Clique esquerdo** no badge: abre a lista de novidades (↑/↓ navegando,
  ↵ abre no navegador, x marca lido, R atualiza, Esc fecha).
- **Clique direito**: força uma atualização dos feeds.
- Enquanto houver não-lidos, um chip com a contagem aparece no badge.
- Todo texto exibido é `Text.PlainText` com dados limitados no parse; os
  links abertos são apenas os dos quatro feeds (allowlist em `NewsModel.js`).

## Estado

- Polling e seen-state vivem no serviço singleton (`service`); o widget é
  uma por monitor.
- "Lido" persiste em `~/.local/state/1977-news/state.json` (XDG state,
  externo ao plugin) e sobrevive a reinícios do shell.
- Configuração no `shell.json` inline na entrada: `pollMinutes` (5–240,
  padrão 20), `filterCanary` (padrão true), `maxItems` (20–200, padrão 80)
  e toggles por fonte (`sourceSite` — feed oficial de notícias do
  omarchy.org, ligado por padrão; `sourceMarketplace` — commits de novos
  plugins, off por padrão; `sourceOmarchy`/`sourceOpencode`/`sourceHermes`).

## Requisitos

- Omarchy 4 com suporte a plugins Quattro.
- Somente `curl` (já presente no Omarchy); sem autenticação nem setup
  privilegiado. Só requisições GET anônimas aos feeds acima, com limite
  de 15 s e 256 KiB por fonte.

## Installation

```bash
omarchy plugin add https://github.com/OWNER/REPOSITORY.git --enable
```

For a local checkout:

```bash
omarchy plugin add "$(pwd)" --enable
```

## Validation and tests

```bash
./tests/run
omarchy plugin validate .
```

## Update

```bash
omarchy plugin update 1977.news
```

## Removal

```bash
omarchy plugin remove 1977.news
```

Remover não limpa o arquivo de estado `~/.local/state/1977-news/` — remova a
pasta manualmente se quiser zerar os não-lidos.

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Review this
repository and its dependencies before enabling it.

## License

MIT © 2026 gnl
