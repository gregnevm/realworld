# Spec 0008 — Catalog build/craft integration (resource-system bridge) — ADR

> Status: **phases 1–4 shipped** (drafted 2026-07-08; §5 signed off + phases 3–4 landed 2026-07-29 on
> the owner's go-ahead). Phase 1 (BOM planner) landed in the catalog browsers; phase 2 (open
> catalogue-keyed stock) behind `sim.use_catalog`; phase 3 (the gated live build/craft) and phase 4
> (the curated live resource tier) — see §6 below. The flag stays **default OFF**, so the shipped
> slice stays byte-identical (its suites prove it). The stock seam is `sim.res_key/res_amount/`
> `cost_keys/afford`; the NEW def seam is `sim.building_def` (data.gd first, `catalog_defs.gd`
> adapter for catalogue-only ids when the flag is on). Depends on **spec 0007** (the research→unlock
> pipeline, live — it is the gate this step consumes) and **spec 0004 + `docs/catalog.md`** (the
> 335-def tree). Design intent for the player side: `GDD_BOOK/gdd.json`
> (`section:mechanics_overview`, `section:scope`).

---

## 0. The gap this closes

Spec 0007 made the tech pipeline run end-to-end — research benches fund it, projects unlock, the HUD
reads live — but it stopped at a deliberate boundary (spec 0007 §5): **unlocking research does not yet
change what the hero can build or craft**. The playable slice (`data.gd`) builds from a 6-resource table
(`wood/stone/food/scrap/planks/components`); the catalogue (`catalog.json`) is a 78-resource superset the
slice cannot touch. So `progression.unlocked_buildings()/_recipes()/_items()` — the exact query a gated
build/craft menu needs — has no consumer in play. This spec decides how to bridge the two so the depth
becomes *buildable*, not just *readable*.

## 1. Repo-precedent constraints (non-negotiable ground truth)

- **Determinism / no-DOM sim** (spec 0003, AGENTS.md): the bridge stays scene-free + headless-testable.
- **Additive to the shipped slice**: the frozen JS game (`game/`) and the current Godot slice must keep
  passing their suites. `data.gd` may be *superseded* by the catalogue as the live source, but only
  behind a flag/phase, never by silently changing the 6-resource save shape mid-stream.
- **View rules R1–R12** (spec 0005): a catalog build/craft menu is a Panel reading a pure slice; it emits
  `build`/`craft` intents; only the router names a mutator. No new Ukrainian in `sim.gd` (R10).
- **Two-validator mirror** (catalog.gd ↔ catalog.test.js; progression.gd ↔ progression.test.js): any new
  pure logic (a bill-of-materials planner, affordability) ships with a Node mirror so CI verifies it
  without Godot.
- **Big migrations need an ADR first** (AGENTS.md rule) — this document.

## 2. The core question

The slice's `stock` is `{res:StringName -> int}` over 6 ids; recipes/buildings in the catalogue cost ids
from 78. Three ways to reconcile:

### Option A — promote the catalogue to the live content source (recommended)
`stock` becomes an open `{catalog_res_id -> int}`; map the 4 raw map-nodes (`tree/rock/bush/scrap`) onto
their catalogue raws (`wood/stone/food/scrap` already share ids); `try_build`/`craft_item` look up
`catalog.gd` defs instead of `data.gd`, gated by `progression.gate_ok(def.research)` and afforded against
the open stock. `data.gd` stays as the **Phase-0 fallback pack** (flag `use_catalog := false` keeps the
shipped slice byte-identical for its suites; the new game boots with `use_catalog := true`).
- **Pro:** the real Phase-1 direction; one content source; the 335-def tree becomes fully playable; the
  progression gate finally has its consumer. **Con:** touches the sim's build/craft/stock paths + save
  shape — the largest change; must be phased and flagged.

### Option B — a parallel catalog-craft modal bridged to 6 resources
Keep `data.gd` live; add a modal that crafts only a curated catalog subset whose costs are re-expressed
in the 6 slice resources. **Pro:** small, isolated. **Con:** a second content system that drifts from the
catalogue; throws away the reachability guarantee; a dead end. **Rejected.**

### Option C — resource-alias layer (incremental A)
Ship Option A's machinery but start with an *alias map* that collapses catalogue resources onto the 6
slice ids until each new resource is given a real map-source / recipe. Buildings/recipes unlock as their
inputs become obtainable. **Pro:** A's destination reached in small, always-green steps. **Con:** the
alias map is throwaway scaffolding.

**Recommendation: Option A, delivered via Option C's phasing** — build A's flagged machinery, grow the
live resource set outward from the 4 raws using the catalogue's own reachability order, so every push
keeps the slice playable and the suites green.

## 3. Proposed phasing (each phase = one green PR)

1. **BOM planner (pure, Node-mirrored, no sim change).** `catalog.gd`: `production_chain(res_id)` — the
   ordered recipe steps from raws to a resource; `missing_for(def, stock)` — the shortfall to afford a
   building/recipe under an open stock. Node test mirrors both. *This is safe to do now* and de-risks the
   rest. It also powers "to make X you need …" tooltips immediately in the ResearchPanel.
