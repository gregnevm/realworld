# RealWorld — sim/capsule.gd : the MAIN CAPSULE domain of the live sim (spec 0010).
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
# капсули (REQ-07/08/09/74/96), місце респавну — respawn_anchor, посадка — ЄДИНИЙ landing (REQ-98).
# W2a/W2b/W2c (ПЕРЕРОБКА під OD-73/76/98/99/103, нова редакція spec 0010): ДВІ незалежні осі прокачки — рівень капсули 0..5 (бафи; вкладення
# `invested`, які забирає рейд) і рівень захисту 0..5 (опір ядра; `protection_invested`) — в одній таблиці `capsule_levels` даних каталогу
# (ні одного числа в коді — REQ-11/91/99); `upgrade`/`upgrade_protection` (атомарно рюкзак → склад у зоні, REQ-13/76/100); зона контролю —
# ОДИН статичний радіус даних (OD-99: ~50 м), що не залежить від осей (REQ-16/80); бафи — РІВНО чотири осі OD-73 (збір, крафт, відновлення/
# комфорт потреб тепло+сон, дослідження), +10% на рівень, +50% на 5-му (OD-98): `in_zone`/`buff_at` + гачки sim.gather_time /
# sim._update_crafting / Session.research_rate / sleep+comfort recovery (кожен під прапором, OFF-код дослівно). Рейд (W3) — наступна
# хвиля; шви 0011 (Орбіта) — окремо, sim/orbit_stub.gd (D2), не тут.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const Clock = preload("res://scripts/clock.gd")   # лише to_wire/from_wire (int64 <-> рядок JSON); годинник сим не читає
const Inventory = preload("res://scripts/sim/inventory.gd")
const Catalog = preload("res://scripts/kernel/catalog.gd")
const OrbitStub = preload("res://scripts/sim/orbit_stub.gd")   # шви 0011 (REQ-0010-86: чи пропонувати «В сейв-зону»/«Підкріплення»)

const KIND := "main_capsule"
const RECORD_VERSION := 2   # версія ЗАПИСУ капсули в сейві (SAVE_VERSION не чіпаємо: OD-C14); 2 = дві осі (+protection, +protection_invested; REQ-0010-60); старша/невідома — явна помилка
const OWNER_LOCAL := "local"   # K1 — соло: власник один, локальний
const NO_CELL := Vector2i(-1, -1)   # «клітинки нема» (повна мапа) — єдиний sentinel модуля
# ЗАКРИТИЙ словник бафів рівня капсули — РІВНО чотири осі OD-73 (REQ-0010-105): швидкість збору/добутку, крафту/переробки, ВІДНОВЛЕННЯ/комфорту
# потреб (тепло, сон — REQ-0010-107: множить відновлення, не наростання й не голод) і дослідження. П'ята вісь (зокрема `melee_mult` першої хвилі)
# й баф голоду — лише рішенням власника. Значення — множники (1.0 нейтральний, як gather_mult у GameData.ITEMS); таблиця в каталозі має
# в КОЖНОМУ рядку рівно ці ключі (валідують обидва дзеркальні тести даних).
const BUFF_KEYS := ["gather_mult", "craft_mult", "need_recovery_mult", "research_mult"]
# Кеш СТОРІНКИ каталогу: capsule_levels читається з диска раз на процес (патерн catalog_defs). s.capsule_table (тести/пак контенту) має
# пріоритет і не кешується.
static var _catalog_table: Variant = null
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
	"panel": "capsule_bay",   # тап по капсулі відкриває цю панель (view-verb open_panel; id панелі — дані, не ім'я механіки в контролері)
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
# Рівень 0 = базова капсула без бафів; protection 0 = базовий захист ядра (REQ-0010-99: окреме поле, осі незалежні). Поля схеми додаються
# ПОСТУПОВО, щоб кожна хвиля мала власні хеш-докази (REQ-0010-35/82): W1b — tile/owner/landed_at/grace_start/level; invested — W2a;
# protection/protection_invested — W2c; W3a — immune_until (UTC-мс; 0 = нема), first_upgrade_at (UTC-мс; 0 = капсулу ще не прокачували, OD-107),
# reinforcement_used (0/1, OD-96), free_transport_token (0/1), next_raid_at (UTC-мс; 0 = не заплановано; пише планувальник W3b),
# raid_rng_cursor (курсор рейд-потоку, рядок int64). Стан АКТИВНОГО рейду (+core_hp) — runtime-половина `sim.capsule_raid`, не цей запис.
static func new_record(cell: Vector2i, now_ms: int = 0) -> Dictionary:
	return {"kind": "main", "tile": [cell.x, cell.y], "level": 0, "owner": OWNER_LOCAL, "landed_at": now_ms, "grace_start": now_ms, "invested": {},
		"protection": 0, "protection_invested": {},
		"immune_until": 0, "first_upgrade_at": 0, "reinforcement_used": 0, "free_transport_token": 0, "next_raid_at": 0, "raid_rng_cursor": "0"}

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
		"protection": int(c.get("protection", 0)),
		"immune_until": Clock.to_wire(int(c.get("immune_until", 0))), "first_upgrade_at": Clock.to_wire(int(c.get("first_upgrade_at", 0))),
		"reinforcement_used": int(c.get("reinforcement_used", 0)), "free_transport_token": int(c.get("free_transport_token", 0)),
		"next_raid_at": Clock.to_wire(int(c.get("next_raid_at", 0))), "raid_rng_cursor": String(c.get("raid_rng_cursor", "0")),
		"owner": String(c.get("owner", OWNER_LOCAL)), "landed_at": Clock.to_wire(int(c.get("landed_at", 0))),
		"grace_start": Clock.to_wire(int(c.get("grace_start", 0))), "invested": ledger(c.get("invested", {})),
		"protection_invested": ledger(c.get("protection_invested", {}))}

