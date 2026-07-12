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
const Tokens = preload("res://scripts/ui/tokens.gd")
const Fmt = preload("res://scripts/ui/format.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
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
var region_label: Label
var speed_label: Label
var chrome_bar: HBoxContainer
var shot_mode := false
var _t := 0.0
var _built := false
var _shot := false
var _region_key := ""   # "name|seed" останнього відформатованого лейбла — не форматуємо щокадру

func _ready() -> void:
	UITheme.install_emoji_fallback()       # web has no system emoji font — icons were boxes without it
	var ui_theme := UITheme.build()        # ONE Theme resource from Tokens (§2.4)

	# --- world space (WorldRoot): tilemap + overlays + camera ---
	view = WorldViewScript.new()
	add_child(view)
	overlay_host = OverlayHost.new()
	add_child(overlay_host)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()

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
	_build_chrome()

	# --- world input adapter (clicks/keys -> verbs; inert until session exists) ---
	winput = WorldInputScript.WorldInput.new()
	winput.router = router
	winput.view = view
	winput.cam = cam
	winput.preg = preg
	winput.oreg = oreg
	winput.speed_changed.connect(_on_speed_changed)
	add_child(winput)

	# --- lifecycle layer: spawn screen now, death screen when needed ---
	var life := CanvasLayer.new()
	life.layer = 20
	add_child(life)
	spawn_screen = Lifecycle.SpawnScreen.new()
	spawn_screen.theme = ui_theme
	spawn_screen.spawn_chosen.connect(_start_game)
	life.add_child(spawn_screen)
	death_screen = Lifecycle.DeathScreen.new()
	death_screen.theme = ui_theme
	death_screen.visible = false
	death_screen.respawn_chosen.connect(func() -> void: router.dispatch(&"respawn", {}, session))
	life.add_child(death_screen)

	if "newhud" in OS.get_cmdline_user_args() and "shot" in OS.get_cmdline_user_args():
		shot_mode = true
		_start_game(50.4501, 30.5234, "Київ")

# The spawn screen (or shot mode) picked a world address — boot the real session on it.
func _start_game(lat: float, lon: float, place_name: String) -> void:
	if session != null:
		return   # уже в грі (пізній GPS-callback чи повторний сигнал): другий бут ремонтував би панелі
	session = SessionScript.new()
	session.start(lat, lon, place_name)
	view.sim = session.sim
	winput.session = session
	hud_root.setup(session, balance, bus, preg, oreg)
	hud_root.mount()
	spawn_screen.visible = false
	hud_layer.visible = true

# Controller-owned chrome: the shareable world address + the time multiplier. Values bind from the
# snapshot's region slice (R5/R8) in _process; mechanics never appear here (R4 spirit).
func _build_chrome() -> void:
	var top := HBoxContainer.new()
	# CanvasLayer-гоча (див. hud_root/lifecycle): TOP_WIDE під CanvasLayer колапсує в нульову ширину,
	# і ALIGNMENT_CENTER тулить лейбли в лівий кут — пінимо TOP_LEFT і розміряємо явно (re-fit на resize)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 14)
	hud_layer.add_child(top)
	chrome_bar = top
	_fit_chrome()
	get_viewport().size_changed.connect(_fit_chrome)
	region_label = Label.new()
	region_label.add_theme_color_override("font_color", Tokens.ACCENT)
	region_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(region_label)
	speed_label = Label.new()
	speed_label.add_theme_color_override("font_color", Tokens.MUT)
	speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_label.text = "×1"
	top.add_child(speed_label)

func _fit_chrome() -> void:
	chrome_bar.position = Vector2.ZERO
	chrome_bar.size = Vector2(get_viewport().get_visible_rect().size.x, 28)

func _on_speed_changed(mult: float) -> void:
	speed_label.text = "⏸ пауза" if mult == 0.0 else "×%d" % int(mult)

# A panel emitted an intent (e.g. the ResearchPanel's enqueue_research); dispatch it through the router.
func _route_intent(verb: StringName, args: Dictionary) -> void:
	router.dispatch(verb, args, session)

func _process(dt: float) -> void:
	if session == null:
		return
	view.sim = session.sim            # travel/respawn swap the sim under the session — track it
	var sdt := dt * winput.speed
	if sdt > 0.0 and not session.sim.dead:
		session.sim.update(sdt)
		session.tick_research(sdt)    # research benches fund the tech pipeline each frame
	CatalogSim.shared().tick(sdt)     # advance the forward-engine catalogue model
	cam.global_position = Vector2(session.sim.player.px * TILE, session.sim.player.py * TILE)
	view.queue_redraw()
	overlay_host.map_n = int(session.sim.n)   # keep in lockstep with the live region (survives travel)
	overlay_host.snap = hud_root.last_snap
	overlay_host.queue_redraw()
	death_screen.visible = session.sim.dead
	var reg: Dictionary = hud_root.last_snap.get("region", {})
	if not reg.is_empty():
		var rk := "%s|%d" % [String(reg.name), int(reg.seed)]
		if rk != _region_key:   # адреса міняється лише на travel/respawn — не форматуємо щокадру
			_region_key = rk
			region_label.text = "%s · seed %s" % [Fmt.region_line(String(reg.name), float(reg.lat), float(reg.lon)),
				Fmt.seed_hex(int(reg.seed))]
	if shot_mode:
		_shot_step(dt)

# --- dev screenshot: build a base, toggle the Light overlay, capture the new HUD, quit ---
func _shot_step(dt: float) -> void:
	_t += dt
	if not _built and _t > 0.15:
		_built = true
		_build_demo_base()
		oreg.toggle(&"light")              # radio-on the L/Light overlay so OverlayHost renders it
		session.sim.time.frac = 0.86       # dusk so daylight darkening is visible
	if _t > 1.6 and not _shot:
		_shot = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("O:/realworld/godot/newhud_shot.png")
		print("NEWHUD_SHOT saved")
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
