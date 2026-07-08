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
its suites are unchanged. Remaining work is *surfacing*: wiring the catalogue into the HUD build/craft
menus so this depth becomes *felt in play*, not just *validated*.

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
`catalog.gd` (`production_chain` / `producer_of` / `missing_for`), Node + Godot mirrored, that the gated
build/craft menu and "to make X you need …" tooltips will consume.

## How to read this

The right-hand columns tell the real story: several deep systems are **coded + tested in the kernel
but only partially surfaced in a playable slice**. With the content tree now authored, the highest-
leverage move is **surfacing** — bind the catalogue to the build/craft UI (via the `catalog.gd`
accessors) so the tree is playable, then wire gear/water/medicine into the sim so the depth becomes
*felt*, not just *tested*. See `GDD_BOOK/gdd.json` `section:risks` (risk #5).
