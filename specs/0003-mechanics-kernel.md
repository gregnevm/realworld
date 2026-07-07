# Spec 0003 — RimWorld-style mechanics kernel (abstractions & interfaces)

Status: **kernel implemented + verified** (239 kernel tests green; existing 119 unit still green) ·
Engine: Godot 4.7 port (`godot/scripts/kernel/`, scene-free, headless-testable) · Reference: JS web slice frozen.

Goal: **develop the full mechanics concept as abstractions & interfaces, analogous to RimWorld** — not a
feature dump, but the small set of composable contracts every mechanic plugs into. The kernel is *additive*:
it is proven by its own test suite and does not touch `sim.gd` yet; §8 is the migration path.

## 0. Scope & exclusions (from the goal)

Locked design constraints for this game (they shape every interface below):

- **One hero = one pawn.** The player drives exactly one deeply-simulated pawn. *Additional human pawns are
  only ever other live players* (MMO). Robots, animals and turrets exist but as **Agents**, never colonists.
- **Raiders are robots** (mechanoids): no needs, no morale — a faction, a target, an HP pool.
- **Excluded now:** managing multiple pawns; pawn **mood & thoughts**; **traits & skills** (deferred to a deep
  late-game pass — the Stat pipeline is built so they slot in without rework); **Beauty / room-quality** buffs.

Everything the kernel ships respects these: `Need` is hero-only, `HealthTracker` is hero-first, `Agent` covers
every non-hero actor, and there is **no** mood/beauty/skill need or stat in the shipped set.

## 1. Design thesis — five contracts, everything else is content

RimWorld's real lesson is not its feature list; it is that ~5 abstractions absorb hundreds of mechanics. The
kernel reproduces that spine (`godot/scripts/kernel/`):

| Kernel module | RimWorld analogue | What it is | Status |
|---|---|---|---|
| `defs.gd` — `Def` / `DefDatabase` | Def / DefDatabase / DefOf | Data-driven definitions + typed registry; behaviour lives in workers, not on the def | ✅ tested |
| `things.gd` — `Thing` / `ThingComp` | ThingWithComps / ThingComp | Located object + a list of orthogonal behaviours (comps) that tick themselves | ✅ tested |
| `stats.gd` — `StatWorker` / `StatPart` | StatDef / StatWorker / StatPart | A value = base folded through modifier parts (quality, health, research, weather) | ✅ tested |
| `systems.gd` — `SimSystem` / `SystemRegistry` | MapComponent / TickManager | Priority-ordered tick spine; a mechanic = a registered system | ✅ tested |
| `balance.gd` — **`Balance`** (one class) | Storyteller + WealthWatcher + IncidentWorker, **merged** | The single difficulty/economy/pacing authority; incidents are data+methods it owns; **`decide()` is the AI-control seam** | ✅ tested |

Plus three domain layers built on the spine:

| Module | RimWorld analogue | Purpose | Status |
|---|---|---|---|
| `climate.gd` — `ClimateProvider` | biome + WeatherManager + GenDate | Temperature/season/daylight/weather from **real lat/lon** + clock; **SEAM** to a live weather API | ✅ tested |
| `health.gd` — `HealthTracker` / `Hediff` / `BodyPart` | Pawn_HealthTracker / Hediff / PawnCapacityDef | Located injuries & disease → capacities → stats; medicine tends | ✅ tested |
| `needs.gd` / `agents.gd` — `Need` / `Agent` | Need / Pawn AI (JobGiver·WorkGiver·Job) | Hero drives; non-hero actor AI (raiders·bots·animals) | ✅ tested |

**Adding a mechanic never edits the tick loop.** You register a `SimSystem`, attach a `ThingComp`, add a
`StatPart`, or add an incident to `Balance`. That is the whole extension surface.

> **Detailed mechanics catalogue + full UX/UI implementation:** see **[spec 0004](0004-mechanics-catalogue-and-ux.md)** —
> every mechanic with a long-form description and its concrete HUD/interaction design. This spec (0003)
> stays the *architecture*; 0004 is the *content + interface*.

## 2. The composition core — `Thing` + `ThingComp`

The single most reused abstraction. A `Thing` is dumb located state (`def`, `pos`, `hp`, `stack`, `flags`);
each `ThingComp` is one behaviour that ticks from a shared `ctx` (`dt`, `dday`, `temp_c`, `light`, `rng`, …).
Three reference comps ship, proving one interface spans unrelated mechanics:

