# RealWorld — tests/run_realtime_tests.gd : spec 0012 (реальний час, відкритий світ, FTUE) — tests written
# FROM THE REQ TABLE by the qa-adversary role.
# Run: godot --headless --path godot -s res://tests/run_realtime_tests.gd
#
# WAVE S0 (this file today): the «перший зелений тест» of the spec — REQ-0012-1/2/3/4/81: with
# use_realtime = OFF the world, the save string and the pacing constants are byte-for-byte the code BEFORE
# the spec. The fixture godot/tests/fixtures/off_baseline.json is captured from the unmodified baseline by
# tests/capture_baseline.gd (header: baseline_commit, platform, Godot build); the scenarios are
# tests/off_scenarios.gd. Platform policy (critique 0012 #12): numeric (hash) pins compare HARD on the
# capture platform, FAIL on a different CI platform, and skip LOUDLY on a dev machine — never silently.
#
# Not duplicated here (they stay the spec's other proofs, green WITHOUT edits — REQ-0012-3): run_tests
# `_t_goals_chain` / `_t_playable_opening` / `_t_save_continue`, run_ui_tests (GoalsPanel, speed chips),
# run_determinism_tests (WORLD_HASH_FINAL, also diffed across two OS processes in CI).
#
# Later waves APPEND their `_t_*` below the `_t_off_*` block (Clock, catch-up, pacing ON, modes, hints);
# the `_t_off_*` pins must stay green after EVERY wave (D4).
extends "res://tests/harness.gd"

const SessionScript = preload("res://scripts/session.gd")
const Scenarios = preload("res://tests/off_scenarios.gd")
const OffFixture = preload("res://tests/off_fixture.gd")
const OffChecker = preload("res://tests/off_checker.gd")

const WORLD_HASH_FINAL := "c4dbef44fe0f95d6"
# keys the spec will add to a save/record; at OFF none of them may appear (REQ-0012-2). `landing` /
# `main_capsule` belong to spec 0010 and are listed because the set comparison must catch them too.
const LATER_KEYS := ["use_realtime", "clock", "saved_at", "last_seen_now", "hints", "pacing_version", "dev_time_scale", "location", "landing", "main_capsule"]

var chk: Variant = null   # OffChecker


func _init() -> void:
	print("== RealWorld realtime tests (spec 0012) ==")
	chk = OffChecker.new(self)
	_t_off_baseline_header()
	_t_off_baseline_hashes()
	_t_off_save_string_and_keys()
	_t_off_legacy_paths()
	_t_off_texts()
	_t_off_capsule_untouched()
	_t_off_legacy_save_loads_off()
	_t_off_flag_default_off()
	# --- WAVE 0012-W1: Clock + the ban on wall-clock / system RNG in the sim (REQ-0012-10/11, REQ-0012-68 helper) ---
	_t_no_wallclock_in_sim()
	_t_no_unseeded_rng_in_sim()
	_t_sim_has_no_clock_back_door()
	_t_clock_os_reads_only_in_system_clock()
	_t_clock_providers()
	_t_clock_state_isolated()
	_t_clock_wire_int64()
	_t_clock_wire_rejects_garbage()
	_t_clock_monotonic()
	chk.skip_banner()
	finish()


# REQ-0012-1: «хеш коміту записується в заголовок фікстури»; the fixture is the proof, so check it is one
func _t_off_baseline_header() -> void:
	var fx: Dictionary = chk.fixture
	ok(chk.has_fixture(), "REQ-0012-1: godot/tests/fixtures/off_baseline.json exists")
	var hex := RegEx.new()
	hex.compile("^[0-9a-f]{40}$")
	ok(hex.search(String(fx.get("baseline_commit", ""))) != null, "REQ-0012-1: the fixture header records baseline_commit (git rev-parse HEAD): %s" % String(fx.get("baseline_commit", "")).left(12))
	ok(String(fx.get("platform", "")) != "" and String(fx.get("godot_version", "")) != "", "REQ-0012-1: the header records the platform and the Godot build (critique 0012 #12)")
	ok(String(fx.get("world_hash_final", "")) == WORLD_HASH_FINAL, "REQ-0012-1: the fixture world_hash_final == the baseline WORLD_HASH_FINAL (%s)" % WORLD_HASH_FINAL)
	print("  note: ", String(chk.env.note))


# REQ-0012-1: use_realtime=false -> world_hash after N ticks and the Session.save_game string == the fixture
func _t_off_baseline_hashes() -> void:
	var cur: Dictionary = chk.scenario("twin_ambient_300")
	if String(chk.env.mode) == "hard":
		ok(String(cur.numeric.world_hash) == WORLD_HASH_FINAL, "REQ-0012-1: twin ambient 300 ticks world_hash == %s (literal; got %s)" % [WORLD_HASH_FINAL, String(cur.numeric.world_hash)])
	elif String(chk.env.mode) == "fail":
		ok(false, "REQ-0012-1: the WORLD_HASH_FINAL literal cannot be checked on this CI platform (%s)" % String(chk.env.note))
	else:
		chk.skipped += 1
		print("  [SKIP] REQ-0012-1: WORLD_HASH_FINAL literal — %s" % String(chk.env.note))
	# pacing-sensitive scenarios: every place Pacing.dday will replace `dt / day_len` (sim.update, environment,
	# farming, director, hero_health, power) is exercised below; one hash moves if any of them drifts at OFF
	chk.numeric("twin_ambient_300", "REQ-0012-1 twin ambient (director + environment + hero health)")
	chk.numeric("flat_100", "REQ-0012-1 flat pad 100 ticks")
	chk.numeric("catalog_power_farm", "REQ-0012-1 power grid + farm growth + temp anomaly over ~1.3 days (power/farm/env dday)")
	chk.numeric("inventory_on_300", "REQ-0012-1 use_inventory ON")
	chk.numeric("catalog_on_300", "REQ-0012-1 use_catalog ON")
	chk.numeric("raid_director_apply", "REQ-0012-1 director raid payload wave (Director.update/apply)")
	chk.numeric("fuzz_verbs", "REQ-0012-1 seeded verb fuzz")
	chk.numeric("director_long", "REQ-0012-1 ~53 game days of the live storyteller (Director dday scaling, MTB cadence)")
	chk.portable("director_grace", "REQ-0012-1 Director gating table (live incidents, grace days)")


