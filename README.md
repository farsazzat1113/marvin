# UNKNOWN · UI23 “Space recovery + performance pass”

**Shared Egg Finder + grounded auto-steal + Cloudflare key gate**, shipped as one
self-contained Roblox **Luau** file: [`UNKNOWN.lua`](UNKNOWN.lua).

UI22 recovered sourced UI20 controls and window-position behavior on top of the
UI21.2 custom-value client with a native space-themed interface. **UI23 then ran a
measured performance/cleanup pass**: publish dedup, hidden-mode polling throttles,
change-gated rendering, bounded module retries and removal of the one permanent
per-frame Heartbeat handler — see [PERF.md](PERF.md) for the measured before/after
table. The grounded navigator, steal/perks, webhook, validation request and income
calculation stay byte-identical to the reviewed UI21.2 baseline; the scanner block
carries one justified backoff edit (hash re-anchored, logic untouched); automated
fingerprints protect these seven blocks. Existing Finder report/feed/claim
endpoints, reset tombstones and retained top-five data are kept. See
[RECOVERY.md](RECOVERY.md) for the feature manifest, confirmed gaps, explicit
functional additions and remaining runtime limitations.

## Grounded auto-steal

- Applies `workspace:SetAttribute('ClientObbyAntiTp', false)` at startup and
  respawn, and reapplies it if the client attribute changes.
- **Never writes the character’s `CFrame` or `Position`, calls `PivotTo`, forces
  death, or respawns the player to recover.** Movement is physical
  `Humanoid:Move`, applied after the normal input render step.
- Conservative route speed: **at most 12 studs/s** (or the game’s slower current
  speed); **1.15-stud look-ahead** steps, without lag-frame catch-up bursts.
- Checks floor support, slope, small rises/drops, head/body clearance and the
  whole next segment. Jump-only, missing-floor, blocked and timed-out routes
  fail closed rather than falling back to a warp.
- Plans **one grounded standing point beside the egg**. `CarryFieldEgg` is called
  on the arrival frame, with no artificial settle delay or circling between spots.
- `carryHome` uses the **same navigator**, then sends the original game’s
  `PlantEgg(uid, CFrame.new(0, 0, 0))` relative placement request. This planting
  offset does **not** teleport the character.
- Confirms carry/plant state; failed pickup attempts back off **2 → 4 → … → 24s**.
  A failed return/plant keeps the carry and retries home with **3 → … → 24s**
  backoff instead of picking up again. Late carry acknowledgements are recovered.
- Death/respawn/disable invalidates the old movement token, stops input and
  restores the correct speed. A surviving carry resumes home; a dropped target
  can be reacquired after cooldown. Reused slot UIDs work again on a new spawn.

Auto Steal defaults **ON**, independently of Auto Join. It targets the egg tracked
by a server join, or the best eligible local field egg. A custom target, when
enabled, restricts both tracked and untracked automatic pickups. Already
carried/claimed eggs are not new pickup candidates. Active routes/carries lock
server hops so Auto Join cannot abandon an egg halfway home.

### Anti Trap

Tracks the game’s `PlacedTrap` tag (plus `Trap`/named-Hitbox fallbacks), including
newly placed or removed traps. Collision tests use **oriented Hitbox bounds**,
expanded for avatar clearance, not just the trap’s center. The planner detours
around safe corners; the live step check stops if a trap appears in an old route.
Trap instances, touch behavior and server state are not disabled or destroyed.

## Faster Finder and Auto Join

- Separate **head-feed, pagination, claim, broadcast and config HTTP lanes**:
  slow reporting/pagination never owns the claim lock.
- Polls the first page approximately every **0.2s with Auto Join on**, **0.8s off**
  after each successful response. Network/HTTP 429 failures back off; these are
  polling intervals, **not a push feed or a guaranteed end-to-end latency**.
- Publishes each page and schedules candidate selection immediately on receipt,
  without a 30-page drain or a 0.25s polling delay. Pagination retains duplicate
  protection, monotonic cursors and a 30-page limit.
- Queue registration, settings, tracked-target handoff, validation-session handoff
  and claim-body serialization are prepared **before** the claim. No disk write,
  key check, report or sleep is inserted between an accepted claim and teleport.
- Rechecks expiry using the clock **after** the claim response. Failed claims and
  teleports roll back the handoff, cool down that candidate and try another one.
  Watchdogs are trip-scoped; failed-init events check destination metadata when
  supplied.
- Tracked pickup reads `EggState` on Heartbeat, independently of the interface,
  feed, periodic scanner and key refresh. Optional asset/plot modules warm in
  separate tasks. Local scan cadence is **0.15s**, not UI20’s one second.
- Auto Join enabled state and minimum income survive a hop. On income ties, an
  eligible local egg wins; targets in pickup cooldown do not pin Auto Join locally.

## Key validation