# Журнал вкладень У КОЖНІЙ осі (`invested` — рівень капсули, `protection_invested` — захист; REQ-0010-14/82/103) у канонічному вигляді:
# ключі — десяткові РЯДКИ рівнів у числовому порядку, усередині — id ресурсів за алфавітом, кількості — цілі. Рядки, бо JSON-ключ завжди
# рядок; world_hash сортує ключі лексикографічно, що збігається з числовим
# порядком лише до рівня 9 (таблиця на ≤10 рядків — перевіряють тести даних; ширший діапазон = bump RECORD_VERSION і падінг ключів).
# ДЕТЕРМІНІЗМ від довжини таблиці не залежить (порядок хеш-входу один і той самий в усіх інстансів); лише ЧИСЛОВІСТЬ порядку.
# `Persistence._canonical` НЕ чіпаємо: region.nodes — теж рядкові числові ключі str(cell), їхній лексикографічний порядок і є еталон
# OFF (WORLD_HASH_FINAL); числово-обізнаний _canonical міняє хеш OFF-регіону (перевірено на Київ N=56, 506 нод).
static func ledger(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	var levels_sorted: Array = (raw as Dictionary).keys()
	levels_sorted.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
	for lk in levels_sorted:
		var res_in: Variant = (raw as Dictionary)[lk]
		if not (res_in is Dictionary):
			continue
		var entry: Dictionary = {}
		var res_sorted: Array = (res_in as Dictionary).keys()
		res_sorted.sort()
		for res in res_sorted:
			entry[String(res)] = int((res_in as Dictionary)[res])
		out[str(int(String(lk)))] = entry
	return out

# Обернене до to_record + ставить БУДІВЛЮ капсули. {} (OFF-запис) лише скидає запис. Викликається ПЕРЕД циклом будівель
# load_region: капсула стає buildings[0], як у new_game (порядок обходу _nearest_storage збігається між живим і
# відновленим симом). Припускає validate_region(...) == &"". REQ-0010-88: ОБИДВІ осі кламляться до МАКСИМУМУ ПОТОЧНОЇ таблиці своєї осі
# (сейв рівня 5 + таблиця на 3 рівні -> 3; те саме для protection), `invested`/`protection_invested` лишаються як є (вкладене не зникає від
# правки каталогу), а бафи/HP ядра «перераховуються» самі — вони не зберігаються, це функції рівнів від таблиці (buffs, core_hp).
static func from_record(s, rec: Dictionary) -> void:
	if rec.is_empty():
		s.main_capsule = {}
		return
	var t: Array = rec.tile
	var cell := Vector2i(int(t[0]), int(t[1]))
	s.main_capsule = new_record(cell, Clock.from_wire(rec.get("landed_at"), 0))
	s.main_capsule.level = clampi(int(rec.get("level", 0)), 0, max_level(s))
	s.main_capsule.protection = clampi(int(rec.get("protection", 0)), 0, max_protection(s))
	s.main_capsule.owner = String(rec.get("owner", OWNER_LOCAL))
	s.main_capsule.grace_start = Clock.from_wire(rec.get("grace_start"), 0)
	s.main_capsule.invested = ledger(rec.get("invested", {}))
	s.main_capsule.protection_invested = ledger(rec.get("protection_invested", {}))
	# W3a: відсутнє поле = типове значення (запис W2c без рейдових полів лишається читабельним; версія запису не міняється, бо це та сама ревізія спеки)
	s.main_capsule.immune_until = Clock.from_wire(rec.get("immune_until"), 0)
	s.main_capsule.first_upgrade_at = Clock.from_wire(rec.get("first_upgrade_at"), 0)
	s.main_capsule.reinforcement_used = clampi(int(rec.get("reinforcement_used", 0)), 0, 1)
	s.main_capsule.free_transport_token = clampi(int(rec.get("free_transport_token", 0)), 0, 1)
	s.main_capsule.next_raid_at = Clock.from_wire(rec.get("next_raid_at"), 0)
	s.main_capsule.raid_rng_cursor = String(rec.get("raid_rng_cursor", "0"))
	s._place_building(KIND, cell.x, cell.y, -1)

# Найперший крок load_region — ДО будь-якої мутації світу: &"" == можна завантажувати, інакше явна причина
# (sim.load_error; Persistence.restore і Session.restore_game відхиляють ВЕСЬ відновлення, REQ-0010-60/83):
#   • прапор ≠ прапор уже запущеного sim              -> capsule_flag_mismatch (прапор незмінний після new_game);
#   • main_capsule без прапора                        -> capsule_orphan (прапор зник: мовчки «OFF» дав би світ без складу);
#   • нема ні прапора, ні запису                      -> &"" (звичайний OFF-запис / старий сейв, REQ-0010-61);
#   • прапор без запису або з порожнім записом        -> capsule_missing (REQ-0010-83: ON-сейв без капсули);
#   • версія запису != RECORD_VERSION                 -> capsule_version (новіша за цю збірку, зіпсована або ЗАПИС ПЕРШОЇ ХВИЛІ з однією
#                                                        віссю, v1: відхиляється явно, не мовчки — REQ-0010-60, Q-15 A);
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
		and _whole(c.get("protection")) and int(c.protection) >= 0 \
		and Clock.from_wire(c.get("landed_at"), -1) >= 0 and Clock.from_wire(c.get("grace_start"), -1) >= 0 \
		and _ledger_ok(c.get("invested", {})) and _ledger_ok(c.get("protection_invested", {})) and _raid_fields_ok(c)

# Рейдові поля W3a (REQ-0010-26/35/82/113): відсутнє — ок (типове), присутнє — мусить бути цілим UTC-мс >= 0 / 0..1 / рядком int64 курсора.
static func _raid_fields_ok(c: Dictionary) -> bool:
	for f in ["immune_until", "first_upgrade_at", "next_raid_at"]:
		if c.has(f) and Clock.from_wire(c.get(f), -1) < 0:
			return false
	for f in ["reinforcement_used", "free_transport_token"]:
		if c.has(f) and not (_whole(c.get(f)) and int(c.get(f)) >= 0 and int(c.get(f)) <= 1):
			return false
	if c.has("raid_rng_cursor"):
		var cur: Variant = c.get("raid_rng_cursor")
		if not (cur is String) or not (cur as String).is_valid_int():
			return false
	return true

# Журнал: {"<рівень>": {"<ресурс>": n}} — ключ-рівень десятковий рядок ≥ 1, n ціле ≥ 0. Відсутній ключ журналу == порожній журнал.
static func _ledger_ok(v: Variant) -> bool:
	if not (v is Dictionary):
		return false
	for lk in (v as Dictionary):
		var key: String = String(lk)
		if not key.is_valid_int() or int(key) < 1 or str(int(key)) != key or not ((v as Dictionary)[lk] is Dictionary):
			return false
		for res in ((v as Dictionary)[lk] as Dictionary):
			var n: Variant = ((v as Dictionary)[lk] as Dictionary)[res]
			if String(res) == "" or not _whole(n) or int(n) < 0:
				return false
	return true

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

# ---------------- levels table (REQ-0010-11 / 12 / 88 / 91 / 99 / 101 / 102 / 105 / 106) ----------------
# Таблиця `capsule_levels` у godot/content/catalog.json (status: "proposed" — числа ПРОПОНУЄ бот run_capsule_balance.gd, власник
# схвалює при мерджі; ПРИЙНЯТІ власником: +10%/рівень, +50% на 5-му (OD-98), ×2 на рівень і ×16 на 5-му (OD-65/103), ~50 м (OD-99)) з ДВОМА
# незалежними осями прокачки (OD-76, REQ-0010-17/99) і одним статичним радіусом зони (OD-74/99, REQ-0010-16):
#   levels[L]     = {level, cost, buffs}        — вісь РІВНЯ КАПСУЛИ 0..5: вартість переходу L-1 -> L і чотири бафи (BUFF_KEYS);
#   protection    = {factor, levels[P]}          — вісь ЗАХИСТУ 0..5: {level, cost, core_hp} (core_hp — максимум HP ядра, РОБОЧЕ тлумачення до Q-5);
#   zone          = {radius_m, cell_m, radius_cells} — ОДИН радіус соло (клітинки; метри лишаються поясненням, Q-4).
# Код не знає жодного числа: ні вартості, ні радіуса, ні максимумів (max_level/max_protection — розмір таблиць), тож розширення
# діапазону — лише дані (REQ-0010-91/99). Рядок рівня L = levels[L] (безперервність level == індекс перевіряють обидва дзеркальні тести).
static func table(s) -> Dictionary:
	var override: Variant = s.get("capsule_table")
	if override is Dictionary and not (override as Dictionary).is_empty():
		return override
	if _catalog_table == null:
		_catalog_table = Catalog.load_json().get("capsule_levels", {})
	return _catalog_table

static func levels(s) -> Array:
	return table(s).get("levels", [])

static func max_level(s) -> int:
	return maxi(0, levels(s).size() - 1)

# Вартість рядка у прикладному вигляді (JSON-float -> int): ключі за алфавітом — «перша причина відмови» upgrade береться з цього порядку.
static func _cost_of(src: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	var ids: Array = (src.get("cost", {}) as Dictionary).keys()
	ids.sort()
	for id in ids:
		cost[String(id)] = int((src.cost as Dictionary)[id])
	return cost

# Рядок рівня капсули: {level, cost, buffs}. {} — рівня поза таблицею нема. buffs — ефективні (на рівні 0 порожньо, REQ-0010-12).
static func row(s, level: int) -> Dictionary:
	var lv: Array = levels(s)
	if level < 0 or level >= lv.size():
		return {}
	return {"level": level, "cost": _cost_of(lv[level]), "buffs": buffs(s, level)}

# ---- вісь захисту (REQ-0010-99/100/102): власні записи даних, незалежні від рівня капсули ----
static func protection_table(s) -> Dictionary:
	return table(s).get("protection", {})

static func protection_levels(s) -> Array:
	return protection_table(s).get("levels", [])

static func max_protection(s) -> int:
	return maxi(0, protection_levels(s).size() - 1)

# Рядок захисту P: {level, cost, core_hp}. {} — поза таблицею.
static func protection_row(s, p: int) -> Dictionary:
	var pl: Array = protection_levels(s)
	if p < 0 or p >= pl.size():
		return {}
	return {"level": p, "cost": _cost_of(pl[p]), "core_hp": float((pl[p] as Dictionary).get("core_hp", 0.0))}

# Максимум HP ядра на рівні захисту P — РОБОЧЕ тлумачення до Q-5 (OD-107 задає лише «успіх рейду = HP ядра <= 0», OD-76 — лише вісь захисту,
# OD-103 — ×2 на рівень «по ресурсах»; що саме вісь задає в ядрі, рішеннями не визначено). Не зберігається в записі: це функція рівня захисту від
# таблиці (REQ-0010-88), поточний core_hp рейду — runtime-половина W3.
static func core_hp(s, p: int) -> float:
	var pl: Array = protection_levels(s)
	return float((pl[p] as Dictionary).get("core_hp", 0.0)) if p >= 0 and p < pl.size() else 0.0

# REQ-0010-102: «ресурсна складність пробиття ядра» на рівні захисту P — СТАБ робочого тлумачення Q-5: збігається з максимумом HP ядра
# (~×2 на рівень, ~×16 на 5-му відносно 1-го; коефіцієнт — `protection.factor` у даних). Поєднання з силою рейдера — Q-6 (W3).
static func breach_cost(s, p: int) -> float:
	return core_hp(s, p)

# Рівень захисту ПОТОЧНОЇ капсули (0 — без капсули) і максимум HP її ядра.
static func protection_of(s) -> int:
	return int((s.main_capsule as Dictionary).get("protection", 0))

static func core_hp_max(s) -> float:
	return core_hp(s, protection_of(s))

# ---- бафи рівня капсули (REQ-0010-12/105/106) ----
# Множники лише з BUFF_KEYS. Рівень 0 — порожньо ЗАВЖДИ, незалежно від даних (REQ-0010-12: базова капсула без бафів), хоч запис даних
# рівня 0 теж має чотири нейтральні (1.0) ключі (REQ-0010-105: у КОЖНОМУ записі рівно чотири осі).
static func buffs(s, level: int) -> Dictionary:
	var lv: Array = levels(s)
	var out: Dictionary = {}
	if level <= 0 or level >= lv.size():
		return out
	var src: Dictionary = (lv[level] as Dictionary).get("buffs", {})
	for key in BUFF_KEYS:
		if src.has(key):
			out[key] = float(src[key])
	return out

# Баф як ЧАСТКА приросту (0.10 == +10%, REQ-0010-106): 0.0 на рівні 0, поза таблицею й для чужого ключа.
static func buff_bonus(s, key: String, level: int) -> float:
	return float(buffs(s, level).get(key, 1.0)) - 1.0 if BUFF_KEYS.has(key) else 0.0

# ---------------- control zone + buffs (REQ-0010-12 / 15 / 16 / 80 / 105 / 106) ----------------
# ЗОНА КОНТРОЛЮ: клітинки на відстані <= zone_radius(s) від клітинки капсули, МЕЖА ВКЛЮЧНО. Радіус соло СТАТИЧНИЙ (OD-74/99, REQ-0010-16): одне
# число даних `zone.radius_cells`, що не залежить ні від рівня капсули, ні від рівня захисту (росте лише при об'єднанні капсул — К2,
# REQ-0010-52, frozen); падіння рівня зменшує лише баф, а не зону (REQ-0010-80). Метрика відстані — ДАНІ (`capsule_levels.metric`, одна на
# всю гру); код реалізує лише словник ZONE_METRICS (кандидат спеки — Чебишов на клітинкових координатах; інші метрики не вигадуємо), а
# тести даних тримають metric == "chebyshev". Відсутній ключ — той самий Чебишов (єдине значення, що його вимовляє спека); ІНША метрика —
# «зони нема» (ні бафів, ні дальності складу: безпечна відмова, нічого не ламає). Рівень 0 теж має зону (склад, REQ-0010-05/12), але бафів
# без рівня >= 1 нема.
const ZONE_METRICS := ["chebyshev"]

static func hero_cell(s) -> Vector2i:
	return Vector2i(int(floor(float(s.player.px))), int(floor(float(s.player.py))))

static func zone_metric(s) -> String:
	return String(table(s).get("metric", ZONE_METRICS[0]))

# Радіус зони соло в КЛІТИНКАХ — одне статичне значення даних (REQ-0010-16). «~50 м» (OD-99) переводить у клітинки одна функція від масштабу
# (метрів на клітинку, Q-4): число `radius_cells` у даних — її результат (⌈radius_m / cell_m⌉, перевіряють тести даних), доки власник не
# зафіксує масштаб. Таблиця без `zone` (тест/пак контенту) -> 0: зона = лише клітинка капсули, безпечна відмова.
static func zone_radius(s) -> int:
	return int((table(s).get("zone", {}) as Dictionary).get("radius_cells", 0))

# Сумісність викликів першої хвилі (`radius(s, level)`): ЗМІСТ ЗМІНЕНО — радіус більше не функція рівня (REQ-0010-16, OD-74/99), тож параметр
# ІГНОРУЄТЬСЯ й повертається той самий статичний радіус для будь-якого рівня капсули/захисту. Нових викликів із рівнем не писати: zone_radius(s).
static func radius(s, _level: int = 0) -> int:
	return zone_radius(s)

# Відстань за метрикою даних; -1 — метрику не реалізовано (in_zone тоді хибне для всіх клітинок).
static func zone_distance(s, dx: int, dy: int) -> int:
	if zone_metric(s) == "chebyshev":
		return maxi(absi(dx), absi(dy))
	return -1

static func in_zone(s, cell: Vector2i) -> bool:
	if (s.main_capsule as Dictionary).is_empty():
		return false
	var t := tile(s)
	var d: int = zone_distance(s, cell.x - t.x, cell.y - t.y)
	return d >= 0 and d <= zone_radius(s)

# БАФ у клітинці: множник із рядка ПОТОЧНОГО рівня капсули (1.0 нейтральний) — лише для ключів BUFF_KEYS і лише всередині зони. Поза зоною,
# на рівні 0, без капсули, для чужого ключа — рівно 1.0, тож споруда/герой за межею просто працюють без бафа й нічого не ламається
# (REQ-0010-80). Без стану: кожен виклик читає рівень і дані СЬОГОДНІ (бафи «на кожному кроці», без ретроактивності: таймери
# процесів лише накопичують, нічого не відкочується).
static func buff_at(s, key: String, cell: Vector2i) -> float:
	if not BUFF_KEYS.has(key) or not in_zone(s, cell):
		return 1.0
	return float(buffs(s, int(s.main_capsule.get("level", 0))).get(key, 1.0))

# Баф ГЕРОЯ (добування, відновлення потреб): клітинка героя — ціла частина його позиції, як у upgrade. `at` — ІНША клітинка (підказка вузла
# питає, скільки дало б добування з місця, де герой реально працюватиме, — gather_stand); NO_CELL == де він стоїть зараз.
static func hero_buff(s, key: String, at: Vector2i = NO_CELL) -> float:
	return buff_at(s, key, hero_cell(s) if at == NO_CELL else at)

# Множник ВІДНОВЛЕННЯ потреб героя (REQ-0010-107, OD-73/98): відігрів/комфорт тепла (Gear.update_comfort, `recover_scale`) і відновлення сну
# (sim._update_player) швидші на buff(рівень) лише коли герой у зоні. Це ЄДИНИЙ множник потреб: він НЕ чіпає наростання жодної потреби (темп
# голоду/сну/холоду, пороги, EXPOSURE_PACE) і взагалі не торкається голоду. 1.0 — нейтральний (OFF, без капсули, поза зоною, рівень 0).
static func recovery_mult(s) -> float:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return 1.0
	return hero_buff(s, "need_recovery_mult")

# ---------------- підказка вузла: одна правда про час добування (D9) ----------------
# «≈N с за одиницю» мусить називати те, що порахує сим, коли герой добуватиме. Баф gather_mult читається з клітинки, де герой СТОЇТЬ ПІД
# ЧАС роботи, а вона не збігається з клітинкою, де він стоїть, коли наводить курсор. Правило сима (sim._do_gather): герой іде шляхом до
# вузла й зупиняється, щойно відстань до центру вузла < GATHER_REACH, тож працює в клітинці з 3×3 навколо вузла. Звідси gather_stand:
#   • герой уже ближче за GATHER_REACH — працює де стоїть (клітинка героя);
#   • УСІ клітинки 3×3 (у межах мапи) мають однаковий вердикт зони — відповідь однозначна, хоч де він стане (повертаємо клітинку вузла).
#     Рахуємо й непрохідні: шлях 4-зв'язний і веде лише прохідними клітинками, але до вузла, обгородженого з усіх боків, його немає — order_gather
#     шляху не перевіряє, тож герой іде від кінця часткового шляху НАВПРОСТЕЦЬ крізь стіну й зупиняється на стіновій клітинці 3×3 (коло
#     досяжності 1.4 лежить усередині 3×3 завжди), вердикт якої може бути іншим, ніж у прохідних;
#   • 3×3 розрізає межу зони (вузол за 0..1 клітинку від межі) — клітинку визначає шлях: «сухий прогін» ходьби sim (compute_path + перетин
#     кола досяжності + крок навпростець від кінця шляху), без кроку dt: крок залежить від частоти кадрів, тож у цій вузькій смузі підказка
#     (вона з «≈») вгадує клітинку з точністю до одного кроку. Жодного нового числа: лише GATHER_REACH сима й розмір сусідства «вузол + 8 клітинок».
static func gather_stand(s, node_cell: int) -> Vector2i:
	var n: int = int(s.n)
	var node := Vector2i(node_cell % n, node_cell / n)
	var centre := Vector2(float(node.x) + 0.5, float(node.y) + 0.5)
	var pos := Vector2(float(s.player.px), float(s.player.py))
	var reach: float = float(s.GATHER_REACH)
	if pos.distance_to(centre) < reach:
		return hero_cell(s)
	var inside: int = 0
	var total: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := node + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:   # поза мапою герой не буває: пряма до центру вузла лишається всередині неї
				continue
			total += 1
			if in_zone(s, c):
				inside += 1
	if inside == 0 or inside == total:
		return node
	for c in s.compute_path(int(pos.x), int(pos.y), node.x, node.y):
		var to := Vector2(float(c.x) + 0.5, float(c.y) + 0.5)
		var t: float = _reach_entry(pos, to, centre, reach)
		if t >= 0.0:
			return _cell_at(pos.lerp(to, t))
		pos = to
	# шлях скінчився, а до вузла ще далі за досяжність (часткова/порожня траєкторія): сим ступає навпростець до центру вузла
	return _cell_at(pos.lerp(centre, maxf(_reach_entry(pos, centre, centre, reach), 0.0)))

# Параметр t∈[0,1] першої точки відрізка a→b, що лежить ближче за r до центру c (a — поза колом); -1 — відрізок кола не досягає.
static func _reach_entry(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d: Vector2 = b - a
	var f: Vector2 = a - c
	if d.is_zero_approx():
		return -1.0
	var qa: float = d.dot(d)
	var qb: float = 2.0 * f.dot(d)
	var disc: float = qb * qb - 4.0 * qa * (f.dot(f) - r * r)
	if disc < 0.0:
		return -1.0
	var t: float = (-qb - sqrt(disc)) / (2.0 * qa)
	return minf(t + 1.0e-4, 1.0) if t >= 0.0 and t <= 1.0 else -1.0   # +ε: сим зупиняється ЗА межею кола, а не на ній

static func _cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.y)))

