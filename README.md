# UNKNOWN

**Shared Egg Finder + Cloudflare Key Gate** — a single-file Roblox UI script with a
compact animated glassmorphism interface, live shared feed, and auto-steal / auto-join.

![Build](https://img.shields.io/badge/build-Public%20v0.4.4%20%2F%20UI21-935CFF)
![Theme](https://img.shields.io/badge/theme-Glass%20Premium%20Animated-38CDFF)
![File](https://img.shields.io/badge/format-single--file%20Lua-success)

## Executor Loadstrings

To run MARVIN directly in your executor:

### 🚀 Obfuscated Build (Protected & Recommended)
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/14f69693-marvin/UNKNOWN.obfuscated.lua"))()
```

### 💻 Clean Source Build
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/14f69693-marvin/UNKNOWN.lua"))()
```

---

## Live design preview

[Open the animated MARVIN dashboard preview](https://html-preview.github.io/?url=https%3A%2F%2Fgithub.com%2Ffarsazzat1113%2Fmarvin%2Fblob%2Fmarvin-premium-purple-ui-2026-11-12%2Fdesign%2Fmarvin-dashboard-preview.html)

This is a separate HTML/CSS/JavaScript visual prototype. Its starfield, nebula lighting,
gradient title, orbital core, hover states, and preview-only controls animate in a browser.
It is not connected to Roblox or the live Lua callbacks.

## Overview

UNKNOWN scans the current server's field eggs, reports sightings to the shared
Finder host, and renders a live list of the best eggs reported across servers —
with one-click join and an automatic "join the best server" mode.

The Finder only boots **after the key-validation endpoint returns `valid=true`**
and revalidates the key every 60 seconds while running.

## What's new in UI21 — Sleek Compact Animated Redesign

- **Compact Glass Design** — Removed oversized 1500x850 desktop dashboard and unwanted portrait frame. Returned to a lightweight, compact floating window (~402px) that never obstructs gameplay.
- **Continuous Rotating Neon Glow** — Multi-stop gradient border (`UIStroke`) with smooth continuous 360° rotation.
- **Dynamic Starfield & Breathing Nebulae** — 32 twinkling micro-stars with randomized sine pulsation and 3 drifting nebula blurs.
- **Shimmering MARVIN Wordmark** — Animated metallic gradient sweep flowing across the bold header title.
- **Tactile Button Physics** — Smooth hover scaling (1.035x) and click spring bounce (0.965x → 1.0x with Back easing) on all interactive buttons.
- **Glowing Launcher Orb** — Floating draggable circle launcher with continuous rotating neon border ring and pulsing halo.
- **Smooth Pop Entrance** — Energetic Back-eased pop animation when opening or toggling the panel.
- **Clean Layout** — Fixed overlapping status and discord texts into clean dedicated vertical zones.

## What's new in UI20 — Auto Steal

- **AUTO STEAL** — hands-free carry + plant for the egg a join tracked:
  the character is parked next to the egg, the game's own carry remote is
  invoked, then the egg is taken home and planted on your plot.
- While **Auto Join** is armed, the best local egg over your minimum gets
  picked up automatically too - no buttons pressed.
- New persisted settings toggle: **SETTINGS → AUTO STEAL: ON/OFF** (default ON).

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
- **AUTO STEAL** — carries + plants the tracked egg without any input.
- **SETTINGS** — auto-execute / auto-steal toggles and Discord link.
