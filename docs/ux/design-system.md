# RealWorld — HUD Design System & per-mechanic interface spec

Status: **binding UX contract** for the mechanics build-out. Companion to [spec 0004](../../specs/0004-mechanics-catalogue-and-ux.md)
(the what-the-player-sees catalogue) and [spec 0003](../../specs/0003-mechanics-kernel.md) (the kernel).
The living, rendered realization is [`hud.html`](hud.html) — every rule below is proven by being *seen and clicked* there.

> Why this doc exists: the mechanics are built in dependency-ordered batches by separate agents. Logic can be
> modular; **UX cannot be** — five independently-styled panels read as five games. This is the single source of
> truth for tokens, layout, the overlay/panel/interaction grammar, and accessibility, so every batch's interface
> composes into ONE coherent HUD. If a mechanic's interface isn't specified here, it isn't done.

---

## 0. First principles (from spec 0004 "Cross-cutting UX rules", made enforceable)

1. **One truth per number.** Every displayed stat is hover-backed by `StatWorker.explain()` — `base × quality ×
   capacity × weather`. No opaque numbers. In the mockup, every numeric value carries a `title=` breakdown; in
   Godot every readout binds to `explain(ctx)`.
2. **Threat is legible, timing is not.** Balance shows *how bad* (phase / threat / wealth) never an exact raid
   countdown. ETAs are soft ("~", "скоро"), never a hard clock.
3. **Determinism visible.** Region/climate/incident outcomes reproduce from seed; the dev overlay (`~`) can show
   the seed + RNG stream.
4. **Colorblind-safe, always.** Every color state is paired with an icon AND/OR a number. No cue is color-only.
   Ramp semantics are fixed (see §1): green = good/safe, amber = warn/act-soon, red = critical, teal = info/cold,
   violet = tech/advanced.
5. **Everything is a panel or overlay toggle.** The top toolbar toggles each dock panel; hotkeys toggle map
   overlays; `H` = contextual help. Nothing is buried in a menu with no discoverable trigger.
6. **Keyboard-first, mouse-fast.** Every action has a hotkey; every hotkey is shown in the tooltip. Focus rings
   are visible (`:focus-visible` → amber outline). The HUD is fully navigable without a mouse.

---

## 1. Design tokens (locked — reuse `:root` in hud.html, mirror `data.gd` colors)

| Token | Value | Meaning |
|---|---|---|
| `--bg / --panel / --panel2` | `#0e1216 / #151b21 / #1b232b` | app bg / panel / raised panel |
| `--line / --line2` | `#26313b / #33414d` | hairline / stronger border |
| `--ink / --mut / --dim` | `#c9d4dc / #7c8b97 / #54636f` | primary / secondary / tertiary text |
| `--good` `#6fae54` | green — safe, satisfied, ally, in-band |
| `--warn / --amber` `#e0b070` | amber — wants attention, act soon, selection accent |
| `--crit` `#e06a5a` | red — critical, hostile, blocked |
| `--teal` `#86d0d6` | info, cold, water, bots, drinkable |
| `--comp` `#b58cff` | violet — tech/research/advanced/components |
| `--blood` `#b23b34` | blood / bleed |
| resource dots | `--wood --stone --food --scrap --planks --comp` | per-resource, from `RES` |

Type: `--sans` (system-ui) for labels; `--mono` (ui-monospace) for all numbers (tabular-nums). Radius `--r:8px`.
Panel header `h2`: 10px, `letter-spacing:.16em`, uppercase, `--mut`, with an optional `.tag` (mono) at right.

---

## 2. Layout — the stable frame every mechanic renders into

```
┌ TOP BAR ─ 🕓day/clock · ☀/🌙phase · 🌡temp · ⛅weather · 📍region ─────── [overlays ▾][⚙] ┐
├ LEFT DOCK ────┬──────────── WORLD VIEWPORT ───────────────┬──── RIGHT DOCK ────────────────┤
│ ▸ Vitals      │  click=order · drag=zone/build · num=slot  │ ▸ Stock                        │
│ ▸ Health doll │  [overlay layer: power/roof/light/heat/…]  │ ▸ Build / Craft (Bills)        │
│ ▸ Equipment   │  [incident banner] [edge threat arrows]    │ ▸ Research                     │
│ ▸ Comfort     │  [context radial on selection]             │ ▸ Agents                       │
│               │                                            │ ▸ Balance (director)           │
├ ACTION BAR ───┴── [1..9 build/craft palette] ── [event feed ▸ toasts / scrolling log] ──────┤
```

