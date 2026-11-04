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
const SessionScript = preload("res://scripts/session.gd")


func _init() -> void:
	print("== RealWorld UI view-layer tests (spec 0005) ==")
	_t_tokens()
	_t_art_icons()
	_t_world_fx()
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
	v.free()

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
	ok(vit._bar_grid.columns == 2 and not vit._carry.visible, "phone vitals pair their bars and drop the carry row")
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

# ---------------- Rule tripwires: R1/R3/R4/R7/R9/R10 as literal grep tests (the spec's whole point) ----------------
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
		"order_move", "order_gather", "order_attack", "accept_invite"]
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