# Підказка вузла (HudModel._inspect_node, лише при ON): ТА САМА sim.gather_time, що в _do_gather, але для клітинки, з якої герой працюватиме.
static func gather_preview(s, node_cell: int) -> float:
	return float(s.gather_time(s.map.nodes[node_cell], gather_stand(s, node_cell)))

# Споруда стоїть на клітинці (x, y) (верхній лівий тайл) — її клітинка і є точка перевірки зони.
static func _bench_cell(b: Dictionary) -> Vector2i:
	return Vector2i(int(b.x), int(b.y))

# ПРОЦЕСИ. Швидкість крафту верстаків: кожен верстак дає 1.0 × craft_mult СВОГО місця (поза зоною — 1.0), сума по верстаках
# множиться на dt у sim._update_crafting (OFF-гілка `dt * count` лишається дослівно). Рівень 0 → сума == кількість верстаків.
static func craft_rate(s) -> float:
	var rate: float = 0.0
	for b in s.buildings:
		if b.kind == "workbench":
			rate += buff_at(s, "craft_mult", _bench_cell(b))
	return rate

# Очки досліджень за ігрову добу від усіх дослідницьких столів: research_rate з def × research_mult місця столу (Session.research_rate).
static func research_rate(s) -> float:
	var rate: float = 0.0
	for b in s.buildings:
		var base: float = float((GameData.BUILDINGS.get(b.kind, {}) as Dictionary).get("research_rate", 0.0))
		if base > 0.0:
			rate += base * buff_at(s, "research_mult", _bench_cell(b))
	return rate