**Dock rule:** a new mechanic gets a home BY SYSTEM, not by novelty. Hero-body → Left dock. World/economy/threat
→ Right dock. Anything spatial (a grid state) → a **world overlay**, never a panel of coordinates.

**Panels are collapsible + toggleable** from the top toolbar's `[overlays ▾]`/panel chips. Default-open set is
small (Vitals, Health, Stock, Balance); advanced panels (Research, Power, Agents) open on first relevance
(first research bench built → Research panel pips into view) with a one-time toast.

---

## 3. The overlay framework (the spatial-state renderer — CRITICAL, this is where most new mechanics live)

RimWorld's power/roof/temperature overlays are the model. A **world overlay** is a toggleable layer drawn over
the viewport that colors/annotates tiles for ONE system. Only one primary overlay is active at a time (radio),
plus always-on micro-markers (fire, traps-to-owner). Each overlay has a **hotkey**, a **legend chip**, and a
**toolbar toggle**. Fixed assignments (do not reassign):

| Hotkey | Overlay | Renders | Batch |
|---|---|---|---|
| `R` | **Roof / indoor** | indoor tiles shaded warm, outdoor cool; roof edge line | 1 |
| `T` | **Temperature** | tile heat-map blue→red vs comfort band; emitter radius rings | 1/2 |
| `L` | **Light** | night darkening + lamp light circles; unlit-work tiles dim | 1/2 |
| `P` | **Power** | wires, net meter (gen vs draw), per-building ⚡ on/off, brownout pulse | 2 |
| `G` | **Grow zones** | crop tiles with growth %, dormancy tag | 3 (K logic) |
| `Z` | **Stockpiles** | zone tint by contents, priority number, fill bar | 3 |
| `F` | **Fire** (always-on markers) | flame glyphs + spread front; not a radio overlay | 5 |
| `K` | **Cover** | cover tiles show shield glyph + % | 5 |
| `M` | **Logistics map** (modal) | real hubs, convoy routes, capsule radius | G (later) |

Overlay legend lives bottom-left of the viewport (the existing `.legend` element grows a per-overlay row).
Toggling an overlay is instant, animated only if `prefers-reduced-motion` is not set.

**Contract for a mechanic that has spatial state:** you MUST provide (a) an overlay renderer keyed to its hotkey,
(b) a legend row, (c) a toolbar chip. You may ALSO provide a summary panel, but the overlay is mandatory — the
player reads spatial systems on the map, not as lists of coordinates.

---

## 4. The panel framework (dock panels for non-spatial system state)

A dock panel = `.panel` with an `h2` header (icon ▸ title + `.tag`), a body, and (optional) a `.minibtns` action
row. Reuse existing sub-components:
- **need bar** (`.need`): 20px icon · track · mono value. Color by urgency, ALWAYS with the number. (Vitals)
- **stat row** (`.stock .r`): glyph · label · right-aligned mono value. (Stock, Equipment, Agents)
- **gauge** (`.gauge`): segmented horizontal meter with phase labels above. (Balance threat, immunity race)
- **doll** (SVG paper-doll): per-part tint + meta capacities. (Health; Equipment reuses body-slot silhouettes)
- **bill row** (NEW, §5.3): recipe · "do until N" stepper · drag-handle · ETA · missing-material badge.
- **tech node** (NEW, §5.3): title · progress bar · prereq lines · lock state.
- **card** (`.card`): incident/quest feed item, left-border colored by category.

New panels MUST be built from these primitives. If a mechanic needs a genuinely new primitive, define it here
first (add a row), then use it — so the vocabulary stays finite.

---

## 5. Interaction grammar (verbs are fixed across the whole game)

