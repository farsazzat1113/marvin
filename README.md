# UNKNOWN

**Shared Egg Finder + Cloudflare Key Gate** — a single-file Roblox UI script with a
compact animated glassmorphism interface, live shared feed, smart sniper auto-join, and auto-steal.

![Build](https://img.shields.io/badge/build-Public%20v0.4.5%20%2F%20UI22-935CFF)
![Theme](https://img.shields.io/badge/theme-Glass%20Premium%20Animated-38CDFF)
![Engine](https://img.shields.io/badge/engine-Smart%20Join%20Sniper-34EB96)
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

## What's new in UI22 — Smart Auto Join & Zero-Latency Sniper

- **Smart Auto Join Engine** — Always prioritizes and teleports to the **highest-rate egg** available across all servers that meets your `MIN AUTO JOIN VALUE`.
- **Instant Snipe (Zero Lag)** — Removed all artificial delays, blocking network claims, and HTTP timeouts before teleporting. Teleport executes directly and immediately for maximum speed.
- **Standby Egg Sniper** — If no current egg meets your threshold, Smart Join stays armed and scans the feed continuously every 1 second; the moment an egg meeting your value is detected, it snipes it instantly.
- **Automatic Multi-Server Fallback** — If candidate #1 fails (server full, egg taken, or Roblox redirect), Smart Join immediately switches to candidate #2, then #3, and so on, keeping strictly to eggs `>= MIN AUTO JOIN VALUE`.
- **Anti-Random-Server Protection** — If Roblox redirects you to a random server because the target was full, Smart Join detects that you arrived in the wrong server and immediately hops to the next eligible server without getting stuck.
- **Persistent State Across Server Hops** — `SMART JOIN: ON/OFF` state now persists across teleports and executor restarts.

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
| 4 | Network | Config loader, broadcast, feed pagination, smart auto-join sniper |
| 5 | Card renderer | Egg cards, rarity/mutation glyphs, instant join flow |
| 6 | Scan loop | Field-egg reader feeding UI + broadcaster |
| 7 | Key gate | Glass key window, validation + periodic recheck |

## Controls

- **Launcher icon** / **F key** — toggle the panel (draggable via its header).
- **ALL SERVERS / MY SERVER** — feed scope tabs.
- **REFRESH** — manual feed refresh with the reset countdown.
- **VALUE OF SERVERS / MIN AUTO JOIN VALUE** — `1B`–`50B` thresholds.
- **SMART JOIN** — zero-latency sniper that teleports to the highest eligible egg and falls back automatically if full.
- **AUTO STEAL** — carries + plants the tracked egg without any input.
- **SETTINGS** — auto-execute / auto-steal toggles and Discord link.
