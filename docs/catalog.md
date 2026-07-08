# Content catalogue — the deep craft / resource / building / research tree

> Source of truth: [`godot/content/catalog.json`](../godot/content/catalog.json).
> Loader: [`godot/scripts/kernel/catalog.gd`](../godot/scripts/kernel/catalog.gd).
> Validated by [`tests/catalog.test.js`](../tests/catalog.test.js) (Node, runs on every push) **and**
> [`godot/tests/run_catalog_tests.gd`](../godot/tests/run_catalog_tests.gd) (headless Godot, CI).

This is the Phase-1 content tree the kernel's `Defs.load_pack` seam was built for. It is **pure data**:
159 typed defs (35 resources · 22 research · 48 buildings · 25 recipes · 29 items) expressed in the
shipped `Def / RecipeDef / ResearchDef` grammar, so **adding content never touches the tick loop**.
It composes on the existing mechanics kernel (production/power/environment/gear/combat) rather than
replacing it, and it does **not** touch `data.gd` — the Phase-0 playable slice keeps its own 6-resource
table; this catalogue is the forward-engine superset.

Design canon: **RimWorld** for the survival/needs/quality flavour, **Factorio** for the multi-step
automation chains (ore → bar → intermediate → advanced) where RimWorld is thin on intermediates.

## The load-bearing invariant: reachability

The tree is only "complete" if nothing is stranded. Both validators compute the same closure from the
**raw roots** (resources you obtain directly from the map — mined / chopped / gathered / hunted / farmed)
and assert that **every** resource is producible, **every** research reachable, **every** building
buildable, and **every** recipe/item craftable. A recipe becomes reachable when its station is buildable,
its research is unlocked, and all its inputs are already obtainable; its output then joins the obtainable
set. This is a fixpoint over the whole graph — the guarantee that the player can actually climb from a
bare map to end-game industry without a gap. The tech tree is additionally checked to be an acyclic DAG
(so research can always finish) and every cross-reference (prereq, gate, station, cost) is checked to
resolve.

## Resource tiers (34)

| Tier | Resources |
|---|---|
| **0 · raw** (13) | wood, stone, scrap, clay, sand, coal, iron_ore, copper_ore, raw_food, meat, hide, plant_fiber, herbal |
| **1 · refined** (9) | planks, charcoal, brick, stone_block, glass, iron_bar, copper_bar, cloth, leather |
| **2 · intermediate** (9) | steel, components, copper_wire, gear_wheel, nails, chemfuel, gunpowder, ammo, herbal_medicine |
| **3 · advanced** (4) | circuit, machine_frame, reinforced_plate, medicine |

Every tier-1+ resource is produced by a recipe and consumed by a later one (or is a legitimate gameplay
sink — `medicine`, `reinforced_plate`); the validator forbids dead-end intermediates.

### Example production chains (Factorio-style depth)

```
copper_ore ──smelt──▶ copper_bar ──machining──▶ copper_wire ─┐
sand ──kiln──▶ glass ────────────────────────────────────────┼─▶ circuit ─▶ solar_panel / auto_turret / assembler
iron_ore + copper_bar ──machining──▶ components ──────────────┘

iron_ore + coal ──smelt──▶ iron_bar + charcoal ──smelt──▶ steel ──▶ machine_frame / reinforced_plate / flak gear
wood ──kiln──▶ charcoal (reductant for glass & steel)
herbal + cloth ──drug_lab──▶ herbal_medicine + components + chemfuel ──▶ medicine
```

## Research tree (22, DAG over 8 tiers)

```
T1  carpentry   fire_mastery   masonry   agriculture   hunting
T2  smelting(fire)  cooking(fire)  textiles(agri)  leatherworking(hunt)
T3  smithing(smelt)  machining(smelt)
T4  steelmaking(smith+machining)  chemistry(smelt)  medicine_research(cook+agri)
T5  electricity(machining)  firearms(machining+chemistry)
T6  electronics(electricity+chemistry)  fortification(masonry+steelmaking)
T7  automation(electronics+steelmaking)  defense_systems(firearms+electronics)  bionics(electronics+medicine_research)
T8  industrialization(automation)
```

Research gates buildings, recipes and items. Each project costs research-points (game-days) and is
consumed by `Production.ResearchState` exactly as the shipped kernel already does.

## Buildings (48, by category)

- **structure** (9): wall, door, floor, stone_wall/floor, brick_wall, steel_wall, sandbags, embrasure
- **production** (16): workbench, campfire, fueled_stove, kiln, stonecutter_table, smelter, smithy,
  machining_table, loom, tailoring_bench, tannery, chemistry_bench, drug_lab, electronics_bench,
  fabrication_bench, assembler (auto-crafts, powered)
- **power** (6): wood_generator (fuel), watermill/windmill (wind), solar_panel (solar), battery,
  power_conduit — all bound to `power.gd`'s `CompPowerSource / CompBattery / CompPowerTrader`
- **storage** (4): storage, shelf, warehouse, fridge (powered cold store)
- **comfort** (7): bedroll, bed, well (water), lamp, heater, cooler, medbed (`gear.gd` `CompMedbed`)
- **farming** (2): grow_zone, hydroponics (powered, faster growth)
- **defense** (4): turret, auto_turret (powered), spike_trap (`CompTrap`), mortar (`CompMortar`)

Buildings marked `station:true` (or `autocraft:true`) host recipe bills; power buildings carry a
`power` block; heaters/coolers/lamps carry emitter hints the Batch-1/Batch-2 seam already understands.

## Items (29)

- **tools** (6): stone → iron → steel axe & pick (`gather_mult` 1.4 → 2.6)
- **weapons** (8): wooden club/spear, bow, iron sword/mace, steel sword, revolver, bolt_rifle
  (melee `dmg_bonus` + `dmg_type`; ranged carry `ranged`/`range`) — firearms/turrets spend the `ammo`
  resource (`make_ammo`: gunpowder + steel) at runtime
- **apparel** (10): tribal/leather/parka/duster torso & legs, caps & helmets — each with
  `insulation_c` and per-damage-type `armor{sharp,blunt,heat}` that bind straight onto `gear.gd`'s
  `CompApparel` / `EquipModel`
- **prosthetics** (5): peg_leg → prosthetic_arm → bionic arm/leg/eye, each with a `restores` body part
  and a `cap_factor` (0.6 peg → 1.15 bionic) that binds onto `gear.gd`'s `Hediff_Implant` /
  `install_prosthetic` surgery — bionics restore a capacity *above* baseline

## How it plugs into the kernel

`Catalog.build_db()` returns a `Defs.DefDatabase` of typed defs. Recipes/research are literally
`Production.RecipeDef` / `Production.ResearchDef`, so a workbench `Thing` carrying a `CompWorkbench`
runs catalogue bills through the unchanged `ProductionSystem`, honouring the research gate — this is
exercised end-to-end in `run_catalog_tests.gd` (`_t_production_integration`, `_t_research_gate`). The
JSON `"research"` gate key is normalised to the `"requires_research"` key `RecipeDef` reads, so no kernel
edit is needed.

## Extending

Add a record to the relevant array in `catalog.json`. `npm test` (or the Godot suite) will immediately
tell you if it strands content, references a missing id, introduces a tech cycle, or leaves an
intermediate feeding nothing. Keep amounts as integers (the Godot loader int-casts JSON floats).
