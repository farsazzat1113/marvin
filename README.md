# UNKNOWN

**Shared Egg Finder + Cloudflare Key Gate** — a single-file Roblox UI script with a
premium glass interface, live shared feed, and auto-join.

![Build](https://img.shields.io/badge/build-Public%20v0.4.3%20%2F%20UI19-935CFF)
![Theme](https://img.shields.io/badge/theme-Glass%20Premium-38CDFF)
![File](https://img.shields.io/badge/format-single--file%20Lua-success)

## Overview

UNKNOWN scans the current server's field eggs, reports sightings to the shared
Finder host, and renders a live list of the best eggs reported across servers —
with one-click join and an automatic "join the best server" mode.

The Finder only boots **after the key-validation endpoint returns `valid=true`**
and revalidates the key every 60 seconds while running.

## What's new in UI19 — "Glass Premium"

- **Glass Premium theme** — translucent deep-space panel, purple→cyan gradient
  borders, soft outer glow, fading header hairline.
- **Animated starfield v2** — fine twinkling stars plus three slow-breathing
  nebula glows, always behind the real content (managed Z-order).
- **Glass cards** — deep indigo egg cards with soft gradients and purple
  hairline borders; consistent 8 px rounding everywhere.
- **Panel pop** — the window opens with a short Back-eased scale animation.
- **Key gate redesign** — centered glass card, accent underline, focus-lit input
  border, gradient verify button with hover/press feedback, entrance animation.
- **Encoding cleanup** — fixed mojibake strings (`â¦` → `…`, `Ã—` → `×`, `—`).
- **Organized source** — numbered section banners ([1]–[7]) and a header map.

## Source map

| # | Section | Responsibility |
|---|---------|----------------|
| 1 | Bootstrap | Auto-execute queue, silent retry per server hop |
| 2 | Finder core | Services, GUI factory, parsing/formatting helpers |
| 3 | Glass Premium UI | Theme, header, settings overlay, animations |
| 4 | Network | Config loader, broadcast, feed pagination, auto-join |
| 5 | Card renderer | Egg cards, rarity/mutation glyphs, join flow |
| 6 | Scan loop | Field-egg reader feeding UI + broadcaster |
| 7 | Key gate | Glass key window, validation + periodic recheck |

## Local state files

Written to the executor workspace when available:

| File | Purpose |
|------|---------|
| `tenshi_beta_ui.json` | UI settings (scope, thresholds, auto-execute, size) |
| `tenshi_public_sighting_lifecycle_v1.json` | Sighting lifecycle / tombstones |
| `tenshi_beta_top5_cycle_v2.json` | Retained top-5 cards across refreshes |
| `tenshi_public_gui_size_v2.json` | Saved GUI scale |
| `unknown_saved_access_key.txt` | Last accepted key (revalidated online) |

## Controls

- **Launcher icon** / **F key** — toggle the panel (draggable via its header).
- **ALL SERVERS / MY SERVER** — feed scope tabs.
- **REFRESH** — manual feed refresh with the reset countdown.
- **VALUE OF SERVERS / MIN AUTO JOIN VALUE** — `1B`–`50B` thresholds.
- **AUTO JOIN** — teleports to the best eligible reported server automatically.
- **SETTINGS** — auto-execute toggle and Discord link.
