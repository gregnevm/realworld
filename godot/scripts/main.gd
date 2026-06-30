# RealWorld — main.gd : scene controller (spawn screen, HUD, input, loop)
extends Node2D

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const WorldViewScript = preload("res://scripts/world_view.gd")
const TILE := 28

var sim
var view: Node2D
var cam: Camera2D
var playing := false
var speed := 1.0
var speed_idx := 0
const SPEEDS := [1.0, 2.0, 3.0, 0.0]

# auto/screenshot mode
var auto_mode := false
var auto_t := 0.0
var auto_built := false
var auto_shot := false

# UI refs
var spawn_layer: CanvasLayer
var hud: CanvasLayer
var info_label: Label
var stock_label: Label
var log_label: Label
var banner_label: Label
var flash_label: Label
var build_bar: HBoxContainer
var build_buttons := {}
var night_rect: ColorRect
var world_panel: PanelContainer

const PRESETS := [
	{"name": "Київ", "lat": 50.4501, "lon": 30.5234},
	{"name": "Львів", "lat": 49.8397, "lon": 24.0297},
	{"name": "Манхеттен", "lat": 40.7549, "lon": -73.9840},
	{"name": "Кіото", "lat": 35.0116, "lon": 135.7681},
	{"name": "Рейк'явік", "lat": 64.1466, "lon": -21.9426},
]

func _ready() -> void:
	_build_world_nodes()
	_build_hud()
	_build_spawn_screen()
	if "auto" in OS.get_cmdline_user_args():
		_start_game(50.4501, 30.5234, "Київ")
		auto_mode = true

func _build_world_nodes() -> void:
	view = WorldViewScript.new()
	add_child(view)
	cam = Camera2D.new()
	cam.zoom = Vector2(1, 1)
	add_child(cam)
	cam.make_current()

func _build_spawn_screen() -> void:
	spawn_layer = CanvasLayer.new()
	spawn_layer.layer = 5
	add_child(spawn_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	spawn_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 200, 120)
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 10)
	spawn_layer.add_child(box)
	var title := Label.new()
	title.text = "RealWorld — Godot"
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Survival-MMORPG на справжній географії. Обери точку висадки:"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	for pr in PRESETS:
		var btn := Button.new()
		btn.text = "%s  (%.3f, %.3f)" % [pr.name, pr.lat, pr.lon]
		btn.pressed.connect(_start_game.bind(pr.lat, pr.lon, pr.name))
		box.add_child(btn)
	var hint := Label.new()
	hint.text = "Керування: клік — іти/добувати/атакувати · WASD · 1–7 будувати · M — логістика · Space — пауза"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.6, 0.7, 0.8)
	box.add_child(hint)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 3
	add_child(hud)

	night_rect = ColorRect.new()
	night_rect.color = Color(0.03, 0.05, 0.13, 0.0)
	night_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	night_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(night_rect)

	info_label = _mk_label(hud, Vector2(12, 10), 16)
	stock_label = _mk_label(hud, Vector2(0, 10), 15)
	stock_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stock_label.position = Vector2(get_viewport().get_visible_rect().size.x - 190, 10)
	stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	banner_label = _mk_label(hud, Vector2(0, 8), 18)
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.modulate = Color(1, 0.6, 0.6)

	flash_label = _mk_label(hud, Vector2(0, 0), 15)
	flash_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	flash_label.position += Vector2(0, -120)

	log_label = _mk_label(hud, Vector2(12, 0), 13)
	log_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_label.position = Vector2(12, get_viewport().get_visible_rect().size.y - 150)

	build_bar = HBoxContainer.new()
	build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_bar.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 250, get_viewport().get_visible_rect().size.y - 54)
	hud.add_child(build_bar)
	var idx := 1
	for key in GameData.BUILD_ORDER:
		var def = GameData.BUILDINGS[key]
		var btn := Button.new()
		btn.text = "%d %s\n%s" % [idx, def.name, GameData.cost_str(def.cost)]
		btn.custom_minimum_size = Vector2(78, 44)
		btn.pressed.connect(_select_build.bind(key))
		build_bar.add_child(btn)
		build_buttons[key] = btn
		idx += 1

	# world / logistics panel (hidden)
	world_panel = PanelContainer.new()
	world_panel.visible = false
	world_panel.set_anchors_preset(Control.PRESET_CENTER)
	world_panel.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 180, 120)
	world_panel.custom_minimum_size = Vector2(360, 0)
	hud.add_child(world_panel)

func _mk_label(parent: CanvasLayer, pos: Vector2, fsize: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l

func _start_game(lat: float, lon: float, place_name: String) -> void:
	var m := WorldGen.generate_map(lat, lon, 56)
	m["place_name"] = place_name
	sim = Sim.new()
	sim.new_game(m)
	view.sim = sim
	playing = true
	spawn_layer.visible = false
	sim._log("Висадка: %s · біом %s" % [place_name, m.biome], "good")

func _process(dt: float) -> void:
	if not playing:
		return
	if not auto_mode:
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W): mv.y -= 1
		if Input.is_key_pressed(KEY_S): mv.y += 1
		if Input.is_key_pressed(KEY_A): mv.x -= 1
		if Input.is_key_pressed(KEY_D): mv.x += 1
		sim.move_input = mv
	var sdt := dt * speed
	if sdt > 0:
		sim.update(sdt)
	cam.global_position = Vector2(sim.player.px * TILE, sim.player.py * TILE)
	view.hover = _mouse_tile()
	view.queue_redraw()
	_update_hud()
	if auto_mode:
		_auto_step(dt)

