# Spec 0004 — Mechanics catalogue & UX/UI implementation

Status: **design (content + interface)** · Companion to [spec 0003](0003-mechanics-kernel.md) (the kernel/architecture).
Scope constraints (from the goal) still hold: **one hero = one pawn**; other people are only other players; robots,
animals and turrets are **Agents**; **raiders are robots**; **no mood/thoughts, no traits/skills yet, no beauty buffs**.

0003 is the *how it's built* (Def/Comp/Stat/System/Balance). This spec is the *what the player sees and does*:
every mechanic gets a **long-form description** and a **concrete UX/UI implementation**. The classic Storyteller is
gone — a single **`Balance`** class now owns difficulty/economy/pacing and is the seam for a future AI director;
its player-facing surface is §B below. A live, rendered implementation of this HUD ships as the interactive
mock-up artifact referenced at the end.

---

## 1. HUD architecture — the frame every mechanic renders into

The screen is divided into stable zones so each new mechanic has an obvious home. Existing `main.gd` already owns
input/render; this is the target layout it grows into.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ TOP BAR:  🕓 clock/day · ☀/🌙 phase · 🌡 temp · ⛅ weather · 📍 region   [⚙] │
├───────────────┬──────────────────────────────────────────┬────────────────┤
│ LEFT DOCK     │                                          │ RIGHT DOCK     │
│  ▸ Vitals     │             WORLD VIEWPORT               │  ▸ Stock       │
│  ▸ Health doll│        (click-to-order, drag-build)      │  ▸ Build/craft │
│  ▸ Equipment  │                                          │  ▸ Agents      │
│               │        [incident banner overlay]         │  ▸ Balance     │
├───────────────┴──────────────────────────────────────────┴────────────────┤
│ ACTION BAR:  [1..9 build/craft palette]        [event feed ▸ toasts/log]   │
└──────────────────────────────────────────────────────────────────────────┘
```

**Design tokens** (reuse `data.gd` colors): resource icons/colors from `RES`; need bars are color-coded by
urgency (green > amber > red); panels share one `StyleBoxFlat`. **Interaction verbs:** *left-click* = context
order (move/gather/attack/haul-target); *left-drag* = build/zone rectangle; *number keys* = select palette
slot; *right-click* = cancel/deconstruct; *hover* = tooltip with the `StatWorker.explain()` breakdown.
**Feedback channels (already in the sim):** `banner` (top, urgent, e.g. incoming raid), `flash_msg` (center,
transient error like "тут не можна будувати"), `messages`/log (bottom-right, scrolling history), `toast`
(right, positive confirmations). **Accessibility:** every color cue is paired with an icon + number; the whole
HUD is keyboard-navigable; `H` opens contextual help.

---

## 2. §B — The Balance panel (director surface & future AI)

**Опис.** `Balance` (spec 0003 §6) is the one authority for game feel. The panel exposes its `assess()` snapshot
so the player can *read the pressure* the way RimWorld shows the storyteller's mood — but here it is a concrete,
inspectable state, because the same numbers will soon be driven by an AI policy via `decide()`.

**UX/UI.**
- **Threat gauge** — a horizontal meter of `assess().threat`, segmented by phase: `спокій → рейд → облога →
  сплеск` (calm/raid/siege/spike). Color ramps green→red; the current phase name sits above it.
- **Wealth readout** — `assess().wealth` with a sparkline of the last N days; a ⓘ tooltip breaks it into
  buildings / stock / gear (so the player learns *why* raids are getting bigger).
- **Next-pressure hint** — "очікуй ~%d рейдерів" from `raid_hint`, plus a soft ETA from the raid MTB. Never a
  hard countdown (adaptive pacing is intentional).
- **Knobs (dev/AI panel):** `difficulty` and `generosity` sliders + per-category cadence weights. In normal play
  these are hidden/AI-owned; in a dev overlay (`~`) they're editable. **This slider row is literally the AI
  control surface** — when the AI ships, it moves these and the panel shows *"director: AI"* with its rationale.
- **Incident feed** — every payload from `Balance.tick()` becomes a feed card (icon, name, one-line effect,
  jump-to-location). Raids/sieges also raise the top `banner`.

---

## A. Hero vitals, health & comfort

**A1 · Hunger (Need_Food).** *Опис:* a 0..1 drive that falls over the day; at the low threshold the hero
auto-eats from storage, at zero it drains HP. *UX/UI:* a 🍖 bar in Vitals, amber at `wants()`, red+pulsing at
`critical()`; a small "їсть" icon when auto-eating; tooltip shows time-to-empty.

**A2 · Rest / sleep (Need_Rest).** *Опис:* falls while awake, restored fast in a bed; low rest slows work and
movement (via a `StatPart`). *UX/UI:* a 😴 bar; at night a "zzz" glyph over the hero when sleeping; a red bed
icon if no bed is reachable.

**A3 · Thirst / water (Need_Water — NEW).** *Опис:* a third drive; drink from OSM-derived rivers/lakes, wells,
or stored water; hot/dry regions drain it faster (ties to climate). *UX/UI:* a 💧 bar; water tiles get a subtle
"drinkable" shimmer on hover; building a well adds a refill radius ring.

**A4 · Located health (HealthTracker + body doll).** *Опис:* the single HP float is replaced by body parts +
hediffs; each wound reduces the capacities of its part. *UX/UI:* a **paper-doll** in the Left Dock — silhouette
with per-part tint (green→red by damage), a bleed drip animation, and a blood-level ring around it. Clicking a
part lists its hediffs with severity bars.

**A5 · Bleeding & downing.** *Опис:* untended wounds drain `blood`; at ~15% blood or lost consciousness the hero
is downed (in MMO, a rescue/finish window). *UX/UI:* a red vignette that intensifies as blood falls; a "⏱ кровотеча
-X%/день" line; screen desaturates near downing.

**A6 · Medicine / tending.** *Опис:* `tend_all()` stops bleeding and blocks infection; needs a `medicine`
resource and a medbed; tend quality (a `StatWorker`) sets effectiveness. *UX/UI:* a "Лікуватися" action on the
health doll (hotkey `T`); shows medicine cost, a progress ring, and the resulting bleed/infection deltas.

**A7 · Infection.** *Опис:* deep untended wounds fester (0..1); at 1.0 the part is lost. *UX/UI:* a yellow
"інфекція %d%%" tag on the affected part that darkens over time; urgent toast when it passes 60%.

**A8 · Disease (immunity race).** *Опис:* `Hediff_Disease` climbs; tending reaches immunity sooner; lose the
race and consciousness collapses. *UX/UI:* a dual bar on the doll — **immunity vs severity** racing toward the
line; the panel calls the winner ("виграєш гонку імунітету").

**A9 · Temperature comfort (NEW).** *Опис:* the region's real temperature (climate) vs the hero's insulation
(apparel) yields a comfort band; outside it, heatstroke/hypothermia hediffs accrue. *UX/UI:* the 🌡 in the top
bar turns blue/red when uncomfortable; a small "−утеплення" hint suggests clothing/heaters; a comfort thermometer
appears in Vitals when out of band.

**A10 · Apparel & armor (NEW).** *Опис:* worn `Thing`s add insulation + `ArmorRating_*` (a `StatPart`),
degrading with hits. *UX/UI:* an Equipment sub-panel with body-slot silhouettes; drag items onto slots; each shows
armor % and insulation °C; worn condition as a thin wear bar.

**A11 · Scars & prosthetics (late-game hook).** *Опис:* healed severe injuries can leave scars (permanent minor
capacity loss); prosthetics/bionics replace parts via a `RecipeDef` + a `Hediff` implant. *UX/UI:* scarred parts
show a faint scar icon; an "операція" bill queued at the medbed; bionic parts render metallic on the doll.

---

## B. Movement, world & vision

**B1 · Terrain movement cost.** *Опис:* tiles carry a move-cost (grass 1×, mud/water slow, road fast); already
partly in worldgen (roads). *UX/UI:* the move-order path preview colors segments by speed; hovering a tile shows
"×швидкість".

**B2 · Roads (OSM).** *Опис:* real OSM roads rasterized to fast tiles; convoys and the hero move quicker on them.
*UX/UI:* roads render as a distinct band; the path-preview visibly hugs them; a "по дорозі +%" note on long moves.

**B3 · Lighting & night vision (NEW).** *Опис:* `climate.daylight()` sets ambient light; at night vision/ work is
reduced unless lit by torches/lamps (power). *UX/UI:* a day/night darkening overlay (already `sim.daylight()`);
lamps cast light circles; unlit work actions show a "−темрява" penalty.

**B4 · Roofing: indoor vs outdoor (NEW).** *Опис:* roofed+walled tiles are "indoor" — buffer temperature, block
rain, stop deterioration; unroofed loot deteriorates and gets weathered. *UX/UI:* a toggleable roof overlay
(hotkey `R`) shades indoor tiles; outdoor stockpiles show a "⛅ псується" warning.

**B5 · Water, wells & fishing (NEW).** *Опис:* OSM water is a resource: drink (A3), fish for food, draw into
wells/tanks. *UX/UI:* click water → "рибалити"/"набрати води" context actions; a catch meter; wells show a fill
gauge.

---

## C. Production & technology

**C1 · Gathering.** *Опис:* nodes (tree/rock/bush/scrap) yield resources over `gather_time` (a `StatWorker`:
skill×tool×manipulation). *UX/UI:* click a node → progress ring on the hero + floating "+🪵"; node depletion
shrinks its sprite; carry-cap bar warns before full.

**C2 · Crafting bills & quotas (NEW, expands passive crafting).** *Опис:* a workbench runs **bills** — "craft
axe ×2", "planks until 50" — instead of the current passive tick. *UX/UI:* a Bills list on the workbench panel:
add-recipe dropdown, a "робити доки N" stepper, drag to reorder, a live queue with ETAs and missing-material
badges.

**C3 · Quality tiers.** *Опис:* `CompQuality` rolls awful→legendary at craft, scaling item stats via
`StatPart_Quality`. *UX/UI:* crafted items show a colored quality pip + label ("майстерна"); tooltip stat lines
include "×якість 1.35"; a legendary craft throws a celebratory toast.

**C4 · Research tree (NEW).** *Опис:* `ResearchDef`s gate advanced buildings/recipes; progressed at a research
bench (later powered/lit). *UX/UI:* a tech-tree panel (nodes, prereq lines, progress bars); locked build/craft
entries show a 🔒 with "дослідити: X"; completing a node toasts the unlocks.

**C5 · Cooking & meals (NEW).** *Опис:* raw food → meals via a stove bill; meals restore more hunger; raw/rotten
food risks a food-poisoning hediff (a `StatWorker` on cook skill sets the odds). *UX/UI:* a stove panel like Bills;
meals show freshness (from `CompRottable`); a "сире — ризик отруєння" warning when eating raw.

**C6 · Spoilage & refrigeration.** *Опис:* `CompRottable` rots food faster when warm, **halts ≤0 °C**; a powered
cooler makes a cold room. *UX/UI:* each food stack shows a rot % bar; cold rooms tint blue with a "🧊 −гниль"
label; a spoilage toast when a stack is lost.

**C7 · Electricity / power grid (NEW).** *Опис:* generators (fuel/**solar = `daylight()`**/wind) feed a net;
batteries store; turrets, coolers, lamps, research consume. Overdraw browns out. *UX/UI:* a power overlay (hotkey
`P`) draws wires + a net meter (gen vs draw); low battery pulses red; each powered building has a ⚡ on/off pip.

**C8 · Farming & seasons.** *Опис:* grow-zones plant crops that mature via `CompGrower` inside a temperature band
with light; seasons (climate) gate what grows where — on the **real map** of the region. *UX/UI:* drag a grow-zone
rectangle, pick a crop; tiles show per-plant growth % and a "поза сезоном/замало світла" dormancy tag; harvest
prompt at 100%.

---

## D. Base building & defense

**D1 · Building & blueprints.** *Опис:* drag-place walls/doors/floors/storage/workbench/bed/turret; cost checked
against stock; blocked tiles rejected. *UX/UI:* ghost preview (green=valid, red=blocked with `flash_msg` reason),
drag-rectangle for walls, a running cost tally, affordability dimming on the palette (already present).

**D2 · Walls, doors & rooms.** *Опис:* walls block pathing/threats; doors pass the hero but slow raiders; enclosed
+roofed tiles form rooms (temperature/indoor). *UX/UI:* auto-connecting wall sprites; a room outline highlight on
hover showing enclosed area + indoor temp.

**D3 · Turrets & ammo (NEW ammo).** *Опис:* turrets auto-fire within range (exists); a NEW ammo/heat model makes
them need reloads/cooldown and power. *UX/UI:* range ring on select/hover; an ammo/heat bar per turret; a "нема
живлення/набоїв" red state.

**D4 · Mortars & artillery (NEW).** *Опис:* long-range indirect fire (a mortar `Thing` launching a `projectile`);
the enemy `siege` raid style builds mortars and bombards. *UX/UI:* click-to-target-tile with a scatter circle +
arc preview; incoming enemy shells show impact markers with a warning beep.

**D5 · Traps (NEW).** *Опис:* deadfall/spike/mine `Thing`s trigger on an enemy `Agent` entering the cell; single-
or multi-use. *UX/UI:* traps placed like buildings but only on non-path tiles you designate; armed traps show a
faint hazard chevron only to the player (hidden from the "camera" feel); trip → burst effect + log line.

**D6 · Cover & sandbags (NEW).** *Опис:* low cover (sandbags/rubble) reduces ranged damage taken; positions
matter in firefights. *UX/UI:* cover tiles show a small shield glyph; when the hero stands in cover, a "укриття
−%" indicator appears near the health doll.

**D7 · Stockpile zones & hauling.** *Опис:* designate filtered stockpile zones with priorities; bots/animals haul
to them (Agents). *UX/UI:* drag a zone, tick allowed resources, set priority; zone tiles tinted by contents; a
per-zone fill bar.

---

## E. Threats & Balance incidents

**E1 · Raids + tactics.** *Опис:* `Balance` sizes a mechanoid force by threat points and picks a tactic:
`assault → droppod(day%4) → siege → sappers`. Droppod lands inside the base (mirror of your capsules). *UX/UI:*
a top `banner` with count + tactic + faction; edge arrows show incoming direction; sappers highlight the wall
they're breaching; droppods show falling markers before impact.

**E2 · Siege.** *Опис:* the siege tactic sets up an enemy camp + mortars at range and bombards until provoked.
*UX/UI:* a ring marking the siege camp; shell arcs + impact predictors; a "вилазка?" prompt suggesting a sortie.

**E3 · Insect infestation (NEW).** *Опис:* the `infestation` incident spawns a hostile `Agent` swarm from inside
(under-mountain/basement) — a pressure that ignores your outer walls. *UX/UI:* pulsing hive markers on the origin
tiles with a short warning before hatch; swarm count in the incident card.

**E4 · Manhunter pack.** *Опис:* the `manhunter` incident flips wild `Agent_Animal`s hostile toward the hero.
*UX/UI:* affected animals get an aggro outline + "оскаженіли"; the feed card lists species + count.

**E5 · Disease incident.** *Опис:* `Balance` can strike a disease hediff (A8) as a small threat. *UX/UI:* handled
by the health doll (A8) plus a feed card naming the illness.

**E6 · Cold snap / heat wave (NEW).** *Опис:* the `cold_snap` incident (and a heat-wave sibling) shifts regional
temperature for N days — freezing crops or forcing cooling. *UX/UI:* the top-bar 🌡 flashes with a "похолодання
−15°C, 2 дні" ticker; affected crops show a frost tint.

**E7 · Natural disasters by real geography (NEW).** *Опис:* region-appropriate hazards from real lat/lon — floods
near OSM rivers/coasts, quakes in seismic belts, storms — enacted as incidents with terrain/building effects.
*UX/UI:* a distinct disaster banner + screen shake/overlay (flood water rising, quake jitter); pre-warning where
the model allows.

**E8 · Toxic / radiation zones (NEW).** *Опис:* some real locations carry a persistent toxic/radiation field
(a real-world hook); exposure accrues a hediff; protective gear mitigates. *UX/UI:* a green/□ hazard overlay on
affected tiles; a rad-dose meter in Vitals when inside; gear reduces the fill rate.

---

## F. Non-hero actors (the colony without colonists)

**F1 · Automation drones / bots.** *Опис:* `Agent_Bot` + `WorkGiver`s haul/mine/build autonomously — your labor
force without extra pawns. *UX/UI:* an Agents panel lists each bot with its current `Job` verb + target; click to
see its path; toggle allowed jobs per bot.

**F2 · Animals: taming.** *Опис:* wild `Agent_Animal`s can be tamed (food + odds); tamed roles: guard/pack/haul.
*UX/UI:* click a wild animal → "приручити" with a success-chance readout; tamed animals get a faction outline +
a role dropdown.

**F3 · Hunting.** *Опис:* wild animals are a food source; downing one yields meat. *UX/UI:* click animal →
"полювати"; a threat hint if the species can turn manhunter; butcher prompt on kill.

**F4 · Pack animals & caravans.** *Опис:* tamed `pack` animals escort convoys, raising capacity and defense.
*UX/UI:* when dispatching a convoy, assign pack animals from a roster; the convoy card shows escort strength.

**F5 · Guard animals.** *Опис:* `role=guard` animals attack the nearest raider / follow the hero. *UX/UI:* a
guard toggle; guard animals show a shield outline and a leash radius around their anchor.

**F6 · Raiders as robots.** *Опис:* `Agent_Raider` mechanoids: no needs/morale, drive at the base; sized by
`Balance`. *UX/UI:* raiders render with a mechanical look + a small HP pip; selecting one shows type/HP (no
"mood" — they are machines).

---

## G. Economy, social & logistics

**G1 · Convoy trade.** *Опис:* dispatch resources to real hub cities; each hub buys/sells at a rate; ambush risk
en route (exists). *UX/UI:* a logistics map (hotkey `M`) of real hubs with buy/sell offers; pick hub+resource+amt;
active convoys show a route dot with an ambush-risk %.

**G2 · Market prices (NEW).** *Опис:* hub offers drift over time/season and with your reputation; scarcity
economics. *UX/UI:* each hub shows a price trend arrow; a tooltip sparkline of recent rates; "твоя репутація:
+X% ціна".

**G3 · Reputation / faction standing (NEW).** *Опис:* actions shift standing with clans/alliances (from
`social.gd`), gating trade, quests, and raid pressure. *UX/UI:* a diplomacy panel of factions with
ally/neutral/hostile pips + a standing bar; changes toast ("Клан «Соколи»: +репутація").

**G4 · Ally quests.** *Опис:* the `Balance` `quest` incident, sourced from friends/clans, offers defend/deliver
tasks for reputation + resources. *UX/UI:* a quest card with objective, timer, reward, and accept/decline; active
quests pin to the feed with progress.

**G5 · Capsules (drop pods).** *Опис:* the daily capsule moves the hero + inventory ≤100 km to a real coordinate
or a friend's invite (spec 0002). *UX/UI:* a capsule button showing charge + radius; the logistics map lets you
pick a target inside the radius (out-of-range greyed); invites appear as pins.

**G6 · Alliances & empires.** *Опис:* the four-tier social graph (player→clan→alliance→empire) sets who raids you
and who can invite you (spec 0002). *UX/UI:* the diplomacy panel groups factions by tier with the `TIER_ICON`s;
hovering shows shared-alliance/empire ally reasons.

---

## H. Persistence & real-GPS

**H1 · Region travel & around-maps.** *Опис:* the world is a lattice of real-coordinate regions; travel saves the
current region (seed+diff+save, hash-chained) and loads/generates the target (spec 0002). *UX/UI:* a travel
confirmation showing distance + capsule cost; a brief "генерується місцевість…" transition; a breadcrumb of
visited regions.

**H2 · Real climate & weather.** *Опис:* temperature/season/daylight/weather come from the region's **real
latitude** (`ClimateProvider`), with a SEAM to a live weather API. *UX/UI:* the top bar's 🌡/⛅ reflect the real
model; a region info tooltip shows lat/lon, season, and "клімат: модель / жива погода" source.

**H3 · Permadeath = fresh rookie.** *Опис:* death loses the pawn entirely (skills/loot/gear gone); a new
un-leveled pawn spawns at the clan base; the settlement persists (spec 0002). *UX/UI:* a dedicated death screen
(cause, days survived, wealth reached) → "нова пішка" respawn; the new hero starts with empty vitals bars and a
clean health doll.

---

## Cross-cutting UX rules

- **One truth per number.** Every stat shown is `StatWorker.explain()`-backed on hover — the player can always see
  *why* (base × quality × capacity × weather). No opaque numbers.
- **Threat is legible, timing is not.** `Balance` shows *how bad* (phase/threat/wealth) but never an exact raid
  countdown — adaptive pacing is a feature, surfaced honestly.
- **Determinism visible.** Region/climate/incident outcomes reproduce from seed; a dev overlay can show the seed
  and the RNG stream for debugging (matches `world_gen.gd`/`social.gd`).
- **Colorblind-safe.** Every color state is paired with an icon and/or number.
- **Everything is a panel toggle.** The top toolbar toggles each Right/Left dock panel; `H` = contextual help.

## Implementation status & next steps

- **Balance director:** implemented + tested (`balance.gd`, 59 kernel tests) — §B is ready to bind to a panel.
- **Kernel mechanics (K in 0003 §7):** logic implemented + tested; these panels bind to existing kernel APIs.
- **This spec's UX:** the layout + per-mechanic interface is realized as a **rendered interactive HUD mock-up**
  (the artifact shipped alongside this session) so the design is *seen and clicked*, not just described. The Godot
  `main.gd` HUD then grows into these zones one panel at a time, following spec 0003 §8's migration order.
