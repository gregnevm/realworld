# RealWorld — net/geo_grid.gd : the shared-world grid (spec 0013 §3.2) — "coordinates are the seed",
# extended to many players: everyone standing in the same cell plays in the same region.
#
# The grid is a pure function of (lat, lon, cell_m). Rows are fixed-height latitude bands; the number
# of columns per row shrinks toward the poles (cos latitude) so every cell is ~cell_m wide everywhere
# on Earth instead of degenerating into slivers. Columns wrap at the antimeridian. No state besides
# the two derived constants, no clock, no RNG — a client and a server that agree on cell_m agree on
# every cell id without exchanging a byte.
extends RefCounted

const Geo = preload("res://scripts/net/geo.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

# One cell == one playable region: the 56x56 map is ~760 m across (frozen OSM scale, spec 0010 §5).
const DEFAULT_CELL_M := 760.0
const MIN_CELL_M := 10.0
const POLE_EPS := 0.01   # degrees; keeps cos(lat) away from 0 when sizing the polar rows

var cell_m: float = DEFAULT_CELL_M
var _dlat: float = 0.0
var _rows: int = 0


func _init(p_cell_m: float = DEFAULT_CELL_M) -> void:
	cell_m = maxf(p_cell_m, MIN_CELL_M)
	_dlat = cell_m / Geo.M_PER_DEG
	_rows = maxi(1, int(ceil(180.0 / _dlat)))


func rows() -> int:
	return _rows


func row_of(lat: float) -> int:
	return clampi(int(floor((clampf(lat, -90.0, 90.0) + 90.0) / _dlat)), 0, _rows - 1)


func _row_lo(row: int) -> float:
	return -90.0 + float(row) * _dlat


func _row_center_lat(row: int) -> float:
	return clampf(_row_lo(row) + _dlat * 0.5, -90.0 + POLE_EPS, 90.0 - POLE_EPS)


func cols_in_row(row: int) -> int:
	var circumference_m := 360.0 * cos(deg_to_rad(_row_center_lat(row))) * Geo.M_PER_DEG
	return maxi(1, int(floor(circumference_m / cell_m)))


func cell_of(lat: float, lon: float) -> Vector2i:
	var row := row_of(lat)
	var cols := cols_in_row(row)
	var col := int(floor((Geo.wrap_lon(lon) + 180.0) / (360.0 / float(cols))))
	return Vector2i(row, clampi(col, 0, cols - 1))


static func key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


# "row:col" -> Vector2i, or null for anything that is not a well-formed key (the wire is untrusted).
static func parse_key(k: String) -> Variant:
	var parts := k.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))


func key_of(lat: float, lon: float) -> String:
	return key(cell_of(lat, lon))


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _rows and cell.y >= 0 and cell.y < cols_in_row(cell.x)


func center(cell: Vector2i) -> Dictionary:
	var cols := cols_in_row(cell.x)
	var width := 360.0 / float(cols)
	return {"lat": _row_center_lat(cell.x), "lon": Geo.wrap_lon(-180.0 + (float(cell.y) + 0.5) * width)}


# The canonical region every player in `cell` shares: its anchor coordinate IS the world seed
# (WorldGen.canon_coord folds the same string the single-player persistence key uses).
func region_of(cell: Vector2i) -> Dictionary:
	var c := center(cell)
	return {
		"key": key(cell),
		"lat": float(c.lat),
		"lon": float(c.lon),
		"canon": WorldGen.canon_coord(float(c.lat), float(c.lon)),
		"seed": WorldGen.hash_seed(float(c.lat), float(c.lon)),
	}


# Every cell whose extent can intersect the disc (lat, lon, radius_m) — a CANDIDATE set (cheap bucket
# lookup); callers filter by exact distance. Sorted by (row, col) so iteration order is canonical.
func cells_within(lat: float, lon: float, radius_m: float) -> Array:
	var out: Array = []
	var lon_w := Geo.wrap_lon(lon)
	var dlat := maxf(radius_m, 0.0) / Geo.M_PER_DEG
	var r0 := row_of(lat - dlat)
	var r1 := row_of(lat + dlat)
	for row in range(r0, r1 + 1):
		var cols := cols_in_row(row)
		var lo := _row_lo(row)
		var far_lat := minf(maxf(absf(lo), absf(lo + _dlat)), 90.0 - POLE_EPS)
		var c := cos(deg_to_rad(far_lat))
		var dlon := 180.0 if c < 1e-6 else radius_m / (Geo.M_PER_DEG * c)
		if cols == 1 or dlon >= 180.0:
			for col in cols:
				out.append(Vector2i(row, col))
			continue
		var width := 360.0 / float(cols)
		var a := int(floor((lon_w - dlon + 180.0) / width))
		var b := int(floor((lon_w + dlon + 180.0) / width))
		if b - a + 1 >= cols:
			for col in cols:
				out.append(Vector2i(row, col))
		else:
			var picked: Array = []
			for k in range(a, b + 1):
				picked.append(posmod(k, cols))
			picked.sort()
			for col in picked:
				out.append(Vector2i(row, int(col)))
	return out


static func compare(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
