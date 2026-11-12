# RealWorld — sim/realtime.gd : spec 0012 — реальний час 1:1 у симі (лише за use_realtime = ON).
#
# Доменний модуль без стану (godot-sim.md): `static func f(s, ...)`. Sim годинник НЕ читає: `s.now_ms` подає Session
# через Sim.set_clock (REQ-0012-10). За OFF жодна функція тут не змінює стан (REQ-0012-1/3: OFF байт-у-байт).
extends RefCounted

const Calendar = preload("res://scripts/calendar.gd")
const Pacing = preload("res://scripts/pacing.gd")

# Прапор ставиться ДО new_game; посеред сесії зміна відхиляється явною помилкою (REQ-0012-5).
static func set_flag(s, v: bool) -> bool:
	if (s.map as Dictionary).is_empty() or v == s.use_realtime:
		s.config_error = &""
		return v
	s.config_error = &"realtime_flag_locked"
	return s.use_realtime

# Після new_game/load_region/travel: доба 86 400 с, таймзона — властивість РЕГІОНУ (REQ-0012-9), frac — з now.
static func init(s) -> void:
	if not s.use_realtime:
		return
	s.time.day_len = Pacing.DAY_S
	s.cal = {"tz": Calendar.tz_for(float(s.map.lat), float(s.map.lon))}
	sync(s, false)

# Годинник -> frac/день (REQ-0012-6). Перетин цивільної опівночі регіону додає дні до лічильника прожитих днів
# (time.day); без поданого годинника (now_ms == 0) frac стоїть.
static func sync(s, announce: bool) -> void:
	if not s.use_realtime or s.now_ms <= 0 or (s.cal as Dictionary).is_empty():
		return
	var tz: Dictionary = s.cal.tz
	var loc: Dictionary = Calendar.local(s.now_ms, tz)
	var gained: int = int(loc.epoch_day) - int(s.cal.get("epoch_day", int(loc.epoch_day)))
	loc["tz"] = tz
	s.cal = loc
	s.time.frac = float(loc.frac)
	if gained <= 0:
		return
	s.time.day += gained
	if announce:
		s._log("🌅 Новий день: %02d.%02d" % [int(loc.day), int(loc.month)])
		if not s.use_main_capsule:
			s._grant_daily_capsule()   # REQ-0012-26: заряд за ON — від реальної опівночі, не від лічильника тіків

# «День» кліматичної моделі: OFF — лічильник днів (день 1 = пік зими, як було); ON — реальна дата (REQ-0012-7).
static func climate_day(s) -> int:
	if s.use_realtime and (s.cal as Dictionary).has("doy"):   # до першої подачі годинника (відновлення сейву) дати ще нема
		return Calendar.climate_day(int(s.cal.doy), Calendar.is_leap(int(s.cal.year)))
	return int(s.time.day)

# Освітленість 0..1 з реальної геометрії сонця (REQ-0012-8/64); -1.0 — не ON або годинник не подано.
static func daylight(s) -> float:
	if s.use_realtime and s.now_ms > 0:
		return Calendar.daylight(s.now_ms, float(s.map.lat), float(s.map.lon))
	return -1.0

# Темп голоду/втоми (одиниць шкали 0..100 за секунду): ON — з Pacing через fall_per_day/day_len (REQ-0012-13/14/15).
# Повертає float64 (не Vector2: той float32 і зсунув би OFF-хеш на 0.42).
static func hunger_rate(s) -> float:
	return 100.0 * Pacing.fall_per_day("hunger_to_critical") / float(s.time.day_len) if s.use_realtime else 0.42

static func tire_rate(s) -> float:
	return 100.0 * Pacing.fall_per_day("rest_to_collapse") / float(s.time.day_len) if s.use_realtime else 0.30

# ---------------- холод (REQ-0012-17/18/85): масштаби для Gear.update_comfort; gear.gd не змінюється ----------------
# Референс OD-70 «київська зима без вогню/стін»: Київ, найхолодніший день кліматичної моделі (день 1), добова середня
# (frac 0.25 — член diurnal = 0), без одягу й погоди. Година доби й одяг референсу рішенням не задані (OD-R26) —
# це робоче тлумачення; «критичне обмороження» = severity 1.0 (нуль шкали, як голод — OD-52).
const FROST_REF := Vector2(50.4501, 30.5234)
const COMFORT_MIN_C := 12.0                  # = Gear.COMFORT_MIN_C (тест звіряє)
const COMFORT_GAIN_PER_C_DAY := 0.05         # = Gear.COMFORT_GAIN_PER_C_DAY
const COMFORT_RECOVER_PER_DAY := 2.0         # = Gear.COMFORT_RECOVER_PER_DAY

static func frost_ref_felt_c(s) -> float:
	return s.climate.temperature_c(FROST_REF.x, FROST_REF.y, 1, 0.25)

# Множник наростання: OFF — EXPOSURE_PACE як було; ON — так, щоб референс дійшов до 1.0 за Pacing.frostbite_onset.
static func frost_gain_scale(s, off_pace: float) -> float:
	if not s.use_realtime:
		return off_pace
	if in_start_window(s):
		return 0.0   # OD-150 (REQ-0012-54): перші 15 хв після першої посадки холод не накопичується — посадка вночі взимку не вбиває новачка
	var past: float = COMFORT_MIN_C - frost_ref_felt_c(s)
	return Pacing.DAY_S / (COMFORT_GAIN_PER_C_DAY * past * Pacing.seconds("frostbite_onset"))

# Множник відігріву: OFF — 1.0 (кернел як є); ON — повний відігрів 1.0 -> 0 за Pacing.warmup_full (OD-49, ~1 год).
static func frost_recover_scale(s) -> float:
	if not s.use_realtime:
		return 1.0
	return Pacing.DAY_S / (COMFORT_RECOVER_PER_DAY * Pacing.seconds("warmup_full"))

