# RealWorld — scripts/calendar.gd : spec 0012 §3.2 — реальна дата, цивільний місцевий час із DST і геометрія сонця.
#
# Чисті статичні функції від (now, lat, lon): `now` — ціле UTC-мс епохи (int64), його подає Session зі свого Clock;
# тут годинник НЕ читається (REQ-0012-10), стану й RNG нема (REQ-0012-63).
#
# Модель часу (OD-49, 2026-11-08): `frac` доби = ЦИВІЛЬНИЙ місцевий час регіону з DST (збігається зі стінним
# годинником гравця); сонячний час (за lon + рівняння часу) — лише для візуалу день/ніч (`daylight`).
#
# Таймзона регіону (REQ-0012-9/12) — властивість КООРДИНАТ, не акаунта: `tz_for(lat, lon)`. Бази IANA в Godot нема,
# тож це таблиця ПРАВИЛ кроку 1: стандартний офсет = round(lon/15) год і правило DST за грубою областю
# (Європа — EU, Північна Америка — US, решта — без DST). Для України (UTC+2, EU-DST) збігається точно; для країн,
# що скасували DST або живуть не в «своєму» поясі, — наближення (відома межа; заміна на IANA-таблицю — шов `tz_for`).
extends RefCounted

const DAY_MS := 86400000
const HOUR_MS := 3600000
const MIN_MS := 60000

const RULE_NONE := &"none"
const RULE_EU := &"eu"   # остання неділя березня 01:00 UTC → остання неділя жовтня 01:00 UTC
const RULE_US := &"us"   # друга неділя березня 02:00 місцевого → перша неділя листопада 02:00 місцевого

# ---------------- григоріанський календар (proleptic, H. Hinnant) ----------------
static func days_from_civil(y: int, m: int, d: int) -> int:
	var yy: int = y - (1 if m <= 2 else 0)
	var era: int = (yy if yy >= 0 else yy - 399) / 400
	var yoe: int = yy - era * 400
	var mp: int = m + (-3 if m > 2 else 9)
	var doy: int = (153 * mp + 2) / 5 + d - 1
	var doe: int = yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468

# epoch-day -> [рік, місяць 1..12, день 1..31]
static func civil_from_days(days: int) -> Array:
	var z: int = days + 719468
	var era: int = (z if z >= 0 else z - 146096) / 146097
	var doe: int = z - era * 146097
	var yoe: int = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var y: int = yoe + era * 400
	var doy: int = doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp: int = (5 * doy + 2) / 153
	var d: int = doy - (153 * mp + 2) / 5 + 1
	var m: int = mp + 3 if mp < 10 else mp - 9
	return [y + (1 if m <= 2 else 0), m, d]

# 0 = неділя … 6 = субота (1970-01-01 — четвер)
static func weekday(days: int) -> int:
	return posmod(days + 4, 7)

static func day_of_year(days: int) -> int:
	var c: Array = civil_from_days(days)
	return days - days_from_civil(int(c[0]), 1, 1) + 1

static func is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0

static func _last_sunday(y: int, m: int) -> int:
	var next_first: int = days_from_civil(y + 1, 1, 1) if m == 12 else days_from_civil(y, m + 1, 1)
	var last: int = next_first - 1
	return last - weekday(last)

static func _nth_sunday(y: int, m: int, nth: int) -> int:
	var first: int = days_from_civil(y, m, 1)
	return first + posmod(7 - weekday(first), 7) + 7 * (nth - 1)

# ---------------- таймзона регіону ----------------
static func tz_for(lat: float, lon: float) -> Dictionary:
	var std_min: int = clampi(int(round(lon / 15.0)) * 60, -720, 840)
	var rule: StringName = RULE_NONE
	if lat >= 34.0 and lat <= 72.0 and lon >= -25.0 and lon <= 40.0:
		rule = RULE_EU
	elif lat >= 24.0 and lat <= 72.0 and lon >= -170.0 and lon <= -52.0:
		rule = RULE_US
	return {"std_min": std_min, "rule": rule}

# Офсет цивільного часу від UTC у хвилинах на момент `now` (з урахуванням DST).
static func offset_min(now: int, tz: Dictionary) -> int:
	var std: int = int(tz.get("std_min", 0))
	var rule: StringName = StringName(tz.get("rule", RULE_NONE))
	if rule == RULE_NONE:
		return std
	var y: int = int(civil_from_days(floori(float(now) / DAY_MS))[0])
	var start: int
	var end: int
	if rule == RULE_EU:
		start = _last_sunday(y, 3) * DAY_MS + HOUR_MS
		end = _last_sunday(y, 10) * DAY_MS + HOUR_MS
	else:   # RULE_US: 02:00 місцевого стандартного -> 03:00; 02:00 місцевого літнього -> 01:00
		start = _nth_sunday(y, 3, 2) * DAY_MS + 2 * HOUR_MS - std * MIN_MS
		end = _nth_sunday(y, 11, 1) * DAY_MS + 2 * HOUR_MS - (std + 60) * MIN_MS
	return std + 60 if now >= start and now < end else std

