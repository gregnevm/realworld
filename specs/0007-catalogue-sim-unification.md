# Spec 0007 — Catalogue ↔ live-sim unification (ADR + spec, no code this pass)

> Status: **design-only · touches no code this pass** (drafted 2026-07-08). Decides *how* the live
> playable sim (`scripts/sim.gd` over `scripts/data.gd`, 6 resources / 7 buildings / 4 items) converges
> onto the deep content catalogue (`content/catalog.json`, 333 defs) that now drives a **parallel**
> forward-engine model (`scripts/catalog_sim.gd`) surfaced in the HUD via the spec-0005 view layer.
> Companion to: **specs/0003** (the Def/Comp/Stat/System kernel this runs on), **specs/0004**
> (mechanics catalogue & UX), **specs/0005** (view-layer rules R1–R12 this must not break),
> **docs/catalog.md** (the tree), **docs/mechanics-status.md** (the infrastructure-vs-content tracker
> whose last open row this closes). No migration code lands this pass — same discipline as spec 0006
> and spec 0005 Batch 0: **architecture before migration.**

---

## 0. Why this exists (one paragraph)

The catalogue project shipped in three merged increments (159 → 333 defs) plus a full read/write view
pipeline: `catalog_view.gd` (pure ViewModel), `catalog_panels.gd` (TechPanel / ResearchTiersPanel /
three action browsers), `catalog_sim.gd` (research/build/craft on the real kernel) and `catalog_verbs.gd`
(the intent router). It is **coherent, reachability-validated, and operable** — but it runs as a
`CatalogSim.shared()` model **beside** the live `data.gd`/`sim.gd` world, not as it. So the HUD now shows
two economies: the hero walks a `data.gd` map (wood/stone/food/scrap/planks/components) while the
browsers build/craft/research against a separate 78-resource catalogue sandbox. That is precisely the
**dual-content drift** risk `docs/mechanics-status.md` and `gdd.json §risks` warn about — two sources of
truth for "what exists." This spec decides, on paper, the **staged path to one world** backed by the
catalogue, reusing the seams already built, so the migration code starts de-risked and each stage ships
CI-green on its own.

### Repo-precedent constraints (verified ground truth — non-negotiable)

- **Determinism is the product.** World = pure function of `lat/lon` → PCG32(FNV); every stochastic path
  takes an explicit seeded rng. Migration must not introduce a global `randf()` or a time seed.
- **No-build, fixed script-load order, global `RW`/registries.** No bundler, no `class_name`,
  inclass+preload only; `sim` never imports `ui` (R1). Migration edits stay inside these.
- **View-layer rules R1–R12 are enforced by `run_ui_tests.gd` tripwires.** Any migration that touches
  `ui/` must keep the source-grep tripwires green (no raw `Color()`, value-data snapshots, build-once).
- **JSON int→float coercion** (catalogue amounts load as floats): compare with `int()`/`is_equal_approx`,
  never `== 5`. Already handled by `catalog.gd`/`catalog_sim.gd`; carry it through the migration.
- **The authoring environment cannot run Godot** (network policy blocks the engine download). Every
  stage is therefore verified by **headless suites in CI + `gdparse` + `node --test`**, never by a local
  render. This forces small, independently-testable stages — a feature, not a limitation.

---

## 1. Current seam inventory (what already exists to build on)

| Layer | Live world (`data.gd`) | Catalogue world (this project) |
|---|---|---|
| Resources | `RES` (6) + `RES_ORDER` | `catalog.json` resources (78), `ResourceDef` |
| Buildings | `BUILDINGS` (7) + `BUILD_ORDER` | `BuildingDef` (85) incl. `is_station()` |
| Items | `ITEMS` (4) | `ItemDef` (71) |
| Crafting | `sim.craft_item()` (flat) | `Production.ProductionSystem` + `Bill` + `CompWorkbench` |
| Research | — (none) | `Production.ResearchState` + the 41-node DAG |
| State holder | `sim.gd` (`stock`, `buildings`, `player`) | `catalog_sim.gd` (`stock`, `things`, `research`) |
| Read (HUD) | `HudModel.snapshot()` slices | `catalog_view.snapshot()` (already in the slice) |
| Write (intents) | `input_verbs.gd` (`build`/`craft`/…) | `catalog_verbs.gd` (`cat_build`/`cat_craft`/`cat_research`) |

The convergence point is deliberate: `HudModel._catalog_slice` already reads a shared model, and the
router already carries both verb sets. Unification is **making `sim.gd` be the catalogue model**, then
retiring the duplicate tables — not writing a new system.

## 2. Decision (ADR)

- **D1 — The catalogue is the single source of truth for content.** `data.gd`'s tables become a *view /
  compatibility shim* over the catalogue, never a second authority. Final state: `data.gd` holds only
  the Phase-0 HUD ordering + the frozen-JS parity constants, deriving everything else from `catalog.gd`.
