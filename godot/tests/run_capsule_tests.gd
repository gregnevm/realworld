# RealWorld — tests/run_capsule_tests.gd : spec 0010 (Основна капсула) — tests written FROM THE REQ TABLE,
# not from the code, by the qa-adversary role.
# Run: godot --headless --path godot -s res://tests/run_capsule_tests.gd
#
# WAVE S0 (this file today): REQ-0010-01 «при use_main_capsule=false запис регіону і world_hash
# байт-у-байт як до спеки» — pinned BEFORE any product code. The fixture godot/tests/fixtures/off_baseline.json
# was captured from the unmodified baseline by tests/capture_baseline.gd; the scenarios behind it live in
# tests/off_scenarios.gd. They deliberately cover the OFF branches the capsule waves will edit (raid damage
# on buildings, death + respawn, demolish, bench crafting, storage reach, base_center, the daily capsule at
# the day boundary, region travel, OSM relocation, a seeded verb fuzz) — NOT only the twin-ambient hash
# (critique 0010 #1). Also pinned: REQ-0010-02 (OFF part: no new key in the record), REQ-0010-60/61 (an
# old save loads as an OFF world, state intact) and a REQ-0010-92 tripwire (no wall-clock in the sim path).
#
# Strings that live OUTSIDE world_hash (sim.messages feed, flash_msg, panel labels) are «view, not sim» —
# no hash can see them, so the capsule/realtime waves would rewrite them silently (M5/F10). They are pinned
# BOTH as fixture scenarios (session_feed / flash_hints / capsule_panel_off) AND as literals in
# `_t_off_baseline_texts` (a re-captured fixture cannot launder a wording change past the literals).
#
# Later waves APPEND their `_t_*` tests below the `_t_off_*` block (config errors, landing, storage reach
# of the capsule, …); the `_t_off_*` pins must stay green after EVERY wave (D4) — they are the proof that
# flag OFF == the code before the spec.
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const Persistence = preload("res://scripts/persistence.gd")
const SessionScript = preload("res://scripts/session.gd")
const Scenarios = preload("res://tests/off_scenarios.gd")
const OffFixture = preload("res://tests/off_fixture.gd")
const OffChecker = preload("res://tests/off_checker.gd")

# run_determinism_tests.gd prints this on the baseline; the literal is asserted here as the REQ-0010-01 anchor
const WORLD_HASH_FINAL := "c4dbef44fe0f95d6"
# the S0 scenario count as captured on the baseline: 28 state scenarios + 3 string scenarios (session_feed /
# flash_hints / capsule_panel_off). A literal, not SCENARIOS.size(): dropping a scenario from BOTH the list and
# the fixture must not pass quietly, and adding one needs a re-capture on the BASELINE commit (see the header)
const SCENARIO_COUNT := 31

var chk: Variant = null   # OffChecker


func _init() -> void:
	print("== RealWorld capsule tests (spec 0010) ==")
	chk = OffChecker.new(self)
	_t_off_baseline_fixture_header()
	_t_off_baseline_world_hash_final()
	_t_off_baseline_record_schema()
	_t_off_baseline_hashes()
	_t_off_baseline_raids()
	_t_off_baseline_death_respawn()
	_t_off_baseline_texts()
	_t_off_baseline_build_storage()
	_t_off_baseline_capsule_travel()
	_t_off_baseline_fuzz()
	_t_off_baseline_save_schema()
	_t_off_legacy_saves()
	_t_off_flags_default_off()
	_t_no_wallclock_in_sim_path()
	chk.skip_banner()
	finish()


