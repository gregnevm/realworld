# Mechanics catalogue — status tracker

> Snapshot: **2026-07-05**, last verified against code **2026-07-29**. Purpose: make the
> *infrastructure-vs-content* gap visible — the kernel is deep (~880 headless asserts across the
> Godot suites + 56 Node) but not every designed mechanic is yet wired into a playable slice. This
> is the at-a-glance «what is real vs only designed» view that complements `GDD_BOOK/gdd.json`
> (`section:mechanics_overview`) and the specs.
>
> Derived from specs 0001–0005 + `godot/scripts/kernel/`; treat integration/test columns as
> **best-effort — the owner should correct any cell**.

**Legend:** ✅ done · 🟡 partial · ⬜ not started · ⚠️ untracked/uncommitted at snapshot

| Mechanic (GDD id) | Designed | Coded | Integrated in playable slice | Tested (headless) | Notes |
|---|:---:|:---:|:---:|:---:|---|
| `map_generation` | ✅ | ✅ | ✅ | ✅ | `world_gen.gd`; OSM overlay + procedural fallback; coord-seed invariants |
| `climate` | ✅ | ✅ | ✅ | ✅ | `kernel/climate.gd` closed-form; seam to live weather API. **Temperature now BITES** (2026-07-29): felt °C drives hypothermia/heatstroke on the live pawn via `sim/hero_health.gd` — campfire/heater/walls are survival, not décor |
| `character_sim` | ✅ | ✅ | ✅ | ✅ | `sim.gd` single hero |
| `needs` | ✅ | ✅ | 🟡 | ✅ | hunger/rest floats live in `sim.gd`; their **consequences** are now kernel deprivation hediffs (`needs.gd` malnutrition/exhaustion, live 2026-07-29). The `Need` objects + water are still not consumed by the slice |
| `health` | ✅ | ✅ | ✅ | ✅ | **live** (2026-07-29): `sim/hero_health.gd` wires the 6-part tracker into the sim — located combat wounds, bleeding, bed-tend, scars, capacity-driven speed/work/melee, downed, per-cause death. Medicine/medbed/prosthetics remain kernel-only |
| `inventory_gear` | ✅ | ✅ | 🟡 | ✅ | `gear.gd` comfort hediffs + `insul` warmth on live armor are wired (2026-07-29); CompApparel/EquipModel/TendService still kernel-only |
| `gathering` | ✅ | ✅ | ✅ | ✅ | tool multipliers formalized (axe 1.6× / pick 1.9×) |
| `base_building` | ✅ | ✅ | ✅ | ✅ | building costs/HP in `data.gd` |
| `crafting_automation` | ✅ | ✅ | 🟡 | ✅ | `kernel/production.gd` bills (count/until); quality 0–6. Live catalogue craft (2026-07-29) is instant `sim.craft_catalog`; work-time bills remain kernel/sandbox |
| `content_tree` | ✅ | ✅ | ✅ | ✅ | 335 defs, reachability-validated. **Live behind `use_catalog`** (2026-07-29, spec 0008 ph.3–4): the curated tier — 38 res / 73 builds / 27 recipes, neolithic→steel — builds, crafts and mines in the real game; the rest browsable until its map source ships |
| `progression_research` | ✅ | ✅ | ✅ | ✅ | **spec 0007** — `kernel/progression.gd` queueable research pipeline over the tree; live from research benches (`session.tick_research`), surfaced in `ResearchPanel` (LEFT dock); planner (`research_path`/`steps_to_unlock`). Node + Godot mirrored tests |
| `raids_pvp` | ✅ | ✅ | ✅ | ✅ | **Paced by Balance since 2026-07-29** (`sim/director.gd`): MTB rolls arm the warning→wave cycle and the wave is sized by threat points (wealth + days + clan `raid_pressure`) — real escalation. Patrols stay the ambient `sim/threats.gd` channel |
| `balance_director` | ✅ | ✅ | ✅ | ✅ | **live** (2026-07-29): `sim/director.gd` runs `Balance.tick()` on its own seeded stream — raids, disease (→ the health tracker), cold snaps (→ `apply_temp_anomaly`), cargo drops. `decide()` stays the AI seam; fauna/quest incidents wait for their substrate |
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