**First launch still requires an online `valid=true` response.** A saved text key
alone does not grant offline access.

For an intentional hop, a one-use `TeleportSetting` can start the Finder without
waiting for validation HTTP only when it matches the saved key and exact
place/job, was issued within **45s**, and was validated within **120s**. The ticket
is consumed on entry. The key is checked immediately in the background, then
every 60s; transient failures retry with backoff, while an explicit invalid,
expired or revoked result stops automation and reopens the access sheet. A known
key expiry is also enforced locally.

“First frame” means the **first usable, grounded frame with replicated game state
and a ready trap map**, not walking before the character/terrain exists. No UI
animation, fresh network feed or background key check is a startup prerequisite.

## Space interface and stable dragging

Native deep navy/black surfaces, purple/electric-blue gradients, glass-like cards,
neon hairlines, three softly drifting nebula layers, 22 twinkling stars and six
particles. No downloaded UI textures, remote bitmap fonts, HTML mockup or global
Lighting modifications. Rarity colors, subtle breathing glow, hover outlines,
press feedback, loading text and entry/show/hide fades remain actual Roblox UI.

- **Centered on first use**, then restored from the new saved pixel coordinates.
  Drag the title bar, or the settings-sheet header, with the mouse or one finger.
  Controls are outside the drag overlay; pressing buttons never starts a drag.
- A single controller owns each window's position. Screen-space pointer deltas,
  a fixed zero anchor and scaled bounds prevent offset jumps. Release, touch
  cancellation, focus loss and hiding stop dragging immediately; no trailing
  position tween or RenderStepped drag loop is used.
- Refresh, scans, scope, notices, animations and settings opening do not re-center,
  resize or otherwise reposition the window. Viewport changes clamp only as needed;
  explicit desktop-size changes preserve its top-left unless it must be clamped.
- The floating **U** launcher is draggable again. Moving it suppresses the ensuing
  activation, so a drag does not accidentally reopen the panel. Both positions
  save on release, not on every pointer event.
- Bottom scope tabs and **thumb-zone Auto Steal / Auto Join / Settings** remain.
  Mobile controls stay at least 44px high in tested viewports. Short landscape
  layouts and large desktop preferences retain a scrollable feed; desktop size
  is capped when needed rather than letting the dock consume that feed.
- **MY SERVER** lists live local eggs. **STEAL** works with Auto Steal off; **FIND**
  marks a real location without moving the avatar. Income and weight have separate
  space from the full-size action row. Local model previews, supplied icons and
  neutral image-unavailable fallbacks remain; no remote model is invented.
- **Top 4 only**, in Settings, is an optional income-sorted presentation mode.
  It defaults OFF. It neither prunes Auto Join candidates nor changes the existing
  retained top-five lifecycle/cache. Turn it off to return to the normal list.
- The original **DISCORD ACCOUNT** action is restored, including executor/browser
  openers, clipboard/notification fallback, and a visible selectable profile URL.
- The original rarity options (Any / Mythic / Cosmic / Secret / Eternal / Divine)
  now have an accessible **MIN RARITY** control. UI20's corresponding control was
  already hidden/inactive; enabling it is an explicit functional addition, not a
  claim of restoring a previously visible control. It drives the existing rank
  filters; tracked/manual pickup semantics are not rewritten.
- The key action visibly says **VERIFY KEY** again, without changing validation,
  session rules or the endpoint. The access card uses the same native space theme.
- **Reduce motion** freezes nebula/star/particle and rarity-glow motion and makes
  transitions instant. Background updates reuse the UI Heartbeat, capped at 20Hz,
  pause when hidden/covered, and create no per-frame instances or tweens. The
  access card owns its visual connection only until that card is destroyed.
- Global UI/input/resize connections, active gesture listeners and tweens are
  cleaned up on destruction. Destroying the main panel also tears down its host
  and existing Finder owners; constructor-failure cleanup is registered early.
- **F**, **HIDE** and the floating launcher retain show/hide behavior. The settings
  sheet remains scrollable with a bottom **DONE** action and save/test feedback.

### Settings

| Setting | Default | Notes |
|---|---|---|
| Auto Execute | ON | Queue this build for the next server hop, if supported |
| Auto Steal | ON | Tracked target or best eligible local egg; independent of Auto Join |
| Auto Join | OFF initially | Persisted once changed; user-entered nonnegative income minimum |
| Custom target | OFF until enabled/edited | One income/s value for both automatic actions; default match mode EXACT |
| Shared feed minimum | `1B/s` | Independent of the Auto Join threshold |
| Speed Boost | OFF | Manual play, `16–32` speed, default `24` |
| Infinite Jump | OFF | Jump-request driven, rate limited, respawn-safe |
| Reduce Motion | OFF | Static space + rarity glow / instant transitions |
| Top 4 only | OFF | Income-sorted view only; keeps the full candidate/cache data |
| Minimum rarity | Any | Original rank options; filters list/eligibility without removing source records |
| Discord Webhook | OFF | Confirmed plants only, plus explicit **SEND TEST** |