- `CompRottable` — food/organics spoil; **halts at ≤0 °C (this is refrigeration)**; destroys the stack at 100 %.
- `CompGrower` — crops advance only inside a temperature band with enough light; dormant at night / off-season.
- `CompQuality` — rolls a quality tier `0..6` once at creation from the maker's competence; feeds Stats.

A wall, a plant, a meal, a corpse, a battery, a mortar are all `Thing` + comps. `ctx` is produced once per tick
by the systems (climate → `temp_c`/`light`, health → `capacities`).

## 3. The stat pipeline — `StatWorker` + `StatPart`

`value = base` folded through ordered `StatPart`s. Shipped parts: `StatPart_Quality` (×item quality),
`StatPart_Capacity` (×a health capacity), `StatPart_Factor` (×a named ctx factor: research, weather, comfort).
`explain(ctx)` yields a tooltip breakdown. This is where the **deferred skills/traits** attach later — each
becomes a `StatPart` with zero changes to callers. It replaces the ad-hoc `gather_mult`/`dmg_bonus` in `sim.gd`.

Example proven in tests: `MeleeDamage = 12 × quality 1.5 × manipulation 1.0 = 18`; a half-crippled arm
(`manipulation 0.5`) drops the same stat to 9.

## 4. Located health — `HealthTracker` / `Hediff` / `BodyPart`

Replaces the hero's single `hp` float. Body parts (torso/head/legs/arms) each power capacities
(`moving`, `manipulation`, `consciousness`, `blood_pumping`). Hediffs sit on parts:

- `Hediff_Injury` — **bleeds** (drains `blood`), **heals** over days, and **festers into infection** if
  untended; reduces its part's capacities by damage fraction. `tend_all()` (medicine) stops the bleed and
  clears infection.
- `Hediff_Disease` — an **immunity-vs-severity race**: tending reaches full immunity sooner, so less severity
  accrues; lose the race and consciousness collapses (downed).

Capacities are the bridge to §3: a wounded leg → `moving < 1` → slower `MoveSpeed`; blood loss further weakens
consciousness & movement. This is the substrate late-game **surgery / prosthetics / implants** extend (add a
`Hediff` subclass and a `RecipeDef`, nothing else).

## 5. Climate from real geography — the signature hook

`ClimateProvider` answers `temperature_c / season / daylight / weather` for any coordinate + clock time.
`ClimateModel_Deterministic` is closed-form: annual temperature falls with |latitude|, a seasonal sinusoid
(amplitude grows toward the poles), a **southern-hemisphere flip**, a diurnal swing, and latitude-scaled day
length. Verified: equator warmer than pole; Kyiv summer > winter; lat −33 is summer in January; midnight darker
than noon; fully deterministic.

**SEAM (mirrors `social.gd`):** swap in a `ClimateProvider` backed by a live weather API (Open-Meteo by
lat/lon) behind the same interface — Temperature, Weather, Growth and Solar systems are unaffected. This is the
mechanic RimWorld cannot have: **biomes and weather are the player's real planet.**

## 6. The `Balance` director — one class, future AI brain

The classic RimWorld design scatters game-feel across Storyteller + StorytellerComp_* + WealthWatcher +
IncidentWorker + difficulty curves. The kernel **collapses all of it into one class, `Balance`** — the single
authority that reads world state and decides what pressure to apply. It owns:

- **Economy/threat math (static):** `wealth(world)` and `threat_points(world, day, pressure)` where
  `wealth = buildings + stock + gear` and points rise with wealth, days survived and hostile pressure.
- **Knobs (the tuning surface):** `difficulty` (global threat ×), `generosity` (loot/gift ×), and
  `category_weight` (per-category cadence). These are exactly the levers an AI director would move.
- **`assess(world, ctx) → snapshot`** — an immutable read `{wealth, threat, phase, raid_hint, …}` consumed by
  BOTH the Balance HUD and the AI.
- **`decide(state, world, ctx) → policy` — THE AI SEAM.** Today it is a transparent rule set (suppress big
  threats while one is active; pass the knobs through). Tomorrow a subclass or an external learned/LLM policy
  overrides *only this method* to steer the session. The sim never calls the brain directly — only `assess()`
  and `tick()`.