**Update (2026-07-29, mechanics integration):** the two biggest «coded-but-not-felt» kernel systems
are now live in the playable slice, through a new sim domain module `sim/hero_health.gd` (the
threats/environment decomposition pattern):

- **Located health replaces the single hp float.** The hero owns a `kernel/health.gd` tracker: enemy
  blows land as wounds on real body parts (armor still mitigates first), wounds bleed/fester/heal,
  sleeping in a **bed** tends them (its medical role), severe healed wounds scar (`gear.gd`), and
  capacities feed back — wounded legs walk slower, wounded arms gather/hit slower, collapse (`downed`)
  drops the pawn where they stand. Death is per-cause (blood loss / destroyed vital / starvation /
  freezing / heatstroke) and named in the feed. `player.hp` survives as a derived readout. The tracker
  saves (`serialize_region.health`), travels in the capsule pawn, and is covered by `world_hash`
  (rejoin lands byte-identical); legacy saves migrate their hp float into a tended torso wound.
- **Temperature has teeth.** Felt °C (tile temp — indoor buffering + campfire/heater emitters — plus
  `insul` warmth on worn gear) drives the kernel comfort hediffs (`gear.gd`) on the live pawn, and
  empty needs drive the new deprivation hediffs (`needs.gd`: malnutrition kills at 1.0, exhaustion
  collapses below the lethal line). A Kyiv day-1 spawn is deep winter and says so (`spawn hint`) —
  fire-first is now a real opening move, and an enclosed heated room is the survival answer.
- Kernel fix the integration exposed: condition hediffs' `gone()` used a 0.02 epsilon that swept a
  just-born hediff at per-frame `dday` (~0.003/tick growth) — the comfort/deprivation authorities
  only ever ran at coarse test steps. `gone()` is now exact-zero, with fine-dday regression tests.
- HUD: the vitals slice adds a blood bar, felt-°C + comfort enum, condition inspect lines and the
  downed flag (`VitalsPanel` renders them; R8/R11 hold). New/updated coverage in `run_tests.gd`
  (`_t_hero_health`, `_t_cold_exposure`, `_t_deprivation_live`, `_t_health_persistence`) and the
  kernel suite; all suites + determinism/rejoin/net gates green.

Still kernel-only after this pass (deliberately): medicine + medbed `TendService`, CompApparel/
EquipModel armor stacking, thirst, prosthetic surgery as a live verb, and Balance-driven incidents.

**Update (2026-07-29, spec 0008 phases 3–4 — the catalogue becomes playable):** on the owner's §5
go-ahead, the 335-def tree now BUILDS and CRAFTS in the live game behind `use_catalog`:

- **Def seam `sim.building_def`** — data.gd's 13 tuned defs win their ids; catalogue-only buildings
  resolve through the `catalog_defs.gd` adapter into the same dict shape, so every tick path
  (blocks/enclosure/heat/light/traps/turrets/capacity/hp/render) serves both vocabularies.
- **Curated live tier, derived not hand-listed**: categories structure/production/storage/defense,
  power-free (no live power net — powered turrets would run for free), defense only with a live brain
  (generic turret loop by `range`/`cooldown`; traps by `trap_dps`). The reachability closure from the
  live raws pins the tier at **38 resources / 73 buildings / 27 recipes** (neolithic→steel/components),
  mirrored in Node (`catalog.test.js`) and Godot (`_t_catalog_live`).
- **Phase 4 sourcing**: under the flag, rocks yield ore/coal/clay/sand interleaved with stone, trees
  fiber, bushes herbs — a pure function of (cell, amount), zero rng consumed, worldgen goldens intact.
- **UI**: the B/C/N browsers flip their badge «демо»→«живе» when the slice state IS the live sim;
  build rows arm the ordinary `select_build` ghost, craft rows run `sim.craft_catalog`, the
  StockPanel lists catalogue-only stock. Sandbox mode (flag OFF, shipped default) is untouched.
- Remaining to full Option A: map sources for the hunting/exotic-mining raws, work-time crafting,
  and the deliberate default-ON flip for new games (spec 0008 §5.2).

