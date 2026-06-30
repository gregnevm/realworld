# RealWorld — sim.gd : deterministic, scene-free game simulation (testable headless)
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

var map: Dictionary
var n: int = 0
var player: Dictionary = {}
var stock: Dictionary = {}
var buildings: Array = []
var bgrid: Dictionary = {}
var enemies: Array = []
var shots: Array = []
var time := {"frac": 0.28, "day": 1, "day_len": 150.0}
var raid := {"timer": 0.0, "next": 95.0, "active": false, "warned": false, "wave": 0}
var convoys: Array = []
var regions: Array = []
var convoy_seq := 0
var craft_timer := 0.0
var dead := false
var move_input := Vector2.ZERO
var messages: Array = []
var banner := ""
var flash_msg := ""
var flash_t := 0.0

var astar: AStarGrid2D            # terrain + blocking buildings (player)
var astar_terrain: AStarGrid2D    # terrain only (raiders smash walls)

# ---------------- setup ----------------
func new_game(m: Dictionary) -> void:
	map = m
	n = m.n
	var sp: Vector2i = m.spawn
	player = {
		"px": sp.x + 0.5, "py": sp.y + 0.5, "face": 0.0,
		"hp": 100.0, "hunger": 82.0, "rest": 92.0,
		"carry": {}, "carry_cap": 30, "action": null, "sleeping": false,
		"eat_cd": 0.0, "atk_cd": 0.0, "dep_cd": 0.0,
		"skills": {"gather": 0.0, "combat": 0.0},
		"equipped": {"tool": "", "weapon": ""}, "items": [],
	}
	stock = {"wood": 50, "stone": 30, "food": 18, "scrap": 16, "planks": 0, "components": 2}
	_build_astar()
	var lx := sp.x + 1
	var ly := sp.y
	if not build_valid(lx, ly):
		lx = sp.x
		ly = sp.y + 1
	_place_building("storage", lx, ly, -1)
	_init_regions()

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	astar_terrain = AStarGrid2D.new()
	astar_terrain.region = Rect2i(0, 0, n, n)
	astar_terrain.cell_size = Vector2(1, 1)
	astar_terrain.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_terrain.update()
	for y in n:
		for x in n:
			var solid := WorldGen.is_terrain_blocked(map.tiles[y * n + x])
			astar.set_point_solid(Vector2i(x, y), solid)
			astar_terrain.set_point_solid(Vector2i(x, y), solid)

func _refresh_solid(x: int, y: int) -> void:
	var i := y * n + x
	var solid := WorldGen.is_terrain_blocked(map.tiles[i])
	if bgrid.has(i) and GameData.BUILDINGS[bgrid[i].kind].get("blocks", false):
		solid = true
	astar.set_point_solid(Vector2i(x, y), solid)

func _init_regions() -> void:
	var home := {"name": map.get("place_name", "Поселення"), "lat": map.lat, "lon": map.lon, "home": true}
	var ranked := []
	for hb in GameData.HUBS:
		var d := WorldGen.haversine_km(home.lat, home.lon, hb.lat, hb.lon)
		if d > 8:
			ranked.append({"name": hb.name, "lat": hb.lat, "lon": hb.lon, "d": d})
	ranked.sort_custom(func(a, b): return a.d < b.d)
	regions = [home]
	for i in range(min(3, ranked.size())):
		var hb = ranked[i]
		regions.append({"name": hb.name, "lat": hb.lat, "lon": hb.lon, "d": hb.d, "offer": GameData.OFFERS[i % GameData.OFFERS.size()]})

# ---------------- helpers ----------------
func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < n and y < n

func _dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))

func is_blocked(x: int, y: int) -> bool:
	if not _in(x, y):
		return true
	if WorldGen.is_terrain_blocked(map.tiles[y * n + x]):
		return true
	if bgrid.has(y * n + x):
		return GameData.BUILDINGS[bgrid[y * n + x].kind].get("blocks", false)
	return false

func carry_total() -> int:
	var s := 0
	for k in player.carry:
		s += int(player.carry[k])
	return s

func stock_total() -> int:
	var s := 0
	for k in stock:
		s += int(floor(stock[k]))
	return s

func storage_cap() -> int:
	var c := 200
	for b in buildings:
		var def = GameData.BUILDINGS[b.kind]
		if def.has("capacity"):
			c += int(def.capacity)
	return c