# REQ-0012-2: the set of keys of the save (and of the record / runtime that world_hash covers) == the fixture;
# SAVE_VERSION unchanged; the save STRING is byte-identical (sha256)
func _t_off_save_string_and_keys() -> void:
	ok(SessionScript.SAVE_VERSION == int(chk.fixture.get("save_version", -1)) and SessionScript.SAVE_VERSION == 1, "REQ-0012-2: Session.SAVE_VERSION is unchanged (1)")
	chk.portable("save_continue", "REQ-0012-2 Session.save_game key-path set (stock/inventory/catalog worlds)")
	chk.portable("twin_ambient_300", "REQ-0012-2 region + runtime key sets (the world_hash input)")
	chk.portable("record_keys", "REQ-0012-2 record schema across worlds")
	chk.numeric("save_continue", "REQ-0012-1/2 Session.save_game string sha256, byte-for-byte")
	# secondary diagnostic (the REQ says compare the SET, which the checks above do): no later key may even appear
	var seen: Array = []
	for kind in Scenarios.SAVE_KINDS:
		for p in (chk.scenario("save_continue").portable[kind].key_paths as Array):
			for seg in String(p).split("."):
				if LATER_KEYS.has(String(seg).trim_suffix("[]")):
					seen.append(p)
	var rec: Dictionary = chk.scenario("twin_ambient_300").portable
	for k in (rec.region_keys as Array) + (rec.runtime_keys as Array):
		if LATER_KEYS.has(String(k)):
			seen.append(k)
	ok(seen.is_empty(), "REQ-0012-2: an OFF save/record carries none of the spec's keys %s" % str(seen.slice(0, 3)))
	ok(bool(rec.world_hash_is_region_plus_dyn), "REQ-0012-2: world_hash == content_hash({region, dyn}) — nothing else (no clock/saved_at) feeds it")


# REQ-0012-3: time.day_len=150, ×1–×3 speeds + pause, the 10-goal chain, hunger/rest by today's constants
func _t_off_legacy_paths() -> void:
	chk.portable("goals_speeds", "REQ-0012-3 goals chain (10) + speed grammar (x1-x3, pause) + goals_view at start")
	chk.portable("needs_pace", "REQ-0012-3 day length, hunger/rest decay, eating, sleeping, day-turn arithmetic")
	chk.portable("hud_and_strings", "REQ-0012-3 OFF HudModel snapshot schema + slices (no new HUD key at OFF) and the shipped death strings")
	chk.numeric("hud_and_strings", "REQ-0012-3 OFF HudModel snapshot content hash")
	var gs: Dictionary = chk.scenario("goals_speeds").portable
	ok(int(gs.goal_count) == 10 and (gs.goal_ids as Array).size() == 10, "REQ-0012-3: the goals chain has 10 goals")
	ok((gs.speeds as Array) == [1.0, 2.0, 3.0], "REQ-0012-3: running speeds are ×1/×2/×3")
	var np: Dictionary = chk.scenario("needs_pace").portable
	ok(float(np.day_len) == 150.0 and float(gs.day_len_at_start) == 150.0, "REQ-0012-3: time.day_len == 150 at OFF")
	ok(int(np.ticks_to_day_turn_from_noon) == 750, "REQ-0012-3: a day turns after 75 s of sim from noon (150 s days) — 750 ticks of 0.1")
	var pace: Array = np.after_100_ticks
	ok(absf(float(pace[0]) - (82.0 - 0.42 * 10.0)) < 1.0e-6 and absf(float(pace[1]) - (92.0 - 0.30 * 10.0)) < 1.0e-6,
		"REQ-0012-3: hunger drains 0.42/s and rest 0.30/s (82→77.8, 92→89.0 after 10 s)")
	ok(absf(float(np.sleep_50_ticks[0]) - 99.82) < 1.0e-6, "REQ-0012-3: sleeping in a bed restores rest at +14/s (40 → 99.82 in 5 s, then wakes)")


# REQ-0012-3 («за OFF поводяться як раніше») for the STRINGS: the FTUE/hint wave rewrites the landing feed, the spawn
# hint and the flash hints, and none of them is in world_hash (sim.messages / flash_msg = view). Same scenarios as the
# capsule suite (one fixture, one capture); literals here guard the hint wording this spec's hints replace at ON.
func _t_off_texts() -> void:
	chk.portable("session_feed", "REQ-0012-3 OFF landing/travel/continue feed (Session.start, no clear)")
	chk.numeric("session_feed", "REQ-0012-3 OFF feed lines with the felt-°C figure")
	chk.portable("flash_hints", "REQ-0012-3 OFF flash hints «(4)» + build refusals")
	chk.portable("capsule_panel_off", "REQ-0012-3/81 OFF CapsulePanel (the daily-charge rows stay at OFF)")
	var feed: Dictionary = chk.scenario("session_feed").portable
	var stock_hint: String = String((feed.stock.start_hints as Array)[0])
	var inv_hint: String = String((feed.inventory.start_hints as Array)[0])
	ok("розпали багаття (9)" in stock_hint and "постав багаття з хотбару (слот 1)" in inv_hint, "REQ-0012-3: the OFF spawn hints are the shipped «розпали багаття (9)» / «постав багаття з хотбару (слот 1)»")
	var fl: Dictionary = chk.scenario("flash_hints").portable
	ok((fl.full_storage.seen as Array) == ["📦 Склад повний — збудуй ще один склад (4)."] and (fl.no_storage.seen as Array) == ["Несеш максимум — збудуй склад (4)."],
		"REQ-0012-3: the OFF flash hints keep the build-bar key «(4)»")


# REQ-0012-81: the daily capsule (spec 0002) is untouched at OFF — scenario S6 «перехід доби, поля capsule»
func _t_off_capsule_untouched() -> void:
	chk.portable("capsule_day_transition", "REQ-0012-81 daily capsule across the day boundary")
	chk.numeric("capsule_day_transition", "REQ-0012-81 daily capsule across the day boundary (Київ)")
	chk.portable("capsule_launch", "REQ-0012-81 try_launch_capsule / capsule_can_reach / invites")
	chk.numeric("capsule_launch", "REQ-0012-81 capsule launch km texts")
	var cd: Dictionary = chk.scenario("capsule_day_transition").portable
	ok((cd.capsule_after as Dictionary) == {"charges": 1, "last_day": 196, "radius_km": 100.0}, "REQ-0012-81: one charge, 100 km radius, last_day follows the day counter")
	ok((cd.capsule_keys as Array) == ["charges", "last_day", "radius_km"], "REQ-0012-81: the capsule dict keeps its three fields (no new field at OFF)")
	ok((cd.lines as Array).has("🚀 Щоденна капсула готова (радіус 100 км)."), "REQ-0012-81: the «Щоденна капсула готова» line is unchanged")