# ---------------------------------------------------------------------------------------------
# REQ-0010-01 (S0): the fixture itself is trustworthy
# ---------------------------------------------------------------------------------------------
func _t_off_baseline_fixture_header() -> void:
	var fx: Dictionary = chk.fixture
	ok(chk.has_fixture(), "REQ-0010-01: godot/tests/fixtures/off_baseline.json exists and has portable+numeric tiers")
	var commit: String = String(fx.get("baseline_commit", ""))
	var hex := RegEx.new()
	hex.compile("^[0-9a-f]{40}$")
	ok(hex.search(commit) != null, "REQ-0010-01: the fixture header records the baseline commit (40-hex git rev-parse HEAD): %s" % commit.left(12))
	ok(String(fx.get("platform", "")) != "" and String(fx.get("godot_version", "")) != "", "REQ-0010-01: the header records platform + Godot build (%s / %s)" % [String(fx.get("platform", "")), String(fx.get("godot_version", ""))])
	ok(String(fx.get("world_hash_final", "")) == WORLD_HASH_FINAL, "REQ-0010-01: the fixture's twin-ambient hash is the CI baseline WORLD_HASH_FINAL (%s)" % WORLD_HASH_FINAL)
	ok(int(fx.get("save_version", -1)) == 1 and SessionScript.SAVE_VERSION == 1, "REQ-0010-01/60: Session.SAVE_VERSION is still 1 (the baseline value)")
	ok((fx.get("portable", {}) as Dictionary).size() == Scenarios.SCENARIOS.size() and (fx.get("numeric", {}) as Dictionary).size() == Scenarios.SCENARIOS.size(),
		"REQ-0010-01: the fixture carries every scenario (%d) — a new scenario needs a re-capture on the BASELINE commit, not on top of product changes" % Scenarios.SCENARIOS.size())
	ok(Scenarios.SCENARIOS.size() == SCENARIO_COUNT and (fx.get("portable", {}) as Dictionary).size() == SCENARIO_COUNT,
		"REQ-0010-01/85: exactly %d baseline scenarios (28 state + session_feed/flash_hints/capsule_panel_off) — none dropped, none added without a baseline re-capture" % SCENARIO_COUNT)
	print("  note: ", String(chk.env.note))


# the determinism anchor: twin ambient 300 ticks Київ N=56 DT=0.1 == c4dbef44fe0f95d6, asserted as a LITERAL
func _t_off_baseline_world_hash_final() -> void:
	var cur: Dictionary = chk.scenario("twin_ambient_300")
	if String(chk.env.mode) == "hard":
		ok(String(cur.numeric.world_hash) == WORLD_HASH_FINAL, "REQ-0010-01: twin ambient 300 ticks (Київ, N=56, DT=0.1) world_hash == %s (literal; got %s)" % [WORLD_HASH_FINAL, String(cur.numeric.world_hash)])
	elif String(chk.env.mode) == "fail":
		ok(false, "REQ-0010-01: WORLD_HASH_FINAL literal cannot be checked on this CI platform (%s)" % String(chk.env.note))
	else:
		chk.skipped += 1
		print("  [SKIP] REQ-0010-01: WORLD_HASH_FINAL literal — %s" % String(chk.env.note))


# REQ-0010-01 «запис регіону не містить жодного нового ключа» + REQ-0010-02 (OFF half): the key sets
func _t_off_baseline_record_schema() -> void:
	chk.portable("twin_ambient_300", "REQ-0010-01 serialize_region/serialize_runtime key sets, world_hash = region + dyn")
	chk.portable("record_keys", "REQ-0010-01/02 record schema across OFF/inventory/catalog/osm worlds + module-state building records")
	chk.portable("spawn_presets", "REQ-0010-01 spawn presets: map, storage landing, base_center on the 5 presets (the canonical cell the capsule will replace)")
	var rec: Dictionary = (chk.scenario("twin_ambient_300") as Dictionary).portable
	var leaked: Array = []
	for k in (rec.region_keys as Array) + (rec.runtime_keys as Array):
		if String(k).contains("capsule") or String(k).contains("landing") or String(k).contains("orbit"):
			leaked.append(k)
	ok(leaked.is_empty(), "REQ-0010-02: an OFF record carries no main_capsule/landing key (%s)" % str(leaked))


func _t_off_baseline_hashes() -> void:
	chk.numeric("twin_ambient_300", "REQ-0010-01 twin ambient")
	chk.numeric("flat_100", "REQ-0010-01 flat pad 100 ticks")
	chk.portable("inventory_on_300", "REQ-0010-01 use_inventory ON")
	chk.numeric("inventory_on_300", "REQ-0010-01 use_inventory ON")
	chk.portable("catalog_on_300", "REQ-0010-01 use_catalog ON")
	chk.numeric("catalog_on_300", "REQ-0010-01 use_catalog ON")
	chk.portable("catalog_power_farm", "REQ-0010-01 catalogue power grid + grow zone")
	chk.numeric("catalog_power_farm", "REQ-0010-01 catalogue power grid + grow zone (power/farm/environment dday)")
	chk.numeric("gather_haul", "REQ-0010-01 gather -> auto-haul loop")