2. **Open stock + raw mapping behind `use_catalog`.** `sim.gd` reads/writes an open stock when the flag is
   on; `data.gd` path untouched when off. Smoke test covers both flags.
3. **Gated catalog build/craft menu.** A `CatalogBuildPanel`/`CatalogCraftPanel` reading a pure slice of
   `progression.unlocked_buildings()/_recipes()` + `missing_for`; emits `build`/`craft` intents; locked
   rows show `steps_to_unlock` (already shipped). R2/R9-clean.
4. **Grow the live resource set** outward along reachability until the alias map is empty and Option A is
   complete.

## 4. What ships now vs later (historical — all four phases have since shipped)

- **Now (safe, this spec's companion PR may include):** phase 1's BOM planner — pure, Node+Godot
  mirrored, zero sim risk; it is useful on its own (tooltips) and is the foundation the rest builds on.
- **Later (needed this ADR approved):** phases 2–4 (the flagged sim/stock changes + the build/craft
  panels). They alter the sim's build/craft/save paths, so they waited on owner sign-off per the
  AGENTS.md migration rule — granted 2026-07-29 (§5).

## 5. Decisions (owner go-ahead 2026-07-29; recorded with the rationale applied)

1. **Option A (phased via C) — confirmed** over B. The alias layer never materialised as a throwaway
   map: `data_bridge.gd` (6 ids) IS the alias, and it stays permanently as the legacy-save
   vocabulary bridge.
2. **Save-shape: both coexist behind the flag; no forced migration.** Phase 2 already persists
   `use_catalog` per save, so old saves keep reading their 6-key stock forever. Flipping the DEFAULT
   to ON for new games is the one remaining switch — it is deliberately NOT taken here: it flips the
   suites' baseline world and deserves its own commit once the live tier has play-time behind it.
3. **Phase-4 scope: the curated first tier, DERIVED not hand-listed.** The live tier = the
   catalogue's own reachability closure seeded from the resources the live map actually sources
   (wood/stone/raw_food/scrap + the phase-4 node-yield raws: iron_ore/coal/clay/sand/copper_ore/
   plant_fiber/herbal). That closes over 38 resources / 73 buildings / 27 recipes / 43 items —
   neolithic through steel/components. The remainder (hunting, farming, exotic mining tiers:
   meat/hide/grain/wool/gold/uranium…) stays browsable-but-unreachable until its map source ships.

## 6. What phases 3–4 shipped (2026-07-29)

- **Def seam `sim.building_def(kind)`** — the ONE place a building id becomes a def dict: data.gd
  first (its 13 tuned Phase-0 defs win — one truth per id), the `catalog_defs.gd` adapter for
  catalogue-only ids when the flag is on. Every tick path (blocks/enclosure/heat/light/traps/
  turrets/capacity/hp/refunds) reads the seam, so both vocabularies ride the same sim.
- **Curated live-buildable filter (capability-driven, not a hand list)** in `catalog_defs.gd`:
  categories structure/production/storage/defense only; no `power` participation (no live power net —
  a free-running powered turret would be the reverse of a decorative trap); defense must map onto a
  live brain (turret-shaped `range+cooldown` → the generic turret loop, or `trap` → `trap_dps`).
  Power/farming/comfort/art/utility/ship wait for their systems.
- **Live build** rides the EXISTING grammar: a catalog browser row arms the ordinary `select_build`
  ghost; the map click lands in `sim.try_build`, which now speaks catalogue ids through the def seam
  (gate → afford → pay → place). No new verb; wire commands work for catalogue ids for free.
- **Live craft**: `sim.craft_catalog(recipe_id)` — station placed (id equality: the live `workbench`
  IS the catalogue station `workbench`) → research gate → afford inputs → pay → deposit output.
  Instant, like the slice's `craft_item`; kernel work-time bills remain the sandbox/kernel model.
  Returns value-data reasons; the router (`catalog_verbs.gd`) owns the refusal texts (R10).
- **Phase 4 node-yield enrichment**: under the flag, gathering yields each node kind's catalogue
  bundle (rocks: ore/coal/clay/sand interleaved with stone; trees: fiber; bushes: herbs/fiber) via a
  PURE function of (cell, remaining amount) — deterministic, replay/rejoin-exact, and it consumes NO
  rng stream, so threat/weather determinism cannot shift by a draw. Worldgen untouched (goldens hold).
- **HUD**: the three catalog browsers switch their honesty badge to «живе» when the snapshot's state
  IS the live sim (`live` flag in the catalog slice); `build_actions` are filtered to the
  live-buildable set so no row promises what the sim would refuse; the StockPanel grows a fixed pool
  of catalogue-stock lines. Sandbox mode (flag OFF) is pixel-identical to before.
- **Tests**: `_t_catalog_live` (run_tests) covers both flag states end to end; the Node mirror pins
  the live-tier closure so the two validators can never disagree about what the live game can reach.
