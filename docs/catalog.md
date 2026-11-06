# Content catalogue — the deep craft / resource / building / research tree

> Source of truth: [`godot/content/catalog.json`](../godot/content/catalog.json).
> Loader: [`godot/scripts/kernel/catalog.gd`](../godot/scripts/kernel/catalog.gd).
> Validated by [`tests/catalog.test.js`](../tests/catalog.test.js) (Node, runs on every push) **and**
> [`godot/tests/run_catalog_tests.gd`](../godot/tests/run_catalog_tests.gd) (headless Godot, CI).

This is the Phase-1 content tree the kernel's `Defs.load_pack` seam was built for. It is **pure data**:
335 typed defs (78 resources · 41 research · 87 buildings · 58 recipes · 71 items) expressed in the
shipped `Def / RecipeDef / ResearchDef` grammar, so **adding content never touches the tick loop**.
The 41-project research DAG is now **walked** end-to-end by the research→unlock pipeline
(`kernel/progression.gd`, **spec 0007**) — two research benches (`research_bench`,
`hi_tech_research_bench`) fund it in play. A pure **bill-of-materials planner** (`catalog.gd`:
`production_chain(res)` — the ordered recipe steps from raws; `producer_of(res)`; `missing_for(cost, stock)`
— the affordability shortfall; `raw_requirements(cost)` — the full raw-resource budget rolled down through
the chain) turns the tree into the production PIPELINE a gated build/craft menu will consume (**spec 0008**
phase 1).
It composes on the existing mechanics kernel (production/power/environment/gear/combat) rather than
replacing it, and it does **not** touch `data.gd` — the Phase-0 playable slice keeps its own 6-resource
table; this catalogue is the forward-engine superset.

Besides the five def sections the file carries one non-def top-level key, **`capsule_levels`** (spec 0010 — the Основна
капсула level table: `levels[0..5] = {level, cost, radius, core_hp, buffs}` plus a `raid` block). It is data for the
`sim/capsule.gd` module, not content defs: it does not enter the id-uniqueness / reachability sweeps, its price ids must be
reachable ones that `data_bridge` maps 1:1. Every number in it is `status:"proposed"` (economy bot
`godot/tests/run_capsule_balance.gd`) until the owner approves it at merge — **except** `raid.immunity_ms` and
`raid.take_percent`, which are owner decisions (OD-24/58, listed in `raid.decided`), not agent proposals.

Design canon: **RimWorld** for the survival/needs/quality/medical flavour, **Factorio** for the
multi-step automation chains (ore → bar → intermediate → advanced) where RimWorld is thin on
intermediates. The arc runs from a bare neolithic start to a spacer endgame (a launchable ship).

## The load-bearing invariant: reachability

The tree is only "complete" if nothing is stranded. Both validators compute the same closure from the
**raw roots** (resources you obtain directly from the map — mined / chopped / gathered / hunted / farmed)
and assert that **every** resource is producible, **every** research reachable, **every** building
buildable, and **every** recipe/item craftable. A recipe becomes reachable when its station is buildable,
its research is unlocked, and all its inputs are already obtainable; its output then joins the obtainable
set. This is a fixpoint over the whole graph — the guarantee that the player can climb from a bare map to
end-game industry without a gap. The tech tree is additionally checked to be an acyclic DAG (so research
can always finish) and every cross-reference (prereq, gate, station, cost) is checked to resolve. Bootstrap
cycles are forbidden by construction (e.g. `advanced_component` is crafted at the `electronics_bench`, not
at the `advanced_fabrication_bench` whose own cost needs advanced components).

## Resource tiers (78)

| Tier | Count | Examples |
|---|---|---|
| **0 · raw** | 26 | wood, stone, scrap, clay, sand, coal, iron/copper/tin/silver/gold/uranium ore, jade, marble, granite, raw_food, meat, hide, plant_fiber, herbal, grain, hops, psychoid_leaves, smokeleaf_leaves, wool, devilstrand_bud |
| **1 · refined** | 23 | planks, charcoal, brick, stone/marble/granite block, glass, iron/copper/tin bar, silver, gold, uranium, cloth, leather, devilstrand, synthread, flour, wort, beer, kibble … |
| **2 · intermediate** | 19 | steel, bronze, components, copper_wire, gear_wheel, nails, chemfuel, gunpowder, ammo, neutroamine, hyperweave, herbal_medicine, drugs (flake/yayo/wake_up/penoxycyline), shells (HE/incendiary/EMP) |
| **3 · advanced** | 10 | circuit, plasteel, advanced_component, machine_frame, reinforced_plate, medicine, glitterworld_medicine, go_juice, luciferium, antigrain_shell |

The "no dead-end intermediate" guard forbids a refined/intermediate resource that feeds nothing; the only
allowed sinks are terminal products consumed by **gameplay at runtime** — drugs (ingested), shells & ammo
(fired), beer/kibble (consumed), end-game armour/prosthetic stock.

### Example production chains (Factorio-style depth)