func deposit(res: String, amt: int) -> int:
	var room: int = max(0, storage_cap() - stock_total())
	var add: int = min(amt, room)
	stock[res] = stock.get(res, 0) + add
	if add < amt:
		_log("⚠ Склад переповнений — частину втрачено.", "warn")
	return add

func base_center() -> Vector2i:
	for b in buildings:
		if b.kind == "storage":
			return Vector2i(b.x, b.y)
	return Vector2i(int(player.px), int(player.py))

func _nearest_enemy(x: float, y: float, maxr: float):
	var best = null
	var bd := maxr
	for e in enemies:
		var d := _dist(x, y, e.px, e.py)
		if d < bd:
			bd = d
			best = e
	return best

func _near_storage(r: float) -> bool:
	for b in buildings:
		if b.kind == "storage" and _dist(player.px, player.py, b.x + 0.5, b.y + 0.5) < r:
			return true
	return false

func _log(text: String, cls: String = "") -> void:
	messages.append({"text": text, "cls": cls})
	if messages.size() > 40:
		messages.remove_at(0)

func _flash(text: String) -> void:
	flash_msg = text
	flash_t = 2.2

# ---------------- building ----------------
func _place_building(kind: String, x: int, y: int, hp: float):
	var def = GameData.BUILDINGS[kind]
	var b := {"kind": kind, "x": x, "y": y, "hp": (def.hp if hp < 0 else hp), "cool": 0.0, "aim": 0.0}
	buildings.append(b)
	bgrid[y * n + x] = b
	if def.get("blocks", false):
		_refresh_solid(x, y)
	return b

func _remove_building(b) -> void:
	buildings.erase(b)
	bgrid.erase(b.y * n + b.x)
	_refresh_solid(b.x, b.y)

func build_valid(x: int, y: int) -> bool:
	if not _in(x, y):
		return false
	var t = map.tiles[y * n + x]
	if t == WorldGen.WATER or t == WorldGen.ROCK:
		return false
	if bgrid.has(y * n + x):
		return false
	if map.nodes.has(y * n + x):
		return false
	return true

func try_build(kind: String, x: int, y: int) -> void:
	if not build_valid(x, y):
		_flash("Тут не можна будувати.")
		return
	var def = GameData.BUILDINGS[kind]
	if not GameData.can_afford(stock, def.cost):
		_flash("Бракує: " + GameData.cost_str(def.cost))
		return
	GameData.pay_cost(stock, def.cost)
	_place_building(kind, x, y, -1)

# ---------------- items / equipment (spec 0001) ----------------
func gather_time(node) -> float:
	var info = GameData.NODEINFO[node.kind]
	var mult: float = 1.0 + player.skills.gather * 0.04
	var tool: String = player.equipped.get("tool", "")
	if tool != "" and GameData.ITEMS.has(tool):
		mult *= float(GameData.ITEMS[tool].get("gather_mult", 1.0))
	return info.time / mult

func melee_damage() -> float:
	var dmg: float = 12.0 + player.skills.combat
	var wpn: String = player.equipped.get("weapon", "")
	if wpn != "" and GameData.ITEMS.has(wpn):
		dmg += float(GameData.ITEMS[wpn].get("dmg_bonus", 0.0))
	return dmg

func has_workbench() -> bool:
	for b in buildings:
		if b.kind == "workbench":
			return true
	return false

func craft_item(item_id: String) -> Dictionary:
	if not GameData.ITEMS.has(item_id):
		return {"ok": false, "msg": "Невідомий предмет."}
	if player.items.has(item_id):
		equip(item_id)  # already owned -> just (re)equip for free, never re-pay
		_log("⚔ Екіпіровано: %s." % GameData.ITEMS[item_id].name)
		return {"ok": true}
	if not has_workbench():
		return {"ok": false, "msg": "Потрібен верстак."}
	var recipe = GameData.ITEMS[item_id].recipe
	if not GameData.can_afford(stock, recipe):
		return {"ok": false, "msg": "Бракує: " + GameData.cost_str(recipe)}
	GameData.pay_cost(stock, recipe)
	player.items.append(item_id)
	equip(item_id)
	_log("🛠 Скрафтив та екіпірував: %s." % GameData.ITEMS[item_id].name, "good")
	return {"ok": true}

func equip(item_id: String) -> void:
	if not GameData.ITEMS.has(item_id) or not player.items.has(item_id):
		return
	var slot: String = GameData.ITEMS[item_id].slot
	player.equipped[slot] = item_id

