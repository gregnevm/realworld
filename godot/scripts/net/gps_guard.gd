# RealWorld — net/gps_guard.gd : plausibility check for consecutive GPS fixes (spec 0013 §3.3).
#
# One responsibility: given the previous accepted fix and a new one, say whether a human could have
# moved that far in that time. It is a FILTER, not a verdict: spoofing policy and the relocation limit
# are open owner decisions (OD-17/22/31/45), so the numbers are PROPOSED defaults, injectable per
# call, and a refusal only means "this fix is not applied" — never a ban.
#
# Rule (no division, so dt = 0 cannot blow up):  dist <= jitter_m + max_speed_mps * dt_s.
#   jitter_m  absorbs ordinary GPS noise (a stationary phone wanders tens of metres).
#   max_speed ~50 m/s (180 km/h) lets trains/cars through and refuses teleports across a city.
extends RefCounted

const Geo = preload("res://scripts/net/geo.gd")

const OK := &"ok"
const R_BAD_FIX := &"bad_fix"        # NaN/inf/out-of-range coordinates, or a malformed fix record
const R_TIME_BACK := &"time_back"    # the new fix is older than the accepted one
const R_TELEPORT := &"teleport"      # faster than a human could travel

const DEFAULT_PARAMS := {"max_speed_mps": 50.0, "jitter_m": 25.0}


# prev / next: {lat, lon, t_ms}. `prev` may be empty ({}) for the first fix of a session.
static func check(prev: Dictionary, next: Dictionary, params: Dictionary = DEFAULT_PARAMS) -> Dictionary:
	if not (next.get("lat") is float or next.get("lat") is int) or not (next.get("lon") is float or next.get("lon") is int):
		return _res(R_BAD_FIX, 0.0, 0.0)
	var lat := float(next.lat)
	var lon := float(next.lon)
	if not Geo.is_valid(lat, lon):
		return _res(R_BAD_FIX, 0.0, 0.0)
	if prev.is_empty():
		return _res(OK, 0.0, 0.0)
	var dt_ms := int(next.get("t_ms", 0)) - int(prev.get("t_ms", 0))
	if dt_ms < 0:
		return _res(R_TIME_BACK, 0.0, 0.0)
	var dist := Geo.distance_m(float(prev.lat), float(prev.lon), lat, lon)
	var dt_s := float(dt_ms) / 1000.0
	var speed := dist / maxf(dt_s, 0.001)
	var allowed := float(params.get("jitter_m", 25.0)) + float(params.get("max_speed_mps", 50.0)) * dt_s
	return _res(OK if dist <= allowed else R_TELEPORT, dist, speed)


static func _res(reason: StringName, dist: float, speed: float) -> Dictionary:
	return {"ok": reason == OK, "reason": reason, "dist_m": dist, "speed_mps": speed}
