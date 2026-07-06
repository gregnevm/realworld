# Spec 0005 — UX/UI view-layer architecture (rules, architecture, approach)

> Status: **Batches 0–5 implemented + verified** (2026-07-05) · additive · `main.gd` untouched (only an additive
> `messages_seq` counter added to `sim.gd` per §2.7). The full spine is live under `godot/scripts/ui/`, proven by
> `tests/run_ui_tests.gd` (65 headless tests, incl. the R1/R3/R4/R7/R9/R10 grep tripwires) and a windowed
> `newhud` screenshot (`godot/newhud_shot.png`). All suites green: 119 unit + 152 kernel + 65 UI + 8 smoke.
> Remaining: Batch 6 (port the modals) + Batch 7 (flip default & delete the monolith paths). Original status below.
>
> Status (original): proposed · additive · does not touch `sim.gd` this pass
> Companion to: **specs/0003-mechanics-kernel.md** (the sim kernel — the "5 contracts" this document mirrors) and **docs/ux/design-system.md** + **docs/ux/hud.html** (the LOCKED visual/interaction contract — tokens §1, layout §2, overlays §3, panel/widget vocabulary §4, interaction grammar §5, a11y §7, verification §8).
> This spec is the missing **code architecture for the view layer**. It says HOW the HUD is structured as Godot code so it stays coherent as 30+ mechanics' panels/overlays land. It does **not** restate what the HUD looks like or how it behaves — that is design-system.md's job — nor what the sim exposes — that is the VIEW BINDING SURFACE and spec 0003's job. It cross-references both.

---

## 0. Why this exists (one paragraph)

`main.gd` is a 1158-line `Node2D` god object that owns theme, world nodes, every HUD element, five modals rebuilt imperatively on every toggle, all data-formatting, and all input routing. There is **no view-layer architecture**: design-system.md specifies pixels, spec 0003 specifies the sim, and nothing specifies the GDScript structure between them. Left as-is, `main.gd` becomes a 10k-line monolith as mechanics land. The kernel already solved the identical scaling problem on the sim side — *"~5 abstractions absorb hundreds of mechanics; adding a mechanic never edits the tick loop"* (spec 0003) — by landing a **parallel, additive, independently-tested** layer under `godot/scripts/kernel/` that never touched `sim.gd`, with a documented migration path (§8). **This spec applies that exact discipline to the view.** It defines the view-side analogue of the kernel's 5 contracts, lands them under `godot/scripts/ui/` beside `main.gd`, proves them headlessly in `tests/run_ui_tests.gd`, and migrates the monolith panel-by-panel behind a flag — `main.gd` is not rewritten until the final flip.

### Repo-precedent constraints (verified ground truth — non-negotiable)

These override any "idiomatic Godot" instinct. The kernel established them; the view layer MUST follow them so reviewers read one pattern, not two:

- **Zero `class_name`.** The entire `scripts/` tree has **no** top-level `class_name` (verified). The kernel uses **inner classes** (`class SimSystem extends RefCounted:` inside `systems.gd`) consumed via `const Systems = preload("res://scripts/kernel/systems.gd")` + `Systems.SimSystem`. The view layer uses the identical idiom. `class_name` is **banned** — it is global, load-order-fragile, and cannot be scoped or reset per test. (Reserve for at most zero primitives.)
- **Zero autoloads.** `project.godot` has **no `[autoload]` section** (verified); `GameData` is a `preload`ed const, not an autoload. `Tokens` and the `FeedbackBus` are therefore **preloaded consts / instances owned by `HudRoot` and passed by reference** — never autoload singletons. This keeps every headless test isolated (autoload singletons share state across tests in one `SceneTree`).
- **Widgets ARE Controls.** A widget is a `Control` subclass (built once, `bind()`-mutated), not a `RefCounted` that owns a Control. But **all testable logic** (formatting, enum→state, threshold math) lives in Node-free `RefCounted`/`static` builders so the headless suite can prove it without a window.
- **GDScript-4.7 gotchas** (from spec 0003 experience, carried verbatim): `:=` cannot infer from a Variant (Dictionary field access / `abs()` / untyped returns) — use explicit `: Type` or `absf/absi/floori`; JSON round-trips coerce int→float (compare with `is_equal_approx`, never `== 180`, across a save/load boundary); `RefCounted` cannot collect cycles (any cached cross-ref needs explicit clearing in `_exit_tree()`); every stochastic path takes a seeded `RandomNumberGenerator`; anchoring must use anchors + `grow_*` + explicit `offset_*` with nominal `size = 0` (never `PRESET_TOP_RIGHT + .position`).

---

# 1. ПРАВИЛА (RULES) — the enforceable view-layer laws

These are **code discipline** the architecture *imposes*. They do not restate design-system.md (that owns tokens/layout/grammar). Each is written so `tests/run_ui_tests.gd` (or a review grep) can actually catch a violation. A rule that can't be tested is written as a review-blocking convention and flagged as such.

### R1 — One-way data flow: the sim never imports the UI

No file under `sim.gd`, `session.gd`, `social.gd`, `persistence.gd`, or `kernel/*.gd` may `preload` or textually reference `res://scripts/ui/`. UI reads the sim; the sim has zero knowledge the UI exists (there is no `sim.hud` field, ever).

> **Test `_t_no_back_reference` (Batch 1, permanent tripwire):** grep every sim/kernel/session/persistence/social `.gd` for `res://scripts/ui` → **0 hits**. Verified feasible today (those files have zero UI refs).

### R2 — Panels/Widgets bind; they never rebuild

A `Panel`/`Widget` builds its child Controls **once** in `_build()` (called from `_ready()`), and thereafter only ever `bind(vm)` — which mutates existing children. The monolith's `_toggle_only → _build_*_panel → _clear` (nuke children, rebuild a VBox on every open) pattern is **banned**. Toggling a panel is `visible = on`, never a rebuild.

> **Test `_t_bind_stable_childcount`:** a `Panel` base exposes `rebuild_count` (incremented only inside `_build()`) and `rebind_count`. Instance a panel, `bind()` twice with different data, assert `rebuild_count == 1` and child count unchanged. (This counter is the enforcement; there is **no** content-hash diff gate — see §Rejected.)

### R3 — Tokens-only styling: no inline hex, no literal StyleBox

No `Color.html("…")`, no `Color(r,g,b,a)`, no `StyleBoxFlat.new()` literal, no hardcoded font size anywhere under `ui/` **except** `ui/tokens.gd` and `ui/theme.gd`. Every color is `Tokens.GOOD` / `Tokens.res("wood")` / `Tokens.urgency(state)`; every box/font comes from the `Theme`. This is the single reconciliation point for the documented **color drift** (`C_GOOD "5fd38a"` vs locked `--good #6fae54`; `C_WARN "ffcf5c"` vs `--warn #e0b070`; `C_BAD "ff6b6b"` vs `--crit #e06a5a`; accent `5db0ff` vs amber `e0b070`; dim `8fa3b5` vs `54636f`) — the drifted `C_*` consts are **deleted**, not ported. `world_view.gd`'s own inline `Color.html(...)` terrain colors fold into `Tokens` in the same pass so overlays and the base tilemap share one palette.

> **Test `_t_no_raw_color`:** grep `ui/**` (excluding `tokens.gd`/`theme.gd`) for `Color.html(` / `Color(` / `StyleBoxFlat.new(` → **0 hits**. Grep is syntactic (a computed hex string evades it), so R3 is *also* a review-blocking rule; the grep is a tripwire, not a proof.

### R4 — A panel/overlay is **registered**, never hand-wired into the controller

Adding a mechanic's UI = call `PanelRegistry.register(spec)` / `OverlayRegistry.register(spec)` / `InputVerbs.bind(verb)` from that mechanic's own registrar (an inner class in `ui/mechanics.gd`). `HudRoot` contains **no mechanic names** and **no `preload`/`new()` of a concrete panel** — it mounts whatever the registries hold. The toolbar chips and hotkey table are *generated* from the registries.

> **Test `_t_controller_has_no_mechanic`:** grep `hud_root.gd` for `raid|convoy|capsule|social|craft|power|research|stock|logistics` → **0 hits**. And: `HudRoot` mounts a registered fake panel without referencing it by type.

### R5 — Every displayed number carries its `explain()` breakdown

Any `StatRow`/`NeedBar`/`Gauge` whose value is an explainable stat is bound `{value, explain, state}` where `value` and `explain` come from the **same source** (`StatWorker.value(ctx)` / `StatWorker.explain(ctx)` once the kernel is wired into `sim.update` — spec 0003 §8). The widget shows `value` and puts `explain` in `tooltip_text`. One-truth-per-number (design-system §0.1) becomes **view law**. Until the kernel lands, the ViewModel binds the legacy getter (`melee_damage`/`gather_time`) with a **placeholder explain of the same shape**, so the swap is drop-in.

