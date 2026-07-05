# Spec 0002 — Social layer, capsules, real-GPS, around-maps & permadeath

Status: **done** (92 unit + 8 smoke green; adversarially reviewed, 3 confirmed defects fixed) ·
Engine: Godot 4.7 port (`godot/`, forward engine) · Reference: JS web slice is frozen.

Refactor executed: world/session orchestration extracted from `main.gd` into a scene-free,
headless-testable `scripts/session.gd` (owns the region store + social graph + travel + respawn);
`main.gd` is now UI/input/render only. Pawn-field list deduped into `Sim.PAWN_FIELDS`. Review fixes:
`persistence._canonical` normalizes whole-number floats so the hash chain survives JSON save/load;
`session.respawn()` flies home by **region identity**, not by any storage present.

Turns the six-part `/goal` into a coherent, headless-testable vertical slice on the deterministic
scene-free sim. Everything that needs infrastructure we cannot run locally (real multiplayer,
on-chain writes) is implemented as a **deterministic local model with a clearly marked seam**.

## 1. UI pass for existing features
Full restyle of `main.gd` HUD: themed `StyleBoxFlat` panels, a top toolbar of panel toggles,
color-coded need bars, richer stock/equipment readout, tooltips + affordability on the build bar,
styled toasts/log. New panels reuse one shared panel style. Death → dedicated respawn screen.

## 2. Friends / clans / alliances / empires  (`scripts/social.gd`, pure + testable)
Four-tier social graph as a **gameplay** layer, not just UI:

    Player ─▶ Clan ─▶ Alliance ─▶ Empire

- `new_graph(name, seed)` deterministically builds the account's graph **plus a simulated roster**
  of other players/clans/alliances/empires (since the "colony = other live players", offline we
  simulate them). Reproducible from `seed`.
- Diplomacy: my clan holds a `stance` (ally / neutral / hostile) toward every other clan; alliance
  membership implies ally, shared empire implies ally.
- **Gameplay effects wired into the sim:**
  - *Raids* are attributed to a **hostile clan faction**; allied/empire clans never raid you, and a
    world with more hostiles raids harder (`raid_pressure`).
  - *Friends* can send you **capsule invites** (goal 4) to their location.
  - *Death* respawns your new pawn at your **clan base** (goal 6).
- **Seam:** `new_graph` is where a real backend would inject the live social graph; the shape is the
  wire format. Nothing else in the sim assumes the roster is simulated.

## 3. Real-GPS + invite mode  (`main.gd` spawn flow)
- **Real-GPS spawn:** on web export, `JavaScriptBridge` → `navigator.geolocation`; everywhere else a
  manual **lat/lon entry** (the universal fallback). Cmdline `-- gps <lat> <lon>` for headless.
- **Invite mode:** the game can boot straight into accepting an invite and land the pawn at the
  invite's target instead of a preset. Cmdline `-- invite <lat> <lon> [name]`.

## 4. Capsules (RimWorld drop pods) + invites  (state on `sim`, math in `data.gd`)
- **Daily base capsule:** each in-game day grants/refills **1** charge. One capsule moves **one
  person, once, ≤ `CAPSULE_BASE_RADIUS_KM` (100 km)** from the launch point, **with full personal
  inventory** (carry + equipped + items). The base/stock stays behind (you can't teleport a base).
- **Invite object:** `{id, inviter, clan, lat, lon, name, radius_km, allow_receive}` — the friend's
  *permission to receive*, *who invited*, and *where to fly*. Accepting validates `allow_receive` and
  that the target is within capsule radius, then launches.
- **Validation is pure/testable:** `capsule_can_reach(lat, lon)` (charge + haversine ≤ radius);
  `accept_invite(id)`. The region swap itself is orchestrated by the session (`main.travel_to`).

## 5. Around-maps generated on entry + seed+diff+save persistence  (`scripts/persistence.gd`)
- The world is a lattice of regions keyed by rounded lat/lon. A region's **terrain is fully
  reproducible from its seed** (`WorldGen.hash_seed(lat,lon)`), so we never store the tilemap for
  procedural regions — only the **diff** (player-built buildings, depleted nodes) + a small **save**
  (player, stock, time). OSM-overlaid regions additionally store a compacted tile **save**.
- **Generated on entry:** `travel_to(lat,lon)` saves the current region into the `WorldStore`, then
  loads the destination from the store if visited, else generates it fresh from seed.
- **Blockchain-shaped storage:** each region record carries `prev` + content-addressed `hash`
  (`content_hash` over canonical JSON) forming an **append-only hash chain** — the on-chain shape is
  `seed + diffs + save`. `persistence.gd` reads/writes this to `user://world.json` today; the same
  record is what a chain backend would commit. **Seam:** `content_hash` / `store_commit`.

## 6. Permadeath = fresh pawn  (`sim.respawn_new_pawn`)
Death no longer freezes forever. You **lose the pawn entirely** — skills reset to zero, carried loot
and equipped/owned items gone — and receive a **new un-leveled pawn** at your clan base. The
settlement (buildings + stock) persists as a clan asset, so the loop continues: die → rookie again.

## Test coverage (headless, added to `tests/run_tests.gd`)
Social graph determinism + diplomacy; capsule charge/radius math + daily refill; invite accept
rules; persistence region roundtrip (seed+diff+save reconstructs state) + hash-chain integrity;
permadeath resets pawn but keeps settlement. Smoke: capsule launch generates+persists a new region.
