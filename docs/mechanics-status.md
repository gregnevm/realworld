# Mechanics catalogue — status tracker

> Snapshot: **2026-07-05**. Purpose: make the *infrastructure-vs-content* gap visible — the kernel is
> deep (~377 headless tests) but not every designed mechanic is yet wired into a playable slice. This
> is the at-a-glance «what is real vs only designed» view that complements `GDD_BOOK/gdd.json`
> (`section:mechanics_overview`) and the specs.
>
> Derived from specs 0001–0005 + `godot/scripts/kernel/` at snapshot time; treat integration/test
> columns as **best-effort — the owner should correct any cell**. Batch 4 (gear) was **untracked** at
> snapshot, so its row may have advanced since.

**Legend:** ✅ done · 🟡 partial · ⬜ not started · ⚠️ untracked/uncommitted at snapshot

| Mechanic (GDD id) | Designed | Coded | Integrated in playable slice | Tested (headless) | Notes |
|---|:---:|:---:|:---:|:---:|---|
| `map_generation` | ✅ | ✅ | ✅ | ✅ | `world_gen.gd`; OSM overlay + procedural fallback; coord-seed invariants |
| `climate` | ✅ | ✅ | 🟡 | ✅ | `kernel/climate.gd` closed-form; seam to live weather API; game-side surfacing partial |
| `character_sim` | ✅ | ✅ | ✅ | ✅ | `sim.gd` single hero |
| `needs` | ✅ | ✅ | 🟡 | ✅ | `kernel/needs.gd` (food/rest); **water lives in `gear.gd`** ⚠️ |
| `health` | ✅ | ✅ | 🟡 | ✅ | `kernel/health.gd` 6-part + hediffs; **scars/prosthetics/medicine in `gear.gd`** ⚠️ |
| `inventory_gear` | ✅ | ⚠️ | ⬜ | ⚠️ | `gear.gd` exists but **untracked**; not yet wired into the sim loop |
| `gathering` | ✅ | ✅ | ✅ | ✅ | tool multipliers formalized (axe 1.6× / pick 1.9×) |
| `base_building` | ✅ | ✅ | ✅ | ✅ | building costs/HP in `data.gd` |
| `crafting_automation` | ✅ | ✅ | 🟡 | ✅ | `kernel/production.gd` bills (count/until); quality 0–6. **Content tree now authored** — see below |
| `content_tree` | ✅ | ✅ | 🟡 | ✅ | `content/catalog.json` + `kernel/catalog.gd`: 335 defs (78 res · 41 research · 87 build · 58 recipe · 71 item), reachability-validated |
| `progression_research` | ✅ | ✅ | ✅ | ✅ | **spec 0007** — `kernel/progression.gd` queueable research pipeline over the tree; live from research benches (`session.tick_research`), surfaced in `ResearchPanel` (LEFT dock); planner (`research_path`/`steps_to_unlock`). Node + Godot mirrored tests |
| `raids_pvp` | ✅ | ✅ | ✅ | ✅ | threat-driven waves + tactic escalation via Balance |
| `balance_director` | ✅ | ✅ | 🟡 | ✅ | `kernel/balance.gd`; `decide()` AI seam; incident MTB pacing |
| `convoy_logistics` | ✅ | ✅ | ✅ | ✅ | real hubs (Kyiv/Lviv/Odesa/…); trade offers |
| `offline_persistence` | ✅ | ✅ | ✅ | ✅ | `persistence.gd` seed+diff+hash-chain; travel/permadeath |
| `social` | ✅ | ✅ | ✅ | ✅ | `social.gd` clans/stances; `new_graph()` = Phase 1 wire-shape |
| `capsules` | ✅ | ✅ | 🟡 | ✅ | `sim.gd` ≤100 km / 1-per-day; invites |
| `territory_control` | ✅ | 🟡 | ⬜ | 🟡 | clan stances feed threat; full territory meta = later |
| `economy` | ✅ | 🟡 | ⬜ | 🟡 | sinks exist (raids/convoy/upkeep); full player economy = Phase 1+ |