> **Test `_t_stat_has_explain`:** a `_stats_slice` entry has both `value` and `explain` keys and `explain` is a non-empty String. (Shape-only until §8 lands — do **not** hard-assert the breakdown text yet.)

### R6 — Spatial state is an `Overlay`, never a coordinate list in a panel

Any mechanic with per-tile state (temperature, light, roof, power, grow, stockpile, fire, cover) MUST register an `Overlay` keyed to its **locked** hotkey (design-system §3: R/T/L/P/G/Z/F/K/M) with a legend row + toolbar chip. A list of tile coordinates in a panel is forbidden. A summary panel is optional and additional.

> Enforced by the `OverlayRegistry` contract (a cell-keyed payload has nowhere else to plug in) + review. Test: `OverlayRegistry.register` asserts the spec supplies `(renderer, legend_rows, chip_label, hotkey)` or fails.

### R7 — Resize-safe anchoring goes through `Widget.pin_*`

The learned-bug recipe (anchors + `grow_horizontal/grow_vertical` + explicit `offset_*`, nominal `size = 0`, let `custom_minimum_size` drive extent) is encapsulated **once** in `Widget.pin_top_left / pin_top_right / pin_bottom_left / pin_center`. Raw `Control.position =` and bare `set_anchors_preset(PRESET_TOP_RIGHT)` in a panel body are banned; magic center-offsets (`Vector2(-190,-160)`) are deleted in favour of `pin_center()`.

> **Test `_t_no_raw_anchor`:** grep `ui/panels.gd` + `ui/widgets.gd` + `ui/overlays.gd` for `.position =` / `PRESET_TOP_RIGHT` → **0 hits**. *Note: resize-safety itself (does the rect stay on-screen after a viewport resize) is **not** provable headlessly — Godot may not run a real layout pass under `--headless`. That check belongs exclusively to the live `ux-hud` `preview_resize` gate (§Approach).*

### R8 — Slices are pure value data (no live object refs, no closures over the sim)

A `Snapshot` / ViewModel slice may contain only ids, enums (`StringName`), numbers, and Strings. It may **not** hold a live `sim.player`, an enemy ref (`player.action.target`), a `Thing`, or a `Callable` that captures the sim. Copy primitives; discard render-only refs (enemy positions) the same frame. This simultaneously satisfies one-way flow, prevents `RefCounted` cycle leaks, and is what makes the snapshot safely immutable.

> **Test `_t_slice_is_value_data`:** for each slice builder, walk the returned Dictionary/Array recursively and assert every leaf `typeof()` ∈ {INT, FLOAT, STRING, STRING_NAME, BOOL} (or nested Dict/Array of same). Catches the closure/enemy-ref footgun that a `sim.`-token grep cannot.

### R9 — All state change routes through a verb; only the router calls sim commands

A Control's `pressed`/click handler emits an `intent(verb, args)` signal. The **only** node that translates an intent into a sim command (`try_build`, `demolish`, `craft_item`, `dispatch_convoy`, `try_launch_capsule`, `order_move`, …) is the `InputController`. No panel calls a sim mutator directly.

> **Test `_t_commands_only_in_router`:** grep `ui/panels.gd` + `ui/widgets.gd` for the sim command names (VIEW BINDING SURFACE §12) → **0 hits**; they appear only under `ui/input_*`.

### R10 — Feedback is subscribe-only; the sim's strings are overridable defaults

Panels/widgets do not read `sim.messages` / `sim.banner` / `sim.flash_msg`. Exactly one adapter — `FeedbackBus` — drains those four push channels (VIEW BINDING SURFACE §13) each frame and re-emits **structured** `{id, cls, params}` events; widgets subscribe. New user-facing wording lives in `ui/format.gd` (Ukrainian, keyed by event id). The sim's baked strings (`phase_name()`, `region_display()`, `inspect()`, `explain()`) are consumed as *default* strings the view may override — **no new Ukrainian is authored in `sim.gd`**.

> **Test `_t_feedback_single_adapter`:** grep `ui/**` (excluding `feedback_bus.gd`) for `.messages` / `.banner` / `.flash_msg` / `.flash_t` → **0 hits**.

### R11 — Enum-not-string; number + icon + color, never color alone

The snapshot carries **enums** (`phase: &"night"`, `weather: &"rain"`, `stance: &"hostile"`, `urgency: &"warn"`), never the sim's pre-baked `"☀ день"`. The view maps enum→color/label at **one** site (`Tokens.urgency()` / `ui/format.gd`). Every state widget renders color **and** an icon **and** a number (design-system §0 colorblind-safety).

> **Test `_t_state_widget_triplet`:** each state widget exposes non-empty `icon` and `value` alongside its state color.

### R12 — Keyboard-first; determinism visible

Every panel/overlay hotkey is **registration metadata** on its spec, not a `switch` in `_unhandled_input` — the router builds the key table from the registries (so the design-system §5 grammar is data). Any overlay sampling stochastic env (weather tint) reads the **ctx value written by a kernel system**, never calls `climate.weather(...)` with an ad-hoc rng (would desync). The world-state fingerprint (`session.chain_head()`) and region seed (`sim.region_seed()`) are surfaced in the TopBar per design-system §0 "determinism visible".