# Цивільний місцевий час регіону: epoch-день, дата, день року і частка доби (float64, від цілих мс — без втрати точності).
static func local(now: int, tz: Dictionary) -> Dictionary:
	var off: int = offset_min(now, tz)
	var lms: int = now + off * MIN_MS
	var eday: int = floori(float(lms) / DAY_MS)
	if eday * DAY_MS > lms:   # floori над float64 для |lms| < 2^53 точний, але межу доби страхуємо цілими
		eday -= 1
	elif (eday + 1) * DAY_MS <= lms:
		eday += 1
	var c: Array = civil_from_days(eday)
	return {
		"epoch_day": eday, "year": int(c[0]), "month": int(c[1]), "day": int(c[2]),
		"doy": eday - days_from_civil(int(c[0]), 1, 1) + 1,
		"frac": float(lms - eday * DAY_MS) / float(DAY_MS),
		"offset_min": off,
	}

# День року -> «день» кліматичної моделі (climate.gd: 360-денний рік, день 1 = найхолодніша точка північної
# півкулі). Найхолодніша точка реального року — ~15 січня (doy 15); півкулю перевертає сам climate.gd (REQ-0012-7).
const COLDEST_DOY := 15
static func climate_day(doy: int, leap: bool = false) -> int:
	var ylen: float = 366.0 if leap else 365.0
	return int(floor(fposmod(float(doy - COLDEST_DOY), ylen) * 360.0 / ylen)) + 1

# ---------------- сонце (NOAA, наближення ~1 хв) ----------------
static func _gamma(doy: int) -> float:
	return TAU / 365.0 * float(doy - 1)

# схилення сонця, радіани
static func declination(doy: int) -> float:
	var g: float = _gamma(doy)
	return 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) \
		+ 0.000907 * sin(2.0 * g) - 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)

# рівняння часу, хвилини
static func eq_time_min(doy: int) -> float:
	var g: float = _gamma(doy)
	return 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))

# Справжній сонячний час у точці (частка доби, 0.5 = сонячний полудень). Зсув lon на 15° = 1/24 доби.
static func solar_frac(now: int, lon: float) -> float:
	var eday: int = floori(float(now) / DAY_MS)
	var utc_frac: float = float(now - eday * DAY_MS) / float(DAY_MS)
	return fposmod(utc_frac + lon / 360.0 + eq_time_min(day_of_year(eday)) / 1440.0, 1.0)

# Висота сонця над горизонтом, градуси.
static func sun_elevation_deg(now: int, lat: float, lon: float) -> float:
	var doy: int = day_of_year(floori(float(now) / DAY_MS))
	var dec: float = declination(doy)
	var phi: float = deg_to_rad(clampf(lat, -90.0, 90.0))
	var h: float = (solar_frac(now, lon) - 0.5) * TAU
	var s: float = sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h)
	return rad_to_deg(asin(clampf(s, -1.0, 1.0)))

# Освітленість сцени 0..1 з реальної геометрії сонця (REQ-0012-8/64): 0 нижче −6° (кінець цивільних сутінків),
# 1 вище +6°, лінійно між ними. Полярний день/ніч виходять самі (без NaN: asin від clamp).
static func daylight(now: int, lat: float, lon: float) -> float:
	return clampf((sun_elevation_deg(now, lat, lon) + 6.0) / 12.0, 0.0, 1.0)

# Схід/захід сонця для дати (epoch-день) у ЦИВІЛЬНИХ місцевих хвилинах від опівночі.
# {polar: &""|&"day"|&"night", rise_min, set_min}; за полярного дня/ночі rise/set = -1.
static func sun_times(eday: int, lat: float, lon: float, tz: Dictionary) -> Dictionary:
	var doy: int = day_of_year(eday)
	var dec: float = declination(doy)
	var phi: float = deg_to_rad(clampf(lat, -90.0, 90.0))
	var cphi: float = cos(phi)
	if absf(cphi) < 1e-9:   # полюс: сонце або весь день над горизонтом, або весь день під ним
		return {"polar": &"day" if sin(phi) * sin(dec) > 0.0 else &"night", "rise_min": -1.0, "set_min": -1.0}
	var arg: float = (cos(deg_to_rad(90.833)) / (cphi * cos(dec))) - tan(phi) * tan(dec)
	if arg > 1.0:
		return {"polar": &"night", "rise_min": -1.0, "set_min": -1.0}
	if arg < -1.0:
		return {"polar": &"day", "rise_min": -1.0, "set_min": -1.0}
	var ha: float = rad_to_deg(acos(arg))
	var eqt: float = eq_time_min(doy)
	var noon_ms: int = eday * DAY_MS + DAY_MS / 2
	var off: float = float(offset_min(noon_ms, tz))
	return {
		"polar": &"",
		"rise_min": fposmod(720.0 - 4.0 * (lon + ha) - eqt + off, 1440.0),
		"set_min": fposmod(720.0 - 4.0 * (lon - ha) - eqt + off, 1440.0),
	}
