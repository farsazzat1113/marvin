# UNKNOWN

**Shared Egg Finder + 24-Hour Linkvertise Key System** — a single-file Roblox UI script with a
compact animated glassmorphism interface, rotating royal crown, live shared feed, smart sniper auto-join, and Linkvertise ad monetization.

![Build](https://img.shields.io/badge/build-Public%20v0.5.0%20%2F%20UI26-935CFF)
![Theme](https://img.shields.io/badge/theme-Glass%20Premium%20Royal%20Crown-FFD700)
![Key Gate](https://img.shields.io/badge/key%20gate-Linkvertise%2024H%20Monetized-FF8C00)
![Engine](https://img.shields.io/badge/engine-Smart%20Join%20Sniper-34EB96)
![File](https://img.shields.io/badge/format-single--file%20Lua-success)

## Executor Loadstrings

To run MARVIN directly in your executor:

### 🚀 1️⃣ Obfuscated Build (Protected & Recommended)
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/7303e424-marvin/UNKNOWN.obfuscated.lua"))()
```

### 💻 2️⃣ Clean Source Build
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/7303e424-marvin/UNKNOWN.lua"))()
```

---

## What's new in UI26 — Linkvertise 24-Hour Ad-Key System

- **💵 Linkvertise Ad Monetization** — Connected directly to your Linkvertise campaign (`https://direct-link.net/3852708/7hzx0OtX0UJe`).
- **⏱️ 24-Hour Daily Key Access** — Keys remain valid for 24 full hours (`86400s`) upon verification, automatically saved to `marvin_key_auth.json`. Returning players jump straight into MARVIN without re-entering keys or seeing ads repeatedly.
- **👑 Royal Key Window** — Centered dark glassmorphic card with a 360° continuously spinning royal crown.
- **🔗 1-Click "GET KEY (ADS)" Button** — Automatically copies your Linkvertise link to the user's clipboard and instructs them to open their browser.
- **☁️ Dynamic Keys via `keys.json`** — Change or add valid keys on GitHub anytime without re-obfuscating or modifying script files.
- **🚫 Auto Steal Removed** — Completely eliminated to prevent any movement interference.
- **🎯 Active PlaceId Matching** — Smart Join strictly validates that target servers match your current `game.PlaceId`.
- **⚡ Smart Auto Join Engine** — Always prioritizes and teleports to the highest-rate egg across all active servers.
- **🔄 Multi-Server Fallback** — Instantly hops to the next best eligible server if the target is full.

---

## Overview

UNKNOWN scans the current server's field eggs, reports sightings to the shared
Finder host, and renders a live list of the best eggs reported across servers —
with one-click join and an automatic "smart join sniper" mode.

## Source map

| # | Section | Responsibility |
|---|---------|----------------|
| 1 | Bootstrap | Auto-execute queue, silent retry per server hop |
| 2 | Finder core | Services, GUI factory, parsing/formatting helpers |
| 3 | Glass Premium UI | Theme, rotating crown, header, settings overlay, animations |
| 4 | Network | Config loader, broadcast, feed pagination, smart auto-join sniper |
| 5 | Card renderer | Egg cards, rarity/mutation glyphs, instant join flow |
| 6 | Scan loop | Field-egg reader feeding UI + broadcaster |
| 7 | Key gate | Linkvertise 24h glass key window with rotating royal crown |

## Controls

- **Launcher icon** / **F key** — toggle the panel (draggable via its header).
- **GET KEY (ADS)** — copies the Linkvertise link to clipboard.
- **ALL SERVERS / MY SERVER** — feed scope tabs.
- **REFRESH** — manual feed refresh with the reset countdown.
- **VALUE OF SERVERS / MIN AUTO JOIN VALUE** — `1B`–`50B` thresholds.
- **SMART JOIN** — zero-latency sniper that teleports to the highest eligible egg and falls back automatically if full.
- **SETTINGS** — auto-execute toggles and Discord link.
