# MARVIN Ultimate

**Shared Egg Finder + Independent Visual Design Engine (CSS/TS Architecture)** —
a single-file Roblox UI script with a completely separate visual design system, CSS/JS-inspired tokens,
safe translation layer, non-invasive visual adapter, rotating royal crown, and 24-hour Linkvertise key gate.

![Build](https://img.shields.io/badge/build-Public%20v0.7.0%20%2F%20UI32-935CFF)
![Theme](https://img.shields.io/badge/design%20engine-Independent%20Visual%20Adapter-FFD700)
![Key Gate](https://img.shields.io/badge/key%20gate-Linkvertise%2024H%20Monetized-FF8C00)
![Engine](https://img.shields.io/badge/engine-Smart%20Join%20Sniper-34EB96)
![File](https://img.shields.io/badge/format-single--file%20Lua-success)

## Executor Loadstrings

To run MARVIN directly in your executor:

### 🚀 1️⃣ Obfuscated Build (Protected & Recommended)
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/c26d50e5-marvin/UNKNOWN.obfuscated.lua"))()
```

### 💻 2️⃣ Clean Source Build
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/c26d50e5-marvin/UNKNOWN.lua"))()
```

---

## Visual Design Engine Architecture

### 1️⃣ Design Token Layer (CSS/JS-Inspired Design System)
- **Centralized Themes:**
  - `RoyalAmethyst` (Default signature luxury glassmorphism)
  - `CyberpunkCyan` (Electric cyan / neon teal high-contrast)
  - `EmeraldMatrix` (Deep jade emerald and amber gold)
  - `ObsidianGold` (Minimalist luxury obsidian and 24K gold)
  - `SafeModeClean` (High legibility, static contrast, zero-motion Safe Mode)
- **Token Dictionary:**
  - Standardized Radii (`xs`, `sm`, `md`, `lg`, `pill`).
  - Standardized Strokes (`thin`, `normal`, `thick`).
  - Gradients, glow, surface transparencies, and typography scales.

### 2️⃣ Safe Roblox Translation Layer
- Converts CSS-style visual declarations (`backgroundColor`, `backgroundTransparency`, `borderRadius`, `border`, `gradient`, `glow`) into native Roblox properties.
- Checks before modifying instances: reuses existing `UICorner`, `UIStroke`, or `UIGradient` objects and never creates redundant duplicates.
- Full snapshot and restore engine (`snapshot(instance, props)` and `restore(instance)`).

### 3️⃣ Non-Invasive Visual Adapter
- Strictly separates visual presentation from core logic and UI controls.
- Adapts existing elements (`panel`, `bar`, `heading`, `crown`, `scope`, `myScope`, `rarity`, `autoJoinButton`, `refreshButton`, `open`, egg cards) without modifying callbacks or event connections.
- Micro-interaction hover scaling on buttons without touching `Activated` connections.
- 100% Safe Mode compatibility: disables motion and transitions when Safe Mode is enabled.

---

## Controls (All Original Functionality & Callbacks Intact)

- **Launcher icon** / **F key** — toggle the panel (draggable via its header).
- **GET KEY (ADS)** — copies the Linkvertise link to clipboard.
- **ALL SERVERS / MY SERVER** — feed scope tabs.
- **REFRESH** — manual feed refresh with the reset countdown.
- **VALUE OF SERVERS / MIN AUTO JOIN VALUE** — `1B`–`50B` thresholds.
- **SMART JOIN** — zero-latency sniper that teleports to the highest eligible egg and falls back automatically if full.
- **SETTINGS** — auto-execute toggles and Discord link.