> Enforced by the `InputVerbs` table being data + review; the rng rule by convention (an overlay's `draw` receives `snap.env`, never a climate provider).

---

# 2. АРХІТЕКТУРНИЙ ДИЗАЙН (ARCHITECTURE)

## 2.1 The view's 6 contracts (mirror of the kernel's 5)

The kernel absorbs mechanics with `Def`/`ThingComp`/`StatPart`/`SimSystem`/`Balance`. The view gets six contracts, each an inner class in a namespace file under `ui/`, each consumed via `preload`. The mapping is the north star — a reviewer who knows the kernel reads the view instantly:

| Kernel contract (`kernel/*.gd`) | View contract (`ui/*.gd`) | Responsibility |
|---|---|---|
| `Def` / `DefDatabase` | **`Tokens`** + **`Theme`** (`ui/tokens.gd`, `ui/theme.gd`) | The single source of colors/boxes/fonts. Reconciles the color drift once. |
| `SimSystem` + `SystemRegistry` | **`Panel`** (base: `ui/panel.gd`; concrete inner classes: `ui/panels.gd`) + **`PanelRegistry`** (`ui/panel_registry.gd`) | A dock/modal unit built once, `bind(vm)`ed each frame; registry is `add()`+sort-by-priority+`get()`+one dispatch — a near-verbatim copy of `SystemRegistry`. |
| (spatial half of systems) | **`Overlay`** (base: `ui/overlay.gd`; concrete inner classes: `ui/overlays.gd`) + **`OverlayRegistry`** (`ui/overlay_registry.gd`) | A viewport tile-layer keyed to a locked hotkey; radio-exclusive primary + always-on markers. |
| `ThingComp` | **`Widget`** (base: `ui/widget.gd`; concrete inner classes: `ui/widgets.gd`) | The finite reusable primitive vocabulary (need bar / stat row / gauge / doll / bill row / tech node / card / slot / chip). |
| `Balance.assess()` (immutable read) | **`HudModel.snapshot()`** (`ui/hud_model.gd`) | Pure, Node-free, headless-testable read of the whole sim → one immutable presentation dict per frame. The `assess()` analogue. |
| `Balance.tick()` incidents | **`FeedbackBus`** (`ui/feedback_bus.gd`) | Ingests the four sim leak channels → typed `{id,cls,params}` events; view owns toast lifetime. |
| sim command methods (§12) | **`InputVerbs` + `InputController`** (`ui/input_verbs.gd`, `ui/input_controller.gd`) | The design-system §5 grammar as data; the ONLY place sim commands are called. |

Underneath sits **`HudRoot`** — the thin controller analogue of `sim.update()`: advance frame → build snapshot → dispatch to registries. It contains no mechanic logic (R4).

## 2.2 Data-flow diagram (strictly one direction, per frame)

```
        ┌──────────── sim.gd / session / social / kernel (NEVER references ui/) ────────────┐
        │   state Dicts (§1–10)        commands (§12)             push channels (§13)        │
        └────┬──────────────────────────────▲──────────────────────────┬────────────────────┘
   poll(read)│                               │ call (via router only)   │ drain
        ┌────▼──────────────┐          ┌──────┴────────────┐      ┌──────▼──────────────┐
        │ HudModel.snapshot │          │ InputController   │◀─────│ FeedbackBus.ingest  │
        │  (pure, Node-free)│          │  (verb → command) │intent└──────┬──────────────┘
        └────┬──────────────┘          └──────▲────────────┘             │ emit {id,cls,params}
   Snapshot  │ bind(vm)                        │ intent(verb,args)         ▼
        ┌────▼─────────────────────────────┐   │                    FeedbackBus signals
        │ HudRoot._process:                │───┘                          │
        │   snap = HudModel.snapshot(...)  │                              ▼
        │   feedback.ingest(sim, dt)       │        Banner / Flash / Toast / Feed widgets
        │   panels.bind_visible(snap)      │        (subscribe once; own their own timers)
        │   overlays.draw_active(snap)     │
        └──────────────────────────────────┘
   OverlayHost (world-space Node2D, child of camera) ← OverlayRegistry.active_and_markers(snap)
```

The sim half has **no arrow pointing back** into `ui/` — that is R1 made visual, the exact mirror of "the kernel sim never calls the AI brain, only `assess()`/`tick()`."

## 2.3 Node / scene tree (CanvasLayer discipline; overlays in world space)

```
NewHudMain (Node2D)                    ← NEW entry scene (Batch 5); main.gd untouched until Batch 7
├─ WorldRoot (Node2D)                  ← world camera space
│  ├─ WorldView (Node2D, _draw)        ← existing tilemap/entity renderer (edited ~5 lines, §2.9)
│  ├─ OverlayHost (Node2D, _draw)      ← OverlayRegistry draws here — WORLD SPACE, pans/zooms free
│  └─ Camera2D
├─ HudLayer (CanvasLayer, layer=10)
│  └─ HudRoot (Control)                ← the 232|1fr|250 grid frame (design-system §2 zones)
│     ├─ TopBar   ├─ LeftDock (VBox of Panel)
│     ├─ RightDock(VBox of Panel)  ├─ ActionBar (palette + Feed)
│     └─ LegendBox (bottom-left of viewport; grows per active overlay)
├─ ModalLayer (CanvasLayer, layer=20) ← Logistics(M)/Equipment(I)/Capsule(C)/Social(F)/Help(H)
└─ ScreenLayer (CanvasLayer, layer=30)← Spawn / Death full-screen states
```

**Overlay seam decision (resolves the shared weakness of the candidate proposals):** overlays draw in a **separate world-space `OverlayHost` `Node2D`** that owns its own `_draw()` and pulls from `OverlayRegistry` — they do **not** draw into `WorldView`'s canvas item, because that would make the sim-facing `WorldView` reach *up* into `ui/` (an R1 violation). Because `OverlayHost` is a child of the world camera, it pans/zooms for free. To avoid cull-math drift between the base tilemap and overlays, `WorldView`'s existing cull-rect computation is extracted into a shared pure helper both consume (see §2.9). Dock panels are never parented under `WorldRoot`.

## 2.4 `Tokens` / `Theme` (the Def analogue) — `ui/tokens.gd`, `ui/theme.gd`

```gdscript
# ui/tokens.gd — the LOCKED §1 palette as one source of truth (R3). Node-free.
# Preloaded const, NOT an autoload. Reconciles the drifted C_* consts here, once.
extends RefCounted

const BG      := Color.html("0e1216")
const PANEL   := Color.html("151b21")
const PANEL2  := Color.html("1b232b")
const LINE    := Color.html("26313b")
const LINE2   := Color.html("33414d")
const INK     := Color.html("c9d4dc")
const MUT     := Color.html("7c8b97")
const DIM     := Color.html("54636f")
const GOOD    := Color.html("6fae54")   # was C_GOOD "5fd38a"  — DRIFT FIXED
const WARN    := Color.html("e0b070")   # was C_WARN "ffcf5c"  — DRIFT FIXED
const CRIT    := Color.html("e06a5a")   # was C_BAD  "ff6b6b"  — DRIFT FIXED
const TEAL    := Color.html("86d0d6")
const COMP    := Color.html("b58cff")
const BLOOD   := Color.html("b23b34")
const R       := 8                 # corner radius
# NOTE: keys are the runtime resource ids in GameData.RES_ORDER. design-system §1's
# `--comp` dot token is shorthand for the runtime id `components` (used here + in data.gd).
const RES := {                     # resource dot colors (design-system §1)
	"wood":  Color.html("c08a4a"), "stone":  Color.html("9aa3ab"), "food":   Color.html("e06a5a"),
	"scrap": Color.html("86d0d6"), "planks": Color.html("e0b070"), "components": Color.html("b58cff"),
}

static func res(id: String) -> Color:
	return RES.get(id, INK)

# The ONE enum→color site (R11). Snapshot carries the enum; the view owns the color.
static func urgency(state: StringName) -> Color:
	match state:
		&"good": return GOOD
		&"warn": return WARN
		&"crit": return CRIT
		_:       return INK
```

```gdscript
# ui/theme.gd — builds ONE Godot Theme resource programmatically from Tokens. Node-free build fn.
# Type variations style each widget by theme_type_variation, not inline StyleBox
# (replaces _sb_panel / _sb_bar / _mk_modal and every C_* const in main.gd).
extends RefCounted
const Tokens = preload("res://scripts/ui/tokens.gd")

static func build() -> Theme:
	var t := Theme.new()
	# A theme_type_variation only resolves if the variation name is (1) REGISTERED as a
	# variation of a built-in base type via set_type_variation, and (2) has its own styleboxes.
	# Styling the raw "PanelContainer" would restyle ALL PanelContainers but leave the
	# `RwPanel` variation empty, so `theme_type_variation = &"RwPanel"` panels fall back to
	# default and render unstyled. Register the variation, THEN set the box on the variation name.
	t.set_type_variation(&"RwPanel", &"PanelContainer")
	t.set_stylebox("panel", &"RwPanel", _sb(Tokens.PANEL, Tokens.LINE, Tokens.R, 14))
	# Same two-step for every variation the widgets ask for:
	#   set_type_variation(&"RwPanelRaised", &"PanelContainer") + its stylebox   (modal)
	#   set_type_variation(&"RwBar", &"PanelContainer")         + its stylebox   (need track)
	#   set_type_variation(&"MonoValue", &"Label")              + its font/size  (numbers)
	# Fonts: bundle a --sans + --mono FontFile under ui/theme/fonts/. MonoValue points every
	# number at the bundled --mono FontFile; tabular alignment depends on that font shipping
	# tabular default figures (verify the chosen TTF), NOT on any Theme numeric-variant setting —
	# Godot exposes no CSS `tabular-nums` / `font-variant-numeric` toggle via Theme.
	return t
```

> **Locked-h2 fidelity gap (explicit decision, per design-system §1):** Godot `Label` has **no CSS `letter-spacing`**, so the locked `h2` (10px, `.16em`, uppercase, `--mut`) cannot be reproduced by a stock `Label`. Resolution: ship a small custom-draw **`H2Header` widget** (or a `LabelSettings` with baked tracking) rather than pretending a Theme value covers it. This is the one place the Godot port cannot be a pure Theme lookup.

## 2.5 `HudModel.snapshot()` — the ViewModel (the `assess()` analogue) — `ui/hud_model.gd`

Pure and Node-free: `HudModel` never `extends Node`, never calls `get_node`/`queue_redraw`/`Color.html`/`add_child`. It is the **single** place that reaches through `session.sim` (per the VIEW BINDING SURFACE). It builds one immutable presentation dict, structured by dock/panel, from **read**/**derived** surfaces only (§1–11). It maps raw fields to enums itself (never binds `sim.phase_name()`), and holds only value data (R8).

```gdscript
# ui/hud_model.gd — PURE. extends RefCounted. The centerpiece.
extends RefCounted
const Fmt = preload("res://scripts/ui/format.gd")   # pure Ukrainian/number formatters

# `world`/`ctx` are the same shapes the kernel already consumes; passed in by HudRoot.
# `balance` is a Balance director constructed ONCE by HudRoot and reused (never new() per frame).
static func snapshot(session, world: Dictionary, ctx: Dictionary, balance) -> Dictionary:
	if session == null or session.sim == null:
		return {"alive": false}
	var sim = session.sim
	var p = sim.player
	return {
		"alive":     true,
		"dead":      bool(sim.dead),
		"region":    _region_slice(sim, session),   # {name,lat,lon,biome,source,seed,chain}
		"clock":     _clock_slice(sim),              # {day, hhmm, phase:&"night", daylight}
		"env":       _env_slice(ctx),                # {temp_c, weather:&"rain", light, indoor}
		"vitals":    _vitals_slice(p, sim),          # need bars w/ urgency enum + carry
		"stats":     _stats_slice(sim, ctx),         # {melee:{value,explain}, …}  (R5)
		"stock":     _stock_slice(sim),              # rows in RES_ORDER + fill
		"build":     _build_slice(sim),              # palette slots: afford/selected/locked
		"threat":    _threat_slice(world, ctx, balance),
		"logistics": _logistics_slice(sim, session),
		"equipment": _equipment_slice(sim),
		"capsule":   _capsule_slice(sim, session),
		"social":    _social_slice(sim),
		"raid":      _raid_slice(sim),               # {state:&"incoming"/…, wave, faction}
	}

static func _clock_slice(sim) -> Dictionary:
	var f: float = float(sim.time.frac)              # explicit type: := can't infer off Variant
	return {"day": int(sim.time.day), "hhmm": Fmt.hhmm(f),
			"phase": Fmt.phase_enum(f), "daylight": float(sim.daylight())}

static func _need_row(id: StringName, label_key: StringName, v: float) -> Dictionary:
	var vv: float = clampf(v, 0.0, 100.0)
	var state: StringName = (&"good" if vv > 50.0 else (&"warn" if vv > 25.0 else &"crit"))
	return {"id": id, "label_key": label_key, "pct": int(vv), "state": state}  # enum, not Color

static func _vitals_slice(p, sim) -> Dictionary:
	return {"bars": [
			_need_row(&"hp",     &"hp",     float(p.hp)),
			_need_row(&"hunger", &"hunger", float(p.hunger)),
			_need_row(&"rest",   &"rest",   float(p.rest))],
		"sleeping": bool(p.sleeping),
		"carry": {"cur": int(sim.carry_total()), "cap": int(p.carry_cap)}}

static func _stats_slice(sim, ctx: Dictionary) -> Dictionary:
	# ONE-TRUTH-PER-NUMBER (R5). Until kernel §8 lands, value = legacy getter, explain = placeholder
	# whose KEYS match {value, explain} so the widget API never changes. NOTE this is NOT a pure
	# source substitution: StatWorker.value(ctx)/.explain(ctx) REQUIRE a hero ctx (capacities +
	# quality_mult), which does not exist until spec 0003 §8 wires the hero HealthTracker into
	# sim.update. So the seam upgrade is gated on that ctx existing — not merely on the widget staying stable.
	return {"melee": {"value": float(sim.melee_damage()),
					  "explain": Fmt.melee_explain_placeholder(sim)}}
```

**Binding / change-detection.** State flows sim → `snapshot()` → `HudRoot` → `panel.bind(vm)` once per frame. There is **no content-hash diff gate** (see §Rejected — it is unsound in GDScript). The only optimization is **bind visible panels only**: `PanelRegistry.bind_visible(snap)` skips hidden panels (mirrors `SystemRegistry`'s per-system dispatch; a hidden modal costs nothing). If profiling at scale later shows churn, add an explicit per-slice dirty flag driven off the sim — never a hash. At `MAP_N = 56` a plain relabel of visible panels is cheap.

**Travel = full re-bind.** `session.travel_to()` swaps sim contents wholesale; `HudRoot` re-snapshots and re-binds after travel — no incremental patching — and resets `FeedbackBus` cursors (§2.7) so the new region's log is not re-emitted or dropped.

## 2.6 `Panel` + `PanelRegistry` — the `SimSystem`/`SystemRegistry` analogue

**Cross-file inheritance decision (load-bearing — chosen to match the kernel idiom exactly, keeping zero `class_name`).** GDScript-4.7 cannot subclass an inner class that lives in *another* file from a standalone file's top-level `extends`: `extends` must be the first statement (only comments/`@tool`/`@icon`/`class_name` may precede it), so no `const Base = preload(...)` can be in scope before it, and the string form `extends "res://…gd".Inner` is **not valid syntax** (a path-string `extends` binds the file's *top-level* class and cannot be suffixed with `.Inner`). This is exactly why the kernel never does it: **every** kernel subclass of an inner class is *itself* an inner class in a file that has `const Systems = preload(...)` above it in scope (e.g. `environment.gd`: `const Systems = preload(...)` then `class TemperatureSystem extends Systems.SimSystem:`). The view layer follows that verbatim: **the base is an inner class, and every concrete panel/widget/overlay is ALSO an inner class** in a namespace file that preloads the base. Concrete panels are `Panels.StockPanel`, not their own top-level files.

```gdscript
# ui/panel.gd — base of every dock/modal panel. Inner class, preloaded (no class_name).
extends RefCounted

class Panel extends PanelContainer:
	signal intent(verb: StringName, args: Dictionary)   # bubbles to InputController (R9)
	var panel_id: StringName = &"panel"
	var dock: int = 0                # LEFT/RIGHT/TOP/BAR/MODAL (design-system §2 zones)
	var priority: int = 0            # order within a dock (mirrors SimSystem.priority)
	var hotkey: int = 0              # KEY_* toggle, 0 = none (metadata, not a switch — R12)
	var default_open := false
	var rebuild_count := 0           # R2 enforcement: incremented ONLY in build_once()
	var rebind_count := 0

	func _ready() -> void:
		theme_type_variation = &"RwPanel"
		build_once()

	func build_once() -> void:       # idempotent guard so a manual test call + a real tree-entry
		if rebuild_count > 0: return # can't double-fire _build (see §5.3 headless note)
		_build()

	func _build() -> void:           # override: create child Widgets ONCE. rebuild_count += 1 here.
		rebuild_count += 1
	func bind(_vm: Dictionary) -> void:  # override: set values on existing children only.
		rebind_count += 1
```

```gdscript
# ui/panel_registry.gd — near-verbatim copy of kernel SystemRegistry (add/sort/get/dispatch).
extends RefCounted

class PanelRegistry extends RefCounted:
	var panels: Array = []
	func register(p) -> void:
		panels.append(p)
		panels.sort_custom(func(a, b): return a.priority < b.priority)   # same idiom as SystemRegistry.add
	func get_panel(id: StringName):
		for p in panels:
			if p.panel_id == id: return p
		return null
	func by_dock(d: int) -> Array:
		return panels.filter(func(p): return p.dock == d)
	func bind_visible(snap: Dictionary) -> void:                          # the view's tick_all
		for p in panels:
			if is_instance_valid(p) and p.visible:
				p.bind(snap)
	func toggle(id: StringName) -> void:                                  # show/hide ONLY — never rebuild (R2)
		var p = get_panel(id)
		if p != null: p.visible = not p.visible
```

A concrete panel — the proof slice — reads a slice, sets values, never touches `sim`. It is an **inner class in `ui/panels.gd`** that preloads the base and extends its inner class, the exact two-line `preload`+`extend` idiom `environment.gd` uses for `Systems.SimSystem` (never a standalone-file `extends` at another file's inner class — that does not parse):

```gdscript
# ui/panels.gd — namespace file for concrete dock/modal panels (all inner classes).
extends RefCounted
const PanelBase = preload("res://scripts/ui/panel.gd")     # in scope BEFORE any inner-class extends
const Widgets   = preload("res://scripts/ui/widgets.gd")   # concrete widgets namespace

class StockPanel extends PanelBase.Panel:                   # == environment.gd's `extends Systems.SimSystem`
	var _rows: Dictionary = {}   # res -> StatRow instance
	func _build() -> void:
		rebuild_count += 1
		for res in GameData.RES_ORDER:                     # yields the runtime id "components", etc.
			var row = Widgets.StatRow.new(); row.set_glyph_res(res)
			_rows[res] = row; add_child(row)
	func bind(vm: Dictionary) -> void:
		rebind_count += 1
		var stock: Dictionary = vm.stock.rows
		for res in _rows:
			_rows[res].set_value(int(stock.get(res, 0)))    # tabular mono via the MonoValue font

	# class VitalsPanel extends PanelBase.Panel: …  ← every concrete panel is another inner class here
```

`HudRoot` mounts `Panels.StockPanel.new()` via the registry; it is never its own top-level file.

## 2.7 `FeedbackBus` — the incident-channel analogue — `ui/feedback_bus.gd`

The ONE adapter that quarantines the sim's baked Ukrainian strings (VIEW BINDING SURFACE §13). It ingests `banner`, `flash_msg`/`flash_t`, `messages[]`, and command-return `msg`, and re-emits structured `{id, cls, params}` events. **During migration** it *reads* `sim.flash_t > 0` as the gate (the sim still decays that timer until Batch 7) to avoid a two-clock double-decay; it takes true lifetime ownership only at the final flip (R10).

**The feed channel drains an append-only tail, NOT a stable index.** The sim's `_log()` (sim.gd) is a **sliding window**: `messages.append(...)` then `if messages.size() > 40: messages.remove_at(0)`. A monotonic index cursor (`while _feed_cursor < sim.messages.size()`) is therefore **broken**: once 40 lifetime messages are logged, `size()` is pinned at 40 and the guard never fires again (the feed permanently stops), and every `remove_at(0)` before the cap shifts survivors down one index so a stale cursor points at the wrong entry (skips some, re-emits others). The contract is a **monotonic sequence counter**, not an index: the sim exposes an append counter `messages_seq: int` (incremented in `_log`, **never** reset by the 40-cap trim), and the bus tracks `_last_seq`, emitting only entries whose seq is newer. This survives the trim boundary with no gap or duplicate.

```gdscript
# ui/feedback_bus.gd — instance owned by HudRoot, passed by reference (NOT an autoload).
extends RefCounted

class FeedbackBus extends RefCounted:
	signal banner(evt: Dictionary)   # {status:StringName raid_incoming/raid_active/none, params}
	signal flash(evt: Dictionary)    # {id, cls, params}  transient toast
	signal feed(evt: Dictionary)     # {cls, text}         event-log card
	var _last_banner := ""
	var _last_seq: int = 0           # monotonic; survives the sim's 40-message sliding-window trim
	var _last_flash := ""

	func ingest(sim, _dt: float) -> void:
		if sim == null: return
		if sim.banner != _last_banner:
			banner.emit({"status": _banner_status(sim.banner), "params": {"text": sim.banner}})
			_last_banner = sim.banner
		if sim.flash_t > 0.0 and sim.flash_msg != _last_flash:
			flash.emit({"id": &"blocked", "cls": "warn", "params": {"text": sim.flash_msg}})
			_last_flash = sim.flash_msg
		# Drain by sequence, not index: emit every message whose append-seq is newer than _last_seq.
		# messages_seq is the count of lifetime appends; the tail we haven't seen is the last
		# (messages_seq - _last_seq) entries of the (trimmed, <=40) messages array.
		var seq: int = int(sim.messages_seq)
		if seq > _last_seq:
			var pending: int = mini(seq - _last_seq, sim.messages.size())
			var start: int = sim.messages.size() - pending
			for i in range(start, sim.messages.size()):
				var m = sim.messages[i]
				feed.emit({"cls": m.cls, "text": m.text})
			_last_seq = seq

	func reset_cursors() -> void:    # called by HudRoot on session.travel_to (§2.5)
		_last_seq = 0; _last_banner = ""; _last_flash = ""
```

> **Sim seam (additive, does not change sim wording — R10-compatible):** the only sim edit this needs is a `messages_seq: int` counter incremented in `_log` (never reset by the trim). It exposes no new Ukrainian and touches no string. If the counter is unavailable during migration, the bus can instead compare against the last-emitted entry and emit only newly-appended item(s) bounded by the known trim — but the seq counter is the clean form.

`BannerWidget`/`FlashWidget`/`FeedWidget` connect once in `_ready()` and own their own display/fade timers — `flash_t` moves out of the sim conceptually. Because a signal connection makes the `FeedbackBus` (a `RefCounted` owned by `HudRoot`) hold each subscriber's `Callable`, **subscriber widgets disconnect from the bus in `_exit_tree()`** (per the §0 gotcha "any cached cross-ref needs explicit clearing in `_exit_tree()`" and R8's cycle-leak guard), so no held `Callable` outlives the freed `Control`. Equivalently, `HudRoot` rebuilds the bus on `session.travel_to` alongside `reset_cursors()`. A headless assertion checks `FeedbackBus` has zero connections after its subscribers are freed.

## 2.8 `Overlay` + `OverlayRegistry` — the spatial half (§3, the biggest gap)

`main.gd` has **no overlay layer at all**. This is net-new, hence purely additive.

```gdscript
# ui/overlay.gd
extends RefCounted
class Overlay extends RefCounted:
	var overlay_id: StringName = &"overlay"
	var hotkey: int = 0                 # KEY_R/T/L/P/G/Z/F/K/M (design-system §3, LOCKED)
	var radio := true                   # false = always-on marker (fire F, cover K)
	var legend_rows: Array = []         # [{swatch:Color, icon:String, label:String}] Ukrainian
	func draw_overlay(host: CanvasItem, snap: Dictionary, cull: Dictionary) -> void: pass
```

```gdscript
# ui/overlay_registry.gd
extends RefCounted
class OverlayRegistry extends RefCounted:
	var overlays: Array = []
	var active: StringName = &""        # the one radio overlay currently on
	var _markers: Dictionary = {}       # always-on toggles
	func register(o) -> void:
		assert(o.hotkey != 0 and not o.legend_rows.is_empty())   # R6 contract
		overlays.append(o)
	func toggle(id: StringName) -> void:
		var o = _get(id)
		if o == null: return
		if o.radio: active = (&"" if active == id else id)       # radio exclusivity
		else: _markers[id] = not _markers.get(id, false)
	func active_and_markers() -> Array:                          # 1 radio + all always-on
		return overlays.filter(func(o): return (o.radio and o.overlay_id == active)
											or (not o.radio and _markers.get(o.overlay_id, false)))
	func legend_for_active() -> Array: ...                       # feeds LegendBox widgets
```

Concrete overlays follow the §2.6 rule: the `Overlay` base is an inner class in `ui/overlay.gd`, and every concrete overlay is **also an inner class** in `ui/overlays.gd` (which preloads the base) — `class LightOverlay extends OverlayBase.Overlay:` after `const OverlayBase = preload("res://scripts/ui/overlay.gd")`, referenced as `Overlays.LightOverlay`. `OverlayHost._draw()` computes the shared cull rect (§2.9), then iterates `active_and_markers()` → `draw_overlay(self, snap, cull)`. Toolbar chips + legend rows are generated from the registry — never hand-listed. **A spatial mechanic ships an `Overlay` inner class + `register(...)` — no HUD edit** (R6).

## 2.9 The shared cull-rect helper (resolving the overlay/tilemap drift risk)

`WorldView._draw()` currently derives its visible-tile bounds (`x0/y0/x1/y1` from camera zoom, `TILE=28`) as private locals. To keep the base tilemap and every overlay in lockstep, extract that computation into a pure helper both call:

```gdscript
# ui/view_geom.gd — PURE. No Node access; takes the numbers, returns the rect.
extends RefCounted
static func cull_rect(cam_pos: Vector2, zoom: Vector2, vp_size: Vector2, n: int, tile: int) -> Dictionary:
	# returns {x0,y0,x1,y1} clamped to [0,n) — the single definition of "visible tiles"
	...
```

`WorldView._draw()` is edited (~5 lines, the ONLY existing-code touch) to call `ViewGeom.cull_rect(...)` and `OverlayHost._draw()` calls the same. This is stated honestly rather than pretending overlays are non-invasive. `world_view.gd`'s inline terrain `Color.html(...)` also fold into `Tokens` in this pass (R3).

## 2.10 `InputVerbs` + `InputController` — the §5 grammar as data — `ui/input_verbs.gd`, `ui/input_controller.gd`

The design-system §5 verb table (order / zone / select-slot / cancel / inspect / overlay / help) becomes a registry, not the `_unhandled_input` switch. A verb is the only thing allowed to call a sim mutator (R9).

```gdscript
# ui/input_controller.gd — the ONLY node that calls sim commands.
extends RefCounted
class InputController extends RefCounted:
	var _verbs: Dictionary = {}                     # StringName -> Callable(session, args)
	func bind(verb: StringName, fn: Callable) -> void: _verbs[verb] = fn
	func dispatch(verb: StringName, args: Dictionary, session) -> void:
		if _verbs.has(verb): _verbs[verb].call(session, args)
	# registrations (data, not a switch — replaces _unhandled_input/_handle_click):
	#   bind(&"order_move", func(s,a): s.sim.order_move(a.x, a.y))
	#   bind(&"build",      func(s,a): s.sim.try_build(a.kind, a.x, a.y))
	#   bind(&"launch",     func(s,a): var r = s.sim.try_launch_capsule(a.lat,a.lon,a.name)
	#                                  if r.ok: s.travel_to(a.lat,a.lon,a.name))
```

Hotkeys for panels (M/I/C/F/H) and overlays (R/T/L/…) are **metadata** on their specs; `_unhandled_key_input` is one table lookup built from the registries (R12).

## 2.11 Widget primitive library (the finite vocabulary, 1:1 with the mockup)

Each is a `Control` subclass (R2), built once, styled by a `theme_type_variation` (R3), pinned via `Widget.pin_*` (R7). Following the same cross-file rule as §2.6, the `Widget` base is an inner class in `ui/widget.gd` and every concrete widget is **also an inner class** in `ui/widgets.gd`, which preloads the base — `class StatRow extends WidgetBase.Widget:` after `const WidgetBase = preload("res://scripts/ui/widget.gd")`. Concrete widgets are referenced as `Widgets.StatRow`, never their own top-level `extends "…".Widget` files (which do not parse). Names are 1:1 with design-system.md §4 / hud.html so parity is checkable element-by-element (§Approach). Introducing a new primitive requires adding it to design-system §4 **first** (the doc gate).

| Widget | mockup class | binds |
|---|---|---|
| `NeedBar` | `.need` | `bind(cur01, pct, state, icon, label)` — color+icon+number (R11) |
| `StatRow` | `.stock .r` | `bind(glyph, label, value, explain)` — explain → tooltip (R5) |
| `Gauge` | `.gauge`/`.phases` | `bind(value, phases)` — segmented meter + phase labels |
| `HealthDoll` | `.doll` | `bind(hediffs, caps)` — `_draw` paper-doll, per-part tint + capacities |
| `BillRow` | new §5.3 | `bind(recipe, target, eta, missing)` — do-until-N stepper |
| `TechNode` | new §5.3 | `bind(title, progress, prereqs, locked)` |
| `Card` | `.card .t-*` | `bind(cls, text)` — feed item, left-border by cls |
| `BuildSlot` | `.slot .sel/.no` | `bind(glyph, num, sel, locked)` |
| `OverlayChip` | `.ov-chip .on` | `bind(label, key, on)` |
| `BannerWidget`/`FlashWidget`/`FeedWidget` | `.banner`/toast/`.feed` | subscribe `FeedbackBus`, own timers |
| `H2Header` | panel `h2` | custom-draw (the letter-spacing gap, §2.4) |

`Widget.pin_*` (R7), encapsulating the verified anchoring recipe once:

```gdscript
# ui/widget.gd
extends RefCounted
class Widget extends Control:
	func bind(_vm) -> void: pass
	static func pin_top_right(c: Control, ox := 12.0, oy := 10.0) -> void:
		c.set_anchors_preset(Control.PRESET_TOP_RIGHT, false)
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		c.grow_vertical   = Control.GROW_DIRECTION_END
		c.offset_left = -ox; c.offset_right = -ox; c.offset_top = oy; c.offset_bottom = oy
		c.size = Vector2.ZERO                 # nominal 0; custom_minimum_size drives extent
	static func pin_top_left(c, ox := 12.0, oy := 10.0) -> void: ...
	static func pin_bottom_left(c, ox := 12.0, oy := 70.0) -> void: ...
	static func pin_center(c) -> void:
		c.set_anchors_preset(Control.PRESET_CENTER, false)
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		c.grow_vertical   = Control.GROW_DIRECTION_BOTH   # deletes magic offsets like (-190,-160)
```

## 2.12 "Adding mechanic X's UI = register these, edit nothing else"

The whole point of the layer. For a new mechanic, author a registrar inner class in `ui/mechanics.gd` that registers against the surfaces below and edits **no controller**:

| Need | Register / add | File you write | Controller edit? |
|---|---|---|---|
| A dock/modal summary | `PanelRegistry.register(Panels.XPanel.new())` | add inner class to `ui/panels.gd` | **none** |
| A per-tile spatial view | `OverlayRegistry.register(Overlays.XOverlay.new())` (hotkey from §3) | add inner class to `ui/overlays.gd` | **none** |
| New presentation data | add an `_x_slice()` to `HudModel` | `ui/hud_model.gd` | none (additive fn) |
| A player action | `InputVerbs.bind(&"x", fn)` | `ui/input_verbs.gd` | none |
| Feedback event | `FeedbackBus.emit({id:&"x",…})` + subscribe | (bus + widget) | none |
| A genuinely new visual primitive | add to design-system §4, then a `Widgets.X` inner class in `ui/widgets.gd` | doc + widget | none |
| Ukrainian wording | add key to `ui/format.gd` | `ui/format.gd` | none |

`HudRoot` never learns what a convoy/raid/capsule is (R4). This is the literal transplant of "adding a mechanic never edits the tick loop."

---

# 3. ПІДХІД (APPROACH)

## 3.1 Mockup-first parity porting

`docs/ux/hud.html` is the pixel oracle; `design-system.md` is the contract. For every widget the loop is: (1) read the mockup's DOM/CSS for that primitive, (2) extract its exact tokens/anatomy into the parity-named widget (`.need → NeedBar`), (3) build the Godot `Control` from `Tokens`/`Theme` so it matches, (4) verify against the running mockup via the `ux-hud` preview. Parity is a **per-widget checklist** (same color role, same anatomy icon·track·mono value, same urgency thresholds) verified by `preview_inspect` token reads — not by eyeballing screenshots. Because colors live in one resource, "does it match the design system" is a single reconciliation of `Tokens` against §1 (which immediately fixes the drift).

## 3.2 Component-library discipline (finite vocabulary)

The kernel's lesson — *"~5 abstractions absorb hundreds of mechanics; adding a mechanic never edits the tick loop"* — is transplanted verbatim: ~11 widget primitives + 6 contracts absorb 30+ panels; adding a mechanic's UI never edits `HudRoot`. A mechanic's entire surface is: subclass `Panel` (or reuse one), compose existing `Widget`s, optionally subclass `Overlay`, then `register(...)`. A genuinely new primitive is added to design-system §4 **first** (the doc gate), then coded once — the vocabulary stays finite by construction. Review rejects a mechanic PR that hand-rolls a bespoke `Control` where a `StatRow`/`Gauge` would do.

## 3.3 One-way binding, proven headlessly

Because `HudModel.snapshot()`, `ui/format.gd`, `ui/view_geom.gd`, the registries, and `InputController` are pure `RefCounted`/`static`, ~80% of the view logic is unit-testable with **no scene tree** — exactly how `run_kernel_tests.gd` feeds a plain `world` dict to a `SimSystem`. A test builds a fake `session`-shaped dict, calls `snapshot()`, asserts fields.

**Control-subclass tests are NEW territory** — no existing test in `godot/tests/` instantiates any `Control`; the kernel suite proves only Node-free `RefCounted` logic, so it is **not** a precedent for building Control trees. Two rules the UI suite must validate first: (1) `.new()` on a `Control` does **not** enter the `SceneTree` and does **not** auto-fire `_ready`; manually calling `_ready()` does **not** propagate down to children (a child added via `add_child` outside the tree never fires its own `_ready`, so its `_build`/`rebuild_count` never runs). (2) So a Control test must drive the **real lifecycle in a headless `SceneTree`**: `get_root().add_child(panel)` inside the `SceneTree`-based `run_ui_tests.gd` (which HAS a root) and `await` one process frame so `_ready` fires naturally down the child chain, then `free()`. Where practical, prefer moving `rebuild_count`/`_build` logic into a Node-free `RefCounted`/`static` builder the test calls directly (the §0/R2 pattern), or gate construction behind the idempotent `build_once()` (§2.6) so an accidental later tree-entry can't double-fire `_build`. The scene tree is needed only for the thin `HudRoot`, which has almost no logic left to test. **Explicitly**: the headless suite *cannot* prove `pin_*` resize-safety or pixel parity — those belong exclusively to the live preview gate.

## 3.4 Verification protocol (two independent gates, both required per batch)

**Gate 1 — headless `tests/run_ui_tests.gd`** (`extends SceneTree`, identical `ok(cond, name)` / `quit(1 if failed > 0)` idiom as `run_kernel_tests.gd`, wired into `test.cmd` beside the existing suites). Asserts:
- `snapshot()` maps `time.frac` → phase enum at the right boundaries; `_need_row` urgency thresholds; `raid` `{state}` mapping.
- `FeedbackBus.ingest` turns N new `messages[]` into N `feed` events, one banner change into one banner event; `reset_cursors` clears state.
- `PanelRegistry` sorts by priority, `get_panel` finds by id, `bind_visible` skips hidden.
- `OverlayRegistry` radio exclusivity (toggle `roof` then `temp` → only `temp` active; `roof` twice → inactive).
- R2 `rebuild_count == 1` after two binds; R8 every slice leaf is value data; R1/R3/R4/R9/R10 greps = 0 hits; `Tokens.GOOD == Color.html("6fae54")` (drift-fixed); R5 `_stats_slice.melee` has `value` + `explain`; `_t_res_keys_resolve` (every `RES_ORDER` id resolves in `Tokens.RES`); `_t_feed_survives_trim` (>40-message boundary).

**Gate 2 — live `ux-hud` preview** (design-system §8 protocol, launch config port 8791). `preview_start` → `preview_snapshot` (accessibility tree shows Ukrainian labels) → `preview_click` a toolbar chip (panel toggles, no rebuild flicker) → `preview_inspect` (computed color == `Tokens` value — the memory note records `preview_screenshot` is broken here, so color/parity verification leans on `preview_inspect`, **not** pixels) → `preview_resize` to ≤900px (dock collapse; R7 resize-safety — the check the headless suite cannot do).

## 3.5 How design / build / review compose per batch

- **Design** owns `hud.html` + `design-system.md` (unchanged authority). A new visual concept lands there first. A widget is "done" when its bound render matches the mockup class under `preview_inspect` token checks.
- **Build** works entirely inside `godot/scripts/ui/` — additive, `main.gd` untouched until Batch 7 (repo precedent: the kernel landed parallel to `sim.gd`). A mechanic is added by registration.
- **Review** is mechanical: run the R1–R12 greps (they are literal test cases) + `run_ui_tests.gd` green + the `ux-hud` protocol once a panel is wired. A mechanic-UI PR that touches `HudRoot` fails review by construction. Report findings via `ReportFindings` (R5 unexplained-number and R3 raw-color are blocking).

---

# 4. MIGRATION — additive strangler-fig (kernel-0003-§8 style; suites stay green)

**Governing rule:** `main.gd` is untouched through Batches 0–6; the **sole** existing-code edit before the Batch 7 flip is the behaviour-preserving `ViewGeom.cull_rect` extraction in `world_view.gd` (Batch 4, §2.9), which is **not** in R1's sim-facing set (R1 covers `sim`/`session`/`social`/`persistence`/`kernel`; `world_view.gd` importing `ui/view_geom.gd` is allowed) and leaves `main.gd`'s render output identical. The new layer is otherwise built and tested in parallel; a **separate `newhud_main.gd` entry scene** (selected by the bare `newhud` user-arg — matched with `"newhud" in uargs` from `OS.get_cmdline_user_args()`, exactly like the existing bare `auto`/`uishot`/`gameshot` args; **no `--` prefix**, which would not match that idiom) boots the new controller — **not** a shadow CanvasLayer mounted beside the live `main.gd`. This structurally eliminates the double-input / double-tick hazard (`main.gd._process` unconditionally writes `sim.move_input` and calls `sim.update`): two HUDs never poll and command the same sim in the same run. At every commit: `run_tests.gd` green, `run_kernel_tests.gd` green, `run_ui_tests.gd` green, and `main.gd` still launches (it never imports `ui/`, so it can't break).

**Batch 0 — Tokens + Theme + format + the empty-green harness (data before behavior).**
Land `ui/tokens.gd`, `ui/theme.gd`, `ui/format.gd`, `ui/view_geom.gd`, `ui/latlon.gd`, and `tests/run_ui_tests.gd` (empty-but-green skeleton). Assert every locked token equals its §1 value (drift reconciled: `WARN == e0b070`, not `ffcf5c`); `Fmt.hhmm/phase_enum/region` correct; `latlon` parse/validate (±90/±180). Imports nothing, breaks nothing. Mirrors how `defs.gd` landed before its consumers.

**Batch 1 — Snapshot + FeedbackBus + the one-way tripwire.**
Land `ui/hud_model.gd` (`snapshot()` + slices) and `ui/feedback_bus.gd`. Feed a fake sim-shaped dict: assert phase-enum boundaries, raid `{state}` mapping, feed/banner ingest + `reset_cursors`, R8 value-data walk. **Ship `_t_no_back_reference` here** — it passes trivially now and stays a tripwire forever. No Controls yet → no window needed.

**Batch 2 — Widget base + read-only primitives (parity porting begins).**
Land `ui/widget.gd` (base) + `ui/widgets.gd` (concrete inner classes with `pin_*`), `ui/panel.gd`, `ui/panel_registry.gd`, and `Widgets.NeedBar`, `Widgets.StatRow`, `Widgets.Card`, `Widgets.Gauge`, `Widgets.H2Header`, `Widgets.BannerWidget`, `Widgets.FlashWidget`. Tests: `_t_bind_stable_childcount` (R2), `_t_stat_has_explain` (R5, shape-only), `_t_no_raw_color` (R3), `_t_state_widget_triplet` (R11). This is **new** territory — no prior test builds Controls — so validate the lifecycle first: parent each widget into `get_root()` and `await process_frame` so `_ready` fires down the child chain (a bare `.new()` never enters the tree, and a manual `_ready()` does not propagate to children — §3.3).

**Batch 3 — First real panel end-to-end: `StockPanel` (the proof slice).**
Land `Panels.StockPanel` (the first inner class in `ui/panels.gd`) + a minimal `HudRoot` that mounts only `Panels.StockPanel` in the RIGHT dock from a registry and drives it from `snapshot()`. Exercised purely by the UI test — **the whole spine (Snapshot → ViewModel → Panel → Widget → Tokens) proven headlessly with `main.gd` still the live HUD.** Mirrors "wire one `SimSystem` before the rest."

**Batch 4 — Overlay framework + first overlay (the biggest gap).**
Land `ui/overlay.gd`, `ui/overlays.gd`, `ui/overlay_registry.gd`, `Widgets.OverlayChip`, `Widgets.LegendBox`, `OverlayHost`, and the first overlay — **`L` Light**, **reimplementing** `main.gd`'s `night_rect` darkening as a world-space `L`/Light overlay in the newhud `OverlayHost` (easiest lift, no legacy reconciliation since no overlay layer exists). `main.gd`'s own `night_rect` stays live and untouched until Batch 7 (where its removal already belongs) — this batch adds the overlay in the newhud-only path, it does **not** move or delete the `night_rect` code out of `main.gd`. Tests: radio toggle, `active_and_markers()` count, hotkey via `InputController`, `draw_overlay` reads `snap.env` not a climate provider (R12). Wire the shared `ViewGeom.cull_rect` (the ~5-line `world_view.gd` edit — the sole existing-code touch, §2.9) here.

**Batch 5 — InputController + `newhud` assembly.**
Land `ui/input_verbs.gd` + `ui/input_controller.gd` (the §5 verb table) and grow `HudRoot` into the full HUD (all LEFT/RIGHT/TOP/BAR panels, each its own commit). Add `godot/newhud_main.gd` + a `newhud` launch config (bare user-arg, matched `"newhud" in uargs`). Both HUDs now exist in parallel; `main.gd` is still default. Verify `newhud` with the live protocol.

**Batch 6 — Port the modals + extract non-UI services.**
Port `LogisticsPanel`(M, keeps `MapWidget`)/`EquipmentPanel`(I)/`CapsulePanel`(C)/`SocialPanel`(F)/`HelpPanel`(H)/`SpawnPanel`, each replacing a `_build_*_panel`+`_clear` path in the `newhud` branch only. Lift the screenshot dev harness to `ui/dev/screenshot_harness.gd` and the Overpass fetch to `net/osm.gd` (pure non-UI moves, mergeable independently).

**Batch 7 — Flip default + delete (separate PR, only after both gates pass).**
Make `newhud_main.gd` the main scene; reduce `main.gd` to the thin root controller (world nodes, `_process` tick, session wrappers) or retire it; delete the dead `_build_*_panel`/`_clear`/`_toggle_only`/`_mk_modal`/`C_*` consts/`_sb_*`. This is the ONLY batch that edits/removes `main.gd`, shipped alone so a revert is one commit. `FeedbackBus` takes true `flash_t` lifetime ownership here.

**Explain-seam upgrade (gated on spec 0003 §8, not merely on a stable widget API):** swap `_stats_slice`'s source from the legacy getter to `StatWorker.value(ctx)` and wire hover to `StatWorker.explain(ctx)`. The `{value, explain}` widget keys don't change, but the swap additionally requires threading a real hero `ctx` (capacities from the HealthTracker + quality_mult) into the slice — and that ctx does not exist for the hero until spec 0003 §8 wires the hero's HealthTracker into `sim.update`. So this is **not** a pure "drop-in, only the source changes" substitution: it depends on the health/stat ctx becoming available. The view-into-ui migration is otherwise independent of the kernel-into-sim migration; only this one seam is coupled to §8. Until then, health/threat/env slices bind legacy getters + placeholder explain with **shape-only** tests, so empty `BalancePanel`/`HealthDoll` shells are "gated, not unfinished."

---

# 5. PROOF-SCAFFOLD — concrete file list + the minimal first vertical slice

## 5.1 File scaffold

```
godot/scripts/ui/
  tokens.gd              # LOCKED §1 palette + res()/urgency(); the ONLY hex home (R3). Preloaded const.
  theme.gd              # builds one Theme from Tokens (type variations); H2Header decision (§2.4).
  format.gd             # PURE Ukrainian/number formatters: hhmm, phase_enum, region, *_explain_placeholder
  view_geom.gd          # PURE cull_rect() shared by WorldView + OverlayHost (§2.9)
  latlon.gd             # PURE GPS parse + ±90/±180 validation (lifted from _parse_latlon)
  hud_model.gd          # ** snapshot(session,world,ctx,balance)->Dictionary + all *_slice(). PURE. **
  feedback_bus.gd       # FeedbackBus: ingest 4 leak channels -> typed events; reset_cursors on travel
  widget.gd             # Widget BASE inner class + pin_top_left/right/bottom_left/center (R7)
  widgets.gd            # ALL concrete widgets as inner classes; `const WidgetBase = preload("…/widget.gd")`
                        #   Widgets.NeedBar/StatRow/Gauge/Card/HealthDoll/BillRow/TechNode/
                        #   BuildSlot/OverlayChip/LegendBox/H2Header/BannerWidget/FlashWidget/FeedWidget
  panel.gd              # Panel BASE inner class (dock/priority/hotkey; build_once + _build + bind; rebuild_count R2)
  panels.gd            # ALL concrete panels as inner classes; `const PanelBase = preload("…/panel.gd")`
                        #   Panels.StockPanel (PROOF SLICE, first), VitalsPanel, HealthPanel,
                        #   EquipmentPanel, PalettePanel, BalancePanel, BuildPanel, TopBar, ActionBar,
                        #   LogisticsPanel, CapsulePanel, SocialPanel, HelpPanel, SpawnPanel
  panel_registry.gd     # PanelRegistry: register/sort/get_panel/by_dock/bind_visible/toggle (== SystemRegistry)
  overlay.gd            # Overlay BASE inner class (overlay_id/hotkey/radio/legend_rows/draw_overlay)
  overlays.gd          # ALL concrete overlays as inner classes; `const OverlayBase = preload("…/overlay.gd")`
                        #   Overlays.LightOverlay (PROOF OVERLAY, migrate night_rect darkening, Batch 4),
                        #   TemperatureOverlay, RoofOverlay, PowerOverlay, GrowOverlay,
                        #   StockpileOverlay, FireOverlay, CoverOverlay
  overlay_registry.gd   # OverlayRegistry: register(asserts contract)/toggle(radio)/active_and_markers
  input_verbs.gd        # the §5 grammar as data (order/build/deconstruct/select/overlay/panel/inspect)
  input_controller.gd   # InputController: dispatch(verb,args,session); ONLY caller of sim commands (R9)
  hud_root.gd           # thin controller: owns registries+bus+VM; 6-line _process; ZERO mechanic names
  mechanics.gd          # namespace of per-mechanic UI registrars (inner classes / static fns)
                        #   _ExampleUi: registers panel/overlay/verb, edits no controller (R4)
  dev/
    screenshot_harness.gd  # lifted out of main.gd (Batch 6)
  theme/fonts/           # bundled --sans + --mono FontFile TTFs (desktop app, no CSP)

godot/scripts/net/
  osm.gd                 # Overpass fetch service, lifted from _fetch_osm/_on_osm_done (Batch 6, non-UI)

godot/newhud_main.gd     # `newhud` bare-user-arg entry scene wiring HudRoot beside the world nodes (Batch 5)
godot/tests/run_ui_tests.gd   # extends SceneTree; ok()/quit(1 if failed>0); wired into test.cmd
```

## 5.2 The minimal first vertical slice (build FIRST — proves the whole spine, no window)

Prove all six contracts with the smallest vertical: **`Tokens` + one `snapshot()` path + `StockPanel` + `StatRow` + one `FeedbackBus` round-trip + one `LightOverlay` radio toggle.**

1. `ui/tokens.gd` + `ui/theme.gd` (`StatRow` styled by the `RwPanel`/`MonoValue` variations).
2. `HudModel._stock_slice()` over a **fake sim dict** `{stock:{wood:12, stone:5}, stock_total:17, storage_cap:200}`.
3. `StockPanel._build()` makes one `StatRow` per `RES_ORDER`; `bind(vm)` sets values. Registered via `PanelRegistry.register(...)`; `HudRoot` mounts it with zero panel-specific code.
4. `FeedbackBus`: push a fake `{cls:"good", text:"…"}` → assert `FeedWidget` gets one card.
5. `LightOverlay` registered; `OverlayRegistry.toggle(&"light")` flips radio; `OverlayHost` draws it in world space.

## 5.3 The headless assertions in `run_ui_tests.gd` that make the slice load-bearing

```gdscript
# run_ui_tests.gd extends SceneTree, so get_root() is a real headless viewport we can parent into.
func _t_stock_spine() -> void:
	var fake := {"sim": {"stock": {"wood": 12, "stone": 5},
						  "stock_total": 17, "storage_cap": 200}}
	var snap := HudModel.snapshot(_fake_session(fake), {}, {}, _fake_balance())
	ok(int(snap.stock.rows.wood) == 12, "snapshot reads fake stock, no live sim ref")   # R8
	var Panels = preload("res://scripts/ui/panels.gd")
	var panel = Panels.StockPanel.new()
	get_root().add_child(panel)                            # REAL tree entry: _ready → build_once fires
	await process_frame                                    # let _ready propagate down the child chain
	var n0 := panel.get_child_count()
	panel.bind(snap); panel.bind(snap)                     # bind twice
	ok(panel.rebuild_count == 1, "bind() never rebuilds; build_once idempotent (R2)")
	ok(panel.get_child_count() == n0, "child count stable across rebind (R2)")
	ok(Tokens.GOOD == Color.html("6fae54"), "palette drift reconciled to §1 (R3)")
	panel.free()                                           # drop the Control; no dangling refs
```

The manual `panel._ready()` form is deliberately avoided: `.new()` never enters the tree, and a hand-called `_ready()` does not fire children's `_ready`, so their `_build`/`rebuild_count` would never run and any recursion into child widget state would read uninitialized children. The `add_child` + `await process_frame` path exercises the real lifecycle, and `build_once()` (§2.6) guarantees a later accidental tree-entry can't double-fire `_build` and break the `rebuild_count == 1` assertion.

Plus the permanent tripwires: `_t_no_back_reference` (R1), `_t_no_raw_color` (R3), `_t_controller_has_no_mechanic` (R4), `_t_commands_only_in_router` (R9), `_t_feedback_single_adapter` (R10), `_t_slice_is_value_data` (R8), and `OverlayRegistry` radio toggle (`toggle(&"light")` twice returns to inactive; `active_and_markers()` count correct). Two additions the findings mandate:

- **`_t_res_keys_resolve`**: assert every `GameData.RES_ORDER` id resolves in `Tokens.RES` with no `INK` fallback (`Tokens.res(id) != Tokens.INK` for each id, or an explicit membership check) — so the `comp` vs `components` key mismatch can never silently render the components dot in the wrong color again.
- **`_t_feed_survives_trim`**: log **45+** messages across **two** `ingest()` calls (crossing the sim's 40-message sliding-window trim) and assert the feed receives every new message exactly once — no gap, no duplicate. The prior index-cursor form passed on a fresh sim (cursor never reached 40 in a short test) yet silently stopped after message 40 in a real session; this test exercises the trim boundary the seq-counter contract (§2.7) fixes.
- **`_t_bus_no_dangling`**: after subscribing `FeedWidget`/`BannerWidget`/`FlashWidget` and freeing them, assert `FeedbackBus` reports zero connections (R8 / §2.7 `_exit_tree` disconnect).

**Green here = the Panel / Widget / Snapshot / Overlay / FeedbackBus / InputVerb contracts and the registration API all work end-to-end, headlessly, with `main.gd` untouched** — the same bar the kernel cleared (prove `SystemRegistry` with a plain world dict) before wiring into `sim.update`.

---

## 6. Rejected alternatives (and why)

- **Top-level `class_name` for every primitive** (and banning `.tscn`): rejected. The repo has zero `class_name`; the kernel uses inner-class + `preload` namespacing. `class_name` is global, load-order-fragile, and un-resettable per test — the opposite of the kernel's isolatable idiom. The view uses inner classes consumed via `preload`.
- **`Tokens`/`Feedback` as autoloads**: rejected. `project.godot` has no autoloads; autoload singletons share mutable state across headless tests in one `SceneTree`. `Tokens` is a preloaded const; `FeedbackBus` is an instance owned by `HudRoot` and passed by reference.
- **`hash(slice)` content diff-gate for skip-rebind**: rejected as unsound in GDScript-4.7 — nested Dictionary/Array hashing is order-sensitive, JSON reload coerces stock int→float (unstable equality across save/load), and a live enemy ref in a slice makes `hash()` nondeterministic *and* violates R8. It also solves an unproven perf problem at `MAP_N=56`. Kept the **intent** (never rebuild Controls) via the `rebuild_count == 1` test (built exactly once, never again on rebind); the optimization is "bind visible panels only," with an explicit per-slice dirty flag as the escalation if profiling ever demands it.
- **Overlays drawing into `WorldView`'s canvas item** (`WorldView._draw()` calling the HUD registry): rejected — it makes the sim-facing `WorldView` reach up into `ui/`, an R1 violation. Overlays draw in a separate world-space `OverlayHost`; the two share `ViewGeom.cull_rect` so the tilemap and overlays can't drift.
```

**RETURN VALUE:** the final spec is written to `O:\realworld\specs\0005-ux-ui-view-layer.md`.