- **`tick(world, ctx, rng) → incidents`** — rolls the incident roster (data + method-Callables owned by
  `Balance`) under the policy, at most one **big threat** at a time (adaptive pacing).

Incidents ship: `raid`, `infestation`, `disease`, `manhunter`, `cold_snap`, `cargo`, `quest`. Raids scale in
size *and tactic* with points — `assault → droppod (day % 4) → siege → sappers` — where **droppod is the enemy
mirror of the player's own capsules**. Hostile pressure comes straight from `social.gd`'s diplomacy. This
replaces the flat day-based `raid_wave_size` timer entirely.

## 7. Mechanics catalogue — every surviving mechanic, mapped to the kernel

Each row is a mechanic expressed *only* through the contracts above. **K** = already implemented & tested in the
kernel; **D** = designed, expressed via a shipped interface, not yet coded.

### 7.1 Hero survival
| # | Mechanic | RimWorld | Kernel expression | |
|---|---|---|---|---|
| 1 | Hunger | Need_Food | `Need_Food` ticked by a `NeedsSystem` | K |
| 2 | Sleep / rest | Need_Rest | `Need_Rest`; sleeping `satisfy()`s it | K |
| 3 | Located injuries | Hediff_Injury | `HealthTracker.injure()` → capacities → stats | K |
| 4 | Bleeding / downing | BleedRate / Downed | `Hediff.bleed_rate()` drains `blood`; `downed` | K |
| 5 | Medicine / tending | TendUtility | `HealthTracker.tend_all()` + `gear.TendService.tend()` — requires a `medicine` res in `world.stock` AND a medbed Thing (`CompMedbed`); effectiveness = StatWorker(medic competence) × medicine quality; consumes exactly one medicine, fails (no effect, no consume) when either is missing | K |
| 6 | Infection | Hediff (infection) | `Hediff_Injury.infection` festers untended | K |
| 7 | Disease / immunity | Hediff_Disease | immunity-vs-severity race | K |
| 8 | Apparel & armor | Apparel / ArmorRating | `gear.CompApparel` Thing (slot / insulation_c / armor-by-damage-type / wear) worn in a `gear.EquipModel` slot map; `StatPart_Armor` on `ArmorRating_<type>`; `apply_armor(dmg,type,equip,rng)` mitigates & wears gear; rising wear degrades armor + insulation | K |
| A9 | Temperature comfort | Hypothermia / Heatstroke + ComfortTemperature | `gear.Hediff_Hypothermia`/`Hediff_Heatstroke` climb while FELT temp (ctx.temp_c + equipped insulation) leaves the comfort band [12–30 °C] and recede inside it, lowering consciousness/moving; `gear.ComfortSystem` (prio 25, after env) / static `update_comfort()` maintain them on the `HealthTracker` | K |
| A3 | Thirst / water | Need_Thirst | `gear.Need_Water` (id `&water`) drains faster above ~25 °C (reads ctx.temp_c); `gear.drink(need, river/well/stored)` satisfies; `gear.hero_needs()` = `default_needs()` + water | K |
| A11 | Scars & prosthetics | Hediff scar / bionic implant surgery | `gear.Hediff_Scar` (permanent, fixed cap penalty); `resolve_to_scar()` non-destructive post-heal sweep leaves a scar where a severe wound healed; `gear.Hediff_Implant` restores a capacity; `install_prosthetic(tracker, part, implant)` = the medbed surgery (removes injuries+scars on the part, fits the implant) | K |