# REQ-0012-4: an old save (no use_realtime) loads with the flag OFF and is not silently migrated to real time
func _t_off_legacy_save_loads_off() -> void:
	var legacy: Dictionary = chk.fixture.get("legacy_saves", {})
	ok(legacy.size() == Scenarios.SAVE_KINDS.size(), "REQ-0012-4: the fixture carries a baseline save per world kind (%s)" % str(legacy.keys()))
	for kind in Scenarios.SAVE_KINDS:
		if not legacy.has(kind):
			continue
		var entry: Dictionary = legacy[kind]
		var text: String = OffFixture.decode_legacy_text(entry)
		ok(text.length() == int(entry.raw_length) and text.sha256_text() == String(entry.sha256), "REQ-0012-4 [%s]: the stored baseline save decodes byte-exact" % kind)
		var cur: Dictionary = Scenarios.restore_legacy(text)
		var diffs: Array = []
		OffFixture.diff(cur.portable, entry.restore.portable, "", diffs)
		if not diffs.is_empty():
			print("    legacy [%s] mismatch:\n      %s" % [kind, OffFixture.summarize(diffs)])
		ok(diffs.is_empty(), "REQ-0012-4 [%s]: an old save restores unchanged (buildings, goals, capsule, home, day, regions)" % kind)
		ok(bool(cur.portable.get("flags", {}).get("future_flags_off", false)), "REQ-0012-4 [%s]: use_realtime stays OFF after loading an old save" % kind)
		ok(float(cur.portable.get("day_len", 0.0)) == 150.0, "REQ-0012-4 [%s]: the restored world still runs 150 s days (not migrated to real time)" % kind)
		ok(bool(cur.portable.get("resave_paths_equal", false)), "REQ-0012-4 [%s]: re-saving it writes no use_realtime/clock/saved_at key" % kind)
		match String(chk.env.mode):
			"hard":
				var nd: Array = []
				OffFixture.diff(cur.numeric, entry.restore.numeric, "", nd)
				if not nd.is_empty():
					print("    legacy [%s] numeric mismatch:\n      %s" % [kind, OffFixture.summarize(nd)])
				ok(nd.is_empty(), "REQ-0012-4 [%s]: old save -> world_hash, re-save sha256 and 40 ticks of continue == baseline" % kind)
			"fail":
				ok(false, "REQ-0012-4 [%s]: numeric legacy pins cannot be verified on this CI platform (%s)" % [kind, String(chk.env.note)])
			_:
				chk.skipped += 1
				print("  [SKIP] REQ-0012-4 [%s] numeric legacy pins — %s" % [kind, String(chk.env.note)])


func _t_off_flag_default_off() -> void:
	var sess: Variant = SessionScript.new()
	var sim: Variant = preload("res://scripts/sim.gd").new()
	for f in Scenarios.FUTURE_FLAGS:
		var on: bool = (f in sess and bool(sess.get(f))) or (f in sim and bool(sim.get(f)))
		ok(not on, "REQ-0012-1/4: %s defaults to OFF on a fresh Session and Sim" % f)
	sim.dispose_farm()
	sim.dispose_power()


# =====================================================================================================
# WAVE 0012-W1 — Clock interface + the ban on the wall clock / system RNG in the sim.
# Written from the REQ rows (REQ-0012-10, REQ-0012-11, REQ-0012-68 helper) and the owner's wire rule (spec
# header R3: absolute times are int64 UTC-ms, in JSON a decimal STRING like the RNG cursors) — NOT from
# clock.gd. The scanner below is this suite's own (independent of run_tests `_code_of` / lint lib.mjs): a
# tripwire is only worth its sensitivity, so it is first proved on planted snippets, then run on the tree.
# Not testable yet (later waves): «Sim.set_clock(now) is the only way now enters» and «a provider swap
# changes frac without touching sim» need Sim.set_clock / TimeModel (W3/W4).
# =====================================================================================================
const Clock = preload("res://scripts/clock.gd")

const INT64_MAX := 9223372036854775807
const INT64_MIN := -9223372036854775807 - 1
const TWO53 := 9007199254740992
const NOW_1P8E12 := 1800000000000   # 2027-01-15T08:00:00Z: the magnitude the spec names («≈1.8e12, int64»)
const MS_PER_HOUR := 3600000
const CLOCK_HOME := "res://scripts/clock.gd"
const SESSION_HOME := "res://scripts/session.gd"

# The sim corpus = every script under godot/scripts MINUS the view layer (brief of the wave: clock.gd itself,
# ui/**, world_view.gd, main.gd, map_widget.gd; newhud_main.gd lives outside scripts/). Walked recursively HERE,
# so a script in a brand-new directory is in the corpus by default.
const SCRIPTS_ROOT := "res://scripts"
const VIEW_DIR_PREFIXES := ["ui/"]
const VIEW_FILES := ["clock.gd", "world_view.gd", "map_widget.gd", "main.gd"]
const MUST_SCAN := ["sim.gd", "session.gd", "persistence.gd", "goals.gd", "social.gd", "world_gen.gd", "data.gd", "catalog_sim.gd",
	"sim/threats.gd", "sim/director.gd", "sim/hero_health.gd", "sim/environment.gd", "kernel/needs.gd", "kernel/gear.gd", "net/command.gd"]

# The spec's list (REQ-0012-10): Time.*, OS.get_*time*, Engine.get_ticks_*, Engine.time_scale, DateTime,
# randomize(), randf*/randi*. A method on a SEEDED RandomNumberGenerator (`rng.randf()`) is the sanctioned way.
const BANNED := [
	["Time.*", "\\bTime\\s*\\."],
	["OS.get_*time*", "\\bOS\\s*\\.\\s*get_\\w*time\\w*"],
	["Engine.get_ticks_*", "\\bEngine\\s*\\.\\s*get_ticks_\\w+"],
	["Engine.time_scale", "\\bEngine\\s*\\.\\s*time_scale"],
	["DateTime", "\\bDateTime\\b"],
	["randomize()", "(^|[^\\w])randomize\\s*\\("],
	["randf*/randi*", "(^|[^.\\w])(randf|randi)\\w*\\s*\\("],
]
# Hidden system randomness the spec's names do not spell out but its headline («системного RNG») covers:
# Array.shuffle()/pick_random() draw from the GLOBAL generator.
const HIDDEN_GLOBAL_RNG := "\\.(shuffle|pick_random)\\s*\\("

