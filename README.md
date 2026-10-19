# Omarchy Ecosystem News

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Official omarchy.org news (RSS) with an unread badge and a reading popout;
Omarchy, OpenCode and Hermes releases and new-plugin marketplace commits
remain available as optional sources in settings.

Kinds: bar-widget, service

## What it shows

| Source | Feed | Default | Example |
|---|---|---|---|
| Omarchy.org | `https://omarchy.org/news/rss.xml` (RSS 2.0, official source) | **on** | "Greptile joins as a Distinguished Corporate Patron" |
| OpenCode | releases from `anomalyco/opencode` | **on** | `v2.0.32` |
| Hermes | releases from `NousResearch/Hermes-Agent` | **on** | stable releases (canary hidden by default) |
| Omarchy | releases from `omacom/omarchy` | off | `v4.0.5` |
| Marketplace | commits on `registry.json` of `omarchy-plugin-marketplace` | off | "New plugin: Luddite Scout" |

By default the list shows **official omarchy.org news + OpenCode and Hermes
releases**. Omarchy releases and the marketplace commit feed stay available
through toggles (`sourceOmarchy`, `sourceMarketplace`) in settings. The
panel groups by project: official news and Omarchy releases both land in
the "OMARCHY" group; OpenCode and Hermes get their own groups, ordered by
recency — the group with the freshest item opens the list.

The canonical repository IDs changed owners (`basecamp/omarchy` →
`omacom/omarchy`, `sst/opencode` → `anomalyco/opencode`); the plugin pins
the new URLs directly.

## Usage

- **Left click** on the badge: opens the news list (↑/↓ browse, ↵ opens in
  the browser, x marks read, R refreshes, Esc closes).
- **Right click**: forces a feed refresh.
- While there are unread items, a count chip appears on the badge.
- Everything displayed is `Text.PlainText` with data bounded at parse time;
  the only links that ever open are the four feeds' own pages (allowlist in
  `NewsModel.js`).

## State

- Polling and seen-state live in the singleton `service`; the widget is a
  per-monitor view.
- "Read" persists to `~/.local/state/1977-news/state.json` (XDG state,
  outside the plugin) and survives shell restarts.
- Settings are inline on the widget entry in `shell.json`: `pollMinutes`
  (5–240, default 20), `filterCanary` (default true), `maxItems`
  (20–200, default 80) and per-source toggles (`sourceSite` — the official
  omarchy.org news feed, on by default; `sourceMarketplace` — new-plugin
  commits, off by default; `sourceOmarchy`/`sourceOpencode`/`sourceHermes`).

## Requirements

- Omarchy 4 with Quattro plugin support.
- Only `curl` (already present in Omarchy); no authentication or privileged
  setup. Anonymous GET requests to the feeds above only, capped at 15 s and
  1 MiB per source.

## Installation

```bash
omarchy plugin add https://github.com/1977-eu/plugin-news.git --enable
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

Removal does not clean the state file `~/.local/state/1977-news/` — delete
the folder manually if you want a fresh unread state.

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Review this
repository and its dependencies before enabling it.

## License

MIT © 2026 gnl
