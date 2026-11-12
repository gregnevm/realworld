# RealWorld — sim/farming.gd : the FARMING domain of the live sim (spec 0008 phase 4 continued —
# the first RENEWABLE resource source).
#
# Connects the last big coded-but-not-felt kernel comp — things.gd CompGrower (temperature- and
# light-gated growth, kernel-tested since Batch 1) — to the live building dicts. A placed grow zone
# owns a grower Thing whose ctx is ITS OWN CELL's felt world: temp_at (indoor buffering + heaters)
# and light_at (daylight + lamps), so a walled, heated, lit room is literally a greenhouse and a
# Kyiv winter starves an outdoor field. Hydroponics rides the power net (device_active): unpowered
# trays simply don't grow.
#
# The mixed-plot v1: each harvest yields the next staple in a deterministic per-cell rotation
# (catalog_defs.farm_crop — the gather_yield pattern). Crop selection per zone is a later verb.
#
# Same bridge contract as sim/power.gd: kernel comps own the physics, building dicts stay the
# persistent truth (b.growth / b.harvests mirror every tick -> saves, world_hash, rejoin), the
# Thing fleet is a derived cache rebuilt lazily on farm_dirty and NEVER serialized. Thing<->Comp
# cycles are owned here — rebuild detaches the old fleet; tests call s.dispose_farm().
extends RefCounted

const Realtime = preload("res://scripts/sim/realtime.gd")   # spec 0012: робочий темп за ON (OD-140)
const Things = preload("res://scripts/kernel/things.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")

# ---------------- fleet lifecycle ----------------
static func rebuild(s) -> void:
	dispose(s)
	s.farm_things = {}
	for b in s.buildings:
		var def: Dictionary = s.building_def(String(b.kind))
		if not bool(def.get("grow", false)):
			continue
		var cell: int = int(b.y) * s.n + int(b.x)
		var t: Variant = Things.Thing.new(null)
		t.add_comp(Things.CompGrower.new({
			"grow_days": CatalogDefs.FARM_GROW_DAYS / maxf(0.01, float(def.get("grow_mult", 1.0))),
			"temp_min": CatalogDefs.FARM_TEMP_MIN,
			"temp_max": CatalogDefs.FARM_TEMP_MAX,
			"min_light": CatalogDefs.FARM_MIN_LIGHT,
		}))
		t.flags["growth"] = clampf(float(b.get("growth", 0.0)), 0.0, 1.0)   # a loaded save resumes mid-cycle
		s.farm_things[cell] = t
	s.farm_dirty = false

static func dispose(s) -> void:
	for cell in s.farm_things:
		s.farm_things[cell].detach()
	s.farm_things = {}

# ---------------- the per-tick pass (called from sim.update, after power) ----------------
static func update(s, dt: float) -> void:
	if s.farm_dirty:
		rebuild(s)
	if s.farm_things.is_empty():
		return   # the shipped slice: no data.gd def grows -> zero cost, byte-identical
	var dday: float = Realtime.work_dday(s, dt)   # OD-140: ферми за ON — робочий темп
	var cells: Array = s.farm_things.keys()
	cells.sort()   # deterministic harvest order
	for cell in cells:
		var b: Variant = s.bgrid.get(cell, null)
		if b == null:
			continue
		# a powered tray (hydroponics) grows only when the net delivers — the power seam feeds food
		if not s.device_active(b):
			continue
		var t: Variant = s.farm_things[cell]
		var x: int = int(cell) % s.n
		var y: int = int(cell) / s.n
		t.tick({"temp_c": s.temp_at(x, y), "light": s.light_at(x, y), "dday": dday})
		var grower: Variant = t.get_comp(Things.CompGrower)
		if grower.mature():
			# a SELECTED crop (set_crop verb) wins; the mixed per-cell rotation is the default
			var crop: String = String(b.get("crop", ""))
			if crop == "":
				crop = CatalogDefs.farm_crop(int(cell), int(b.get("harvests", 0)))
			var added: int = s.deposit(crop, CatalogDefs.FARM_YIELD)
			b["harvests"] = int(b.get("harvests", 0)) + 1
			t.flags["growth"] = 0.0   # replant the cycle
			if added > 0:
				s._log("🌾 Урожай: %s+%d." % [CatalogDefs.res_icon(crop), added], "good")
		b["growth"] = float(grower.growth())
