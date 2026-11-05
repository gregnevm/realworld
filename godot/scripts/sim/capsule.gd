# RealWorld — sim/capsule.gd : the MAIN CAPSULE domain of the live sim (spec 0010, wave W1a).
#
# Домен «Основна капсула»: гравець висаджує її на канонічній клітинці координат, вона — склад (capability
# `storage` через шов building_def), «трон» і незнищенний орієнтир. Патерн доменних модулів sim/ (threats/
# inventory/world_meta): static func над інстансом `s` (сим), модуль БЕЗ стану, без preload sim.gd (без циклу);
# sim.gd тримає лише однорядкові делегати/гілки під прапором `use_main_capsule`.
#
# Прапор OFF == код до спеки байт-у-байт (патерн use_catalog/use_inventory): при OFF sim викликає лише
# preflight/set_flag (вони повертають &""/значення й не торкаються світу), а def капсули резолвиться тільки
# коли прапор ON (sim.building_def).
#
# W1a покриває: прапор і явні помилки конфігурації (REQ-03/59), канонічну клітинку й посадку (REQ-04/73/98),
# склад (REQ-05), заборони видалення (REQ-06/75). Рівні/прокачка/бафи/рейд — наступні хвилі (W2…W3); шви
# 0011 (Орбіта) — окремо, sim/orbit_stub.gd (D2), не тут.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

const KIND := "main_capsule"
const NO_CELL := Vector2i(-1, -1)   # «клітинки нема» (повна мапа) — єдиний sentinel модуля
# Відмова гравцю при спробі покинути регіон/запустити капсулу (одне джерело: world_meta, session, refuses_region_swap).
const MSG_NO_TRAVEL := "Недоступно: Основна капсула — твій дім."

# Def капсули — те, що sim.building_def віддає за KIND при ON. Усі властивості — capability-поля, які
# sim/ уже читає з будь-якого def (blocks / capacity / storage / indestructible / landmark): жодного
# `if kind == "main_capsule"` у tick-шляхах. ЄМНІСТЬ — те саме число, що в data.gd-складу (одне джерело;
# нового числа тут нема: П10 лишається за власником), тож OFF-старт (200 + склад) і ON-старт (200 + капсула) рівні.
const DEF := {
	"name": "Основна капсула", "hp": 1.0, "blocks": true, "cost": {},
	"capacity": GameData.BUILDINGS["storage"]["capacity"],
	"storage": true, "indestructible": true, "landmark": true, "glyph": "◎",
}

# ---------------- config (REQ-0010-03 / 59) ----------------
# Помилка конфігурації для (use_inventory, use_catalog): &"" == можна. Порядок перевірки: інвентар → каталог.
static func config_error(use_inventory: bool, use_catalog: bool) -> StringName:
	if not use_inventory:
		return &"capsule_needs_inventory"
	if not use_catalog:
		return &"capsule_needs_catalog"
	return &""

# Усе, що new_game мусить знати ДО першої мутації: при OFF — &"" (старий шлях), при ON — конфігурація +
# чи є куди сісти (повна мапа — теж явна помилка, а не напівживий світ без капсули).
static func preflight(flag: bool, use_inventory: bool, use_catalog: bool, m: Dictionary) -> StringName:
	if not flag:
		return &""
	var err := config_error(use_inventory, use_catalog)
	if err == &"" and canon_cell(m) == NO_CELL:
		return &"capsule_no_room"
	return err

# Setter-guard прапора sim.use_main_capsule (REQ-0010-60): до new_game (мапа порожня) значення вільне, після —
# замкнене, а спроба зміни лишає значення й виставляє s.config_error = &"capsule_flag_locked".
static func set_flag(s, v: bool) -> bool:
	if (s.map as Dictionary).is_empty() or v == s.use_main_capsule:
		s.config_error = &""
		return v
	s.config_error = &"capsule_flag_locked"
	return s.use_main_capsule

# ---------------- canonical cell (REQ-0010-04 / 73) ----------------
# Клітинки на Чебишовській відстані рівно r від c, у детермінованому порядку (dx²+dy², y, x): порядок
# повний (пара (y,x) унікальна), тож сортування не залежить від реалізації sort.
static func ring(c: Vector2i, r: int) -> Array:
	if r <= 0:
		return [c]
	var out: Array = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) == r:
				out.append(Vector2i(c.x + dx, c.y + dy))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = (a.x - c.x) * (a.x - c.x) + (a.y - c.y) * (a.y - c.y)
		var db: int = (b.x - c.x) * (b.x - c.x) + (b.y - c.y) * (b.y - c.y)
		if da != db:
			return da < db
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	return out

# Клітинка під капсулу: на мапі, не вода/скеля, без ноди ресурсу, не зайнята. `occupied` — ключі = індекси
# клітинок y*n+x (як sim.bgrid) АБО Vector2i; значення байдужі.
static func cell_free(m: Dictionary, c: Vector2i, occupied: Dictionary = {}) -> bool:
	var n: int = int(m.n)
	if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
		return false
	var i: int = c.y * n + c.x
	if WorldGen.is_terrain_blocked(int(m.tiles[i])) or (m.nodes as Dictionary).has(i):
		return false
	return not (occupied.has(i) or occupied.has(c))