- **D2 — Migrate in independently-shippable stages, each CI-green.** No big-bang rewrite. Every stage
  keeps `run_tests` (119) / `run_kernel_tests` (152) / `run_catalog_tests` / `run_ui_tests` /
  `run_smoke` green, and adds its own headless coverage before it lands.
- **D3 — Keep `catalog_sim.gd` as the model; fold it into `sim.gd`'s tick rather than replace it.** The
  hero's world gains a `ResearchState` and station `Bill`s; the existing movement/needs/raid loop is
  untouched. `CatalogSim.shared()` stops being a *separate* sandbox once `sim.gd` owns one instance.
- **D4 — The frozen JS slice (`game/`) stays a reference and is NOT migrated.** Parity is a Godot-side
  concern from here; `game/js/entities.js` is a historical snapshot (spec 0005 precedent).
- **D5 — No networking, no new content, no render changes this pass.** Networking is spec 0006; content
  depth is done; this spec is purely the data-model convergence.

## 3. Staged migration plan (each stage = one PR, CI-green)

**Stage 0 — parallel model (DONE).** `catalog_sim` + browsers operate the tree beside the live sim.
Shipped in PR #3. This spec covers Stages 1–5.

**Stage 1 — resource vocabulary bridge.** A pure `scripts/data_bridge.gd`: a bidirectional map between
the 6 `data.gd` ids and catalogue ids (`wood/stone/scrap/planks/components` are 1:1 already;
`food` → `raw_food`/meal). Headless test: every `data.gd` RES id resolves to a catalogue `ResourceDef`;
round-trips are stable. No behaviour change — this is the Rosetta stone Stage 2 needs.

**Stage 2 — catalogue-keyed stock.** `sim.stock` becomes keyed by catalogue resource ids (a superset of
the 6); `data.gd.RES`/`RES_ORDER` become a curated *display view* over `catalog.gd` resources. The HUD
stock panel still shows the ordered 6 (via `RES_ORDER`), now sourced from the catalogue. Gathering nodes
map their yield through the bridge. Existing stock tests updated to the new ids; `run_smoke` stays green.

**Stage 3 — catalogue buildings.** `sim.try_build` reads cost/hp/`is_station` from `BuildingDef` instead
of `BUILDINGS`; `data.gd.BUILDINGS`/`BUILD_ORDER` become a curated buildable subset (the Phase-0 palette)
projected from the catalogue. `build_slice` in `HudModel` already speaks the shape. Station buildings
placed here gain a `CompWorkbench` — the hook for Stage 4.

**Stage 4 — research + crafting in the tick.** The hero gains a `ResearchState`; `sim.update` ticks the
catalogue `ProductionSystem` over placed station `Bill`s (folding `catalog_sim.tick` into the real loop).
`craft_item` becomes "queue a bill"; the flat craft is retired. `HudModel._catalog_slice` now reads the
LIVE `sim`, and `CatalogSim.shared()` is replaced by `session.sim` — the two economies become one. The
browsers keep working unchanged (same slices, same intents, now one target).

**Stage 5 — retire the duplicate tables.** `data.gd` shrinks to the compat shim (HUD order + JS-parity
constants); `ITEMS` folds into `ItemDef`. `docs/mechanics-status.md` `content_tree` row flips to fully
integrated; the "two worlds" scaffolding note is deleted.

## 4. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Breaking the 119 sim tests / smoke playthrough | Stage-gate: each PR keeps all suites green; stock/build tests migrate id-by-id with the bridge. |
| `data.gd`-keyed save files (`persistence.gd` diff+hash-chain) break on new ids | Stage 2 writes a save-version bump + a bridge-based load migration; `is_equal_approx`, hash-chain rules from spec 0002. |
| Can't render-verify the HUD after Stage 3/4 | Every stage adds headless view-model + panel tests (the spec-0005 pattern); `parse_check` compiles the whole graph; a real render is a manual post-merge check. |
| Balance/economy retuned by richer costs | Stage 4 keeps `Balance.assess()` inputs shaped as today; a separate tuning pass follows, out of scope here. |
| Dual-model window (Stages 1–3) shows two economies | Accepted, temporary; explicitly the point of staging. Stage 4 collapses it. |

## 5. Test strategy (headless-first, since no local render)

- Each stage ships its own `run_catalog_tests.gd` / `run_ui_tests.gd` additions BEFORE the behaviour
  change, following the proven pattern (value-data / R8, build-once / R2, prereq-gate enums, playthrough).
- `parse_check.gd` (now preloading `newhud_main`) compile-checks the whole HUD graph every stage.
- `node --test` continues to guard the content graph (`tests/catalog.test.js`) and the frozen JS core.
- `gdparse` on every changed `.gd` before push; CI (Godot 4.7 on the runner) is the authoritative gate.

## 6. Non-goals (this pass)

Networking (spec 0006), new content (done), render/theme changes, Balance retuning, and any edit to the
frozen `game/` JS slice. This spec is the **decision + staged plan**; Stage 1 is the first code PR.
