# RealWorld — kernel/climate.gd : climate derived from REAL geography (the signature hook).
#
# RimWorld analogue: biome + Map temperature + WeatherManager + GenDate day/season/daylight — except
# here the inputs are a region's real lat/lon plus the world clock, not a fictional planet. A
# ClimateProvider answers temperature / season / daylight / weather for any coordinate and time.
# ClimateModel_Deterministic is a closed-form model (seasonal sinusoid scaled by |lat|, hemisphere
# flip below the equator, diurnal swing, latitude-scaled day length) — fully deterministic, no
# network, reproducible from coordinates. SEAM: drop in a ClimateProvider backed by a real weather
# API (e.g. Open-Meteo by lat/lon) behind this same interface; every downstream system (temperature,
# growth, solar power, weather incidents) is unaffected. This mirrors the social.gd backend seam.
extends RefCounted

const SEASON_NAME := {0: "зима", 1: "весна", 2: "літо", 3: "осінь"}
const DAYS_PER_YEAR := 360.0

# The interface every consumer talks to. Values are ctx-free so systems can query any region/time.
class ClimateProvider extends RefCounted:
	func temperature_c(_lat: float, _lon: float, _day: int, _frac: float) -> float:
		return 20.0
	func season(_lat: float, _day: int) -> int:
		return 2
	func daylight(_lat: float, _day: int, _frac: float) -> float:
		return 0.5
	func weather(_lat: float, _lon: float, _day: int, _frac: float, _rng: RandomNumberGenerator) -> StringName:
		return &"clear"

# Closed-form Earth-shaped model. Not a forecast — a plausible, deterministic climate from latitude.
class ClimateModel_Deterministic extends ClimateProvider:

	# Day-of-year in [0,1). The world day counter is treated as a calendar day.
	func _year_phase(day: int) -> float:
		return float(((day - 1) % int(DAYS_PER_YEAR))) / DAYS_PER_YEAR

	# Seasonal term in [-1,+1]: -1 at local mid-winter, +1 at local mid-summer. Southern hemisphere
	# is flipped (July is winter below the equator).
	func _seasonal(lat: float, day: int) -> float:
		var s: float = -cos(_year_phase(day) * TAU)   # N-hemisphere: peaks near day 180
		if lat < 0.0:
			s = -s
		return s

	func temperature_c(lat: float, _lon: float, day: int, frac: float) -> float:
		var abs_lat: float = abs(lat)
		var base_annual: float = 30.0 - 0.55 * abs_lat        # ~30°C at equator, deep cold at poles
		var seasonal_amp: float = 2.0 + 0.30 * abs_lat        # bigger annual swing at high latitude
		var seasonal: float = _seasonal(lat, day) * seasonal_amp
		var diurnal: float = -cos(frac * TAU) * (4.0 + 0.05 * abs_lat)  # coldest pre-dawn, warm midday
		return base_annual + seasonal + diurnal

	func season(lat: float, day: int) -> int:
		# Quadrant from the seasonal value and its direction of travel (rising -> spring/summer).
		var here: float = _seasonal(lat, day)
		var ahead: float = _seasonal(lat, day + 15)
		var rising: bool = ahead >= here
		if here >= 0.0:
			return 2 if not rising else 1   # high & falling = summer, high & rising = late spring
		else:
			return 0 if not rising else 3   # low & rising = winter easing, low & falling = autumn
		# (a coarse but stable mapping; exact solstice math is not needed for gameplay)

	func daylight(lat: float, day: int, frac: float) -> float:
		# Longer summer days / shorter winter days, exaggerated toward the poles.
		var swing: float = _seasonal(lat, day) * (abs(lat) / 90.0)
		var half_day: float = clampf(0.30 + 0.18 * swing, 0.08, 0.48)   # half-length of the lit window
		var noon_dist: float = abs(frac - 0.5)
		return clampf(1.0 - noon_dist / maxf(0.05, half_day), 0.0, 1.0)

	# Weather is stochastic but seeded per query; wetter/foggier is more likely when cold.
	func weather(lat: float, lon: float, day: int, frac: float, rng: RandomNumberGenerator) -> StringName:
		var t: float = temperature_c(lat, lon, day, frac)
		var r: float = rng.randf()
		if t < -5.0:
			return &"snow" if r < 0.35 else &"clear"
		if r < 0.62:
			return &"clear"
		elif r < 0.80:
			return &"rain"
		elif r < 0.90:
			return &"fog"
		else:
			return &"cold_snap"