# ---------------- upgrade (REQ-0010-13 / 14 / 17 / 76 / 91 / 99 / 100) ----------------
# Прокачка осі на наступний рівень: `upgrade` — РІВЕНЬ КАПСУЛИ (бафи; вкладення `invested`, які забирає рейд), `upgrade_protection` — РІВЕНЬ
# ЗАХИСТУ (опір ядра; `protection_invested`). Осі НЕЗАЛЕЖНІ (REQ-0010-17/99, Q-5 A): прокачка однієї не змінює іншу й не вимагає її.
# Вартість береться СПЕРШУ з рюкзака, потім зі складу — лише поки герой у зоні (склад «капсули в її радіусі», REQ-0010-13/76/100);
# АТОМАРНО: спершу план по всіх ресурсах, жодного списання при будь-якій нестачі. Повертає value-data (текст — у роутері, R10; verbs
# capsule_upgrade/capsule_protect заведено в ui/input_verbs.gd (W4a), текст відмови — там же):
#   {ok:true, axis, level|protection, paid:{res:n}}                              — рівень піднято, журнал дописано
#   {ok:false, reason:&"no_capsule"|&"dead"|&"duplicate"|&"max"|&"cost", ...}    — світ не змінено
#   для &"cost": missing:{res:n} (ключі за алфавітом — ПЕРША причина = перший ключ), far:bool (герой поза зоною, а склад покрив би
#   хоч частину нестачі — підійди до капсули), level|protection, next.
# Ключ рівня в результаті — `level` для осі капсули й `protection` для осі захисту (axis = &"capsule" | &"protection").
# cmd_id >= 0 — ідентифікатор команди: повтор з тим самим id у ТОМУ САМОМУ тіку ідемпотентний (списання один раз; мітка
# sim.capsule_cmds_tick очищається на початку update і не входить у хеш; одна на обидві осі: id — одна команда); -1 — без дедуплікації.
# Журнал: ledger[str(L+1)] НАКОПИЧУЄТЬСЯ (add) при повторній прокачці після падіння — ПРОПОЗИЦІЯ агента (єдине правило, що зберігає
# REQ-0010-66 «sum(invested) = списане − забране»), схвалює власник при мерджі (Q-8).
static func upgrade(s, cmd_id: int = -1) -> Dictionary:
	return _upgrade_axis(s, &"capsule", cmd_id)

# REQ-0010-100: те саме для осі захисту; джерела, атомарність, дедуп і відмови — ті ж (одна реалізація, дві осі).
static func upgrade_protection(s, cmd_id: int = -1) -> Dictionary:
	return _upgrade_axis(s, &"protection", cmd_id)

# ЧИСТЕ читання (нічого не списує, не чіпає дедуп): що коштувала б наступна прокачка осі зараз — ОДНЕ джерело плану для upgrade/upgrade_protection
# і для панелі (W4a: рядок «бракує …» у слайсі HUD не дублює логіку джерел). {axis, level, max, next, cost, plan:{res:{pack,stock}}, missing:{res:n},
# far, can}; на `max` решта полів порожня. Склад береться лише коли герой у зоні (REQ-0010-13/76).
static func quote(s, axis: StringName) -> Dictionary:
	var prot: bool = axis == &"protection"
	var level: int = int((s.main_capsule as Dictionary).get("protection" if prot else "level", 0))
	var out: Dictionary = {"axis": axis, "level": level, "max": level >= (max_protection(s) if prot else max_level(s)), "next": level + 1,
		"cost": {}, "plan": {}, "missing": {}, "far": false, "can": false}
	if bool(out.max):
		return out
	var cost: Dictionary = (protection_row(s, level + 1) if prot else row(s, level + 1)).cost
	var in_reach: bool = in_zone(s, hero_cell(s))
	var plan: Dictionary = {}
	var missing: Dictionary = {}
	var far: bool = false
	for res in cost:
		var need: int = int(cost[res])
		var from_pack: int = mini(Inventory.count(s, String(res)), need)
		var in_stock: int = int(s.res_amount(String(res)))
		var from_stock: int = mini(in_stock, need - from_pack) if in_reach else 0
		if from_pack + from_stock < need:
			missing[res] = need - from_pack - from_stock
			far = far or (not in_reach and in_stock > 0)
		plan[res] = {"pack": from_pack, "stock": from_stock}
	out.cost = cost
	out.plan = plan
	out.missing = missing
	out.far = far
	out.can = missing.is_empty()
	return out

static func _upgrade_axis(s, axis: StringName, cmd_id: int) -> Dictionary:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return {"ok": false, "reason": &"no_capsule", "axis": axis}
	if s.dead:
		return {"ok": false, "reason": &"dead", "axis": axis}
	if cmd_id >= 0:
		var seen: Dictionary = s.capsule_cmds_tick
		if seen.has(cmd_id):
			return {"ok": false, "reason": &"duplicate", "axis": axis}
		seen[cmd_id] = true
	var prot: bool = axis == &"protection"
	var field: String = "protection" if prot else "level"            # ключ рівня і в записі капсули, і в результаті
	var book_key: String = "protection_invested" if prot else "invested"
	var q: Dictionary = quote(s, axis)
	var level: int = int(q.level)
	if bool(q.max):
		return {"ok": false, "reason": &"max", "axis": axis, field: level}
	var next: int = int(q.next)
	var cost: Dictionary = q.cost
	var plan: Dictionary = q.plan
	var missing: Dictionary = q.missing
	var far: bool = bool(q.far)
	if not missing.is_empty():
		return {"ok": false, "reason": &"cost", "axis": axis, "missing": missing, "far": far, field: level, "next": next}
	for res in plan:
		Inventory.take(s, String(res), int(plan[res].pack))
		if int(plan[res].stock) > 0:
			s._stock_take(String(res), int(plan[res].stock))
	if not cost.is_empty():
		var book: Dictionary = s.main_capsule.get(book_key, {})
		var entry: Dictionary = book.get(str(next), {})
		for res in cost:
			entry[res] = int(entry.get(res, 0)) + int(cost[res])
		book[str(next)] = entry
		s.main_capsule[book_key] = book
	s.main_capsule[field] = next
	if not prot and int(s.main_capsule.get("first_upgrade_at", 0)) <= 0:
		s.main_capsule["first_upgrade_at"] = maxi(1, int(s.now_ms))   # «є що втрачати» (OD-107): 0 == ніколи; годинник не подано (0) -> 1 мс, мітка завжди > 0
	return {"ok": true, "axis": axis, field: next, "paid": cost.duplicate()}

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