const SCANNER_MUST_HIT := [
	"var t: int = Time.get_ticks_msec()",
	"var t: float = Time.get_unix_time_from_system()",
	"var d: Dictionary = Time.get_datetime_dict_from_system()",
	"var t: int = OS.get_system_time_msecs()",
	"var t: int = OS.get_unix_time()",
	"var d: Dictionary = OS.get_datetime()",
	"var t: int = Engine.get_ticks_msec()",
	"Engine.time_scale = 3.0",
	"var d := DateTime.new()",
	"rng.randomize()",
	"randomize()",
	"var x: float = randf()",
	"var x: float = randf_range(0.0, 1.0)",
	"var n: int = randi() % 6",
	"var n: int = randi_range(1, 6)",
	"var g: float = randfn(0.0, 1.0)",
	"if absf(randf() - 0.5) > 0.1: pass",
	"print(\"#\", Time.get_ticks_msec())",                                   # a '#' in a string must not hide code after it
	"var s: String = \"it's \" + str(Time.get_ticks_msec())",               # an apostrophe inside a double-quoted string
	"var s: String = \"a\\\"b\" + str(Time.get_ticks_msec())",              # an escaped quote
	"var t: int = Time.get_ticks_msec()   # \"quote and 'apostrophe",       # a comment never hides the code BEFORE it
]
const SCANNER_MUST_PASS := [
	"# Time.get_ticks_msec() randomize() DateTime Engine.time_scale",
	"\t## OS.get_system_time_secs() in a doc comment",
	"var s: String = \"Time.get_ticks_msec() randf() DateTime\"",
	"var s: String = 'OS.get_datetime() randomize()'",
	"var r: float = rng.randf()",
	"var r: int = rng.randi_range(0, 3)",
	"var r: float = s.env_rng.randfn(0.0, 1.0)",
	"var r: int = rand_from_seed(seed_val)[0]",
	"var tm: Timer = Timer.new()",
	"var p: float = s.time.frac",
	"var q: int = float_time_of_day()",
	"func randomized_pick(arr: Array) -> int:",
	"var z: int = errand() + brandf() + grandfather_randi()",
	"var f: int = Engine.get_frames_drawn()",
	"rng.seed = hash_seed",
]


# ---- own scanner -------------------------------------------------------------------------------------

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# One source line as executable code: the trailing comment is dropped; with blank_strings the CONTENT of string
# literals is dropped too (so "Time." in a message is not a call), otherwise strings are kept (to read preload paths).
func _code_of(line: String, blank_strings: bool) -> String:
	var out := ""
	var quote := ""
	var i := 0
	var n := line.length()
	while i < n:
		var ch: String = line[i]
		if quote != "":
			if ch == "\\" and i + 1 < n:
				if not blank_strings:
					out += ch + line[i + 1]
				i += 2
				continue
			if ch == quote:
				quote = ""
				out += ch
			elif not blank_strings:
				out += ch
		elif ch == "\"" or ch == "'":
			quote = ch
			out += ch
		elif ch == "#":
			break
		else:
			out += ch
		i += 1
	return out


func _banned_res() -> Array:
	var out: Array = []
	for row: Array in BANNED:
		var re := RegEx.new()
		re.compile(String(row[1]))
		out.append([String(row[0]), re])
	return out


func _labels_in(code: String, res: Array) -> Array:
	var labels: Array = []
	for row: Array in res:
		if (row[1] as RegEx).search(code) != null:
			labels.append(String(row[0]))
	return labels


# -> ["line:label", ...] for every banned call in the executable code of `src`
func _scan_source(src: String, res: Array) -> Array:
	var hits: Array = []
	var no := 0
	for line: String in src.split("\n"):
		no += 1
		for lbl: String in _labels_in(_code_of(line, true), res):
			hits.append("%d:%s" % [no, lbl])
	return hits