# ---------------- pathfinding ----------------
func _nearest_free(grid: AStarGrid2D, c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := c.x + dx
				var y := c.y + dy
				if not _in(x, y):
					continue
				if not grid.is_point_solid(Vector2i(x, y)):
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func _path_on(grid: AStarGrid2D, fx: int, fy: int, tx: int, ty: int) -> Array:
	tx = clampi(tx, 0, n - 1)
	ty = clampi(ty, 0, n - 1)
	var from := Vector2i(fx, fy)
	var tgt := Vector2i(tx, ty)
	if grid.is_point_solid(tgt):
		tgt = _nearest_free(grid, tgt)
		if tgt == Vector2i(-1, -1):
			return []
	# A solid start (e.g. player built a wall on their own tile) would otherwise
	# yield an empty path; clear it for the query to match JS (it escapes anyway).
	var start_solid := grid.is_point_solid(from)
	if start_solid:
		grid.set_point_solid(from, false)
	# allow_partial_path=true => best-effort partial path toward the closest
	# reachable cell when the target is unreachable (matches JS findPath semantics).
	var p = grid.get_id_path(from, tgt, true)
	if start_solid:
		grid.set_point_solid(from, true)
	var out := []
	for i in range(1, p.size()):
		out.append(p[i])
	return out

func compute_path(fx: int, fy: int, tx: int, ty: int) -> Array:
	return _path_on(astar, fx, fy, tx, ty)

func _terrain_path(fx: int, fy: int, tx: int, ty: int) -> Array:
	return _path_on(astar_terrain, fx, fy, tx, ty)

# ---------------- orders ----------------
func order_move(tx: int, ty: int) -> void:
	player.sleeping = false
	var path := compute_path(int(player.px), int(player.py), tx, ty)
	if path.is_empty():
		_flash("Туди не дійти.")
		return
	player.action = {"type": "move", "path": path, "cell": (ty * n + tx if _in(tx, ty) else -1)}

func order_gather(x: int, y: int) -> void:
	player.sleeping = false
	if not _in(x, y) or not map.nodes.has(y * n + x):
		return
	var path := compute_path(int(player.px), int(player.py), x, y)
	player.action = {"type": "gather", "nx": x, "ny": y, "cell": y * n + x, "path": path, "t": 0.0, "dur": 0.0}

func order_attack(e) -> void:
	player.sleeping = false
	player.action = {"type": "attack", "target": e, "path": [], "repath_cd": 0.0}

# ---------------- movement ----------------
func _step_to(o: Dictionary, tx: float, ty: float, step: float) -> bool:
	var dx: float = tx - o.px
	var dy: float = ty - o.py
	var d := sqrt(dx * dx + dy * dy)
	if d <= step or d < 1e-6:
		o.px = tx
		o.py = ty
		return true
	o.px += dx / d * step
	o.py += dy / d * step
	o.face = atan2(dy, dx)
	return false

func _follow_path(o: Dictionary, path: Array, step: float) -> bool:
	if path.is_empty():
		return true
	var nx: Vector2i = path[0]
	if _step_to(o, nx.x + 0.5, nx.y + 0.5, step):
		path.remove_at(0)
	return path.is_empty()

# ---------------- main update ----------------
func update(dt: float) -> void:
	if flash_t > 0:
		flash_t = max(0.0, flash_t - dt)
	if dead:
		return  # match JS: the sim freezes after death (no needs/raids/convoys advance)
	time.frac += dt / time.day_len
	while time.frac >= 1.0:
		time.frac -= 1.0
		time.day += 1
		_log("🌅 Новий день: %d" % time.day)
	_update_player(dt)
	_update_crafting(dt)
	_update_raids(dt)
	_update_enemies(dt)
	_update_turrets(dt)
	_update_convoys(dt)
	for i in range(shots.size() - 1, -1, -1):
		shots[i].t -= dt
		if shots[i].t <= 0:
			shots.remove_at(i)

func _update_player(dt: float) -> void:
	var p = player
	p.atk_cd = max(0.0, p.atk_cd - dt)
	p.eat_cd = max(0.0, p.eat_cd - dt)
	p.dep_cd = max(0.0, p.dep_cd - dt)
	p.hunger = clampf(p.hunger - 0.42 * dt, 0, 100)
	p.rest = clampf(p.rest - (-14.0 if p.sleeping else 0.30) * dt, 0, 100)
	if p.hunger <= 0:
		p.hp -= 2.0 * dt
	if p.rest <= 0:
		p.hp -= 1.0 * dt
	if p.hunger > 45 and p.rest > 25 and p.hp < 100:
		p.hp = min(100.0, p.hp + 0.7 * dt)
	p.hp = clampf(p.hp, 0, 100)
	if p.hp <= 0 and not dead:
		_on_death()
		return
	if p.hunger < 55 and p.eat_cd <= 0 and int(stock.get("food", 0)) >= 1 and _near_storage(2.2):
		stock.food -= 1
		p.hunger = min(100.0, p.hunger + 38.0)
		p.eat_cd = 2.5
	if carry_total() > 0 and p.dep_cd <= 0 and _near_storage(1.8):
		for k in p.carry.keys():
			if p.carry[k] > 0:
				var a := deposit(k, p.carry[k])
				p.carry[k] -= a
		p.dep_cd = 0.4
	if move_input.length() > 0.1:
		p.action = null
		p.sleeping = false
		var spd := 3.4 * dt
		var v := move_input.normalized()
		var nx: float = p.px + v.x * spd
		var ny: float = p.py + v.y * spd
		if not is_blocked(int(floor(nx)), int(floor(p.py))):
			p.px = nx
		if not is_blocked(int(floor(p.px)), int(floor(ny))):
			p.py = ny
		p.face = atan2(v.y, v.x)
		return
	if p.action == null:
		var e = _nearest_enemy(p.px, p.py, 1.4)
		if e != null:
			p.action = {"type": "attack", "target": e, "path": [], "repath_cd": 0.0}
	if p.action == null:
		_maybe_sleep(dt)
		return
	var step := 3.4 * dt
	match p.action.type:
		"move":
			if _follow_path(p, p.action.path, step):
				p.action = null
		"gather":
			_do_gather(dt, step)
		"attack":
			_do_attack(dt, step)

func _do_gather(dt: float, step: float) -> void:
	var p = player
	var a = p.action
	if not map.nodes.has(a.cell):
		p.action = null
		return
	var node = map.nodes[a.cell]
	if _dist(p.px, p.py, a.nx + 0.5, a.ny + 0.5) >= 1.4:
		var done := _follow_path(p, a.path, step)
		p.face = atan2(a.ny + 0.5 - p.py, a.nx + 0.5 - p.px)
		if done and not WorldGen.is_terrain_blocked(map.tiles[a.cell]):
			_step_to(p, a.nx + 0.5, a.ny + 0.5, step)
		return
	var info = GameData.NODEINFO[node.kind]
	a.dur = gather_time(node)
	a.t += dt
	if a.t >= a.dur:
		a.t = 0.0
		if carry_total() >= p.carry_cap:
			_flash("Несеш максимум — на склад 📦.")
			p.action = null
			return
		p.carry[info.res] = p.carry.get(info.res, 0) + 1
		node.amount -= 1
		p.skills.gather = min(20.0, p.skills.gather + 0.2)
		if node.amount <= 0:
			map.nodes.erase(a.cell)
			p.action = null

func _do_attack(dt: float, step: float) -> void:
	var p = player
	var a = p.action
	var e = a.target
	if e == null or e.dead or not enemies.has(e):
		var nx = _nearest_enemy(p.px, p.py, 2.5)
		if nx != null:
			a.target = nx
			e = nx
		else:
			p.action = null
			return
	var d := _dist(p.px, p.py, e.px, e.py)
	if d > 1.25:
		a.repath_cd -= dt
		if a.path.is_empty() or a.repath_cd <= 0:
			a.path = compute_path(int(p.px), int(p.py), int(e.px), int(e.py))
			a.repath_cd = 0.4
		_follow_path(p, a.path, step)
		p.face = atan2(e.py - p.py, e.px - p.px)
	else:
		p.face = atan2(e.py - p.py, e.px - p.px)
		if p.atk_cd <= 0:
			_damage_enemy(e, melee_damage())
			p.atk_cd = 0.7
			p.skills.combat = min(20.0, p.skills.combat + 0.15)

func _maybe_sleep(_dt: float) -> void:
	var p = player
	if p.rest >= 99:
		p.sleeping = false
		return
	var bed = null
	for b in buildings:
		if b.kind == "bed" and _dist(p.px, p.py, b.x + 0.5, b.y + 0.5) < 1.6:
			bed = b
			break
	p.sleeping = (bed != null and _nearest_enemy(p.px, p.py, 9) == null)

func _update_crafting(dt: float) -> void:
	var count := 0
	for b in buildings:
		if b.kind == "workbench":
			count += 1
	if count == 0:
		return
	craft_timer += dt * count
	while craft_timer >= 3.5:
		craft_timer -= 3.5
		if int(stock.get("wood", 0)) >= 2 and stock_total() < storage_cap():
			stock.wood -= 2
			stock.planks = stock.get("planks", 0) + 1

# ---------------- raids ----------------
func _update_raids(dt: float) -> void:
	var r = raid
	if r.active:
		if enemies.is_empty():
			r.active = false
			r.warned = false
			r.next = 78.0 + randf() * 46.0
			r.timer = 0.0
			banner = ""
			_log("✅ Рейд відбито!", "good")
		return
	r.timer += dt
	if not r.warned and r.timer > r.next - 12.0:
		r.warned = true
		banner = "⚠ НАБЛИЖАЄТЬСЯ РЕЙД"
		_log("⚠ Рейдери на підході — укріплюй базу!", "warn")
	if r.timer >= r.next:
		_spawn_wave()

func _spawn_wave() -> void:
	var r = raid
	r.active = true
	r.wave += 1
	var cnt := GameData.raid_wave_size(time.day)
	var edge := randi() % 4
	var placed := 0
	var guard := 0
	while placed < cnt and guard < 500:
		guard += 1
		var x := 0
		var y := 0
		var o := 1 + randi() % 3
		match edge:
			0:
				x = o
				y = 2 + randi() % (n - 4)
			1:
				x = n - 1 - o
				y = 2 + randi() % (n - 4)
			2:
				x = 2 + randi() % (n - 4)
				y = o
			_:
				x = 2 + randi() % (n - 4)
				y = n - 1 - o
		if WorldGen.is_terrain_blocked(map.tiles[y * n + x]):
			continue
		enemies.append(GameData.make_raider(x + 0.5, y + 0.5, time.day))
		placed += 1
	banner = "⚔ РЕЙД! %d рейдерів" % cnt
	_log("⚔ Рейд #%d: %d рейдерів атакують базу!" % [r.wave, cnt], "bad")

func _update_enemies(dt: float) -> void:
	var p = player
	var center := base_center()
	for k in range(enemies.size() - 1, -1, -1):
		var e = enemies[k]
		e.atk_cd = max(0.0, e.atk_cd - dt)
		e.hit_flash = max(0.0, e.hit_flash - dt)
		var step: float = e.speed * dt
		var dtp := _dist(e.px, e.py, p.px, p.py)
		if dtp < 1.25:
			e.face = atan2(p.py - e.py, p.px - e.px)
			if e.atk_cd <= 0:
				p.hp = clampf(p.hp - e.dmg, 0, 100)
				e.atk_cd = 1.1
				if p.hp <= 0 and not dead:
					_on_death()
			continue
		var st = null
		for b in buildings:
			if b.kind == "storage" and _dist(e.px, e.py, b.x + 0.5, b.y + 0.5) < 1.35:
				st = b
				break
		if st != null:
			if e.atk_cd <= 0:
				_damage_building(st, e.dmg, true)
				e.atk_cd = 1.0
			continue
		var tx := int(p.px) if dtp < 6 else center.x
		var ty := int(p.py) if dtp < 6 else center.y
		e.path_cd -= dt
		if e.path.is_empty() or e.path_cd <= 0 or e.tx != tx or e.ty != ty:
			e.tx = tx
			e.ty = ty
			e.path_cd = 0.9 + randf() * 0.5
			e.path = _terrain_path(int(e.px), int(e.py), tx, ty)
		if not e.path.is_empty():
			var nx: Vector2i = e.path[0]
			var bi := nx.y * n + nx.x
			if bgrid.has(bi) and GameData.BUILDINGS[bgrid[bi].kind].get("blocks", false):
				e.face = atan2(nx.y + 0.5 - e.py, nx.x + 0.5 - e.px)
				if e.atk_cd <= 0:
					_damage_building(bgrid[bi], e.dmg, false)
					e.atk_cd = 1.0
			else:
				if _step_to(e, nx.x + 0.5, nx.y + 0.5, step):
					e.path.remove_at(0)
		else:
			_step_to(e, center.x + 0.5, center.y + 0.5, step)

func _update_turrets(dt: float) -> void:
	for b in buildings:
		if b.kind != "turret":
			continue
		var def = GameData.BUILDINGS.turret
		b.cool = max(0.0, b.cool - dt)
		var e = _nearest_enemy(b.x + 0.5, b.y + 0.5, def.range)
		if e == null:
			continue
		b.aim = atan2(e.py - (b.y + 0.5), e.px - (b.x + 0.5))
		if b.cool <= 0:
			b.cool = 0.5
			_damage_enemy(e, def.dps * 0.5)
			shots.append({"x1": b.x + 0.5, "y1": b.y + 0.5, "x2": e.px, "y2": e.py, "t": 0.12})

func _damage_building(b, amt: float, steal: bool) -> void:
	b.hp -= amt
	if steal and b.kind == "storage":
		var keys := []
		for kk in GameData.RES_ORDER:
			if int(stock.get(kk, 0)) > 0:
				keys.append(kk)
		if not keys.is_empty():
			var kk = keys[randi() % keys.size()]
			var lost: int = min(int(stock[kk]), 1 + randi() % 2)
			stock[kk] -= lost
	if b.hp <= 0:
		_remove_building(b)
		_log("💥 %s зруйновано рейдерами." % GameData.BUILDINGS[b.kind].name, "bad")

func _damage_enemy(e, amt: float) -> void:
	e.hp -= amt
	e.hit_flash = 0.12
	if e.hp <= 0 and not e.dead:
		e.dead = true
		enemies.erase(e)
		deposit("scrap", 2 + randi() % 2)
		if randf() < 0.25:
			deposit("components", 1)
		if randf() < 0.4:
			deposit("food", 1)

func _on_death() -> void:
	dead = true
	banner = ""
	_log("☠ Твій персонаж загинув.", "bad")

# ---------------- logistics ----------------
func dispatch_convoy(hub_index: int, send_res: String, send_amt: int) -> Dictionary:
	if hub_index <= 0 or hub_index >= regions.size():
		return {"ok": false, "msg": "Невірний пункт."}
	var hub = regions[hub_index]
	if hub.get("home", false):
		return {"ok": false, "msg": "Невірний пункт."}
	send_amt = max(1, int(send_amt))
	if int(stock.get(send_res, 0)) < send_amt:
		return {"ok": false, "msg": "Недостатньо ресурсу на складі."}
	if send_res != hub.offer.buys:
		return {"ok": false, "msg": "%s приймає лише %s." % [hub.name, GameData.RES[hub.offer.buys].label]}
	stock[send_res] -= send_amt
	var recv_res = hub.offer.sells
	var recv_amt: int = max(1, int(send_amt / int(hub.offer.rate)))
	var dist := WorldGen.haversine_km(regions[0].lat, regions[0].lon, hub.lat, hub.lon)
	var one_way := clampf(dist * 0.045, 7, 55)
	convoy_seq += 1
	convoys.append({
		"id": convoy_seq, "hub_index": hub_index, "hub_name": hub.name,
		"send_res": send_res, "send_amt": send_amt, "recv_res": recv_res, "recv_amt": recv_amt,
		"phase": "out", "t": 0.0, "dur": one_way, "dist": int(dist), "ambushed": false,
	})
	_log("🚚 Конвой #%d вирушив до %s (%d км)." % [convoy_seq, hub.name, int(dist)], "good")
	return {"ok": true}

func _update_convoys(dt: float) -> void:
	for k in range(convoys.size() - 1, -1, -1):
		var c = convoys[k]
		c.t += dt
		if c.t < c.dur:
			continue
		if c.phase == "out":
			c.phase = "back"
			c.t = 0.0
			_log("🔄 Конвой #%d обміняв вантаж у %s." % [c.id, c.hub_name])
			if randf() < 0.25:
				c.ambushed = true
				var lost: int = max(1, int(round(c.recv_amt * (0.3 + randf() * 0.4))))
				c.recv_amt = max(0, c.recv_amt - lost)
				_log("⚔ Засідка на конвой #%d! −%d." % [c.id, lost], "bad")
		else:
			deposit(c.recv_res, c.recv_amt)
			_log("📦 Конвой #%d повернувся: +%d %s." % [c.id, c.recv_amt, GameData.RES[c.recv_res].icon], "good")
			convoys.remove_at(k)

# ---------------- presentation helpers ----------------
func daylight() -> float:
	var sun := -cos(time.frac * TAU)
	return clampf(0.46 * (1.0 - (sun * 0.5 + 0.5)), 0.0, 0.46)

func phase_name() -> String:
	var f = time.frac
	if f < 0.22 or f > 0.80:
		return "🌙 ніч"
	if f < 0.30:
		return "🌅 світанок"
	if f > 0.72:
		return "🌇 сутінки"
	return "☀ день"

func clock_str() -> String:
	var mins := int(time.frac * 24 * 60)
	return "%02d:%02d" % [mins / 60, mins % 60]