### Custom income target

All value fields accept a finite nonnegative raw number or the existing income
units `K`, `M`, `B`, `T`, `Qa`, `Qi`, for example `2500000`, `2.5M`, `75B` or `2T`.
There is no client-side 1B–50B cap. Scientific notation is accepted; commas,
negative values, expressions, NaN and infinity are rejected rather than coerced.

Editing **CUSTOM TARGET / INCOME PER SECOND** enables the shared target. Choose
**EXACT VALUE (=)** or **THIS VALUE OR HIGHER (>=)**. The enabled target is applied
to Auto Join, automatic local/tracked pickup, and the ALL SERVERS view. MY SERVER
remains a live local listing. Explicit manual STEAL/JOIN actions remain manual
overrides. With the custom target disabled, the original independent minimum
settings are used.

Exact means numeric equality of the available `rate`, not a tolerance around the
rounded UI text and not an egg purchase/sale price. Values use Luau floating-point
numbers, not arbitrary-precision decimals; formatting round-trips the stored
number, and nonzero inputs that underflow to zero are rejected. The game/feed can provide a
displayed or estimated rate; the client cannot prove a hidden server-side value.
Unknown rates do not satisfy an exact match. Before pickup and after a claim,
criteria are checked again. Known matching hop metadata can preserve the fast
start while optional assets load. The target survives a hop via
`UNKNOWNValueTargetV1`, including without `readfile`. The Finder backend may have
its own retention/report limits; arbitrary client input does not prove that every
possible value will be available in its live feed.

**Speed Boost and Infinite Jump are suspended for the entire safe route, pickup,
return and planting operation.** Manual speed is restored afterward and on stop.

### Discord webhook privacy

Paste a valid HTTPS `discord.com` / `discordapp.com` `/api/webhooks/id/token` URL in
Settings; leaving the field saves and masks it. Enable notifications if wanted,
or use **SEND TEST** explicitly. The sender has its own bounded queue, timeouts,
429 retry-after handling and deduplication; failures do not interrupt gameplay.
Only egg details, income, rarity, server ID and the build label are sent — **never
your access key**. The webhook URL is a secret stored **locally** in executor
settings, not in the Finder feed. Clear the field to remove it.

## Publishing / Auto Execute

The default next-hop source for this PR build is:

```text
https://raw.githubusercontent.com/farsazzat1113/marvin/arena/c057ebf5-marvin/UNKNOWN.lua?v=ui23
```

**This build is published on the `arena/c057ebf5-marvin` branch**; the URL above
serves exactly this file (UNKNOWN.lua SHA-256
`5f7e6816471b547c2d3a559b54e0e122c22087a69d56be7fda948b25fa5a025e`).
Publication was explicitly authorized. An older pinned loader can leave an old
source override in
the executor environment; do not assume it points to the current local file.

The queued code waits for essential client objects, checks the freshest Auto
Execute setting, and retries downloads up to three times. It refuses a source
without the current build label rather than silently executing a different build.
This is a version guard, **not a cryptographic hash/signature check**. No access key
or webhook URL is embedded in the queued code.

If the executor has no teleport-queue API, Auto Join pauses instead of claiming
that automatic restart is available. Manual **JOIN ONLY** is still possible and
requires manual script execution in the destination. A source mismatch or missing
publication cannot be repaired by toggling Auto Execute ON.

### Roblox Studio compatibility boundary

This is the existing executor-oriented client, not a standalone Studio game.
Its production `require` references are game-owned ModuleScripts:

- Required: `Client.EggState`, `Shared.Types.AreaEggs`.
- Independently warmed: `Data.Assets`, `Shared.Modules.Mutations`,
  `Shared.Util.EggRecords`, `Shared.Util.AreaEggSlotIdentity`, `Client.PlotState`,
  `Shared.Util.AreaEggCycle`.

The full source includes these real references, not invented module bodies.
Ordinary LocalScripts do not provide executor HTTP, local file APIs, teleport
queueing or client `loadstring`. A Studio port would require actual module/server
implementations and a separate architecture change; no such port or stubs are
claimed here.

## Local state and network compatibility

| Executor workspace file | Purpose |
|---|---|
| `tenshi_beta_ui.json` | Persisted settings, **including the private webhook URL** |
| `tenshi_public_sighting_lifecycle_v1.json` | Existing reset/tombstone lifecycle |
| `tenshi_beta_top5_cycle_v2.json` | Existing retained top-five cache |
| `unknown_saved_access_key.txt` | Last online-accepted key; **private** |

