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