# the branches Threats.* / Director.* get edited in: forced raid on a walled base, Director.apply payload wave, patrol fight
func _t_off_baseline_raids() -> void:
	chk.portable("raid_forced_building", "REQ-0010-01 forced raid vs a walled base")
	chk.numeric("raid_forced_building", "REQ-0010-01 forced raid vs a walled base (damage_building + steal + wall hits)")
	chk.portable("raid_director_apply", "REQ-0010-01 Director.apply(raid) payload wave")
	chk.numeric("raid_director_apply", "REQ-0010-01 Director.apply(raid) payload wave + death/respawn mid-raid")
	chk.portable("director_grace", "REQ-0010-01 Director gating table (live incidents, grace days, forced apply)")
	chk.numeric("director_long", "REQ-0010-01 ~53 game days of the live storyteller (cadence, grace, dday scaling, death/respawn loop)")
	chk.portable("patrol_fight", "REQ-0010-01 patrol robots + turret")
	chk.numeric("patrol_fight", "REQ-0010-01 patrol robots + turret (damage_enemy loot rolls)")


# REQ-0010-07/96 are the ON behaviour; OFF must keep «новий виживальник у домі» exactly as shipped
func _t_off_baseline_death_respawn() -> void:
	for name in ["death_respawn", "death_respawn_inventory", "death_respawn_away"]:
		chk.portable(name, "REQ-0010-01 death -> respawn_new_pawn at base_center")
		chk.numeric(name, "REQ-0010-01 death -> respawn_new_pawn at base_center")
	chk.portable("hud_and_strings", "REQ-0010-40/85 OFF: HudModel snapshot schema + capsule/death/raid DATA slices + death-screen strings (panel labels / feed / flash: see _t_off_baseline_texts)")
	chk.numeric("hud_and_strings", "REQ-0010-85 OFF: HudModel snapshot content hash + invites")
	var lines: Array = (chk.scenario("death_respawn").portable.respawn_lines as Array)
	ok(lines == ["Новий виживальник прибув у поселення — навички з нуля."], "REQ-0010-40/85: the OFF respawn line is the shipped text (no capsule wording leaks into OFF)")


