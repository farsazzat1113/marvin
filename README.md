# MARVIN Ultimate

**Shared Egg Finder + Independent Visual Design Engine (CSS/TS Architecture) + Smart Sniper & Direct Egg Teleport** —
a single-file Roblox UI script with a completely separate visual design system, CSS/JS-inspired tokens,
safe translation layer, non-invasive visual adapter, smart sniper with direct egg teleport on join, rotating royal crown, and 24-hour Linkvertise key gate.

![Build](https://img.shields.io/badge/build-Public%20v0.7.3%20%2F%20UI34--Clean-935CFF)
![Performance](https://img.shields.io/badge/performance-Zero--Lag%20Featherlight-34EB96)
![Theme](https://img.shields.io/badge/design%20engine-Independent%20Visual%20Adapter-FFD700)
![Key Gate](https://img.shields.io/badge/key%20gate-Linkvertise%2024H%20Monetized-FF8C00)
![Engine](https://img.shields.io/badge/engine-Smart%20Sniper%20%2B%20Direct%20Egg%20Teleport-34EB96)
![File](https://img.shields.io/badge/format-single--file%20Lua-success)

## Universal Hub Loadstring (Like Figgy Hub)

Run MARVIN VIP in any executor with our universal auto-updating loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/MarvinHub.lua"))()
```
*Or without file extension:*
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/MarvinHub"))()
```

### ⚡ 1-Click Execution (Pre-authenticated with VIP Key)
```lua
_G.MARVIN_KEY = "MARVIN-KEY-VIP"; loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/MarvinHub.lua"))()
```

### 🌐 Official Web Portal & Key Gateway
Visit: **[https://farsazzat1113.github.io/marvin/](https://farsazzat1113.github.io/marvin/)**
- Anti-Adblock protected 24h key generator
- 1-Click Loadstring copy
- Executor compatibility guide (Real Executor, Delta, Fluxus, etc.)

---

## Direct Executor Builds

### 👑 0️⃣ Private Developer Edition (Zero Key Gate / Bypassed for Owner)
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/c26d50e5-marvin/marvin_private.lua"))()
```

### 🚀 1️⃣ Obfuscated Build (Protected & Recommended)
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/c26d50e5-marvin/UNKNOWN.obfuscated.lua"))()
```

### 💻 2️⃣ Clean Source Build
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/arena/c26d50e5-marvin/UNKNOWN.lua"))()
```

---

## Smart Sniper + Direct Egg Teleport Engine

The modular `MARVIN_SmartSniperTeleport` subsystem connects the cross-server Egg Finder directly to in-game player spawn and spatial positioning:

1. **Target Egg Tracking:** Finds servers containing the exact target egg selected by the user (either via manual card click or automated Smart Join / Auto Join candidate selection).
2. **Server Join & Metadata Handoff:** Prepares and passes target metadata (`uid`, `key`, `name`, `placeId`, `jobId`, `rate`, `area`, `queuedAt`) across server hops using `TeleportService:SetTeleportSetting` and local JSON cache fallback (`marvin_sniper_target.json`).
3. **Character Readiness Detection:** Awaits full character assembly (`Character`, `HumanoidRootPart`, `Humanoid.Health > 0`) upon server entry.
4. **Multi-Stage Spatial Resolution:**
   - *Stage 1 (Workspace Containers):* Queries `AreaEggSlotsClient`, `EggSlots`, `AreaEggSlots`, `Eggs` folders and matches model names, UIDs, and attributes.
   - *Stage 2 (EggState Modules):* Queries `EggState.ReadFieldEggs()` records for authoritative `BottomCFrame` or `CFrame` coordinates.
   - *Stage 3 (Pivot & Parts):* Fallback to model primary part or pivot location with coordinate sanity bounds.
5. **Direct Teleport to Safe Offset:** Teleports the character directly to a safe position offset (+2.5 studs X, +2.0 studs Y, +2.5 studs Z, facing the egg) with zeroed linear and angular velocities to prevent physics kickback or rubberbanding.
6. **Bypasses Default Base/House Spawn:** Immediately overrides spawn settling at the normal base or house location when direct teleport target is available.
7. **Arrival & Availability Verification:** Checks Euclidean distance (`dist <= 18 studs`) and validates egg state against field records (`State == States.Slot` or available).
8. **Server-Authoritative Confirmation:** Respects server-authoritative acquisition mechanics — logs status and stands by for authoritative game confirmation without prematurely claiming client acquisition.
9. **Safe Fallback:** If character loading times out or the target egg is not resolved, the player safely settles at the standard spawn without throwing errors or breaking the session.

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
- **Strict Deduplication:** Reuses existing `UICorner`, `UIStroke`, `UIGradient`, and `UIScale` objects, cleans up any redundant modifier duplicates, and guards against duplicate event listeners.
- **Animated Color Gradients:** Native support for continuous 360° rotating gradients and smooth shimmering offsets via `animateGradient` and `stopGradientAnimation`.
- **Full Safe Mode Integration:** Halts all gradient motion and transitions in Safe Mode for optimal performance and legibility.
- Full snapshot and restore engine (`snapshot(instance, props)` and `restore(instance)`).

### 3️⃣ Non-Invasive Visual Adapter
- Strictly separates visual presentation from core logic and UI controls.
- **Preserves Dimensions & Functionality:** Never alters element `Size`, `Position`, `AnchorPoint`, or `LayoutOrder`, and leaves 100% of event callbacks and signals untouched.
- Adapts all UI elements (`panel`, `bar`, `heading`, `crown`, `scope`, `myScope`, `rarity`, `autoJoinButton`, `refreshButton`, `settingsButton`, `open`, egg cards).
- Micro-interaction hover scaling on buttons without touching `Activated` connections.
- **Server Authority Respect:** Defers egg acquisition status until authoritatively verified by the game server via `awaitServerAcquisitionConfirmation`.

---

## Controls (All Original Functionality & Callbacks Intact)

- **Launcher icon** / **F key** — toggle the panel (draggable via its header).
- **GET KEY (ADS)** — copies the Linkvertise link to clipboard.
- **ALL SERVERS / MY SERVER** — feed scope tabs.
- **REFRESH** — manual feed refresh with the reset countdown.
- **VALUE OF SERVERS / MIN AUTO JOIN VALUE** — `1B`–`50B` thresholds.
- **SMART JOIN** — zero-latency sniper that teleports to the highest eligible egg and falls back automatically if full.
- **SETTINGS** — auto-execute toggles and Discord link.