**Update (2026-07-29, the follow-through pass):** the two debts this PR left itself are paid.
**Crop selection** (`set_crop` verb — clicking your own grow zone cycles мішана→зерно→їжа→волокно→
трави→hops; `b.crop` persists and overrides the mixed rotation) opens the brewery chain — the live
tier is now pinned at **44 resources** (hops/wort/beer), mirrored Node+Godot. **Power nets are
SPATIAL**: participants group by 4-adjacency and `power_conduit` (now buildable) extends a grid
across distance — a generator powers what it touches or what a cable line reaches; each grid solves
its own brownout, the HUD reads the aggregate.

**Update (2026-07-29, the Balance director goes live):** the audit's one dishonest cell — «tactic
escalation via Balance» while raids ran on a flat timer — is now true in code, not just corrected in
prose. `sim/director.gd` runs `kernel/balance.gd`'s `tick()` every sim tick on its OWN seeded stream
(cursor in the runtime record — twins and rejoiners replay the same storyteller): the raid incident
arms the shipped warning→wave cycle with a wave SIZED by threat points (wealth + days survived +
clan pressure through `assess()` — the flat `78+rand·46` reroll is gone, the cycle idles until the
director arms it, and a fresh base gets a real grace period); disease lands on the live health
tracker (the bed-tend immunity race); cold snaps ride the spec-E6 `apply_temp_anomaly` seam; cargo
drops pay generosity-scaled scrap into the stock. Incidents without a live substrate
(infestation/manhunter → fauna, quest → quests) still roll but their payloads are DROPPED, not
faked. `decide()` remains the AI-policy seam; knobs stay at defaults. The HUD threat readout and
the live pacing now read the same `world_of` numbers (one sim-side builder). `_t_director_live`
covers twin hashes, every live incident channel, the armed raid cycle and live escalation.

**Update (2026-07-29, farming goes live — the first renewable source):** `sim/farming.gd` bridges
grow zones onto the last big unconsumed kernel comp — `things.gd CompGrower` (temperature- and
light-gated growth). Each zone ticks with ITS OWN cell's felt world (`temp_at`/`light_at`): a
walled, heated, lit room is literally a greenhouse, a Kyiv winter starves an outdoor field, night
puts crops to sleep — the same climate that bites the pawn now feeds or starves the base.
Hydroponics (×2.4) gates on `device_active`: the power net literally feeds food. v1 is a MIXED plot
(deterministic per-cell harvest rotation, the gather_yield pattern; per-zone crop selection is a
later verb). `b.growth`/`b.harvests` persist like fuel/charge. Cooked meal thing-outputs (bread &
co) are now EDIBLE stock — auto-eat prefers the most nourishing (`MEAL_NUTRITION`), so the grain →
flour → bread chain genuinely feeds the pawn. The live tier grows 38 → **41 resources**, pinned
mirror-wise in Node and Godot. Covered by `_t_farming_live`.

**Update (2026-07-29, Batch 8c — the power net goes live):** `sim/power.gd` bridges the placed
building dicts onto the kernel power organ (`kernel/power.gd`: sources/traders/batteries +
PowerNetSystem with priority brownout shedding). The kernel comps own the physics; the building
dicts stay the persistent truth (`b.fuel`/`b.charge` mirror back every tick → saves, `world_hash`,
rejoin). Solar rides the real daylight curve, wind the seeded weather stream, fuel generators
auto-refuel from the open stock (1 unit = 1 fuel). `sim.device_active` — the seam built for exactly
this — now gates every power-TRADER def: browned-out turrets hold fire, unpowered stations refuse
crafts with an honest `no_power`. The powered half of the catalogue (generators, batteries, solar,
electric stations, auto-turrets, fridge) joins the live tier; the `power_conduit` stays out until
nets are spatial. One region = one implicit net. HUD: a `power` slice + `PowerPanel` (hotkey E).
Covered by `_t_power_live` (shedding order, battery buffering, day/night solar, refuel economy,
fuel/charge persistence, twin hashes); the shipped flag-OFF slice pays zero cost and stays
byte-identical.

## How to read this

The right-hand columns tell the real story: several deep systems are **coded + tested in the kernel
but only partially surfaced in a playable slice**. With the content tree now authored, the highest-
leverage move is **surfacing** — bind the catalogue to the build/craft UI (via the `catalog.gd`
accessors) so the tree is playable, then wire gear/water/medicine into the sim so the depth becomes
*felt*, not just *tested*. See `GDD_BOOK/gdd.json` `section:risks` (risk #5).