```
copper_ore ─smelt▶ copper_bar ─machining▶ copper_wire ─┐
sand ─kiln▶ glass ──────────────────────────────────────┼▶ circuit ─▶ solar / auto_turret / assembler
iron_ore + copper_bar ─machining▶ components ───────────┘

uranium_ore ─smelt▶ uranium ─┐
iron_ore + coal ─smelt▶ iron_bar + charcoal ─smelt▶ steel ─┼─electric_smelter▶ plasteel ─┐
                                                            │  circuit + silver ───────────┼▶ advanced_component
                                                            └──────────────────────────────┘        │
plasteel + advanced_component + glitterworld_medicine ─advanced_fabrication▶ archotech limbs         │
plasteel + advanced_component + uranium + gold ─ship_construction▶ ship reactor / engine / core ◀────┘

grain ─mill▶ flour ─stove▶ bread ; grain + hops ─brewery▶ wort ─▶ beer
psychoid_leaves ─drug_lab▶ flake / yayo ─▶ go_juice / luciferium ; herbal + chemfuel ─▶ neutroamine ─▶ medicine
```

## Research tree (41 nodes, DAG over 9 tiers)

```
T1  carpentry  fire_mastery  masonry  agriculture  hunting
T2  smelting  cooking  textiles  leatherworking
T3  smithing  machining  metallurgy(smelt)  brewing(cook)  husbandry(agri+hunt)  stonecarving(masonry)
T4  steelmaking  chemistry  medicine_research  advanced_chemistry(chem)  advanced_metallurgy(metallurgy+steel)  advanced_textiles(textiles)
T5  electricity  firearms  gunsmithing(firearms)  geothermal_power(electricity)  drug_production(adv_chem+medicine)
T6  electronics  fortification
T7  automation  defense_systems  bionics  microelectronics(electronics)  plasteel_working(adv_metallurgy+electronics)
T8  industrialization  advanced_fabrication  spacer_tech  advanced_prosthetics  spacer_medicine  powered_armor  advanced_weapons
T9  ship_construction(spacer_tech + advanced_fabrication)
```

Research gates buildings, recipes and items; each project costs research-points (game-days) consumed by
`Production.ResearchState`, the shipped kernel's mechanism.

## Buildings (85, by category)

- **structure** (10): wood/stone/brick/steel/granite walls, doors, floors, sandbags, embrasure
- **production** (20): workbench, campfire, fueled_stove, kiln, stonecutter, smelter, **electric_smelter**,
  smithy, machining_table, loom, tailoring/tannery, chemistry_bench, drug_lab, **brewery**, **millstone**,
  electronics_bench, fabrication_bench, **advanced_fabrication_bench**, assembler (auto-crafts)
- **power** (9): wood/chemfuel/geothermal generators, watermill, windmill, solar, battery, large_battery,
  power_conduit — all bound to `power.gd`'s `CompPowerSource / CompBattery / CompPowerTrader`
- **storage** (4): storage, shelf, warehouse, fridge
- **comfort** (19): bedrolls & beds (incl. royal & hospital), well, lamps/heater/cooler, chairs/stools/
  tables/dressers, torches/braziers, medbed, grave, sarcophagus
- **farming** (2): grow_zone, hydroponics
- **defense** (9): turret, auto/autocannon/uranium-slug/sniper turrets, spike/deadfall/IED traps, mortar
- **art** (3): small / large / grand sculptures (marble → granite+silver → jade+gold+plasteel)
- **utility** (3): comms console, orbital trade beacon, biosculpter pod
- **ship** (6): structural beam, reactor, engine, computer core, cryptosleep casket, sensor cluster

## Items (71)

- **tools** (6): stone → iron → steel axe & pick (`gather_mult` 1.4 → 2.6)
- **weapons** (26): clubs/spears/bow → knife/gladius/sword/mace/warhammer → plasteel_sword/monosword;
  ranged bow → revolver/autopistol/shotgun/assault/sniper/LMG/minigun → charge_rifle; grenades (frag/EMP/
  molotov). Melee carry `dmg_bonus`+`dmg_type`; ranged carry `ranged`/`range`; guns/turrets spend `ammo`
  and mortars spend HE/incendiary/EMP/antigrain shells (`combat.gd`)
- **apparel** (23): tribal/leather/parka/duster → flak set → plate → marine/power armour; devilstrand &
  hyperweave layers; hats/helmets; utility belts (shield/smokepop/jump-pack). Each carries `insulation_c`
  and per-damage-type `armor{sharp,blunt,heat}` that bind onto `gear.gd`'s `CompApparel` / `EquipModel`
- **prosthetics** (16): peg_leg → prosthetic arm → power_claw/drill_arm → bionic ear/spine/stomach/heart →
  **archotech** eye/arm/leg; joywire/painstopper. Each has a `restores` body part and a `cap_factor`
  (0.6 peg → 1.3 archotech) binding onto `gear.gd`'s `Hediff_Implant` / `install_prosthetic` surgery

## How it plugs into the kernel

`Catalog.build_db()` returns a `Defs.DefDatabase` of typed defs. Recipes/research are literally
`Production.RecipeDef` / `Production.ResearchDef`, so a workbench `Thing` carrying a `CompWorkbench`
runs catalogue bills through the unchanged `ProductionSystem`, honouring the research gate — exercised
end-to-end in `run_catalog_tests.gd`. The JSON `"research"` gate key is normalised to the
`"requires_research"` key `RecipeDef` reads, so no kernel edit is needed.

## Extending

Add a record to the relevant array in `catalog.json`. `npm test` (or the Godot suite) will immediately
tell you if it strands content, references a missing id, introduces a tech cycle, or leaves an
intermediate feeding nothing. Keep amounts as integers (the Godot loader int-casts JSON floats). A new
terminal consumable (a drug, a shell) that is spent at runtime rather than by a recipe goes in the test's
`allowedSinks` set with a one-word note on how gameplay consumes it.