| Verb | Input | Meaning |
|---|---|---|
| **order** | left-click a tile/thing | context action (move / gather / attack / haul-target / target-tile) |
| **zone / build** | left-drag rectangle | build wall run, paint grow/stockpile zone |
| **select slot** | number keys 1–9 | pick build/craft palette slot |
| **cancel / deconstruct** | right-click | cancel order, deconstruct building, disarm |
| **inspect** | hover | tooltip with `StatWorker.explain()` breakdown |
| **overlay** | hotkey (§3) | toggle spatial overlay |
| **help** | `H` | contextual help for whatever is under the cursor / selected |

Selection shows a **context radial/inline actions** near the thing (turret → range ring + ammo; animal wild →
"приручити %"; water → "набрати / рибалити"). Ghost preview on build: green=valid, red=blocked + a `flash_msg`
reason in Ukrainian (e.g. "тут не можна будувати"). Feedback channels (already in sim): `banner` (top, urgent),
`flash_msg` (center, transient error), `toast` (right, positive confirm), `feed`/log (bottom-right, history).

---

## 6. Per-mechanic interface spec, by dependency batch

Each entry = **Panel** (dock home) · **Overlay** (spatial, if any) · **Interactions** · **Feedback** · **the
`explain()`/legibility hook**. Batches match the kernel build order. Every batch's UX must land in `hud.html`,
rendered and clickable, before the batch is "done".