# ---------------- офлайн-догін (REQ-0012-31…34, 67, 84; OD-53, OD-49, OD-139) ----------------
# Чиста функція від (стан, saved_at, now) — годинник не читається. Кроки К1:
#   (1) лічильник прожитих днів (OD-139) — за реальними цивільними опівночами регіону між saved_at і now
#       (це годинник, а не симуляція: ліміт догону його не обрізає — як мітки UTC-мс у 0010 REQ-114/116);
#   (2) потреби героя офлайн (OD-142) — реальний темп за зарахований час, підлога 15 (без смерті офлайн);
#   (3) напади — у К1 відсутні (OD-53, REQ-84): у звіті 0 подій нападу.
# Ліміт догону симуляції — 24 год (OD-49); `applied_ms` — скільки симуляційного часу «зараховано» (для потреб/виробництва,
# коли їхні правила з'являться). now < saved_at — нульовий догін (REQ-33/68).
const CATCH_UP_LIMIT_MS := 86400000   # OD-49 (2026-11-08): 24 год реального офлайн-часу, стартове до плейтесту

static func catch_up(s, saved_at: int, now: int) -> Dictionary:
	var report := {"offline_ms": 0, "applied_ms": 0, "days": 0, "attacks": 0}
	if not s.use_realtime or saved_at <= 0 or now <= saved_at or (s.cal as Dictionary).is_empty():
		return report
	var tz: Dictionary = s.cal.tz
	var end_day: int = int(Calendar.local(now, tz).epoch_day)
	var days: int = end_day - int(Calendar.local(saved_at, tz).epoch_day)
	s.time.day += maxi(0, days)
	s.cal["epoch_day"] = end_day   # дні за цей проміжок пораховано тут — наступний sync() не додасть їх удруге
	report.offline_ms = now - saved_at
	report.applied_ms = mini(now - saved_at, CATCH_UP_LIMIT_MS)
	report.days = maxi(0, days)
	# (2) потреби офлайн (OD-142): падають у реальному темпі за зарахований час, але не нижче OFFLINE_NEED_FLOOR —
	# офлайн не вбиває голодом/виснаженням (OD-53 «без шкоди офлайн» поширено на потреби); здоров'я офлайн не тікає.
	# Чанки на АБСОЛЮТНІЙ сітці (REQ-33/34): кількість меж floor(t/CHUNK) між saved_at і saved_at+applied; кожен чанк —
	# те саме віднімання, тож будь-яке розбиття інтервалу дає ту саму послідовність операцій і той самий float.
	var chunks: int = floori(float(saved_at + int(report.applied_ms)) / CHUNK_MS) - floori(float(saved_at) / CHUNK_MS)
	var p: Dictionary = s.player
	var h0: float = float(p.hunger)
	var r0: float = float(p.rest)
	var dh: float = hunger_rate(s) * CHUNK_MS / 1000.0
	var dr: float = tire_rate(s) * CHUNK_MS / 1000.0
	for i in chunks:
		var h: float = _offline_need(float(p.hunger), dh)
		var r: float = _offline_need(float(p.rest), dr)
		if h == float(p.hunger) and r == float(p.rest):
			break   # обидві на підлозі: далі нічого не зміниться
		p.hunger = h
		p.rest = r
	report["chunks"] = chunks
	report["hunger_lost"] = h0 - float(p.hunger)
	report["rest_lost"] = r0 - float(p.rest)
	return report

const CHUNK_MS := 60000            # OD-143: крок догону — 1 хв реального часу
const OFFLINE_NEED_FLOOR := 15.0   # OD-142: шкала 0..100; поріг «голодний, але живий»

static func _offline_need(v: float, drop: float) -> float:
	if v <= OFFLINE_NEED_FLOOR:
		return v
	return maxf(OFFLINE_NEED_FLOOR, v - drop)

# ---------------- робочий темп (OD-140, OD-141; REQ-0012-19/22/25) ----------------
# Дослідження, біли/ферми, пальне/енергія і гострі/хронічні канали ран за ON ідуть у ТОМУ Ж реальному темпі, що й
# за OFF (робоча доба 150 с): ці числа відкалібровані на перших хвилинах гри, а реальна доба розтягнула б їх у 576 разів.
# За ON у реальну добу живуть лише годинник, клімат, потреби (голод/втома/депривація), холод і рейди.
const WORK_DAY_S := 150.0

static func work_dday(s, dt: float) -> float:
	if s.use_realtime:
		return dt / WORK_DAY_S
	return dt / maxf(1.0, float(s.time.day_len))

# ---------------- сон (OD-143: sleep_full = 1 год; REQ-0012-16) ----------------
static func sleep_rate(s) -> float:
	return 100.0 / Pacing.seconds("sleep_full") if s.use_realtime else 14.0


# ---------------- безпечний старт (OD-150; REQ-0012-54) і пауза застосунку (OD-149; REQ-0012-38) ----------------
const START_WARM_MS := 900000      # OD-150: 15 хв після першої посадки капсули — без наростання холоду
const MICRO_PAUSE_MS := 5000       # OD-149: розрив кадрів ≥ 5 с (застосунок був згорнутий) — догін, а не величезний dt
const MAX_FRAME_DT := 0.25         # OD-149: коротший розрив (дзвінок на 3 с) — dt кадру обрізається

static func in_start_window(s) -> bool:
	var cap: Dictionary = s.main_capsule
	if cap.is_empty() or int(s.now_ms) <= 0:
		return false
	var landed: int = int(cap.get("landed_at", 0))
	return landed > 0 and int(s.now_ms) - landed < START_WARM_MS