### 7.2 Production & economy
| # | Mechanic | RimWorld | Kernel expression | |
|---|---|---|---|---|
| 9 | Recipes & bills / quotas | RecipeDef / Bill | `RecipeDef(def_type=recipe)` + `CompWorkbench` bill queue + a `ProductionSystem` (prio 20) running `count N`/`until N` bills off the workbench Thing | K |
| 10 | Quality tiers | QualityCategory | `CompQuality` + `StatPart_Quality` | K |
| 11 | Research tree | ResearchProjectDef | `ResearchDef(def_type=research)` + `ResearchState` (try_start/advance/is_unlocked, prereq-gated); `Production.can_make()` gates recipes on unlocked ids | K |
| 12 | Cooking / meals / food poisoning | RecipeDef + FoodPoisoning | a `meal` Thing from a cook recipe carries `CompRottable`; `CookWorker.poison_chance` = base × raw-penalty × `StatPart_CookSkill` (drops with cook level); `roll_poison(rng)` seeded | K |
| 13 | Spoilage & refrigeration | CompRottable + temperature | `CompRottable` (ships) reading `ctx.temp_c` from climate | K |
| 14 | Outdoor deterioration | CompDeteriorate | same comp pattern keyed on "under roof?" + weather | K |
| D7 | Stockpile zones + priority hauling | Zone_Stockpile / StorageSettings + WorkGiver_HaulToCell | `StockZone` (rect + resource filter + priority, `accepts()`); `Production.best_zone_for()` picks the highest-priority accepting zone; `WorkGiver_HaulZone` routes each pile there (added alongside `agents.gd` `WorkGiver_Haul`, not editing it) | K |

### 7.3 Base, power & environment
| # | Mechanic | RimWorld | Kernel expression | |
|---|---|---|---|---|
| 15 | Electricity / power grid | CompPowerTrader / PowerNet | `CompPowerTrader`/`CompPowerSource`/`CompBattery` comps + `PowerNetSystem`; **solar output = `ctx.light` (daylight)**; brownout sheds lowest-priority loads; flips heater/lamp emitter `active` | K |
| 16 | Farming / grow zones / seasons | Plant / GrowthRate | `CompGrower` (ships) + climate `temperature_c`/`season`/`daylight` | K |
| 17 | Temperature (heat/cold stress) | Map temperature | `TemperatureSystem` writes `ctx.temp_c`; hurts hero/crops/rot; heaters & coolers are power-consuming Things | K |
| 18 | Weather events | WeatherDef | `ClimateProvider.weather()` (ships) + a `WeatherSystem` applying rain/fog/cold-snap effects | K |
| 19 | Fire & spread | Fire | `combat.gd` `CompFlammable` + `FireSystem` (prio 30) spreading across adjacent (Manhattan 1) flammable Things over seeded `world.rng`; `ctx.wet` (rain/snow) suppresses ignition & extinguishes | K |
| 20 | Defensive traps | Building_Trap | `combat.gd` `CompTrap` triggers on a **hostile** `Agent` entering `parent.pos` (deals damage, decrements `uses`, disarms at 0); NEVER triggers on the hero/player faction | K |
| D3 | Turrets: ammo & heat | Building_TurretGun + CompRefuelable | `combat.gd` `CompTurret` auto-fires at the nearest hostile `Agent` in `range` ONLY when its co-located `Power.CompPowerTrader.is_live()` AND ammo>0 AND heat<heat_max AND off cooldown; consumes ammo, adds heat, deals damage; otherwise bleeds heat/cooldown down; deterministic targeting (nearest, tie by list index) | K |

### 7.4 Threats & the director
| # | Mechanic | RimWorld | Kernel expression | |
|---|---|---|---|---|
| 21 | Balance pacing | Storyteller | `Balance.tick()` MTB rolls + adaptive gating | K |
| 22 | Wealth-based difficulty | WealthWatcher | `Balance.wealth()` / `threat_points()` / `difficulty` knob | K |
| 23 | Raid tactics | Raid strategies | `Balance._exec_raid().style` = assault/droppod/siege/sappers | K |
| 24 | Mortars / artillery | Building_TurretGun (mortar) | `combat.gd` `CompMortar` fires a `Projectile` Thing at a target cell with seeded scatter (grows with range); `Projectile` lands after a fuse (dday countdown) and deals area damage; `Combat.from_siege()` is the hook the `siege` raid style calls to build enemy mortars | K |
| 25 | Manhunter packs | ManhunterPack | `Balance` `manhunter` incident → `Agent_Animal.manhunter` | K |
| 26 | Ally quests | QuestScriptDef | `Balance` `quest` incident sourced from `social.gd` friends/clans; reward = reputation/resources | K |
| 27 | Cargo drops / gifts | CargoPods | `Balance` `cargo` incident (× `generosity`) | K |
| 32 | Insect infestation | Infestation | `Balance` `infestation` incident → hostile `Agent` swarm | K |
| D6 | Cover | Cover / hit-mitigation | `combat.gd` `StatPart_Cover` (folds `ctx.cover_mult` into a ranged-damage `StatWorker`) + `Combat.apply_cover(dmg, defender_pos, world)` reading `world.cover` cells (defender on/adjacent to cover takes `world.cover_frac` less ranged damage) | K |

