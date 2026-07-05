# RealWorld — kernel/defs.gd : data-driven definitions + typed registry.
#
# RimWorld analogue: Def / DefDatabase / DefOf. A Def is an immutable record — a stable id, a
# def_type bucket, and a pure-data payload. Behaviour never lives on the Def; it lives in Workers,
# Comps and Systems that are keyed off the def. Because the whole content catalogue is plain data it
# is serialisable and shippable. SEAM: DefDatabase.load_pack() is the single injection point a real
# content pipeline / on-chain catalogue would replace; the pack shape IS the wire format.
extends RefCounted

# One definition record. Subclass (or attach a Worker) to add typed behaviour; the base stays data.
class Def extends RefCounted:
	var id: StringName
	var def_type: StringName
	var data: Dictionary

	func _init(p_type: StringName, p_id: StringName, p_data: Dictionary = {}) -> void:
		def_type = p_type
		id = p_id
		data = p_data

	func field(k: StringName, dflt = null):
		return data.get(k, dflt)

	# Declare invariants here; return "" when valid, else a human-readable error. DefDatabase runs
	# these across the whole catalogue at load, so bad content fails loudly instead of at play time.
	func validate(_db) -> String:
		return ""

# The registry. Indexes defs by id and by type; DefOf-style strict lookup surfaces missing content.
class DefDatabase extends RefCounted:
	var _by_id: Dictionary = {}         # StringName -> Def
	var _by_type: Dictionary = {}       # StringName -> Array[Def]

	func register(d) -> void:
		_by_id[d.id] = d
		if not _by_type.has(d.def_type):
			_by_type[d.def_type] = []
		_by_type[d.def_type].append(d)

	func has(id: StringName) -> bool:
		return _by_id.has(id)

	func get_def(id: StringName):
		return _by_id.get(id, null)

	# DefOf-style: a missing id is a content bug, not a gameplay branch — shout and return null.
	func def_of(id: StringName):
		if not _by_id.has(id):
			push_error("Missing def: %s" % id)
			return null
		return _by_id[id]

	func all_of_type(t: StringName) -> Array:
		return _by_type.get(t, [])

	func count() -> int:
		return _by_id.size()

	# Validate every registered def; returns the list of error strings (empty == healthy catalogue).
	func validate_all() -> Array:
		var errs := []
		for id in _by_id:
			var e: String = _by_id[id].validate(self)
			if e != "":
				errs.append("%s: %s" % [id, e])
		return errs

	# SEAM: inject a content pack (from disk, a server, or a chain) as raw records.
	func load_pack(pack: Array) -> void:
		for rec in pack:
			register(Def.new(StringName(rec.def_type), StringName(rec.id), rec.get("data", {})))