# ---------------- NPC-загрози й неруйнівна капсула (OD-107, critique-0010 #2, D8) ----------------
# Патруль націлюється на base_center() = капсулу, яку Threats.damage_building не шкодить (indestructible): боти стояли б і били без кінця —
# облога, що не може ні вдатися, ні скінчитись. Патрулі при ON ПРИДУШЕНІ (ІНТЕРИМ до вимірювання/рішення власника — питання власнику, не рішення
# дизайну), їхні кидки RNG лишаються (курсори потоків не зсуваються). Легасі-цикл рейду (Threats.update_raids/spawn_wave) при ON теж не армується:
# його замінює автомат нижче (W3a) — рейд на капсулу має початок (контакт), кінець (ядро пробито / рейдерів нема) і наслідок.
static func holds_npc_threats(s) -> bool:
	return s.get("use_main_capsule") == true

# ---------------- raid core (W3a: REQ-0010-17/21…26/34/62/65…67/69/81/82/84/104/113/119) ----------------
# РЕЙД = фізична облога (OD-58/107): рейдери (GameData.make_raider) з краю карти йдуть до капсули й б'ють перешкоди через Threats.damage_building;
# удар по неруйнівній капсулі потрапляє у on_hit й знижує HP ядра (runtime `capsule_raid.core_hp`). УСПІХ рейду — РІВНО HP ядра <= 0
# (core_breached, REQ-0010-21); об'єкт капсули не видаляється ніколи (REQ-0010-75). Максимум HP ядра = рядок осі ЗАХИСТУ (core_hp(P), ×2 на
# рівень — OD-103; зв'язок «захист -> HP ядра» — РОБОЧЕ тлумачення до Q-5). Наслідок успіху — ЧИСТА функція resolve_raid.
# Автомат (runtime, один активний — REQ-0010-62): planned -> warning -> contact -> розв'язано (none); чергу довжини raid.queue_max
# заповнюють рейди, що прийшли під час активного. УСІ часи — UTC-мс (REQ-0010-114): sim-секунди не беруть участі.
const STREAM_SALT := 0xCA5D1E   # окремий seeded-потік рейдів: seed = region_seed ^ сіль; курсор — main_capsule.raid_rng_cursor (REQ-0010-34/82)
const ST_NONE := "none"
const ST_PLANNED := "planned"       # заплановано: warn_at у майбутньому (або щойно армовано)
const ST_WARNING := "warning"       # попередження оголошено; рейдерів ще нема
const ST_CONTACT := "contact"       # рейдери на мапі, HP ядра тратиться
const RAID_STATES := [ST_NONE, ST_PLANNED, ST_WARNING, ST_CONTACT]
const EVENTS_KEEP := 24             # довжина журналу подій (view-пам'ять, не хеш)
const MSG_WARNING := "⚠ НАБЛИЖАЄТЬСЯ РЕЙД"
const MSG_BREACH := "💥 Ядро капсули пробито: рівень %d → %d. Частину вкладеного знищено."   # без роду (D8)
const MSG_BREACH_ZERO := "💥 Ядро капсули пробито — на базовому рівні втрачати нічого."
const MSG_DEFENDED := "✅ Рейд відбито!"

# ---- дані: блок `raid` таблиці (рішення власника — `decided`, пропозиції бота — `proposed`; код чисел не має, REQ-0010-11) ----
static func raid_data(s_or_tbl: Variant) -> Dictionary:
	var tbl: Dictionary = s_or_tbl if s_or_tbl is Dictionary else table(s_or_tbl)
	return tbl.get("raid", {})

# ---- чисті предикати й функції (без sim, без годинника) ----
# REQ-0010-21: ЄДИНИЙ предикат успіху рейду — HP ядра вичерпано.
static func core_breached(core_hp: float) -> bool:
	return core_hp <= 0.0

static func raid_succeeded(core_hp: float) -> bool:
	return core_breached(core_hp)

# Імунітет — чиста перевірка цілого UTC-мс (REQ-0010-26): діє, поки `now` менший за мітку.
static func immune_at(cap: Dictionary, now_ms: int) -> bool:
	return now_ms < int(cap.get("immune_until", 0))

static func is_immune(s) -> bool:
	return not (s.main_capsule as Dictionary).is_empty() and immune_at(s.main_capsule, int(s.now_ms))

static func immune_left_ms(s) -> int:
	return maxi(0, int(s.main_capsule.get("immune_until", 0)) - int(s.now_ms)) if not (s.main_capsule as Dictionary).is_empty() else 0

# REQ-0010-69: «соло» = актор не член команди/клану. У К1 команд нема (соцграф 0002 симульований), тож усі соло.
static func is_solo(_actor: String) -> bool:
	return true

# Скільки одиниць знищує рейд з `invested[L][res]` (OD-107: частка `take_percent`; правило округлення — дані, пропозиція Q-8).
static func take_of(amount: int, percent: int, mode: String) -> int:
	var x: float = float(amount) * float(percent) / 100.0
	match mode:
		"ceil":
			return int(ceil(x))
		"round":
			return int(round(x))
		_:
			return int(floor(x))

# ЧИСТА функція розв'язку рейду (REQ-0010-17/21…25/65/66/67/81/104/113): однакові входи -> однаковий вихід, жодного читання sim/годинника/RNG
# (потік випадковості приходить ЯК ВХІД: inp.roll ∈ [0,1)). Входи inp:
#   now_ms     — UTC-мс розв'язання (від нього імунітет);
#   core_hp    — поточне HP ядра (немає ключа -> повний максимум рівня ЗАХИСТУ з таблиці: опір ядра — функція protection, ×2 на рівень);
#   power      — сила рейдера в одиницях HP ядра, що вона знімає за облогу (0 = «шкоду вже нанесено фізично»: живий шлях викликає з 0);
#   structures — внесок споруд, частка сили, що вони гасять, [0,1];   autodefense — автооборона (OD-33), частка, [0,1];
#   roll       — потік випадковості [0,1), розкид шкоди ±raid.roll_spread (пропозиція бота).
# Формула поєднання (параметр балансу Q-6, у даних, `proposed`): шкода = power × (1−structures) × (1−autodefense) × (1 − spread + 2·spread·roll).
# Повертає {kind: &"immune"|&"noop_l0"|&"breach"|&"defended"|&"no_data", core_hp_max, core_hp_before, core_hp (після), damage, breached,
#   destroyed:{res:n}, destroyed_level, token_granted, immune_until, cap_after} — cap_after = копія cap зі змінами НАСЛІДКУ (рівень −1, invested[L]
# мінус знищене, імунітет, жетон, reinforcement_used=0); protection і protection_invested НЕ чіпаються (REQ-0010-104, стаб до Q-5).
static func resolve_raid(cap: Dictionary, inp: Dictionary, tbl: Dictionary) -> Dictionary:
	var rd: Dictionary = raid_data(tbl)
	var level: int = int(cap.get("level", 0))
	var prot: int = int(cap.get("protection", 0))
	var pl: Array = (tbl.get("protection", {}) as Dictionary).get("levels", [])
	var hp_max: float = float((pl[prot] as Dictionary).get("core_hp", 0.0)) if prot >= 0 and prot < pl.size() else 0.0
	var hp_before: float = float(inp.get("core_hp", hp_max))
	var out: Dictionary = {"kind": &"no_data", "core_hp_max": hp_max, "core_hp_before": hp_before, "core_hp": hp_before, "damage": 0.0, "breached": false,
		"destroyed": {}, "destroyed_level": 0, "token_granted": false, "immune_until": int(cap.get("immune_until", 0)), "cap_after": cap.duplicate(true)}
	if not rd.has("immunity_ms") or not rd.has("take_percent"):
		return out   # без рішень власника в даних наслідок не вигадуємо
	var now: int = int(inp.get("now_ms", 0))
	if immune_at(cap, now):
		out.kind = &"immune"   # REQ-0010-25: під імунітетом — без змін стану
		return out
	var spread: float = float(rd.get("roll_spread", 0.0))
	var mit_s: float = clampf(float(inp.get("structures", 0.0)), 0.0, 1.0)
	var mit_a: float = clampf(float(inp.get("autodefense", 0.0)), 0.0, 1.0)
	var roll: float = clampf(float(inp.get("roll", 0.5)), 0.0, 1.0)
	var damage: float = maxf(0.0, float(inp.get("power", 0.0))) * (1.0 - mit_s) * (1.0 - mit_a) * (1.0 - spread + 2.0 * spread * roll)
	out.damage = damage
	out.core_hp = hp_before - damage
	out.breached = core_breached(float(out.core_hp))
	if level <= 0:
		out.kind = &"noop_l0"   # REQ-0010-23/65: на базовому рівні рейд нічого не змінює (капсула не знищується, жетон не видається)
		return out
	if not bool(out.breached):
		out.kind = &"defended"
		return out
	out.kind = &"breach"
	var after: Dictionary = out.cap_after
	var inv: Dictionary = (after.get("invested", {}) as Dictionary)
	var book: Dictionary = (inv.get(str(level), {}) as Dictionary)
	var destroyed: Dictionary = {}
	for res in book:
		var cut: int = take_of(int(book[res]), int(rd.take_percent), String(rd.get("take_round", "floor")))
		cut = clampi(cut, 0, int(book[res]))
		destroyed[String(res)] = cut
		book[res] = int(book[res]) - cut   # забране + залишок == значення до рейду (REQ-0010-66)
	if inv.has(str(level)):
		inv[str(level)] = book
	after["invested"] = inv
	after["level"] = level - 1
	var granted: bool = level - 1 == 0 and int(after.get("free_transport_token", 0)) < 1   # REQ-0010-24/67: жетон лише за падіння до 0, ≤ 1
	if granted:
		after["free_transport_token"] = 1
	after["immune_until"] = now + int(rd.immunity_ms)   # REQ-0010-25: від МОМЕНТУ розв'язання
	after["reinforcement_used"] = 0                      # REQ-0010-113: починається нове вікно — виклик знову доступний
	out.destroyed = destroyed
	out.destroyed_level = level
	out.token_granted = granted
	out.immune_until = int(after.immune_until)
	return out