func _update_hud() -> void:
	var p = sim.player
	info_label.text = "День %d · %s %s\nHP   %s %d\nГолод %s %d\nВідпоч %s %d\nНесе: %d/%d" % [
		sim.time.day, sim.clock_str(), sim.phase_name(),
		_bar(p.hp), int(p.hp), _bar(p.hunger), int(p.hunger), _bar(p.rest), int(p.rest),
		sim.carry_total(), p.carry_cap]
	var st := "Склад %d/%d\n" % [sim.stock_total(), sim.storage_cap()]
	for k in GameData.RES_ORDER:
		st += "%s %d\n" % [GameData.RES[k].label, int(sim.stock.get(k, 0))]
	stock_label.text = st
	banner_label.text = sim.banner
	flash_label.text = sim.flash_msg if sim.flash_t > 0 else ""
	var lines := []
	var start: int = max(0, sim.messages.size() - 5)
	for i in range(start, sim.messages.size()):
		lines.append(sim.messages[i].text)
	log_label.text = "\n".join(lines)
	for key in build_buttons:
		build_buttons[key].modulate = Color(1, 1, 1) if GameData.can_afford(sim.stock, GameData.BUILDINGS[key].cost) else Color(1, 1, 1, 0.5)
		build_buttons[key].button_pressed = (view.selected_build == key)
	night_rect.color.a = sim.daylight()

func _bar(v: float) -> String:
	var filled := int(round(v / 100.0 * 6))
	return "[" + "#".repeat(filled) + "-".repeat(6 - filled) + "]"

func _mouse_tile() -> Vector2i:
	var w := get_global_mouse_position()
	return Vector2i(int(floor(w.x / TILE)), int(floor(w.y / TILE)))

func _select_build(key: String) -> void:
	view.selected_build = "" if view.selected_build == key else key

func _unhandled_input(event: InputEvent) -> void:
	if not playing or auto_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(_mouse_tile())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			view.selected_build = ""
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_7:
			var bi: int = k - KEY_1
			if bi < GameData.BUILD_ORDER.size():
				_select_build(GameData.BUILD_ORDER[bi])
		elif k == KEY_SPACE:
			_cycle_speed()
		elif k == KEY_M:
			_toggle_world()
		elif k == KEY_ESCAPE:
			view.selected_build = ""
			sim.player.action = null

func _handle_click(t: Vector2i) -> void:
	if view.selected_build != "":
		sim.try_build(view.selected_build, t.x, t.y)
		return
	# attack a nearby enemy?
	var best = null
	var bd := 0.7
	var fx := get_global_mouse_position().x / TILE
	var fy := get_global_mouse_position().y / TILE
	for e in sim.enemies:
		var d: float = sqrt((e.px - fx) * (e.px - fx) + (e.py - fy) * (e.py - fy))
		if d < bd:
			bd = d
			best = e
	if best != null:
		sim.order_attack(best)
		return
	if sim.map.nodes.has(t.y * sim.n + t.x):
		sim.order_gather(t.x, t.y)
	else:
		sim.order_move(t.x, t.y)

func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	speed = SPEEDS[speed_idx]

func _toggle_world() -> void:
	world_panel.visible = not world_panel.visible
	if not world_panel.visible:
		return
	for c in world_panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	world_panel.add_child(vb)
	var title := Label.new()
	title.text = "🗺 Логістика — конвої (везе 20 од.)"
	vb.add_child(title)
	for i in range(1, sim.regions.size()):
		var r = sim.regions[i]
		var btn := Button.new()
		btn.text = "→ %s (%d км): %s → %s" % [r.name, int(r.d), GameData.RES[r.offer.buys].label, GameData.RES[r.offer.sells].label]
		btn.pressed.connect(_send_convoy.bind(i))
		vb.add_child(btn)
	var close := Button.new()
	close.text = "Закрити"
	close.pressed.connect(func(): world_panel.visible = false)
	vb.add_child(close)

func _send_convoy(hub_index: int) -> void:
	var r = sim.regions[hub_index]
	var res = sim.dispatch_convoy(hub_index, r.offer.buys, 20)
	if not res.ok:
		sim._flash(res.msg)

# ---------------- auto screenshot mode ----------------
func _auto_step(dt: float) -> void:
	auto_t += dt
	if not auto_built and auto_t > 0.15:
		auto_built = true
		_auto_build_base()
	if auto_t > 2.6 and not auto_shot:
		auto_shot = true
		_capture_and_quit()

func _auto_build_base() -> void:
	sim.stock.wood = 240
	sim.stock.stone = 240
	sim.stock.scrap = 60
	sim.stock.components = 12
	var c = sim.base_center()
	for d in range(-3, 4):
		_put("wall", c.x + d, c.y - 3)
		_put("wall", c.x + d, c.y + 3)
		_put("wall", c.x - 3, c.y + d)
		_put("wall", c.x + 3, c.y + d)
	_put("door", c.x, c.y + 3)
	_put("workbench", c.x - 1, c.y - 1)
	_put("bed", c.x + 1, c.y - 1)
	_put("turret", c.x - 2, c.y + 2)
	_put("turret", c.x + 2, c.y - 2)
	sim.player.px = c.x + 0.5
	sim.player.py = c.y + 1.5
	sim.time.frac = 0.46

func _put(kind: String, x: int, y: int) -> void:
	if sim.build_valid(x, y) and GameData.can_afford(sim.stock, GameData.BUILDINGS[kind].cost):
		sim.try_build(kind, x, y)

func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("O:/realworld/godot/auto_shot.png")
	print("AUTO_SHOT saved")
	get_tree().quit()
