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
var shot_mode := false
var _t := 0.0
var _built := false
var _shot := false
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
		view.selected_build = "" if String(view.selected_build) == kind else kind)
	# time speed is VIEW state too (the sim only ever sees scaled dt): the top-bar chips land here
	router.bind(&"set_speed", func(_s, a: Dictionary) -> void:
		winput.apply_speed(&"set", float(a.get("mult", 1.0))))
	# touch tools — all VIEW state (menu, armed tool, camera), bound where the view lives
	router.bind(&"toggle_menu", func(_s, _a: Dictionary) -> void: _set_menu(not panel_menu.visible))
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

	if shot_mode and not ("spawn" in OS.get_cmdline_user_args()):   # `-- newhud shot spawn` captures the spawn screen
		_start_game(50.4501, 30.5234, "Київ")

# The spawn screen (or shot mode) picked a world address — boot the real session on it.
func _start_game(lat: float, lon: float, place_name: String) -> void:
	if session != null:
		return   # уже в грі (пізній GPS-callback чи повторний сигнал): другий бут ремонтував би панелі
	session = SessionScript.new()
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
	cam.global_position = Vector2(session.sim.player.px * TILE, session.sim.player.py * TILE)
	view.observe_sim(dt)             # floating +N / -N feedback (view-only diff of sim numbers)
	view.queue_redraw()
	# VIEW state for this frame's snapshot (hud_root runs after us: parent before child)
	hud_root.view_ctx = {"hover": view.hover, "hover_world": winput.hover_world(),
		"in_world": winput.tooltip_wanted(touch_ui) and not session.sim.dead and not panel_menu.visible,
		"selected_build": String(view.selected_build), "speed": winput.speed,
		"touch": touch_ui, "menu_open": panel_menu.visible,
		"pointer": winput.pointer_screen if winput.pointer_is_touch else get_viewport().get_mouse_position()}
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

# --- dev screenshot: build a base, toggle the Light overlay, capture the new HUD, quit ---
func _shot_step(dt: float) -> void:
	_t += dt
	if not _built and _t > 0.15 and session != null:
		_built = true
		_build_demo_base()
		if "light" in OS.get_cmdline_user_args():
			oreg.toggle(&"light")          # `shot light`: radio-on the L/Light overlay (default frame = what a player sees)
		session.sim.time.frac = 0.86       # dusk so daylight darkening is visible
		if "death" in OS.get_cmdline_user_args():
			session.sim.dead = true        # `shot death`: capture the death screen
	if "fx" in OS.get_cmdline_user_args() and _t > 1.45 and _t < 1.5:
		var hp := Vector2(session.sim.player.px * TILE, session.sim.player.py * TILE - TILE * 1.3)   # `shot fx`: show the floating texts
		view.fx_add("+3", hp, Color(1.0, 0.95, 0.8), "res_wood")
		view.fx_add("-7", hp + Vector2(TILE * 2.5, TILE * 0.3), Color(1.0, 0.85, 0.4))
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
	if session.sim.build_valid(x, y) and session.sim.afford(GameData.BUILDINGS[kind].cost):
		router.dispatch(&"build", {"kind": kind, "x": x, "y": y}, session)