# Спіраль Чебишова від `start` за зростанням r: перше кільце з вільною клітинкою, усередині кільця
# мінімум (dx²+dy², y, x). NO_CELL — вільної клітинки на всій мапі нема.
static func nearest_free_cell(m: Dictionary, start: Vector2i, occupied: Dictionary = {}) -> Vector2i:
	for r in range(0, int(m.n) + 1):
		for c in ring(start, r):
			if cell_free(m, c, occupied):
				return c
	return NO_CELL

# Канонічна клітинка капсули: ЧИСТА функція мапи (а мапа — чиста функція lat/lon): m.spawn з _pick_spawn,
# а якщо клітинка зайнята/непрохідна/нода — стабільний зсув спіраллю. Ім'я canon_coord(lat,lon) зі спеки
# вже зайняте WorldGen.canon_coord (рядок-ключ регіону), тому тут canon_cell(map).
static func canon_cell(m: Dictionary, occupied: Dictionary = {}) -> Vector2i:
	return nearest_free_cell(m, m.spawn, occupied)

# ---------------- state ----------------
# Запис капсули в sim.main_capsule; tile — [x, y] (JSON-безпечний вигляд, схема §F контракту). Рівень 0 =
# базова капсула без бафів. Решта полів запису (landed_at, invested, …) додаються наступними хвилями.
static func new_record(cell: Vector2i) -> Dictionary:
	return {"kind": "main", "tile": [cell.x, cell.y], "level": 0}

static func tile(s) -> Vector2i:
	var t: Array = s.main_capsule.tile
	return Vector2i(int(t[0]), int(t[1]))

# ---------------- landing (REQ-0010-98: ЄДИНИЙ шов посадки) ----------------
# Перша посадка (капсули ще нема) ставить капсулу на canon_cell(pos) і героя поруч; повторна — лише героя
# біля наявної капсули. `region_key` повертається в результаті (його власник — Session.home, хвиля W1b).
static func landing(s, region_key: String, pos: Vector2i) -> Dictionary:
	var installed := false
	if (s.main_capsule as Dictionary).is_empty():
		var cell := nearest_free_cell(s.map, pos, s.bgrid)
		if cell == NO_CELL:
			return {"ok": false, "reason": &"no_room", "region_key": region_key}
		s.main_capsule = new_record(cell)
		s._place_building(KIND, cell.x, cell.y, -1)
		installed = true
	var hero := respawn_cell(s)
	s.player.px = hero.x + 0.5
	s.player.py = hero.y + 0.5
	s.player.action = null
	return {"ok": true, "cell": tile(s), "hero_cell": hero, "installed": installed, "region_key": region_key}

# Вільна прохідна клітинка біля капсули (не is_blocked, не нода): найближче кільце, усередині — (dx²+dy², y, x);
# якщо кільце 1 зайняте — кільце розширюється (споруди не знесено, REQ-0010-74). Стелі-числа нема: до краю мапи.
static func respawn_cell(s) -> Vector2i:
	var t := tile(s)
	for r in range(1, int(s.n) + 1):
		for c in ring(t, r):
			if not s.is_blocked(c.x, c.y) and not (s.map.nodes as Dictionary).has(c.y * int(s.n) + c.x):
				return c
	return s.map.spawn

# ---------------- region swaps (REQ-0010-04 / 75) ----------------
# Капсула ОДНА і лежить у своєму регіоні: arrive_region стирає будівлі регіону (разом із капсулою й bgrid), тож при ON
# «нова місцевість» відхиляється ДО мутацій (запис і будівля лишаються в узгодженні; не «висячий» запис із базою чужого
# регіону). Прямі виклики (Session.travel_to, тести) бачать ту саму відмову. true == відхилено (+ рядок у фід).
static func refuses_region_swap(s) -> bool:
	if s.get("use_main_capsule") != true:
		return false
	s._log(MSG_NO_TRAVEL, "warn")
	return true

# OSM-релокація (sim.after_map_change): при ON дім — капсула, а НЕ склад і не map.spawn (= клітинка самої капсули,
# непрохідна: герой, поставлений туди, застряг би в твердій клітинці). Герой — біля капсули тим самим швом landing
# (REQ-0010-98); склад-якір OFF не переноситься (капсула не рухається, REQ-0010-75). true == оброблено (OFF -> false).
static func on_map_change(s) -> bool:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return false
	landing(s, WorldGen.canon_coord(float(s.map.lat), float(s.map.lon)), s.map.spawn)
	s._recompute_indoor()
	return true

# ---------------- NPC-загрози й неруйнівна капсула (OD-58, critique-0010 #2, D8) ----------------
# Легасі-рейд (Director.apply -> Threats.update_raids/spawn_wave) і патруль націлюються на base_center() = капсулу, яку
# Threats.damage_building не шкодить (indestructible): рейдери стоять і б'ють без кінця — облога, що не може ні вдатися,
# ні скінчитись, з банером «РЕЙД». OD-58 (власник): перший NPC-рейд — лише після першої прокачки (до W2a її нема, рівень 0),
# а саме пробиття ядра (core_hp<=0) з'являється у W3. До рейд-автомата капсули (W3) усі ці загрози при ON ПРИДУШЕНІ —
# DROPPED, не відкладені (жодного прихованого стану-черги), а їхні кидки RNG лишаються (курсори потоків не зсуваються).
# Хвиля W3 замінює тіло цього предиката на ворота «рівень>=1, імунітет, грейс, один активний» (REQ-0010-20/62/65).
static func holds_npc_threats(s) -> bool:
	return s.get("use_main_capsule") == true