### 7.5 Non-hero actors (the "colony without colonists")
| # | Mechanic | RimWorld | Kernel expression | |
|---|---|---|---|---|
| 28 | Automation drones | (mech workers) | `Agent_Bot` + `WorkGiver_Haul` (mine/build workgivers follow) | K |
| 29 | Animals: tame/hunt/pack/guard | Pawn (animal) | `Agent_Animal` roles: `guard` / `pack` / manhunter / wild | K |
| 30 | Raiders as robots | Mechanoids | `Agent_Raider` (hostile faction, drives at base) | K |
| 31 | Caravans need food + get ambushed | Caravan | existing `dispatch_convoy` + `Agent_Animal(pack)` escorts; ambush already modelled | K/D |

## 8. Integration path (does not break the green suites)

The kernel is a parallel, tested layer today. Migration is incremental and each step keeps all suites green:

1. **Stats first** — route `sim.gather_time` / `melee_damage` through `StatWorker` (behaviour-preserving), then
   attach `StatPart_Quality` when crafted gear gains `CompQuality`.
2. **Systems spine** — move `_update_raids/_enemies/_convoys/crafting` into `SimSystem`s registered in a
   `SystemRegistry`; `sim.update()` becomes *advance clock → build ctx → registry.tick_all*.
3. **Climate ctx** — a `TemperatureSystem` writes `ctx.temp_c`/`light` from the region's real lat/lon; wire
   `CompRottable`/`CompGrower` onto food and a new farm plot.
4. **Balance** — replace the raid timer with `Balance.tick()`, feeding `hostile_pressure` from `social.gd`
   (already wired) and `wealth()` from `stock`+`buildings`; surface `assess()` in the HUD (see spec 0004 §B).
5. **Health** — swap the hero's `hp` float for a `HealthTracker`; raiders keep a plain HP (they are robots).

## 9. Notes & invariants

- **Determinism** is preserved end-to-end: every stochastic path (quality roll, weather, incident MTB) takes a
  seeded `RandomNumberGenerator`, exactly like `world_gen.gd` / `social.gd`.
- **Ownership / cycles:** a `ThingComp` holds a strong back-reference to its `Thing`; `Thing.detach()` breaks the
  cycle when the sim drops it (RefCounted cannot collect cycles). Tests leak-at-exit harmlessly.
- **Seams that a backend replaces later:** `DefDatabase.load_pack()` (content catalogue), `ClimateProvider`
  (real weather), `social.gd.new_graph()` (live roster) — all three share the same "shape IS the wire format"
  contract established in spec 0002.

## 10. Test coverage (`godot/tests/run_kernel_tests.gd`, 284 assertions, headless)

Def registry + type index + DefOf + pack injection · Thing/Comp rot (warm vs frozen), growth (band + night
dormancy), quality (deterministic per seed, monotone) · Stat pipeline (quality × capacity, explain) · System
priority ordering · Climate (equator/pole, Kyiv seasons, hemisphere flip, day/night, determinism) · Needs
(fall/satisfy/thresholds) · Health (capacity→stat, bleed/tend/recover, infection festers vs tended, disease
immunity race, capacities bundle) · **Balance** (wealth, threat scaling, `assess` snapshot, `difficulty`/
`generosity` knobs, raid tactic escalation, `decide()` gating, deterministic `tick`, adaptive big-threat
suppression) · Agents (raider→base, bot haul vs idle, animal guard/graze/manhunter).

Plus per-batch coverage for the five layered systems — environment (temp/weather/light/deteriorate), power
(net/battery/brownout + emitter seam), production (bills/research/cooking/quality/zones), gear (armor/
comfort/tend/water/scars), combat (turret/mortar/trap/fire/cover) — and a **capstone end-to-end integration
test** (`_t_integration`) that composes ALL FIVE layers in ONE `SystemRegistry` and ticks the interleaved
10→30 spine (temperature→weather→light→power→production→comfort→fire): it proves environment writes the ctx
substrate, power balances the net and drives the heater emitter, production runs a bench bill, comfort
grows/recedes a hypothermia hediff, fire spreads (and is quenched when wet), the Batch-1↔2 emitter handoff
cools the cell on brownout, and the whole spine is deterministic per seed.

