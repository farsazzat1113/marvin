# UNKNOWN · UI21 “Obsidian”

**Shared Egg Finder + grounded auto-steal + Cloudflare key gate**, shipped as one
self-contained Roblox **Luau** file: [`UNKNOWN.lua`](UNKNOWN.lua).

UI21 replaces UI20’s character warps and Glass Premium interface. Existing Finder
report/feed/claim endpoints, reset tombstones and retained top-five data are kept.

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

Auto Steal defaults **ON**. It targets the egg tracked by a server join; while Auto
Join is enabled it can also take the best eligible local field egg. Already
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

## Obsidian interface

A new graphite/champagne/teal visual system, native monogram launcher, soft fades
and press motion, rarity-colored card borders and breathing icon glows. No remote
UI textures, bitmap font downloads or always-running starfield are required.

- Bottom-right panel, bottom scope tabs and **thumb-zone Auto Join / Settings**.
- Mobile controls stay touch-sized instead of shrinking with desktop UI scale;
  short landscape mode frees space for the scrolling feed.
- Full-height, scrollable settings sheet with a bottom **DONE** action and visible
  save/test feedback.
- **Reduce motion** disables looping glow motion and transition tweening.
- **F**, the minimize button and the floating **U** launcher show/hide the panel.

### Settings

| Setting | Default | Notes |
|---|---|---|
| Auto Execute | ON | Queue this build for the next server hop, if supported |
| Auto Steal | ON | Tracked target, or best eligible local egg with Auto Join |
| Auto Join | OFF initially | Persisted once changed; income threshold `1B–50B` |
| Shared feed minimum | `1B/s` | Independent of the Auto Join threshold |
| Speed Boost | OFF | Manual play, `16–32` speed, default `24` |
| Infinite Jump | OFF | Jump-request driven, rate limited, respawn-safe |
| Reduce Motion | OFF | Static rarity glow / instant transitions |
| Discord Webhook | OFF | Confirmed plants only, plus explicit **SEND TEST** |

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

The old pinned backup loader has been removed. The default hop source is now:

```text
https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/UNKNOWN.lua?v=ui21
```

**Publish/merge this build to the default branch, `Marvin`, before testing cross-server
Auto Execute.** Editing a local/session branch does not update that remote URL.
To test a different **already published** source, set it before running the file:

```lua
getgenv().UNKNOWN_SCRIPT_URL = 'https://raw.githubusercontent.com/OWNER/REPO/BRANCH/UNKNOWN.lua'
```

That override is carried into the queued loader for subsequent hops. The queue
checks the freshest Auto Execute teleport setting, including on executors without
`readfile`; it never embeds the access key or webhook URL. Executors with no
teleport-queue API still require manual execution after entering the next server.

## Local state and network compatibility

| Executor workspace file | Purpose |
|---|---|
| `tenshi_beta_ui.json` | Persisted settings, **including the private webhook URL** |
| `tenshi_public_sighting_lifecycle_v1.json` | Existing reset/tombstone lifecycle |
| `tenshi_beta_top5_cycle_v2.json` | Existing retained top-five cache |
| `unknown_saved_access_key.txt` | Last online-accepted key; **private** |

The old UI-size-only file is no longer written; desktop size is in the UI settings.
The Finder continues to share egg sightings and place/job IDs. The existing
optional feature-report contract (including player IDs) is preserved; it never
blocks the classic public sender. Access keys and webhook credentials are never
included in either Finder report.

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

**Limit:** the client attribute does not disable server-side enforcement. Offline
checks do not establish the game’s private Anti-TP thresholds or guarantee
“no death” on a live server. The design avoids artificial displacement and fails
closed; actual physics, streaming, server rules and game-module changes still
need the checks above.
