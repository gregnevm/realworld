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
# склад (REQ-05), заборони видалення (REQ-06/75). W1b: запис капсули в сейві/хеші (REQ-02/35/60/82/83), респавн біля
# капсули (REQ-07/08/09/74/96), місце респавну — respawn_anchor, посадка — ЄДИНИЙ landing (REQ-98). Рівні/прокачка/
# бафи/рейд — наступні хвилі (W2…W3); шви 0011 (Орбіта) — окремо, sim/orbit_stub.gd (D2), не тут.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const Clock = preload("res://scripts/clock.gd")   # лише to_wire/from_wire (int64 <-> рядок JSON); годинник сим не читає

const KIND := "main_capsule"
const RECORD_VERSION := 1   # версія ЗАПИСУ капсули в сейві (SAVE_VERSION не чіпаємо: OD-C14); невідома версія — явна помилка
const OWNER_LOCAL := "local"   # K1 — соло: власник один, локальний
const NO_CELL := Vector2i(-1, -1)   # «клітинки нема» (повна мапа) — єдиний sentinel модуля
# Відмова гравцю при спробі покинути регіон/запустити капсулу (одне джерело: world_meta, session, refuses_region_swap).
const MSG_NO_TRAVEL := "Недоступно: Основна капсула — твій дім."
# Рядки смерті/респавну при ON (REQ-0010-10): без «новий виживальник у поселенні»; OFF-рядки лишаються в threats.gd дослівно.
const MSG_DEATH := "☠ Загибель. Торба лишилась на місці. З'явишся біля капсули."
const MSG_RESPAWN := "Ти знову біля капсули — навички з нуля."   # D14: без граматичного роду; текст підтверджує дизайнер

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
# Запис капсули в sim.main_capsule (ПАМ'ЯТЬ): tile — [x, y] (JSON-безпечний вигляд, схема §F контракту), час — цілі UTC-мс
# (int64) з ВХОДУ sim.now_ms (Session пушить годинник ДО new_game; 0 == годинник не подано — явний стан, а не «зараз»).
# Рівень 0 = базова капсула без бафів. Поля схеми додаються ПОСТУПОВО, щоб кожна хвиля мала власні хеш-докази
# (REQ-0010-35/82): W1b — tile/owner/landed_at/grace_start/level; invested — W2a; immune_until/жетон/курсор рейду — W3a.
static func new_record(cell: Vector2i, now_ms: int = 0) -> Dictionary:
	return {"kind": "main", "tile": [cell.x, cell.y], "level": 0, "owner": OWNER_LOCAL, "landed_at": now_ms, "grace_start": now_ms}

static func tile(s) -> Vector2i:
	var t: Array = s.main_capsule.tile
	return Vector2i(int(t[0]), int(t[1]))

# ---------------- save record (REQ-0010-02 / 35 / 60 / 82) ----------------
# Серіалізований вигляд: version — версія ЗАПИСУ, час — РЯДКОМ (int64, як курсори RNG). Він входить і в serialize_region
# (сейв), і в world_hash; sim.now_ms — НІ (годинник — вхід, не стан світу). Запис БУДІВЛІ капсули в `buildings` не
# серіалізується: єдина правда про позицію — main_capsule.tile.
static func to_record(s) -> Dictionary:
	var c: Dictionary = s.main_capsule
	var t: Vector2i = tile(s)
	return {"version": RECORD_VERSION, "kind": String(c.get("kind", "main")), "tile": [t.x, t.y], "level": int(c.get("level", 0)),
		"owner": String(c.get("owner", OWNER_LOCAL)), "landed_at": Clock.to_wire(int(c.get("landed_at", 0))),
		"grace_start": Clock.to_wire(int(c.get("grace_start", 0)))}

# Обернене до to_record + ставить БУДІВЛЮ капсули. {} (OFF-запис) лише скидає запис. Викликається ПЕРЕД циклом будівель
# load_region: капсула стає buildings[0], як у new_game (порядок обходу _nearest_storage збігається між живим і
# відновленим симом). Припускає validate_region(...) == &"". Рівень поки не клампиться: таблиця рівнів (W2a) і
# REQ-0010-88 («рівень кламиться до нового максимуму») приходять разом.
static func from_record(s, rec: Dictionary) -> void:
	if rec.is_empty():
		s.main_capsule = {}
		return
	var t: Array = rec.tile
	var cell := Vector2i(int(t[0]), int(t[1]))
	s.main_capsule = new_record(cell, Clock.from_wire(rec.get("landed_at"), 0))
	s.main_capsule.level = maxi(0, int(rec.get("level", 0)))
	s.main_capsule.owner = String(rec.get("owner", OWNER_LOCAL))
	s.main_capsule.grace_start = Clock.from_wire(rec.get("grace_start"), 0)
	s._place_building(KIND, cell.x, cell.y, -1)

