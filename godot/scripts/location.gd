# RealWorld — scripts/location.gd : spec 0012 §3.7 — звідки береться місце висадки (LocationProvider), чи воно валідне,
# і де найближче «вільне» місце (nearest_free + OccupancyProvider). Без стану між сесіями (REQ-0012-63), без годинника:
# вік фіксу передає край пристрою.
#
# Провайдери (REQ-0012-39): `FakeProvider` (задані lat/lon — пресети, ручне введення; dev/ПК, REQ-40),
# `DeviceProvider` (GPS телефону: у кроці 1 нативного плагіна геолокації ще нема — чесно повертає «недоступно»,
# поки край пристрою не передасть фікс через `feed()`). Будь-який провайдер віддає ОДИН формат фіксу, тож світ
# (`canon_coord`, seed) не залежить від того, хто дав координати (REQ-0012-41).
# Числа (поріг давності/точності, крок і радіус пошуку) — OD-147 (агент за делегуванням власника, 2026-11-12).
extends RefCounted

const WorldGen = preload("res://scripts/world_gen.gd")

const MAX_FIX_AGE_MS := 600000      # OD-147: фікс, старший за 10 хв, — «застарілий»
const MAX_ACCURACY_M := 1000.0      # OD-147: точність гірша за 1 км — «неточний»
const NULL_ISLAND_EPS := 1e-6       # (0, 0) — типовий «порожній» фікс, а не місце
const FREE_STEP_DEG := 0.01         # OD-147: крок спіралі «вільне поруч» (~1 км по широті)
const FREE_MAX_RING := 25           # OD-147: максимум 25 кілець (~25 км) → явна помилка

const R_OK := &"ok"
const R_NAN := &"not_finite"
const R_RANGE := &"out_of_range"
const R_NULL_ISLAND := &"null_island"
const R_DENIED := &"permission_denied"
const R_STALE := &"stale_fix"
const R_INACCURATE := &"inaccurate_fix"
const R_UNAVAILABLE := &"unavailable"
const R_NO_FREE := &"no_free_spot"

# Текст стану «локація недоступна» для екрана вибору місця (REQ-0012-75: явний стан, а не мовчазний фолбек).
const MSG := {
	R_NAN: "Координати пошкоджені — оберіть місце вручну.",
	R_RANGE: "Поза межами: широта ±90°, довгота ±180°.",
	R_NULL_ISLAND: "GPS не дав місця (0, 0) — оберіть місце вручну.",
	R_DENIED: "Доступ до геолокації заборонено — оберіть місто або координати.",
	R_STALE: "Геолокація застаріла — спробуйте ще раз надворі.",
	R_INACCURATE: "Геолокація надто неточна — спробуйте ще раз або оберіть вручну.",
	R_UNAVAILABLE: "GPS цього пристрою ще не підключений — оберіть місто або координати.",
	R_NO_FREE: "Поруч немає вільного місця — оберіть інше.",
}

# REQ-0012-75: валідація ДО canon_coord. fix — {lat, lon, age_ms?, accuracy_m?, denied?}.
static func validate(fix: Dictionary) -> Dictionary:
	if bool(fix.get("denied", false)):
		return _bad(R_DENIED)
	if bool(fix.get("unavailable", false)):
		return _bad(R_UNAVAILABLE)
	var la: Variant = fix.get("lat")
	var lo: Variant = fix.get("lon")
	if not (la is float or la is int) or not (lo is float or lo is int):
		return _bad(R_NAN)
	var lat := float(la)
	var lon := float(lo)
	if not is_finite(lat) or not is_finite(lon):
		return _bad(R_NAN)
	if absf(lat) > 90.0 or absf(lon) > 180.0:
		return _bad(R_RANGE)
	if absf(lat) < NULL_ISLAND_EPS and absf(lon) < NULL_ISLAND_EPS:
		return _bad(R_NULL_ISLAND)
	if int(fix.get("age_ms", 0)) > MAX_FIX_AGE_MS:
		return _bad(R_STALE)
	if float(fix.get("accuracy_m", 0.0)) > MAX_ACCURACY_M:
		return _bad(R_INACCURATE)
	return {"ok": true, "reason": R_OK, "lat": lat, "lon": lon}

static func _bad(r: StringName) -> Dictionary:
	return {"ok": false, "reason": r, "msg": String(MSG.get(r, ""))}

# ---------------- провайдери (REQ-0012-39/40) ----------------
class LocationProvider extends RefCounted:
	func kind() -> StringName:
		return &"none"
	func current() -> Dictionary:
		return {"unavailable": true}

class FakeProvider extends LocationProvider:
	var lat := 0.0
	var lon := 0.0
	func _init(p_lat: float = 0.0, p_lon: float = 0.0) -> void:
		lat = p_lat
		lon = p_lon
	func kind() -> StringName:
		return &"fake"
	func current() -> Dictionary:
		return {"lat": lat, "lon": lon, "age_ms": 0, "accuracy_m": 0.0}

# Фікс телефону. Край пристрою (плагін/ОС) кладе сюди останній фікс через feed(); без нього — «недоступно».
class DeviceProvider extends LocationProvider:
	var _fix: Dictionary = {}
	func kind() -> StringName:
		return &"device"
	func feed(fix: Dictionary) -> void:
		_fix = fix.duplicate()
	func current() -> Dictionary:
		return _fix if not _fix.is_empty() else {"unavailable": true}

# REQ-0012-40: фейк-провайдер (ручні координати як «GPS») — лише в dev/ПК-збірці. Мобільна релізна збірка — ні.
static func fake_allowed(is_mobile: bool, is_debug: bool) -> bool:
	return is_debug or not is_mobile

# ---------------- зайнятість і «вільне поруч» (REQ-0012-43/44/76) ----------------
# Крок 1 — без сервера: заглушка «все вільне» (REQ-44). Набір `occupied` — ключі canon_coord.
class OccupancyProvider extends RefCounted:
	var occupied: Dictionary = {}
	func snapshot() -> Dictionary:
		return occupied.duplicate()

# Детермінована спіраль на сітці FREE_STEP_DEG навколо coord: кільце 0, 1, 2… (у кільці — фіксований порядок
# dy, dx), пропускає клітини поза широтою ±90 і загортає довготу на ±180. Результат залежить лише від (coord, occupied).
static func nearest_free(lat: float, lon: float, occupied: Dictionary) -> Dictionary:
	var v: Dictionary = validate({"lat": lat, "lon": lon})
	if not bool(v.ok):
		return v
	for r in FREE_MAX_RING + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var la: float = lat + dy * FREE_STEP_DEG
				if absf(la) > 90.0:
					continue
				var lo: float = wrapf(lon + dx * FREE_STEP_DEG, -180.0, 180.0)
				if not occupied.has(WorldGen.canon_coord(la, lo)):
					return {"ok": true, "reason": R_OK, "lat": la, "lon": lo, "ring": r}
	return _bad(R_NO_FREE)