# REQ-0010-40/85 (M5/F10, D9): the OFF strings no hash can see — the landing/travel/continue feed, the «(4)» flash
# hints, the build refusals, the CapsulePanel labels. Fixture pins (all tiers) + literal anchors.
func _t_off_baseline_texts() -> void:
	chk.portable("session_feed", "REQ-0010-40/85 OFF Session.start landing feed (no clear) + travel + continue lines")
	chk.numeric("session_feed", "REQ-0010-40/85 OFF feed lines with the felt-°C figure")
	chk.portable("flash_hints", "REQ-0010-85 OFF flash hints «(4)» + build refusals (stock + inventory worlds)")
	chk.portable("capsule_panel_off", "REQ-0010-41/85 OFF CapsulePanel labels, buttons, intents, refusals (hand vm + real snapshot)")
	# --- literals: the shipped wording itself (a re-capture of the fixture must not be able to bless a change) ---
	var feed: Dictionary = chk.scenario("session_feed").portable
	var cold_stock: String = "warn|❄ Тут холодно (#°C): розпали багаття (9), а тоді обнеси клітинку стінами (1) з дверима (2) — у приміщенні тепло тримається."
	var cold_inv: String = "warn|❄ Тут холодно (#°C): постав багаття з хотбару (слот 1), потім стіни з дверима навколо — у приміщенні тепло тримається."
	for kind in ["stock", "inventory"]:
		var row: Dictionary = feed[kind]
		var plain: Array = row.start_plain
		ok(int(row.start_count) == 4 and plain.size() == 3 and (row.start_hints as Array).size() == 1, "REQ-0010-85 [%s]: the OFF landing writes 4 feed lines (3 plain + the climate hint), no clear" % kind)
		ok(String(plain[0]).begins_with("good|Висадка: Київ · біом "), "REQ-0010-40/85 [%s]: landing line 1 is «Висадка: Київ · біом …» (good)" % kind)
		ok(String(plain[1]).begins_with("|Клан: ") and String(plain[1]).ends_with(" · рейди від ворожих фракцій."), "REQ-0010-85 [%s]: landing line 2 is «Клан: … · рейди від ворожих фракцій.»" % kind)
		ok(String(plain[2]) == "|✉ Друзі надіслали інвайтів: 3 — капсула (V) долетить до них.", "REQ-0010-40/85 [%s]: landing line 3 is the shipped invite line («капсула (V)»: the daily capsule wording stays at OFF)" % kind)
		ok((row.start_hints as Array)[0] == (cold_inv if kind == "inventory" else cold_stock), "REQ-0010-40/85 [%s]: the spawn climate hint is the shipped «багаття» wording (OFF: not rewritten)" % kind)
		ok((row.away_plain as Array) == ["good|🛬 Нова місцевість: Львів · біом помірний."] and (row.back_plain as Array) == ["good|↩ Повернення в Київ."], "REQ-0010-85 [%s]: travel lines «🛬 Нова місцевість» / «↩ Повернення» unchanged" % kind)
		ok((row.continue_plain as Array) == ["good|▶ Продовжено: Київ · день 1."], "REQ-0010-85 [%s]: Continue says «▶ Продовжено: Київ · день 1.»" % kind)
	var fl: Dictionary = chk.scenario("flash_hints").portable
	ok((fl.full_storage.seen as Array) == ["📦 Склад повний — збудуй ще один склад (4)."], "REQ-0010-85: a full storage flashes «… збудуй ще один склад (4).» (the build-bar key hint, OFF)")
	ok((fl.no_storage.seen as Array) == ["Несеш максимум — збудуй склад (4)."], "REQ-0010-85: full hands with NO storage flash «Несеш максимум — збудуй склад (4).»")
	ok((fl.storage_unreachable.seen as Array) == ["Склад недосяжний — віднеси вантаж сам."] and (fl.walled_ring as Array) == [16, 16],
		"REQ-0010-05/85 (OFF anchor): a walled-in storage flashes «Склад недосяжний — віднеси вантаж сам.» (the storage-reach text the capsule-as-storage wave edits)")
	var br: Dictionary = fl.build_stock_world
	ok(String(br.occupied.flash) == "Тут не можна будувати." and String(br.off_map.flash) == "Тут не можна будувати." and String(br.unknown_kind.flash) == "Тут не можна будувати.",
		"REQ-0010-06 (OFF anchor): an occupied / off-map / unknown build refusal says «Тут не можна будувати.» (the text a capsule cell will sit next to)")
	ok(String(br.research_gated.flash).begins_with("🔒 Потребує дослідження: ") and String(br.unaffordable.flash).begins_with("Бракує: ") and String(br.affordable.flash) == "" and bool(br.affordable.placed),
		"REQ-0010-85: research-gated / unaffordable refusals keep their wording; an affordable build is silent and placed")
	ok(String(fl.inventory_world.no_item.flash) == "Нема «Стіна» у рюкзаку — скрафти (🎒)." and (fl.inventory_world.pack_full_gather.seen as Array) == ["🎒 Рюкзак повний — розклади на складі."],
		"REQ-0010-85: the inventory world's «Нема … у рюкзаку» / «Рюкзак повний» wording unchanged")
	var cp: Dictionary = chk.scenario("capsule_panel_off").portable
	ok((cp.headers as Array) == ["КАПСУЛА", "ІНВАЙТИ"] and String(cp.meta.menu_label) == "🚀 Капсула" and String(cp.meta.panel_id) == "capsule_bay" and int(cp.meta.hotkey) == KEY_V,
		"REQ-0010-41/85: the OFF panel keeps its headers, menu label «🚀 Капсула», id and the V hotkey")
	ok(String(cp.full_vm.status) == "Зарядів: 1 · радіус 100 км" and String(cp.drained_vm.status) == "Зарядів: 0 · радіус 100 км",
		"REQ-0010-41/85: the OFF panel shows «Зарядів: N · радіус R км» (charges/radius rows exist at OFF)")
	var rows: Array = cp.full_vm.rows
	ok(String(cp.full_vm.launch) == "🚀 Запуск за координатами" and String(rows[0].button) == "Прийняти" and String(rows[1].label) == "✉ Інший (—) → Пункт" and rows.size() == 4,
		"REQ-0010-85: «🚀 Запуск за координатами», invite rows «✉ кому (клан) → місце» (— for no clan), button «Прийняти», pool of 4")
	ok(bool(cp.drained_vm.launch_disabled) and bool(cp.drained_vm.rows[0].button_disabled) and not bool(cp.full_vm.launch_disabled), "REQ-0010-41: a spent charge disables the launch and the invite buttons")
	var verbs: Array = []
	for it in (cp.intents as Array):
		verbs.append(String(it.verb))
	ok(verbs == ["take_invite", "launch_capsule"], "REQ-0010-36 (OFF anchor): the panel emits take_invite / launch_capsule intents — and nothing for a hidden slot or a refused parse (%s)" % str(verbs))
	ok(String(cp.refusals.out_of_range).ends_with("⚠ Поза межами: широта ±90°, довгота ±180°.") and String(cp.refusals.empty).ends_with("⚠ Введи координати (напр. 50.4501, 30.5234)."),
		"REQ-0010-38/85: a bad coordinate shows the reason in words under the status line")
	var fresh: Dictionary = cp.real_session_fresh
	var spent: Dictionary = cp.real_session_spent
	ok(bool(fresh.status_is_sim_truth) and bool(spent.status_is_sim_truth) and int(fresh.sim_charges) == 1 and int(spent.sim_charges) == 0 and bool(spent.launch_disabled) and not bool(fresh.launch_disabled),
		"REQ-0010-41 + D9: the panel on a REAL session follows sim.capsule (1 charge -> launch -> 0 charges, launch disabled)")
	ok(int(fresh.sim_invites) == 3 and (fresh.rows as Array).filter(func(r: Dictionary) -> bool: return bool(r.visible)).size() == 3, "REQ-0010-85 + D9: the 3 seeded invites are the 3 visible rows")


