# RealWorld — newhud_main.gd : the NEW HUD entry scene (spec 0005 Batch 5).
#
# Boots the view-layer architecture beside the world nodes WITHOUT touching main.gd (which stays the
# default scene until Batch 7). Selected by the bare `newhud` user-arg. The whole HUD is assembled from
# REGISTRIES (mechanics.gd) — this file wires the frame, never a concrete panel by type.
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
const TILE := 28

var session
var view: Node2D
var overlay_host: Node2D
var cam: Camera2D
var hud_root
var preg
var oreg
var bus
var balance
var router
var shot_mode := false
var _t := 0.0
var _built := false
var _shot := false

func _ready() -> void:
	# --- world space (WorldRoot): tilemap + overlays + camera ---
	view = WorldViewScript.new()
	add_child(view)
	overlay_host = OverlayHost.new()
	add_child(overlay_host)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()

	# --- session (real sim) ---
	session = SessionScript.new()
	session.start(50.4501, 30.5234, "Київ")
	view.sim = session.sim
	balance = Balance.Balance.new()

	# --- registries + feedback bus + router ---
	preg = PanelReg.PanelRegistry.new()
	oreg = OverlayReg.OverlayRegistry.new()
	bus = FeedbackBus.FeedbackBus.new()
	router = InputController.InputController.new()
	InputVerbs.install(router)
	CatalogVerbs.install(router, CatalogSim.shared())   # forward-engine build/craft/research commands
	Mechanics.register_all(preg, oreg)     # mechanics register themselves — no controller edit (R4)
	overlay_host.oreg = oreg
	overlay_host.map_n = int(session.sim.n)   # match the tilemap's cull extent (avoids overlay drift)

	# --- HUD layer ---
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	hud_root = HudRootScript.new()
	hud_root.theme = UITheme.build()       # ONE Theme resource from Tokens (§2.4)
	hud.add_child(hud_root)
	hud_root.setup(session, balance, bus, preg, oreg)
	hud_root.mount()

	# Wire every registered panel's intent bubble to the router (browsers emit cat_build/craft/research).
	for p in preg.panels:
		if p.has_signal("intent"):
			p.intent.connect(func(verb, args): router.dispatch(verb, args, session))

	if "newhud" in OS.get_cmdline_user_args() and "shot" in OS.get_cmdline_user_args():
		shot_mode = true

func _process(dt: float) -> void:
	if session == null:
		return
	if not session.sim.dead:
		session.sim.update(dt)
	CatalogSim.shared().tick(dt)   # advance the forward-engine catalogue model (research + station bills)
	cam.global_position = Vector2(session.sim.player.px * TILE, session.sim.player.py * TILE)
	view.queue_redraw()
	overlay_host.map_n = int(session.sim.n)   # keep in lockstep with the live region (survives travel)
	overlay_host.snap = hud_root.last_snap
	overlay_host.queue_redraw()
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
	var sim = session.sim
	sim.stock.wood = 240; sim.stock.stone = 240; sim.stock.scrap = 60; sim.stock.components = 12
	var c: Vector2i = sim.base_center()
	for d in range(-3, 4):
		_put("wall", c.x + d, c.y - 3); _put("wall", c.x + d, c.y + 3)
		_put("wall", c.x - 3, c.y + d); _put("wall", c.x + 3, c.y + d)
	_put("door", c.x, c.y + 3)
	_put("workbench", c.x - 1, c.y - 1)
	_put("bed", c.x + 1, c.y - 1)
	_put("turret", c.x - 2, c.y + 2)
	_put("turret", c.x + 2, c.y - 2)
	sim.player.px = c.x + 0.5; sim.player.py = c.y + 1.5
	router.dispatch(&"craft", {"id": "axe"}, session)
	router.dispatch(&"craft", {"id": "spear"}, session)

func _put(kind: String, x: int, y: int) -> void:
	if session.sim.build_valid(x, y) and GameData.can_afford(session.sim.stock, GameData.BUILDINGS[kind].cost):
		router.dispatch(&"build", {"kind": kind, "x": x, "y": y}, session)