## Designed but deliberately NOT coded (RimWorld systems on ice)

Locked out of Phase 0 scope on purpose (`section:scope`): **mood/thoughts**, **traits**, deep
**skills as mechanics**, **beauty / room-quality buffs**, **multi-pawn management** (one hero only),
**additional human pawns** (MMO-only). Tracked here so «designed» never gets mistaken for «coming».

## The content tree (closing the infrastructure-vs-content gap)

The snapshot above flagged the core tension: the kernel is deep but the *content* was thin (6 resources,
7 buildings, 4 items in `data.gd`). That gap is now closed on the forward-engine side by a full,
validated **content catalogue** — the "повне дерево крафтів, ресурсів, будівель" tree:

- **`godot/content/catalog.json`** — 333 typed defs across 4 resource tiers, a 9-tier research DAG
  (neolithic → spacer/ship), 85 buildings and 58 recipes forming real multi-step production chains (ore →
  bar → alloy → advanced_component → ship parts), and 71 tools/weapons/apparel/prosthetics bound to the
  shipped `gear.gd` stats (apparel → `CompApparel`, prosthetics/archotech → `Hediff_Implant`, ammo &
  mortar shells → `combat.gd`, drugs/beer → `needs.gd`, power/geothermal → `power.gd`).
- **`godot/scripts/kernel/catalog.gd`** — typed loader (reuses `RecipeDef`/`ResearchDef`) + graph
  validators.
- Verified two ways: **`tests/catalog.test.js`** (Node, every push) and
  **`godot/tests/run_catalog_tests.gd`** (headless Godot, CI) — both assert the tree is an acyclic DAG
  with **full reachability from raw roots** (nothing stranded) and craft a real recipe through the live
  `ProductionSystem`. Full reference: [`docs/catalog.md`](catalog.md).

The catalogue is **additive** — `data.gd` (Phase-0 playable slice) is untouched, so the shipped game and
its suites are unchanged.

**Surfacing — first increment (done):** the catalogue now flows into the HUD through a proper view-layer
pipeline: `ui/catalog_view.gd` (a pure ViewModel — the `HudModel.snapshot()` analogue — that maps the
DefDatabase + play-state `{unlocked, stock}` to value-data slices: research progress, buildable/craftable
counts, next-available research) → `ui/catalog_panels.gd` `TechPanel` (build-once + value bind, styled
only via Widgets/Tokens) → registered in `ui/mechanics.gd`, so surfacing it never edited `hud_root.gd`
(R4). `HudModel.snapshot()` carries a `catalog` slice end to end. Headless-tested in `run_ui_tests.gd`
(value-data / R8, build-once / R2, prereq-gate status enums) with the R3/R7/R9/R10 tripwires extended to
the new files.

**Write-side — done (the tree is now operable, not just visible):** `catalog_sim.gd` is a scene-free,
deterministic **catalogue-backed play model** on the shipped kernel — it holds stock + research +
placed buildings and exposes the three verbs that USE the tree: RESEARCH a project
(`Production.ResearchState` gate + advance), BUILD a station (pays cost, attaches a `CompWorkbench`),
CRAFT a recipe (`Production.ProductionSystem` + `Bill` turn inputs into stock at the placed station).
`ui/catalog_verbs.gd` is the router (spec 0005 §2.10 / R9): it binds `cat_research` / `cat_build` /
`cat_craft` **intents** a panel emits to those commands — the panel never touches the sim. Proven end to
end in `run_catalog_tests.gd` (`_t_sim_playthrough`: research carpentry → build a workbench → craft
planks → tech up to smelting → build a smelter → smelt iron from raw ore, with the research gate holding)
and in `run_ui_tests.gd` (intent → router → sim; `TechPanel.act_next_research()` fires the full
panel → router → sim path).

