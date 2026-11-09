# RealWorld — net/geo.gd : PURE great-circle math for the RealGPS layer (spec 0013 §3.1).
#
# One responsibility: turn two coordinates into distance / bearing / a destination point. No state,
# no clock, no RNG. Distance delegates to WorldGen.haversine_km so the game has ONE haversine
# (a second formula would drift by metres and desync "who is near whom" between client and server).
extends RefCounted

const WorldGen = preload("res://scripts/world_gen.gd")
const Social = preload("res://scripts/social.gd")

const EARTH_R_M := 6371008.8
const M_PER_DEG := 111194.9266   # 2*pi*R/360 — metres per degree of latitude (and of longitude at the equator)


# A fix a server may accept: finite numbers inside the legal ranges. NaN/inf never reach a grid.
static func is_valid(lat: float, lon: float) -> bool:
	return is_finite(lat) and is_finite(lon) and absf(lat) <= 90.0 and absf(lon) <= 180.0


static func wrap_lon(lon: float) -> float:
	return wrapf(lon, -180.0, 180.0)


static func distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	return WorldGen.haversine_km(lat1, lon1, lat2, lon2) * 1000.0


# Initial bearing from point 1 to point 2, degrees clockwise from north in [0, 360).
static func bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dl := deg_to_rad(lon2 - lon1)
	var y := sin(dl) * cos(p2)
	var x := cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)


# 8-wind label in the game's own (Ukrainian) compass vocabulary — Social.CARDINALS is the source.
static func cardinal8(bearing: float) -> String:
	var idx := int(roundf(fposmod(bearing, 360.0) / 45.0)) % 8
	return str(Social.CARDINALS[idx])


# The point `dist_m` away from (lat, lon) along `bearing` degrees. Longitude is wrapped, latitude clamped.
static func destination(lat: float, lon: float, bearing: float, dist_m: float) -> Dictionary:
	var d := dist_m / EARTH_R_M
	var b := deg_to_rad(bearing)
	var p1 := deg_to_rad(lat)
	var l1 := deg_to_rad(lon)
	var p2 := asin(clampf(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(b), -1.0, 1.0))
	var l2 := l1 + atan2(sin(b) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
	return {"lat": clampf(rad_to_deg(p2), -90.0, 90.0), "lon": wrap_lon(rad_to_deg(l2))}