The old UI-size-only file is no longer written; desktop size is in the UI settings.
UI22 adds `windowPosition` / `launcherPosition` (safe-area-relative pixel x/y),
`minRank` and `topFourOnly` to that same settings file. Invalid/offscreen new
coordinates are rejected/clamped. Legacy UI20 `panel` / `icon` arrays used a
different anchor/scale and are not blindly reinterpreted: UI22 centers once when
no valid new position exists, then retains the user-selected location.
The Finder continues to share egg sightings and place/job IDs. The existing
optional feature-report contract (including player IDs) is preserved; it never
blocks the classic public sender. Access keys and webhook credentials are never
included in either Finder report.

## Measured performance (UI23)

Selected harness results (60s simulated windows; see [PERF.md](PERF.md) for the
full method, every scenario and the estimates-vs-measurements split):

| Metric | UI22 | UI23 |
|---|---|---|
| Hidden manual `/v1/eggs` head polls | 70 | 29 (−59%) |
| Visible manual UI text writes | 11038 | 883 (−92%) |
| Stable-feed 10s text writes | 2595 | 161 (−94%) |
| Missing-module `require` retries /30s | 312 | 24 (−92%) |
| Exposed-page fetches while hidden+manual | 54 | 0 (paused) |
| Auto Join page discovery while hidden | 33 | 33 (preserved) |
| Feed-change freshness / show-wake refresh | 0.4s / within 1s | 0.4s / within 1s (preserved) |
| Hop resume UI readiness with 2s-slow validation | synchronous | synchronous (proven) |

Feed cadences while visible (0.2s Auto Join / 0.8s manual), scan/report/renewal
schedules, the join pipeline and all protected blocks are intentionally unchanged.

## Offline checks

Install the [Luau CLI](https://github.com/luau-lang/luau), then:

```bash
LUAU_BIN=/path/to/luau LUAU_COMPILE_BIN=/path/to/luau-compile python3 tests/run.py
```

The runner compiles the **actual shipped file**, including Luau register limits,
and executes its real policy/runtime with deterministic Roblox/executor mocks.
It checks transform-write guards, traps, ground gaps, lag frames, cooldowns, late
ACKs, respawn, perks, startup/auth, HTTP lane independence, expiry/rollback,
pagination, mobile touch targets, webhook opt-in/rate limits, cleanup and queueing.
There are currently **7 policy + 47 integration + 28 UI/input + 5 performance-bound groups (87 total)**.
The UI suite adds mouse/touch offsets, safe-area/scaling geometry, all four bounds,
release/cancel/focus handling, no-refresh position/size writes, persisted positions,
responsive layouts (including oversized short-desktop cases), independent button
actions, opener fallbacks, rarity callbacks, Top 4/cache/candidate independence,
visual budgets/reduced motion, key button/Enter submission and destruction/failed
construction cleanup. The original integration suite still covers custom targets,
STEAL/FIND, previews and queued-runtime guards. These checks do not validate
live game rendering, a real executor queue or network service availability.
No test contacts Roblox, the live Finder/key service or Discord.

### Still requires an in-game smoke test

1. Pick up a nearby tracked egg and plant it with **no character warp**; repeat
   with a slowed carry speed, a distant egg and a streamed-in field.
2. Put a rotated/thin Trap Hitbox in both the outbound and home paths; add one
   mid-route. A blocked/unsupported route must stop, not clip or jump through it.
3. Fail a carry/plant, respawn mid-route and mid-carry, then toggle Auto Steal and
   manual perks; verify cooldown, recovery, restored speed and no stale worker.
4. With the new source published, hop while validation/report requests are slow;
   confirm the tracked target starts as soon as character/terrain are usable.
5. Check portrait/landscape settings, Discord **SEND TEST**, and revoked/expired
   key behavior using your own test configuration.
6. Enter a custom income below 1B and above 50B, select EXACT versus AT LEAST,
   change it mid-claim and mid-route, and verify the actual live rate semantics.
7. Verify the configured next-hop URL contains this exact published build; test
   an unsupported executor and the explicit manual JOIN ONLY path separately.
8. Drag from different header offsets at different desktop scales, with mouse
   and real one-/two-finger touch. Release outside the header; cancel/lose focus,
   rotate the device, refresh the feed, hide/show and reinject. Verify no jump,
   stale gesture, accidental button activation or unwanted re-centering.
9. Inspect actual star/nebula/glass rendering, Z-order, clipping, readability,
   frame cost, reduced motion and 44px mobile targets in Roblox on real devices.
10. Exercise the original Discord profile, accessible rarity filter and Top 4
    switch, including unavailable reports and returning to the full listing.

**Limit:** the client attribute does not disable server-side enforcement. Offline
checks do not establish the game’s private Anti-TP thresholds or guarantee
“no death” on a live server. The design avoids artificial displacement and fails
closed; actual physics, streaming, server rules and game-module changes still
need the checks above.