**Interactive browser UI — done:** three LEFT-dock browsers (`BuildBrowser` / `CraftBrowser` /
`ResearchBrowser`, hotkeys B/C/R) render the actionable slices (`build_actions` / `craft_actions` /
`research_actions` — buildable/craftable/startable-now rows the ViewModel caps to a fixed pool) as
clickable `CatalogSlot` widgets; a slot press emits the `cat_build` / `cat_craft` / `cat_research` intent
(R9 — the panel never touches the sim). `newhud_main` now installs `catalog_verbs` on the router with a
process-shared `CatalogSim.shared()`, wires every panel's intent bubble to the router, and ticks the
shared model each frame — so the HUD reads and the router writes the SAME state: browse an action, click
it, watch the counts move. `HudModel.snapshot()` sources the catalog slice from that shared model, and
`parse_check.gd` now preloads `newhud_main` so the whole HUD wiring is compile-checked in CI. Proven in
`run_ui_tests.gd` `_t_action_browsers` (build-once/R2, slot click → intent → router → `catalog_sim`
places the building). Remaining: migrating the *live* data.gd sim onto `catalog_sim` (one world, not
two) — a large data-model migration, so it is decided on paper first in
[`specs/0007-catalogue-sim-unification.md`](../specs/0007-catalogue-sim-unification.md) (ADR + 5-stage,
each-stage-CI-green plan), per the AGENTS.md "big migration ⇒ ADR before code" rule.

**Update (2026-07-08, spec 0007):** the first walk of the tree now ships — a **research→unlock pipeline**
(`kernel/progression.gd`) drives it end to end. `ResearchState` (spec 0003) got the missing layer above it:
a queue, "what's researchable now", "what does this tech state unlock", a tech-level readout, and a
tech-path planner. It is **live** — a Phase-0 `research_bench` funds it (`session.tick_research`), the
`ResearchPanel` (LEFT dock) shows level + active-project bar + a clickable available-projects list + queue,
and unlocks toast through the feed. Verified in Node (`tests/progression.test.js`, 12) + headless Godot
(`run_progression_tests.gd`) against the same `catalog.json`. The **remaining** surfacing is the catalog
*build/craft menu gated by unlock* (bridging the slice's 6-resource table to the catalog's 78) — deferred
so this pass stays additive; see spec 0007 §5. That next step is now designed in **spec 0008** (ADR,
design-only) with its safe phase-1 companion already shipped: a pure **bill-of-materials planner** in
`catalog.gd` (`production_chain` / `producer_of` / `missing_for` / `raw_requirements`), Node + Godot
mirrored, that the gated build/craft menu and "to make X you need …" tooltips will consume.

**Update (2026-07-10, spec 0008 phase 1 — BOM guidance wired):** the planner now has its first UI
consumer. `ui/catalog_view.gd` folds it into the interactive browsers' actionable slices, so the
`CatalogSim`-backed Build/Craft/Research browsers show, beside every affordable row, the **near-miss**
rows too — unlocked-but-unaffordable buildings/recipes rendered dimmed (`enabled:false`) with a
`Потрібно ще: …` shortfall tip (`missing_for`); affordable rows carry an `Уся сировина: …` deep raw
budget (`raw_requirements`); crafts carry their production-chain tip (`production_chain`); and research
rows advertise `Відкриє: 🏛N ⚒N 🔧N` (tree scan). This also fixes the dead/empty CraftBrowser — once a
station is placed it lists that station's recipes with their input shortfall. Purely additive (the
`CatalogSim` forward model, not the live `data.gd` sim), so the shipped slice and its suites are
untouched; tips are computed only for the ≤12 rows that survive the cap (no per-frame graph walk for
hidden rows). Verified in `run_ui_tests.gd` `_t_bom_tips`. Spec 0008 phases 2–4 (the flagged
`use_catalog` migration of the **live** sim onto the catalogue) remain owner-gated per the ADR.

## How to read this

The right-hand columns tell the real story: several deep systems are **coded + tested in the kernel
but only partially surfaced in a playable slice**. With the content tree now authored, the highest-
leverage move is **surfacing** — bind the catalogue to the build/craft UI (via the `catalog.gd`
accessors) so the tree is playable, then wire gear/water/medicine into the sim so the depth becomes
*felt*, not just *tested*. See `GDD_BOOK/gdd.json` `section:risks` (risk #5).