# demolish / base_center / storage reach / bench crafting / OSM relocation
func _t_off_baseline_build_storage() -> void:
	for name in ["demolish_base_center", "storage_reach", "workbench_craft", "osm_overlay"]:
		chk.portable(name, "REQ-0010-01 build/storage verbs")
	chk.numeric("demolish_base_center", "REQ-0010-01 demolish/base_center")
	chk.numeric("workbench_craft", "REQ-0010-01 workbench plank loop")
	chk.numeric("osm_overlay", "REQ-0010-01 OSM overlay + after_map_change")
	var reach: Dictionary = chk.scenario("storage_reach").portable.reach_rows
	ok(bool(reach["2.5"].near) and bool(reach["2.49"].near) and not bool(reach["2.51"].near), "REQ-0010-05 (OFF anchor): stash/take reach is <= 2.5 tiles from a storage centre (the radius the capsule must reuse)")


# the daily capsule (spec 0002) — REQ-0010-41 says it is OFF-only; today it is the ONLY capsule
func _t_off_baseline_capsule_travel() -> void:
	chk.portable("capsule_day_transition", "REQ-0010-41 daily charge at the day boundary")
	chk.numeric("capsule_day_transition", "REQ-0010-41 daily charge at the day boundary (Київ)")
	chk.portable("capsule_launch", "REQ-0010-41 try_launch_capsule / capsule_can_reach / invites")
	chk.numeric("capsule_launch", "REQ-0010-41 try_launch_capsule km texts")
	chk.portable("travel_regions", "REQ-0010-01 Session.travel_to (arrive_region + load_region + apply_pawn)")
	chk.numeric("travel_regions", "REQ-0010-01 Session.travel_to hash chain")


func _t_off_baseline_fuzz() -> void:
	chk.numeric("fuzz_verbs", "REQ-0010-01 seeded verb fuzz (stock + inventory worlds)")


# ---------------------------------------------------------------------------------------------
# REQ-0010-02 (OFF) / REQ-0010-60: the save format of an OFF world
# ---------------------------------------------------------------------------------------------
func _t_off_baseline_save_schema() -> void:
	chk.portable("save_continue", "REQ-0010-02/60 Session.save_game key paths, version, store (stock/inventory/catalog worlds)")
	chk.numeric("save_continue", "REQ-0010-01 Session.save_game string sha256 (byte-for-byte)")
	var paths: Array = (chk.scenario("save_continue").portable.stock.key_paths as Array)
	var bad: Array = []
	for p in paths:
		var seg: String = String(p)
		if seg.contains("main_capsule") or seg.contains("landing") or seg.contains("orbit"):
			bad.append(seg)
	ok(bad.is_empty(), "REQ-0010-02/60: an OFF save has no main_capsule/landing/orbit key path (%s)" % str(bad.slice(0, 3)))


