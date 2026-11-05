# RealWorld — newhud_main.gd : the NEW HUD entry scene (spec 0005 Batch 5 → playable Batch 7).
#
# Boots the view-layer architecture as a PLAYABLE game: spawn screen (координати — це seed) → live
# session → world input (clicks/keys through the verb router) → death screen → respawn. The HUD is
# assembled from REGISTRIES (mechanics.gd) — this file wires the frame, never a concrete panel by
# type. `-- newhud shot` still auto-starts Kyiv and captures the dev screenshot.
extends Node2D

const SessionScript = preload("res://scripts/session.gd")
const WorldViewScript = preload("res://scripts/world_view.gd")
const OverlayHost = preload("res://scripts/ui/overlay_host.gd")
const HudRootScript = preload("res://scripts/ui/hud_root.gd")
const PanelReg = preload("res://scripts/ui/panel_registry.gd")
const OverlayReg = preload("res://scripts/ui/overlay_registry.gd")
const FeedbackBus = preload("res://scripts/ui/feedback_bus.gd")
const InputController = preload("res://scripts/ui/input_controller.gd")
const InputVerbs = preload("res://scripts/ui/input_verbs.gd")
const CatalogVerbs = preload("res://scripts/ui/catalog_verbs.gd")
const CatalogSim = preload("res://scripts/catalog_sim.gd")
const Mechanics = preload("res://scripts/ui/mechanics.gd")
const Balance = preload("res://scripts/kernel/balance.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const GameData = preload("res://scripts/data.gd")
const WorldInputScript = preload("res://scripts/ui/world_input.gd")
const Lifecycle = preload("res://scripts/ui/lifecycle.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const TouchCtl = preload("res://scripts/ui/touch_controls.gd")
const AM = preload("res://scripts/ui/action_model.gd")
const InventoryMod = preload("res://scripts/sim/inventory.gd")
const TILE := ViewGeom.TILE

var session: SessionScript
var view: Node2D
var overlay_host: Node2D
var cam: Camera2D
var hud_layer: CanvasLayer
var hud_root: HudRootScript
var preg: PanelReg.PanelRegistry
var oreg: OverlayReg.OverlayRegistry
var bus: FeedbackBus.FeedbackBus
var balance: Balance.Balance
var router: InputController.InputController
var winput: WorldInputScript.WorldInput
var spawn_screen: Lifecycle.SpawnScreen
var death_screen: Lifecycle.DeathScreen
var panel_menu: Widgets.PanelMenu
# Touch frame (phones): Android/iOS builds, or `-- touch [scale=1.7]` to drive it on a desktop. The
# canvas grows by a DPI-derived content scale so text/targets keep a physical size, the HUD goes
# compact, and the keyboard/right-button/wheel get on-screen stand-ins (top-bar tools + ☰ menu).
var touch_ui := false
# --- touch action scheme (phones): VIEW state owned by the scene; the touch layer only emits signals ---
var tc: TouchCtl.TouchControls = null
var act_mode: StringName = &"gather"
var act_slot := 0
var act_build := "campfire"
var act_overview := false
var overview_pos := Vector2.ZERO
var act_target: Dictionary = {}
var _act_slots: Array = []
var shot_mode := false
var demo_mode := false             # `-- newhud demo`: spawn screen → auto-landing → hero walks a loop → quit (for --write-movie)
var _demo_t := 0.0
var _demo_leg := -1
var _t := 0.0
var _built := false
var _shot := false
var _shot_acted := false
# Autosave (continue): every AUTOSAVE_EVERY real seconds, at each new game day and on quit. Cheap —
# one JSON write of the session; the store already holds every visited region.
const AUTOSAVE_EVERY := 30.0
var _autosave_t := 0.0
var _saved_day := -1

func _ready() -> void:
	UITheme.install_emoji_fallback()       # web has no system emoji font — icons were boxes without it
	var ui_theme := UITheme.build()        # ONE Theme resource from Tokens (§2.4)
	_setup_touch()

	# --- world space (WorldRoot): tilemap + overlays + camera ---
	view = WorldViewScript.new()
	add_child(view)
	overlay_host = OverlayHost.new()
	add_child(overlay_host)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.zoom = Vector2(1.5, 1.5)   # generated sprites are detailed: default to ~42 px tiles, not 28

	# --- registries + feedback bus + router (session-independent wiring) ---
	preg = PanelReg.PanelRegistry.new()
	oreg = OverlayReg.OverlayRegistry.new()
	bus = FeedbackBus.FeedbackBus.new()
	balance = Balance.Balance.new()
	router = InputController.InputController.new()
	InputVerbs.install(router)
	CatalogVerbs.install(router, CatalogSim.shared())   # forward-engine build/craft/research commands
	# view-state verb: arming the build ghost is VIEW state, not a sim command — bound here where the
	# view lives (entry-scene wiring, the same tier that installs the session verbs)
	router.bind(&"select_build", func(_s, a: Dictionary) -> void:
		var kind := String(a.kind)
		if tc != null:   # touch scheme: the drawer picks WHAT the action button builds (no ghost to aim)
			act_build = kind
			_set_mode(&"build")
			return
		view.selected_build = "" if String(view.selected_build) == kind else kind)
	# time speed is VIEW state too (the sim only ever sees scaled dt): the top-bar chips land here
	router.bind(&"set_speed", func(_s, a: Dictionary) -> void:
		winput.apply_speed(&"set", float(a.get("mult", 1.0))))
	# touch tools — all VIEW state (menu, armed tool, camera), bound where the view lives
	router.bind(&"toggle_menu", func(_s, _a: Dictionary) -> void: _set_menu(not panel_menu.visible))
	router.bind(&"toggle_inventory", func(_s, _a: Dictionary) -> void: preg.toggle(&"inventory"))
	router.bind(&"cancel_tool", func(_s, _a: Dictionary) -> void:
		view.selected_build = ""
		router.dispatch(&"cancel_action", {}, session))
	router.bind(&"remove_tool", func(_s, _a: Dictionary) -> void:
		var rt := String(WorldInputScript.WorldInput.REMOVE_TOOL)
		view.selected_build = "" if String(view.selected_build) == rt else rt)
	router.bind(&"zoom_in", func(_s, _a: Dictionary) -> void: winput.zoom_step(1.25))
	router.bind(&"zoom_out", func(_s, _a: Dictionary) -> void: winput.zoom_step(0.8))
	Mechanics.register_all(preg, oreg)     # mechanics register themselves — no controller edit (R4)
	overlay_host.oreg = oreg

	# --- vignette between world and HUD (frames the scene; never eats input) ---
	var vig_layer := CanvasLayer.new()
	vig_layer.layer = 5
	add_child(vig_layer)
	Lifecycle.Chrome.add_vignette(vig_layer)

	# --- HUD layer (hidden until a world is chosen) ---
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.visible = false
	add_child(hud_layer)
	hud_root = HudRootScript.new()
	hud_root.theme = ui_theme
	hud_layer.add_child(hud_root)
	# Bridge panel intents -> the verb router -> sim/session (R9). Generic: names no mechanic.
	# ONE connection per panel — a second connect would double-dispatch every intent.
	for p in preg.panels:
		p.intent.connect(_route_intent)
	_build_menu(ui_theme)

	# --- world input adapter (clicks/keys -> verbs; inert until session exists) ---
	winput = WorldInputScript.WorldInput.new()
	winput.router = router
	winput.view = view
	winput.cam = cam
	winput.preg = preg
	winput.oreg = oreg
	add_child(winput)

	# --- lifecycle layer: spawn screen now, death screen when needed ---
	var life := CanvasLayer.new()
	life.layer = 20
	add_child(life)
	shot_mode = "newhud" in OS.get_cmdline_user_args() and "shot" in OS.get_cmdline_user_args()
	spawn_screen = Lifecycle.SpawnScreen.new()
	spawn_screen.theme = ui_theme
	if not shot_mode:
		spawn_screen.continue_meta = SessionScript.save_meta()
	spawn_screen.spawn_chosen.connect(_start_game)
	spawn_screen.continue_chosen.connect(_continue_game)
	life.add_child(spawn_screen)
	death_screen = Lifecycle.DeathScreen.new()
	death_screen.theme = ui_theme
	death_screen.visible = false
	death_screen.respawn_chosen.connect(func() -> void:
		router.dispatch(&"respawn", {}, session)
		_autosave())
	life.add_child(death_screen)

	demo_mode = "newhud" in OS.get_cmdline_user_args() and "demo" in OS.get_cmdline_user_args()
	if shot_mode and not ("spawn" in OS.get_cmdline_user_args()):   # `-- newhud shot spawn` captures the spawn screen
		_start_game(50.4501, 30.5234, "Київ")

# The spawn screen (or shot mode) picked a world address — boot the real session on it.
func _start_game(lat: float, lon: float, place_name: String) -> void:
	if session != null:
		return   # уже в грі (пізній GPS-callback чи повторний сигнал): другий бут ремонтував би панелі
	session = SessionScript.new()
	session.use_inventory = true          # spec 0009: new games play with the Minecraft-style inventory
	session.autosave = not shot_mode
	session.start(lat, lon, place_name)
	_enter_session()
	_autosave()   # a new landing claims the save slot at once (the spawn screen warned about it)

# The spawn screen's «▶ Продовжити»: rebuild the whole session from the save file.
func _continue_game() -> void:
	if session != null:
		return
	var s := SessionScript.new()
	if not s.restore_game():
		return   # unreadable save: the screen stays (presets still work)
	session = s
	_enter_session()

func _enter_session() -> void:
	view.sim = session.sim
	winput.session = session
	hud_root.setup(session, balance, bus, preg, oreg)
	hud_root.set_compact(touch_ui)        # BEFORE mount: compact panels pick their phone defaults
	hud_root.mount()
	spawn_screen.visible = false
	hud_layer.visible = true
	_saved_day = int(session.sim.time.day)
	if touch_ui and tc == null:
		_setup_action_controls()
	if session.sim.use_inventory:   # spec 0009: the hotbar replaces the build palette (touch: the quick bar shows it)
		var bbar: Variant = preg.get_panel(&"build_bar")
		if bbar != null:
			bbar.visible = false
		var hot: Variant = preg.get_panel(&"hotbar")
		if hot != null:
			hot.visible = not touch_ui

func _autosave() -> void:
	if session == null or shot_mode or not session.autosave:
		return
	session.save_game()
	_autosave_t = 0.0
	_saved_day = int(session.sim.time.day)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()   # quitting keeps the world (the web build relies on the timed saves)
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_autosave()   # a phone may kill a backgrounded app without another callback
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()

# Android «back»: peel one layer — the menu, then an armed tool, then the game (saved) itself.
func _on_back() -> void:
	if panel_menu != null and panel_menu.visible:
		_set_menu(false)
	elif view != null and String(view.selected_build) != "":
		view.selected_build = ""
	else:
		_autosave()
		get_tree().quit()

# --- touch frame ---------------------------------------------------------------------------------
func _setup_touch() -> void:
	var args := OS.get_cmdline_user_args()
	touch_ui = OS.has_feature("mobile") or "touch" in args
	if not touch_ui:
		return
	var sf: float = WorldInputScript.WorldInput.ui_scale(float(DisplayServer.screen_get_dpi()), Vector2(get_window().size))
	for a in args:
		if String(a).begins_with("scale="):
			sf = clampf(float(String(a).substr(6)), 1.0, 3.0)
	get_window().content_scale_factor = sf

# The ☰ menu: one toggle per registered panel/overlay that carries a menu_label (generic — the
# registries' own metadata, R4 spirit), flipping the SAME registry state the hotkeys flip.
func _build_menu(ui_theme: Theme) -> void:
	panel_menu = Widgets.PanelMenu.new()
	panel_menu.theme = ui_theme   # a CanvasLayer breaks theme inheritance — hand it the frame's theme
	Widgets.WidgetBase.Widget.pin_center(panel_menu)
	panel_menu.visible = false
	hud_layer.add_child(panel_menu)
	var entries: Array = []
	for p in preg.panels:
		if String(p.menu_label) != "":
			entries.append({"kind": &"panel", "id": p.panel_id, "label": String(p.menu_label)})
	for o in oreg.overlays:
		if String(o.menu_label) != "":
			entries.append({"kind": &"overlay", "id": o.overlay_id, "label": String(o.menu_label)})
	panel_menu.setup(entries)
	panel_menu.chosen.connect(func(kind: StringName, id: StringName) -> void:
		if kind == &"overlay":
			oreg.toggle(id)
		else:
			preg.toggle(id)
		_refresh_menu())
	panel_menu.closed.connect(func() -> void: _set_menu(false))

func _set_menu(on: bool) -> void:
	panel_menu.visible = on
	if on:
		_refresh_menu()

func _refresh_menu() -> void:
	var states: Dictionary = {}
	for p in preg.panels:
		states["panel:%s" % String(p.panel_id)] = bool(p.visible)
	for o in oreg.overlays:
		states["overlay:%s" % String(o.overlay_id)] = bool(oreg.is_on(o.overlay_id))
	panel_menu.bind(states)

# A panel emitted an intent (e.g. the ResearchPanel's enqueue_research); dispatch it through the router.
func _route_intent(verb: StringName, args: Dictionary) -> void:
	router.dispatch(verb, args, session)

func _process(dt: float) -> void:
	if demo_mode:
		_demo_step(dt)
	if session == null:
		if shot_mode:
			_shot_step(dt)   # `shot spawn`: the spawn screen itself is the subject
		return
	view.sim = session.sim            # travel/respawn swap the sim under the session — track it
	var sdt := dt * winput.speed
	if sdt > 0.0 and not session.sim.dead:
		session.sim.update(sdt)
		session.tick_research(sdt)    # research benches fund the tech pipeline each frame
	session.tick_goals(dt)            # onboarding goals observe the world (real time, ~2×/s)
	CatalogSim.shared().tick(sdt)     # advance the forward-engine catalogue model
	# camera eases after the hero (exp. smoothing, frame-rate independent) instead of hard-locking to it;
	# a jump (spawn/travel/respawn) larger than half a screen snaps
	if tc != null:
		_tick_action(dt)
	elif session.sim.use_inventory:
		_sync_held_ghost()
	var cam_target := overview_pos if act_overview else Vector2(session.sim.player.px * TILE, session.sim.player.py * TILE)
	if cam.global_position.distance_to(cam_target) > 600.0:
		cam.global_position = cam_target
	else:
		cam.global_position = cam.global_position.lerp(cam_target, 1.0 - exp(-7.0 * dt))
	# hurt shake: deterministic sine noise (no global RNG — tripwire), decays inside world_view
	var tsec: float = Time.get_ticks_msec() * 0.001
	cam.offset = Vector2(sin(tsec * 53.0), cos(tsec * 47.0)) * 6.0 * view.shake * view.shake   # trauma² (Eiserloh)
	view.observe_sim(dt)             # floating +N / -N feedback (view-only diff of sim numbers)
	if view.hitstop <= 0.0:          # render-only hit-stop: the frame holds 40–60 ms, the sim never pauses
		view.queue_redraw()
	# VIEW state for this frame's snapshot (hud_root runs after us: parent before child)
	hud_root.view_ctx = {"hover": view.hover, "hover_world": winput.hover_world(),
		"in_world": winput.tooltip_wanted(touch_ui) and not session.sim.dead and not panel_menu.visible,
		"selected_build": String(view.selected_build), "speed": winput.speed,
		"touch": touch_ui, "menu_open": panel_menu.visible,
		"pointer": winput.pointer_screen if winput.pointer_is_touch else get_viewport().get_mouse_position(),
		"hero_screen": view.get_global_transform_with_canvas() * Vector2(session.sim.player.px * TILE, session.sim.player.py * TILE - TILE * 1.1)}
	overlay_host.map_n = int(session.sim.n)   # keep in lockstep with the live region (survives travel)
	overlay_host.snap = hud_root.last_snap
	overlay_host.queue_redraw()
	death_screen.visible = session.sim.dead
	if session.sim.dead:
		death_screen.bind(hud_root.last_snap.get("death", {}))
	_autosave_t += dt
	if _autosave_t >= AUTOSAVE_EVERY or int(session.sim.time.day) != _saved_day:
		_autosave()
	if shot_mode:
		_shot_step(dt)

# --- dev demo (for `--write-movie`): the spawn screen breathes for 3 s, then a landing, a base, and a walking loop ---
func _demo_step(dt: float) -> void:
	_demo_t += dt
	if session == null:
		if _demo_t > 3.0:
			_start_game(50.4501, 30.5234, "Київ")
			_build_demo_base()
		return
	if tc != null:   # touch demo: drive the REAL control layer (stick vector + action-button signals)
		_demo_touch(dt)
		return
	var leg: int = int((_demo_t - 3.0) / 4.0)
	if leg != _demo_leg:
		_demo_leg = leg
		if _demo_leg == 0:
			session.sim.time.frac = 0.45   # late morning: the art reads at its best
		var sim: Variant = session.sim
		var hx: int = int(sim.player.px)
		var hy: int = int(sim.player.py)
		if leg % 2 == 0:   # chop the nearest tree (path + swing + «+N» feedback)
			var best := -1
			var bd := 1 << 30
			for key in sim.map.nodes:
				if String(sim.map.nodes[key].kind) != "tree":
					continue
				var d: int = absi(int(key) % sim.n - hx) + absi(int(key) / sim.n - hy)
				if d > 2 and d < bd:
					bd = d
					best = int(key)
			if best >= 0:
				sim.order_gather(best % sim.n, best / sim.n)
		else:              # light a campfire next to the hero (placement pop + goal toast), then walk away
			for o2 in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(2, 0)]:
				if sim.build_valid(hx + o2.x, hy + o2.y):
					sim.try_build("campfire", hx + o2.x, hy + o2.y)
					break
			for r in [5, 4, 6, 3]:
				var done := false
				for o in [Vector2i(r, 0), Vector2i(0, r), Vector2i(-r, 0), Vector2i(0, -r)]:
					var tx: int = clampi(hx + o.x, 1, sim.n - 2)
					var ty: int = clampi(hy + o.y, 1, sim.n - 2)
					sim.order_move(tx, ty)
					var a: Variant = sim.player.action
					if a is Dictionary and (a.get("path", []) as Array).size() > 0:
						done = true
						break
				if done:
					break
	if _demo_t > 19.0:
		get_tree().quit()

# Touch demo script (t from landing): walk east with the stick, tap-chop the auto-target, switch to Build
# (double tap), place what the drawer offers, then hold for the radial. Exercises the whole scheme.
func _demo_touch(_dt: float) -> void:
	var t: float = _demo_t - 3.0
	var step: int = int(t * 10.0)
	if step == _demo_leg:
		return
	_demo_leg = step
	if step == 1:
		session.sim.time.frac = 0.45
	tc.move_vec = Vector2(1, 0.2).normalized() if (step >= 5 and step < 20) else Vector2.ZERO
	if step == 22 or step == 40:
		tc.action_tap.emit()
	if step == 60:
		tc.action_double.emit()
	if step == 70:
		tc.action_tap.emit()
	if step == 85:
		tc.action_hold.emit(tc.act_center())
	if step >= 120:
		get_tree().quit()

# --- dev screenshot: build a base, toggle the Light overlay, capture the new HUD, quit ---
func _shot_step(dt: float) -> void:
	_t += dt
	if not _built and _t > 0.15 and session != null:
		_built = true
		_build_demo_base()
		if "bag" in OS.get_cmdline_user_args():   # `shot bag`: a death bag nearby + one off screen (map markers)
			var sb: Variant = session.sim
			sb.bags.append({"x": int(sb.player.px) + 2, "y": int(sb.player.py) + 2, "slots": [{"id": "wood", "n": 9}, {"id": "stone", "n": 4}], "day": 1})
			sb.bags.append({"x": 2, "y": 2, "slots": [{"id": "food", "n": 3}], "day": 1})
		if "inv" in OS.get_cmdline_user_args():
			preg.toggle(&"inventory")   # `shot inv`: the inventory screen (spec 0009)
		if "drawer" in OS.get_cmdline_user_args():
			preg.get_panel(&"build_bar").set_category(1)   # `shot drawer`: touch build drawer opened on «Побут»
		if "gear" in OS.get_cmdline_user_args():
			preg.toggle(&"gear")           # `shot gear`: open the loadout panel
		if "light" in OS.get_cmdline_user_args():
			oreg.toggle(&"light")          # `shot light`: radio-on the L/Light overlay (default frame = what a player sees)
		session.sim.time.frac = 0.86       # dusk so daylight darkening is visible
		if "death" in OS.get_cmdline_user_args():   # `shot death`: a REAL death (epitaph + bag), not a bare flag
			session.sim.player.born = 1
			session.sim.time.day = 3
			session.sim.last_death = {"cause": "переохолодження", "day": 3, "born": 1}
			session.sim._on_death()
	if "fx" in OS.get_cmdline_user_args() and _t > 1.45 and _t < 1.5:
		var hp := Vector2(session.sim.player.px * TILE, session.sim.player.py * TILE - TILE * 1.3)   # `shot fx`: show the floating texts
		view.fx_add("+3", hp, Color(1.0, 0.95, 0.8), "res_wood")
		view.fx_add("-7", hp + Vector2(TILE * 2.5, TILE * 0.3), Color(1.0, 0.85, 0.4))
	if tc != null and _t > 1.2 and not _shot_acted:
		_shot_acted = true
		if "radial" in OS.get_cmdline_user_args():   # `shot radial`: the hold menu on the current target
			_open_radial(act_target if not act_target.is_empty() else AM.target_at(session.sim, Vector2i(int(session.sim.player.px) + 1, int(session.sim.player.py)), act_mode, act_build), tc.act_center())
		if "overview" in OS.get_cmdline_user_args() and not act_overview:
			_on_overview()
		if "buildmode" in OS.get_cmdline_user_args():
			_set_mode(&"build")
	if _t > 1.6 and not _shot:
		_shot = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		# Portable output: res:// maps to the godot/ project dir (writable in a source run — editor/CI),
		# so CI can pick it up at godot/newhud_shot.png. Gitignored via godot/*_shot*.png.
		img.save_png("res://newhud_shot.png")                       # full-res artifact
		img.resize(854, 480, Image.INTERPOLATE_BILINEAR)
		img.save_png("res://newhud_thumb.png")                      # small copy for a text-channel readback
		print("NEWHUD_SHOT saved -> ", ProjectSettings.globalize_path("res://newhud_shot.png"))
		get_tree().quit()

func _build_demo_base() -> void:
	var sim: Variant = session.sim
	# сідінг через шов res_key (spec 0008): прямий stock.wood = ... писав би повз словник каталогу
	sim.stock[sim.res_key("wood")] = 240
	sim.stock[sim.res_key("stone")] = 240
	sim.stock[sim.res_key("scrap")] = 60
	sim.stock[sim.res_key("components")] = 12
	# демо-база показує гейтовий контент — відкриваємо потрібні гілки, як їх відкрив би гравець
	sim.research_unlocked = {"machining": true, "smelting": true, "hunting": true, "smithing": true}
	var c: Vector2i = sim.base_center()
	for d in range(-3, 4):
		_put("wall", c.x + d, c.y - 3)
		_put("wall", c.x + d, c.y + 3)
		_put("wall", c.x - 3, c.y + d)
		_put("wall", c.x + 3, c.y + d)
	_put("door", c.x, c.y + 3)
	_put("workbench", c.x - 1, c.y - 1)
	_put("bed", c.x + 1, c.y - 1)
	_put("research_bench", c.x + 1, c.y + 1)
	_put("turret", c.x - 2, c.y + 2)
	_put("turret", c.x + 2, c.y - 2)
	# контент-пак у кадрі: лампа, обігрівач і смуга шипів перед ворітьми
	_put("lamp", c.x - 1, c.y + 1)
	_put("heater", c.x, c.y - 1)
	_put("spike_trap", c.x, c.y + 4)
	_put("spike_trap", c.x - 1, c.y + 4)
	if bool(sim.use_inventory):   # staging: the crafts below are paid from the backpack — stock it, so the frame
		InventoryMod.add(sim, "scrap", 40)   # shows the kit and not a stale «бракує» flash (an artifact, not the game)
		InventoryMod.add(sim, "wood", 20)
		InventoryMod.add(sim, "components", 6)
	router.dispatch(&"craft", {"id": "plate"}, session)
	sim.player.px = c.x + 0.5
	sim.player.py = c.y + 1.5
	router.dispatch(&"craft", {"id": "axe"}, session)
	router.dispatch(&"craft", {"id": "spear"}, session)
	# лор у кадрі: патрульний робот Старого світу на підході до бази
	sim.enemies.append(GameData.make_patrol_bot(c.x + 5.5, c.y + 0.5, 3))
	# populate the research pipeline so the ResearchPanel reads live in the screenshot
	router.dispatch(&"enqueue_research", {"id": "carpentry"}, session)
	router.dispatch(&"enqueue_research", {"id": "masonry"}, session)
	session.progression.add_points(0.8)   # ~half of carpentry so the active bar is visibly filled

func _put(kind: String, x: int, y: int) -> void:
	if bool(session.sim.use_inventory):   # dev demo: hand the building item over first (spec 0009)
		if session.sim.build_valid(x, y):
			InventoryMod.add(session.sim, InventoryMod.BLD + kind, 1)
			router.dispatch(&"build", {"kind": kind, "x": x, "y": y}, session)
		return
	if session.sim.build_valid(x, y) and session.sim.afford(GameData.BUILDINGS[kind].cost):
		router.dispatch(&"build", {"kind": kind, "x": x, "y": y}, session)


# ================= touch action scheme (left stick · action button · quick slots · radial) =================
# Research 2026-11 (Apple HIG game controls, AOSP ViewConfiguration, Brawl Stars auto-aim, Don't Starve PE /
# Last Day on Earth action buttons, Terraria/Minecraft hotbars, Kurtenbach & Buxton radial menus).
func _setup_action_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	tc = TouchCtl.TouchControls.new()
	tc.theme = hud_root.theme
	layer.add_child(tc)
	tc.gui_rects = func() -> Array: return hud_root.dock_rects()
	winput.touch_block = func(p: Vector2) -> bool: return tc.claims(p)
	tc.overview_toggled.connect(_on_overview)
	tc.action_tap.connect(_on_action_tap)
	tc.action_double.connect(_on_action_double)
	tc.action_hold.connect(func(center: Vector2) -> void: _open_radial(act_target, center))
	tc.zoom_step.connect(func(d: int) -> void: winput.zoom_step(1.15 if d > 0 else 1.0 / 1.15))
	tc.slot_step.connect(func(d: int) -> void: _apply_slot(posmod(act_slot + d, maxi(1, _act_slots.size()))))
	tc.slot_selected.connect(_apply_slot)
	tc.inventory_pressed.connect(func() -> void: preg.toggle(&"inventory" if bool(session.sim.use_inventory) else &"gear"))
	tc.option_chosen.connect(func(o: Dictionary) -> void: router.dispatch(StringName(o.verb), o.args, session))
	winput.long_pressed.connect(func(cell: Vector2i, screen: Vector2) -> void:
		_open_radial(AM.target_at(session.sim, cell, act_mode, act_build), screen))
	var bb: Variant = preg.get_panel(&"build_bar")
	if bb != null:
		bb.external_drawer = true       # the action button replaces the 🔨 FAB; the drawer is PROACTIVE (mode-driven)
	hud_root.set_bar_lift(68.0)          # the drawer sits above the quick bar, centred

# The quick-bar slot holding the current onboarding goal's building (-1 = none) — the touch twin of
# InventoryBarPanel's pulse (value data from the last snapshot; the scene owns the slot list).
func _guide_slot() -> int:
	var cur: Dictionary = ((hud_root.last_snap.get("goals", {}) as Dictionary).get("current", {}) as Dictionary)
	var kind := String(cur.get("build", ""))
	if kind == "":
		return -1
	for i in _act_slots.size():
		var sl: Dictionary = _act_slots[i]
		if StringName(sl.get("type", &"")) == &"build" and String(sl.get("id", "")) == kind:
			return i
	return -1

var _act_hand := -1                 # last seen hotbar hand (inventory world) — a change re-derives the mode
var _act_hand_type: StringName = &""

func _tick_action(dt: float) -> void:
	var sim: Variant = session.sim
	if act_overview:   # the stick drives the cursor (camera), not the hero
		winput.stick_move = Vector2.ZERO
		overview_pos += tc.move_vec * 12.0 * TILE * dt
		overview_pos = overview_pos.clamp(Vector2.ZERO, Vector2(sim.n, sim.n) * TILE)
	else:
		winput.stick_move = tc.move_vec
	if bool(sim.use_inventory):
		_act_slots = AM.slots_from_inventory(sim)
		act_slot = int(sim.player.get("hand", 0))
		var hs: Dictionary = _act_slots[act_slot]
		if StringName(hs.type) == &"build":
			act_build = String(hs.id)
		if act_slot != _act_hand or StringName(hs.type) != _act_hand_type:
			# the hand changed by ANY path (hotbar panel, digit key, a new game holding the campfire, the slot
			# emptied): the action button follows what you hold — owner rule «picking a specific item switches
			# the mode». 3rd independent read: campfire in hand, button still offered «Добути · брухт».
			_act_hand = act_slot
			_act_hand_type = StringName(hs.type)
			act_mode = AM.mode_for_slot(hs)
			act_target = {}
	else:
		_act_slots = AM.default_slots(sim, act_build)
	act_slot = clampi(act_slot, 0, _act_slots.size() - 1)
	var origin := Vector2(sim.player.px, sim.player.py)
	var facing: float = float(sim.player.face)
	if act_overview:
		act_target = AM.target_at(sim, Vector2i(int(overview_pos.x / TILE), int(overview_pos.y / TILE)), act_mode, act_build)
	elif not AM.keep_target(sim, act_target, act_mode, origin, facing):
		act_target = AM.pick_target(sim, act_mode, origin, facing, act_build)
	if not act_target.is_empty():
		act_target["mode"] = act_mode
	view.action_target = act_target
	view.action_mode = act_mode
	view.action_build = act_build
	tc.bind_state({"mode": act_mode, "slots": _act_slots, "active": act_slot, "overview": act_overview,
		"target": _target_label(act_target), "guide": _guide_slot()})
	var bb: Variant = preg.get_panel(&"build_bar")
	if bb != null and not bool(sim.use_inventory) and bool(bb._open) != (act_mode == &"build"):
		bb.set_drawer(act_mode == &"build")   # proactive drawer: Build mode opens it, any other mode closes it
		if act_mode == &"build":
			bb.set_category(bb.cat_of(act_build))   # …on the tab of the building the button will place

func _target_label(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	var sim: Variant = session.sim
	var v: Dictionary = AM.primary(act_mode, t, act_build)
	var verb := String(v.get("verb", ""))
	var what := ""
	match StringName(t.kind):
		&"node":
			var nk := String(sim.map.nodes[int(t.y) * int(sim.n) + int(t.x)].kind)
			what = String({"tree": "дерево", "rock": "камінь", "bush": "кущ", "scrap": "брухт"}.get(nk, nk))
		&"enemy":
			what = "робот" if String(t.ref.get("kind", "")) == "bot" else "рейдер"
		&"building":
			what = String(sim.building_def(String(t.ref.kind)).get("name", ""))
		&"cell":
			what = String(sim.building_def(act_build).get("name", act_build))
	var verb_ua := {"order_gather": "Добути", "order_attack": "Атакувати", "build": "Збудувати", "repair": "Ремонт",
		"order_move": "Іти", "deconstruct": "Розібрати"}
	return ("%s · %s" % [String(verb_ua.get(verb, "")), what]).strip_edges().trim_prefix("· ").trim_suffix(" ·")

func _on_action_tap() -> void:
	var v: Dictionary = AM.primary(act_mode, act_target, act_build)
	if v.is_empty():
		var why := {&"gather": "Поруч нема що добувати", &"build": "Нема місця попереду",
		&"repair": "Поруч нема пошкоджених будівель", &"fight": "Поруч нема ворогів"}
		tc.show_toast(String(why.get(act_mode, "Нема цілі")))
		return
	router.dispatch(StringName(v.verb), v.args, session)
	act_target = {}   # re-acquire next frame (the node/cell may be gone or taken)

func _on_action_double() -> void:
	for e in session.sim.enemies:   # never re-mode mid-fight: a mashed attack button must not become «build»
		# «fight» = an enemy that is actually coming for the hero (its intent hunts) and is close — a patrol
		# bot idling nearby must not lock the player out of building
		if bool(view.enemy_intent(e).hunt) and Vector2(e.px, e.py).distance_to(Vector2(session.sim.player.px, session.sim.player.py)) < 5.0:
			tc.show_toast("У бою режим не змінюється")
			return
	_set_mode(AM.next_mode(act_mode))

func _set_mode(m: StringName) -> void:
	act_mode = m
	act_target = {}
	for i in _act_slots.size():   # the bar follows the mode (auto-switch both ways)
		if AM.mode_for_slot(_act_slots[i]) == m:
			act_slot = i
			if bool(session.sim.use_inventory):
				router.dispatch(&"set_hand", {"i": i}, session)   # inventory world: the hand takes that slot
			break

func _apply_slot(i: int) -> void:
	if i < 0 or i >= _act_slots.size():
		return
	act_slot = i
	var sl: Dictionary = _act_slots[i]
	act_mode = AM.mode_for_slot(sl)
	act_target = {}
	if bool(session.sim.use_inventory):
		router.dispatch(&"set_hand", {"i": i}, session)   # the hand IS the hotbar slot (equips tools itself)
		if StringName(sl.type) == &"build":
			act_build = String(sl.id)
		return
	if StringName(sl.type) in [&"tool", &"weapon"] and String(sl.id) != "":
		router.dispatch(&"equip", {"id": String(sl.id)}, session)
	if StringName(sl.type) == &"build":
		act_build = String(sl.id)

func _open_radial(t: Dictionary, at: Vector2) -> void:
	var opts: Array = AM.options(session.sim, t, act_build)
	if opts.is_empty():
		tc.show_toast("Тут нічого робити")
		return
	tc.show_radial(at, opts)

func _on_overview() -> void:
	act_overview = not act_overview
	overview_pos = Vector2(session.sim.player.px, session.sim.player.py) * TILE
	act_target = {}
	tc.show_toast("Огляд мапи · 2× тап стіка — назад" if act_overview else "Назад до героя")

# Desktop inventory world: holding a building item arms its ghost (click/drag places it, consuming items);
# holding anything else clears a ghost we armed. The 🗑 remove tool is left alone.
var _held_kind := ""
func _sync_held_ghost() -> void:
	var sim: Variant = session.sim
	var h: Dictionary = sim.player.inv[clampi(int(sim.player.get("hand", 0)), 0, 7)]
	var id := String(h.id)
	var kind := id.substr(4) if id.begins_with("bld:") else ""
	if kind == _held_kind:
		return
	if String(view.selected_build) == _held_kind or kind != "":
		view.selected_build = kind
	_held_kind = kind
