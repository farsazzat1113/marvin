# UNKNOWN

**Shared Egg Finder + Cloudflare Key Gate** — a single-file Roblox UI script with a
premium glass interface, live shared feed, and auto-join.

![Build](https://img.shields.io/badge/build-Public%20v0.5.0%20%2F%20UI21-935CFF)
![Theme](https://img.shields.io/badge/theme-Glass%20Premium-38CDFF)
![File](https://img.shields.io/badge/format-single--file%20Lua-success)

## Overview

UNKNOWN scans the current server's field eggs, reports sightings to the shared
Finder host, and renders a live list of the best eggs reported across servers —
with one-click join and an automatic "join the best server" mode.

The Finder only boots **after the key-validation endpoint returns `valid=true`**
and revalidates the key every 60 seconds while running.

## What's new in UI21 — Deathless Steal + Fast Join

- **No more deaths while stealing** — the obby anti-teleport punisher is
  disarmed every Heartbeat via `Workspace:SetAttribute("ClientObbyAntiTp", false)`,
  and the steal movement uses **no teleports at all**: short ground-hugging
  steps (9 studs/frame, velocity zeroed), so the character never pops upward,
  never gets lagback-yanked out of the area, and never trips the kill logic.
- **Park once, steal instantly** — a single stop beside the nest at ground
  level, then the carry remote fires the same frame of arrival.
- **Safe carry home** — the way back to your plot uses the same safe steps.
- **Anti Trap pathing** — trap Hitboxes (any Owner other than you) are steered
  around; if a nest is fully caged, the egg cools down instead of walking in.
- **Fail cooldown + respawn recovery** — after 3 failed attempts an egg rests
  for 45 s; if the character dies mid-run, the script waits for the respawn
  and retries cleanly instead of skipping that egg forever.
- **First-frame steal after a hop** — the remembered joined egg is hunted
  straight from its world model before the fresh scan even lands, and the
  queued auto-execute now reloads **this** build (it used to reload the packed
  upstream copy, which silently dropped Auto Steal after every teleport).
- **Fast Auto Join** — feed refresh cadence 6 s → 2 s while armed, and the
  hop is fully pre-staged *before* the claim round-trip so the teleport fires
  the instant the server approves.

## What's new in UI20 — Auto Steal

- **AUTO STEAL** — hands-free carry + plant for the egg a join tracked:
  the character is parked next to the egg, the game's own carry remote is
  invoked, then the egg is taken home and planted on your plot.
- While **Auto Join** is armed, the best local egg over your minimum gets
  picked up automatically too - no buttons pressed.
- New persisted settings toggle: **SETTINGS → AUTO STEAL: ON/OFF** (default ON).

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
- **AUTO STEAL** — carries + plants the tracked egg without any input.
- **SETTINGS** — auto-execute / auto-steal toggles and Discord link.
