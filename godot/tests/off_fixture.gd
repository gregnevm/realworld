# RealWorld — tests/off_fixture.gd : loading + comparing godot/tests/fixtures/off_baseline.json.
#
# Shared by run_capsule_tests.gd (spec 0010) and run_realtime_tests.gd (spec 0012). The fixture is the
# "flag OFF == the code before the specs" memory; scenarios live in off_scenarios.gd (one copy for the
# capture and for the suites).
#
# Platform policy (critique 0012 #12 / brief): the `numeric` tier (world_hash, float state after ticks)
# flows through libm cos() in the climate model, so it is only reproducible on the platform that
# captured it.
#   same platform      -> HARD comparison.
#   other platform, CI -> FAIL (a gate that is silently skipped on the CI runner guarantees nothing).
#   other platform     -> LOUD skip: [SKIP] per check + a closing WARN banner. Never a silent pass.
# The `portable` tier (texts, cells, key sets, counters) is compared on EVERY platform.
#
# Float tolerance: Godot's JSON number parser is off by 1 ulp for ~9% of doubles (to_float), so a float
# that travelled through the fixture file may differ from the live value in the last bit. Floats are
# therefore compared to 1e-9 relative; strings (hashes, texts), ints and booleans are compared exactly.
extends RefCounted

const FIXTURE_PATH := "res://tests/fixtures/off_baseline.json"
const FLOAT_TOL := 1.0e-9
const MAX_DIFFS_SHOWN := 6


static func load_fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	return parsed if parsed is Dictionary else {}


# {same_platform, in_ci, hard, mode: "hard" | "fail" | "skip", note}
static func env_status(fixture: Dictionary) -> Dictionary:
	var fx_platform: String = String(fixture.get("platform", ""))
	var same: bool = fx_platform == OS.get_name()
	var in_ci: bool = OS.get_environment("CI") != "" or OS.get_environment("GITHUB_ACTIONS") != ""
	var mode: String = "hard" if same else ("fail" if in_ci else "skip")
	var note: String = "fixture platform=%s current=%s ci=%s fixture_godot=%s current_godot=%s" % [fx_platform, OS.get_name(), str(in_ci),
		String(fixture.get("godot_version", "?")), String(Engine.get_version_info().string)]
	return {"same_platform": same, "in_ci": in_ci, "mode": mode, "note": note}


static func decode_legacy_text(entry: Dictionary) -> String:
	var gz: PackedByteArray = Marshalls.base64_to_raw(String(entry.get("gz_b64", "")))
	if gz.is_empty():
		return ""
	var raw: PackedByteArray = gz.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	return raw.get_string_from_utf8()


# ---------------------------------------------------------------------------------------------
# structural diff of the current value against the fixture value; appends human-readable lines
# ---------------------------------------------------------------------------------------------
static func diff(cur: Variant, fix: Variant, path: String, out: Array) -> void:
	if cur is Dictionary and fix is Dictionary:
		var keys: Dictionary = {}
		for k in cur:
			keys[str(k)] = true
		for k in fix:
			keys[str(k)] = true
		var sorted_keys: Array = keys.keys()
		sorted_keys.sort()
		for k in sorted_keys:
			var in_cur: bool = _hasv(cur, String(k))
			var in_fix: bool = _hasv(fix, String(k))
			if in_cur and not in_fix:
				out.append("%s.%s: NEW in current (not in the baseline): %s" % [path, k, _short(_getv(cur, String(k)))])
			elif in_fix and not in_cur:
				out.append("%s.%s: MISSING in current (baseline had %s)" % [path, k, _short(_getv(fix, String(k)))])
			else:
				diff(_getv(cur, String(k)), _getv(fix, String(k)), path + "." + String(k), out)
	elif cur is Array and fix is Array:
		if _all_strings(cur) and _all_strings(fix):
			if cur != fix:
				var added: Array = []
				var removed: Array = []
				for e in cur:
					if not (fix as Array).has(e):
						added.append(e)
				for e in fix:
					if not (cur as Array).has(e):
						removed.append(e)
				out.append("%s: string list differs (+%s -%s%s)" % [path, _short(added), _short(removed), "; order only" if added.is_empty() and removed.is_empty() else ""])
			return
		if cur.size() != fix.size():
			out.append("%s: array size %d != baseline %d" % [path, cur.size(), fix.size()])
			return
		for i in cur.size():
			diff(cur[i], fix[i], "%s[%d]" % [path, i], out)
	elif _is_num(cur) and _is_num(fix):
		var a: float = float(cur)
		var b: float = float(fix)
		if absf(a - b) > FLOAT_TOL * maxf(1.0, maxf(absf(a), absf(b))):
			out.append("%s: %s != baseline %s" % [path, str(cur), str(fix)])
	elif _is_text(cur) and _is_text(fix):
		if str(cur) != str(fix):   # String vs StringName (a StringName survives no JSON trip) is the same text
			out.append("%s: %s != baseline %s" % [path, _short(cur), _short(fix)])
	else:
		if typeof(cur) != typeof(fix) or cur != fix:
			out.append("%s: %s != baseline %s" % [path, _short(cur), _short(fix)])


static func _hasv(d: Dictionary, k: String) -> bool:
	if d.has(k):
		return true
	return d.has(StringName(k)) or (k.is_valid_int() and d.has(k.to_int()))


static func _getv(d: Dictionary, k: String) -> Variant:
	if d.has(k):
		return d[k]
	if d.has(StringName(k)):
		return d[StringName(k)]
	if k.is_valid_int() and d.has(k.to_int()):
		return d[k.to_int()]
	return null


static func _is_text(v: Variant) -> bool:
	return v is String or v is StringName


static func _is_num(v: Variant) -> bool:
	return v is int or v is float


static func _all_strings(a: Array) -> bool:
	for e in a:
		if not _is_text(e):
			return false
	return true


static func _short(v: Variant) -> String:
	var t: String = JSON.stringify(v)
	return t if t.length() <= 180 else t.left(177) + "..."


# the first MAX_DIFFS_SHOWN lines + a count, for the failure log
static func summarize(diffs: Array) -> String:
	var lines: Array = diffs.slice(0, MAX_DIFFS_SHOWN)
	var s: String = "\n      ".join(PackedStringArray(lines))
	if diffs.size() > MAX_DIFFS_SHOWN:
		s += "\n      … +%d more" % (diffs.size() - MAX_DIFFS_SHOWN)
	return s