# ---- runtime-половина: sim.capsule_raid (core_hp тут, НЕ в регіональному записі; у runtime-хеші й resume) ----
# `reentry` — ТРАНЗИТНИЙ прапор (Session.restore_game / on_catch_up): у словнику є, але НЕ серіалізується й не хешується — «продовжений» світ хешується так само,
# як збережений (REQ-0010-02/35); прапор лише наказує першому тіку перепланувати рейд, що не дійшов до контакту.
static func idle_raid() -> Dictionary:
	return {"state": ST_NONE, "id": 0, "seq": 0, "warn_at": 0, "contact_at": 0, "warned_at": 0, "dir": 0, "count": 0, "day_equiv": 0,
		"faction": "", "core_hp": 0.0, "spawned": false, "queue": [], "reentry": false, "defer_due": false}

static func serialize_raid(s) -> Dictionary:
	var r: Dictionary = s.capsule_raid
	var q: Array = []
	for e in (r.get("queue", []) as Array):
		q.append({"faction": String((e as Dictionary).get("faction", "")), "points": float((e as Dictionary).get("points", 0.0))})
	return {"state": String(r.get("state", ST_NONE)), "id": int(r.get("id", 0)), "seq": int(r.get("seq", 0)),
		"warn_at": Clock.to_wire(int(r.get("warn_at", 0))), "contact_at": Clock.to_wire(int(r.get("contact_at", 0))),
		"warned_at": Clock.to_wire(int(r.get("warned_at", 0))), "dir": int(r.get("dir", 0)), "count": int(r.get("count", 0)),
		"day_equiv": int(r.get("day_equiv", 0)), "faction": String(r.get("faction", "")), "core_hp": float(r.get("core_hp", 0.0)),
		"spawned": bool(r.get("spawned", false)), "queue": q}

# Обернене до serialize_raid (Persistence.apply_runtime; лише ON). Невідомий стан -> none (безпечно: рейду нема, а не напівживий).
static func apply_raid(s, rec: Dictionary) -> void:
	var r: Dictionary = idle_raid()
	var st: String = String(rec.get("state", ST_NONE))
	r.state = st if RAID_STATES.has(st) else ST_NONE
	r.id = int(rec.get("id", 0))
	r.seq = int(rec.get("seq", 0))
	for f in ["warn_at", "contact_at", "warned_at"]:
		r[f] = Clock.from_wire(rec.get(f), 0)
	r.dir = clampi(int(rec.get("dir", 0)), 0, 3)
	r.count = int(rec.get("count", 0))
	r.day_equiv = int(rec.get("day_equiv", 0))
	r.faction = String(rec.get("faction", ""))
	r.core_hp = float(rec.get("core_hp", 0.0))
	r.spawned = bool(rec.get("spawned", false))
	for e in (rec.get("queue", []) as Array):
		(r.queue as Array).append({"faction": String((e as Dictionary).get("faction", "")), "points": float((e as Dictionary).get("points", 0.0))})
	s.capsule_raid = r

# Потік рейдів: seed від координат регіону (як потоки environment.gd), курсор — із запису капсули (переживає сейв). Викликає sim._env_init (ON).
static func init_raid(s) -> void:
	s.capsule_raid = idle_raid()
	s.capsule_events = []
	s.capsule_rng = RandomNumberGenerator.new()
	s.capsule_rng.seed = s.region_seed() ^ STREAM_SALT
	var cur: String = String(s.main_capsule.get("raid_rng_cursor", "0"))
	if cur != "0" and cur.is_valid_int():
		s.capsule_rng.state = cur.to_int()

# Курсор потоку -> запис капсули (входить у регіональний хеш і сейв, REQ-0010-82): викликається після КОЖНОГО блоку, що тягнув з capsule_rng.
static func _sync_cursor(s) -> void:
	s.main_capsule["raid_rng_cursor"] = str(s.capsule_rng.state)

static func _event(s, e: Dictionary) -> void:
	var ev: Array = s.capsule_events
	ev.append(e)
	while ev.size() > EVENTS_KEEP:
		ev.pop_front()

static func _active(s) -> bool:
	return String((s.capsule_raid as Dictionary).get("state", ST_NONE)) != ST_NONE

# ---- ворота планувальника (REQ-0010-65/111): усі умови РАЗОМ; жодна сама рейд не відкриває ----
# &"" — можна планувати; інакше причина: &"off" · &"no_data" · &"level0" (капсулу жодного разу не прокачано, OD-107) · &"grace" (3 доби від першої
# посадки, OD-66, UTC-мс) · &"immune" (REQ-0010-27) · &"queued" (є активний рейд, у черзі є місце) · &"active" (є активний, черга повна).
static func gate(s, _payload: Dictionary = {}) -> StringName:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return &"off"
	var rd: Dictionary = raid_data(s)
	if not rd.has("grace_ms") or not rd.has("queue_max"):
		return &"no_data"
	var cap: Dictionary = s.main_capsule
	if int(cap.get("first_upgrade_at", 0)) <= 0:
		return &"level0"
	if int(s.now_ms) - int(cap.get("grace_start", 0)) < int(rd.grace_ms):
		return &"grace"
	if immune_at(cap, int(s.now_ms)):
		return &"immune"
	if _active(s):
		return &"queued" if (s.capsule_raid.queue as Array).size() < int(rd.queue_max) else &"active"
	return &""

# Вхід від режисера (Director.apply при ON): `points` = Balance.assess(...).threat бази (REQ-0010-112; 0 -> без множника багатства).
# Повертає причину відмови чи &"" (заплановано). &"queued" кладе рейд у чергу. Відхилений рейд — DROPPED (жодного прихованого стану).
static func on_director_raid(s, payload: Dictionary, points: float = 0.0) -> StringName:
	var why: StringName = gate(s, payload)
	if why == &"":
		_plan(s, payload, points, maxi(0, int(s.now_ms)))
		return &""
	if why == &"queued":
		(s.capsule_raid.queue as Array).append({"faction": String(payload.get("faction", "невідомі мародери")), "points": points})
	_event(s, {"kind": &"dropped", "reason": why})
	return why

# Склад рейду (REQ-0010-87/112): рядок by_level для рівня капсули × множник багатства (assess.threat / wealth_ref_points, не нижче 1).
static func composition(s, points: float) -> Dictionary:
	var rd: Dictionary = raid_data(s)
	var by: Dictionary = rd.get("by_level", {})
	var level: int = int(s.main_capsule.get("level", 0))
	var row: Dictionary = {}
	for k in range(level, 0, -1):   # рівень поза таблицею -> найближчий нижчий рядок
		if by.has(str(k)):
			row = by[str(k)]
			break
	if row.is_empty():
		return {"count": 0, "day_equiv": 0}
	var ref: float = float(rd.get("wealth_ref_points", 0.0))
	var mult: float = maxf(1.0, points / ref) if ref > 0.0 and points > 0.0 else 1.0
	var count: int = clampi(int(round(float(row.count) * mult)), 1, int(rd.get("count_max", int(row.count))))
	return {"count": count, "day_equiv": int(row.day_equiv)}

