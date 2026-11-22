# TENSHI UPDATE HISTORY
**Official Autonomous Intelligence, Live Monitoring & Maintenance Log**

---

## 📋 Release Index
- **Latest Build:** `v2.4 / UI34-Autonomous` (Active)
- **Target Experience:** Roblox — *Steal An Egg* (`Universe ID: 10563114921`, `Place ID: 107778070777162`)
- **Architecture Standard:** Autonomous Modular Luau + Independent Visual Adapter + Stream Cipher Protection

---

### 🔹 Update Number: `v2.4-AUTONOMOUS`
* **Update Date:** `2026-11-20` (UTC)
* **Status:** `STABLE`
* **Changed Files:**
  - `UNKNOWN.lua` (Production Source)
  - `UNKNOWN.obfuscated.lua` (Encrypted Distribution Payload)
  - `marvin_private.lua` (Keyless Developer/Owner Edition)
  - `MarvinHub.lua` & `MarvinHub` (Universal GitHub Loader)
  - `index.html` (Monetized Key Gateway & Web Portal)
  - `README.md` (System Architecture Documentation)

#### 🛠️ Fixed Bugs:
1. **Smart Join Callback Candidate Race (PR #7 Alignment):** Fixed uninitialized `autoJoinCandidates` state prior to `minValueInput.FocusLost` callback at lines 2319–2321.
2. **Anti-Stuck Carry Timeout:** Implemented 50-second state reset guard in `attemptPendingPlant()` preventing infinite carry lockouts upon player death or dropped egg.
3. **Plot Placement Raycast Fallback:** Added `Geometric PetArea Center Fallback` ensuring `nextStealPlacementCFrame()` never returns `nil` if `PlacedEggRenderer` changes.
4. **Foreign Carrier Collision Avoidance:** Added `entry.carrierUserId` and `entry.isCarried` checks in `isAvailableFieldEgg()` preventing the bot from chasing eggs already carried by other players.
5. **Safe Movement & Jumping:** Added anti-stuck fallback in `walkToPoint()` using direct `MoveTo` and `ChangeState(Jumping)` if navmesh waypoints stall.

#### ✨ New Features:
1. **TENSHI_NotificationCenter:** In-memory notification hub supporting all 10 standard event categories:
   - `UPDATE DETECTED`, `NEW PET FOUND`, `NEW EGG FOUND`, `DATA CHANGED`, `BUG DETECTED`, `FIX AVAILABLE`, `FIX COMPLETED`, `DATABASE UPDATED`, `SERVER STATUS`, `SYSTEM WARNING`.
   - Includes timestamp, importance rating (`LOW`/`MEDIUM`/`HIGH`/`CRITICAL`), action requirement, resolution status, and smart 8-second deduplication.
2. **TENSHI_ServerIntelligence:**
   - Server status monitoring, player counts, latency/ping, and reported egg value indexing.
   - Favorite server manager persisted to `tenshi_favorite_servers.json`.
   - Dead/full server quarantine (`deadJobIds`) to prevent reconnection loops.
   - Server comparison heuristic prioritizing favorites, highest multiplier rate, and lowest ping.
3. **TENSHI_AutonomousMaintenanceEngine:**
   - Autonomous dependency auditing of `Client.EggState`, `Data.Assets`, `Client.PlotState`, `Shared.Types.AreaEggs`, and `Shared.Remotes`.
   - Generates standardized executive summary reports (`Tenshi Finder Report`).
   - Outputs `NO VERIFIED CHANGES FOUND.` when game schema remains stable.
   - Creates automatic local state backups to `tenshi_backup_v1.json`.
   - Interactive Settings toggle: `AUTONOMOUS MAINTENANCE MODE: ON/OFF`.
4. **Upgraded Auto Steal Engine:**
   - Smart priority targeting: hops directly to tracked Smart Join eggs first, then falls back to rarest/highest rate local field egg.
   - Multi-stage pickup sync with server authority (`CarryFieldEgg`).
   - Plot return and precision raycast grid planting (`PlantEgg`).
   - Auto-collection of away earnings (`Remotes.AwayEarnings.AskCollect`).
   - Settings toggle: `AUTO STEAL: ON/OFF` persisted to `tenshi_beta_ui.json`.
5. **Private Owner Keyless Build (`marvin_private.lua`):**
   - Zero key prompts, zero ads, direct unprompted launch with all VIP features enabled.

#### ❌ Removed Features:
- Removed hardcoded Linkvertise clipboard loop; replaced with browser-launching `openurl()` and web portal handoff.
- Deprecated manual key verification prompts in Private Owner Build.

#### 📊 Data Changes:
- Extended `tenshi_beta_ui.json` schema to include `autoSteal` boolean state.
- Integrated `tenshi_favorite_servers.json` for favorite server storage.
- Integrated `tenshi_backup_v1.json` for pre-teleport state resilience.

#### ⚡ Performance Changes:
- Zero-lag execution: AST-validated single-file build with 174 top-level statements.
- Memory leak protection: automated cleanup of orphaned UIStroke/UICorner modifier instances.
- Non-blocking network handoff: background thread pcall wrapping on all Teleport and Remote invocations.

#### 🧪 Test Results:
- `luaparse` Node.js AST check: **100% Pass** (0 syntax errors).
- XOR Stream Cipher roundtrip decryption check: **100.00% byte-for-byte fidelity** (327,023 bytes).
- Live Preview Web Server check: **200 OK** on port 8080.

#### ⏪ Rollback Information:
- If a game update alters `EggState.ReadFieldEggs()` signature, the Autonomous Maintenance Engine automatically activates local snapshot cache fallback and outputs `Tenshi Finder Report` with status `WARNING`.
- To restore previous settings, revert `tenshi_beta_ui.json` from `tenshi_backup_v1.json`.
- Git base commit: `f892ff6e12d2e1eb934569429e6c84cb2f4229ce` (Branch `arena/c26d50e5-marvin`).