### Batch 1 — Environment (the ctx layer the player must be able to *read*)
- **Temperature (#17).** *Panel:* top-bar 🌡 turns teal(cold)/red(hot) out of comfort; a Comfort mini-panel in
  Vitals appears only when out of band, with a thermometer + "−утеплення" hint. *Overlay:* `T` heat-map + emitter
  rings. *Explain:* 🌡 tooltip = "клімат 14° · у приміщенні +5° · обігрівач +3° = 22°".
- **Weather (#18).** *Panel:* top-bar ⛅ icon + name; effect chips ("дощ: −ріст, гасить вогонь"). *Feedback:*
  weather-change toast. No overlay (it's global) but rain tints the viewport.
- **Lighting / night (B3).** *Overlay:* `L` — night darkening (exists) + lamp circles; unlit work tiles dimmed
  with a "−темрява" penalty tag on the work cursor. *Explain:* light value in the tile tooltip.
- **Roofing indoor/outdoor (B4).** *Overlay:* `R` — indoor tiles shaded warm, roof edge line; outdoor stockpiles
  get a "⛅ псується" warning. *Panel:* room hover shows enclosed area + indoor temp.
- **Deterioration (#14).** *Feedback:* outdoor item stacks show a thin "знос %" wear bar + a toast when one is
  lost. Ties to the `R` overlay (indoor = safe).

### Batch 2 — Power grid
- **Power net (#15/C7).** *Overlay:* `P` — wires, a floating net meter `gen ⚡X / draw Y`, per-building on/off pip,
  low-battery red pulse, brownout ripple. *Panel:* a Power summary (gen, draw, stored, headroom) in Right dock,
  visible once a generator exists. *Interactions:* click a powered building → ⚡ toggle; drag to lay conduit.
  *Explain:* solar tooltip = "сонячна панель × світло 0.8 = 240W".
- **Generators / batteries.** rows in the Power panel: each source its output; battery a charge gauge + "заряд
  4.2h". Solar output visibly tracks the `L`/daylight value (teach the coupling).
- **Heaters & coolers.** placed like buildings; show their target-temp setpoint + a radius ring in the `T`
  overlay; a ⚡ pip; go dark on brownout (and their temp effect stops — visible in `T`).
- **Lamps.** show a light circle in `L`; ⚡ pip; dark on brownout.
- **Brownout.** net meter goes red, lowest-priority loads pulse then drop; a "🔌 перевантаження" banner.

### Batch 3 — Production & technology
- **Bills / quotas (#9/C2).** *Panel:* workbench selection opens a **Bills** list — add-recipe dropdown, a "робити
  доки N" stepper, drag-to-reorder, per-bill ETA + a red missing-material badge. *Feedback:* craft-complete toast.
- **Research tree (#11/C4).** *Panel:* a Research dock panel = tech nodes with prereq lines + progress bars;
  locked build/craft palette slots show 🔒 + "дослідити: X" (the palette already dims/locks slot 9). Completing a
  node toasts the unlocks + un-dims the slots.
- **Cooking / meals (#12/C5).** a stove Bills panel (same primitive); meals show freshness from `CompRottable`; a
  "сире — ризик отруєння %" warning when eating raw, scaled by cook skill.
- **Quality (#10).** crafted items show a colored quality pip + label ("майстерна"); tooltip stat lines include
  "×якість 1.35"; legendary → celebratory toast. (Equipment panel already previews this.)
- **Stockpiles + hauling (D7).** *Overlay:* `Z` — drag a zone, tick allowed resources, set priority; zone tiles
  tint by contents + a fill bar. Bots/animals (Agents panel) show "haul → zone".

### Batch 4 — Hero gear, health-services & comfort
- **Apparel & armor (#8/A10).** *Panel:* Equipment sub-panel with **body-slot silhouettes** (reuse the doll
  shape); drag items onto slots; each shows armor % + insulation °C + a thin wear bar. *Explain:* armor tooltip =
  the `ArmorRating` StatWorker breakdown.
- **Temperature comfort (A9).** the Comfort panel from Batch 1 now reads apparel insulation vs `ctx.temp_c`;
  heatstroke/hypothermia appear as **hediffs on the health doll** with a severity bar.
- **Medicine / medbed (#5/A6).** the doll's "Лікувати 💊" action (hotkey `T`… note: reserve a non-conflicting key,
  use the doll button) shows medicine cost + a progress ring + resulting bleed/infection deltas; needs a medbed
  Thing (a build slot) and a `medicine` resource (Stock row).
- **Thirst / water (A3).** a 💧 need bar (already in Vitals). Water tiles get a "drinkable" teal shimmer on hover;
  a well adds a refill-radius ring (a mini-overlay). Hot/dry regions drain it faster (visible decay rate).
- **Scars / prosthetics (A11).** scarred parts show a faint scar icon on the doll; an "операція" bill queued at
  the medbed (Bills primitive); bionic parts render metallic on the doll.

### Batch 5 — Threats & combat objects
- **Turrets & ammo (D3).** select → **range ring** + an ammo/heat bar; a "нема живлення/набоїв" red state; ⚡ pip.
- **Mortars / artillery (#24/D4).** click-to-target-tile with a **scatter circle + arc preview**; incoming enemy
  shells show impact markers + a warning beep; the siege incident places an enemy camp ring.
- **Traps (#20/D5).** placed like buildings but only on designated non-path tiles; armed traps show a faint hazard
  chevron **only to the owner**; trip → burst effect + log line.
- **Fire & spread (#19).** `F` always-on flame glyphs + a spread front; rain (`ctx.wet`) visibly suppresses; a
  "🔥 пожежа" banner if it reaches a building.
- **Cover / sandbags (D6).** `K` overlay — cover tiles show a shield glyph + %; hero in cover shows "укриття −%"
  near the health doll.

---

## 7. Accessibility & responsiveness checklist (every batch must pass)

- [ ] Every color state paired with icon + number (grep for color-only cues).
- [ ] Every actionable control reachable by keyboard; visible `:focus-visible` amber ring.
- [ ] Tooltips (`title=` in mockup / `explain()` in Godot) on every number and every stateful glyph.
- [ ] Reduced-motion honored (`prefers-reduced-motion`): no essential info conveyed by animation alone.
- [ ] Responsive: at ≤900px the HUD collapses to a single column (grid-areas already switch); panels stack, the
      world stays first-class. Overlays remain togglable.
- [ ] Ukrainian throughout; numbers mono/tabular; no clipping at the 1200px max width.

## 8. Verification protocol (how UX is "run & verified", per user rule)

For each batch's UX, in `docs/ux` via the `ux-hud` launch config (port 8791):
1. `preview_start ux-hud`; open `hud.html`.
2. `preview_snapshot` — assert the new panel/legend text is present and in Ukrainian.
3. `preview_click` the new controls (overlay hotkey buttons, bill steppers, ⚡ toggles) → `preview_snapshot`
   confirms state change.
4. `preview_inspect` the new elements for token compliance (colors/spacing match §1).
5. Canvas overlays: verify via `preview_eval` reading state, and the `toDataURL → file` screenshot workaround
   (canvas `preview_screenshot` is unreliable here) for a visual check.
6. `preview_resize mobile` → confirm single-column collapse still legible.
Only then is the batch's interface complete.
