# Spec 0008 — Catalog build/craft integration (resource-system bridge) — ADR, design-only

> Status: **phases 1–4 shipped (first tier)** (drafted 2026-07-08; updated 2026-07-17). Phase 1 (BOM
> planner) landed in the catalog browsers; phase 2 (open catalogue-keyed stock) landed behind
> `sim.use_catalog`; **phases 3–4 (first slice) landed 2026-07-17** per the owner's «продовжуй за
> роадмепом» go-ahead, taking the §2 recommendation as the decision (Option A phased via C):
> • **building-def seam** — `sim.building_def()` (`sim/catalog_live.gd`): data.gd palette first, else
>   the catalogue BuildingDef in the same shape; every def consumer (sim, sim/ modules, world_view,
>   hud_model, session) reads through it (tripwire `_t_building_def_seam`), so `try_build` places any
>   unlocked, affordable catalogue building on the LIVE map (gated on the flag for new placements);
> • **live catalogue craft** — `sim.catalog_craft(recipe)`: station standing on the map + research
>   gate + open-stock afford → inputs paid, bulk output deposited (thing-output recipes deferred);
> • **map deposits (phase 4, tier 1)** — `world_gen.generate_map(..., deposits)`: clay/sand/coal/
>   iron/copper/fiber nodes from an independent seeded stream (base map byte-identical, ON = strict
>   superset, guaranteed minimum per kind), so the neolithic→iron chains are playable anywhere;
> • **live browsers** — the B/C/N catalog browsers act on the REAL game when the world is catalogue-
>   backed (`cat_build` arms the placement ghost, `cat_craft` hits the live sim, `cat_research` feeds
>   the live queue), badge flips «демо»→«у грі»; sandbox mode unchanged otherwise;
> • **the flip** — `newhud` new games boot with `session.use_catalog = true`; the engine default stays
>   OFF, so the frozen slice and every pre-existing suite are byte-identical (per-region flag persists
>   in saves — §5.2 answered as "coexist behind the flag", no migration).
> Phase-4 remainder (ores beyond the first tier, thing-output crafting, timed bills) tracks the
> unification plan (spec 0007-catalogue-sim-unification Stage 4+). The stock seam is
> `sim.res_key/res_amount/cost_keys/afford`, covered by `_t_open_stock`/`_t_catalog_live` (both flag
> states). Depends on **spec 0007** (the research→unlock pipeline — the gate this step consumes) and
> **spec 0004 + `docs/catalog.md`** (the 335-def tree). Design intent for the player side:
> `GDD_BOOK/gdd.json` (`section:mechanics_overview`, `section:scope`).

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

## 4. What ships now vs later

- **Now (safe, this spec's companion PR may include):** phase 1's BOM planner — pure, Node+Godot
  mirrored, zero sim risk; it is useful on its own (tooltips) and is the foundation the rest builds on.
- **Later (needs this ADR approved):** phases 2–4 (the flagged sim/stock changes + the build/craft
  panels). They alter the sim's build/craft/save paths, so they wait on owner sign-off per the AGENTS.md
  migration rule.

## 5. Open decisions for the owner

1. Confirm **Option A (phased via C)** over B.
2. Save-shape: is a one-time migration of the 6-key stock to the open stock acceptable, or must both
   coexist behind the flag indefinitely?
3. Scope of phase 4: promote the *whole* 78-resource tree, or a curated first tier (neolithic → iron)
   for the first playable pass?
