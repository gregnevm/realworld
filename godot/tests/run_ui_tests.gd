# RealWorld — headless tests for the UX/UI view layer (spec 0005).
# Run: Godot_console.exe --headless --path godot -s res://tests/run_ui_tests.gd
#
# Same idiom as run_kernel_tests.gd: extends SceneTree, ok(cond,name), quit(1 if failed>0).
# Proves the pure spine (Tokens/Format/ViewGeom/LatLon/HudModel/FeedbackBus) with NO window, and the
# Control layer (Widget/Panel/registries/overlays) through the REAL headless lifecycle (get_root()+await).
extends SceneTree

const Tokens = preload("res://scripts/ui/tokens.gd")
const Fmt = preload("res://scripts/ui/format.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const LatLon = preload("res://scripts/ui/latlon.gd")
const HudModel = preload("res://scripts/ui/hud_model.gd")
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

var passed := 0
var failed := 0

func _init() -> void:
	print("== RealWorld UI view-layer tests (spec 0005) ==")
	_t_tokens()
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
	_t_panel_registry()
	_t_overlay_registry()
	_t_bus_no_dangling()
	_t_rule_tripwires()
	print("\n== RESULT: %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [pass] ", name)
	else:
		failed += 1
		printerr("  [FAIL] ", name)
		print("  [FAIL] ", name)

# ---------------- Tokens (R3 / drift reconciliation) ----------------
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
	ok((snap.vitals.bars as Array).size() == 3, "vitals slice has hp/hunger/rest bars")
	ok(snap.vitals.bars[1].state == &"good", "hunger 82 -> good urgency enum")
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
	ok(_all_value_data(snap.research), "research slice is pure value data (R8)")
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

# ---------------- FeedbackBus subscribers disconnect on free (R8 / §2.7 cycle-leak guard) ----------------
func _t_bus_no_dangling() -> void:
	var bus = FeedbackBus.FeedbackBus.new()
	var fw = Widgets.FeedWidget.new(); fw.subscribe(bus)
	var bw = Widgets.BannerWidget.new(); bw.subscribe(bus)
	var flw = Widgets.FlashWidget.new(); flw.subscribe(bus)
	ok(bus.feed.get_connections().size() == 1 and bus.banner.get_connections().size() == 1, "subscribers connect once")
	fw.free(); bw.free(); flw.free()
	ok(bus.feed.get_connections().size() == 0 and bus.banner.get_connections().size() == 0 and bus.flash.get_connections().size() == 0, "freeing subscribers leaves zero dangling connections (R8)")

# ---------------- Rule tripwires: R1/R3/R4/R7/R9/R10 as literal grep tests (the spec's whole point) ----------------
func _t_rule_tripwires() -> void:
	# R1 — one-way flow: no sim/kernel/session/social/persistence file references res://scripts/ui
	var sim_side := ["res://scripts/sim.gd", "res://scripts/session.gd", "res://scripts/social.gd",
		"res://scripts/persistence.gd", "res://scripts/world_gen.gd", "res://scripts/kernel/balance.gd"]
	var r1 := true
	for f in sim_side:
		if "res://scripts/ui" in _read_code(f):
			r1 = false
	ok(r1, "R1: sim/kernel/session/social/persistence never reference res://scripts/ui")
	# R3 — no raw color/stylebox under ui/ except tokens.gd + theme.gd
	var ui_files := ["widgets.gd", "panels.gd", "overlays.gd", "hud_model.gd", "hud_root.gd",
		"panel.gd", "widget.gd", "overlay.gd", "feedback_bus.gd", "format.gd", "view_geom.gd"]
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
	for f in ["panels.gd", "widgets.gd", "overlays.gd"]:
		var body := _read_code("res://scripts/ui/" + f)
		if ".position =" in body or "PRESET_TOP_RIGHT" in body:
			r7 = false
	ok(r7, "R7: no raw .position/PRESET_TOP_RIGHT in panels/widgets/overlays (pin_* only)")
	# R9 — sim commands appear only in the router, never in panels/widgets
	var cmds := ["try_build", "demolish", "craft_item", "dispatch_convoy", "try_launch_capsule",
		"order_move", "order_gather", "order_attack", "accept_invite"]
	var r9 := true
	for f in ["panels.gd", "widgets.gd"]:
		var body := _read_code("res://scripts/ui/" + f)
		for cmd in cmds:
			if cmd in body:
				r9 = false
	ok(r9, "R9: panels/widgets call no sim mutator (only the InputController does)")
	# R10 — only feedback_bus.gd drains the sim push channels. Target sim-field reads precisely:
	# .flash_msg/.flash_t/.messages are sim-only names; use "sim.banner" (not ".banner") since the
	# FeedbackBus SIGNAL is also named `banner` and BannerWidget legitimately subscribes to bus.banner.
	var r10 := true
	for f in ["widgets.gd", "panels.gd", "hud_model.gd", "hud_root.gd", "overlays.gd"]:
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