Batch 6 adds the **content-catalogue suite** (`_t_catalog`, 45 assertions): depth thresholds (63 resources /
11 nodes / 5 crops / 46 buildings / 51 recipes / 31 research), a clean `validate_catalog()` on the shipped
content, negative validator tests (unknown input, research cycle, dead tech, station bootstrap deadlock),
the station & power bill gates, and end-to-end chains — ore→charcoal→iron→steel→components→rifle (quality-
stamped Thing), carcass→(meat+hide byproduct)→leather→parka (wearable `CompApparel`, +18 °C), campfire meal
that rots by catalogue `rot_days`, herbs→herbal medicine→medicine feeding `TendService.tend()` with the
catalogue medbed, crop defs driving `CompGrower` + `harvest_crop()`, and the real research path
гончарство→металургія→ковальство→механообробка ground through `try_start`/`advance`.

## 11. Content catalogue (Batch 6 — `kernel/catalog.gd`)

The grammar above gets its full **vocabulary**: a single data module registering, through the
`DefDatabase.load_pack` seam, the complete playable content tree —

- **63 resources** in 5 tiers (сировина → матеріали → високотехнологічні → їжа/медицина → спорядження),
  each with `label/icon/tier/cat/source/value` (+`nutrition` for food). `source` grounds the craft closure:
  `gather/hunt/fish/farm/water` are base sources, `craft` must be reachable via recipes.
- **11 gather nodes** (дерево/скеля/ягідник/брухт/волокнина/глинище/піщаник/залізна+мідна жила/вугільний
  пласт/травник) and **5 crops** (пшениця/овочі/ягідник/бавовна/цілющі трави) whose payloads are literal
  `CompGrower` props; `make_crop_thing()`/`harvest_crop()` close the farm loop.
- **46 buildings** in 7 categories (структури/склад/виробництво/енергія/комфорт/оборона/ферма) with cost,
  hp, build work, research gates, `station` tags, and `power` payloads that are literal power-comp props;
  `make_building_thing()` instantiates any of them as a kernel Thing with the right comps (workbench,
  power trader/source/battery, medbed).
- **51 recipes** across 17 stations (верстак/багаття/піч/плавильня/кузня/ткацтво/чинбарня/кравецтво/
  різник/плита/млин/аптека/лабораторія/біопереробник/хімстіл/токарний/електромонтажний), chained
  raw→material→advanced→gear; thing-outputs carry catalogue comps (meals: `CompRottable`; apparel:
  `CompApparel` with insulation + typed armor). New recipe fields: `station` (bench gate) and
  `byproducts` (butchering yields meat AND hide).
- **31 research projects** in 4 eras (виживання → матеріали → індустрія → електрика), an acyclic DAG whose
  prereqs stage the whole tree from гончарство to біоніка.

Two new **ProductionSystem gates** compose the catalogue with earlier batches: a station-bound recipe
stalls on a foreign bench, and a bench carrying a `CompPowerTrader` (електромонтажний стіл) crafts only
while the net delivers (Batch 2 ↔ 6 seam).

**The deep validator** (`validate_catalog`) is the playability proof, beyond per-def `validate()`:
referential integrity (every input/output/cost/prereq/station names a registered def) · research DAG
acyclicity + no dead tech · station coverage both ways · and a **solvability closure** — a fixpoint over
the coupled sets {obtainable resources} × {buildable stations} that starts from base sources only and
proves every resource, recipe and building reachable, catching bootstrap deadlocks (a bench whose parts
are made only on that bench) that pure reference checks cannot see. The shipped catalogue passes with
zero errors; the suite also proves the validator *catches* seeded breakage.

**Host wiring:** `session.gd` owns the account-level kernel world (`session.kernel` = db + `ResearchState`
+ kernel Things) and ticks it in game-days via `kernel_tick()`; the view layer surfaces it through three
pure `HudModel` slices (`catalog`/`research`/`bills`) bound by the `BuildPanel`/`ResearchPanel`/`CraftPanel`
(spec 0005 grammar, R2/R8/R11 enforced in `run_ui_tests.gd`).
