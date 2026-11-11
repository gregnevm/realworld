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
	if s.use_realtime and not (s.cal as Dictionary).is_empty():
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
