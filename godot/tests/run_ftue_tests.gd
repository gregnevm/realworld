# RealWorld — tests/run_ftue_tests.gd : хронометр G4 (REQ-0010-42, REQ-0012-52) — тести ВІД ВИМОГ V1–V5, не від реалізації.
#   V1 два виміри (старт -> посадка без вердикту; посадка -> перша дія, ціль <= 30 с = ✓/✗);
#   V2 «осмислена дія» = добута одиниця або поставлена споруда рукою гравця; бездіяльність не рахується; ловиться рівно раз;
#   V3 спостереження, не правило: world_hash із вимірюванням і без — однаковий; файл окремий від сейву;
#   V4 журнал: останні 10, save -> load, зіпсований/чужий файл = порожньо без падіння, сміття не показується;
#   V5 рядки українською, найновіший перший, без вимірів — порожньо.
# Червоний тест тут = дефект продукту (очікування під код не підганяються).
# Run: godot --headless --path godot -s res://tests/run_ftue_tests.gd
extends "res://tests/harness.gd"

const FtueMeter = preload("res://scripts/ftue_meter.gd")
const SessionScript = preload("res://scripts/session.gd")
const Persistence = preload("res://scripts/persistence.gd")
const InvMod = preload("res://scripts/sim/inventory.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const InputCtl = preload("res://scripts/ui/input_controller.gd")
const InputVerbsMod = preload("res://scripts/ui/input_verbs.gd")
const WorldInputScript = preload("res://scripts/ui/world_input.gd")
const SettingsScript = preload("res://scripts/settings.gd")

const T0 := 1800000000000   # 2027-01-15 (UTC-мс) — фейковий годинник пристрою
const TMP := "user://ftue_test.json"
const SAVE_TMP := "user://ftue_save_test.json"
const LAT := 50.4501
const LON := 30.5234
const FRAME := 0.25         # с на кадр (= стеля dt кадру за реального часу)

const ALL := {"inv": true, "cat": true, "cap": true, "rt": true, "orbit": true}
const BUILD_DEFAULT_NO_ORBIT := {"inv": true, "cat": true, "cap": true, "rt": true, "orbit": false}
const NO_REALTIME := {"inv": true, "cat": true, "cap": true, "rt": false, "orbit": false}
const INV_ONLY := {"inv": true, "cat": false, "cap": false, "rt": false, "orbit": false}
const PLAIN := {"inv": false, "cat": false, "cap": false, "rt": false, "orbit": false}

# Ловить помилки скрипта, що стались УСЕРЕДИНІ модуля хронометра (headless їх лише друкує, а виклик «тихо» повертає дефолт):
# «без падіння» (V4) означає й «без SCRIPT ERROR».
class ErrTrap extends Logger:
	var count := 0
	var last := ""

	func _log_error(_function: String, file: String, line: int, code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT and file.ends_with("ftue_meter.gd"):
			count += 1
			last = "%s (рядок %d)" % [code, line]

var _now := T0
var _trap: ErrTrap = ErrTrap.new()


func _init() -> void:
	print("== RealWorld FTUE chronometer G4 tests (REQ-0010-42 / REQ-0012-52) ==")
	_cleanup()
	OS.add_logger(_trap)
	# V1
	_t_two_measurements()
	_t_target_boundary()
	_t_shown_number_agrees_with_verdict()
	_t_wait_has_no_verdict()
	# V2 — модуль
	_t_observe_guards()
	_t_once_only()
	_t_new_run_while_open()
	# V2 — справжній сим
	_t_idle_is_not_action("усе ON", ALL, 1200.0)
	_t_idle_is_not_action("збірка без Орбіти", BUILD_DEFAULT_NO_ORBIT, 600.0)
	_t_idle_is_not_action("без реального часу", NO_REALTIME, 600.0)
	_t_idle_is_not_action("лише інвентар", INV_ONLY, 600.0)
	_t_idle_is_not_action("усе OFF", PLAIN, 600.0)
	_t_catch_up_is_not_action()
	_t_restore_catch_up_is_not_action()
	_t_raid_is_not_action()
	_t_non_actions_do_not_count()
	_t_real_gather("усе ON", ALL)
	_t_real_gather("усе OFF", PLAIN)
	_t_real_build_hotbar("усе ON", ALL)
	_t_real_build_hotbar("лише інвентар", INV_ONLY)
	_t_real_build_stock()
	_t_build_after_loss()
	_t_build_after_travel()
	_t_gather_at_skill_cap()
	# V3
	_t_probe_is_read_only()
	_t_world_hash_twin()
	_t_file_is_separate()
	# V4
	_t_keep_last_ten()
	_t_save_load_roundtrip()
	_t_corrupt_files()
	_t_alien_field_types()
	_t_garbage_values_not_shown()
	# V5
	_t_lines_contract()
	_t_wiring()
	ok(_trap.count == 0, "V2–V5: за весь прогін модуль хронометра не дав жодної помилки скрипта (є %d)" % _trap.count)
	OS.remove_logger(_trap)
	_cleanup()
	_t_brief()
	finish()


# ---------------------------------------------------------------- helpers

func _cleanup() -> void:
	for p in [TMP, SAVE_TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _session(flags: Dictionary) -> Variant:
	var s: Variant = SessionScript.new()
	s.use_inventory = bool(flags.inv)
	s.use_catalog = bool(flags.cat)
	s.use_main_capsule = bool(flags.cap)
	s.use_realtime = bool(flags.rt)
	s.use_orbit = bool(flags.orbit)
	s.autosave = false
	_now = T0
	if not s.start(LAT, LON, "Київ", T0):
		return null
	return s


# Один кадр гри — той самий порядок, що в newhud_main._process (годинник пристрою -> догін/обрізаний dt -> сим -> дослідження -> цілі).
func _frame(s: Variant, dt: float = FRAME) -> void:
	_now += int(round(dt * 1000.0))
	var fdt: float = s.frame_dt(dt, _now)
	s.push_clock(_now)
	if fdt > 0.0 and not bool(s.sim.dead):
		s.sim.update(fdt)
		s.tick_research(fdt)
	s.tick_goals(dt)


func _router() -> Variant:
	var ic: Variant = InputCtl.InputController.new()
	InputVerbsMod.install(ic)
	return ic


# Тап по клітинці світу: та сама чиста граматика кліку, що у WorldInput._click, і диспетчеризація через роутер вербів.
func _tap(s: Variant, ic: Variant, selected_build: String, t: Vector2i) -> StringName:
	var d: Dictionary = WorldInputScript.WorldInput.decide_click(s.sim.enemies, s.sim.map.nodes, int(s.sim.n), selected_build, t, t.x + 0.5, t.y + 0.5)
	ic.dispatch(StringName(d.verb), d.args, s)
	return StringName(d.verb)


func _meter_for(s: Variant) -> RefCounted:
	var m: RefCounted = FtueMeter.new()
	m.begin("app", 4000, FtueMeter.probe(s.sim), "test", "2027-01-15 10:00")
	return m


func _nearest_node(sim: Variant) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd: float = INF
	var n: int = int(sim.n)
	for cell in sim.map.nodes:
		var c := Vector2i(int(cell) % n, int(cell) / n)
		var d: float = Vector2(c.x + 0.5 - float(sim.player.px), c.y + 0.5 - float(sim.player.py)).length()
		if d < bd:
			bd = d
			best = c
	return best


func _free_cell_near_hero(sim: Variant) -> Vector2i:
	var px: int = int(sim.player.px)
	var py: int = int(sim.player.py)
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if (dx != 0 or dy != 0) and sim.build_valid(px + dx, py + dy):
					return Vector2i(px + dx, py + dy)
	return Vector2i(-1, -1)


func _all_text(m: RefCounted) -> String:
	return "\n".join(m.lines(100))


# Число секунд першої дії так, як його ПРОЧИТАЄ людина в рядку (перед «✓»/«✗»); -1 — нема.
func _shown_action_secs(line: String) -> float:
	var re := RegEx.new()
	re.compile("([0-9]+(?:[.,][0-9]+)?)\\s*с\\s*(?:✓|✗)")
	var mt: RegExMatch = re.search(line)
	if mt == null:
		return -1.0
	return mt.get_string(1).replace(",", ".").to_float()


func _has_cyrillic(text: String) -> bool:
	for i in range(text.length()):
		var c: int = text.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false


func _looks_like_garbage(text: String) -> bool:
	var low: String = text.to_lower()
	var re := RegEx.new()
	re.compile("-\\s*[0-9]")
	if re.search(low) != null:
		return true
	for bad in ["nan", "inf", "null", "{", "}", "[", "]", "e+", "wait_ms", "action_ms"]:
		if low.contains(bad):
			return true
	return false


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ---------------------------------------------------------------- V1

# V1: два виміри в одному записі; origin "app" і "menu" читаються по-різному; до першої дії вердикту нема.
func _t_two_measurements() -> void:
	var m: RefCounted = FtueMeter.new()
	ok(not m.is_open() and m.lines(5).is_empty(), "V1: свіжий хронометр — вимір не йде, рядків нема")
	m.begin("app", 12000, {"gather": 0.0, "built": 1}, "abc1234", "2027-01-15 10:00")
	ok(m.is_open(), "V1: після посадки вимір «до першої дії» іде")
	var rows: PackedStringArray = m.lines(1)
	ok(rows.size() == 1, "V1: посадка одразу дає один рядок (вимір (а) зафіксовано)")
	var app_line: String = rows[0] if rows.size() == 1 else ""
	ok(app_line.contains("12"), "V1: рядок показує час до посадки (12 с)")
	ok(not app_line.contains("✓") and not app_line.contains("✗"), "V1: до першої дії вердикту ✓/✗ нема")
	var n: RefCounted = FtueMeter.new()
	n.begin("menu", 12000, {"gather": 0.0, "built": 1}, "abc1234", "2027-01-15 10:00")
	var menu_line: String = n.lines(1)[0]
	ok(app_line != menu_line, "V1: origin «app» і «menu» дають різний текст (читач знає, від чого відлік)")
	ok(m.observe(8000, {"gather": 0.0, "built": 2}), "V1: перша дія зловлена")
	var done: String = m.lines(1)[0]
	ok(done.contains("12") and done.contains("8"), "V1: один рядок несе обидва виміри (12 с до посадки, 8 с до дії)")
	ok(done.contains("✓") and not done.contains("✗"), "V1: дія за 8 с — ✓")


# V1: межа цілі (б) — рівно 30 с ще ✓, наступна мілісекунда вже ✗; 0 — ✓.
func _t_target_boundary() -> void:
	for pair in [[0, true], [29999, true], [30000, true], [30001, false], [31000, false], [600000, false]]:
		var m: RefCounted = FtueMeter.new()
		m.begin("app", 1000, {"gather": 0.0, "built": 1}, "", "")
		m.observe(int(pair[0]), {"gather": 0.2, "built": 1})
		var line: String = m.lines(1)[0]
		var want_ok: bool = bool(pair[1])
		ok(line.contains("✓") == want_ok and line.contains("✗") == (not want_ok), "V1: дія за %d мс -> %s" % [int(pair[0]), "✓" if want_ok else "✗"])


# V1 + D9/D5: число, яке ЧИТАЄ людина, не суперечить вердикту поруч («30 с ✗ (ціль ≤ 30 с)» — неправда на екрані).
func _t_shown_number_agrees_with_verdict() -> void:
	for a in [29949, 29960, 29999, 30000, 30001, 30400, 30499, 30500, 31000]:
		var m: RefCounted = FtueMeter.new()
		m.begin("app", 1000, {"gather": 0.0, "built": 1}, "", "")
		m.observe(int(a), {"gather": 0.2, "built": 1})
		var line: String = m.lines(1)[0]
		var shown: float = _shown_action_secs(line)
		var verdict_ok: bool = line.contains("✓")
		ok(shown >= 0.0 and (shown <= 30.0) == verdict_ok, "V1/D9: %d мс — показане число (%s с) узгоджене з вердиктом %s" % [int(a), str(shown), "✓" if verdict_ok else "✗"])


# V1: для (а) порогу нема (OD-31 TBD) — хоч 0 с, хоч 10 хв до посадки: лише число, без ✓/✗, поки дії не було.
func _t_wait_has_no_verdict() -> void:
	for w in [0, 500, 30001, 600000]:
		var m: RefCounted = FtueMeter.new()
		m.begin("menu", int(w), {"gather": 0.0, "built": 1}, "", "")
		var line: String = m.lines(1)[0]
		ok(not line.contains("✓") and not line.contains("✗"), "V1: посадка за %d мс — без вердикту" % int(w))
	# після дії вердикт рівно ОДИН (за (б)); довге очікування посадки його не псує
	var m2: RefCounted = FtueMeter.new()
	m2.begin("app", 600000, {"gather": 0.0, "built": 1}, "", "")
	m2.observe(5000, {"gather": 0.0, "built": 2})
	var line2: String = m2.lines(1)[0]
	ok(line2.count("✓") == 1 and line2.count("✗") == 0, "V1: 10 хв до посадки + дія за 5 с — рівно один ✓ (вердикт лише за другий вимір)")


# ---------------------------------------------------------------- V2 (модуль)

# V2: поза виміром нічого не ловиться; незмінний слід — не дія; зменшення сліду (споруду зруйновано, новий герой) — не дія.
func _t_observe_guards() -> void:
	var m: RefCounted = FtueMeter.new()
	ok(not m.observe(1000, {"gather": 5.0, "built": 9}), "V2: observe до посадки — нічого не ловить і не падає")
	ok(m.lines(5).is_empty(), "V2: observe до посадки не створює рядка")
	var base: Dictionary = {"gather": 1.0, "built": 3}
	m.begin("app", 1000, base, "", "")
	ok(not m.observe(1000, {"gather": 1.0, "built": 3}), "V2: слід не змінився — дії нема")
	ok(not m.observe(2000, {"gather": 0.0, "built": 2}), "V2: слід зменшився (руйнування/новий герой) — це не дія гравця")
	ok(not m.observe(2500, {}), "V2: порожній слід — не дія і не падіння")
	base["built"] = 0
	base["gather"] = 0.0
	# built: 2, а не 3 — після руйнування (3 -> 2 вище) повернення до 3 є новою спорудою гравця (дефект 4 цього ж сьюту, `_t_build_after_loss`)
	ok(not m.observe(3000, {"gather": 1.0, "built": 2}), "V2: база виміру — знімок на момент посадки (чужа правка словника її не зсуває)")
	ok(m.is_open(), "V2: вимір усе ще йде")
	ok(m.observe(4000, {"gather": 1.2, "built": 3}), "V2: +1 добута одиниця — дія")
	ok(not m.is_open(), "V2: після першої дії вимір закрито")


# V2: дія ловиться рівно раз; наступні дії (і того ж, і іншого виду) вимір не змінюють.
func _t_once_only() -> void:
	var m: RefCounted = FtueMeter.new()
	m.begin("app", 1000, {"gather": 0.0, "built": 1}, "", "")
	ok(m.observe(7000, {"gather": 0.2, "built": 1}), "V2: перша дія -> true")
	var frozen: String = _all_text(m)
	var again: bool = false
	for step in [[7100, 0.4, 1], [9000, 0.4, 2], [45000, 3.0, 7], [1, 9.0, 9]]:
		again = again or m.observe(int(step[0]), {"gather": float(step[1]), "built": int(step[2])})
	ok(not again, "V2: наступні дії більше не повертають true")
	ok(_all_text(m) == frozen, "V2: наступні дії (зокрема споруда після збору і пізня дія на 45 с) рядок не змінюють")
	ok(frozen.contains("✓"), "V2: вердикт лишився за ПЕРШОЮ дією (7 с — ✓)")


# V2/V4: наступний гравець («Нова гра»), коли попередній так нічого й не зробив — дія йде в НОВИЙ вимір, старий лишається «без дії».
func _t_new_run_while_open() -> void:
	var m: RefCounted = FtueMeter.new()
	m.begin("app", 1000, {"gather": 0.0, "built": 1}, "", "гравець-1")
	m.begin("menu", 2000, {"gather": 0.0, "built": 1}, "", "гравець-2")
	ok(m.observe(5000, {"gather": 0.0, "built": 2}), "V2: дія другого гравця зловлена")
	var rows: PackedStringArray = m.lines(5)
	ok(rows.size() == 2, "V4: обидва виміри в журналі")
	if rows.size() == 2:
		ok(rows[0].contains("✓") and rows[0].contains("гравець-2"), "V2: дія записана у вимір ДРУГОГО гравця (найновіший рядок)")
		ok(not rows[1].contains("✓") and not rows[1].contains("✗") and rows[1].contains("гравець-1"), "V2: вимір першого гравця лишився без дії й без вердикту")


# ---------------------------------------------------------------- V2 (справжній сим)

# V2: герой стоїть, сим тікає `seconds` реальних секунд — слід не змінюється, дія не зараховується.
func _t_idle_is_not_action(label: String, flags: Dictionary, seconds: float) -> void:
	var s: Variant = _session(flags)
	ok(s != null, "V2 простій [%s]: сесія стартує" % label)
	if s == null:
		return
	var m: RefCounted = _meter_for(s)
	var base: Dictionary = FtueMeter.probe(s.sim)
	var caught_at: float = -1.0
	var t: float = 0.0
	while t < seconds:
		_frame(s)
		t += FRAME
		if m.observe(int(t * 1000.0), FtueMeter.probe(s.sim)):
			caught_at = t
			break
	ok(caught_at < 0.0, "V2 простій [%s]: %d с без жодного вводу — дія НЕ зарахована%s" % [label, int(seconds), "" if caught_at < 0.0 else " (хибно зловлено на %.1f с: %s, база %s)" % [caught_at, str(FtueMeter.probe(s.sim)), str(base)]])
	ok(m.is_open(), "V2 простій [%s]: вимір досі відкритий" % label)
	var line: String = m.lines(1)[0]
	ok(not line.contains("✓") and not line.contains("✗"), "V2 простій [%s]: рядок без вердикту" % label)


# V2: догін реального часу в кадрі (застосунок був згорнутий 6 год) — світ змінився без гравця, дії нема.
func _t_catch_up_is_not_action() -> void:
	var s: Variant = _session(ALL)
	if s == null:
		ok(false, "V2 догін: сесія стартує")
		return
	var m: RefCounted = _meter_for(s)
	for i in range(8):
		_frame(s)
	_frame(s, 6.0 * 3600.0)   # розрив кадрів 6 год -> догін (REQ-0012-38)
	var hit: bool = m.observe(6 * 3600 * 1000, FtueMeter.probe(s.sim))
	for i in range(40):
		_frame(s)
		hit = hit or m.observe(6 * 3600 * 1000 + i * 250, FtueMeter.probe(s.sim))
	ok(not hit and m.is_open(), "V2 догін: 6 год у фоні — догін не зарахований як дія гравця")


# V2: save -> «Продовжити» через 6 год (догін при відновленні) — слід гравця той самий, що до сейву.
func _t_restore_catch_up_is_not_action() -> void:
	var s: Variant = _session(ALL)
	if s == null:
		ok(false, "V2 відновлення: сесія стартує")
		return
	var m: RefCounted = _meter_for(s)
	for i in range(8):
		_frame(s)
	ok(s.save_game(SAVE_TMP), "V2 відновлення: сейв записано")
	var r: Variant = SessionScript.new()
	r.autosave = false
	r.use_orbit = true
	var restored: bool = r.restore_game(SAVE_TMP, _now + 6 * 3600 * 1000)
	ok(restored, "V2 відновлення: сейв відновлюється")
	if restored:
		ok(not m.observe(6 * 3600 * 1000, FtueMeter.probe(r.sim)), "V2 відновлення: 6 год офлайну + догін — дії гравця нема")
	_cleanup()


# V2: рейд на капсулу (dev-хук forceraid) без участі гравця — не дія.
func _t_raid_is_not_action() -> void:
	var s: Variant = _session(BUILD_DEFAULT_NO_ORBIT)
	if s == null:
		ok(false, "V2 рейд: сесія стартує")
		return
	var m: RefCounted = _meter_for(s)
	var fr: Dictionary = MainCapsule.force_raid(s.sim, true)
	ok(bool(fr.get("ok", false)), "V2 рейд: рейд заплановано (передумова)")
	if not bool(fr.get("ok", false)):
		return
	var hit: bool = false
	var saw_enemy: bool = false
	var t_ms: int = 0
	var wave0: int = int(s.sim.raid.wave)
	while _now < int(fr.contact_at) - 8000 and not hit:
		_frame(s, 4.0)   # попередження проминаємо кроками < 5 с (не догін)
		t_ms += 4000
		hit = m.observe(t_ms, FtueMeter.probe(s.sim))
	for i in range(1040):   # контакт + 4 хв після нього, покадрово
		if hit:
			break
		_frame(s)
		t_ms += 250
		saw_enemy = saw_enemy or not (s.sim.enemies as Array).is_empty()
		hit = m.observe(t_ms, FtueMeter.probe(s.sim))
	ok(int(s.sim.raid.wave) > wave0, "V2 рейд: рейд дійшов до контакту (передумова)")
	print("    (рейд: вороги на мапі були = %s, герой живий = %s)" % [str(saw_enemy), str(not bool(s.sim.dead))])
	ok(not hit and m.is_open(), "V2 рейд: попередження + контакт рейду без вводу гравця — дія НЕ зарахована")


# V2: ввід, що світу не змінив (хід, відмовлена постановка, вибір слота, сортування, наказ зібрати до першої одиниці), — не дія.
func _t_non_actions_do_not_count() -> void:
	var s: Variant = _session(ALL)
	if s == null:
		ok(false, "V2 не-дії: сесія стартує")
		return
	var ic: Variant = _router()
	var m: RefCounted = _meter_for(s)
	var sim: Variant = s.sim
	var built0: int = (sim.buildings as Array).size()
	var cap: Vector2i = MainCapsule.tile(sim)
	ic.dispatch(&"build", {"kind": "campfire", "x": cap.x, "y": cap.y}, s)   # зайнята клітинка — відмова
	ic.dispatch(&"build", {"kind": "campfire", "x": -5, "y": -5}, s)         # поза мапою — відмова
	ic.dispatch(&"build", {"kind": "no_such_building", "x": cap.x + 2, "y": cap.y + 2}, s)
	ok((sim.buildings as Array).size() == built0, "V2 не-дії: відмовлені постановки нічого не поставили (передумова)")
	ok(not m.observe(1000, FtueMeter.probe(sim)), "V2 не-дії: відмовлена постановка — не дія")
	ic.dispatch(&"set_hand", {"i": 3}, s)
	ic.dispatch(&"inv_sort", {}, s)
	ic.dispatch(&"inv_move", {"a": 0, "b": 5}, s)
	ok(not m.observe(2000, FtueMeter.probe(sim)), "V2 не-дії: слот руки / сортування / перекладання рюкзака — не дія")
	var free: Vector2i = _free_cell_near_hero(sim)
	ic.dispatch(&"order_move", {"x": free.x, "y": free.y}, s)
	var hit: bool = false
	for i in range(40):
		_frame(s)
		hit = hit or m.observe(2000 + i * 250, FtueMeter.probe(sim))
	ok(not hit, "V2 не-дії: хід героя (10 с) — не дія")
	var node: Vector2i = _nearest_node(sim)
	if node.x >= 0:
		ic.dispatch(&"order_gather", {"x": node.x, "y": node.y}, s)
		ok(not m.observe(13000, FtueMeter.probe(sim)), "V2 не-дії: наказ зібрати (ще жодної одиниці) — не дія")
		ic.dispatch(&"cancel_action", {}, s)
		for i in range(8):
			_frame(s)
		ok(not m.observe(15000, FtueMeter.probe(sim)), "V2 не-дії: скасований наказ — не дія")
	ok(m.is_open(), "V2 не-дії: вимір досі відкритий")


# V2: справжній збір через верб order_gather (тап по вузлу) — дія ловиться тим самим кадром, коли добуто першу одиницю, і не раніше.
func _t_real_gather(label: String, flags: Dictionary) -> void:
	var s: Variant = _session(flags)
	if s == null:
		ok(false, "V2 збір [%s]: сесія стартує" % label)
		return
	var ic: Variant = _router()
	var sim: Variant = s.sim
	var m: RefCounted = _meter_for(s)
	var node: Vector2i = _nearest_node(sim)
	ok(node.x >= 0, "V2 збір [%s]: поруч є вузол ресурсу (передумова)" % label)
	if node.x < 0:
		return
	var cell: int = node.y * int(sim.n) + node.x
	var amount0: int = int(sim.map.nodes[cell].amount)
	var verb: StringName = _tap(s, ic, "", node)
	ok(verb == &"order_gather", "V2 збір [%s]: тап по вузлу = верб order_gather" % label)
	var early: bool = false
	var caught: bool = false
	var gathered: bool = false
	var t: float = 0.0
	while t < 900.0 and not gathered:
		_frame(s)
		t += FRAME
		gathered = not sim.map.nodes.has(cell) or int(sim.map.nodes[cell].amount) < amount0
		var hit: bool = m.observe(int(t * 1000.0), FtueMeter.probe(sim))
		if hit and not gathered:
			early = true
		caught = caught or hit
	print("    (збір [%s]: перша одиниця через %.1f с)" % [label, t])
	ok(gathered, "V2 збір [%s]: герой дійшов і добув одиницю (передумова)" % label)
	ok(not early, "V2 збір [%s]: поки герой лише йшов/працював, дія не зарахована" % label)
	ok(caught, "V2 збір [%s]: перша добута одиниця зловлена тим самим кадром" % label)
	ok(not m.is_open(), "V2 збір [%s]: вимір закрито" % label)
	var frozen: String = _all_text(m)
	var again: bool = false
	for i in range(240):   # герой збирає далі (ще хвилину)
		_frame(s)
		again = again or m.observe(int((t + i * FRAME) * 1000.0), FtueMeter.probe(sim))
	ok(not again and _all_text(m) == frozen, "V2 збір [%s]: подальший збір вимір не змінює" % label)
	ok(frozen.contains("✓") or frozen.contains("✗"), "V2 збір [%s]: рядок має вердикт" % label)


# V2: справжня постановка з хотбару — слот руки (верб set_hand) -> тап по вільній клітинці (верб build) -> дія зловлена.
func _t_real_build_hotbar(label: String, flags: Dictionary) -> void:
	var s: Variant = _session(flags)
	if s == null:
		ok(false, "V2 хотбар [%s]: сесія стартує" % label)
		return
	var ic: Variant = _router()
	var sim: Variant = s.sim
	var m: RefCounted = _meter_for(s)
	var slot: int = -1
	for i in range(8):
		if InvMod.is_building(String(sim.player.inv[i].id)):
			slot = i
			break
	ok(slot >= 0, "V2 хотбар [%s]: у стартовому хотбарі є споруда (передумова)" % label)
	if slot < 0:
		return
	ic.dispatch(&"set_hand", {"i": slot}, s)
	ok(not m.observe(1000, FtueMeter.probe(sim)), "V2 хотбар [%s]: узяти споруду в руку — ще не дія" % label)
	var kind: String = InvMod.building_kind(String(InvMod.held(sim).id))
	var cell: Vector2i = _free_cell_near_hero(sim)
	var built0: int = (sim.buildings as Array).size()
	var verb: StringName = _tap(s, ic, kind, cell)
	ok(verb == &"build" and (sim.buildings as Array).size() == built0 + 1, "V2 хотбар [%s]: тап ставить «%s» (передумова)" % [label, kind])
	ok(m.observe(3000, FtueMeter.probe(sim)), "V2 хотбар [%s]: поставлена споруда зловлена як перша дія" % label)
	var line: String = m.lines(1)[0]
	ok(line.contains("✓") and not m.is_open(), "V2 хотбар [%s]: 3 с — ✓, вимір закрито" % label)
	# далі гравець ще й збирає — вимір не змінюється
	var node: Vector2i = _nearest_node(sim)
	var again: bool = false
	if node.x >= 0:
		_tap(s, ic, "", node)
		for i in range(400):
			_frame(s)
			again = again or m.observe(3000 + i * 250, FtueMeter.probe(sim))
	ok(not again and m.lines(1)[0] == line, "V2 хотбар [%s]: збір після постановки вимір не змінює" % label)


# V2: постановка зі складу (без особистого інвентаря, опт-аут) — теж дія.
func _t_real_build_stock() -> void:
	var s: Variant = _session(PLAIN)
	if s == null:
		ok(false, "V2 склад: сесія стартує")
		return
	var ic: Variant = _router()
	var sim: Variant = s.sim
	var m: RefCounted = _meter_for(s)
	var cell: Vector2i = _free_cell_near_hero(sim)
	var built0: int = (sim.buildings as Array).size()
	_tap(s, ic, "campfire", cell)
	ok((sim.buildings as Array).size() == built0 + 1, "V2 склад: багаття поставлено зі складу (передумова)")
	ok(m.observe(2000, FtueMeter.probe(sim)), "V2 склад: поставлена споруда зловлена як перша дія")


# V2: до першої дії світ утратив споруду НЕ рукою гравця (вороги знесли склад) — постановка гравця після цього все одно дія.
func _t_build_after_loss() -> void:
	var s: Variant = _session(PLAIN)
	if s == null:
		ok(false, "V2 після втрати: сесія стартує")
		return
	var ic: Variant = _router()
	var sim: Variant = s.sim
	var m: RefCounted = _meter_for(s)
	var victim: Variant = null
	for b in sim.buildings:
		if not bool(sim.building_def(String(b.kind)).get("indestructible", false)):
			victim = b
			break
	ok(victim != null, "V2 після втрати: є споруда, яку можуть знести вороги (передумова)")
	if victim == null:
		return
	sim._damage_building(victim, 99999.0, false)
	ok(not m.observe(1000, FtueMeter.probe(sim)), "V2 після втрати: руйнування ворогами — не дія гравця")
	var cell: Vector2i = _free_cell_near_hero(sim)
	var before: int = (sim.buildings as Array).size()
	_tap(s, ic, "campfire", cell)
	ok((sim.buildings as Array).size() == before + 1, "V2 після втрати: гравець поставив багаття (передумова)")
	ok(m.observe(5000, FtueMeter.probe(sim)), "V2 після втрати: постановка гравця після чужого руйнування зловлена як дія")


# V2: (опт-аут без капсули) гравець спершу летить щоденною капсулою в нову місцевість, там ставить першу споруду — це дія.
func _t_build_after_travel() -> void:
	var s: Variant = _session(INV_ONLY)
	if s == null:
		ok(false, "V2 після перельоту: сесія стартує")
		return
	var ic: Variant = _router()
	var m: RefCounted = _meter_for(s)
	s.travel_to(LAT + 0.5, LON + 0.5, "Сусіди")
	var sim: Variant = s.sim
	var hit: bool = m.observe(4000, FtueMeter.probe(sim))
	ok(not hit, "V2 після перельоту: сам переліт не зарахований як «збір/споруда»")
	if hit:
		return
	var slot: int = -1
	for i in range(8):
		if InvMod.is_building(String(sim.player.inv[i].id)):
			slot = i
			break
	ok(slot >= 0, "V2 після перельоту: споруда в хотбарі долетіла з героєм (передумова)")
	if slot < 0:
		return
	ic.dispatch(&"set_hand", {"i": slot}, s)
	var kind: String = InvMod.building_kind(String(InvMod.held(sim).id))
	var cell: Vector2i = _free_cell_near_hero(sim)
	var before: int = (sim.buildings as Array).size()
	_tap(s, ic, kind, cell)
	ok((sim.buildings as Array).size() == before + 1, "V2 після перельоту: споруду поставлено (передумова)")
	ok(m.observe(9000, FtueMeter.probe(sim)), "V2 після перельоту: перша споруда в новій місцевості зловлена як дія")


# V2 (межа): герой із максимальною навичкою збору (ветеран-клон) добуває одиницю — це така сама дія.
func _t_gather_at_skill_cap() -> void:
	var s: Variant = _session(ALL)
	if s == null:
		ok(false, "V2 стеля навички: сесія стартує")
		return
	var ic: Variant = _router()
	var sim: Variant = s.sim
	sim.player.skills.gather = 20.0
	var m: RefCounted = _meter_for(s)
	var node: Vector2i = _nearest_node(sim)
	if node.x < 0:
		ok(false, "V2 стеля навички: поруч є вузол (передумова)")
		return
	var cell: int = node.y * int(sim.n) + node.x
	var amount0: int = int(sim.map.nodes[cell].amount)
	_tap(s, ic, "", node)
	var gathered: bool = false
	var caught: bool = false
	var t: float = 0.0
	while t < 900.0 and not gathered:
		_frame(s)
		t += FRAME
		gathered = not sim.map.nodes.has(cell) or int(sim.map.nodes[cell].amount) < amount0
		caught = caught or m.observe(int(t * 1000.0), FtueMeter.probe(sim))
	ok(gathered, "V2 стеля навички: одиницю добуто (передумова)")
	ok(caught, "V2 стеля навички: добута одиниця героєм із навичкою 20 зловлена як дія")


# ---------------------------------------------------------------- V3

# V3: probe лише читає — world_hash до і після однаковий, у герої/світі не з'являється нових ключів.
func _t_probe_is_read_only() -> void:
	ok(FtueMeter.probe(null) is Dictionary, "V3: probe(null) не падає (сесії ще нема)")
	for flags in [ALL, PLAIN]:
		var s: Variant = _session(flags)
		if s == null:
			ok(false, "V3 probe: сесія стартує")
			continue
		var h0: String = Persistence.world_hash(s.sim)
		var keys0: Array = (s.sim.player as Dictionary).keys()
		var a: Dictionary = {}
		for i in range(50):
			a = FtueMeter.probe(s.sim)
		a["gather"] = 99.0
		a["built"] = 99
		ok(Persistence.world_hash(s.sim) == h0, "V3: 50 викликів probe (+ правка результату) не міняють world_hash")
		ok((s.sim.player as Dictionary).keys() == keys0, "V3: probe не додає ключів герою")
		ok(FtueMeter.probe(s.sim) == FtueMeter.probe(s.sim), "V3: probe детермінований (той самий стан -> той самий слід)")


# Однаковий сценарій гравця: трохи простою, збір, постановка, ще простій. `m` == null — без хронометра.
func _scenario(flags: Dictionary, m: Variant) -> Variant:
	var s: Variant = _session(flags)
	if s == null:
		return null
	var ic: Variant = _router()
	var sim: Variant = s.sim
	if m != null:
		m.begin("app", 4000, FtueMeter.probe(sim), "test", "2027-01-15 10:00")
		m.save(TMP)
	var steps: int = 0
	for phase in range(3):
		if phase == 1:
			var node: Vector2i = _nearest_node(sim)
			if node.x >= 0:
				_tap(s, ic, "", node)
		elif phase == 2:
			var cell: Vector2i = _free_cell_near_hero(sim)
			if bool(flags.inv):
				ic.dispatch(&"set_hand", {"i": 0}, s)
				_tap(s, ic, InvMod.building_kind(String(InvMod.held(sim).id)), cell)
			else:
				_tap(s, ic, "campfire", cell)
		for i in range(240):
			_frame(s)
			steps += 1
			if m != null:
				FtueMeter.probe(sim)
				if m.is_open() and m.observe(steps * 250, FtueMeter.probe(sim)):
					m.save(TMP)
				m.lines(5)
	return s


# V3 (D13): та сама сесія з хронометром і без — той самий world_hash; і з хронометром дія справді зловлена (тест не порожній).
func _t_world_hash_twin() -> void:
	for pair in [["усе ON", ALL], ["усе OFF", PLAIN]]:
		var m: RefCounted = FtueMeter.new()
		var with_meter: Variant = _scenario(pair[1], m)
		var without: Variant = _scenario(pair[1], null)
		var again: Variant = _scenario(pair[1], null)
		if with_meter == null or without == null or again == null:
			ok(false, "V3 twin [%s]: сесії стартують" % String(pair[0]))
			continue
		var h_with: String = Persistence.world_hash(with_meter.sim)
		var h_without: String = Persistence.world_hash(without.sim)
		ok(h_without == Persistence.world_hash(again.sim), "V3 twin [%s]: сценарій сам детермінований (передумова)" % String(pair[0]))
		ok(h_with == h_without, "V3 twin [%s]: world_hash із вимірюванням == без нього" % String(pair[0]))
		ok(not m.is_open(), "V3 twin [%s]: у сесії з хронометром дію зловлено (вимір справді працював)" % String(pair[0]))
	_cleanup()


# V3: файл хронометра — окремий від сейву й налаштувань; сейв сесії нічого про хронометр не містить.
func _t_file_is_separate() -> void:
	ok(String(FtueMeter.PATH) == "user://ftue.json", "V3: файл хронометра — user://ftue.json")
	ok(String(FtueMeter.PATH) != String(SessionScript.SAVE_PATH) and String(FtueMeter.PATH) != String(SessionScript.STORE_PATH) and String(FtueMeter.PATH) != String(SettingsScript.PATH), "V3: це не сейв, не склад регіонів і не налаштування")
	var s: Variant = _session(ALL)
	if s == null:
		ok(false, "V3 файл: сесія стартує")
		return
	var m: RefCounted = _meter_for(s)
	var cell: Vector2i = _free_cell_near_hero(s.sim)
	s.sim.try_build("campfire", cell.x, cell.y)
	ok(m.observe(2000, FtueMeter.probe(s.sim)), "V3 файл: дію зловлено (передумова)")
	ok(m.save(TMP), "V3 файл: журнал записано у свій файл")
	ok(s.save_game(SAVE_TMP), "V3 файл: сейв записано")
	var save_text: String = FileAccess.get_file_as_string(SAVE_TMP).to_lower()
	ok(not save_text.contains("ftue") and not save_text.contains("action_ms") and not save_text.contains("wait_ms"), "V3: у сейві світу нема даних хронометра")
	var r: Variant = SessionScript.new()
	r.autosave = false
	r.use_orbit = true
	ok(r.restore_game(SAVE_TMP, _now), "V3 файл: сейв, записаний під час виміру, відновлюється")
	_cleanup()


# ---------------------------------------------------------------- V4

# V4: журнал тримає останні 10; найстаріші витісняються; найновіший перший.
func _t_keep_last_ten() -> void:
	var m: RefCounted = FtueMeter.new()
	for i in range(1, 14):   # 13 гравців поспіль; мітки p01..p13
		m.begin("app" if i == 1 else "menu", 1000, {"gather": 0.0, "built": 1}, "", "p%02d" % i)
		if i % 2 == 0:
			m.observe(i * 1000, {"gather": 0.0, "built": 2})
	var rows: PackedStringArray = m.lines(100)
	ok(rows.size() == 10, "V4: після 13 вимірів у журналі рівно 10 (є %d)" % rows.size())
	if rows.size() == 10:
		ok(rows[0].contains("p13") and rows[9].contains("p04"), "V4: лишились останні 10 (p04..p13), найновіший перший")
		var all: String = "\n".join(rows)
		ok(not all.contains("p01") and not all.contains("p02") and not all.contains("p03"), "V4: три найстаріші витіснено")
		ok(rows[1].contains("p12") and (rows[1].contains("✓") or rows[1].contains("✗")) and not rows[0].contains("✓"), "V4: дії лишились при своїх вимірах після витіснення")
	ok(m.is_open(), "V4: останній вимір (p13) ще відкритий")
	ok(m.observe(2000, {"gather": 0.4, "built": 1}) and m.lines(2)[0].contains("p13") and m.lines(2)[0].contains("✓"), "V4: дія після витіснення лягає в найновіший вимір")
	ok(m.save(TMP), "V4: журнал із 10 записів зберігається")
	var back: RefCounted = FtueMeter.new()
	back.load_file(TMP)
	ok(back.lines(100).size() == 10, "V4: після load усе ще 10")
	back.begin("menu", 500, {"gather": 0.0, "built": 1}, "", "p14")
	var rows2: PackedStringArray = back.lines(100)
	ok(rows2.size() == 10 and rows2[0].contains("p14") and not "\n".join(rows2).contains("p04"), "V4: новий вимір після load витісняє найстаріший")
	_cleanup()


# V4: save -> load: ті самі рядки тим самим порядком; дробові секунди, обидва origin, обидва види дії, запис без дії.
func _t_save_load_roundtrip() -> void:
	var m: RefCounted = FtueMeter.new()
	m.begin("app", 3456, {"gather": 0.0, "built": 1}, "sha1", "2027-01-15 10:00")
	m.observe(1234, {"gather": 0.2, "built": 1})
	m.begin("menu", 15000, {"gather": 0.0, "built": 1}, "sha1", "2027-01-15 10:05")
	m.observe(45000, {"gather": 0.0, "built": 2})
	m.begin("menu", 0, {"gather": 0.0, "built": 1}, "sha1", "2027-01-15 10:09")
	var before: PackedStringArray = m.lines(100)
	ok(m.save(TMP), "V4 round-trip: save пише файл")
	var back: RefCounted = FtueMeter.new()
	ok(back.load_file(TMP), "V4 round-trip: load читає записане")
	ok(back.lines(100) == before, "V4 round-trip: рядки після load ідентичні (порядок, числа, вердикти)")
	ok(back.lines(1) == m.lines(1), "V4 round-trip: і короткий рядок для ☰ ідентичний")
	var again: RefCounted = FtueMeter.new()
	back.save(TMP)
	again.load_file(TMP)
	ok(again.lines(100) == before, "V4 round-trip: другий цикл save -> load стабільний")
	ok(JSON.stringify(again.to_dict()) == JSON.stringify(back.to_dict()), "V4 round-trip: to_dict після циклу — канонічний (без дрейфу типів)")
	# вимір, що йшов під час виходу із застосунку, після перезапуску НЕ продовжується чужою сесією
	ok(not back.is_open(), "V4 round-trip: після load жоден вимір не «йде»")
	ok(not back.observe(999, {"gather": 5.0, "built": 9}) and back.lines(100) == before, "V4 round-trip: observe після load нічого не дописує у старі записи")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	ok(not back.load_file(TMP) and back.lines(100).is_empty(), "V4: файла нема -> порожній журнал")
	_cleanup()


# V4: зіпсований / чужий / старої чи майбутньої версії файл = порожній журнал, без падіння; хронометр після цього робочий.
func _t_corrupt_files() -> void:
	var good: RefCounted = FtueMeter.new()
	good.begin("app", 1000, {"gather": 0.0, "built": 1}, "", "")
	var cases: Array = [
		["обірваний JSON", "{ це не json"],
		["порожній файл", ""],
		["масив замість об'єкта", "[1, 2, 3]"],
		["число", "42"],
		["null", "null"],
		["рядок", "\"ftue\""],
		["без версії", "{\"runs\": [{\"wait_ms\": 1000, \"action_ms\": 5000}]}"],
		["версія 0 (стара)", "{\"version\": 0, \"runs\": [{\"wait_ms\": 1000, \"action_ms\": 5000}]}"],
		["версія 99 (майбутня)", "{\"version\": 99, \"runs\": [{\"wait_ms\": 1000, \"action_ms\": 5000}]}"],
		["версія null", "{\"version\": null, \"runs\": [{\"wait_ms\": 1000, \"action_ms\": 5000}]}"],
		["версія-список", "{\"version\": [1], \"runs\": [{\"wait_ms\": 1000, \"action_ms\": 5000}]}"],
		["runs — не масив", "{\"version\": 1, \"runs\": {\"wait_ms\": 1000}}"],
		["runs відсутній", "{\"version\": 1}"],
		["чужий файл (налаштування)", "{\"version\": 1, \"values\": {\"show_fps\": true}}"],
		["чужий файл (сейв)", "{\"version\": 3, \"store\": {}, \"region\": {\"buildings\": []}}"],
	]
	for c in cases:
		_write(TMP, String(c[1]))
		var m: RefCounted = FtueMeter.new()
		m.from_dict(good.to_dict())   # у пам'яті вже щось було — файл має це стерти, а не змішати
		var e0: int = _trap.count
		var res: Variant = m.load_file(TMP)
		ok(_trap.count == e0, "V4 зіпсований файл [%s]: без помилки скрипта%s" % [String(c[0]), "" if _trap.count == e0 else " -> " + _trap.last])
		ok(res is bool and not bool(res), "V4 зіпсований файл [%s]: load повертає false" % String(c[0]))
		ok(m.lines(100).is_empty() and not m.is_open(), "V4 зіпсований файл [%s]: порожній журнал" % String(c[0]))
		m.begin("menu", 2000, {"gather": 0.0, "built": 1}, "", "")
		ok(m.lines(100).size() == 1 and m.observe(3000, {"gather": 0.0, "built": 2}), "V4 зіпсований файл [%s]: хронометр далі працює" % String(c[0]))
	_cleanup()


# V4: поле не того типу в ОДНОМУ записі (файл правили руками / інша збірка) не валить розбір і не лишає журнал «напіврозібраним»:
# або запис пропущено (2 рядки з 3), або відкинуто весь файл (0) — але не «скільки встигли до помилки».
func _t_alien_field_types() -> void:
	var good_a: String = "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": 5000, \"action\": \"build\", \"build\": \"x\", \"at\": \"A\"}"
	var good_b: String = "{\"origin\": \"menu\", \"wait_ms\": 2000, \"action_ms\": -1, \"action\": \"\", \"build\": \"x\", \"at\": \"B\"}"
	var bad_rows: Array = [
		["action — число", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": 5000, \"action\": 3, \"build\": \"x\", \"at\": \"Z\"}"],
		["origin — число", "{\"origin\": 7, \"wait_ms\": 1000, \"action_ms\": 5000, \"action\": \"build\", \"build\": \"x\", \"at\": \"Z\"}"],
		["at — число", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": 5000, \"action\": \"build\", \"build\": \"x\", \"at\": 20270115}"],
		["at — об'єкт", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": 5000, \"action\": \"build\", \"build\": \"x\", \"at\": {\"y\": 2027}}"],
		["build — null", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": 5000, \"action\": \"build\", \"build\": null, \"at\": \"Z\"}"],
		["action — список", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": 5000, \"action\": [\"build\"], \"build\": \"x\", \"at\": \"Z\"}"],
		["wait_ms — рядок", "{\"origin\": \"app\", \"wait_ms\": \"1000\", \"action_ms\": 5000, \"action\": \"build\", \"build\": \"x\", \"at\": \"Z\"}"],
		["action_ms — true", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": true, \"action\": \"build\", \"build\": \"x\", \"at\": \"Z\"}"],
		["запис — рядок", "\"сміття\""],
		["запис — null", "null"],
		["запис — порожній об'єкт", "{}"],
	]
	for c in bad_rows:
		_write(TMP, "{\"version\": 1, \"runs\": [%s, %s, %s]}" % [good_a, String(c[1]), good_b])
		var m: RefCounted = FtueMeter.new()
		var e0: int = _trap.count
		var res: Variant = m.load_file(TMP)
		var rows: PackedStringArray = m.lines(100)
		ok(_trap.count == e0, "V4 чужий тип [%s]: без помилки скрипта%s" % [String(c[0]), "" if _trap.count == e0 else " -> " + _trap.last])
		var text: String = "\n".join(rows)
		var consistent: bool = rows.size() == 0 or rows.size() == 3 or (rows.size() == 2 and rows[0].contains("B") and rows[1].contains("A"))
		ok(res is bool and consistent, "V4 чужий тип [%s]: розбір не обривається посередині (рядків %d, очікувано 0, 2 або 3)" % [String(c[0]), rows.size()])
		ok(not _looks_like_garbage(text), "V4 чужий тип [%s]: сміття не показано" % String(c[0]))
	_cleanup()


# V4: від'ємні / нескінченні / абсурдні значення з файла не показуються гравцеві (ні як число, ні як вердикт).
func _t_garbage_values_not_shown() -> void:
	var rows_json: Array = [
		["від'ємний wait", "{\"origin\": \"app\", \"wait_ms\": -5000, \"action_ms\": 4000, \"action\": \"build\", \"at\": \"Z\"}"],
		["від'ємна дія -7", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": -7, \"action\": \"build\", \"at\": \"Z\"}"],
		["дробові", "{\"origin\": \"app\", \"wait_ms\": 1000.75, \"action_ms\": 4000.25, \"action\": \"gather\", \"at\": \"Z\"}"],
		["нескінченність", "{\"origin\": \"app\", \"wait_ms\": 1e999, \"action_ms\": 1e999, \"action\": \"build\", \"at\": \"Z\"}"],
		["мінус нескінченність", "{\"origin\": \"app\", \"wait_ms\": -1e999, \"action_ms\": -1e999, \"action\": \"build\", \"at\": \"Z\"}"],
		["1e300", "{\"origin\": \"app\", \"wait_ms\": 1e300, \"action_ms\": 1e300, \"action\": \"build\", \"at\": \"Z\"}"],
		["невідома дія", "{\"origin\": \"app\", \"wait_ms\": 1000, \"action_ms\": 4000, \"action\": \"teleport\", \"at\": \"Z\"}"],
		["невідомий origin", "{\"origin\": \"<b>\", \"wait_ms\": 1000, \"action_ms\": 4000, \"action\": \"build\", \"at\": \"Z\"}"],
	]
	for c in rows_json:
		_write(TMP, "{\"version\": 1, \"runs\": [%s]}" % String(c[1]))
		var m: RefCounted = FtueMeter.new()
		var e0: int = _trap.count
		var res: Variant = m.load_file(TMP)
		var text: String = _all_text(m)
		ok(res is bool and _trap.count == e0, "V4 сміття [%s]: load не падає і не дає помилки скрипта" % String(c[0]))
		ok(not _looks_like_garbage(text), "V4 сміття [%s]: у рядку нема від'ємних чисел / nan / inf / дужок%s" % [String(c[0]), "" if not _looks_like_garbage(text) else " -> «%s»" % text])
		ok(not text.contains("<b>") and not text.contains("teleport"), "V4 сміття [%s]: чужі значення полів не потрапляють у текст" % String(c[0]))
		# запис із сміттєвим часом не має отримати вердикт «✓ уклався», якого ніхто не міряв
		if String(c[0]) in ["від'ємна дія -7", "мінус нескінченність"]:
			ok(not text.contains("✓"), "V4 сміття [%s]: від'ємний час дії не стає «✓»%s" % [String(c[0]), "" if not text.contains("✓") else " -> «%s»" % text])
		if String(c[0]) in ["нескінченність", "1e300"]:
			ok(not text.contains("✓"), "V4 сміття [%s]: абсурдний час дії не стає «✓»%s" % [String(c[0]), "" if not text.contains("✓") else " -> «%s»" % text])
	# більше 10 записів у файлі — показуємо останні 10
	var many: Array = []
	for i in range(1, 26):
		many.append("{\"origin\": \"menu\", \"wait_ms\": 1000, \"action_ms\": -1, \"action\": \"\", \"at\": \"q%02d\"}" % i)
	_write(TMP, "{\"version\": 1, \"runs\": [%s]}" % ", ".join(many))
	var big: RefCounted = FtueMeter.new()
	big.load_file(TMP)
	var rows: PackedStringArray = big.lines(100)
	ok(rows.size() == 10 and rows[0].contains("q25") and rows[9].contains("q16"), "V4: файл із 25 записів -> останні 10, найновіший перший")
	# значення, що приходять у begin/observe (годинник стрибнув назад), теж не показуються від'ємними
	var neg: RefCounted = FtueMeter.new()
	neg.begin("app", -4000, {"gather": 0.0, "built": 1}, "", "")
	neg.observe(-2500, {"gather": 0.0, "built": 2})
	ok(not _looks_like_garbage(_all_text(neg)), "V4: від'ємні тривалості на вході не показуються від'ємними")
	_cleanup()


# ---------------------------------------------------------------- V5

# V5: порожньо без вимірів; найновіший перший; ліміт; українською (кирилиця, без сирих ідентифікаторів); D14 — без роду.
func _t_lines_contract() -> void:
	var m: RefCounted = FtueMeter.new()
	ok(m.lines().is_empty() and m.lines(1).is_empty() and m.lines(5).is_empty(), "V5: без вимірів — порожньо (у ☰ нічого зайвого)")
	for i in range(1, 8):
		m.begin("app" if i == 1 else "menu", i * 1000, {"gather": 0.0, "built": 1}, "sha", "t%d" % i)
		m.observe(i * 6000, {"gather": 0.2 if i % 2 == 0 else 0.0, "built": 1 if i % 2 == 0 else 2})
	ok(m.lines().size() == 1, "V5: типово — один рядок (для ☰)")
	ok(m.lines(1).size() == 1 and m.lines(5).size() == 5 and m.lines(100).size() == 7, "V5: ліміт дотримано (1 / 5 / усі 7)")
	ok(m.lines(0).is_empty(), "V5: ліміт 0 — порожньо")
	var rows: PackedStringArray = m.lines(5)
	var order_ok: bool = true
	for i in range(rows.size()):
		order_ok = order_ok and rows[i].contains("t%d" % (7 - i))
	ok(order_ok, "V5: найновіший перший (t7, t6, t5, t4, t3)")
	ok(m.lines(1)[0].contains("7") and m.lines(1)[0].contains("42"), "V5: короткий рядок ☰ — саме останній вимір (7 с до посадки, 42 с до дії)")
	var re := RegEx.new()
	re.compile("[A-Za-z]{3,}")
	for row in m.lines(100):
		var bare: String = row
		for tag in ["t1", "t2", "t3", "t4", "t5", "t6", "t7"]:
			bare = bare.replace(tag, "")
		ok(_has_cyrillic(bare) and re.search(bare) == null, "V5: рядок українською, без сирих латинських ідентифікаторів («%s»)" % row)
		ok(not row.contains("\n"), "V5: один вимір — один рядок")
	var all: String = "\n".join(m.lines(100)).to_lower()
	var gendered: bool = false
	for w in ["зробив", "зробила", "встиг ", "встигла", "приземлився", "приземлилась", "гравець зібрав", "поставив", "поставила"]:
		gendered = gendered or all.contains(w)
	ok(not gendered, "V5/D14: тексти не вгадують стать гравця")
	# обидва види дії читаються по-різному, обидва origin — теж (M5: текст каже правду про те, що сталося)
	var b: RefCounted = FtueMeter.new()
	b.begin("app", 1000, {"gather": 0.0, "built": 1}, "", "")
	b.observe(2000, {"gather": 0.0, "built": 2})
	var g: RefCounted = FtueMeter.new()
	g.begin("app", 1000, {"gather": 0.0, "built": 1}, "", "")
	g.observe(2000, {"gather": 0.2, "built": 1})
	ok(b.lines(1)[0] != g.lines(1)[0], "V5/M5: рядок розрізняє «споруда» і «збір»")
	ok(String(FtueMeter.row_text(b.to_dict().runs[0])) != "" and b.lines(1)[0].contains(String(FtueMeter.row_text(b.to_dict().runs[0]))), "V5: row_text — той самий текст, що в рядку журналу (одна правда)")


# V1/V3/V5 — підключення в newhud_main (сцену headless не піднімаємо; звіряємо шви в коді).
func _t_wiring() -> void:
	var src: String = FileAccess.get_file_as_string("res://newhud_main.gd")
	ok(src.contains("ftue.begin(") and src.contains("ftue.observe("), "підключення: посадка починає вимір, кадр гри спостерігає")
	ok(src.contains("\"menu\"") and src.contains("\"app\""), "підключення: обидва origin розрізняються")
	ok(src.contains("ftue.load_file()"), "підключення: журнал читається на старті (переживає перезапуск)")
	ok(src.contains("ftue.lines("), "підключення: рядки доходять до ☰ / налаштувань")
	ok(src.contains("Time.get_ticks_msec()") and not src.contains("ftue.begin(_ftue_origin, Time.get_unix"), "підключення: тривалості — з монотонного годинника")
	# sim-корпус про хронометр не знає (спостереження, не правило гри)
	var leaked: Array = []
	for path in ["res://scripts/sim.gd", "res://scripts/session.gd", "res://scripts/persistence.gd", "res://scripts/goals.gd"]:
		if FileAccess.get_file_as_string(path).to_lower().contains("ftue_meter"):
			leaked.append(path)
	var d := DirAccess.open("res://scripts/sim")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".gd") and FileAccess.get_file_as_string("res://scripts/sim/" + f).to_lower().contains("ftue"):
				leaked.append(f)
	ok(leaked.is_empty(), "V3: sim/session/persistence не посилаються на хронометр %s" % str(leaked))
	var meter_src: String = ""
	for ln in FileAccess.get_file_as_string("res://scripts/ftue_meter.gd").split("\n"):
		var cut: int = ln.find("#")   # коментарі не рахуємо (у рядках модуля «#» нема)
		meter_src += (ln if cut < 0 else ln.substr(0, cut)) + "\n"
	ok(not meter_src.contains("Time.") and not meter_src.contains("randi") and not meter_src.contains("randf") and not meter_src.contains("RandomNumberGenerator"), "V3: модуль хронометра не читає годинник і не чіпає RNG")


# V5 (додано автором коду 2026-11-20, не qa-adversary): короткий рядок для ☰ — порожній без вимірів, без вердикту до дії,
# число й вердикт узгоджені з повним рядком, і він коротший за повний (у ☰ довгий рядок ховався під кнопкою дії).
func _t_brief() -> void:
	var m: RefCounted = FtueMeter.new()
	ok(m.brief() == "", "V5 brief: без вимірів — порожньо")
	m.begin("app", 2100, {"gather": 0.0, "built": 1}, "", "")
	ok(m.brief().contains("2.1 с") and not m.brief().contains("✓") and not m.brief().contains("✗"), "V5 brief: до дії — час посадки без вердикту")
	m.observe(30001, {"gather": 0.0, "built": 2})
	ok(m.brief().contains("30.1 с") and m.brief().contains("✗") and m.brief().length() < String(m.lines(1)[0]).length(), "V5 brief: число не суперечить вердикту; коротший за повний рядок")
