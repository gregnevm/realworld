# RealWorld — headless tests for the UX/UI view layer (spec 0005).
# Run: Godot_console.exe --headless --path godot -s res://tests/run_ui_tests.gd
#
# Same idiom as run_kernel_tests.gd: extends tests/harness.gd (shared ok(cond,name) + finish()).
# Proves the pure spine (Tokens/Format/ViewGeom/LatLon/HudModel/FeedbackBus) with NO window, and the
# Control layer (Widget/Panel/registries/overlays) through the REAL headless lifecycle (get_root()+await).
extends "res://tests/harness.gd"

const Tokens = preload("res://scripts/ui/tokens.gd")
const Fmt = preload("res://scripts/ui/format.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const ArtIcons = preload("res://scripts/ui/art_icons.gd")
const WorldViewScript = preload("res://scripts/world_view.gd")
const AM = preload("res://scripts/ui/action_model.gd")
const TouchCtl = preload("res://scripts/ui/touch_controls.gd")
const LatLon = preload("res://scripts/ui/latlon.gd")
const HudModel = preload("res://scripts/ui/hud_model.gd")
const CatalogView = preload("res://scripts/ui/catalog_view.gd")
const CatalogPanels = preload("res://scripts/ui/catalog_panels.gd")
const CatalogVerbs = preload("res://scripts/ui/catalog_verbs.gd")
const CatalogSim = preload("res://scripts/catalog_sim.gd")
const InputCtl = preload("res://scripts/ui/input_controller.gd")
const FeedbackBus = preload("res://scripts/ui/feedback_bus.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const Panels = preload("res://scripts/ui/panels.gd")
const PanelReg = preload("res://scripts/ui/panel_registry.gd")
const OverlayReg = preload("res://scripts/ui/overlay_registry.gd")
const Overlays = preload("res://scripts/ui/overlays.gd")
const Balance = preload("res://scripts/kernel/balance.gd")
const GameData = preload("res://scripts/data.gd")
const Progression = preload("res://scripts/kernel/progression.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const WorldInput = preload("res://scripts/ui/world_input.gd")
const Mechanics = preload("res://scripts/ui/mechanics.gd")
const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")
const HudRootScript = preload("res://scripts/ui/hud_root.gd")
const LifecycleScript = preload("res://scripts/ui/lifecycle.gd")
const InvPanels = preload("res://scripts/ui/inventory_panels.gd")
const SessionScript = preload("res://scripts/session.gd")
const CapsuleMod = preload("res://scripts/sim/capsule.gd")
const InventoryMod = preload("res://scripts/sim/inventory.gd")
const InputVerbsMod = preload("res://scripts/ui/input_verbs.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const CapsuleTexts = preload("res://scripts/ui/capsule_texts.gd")
const HeroHealthMod = preload("res://scripts/sim/hero_health.gd")
const WorldPanels = preload("res://scripts/ui/world_panels.gd")
const PersistenceMod = preload("res://scripts/persistence.gd")


func _init() -> void:
	print("== RealWorld UI view-layer tests (spec 0005) ==")
	_t_tokens()
	_t_art_icons()
	_t_world_fx()
	_t_panel_fold()
	_t_goal_guide()
	_t_comprehension()
	_t_build_drawer()
	_t_enemy_intent()
	_t_action_model()
	await _t_touch_controls()
	_t_format()
	_t_view_geom()
	_t_latlon()
	_t_snapshot()
	_t_value_data()
	_t_feedback()
	_t_feed_survives_trim()
	_t_feed_clamp()
	_t_feed_self_heal()
	_t_widgets()
	_t_stock_spine()
	_t_research_surface()
	_t_catalog_view()
	_t_tech_panel()
	_t_catalog_verbs()
	_t_tech_intent()
	_t_action_browsers()
	_t_bom_tips()
	_t_catalog_live_slice()
	_t_panel_registry()
	_t_overlay_registry()
	_t_hotkey_contract()
	_t_bus_no_dangling()
	_t_world_input_grammar()
	_t_playability_grammar()
	_t_inspect_slice()
	_t_feedback_mounted()
	_t_frame_panels()
	_t_one_truth_overlays()
	_t_touch_grammar()
	_t_touch_frame()
	await _t_capsule_ui()
	_t_capsule_budget()
	await _t_capsule_adv()
	_t_capsule_adv_pure()
	await _t_capsule_texts()
	_t_capsule_no_goal_gates()
	await _t_capsule_w4b_adv()
	_t_rule_tripwires()
	# release the process-shared forward-engine model: its placed Things carry comp back-references
	# (RefCounted cycles) that would otherwise show up as ObjectDB leaks at exit
	CatalogSim.dispose_shared()
	finish()


# ---------------- Tokens (R3 / drift reconciliation) ----------------
# Every emoji→art mapping must resolve to a real PNG (a typo'd id would silently fall back to the emoji
# forever), every live resource has its icon, and building sprites crop to a non-empty opaque region.
func _t_art_icons() -> void:
	for g in ArtIcons.GLYPH_ART:
		ok(ArtIcons.for_glyph(String(g)) != null, "GLYPH_ART %s → %s has a PNG" % [g, ArtIcons.GLYPH_ART[g]])
	for res in GameData.RES_ORDER:
		ok(ArtIcons.res(String(res)) != null, "live resource %s has an icon" % res)
	var wall: Texture2D = ArtIcons.building("wall")
	ok(wall != null and wall.get_size().x > 8.0, "building('wall') loads and crops")
	ok(ArtIcons.for_glyph("no-such-glyph") == null and ArtIcons.building("no_such_building") == null, "unknown glyph/building → null (emoji fallback)")

# Floating feedback is a pure observer: a stock rise / hit spawns text, nothing is written back to the sim,
# texts age out, and an idle frame spawns nothing.
func _t_world_fx() -> void:
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var sim = Sim.new()
	sim.new_game({"n": nn, "tiles": tiles, "nodes": {}, "spawn": Vector2i(8, 8), "lat": 50.4501, "lon": 30.5234})
	var v = WorldViewScript.new()
	v.sim = sim
	v.observe_sim(0.016)
	ok(v._fx.is_empty(), "world fx: first observation only records baselines")
	var before_wood: int = int(sim.res_amount("wood"))
	sim.stock[sim.res_key("wood")] = before_wood + 3
	v.observe_sim(0.016)
	ok(v._fx.size() == 1 and String(v._fx[0].text) == "+3", "world fx: a stock rise spawns +N text")
	ok(int(sim.res_amount("wood")) == before_wood + 3, "world fx: observer never writes the sim")
	v.observe_sim(0.016)
	ok(v._fx.size() == 1, "world fx: an idle frame spawns nothing")
	v.observe_sim(2.0)
	ok(v._fx.is_empty(), "world fx: texts age out")
	ok(v._born.is_empty(), "world fx: buildings present at load never pop (baseline)")
	sim.stock[sim.res_key("wood")] = 200
	sim.try_build("campfire", 9, 9)
	v.observe_sim(0.016)
	ok(v._born.has(9 * nn + 9), "world fx: a newly placed building gets a placement pop")
	v.free()

# Progressive disclosure: a panel shaped «VBox → header + rows» folds to its header on click; the rows keep
# their own state/refs (nothing rebuilt — R2), and a panel can start folded.
func _t_panel_fold() -> void:
	var p = Panels.GoalsPanel.new()
	p.build_once()
	var rb: int = p.rebuild_count
	var vb: Node = p.get_child(0)
	var head: Node = vb.get_child(0)
	ok(bool(head.collapsible) and p._fold_body != null, "fold: header is collapsible and the rows share one body")
	ok(p._fold_body.visible and vb.get_child_count() == 2, "fold: starts open; VBox is [header, body]")
	head.set_collapsed(true)
	ok(not p._fold_body.visible, "fold: collapsing hides the body only")
	head.set_collapsed(false)
	ok(p._fold_body.visible and p.rebuild_count == rb, "fold: unfolding restores it without a rebuild (R2)")
	var r = Panels.ResearchPanel.new()
	r.build_once()
	ok(r.collapsed_default and not r._fold_body.visible, "fold: ResearchPanel starts folded")
	r.free()
	p.free()

# Contextual onboarding: the build slot the current goal is about pulses (amber tint + scale); other
# slots stay neutral, and a goal without a build target lights nothing.
func _t_goal_guide() -> void:
	var bb = Panels.BuildBarPanel.new()
	bb.build_once()
	var slots: Array = [
		{"key": "wall", "hotkey": "1", "name": "Стіна", "cost": "", "afford": true, "locked": false, "selected": false},
		{"key": "campfire", "hotkey": "9", "name": "Багаття", "cost": "", "afford": true, "locked": false, "selected": false}]
	bb.bind({"build": {"slots": slots}, "goals": {"current": {"build": "campfire"}}})
	ok(bb._btns[1].modulate != Tokens.WHITE and bb._btns[0].modulate == Tokens.WHITE, "goal guide: only the goal's slot is tinted")
	bb.bind({"build": {"slots": slots}, "goals": {"current": {"build": ""}}})
	ok(bb._btns[1].modulate == Tokens.WHITE and bb._btns[1].scale == Vector2.ONE, "goal guide: no target → no pulse")
	bb.free()

# Comprehension pass (gamedev §5 — the first independent read failed on these): the death screen tells the
# truth about the bag and uses no gendered verb; the goal chip shows THIS goal's progress (no «5/10» step
# count); medallions carry a word while learning / while off; the inventory hotbar points at the goal's item.
func _t_comprehension() -> void:
	var DS = LifecycleScript.DeathScreen
	ok("Торба (18" in DS._fate({"inventory": true, "bag_items": 18}), "death: the bag waits where the pawn fell (spec 0009)")
	ok("втрачено" in DS._fate({"inventory": false}), "death: the classic world still says carried loot is lost")
	ok("багаття" in DS._lesson("переохолодження"), "death: the cold cause maps to the warmth lesson")
	var src := FileAccess.get_file_as_string("res://scripts/ui/lifecycle.gd")
	ok(not ("ЗАГИНУВ" in src) and not ("нова пішка" in src), "death: no gendered «ти загинув», no «пішка»")
	var gp = Panels.GoalsPanel.new()
	gp.build_once()
	gp.bind({"goals": {"available": true, "done": 4, "total": 10, "current": {"title": "Розпали багаття", "hint": "h", "pct": 0.0}, "next": "Укриття"}})
	ok(gp._title.text == "Розпали багаття" and "Крок 5 з 10" in gp._title.tooltip_text, "goal chip: no step count on the chip, the step lives in the tooltip")
	gp.free()
	var md = Widgets.Medallion.new()
	md.build_once()
	md.bind({"value": "8", "state": &"crit", "caption": "Мало їжі"})
	ok(md.caption == "Мало їжі", "medallion: carries the alert word")
	md.free()
	var sp = Panels.StockPanel.new()
	sp.build_once()
	sp.bind({"clock": {"day": 5}, "stock": {"rows": {"wood": 0, "food": 2}, "total": 3, "cap": 32, "backpack": true}})
	ok(not sp._rows["wood"].visible and sp._rows["food"].visible and sp._rows["food"].caption == "Мало їжі",
		"stock: zeros hidden (food stays), low food says so in words")
	ok(sp._total.label.begins_with("Рюкзак"), "stock: the slot counter is named the backpack in an inventory world")
	sp.bind({"clock": {"day": 5}, "stock": {"rows": {"food": 8}, "total": 3, "cap": 32, "backpack": true}})
	ok(sp._rows["food"].state == &"good" and sp._rows["food"].caption == "", "stock: 8 portions is calm, not the loudest red on screen")
	sp.free()
	var slots: Array = [{"id": "bld:campfire", "n": 1}, {"id": "", "n": 0}]
	ok(InvPanels.SlotKit.guide_slot({"goals": {"current": {"build": "campfire"}}}, slots) == 0, "hotbar guide: the goal's building slot")
	ok(InvPanels.SlotKit.guide_slot({"goals": {"current": {"build": "bed"}}}, slots) == -2, "hotbar guide: not carried → the backpack button")
	var InvMod = preload("res://scripts/sim/inventory.gd")
	ok(InvMod.words({"scrap": 8}).contains("брухт ×8"), "shortfall in words: the resource is named, not just ⚙")

# Touch build drawer: closed = only the 🔨 button; a category tab shows just its slots; desktop shows the
# flat hotkey row with no button/tabs. Same Button pool throughout (R2).
func _t_build_drawer() -> void:
	var bb = Panels.BuildBarPanel.new()
	bb.build_once()
	var slots: Array = []
	for k in ["wall", "door", "storage", "campfire", "turret"]:
		slots.append({"key": k, "hotkey": "", "name": k, "cost": "", "afford": true, "locked": false, "selected": false})
	bb.bind({"build": {"slots": slots}, "ui": {"touch": false}})
	ok(not bb._fab.visible and not bb._tabs.visible and bb._scroll.visible and bb._btns[4].visible, "drawer: desktop = flat row, no 🔨/tabs")
	bb.bind({"build": {"slots": slots}, "ui": {"touch": true}})
	ok(bb._fab.visible and not bb._scroll.visible and not bb._tabs.visible, "drawer: touch starts closed — just the 🔨 button")
	bb.set_category(3)
	bb.bind({"build": {"slots": slots}, "ui": {"touch": true}})
	ok(bb._scroll.visible and bb._tabs.visible and bb._btns[4].visible and not bb._btns[0].visible, "drawer: the Оборона tab shows only defence slots")
	ok(bb.rebuild_count == 1, "drawer: tabs/drawer never rebuild the panel (R2)")
	bb.free()

# Threat telegraphing (Into the Breach): an enemy in reach shows ⚔ + the damage it will deal after armour;
# a distant idle patrol bot shows 👁. Pure read of sim data.
func _t_enemy_intent() -> void:
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var sim = Sim.new()
	sim.new_game({"n": nn, "tiles": tiles, "nodes": {}, "spawn": Vector2i(8, 8), "lat": 50.4501, "lon": 30.5234})
	var v = WorldViewScript.new()
	v.sim = sim
	var near: Dictionary = GameData.make_raider(sim.player.px + 0.6, sim.player.py, 1)
	var far: Dictionary = GameData.make_patrol_bot(1.5, 1.5, 1)
	var a: Dictionary = v.enemy_intent(near)
	var b: Dictionary = v.enemy_intent(far)
	ok(String(a.glyph) == "⚔" and int(a.num) == int(round(float(near.dmg) * float(sim.armor_mult()))), "intent: adjacent raider telegraphs ⚔ + damage after armour")
	ok(String(b.glyph) == "👁" and int(b.num) < 0, "intent: a distant patrol bot shows 👁 (searching), no number")
	v.free()

# Touch action scheme — the pure half: gestures, auto-target (cone/priority/sticky), verbs, radial, slots.
func _t_action_model() -> void:
	ok(AM.classify(0.1, Vector2.ZERO, INF) == &"tap", "gesture: a short still press is a tap")
	ok(AM.classify(0.1, Vector2.ZERO, 0.2) == &"double", "gesture: a second tap within 300 ms is a double")
	ok(AM.classify(0.5, Vector2(3, 2), INF) == &"hold", "gesture: ≥400 ms still is a hold")
	ok(AM.classify(0.2, Vector2(4, -60), INF) == &"drag_v" and AM.classify(0.2, Vector2(70, 5), INF) == &"drag_h", "gesture: swipes split by axis")
	ok(AM.classify(0.2, Vector2(20, 10), INF) == &"none", "gesture: a wobble past the slop is nothing")
	ok(AM.next_mode(&"fight") == &"gather", "modes cycle gather → build → repair → fight → gather")
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var nodes := {}
	nodes[8 * nn + 10] = {"kind": "tree", "amount": 5}      # in front (east), 2 tiles
	nodes[8 * nn + 6] = {"kind": "rock", "amount": 5}       # behind (west), 2 tiles
	var sim = Sim.new()
	sim.new_game({"n": nn, "tiles": tiles, "nodes": nodes, "spawn": Vector2i(8, 8), "lat": 50.4501, "lon": 30.5234})
	var o := Vector2(8.5, 8.5)
	var t: Dictionary = AM.pick_target(sim, &"gather", o, 0.0)
	ok(StringName(t.get("kind", &"")) == &"node" and int(t.x) == 10, "auto-target: the node in front wins over an equally near one behind")
	t["mode"] = &"gather"
	ok(AM.keep_target(sim, t, &"gather", o, deg_to_rad(60.0)), "auto-target: a held target survives a 60° swing (sticky)")
	ok(not AM.keep_target(sim, t, &"gather", o, PI), "auto-target: turning away drops it")
	var v: Dictionary = AM.primary(&"gather", t)
	ok(StringName(v.verb) == &"order_gather" and int(v.args.x) == 10, "primary: gather → order_gather on the target")
	var bt: Dictionary = AM.pick_target(sim, &"build", o, 0.0, "campfire")
	ok(StringName(bt.get("kind", &"")) == &"cell" and sim.build_valid(int(bt.x), int(bt.y)), "build mode: targets a valid cell next to the hero")
	ok(StringName(AM.primary(&"build", bt, "campfire").verb) == &"build", "primary: build mode places the chosen building")
	ok(AM.pick_target(sim, &"fight", o, 0.0).is_empty(), "fight mode with no enemy → no target (toast, no swing)")
	var opts: Array = AM.options(sim, AM.target_at(sim, Vector2i(10, 8)))
	ok(StringName(opts[0].verb) == &"order_gather" and StringName(opts[-1].verb) == &"order_move", "radial: primary first, «go here» last")
	ok(AM.mode_for_slot({"type": &"weapon"}) == &"fight" and AM.mode_for_slot({"type": &"build"}) == &"build" and AM.mode_for_slot({"type": &"repair"}) == &"repair", "slots switch the mode automatically")
	var slots: Array = AM.default_slots(sim, "wall")
	ok(slots.size() >= 4 and StringName(slots[2].type) == &"build" and String(slots[2].id) == "wall", "quick bar: tool · weapon · armed building · repair")
	sim.player.items.append("axe")
	ok(String(AM.default_slots(sim, "wall")[0].id) == "axe", "quick bar: a crafted axe appears in the tool slot by itself")

# The action button gestures through the real _input path (synthetic ScreenTouch/Drag).
func _t_touch_controls() -> void:
	var tcn = TouchCtl.TouchControls.new()
	get_root().add_child(tcn)
	await process_frame
	var got := {"tap": 0, "double": 0, "hold": 0, "slot": 0, "zoom": 0, "over": 0}
	tcn.action_tap.connect(func() -> void: got.tap += 1)
	tcn.action_double.connect(func() -> void: got.double += 1)
	tcn.action_hold.connect(func(_c: Vector2) -> void: got.hold += 1)
	tcn.slot_step.connect(func(_d: int) -> void: got.slot += 1)
	tcn.zoom_step.connect(func(_d: int) -> void: got.zoom += 1)
	tcn.overview_toggled.connect(func() -> void: got.over += 1)
	var c: Vector2 = tcn.act_center()
	var touch := func(pos: Vector2, down: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.index = 1
		e.position = pos
		e.pressed = down
		tcn._input(e)
	touch.call(c, true); touch.call(c, false)
	ok(got.tap == 1, "action button: a tap acts at once")
	touch.call(c, true); touch.call(c, false)
	ok(got.double == 1 and got.tap == 1, "action button: a quick second tap is a double (mode cycle), not a 2nd act")
	tcn._now += 1.0
	touch.call(c, true)
	tcn._process(0.5)
	touch.call(c, false)
	ok(got.hold == 1 and got.tap == 1, "action button: a 0.5 s hold opens the radial, no tap")
	tcn._now += 1.0
	touch.call(c, true)
	var d := InputEventScreenDrag.new()
	d.index = 1
	d.position = c + Vector2(100, 0)
	d.relative = Vector2(100, 0)
	tcn._input(d)
	touch.call(c + Vector2(100, 0), false)
	ok(got.slot >= 1 and got.tap == 1, "action button: a horizontal swipe steps the quick slot")
	var st := Vector2(60, tcn.size.y - 60)
	for i in 2:
		var e2 := InputEventScreenTouch.new()
		e2.index = 0
		e2.position = st
		e2.pressed = true
		tcn._input(e2)
		e2 = InputEventScreenTouch.new()
		e2.index = 0
		e2.position = st
		e2.pressed = false
		tcn._input(e2)
	ok(got.over == 1, "left stick: a strict double tap toggles the map overview")
	ok(tcn.claims(c) and not tcn.claims(Vector2(tcn.size.x * 0.6, 40)), "touch layer claims its controls, never the open map")
	tcn.queue_free()
	await process_frame

func _t_tokens() -> void:
	ok(Tokens.GOOD == Color("6fae54"), "GOOD reconciled to locked --good (drift fixed from 5fd38a)")
	ok(Tokens.WARN == Color("e0b070"), "WARN reconciled to locked --warn (drift fixed from ffcf5c)")
	ok(Tokens.CRIT == Color("e06a5a"), "CRIT reconciled to locked --crit (drift fixed from ff6b6b)")
	ok(Tokens.urgency(&"good") == Tokens.GOOD and Tokens.urgency(&"crit") == Tokens.CRIT, "urgency() maps enum->color at one site (R11)")
	# _t_res_keys_resolve: every runtime resource id resolves (no silent INK fallback -> the comp/components bug)
	var all_resolve := true
	for id in GameData.RES_ORDER:
		if not Tokens.RES.has(id):
			all_resolve = false
	ok(all_resolve, "every GameData.RES_ORDER id resolves in Tokens.RES (comp vs components can't regress)")
	ok(Tokens.res("components") == Color("b58cff"), "components dot resolves to violet, not INK fallback")

# ---------------- Format (enums + Ukrainian, mirrors sim formatting) ----------------
func _t_format() -> void:
	ok(Fmt.hhmm(0.5) == "12:00" and Fmt.hhmm(0.0) == "00:00", "hhmm formats midday/midnight")
	ok(Fmt.phase_enum(0.1) == &"night" and Fmt.phase_enum(0.9) == &"night", "phase_enum: night before dawn / after dusk")
	ok(Fmt.phase_enum(0.25) == &"dawn", "phase_enum: dawn window")
	ok(Fmt.phase_enum(0.5) == &"day", "phase_enum: midday is day")
	ok(Fmt.phase_enum(0.75) == &"dusk", "phase_enum: dusk window")
	ok(Fmt.urgency_enum(80.0) == &"good" and Fmt.urgency_enum(40.0) == &"warn" and Fmt.urgency_enum(10.0) == &"crit", "urgency thresholds mirror _bbar (>50 / >25)")
	ok(Fmt.need_label(&"hunger") == "Голод" and Fmt.need_icon(&"hunger") == "🍖", "need label+icon are Ukrainian+glyph (R11)")
	ok(Fmt.region_line("Київ", 50.4501, 30.5234) == "Київ (50.4501, 30.5234)", "region_line keeps faithful %.4f precision")

# ---------------- ViewGeom (pure cull, shared by tilemap + overlays) ----------------
func _t_view_geom() -> void:
	# camera centered on a 56x56 (tile 28) map, viewport large enough to see all -> whole map visible
	var full := ViewGeom.cull_rect(Vector2(784, 784), Vector2(1, 1), Vector2(1568, 1568), 56, 28)
	ok(int(full.x0) == 0 and int(full.y0) == 0 and int(full.x1) == 55 and int(full.y1) == 55, "cull_rect sees the whole map when zoomed out")
	# a tight viewport near the origin sees only a corner
	var corner := ViewGeom.cull_rect(Vector2(140, 140), Vector2(2, 2), Vector2(560, 360), 56, 28)
	ok(int(corner.x0) >= 0 and int(corner.x1) < 55, "cull_rect clamps a zoomed-in view to a sub-rect")
	ok(ViewGeom.contains(full, 10, 10) and not ViewGeom.contains(corner, 55, 55), "contains() honors the rect")
	var fr := ViewGeom.full_rect(56)
	ok(int(fr.x1) == 55 and int(fr.y1) == 55, "full_rect covers [0,n)")
	# n-dependence: a different region size clamps to n-1 (OverlayHost must pass sim.n, not a hardcoded 56)
	var small := ViewGeom.cull_rect(Vector2(560, 560), Vector2(1, 1), Vector2(4000, 4000), 40, 28)
	ok(int(small.x1) == 39 and int(small.y1) == 39, "cull_rect clamps to n-1 for n=40 (no drift when region size != 56)")

# ---------------- LatLon (pure parse/validate, lifted from main._parse_latlon) ----------------
func _t_latlon() -> void:
	var a := LatLon.parse("50.45", "30.52")
	ok(bool(a.ok) and is_equal_approx(float(a.lat), 50.45), "parse two fields")
	var b := LatLon.parse("50.45, 30.52", "")
	ok(bool(b.ok) and is_equal_approx(float(b.lon), 30.52), "parse single 'lat, lon' pasted address form")
	ok(not bool(LatLon.parse("120", "0").ok), "reject out-of-range latitude")
	ok(not bool(LatLon.parse("0", "200").ok), "reject out-of-range longitude (the short-circuited operand)")
	ok(not bool(LatLon.parse("50, 200", "").ok), "reject out-of-range longitude in pasted address form")
	ok(not bool(LatLon.parse("", "").ok), "reject empty input")

# ---------------- HudModel.snapshot (the ViewModel; the assess() analogue) ----------------
func _t_snapshot() -> void:
	var sess = _fake_session()
	var world := {"buildings": [{"value": 45.0}], "stock": sess.sim.stock, "items": ["axe"]}
	var bal = Balance.Balance.new()
	var snap := HudModel.snapshot(sess, world, {"day": 5, "hostile_pressure": 1.0}, bal)
	ok(bool(snap.alive) and not bool(snap.dead), "snapshot reports alive world")
	ok(String(snap.region.name) == "Тестоград" and int(snap.region.seed) == 12345678, "region slice reads coords + seed")
	ok(snap.clock.phase == &"day" and String(snap.clock.hhmm) == "12:00", "clock slice maps frac->phase enum + hhmm")
	ok((snap.vitals.bars as Array).size() == 4, "vitals slice has hp/hunger/rest/blood bars")
	ok(snap.vitals.bars[1].state == &"good", "hunger 82 -> good urgency enum")
	ok(snap.vitals.bars[3].id == &"blood" and int(snap.vitals.bars[3].pct) == 100, "blood bar defaults to full on a lean fake (graceful)")
	ok(not bool(snap.vitals.downed) and (snap.vitals.conditions as Array).is_empty(), "located-health extras degrade gracefully on a fake sim")
	ok(snap.vitals.comfort is StringName, "felt-°C comfort state is an enum (R11)")
	ok(int(snap.stock.rows.wood) == 12 and int(snap.stock.total) == 17, "stock slice reads fake stock, total summed purely (R8)")
	ok(int(snap.stock.cap) == 200, "stock slice reads storage cap")
	ok(snap.stats.melee.has("value") and String(snap.stats.melee.explain) != "", "stat slice carries value+explain (R5 shape)")
	ok(snap.raid.state == &"none", "raid slice enum defaults to none")
	ok(bool(snap.threat.available) and snap.threat.phase is StringName, "threat slice maps Balance.assess() -> phase enum")
	# a null session degrades gracefully (never crashes headless)
	ok(not bool(HudModel.snapshot(null, {}, {}, bal).alive), "null session -> {alive:false}")
	# a DEAD world snapshots without crashing (dead flag true, hp=0 -> crit urgency)
	sess.sim.dead = true
	sess.sim.player.hp = 0.0
	var dsnap := HudModel.snapshot(sess, world, {"day": 5}, bal)
	ok(bool(dsnap.alive) and bool(dsnap.dead), "dead world still snapshots (alive=true, dead=true)")
	ok(dsnap.vitals.bars[0].state == &"crit", "hp 0 -> crit urgency enum on the death path")
	sess.sim.dead = false; sess.sim.player.hp = 100.0

# ---------------- R8: every snapshot leaf is value data (no live refs / closures) ----------------
func _t_value_data() -> void:
	var sess = _fake_session()
	var bal = Balance.Balance.new()
	var snap := HudModel.snapshot(sess, {"buildings": [], "stock": sess.sim.stock, "items": []}, {"day": 3}, bal)
	ok(_all_value_data(snap), "every snapshot leaf is int/float/String/StringName/bool (R8 — no sim/enemy/Callable ref)")

func _all_value_data(v) -> bool:
	var t := typeof(v)
	if t == TYPE_DICTIONARY:
		for k in v:
			if not _all_value_data(v[k]):
				return false
		return true
	if t == TYPE_ARRAY:
		for e in v:
			if not _all_value_data(e):
				return false
		return true
	return t in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_BOOL]

# ---------------- FeedbackBus (the ONE adapter; R10) ----------------
func _t_feedback() -> void:
	var sim := _FakeSim.new()
	var bus = FeedbackBus.FeedbackBus.new()
	var got_feed := []
	var got_banner := []
	bus.feed.connect(func(evt): got_feed.append(evt))
	bus.banner.connect(func(evt): got_banner.append(evt))
	sim._log("перше повідомлення", "good")
	sim._log("друге повідомлення", "warn")
	bus.ingest(sim, 0.1)
	ok(got_feed.size() == 2, "ingest turns 2 new messages into 2 feed events")
	sim.banner = "⚠ НАБЛИЖАЄТЬСЯ РЕЙД"
	bus.ingest(sim, 0.1)
	ok(got_banner.size() == 1 and got_banner[0].status == &"raid_incoming", "banner change -> 1 banner event with mapped status")
	bus.ingest(sim, 0.1)   # no new messages
	ok(got_feed.size() == 2, "re-ingest with no change emits nothing")
	bus.reset_cursors()
	got_feed.clear()
	bus.ingest(sim, 0.1)
	ok(got_feed.size() == sim.messages.size(), "reset_cursors re-emits the current tail")

# ---------------- _t_feed_survives_trim: cross the 40-message sliding-window boundary ----------------
func _t_feed_survives_trim() -> void:
	var sim := _FakeSim.new()
	var bus = FeedbackBus.FeedbackBus.new()
	var seen := []
	bus.feed.connect(func(evt): seen.append(evt.text))
	for i in 25:
		sim._log("msg-%d" % i)
	bus.ingest(sim, 0.1)                       # drains 25
	for i in range(25, 45):
		sim._log("msg-%d" % i)                 # crosses the 40-cap trim
	bus.ingest(sim, 0.1)                       # must drain exactly msg-25..msg-44, no gap/dup
	ok(seen.size() == 45, "feed receives all 45 messages across the 40-cap trim (no gap, no duplicate)")
	ok(seen[0] == "msg-0" and seen[44] == "msg-44", "feed order preserved across the sliding-window trim")

# ---------------- _t_feed_clamp: MORE than 40 new messages between ingests exercises the mini() clamp ----------------
func _t_feed_clamp() -> void:
	var sim := _FakeSim.new()
	var bus = FeedbackBus.FeedbackBus.new()
	var seen := []
	bus.feed.connect(func(evt): seen.append(evt.text))
	for i in 5:
		sim._log("a-%d" % i)
	bus.ingest(sim, 0.1)                       # drains 5, _last_seq = 5
	seen.clear()
	for i in 50:
		sim._log("b-%d" % i)                   # 50 > 40 window: seq-_last_seq = 50 must clamp to msgs.size()
	bus.ingest(sim, 0.1)
	ok(seen.size() == sim.messages.size() and seen.size() == 40, "over-window burst clamps to the trimmed tail (no negative index)")
	ok(seen[seen.size() - 1] == "b-49", "clamped drain ends at the newest message")

# ---------------- _t_feed_self_heal: a fresh sim (backwards messages_seq) re-syncs, not swallows ----------------
func _t_feed_self_heal() -> void:
	var bus = FeedbackBus.FeedbackBus.new()
	var old_sim := _FakeSim.new()
	for i in 10:
		old_sim._log("old-%d" % i)
	bus.ingest(old_sim, 0.1)                   # _last_seq climbs to 10
	var fresh := _FakeSim.new()                # new game/respawn: messages_seq restarts at 0
	fresh._log("Висадка…", "good")
	var seen := []
	bus.feed.connect(func(evt): seen.append(evt.text))
	bus.ingest(fresh, 0.1)                      # must NOT swallow the fresh sim's opening log
	ok(seen.size() == 1 and seen[0] == "Висадка…", "fresh sim re-syncs (backwards seq self-heals, no swallow)")

# ---------------- Widgets: build-once + R11 triplet (color+icon+number) ----------------
func _t_widgets() -> void:
	var bar = Widgets.NeedBar.new()
	bar.bind({"icon": "🍖", "pct": 82, "state": &"good"})   # build_once fires on first bind
	ok(bar.icon == "🍖" and bar.value == "82", "NeedBar exposes icon+value alongside state color (R11 triplet)")
	ok(bar.state == &"good", "NeedBar carries the urgency enum, not a bare color (R11)")
	var row = Widgets.StatRow.new()
	row.set_glyph_res("wood"); row.set_value(42)
	ok(row.value == "42", "StatRow builds lazily + sets mono value")
	# Gauge parity: the locked .phases strip must be present + labelled (design-system §4 / hud.html)
	var g = Widgets.Gauge.new()
	g.bind({"fill": 0.5, "state": &"warn", "phases": ["спокій", "рейд", "облога", "сплеск"], "active": 1})
	ok(g._phase_labels.size() == 4 and g._phase_labels[0].text == "спокій" and g._phase_labels[3].text == "сплеск", "Gauge renders the 4-phase label strip (parity with locked anatomy)")
	bar.free(); row.free(); g.free()

# ---------------- StockPanel proof slice: build once, bind twice (R2) ----------------
func _t_stock_spine() -> void:
	var sess = _fake_session()
	var bal = Balance.Balance.new()
	var snap := HudModel.snapshot(sess, {"buildings": [], "stock": sess.sim.stock, "items": []}, {"day": 5}, bal)
	var panel = Panels.StockPanel.new()
	panel.bind(snap)
	var n0 := panel.get_child(0).get_child_count()   # header + 6 res rows + total
	panel.bind(snap)                                  # second bind must NOT rebuild
	ok(panel.rebuild_count == 1, "StockPanel builds exactly once across two binds (R2)")
	ok(panel.rebind_count == 2, "StockPanel rebinds each frame (bind != rebuild)")
	ok(panel.get_child(0).get_child_count() == n0, "child count stable across rebind (R2)")
	ok(int(snap.stock.rows.wood) == 12, "proof spine: snapshot -> panel binds fake stock, no live sim ref (R8)")
	panel.free()

# ---------------- Research surface: the tech-pipeline slice + panel (spec 0007) ----------------
func _t_research_surface() -> void:
	var prog = Progression.new(Catalog.load_json())
	prog.start(prog.auto_next())                 # one active project
	prog.enqueue(prog.auto_next())               # and one queued
	var sess = _fake_session()
	sess.progression = prog
	var snap := HudModel.snapshot(sess, {"buildings": [], "stock": sess.sim.stock, "items": []}, {"day": 2}, Balance.Balance.new())
	# slice is wired + pure value data (R8), reports totals, surfaces researchable options
	ok(bool(snap.research.wired), "research slice is wired when the session carries a progression")
	ok(int(snap.research.total) >= 40 and int(snap.research.unlocked) >= 0, "research slice reports unlocked/total")
	ok(String(snap.research.active_label) != "", "active project label surfaced")
	ok((snap.research.options as Array).size() > 0, "researchable options surfaced")
	ok(int(snap.research.counts.buildings.total) == prog.catalog_counts().buildings.total and int(snap.research.counts.items.total) > 0, "catalog counts surfaced (per-category unlocked/total)")
	ok(snap.research.next_unlocks.has("total"), "active-project unlock preview surfaced")
	ok(snap.research.has("rate") and snap.research.has("active_eta_days"), "research rate + active ETA surfaced")
	ok(_all_value_data(snap.research), "research slice is pure value data incl. counts + next_unlocks + eta (R8)")
	# a null-progression session degrades to {wired:false} (the fake-session default path)
	ok(not bool(HudModel.snapshot(_fake_session(), {"buildings": [], "stock": {}, "items": []}, {"day": 1}, Balance.Balance.new()).research.wired),
		"no progression -> research slice degrades to {wired:false}")
	# panel build-once + bind-twice (R2), like the stock proof slice
	var panel = Panels.ResearchPanel.new()
	panel.bind(snap)
	panel.bind(snap)
	ok(panel.rebuild_count == 1, "ResearchPanel builds exactly once across two binds (R2)")
	ok(panel.rebind_count == 2, "ResearchPanel rebinds each frame (bind != rebuild)")
	# a row click bubbles an enqueue_research intent carrying the project id (R9: panel emits, sim untouched)
	var got := []
	panel.intent.connect(func(v, a): got.append([v, a]))
	var first_id: StringName = StringName(snap.research.options[0].id)
	panel._rows[0].picked.emit(first_id)
	ok(got.size() == 1 and got[0][0] == &"enqueue_research" and String(got[0][1].id) == String(first_id),
		"row click -> enqueue_research intent with the project id")
	panel.free()

# ---------------- CatalogView: the content-tree pipeline (deep catalogue -> value-data slices) ----------------
func _t_catalog_view() -> void:
	var db = CatalogView.default_db()
	ok(db != null and db.count() > 300, "CatalogView.default_db builds the full tree (%d defs)" % db.count())
	# neolithic start: nothing unlocked, starter stock
	var snap: Dictionary = CatalogView.snapshot(db, {"unlocked": {}, "stock": {"wood": 50, "stone": 30}})
	ok(bool(snap.available), "catalog snapshot available")
	var s: Dictionary = snap.summary
	ok(int(s.research) == 41 and int(s.researched) == 0, "summary: 0/41 researched at the neolithic start")
	ok(int(s.buildings) == 87 and int(s.buildable) > 0, "some no-research buildings buildable from starter stock (%d)" % int(s.buildable))
	ok(is_equal_approx(float(s.progress), 0.0), "research progress is 0 at the start")
	ok((snap.next as Array).size() >= 5, "tier-1 research is available next (%d options)" % (snap.next as Array).size())
	ok(_all_value_data(snap), "catalog slice is all value data (R8 — no DefDatabase / Callable leaks)")
	# advancing state: unlocking smelting makes its dependent (metallurgy) AVAILABLE
	var snap2: Dictionary = CatalogView.snapshot(db, {"unlocked": {&"smelting": true, &"fire_mastery": true}, "stock": {}})
	ok(int(snap2.summary.researched) == 2, "researched count reflects the unlocked set")
	var metallurgy_available := false
	for r in snap2.research:
		if r.id == &"metallurgy":
			metallurgy_available = (r.status == &"available")
	ok(metallurgy_available, "metallurgy flips locked->available once smelting is unlocked (prereq gate)")
	ok(not bool(CatalogView.snapshot(null).get("available", false)), "null db -> {available:false} (graceful)")
	# per-tier progress climbs 1..9 (neolithic -> ship); values reflect the unlocked set
	var tiers: Array = snap2.tiers
	ok(tiers.size() == 9 and int(tiers[0].tier) == 1 and int(tiers[8].tier) == 9, "tiers slice spans 9 eras ascending")
	ok(int(tiers[0].unlocked) == 1 and int(tiers[0].total) == 5, "tier-1 shows 1/5 unlocked (fire_mastery; smelting is tier-2)")

# ---------------- TechPanel: build-once + value bind, same contract as StockPanel (R2/R8) ----------------
func _t_tech_panel() -> void:
	var cat: Dictionary = CatalogView.snapshot(CatalogView.default_db(), {"unlocked": {}, "stock": {"wood": 50, "stone": 30}})
	var vm := {"catalog": cat}
	var panel = CatalogPanels.TechPanel.new()
	panel.bind(vm)
	var n0: int = panel.get_child(0).get_child_count()   # header + gauge + 4 stat rows
	panel.bind(vm)                                        # second bind must NOT rebuild
	ok(panel.rebuild_count == 1, "TechPanel builds exactly once across two binds (R2)")
	ok(panel.rebind_count == 2, "TechPanel rebinds each frame (bind != rebuild)")
	ok(panel.get_child(0).get_child_count() == n0, "child count stable across rebind (R2)")
	ok(panel.panel_id == &"tech" and panel.dock == 1, "TechPanel: id=tech, RIGHT dock (registered via mechanics.gd)")
	# ResearchTiersPanel — 9 fixed era rows, build-once + bind (R2)
	var tp = CatalogPanels.ResearchTiersPanel.new()
	tp.bind(vm)
	var t0: int = tp.get_child(0).get_child_count()   # header + 9 tier rows
	tp.bind(vm)
	ok(tp.rebuild_count == 1 and tp.rebind_count == 2, "ResearchTiersPanel builds once, binds each frame (R2)")
	ok(tp.get_child(0).get_child_count() == t0 and tp._rows.size() == 9, "ResearchTiersPanel holds 9 fixed era rows")
	ok(tp.panel_id == &"research_tiers" and tp.dock == 1, "ResearchTiersPanel: id, RIGHT dock")
	tp.free()
	# the HudModel snapshot now carries the catalog slice end to end (pipeline surfaced in the HUD)
	var sess = _fake_session()
	var full := HudModel.snapshot(sess, {"buildings": [], "stock": sess.sim.stock, "items": []}, {"day": 5}, Balance.Balance.new())
	ok(full.has("catalog") and bool(full.catalog.available), "HudModel.snapshot surfaces the catalog slice (pipeline end to end)")
	panel.free()

# ---------------- CatalogVerbs: the write-side router (intent -> catalog_sim command, R9) ----------------
func _t_catalog_verbs() -> void:
	var sim = CatalogSim.new()
	sim.grant("wood", 100); sim.grant("stone", 50)
	var ic = InputCtl.InputController.new()
	CatalogVerbs.install(ic, sim)
	ok(ic.has(&"cat_build") and ic.has(&"cat_research") and ic.has(&"cat_craft"), "catalog verbs installed on the router")
	ic.dispatch(&"cat_build", {"id": "workbench"}, null)
	ok(sim.has_building("workbench"), "dispatch cat_build -> station placed (intent -> router -> sim, R9)")
	ic.dispatch(&"cat_research", {"id": "carpentry"}, null)
	ok(String(sim.research.active) == "carpentry", "dispatch cat_research -> project started")
	for i in 4:
		sim.tick(1.0)
	ic.dispatch(&"cat_craft", {"id": "make_planks", "mode": "count", "target": 2}, null)
	for i in 6:
		sim.tick(1.0)
	ok(sim.amount("planks") >= 4, "dispatch cat_craft -> the recipe runs and yields stock (%d planks)" % sim.amount("planks"))
	sim.dispose()   # break the placed Thing<->Comp cycles so the suite exits leak-free

# ---------------- TechPanel intent: panel action -> router -> sim (the full interactive path) ----------------
func _t_tech_intent() -> void:
	var sim = CatalogSim.new()
	var ic = InputCtl.InputController.new()
	CatalogVerbs.install(ic, sim)
	var cat: Dictionary = CatalogView.snapshot(sim.db, sim.view_state())
	var panel = CatalogPanels.TechPanel.new()
	panel.bind({"catalog": cat})
	panel.intent.connect(func(v, a): ic.dispatch(v, a, null))   # HudRoot/InputController wiring
	panel.act_next_research()                                    # simulates the "research next" affordance
	ok(String(sim.research.active) != "", "panel action -> intent -> router -> sim starts research (%s)" % String(sim.research.active))
	panel.free()
	sim.dispose()

# ---------------- ActionBrowser: clickable build/craft/research slots -> intent -> router -> sim ----------------
func _t_action_browsers() -> void:
	var sim = CatalogSim.new()
	sim.grant("wood", 100); sim.grant("stone", 50)
	var ic = InputCtl.InputController.new()
	CatalogVerbs.install(ic, sim)
	var cat: Dictionary = CatalogView.snapshot(sim.db, sim.view_state())
	ok((cat.build_actions as Array).size() > 0, "catalog build_actions non-empty (buildable-now rows, %d)" % (cat.build_actions as Array).size())
	ok((cat.craft_actions as Array).size() == 0, "craft_actions empty until a station is placed")
	ok((cat.research_actions as Array).size() >= 5, "research_actions lists the startable tier-1 projects (%d)" % (cat.research_actions as Array).size())
	var bb = CatalogPanels.BuildBrowser.new()
	bb.bind({"catalog": cat})
	var n0: int = bb.get_child(0).get_child_count()   # header + 12 slot pool
	bb.bind({"catalog": cat})
	ok(bb.rebuild_count == 1 and bb.rebind_count == 2, "BuildBrowser builds once, binds each frame (R2)")
	ok(bb._slots.size() == 12 and bb.panel_id == &"build_browser" and bb.dock == 0, "BuildBrowser: fixed 12-slot pool, LEFT dock")
	ok(bb.get_child(0).get_child_count() == n0, "child count stable across rebind (R2)")
	# full interactive loop: a slot press bubbles an intent through the router into the sim
	bb.intent.connect(func(v, a): ic.dispatch(v, a, null))
	var slot0 = bb._slots[0]
	ok(slot0.item_id != &"", "first build slot bound to a real building id (%s)" % String(slot0.item_id))
	slot0.chosen.emit(slot0.item_id)   # simulate the click
	ok(sim.has_building(slot0.item_id), "click a build slot -> intent -> router -> catalog_sim places it")
	# HudModel snapshot carries the actionable slices too (shared sim -> browsers -> router coherent)
	var sess = _fake_session()
	var full := HudModel.snapshot(sess, {"buildings": [], "stock": sess.sim.stock, "items": []}, {"day": 5}, Balance.Balance.new())
	ok(full.catalog.has("build_actions") and full.catalog.has("research_actions"), "HudModel catalog slice carries the actionable rows")
	bb.free()
	sim.dispose()   # the clicked-in station is a Thing<->Comp cycle until detached

# ---------------- BOM guidance: the planner wired into the browser slots (spec 0008 phase 1) ----------------
# ---- spec 0008 phase 3: the SAME catalog pipeline in LIVE mode — state from the real sim ----
class _LiveSession extends RefCounted:
	var sim: Variant = null
	var started: Array = []
	func start_research(id: String) -> bool:
		started.append(id)
		return true

func _t_catalog_live_slice() -> void:
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var sim = Sim.new()
	sim.use_catalog = true
	sim.new_game({"n": nn, "tiles": tiles, "nodes": {}, "spawn": Vector2i(8, 8), "lat": 50.4501, "lon": 30.5234})
	sim.research_unlocked = {"fire_mastery": true}
	sim.stock[sim.res_key("clay")] = 20
	sim.stock[sim.res_key("stone")] = 20
	var sess = _LiveSession.new()
	sess.sim = sim
	var snap := HudModel.snapshot(sess, {"buildings": [], "stock": sim.stock, "items": []}, {"day": 1}, Balance.Balance.new())
	# the slice flips to live and its rows are honest: every build row is a live-buildable id
	ok(bool(snap.catalog.get("live", false)), "catalog slice reports LIVE state when the sim flag is on")
	var live_ids: Dictionary = CatalogDefs.live_ids()
	var rows: Array = snap.catalog.build_actions
	ok(not rows.is_empty(), "live build_actions surface catalogue-only buildings (%d)" % rows.size())
	var all_live := true
	var has_kiln := false
	for r in rows:
		if not live_ids.has(StringName(str(r.id))):
			all_live = false
		if str(r.id) == "kiln":
			has_kiln = true
	ok(all_live, "every live build row is placeable by the sim (filter holds)")
	ok(has_kiln, "unlocked fire_mastery surfaces the kiln as a build action")
	# a placed station feeds craft_actions from the LIVE world
	sim.try_build("kiln", 3, 3)
	var snap2 := HudModel.snapshot(sess, {"buildings": [], "stock": sim.stock, "items": []}, {"day": 1}, Balance.Balance.new())
	var craft_ids: Array = []
	for r in (snap2.catalog.craft_actions as Array):
		craft_ids.append(str(r.id))
	ok(craft_ids.has("make_charcoal"), "placed live kiln surfaces its recipes in craft_actions")
	# catalogue-only stock lines surface in the stock slice (phase 4)
	sim.stock["charcoal"] = 5
	var snap3 := HudModel.snapshot(sess, {"buildings": [], "stock": sim.stock, "items": []}, {"day": 1}, Balance.Balance.new())
	var extra: Array = snap3.stock.get("extra", [])
	var has_charcoal := false
	for e in extra:
		if str(e.id) == "charcoal":
			has_charcoal = true
	ok(has_charcoal and int(snap3.stock.total) >= 5, "stock slice lists catalogue-only resources with icons")
	# live verb routing (R9): cat_build arms the ordinary select_build ghost; cat_craft flashes honest refusals
	var ic = InputCtl.InputController.new()
	var sandbox = CatalogSim.new(CatalogView.default_db())
	CatalogVerbs.install(ic, sandbox)
	var armed: Array = []
	ic.bind(&"select_build", func(_s, a): armed.append(str(a.kind)))
	ic.dispatch(&"cat_build", {"id": "stone_wall"}, sess)
	ok(armed == ["stone_wall"], "live cat_build arms the select_build ghost (same grammar as the BuildBar)")
	ic.dispatch(&"cat_craft", {"id": "cut_block"}, sess)
	ok("станція" in String(sim.flash_msg), "live cat_craft flashes the no-station refusal via the router (R10)")
	ic.dispatch(&"cat_craft", {"id": "make_charcoal"}, sess)
	ok(int(sim.stock.get("charcoal", 0)) == 7, "live cat_craft runs the recipe on the LIVE stock (5 -> 7)")
	ic.dispatch(&"cat_research", {"id": "masonry"}, sess)
	ok(sess.started == ["masonry"], "live cat_research feeds the session research pipeline")
	# sandbox default is untouched: a flagless fake still reads the sandbox (badge stays «демо»)
	var sandbox_snap := HudModel.snapshot(_fake_session(), {"buildings": [], "stock": {}, "items": []}, {"day": 1}, Balance.Balance.new())
	ok(not bool(sandbox_snap.catalog.get("live", false)), "flag OFF keeps the sandbox catalog slice (shipped default)")
	sandbox.dispose()   # Thing<->Comp cycles (leak gate)

func _t_bom_tips() -> void:
	var db = CatalogView.default_db()
	# a thin stock affords almost nothing, so unlocked buildings surface as dimmed near-miss rows
	var snap: Dictionary = CatalogView.snapshot(db, {"unlocked": {}, "stock": {"wood": 3}})
	var builds: Array = snap.build_actions
	ok(builds.size() > 0, "build_actions surfaced with a thin stock (near-miss rows included, %d)" % builds.size())
	var all_tipped := true
	for r in builds:
		if not (r.has("tip") and r.has("enabled")) or String(r.tip) == "":
			all_tipped = false
	ok(all_tipped, "every build row carries a non-empty BOM tip + enabled flag (R8 value-data)")
	ok(_all_value_data(snap), "BOM-tipped slices are still pure value data (R8)")
	var near_found := false
	for r in builds:
		if not bool(r.enabled) and String(r.tip).begins_with("Потрібно ще:"):
			near_found = true
	ok(near_found, "an unaffordable building shows as a disabled 'Потрібно ще: …' near-miss row")
	# raw budget rolls a crafted input all the way down to raw resources (planner consumed)
	var bill := CatalogView.raw_bill_str(db, {"components": 1})
	ok(bill != "", "raw_bill_str expands a crafted input to a raw budget (%s)" % bill)
	# research rows advertise what they unlock
	var ra: Array = snap.research_actions
	ok(ra.size() > 0 and String(ra[0].tip).begins_with("Відкриє:"), "research rows tip names what the project unlocks")

# ---------------- PanelRegistry == SystemRegistry (sort/get/by_dock/bind_visible) ----------------
func _t_panel_registry() -> void:
	var reg = PanelReg.PanelRegistry.new()
	var a = Panels.StockPanel.new()      # priority 10, RIGHT
	var b = Panels.BalancePanel.new()    # priority 20, RIGHT
	var c = Panels.VitalsPanel.new()     # priority 10, LEFT
	reg.register(b); reg.register(a); reg.register(c)
	ok(reg.count() == 3 and reg.panels[0].priority <= reg.panels[2].priority, "registry sorts by priority (== SystemRegistry.add)")
	ok(reg.get_panel(&"stock") == a, "get_panel finds by id")
	ok(reg.by_dock(1).size() == 2, "by_dock returns the two RIGHT-dock panels")
	var sess = _fake_session()
	var snap := HudModel.snapshot(sess, {"buildings": [], "stock": sess.sim.stock, "items": []}, {"day": 5}, Balance.Balance.new())
	a.visible = true; b.visible = false
	var before: int = b.rebind_count
	reg.bind_visible(snap)
	ok(b.rebind_count == before, "bind_visible SKIPS a hidden panel (the view's tick_all)")
	ok(a.rebind_count > 0, "bind_visible binds the visible panel")
	a.free(); b.free(); c.free()

# ---------------- OverlayRegistry radio exclusivity + R6 contract ----------------
func _t_overlay_registry() -> void:
	var oreg = OverlayReg.OverlayRegistry.new()
	oreg.register(Overlays.LightOverlay.new())
	oreg.register(Overlays.TemperatureOverlay.new())
	ok(oreg.count() == 2, "two overlays registered (each supplied hotkey+legend per R6)")
	oreg.toggle(&"light")
	ok(oreg.is_on(&"light") and oreg.active_and_markers().size() == 1, "toggle light -> 1 active radio overlay")
	oreg.toggle(&"temperature")
	ok(oreg.is_on(&"temperature") and not oreg.is_on(&"light"), "radio exclusivity: temp on turns light off")
	oreg.toggle(&"temperature")
	ok(oreg.active_and_markers().size() == 0, "toggle temp again -> nothing active (radio off)")
	ok(oreg.legend_for_active().size() == 0, "no legend rows when no overlay active")

# ---------------- §3 hotkey contract: no panel may grab a LOCKED overlay key ----------------
# design-system §3 fixes the overlay keys (R/T/L/P/G/Z/F/K — "do not reassign"); a panel that grabs one
# steals a spatial toggle the player already learned (ResearchBrowser once sat on R). KEY_M is exempt:
# the LogisticsPanel is the current surface of the §3 "logistics map (modal)" slot until the modal
# exists. AGENTS.md states the rule; this tripwire enforces it (a rule without a tripwire is a wish).
func _t_hotkey_contract() -> void:
	var locked: Array = [KEY_R, KEY_T, KEY_L, KEY_P, KEY_G, KEY_Z, KEY_F, KEY_K]
	var preg = PanelReg.PanelRegistry.new()
	var oreg = OverlayReg.OverlayRegistry.new()
	Mechanics.register_all(preg, oreg)
	var no_locked := true
	var no_dupes := true
	var seen: Dictionary = {}
	for o in oreg.overlays:
		if o.hotkey != 0:
			seen[o.hotkey] = String(o.overlay_id)
	for p in preg.panels:
		if p.hotkey in locked:
			no_locked = false
			print("      panel '%s' grabs LOCKED §3 overlay key" % p.panel_id)
		if p.hotkey != 0:
			if seen.has(p.hotkey):
				no_dupes = false
				print("      hotkey clash: panel '%s' vs '%s'" % [p.panel_id, seen[p.hotkey]])
			seen[p.hotkey] = String(p.panel_id)
	ok(no_locked, "no registered panel sits on a LOCKED §3 overlay key (R/T/L/P/G/Z/F/K)")
	ok(no_dupes, "every registered hotkey is claimed exactly once across panels+overlays")
	for p in preg.panels:
		p.free()

# ---------------- FeedbackBus subscribers disconnect on free (R8 / §2.7 cycle-leak guard) ----------------
func _t_bus_no_dangling() -> void:
	var bus = FeedbackBus.FeedbackBus.new()
	var fw = Widgets.FeedWidget.new(); fw.subscribe(bus)
	var bw = Widgets.BannerWidget.new(); bw.subscribe(bus)
	var flw = Widgets.FlashWidget.new(); flw.subscribe(bus)
	ok(bus.feed.get_connections().size() == 1 and bus.banner.get_connections().size() == 1, "subscribers connect once")
	fw.free(); bw.free(); flw.free()
	ok(bus.feed.get_connections().size() == 0 and bus.banner.get_connections().size() == 0 and bus.flash.get_connections().size() == 0, "freeing subscribers leaves zero dangling connections (R8)")

# ---------------- WorldInput: the click/key grammar as a PURE function (main.gd parity, R12) ----------------
func _t_world_input_grammar() -> void:
	var WI := WorldInput.WorldInput
	# armed build wins over everything under the cursor
	var d: Dictionary = WI.decide_click([{"px": 5.1, "py": 5.1}], {0: {}}, 8, "wall", Vector2i(5, 5), 5.1, 5.1)
	ok(StringName(d.verb) == &"build" and String(d.args.kind) == "wall" and int(d.args.x) == 5, "armed build wins the click")
	# a raider within 0.7 tiles of the cursor -> attack, and the target is the raider dict itself
	var e := {"px": 3.2, "py": 3.2}
	d = WI.decide_click([e], {}, 8, "", Vector2i(3, 3), 3.0, 3.0)
	ok(StringName(d.verb) == &"order_attack" and d.args.target == e, "raider near the cursor -> attack")
	# a resource node under the cursor -> gather (tile index i = y*n + x)
	d = WI.decide_click([], {2 * 8 + 4: {"kind": "tree"}}, 8, "", Vector2i(4, 2), 4.5, 2.5)
	ok(StringName(d.verb) == &"order_gather" and int(d.args.y) == 2, "node under the cursor -> gather")
	# an OWN grow zone under the cursor -> cycle its crop (farming v2 verb)
	d = WI.decide_click([], {}, 8, "", Vector2i(4, 4), 4.5, 4.5, {4 * 8 + 4: true})
	ok(StringName(d.verb) == &"set_crop" and int(d.args.x) == 4, "grow zone under the cursor -> set_crop")
	# ...but a resource node on the same cell wins (gather beats crop-cycling)
	d = WI.decide_click([], {4 * 8 + 4: {"kind": "bush"}}, 8, "", Vector2i(4, 4), 4.5, 4.5, {4 * 8 + 4: true})
	ok(StringName(d.verb) == &"order_gather", "node wins over the grow zone on the same cell")
	# empty tile -> walk
	d = WI.decide_click([], {}, 8, "", Vector2i(6, 6), 6.5, 6.5)
	ok(StringName(d.verb) == &"order_move" and int(d.args.x) == 6, "empty tile -> move")
	# a distant raider must NOT hijack the walk
	d = WI.decide_click([{"px": 1.0, "py": 1.0}], {}, 8, "", Vector2i(6, 6), 6.5, 6.5)
	ok(StringName(d.verb) == &"order_move", "distant raider does not intercept the walk")
	# digit keys map to build-bar slots 1..9,0 (R12 keyboard-first)
	ok(WI.build_slot_for_key(KEY_1) == 0 and WI.build_slot_for_key(KEY_9) == 8
		and WI.build_slot_for_key(KEY_0) == 9 and WI.build_slot_for_key(KEY_SPACE) == -1,
		"digit keys map to build-bar slots (1..9,0)")

# ================= грабельність (playability) — the frame the player actually reads =================
# A flat 16×16 grass sim (Kyiv coordinates) for slices that need the real sim API.
func _live_sim(day: int = 195) -> Variant:
	var nn := 16
	var tiles := PackedByteArray()
	tiles.resize(nn * nn)
	tiles.fill(WorldGen.GRASS)
	var s = Sim.new()
	s.new_game({"n": nn, "tiles": tiles, "nodes": {}, "spawn": Vector2i(8, 8), "lat": 50.4501, "lon": 30.5234})
	s.time.day = day
	s.time.frac = 0.5
	s.patrol.next = 1e9
	return s

# ---- the input grammar the player's hands learn: pause, speed, painting runs ----
func _t_playability_grammar() -> void:
	var WI := WorldInput.WorldInput
	var r: Dictionary = WI.next_speed(1.0, 1.0, &"toggle_pause")
	ok(float(r.speed) == 0.0 and float(r.last) == 1.0, "Space pauses in ONE press (the old cycle needed three)")
	r = WI.next_speed(0.0, 2.0, &"toggle_pause")
	ok(float(r.speed) == 2.0, "Space resumes at the speed you paused from (×2)")
	ok(float(WI.next_speed(1.0, 1.0, &"faster").speed) == 2.0 and float(WI.next_speed(3.0, 3.0, &"faster").speed) == 3.0,
		"+ steps up and clamps at ×3")
	ok(float(WI.next_speed(2.0, 2.0, &"slower").speed) == 1.0 and float(WI.next_speed(1.0, 1.0, &"slower").speed) == 1.0,
		"− steps down and never pauses by accident")
	ok(float(WI.next_speed(0.0, 2.0, &"faster").speed) == 3.0, "+ while paused resumes one step faster")
	r = WI.next_speed(1.0, 1.0, &"set", 0.0)
	ok(float(r.speed) == 0.0 and float(r.last) == 1.0, "the ⏸ chip pauses and remembers the running speed")
	ok(WI.paintable("wall") and WI.paintable("floor") and WI.paintable("stone_wall") and WI.paintable("power_conduit"),
		"walls/floors/cables paint as runs (§5 drag = build run)")
	ok(not WI.paintable("workbench") and not WI.paintable("bed") and WI.paintable("bed", {"paint": true}),
		"single objects stay one-click unless a def opts in")
	var run: Array = WI.line_cells(Vector2i(0, 0), Vector2i(4, 0))
	ok(run.size() == 5 and run[0] == Vector2i(0, 0) and run[4] == Vector2i(4, 0), "a straight drag paints every cell of the run")
	var diag: Array = WI.line_cells(Vector2i(0, 0), Vector2i(2, 2))
	var four_conn := true
	for i in range(1, diag.size()):
		var d: Vector2i = diag[i] - diag[i - 1]
		if absi(d.x) + absi(d.y) != 1:
			four_conn = false
	ok(four_conn and diag[diag.size() - 1] == Vector2i(2, 2), "a diagonal drag stays 4-connected (no corner gap leaks room air)")

# ---- inspect = hover: the tooltip predicts the click ----
func _t_inspect_slice() -> void:
	var s = _live_sim()
	s.map.nodes[3 * 16 + 3] = {"kind": "tree", "amount": 12}
	var vm: Dictionary = HudModel._inspect_slice(s, {"hover": Vector2i(3, 3)})
	ok(bool(vm.shown) and "Дерево" in String(vm.title) and "12" in String(vm.lines[0]) and "ЛКМ" in String(vm.hint),
		"hovering a tree names it, its yield and the click")
	vm = HudModel._inspect_slice(s, {})
	ok(not bool(vm.shown), "no hover in ctx -> hidden tooltip")
	var bot: Dictionary = GameData.make_patrol_bot(10.5, 3.5, 1)
	s.enemies.append(bot)
	vm = HudModel._inspect_slice(s, {"hover": Vector2i(10, 3), "hover_world": Vector2(10.5, 3.4)})
	ok("робот" in String(vm.title) and "атакувати" in String(vm.hint), "hovering an enemy offers the attack")
	s.enemies.clear()
	s.map.tiles[5 * 16 + 5] = WorldGen.WATER
	vm = HudModel._inspect_slice(s, {"hover": Vector2i(5, 5), "selected_build": "wall"})
	ok(StringName(vm.state) == &"crit" and "вода" in " ".join(vm.lines), "a ghost over water says WHY it can't land")
	s.stock[s.res_key("stone")] = 0
	vm = HudModel._inspect_slice(s, {"hover": Vector2i(6, 6), "selected_build": "wall"})
	ok("бракує" in " ".join(vm.lines), "a ghost you can't afford names the shortfall")
	s.stock[s.res_key("stone")] = 30
	vm = HudModel._inspect_slice(s, {"hover": Vector2i(6, 6), "selected_build": "wall"})
	ok(StringName(vm.state) == &"good" and "затисни" in String(vm.hint), "a valid wall ghost is green and teaches the drag")
	vm = HudModel._inspect_slice(s, {"hover": Vector2i(9, 8)})   # the starting storage
	ok("розібрати" in String(vm.hint) or "єдиний склад" in String(vm.hint), "hovering a building explains deconstruction")
	vm = HudModel._inspect_slice(s, {"hover": Vector2i(1, 12)})
	ok("°C" in String(vm.lines[0]) and "іти" in String(vm.hint), "bare ground reads its temperature and the walk order")
	s.dispose_farm()
	s.dispose_power()

# ---- the §2.7 channels are MOUNTED in the playable frame (they used to exist only in tests) ----
func _t_feedback_mounted() -> void:
	var hr = HudRootScript.new()
	var bus = FeedbackBus.FeedbackBus.new()
	var preg = PanelReg.PanelRegistry.new()
	hr.setup(_fake_session(), Balance.Balance.new(), bus, preg, null)
	hr.mount()
	hr.mount()   # idempotent: a second mount must not double-subscribe
	ok(hr.feed_w != null and hr.flash_w != null and hr.banner_w != null and hr.tip_w != null, "HudRoot mounts feed/flash/banner/tooltip")
	ok(bus.feed.get_connections().size() == 1 and bus.flash.get_connections().size() == 1 and bus.banner.get_connections().size() == 1,
		"each channel subscribed exactly once")
	for i in 8:
		bus.feed.emit({"cls": "good", "text": "подія %d" % i})
	var vis: Array = hr.feed_w.visible_texts()
	ok(vis.size() == Widgets.FeedWidget.POOL and String(vis[vis.size() - 1]) == "подія 7", "the feed keeps a fixed pool, newest last")
	bus.flash.emit({"params": {"text": "Бракує: 🪨5"}})
	ok(hr.flash_w.text == "Бракує: 🪨5" and hr.flash_w.visible, "a refusal reaches the player as a flash")
	bus.banner.emit({"status": &"raid_incoming", "params": {"text": "⚠ НАБЛИЖАЄТЬСЯ РЕЙД"}})
	ok(hr.banner_w.visible and hr.banner_w.status == &"raid_incoming", "the raid banner shows with its urgency")
	hr.free()
	ok(bus.feed.get_connections().size() == 0, "freeing the HUD leaves no dangling feed subscriber")

# ---- top bar / goals / build bar / research reveal bound from a REAL session snapshot ----
func _t_frame_panels() -> void:
	var sess = SessionScript.new()
	sess.autosave = false
	sess.start(50.4501, 30.5234, "Київ")
	var snap: Dictionary = HudModel.snapshot(sess, HudModel.world_of(sess.sim), {"day": 1, "speed": 2.0, "selected_build": "wall"}, Balance.Balance.new())
	ok(String(snap.clock.season) == "зима" and float(snap.env.temp_c) < 0.0, "the snapshot carries the real season + outdoor °C (env was hardwired to 15°C)")
	var top = Panels.TopBarPanel.new()
	top.bind(snap)
	ok("День 1" in top._clock.text and "−" in top._temp.text and "Київ" in top._region.text, "top bar: day/clock, °C with a real minus, region")
	ok(top._chips[2].button_pressed and not top._chips[1].button_pressed, "top bar chips follow the live speed (×2)")
	var goals = Panels.GoalsPanel.new()
	goals.bind(snap)
	ok("багаття" in goals._title.text and "9" in goals._hint.text, "goals panel opens on «light a fire» and names the key")
	var bar = Panels.BuildBarPanel.new()
	bar.bind(snap)
	ok(bar._btns[0].button_pressed and not bar._btns[1].button_pressed, "build bar pressed state mirrors the armed ghost (digits sync)")
	var research = Panels.ResearchPanel.new()
	var preg = PanelReg.PanelRegistry.new()
	preg.register(research)
	research.visible = research.default_open
	preg.bind_visible(snap)
	ok(not research.visible, "research panel waits for its first bench (design-system §2 first relevance)")
	sess.sim._place_building("research_bench", 3, 3, -1)
	snap = HudModel.snapshot(sess, HudModel.world_of(sess.sim), {"day": 1}, Balance.Balance.new())
	preg.bind_visible(snap)
	ok(research.visible and research.revealed, "…and pips into view once a bench works")
	research.visible = false
	preg.bind_visible(snap)
	ok(not research.visible, "after the reveal the player owns its visibility (no re-pop)")
	for pnl in [top, goals, bar, research]:
		pnl.free()
	sess.sim.dispose_farm()
	sess.sim.dispose_power()

# ---- one truth: the night the player SEES == the light the work penalty USES; the heat map == temp_at ----
func _t_one_truth_overlays() -> void:
	var s = _live_sim()
	s.time.frac = 0.95   # deep night
	s._place_building("torch", 4, 4, -1)
	s._place_building("campfire", 11, 11, -1)
	for w in [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1)]:
		s._place_building("wall", w.x, w.y, -1)
	s._place_building("door", 2, 3, -1)
	var snap: Dictionary = HudModel.snapshot(_session_of(s), HudModel.world_of(s), {"day": 195}, null)
	var lt: Dictionary = snap.light
	var heat: Dictionary = snap.heat
	var indoor: Dictionary = {}
	for c in heat.indoor:
		indoor[int(c)] = true
	var light_ok := true
	var heat_ok := true
	for y in 16:
		for x in 16:
			if absf(Overlays.Lit.tile_light(float(lt.ambient), lt.sources, x, y) - s.light_at(x, y)) > 0.001:
				light_ok = false
			if absf(Overlays.TemperatureOverlay.tile_temp(heat, indoor, x, y, 16) - s.temp_at(x, y)) > 0.001:
				heat_ok = false
	ok(light_ok and lt.sources.size() == 2, "night shade light == sim.light_at on every tile (torch + campfire pools)")
	ok(heat_ok and indoor.has(2 * 16 + 2), "heat map == sim.temp_at on every tile (room buffering + emitters)")
	s.dispose_farm()
	s.dispose_power()

func _session_of(sim) -> Variant:
	var fs := _FakeSession.new()
	fs.sim = sim
	return fs

# ================= мобільний UI (touch frame) — phones get the same game through fingers =================
func _t_touch_grammar() -> void:
	var WI := WorldInput.WorldInput
	ok(WI.classify_release(0.12, false, false) == &"tap", "a short still touch is a tap (it acts)")
	ok(WI.classify_release(0.8, false, false) == &"inspect", "a still hold past LONG_PRESS inspects instead of acting")
	ok(WI.classify_release(0.12, true, false) == &"none" and WI.classify_release(0.12, false, true) == &"none",
		"a drag or a pinch never acts")
	ok(is_equal_approx(WI.ui_scale(96.0, Vector2(1280, 720)), 1.0), "desktop keeps the authored scale")
	var phone: float = WI.ui_scale(400.0, Vector2(2400, 1080))
	ok(phone > 1.5 and phone < 1.9, "a 400 dpi 20:9 phone scales the canvas up (×%.2f) so text keeps ~14sp" % phone)
	ok(is_equal_approx(WI.ui_scale(280.0, Vector2(2560, 1600)), 1.0), "a 10\" tablet keeps the desktop layout")
	var rt := String(WI.REMOVE_TOOL)
	var d: Dictionary = WI.decide_click([], {2 * 8 + 3: {"kind": "tree"}}, 8, rt, Vector2i(3, 2), 3.5, 2.5)
	ok(StringName(d.verb) == &"deconstruct", "the armed remove tool turns a tap into deconstruct (touch's right button)")
	ok(WI.paintable(rt), "the remove tool sweeps runs like walls do")
	ok(Fmt.touchify("ЛКМ — рубати · повну торбу пішак сам віднесе на склад").begins_with("тап — рубати"),
		"tooltips speak touch on a phone (ЛКМ -> тап)")
	ok(Fmt.touchify("Натисни 9 (Багаття) і клікни біля пішака.") == "Вибери внизу 9 (Багаття) і торкнись біля пішака.",
		"goal hints name the bottom bar and a touch, not a key and a click")

func _t_touch_frame() -> void:
	var sess = SessionScript.new()
	sess.autosave = false
	sess.start(50.4501, 30.5234, "Київ")
	var preg = PanelReg.PanelRegistry.new()
	var oreg = OverlayReg.OverlayRegistry.new()
	Mechanics.register_all(preg, oreg)
	var hr = HudRootScript.new()
	hr._build_zones()   # headless: no _ready (not in the tree) — build the dock zones the mount fills
	hr.setup(sess, Balance.Balance.new(), FeedbackBus.FeedbackBus.new(), preg, oreg)
	hr.set_compact(true)
	hr.mount()
	ok(hr.dock_top > 40.0, "compact docks start under the top strip")
	ok(not preg.get_panel(&"balance").visible and preg.get_panel(&"stock").visible and preg.get_panel(&"goals").visible,
		"a phone opens the essentials (stock/vitals/goals) and keeps the threat gauge in the menu")
	var labelled := 0
	for p in preg.panels:
		if String(p.menu_label) != "":
			labelled += 1
	var menu = Widgets.PanelMenu.new()
	var entries: Array = []
	for p in preg.panels:
		if String(p.menu_label) != "":
			entries.append({"kind": &"panel", "id": p.panel_id, "label": String(p.menu_label)})
	for o in oreg.overlays:
		entries.append({"kind": &"overlay", "id": o.overlay_id, "label": String(o.menu_label)})
	menu.setup(entries)
	ok(labelled >= 15 and menu.entry_count() == entries.size(), "the ☰ menu offers every labelled panel + both overlays (%d)" % menu.entry_count())
	var snap: Dictionary = HudModel.snapshot(sess, HudModel.world_of(sess.sim), {"day": 1, "touch": true, "selected_build": String(WorldInput.WorldInput.REMOVE_TOOL)}, null)
	ok(bool(snap.ui.touch) and bool(snap.ui.remove), "the ui slice carries the touch flag and the armed remove tool")
	var top = preg.get_panel(&"top_bar")
	top.bind(snap)
	ok(top._tool_box.visible and not top._region.visible, "touch top strip shows the tools (☰ ✖ 🗑 − +) and drops the region label")
	ok(top._tools[2].button_pressed, "the 🗑 tool reads armed")
	var vit = preg.get_panel(&"vitals")
	vit.bind(snap)
	ok(vit._meds.size() == 4 and not vit._carry.visible, "phone vitals: need medallions, no carry token (no bars)")
	var c := Vector2i(int(sess.sim.player.px), int(sess.sim.player.py))
	var store: Vector2i = sess.sim.base_center()
	var rm: Dictionary = HudModel._inspect_slice(sess.sim, {"hover": store, "touch": true, "selected_build": String(WorldInput.WorldInput.REMOVE_TOOL)})
	ok("єдиний склад" in " ".join(rm.lines), "the remove tool warns before the last storage")
	sess.sim._place_building("bed", c.x + 2, c.y + 2, -1)
	rm = HudModel._inspect_slice(sess.sim, {"hover": Vector2i(c.x + 2, c.y + 2), "touch": true, "selected_build": String(WorldInput.WorldInput.REMOVE_TOOL)})
	ok("назад:" in " ".join(rm.lines) and "торкнись" in String(rm.hint), "the remove tool shows the refund and the touch verb")
	menu.free()
	hr.free()
	sess.sim.dispose_farm()
	sess.sim.dispose_power()

# ---------------- Основна капсула, UI (spec 0010 W4a: REQ-0010-16/36/37/38/41/86/87/90) ----------------
const CAPSULE_NOW_MS := 1700000000000

func _capsule_session(on: bool) -> Variant:
	var s: Variant = SessionScript.new()
	s.autosave = false
	s.use_inventory = true
	s.use_catalog = on
	s.use_main_capsule = on
	ok(bool(s.start(50.4501, 30.5234, "Київ", CAPSULE_NOW_MS)), "capsule ui: %s session starts" % ("ON" if on else "OFF"))
	return s

func _cap_snap(s: Variant, ctx: Dictionary = {}) -> Dictionary:
	var c: Dictionary = {"day": int(s.sim.time.day)}
	c.merge(ctx, true)
	return HudModel.snapshot(s, {"buildings": [], "stock": s.sim.stock, "items": []}, c, Balance.Balance.new())

# Перша нестача за алфавітом, яку квота обіцяє, і віддати героєві рівно ціну осі (щоб натиснути «Прокачати» по-справжньому).
func _grant_cost(s: Variant, axis: StringName) -> void:
	var q: Dictionary = CapsuleMod.quote(s.sim, axis)
	for res in q.cost:
		InventoryMod.add(s.sim, String(res), int(q.cost[res]))

func _t_capsule_ui() -> void:
	var s: Variant = _capsule_session(true)
	var sim: Variant = s.sim
	var snap: Dictionary = _cap_snap(s)
	var main: Dictionary = snap.capsule.get("main", {})
	ok(not main.is_empty() and bool(main.active) and int(main.level) == 0 and int(main.protection) == 0, "REQ-0010-41: ON snapshot carries capsule.main (level 0, protection 0)")
	ok(int(main.max) == CapsuleMod.max_level(sim) and int(main.max_protection) == CapsuleMod.max_protection(sim), "REQ-0010-86: maxima come from the data tables, not from the view")
	# R8: value data only
	ok(not _holds_object(main), "R8: capsule.main is value data (no live refs)")
	# OFF: no main key at all — the OFF panel path is byte-for-byte what it was
	var off: Variant = _capsule_session(false)
	ok(not _cap_snap(off).capsule.has("main"), "REQ-0010-41: OFF snapshot has no capsule.main (charges/radius/launch rows stay)")
	# --- the panel ---
	var panel: Variant = WorldPanels.CapsulePanel.new()
	get_root().add_child(panel)
	await process_frame
	panel.bind(snap)
	ok(not panel._status.visible and not panel._launch.visible and not panel._coords.visible and not panel._inv_head.visible,
		"REQ-0010-41: ON panel hides the charge/radius status, coordinate launch and invites")
	var inv_hidden := true
	for r in panel._invite_rows:
		inv_hidden = inv_hidden and not bool(r.visible)
	ok(inv_hidden, "REQ-0010-41: ON panel hides every invite row")
	ok(panel._m_levels.visible and "Рівень 0/%d" % int(main.max) in String(panel._m_levels.text) and "Захист 0/%d" % int(main.max_protection) in String(panel._m_levels.text),
		"panel: both axes are said in words with N/max")
	ok(panel._m_up.visible and panel._m_up.theme_type_variation == UITheme.V_PRIMARY, "REQ-0010-37/86: «Прокачати» is the ONE filled primary action")
	ok(not panel._m_prot.visible or not panel._m_more_box.visible, "REQ-0010-86 (D1): «Захист» and «Склад» are folded under «Ще» until opened")
	var filled_ref: Array = [0]
	_count_primary(panel, filled_ref)
	ok(int(filled_ref[0]) == 1, "REQ-0010-37: the panel has exactly one filled button")
	ok(panel.default_open == false and panel.compact_open == 0, "REQ-0010-37: the capsule panel is not a permanent HUD element")
	var rb: int = int(panel.rebuild_count)
	for i in 5:
		panel.bind(_cap_snap(s))
	ok(int(panel.rebuild_count) == rb, "R2: ON panel is built once and only rebound")
	# --- refusal = the first reason in words, ONE truth in panel and flash (REQ-0010-38) ---
	# the start kit pays level 1 outright — empty the pack and the stock so the refusal path is the one under test
	sim.stock.clear()
	for sl in sim.player.inv:
		sl.id = ""
		sl.n = 0
	main = _cap_snap(s).capsule.main
	panel.bind(_cap_snap(s))
	var why: String = String(main.upgrade.why)
	ok(why.begins_with("Бракує: ") and "×" in why and String(panel._m_up_why.text) == why and panel._m_up_why.visible,
		"REQ-0010-38: the unaffordable upgrade shows its first reason in words (%s)" % why)
	var router := InputCtl.InputController.new()
	InputVerbsMod.install(router)
	var intents: Array = []
	panel.intent.connect(func(verb: StringName, args: Dictionary) -> void: intents.append(verb))
	panel._m_up.pressed.emit()
	ok(intents == [&"capsule_upgrade"], "REQ-0010-38: ONE tap on the filled button emits one intent, no keyboard")
	for v in intents:
		router.dispatch(v, {}, s)
	ok(sim.flash_msg == why and int(sim.main_capsule.level) == 0, "REQ-0010-38: the refusal flashes the same first reason; nothing is spent")
	# --- success through the router (R9) ---
	_grant_cost(s, &"capsule")
	panel.bind(_cap_snap(s))
	ok(bool(_cap_snap(s).capsule.main.upgrade.can) and not panel._m_up_why.visible, "panel: with the price in the backpack the reason row is gone")
	panel._m_up.pressed.emit()
	router.dispatch(intents[intents.size() - 1], {}, s)
	ok(int(sim.main_capsule.level) == 1 and sim.flash_msg == "◎ Капсула: рівень 1", "REQ-0010-36: capsule_upgrade through the router raises the level (%s)" % sim.flash_msg)
	var m1: Dictionary = _cap_snap(s).capsule.main
	panel.bind(_cap_snap(s))
	ok(int(m1.level) == 1 and "Рівень 1/" in String(panel._m_levels.text), "REQ-0010-87: the level shown follows the sim (1)")
	# protection axis: a separate verb, a separate row
	_grant_cost(s, &"protection")
	panel._on_more()
	panel.bind(_cap_snap(s))
	ok(panel._m_more_box.visible and panel._m_prot.visible, "REQ-0010-86: «Ще» reveals «Захист»")
	panel._m_prot.pressed.emit()
	router.dispatch(intents[intents.size() - 1], {}, s)
	ok(intents[intents.size() - 1] == &"capsule_protect" and CapsuleMod.protection_of(sim) == 1 and int(sim.main_capsule.level) == 1,
		"REQ-0010-36/100: capsule_protect raises ONLY the protection axis")
	# --- actions by state (REQ-0010-86) ---
	sim.main_capsule.level = CapsuleMod.max_level(sim)
	sim.main_capsule.protection = 0
	var mx: Dictionary = _cap_snap(s).capsule.main
	panel.bind(_cap_snap(s))
	ok(not (mx.actions as Array).has(&"upgrade") and (mx.actions as Array).has(&"protection") and not panel._m_up.visible and panel._m_prot.visible,
		"REQ-0010-86: level 5 — «Прокачати» is gone, «Захист» stays")
	sim.main_capsule.protection = CapsuleMod.max_protection(sim)
	panel.bind(_cap_snap(s))
	ok(not panel._m_prot.visible and (_cap_snap(s).capsule.main.actions as Array).has(&"storage"), "REQ-0010-86: protection 5 — «Захист» is gone, «Склад» stays")
	ok(not (mx.actions as Array).has(&"safe_zone") and not (mx.actions as Array).has(&"reinforcement"),
		"REQ-0010-86: no safe-zone/reinforcement action while the 0011 seam is a stub (no unavailable actions shown)")
	# --- storage rows: take through the router ---
	sim.main_capsule.level = 0
	sim.main_capsule.protection = 0
	InventoryMod.add(sim, "wood", 4)
	InventoryMod.stash_all(sim)
	if not panel._m_more_open:
		panel._on_more()
	panel.bind(_cap_snap(s))
	ok(panel._m_stash.visible and panel._m_store_rows[0].visible, "panel: «Склад» lists the stock under «Ще»")
	var got: Array = []
	panel.intent.connect(func(verb: StringName, args: Dictionary) -> void: got.append([verb, args]))
	panel._on_store(0)
	ok(got.size() == 1 and got[0][0] == &"take_storage" and int(got[0][1].n) == 10, "panel: a storage row emits take_storage (10)")
	# --- ring (REQ-0010-16): only when selected or warned ---
	ok(not bool(_cap_snap(s).capsule.main.ring.show), "REQ-0010-16: no ring without a selection or a raid warning")
	var rs: Dictionary = _cap_snap(s, {"open_panels": ["capsule_bay"]}).capsule.main.ring
	ok(bool(rs.show) and not bool(rs.alert) and int(rs.radius) == CapsuleMod.zone_radius(sim), "REQ-0010-16: ring shows with the panel open, radius = the static data radius")
	var tile: Vector2i = CapsuleMod.tile(sim)
	ok(int(rs.x) == tile.x and int(rs.y) == tile.y, "REQ-0010-16: ring is centred on the capsule cell")
	sim.capsule_raid.state = "warning"
	var ra: Dictionary = _cap_snap(s).capsule.main.ring
	ok(bool(ra.show) and bool(ra.alert), "REQ-0010-16: a raid warning shows the ring (alert) without any selection")
	sim.capsule_raid.state = "none"
	var lv_radii: Array = []
	for lv in [0, 3, 5]:
		sim.main_capsule.level = lv
		sim.main_capsule.protection = 5 - lv
		lv_radii.append(int(_cap_snap(s, {"open_panels": ["capsule_bay"]}).capsule.main.ring.radius))
	ok(lv_radii[0] == lv_radii[1] and lv_radii[1] == lv_radii[2], "REQ-0010-16: ring radius is the same for every level and protection")
	# --- tap on the capsule opens its panel; no «Розібрати» (REQ-0010-36/37) ---
	var cap_cell: int = tile.y * int(sim.n) + tile.x
	ok(sim.bgrid.has(cap_cell) and String(sim.building_def(CapsuleMod.KIND).get("panel", "")) == "capsule_bay", "the capsule def names its panel (data, not a controller special-case)")
	var d: Dictionary = WorldInput.WorldInput.decide_click([], {}, int(sim.n), "", tile, tile.x + 0.5, tile.y + 0.5, {}, {cap_cell: "capsule_bay"})
	ok(StringName(d.verb) == &"open_panel" and String(d.args.id) == "capsule_bay", "REQ-0010-37: one tap on the capsule -> open_panel")
	d = WorldInput.WorldInput.decide_click([], {}, int(sim.n), "wall", tile, tile.x + 0.5, tile.y + 0.5, {}, {cap_cell: "capsule_bay"})
	ok(StringName(d.verb) == &"build", "decide_click: an armed build still wins over a landmark")
	d = WorldInput.WorldInput.decide_click([], {}, int(sim.n), "", tile, tile.x + 0.5, tile.y + 0.5)
	ok(StringName(d.verb) == &"order_move", "decide_click: the optional landmark arg keeps the old signature's behaviour")
	var t: Dictionary = AM.target_at(sim, tile, &"gather")
	var pv: Dictionary = AM.primary(&"gather", t, "", sim)
	ok(StringName(pv.get("verb", &"")) == &"open_panel", "touch action button on the capsule opens its panel")
	var verbs: Array = []
	for o in AM.options(sim, t):
		verbs.append(StringName(o.verb))
	ok(verbs.has(&"open_panel") and not verbs.has(&"deconstruct"), "REQ-0010-06/36: the radial offers the panel and no «Розібрати»")
	# --- inspect ---
	var ins: Dictionary = _cap_snap(s, {"hover": tile}).inspect
	ok(bool(ins.shown) and String(ins.title) == "Основна капсула" and not ("розібрати" in String(ins.hint).to_lower()), "inspect: the capsule says what it is and does not offer «розібрати»")
	var insr: Dictionary = _cap_snap(s, {"hover": tile, "selected_build": WorldInput.WorldInput.REMOVE_TOOL}).inspect
	ok("не розбирається" in str(insr.lines), "inspect: the remove tool says the capsule cannot be removed")
	# --- immunity + raid lines are words, not gender-marked ---
	sim.main_capsule.immune_until = int(sim.now_ms) + 5400000
	panel.bind(_cap_snap(s))
	ok(panel._m_immune.visible and "1 год 30 хв" in String(panel._m_immune.text), "panel: the immunity window is said in hours and minutes")
	# --- greybox hull marks are drawn from the sim levels, six distinguishable states per axis (REQ-0010-87) ---
	ok(CapsuleMod.max_level(sim) == 5 and CapsuleMod.max_protection(sim) == 5, "REQ-0010-87: six states per axis (0..5)")
	var wv: Variant = WorldViewScript.new()
	wv.sim = sim
	ok(wv.has_method("_draw_capsule_marks"), "REQ-0010-87: world_view draws the greybox level lamps / protection plates / immunity bubble (no art, P4)")
	wv.free()
	panel.queue_free()
	await process_frame

func _count_primary(node: Node, acc: Array) -> void:
	if node is Button and (node as Button).visible and (node as Button).theme_type_variation == UITheme.V_PRIMARY:
		acc[0] = int(acc[0]) + 1
	for c in node.get_children():
		_count_primary(c, acc)

func _holds_object(v: Variant) -> bool:
	if v is Object:
		return true
	if v is Dictionary:
		for k in v:
			if _holds_object(v[k]):
				return true
	if v is Array:
		for e in v:
			if _holds_object(e):
				return true
	return false

# REQ-0010-37/90 (P9): the permanent-element set is the same at OFF and ON and within the design-system budget.
func _t_capsule_budget() -> void:
	var preg := PanelReg.PanelRegistry.new()
	var oreg := OverlayReg.OverlayRegistry.new()
	Mechanics.register_all(preg, oreg)
	var perm: Array = []
	for p in preg.panels:
		var open_compact: bool = bool(p.default_open) if int(p.compact_open) < 0 else int(p.compact_open) == 1
		if bool(p.default_open) or open_compact:
			perm.append(String(p.panel_id))
	var cap: Variant = preg.get_panel(&"capsule_bay")
	ok(cap != null and not perm.has("capsule_bay"), "REQ-0010-37: capsule_bay is not in the permanent set")
	var doc: String = _read(ProjectSettings.globalize_path("res://") + "../docs/ux/design-system.md")
	var rx := RegEx.new()
	rx.compile("Ліміт:\\s*(\\d+)")
	var m: RegExMatch = rx.search(doc)
	ok(m != null, "REQ-0010-90: design-system.md states the permanent-element budget")
	var budget: int = int(m.get_string(1)) if m != null else 0
	ok(perm.size() <= budget and budget == 16, "REQ-0010-37/90: permanent elements (%d) <= the design-system budget (%d)" % [perm.size(), budget])
	# the overlay for the ring owns no hotkey/menu entry and is not a registry radio overlay (an always-on marker like NightShade)
	var ring: Variant = Overlays.CapsuleRing.new()
	ok(not bool(ring.radio) and int(ring.hotkey) == 0 and String(ring.menu_label) == "", "REQ-0010-37: the zone ring is a marker with no hotkey and no menu entry")
	var named := false
	for o in oreg.overlays:
		named = named or String(o.overlay_id) == "capsule_ring"
	ok(not named, "REQ-0010-37: the zone ring is not a registered overlay (no new toggle)")
	for p in preg.panels:
		p.free()   # Control nodes are not refcounted: unparented panels would leak at exit


# ---------------- QA-adversary, spec 0010 W4a: атаки від REQ, а не від реалізації ----------------
func _hash(s: Variant) -> String:
	return String(PersistenceMod.world_hash(s.sim))

func _cap_router() -> Variant:
	var router := InputCtl.InputController.new()
	InputVerbsMod.install(router)
	return router

# Скинути торбу й склад (старт-кіт оплачує рівень 1 сам).
func _cap_poor(s: Variant) -> void:
	s.sim.stock.clear()
	for sl in s.sim.player.inv:
		sl.id = ""
		sl.n = 0

func _cap_far(s: Variant) -> void:
	var t: Vector2i = CapsuleMod.tile(s.sim)
	s.sim.player.px = float(mini(int(s.sim.n) - 2, t.x + CapsuleMod.zone_radius(s.sim) + 6)) + 0.5
	s.sim.player.py = float(t.y) + 0.5
	ok(not CapsuleMod.in_zone(s.sim, CapsuleMod.hero_cell(s.sim)), "adv setup: the hero stands outside the zone")

func _t_capsule_adv() -> void:
	var router: Variant = _cap_router()
	# --- D9 «що бачить гравець == що рахує сим»: slice.can/why проти справжнього результату дії, у 4 станах ---
	for axis in [&"capsule", &"protection"]:
		var verb: StringName = &"capsule_upgrade" if axis == &"capsule" else &"capsule_protect"
		var key: String = "upgrade" if axis == &"capsule" else "protect"
		for state in ["empty", "pack", "stock_near", "stock_far"]:
			var s: Variant = _capsule_session(true)
			_cap_poor(s)
			if state != "empty":
				_grant_cost(s, axis)
			if state.begins_with("stock"):
				InventoryMod.stash_all(s.sim)
			if state == "stock_far":
				_cap_far(s)
			var ax: Dictionary = _cap_snap(s).capsule.main[key]
			var h0: String = _hash(s)
			s.sim.flash_msg = ""
			var lvl0: int = int(s.sim.main_capsule.level)
			router.dispatch(verb, {}, s)
			var raised: bool = int(s.sim.main_capsule.level) > lvl0 or CapsuleMod.protection_of(s.sim) > 0
			var expect_can: bool = state == "pack" or state == "stock_near"
			ok(bool(ax.can) == expect_can, "D9 %s/%s: the panel's can (%s) says what the sim would do" % [axis, state, str(ax.can)])
			ok(raised == bool(ax.can), "D9 %s/%s: the tap raised the axis iff the panel said it could" % [axis, state])
			if not bool(ax.can):
				ok(_hash(s) == h0, "REQ-0010-38 %s/%s: a refusal leaves world_hash untouched (no partial spend)" % [axis, state])
				ok(String(ax.why) != "" and s.sim.flash_msg == String(ax.why), "REQ-0010-38 %s/%s: the flash is exactly the panel's first reason (%s)" % [axis, state, str(s.sim.flash_msg)])
				ok(String(ax.why).begins_with("Бракує: "), "REQ-0010-38 %s/%s: the reason is in words" % [axis, state])
				if state == "stock_far":
					ok("підійди" in String(ax.why), "REQ-0010-38 %s: far from the zone the reason says to walk back" % axis)
			else:
				ok(String(ax.why) == "", "D9 %s/%s: an affordable axis carries no reason" % [axis, state])
	# --- мертвий герой: відмова словами, без побічних ефектів ---
	var dead: Variant = _capsule_session(true)
	_grant_cost(dead, &"capsule")
	dead.sim.dead = true
	var hd: String = _hash(dead)
	dead.sim.flash_msg = ""
	router.dispatch(&"capsule_upgrade", {}, dead)
	ok(int(dead.sim.main_capsule.level) == 0 and _hash(dead) == hd and dead.sim.flash_msg != "", "REQ-0010-38: a dead hero's tap is refused in words, nothing is spent")
	# --- макс-рівні: повтор тапу після L5 нічого не робить і каже чому ---
	var mx: Variant = _capsule_session(true)
	mx.sim.main_capsule.level = CapsuleMod.max_level(mx.sim)
	var hm: String = _hash(mx)
	mx.sim.flash_msg = ""
	router.dispatch(&"capsule_upgrade", {}, mx)
	ok(_hash(mx) == hm and mx.sim.flash_msg != "", "REQ-0010-86: a stale tap on «Прокачати» at max is refused in words, no change")
	# --- twin: однакові тапи -> однаковий світ і однаковий slice (детермінізм) ---
	var a: Variant = _capsule_session(true)
	var b: Variant = _capsule_session(true)
	for sx in [a, b]:
		_grant_cost(sx, &"capsule")
		router.dispatch(&"capsule_upgrade", {}, sx)
		_grant_cost(sx, &"protection")
		router.dispatch(&"capsule_protect", {}, sx)
		router.dispatch(&"capsule_upgrade", {}, sx)
	ok(_hash(a) == _hash(b), "REQ-0010-36: the same taps on twin sessions give the same world_hash")
	ok(var_to_str(_cap_snap(a).capsule.main) == var_to_str(_cap_snap(b).capsule.main), "twin sessions give the same capsule slice")
	# --- відкриття панелі — view, не sim: хеш не рухається; open_panel не на дроті ---
	var h_open: String = _hash(a)
	var d: Dictionary = WorldInput.WorldInput.decide_click([], {}, int(a.sim.n), "", CapsuleMod.tile(a.sim), 1.0, 1.0, {}, {CapsuleMod.tile(a.sim).y * int(a.sim.n) + CapsuleMod.tile(a.sim).x: "capsule_bay"})
	ok(StringName(d.verb) == &"open_panel" and _hash(a) == h_open, "REQ-0010-36: the tap's decision is a view verb and never touches the sim")
	var Cmd: Variant = load("res://scripts/net/command.gd")
	ok(not Cmd.WIRE_VERBS.has("open_panel"), "REQ-0010-36: open_panel is a view verb, not a wire verb")
	# --- сліпий інструмент «Розібрати» на капсулі: відмова, капсула стоїть ---
	var tile: Vector2i = CapsuleMod.tile(a.sim)
	var hr: String = _hash(a)
	router.dispatch(&"deconstruct", {"x": tile.x, "y": tile.y}, a)
	ok(a.sim.bgrid.has(tile.y * int(a.sim.n) + tile.x) and _hash(a) == hr, "REQ-0010-06: the remove tool on the capsule changes nothing")
	# --- save/load посеред: slice після round-trip через JSON той самий ---
	var wire: Dictionary = JSON.parse_string(JSON.stringify(PersistenceMod.resume_payload(a.sim)))
	var r: Variant = _capsule_session(true)
	PersistenceMod.restore(r.sim, wire)
	var m_a: Dictionary = _cap_snap(a, {"open_panels": ["capsule_bay"]}).capsule.main
	var m_r: Dictionary = _cap_snap(r, {"open_panels": ["capsule_bay"]}).capsule.main
	for k in ["level", "protection", "max", "max_protection", "actions", "ring", "upgrade", "protect"]:
		ok(var_to_str(m_a[k]) == var_to_str(m_r[k]), "save/load: capsule.main.%s survives the round trip" % k)
	# --- кільце: стани автомата ---
	for st in ["none", "cancelled", "resolved"]:
		a.sim.capsule_raid.state = st
		ok(not bool(_cap_snap(a).capsule.main.ring.show), "REQ-0010-16: raid state «%s» without a selection shows no ring" % st)
	a.sim.capsule_raid.state = "contact"
	var rc: Dictionary = _cap_snap(a).capsule.main.ring
	ok(bool(rc.show) and bool(rc.alert), "REQ-0010-16: contact shows the ring as an alert")
	a.sim.capsule_raid.state = "none"
	ok(not bool(_cap_snap(a, {"open_panels": ["gear", "stock"]}).capsule.main.ring.show), "REQ-0010-16: other open panels do not summon the ring")
	var sel: Dictionary = _cap_snap(a, {"open_panels": ["capsule_bay"]}).capsule.main.ring
	ok(not bool(sel.alert), "REQ-0010-16: a plain selection is not an alert")
	a.sim.main_capsule.immune_until = int(a.sim.now_ms) + 1000
	ok(not bool(_cap_snap(a).capsule.main.ring.show), "REQ-0010-16: the immunity shield alone does not summon the zone ring")
	a.sim.main_capsule.immune_until = 0

	# --- панель: стани дій (REQ-0010-86) × одна залита кнопка (REQ-0010-37) ---
	var panel: Variant = WorldPanels.CapsulePanel.new()
	get_root().add_child(panel)
	await process_frame
	var fresh: Variant = _capsule_session(true)
	var combos: Array = [[0, 0], [0, 5], [5, 0], [5, 5], [3, 2]]
	for c in combos:
		fresh.sim.main_capsule.level = c[0]
		fresh.sim.main_capsule.protection = c[1]
		var sn: Dictionary = _cap_snap(fresh)
		panel.bind(sn)
		var acts: Array = sn.capsule.main.actions
		ok(acts.has(&"upgrade") == (c[0] < 5) and acts.has(&"protection") == (c[1] < 5), "REQ-0010-86 L%d/P%d: actions follow the axes" % [c[0], c[1]])
		ok(panel._m_up.visible == (c[0] < 5) and panel._m_prot.visible == (c[1] < 5), "REQ-0010-86 L%d/P%d: no button for a vanished action" % [c[0], c[1]])
		var fr: Array = [0]
		_count_primary(panel, fr)
		ok(int(fr[0]) == (1 if c[0] < 5 else 0), "REQ-0010-37 L%d/P%d: at most ONE filled button (%d)" % [c[0], c[1], int(fr[0])])
		ok("Рівень %d/5" % c[0] in String(panel._m_levels.text) and "Захист %d/5" % c[1] in String(panel._m_levels.text), "M5 L%d/P%d: the printed levels equal the sim" % [c[0], c[1]])
		ok(not panel._m_up.visible or ("рівень %d" % (c[0] + 1)) in String(panel._m_up.text), "M5 L%d: the button names the NEXT level" % c[0])
	# --- щит і рейд-рядки зникають разом зі станом (текст не залишається неправдою) ---
	fresh.sim.main_capsule.immune_until = int(fresh.sim.now_ms) + 60000
	panel.bind(_cap_snap(fresh))
	ok(panel._m_immune.visible, "panel: immunity row shown while the window is open")
	fresh.sim.main_capsule.immune_until = 0
	panel.bind(_cap_snap(fresh))
	ok(not panel._m_immune.visible, "M5: the immunity row disappears when the window closes")
	fresh.sim.capsule_raid.state = "warning"
	panel.bind(_cap_snap(fresh))
	ok(panel._m_raid.visible, "panel: a raid warning is said in the panel")
	fresh.sim.capsule_raid.state = "none"
	panel.bind(_cap_snap(fresh))
	ok(not panel._m_raid.visible, "M5: the raid row disappears when the state returns to none")
	# --- жодних зарядів/радіусу в тексті усіх видимих міток при ON ---
	var leak := false
	for n in _all_labels(panel):
		if n.is_visible_in_tree() or n.visible:
			var t: String = String(n.text)
			leak = leak or "Зарядів" in t or " км" in t or "Запуск" in t or "Інвайт" in t
	ok(not leak, "REQ-0010-41: no visible label at ON speaks of charges, km, launch or invites")
	# --- перемикання ON -> OFF на тій самій панелі повертає легасі й ховає ON-вузли ---
	var off: Variant = _capsule_session(false)
	panel.bind(_cap_snap(off))
	var main_hidden := true
	for n in panel._m_nodes:
		main_hidden = main_hidden and not bool(n.visible)
	ok(main_hidden and panel._status.visible and panel._launch.visible and panel._coords.visible and panel._inv_head.visible,
		"REQ-0010-41: OFF binding restores the charge rows and hides every ON node")
	# свіжа OFF-панель: жодного ON-вузла
	var p2: Variant = WorldPanels.CapsulePanel.new()
	get_root().add_child(p2)
	await process_frame
	p2.bind(_cap_snap(off))
	var any_main := false
	for n in p2._m_nodes:
		any_main = any_main or bool(n.visible)
	ok(not any_main and p2._status.visible, "REQ-0010-41: a fresh OFF panel shows no ON node")
	ok(String(p2._status.text).begins_with("Зарядів:"), "REQ-0010-41: OFF keeps the charge text")
	var ck: Array = _cap_snap(off).capsule.keys()
	ck.sort()
	ok(ck == ["charges", "invites", "radius_km"], "REQ-0010-41: the OFF capsule slice has exactly its old keys (%s)" % str(ck))
	# --- склад: ліміт 6 рядків не може сховати ресурс мовчки? (лише фіксуємо поведінку: рядки відповідають запасу) ---
	var stk: Variant = _capsule_session(true)
	_cap_poor(stk)
	InventoryMod.add(stk.sim, "wood", 3)
	InventoryMod.stash_all(stk.sim)
	var rows: Array = _cap_snap(stk).capsule.main.storage
	var total := 0
	for rw in rows:
		total += int(rw.n)
	var real_total := 0
	for k in stk.sim.stock:
		real_total += int(stk.sim.stock[k])
	ok(total == real_total, "D9: the storage rows add up to the real stock (%d vs %d)" % [total, real_total])
	p2.queue_free()
	panel.queue_free()
	await process_frame

func _all_labels(node: Node) -> Array:
	var out: Array = []
	if node is Label or node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_labels(c))
	return out

func _t_capsule_adv_pure() -> void:
	# --- decide_click: позамежові клітинки не повинні псевдонімити в клітинку-орієнтир (індекс y*n+x) ---
	var n := 56
	var lm := {55: "capsule_bay"}   # клітинка (55, 0)
	var d: Dictionary = WorldInput.WorldInput.decide_click([], {}, n, "", Vector2i(-1, 1), -0.5, 1.5, {}, lm)
	ok(StringName(d.verb) != &"open_panel", "REQ-0010-37: a tap left of the map (-1,1) does not alias to the landmark cell (55,0)")
	d = WorldInput.WorldInput.decide_click([], {}, n, "", Vector2i(n, -1), float(n) + 0.5, -0.5, {0: "capsule_bay"}, {0: "capsule_bay"})
	ok(StringName(d.verb) != &"open_panel", "REQ-0010-37: a tap above-right of the map (56,-1) does not alias to the landmark cell (0,0)")
	# --- ворог біля капсули не краде тап?  (граматика: атака має пріоритет — фіксуємо, що рішення детерміноване і не падає) ---
	d = WorldInput.WorldInput.decide_click([], {}, n, "", Vector2i(3, 3), 3.5, 3.5, {}, {3 * n + 3: "capsule_bay"})
	ok(StringName(d.verb) == &"open_panel" and String(d.args.id) == "capsule_bay", "REQ-0010-37: the tap on the landmark cell opens the panel it names")
	d = WorldInput.WorldInput.decide_click([], {}, n, "", Vector2i(4, 3), 4.5, 3.5, {}, {3 * n + 3: "capsule_bay"})
	ok(StringName(d.verb) == &"order_move", "REQ-0010-37: the neighbour cell still walks")
	d = WorldInput.WorldInput.decide_click([], {}, n, String(WorldInput.WorldInput.REMOVE_TOOL), Vector2i(3, 3), 3.5, 3.5, {}, {3 * n + 3: "capsule_bay"})
	ok(StringName(d.verb) == &"deconstruct", "decide_click: the armed remove tool is the tool's verb even over a landmark (the sim refuses it)")
	# --- Fmt: ПЕРША причина = перший ключ за алфавітом, незалежно від порядку вставки ---
	var w: String = Fmt.capsule_shortfall({"wood": 8, "stone": 2, "iron": 1}, false)
	ok(w.begins_with("Бракує: ") and w.count("×") == 1 and "×1" in w, "REQ-0010-38: only the first (alphabetical) missing resource is named, once (%s)" % w)
	ok(Fmt.capsule_shortfall({}, false) == "" and Fmt.capsule_shortfall({}, true) == "", "Fmt: nothing missing -> no reason, even if far")
	ok(not ("підійди" in Fmt.capsule_shortfall({"wood": 1}, false)) and "підійди" in Fmt.capsule_shortfall({"wood": 1}, true), "Fmt: the walk-back hint appears only when far")
	ok(Fmt.left_ms(0) == "0 хв" and Fmt.left_ms(1) == "1 хв" and Fmt.left_ms(60000) == "1 хв" and Fmt.left_ms(60001) == "2 хв" and Fmt.left_ms(3600000) == "1 год 0 хв" and Fmt.left_ms(-5) == "0 хв",
		"Fmt.left_ms: ceil to the minute, never negative")
	# --- роутер: усі причини відмови мають слова, крім duplicate ---
	for rsn in [&"cost", &"max", &"no_capsule", &"dead"]:
		var r: Dictionary = {"ok": false, "reason": rsn, "missing": {"wood": 1}, "far": false}
		ok(InputVerbsMod.capsule_result_text(r) != "", "REQ-0010-38: refusal «%s» is said in words" % rsn)
	ok(InputVerbsMod.capsule_result_text({"ok": true, "axis": &"protection", "protection": 3}) != InputVerbsMod.capsule_result_text({"ok": true, "axis": &"capsule", "level": 3}),
		"REQ-0010-87 (D5): the two axes are named differently in the flash")
	# --- бюджет: число в design-system і текст «Зараз їх N» не брешуть (M5) ---
	var preg := PanelReg.PanelRegistry.new()
	var oreg := OverlayReg.OverlayRegistry.new()
	Mechanics.register_all(preg, oreg)
	var perm := 0
	for p in preg.panels:
		if bool(p.default_open) or int(p.compact_open) == 1:
			perm += 1
	var doc: String = _read(ProjectSettings.globalize_path("res://") + "../docs/ux/design-system.md")
	var rx := RegEx.new()
	rx.compile("Зараз їх (\\d+)")
	var m: RegExMatch = rx.search(doc)
	ok(m != null and int(m.get_string(1)) == perm, "M5/REQ-0010-90: design-system says «Зараз їх N» and N equals the real permanent set (%d)" % perm)
	var capsule_ids := 0
	for p in preg.panels:
		if "capsule" in String(p.panel_id):
			capsule_ids += 1
	ok(capsule_ids == 1, "REQ-0010-37: the capsule added exactly one (non-permanent) panel, no second one")
	for p in preg.panels:
		p.free()
	# --- P4: арт не згенеровано до G0–G1 ---
	var man: String = _read(ProjectSettings.globalize_path("res://") + "../art/manifest.json").to_lower()
	ok(not ("main_capsule" in man), "REQ-0010-87 (P4): no art-manifest entry for the main capsule before G0-G1")

# ---------------- Rule tripwires: R1/R3/R4/R7/R9/R10 as literal grep tests (the spec's whole point) ----------------
# --- REQ-0010-10/40/85/27(UI): тексти смерті, спавну й панелі при ON, tripwire застарілих тверджень, OFF-рядки дослівно ---
func _all_texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append(String((n as Label).text))
	elif n is Button:
		out.append(String((n as Button).text))
	if n is Control:
		out.append(String((n as Control).tooltip_text))
	for c in n.get_children():
		_all_texts(c, out)
	return out

func _stale_hits(lines: Array) -> Array:
	var hits: Array = []
	for ln in lines:
		var low: String = String(ln).to_lower()
		for bad in CapsuleTexts.FORBIDDEN_ON:
			if String(bad) in low:
				hits.append("%s <- %s" % [bad, String(ln).left(60)])
	return hits

# Усі `const MSG*` з файлу (рядки sim-шару: R1 не пускає їх у ui, тож tripwire читає вихідник).
func _msg_consts(path: String) -> Array:
	var rx := RegEx.new()
	rx.compile("(?m)^const (MSG\\w*)\\s*:=\\s*\"(.*)\"")
	var out: Array = []
	for m in rx.search_all(_read_code(path)):
		out.append(m.get_string(2))
	return out

func _t_capsule_texts() -> void:
	# --- ключі: таблиця не порожня, кожен рядок заповнений, forbidden-список сам не вироджений ---
	ok(CapsuleTexts.TEXTS.size() >= 10 and CapsuleTexts.FORBIDDEN_ON.size() >= 4, "REQ-0010-85: the capsule text table is keyed and the tripwire list is not empty")
	var keys_ok := true
	for k in CapsuleTexts.TEXTS:
		if String(CapsuleTexts.TEXTS[k]) == "" or String(CapsuleTexts.t(String(k))) != String(CapsuleTexts.TEXTS[k]):
			keys_ok = false
	ok(keys_ok, "REQ-0010-85: every key resolves to a non-empty string")
	# --- статичний скан за КЛЮЧАМИ таблиці й за const MSG* sim-модулів капсули ---
	var table_lines: Array = []
	for k in CapsuleTexts.TEXTS:
		table_lines.append(String(CapsuleTexts.TEXTS[k]))
	ok(_stale_hits(table_lines).is_empty(), "REQ-0010-40/85: no capsule text key carries a stale claim (%s)" % str(_stale_hits(table_lines)))
	var sim_lines: Array = _msg_consts("res://scripts/sim/capsule.gd") + _msg_consts("res://scripts/sim/hero_health.gd")
	ok(sim_lines.size() >= 8, "REQ-0010-85: the scan sees the sim-side capsule messages (%d)" % sim_lines.size())
	ok(_stale_hits(sim_lines).is_empty(), "REQ-0010-40/85: sim capsule MSG_* carry no stale claim (%s)" % str(_stale_hits(sim_lines)))
	# нові рядки капсули не лишаються розсипом по view-файлах: імунітет — лише через таблицю
	ok(not ("Імунітет" in _read_code("res://scripts/ui/world_panels.gd")) and not ("імунітет" in _read_code("res://scripts/ui/hud_model.gd")),
		"REQ-0010-85: the immunity strings live in capsule_texts.gd only")
	# --- динамічний скан ON: спавн (холод) -> панель з імунітетом і тривогою -> смерть -> екран смерті -> респавн ---
	var s: Variant = _capsule_session(true)
	var sim: Variant = s.sim
	var live: Array = []
	sim.messages.clear()
	sim.time.frac = 0.0
	sim.spawn_hint()
	var cold: bool = sim.hero_felt_c() < HeroHealthMod.Gear.COMFORT_MIN_C
	for m in sim.messages:
		live.append(String(m.text))
	if cold:
		ok("укриття біля капсули" in " ".join(live) and not ("багаття" in " ".join(live)), "REQ-0010-40: the ON cold spawn hint sends to a shelter by the capsule, not to «campfire first»")
	else:
		ok(true, "REQ-0010-40: spawn hint — felt temperature is inside the comfort band (no hint) [skipped]")
	var panel: Variant = WorldPanels.CapsulePanel.new()
	get_root().add_child(panel)
	await process_frame
	sim.main_capsule.immune_until = int(sim.now_ms) + 5400000
	sim.capsule_raid.state = String(CapsuleMod.ST_WARNING)
	panel.bind(_cap_snap(s, {"open_panels": ["capsule_bay"]}))
	var panel_lines: Array = _all_texts(panel)
	ok(_stale_hits(panel_lines).is_empty(), "REQ-0010-40: the ON capsule panel carries no stale claim (%s)" % str(_stale_hits(panel_lines)))
	panel.queue_free()
	sim.main_capsule.immune_until = 0
	sim.capsule_raid.state = String(CapsuleMod.ST_NONE)
	sim.player.born = 1
	sim.time.day = 3
	sim.last_death = {"cause": "переохолодження", "day": 3, "born": 1}
	InventoryMod.add(sim, "wood", 5)
	sim._on_death()
	var snap: Dictionary = _cap_snap(s)
	ok(bool(snap.death.get("capsule", false)) and not _holds_object(snap.death), "REQ-0010-10: the ON death slice carries capsule:true as value data")
	var ds: Variant = LifecycleScript.DeathScreen.new()
	get_root().add_child(ds)
	await process_frame
	ds.bind(snap.death)
	var death_lines: Array = _all_texts(ds)
	ok(_stale_hits(death_lines).is_empty(), "REQ-0010-10/40: the ON death screen carries no stale claim (%s)" % str(_stale_hits(death_lines)))
	var death_text: String = " ".join(death_lines)
	ok("З'явитись у капсулі" in death_text and "біля капсули" in death_text and "позначена на мапі" in death_text, "REQ-0010-10: the ON death screen leads to the capsule and shows the bag marker")
	ok(not ("Торба лежить" in death_text) and not ("годин" in death_text) and not ("підбере" in death_text.to_lower()), "REQ-0010-10: no promise about the bag's fate or TTL (blocked on Q-10(a))")
	for bad in ["загинув", "загинула", "з'явився", "з'явилась"]:
		ok(not (bad in death_text.to_lower()), "D8: the ON death text has no grammatical gender («%s»)" % bad)
	for m in sim.messages:
		live.append(String(m.text))
	s.respawn()
	for m in s.sim.messages:
		live.append(String(m.text))
	ok(_stale_hits(live).is_empty(), "REQ-0010-40: ON feed lines (spawn, death, respawn) carry no stale claim (%s)" % str(_stale_hits(live)))
	# --- OFF: ті самі екрани, рядки смерті/кнопка/підказка ДОСЛІВНО як до спеки ---
	var off: Variant = _capsule_session(false)
	var off_snap: Dictionary = _cap_snap(off)
	ok(not off_snap.death.has("capsule"), "REQ-0010-85: the OFF death slice has no capsule key")
	var DS = LifecycleScript.DeathScreen
	ok(DS._fate({"inventory": true, "bag_items": 18}) == "Торба (18 предм.) лежить на місці загибелі — вона позначена на мапі, її можна забрати.\nПоселення й склад лишаються. Новий виживальник прибуде туди й почне з нуля.", "REQ-0010-85: OFF death fate (bag) is verbatim")
	ok(DS._fate({"inventory": true, "bag_items": 0}) == "Рюкзак був порожній — втрачати нічого.\nПоселення й склад лишаються. Новий виживальник прибуде туди й почне з нуля.", "REQ-0010-85: OFF death fate (empty pack) is verbatim")
	ok(DS._fate({}) == "Усе, що було при собі, втрачено.\nПоселення й склад лишаються. Новий виживальник прибуде туди й почне з нуля.", "REQ-0010-85: OFF death fate (classic) is verbatim")
	ok(DS._lesson("переохолодження") == "Порада: багаття, а навколо — стіни з дверима: у приміщенні тепло тримається.", "REQ-0010-85: OFF cold lesson is verbatim")
	ok(DS._lesson("") == "Порада: тримай тепло, їжу й сон — і будуй оборону до 5-го дня.", "REQ-0010-85: OFF default lesson is verbatim")
	# кнопка: bind(ON) -> «З'явитись у капсулі», наступний bind(OFF) повертає «Новий виживальник» (екран живе між сесіями)
	ds.bind(off_snap.death)
	ok(String(ds._btn.text) == "Новий виживальник", "REQ-0010-85: the OFF button is «Новий виживальник»")
	ds.bind(snap.death)
	ok(String(ds._btn.text) == "З'явитись у капсулі", "REQ-0010-10: the ON button is set in bind, not in _ready")
	ds.queue_free()
	var hint_src: String = FileAccess.get_file_as_string("res://scripts/sim/hero_health.gd")
	ok("постав багаття з хотбару (слот 1), потім стіни з дверима навколо" in hint_src and "розпали багаття (9), а тоді обнеси клітинку стінами (1) з дверима (2)" in hint_src, "REQ-0010-85: the OFF spawn hints are verbatim")
	off.sim.messages.clear()
	off.sim.time.frac = 0.0
	off.sim.spawn_hint()
	if off.sim.hero_felt_c() < HeroHealthMod.Gear.COMFORT_MIN_C:
		ok("постав багаття з хотбару (слот 1)" in str(off.sim.messages), "REQ-0010-85: the OFF cold spawn hint still sends to the campfire")

# --- REQ-0010-95: жодна дія капсули не заблокована невиконаною ціллю; обов'язкового ланцюга капсула не створює ---
func _t_capsule_no_goal_gates() -> void:
	var Goals = load("res://scripts/goals.gd")
	var router: Variant = _cap_router()
	var s: Variant = _capsule_session(true)
	ok((s.goals_done as Dictionary).is_empty(), "REQ-0010-95: a fresh ON session has completed no goal")
	_grant_cost(s, &"capsule")
	var acts: Array = []
	for a in CapsuleMod.actions(s.sim):
		acts.append(a)
	ok(acts.has(&"upgrade") and acts.has(&"storage"), "REQ-0010-95: capsule actions are offered with zero goals done")
	router.dispatch(&"capsule_upgrade", {}, s)
	ok(int(s.sim.main_capsule.level) == 1, "REQ-0010-95: the upgrade works with every goal unfinished (no goal gate)")
	_grant_cost(s, &"protection")
	router.dispatch(&"capsule_protect", {}, s)
	ok(CapsuleMod.protection_of(s.sim) == 1, "REQ-0010-95: the protection axis works with every goal unfinished")
	InventoryMod.add(s.sim, "wood", 3)
	router.dispatch(&"stash_all", {}, s)
	ok(int(s.sim.stock.get(s.sim.res_key("wood"), 0)) >= 3, "REQ-0010-95: the stash works with every goal unfinished")
	# жодного коду ланцюга цілей на шляху капсули; жодного запису-орієнтиру з порядковим номером/залежністю
	for f in ["res://scripts/sim/capsule.gd", "res://scripts/ui/input_verbs.gd", "res://scripts/ui/world_panels.gd", "res://scripts/ui/capsule_texts.gd"]:
		var body: String = _read_code(f).to_lower()
		ok(not ("goals_done" in body) and not ("goals.gd" in body) and not ("current_goal" in body), "REQ-0010-95: %s does not read the goal chain" % f.get_file())
	var capsule_goal := false
	for g in Goals.GOALS:
		var gd: Dictionary = g
		if "капсул" in String(gd.title).to_lower() or "capsule" in str(gd.get("id", "")) or gd.has("requires") or gd.has("after") or gd.has("step"):
			capsule_goal = true
	ok(not capsule_goal, "REQ-0010-95: the capsule adds no mandatory goal and no goal entry carries a dependency/ordinal")

# --- W4b (qa-adversary): атаки на tripwire, щит імунітету, ON-смерть з порожньою торбою, стаб-спавн, чистоту знімка, гейти цілей ---
class _SpawnStub extends RefCounted:
	var use_main_capsule := false
	var use_inventory := true
	var felt := -10.0
	var logs: Array = []
	func hero_felt_c() -> float:
		return felt
	func _log(t: String, _k: String = "") -> void:
		logs.append(t)

func _visible_texts(n: Node, out: Array = []) -> Array:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return out
	if n is Label:
		out.append(String((n as Label).text))
	elif n is Button:
		out.append(String((n as Button).text))
	for c in n.get_children():
		_visible_texts(c, out)
	return out

func _t_capsule_w4b_adv() -> void:
	# --- tripwire чутливий: кожна заборонена фраза зі спеки §2 п.6 ловиться (без регістру), схвалені рядки — ні ---
	for bad in ["Щоденна капсула", "Новий виживальник", "до 5-го дня", "Постав БАГАТТЯ першим кроком"]:
		ok(not _stale_hits([bad]).is_empty(), "REQ-0010-40: the tripwire catches «%s»" % bad)
	ok(_stale_hits(["З'явитись у капсулі", "збудуй укриття біля капсули"]).is_empty(), "REQ-0010-40: the tripwire does not flag the approved ON lines")
	# --- статичний скан УСІХ рядкових літералів capsule.gd (не лише const MSG*): inline _log-рядки теж під tripwire ---
	var lit := RegEx.new()
	lit.compile("\"([^\"\\n]*)\"")
	var lits: Array = []
	for m in lit.search_all(_read_code("res://scripts/sim/capsule.gd")):
		var t: String = m.get_string(1)
		if " " in t or (t.length() > 0 and t.unicode_at(0) > 127):
			lits.append(t)
	ok(lits.size() >= 8, "REQ-0010-85: the literal scan of capsule.gd sees its text (%d)" % lits.size())
	ok(_stale_hits(lits).is_empty(), "REQ-0010-40/85: no string literal in sim/capsule.gd carries a stale claim (%s)" % str(_stale_hits(lits)))
	# D8: жодних родових форм у таблиці, літералах capsule.gd і MSG hero_health
	var gendered := ["загинув", "загинула", "з'явився", "з'явилась", "прибув", "прибула", "померла"]
	var every: Array = lits.duplicate()
	for k in CapsuleTexts.TEXTS:
		every.append(String(CapsuleTexts.TEXTS[k]))
	every += _msg_consts("res://scripts/sim/hero_health.gd")
	var g_hits: Array = []
	for ln in every:
		for w in gendered:
			if w in String(ln).to_lower():
				g_hits.append(w)
	ok(g_hits.is_empty(), "D8: ON capsule texts carry no grammatical gender (%s)" % str(g_hits))
	# --- спавн-підказка: детермінований стаб (не залежить від клімату) ---
	var on := _SpawnStub.new()
	on.use_main_capsule = true
	HeroHealthMod.spawn_hint(on)
	ok(on.logs.size() == 1 and "укриття" in on.logs[0] and "капсул" in on.logs[0] and not ("багаття" in String(on.logs[0]).to_lower()), "REQ-0010-40: ON cold spawn hint = shelter by the capsule, no campfire (stub)")
	ok(_stale_hits(on.logs).is_empty(), "REQ-0010-40: the ON spawn hint passes the tripwire")
	var off_inv := _SpawnStub.new()
	HeroHealthMod.spawn_hint(off_inv)
	ok(off_inv.logs.size() == 1 and "постав багаття з хотбару (слот 1)" in off_inv.logs[0], "REQ-0010-85: OFF+inventory spawn hint is the campfire one (stub)")
	var off_cls := _SpawnStub.new()
	off_cls.use_inventory = false
	HeroHealthMod.spawn_hint(off_cls)
	ok(off_cls.logs.size() == 1 and "розпали багаття (9)" in off_cls.logs[0], "REQ-0010-85: OFF classic spawn hint is the campfire one (stub)")
	var warm := _SpawnStub.new()
	warm.use_main_capsule = true
	warm.felt = 20.0
	HeroHealthMod.spawn_hint(warm)
	ok(warm.logs.is_empty(), "REQ-0010-40: no spawn hint inside the comfort band even at ON")
	# --- екран смерті ON: порожня торба, слайс без last_death, ON->OFF->ON перемикання bind ---
	var DS = LifecycleScript.DeathScreen
	var empty_on: String = DS._fate({"capsule": true, "inventory": true, "bag_items": 0})
	ok("Рюкзак був порожній" in empty_on and "біля капсули" in empty_on and _stale_hits([empty_on]).is_empty(), "REQ-0010-10: ON death with an empty pack leads to the capsule, no stale claim")
	ok(not ("Торба (" in empty_on), "REQ-0010-10: ON empty-pack death does not mention a bag")
	var bag_on: String = DS._fate({"capsule": true, "inventory": true, "bag_items": 7})
	ok("(7 предм.)" in bag_on and "позначена на мапі" in bag_on, "REQ-0010-10: ON death shows the bag count and map marker")
	ok(DS._fate({"capsule": false, "inventory": true, "bag_items": 18}) == DS._fate({"inventory": true, "bag_items": 18}), "REQ-0010-85: capsule:false is exactly the OFF text")
	for c in ["переохолодження", "голод", "тепловий удар", "втрата крові", ""]:
		var l: String = DS._lesson(c, true)
		ok(l != "" and _stale_hits([l]).is_empty(), "REQ-0010-40: ON lesson for «%s» is stale-free" % c)
		ok(DS._lesson(c) == DS._lesson(c, false), "REQ-0010-85: the lesson defaults to the OFF text for «%s»" % c)
	var sx: Variant = _capsule_session(true)
	var fresh_slice: Dictionary = _cap_snap(sx).death
	ok(bool(fresh_slice.get("capsule", false)), "REQ-0010-10: the ON death slice carries capsule:true even before any death")
	var ds: Variant = LifecycleScript.DeathScreen.new()
	get_root().add_child(ds)
	await process_frame
	ds.bind(fresh_slice)
	ok(String(ds._btn.text) == "З'явитись у капсулі", "REQ-0010-10: ON button on a death-less slice")
	ds.bind({"cause": "переохолодження", "day": 2, "lived": 2})
	ok(String(ds._btn.text) == "Новий виживальник" and not ("капсул" in String(ds._what.text)), "REQ-0010-85: a slice without the capsule key restores the OFF screen (no ON leak)")
	ok(String(ds._epitaph.text) == "Порада: багаття, а навколо — стіни з дверима: у приміщенні тепло тримається.", "REQ-0010-85: the OFF bind restores the OFF lesson verbatim (epitaph does not keep the ON branch)")
	ds.bind(fresh_slice)
	ok(String(ds._btn.text) == "З'явитись у капсулі" and _stale_hits(_all_texts(ds)).is_empty(), "REQ-0010-10: ON again after OFF, tripwire clean")
	ds.queue_free()
	# --- щит і рядок імунітету (REQ-0010-27 UI): рівно поки діє, зникає на межі ---
	var s: Variant = _capsule_session(true)
	var sim: Variant = s.sim
	var panel: Variant = WorldPanels.CapsulePanel.new()
	get_root().add_child(panel)
	await process_frame
	panel.bind(_cap_snap(s, {"open_panels": ["capsule_bay"]}))
	ok(int(_cap_snap(s).capsule.main.immune_left_ms) == 0 and not ("Імунітет" in " ".join(_visible_texts(panel))), "REQ-0010-27: no immunity line without immunity")
	ok(not ("імунітет" in " ".join(HudModel._inspect_capsule(sim).lines).to_lower()), "REQ-0010-27: the inspector has no immunity line without immunity")
	var now: int = int(sim.now_ms)
	sim.main_capsule.immune_until = now + 90 * 60000
	var sn: Dictionary = _cap_snap(s, {"open_panels": ["capsule_bay"]})
	ok(int(sn.capsule.main.immune_left_ms) == 90 * 60000, "REQ-0010-27: the snapshot carries the exact remaining ms")
	panel.bind(sn)
	var vis: String = " ".join(_visible_texts(panel))
	ok("Імунітет" in vis and "1 год 30 хв" in vis, "REQ-0010-27: the panel row shows the remaining time (%s)" % vis)
	ok("імунітет ще 1 год 30 хв" in " ".join(HudModel._inspect_capsule(sim).lines), "REQ-0010-27: the inspector row shows the remaining time")
	sim.main_capsule.immune_until = now + 1
	ok(CapsuleMod.is_immune(sim) and int(_cap_snap(s).capsule.main.immune_left_ms) == 1, "REQ-0010-27: one ms before the end the capsule is still immune")
	sim.main_capsule.immune_until = now
	var edge: Dictionary = _cap_snap(s, {"open_panels": ["capsule_bay"]})
	panel.bind(edge)
	ok(not CapsuleMod.is_immune(sim) and int(edge.capsule.main.immune_left_ms) == 0 and not ("Імунітет" in " ".join(_visible_texts(panel))), "REQ-0010-27: at immune_until == now the shield and the row are gone")
	sim.main_capsule.immune_until = now - 5000
	ok(int(_cap_snap(s).capsule.main.immune_left_ms) == 0, "REQ-0010-27: an expired mark never yields a negative remaining time")
	# щит у world_view: гейт is_immune прямо перед бульбашкою (greybox, без тексту)
	var wv_src: String = _read_code("res://scripts/world_view.gd")
	var at: int = wv_src.find("func _draw_capsule_marks")
	var body: String = wv_src.substr(at, wv_src.find("\nfunc ", at + 10) - at)
	var gate: int = body.find("\tif MainCapsule.is_immune(sim):\n\t\tdraw_circle(")
	ok(gate > 0 and body.find("draw_arc", gate) > gate and body.count("is_immune") == 1, "REQ-0010-27: the shield is drawn only under is_immune (no unconditional bubble)")
	ok(not ("draw_string" in body), "REQ-0010-27/87: the shield and marks carry no text (diegetic)")
	# знімок — чисте читання
	sim.main_capsule.immune_until = now + 90 * 60000
	var h0: String = PersistenceMod.world_hash(sim)
	var a1: Dictionary = _cap_snap(s, {"open_panels": ["capsule_bay"]})
	var a2: Dictionary = _cap_snap(s, {"open_panels": ["capsule_bay"]})
	ok(PersistenceMod.world_hash(sim) == h0, "REQ-0010-27: HudModel.snapshot (ON) does not touch the sim (world_hash stable)")
	ok(JSON.stringify(a1.capsule) == JSON.stringify(a2.capsule) and JSON.stringify(a1.death) == JSON.stringify(a2.death), "REQ-0010-27: the capsule/death slices are deterministic")
	# --- панель у всіх станах: рівень 0 / 1 / макс × тривога/контакт — без застарілих рядків і без гейтів ---
	sim.main_capsule.immune_until = 0
	for lvl in [0, 1, CapsuleMod.max_level(sim)]:
		sim.main_capsule.level = lvl
		for st in [CapsuleMod.ST_NONE, CapsuleMod.ST_WARNING, CapsuleMod.ST_CONTACT]:
			sim.capsule_raid.state = String(st)
			panel.bind(_cap_snap(s, {"open_panels": ["capsule_bay"]}))
			var hits: Array = _stale_hits(_all_texts(panel))
			ok(hits.is_empty(), "REQ-0010-40: panel L%d/%s is stale-free (%s)" % [lvl, st, str(hits)])
			var low: String = " ".join(_all_texts(panel)).to_lower()
			ok(not ("спершу" in low) and not ("виконай ціль" in low), "REQ-0010-95: panel L%d/%s gates nothing behind a goal" % [lvl, st])
	panel.queue_free()
	# OFF: жодного capsule.main, жодного capsule у слайсі смерті
	var off: Variant = _capsule_session(false)
	var osn: Dictionary = _cap_snap(off)
	ok(not osn.capsule.has("main") and not osn.death.has("capsule"), "REQ-0010-85: OFF slices carry no capsule keys")
	# --- ON-логи рейду (попередження) під tripwire ---
	var r: Variant = _capsule_session(true)
	r.sim.messages.clear()
	var fr: Dictionary = CapsuleMod.force_raid(r.sim, true)
	ok(bool(fr.get("ok", false)), "REQ-0010-40: the dev raid hook arms a raid (log scan fixture)")
	CapsuleMod._announce(r.sim, int(r.sim.now_ms))
	var raid_lines: Array = []
	for m in r.sim.messages:
		raid_lines.append(String(m.text))
	ok(raid_lines.size() >= 1 and _stale_hits(raid_lines).is_empty(), "REQ-0010-40: ON raid feed lines are stale-free (%s)" % str(raid_lines))
	# --- REQ-95: той самий результат дії з порожніми й з УСІМА виконаними цілями ---
	var Goals = load("res://scripts/goals.gd")
	var router: Variant = _cap_router()
	var done: Variant = _capsule_session(true)
	for g in Goals.GOALS:
		done.goals_done[String(g.id)] = true
	var none: Variant = _capsule_session(true)
	_grant_cost(done, &"capsule")
	_grant_cost(none, &"capsule")
	router.dispatch(&"capsule_upgrade", {}, done)
	router.dispatch(&"capsule_upgrade", {}, none)
	ok(int(done.sim.main_capsule.level) == 1 and int(none.sim.main_capsule.level) == 1 and PersistenceMod.world_hash(done.sim) == PersistenceMod.world_hash(none.sim),
		"REQ-0010-95: capsule upgrade is identical with no goals done and with all goals done (twin hash)")

func _t_rule_tripwires() -> void:
	# R1 — one-way flow: no sim/kernel/session/social/persistence file references res://scripts/ui
	var sim_side := ["res://scripts/sim.gd", "res://scripts/session.gd", "res://scripts/social.gd",
		"res://scripts/persistence.gd", "res://scripts/world_gen.gd", "res://scripts/kernel/balance.gd",
		"res://scripts/catalog_sim.gd", "res://scripts/data_bridge.gd"]
	var r1 := true
	for f in sim_side:
		if "res://scripts/ui" in _read_code(f):
			r1 = false
	ok(r1, "R1: sim/kernel/session/social/persistence never reference res://scripts/ui")
	# R3 — no raw color/stylebox under ui/ except tokens.gd + theme.gd
	var ui_files := ["widgets.gd", "panels.gd", "overlays.gd", "hud_model.gd", "hud_root.gd",
		"panel.gd", "widget.gd", "overlay.gd", "feedback_bus.gd", "format.gd", "view_geom.gd",
		"catalog_view.gd", "catalog_panels.gd", "world_input.gd", "lifecycle.gd", "world_panels.gd"]
	var r3 := true
	for f in ui_files:
		var body := _read_code("res://scripts/ui/" + f)   # comment-stripped: doc comments may mention them
		if "Color.html(" in body or "StyleBoxFlat.new(" in body or "Color(" in body:
			r3 = false
			printerr("  R3 leak in ", f)
	ok(r3, "R3: no raw Color()/Color.html()/StyleBoxFlat.new() outside tokens.gd + theme.gd")
	# R4 — the thin controller names no mechanic
	var hud := _read_code("res://scripts/ui/hud_root.gd")
	var mechs := ["raid", "convoy", "capsule", "social", "craft", "power", "research", "stock", "logistics"]
	var r4 := true
	for m in mechs:
		if m in hud:
			r4 = false
	ok(r4, "R4: hud_root.gd contains no mechanic name (registered, not hand-wired)")
	# R7 — resize-safe anchoring only via pin_* (no raw .position/PRESET_TOP_RIGHT in panels/widgets/overlays)
	var r7 := true
	for f in ["panels.gd", "widgets.gd", "overlays.gd", "catalog_panels.gd", "lifecycle.gd", "world_panels.gd"]:
		var body := _read_code("res://scripts/ui/" + f)
		if ".position =" in body or "PRESET_TOP_RIGHT" in body:
			r7 = false
	ok(r7, "R7: no raw .position/PRESET_TOP_RIGHT in panels/widgets/overlays (pin_* only)")
	# R9 — sim commands appear only in the router, never in panels/widgets
	var cmds := ["try_build", "demolish", "craft_item", "dispatch_convoy", "try_launch_capsule",
		"order_move", "order_gather", "order_attack", "accept_invite",
		"upgrade_capsule", "upgrade_protection", "call_reinforcement"]   # spec 0010 REQ-0010-36: sim-імена капсули — лише в роутері
	var r9 := true
	for f in ["panels.gd", "widgets.gd", "catalog_panels.gd", "lifecycle.gd", "world_panels.gd"]:
		var body := _read_code("res://scripts/ui/" + f)
		for cmd in cmds:
			if cmd in body:
				r9 = false
	ok(r9, "R9: panels/widgets call no sim mutator (only the InputController does)")
	# R9-addendum — world_input.gd легітимно НАЗИВАЄ verb-и (order_move...), тож у списку вище його
	# нема; але прямі сим-поля йому заборонені: єдиний санкціонований канал — sim.move_input.
	# Ловимо ".player." (наказ пішки колись писався тут напряму) і сирі доступи до складу.
	var wi := _read_code("res://scripts/ui/world_input.gd")
	ok(not (".player." in wi) and not (".stock" in wi),
		"R9: world_input touches no sim fields beyond the move_input channel")
	# R10 — only feedback_bus.gd drains the sim push channels. Target sim-field reads precisely:
	# .flash_msg/.flash_t/.messages are sim-only names; use "sim.banner" (not ".banner") since the
	# FeedbackBus SIGNAL is also named `banner` and BannerWidget legitimately subscribes to bus.banner.
	var r10 := true
	for f in ["widgets.gd", "panels.gd", "hud_model.gd", "hud_root.gd", "overlays.gd", "catalog_view.gd", "catalog_panels.gd", "world_input.gd", "lifecycle.gd", "world_panels.gd"]:
		var body := _read_code("res://scripts/ui/" + f)
		if ".messages" in body or "sim.banner" in body or ".flash_msg" in body or ".flash_t" in body:
			r10 = false
	ok(r10, "R10: only feedback_bus.gd reads sim.messages/banner/flash (single adapter)")

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

# comment-stripped file text (drops full-line # comments) so tripwire greps ignore doc comments
func _read_code(path: String) -> String:
	var out := PackedStringArray()
	for line in _read(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)

# ================= fakes (inner classes, like run_kernel_tests _StubClimate) =================
func _fake_session():
	var s := _FakeSession.new()
	s.sim = _FakeSim.new()
	s.sim.stock = {"wood": 12, "stone": 5}
	s.sim.player = {"hp": 100.0, "hunger": 82.0, "rest": 92.0, "carry_cap": 30,
		"sleeping": false, "equipped": {"tool": "axe", "weapon": ""}, "items": ["axe"], "carry": {}}
	return s

class _FakeSession extends RefCounted:
	var sim
	var progression = null
	func chain_head() -> String: return "abcdef1234567890"
	func stored_region_count() -> int: return 1

class _FakeSim extends RefCounted:
	var player: Dictionary = {"hp": 100.0, "hunger": 82.0, "rest": 92.0, "carry_cap": 30, "sleeping": false, "equipped": {"tool": "", "weapon": ""}, "items": [], "carry": {}}
	var stock: Dictionary = {}
	var dead := false
	var map: Dictionary = {"place_name": "Тестоград", "lat": 50.4501, "lon": 30.5234, "seed": 12345678}
	var time: Dictionary = {"frac": 0.5, "day": 5}
	var raid: Dictionary = {"active": false, "warned": false, "wave": 0}
	var enemies: Array = []
	var messages: Array = []
	var messages_seq := 0
	var banner := ""
	var flash_msg := ""
	var flash_t := 0.0
	func _log(text: String, cls: String = "") -> void:
		messages.append({"text": text, "cls": cls})
		messages_seq += 1
		if messages.size() > 40:
			messages.remove_at(0)
	func carry_total() -> int: return 0
	func storage_cap() -> int: return 200
	func melee_damage() -> float: return 12.0
	func daylight() -> float: return 0.0
	func region_seed() -> int: return int(map.get("seed", 0))