# REQ-0010-61: an old save (written by the BASELINE build) loads as an OFF world with its state intact
func _t_off_legacy_saves() -> void:
	var legacy: Dictionary = chk.fixture.get("legacy_saves", {})
	ok(legacy.size() == Scenarios.SAVE_KINDS.size(), "REQ-0010-61: the fixture carries a baseline save for every world kind (%s)" % str(legacy.keys()))
	for kind in Scenarios.SAVE_KINDS:
		if not legacy.has(kind):
			continue
		var entry: Dictionary = legacy[kind]
		var text: String = OffFixture.decode_legacy_text(entry)
		ok(text.length() == int(entry.raw_length) and text.sha256_text() == String(entry.sha256), "REQ-0010-61 [%s]: the stored baseline save decodes byte-exact (sha256 %s…)" % [kind, String(entry.sha256).left(10)])
		var cur: Dictionary = Scenarios.restore_legacy(text)
		var diffs: Array = []
		OffFixture.diff(cur.portable, entry.restore.portable, "", diffs)
		if not diffs.is_empty():
			print("    legacy [%s] portable mismatch:\n      %s" % [kind, OffFixture.summarize(diffs)])
		ok(diffs.is_empty(), "REQ-0010-61 [%s]: an old save restores as the SAME OFF world (flags, buildings, home, capsule, goals, day, regions)" % kind)
		var flags: Dictionary = cur.portable.get("flags", {})
		ok(bool(flags.get("future_flags_off", false)), "REQ-0010-60/61 [%s]: an old save leaves use_main_capsule/use_orbit/use_realtime OFF (not converted)" % kind)
		ok(bool(cur.portable.get("resave_paths_equal", false)), "REQ-0010-61 [%s]: re-saving the restored world adds/removes no key path (no silent migration)" % kind)
		match String(chk.env.mode):
			"hard":
				var nd: Array = []
				OffFixture.diff(cur.numeric, entry.restore.numeric, "", nd)
				if not nd.is_empty():
					print("    legacy [%s] numeric mismatch:\n      %s" % [kind, OffFixture.summarize(nd)])
				ok(nd.is_empty(), "REQ-0010-61 [%s]: old save -> world_hash after restore, re-save sha256 and 40 ticks of continue == baseline" % kind)
			"fail":
				ok(false, "REQ-0010-61 [%s]: numeric legacy pins cannot be verified on this CI platform (%s)" % [kind, String(chk.env.note)])
			_:
				chk.skipped += 1
				print("  [SKIP] REQ-0010-61 [%s] numeric legacy pins — %s" % [kind, String(chk.env.note)])


# A flag introduced by this spec must exist OFF by default: absent (baseline) or false on a fresh Sim/Session
func _t_off_flags_default_off() -> void:
	var sim: Variant = Sim.new()
	var sess: Variant = SessionScript.new()
	for f in Scenarios.FUTURE_FLAGS:
		var on_sim: bool = f in sim and bool(sim.get(f))
		var on_sess: bool = f in sess and bool(sess.get(f))
		ok(not on_sim and not on_sess, "REQ-0010-01: %s defaults to OFF on a fresh Sim and Session" % f)
	sim.dispose_farm()
	sim.dispose_power()


# REQ-0010-92 (tripwire): the sim path reads no wall-clock — time may only ENTER through Sim.set_clock (0012 D1).
# Scope = sim.gd, sim/, kernel/, persistence.gd, world_gen.gd: the files whose output feeds world_hash.
func _t_no_wallclock_in_sim_path() -> void:
	var re := RegEx.new()
	re.compile("(^|[^.\\w])(OS\\.get_(unix_time|datetime|time|ticks|system_time|date)\\w*|Time\\.get_\\w+)\\s*\\(")
	var files: Array = ["res://scripts/sim.gd", "res://scripts/persistence.gd", "res://scripts/world_gen.gd"]
	for dir_path in ["res://scripts/sim", "res://scripts/kernel"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				files.append(dir_path + "/" + f)
	var offenders: Array = []
	for path in files:
		var code: PackedStringArray = PackedStringArray()
		for line in FileAccess.get_file_as_string(String(path)).split("\n"):
			if not line.strip_edges().begins_with("#"):
				code.append(String(line).get_slice("#", 0))
		if re.search("\n".join(code)) != null:
			offenders.append(path)
	ok(files.size() > 20, "REQ-0010-92: the wall-clock tripwire scans the sim path (%d files)" % files.size())
	ok(offenders.is_empty(), "REQ-0010-92: no Time.* / OS.get_*time* call in the sim path (time enters only via Sim.set_clock)%s" % ("" if offenders.is_empty() else " — " + ", ".join(PackedStringArray(offenders))))