# Інтервал попередження: рівномірно з [warn_min, warn_max] (OD-88; спосіб вибору — параметр рейд-потоку, REQ-0010-108, TBD) — ОДИН кидок потоку.
static func _warn_interval(s) -> int:
	var rd: Dictionary = raid_data(s)
	var lo: int = int(rd.get("warn_min_ms", 0))
	var hi: int = maxi(lo, int(rd.get("warn_max_ms", lo)))
	return lo + int(floor(float(s.capsule_rng.randf()) * float(hi - lo)))

static func _plan(s, payload: Dictionary, points: float, warn_at: int) -> void:
	var r: Dictionary = s.capsule_raid
	r.seq = int(r.seq) + 1
	r.id = int(r.seq)
	r.state = ST_PLANNED
	r.warn_at = warn_at
	r.contact_at = warn_at + _warn_interval(s)
	r.warned_at = 0
	r.dir = int(s.capsule_rng.randi() % 4)
	var comp: Dictionary = composition(s, points)
	r.count = int(comp.count)
	r.day_equiv = int(comp.day_equiv)
	r.faction = String(payload.get("faction", "невідомі мародери"))
	r.core_hp = 0.0
	r.spawned = false
	_sync_cursor(s)

# Повернення в «заплановано» з новим warn_at (REQ-0010-62/119): рейд не дійшов до контакту, бо власник був поза грою.
static func _reschedule(s, now: int) -> void:
	var r: Dictionary = s.capsule_raid
	r.state = ST_PLANNED
	r.warn_at = now
	r.contact_at = now + _warn_interval(s)
	r.warned_at = 0
	r.core_hp = 0.0
	r.spawned = false
	s.raid.warned = false
	s.raid.active = false
	if String(s.banner) == MSG_WARNING:
		s.banner = ""
	_sync_cursor(s)

# Вхід у гру після відсутності (REQ-0010-94/119; хук для catch-up spec 0012): годинник -> sim (монотонно), рейд, що ще не дійшов до контакту
# (planned/warning), повертається в planned з warn_at = now. КОНТАКТ лишається як є: sim у фоні не тікає, тож він «заморожений без втрат» (REQ-0010-63,
# стаб до Q-1). Жодних рейд-подій, жодних змін level/invested; `raid_events` — завжди 0.
static func on_catch_up(s, now_ms: int) -> Dictionary:
	s.set_clock(now_ms)
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return {"raid_events": 0, "rescheduled": false}
	s.capsule_raid["reentry"] = true
	s.capsule_raid["defer_due"] = true
	return {"raid_events": 0, "rescheduled": _reenter(s)}

# Session.restore_game: «Продовжити» = власник був поза грою. Годинник ще не подано (0) -> перепланування відкладається до першого тіка з now > 0.
static func mark_reentry(s) -> void:
	if s.get("use_main_capsule") == true and not (s.main_capsule as Dictionary).is_empty():
		s.capsule_raid["reentry"] = true
		s.capsule_raid["defer_due"] = true

static func _reenter(s) -> bool:
	var r: Dictionary = s.capsule_raid
	if not bool(r.get("reentry", false)) or int(s.now_ms) <= 0:
		return false
	r.reentry = false
	var st: String = String(r.state)
	if st == ST_PLANNED or st == ST_WARNING:
		_reschedule(s, int(s.now_ms))
		return true
	return false

# ---- тік автомата (sim.update, ПІСЛЯ турелей: команди гравця цього тіка вже застосовано — REQ-0010-84; один перехід за тік) ----
static func update(s, _dt: float) -> void:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return
	var r: Dictionary = s.capsule_raid
	if r.is_empty():
		return
	_reenter(s)
	var now: int = int(s.now_ms)
	match String(r.state):
		ST_PLANNED:
			if now >= int(r.warn_at):
				_announce(s, now)
		ST_WARNING:
			_hold_banner(s, MSG_WARNING)
			if now >= int(r.contact_at):
				_contact(s)
		ST_CONTACT:
			_contact_tick(s)

static func _hold_banner(s, text: String) -> void:
	if String(s.banner) == "":
		s.banner = text   # банер — view (не хеш): після «Продовжити» відновлюємо його з автомата

static func _announce(s, now: int) -> void:
	var r: Dictionary = s.capsule_raid
	var rd: Dictionary = raid_data(s)
	r.state = ST_WARNING
	r.warned_at = now
	r.warn_at = now   # ОДИН warn_at: запис == подія (REQ-0010-108/109), навіть після стрибка годинника
	r.contact_at = maxi(int(r.contact_at), now + int(rd.get("warn_min_ms", 0)))   # попередження ДО контакту не менш ніж warn_min (REQ-0010-19/108), навіть якщо годинник стрибнув
	s.raid.warned = true
	s.banner = MSG_WARNING
	s._log("⚠ Рейдери на підході (%s) — укріплюй базу!" % String(r.faction), "warn")
	_event(s, {"kind": &"warning", "event": &"raid_warning", "raid_id": int(r.id), "warn_at": now, "contact_at": int(r.contact_at), "dir": int(r.dir),
		"composition": {"count": int(r.count), "day_equiv": int(r.day_equiv)}})

static func _contact(s) -> void:
	var r: Dictionary = s.capsule_raid
	r.state = ST_CONTACT
	r.core_hp = core_hp_max(s)
	var edge: int = int(r.dir)
	var placed: int = 0
	var guard: int = 0
	while placed < int(r.count) and guard < 500:
		guard += 1
		var c: Vector2i = s._edge_cell(edge, s.capsule_rng)   # рейд-потік, НЕ threat_rng (REQ-0010-34)
		if WorldGen.is_terrain_blocked(s.map.tiles[c.y * int(s.n) + c.x]):
			continue
		s.enemies.append(GameData.make_raider(float(c.x) + 0.5, float(c.y) + 0.5, int(r.day_equiv)))
		placed += 1
	r.spawned = true
	s.raid.active = true
	s.raid.warned = true
	s.raid.wave = int(s.raid.wave) + 1
	s.banner = "⚔ РЕЙД! %d рейдерів — %s" % [placed, String(r.faction)]
	s._log("⚔ Рейд #%d: %d рейдерів (%s) атакують капсулу!" % [int(r.id), placed, String(r.faction)], "bad")
	_event(s, {"kind": &"contact", "raid_id": int(r.id), "count": placed})
	_sync_cursor(s)

static func _raiders_alive(s) -> bool:
	for e in s.enemies:
		if String((e as Dictionary).get("kind", "raider")) != "bot":
			return true
	return false

static func _contact_tick(s) -> void:
	var r: Dictionary = s.capsule_raid
	_hold_banner(s, "⚔ РЕЙД! %d рейдерів — %s" % [int(r.count), String(r.faction)])
	if core_breached(float(r.core_hp)) or (bool(r.spawned) and not _raiders_alive(s)):
		apply_raid_outcome(s)

# Удар по неруйнівній капсулі (Threats.damage_building): лише в стані contact — HP ядра -= amt. Поза рейдом (патруль, трап) — ігнор.
static func on_hit(s, amt: float) -> void:
	var r: Variant = s.get("capsule_raid")
	if r is Dictionary and String((r as Dictionary).get("state", ST_NONE)) == ST_CONTACT:
		(r as Dictionary).core_hp = float((r as Dictionary).core_hp) - amt

# Розв'язати активний рейд і застосувати наслідок (REQ-0010-21…25/66/104/113): resolve_raid (ЧИСТА) + запис у капсулу + лог + відхід рейдерів + скидання
# HP ядра й дзеркала s.raid. `inp` доповнює/перекриває входи (тести й сим-бот): now_ms/core_hp беруться з sim, power = 0 (шкоду нанесено фізично).
static func apply_raid_outcome(s, inp: Dictionary = {}) -> Dictionary:
	var r: Dictionary = s.capsule_raid
	var full: Dictionary = {"now_ms": int(s.now_ms), "core_hp": float(r.get("core_hp", 0.0)), "power": 0.0}
	for k in inp:
		full[k] = inp[k]
	var res: Dictionary = resolve_raid(s.main_capsule, full, table(s))
	var kind: StringName = res.kind
	if kind == &"no_data":
		return res
	if kind == &"breach":
		s.main_capsule = res.cap_after
		s._log(MSG_BREACH % [int(res.destroyed_level), int(res.destroyed_level) - 1], "bad")
	elif kind == &"noop_l0":
		s._log(MSG_BREACH_ZERO, "warn")
	elif kind == &"defended":
		s._log(MSG_DEFENDED, "good")
	if kind == &"immune" and String(r.state) == ST_NONE:
		return res   # REQ-0010-25/68: рейду нема, імунітет діє — ні капсула, ні автомат, ні хеш не змінюються
	_end_raid(s, res)   # (живий рейд, що застав імунітет, скасовується без наслідків: недосяжно з воріт, але автомат не зависає)
	return res