# Найперший крок load_region — ДО будь-якої мутації світу: &"" == можна завантажувати, інакше явна причина
# (sim.load_error; Persistence.restore і Session.restore_game відхиляють ВЕСЬ відновлення, REQ-0010-60/83):
#   • прапор ≠ прапор уже запущеного sim              -> capsule_flag_mismatch (прапор незмінний після new_game);
#   • main_capsule без прапора                        -> capsule_orphan (прапор зник: мовчки «OFF» дав би світ без складу);
#   • нема ні прапора, ні запису                      -> &"" (звичайний OFF-запис / старий сейв, REQ-0010-61);
#   • прапор без запису або з порожнім записом        -> capsule_missing (REQ-0010-83: ON-сейв без капсули);
#   • версія запису != RECORD_VERSION                 -> capsule_version (новіша за цю збірку або зіпсована);
#   • ON-запис без інвентаря/каталогу                 -> та сама помилка конфігурації, що в new_game (REQ-0010-03/59);
#   • зіпсовані поля (tile поза мапою, рівень < 0…)   -> capsule_invalid.
static func validate_region(rec: Dictionary, sim_started: bool, sim_flag: bool) -> StringName:
	var flag: bool = bool(rec.get("use_main_capsule", false))
	if sim_started and flag != sim_flag:
		return &"capsule_flag_mismatch"
	if not flag:
		return &"capsule_orphan" if rec.has("main_capsule") else &""
	var cap: Variant = rec.get("main_capsule", null)
	if not (cap is Dictionary) or (cap as Dictionary).is_empty():
		return &"capsule_missing"
	var c: Dictionary = cap
	if Clock.from_wire(c.get("version"), -1) != RECORD_VERSION:
		return &"capsule_version"
	var err := config_error(bool(rec.get("use_inventory", false)), bool(rec.get("use_catalog", false)))
	if err != &"":
		return err
	return &"" if _fields_ok(c, int(rec.get("n", 0))) else &"capsule_invalid"

static func _whole(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v) and v == floorf(v))

static func _fields_ok(c: Dictionary, n: int) -> bool:
	var t: Variant = c.get("tile")
	if not (t is Array) or (t as Array).size() != 2:
		return false
	for v in (t as Array):
		if not _whole(v) or int(v) < 0 or int(v) >= n:
			return false
	return String(c.get("kind", "")) == "main" and c.get("owner") is String and _whole(c.get("level")) and int(c.level) >= 0 \
		and Clock.from_wire(c.get("landed_at"), -1) >= 0 and Clock.from_wire(c.get("grace_start"), -1) >= 0

# ---------------- landing (REQ-0010-98: ЄДИНИЙ шов посадки) ----------------
# Перша посадка (капсули ще нема) ставить капсулу на canon_cell(pos) і героя поруч; повторна — лише героя
# біля наявної капсули: `pos` повторної посадки — анонс respawn_anchor, а клітинку героя ЗАВЖДИ перераховує respawn_cell
# (та сама функція, що в анонсі, D9) за живою дошкою: застарілий анонс не поставить героя в стіну.
# `region_key` повертається в результаті (його власник — Session.home).
static func landing(s, region_key: String, pos: Vector2i) -> Dictionary:
	var installed := false
	if (s.main_capsule as Dictionary).is_empty():
		var cell := nearest_free_cell(s.map, pos, s.bgrid)
		if cell == NO_CELL:
			return {"ok": false, "reason": &"no_room", "region_key": region_key}
		s.main_capsule = new_record(cell, int(s.now_ms))   # landed_at/grace_start = вхід годинника (REQ-0010-35/92)
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

# ---------------- respawn (REQ-0010-07 / 08 / 09 / 10 / 96) ----------------
# ГДЕ з'являється герой: {region_key, pos}. ON — регіон капсули з Session.home {region_key, tile} (REQ-0010-09: `home` при
# ON і є посиланням на капсулу) і pos = ВІЛЬНА ПРОХІДНА клітинка біля капсули (REQ-0010-09 «повертає клітинку біля капсули»,
# REQ-0010-74: шов сам розширює пошук, а не віддає клітинку капсули); OFF — регіон дому й NO_CELL («позицію добирає старий
# респавн»). Єдина сигнатура шва (власник — 0010). ЧИЄ тіло — шов OrbitStub.respawn_source (0011).
# ОДНА ПРАВДА (D9): pos рахує respawn_cell — та сама функція, якою landing ставить героя, тож анонсована клітинка і клітинка
# посадки збігаються за побудовою (споживач шва без посадки — напр. прев'ю 0012 — бачить правду). Клітинку шукаємо навколо
# капсули ЖИВОГО сима (єдина правда про її місце), а не навколо home.tile: home.tile — посилання для сесії без світу.
static func respawn_anchor(session) -> Dictionary:
	var h: Dictionary = session.home
	var sim: Variant = session.sim
	if sim != null and sim.get("use_main_capsule") == true and not (sim.main_capsule as Dictionary).is_empty():
		var key: String = String(h.get("region_key", WorldGen.canon_coord(float(sim.map.lat), float(sim.map.lon))))
		return {"region_key": key, "pos": respawn_cell(sim)}
	return {"region_key": WorldGen.canon_coord(float(h.lat), float(h.lon)), "pos": NO_CELL}

# ON: новий герой біля капсули. Тіло — шов respawn_source (стаб 0011), місце — ЄДИНИЙ шов landing (REQ-0010-98); капсула,
# її рівень, склад і ledger не чіпаються (REQ-0010-96), стан ворогів/рейду — теж: «смерть не скасовує рейд» (REQ-0010-63,
# рейд-автомат — W3), а sim.update стоїть, поки герой мертвий. Стан капсули респавн не блокує (REQ-0010-08). false == OFF
# (або ON без капсули — недосяжно після validate_region): викликач іде старим шляхом.
static func respawn(s, anchor: Dictionary = {}) -> bool:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return false
	s.player = s.respawn_source()   # шов: sim.respawn_source -> OrbitStub (стаб 0011); тест/0011 підміняють його
	if s.get("use_inventory") == true:
		s.player.inv = s._inv_empty()      # новачок прибуває з порожніми руками: торба й склад тримають решту
		s.player.hand = 0
	var key: String = String(anchor.get("region_key", WorldGen.canon_coord(float(s.map.lat), float(s.map.lon))))
	landing(s, key, anchor.get("pos", tile(s)))
	HeroHealth.reset(s)   # тіло без шрамів
	s.dead = false
	s._log(MSG_RESPAWN, "warn")
	return true

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