func _walk_gd(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	for d: String in dir.get_directories():
		_walk_gd(dir_path + "/" + d, out)


func _is_view(rel: String) -> bool:
	if rel in VIEW_FILES:
		return true
	for pre: String in VIEW_DIR_PREFIXES:
		if rel.begins_with(pre):
			return true
	return false


func _sim_corpus() -> Array:
	var all: Array = []
	_walk_gd(SCRIPTS_ROOT, all)
	all.sort()
	var out: Array = []
	for p: String in all:
		if not _is_view(p.trim_prefix(SCRIPTS_ROOT + "/")):
			out.append(p)
	return out


func _rel(p: String) -> String:
	return p.trim_prefix(SCRIPTS_ROOT + "/")


# ---- REQ-0012-10 -------------------------------------------------------------------------------------

# REQ-0012-10: «Sim не звертається до годинника й системного RNG» — заборонені API; Time.get_unix_time_from_system
# живе лише в clock.gd.
func _t_no_wallclock_in_sim() -> void:
	var res: Array = _banned_res()
	# (a) the scanner is not blind, and not trigger-happy
	var missed: Array = []
	for s: String in SCANNER_MUST_HIT:
		if _scan_source(s, res).is_empty():
			missed.append(s)
	ok(missed.is_empty(), "REQ-0012-10: the scanner flags every banned API on planted lines (missed: %s)" % str(missed))
	var noisy: Array = []
	for s: String in SCANNER_MUST_PASS:
		if not _scan_source(s, res).is_empty():
			noisy.append(s)
	ok(noisy.is_empty(), "REQ-0012-10: the scanner ignores comments, string contents, seeded rng methods and look-alikes (false hits: %s)" % str(noisy))
	# (b) the corpus is what the brief says: everything under scripts/ except the view layer
	var corpus: Array = _sim_corpus()
	var rels: Array = []
	for p: String in corpus:
		rels.append(_rel(p))
	var missing: Array = []
	for m: String in MUST_SCAN:
		if not rels.has(m):
			missing.append(m)
	ok(corpus.size() >= 30 and missing.is_empty(), "REQ-0012-10: the sim corpus has %d scripts and includes the sim/kernel/session/persistence/net core (missing: %s)" % [corpus.size(), str(missing)])
	ok(not rels.has("clock.gd") and not rels.has("ui/panels.gd") and not rels.has("world_view.gd"), "REQ-0012-10: clock.gd and the view layer are outside the corpus (so a false red cannot hide a real one)")
	# (c) the verdict: no banned API in the executable code of any corpus script
	var offenders: Array = []
	for p: String in corpus:
		for h: String in _scan_source(_read(p), res):
			offenders.append("%s:%s" % [_rel(p), h])
	ok(offenders.is_empty(), "REQ-0012-10: no Time.*/OS.get_*time*/Engine.get_ticks_*/Engine.time_scale/DateTime/randomize()/randf*/randi* in %d sim scripts%s"
		% [corpus.size(), "" if offenders.is_empty() else " — " + ", ".join(PackedStringArray(offenders))])
	# (d) Array.shuffle()/pick_random() = the global generator = system randomness
	var hidden := RegEx.new()
	hidden.compile(HIDDEN_GLOBAL_RNG)
	var shuffles: Array = []
	for p: String in corpus:
		var no := 0
		for line: String in _read(p).split("\n"):
			no += 1
			if hidden.search(_code_of(line, true)) != null:
				shuffles.append("%s:%d" % [_rel(p), no])
	ok(shuffles.is_empty(), "REQ-0012-10 (headline «системного RNG»): no Array.shuffle()/pick_random() (global generator) in the sim%s" % ("" if shuffles.is_empty() else " — " + ", ".join(PackedStringArray(shuffles))))
	# (e) the one allowed reader of the device clock is clock.gd — looked for in EVERY product script, view layer included
	var every: Array = []
	_walk_gd(SCRIPTS_ROOT, every)
	every.append("res://newhud_main.gd")
	every.sort()
	var homes: Array = []
	for p: String in every:
		for line: String in _read(p).split("\n"):
			if _code_of(line, true).find("Time.get_unix_time_from_system") >= 0:
				homes.append(p)
				break
	ok(homes == [CLOCK_HOME], "REQ-0012-10: Time.get_unix_time_from_system is called in clock.gd and nowhere else (found: %s)" % str(homes))


# REQ-0012-10 «RandomNumberGenerator без явного seed»: a Godot 4 generator that is never given a seed/state is
# seeded from the system. Stricter than a by-name lint: a FUNCTION-LOCAL generator must be seeded later in the SAME
# function; a member (class-level `var`, or `obj.name = ...`) must be seeded somewhere in the corpus.
func _t_no_unseeded_rng_in_sim() -> void:
	var corpus: Array = _sim_corpus()
	var sources: Dictionary = {}
	var seeded_anywhere: String = ""
	for p: String in corpus:
		var lines: Array = []
		for line: String in _read(p).split("\n"):
			lines.append(_code_of(line, true))
		sources[p] = lines
		seeded_anywhere += "\n".join(PackedStringArray(lines)) + "\n"
	var create_re := RegEx.new()
	create_re.compile("(?:^(\\s*)var\\s+(\\w+)\\s*(?::\\s*[\\w.]+\\s*)?:?=|(?:(\\w+)\\.)?(\\w+)\\s*=)\\s*RandomNumberGenerator\\.new\\s*\\(\\s*\\)\\s*$")
	var bad: Array = []
	var created := 0
	for p: String in corpus:
		var lines: Array = sources[p]
		for i in lines.size():
			var code: String = String(lines[i])
			if code.find("RandomNumberGenerator.new") < 0:
				continue
			created += 1
			var m: RegExMatch = create_re.search(code.strip_edges(false, true))
			if m == null:
				bad.append("%s:%d unbound/unusual RandomNumberGenerator.new()" % [_rel(p), i + 1])
				continue
			var is_var: bool = m.get_string(2) != ""
			var name: String = m.get_string(2) if is_var else m.get_string(4)
			var is_member: bool = (is_var and m.get_string(1) == "") or m.get_string(3) != ""
			var seed_re := RegEx.new()
			seed_re.compile("\\b%s\\.(seed|state)\\s*=[^=]" % name)
			if is_member:
				if seed_re.search(seeded_anywhere) == null:
					bad.append("%s:%d member %s is never seeded anywhere" % [_rel(p), i + 1, name])
			else:
				var ok_local := false
				for j in range(i + 1, lines.size()):
					var nxt: String = String(lines[j]).strip_edges()
					if nxt.begins_with("func ") or nxt.begins_with("static func "):
						break
					if seed_re.search(String(lines[j])) != null:
						ok_local = true
						break
				if not ok_local:
					bad.append("%s:%d local %s is not seeded in its own function" % [_rel(p), i + 1, name])
	ok(created >= 6, "REQ-0012-10: found the RandomNumberGenerator.new() sites of the sim (%d) — the scan is not vacuous" % created)
	ok(bad.is_empty(), "REQ-0012-10: every RandomNumberGenerator in the sim is explicitly seeded%s" % ("" if bad.is_empty() else " — " + "; ".join(PackedStringArray(bad))))


# REQ-0012-10 «now приходить лише аргументом Session → Sim.set_clock(now)»: the ban list names APIs, and the one
# provider that reads the OS is clock.gd's SystemClock — so a sim module could read the device clock through
# `SystemClock.new().now_ms()` without tripping any banned name. Two back doors: (1) naming SystemClock anywhere
# but Session; (2) a view-layer file the corpus pulls in (net/command.gd preloads ui/input_*.gd) is exempt from
# the scan by directory — but the code path is the sim's.
func _t_sim_has_no_clock_back_door() -> void:
	var corpus: Array = _sim_corpus()
	var users: Array = []
	for p: String in corpus:
		if p == SESSION_HOME:
			continue
		var no := 0
		for line: String in _read(p).split("\n"):
			no += 1
			if _code_of(line, true).find("SystemClock") >= 0:
				users.append("%s:%d" % [_rel(p), no])
	ok(users.is_empty(), "REQ-0012-10: only Session may name SystemClock — the sim receives now as an argument%s" % ("" if users.is_empty() else " — " + ", ".join(PackedStringArray(users))))
	# (2) transitive closure over preload()/load() paths from the corpus into the exempt files
	var path_re := RegEx.new()
	path_re.compile("res://scripts/[\\w/]+\\.gd")
	var in_corpus: Dictionary = {}
	for p: String in corpus:
		in_corpus[p] = true
	var queue: Array = corpus.duplicate()
	var reached: Array = []
	var seen: Dictionary = {}
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		for line: String in _read(cur).split("\n"):
			for m: RegExMatch in path_re.search_all(_code_of(line, false)):
				var dep: String = m.get_string()
				if in_corpus.has(dep) or seen.has(dep):
					continue
				seen[dep] = true
				reached.append(dep)
				queue.append(dep)
	reached.sort()
	var res: Array = _banned_res()
	var dirty: Array = []
	for dep: String in reached:
		if dep == CLOCK_HOME:
			continue   # the sanctioned reader; its own shape is checked below
		for h: String in _scan_source(_read(dep), res):
			dirty.append("%s:%s" % [_rel(dep), h])
	print("  note: exempt files reachable from the sim corpus: ", ", ".join(PackedStringArray(reached.map(func(x: String) -> String: return _rel(x)))))
	ok(dirty.is_empty(), "REQ-0012-10: exempt (view-layer) scripts that the sim corpus preloads read no clock/system RNG%s" % ("" if dirty.is_empty() else " — " + ", ".join(PackedStringArray(dirty))))


# REQ-0012-11: SystemClock is THE provider that reads the OS («системний = годинник пристрою»); Fixed/Fake/Monotonic
# and the wire helpers must not — otherwise a «fixed» test clock would drift with the machine.
func _t_clock_os_reads_only_in_system_clock() -> void:
	var res: Array = _banned_res()
	var cur := ""
	var no := 0
	var hits: Array = []
	for line: String in _read(CLOCK_HOME).split("\n"):
		no += 1
		if line.begins_with("class "):
			cur = line.get_slice(" ", 1).trim_suffix(":")
		elif line != "" and not line.begins_with("\t") and not line.begins_with("#"):
			cur = ""   # a top-level statement ends the class body
		for lbl: String in _labels_in(_code_of(line, true), res):
			hits.append([cur, no, lbl])
	var outside: Array = []
	for h: Array in hits:
		if String(h[0]) != "SystemClock":
			outside.append("%s@%d %s" % [str(h[0]), int(h[1]), str(h[2])])
	ok(not hits.is_empty(), "REQ-0012-11: clock.gd reads the OS clock somewhere (SystemClock is not a stub)")
	ok(outside.is_empty(), "REQ-0012-11: only class SystemClock touches Time/OS/Engine/rng — Fixed/Fake/Monotonic/wire helpers are pure (offending: %s)" % str(outside))


# ---- REQ-0012-11: providers ----------------------------------------------------------------------------

# a provider written by a TEST: anything that implements the interface drops in with no sim change
class StepClock extends Clock.ClockBase:
	var t: int = 1800000000000

	func now_ms() -> int:
		t += 1000
		return t


# stands in for the one reader of Clock (Session hands the result to the sim as an argument): it knows ONLY the interface
func _read_now(c: Clock.ClockBase) -> int:
	return c.now_ms()


# REQ-0012-11: «єдиний інтерфейс Clock з провайдерами системний/фіксований/фейк, підмінюваний без редагування sim»
func _t_clock_providers() -> void:
	var fixed := Clock.FixedClock.new(NOW_1P8E12)
	var fake := Clock.FakeClock.new(NOW_1P8E12)
	var sys := Clock.SystemClock.new()
	var step := StepClock.new()
	var all: Array = [fixed, fake, sys, step]
	var not_base: Array = []
	var not_int: Array = []
	for p in all:
		var pv: Variant = p
		if not (pv is Clock.ClockBase):
			not_base.append(str(pv))
		elif typeof((pv as Clock.ClockBase).now_ms()) != TYPE_INT:
			not_int.append(str(pv))
	ok(not_base.is_empty(), "REQ-0012-11: Fixed, Fake, System and a test-defined provider are all ClockBase (one interface)")
	ok(not_int.is_empty(), "REQ-0012-11: now_ms() is a whole number (int64) for every provider — never a float")
	# the swap: one variable typed as the interface; the reader's code never changes
	var held: Clock.ClockBase = fixed
	var a: int = _read_now(held)
	held = Clock.FixedClock.new(NOW_1P8E12 + Clock.MS_PER_DAY)
	var b: int = _read_now(held)
	ok(a == NOW_1P8E12 and b - a == 86400000, "REQ-0012-11: swapping the provider changes now by exactly the difference between the two instants (MS_PER_DAY = 86 400 000)")
	ok(Clock.MS_PER_DAY == 86400000, "REQ-0012-11/69: MS_PER_DAY is 86 400 000 ms (the 24-h immunity of OD-24 is that many ms)")
	held = step
	var s1: int = _read_now(held)
	var s2: int = _read_now(held)
	ok(s2 - s1 == 1000, "REQ-0012-11: a provider defined outside clock.gd works through the same call (no registry, no edit of the reader)")
	# epoch semantics: UTC milliseconds since 1970 — 1.8e12 ms is exactly 08:00:00 UTC of its day
	ok(_read_now(fixed) % Clock.MS_PER_DAY == 8 * MS_PER_HOUR, "REQ-0012-11: 1.8e12 is UTC-ms since the epoch (≡ 08:00:00 UTC) — not seconds, not local time")
	# FixedClock: «фіксований (тести)» — it does not move, however often it is read
	var moved := false
	for i in 1000:
		if fixed.now_ms() != NOW_1P8E12:
			moved = true
	ok(not moved, "REQ-0012-11: FixedClock never moves (1000 reads, one value)")
	ok(Clock.FixedClock.new().now_ms() == 0, "REQ-0012-11: FixedClock() without an argument is the epoch (0), not 'now'")
	# FakeClock: «фейк (dev)» — settable, forwards AND backwards, exact in int64
	var fk := Clock.FakeClock.new(NOW_1P8E12)
	fk.advance(86400000)
	ok(fk.now_ms() == NOW_1P8E12 + 86400000, "REQ-0012-11: FakeClock.advance(+1 day)")
	fk.advance(0)
	ok(fk.now_ms() == NOW_1P8E12 + 86400000, "REQ-0012-11: FakeClock.advance(0) is a no-op")
	fk.advance(-2 * 86400000)
	ok(fk.now_ms() == NOW_1P8E12 - 86400000, "REQ-0012-11: FakeClock.advance(negative) winds the clock BACK (the REQ-0012-68 rewind scenario needs it)")
	for target in [0, -1, NOW_1P8E12, TWO53 + 1, INT64_MAX, INT64_MIN]:
		fk.set_ms(target)
		if fk.now_ms() != target:
			ok(false, "REQ-0012-11: FakeClock.set_ms(%d) reads back %d" % [target, fk.now_ms()])
	ok(fk.now_ms() == INT64_MIN, "REQ-0012-11: FakeClock.set_ms reads back exactly at the int64 extremes")
	fk.set_ms(TWO53 + 1)
	fk.advance(1)
	ok(fk.now_ms() == TWO53 + 2, "REQ-0012-11: FakeClock arithmetic is integer — 2^53+1 plus 1 is 2^53+2 (a float clock would stall at 2^53)")
	# SystemClock: «годинник пристрою» in UTC milliseconds — bracketed by the engine's own clock
	var t0: float = Time.get_unix_time_from_system()
	var n: int = sys.now_ms()
	var t1: float = Time.get_unix_time_from_system()
	ok(n >= int(floor(t0 * 1000.0)) and n <= int(ceil(t1 * 1000.0)), "REQ-0012-11: SystemClock.now_ms() is the device clock in MILLISECONDS (%d within [%d, %d])" % [n, int(floor(t0 * 1000.0)), int(ceil(t1 * 1000.0))])
	ok(n > 1600000000000 and n < 3000000000000, "REQ-0012-11: SystemClock reads like UTC-ms since 1970 (between 2020 and 2065)")
	var n2: int = sys.now_ms()
	ok(absi(n2 - n) < 2000, "REQ-0012-11: two consecutive SystemClock reads are within 2 s of each other (same clock, same unit)")


# REQ-0012-63 (the Clock part): no static/global state — ON→OFF→ON in one process shares nothing — and no ObjectDB
# growth from providers.
func _t_clock_state_isolated() -> void:
	var src: String = _read(CLOCK_HOME)
	var statics := RegEx.new()
	statics.compile("(?m)^\\s*static\\s+var\\b")
	ok(statics.search(src) == null, "REQ-0012-63: clock.gd declares no `static var` (no process-wide state)")
	ok(not ("class_name " in src) and not ("Engine.register_singleton" in src), "REQ-0012-63: clock.gd is neither a class_name global nor a registered singleton")
	var proj: String = _read("res://project.godot")
	ok(proj.find("clock.gd") < 0, "REQ-0012-63: clock.gd is not an autoload (AGENTS.md: no autoloads)")
	# two instances are independent; a fresh one does not inherit what another was set to
	var a := Clock.FakeClock.new(100)
	var b := Clock.FakeClock.new(100)
	a.advance(5000)
	ok(a.now_ms() == 5100 and b.now_ms() == 100, "REQ-0012-63: advancing one FakeClock does not move another")
	var c := Clock.FakeClock.new()
	ok(c.now_ms() == 0, "REQ-0012-63: a fresh FakeClock starts at 0, not at what a previous instance was set to")
	var m1 := Clock.Monotonic.new()
	var m2 := Clock.Monotonic.new()
	m1.observe(NOW_1P8E12)
	ok(m2.last_seen == 0 and m2.observe(5) == 5, "REQ-0012-63: two Monotonic guards share no last_seen")
	# providers are RefCounted: churn must not grow the object count (warm-up first so script loading is not counted)
	var warm: Array = [Clock.FixedClock.new(), Clock.FakeClock.new(), Clock.SystemClock.new(), Clock.Monotonic.new(), StepClock.new()]
	warm.clear()
	var before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in 2000:
		var f := Clock.FixedClock.new(i)
		var k := Clock.FakeClock.new(i)
		var s := Clock.SystemClock.new()
		var g := Clock.Monotonic.new()
		g.observe(f.now_ms() + k.now_ms() + (s.now_ms() & 1))
	var after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	ok(after == before, "REQ-0012-63: 8000 provider/guard instances created and dropped leave the object count unchanged (%d -> %d)" % [before, after])


# ---- wire: int64 UTC-ms as a JSON string (spec header R3) ----------------------------------------------------

# spec header R3: «ціле: UTC-мілісекунди епохи (int64, у JSON рядком, як курсори RNG)» — 1.8e12 -> string -> int without loss
func _t_clock_wire_int64() -> void:
	var samples: Array = [0, 1, -1, 86400000, NOW_1P8E12, NOW_1P8E12 + 123, TWO53 - 1, TWO53, TWO53 + 1, TWO53 + 2, 1 << 62, INT64_MAX - 1, INT64_MAX, INT64_MIN + 1, INT64_MIN]
	var sentinel := -4242424242   # no sample equals it, so a lazy `return fallback` cannot pass
	var digits := RegEx.new()
	digits.compile("^-?[0-9]+$")
	var bad_form: Array = []
	var bad_back: Array = []
	var bad_json: Array = []
	for v in samples:
		var w: Variant = Clock.to_wire(v)
		if typeof(w) != TYPE_STRING or digits.search(String(w)) == null or String(w) != str(v):
			bad_form.append(str(v))
		if Clock.from_wire(w, sentinel) != v:
			bad_back.append("%s -> %s -> %d" % [str(v), str(w), Clock.from_wire(w, sentinel)])
		var text: String = JSON.stringify({"saved_at": w, "n": 1})
		var parsed: Variant = JSON.parse_string(text)
		var back: Variant = (parsed as Dictionary).get("saved_at") if parsed is Dictionary else null
		if typeof(back) != TYPE_STRING or Clock.from_wire(back, sentinel) != v or text.find("\"%s\"" % str(v)) < 0:
			bad_json.append(str(v))
	ok(bad_form.is_empty(), "wire: to_wire(int) is a canonical decimal STRING (no exponent/point/grouping), == str(v) like the RNG cursors (bad: %s)" % str(bad_form))
	ok(bad_back.is_empty(), "wire: from_wire(to_wire(v)) == v at 0, ±1, 1.8e12, 2^53±1 and both int64 extremes (bad: %s)" % str(bad_back))
	ok(bad_json.is_empty(), "wire: the value survives JSON.stringify -> JSON.parse_string as a quoted string and decodes exactly (bad: %s)" % str(bad_json))
	ok(Clock.to_wire(1800000000000) == "1800000000000", "wire: 1.8e12 is written as the 13-digit string \"1800000000000\"")
	# the premise of the rule (informational — it is a fact about the engine, not about the product, so not an assertion):
	# a bare JSON NUMBER above 2^53 does not survive Godot's parser, a string does
	var lossy: Variant = JSON.parse_string(JSON.stringify({"t": TWO53 + 1}))
	var lossy_back: int = Clock.from_wire((lossy as Dictionary).get("t"), sentinel) if lossy is Dictionary else sentinel
	print("  note: premise of the string rule — 2^53+1 as a bare JSON number reads back as %d (%s)" % [lossy_back, "corrupted" if lossy_back != TWO53 + 1 else "survived on this engine build"])
	# a number that DID come through JSON as a float (an older/hand-edited save) is still read back exactly below 2^53
	ok(Clock.from_wire(1.8e12) == NOW_1P8E12 and Clock.from_wire(float(TWO53)) == TWO53, "wire: a float from JSON.parse_string decodes exactly while it is exactly representable (1.8e12, 2^53)")
	ok(typeof(Clock.from_wire("1800000000000")) == TYPE_INT and typeof(Clock.from_wire(1.8e12)) == TYPE_INT, "wire: from_wire always returns an int")
	# the same convention as the RNG cursors: every 64-bit generator state (negative ones included) round-trips
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var drift: Array = []
	for i in 300:
		rng.randi()
		var st: int = rng.state
		if Clock.from_wire(Clock.to_wire(st), sentinel) != st or Clock.to_wire(st) != str(st):
			drift.append(str(st))
	ok(drift.is_empty(), "wire: 300 full-range 64-bit RNG states round-trip and match the persistence.gd str(state) format (bad: %s)" % str(drift.slice(0, 3)))


# «NaN/inf/нечисло -> fallback» (contract) — and a corrupt save must never invent a time
func _t_clock_wire_rejects_garbage() -> void:
	var fb := -7
	var junk: Array = [NAN, INF, -INF, "", " ", "abc", "12abc", "1,800,000,000,000", "--5", "0x1F", "NaN", "nan", "inf", "-inf", "Infinity",
		null, true, false, [], {}, Vector2(1, 2), [1800000000000]]
	var accepted: Array = []
	for j in junk:
		if Clock.from_wire(j, fb) != fb:
			accepted.append("%s=%s" % [var_to_str(j), str(Clock.from_wire(j, fb))])
	ok(accepted.is_empty(), "wire: NaN, ±inf, empty/blank/non-numeric text, null, bool, containers -> the fallback (accepted: %s)" % str(accepted))
	# beyond int64 is not an int64: no wrap-around, no clamp to the extremes — a corrupt save must not become a far-future `now`
	var over: Array = ["9223372036854775808", "-9223372036854775809", "99999999999999999999", "18446744073709551615", "1" + "0".repeat(30),
		9.3e18, -9.3e18, 1.0e30, -1.0e30, 9223372036854775808.0]
	var wrapped: Array = []
	for o in over:
		if Clock.from_wire(o, fb) != fb:
			wrapped.append("%s=%s" % [str(o), str(Clock.from_wire(o, fb))])
	ok(wrapped.is_empty(), "wire: values outside int64 (strings and floats) -> the fallback, never wrapped or clamped (accepted: %s)" % str(wrapped))
	ok(Clock.from_wire("9223372036854775807", fb) == INT64_MAX and Clock.from_wire("-9223372036854775808", fb) == INT64_MIN, "wire: the int64 extremes themselves are valid")
	ok(Clock.from_wire("x", 12345) == 12345 and Clock.from_wire(NAN, -9) == -9 and Clock.from_wire("x", INT64_MAX) == INT64_MAX, "wire: the fallback argument is honoured (including a huge one)")
	ok(Clock.from_wire("x") == 0 and Clock.from_wire(null) == 0, "wire: the default fallback is 0")
	ok(Clock.from_wire("1800000000000", fb) == NOW_1P8E12 and Clock.from_wire("-5", fb) == -5, "wire: ordinary decimal strings still decode (garbage handling does not eat valid input)")


# ---- REQ-0012-68 helper: Monotonic ----------------------------------------------------------------------------

# REQ-0012-68 (helper): «now < last_seen_now не відновлює, не нараховує і не скорочує кулдаун» — observe(now)
# returns max(now, last_seen) and never lets the remembered value go down.
func _t_clock_monotonic() -> void:
	var mono := Clock.Monotonic.new()
	var mv: Variant = mono
	ok(not (mv is Clock.ClockBase), "REQ-0012-68: Monotonic is a guard around a clock, not a fourth provider")
	# the last_seen is restored from a save («last_seen_now», a wire string) and is the floor
	mono.last_seen = Clock.from_wire(Clock.to_wire(NOW_1P8E12), -1)
	ok(mono.observe(NOW_1P8E12 - MS_PER_HOUR) == NOW_1P8E12, "REQ-0012-68: a clock wound back 1 h below the restored last_seen is read as last_seen")
	ok(mono.observe(0) == NOW_1P8E12 and mono.observe(-5) == NOW_1P8E12 and mono.observe(INT64_MIN) == NOW_1P8E12, "REQ-0012-68: a clock at 0, negative or INT64_MIN never lowers it")
	ok(mono.last_seen == NOW_1P8E12, "REQ-0012-68: last_seen did not move on a rewound reading")
	ok(mono.observe(NOW_1P8E12) == NOW_1P8E12, "REQ-0012-68: an equal reading returns the same value")
	ok(mono.observe(NOW_1P8E12 + 1) == NOW_1P8E12 + 1 and mono.last_seen == NOW_1P8E12 + 1, "REQ-0012-68: a later reading advances last_seen to exactly that value")
	# exact beyond 2^53 (the whole point of int64 over float64 time)
	var big := Clock.Monotonic.new()
	big.observe(TWO53)
	ok(big.observe(TWO53 + 1) == TWO53 + 1 and big.observe(TWO53) == TWO53 + 1, "REQ-0012-68: ordering is exact at 2^53 — 2^53+1 is later than 2^53")
	var top := Clock.Monotonic.new()
	top.observe(INT64_MAX)
	ok(top.observe(NOW_1P8E12) == INT64_MAX, "REQ-0012-68: at INT64_MAX nothing is later")
	# property: against a reference running maximum, over a seeded random walk with forward steps, small rewinds and huge rewinds
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var m := Clock.Monotonic.new()
	var ref := 0
	var raw := NOW_1P8E12
	var prev := -1
	var wrong: Array = []
	for i in 3000:
		var step: int = rng.randi_range(-86400000, 86400000)
		if rng.randf() < 0.05:
			step = -rng.randi_range(0, 2000000000) * 500   # a violent rewind (up to ~1e12 ms)
		raw += step
		var got: int = m.observe(raw)
		ref = maxi(ref, raw)
		if got != ref or got < prev or m.last_seen != got or got < raw:
			wrong.append("step %d raw=%d got=%d ref=%d" % [i, raw, got, ref])
			if wrong.size() > 2:
				break
		prev = got
	ok(wrong.is_empty(), "REQ-0012-68: 3000 random observations == the running maximum; never below the previous result, never below `now`, last_seen == result (%s)" % str(wrong))
	# the exploit this exists for: wind the device clock back, act, return — the stored timestamp must not move EARLIER,
	# or the cooldown it starts would be shorter than the one it replaced
	var fake := Clock.FakeClock.new(NOW_1P8E12)
	var guard := Clock.Monotonic.new()
	var cooldown: int = 5 * 60 * 1000   # the 5-minute clone cooldown named in REQ-0012-28
	var start1: int = guard.observe(fake.now_ms())
	fake.advance(-MS_PER_HOUR)
	var start2: int = guard.observe(fake.now_ms())   # the action happens while the clock is wound back
	ok(start2 >= start1, "REQ-0012-68: an action taken after winding the clock back is stamped no earlier than the previous stamp (%d vs %d)" % [start2, start1])
	fake.set_ms(start1 + cooldown - 1)   # real time catches up to 1 ms before the first cooldown ends
	var remaining: int = (start2 + cooldown) - guard.observe(fake.now_ms())
	ok(remaining == 1, "REQ-0012-68: the cooldown is not shortened (nor stretched) by the rewind — 1 ms remains, got %d" % remaining)
	fake.advance(1)
	ok(guard.observe(fake.now_ms()) >= start2 + cooldown, "REQ-0012-68: and it ends exactly when the real cooldown ends")