static func _end_raid(s, res: Dictionary) -> void:
	var r: Dictionary = s.capsule_raid
	var kept: Array = []
	for e in s.enemies:   # рейдери відходять (патрульні роботи — ні: вони не частина рейду)
		if String((e as Dictionary).get("kind", "raider")) == "bot":
			kept.append(e)
	s.enemies = kept
	s.raid.active = false
	s.raid.warned = false
	s.raid.timer = 0.0
	s.raid.next = s.RAID_IDLE
	s.banner = ""
	_event(s, {"kind": res.kind, "raid_id": int(r.id), "destroyed": res.destroyed, "token_granted": res.token_granted, "immune_until": res.immune_until})
	r.state = ST_NONE
	r.core_hp = 0.0
	r.spawned = false
	r.warned_at = 0
	var q: Array = r.queue
	if not q.is_empty():   # чергу розбирає той самий автомат: наступний рейд чекає кінця імунітету (REQ-0010-27)
		var nxt: Dictionary = q.pop_front()
		_plan(s, nxt, float(nxt.get("points", 0.0)), maxi(int(s.now_ms), int(s.main_capsule.get("immune_until", 0))))


# ---------------- каденс і режисерські ворота (W3b: REQ-0010-20/27/68/70/71/93/110/111/112/114/115) ----------------
# NPC/машинний рейд планує РЕЙД-ПОТІК капсули (REQ-0010-34/110), а не MTB-кидок Balance у sim-днях: момент рейду — `next_raid_at` (UTC-мс запису капсули),
# інтервал — рівномірно з [cadence_min_ms; cadence_max_ms] (OD-86: від 259 200 000 до 345 600 000 мс; РІВНОМІРНА форма розподілу — ПРОПОЗИЦІЯ бота,
# середнє 3.5 доби). Інтервал — ЛІЧИЛЬНИКОВА похідна потоку: seed = (region_seed ^ STREAM_SALT) + (k+1)·CADENCE_STRIDE, k = номер рейду (capsule_raid.seq);
# тож планувальник НЕ рухає курсор `raid_rng_cursor` між рейдами й нічого не пише в запис, доки рейд не заплановано (запис змінюється подією, а не тіком).
# Усе лише в `now` (REQ-0010-114/115): не залежить від debug-швидкості, use_realtime, day_len (одиниці часу Q-2 — варіант A спеки, стаб).
const CADENCE_STRIDE := 0x9E3779B1

static func cadence_interval(s, k: int) -> int:
	var rd: Dictionary = raid_data(s)
	var lo: int = int(rd.get("cadence_min_ms", 0))
	var hi: int = maxi(lo, int(rd.get("cadence_max_ms", lo)))
	var g := RandomNumberGenerator.new()
	g.seed = (s.region_seed() ^ STREAM_SALT) + (k + 1) * CADENCE_STRIDE
	return lo + int(floor(g.randf() * float(hi - lo)))

# Коли настає наступний рейд (UTC-мс): мітка `next_raid_at`, а поки її нема — «ворота відкрито + інтервал», де ворота відкрито = пізніше з (кінець грейсу,
# перша прокачка) (OD-66/107). -1 — каденсу нема: капсулу не прокачано чи даних каденсу нема.
static func due_at(s) -> int:
	var cap: Dictionary = s.main_capsule
	var nxt: int = int(cap.get("next_raid_at", 0))
	if nxt > 0:
		return nxt
	var rd: Dictionary = raid_data(s)
	var first: int = int(cap.get("first_upgrade_at", 0))
	if first <= 0 or not rd.has("cadence_min_ms"):
		return -1
	var opened: int = maxi(int(cap.get("grace_start", 0)) + int(rd.get("grace_ms", 0)), first)
	return opened + cadence_interval(s, int((s.capsule_raid as Dictionary).get("seq", 0)))

# Рейд, що «настав» поза грою (catch-up/«Продовжити», транзитний `defer_due`): у самому catch-up НЕ створюється й нічого не пише (REQ-0010-94); перший тік
# після входу відкладає його на повний інтервал від входу (OD-53: без атак на гравця; стаб до Q-1, REQ-0010-119) — жодного раптового рейду після повернення.
# Тік планувальника (Director.update, ON): true == рейд ПОРА кидати зараз — усі ворота відкриті (gate == &"": грейс, прокачка, не імунітет, нема активного) і
# час настав. Імунітет/активний рейд лише ВІДКЛАДАЮТЬ настання (REQ-0010-27). Годинник не подано (now_ms = 0) -> грейс не минув -> рейду нема ніколи.
static func cadence_tick(s) -> bool:
	if gate(s) != &"":
		return false
	var due: int = due_at(s)
	if bool(s.capsule_raid.get("defer_due", false)) and int(s.now_ms) > 0:
		s.capsule_raid["defer_due"] = false
		if due >= 0 and due <= int(s.now_ms):
			s.main_capsule["next_raid_at"] = int(s.now_ms) + cadence_interval(s, int(s.capsule_raid.get("seq", 0)))
			return false
	return due >= 0 and int(s.now_ms) >= due

# Запланувати рейд за каденсом: автомат + мітка НАСТУПНОГО рейду від моменту плану (інтервал між двома планами = вибраний інтервал, не залежить від тривалості бою).
static func plan_scheduled(s, payload: Dictionary, points: float) -> void:
	var now: int = maxi(0, int(s.now_ms))
	_plan(s, payload, points, now)
	s.main_capsule["next_raid_at"] = now + cadence_interval(s, int(s.capsule_raid.seq))

# Події рейду для споживача ПОЗА sim (push-сповіщення пристрою, REQ-0010-109: доставка — клієнт, sim лише емітить): забрати й очистити. Не хеш.
static func drain_events(s) -> Array:
	var out: Array = (s.capsule_events as Array).duplicate(true)
	(s.capsule_events as Array).clear()
	return out

# REQ-0010-120: dev-хук форсованого рейду для G5 — лише у debug-збірці (у релізній відмова; за зразком REQ-0012-40). Sim збірки не питає (REQ-0010-92):
# прапор `debug_build` дає КРАЙ пристрою (newhud_main: has_feature("debug") рушія, перемикач `-- capsule forceraid`). Обходить ворота (грейс/перша
# прокачка/імунітет), але НЕ попередження: контакт = now + warn_min_ms (найкоротше легальне, REQ-0010-19); прискорення — фейк-Clock.
# Каденс: next_raid_at НЕ перезаписується, але _plan збільшує capsule_raid.seq, а інтервал наступного рейду виводиться з seq (лічильникова похідна) — тож наступний
# due_at зсувається (інший k -> інший інтервал із тих самих [3;4] діб). Для dev-хука це прийнятно; межі каденсу (OD-86) зберігаються.
static func force_raid(s, debug_build: bool) -> Dictionary:
	if not debug_build:
		return {"ok": false, "reason": &"release_build"}
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return {"ok": false, "reason": &"no_capsule"}
	if _active(s):
		return {"ok": false, "reason": &"active"}
	var now: int = maxi(0, int(s.now_ms))
	_plan(s, {"faction": "тестові мародери"}, 0.0, now)
	s.capsule_raid.contact_at = now + int(raid_data(s).get("warn_min_ms", 0))
	return {"ok": true, "raid_id": int(s.capsule_raid.id), "contact_at": int(s.capsule_raid.contact_at)}

# ---------------- дії панелі за станами (REQ-0010-86; модель для HUD, W4a) ----------------
# «Прокачати» зникає на макс. рівні капсули, «Захист» — на макс. захисті; «Склад» — завжди; «В сейв-зону» — лише коли є сейв-сток (Орбіта; у К1 стаб — нема);
# «Підкріплення» — лише коли шов 0011 його пропонує (вікно П5 невідоме -> стаб не пропонує). Недоступних дій не показуємо.
const ACT_UPGRADE := &"upgrade"
const ACT_PROTECTION := &"protection"
const ACT_STORAGE := &"storage"
const ACT_SAFE_ZONE := &"safe_zone"
const ACT_REINFORCEMENT := &"reinforcement"

static func actions(s, safe_stock: Variant = null) -> Array[StringName]:
	var out: Array[StringName] = []
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return out
	if int(s.main_capsule.get("level", 0)) < max_level(s):
		out.append(ACT_UPGRADE)
	if protection_of(s) < max_protection(s):
		out.append(ACT_PROTECTION)
	out.append(ACT_STORAGE)
	if safe_stock != null:
		out.append(ACT_SAFE_ZONE)
	if OrbitStub.reinforcement_offered(s, safe_stock):
		out.append(ACT_REINFORCEMENT)
	return out
