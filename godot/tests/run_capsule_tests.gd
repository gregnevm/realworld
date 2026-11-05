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
#
# WAVE 0010-W1a (appended below the `_t_off_*` block): flag/config errors, landing, storage role, deletion bans.
# REQ-0010-01 (OFF isolation), 03/59 (config errors), 04/73 (canonical cell + landing), 05 (storage role),
# 06 (refusals), 41 sim part (no daily charge), 75 (no deletion path: scan + guarded sites + fuzz), 77 (stash
# refusal reason). Expectations come from the spec rows and the owner's decisions, NOT from the code: where a
# row leaves a point open (capacity number TBD П10, the metric behind «відстань» in REQ-73) the test pins only
# what every reading agrees on. A red test here is a finding, not a test bug.
#
# WAVE 0010-W1b (appended after the W1a block): respawn + seams + save/hash + the now-input + Session.
# REQ-0010-02 (flag persists / old save -> OFF), 07/08/74 (respawn next to the capsule at every level, ring expansion,
# buildings untouched), 09 (respawn_anchor / respawn_source stub / Session.home reference / Continue), 10 + 96 (sim
# part: death changes nothing in the capsule, the bag mechanism is the spec-0009 one, no «новий виживальник у домі»),
# 34 (the flag does not shift director/env/threat cursors), 35 + 82 (CURRENT record fields move the hash; int64
# times survive JSON as strings), 41 (Session part), 60 (flag frozen, refused loads mutate nothing), 61 (an old OFF
# save stays OFF), 83 (save between death and respawn; an ON save without its capsule is refused explicitly),
# 92 (time enters only through Sim.set_clock; monotone; not hashed), 98 (ONE landing seam). Fields of the record
# that later waves add (invested W2a; immune_until / token / raid cursor W3a) are NOT attacked here — they do not exist yet.
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const Persistence = preload("res://scripts/persistence.gd")
const SessionScript = preload("res://scripts/session.gd")
const Scenarios = preload("res://tests/off_scenarios.gd")
const OffFixture = preload("res://tests/off_fixture.gd")
const OffChecker = preload("res://tests/off_checker.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")
const Upkeep = preload("res://scripts/sim/upkeep.gd")
const Director = preload("res://scripts/sim/director.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const KernelBalance = preload("res://scripts/kernel/balance.gd")
const InputCtl = preload("res://scripts/ui/input_controller.gd")
const InputVerbs = preload("res://scripts/ui/input_verbs.gd")

const PAD_N := 16   # the flat grass pad of the W1a tests (spawn (8,8), like the S0 `_flat` pad)

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
	# --- wave 0010-W1a ---
	_t_config_errors()
	_t_off_isolation_from_on()
	_t_land_deterministic()
	_t_land_edges()
	_t_canon_shift()
	_t_canon_shift_end_to_end()
	_t_storage_reach()
	_t_stash_full_reason()
	_t_capsule_refusals()
	_t_capsule_not_craftable()
	_t_no_daily_charge()
	_t_no_delete_paths_scan()
	_t_region_changes_keep_capsule_consistent()
	_t_no_eternal_siege()
	_t_capsule_fuzz()
	# --- wave 0010-W1b ---
	_t_flag_persist()
	_t_flag_locked()
	_t_old_save_stays_off()
	_t_respawn_position()
	_t_respawn_blocked_rings()
	_t_respawn_seams()
	_t_death_bag_and_texts()
	_t_session_on()
	_t_save_continue_on()
	_t_restore_parity_live()
	_t_save_refusals()
	_t_single_landing()
	_t_stream_cursors()
	_t_hash_fields()
	_t_clock_input()
	_t_no_wallclock_alias_proof()
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


# =============================================================================================
# WAVE 0010-W1a — helpers
# =============================================================================================
func _dispose(s: Variant) -> void:
	if s != null:
		s.dispose_farm()
		s.dispose_power()


func _gen(lat: float, lon: float, n: int = Scenarios.N) -> Dictionary:
	return WorldGen.generate_map(lat, lon, n)


# flags are set BEFORE new_game (REQ-0010-02); `hint` off: the climate hint is a message, not world state
func _sim_with(m: Dictionary, inventory: bool, catalog: bool, capsule: bool) -> Variant:
	var s: Variant = Sim.new()
	s.use_inventory = inventory
	s.use_catalog = catalog
	s.use_main_capsule = capsule
	s.new_game(m, false)
	return s


func _pad_map(n: int, spawn: Vector2i, fill: int = WorldGen.GRASS) -> Dictionary:
	var tiles: PackedByteArray = PackedByteArray()
	tiles.resize(n * n)
	tiles.fill(fill)
	return {"n": n, "tiles": tiles, "nodes": {}, "spawn": spawn, "lat": Scenarios.LAT, "lon": Scenarios.LON}


# every cell WATER except the listed ones (grass): the deterministic-order probes of REQ-0010-73
func _island_map(n: int, spawn: Vector2i, cells: Array) -> Dictionary:
	var m: Dictionary = _pad_map(n, spawn, WorldGen.WATER)
	var tiles: PackedByteArray = m.tiles
	for c in cells:
		var v: Vector2i = c
		tiles[v.y * n + v.x] = WorldGen.GRASS
	m.tiles = tiles
	return m


func _mute(s: Variant) -> void:
	s.balance = KernelBalance.Balance.new()
	for cat in s.balance.category_weight:
		s.balance.category_weight[cat] = 0.0


func _topup(s: Variant) -> void:
	s.player.hp = 100.0
	s.player.hunger = 100.0
	s.player.rest = 100.0


# the quiet ON world: 16x16 grass pad, spawn (8,8) -> capsule on (8,8); summer noon, director + patrols muted
func _on_pad() -> Variant:
	var s: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), true, true, true)
	_quiet(s)
	return s


func _quiet(s: Variant) -> void:
	s.time.day = 195
	s.time.frac = 0.5
	s.weather = &"clear"
	s.patrol.next = 1.0e9
	_mute(s)
	s.messages.clear()


func _cap_tile(s: Variant) -> Vector2i:
	var t: Array = (s.main_capsule as Dictionary).get("tile", [-1, -1])
	return Vector2i(int(t[0]), int(t[1]))


func _cap_count(s: Variant) -> int:
	var c: int = 0
	for b in s.buildings:
		if String(b.kind) == MainCapsule.KIND:
			c += 1
	return c


func _hero_cell(s: Variant) -> Vector2i:
	return Vector2i(int(floor(float(s.player.px))), int(floor(float(s.player.py))))


# the REQ-0010-75 invariants of a live ON world: ONE capsule building, on the recorded tile, in bgrid, level in 0..5
# (OD-56), the ledger (when present) made of non-negative integers. "" == fine
func _cap_problem(s: Variant, tile: Vector2i) -> String:
	if (s.main_capsule as Dictionary).is_empty():
		return "main_capsule record is empty"
	if _cap_tile(s) != tile:
		return "tile moved %s -> %s" % [str(tile), str(_cap_tile(s))]
	if _cap_count(s) != 1:
		return "%d capsule buildings (want exactly 1)" % _cap_count(s)
	var bb: Variant = s.bgrid.get(tile.y * int(s.n) + tile.x, null)
	if bb == null or String(bb.kind) != MainCapsule.KIND:
		return "bgrid lost the capsule cell"
	var lvl: int = int(s.main_capsule.get("level", 0))
	if lvl < 0 or lvl > 5:
		return "level %d outside 0..5" % lvl
	var inv: Dictionary = s.main_capsule.get("invested", {})
	for k in inv:
		for res in (inv[k] as Dictionary):
			if int((inv[k] as Dictionary)[res]) < 0:
				return "negative ledger entry %s/%s" % [str(k), str(res)]
	return ""


# the record and the building list must AGREE (no dangling record, no orphan building) — weaker than _cap_problem
func _cap_consistent(s: Variant) -> bool:
	var has_rec: bool = not (s.main_capsule as Dictionary).is_empty()
	if not has_rec:
		return _cap_count(s) == 0
	return _cap_problem(s, _cap_tile(s)) == ""


func _world_sig(s: Variant) -> String:
	return var_to_str([s.map, s.n, s.buildings, s.bgrid, s.stock, s.regions, s.main_capsule, s.invites, s.bags, s.enemies, s.player, s.capsule, s.time])


func _wood_total(s: Variant) -> int:
	return Inventory.count(s, "wood") + int(s.res_amount("wood"))


func _texts(s: Variant) -> Array:
	var out: Array = []
	for m in s.messages:
		out.append(String(m.text))
	return out


# a passable, resource-free cell at least `min_d` (Chebyshev) from `from` — the hero's «away from base» spot
func _far_cell(s: Variant, from: Vector2i, min_d: int) -> Vector2i:
	for y in range(int(s.n)):
		for x in range(int(s.n)):
			if maxi(absi(x - from.x), absi(y - from.y)) >= min_d and not s.is_blocked(x, y) and not (s.map.nodes as Dictionary).has(y * int(s.n) + x):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _kill(sim: Variant) -> void:
	var guard: int = 0
	while not sim.dead and guard < 40:
		HeroHealth.damage(sim, 500.0, "тест")
		sim.update(Scenarios.DT)
		guard += 1


# ambient run on a real map: the world_hash after `ticks` (hero topped up, like the twin-ambient pin)
func _ambient_hash(lat: float, lon: float, capsule: bool, ticks: int) -> String:
	var s: Variant = _sim_with(_gen(lat, lon), capsule, capsule, capsule)
	for t in ticks:
		s.update(Scenarios.DT)
		_topup(s)
	var h: String = Persistence.world_hash(s)
	_dispose(s)
	return h


func _gd_files(dir_path: String, out: Array) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	for sub in d.get_directories():
		_gd_files(dir_path + "/" + sub, out)


# =============================================================================================
# REQ-0010-03 / REQ-0010-59: ON without use_inventory / without use_catalog -> explicit config error, NO world
# =============================================================================================
func _t_config_errors() -> void:
	var fresh: Variant = Sim.new()
	var fresh_sig: String = _world_sig(fresh)
	var cases: Array = [
		{"name": "REQ-0010-03 ON + use_inventory=false", "inv": false, "cat": true},
		{"name": "REQ-0010-59 ON + use_catalog=false", "inv": true, "cat": false},
		{"name": "REQ-0010-03/59 ON + neither prerequisite", "inv": false, "cat": false},
	]
	for c in cases:
		var label: String = String(c["name"])
		var s: Variant = Sim.new()
		s.use_inventory = bool(c["inv"])
		s.use_catalog = bool(c["cat"])
		s.use_main_capsule = true
		ok(bool(s.use_main_capsule), "%s: the flag can be set before new_game" % label)
		s.new_game(_gen(Scenarios.LAT, Scenarios.LON))
		ok(s.config_error != &"", "%s: new_game reports an explicit configuration error (config_error=%s)" % [label, str(s.config_error)])
		ok(_world_sig(s) == fresh_sig, "%s: NO world is created — map/buildings/stock/regions/player are exactly those of a never-started Sim" % label)
		ok(_cap_count(s) == 0 and (s.main_capsule as Dictionary).is_empty() and not s.has_building("storage"),
			"%s: neither a capsule nor an OFF-style storage fallback appears" % label)
		# the failed start leaves the Sim reusable: fix the prerequisites, start again, the capsule lands
		s.use_inventory = true
		s.use_catalog = true
		ok(bool(s.use_main_capsule), "%s: a failed start does not lock or reset the flag" % label)
		s.new_game(_gen(Scenarios.LAT, Scenarios.LON), false)
		ok(s.config_error == &"" and _cap_count(s) == 1 and _cap_problem(s, _cap_tile(s)) == "", "%s: after fixing the config the SAME Sim starts a normal ON world (error cleared, one capsule)" % label)
		_dispose(s)
	# controls: OFF needs neither prerequisite; ON with both is a normal world
	var off: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), false, false, false)
	ok(off.config_error == &"" and off.has_building("storage") and (off.main_capsule as Dictionary).is_empty() and _cap_count(off) == 0,
		"REQ-0010-03/59 control: flag OFF without inventory/catalog is a normal OFF world (storage, no capsule, no error)")
	var good: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	ok(good.config_error == &"" and _cap_count(good) == 1 and not good.has_building("storage"),
		"REQ-0010-03/59 control: ON with inventory+catalog -> one capsule, no error, and no extra starter storage building")
	_dispose(off)
	_dispose(good)
	_dispose(fresh)


# =============================================================================================
# REQ-0010-01: an ON world must leave no residue in a later OFF world (statics/caches), and the flag is frozen after start
# =============================================================================================
func _t_off_isolation_from_on() -> void:
	var before: String = _ambient_hash(Scenarios.LAT, Scenarios.LON, false, 120)
	var on: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	for t in 60:
		on.update(Scenarios.DT)
		_topup(on)
	_dispose(on)
	var after: String = _ambient_hash(Scenarios.LAT, Scenarios.LON, false, 120)
	ok(before == after, "REQ-0010-01: an OFF world built AFTER an ON world hashes exactly like one built before it (no static/cache residue): %s == %s" % [before, after])
	# at OFF the capsule vocabulary does not exist
	var off: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, false)
	ok((off.main_capsule as Dictionary).is_empty(), "REQ-0010-01: OFF keeps main_capsule empty")
	ok((off.building_def(MainCapsule.KIND) as Dictionary).is_empty(), "REQ-0010-01: at OFF the capsule kind is not a building def (an unknown kind stays unknown)")
	ok(not off.has_storage_cap(MainCapsule.KIND), "REQ-0010-01: at OFF the capsule kind is not a storage")
	ok(off.has_building("storage"), "REQ-0010-01: OFF still lands the classic storage building")
	var leaked: Array = []
	for k in Persistence.serialize_region(off):
		if String(k).contains("capsule"):
			leaked.append(k)
	ok(leaked.is_empty(), "REQ-0010-01: the OFF region record carries no capsule key (%s)" % str(leaked))
	_dispose(off)
	# the flag is frozen once the world started (REQ-0010-02/60): flipping must not half-convert a running world
	var f1: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), false, false, false)
	var f2: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), false, false, false)
	f1.use_main_capsule = true
	ok(not bool(f1.use_main_capsule), "REQ-0010-02/60: an OFF world cannot be flipped ON after new_game")
	for t in 100:
		f1.update(Scenarios.DT)
		_topup(f1)
		f2.update(Scenarios.DT)
		_topup(f2)
	ok(Persistence.world_hash(f1) == Persistence.world_hash(f2) and _cap_count(f1) == 0 and (f1.main_capsule as Dictionary).is_empty(),
		"REQ-0010-01/60: the refused flip leaves the OFF world byte-for-byte on the untouched twin's trajectory")
	_dispose(f1)
	_dispose(f2)
	var g: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	g.use_main_capsule = false
	ok(bool(g.use_main_capsule) and _cap_problem(g, _cap_tile(g)) == "", "REQ-0010-02/60: an ON world cannot be flipped OFF after new_game (capsule intact)")
	_dispose(g)


# =============================================================================================
# REQ-0010-04: exactly ONE level-0 capsule on a cell that is a pure function of (lat, lon); twins agree
# =============================================================================================
func _land_checks(label: String, m: Dictionary, s: Variant) -> Vector2i:
	var n: int = int(s.n)
	var tile: Vector2i = _cap_tile(s)
	var idx: int = tile.y * n + tile.x
	ok(_cap_count(s) == 1 and _cap_problem(s, tile) == "", "%s: exactly ONE capsule building, matching the record (%s)" % [label, _cap_problem(s, tile)])
	ok(int(s.main_capsule.get("level", -1)) == 0, "%s: lands at level 0" % label)
	ok(tile.x >= 0 and tile.y >= 0 and tile.x < n and tile.y < n, "%s: tile %s is on the map" % [label, str(tile)])
	ok(not WorldGen.is_terrain_blocked(int(m.tiles[idx])) and not (m.nodes as Dictionary).has(idx), "%s: the cell is neither water/rock nor a resource node" % label)
	ok(s.base_center() == tile, "%s: base_center() is the capsule cell" % label)
	ok(not s.build_valid(tile.x, tile.y), "%s: the capsule cell is not buildable" % label)
	var storages: int = 0
	for b in s.buildings:
		if s.has_storage_cap(String(b.kind)):
			storages += 1
	ok(storages == 1, "%s: the capsule is the ONLY storage-capable building at the start (no second container)" % label)
	var hero: Vector2i = _hero_cell(s)
	ok(hero != tile and not s.is_blocked(hero.x, hero.y), "%s: the hero starts on a passable cell, not inside the impassable capsule cell (hero %s)" % [label, str(hero)])
	var sp: Vector2i = m.spawn
	var sp_free: bool = not WorldGen.is_terrain_blocked(int(m.tiles[sp.y * n + sp.x])) and not (m.nodes as Dictionary).has(sp.y * n + sp.x)
	if sp_free:
		ok(tile == sp, "%s: spec §2 п.7 — the cell is canon(_pick_spawn): a free spawn %s IS the capsule cell (got %s)" % [label, str(sp), str(tile)])
	return tile


func _t_land_deterministic() -> void:
	var rows: Dictionary = {}
	for pr in GameData.SPAWN_PRESETS:
		var lat: float = float(pr.lat)
		var lon: float = float(pr.lon)
		var m: Dictionary = _gen(lat, lon)
		var s: Variant = _sim_with(m, true, true, true)
		var label: String = "REQ-0010-04 [%s]" % String(pr.name)
		var tile: Vector2i = _land_checks(label, m, s)
		var h0: String = Persistence.world_hash(s)
		for t in 60:
			s.update(Scenarios.DT)
			_topup(s)
		ok(_cap_problem(s, tile) == "", "%s: the capsule is still there, same cell, after 60 ticks (%s)" % [label, _cap_problem(s, tile)])
		rows[String(pr.name)] = {"tile": tile, "h0": h0, "h60": Persistence.world_hash(s)}
		_dispose(s)
	# twin pass in the REVERSE order on fresh maps: same lat/lon -> same cell and same world_hash (no call-history dependence)
	var presets: Array = (GameData.SPAWN_PRESETS as Array).duplicate()
	presets.reverse()
	for pr in presets:
		var m2: Dictionary = _gen(float(pr.lat), float(pr.lon))
		var s2: Variant = _sim_with(m2, true, true, true)
		var name: String = String(pr.name)
		var row: Dictionary = rows[name]
		ok(_cap_tile(s2) == row.tile, "REQ-0010-04 twin [%s]: same coordinates -> the same cell (%s == %s)" % [name, str(_cap_tile(s2)), str(row.tile)])
		ok(Persistence.world_hash(s2) == row.h0, "REQ-0010-04 twin [%s]: same coordinates -> the same world_hash right after landing" % name)
		for t in 60:
			s2.update(Scenarios.DT)
			_topup(s2)
		ok(Persistence.world_hash(s2) == row.h60, "REQ-0010-04 twin [%s]: ... and after 60 ticks" % name)
		_dispose(s2)
	# the cell is a function of the MAP too: other map sizes of the same coordinate still give a valid single capsule
	for nn in [32, 112]:
		var mm: Dictionary = _gen(Scenarios.LAT, Scenarios.LON, nn)
		var sm: Variant = _sim_with(mm, true, true, true)
		_land_checks("REQ-0010-04 [Київ n=%d]" % nn, mm, sm)
		_dispose(sm)
	# presets must not all collapse onto one cell (the cell really is derived from the world, not a constant)
	var distinct: Dictionary = {}
	for k in rows:
		distinct[str(rows[k].tile)] = true
	ok(distinct.size() >= 2, "REQ-0010-04: the 5 presets do not all land on one hard-coded cell (%d distinct)" % distinct.size())
	# the same ambient run twice at ON: identical hash (the determinism spine at ON)
	var a: String = _ambient_hash(Scenarios.LAT, Scenarios.LON, true, 300)
	var b: String = _ambient_hash(Scenarios.LAT, Scenarios.LON, true, 300)
	ok(a == b, "REQ-0010-04: twin ambient 300 ticks (Київ, ON) -> identical world_hash (%s)" % a)


func _t_land_edges() -> void:
	# a capsule in the map CORNER: the search ring and the hero's ring leave the map; nothing may crash or step outside
	var corner: Variant = _sim_with(_pad_map(8, Vector2i(0, 0)), true, true, true)
	ok(_cap_tile(corner) == Vector2i(0, 0) and _cap_problem(corner, Vector2i(0, 0)) == "", "REQ-0010-04 edge: spawn in the map corner -> the capsule sits on (0,0)")
	var hc: Vector2i = _hero_cell(corner)
	ok(hc.x >= 0 and hc.y >= 0 and hc.x < 8 and hc.y < 8 and hc != Vector2i(0, 0) and not corner.is_blocked(hc.x, hc.y), "REQ-0010-04 edge: the hero in the corner case is on the map, on a passable cell, not in the capsule (hero %s)" % str(hc))
	_dispose(corner)
	# an island: every neighbour of the capsule is water, the only dry cell is two steps away
	var isl: Variant = _sim_with(_island_map(PAD_N, Vector2i(8, 8), [Vector2i(8, 8), Vector2i(10, 8)]), true, true, true)
	ok(_cap_tile(isl) == Vector2i(8, 8), "REQ-0010-04/73 island: the capsule keeps the free spawn cell")
	var hi: Vector2i = _hero_cell(isl)
	ok(not isl.is_blocked(hi.x, hi.y) and hi != Vector2i(8, 8), "REQ-0010-06/74 island: with the whole ring blocked the hero still starts on a passable cell, never in water/capsule (hero %s)" % str(hi))
	_dispose(isl)
	# re-landing on an existing capsule must not mint a second one (REQ-0010-04 «рівно одну», REQ-0010-98 landing seam)
	var s: Variant = _on_pad()
	var tile: Vector2i = _cap_tile(s)
	for target in [Vector2i(3, 3), Vector2i(8, 8), Vector2i(15, 15)]:
		MainCapsule.landing(s, WorldGen.canon_coord(Scenarios.LAT, Scenarios.LON), target)
		ok(_cap_problem(s, tile) == "", "REQ-0010-04: landing(%s) again keeps exactly one capsule on the same tile (%s)" % [str(target), _cap_problem(s, tile)])
		var h: Vector2i = _hero_cell(s)
		ok(h != tile and not s.is_blocked(h.x, h.y), "REQ-0010-04: ... and the hero is on a passable cell afterwards (%s)" % str(h))
	_dispose(s)


# =============================================================================================
# REQ-0010-73: canonical cell shift — fixed deterministic order (increasing distance, ties by (y, x)), stable
# =============================================================================================
func _t_canon_shift() -> void:
	var sp: Vector2i = Vector2i(8, 8)
	# Each case lists the ONLY dry cells of an otherwise-water map. The picks below hold under any metric for
	# «відстань» (Chebyshev/Euclid/Manhattan): the candidates tie, or one is strictly nearer — so the test pins
	# the spec's rule («за зростанням відстані, tie-break (y, x)») without inventing which metric the spec means.
	var cases: Array = [
		{"name": "spawn itself is dry", "cells": [sp, Vector2i(7, 8)], "want": sp},
		{"name": "tie left/right -> smaller x", "cells": [Vector2i(7, 8), Vector2i(9, 8)], "want": Vector2i(7, 8)},
		{"name": "tie up/down -> smaller y", "cells": [Vector2i(8, 7), Vector2i(8, 9)], "want": Vector2i(8, 7)},
		{"name": "tie on the anti-diagonal -> smaller y", "cells": [Vector2i(9, 7), Vector2i(7, 9)], "want": Vector2i(9, 7)},
		{"name": "tie on a row below -> smaller x", "cells": [Vector2i(7, 9), Vector2i(9, 9)], "want": Vector2i(7, 9)},
		{"name": "nearer beats farther", "cells": [Vector2i(9, 8), Vector2i(5, 5)], "want": Vector2i(9, 8)},
		{"name": "nearer beats farther (reversed listing)", "cells": [Vector2i(5, 5), Vector2i(9, 8)], "want": Vector2i(9, 8)},
		{"name": "tie (+3,0)/(0,+3) -> smaller y", "cells": [Vector2i(11, 8), Vector2i(8, 11)], "want": Vector2i(11, 8)},
		{"name": "tie (0,-3)/(+3,0) -> smaller y", "cells": [Vector2i(8, 5), Vector2i(11, 8)], "want": Vector2i(8, 5)},
		{"name": "tie on the diagonal -> smaller y", "cells": [Vector2i(4, 4), Vector2i(12, 12)], "want": Vector2i(4, 4)},
		{"name": "four axis cells at distance 2 -> top one", "cells": [Vector2i(8, 6), Vector2i(6, 8), Vector2i(10, 8), Vector2i(8, 10)], "want": Vector2i(8, 6)},
		{"name": "single far dry cell", "cells": [Vector2i(15, 15)], "want": Vector2i(15, 15)},
	]
	for c in cases:
		var m: Dictionary = _island_map(PAD_N, sp, c["cells"])
		var got: Vector2i = MainCapsule.canon_cell(m)
		var again: Vector2i = MainCapsule.canon_cell(m)
		ok(got == c["want"], "REQ-0010-73 [%s]: canon cell is %s (got %s)" % [String(c["name"]), str(c["want"]), str(got)])
		ok(got == again, "REQ-0010-73 [%s]: stable on repeat" % String(c["name"]))
	# a blocked spawn on an otherwise open pad shifts to a cell next to it, whatever blocks it
	var sp_idx: int = sp.y * PAD_N + sp.x
	var blockers: Array = ["water", "rock", "node", "occupied"]
	for kind in blockers:
		var m2: Dictionary = _pad_map(PAD_N, sp)
		var occupied: Dictionary = {}
		match String(kind):
			"water":
				var tw: PackedByteArray = m2.tiles
				tw[sp_idx] = WorldGen.WATER
				m2.tiles = tw
			"rock":
				var tr: PackedByteArray = m2.tiles
				tr[sp_idx] = WorldGen.ROCK
				m2.tiles = tr
			"node":
				m2.nodes[sp_idx] = {"kind": "tree", "amount": 5}
			"occupied":
				occupied[sp_idx] = true
		var got2: Vector2i = MainCapsule.canon_cell(m2, occupied)
		ok(got2 != sp and maxi(absi(got2.x - sp.x), absi(got2.y - sp.y)) == 1, "REQ-0010-73 [%s on spawn]: the cell shifts to the ring right next to it (got %s)" % [String(kind), str(got2)])
		ok(MainCapsule.canon_cell(m2, occupied) == got2, "REQ-0010-73 [%s on spawn]: stable on repeat" % String(kind))
	# the whole 3x3 around the spawn is water: the nearest dry cell is two steps away (never inside the water ring)
	var ringed: Dictionary = _pad_map(PAD_N, sp)
	var rt: PackedByteArray = ringed.tiles
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			rt[(sp.y + dy) * PAD_N + sp.x + dx] = WorldGen.WATER
	ringed.tiles = rt
	var gr: Vector2i = MainCapsule.canon_cell(ringed)
	ok(maxi(absi(gr.x - sp.x), absi(gr.y - sp.y)) == 2, "REQ-0010-73: with the 3x3 under water the capsule lands at distance 2, not inside it (got %s)" % str(gr))
	# `occupied` is a SET: insertion order must not matter
	var plain: Dictionary = _pad_map(PAD_N, sp)
	var occ_a: Dictionary = {}
	occ_a[sp_idx] = true
	occ_a[sp_idx + 1] = true
	occ_a[sp_idx - PAD_N] = true
	var occ_b: Dictionary = {}
	occ_b[sp_idx - PAD_N] = true
	occ_b[sp_idx + 1] = true
	occ_b[sp_idx] = true
	ok(MainCapsule.canon_cell(plain, occ_a) == MainCapsule.canon_cell(plain, occ_b), "REQ-0010-73: the shift does not depend on the insertion order of the occupied set")


func _t_canon_shift_end_to_end() -> void:
	var cells: Array = []
	var hashes: Array = []
	for run in 2:
		var m: Dictionary = _gen(Scenarios.LAT, Scenarios.LON)
		var sp: Vector2i = m.spawn
		var n: int = int(m.n)
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = sp + d
			m.nodes[c.y * n + c.x] = {"kind": "tree", "amount": 20}
		var s: Variant = _sim_with(m, true, true, true)
		var tile: Vector2i = _cap_tile(s)
		cells.append(tile)
		hashes.append(Persistence.world_hash(s))
		ok(tile != sp and _cap_problem(s, tile) == "", "REQ-0010-73 e2e [run %d]: trees on the spawn cell and its 4 neighbours -> the capsule lands elsewhere, one capsule, consistent (%s)" % [run, _cap_problem(s, tile)])
		ok(not (m.nodes as Dictionary).has(tile.y * n + tile.x), "REQ-0010-73 e2e [run %d]: the capsule does not sit on a resource node" % run)
		var h: Vector2i = _hero_cell(s)
		ok(h != tile and not s.is_blocked(h.x, h.y), "REQ-0010-73 e2e [run %d]: the hero starts on a passable cell (%s)" % [run, str(h)])
		_dispose(s)
	ok(cells[0] == cells[1] and hashes[0] == hashes[1], "REQ-0010-73 e2e: the shift is stable — two games on the same blocked map agree on the cell and on world_hash (%s / %s)" % [str(cells), str(hashes)])
	# nowhere to land (all water): an explicit refusal, never a capsule in the water and never a half-alive ON world
	var sw: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8), WorldGen.WATER), true, true, true)
	ok(_cap_count(sw) == 0 and (sw.main_capsule as Dictionary).is_empty() and sw.buildings.is_empty(), "REQ-0010-73/04: on a map with no dry cell no capsule is placed (in particular none in the water)")
	ok(sw.config_error != &"", "REQ-0010-04: ... and the start fails EXPLICITLY (config_error=%s) instead of yielding an ON world without its capsule" % str(sw.config_error))
	_dispose(sw)


# =============================================================================================
# REQ-0010-05: the capsule IS the storage — same reach as a storage building, no second container
# =============================================================================================
func _probe_reach(s: Variant, center: Vector2, dir: Vector2, d: float) -> Dictionary:
	s.player.px = center.x + dir.x * d
	s.player.py = center.y + dir.y * d
	s.player.inv = Inventory.empty_slots()
	s.stock[s.res_key("wood")] = 50
	Inventory.add(s, "wood", 7)
	var total_before: int = _wood_total(s)
	var near: bool = Inventory.near_storage(s)
	var stash: Dictionary = Inventory.stash_all(s)
	var stock_after_stash: int = int(s.res_amount("wood"))
	var pack_after_stash: int = Inventory.count(s, "wood")
	var take: Dictionary = Inventory.take_from_storage(s, "wood", 3)
	return {"near": near, "stash_ok": bool(stash.ok), "stock_after_stash": stock_after_stash, "pack_after_stash": pack_after_stash,
		"take_ok": bool(take.ok), "taken": int(take.get("taken", 0)), "conserved": _wood_total(s) == total_before}


func _t_storage_reach() -> void:
	var s: Variant = _on_pad()
	var cap: Vector2i = _cap_tile(s)
	var cap_c: Vector2 = Vector2(cap.x + 0.5, cap.y + 0.5)
	ok(int(s.storage_cap()) > 0, "REQ-0010-05/77: the capsule-only world has a positive storage capacity (%d)" % int(s.storage_cap()))
	# the reference: a REAL storage building far from the capsule, in the same world
	Inventory.add(s, "bld:storage", 1)
	s.try_build("storage", 2, 2)
	ok(s.bgrid.has(2 * PAD_N + 2) and String(s.bgrid[2 * PAD_N + 2].kind) == "storage", "REQ-0010-05 setup: a reference storage building stands at (2,2)")
	var sto_c: Vector2 = Vector2(2.5, 2.5)
	var reach: float = Inventory.STASH_REACH
	var axis: Array = [Vector2(1, 0), Vector2(0, 1)]
	var dists: Array = [1.0, 2.0, 2.49, 2.5, 2.51, 3.0]
	for dir in axis:
		for d in dists:
			var dd: float = float(d)
			var rc: Dictionary = _probe_reach(s, cap_c, dir, dd)
			var rs: Dictionary = _probe_reach(s, sto_c, dir, dd)
			ok(bool(rc.near) == (dd <= reach), "REQ-0010-05: capsule — stash/take reach: %.2f tiles along %s is %s (reach %.2f)" % [dd, str(dir), "near" if bool(rc.near) else "far", reach])
			ok(var_to_str(rc) == var_to_str(rs), "REQ-0010-05: capsule == storage building at %.2f tiles along %s (same near/stash/take/conservation)" % [dd, str(dir)])
	for dd2 in [2.49, 2.51]:
		var diag: Vector2 = Vector2(1, 1).normalized()
		var rcd: Dictionary = _probe_reach(s, cap_c, diag, float(dd2))
		ok(bool(rcd.near) == (float(dd2) <= reach), "REQ-0010-05: capsule reach on the diagonal at %.2f is a true radius (near=%s)" % [float(dd2), str(rcd.near)])
	# behaviour at the two ends: next to the capsule stash+take work and conserve; out of reach they refuse and move nothing
	var near_row: Dictionary = _probe_reach(s, cap_c, Vector2(1, 0), 1.0)
	ok(bool(near_row.stash_ok) and int(near_row.stock_after_stash) == 57 and int(near_row.pack_after_stash) == 0, "REQ-0010-05: next to the capsule stash_all moves the whole pack stack into the one stock (50+7)")
	ok(bool(near_row.take_ok) and int(near_row.taken) == 3 and bool(near_row.conserved), "REQ-0010-05: next to the capsule take_from_storage returns the requested amount; nothing created or lost")
	var far_row: Dictionary = _probe_reach(s, cap_c, Vector2(1, 0), 3.0)
	ok(not bool(far_row.stash_ok) and int(far_row.stock_after_stash) == 50 and int(far_row.pack_after_stash) == 7 and not bool(far_row.take_ok) and bool(far_row.conserved),
		"REQ-0010-05: out of reach stash/take refuse and change nothing")
	# no new storage: the capsule record holds no container of its own; capacity is the SAME seam as a storage building's
	var bad_keys: Array = []
	for k in s.main_capsule:
		if ["stock", "storage", "items", "inventory", "bag", "bags", "safe_stock", "container", "slots"].has(String(k)):
			bad_keys.append(k)
	ok(bad_keys.is_empty(), "REQ-0010-05: the capsule record has no container of its own (%s) — the storage role reuses the sim stock" % str(bad_keys))
	var off_pad: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), true, true, false)
	var on_pad: Variant = _on_pad()
	ok(int(on_pad.storage_cap()) == int(off_pad.storage_cap()), "REQ-0010-05/77: ON capsule-only capacity == OFF storage-only capacity (%d == %d) — no new capacity number invented (П10 stays open)" % [int(on_pad.storage_cap()), int(off_pad.storage_cap())])
	# the storage-link perk (pay from storages within LINK_REACH once gather >= LINK_SKILL) reads the same capability:
	# the capsule links at exactly the radius a storage building does
	for who in [on_pad, off_pad]:
		who.stock.clear()
		who.stock[who.res_key("wood")] = 30
		who.player.inv = Inventory.empty_slots()
		who.player.skills.gather = Inventory.LINK_SKILL
	var link_on: Dictionary = {}
	var link_off: Dictionary = {}
	var off_center: Vector2 = Vector2(9.5, 8.5)   # the OFF pad's classic storage lands on (spawn.x+1, spawn.y)
	for d in [0.0, 5.0, 9.99, 10.0, 10.01, 10.5]:
		link_on[str(d)] = Inventory.can_pay(on_pad, {"wood": 5}, Vector2(cap_c.x + float(d), cap_c.y))
		link_off[str(d)] = Inventory.can_pay(off_pad, {"wood": 5}, Vector2(off_center.x + float(d), off_center.y))
	ok(var_to_str(link_on) == var_to_str(link_off), "REQ-0010-05: the storage-link radius around the capsule equals the one around a storage building (%s vs %s)" % [str(link_on), str(link_off)])
	ok(bool(link_on["10.0"]) and not bool(link_on["10.5"]), "REQ-0010-05: ... and is a real radius (links at %.1f, not at 10.5)" % Inventory.LINK_REACH)
	var stock_before: int = int(on_pad.stock_total())
	on_pad.player.px = cap_c.x + 1.0
	on_pad.player.py = cap_c.y
	on_pad.player.inv = Inventory.empty_slots()
	Inventory.add(on_pad, "wood", 9)
	Inventory.stash_all(on_pad)
	ok(int(on_pad.stock_total()) == stock_before + 9, "REQ-0010-05: stashing at the capsule grows the ONE shared stock (no side container): %d -> %d" % [stock_before, int(on_pad.stock_total())])
	_dispose(off_pad)
	_dispose(on_pad)
	# the storage role also covers the auto-eat path: hunger<55 within the storage radius eats from the stock
	var e: Variant = _on_pad()
	Inventory.add(e, "bld:storage", 1)
	e.try_build("storage", 2, 2)
	var eat_rows: Dictionary = {}
	for who in ["capsule", "storage"]:
		for d in [2.1, 2.3]:
			e.player.inv = Inventory.empty_slots()
			e.player.hunger = 40.0
			e.player.eat_cd = 0.0
			e.stock[e.res_key("food")] = 18
			var c: Vector2 = cap_c if who == "capsule" else sto_c
			e.player.px = c.x + float(d)
			e.player.py = c.y
			e.update(Scenarios.DT)
			eat_rows["%s@%s" % [who, str(d)]] = int(e.res_amount("food")) < 18
	ok(bool(eat_rows["capsule@2.1"]) == bool(eat_rows["storage@2.1"]) and bool(eat_rows["capsule@2.3"]) == bool(eat_rows["storage@2.3"]), "REQ-0010-05: the hero eats from the stock near the capsule exactly as near a storage building (%s)" % str(eat_rows))
	ok(bool(eat_rows["capsule@2.1"]) and not bool(eat_rows["capsule@2.3"]), "REQ-0010-05: ... eats inside the storage radius, not outside it (%s)" % str(eat_rows))
	_dispose(e)
	_dispose(s)


# =============================================================================================
# REQ-0010-77 (reason only): stash_all at a FULL storage is refused with a reason; nothing moves
# =============================================================================================
func _t_stash_full_reason() -> void:
	var s: Variant = _on_pad()
	var cap: Vector2i = _cap_tile(s)
	var cap_c: Vector2 = Vector2(cap.x + 0.5, cap.y + 0.5)
	s.player.px = cap_c.x + 1.0
	s.player.py = cap_c.y
	var limit: int = int(s.storage_cap())
	# nothing to stash into a non-full storage: the plain «empty pack» refusal
	s.stock.clear()
	s.stock[s.res_key("wood")] = 10
	s.player.inv = Inventory.empty_slots()
	var empty_pack: Dictionary = Inventory.stash_all(s)
	ok(not bool(empty_pack.ok) and String(empty_pack.get("msg", "")) != "", "REQ-0010-77: an empty pack at a non-full storage is refused with a reason (%s)" % String(empty_pack.get("msg", "")))
	# exactly full
	s.stock.clear()
	s.stock[s.res_key("wood")] = limit
	s.player.inv = Inventory.empty_slots()
	Inventory.add(s, "wood", 7)
	var hash_before: String = Persistence.world_hash(s)
	var sig_before: String = var_to_str([s.stock, s.player.inv])
	var full: Dictionary = Inventory.stash_all(s)
	ok(not bool(full.ok) and int(full.get("moved", 0)) == 0, "REQ-0010-77: stash_all into a full storage is refused, nothing moved")
	ok(String(full.get("msg", "")) != "", "REQ-0010-77: ... with a non-empty reason in words")
	ok(String(full.get("msg", "")) != String(empty_pack.get("msg", "")), "REQ-0010-77/D9: ... and the reason differs from the «empty pack» one — the player is told WHY (full), not that there is nothing to stash (%s)" % String(full.get("msg", "")))
	ok(var_to_str([s.stock, s.player.inv]) == sig_before and Persistence.world_hash(s) == hash_before, "REQ-0010-77: the refused stash changes neither stock, pack nor world_hash")
	# take still works when the storage is full (room in the pack)
	var take: Dictionary = Inventory.take_from_storage(s, "wood", 2)
	ok(bool(take.ok), "REQ-0010-77: a full storage still lets you take from it")
	# partial fit: 3 free units, 7 in the pack -> 3 move, 4 stay, nothing lost, never over capacity
	s.stock.clear()
	s.stock[s.res_key("wood")] = limit - 3
	s.player.inv = Inventory.empty_slots()
	Inventory.add(s, "wood", 7)
	var total: int = _wood_total(s)
	var part: Dictionary = Inventory.stash_all(s)
	ok(bool(part.ok) and int(part.moved) == 3 and Inventory.count(s, "wood") == 4 and int(s.stock_total()) == limit, "REQ-0010-77: a storage with 3 free units takes exactly 3 of 7 (moved %s, pack %d, stock %d/%d)" % [str(part.get("moved")), Inventory.count(s, "wood"), int(s.stock_total()), limit])
	ok(_wood_total(s) == total, "REQ-0010-77: ... conserving the total")
	var again: Dictionary = Inventory.stash_all(s)
	ok(not bool(again.ok) and Inventory.count(s, "wood") == 4 and String(again.get("msg", "")) != String(empty_pack.get("msg", "")), "REQ-0010-77: the very next stash is refused as FULL, pack keeps its 4")
	# a big pack against a small gap: never overflows the capacity
	s.stock.clear()
	s.stock[s.res_key("wood")] = limit - 10
	s.player.inv = Inventory.empty_slots()
	Inventory.add(s, "wood", 40)
	var tot2: int = _wood_total(s)
	Inventory.stash_all(s)
	ok(int(s.stock_total()) <= limit and _wood_total(s) == tot2, "REQ-0010-77: 40 wood into a gap of 10 never exceeds capacity and loses nothing (stock %d/%d)" % [int(s.stock_total()), limit])
	_dispose(s)


# =============================================================================================
# REQ-0010-06: demolish / deconstruct / damage-to-removal are refused with a reason; the cell is closed to building
# =============================================================================================
func _t_capsule_refusals() -> void:
	var s: Variant = _on_pad()
	var cap: Vector2i = _cap_tile(s)
	var idx: int = cap.y * PAD_N + cap.x
	var kinds: Array = ["wall", "door", "floor", "campfire", "torch", "storage", "bed", "workbench", MainCapsule.KIND]
	s.player.inv = Inventory.empty_slots()
	for k in kinds:
		Inventory.add(s, Inventory.BLD + String(k), 1)
	for k in kinds:
		ok(Inventory.count(s, Inventory.BLD + String(k)) == 1, "REQ-0010-06 setup: one %s item in the pack" % String(k))
	# 1. building on the capsule cell, every kind (incl. a second capsule)
	var cnt: int = s.buildings.size()
	for k in kinds:
		s.flash_msg = ""
		s.try_build(String(k), cap.x, cap.y)
		ok(s.buildings.size() == cnt and String(s.bgrid[idx].kind) == MainCapsule.KIND, "REQ-0010-06: try_build(%s) on the capsule cell is refused, the cell still holds the capsule" % String(k))
		ok(Inventory.count(s, Inventory.BLD + String(k)) == 1, "REQ-0010-06: ... and the refused %s item is NOT consumed" % String(k))
		ok(String(s.flash_msg) != "", "REQ-0010-06/D9: ... and the player is told why (flash: %s)" % String(s.flash_msg))
	# 2. a second capsule on a free cell
	s.try_build(MainCapsule.KIND, cap.x + 4, cap.y)
	ok(_cap_count(s) == 1 and not s.bgrid.has(cap.y * PAD_N + cap.x + 4) and Inventory.count(s, Inventory.BLD + MainCapsule.KIND) == 1, "REQ-0010-04/06: a second Основна капсула cannot be built anywhere (one capsule, the item is not consumed)")
	# 3. the ban is narrow: the neighbours stay buildable
	s.try_build("wall", cap.x + 1, cap.y)
	ok(s.bgrid.has(cap.y * PAD_N + cap.x + 1) and String(s.bgrid[cap.y * PAD_N + cap.x + 1].kind) == "wall", "REQ-0010-06: only the capsule cell is closed — the neighbour cell takes a wall")
	# 4. demolish the capsule: refused, with a reason, nothing changes (pack item, stock, hash)
	var h0: String = Persistence.world_hash(s)
	var pack0: int = Inventory.count(s, Inventory.BLD + MainCapsule.KIND)
	var r: Dictionary = s.demolish(cap.x, cap.y)
	ok(not bool(r.get("ok", true)) and String(r.get("msg", "")) != "", "REQ-0010-06: demolish(capsule) is refused with a reason (%s)" % String(r.get("msg", "")))
	ok(_cap_problem(s, cap) == "" and Persistence.world_hash(s) == h0 and Inventory.count(s, Inventory.BLD + MainCapsule.KIND) == pack0,
		"REQ-0010-06: ... the refusal has NO side effect (no capsule item minted into the pack, no refund, same world_hash)")
	# the «last storage» guard must not be what saves it: with another storage standing the capsule is STILL refused
	s.try_build("storage", cap.x + 3, cap.y + 3)
	ok(s.has_building("storage"), "REQ-0010-06 setup: a second storage building stands")
	var r2: Dictionary = s.demolish(cap.x, cap.y)
	ok(not bool(r2.get("ok", true)) and _cap_problem(s, cap) == "", "REQ-0010-06: with another storage present the capsule is still undemolishable")
	var rw: Dictionary = s.demolish(cap.x + 1, cap.y)
	ok(bool(rw.get("ok", false)), "REQ-0010-06: ... while the neighbouring wall is demolished normally")
	# 5. the touch/remove verb goes through the router: same refusal, reason shown to the player (D9)
	var ic: Variant = InputCtl.InputController.new()
	InputVerbs.install(ic)
	s.flash_msg = ""
	ic.dispatch(&"deconstruct", {"x": cap.x, "y": cap.y}, {"sim": s})
	ok(_cap_problem(s, cap) == "" and String(s.flash_msg) != "", "REQ-0010-06: the «deconstruct» verb on the capsule is refused and the reason reaches the player (flash: %s)" % String(s.flash_msg))
	s.flash_msg = ""
	ic.dispatch(&"build", {"kind": "wall", "x": cap.x, "y": cap.y}, {"sim": s})
	ok(_cap_problem(s, cap) == "", "REQ-0010-06: the «build» verb on the capsule cell leaves the capsule intact")
	# 6. repair of the capsule costs nothing and changes nothing
	var stock0: String = var_to_str(s.stock)
	var rep: Dictionary = Upkeep.repair(s, cap.x, cap.y)
	ok(not bool(rep.get("ok", true)) and var_to_str(s.stock) == stock0, "REQ-0010-06: repair(capsule) is refused and charges nothing")
	# 7. damage-to-removal: even absurd damage, with and without theft, neither removes it nor touches the stock
	var b: Dictionary = s.bgrid[idx]
	var stock1: String = var_to_str(s.stock)
	s._damage_building(b, 1.0e9, true)
	s._damage_building(b, 1.0e9, false)
	ok(_cap_problem(s, cap) == "" and float(b.hp) > 0.0, "REQ-0010-06/75: 2e9 damage leaves the capsule standing with positive hp (hp=%s)" % str(b.hp))
	ok(var_to_str(s.stock) == stock1, "REQ-0010-77: a raid hit on the capsule steals nothing from the stock")
	# 8. a hit on a NEIGHBOUR is still ordinary (the immunity is the capsule's, not the neighbourhood's)
	var nb: Variant = s.bgrid.get(cap.y * PAD_N + cap.x + 3 + 3 * PAD_N, null)
	if nb != null:
		var hp_before: float = float(nb.hp)
		s._damage_building(nb, 1.0, false)
		ok(float(nb.hp) < hp_before, "REQ-0010-06: ordinary buildings next to the capsule still take damage")
	_dispose(s)


# REQ-0010-04/06 (derived): a second capsule must not be minted by the crafting menu either — a free, unplaceable item is
# a resource out of nothing (REQ-0010-66 ethos) and a false affordance
func _t_capsule_not_craftable() -> void:
	var s: Variant = _on_pad()
	s._place_building("workbench", 4, 8, -1)
	s.player.px = 5.5
	s.player.py = 8.5
	s.player.inv = Inventory.empty_slots()
	Inventory.add(s, "wood", 30)
	Inventory.add(s, "stone", 30)   # a wall costs wood AND stone: the control must be payable
	var control: Dictionary = Inventory.craft_building(s, "wall")
	ok(bool(control.get("ok", false)), "REQ-0010-04/06 control: a legitimate hand-craft (wall) works in this setup (%s)" % String(control.get("msg", "")))
	var r: Dictionary = Inventory.craft_building(s, MainCapsule.KIND)
	ok(not bool(r.get("ok", false)), "REQ-0010-04/06: crafting «Основна капсула» next to a workbench is refused (the capsule is a landmark, never an item)")
	ok(Inventory.count(s, Inventory.BLD + MainCapsule.KIND) == 0, "REQ-0010-04/06: ... and no capsule item appears in the pack for free (count %d)" % Inventory.count(s, Inventory.BLD + MainCapsule.KIND))
	_dispose(s)


# =============================================================================================
# REQ-0010-41 (sim part): at ON the daily charge is never granted and the daily launch is «недоступно»
# =============================================================================================
func _cross_days(s: Variant, days: int) -> int:
	var crossed: int = 0
	for d in days:
		var day0: int = int(s.time.day)
		var guard: int = 0
		while int(s.time.day) == day0 and guard < 3000:
			s.update(Scenarios.DT)
			_topup(s)
			guard += 1
		if int(s.time.day) > day0:
			crossed += 1
	return crossed


func _t_no_daily_charge() -> void:
	var on: Variant = _on_pad()
	var off: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), true, true, false)
	_quiet(off)
	for s in [on, off]:
		s.capsule.charges = 0
		s.capsule.last_day = int(s.time.day)
	var day_on: int = int(on.capsule.last_day)
	ok(_cross_days(off, 1) == 1, "REQ-0010-41 control: the OFF world crosses a day boundary")
	ok(int(off.capsule.charges) == GameData.CAPSULE_DAILY_CHARGES, "REQ-0010-41 control: at OFF the daily charge IS granted at the boundary (the mechanism the test probes works)")
	ok(_cross_days(on, 3) == 3, "REQ-0010-41: the ON world crosses 3 day boundaries")
	ok(int(on.capsule.charges) == 0, "REQ-0010-41: at ON no daily charge is granted across 3 days (charges stay 0, got %d)" % int(on.capsule.charges))
	ok(int(on.capsule.last_day) == day_on, "REQ-0010-41: grant_daily_capsule is not invoked at ON (its last_day bookkeeping is untouched)")
	var daily_lines: Array = _texts(on).filter(func(t: String) -> bool: return t.contains("Щоденна капсула"))
	ok(daily_lines.is_empty(), "REQ-0010-41: no «Щоденна капсула готова» line at ON (%s)" % str(daily_lines))
	# the launch itself: refused with «недоступно» for ANY input, even with a charge in hand; no side effect
	on.capsule.charges = 1
	var hash0: String = Persistence.world_hash(on)
	var targets: Array = [
		[Scenarios.LAT + 0.1, Scenarios.LON, "Близько"],
		[Scenarios.LAT2, Scenarios.LON2, "Далеко"],
		[999.0, 999.0, "Нісенітниця"],
		[Scenarios.LAT, Scenarios.LON, ""],
	]
	for t in targets:
		var res: Dictionary = on.try_launch_capsule(float(t[0]), float(t[1]), String(t[2]))
		ok(not bool(res.get("ok", false)) and String(res.get("msg", "")).to_lower().contains("недоступно"), "REQ-0010-41: try_launch_capsule(%s) at ON -> refused with «недоступно» (%s)" % [String(t[2]), String(res.get("msg", ""))])
	ok(int(on.capsule.charges) == 1 and Persistence.world_hash(on) == hash0, "REQ-0010-41: refused launches spend no charge and leave world_hash untouched")
	ok(_texts(on).filter(func(t: String) -> bool: return t.contains("Капсула запущена")).is_empty(), "REQ-0010-41: no «Капсула запущена» line")
	# the second route to the same launch: accepting an invite
	on.add_invite({"id": "i1", "inviter": "Друг", "clan": "К", "name": "Місце", "lat": Scenarios.LAT + 0.1, "lon": Scenarios.LON, "allow_receive": true, "radius_km": 100.0}, true)
	var acc: Dictionary = on.accept_invite("i1")
	ok(not bool(acc.get("ok", false)) and on.invites.size() == 1 and int(on.capsule.charges) == 1, "REQ-0010-41: accept_invite at ON cannot bypass the refusal (invite kept, no charge spent)")
	# control: the very same inputs DO launch at OFF
	off.capsule.charges = 1
	var ctl: Dictionary = off.try_launch_capsule(Scenarios.LAT + 0.1, Scenarios.LON, "Близько")
	ok(bool(ctl.get("ok", false)), "REQ-0010-41 control: the same near target launches at OFF — the ON refusal is the flag's doing, not bad input")
	_dispose(on)
	_dispose(off)


# =============================================================================================
# REQ-0010-75: no path may remove the capsule — (a) every code site that removes/resets buildings is on a reviewed list,
# (b) the list's behavioural guards, (c) a seeded fuzz of random verbs with the invariants
# =============================================================================================
func _t_no_delete_paths_scan() -> void:
	var re_rm: RegEx = RegEx.new()
	re_rm.compile("_remove_building\\(|\\.buildings\\.(erase|remove_at|clear|pop_back|pop_front|pop_at)\\(|(^|[^\\w.])buildings\\.(erase|remove_at|clear|pop_back|pop_front|pop_at)\\(|(^|[^\\w.])bgrid\\.(erase|clear)\\(|\\.bgrid\\.(erase|clear)\\(|(^|[^\\w.])(\\.)?buildings\\s*=\\s*\\[|(^|[^\\w.])(\\.)?bgrid\\s*=\\s*\\{")
	var re_fn: RegEx = RegEx.new()
	re_fn.compile("^\\s*(?:static\\s+)?func\\s+(\\w+)")
	var files: Array = []
	_gd_files("res://scripts", files)
	var sites: Dictionary = {}
	for path in files:
		var cur_fn: String = ""
		for line in FileAccess.get_file_as_string(String(path)).split("\n"):
			var code: String = String(line).get_slice("#", 0)
			var mf: RegExMatch = re_fn.search(code)
			if mf != null:
				cur_fn = mf.get_string(1)
			if re_rm.search(code) != null:
				sites["%s::%s" % [String(path).trim_prefix("res://scripts/"), cur_fn]] = true
	# Reviewed sites (REQ-0010-75 «перелік шляхів видалення»). Each is guarded by one of the behavioural tests of this
	# file: _remove_building (the primitive) / demolish / damage_building -> _t_capsule_refusals; arrive_region + load_region
	# (region swaps) -> _t_region_changes_keep_capsule_consistent; after_map_change (OSM relocation) -> same test.
	var reviewed: Dictionary = {
		"sim.gd::_remove_building": true, "sim.gd::demolish": true, "sim.gd::arrive_region": true, "sim.gd::load_region": true,
		"sim.gd::after_map_change": true, "sim/threats.gd::damage_building": true,
	}
	var unknown: Array = []
	for k in sites:
		if not reviewed.has(k):
			unknown.append(k)
	unknown.sort()
	ok(files.size() > 40, "REQ-0010-75: the deletion-path scan covers the whole scripts/ tree (%d files)" % files.size())
	ok(unknown.is_empty(), "REQ-0010-75: no UNREVIEWED code path removes/resets buildings — a new one must be reviewed against the capsule ban%s" % ("" if unknown.is_empty() else " — " + ", ".join(PackedStringArray(unknown))))
	var vanished: Array = []
	for k in reviewed:
		if not sites.has(k):
			vanished.append(k)
	ok(vanished.is_empty(), "REQ-0010-75: the reviewed list is current (a removed site must be dropped from it, with its guard test)%s" % ("" if vanished.is_empty() else " — " + ", ".join(PackedStringArray(vanished))))


func _t_region_changes_keep_capsule_consistent() -> void:
	# arrive_region (a capsule/travel landing in ANOTHER region) wipes buildings/bgrid: the capsule must not be left as a
	# dangling record pointing at a building that no longer exists (and base_center() at a cell of the old region)
	var s: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	var tile: Vector2i = _cap_tile(s)
	var lat0: float = float(s.map.lat)
	s.arrive_region(_gen(Scenarios.LAT2, Scenarios.LON2), s.extract_pawn())
	var refused: bool = is_equal_approx(float(s.map.lat), lat0)
	ok(refused or _cap_consistent(s), "REQ-0010-75: arrive_region at ON either refuses or keeps record and building in agreement — record=%s buildings(capsule)=%d base_center=%s" % [str((s.main_capsule as Dictionary).has("tile")), _cap_count(s), str(s.base_center())])
	ok(refused or (s.base_center() != tile) == (_cap_count(s) == 0), "REQ-0010-75: after arrive_region base_center() points at the capsule only if the capsule exists in this region")
	_dispose(s)
	# the OSM relocation (after_map_change) moves the hero to map.spawn — which IS the capsule cell at ON
	var o: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	var t2: Vector2i = _cap_tile(o)
	o.after_map_change()
	ok(_cap_problem(o, t2) == "", "REQ-0010-75: after_map_change (OSM relocation) keeps the capsule (%s)" % _cap_problem(o, t2))
	var h: Vector2i = _hero_cell(o)
	ok(not o.is_blocked(h.x, h.y), "REQ-0010-06: after_map_change does not drop the hero INTO the impassable capsule cell (hero %s, capsule %s)" % [str(h), str(t2)])
	# and the hero can still move out (the stuck-hero check): a path from where the hero stands to a free cell two steps away
	var goal: Vector2i = Vector2i(h.x + 2, h.y)
	if o.is_blocked(goal.x, goal.y):
		goal = Vector2i(h.x, h.y + 2)
	var path: Array = o.compute_path(h.x, h.y, goal.x, goal.y)
	ok(not path.is_empty() or o.is_blocked(goal.x, goal.y), "REQ-0010-06: ... and a path out of the relocation cell exists (not stuck, path %d)" % path.size())
	_dispose(o)


# D4/D8 + critique 0010 #2: an indestructible capsule + legacy raiders = a raid that can neither succeed nor end. Whatever the
# fix (raids held back until W3, raiders leaving, …) a raid must not stay «active» forever while its raiders stand idle at a
# capsule they cannot hurt, nor keep a «РЕЙД» banner up.
func _siege(start_kind: String) -> Dictionary:
	var s: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	_mute(s)
	s.patrol.next = 1.0e9
	s.messages.clear()
	var cap: Vector2i = _cap_tile(s)
	var stock0: String = var_to_str(s.stock)
	var away: Vector2i = _far_cell(s, cap, 20)
	s.player.px = float(away.x) + 0.5
	s.player.py = float(away.y) + 0.5
	if start_kind == "timer":
		s.time.day = 20
		s.raid.next = float(s.raid.timer) + 1.0
	else:
		s.time.day = 6
		s.time.frac = 0.5
		Director.apply(s, {"incident": "raid", "count": 3, "faction": "Тестові мародери"})
	var peak: int = 0
	var ever_active: bool = false
	for t in 3000:
		s.update(Scenarios.DT)
		_topup(s)
		peak = maxi(peak, s.enemies.size())
		ever_active = ever_active or bool(s.raid.active)
		if s.dead:
			s.respawn_new_pawn()
			s.player.px = float(away.x) + 0.5
			s.player.py = float(away.y) + 0.5
	var near: int = 0
	for e in s.enemies:
		if maxi(absi(int(e.px) - cap.x), absi(int(e.py) - cap.y)) <= 2:
			near += 1
	var out: Dictionary = {"active": bool(s.raid.active), "enemies": s.enemies.size(), "near": near, "banner": String(s.banner), "intact": _cap_problem(s, cap) == "",
		"stock_same": var_to_str(s.stock) == stock0, "peak": peak, "ever_active": ever_active, "level": int(s.main_capsule.get("level", -1))}
	_dispose(s)
	return out


func _t_no_eternal_siege() -> void:
	for kind in ["timer", "director_apply"]:
		var r: Dictionary = _siege(String(kind))
		# OD-58 (owner, decided): «перший NPC-рейд — лише після першої прокачки (є що втрачати)». Until W2a no upgrade exists, so
		# a level-0 capsule must see NO raid wave at all — however the director's raid is triggered.
		ok(int(r.level) == 0, "OD-58 [%s] setup: the capsule is still level 0 (no upgrade exists in this wave)" % String(kind))
		ok(int(r.peak) == 0 and not bool(r.ever_active), "OD-58/REQ-0010-65 [%s]: a level-0 capsule is never raided — the first NPC raid waits for the first upgrade (peak raiders alive %d, raid ever active=%s)" % [String(kind), int(r.peak), str(r.ever_active)])
		ok(bool(r.intact), "REQ-0010-75 [%s]: the capsule survives 300 s of a forced raid" % String(kind))
		ok(bool(r.stock_same), "REQ-0010-77 [%s]: ... and the raid takes nothing from the stock (no level drop / theft until П2 decides otherwise)" % String(kind))
		ok(not bool(r.active), "D8/critique-0010 #2 [%s]: after 300 s of sim the raid is over — it is not an endless siege (active=%s, %d raiders still alive, %d idling within 2 cells of the capsule, banner «%s»)" % [String(kind), str(r.active), int(r.enemies), int(r.near), String(r.banner)])


# the fuzz: random verbs aimed at the capsule a third of the time + forced raids + a death; invariants every 25 ticks
func _fuzz_on(seed_val: int, ticks: int) -> Dictionary:
	var sim: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val
	var tile: Vector2i = _cap_tile(sim)
	var sp: Vector2i = sim.map.spawn
	var node_cells: Array = (sim.map.nodes as Dictionary).keys()
	node_cells.sort()
	var kinds: Array = ["wall", "door", "floor", "campfire", "torch", "bed", "workbench", "storage", MainCapsule.KIND]
	var counts: Dictionary = {"build_on_capsule": 0, "demolish_capsule": 0, "damage_capsule": 0, "repair_capsule": 0, "launch": 0, "raid": 0, "respawn": 0, "stash": 0}
	var bad: Array = []
	sim.research_unlocked = {"hunting": true, "machining": true}
	for t in ticks:
		if t == 500 or t == 1300:
			sim.raid.next = float(sim.raid.timer) + 1.0
			counts.raid += 1
		if t == 900:
			_kill(sim)
			sim.respawn_new_pawn()
			counts.respawn += 1
			var hh: Vector2i = _hero_cell(sim)
			if sim.is_blocked(hh.x, hh.y):
				bad.append("t=%d respawn dropped the hero into a blocked cell %s" % [t, str(hh)])
		if t % 6 == 0:
			var verb: int = rng.randi() % 10
			var aim: bool = rng.randi() % 3 == 0
			var cx: int = tile.x if aim else sp.x + rng.randi_range(-6, 6)
			var cy: int = tile.y if aim else sp.y + rng.randi_range(-6, 6)
			var on_capsule: bool = cx == tile.x and cy == tile.y
			match verb:
				0, 1:
					var kind: String = String(kinds[rng.randi() % kinds.size()])
					if rng.randi() % 2 == 0:
						Inventory.add(sim, Inventory.BLD + kind, 1)
					sim.try_build(kind, cx, cy)
					counts.build_on_capsule += 1 if on_capsule else 0
				2:
					sim.demolish(cx, cy)
					counts.demolish_capsule += 1 if on_capsule else 0
				3:
					if not node_cells.is_empty():
						var cell: int = int(node_cells[rng.randi() % node_cells.size()])
						if (sim.map.nodes as Dictionary).has(cell):
							sim.order_gather(cell % int(sim.n), cell / int(sim.n))
				4:
					sim.order_move(cx, cy)
				5:
					var bb: Variant = sim.bgrid.get(cy * int(sim.n) + cx, null)
					if bb != null:
						sim._damage_building(bb, rng.randf_range(1.0, 400.0), rng.randi() % 2 == 0)
						counts.damage_capsule += 1 if on_capsule else 0
				6:
					Upkeep.repair(sim, cx, cy)
					counts.repair_capsule += 1 if on_capsule else 0
				7:
					if rng.randi() % 2 == 0:
						sim.player.px = float(tile.x) + 0.5 + rng.randf_range(-2.0, 2.0)
						sim.player.py = float(tile.y) + 0.5 + rng.randf_range(-2.0, 2.0)
					Inventory.add(sim, "wood", 1 + rng.randi() % 9)
					counts.stash += 1 if bool(Inventory.stash_all(sim).get("ok", false)) else 0
					Inventory.take_from_storage(sim, "wood", 1 + rng.randi() % 5)
				8:
					sim.try_launch_capsule(rng.randf_range(-80.0, 80.0), rng.randf_range(-170.0, 170.0), "фазз")
					counts.launch += 1
				9:
					sim.craft_item(String(GameData.ITEM_ORDER[rng.randi() % GameData.ITEM_ORDER.size()]))
		sim.update(Scenarios.DT)
		_topup(sim)
		if sim.dead:
			sim.respawn_new_pawn()
			counts.respawn += 1
		if t % 25 == 0:
			var p: String = _cap_problem(sim, tile)
			if p != "":
				bad.append("t=%d %s" % [t, p])
				break
	var fin: String = _cap_problem(sim, tile)
	if fin != "" and bad.is_empty():
		bad.append("end: %s" % fin)
	var out: Dictionary = {"hash": Persistence.world_hash(sim), "bad": bad, "counts": counts}
	_dispose(sim)
	return out


func _t_capsule_fuzz() -> void:
	var a: Dictionary = _fuzz_on(20261105, 2000)
	var b: Dictionary = _fuzz_on(20261105, 2000)
	var c: Dictionary = _fuzz_on(20261106, 2000)
	ok((a.bad as Array).is_empty(), "REQ-0010-75 fuzz seed 20261105: capsule invariants hold for 2000 ticks of random verbs/raids/death %s" % str(a.bad))
	ok((c.bad as Array).is_empty(), "REQ-0010-75 fuzz seed 20261106: capsule invariants hold %s" % str(c.bad))
	ok(String(a.hash) == String(b.hash), "REQ-0010-04/75 fuzz: the same seed twice -> the same world_hash at ON (%s == %s)" % [String(a.hash), String(b.hash)])
	var ca: Dictionary = a.counts
	ok(int(ca.build_on_capsule) > 0 and int(ca.demolish_capsule) > 0 and int(ca.damage_capsule) > 0 and int(ca.repair_capsule) > 0 and int(ca.raid) == 2 and int(ca.respawn) >= 1,
		"REQ-0010-75 fuzz: the run really aimed at the capsule (build/demolish/damage/repair attempts, 2 raids, a death): %s" % str(ca))


# =============================================================================================
# WAVE 0010-W1b — helpers
# =============================================================================================
const CLOCK_T := 1800000000000             # an injected device instant (UTC ms)
const BIG_MS := 9007199254740993           # 2^53 + 1: the first integer a float cannot hold
const I64_MAX := 9223372036854775807       # the largest int64 — a JSON number would round it, a string cannot
const SAVE_TMP := "user://qa_capsule_w1b_save.json"
const NO_CELL := Vector2i(-1, -1)


# The spec-0011 seam substitute (REQ-0010-09 «підміна respawn_source стабом»): a body with markers that stands FAR from the
# capsule — where the hero ends up must come from landing, WHOSE body it is must come from the source.
class StubSim extends "res://scripts/sim.gd":
	var source_calls: int = 0

	func respawn_source() -> Dictionary:
		source_calls += 1
		var body: Dictionary = _default_player(Vector2i(0, 0))
		body["born"] = 4242
		body["skills"] = {"gather": 7.0, "combat": 3.0}
		return body


func _on_real(ms: int = CLOCK_T, lat: float = Scenarios.LAT, lon: float = Scenarios.LON) -> Variant:
	var s: Variant = Sim.new()
	s.use_inventory = true
	s.use_catalog = true
	s.use_main_capsule = true
	s.set_clock(ms)
	s.new_game(_gen(lat, lon), false)
	return s


func _stub_on(m: Dictionary) -> Variant:
	var s: Variant = StubSim.new()
	s.use_inventory = true
	s.use_catalog = true
	s.use_main_capsule = true
	s.set_clock(CLOCK_T)
	s.new_game(m, false)
	return s


func _session_on(now_ms: int = CLOCK_T, lat: float = Scenarios.LAT, lon: float = Scenarios.LON) -> Variant:
	var sess: Variant = SessionScript.new()
	sess.autosave = false
	sess.use_inventory = true
	sess.use_catalog = true
	sess.use_main_capsule = true
	sess.start(lat, lon, "Тест", now_ms)
	return sess


func _dispose_session(sess: Variant) -> void:
	if sess != null and sess.sim != null:
		_dispose(sess.sim)


func _json_rt(d: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(d, "", true, true))


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# the smallest Chebyshev ring around `t` that holds a passable, resource-free cell — computed by brute force over the
# whole map, independently of any search order the code uses (REQ-0010-07 «суміжна», REQ-0010-74 «до першої вільної»)
func _min_free_ring(s: Variant, t: Vector2i) -> int:
	var best: int = 1 << 30
	for y in range(int(s.n)):
		for x in range(int(s.n)):
			if Vector2i(x, y) == t:
				continue
			if s.is_blocked(x, y) or (s.map.nodes as Dictionary).has(y * int(s.n) + x):
				continue
			best = mini(best, _cheb(Vector2i(x, y), t))
	return best


func _bsig(s: Variant) -> String:
	var rows: Array = []
	for b in s.buildings:
		rows.append("%s@%d,%d:%s" % [String(b.kind), int(b.x), int(b.y), str(b.hp)])
	rows.sort()
	return "|".join(PackedStringArray(rows))


func _ring_cells(c: Vector2i, r: int, n: int) -> Array:
	var out: Array = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) == r:
				var v: Vector2i = Vector2i(c.x + dx, c.y + dy)
				if v.x >= 0 and v.y >= 0 and v.x < n and v.y < n:
					out.append(v)
	return out


func _inv_is_empty(s: Variant) -> bool:
	for sl in s.player.inv:
		if String(sl.id) != "":
			return false
	return true


func _text_has(s: Variant, needles: Array) -> String:
	for line in _texts(s):
		for nd in needles:
			if String(line).contains(String(nd)):
				return "«%s» in «%s»" % [String(nd), String(line)]
	return ""


func _rm_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# =============================================================================================
# REQ-0010-02: the flag is persisted in serialize_region; ON round-trips (through real JSON) to the SAME world;
# a record without the key loads as OFF
# =============================================================================================
func _t_flag_persist() -> void:
	var s: Variant = _on_real(CLOCK_T)
	for t in 80:
		s.update(Scenarios.DT)
		_topup(s)
	var rec: Dictionary = Persistence.serialize_region(s)
	ok(rec.get("use_main_capsule", false) == true and rec.get("main_capsule") is Dictionary and not (rec.get("main_capsule") as Dictionary).is_empty(),
		"REQ-0010-02: at ON serialize_region persists the flag (use_main_capsule=true) AND the capsule record")
	var wire: Dictionary = _json_rt(Persistence.resume_payload(s))
	var r: Variant = Sim.new()
	ok(not bool(r.use_main_capsule), "REQ-0010-02 setup: a fresh Sim has the flag OFF before it loads anything")
	Persistence.restore(r, wire)
	ok(r.load_error == &"" and bool(r.use_main_capsule), "REQ-0010-02: loading an ON record turns the flag ON in the fresh Sim (load_error=%s)" % str(r.load_error))
	ok(_cap_count(r) == 1 and _cap_problem(r, _cap_tile(s)) == "", "REQ-0010-02: ... with exactly one capsule building on the saved tile (%s)" % _cap_problem(r, _cap_tile(s)))
	ok(Persistence.content_hash(r.main_capsule) == Persistence.content_hash(s.main_capsule), "REQ-0010-02: the capsule record survives the JSON round-trip field for field")
	ok(Persistence.world_hash(r) == Persistence.world_hash(s), "REQ-0010-02/35: restoring a resume payload through JSON gives the SAME world_hash at ON")
	ok(not (r.building_def(MainCapsule.KIND) as Dictionary).is_empty(), "REQ-0010-02: the restored Sim speaks the ON vocabulary (the capsule kind is a def)")
	for t in 100:
		s.update(Scenarios.DT)
		r.update(Scenarios.DT)
		_topup(s)
		_topup(r)
	ok(Persistence.world_hash(r) == Persistence.world_hash(s), "REQ-0010-02 Continue-parity: 100 more ticks on the live world and on the restored one -> still the same world_hash")
	# a record WITHOUT the key is an OFF world — even into a Sim whose dev switch was preset ON before any world existed
	var off: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, false)
	var off_payload: Dictionary = Persistence.resume_payload(off)
	ok(not (off_payload.region as Dictionary).has("use_main_capsule") and not (off_payload.region as Dictionary).has("main_capsule"), "REQ-0010-02 setup: an OFF record carries neither key")
	var pre_on: Variant = Sim.new()
	pre_on.use_inventory = true
	pre_on.use_catalog = true
	pre_on.use_main_capsule = true
	Persistence.restore(pre_on, _json_rt(off_payload))
	ok(pre_on.load_error == &"" and not bool(pre_on.use_main_capsule), "REQ-0010-02/61: a record without the key loads with the flag OFF, even into a Sim preset ON (load_error=%s)" % str(pre_on.load_error))
	ok((pre_on.main_capsule as Dictionary).is_empty() and _cap_count(pre_on) == 0 and pre_on.has_building("storage"), "REQ-0010-02/61: ... no capsule appears, the classic storage is there")
	ok(Persistence.world_hash(pre_on) == Persistence.world_hash(off), "REQ-0010-02/61: ... and the world hashes exactly like the OFF world it was saved from")
	var explicit_off: Dictionary = (off_payload.region as Dictionary).duplicate(true)
	explicit_off["use_main_capsule"] = false
	var eo: Variant = Sim.new()
	eo.load_region(_json_rt(explicit_off))
	ok(eo.load_error == &"" and not bool(eo.use_main_capsule) and (eo.main_capsule as Dictionary).is_empty(), "REQ-0010-02: an explicit use_main_capsule=false without a capsule record is a plain OFF world, not an error")
	for x in [s, r, off, pre_on, eo]:
		_dispose(x)


# =============================================================================================
# REQ-0010-60: the flag is frozen after new_game — also against LOADS; a refused load mutates NOTHING
# =============================================================================================
func _t_flag_locked() -> void:
	var on: Variant = _on_real(CLOCK_T)
	var off: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, false)
	var on_rec: Dictionary = _json_rt(Persistence.serialize_region(on))
	var off_rec: Dictionary = _json_rt(Persistence.serialize_region(off))
	var on_sig: String = _world_sig(on)
	on.load_region(off_rec)   # an OFF record into a RUNNING ON world would flip the frozen flag
	ok(on.load_error != &"" and bool(on.use_main_capsule) and _world_sig(on) == on_sig,
		"REQ-0010-60: an OFF record loaded into a RUNNING ON world is refused (load_error=%s), the flag stays ON and the world is untouched" % str(on.load_error))
	var off_sig: String = _world_sig(off)
	off.load_region(on_rec)
	ok(off.load_error != &"" and not bool(off.use_main_capsule) and _world_sig(off) == off_sig,
		"REQ-0010-60: an ON record loaded into a RUNNING OFF world is refused (load_error=%s), the flag stays OFF and the world is untouched" % str(off.load_error))
	on.load_region(on_rec)
	ok(on.load_error == &"" and bool(on.use_main_capsule) and _cap_problem(on, _cap_tile(on)) == "", "REQ-0010-60: reloading an ON record into the ON world is fine (a region revisit) and clears the error")
	# a record the build cannot trust: explicit error, NOT a silent OFF world — and the Sim stays exactly as a never-started one
	var base: Dictionary = _json_rt(Persistence.serialize_region(_on_real(CLOCK_T)))
	var dirty_runtime: Dictionary = {"dead": true, "weather": "storm", "weather_t": 3.5, "enemies": [{"px": 1.0, "py": 1.0, "hp": 9.0, "kind": "raider", "path": []}], "env_rng_state": "12345"}
	for case_name in ["version_plus_1", "version_99", "version_missing", "flag_missing_capsule_present", "flag_false_capsule_present"]:
		var rec: Dictionary = base.duplicate(true)
		var cap: Dictionary = rec.main_capsule
		match String(case_name):
			"version_plus_1":
				cap["version"] = MainCapsule.RECORD_VERSION + 1
			"version_99":
				cap["version"] = 99
			"version_missing":
				cap.erase("version")
			"flag_missing_capsule_present":
				rec.erase("use_main_capsule")
			"flag_false_capsule_present":
				rec["use_main_capsule"] = false
		var fresh: Variant = Sim.new()
		var fresh_sig: String = _world_sig(fresh)
		fresh.load_region(rec)
		ok(fresh.load_error != &"", "REQ-0010-60 [%s]: the record is refused with an explicit error, not loaded silently as OFF (load_error=%s)" % [String(case_name), str(fresh.load_error)])
		ok(_world_sig(fresh) == fresh_sig and (fresh.map as Dictionary).is_empty() and fresh.buildings.is_empty() and not bool(fresh.use_main_capsule),
			"REQ-0010-60/83 [%s]: ... and the refusal happens BEFORE any mutation (no map, no buildings, flag untouched)" % String(case_name))
		var f2: Variant = Sim.new()
		var env0: int = int(f2.env_rng.state)   # a fresh RandomNumberGenerator seeds itself: compare against THIS instance's own state
		Persistence.restore(f2, {"region": rec, "runtime": dirty_runtime})
		ok(f2.load_error != &"" and not bool(f2.dead) and (f2.enemies as Array).is_empty() and f2.weather == &"clear" and int(f2.env_rng.state) == env0,
			"REQ-0010-60/83 [%s]: Persistence.restore does NOT apply the runtime half over a refused world (dead=%s, enemies=%d, weather=%s)" % [String(case_name), str(f2.dead), (f2.enemies as Array).size(), str(f2.weather)])
		_dispose(fresh)
		_dispose(f2)
	for x in [on, off]:
		_dispose(x)


# =============================================================================================
# REQ-0010-61: an old (OFF) save stays OFF — it is not converted, even when the dev switch is ON at Continue
# =============================================================================================
func _t_old_save_stays_off() -> void:
	var old: Variant = SessionScript.new()
	old.autosave = false
	ok(bool(old.start(Scenarios.LAT, Scenarios.LON, "Старий світ")) and old.last_error == &"", "REQ-0010-61 setup: a default (OFF) Session.start succeeds")
	ok(old.home.keys().size() == 3 and not old.home.has("tile") and not old.home.has("region_key"), "REQ-0010-61: the OFF home is the old {lat, lon, name} — no capsule reference keys")
	ok((old.sim.main_capsule as Dictionary).is_empty() and old.sim.has_building("storage") and _cap_count(old.sim) == 0, "REQ-0010-61: the OFF world has its storage and no capsule")
	ok(old.save_game(SAVE_TMP), "REQ-0010-61 setup: the OFF session saves")
	var text0: String = FileAccess.get_file_as_string(SAVE_TMP)
	var home0: Dictionary = (old.home as Dictionary).duplicate(true)
	var hash0: String = Persistence.world_hash(old.sim)
	var cont: Variant = SessionScript.new()
	cont.autosave = false
	cont.use_inventory = true
	cont.use_catalog = true
	cont.use_main_capsule = true   # the dev switch is ON when the player presses Continue on the OLD save
	ok(bool(cont.restore_game(SAVE_TMP)) and cont.last_error == &"", "REQ-0010-61: Continue on the old save succeeds even with the dev switch ON")
	ok(not bool(cont.sim.use_main_capsule), "REQ-0010-61: the restored world is OFF — it is not converted automatically")
	ok((cont.sim.main_capsule as Dictionary).is_empty() and _cap_count(cont.sim) == 0 and cont.sim.has_building("storage"), "REQ-0010-61: no capsule is minted, the classic storage is still there")
	ok(var_to_str(cont.home) == var_to_str(home0) and bool(cont.has_home), "REQ-0010-61: home is the old {lat, lon, name} byte-for-byte (no tile/region_key migration): %s" % str(cont.home))
	ok(Persistence.world_hash(cont.sim) == hash0, "REQ-0010-61: the restored OFF world hashes exactly like the one that was saved")
	for k in Persistence.serialize_region(cont.sim):
		ok(not String(k).contains("capsule") or String(k) == "capsule", "REQ-0010-61: no new capsule key appears in the OFF record after Continue (%s)" % String(k))
	# the REAL baseline saves of the S0 fixture (stock / inventory / catalog worlds) with the dev switch ON at Continue
	var legacy: Dictionary = chk.fixture.get("legacy_saves", {})
	ok(legacy.size() == 3, "REQ-0010-61 setup: the fixture holds the three baseline saves (%s)" % str(legacy.keys()))
	for kind in legacy:
		var lp: String = SAVE_TMP + ".legacy"
		var lf: FileAccess = FileAccess.open(lp, FileAccess.WRITE)
		lf.store_string(OffFixture.decode_legacy_text(legacy[kind]))
		lf.close()
		var lc: Variant = SessionScript.new()
		lc.autosave = false
		lc.use_inventory = true
		lc.use_catalog = true
		lc.use_main_capsule = true
		var lrestored: bool = lc.restore_game(lp)
		ok(lrestored and lc.last_error == &"", "REQ-0010-61 [%s save]: the baseline save restores with the dev switch ON (last_error=%s)" % [String(kind), str(lc.last_error)])
		if lrestored:
			ok(not bool(lc.sim.use_main_capsule) and (lc.sim.main_capsule as Dictionary).is_empty() and _cap_count(lc.sim) == 0 and lc.sim.has_building("storage"),
				"REQ-0010-61 [%s save]: it stays an OFF world — no capsule is minted, the storage is there" % String(kind))
			ok(lc.home.keys().size() == 3 and lc.home.has("lat") and lc.home.has("lon") and lc.home.has("name") and not lc.home.has("tile"), "REQ-0010-61 [%s save]: home is the old {lat, lon, name} (no capsule reference grafted on): %s" % [String(kind), str(lc.home)])
		_rm_file(lp)
		_dispose_session(lc)
	ok(cont.save_game(SAVE_TMP + ".2"), "REQ-0010-61 setup: the continued session re-saves")
	ok(Persistence.content_hash(JSON.parse_string(FileAccess.get_file_as_string(SAVE_TMP + ".2"))) == Persistence.content_hash(JSON.parse_string(text0)),
		"REQ-0010-61: save -> Continue (dev switch ON) -> save gives the same save content (canonical; JSON number formatting aside)")
	_rm_file(SAVE_TMP)
	_rm_file(SAVE_TMP + ".2")
	_dispose_session(old)
	_dispose_session(cont)


# =============================================================================================
# REQ-0010-07 / 08 / 96: after death the new hero stands NEXT TO the capsule (not at the death site, not «at home»),
# at every level, whatever else the capsule record holds; the capsule is not touched
# =============================================================================================
func _t_respawn_position() -> void:
	for pr in GameData.SPAWN_PRESETS:
		var name: String = String(pr.name)
		var label: String = "REQ-0010-07 [%s]" % name
		var s: Variant = _sim_with(_gen(float(pr.lat), float(pr.lon)), true, true, true)
		_quiet(s)
		var tile: Vector2i = _cap_tile(s)
		var away: Vector2i = _far_cell(s, tile, 12)
		if away == NO_CELL:
			away = _far_cell(s, tile, 6)
		ok(away != NO_CELL, "%s setup: a passable cell far from the capsule exists" % label)
		s.player.px = float(away.x) + 0.5
		s.player.py = float(away.y) + 0.5
		var cap0: String = Persistence.content_hash(s.main_capsule)
		var stock0: String = var_to_str(s.stock)
		var bsig0: String = _bsig(s)
		_kill(s)
		ok(bool(s.dead), "%s setup: the hero died" % label)
		var died: Vector2i = _hero_cell(s)
		ok(_cheb(died, tile) >= 6, "%s setup: it died far from the capsule (%d cells)" % [label, _cheb(died, tile)])
		s.respawn_new_pawn()
		var h: Vector2i = _hero_cell(s)
		var want: int = _min_free_ring(s, tile)
		ok(not bool(s.dead) and float(s.player.hp) > 0.0, "%s: the new hero lives (dead=%s hp=%s)" % [label, str(s.dead), str(s.player.hp)])
		ok(want >= 1 and _cheb(h, tile) == want and not s.is_blocked(h.x, h.y) and not (s.map.nodes as Dictionary).has(h.y * int(s.n) + h.x),
			"%s: respawn on a FREE cell of the NEAREST ring around the capsule (ring %d, hero %s, capsule %s)" % [label, want, str(h), str(tile)])
		ok(h != died and _cheb(h, died) >= 4, "%s: ... not where the hero died (%s) and not by the old «home» logic" % [label, str(died)])
		ok(s.player.get("action") == null and _inv_is_empty(s), "%s: the new hero arrives idle and empty-handed" % label)
		ok(Persistence.content_hash(s.main_capsule) == cap0 and _cap_problem(s, tile) == "", "REQ-0010-96 [%s]: the capsule record (level, owner, instants) is exactly as before the death" % name)
		ok(var_to_str(s.stock) == stock0 and _bsig(s) == bsig0, "REQ-0010-96 [%s]: the storage stock and every building are exactly as before the death" % name)
		for t in 30:
			s.update(Scenarios.DT)
			_topup(s)
		ok(not bool(s.dead), "%s: the new hero survives 30 more ticks" % label)
		_dispose(s)
	# REQ-0010-08: the capsule's state never blocks the respawn — levels 0..5, immunity running, «just after a raid»
	for lvl in range(0, 6):
		var s2: Variant = _on_pad()
		s2.main_capsule.level = lvl
		if lvl % 2 == 1:
			s2.main_capsule["immune_until"] = CLOCK_T + 86400000
			s2.main_capsule["free_transport_token"] = 1
		s2.player.px = 2.5
		s2.player.py = 2.5
		var c0: String = var_to_str(s2.main_capsule)
		_kill(s2)
		s2.respawn_new_pawn()
		var h2: Vector2i = _hero_cell(s2)
		ok(not bool(s2.dead) and _cheb(h2, Vector2i(8, 8)) == 1 and not s2.is_blocked(h2.x, h2.y),
			"REQ-0010-08 [level %d%s]: respawn succeeds next to the capsule (hero %s)" % [lvl, " + immunity + token" if lvl % 2 == 1 else "", str(h2)])
		ok(var_to_str(s2.main_capsule) == c0, "REQ-0010-96 [level %d]: respawn leaves the capsule record untouched" % lvl)
		_dispose(s2)
	# REQ-0010-08/09: another storage ANYWHERE does not move the respawn («не залежить від наявності будь-якого іншого сховища»)
	var s3: Variant = _on_pad()
	s3._place_building("storage", 2, 2, -1)
	s3.player.px = 3.5
	s3.player.py = 3.5
	_kill(s3)
	s3.respawn_new_pawn()
	var h3: Vector2i = _hero_cell(s3)
	ok(_cheb(h3, Vector2i(8, 8)) == 1 and _cheb(h3, Vector2i(2, 2)) >= 4, "REQ-0010-08/09: with an extra storage at (2,2) the hero still respawns next to the CAPSULE (hero %s)" % str(h3))
	_dispose(s3)
	# a death right next to the capsule: respawn is still next to it (the death cell itself may be re-used or not — either is adjacent)
	var s4: Variant = _on_pad()
	s4.player.px = 9.5
	s4.player.py = 8.5
	_kill(s4)
	s4.respawn_new_pawn()
	ok(_cheb(_hero_cell(s4), Vector2i(8, 8)) == 1 and not bool(s4.dead), "REQ-0010-07: a death beside the capsule respawns beside the capsule")
	_dispose(s4)
	# determinism: two worlds, one script -> the same respawn cell and the same hash
	var cells: Array = []
	var hashes: Array = []
	for pass_i in 2:
		var tw: Variant = _on_real(CLOCK_T)
		_quiet(tw)
		var far: Vector2i = _far_cell(tw, _cap_tile(tw), 12)
		tw.player.px = float(far.x) + 0.5
		tw.player.py = float(far.y) + 0.5
		_kill(tw)
		tw.respawn_new_pawn()
		for t in 50:
			tw.update(Scenarios.DT)
			_topup(tw)
		cells.append(_hero_cell(tw))
		hashes.append(Persistence.world_hash(tw))
		_dispose(tw)
	ok(cells[0] == cells[1] and hashes[0] == hashes[1], "REQ-0010-07/04: twin worlds, same death, same respawn -> the same cell %s and the same world_hash" % str(cells[0]))


# =============================================================================================
# REQ-0010-74: every cell next to the capsule is blocked -> the search ring grows to the first passable free cell;
# nothing is demolished; never off the map
# =============================================================================================
func _walled_respawn(m: Dictionary, wall_rings: Array) -> Dictionary:
	var s: Variant = _sim_with(m, true, true, true)
	_quiet(s)
	var tile: Vector2i = _cap_tile(s)
	var n: int = int(s.n)
	for r in wall_rings:
		for c in _ring_cells(tile, int(r), n):
			var v: Vector2i = c
			if not s.bgrid.has(v.y * n + v.x) and not WorldGen.is_terrain_blocked(int(s.map.tiles[v.y * n + v.x])):
				s._place_building("wall", v.x, v.y, -1)
	var bsig0: String = _bsig(s)
	var away: Vector2i = _far_cell(s, tile, 5)
	if away != NO_CELL:
		s.player.px = float(away.x) + 0.5
		s.player.py = float(away.y) + 0.5
	_kill(s)
	s.respawn_new_pawn()
	var h: Vector2i = _hero_cell(s)
	var out: Dictionary = {"hero": h, "tile": tile, "blocked": s.is_blocked(h.x, h.y), "on_map": h.x >= 0 and h.y >= 0 and h.x < n and h.y < n,
		"walls_intact": _bsig(s) == bsig0, "want": _min_free_ring(s, tile), "dead": bool(s.dead), "capsule_ok": _cap_problem(s, tile) == ""}
	_dispose(s)
	return out


func _t_respawn_blocked_rings() -> void:
	for rings in [[1], [1, 2], [1, 2, 3], [1, 2, 3, 4, 5, 6]]:
		var r: Dictionary = _walled_respawn(_pad_map(PAD_N, Vector2i(8, 8)), rings)
		var label: String = "REQ-0010-74 [walls on rings %s]" % str(rings)
		var hero: Vector2i = r.hero
		var cheb: int = _cheb(hero, r.tile)
		ok(not bool(r.dead) and not bool(r.blocked) and bool(r.on_map), "%s: respawn is not blocked — the hero lives on a passable on-map cell %s" % [label, str(hero)])
		ok(cheb == int(r.want) and int(r.want) == int(rings.max()) + 1, "%s: the search ring expanded exactly to the first passable one (ring %d, wanted %d)" % [label, cheb, int(r.want)])
		ok(bool(r.walls_intact) and bool(r.capsule_ok), "%s: no building was demolished to make room (walls/capsule intact)" % label)
	# map corners: the ring leaves the map on two sides — nothing may step outside
	for corner in [Vector2i(0, 0), Vector2i(7, 7), Vector2i(7, 0), Vector2i(0, 7)]:
		var rc: Dictionary = _walled_respawn(_pad_map(8, corner), [1])
		var hc: Vector2i = rc.hero
		ok(not bool(rc.dead) and not bool(rc.blocked) and bool(rc.on_map) and _cheb(hc, rc.tile) == 2 and bool(rc.walls_intact),
			"REQ-0010-74 [corner %s, ring 1 walled]: hero on the map at ring 2 (hero %s)" % [str(corner), str(hc)])
	# water instead of walls: the island whose only dry cells are far away
	for dry in [[Vector2i(8, 8), Vector2i(10, 8)], [Vector2i(8, 8), Vector2i(13, 8)], [Vector2i(8, 8), Vector2i(15, 15)]]:
		var ri: Dictionary = _walled_respawn(_island_map(PAD_N, Vector2i(8, 8), dry), [])
		ok(ri.hero == dry[1] and not bool(ri.dead) and bool(ri.capsule_ok), "REQ-0010-74 [island, dry cell %s]: the hero respawns on the only passable cell (got %s)" % [str(dry[1]), str(ri.hero)])
	# two equally distant dry cells: whichever is chosen, the choice is stable (twin runs agree)
	var tie_a: Dictionary = _walled_respawn(_island_map(PAD_N, Vector2i(8, 8), [Vector2i(8, 8), Vector2i(14, 8), Vector2i(2, 8)]), [])
	var tie_b: Dictionary = _walled_respawn(_island_map(PAD_N, Vector2i(8, 8), [Vector2i(8, 8), Vector2i(14, 8), Vector2i(2, 8)]), [])
	ok(tie_a.hero == tie_b.hero and (tie_a.hero == Vector2i(14, 8) or tie_a.hero == Vector2i(2, 8)), "REQ-0010-74: an exact tie between two dry cells resolves the same way every time (%s)" % str(tie_a.hero))


# =============================================================================================
# REQ-0010-09: the seams. respawn_source (0011 stub = _default_player; substitutable), respawn_anchor(session) ->
# {region_key, pos}, Session.home as a reference to the capsule
# =============================================================================================
func _t_respawn_seams() -> void:
	var d: Variant = _on_pad()
	ok(var_to_str(d.respawn_source()) == var_to_str(d._default_player(d.map.spawn)), "REQ-0010-09: until 0011 the respawn_source seam answers with the existing starter pawn (_default_player)")
	# a substituted source decides WHOSE body comes back; landing decides WHERE
	var st: Variant = _stub_on(_pad_map(PAD_N, Vector2i(8, 8)))
	_quiet(st)
	st.player.px = 2.5
	st.player.py = 2.5
	var cap0: String = var_to_str(st.main_capsule)
	var stock0: String = var_to_str(st.stock)
	_kill(st)
	st.respawn_new_pawn()
	ok(int(st.source_calls) == 1, "REQ-0010-09: one respawn asks the respawn_source seam exactly once (%d)" % int(st.source_calls))
	ok(int(st.player.born) == 4242 and is_equal_approx(float(st.player.skills.gather), 7.0), "REQ-0010-09: the body that arrives IS the one the seam returned (markers born=%s skills=%s)" % [str(st.player.born), str(st.player.skills)])
	ok(_cheb(_hero_cell(st), Vector2i(8, 8)) == 1, "REQ-0010-09: ... yet it stands next to the capsule, not where the source put it (%s)" % str(_hero_cell(st)))
	ok(_inv_is_empty(st) and not bool(st.dead), "REQ-0010-09: ... empty-handed and alive")
	ok(var_to_str(st.main_capsule) == cap0 and var_to_str(st.stock) == stock0, "REQ-0010-96: a substituted source changes nothing in the capsule record or the storage")
	# respawn_anchor(session) -> {region_key, pos}, in the plain case and with the capsule walled in
	for walled in [false, true]:
		var sim: Variant = _stub_on(_pad_map(PAD_N, Vector2i(8, 8)))
		_quiet(sim)
		var tile: Vector2i = _cap_tile(sim)
		if walled:
			for c in _ring_cells(tile, 1, int(sim.n)):
				var v: Vector2i = c
				sim._place_building("wall", v.x, v.y, -1)
		var sess: Variant = SessionScript.new()
		sess.autosave = false
		sess.sim = sim
		sess.has_home = true
		sess.home = {"lat": Scenarios.LAT, "lon": Scenarios.LON, "name": "тест", "region_key": WorldGen.canon_coord(Scenarios.LAT, Scenarios.LON), "tile": [tile.x, tile.y]}
		var label: String = "REQ-0010-09/74 [%s]" % ("capsule walled in" if walled else "open ground")
		var anchor: Dictionary = MainCapsule.respawn_anchor(sess)
		var pos: Vector2i = anchor.get("pos", NO_CELL)
		ok(anchor.has("region_key") and anchor.has("pos") and anchor.get("region_key") is String and anchor.get("pos") is Vector2i, "%s: respawn_anchor returns {region_key: String, pos: Vector2i}" % label)
		ok(String(anchor.get("region_key", "")) == Persistence.region_key(Scenarios.LAT, Scenarios.LON), "%s: region_key is the region of the home capsule (%s)" % [label, str(anchor.get("region_key"))])
		var want: int = _min_free_ring(sim, tile)
		ok(pos != tile and _cheb(pos, tile) == want and not sim.is_blocked(pos.x, pos.y),
			"%s: «при ON повертає клітинку біля капсули» — pos is a passable free cell of the nearest ring (ring %d), got %s for a capsule on %s" % [label, want, str(pos), str(tile)])
		_kill(sim)
		sess.respawn()
		ok(not bool(sim.dead) and _hero_cell(sim) == pos, "%s: Session.respawn puts the hero exactly on the cell the anchor announced (D9: one truth) — hero %s, anchor %s" % [label, str(_hero_cell(sim)), str(pos)])
		ok(_cap_problem(sim, tile) == "" and int(sim.source_calls) == 1, "%s: the capsule is intact and the body came through the seam" % label)
		_dispose(sim)
	# OFF: the anchor is the home coordinate and announces no cell
	var off: Variant = SessionScript.new()
	off.autosave = false
	off.start(Scenarios.LAT, Scenarios.LON, "Дім")
	var oa: Dictionary = MainCapsule.respawn_anchor(off)
	ok(String(oa.get("region_key", "")) == Persistence.region_key(Scenarios.LAT, Scenarios.LON) and oa.get("pos") is Vector2i, "REQ-0010-09: at OFF the anchor is the home region (default home) with a typed pos")
	for x in [d, st]:
		_dispose(x)
	_dispose_session(off)


# =============================================================================================
# REQ-0010-10 / 96 (sim part): the death/bag mechanism is the spec-0009 one at ON; the log promises no «новий
# виживальник у домі»; the bag stays where the pawn fell
# =============================================================================================
func _t_death_bag_and_texts() -> void:
	var on: Variant = _on_pad()
	var off: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), true, true, false)
	_quiet(off)
	for s in [on, off]:
		s.player.px = 3.5
		s.player.py = 3.5
		_kill(s)
	ok(on.bags.size() == 1 and var_to_str(on.bags) == var_to_str(off.bags),
		"REQ-0010-10: at ON the death drops the SAME bag, at the same cell, as the spec-0009 world (ON %s vs OFF %s)" % [var_to_str(on.bags), var_to_str(off.bags)])
	var bag0: String = var_to_str(on.bags)
	on.respawn_new_pawn()
	ok(var_to_str(on.bags) == bag0, "REQ-0010-10/96: respawn neither moves nor deletes the bag — it stays where the pawn fell")
	ok(_inv_is_empty(on), "REQ-0010-10: the new hero does not inherit the bag's contents")
	var promise: String = _text_has(on, ["Новий виживальник", "новий виживальник", "поселення", "у домі", "в домі", "Поселення"])
	ok(promise == "", "REQ-0010-10/40: after death + respawn at ON the feed makes no «новий виживальник / поселення / у домі» promise %s" % promise)
	for s in [on, off]:
		_dispose(s)


# =============================================================================================
# REQ-0010-09 / 41 / 92 (Session part): flags reach the Sim before new_game; Session.home is a reference to the capsule;
# a refused configuration yields no half-world; the landing instant is the pushed clock
# =============================================================================================
func _t_session_on() -> void:
	var sess: Variant = _session_on(CLOCK_T)
	var sim: Variant = sess.sim
	ok(sess.last_error == &"" and sim != null, "REQ-0010-09 setup: an ON Session.start succeeds (last_error=%s)" % str(sess.last_error))
	ok(bool(sim.use_main_capsule) and bool(sim.use_catalog) and bool(sim.use_inventory), "REQ-0010-02: Session.start hands the flags to the Sim BEFORE new_game (ON world, catalogue vocabulary, inventory)")
	var tile: Vector2i = _cap_tile(sim)
	ok(bool(sess.has_home) == (not (sim.main_capsule as Dictionary).is_empty()) and bool(sess.has_home), "REQ-0010-09: has_home <=> the capsule exists")
	ok(sess.home.has("region_key") and String(sess.home.region_key) == Persistence.region_key(Scenarios.LAT, Scenarios.LON), "REQ-0010-09: Session.home.region_key is the region of the capsule (%s)" % str(sess.home.get("region_key")))
	ok(sess.home.has("tile") and Vector2i(int(sess.home.tile[0]), int(sess.home.tile[1])) == tile, "REQ-0010-09: Session.home.tile IS the capsule tile %s (a reference, not a copy of a coordinate)" % str(tile))
	ok(int(sim.main_capsule.landed_at) == CLOCK_T and int(sim.main_capsule.grace_start) == CLOCK_T, "REQ-0010-92/35: the landing instant is the clock pushed at Session.start (landed_at=%s, wanted %d)" % [str(sim.main_capsule.landed_at), CLOCK_T])
	var stale: String = _text_has(sim, ["долетить", "Щоденна капсула", "Друзі надіслали"])
	ok(stale == "" and (sim.invites as Array).is_empty(), "REQ-0010-41/40: at ON the feed carries no «капсула (V) долетить / Щоденна капсула» claim and no seeded invites %s" % stale)
	# a refused configuration: no world, no home, a reason — and the same Session can start again once fixed
	for missing in ["catalog", "inventory"]:
		var bad: Variant = SessionScript.new()
		bad.autosave = false
		bad.use_inventory = missing != "inventory"
		bad.use_catalog = missing != "catalog"
		bad.use_main_capsule = true
		var started: bool = bad.start(Scenarios.LAT, Scenarios.LON, "Тест", CLOCK_T)
		ok(not started and bad.last_error != &"" and bad.sim == null and not bool(bad.has_home), "REQ-0010-03/59 [no %s]: Session.start returns false with a reason, creates no world and no home (error=%s)" % [missing, str(bad.last_error)])
		bad.use_inventory = true
		bad.use_catalog = true
		var again: bool = bad.start(Scenarios.LAT, Scenarios.LON, "Тест", CLOCK_T)
		ok(again and bad.last_error == &"" and bad.sim != null and bool(bad.has_home) and _cap_count(bad.sim) == 1, "REQ-0010-03/59 [no %s]: after fixing the config the same Session starts a normal ON world" % missing)
		_dispose_session(bad)
	# a Session that already ran a world and then FAILS an ON start must not keep claiming a home with no capsule behind it
	var reuse: Variant = SessionScript.new()
	reuse.autosave = false
	reuse.start(Scenarios.LAT, Scenarios.LON, "Попередній світ")
	ok(bool(reuse.has_home), "REQ-0010-09 setup: the reused Session ran a world first (has_home)")
	reuse.use_inventory = true
	reuse.use_main_capsule = true   # use_catalog is still false: the ON start is refused (REQ-0010-59)
	var reuse_started: bool = reuse.start(Scenarios.LAT, Scenarios.LON, "Новий світ", CLOCK_T)
	ok(not reuse_started and reuse.sim == null, "REQ-0010-59 setup: the ON start without a catalogue is refused and leaves no sim")
	ok(not bool(reuse.has_home), "REQ-0010-09: has_home <=> the capsule exists — after a refused ON start there is no capsule, so there must be no home either (has_home=%s, home=%s)" % [str(reuse.has_home), str(reuse.home)])
	# twin sessions: same coordinate + same clock -> same world; another landing instant -> another world
	var twin: Variant = _session_on(CLOCK_T)
	var later: Variant = _session_on(CLOCK_T + 1)
	ok(Persistence.world_hash(twin.sim) == Persistence.world_hash(sim), "REQ-0010-04/92: twin Sessions (same lat/lon, same clock) -> the same world_hash")
	ok(Persistence.world_hash(later.sim) != Persistence.world_hash(sim), "REQ-0010-82: another landing instant is another world (landed_at is hashed)")
	# the clock is monotone at the Session edge too
	sess.push_clock(CLOCK_T - 1000)
	ok(int(sim.now_ms) == CLOCK_T, "REQ-0010-68/92: Session.push_clock with an earlier instant does not rewind the sim clock (now_ms=%s)" % str(sim.now_ms))
	sess.push_clock(CLOCK_T + 10)
	ok(int(sim.now_ms) == CLOCK_T + 10 and int(sim.main_capsule.landed_at) == CLOCK_T, "REQ-0010-92: a later push advances now_ms but the landing instant stays a fact (landed_at=%s)" % str(sim.main_capsule.landed_at))
	var nobody: Variant = SessionScript.new()
	nobody.push_clock(CLOCK_T)
	ok(nobody.sim == null, "REQ-0010-92: push_clock on a Session with no world is a harmless no-op")
	# a capsule/travel launch is refused at the Session edge without touching the world (REQ-0010-41/75)
	var sig0: String = _world_sig(sim)
	sess.travel_to(Scenarios.LAT2, Scenarios.LON2, "Львів")
	ok(_world_sig(sim) == sig0 and _cap_problem(sim, tile) == "", "REQ-0010-41/75: travel_to another region at ON leaves capsule, stock and buildings exactly as they were")
	# Session.respawn: died far away -> next to the capsule in the SAME region, home untouched, capsule untouched
	_quiet(sim)
	var far: Vector2i = _far_cell(sim, tile, 12)
	sim.player.px = float(far.x) + 0.5
	sim.player.py = float(far.y) + 0.5
	var home0: String = var_to_str(sess.home)
	var cap0: String = Persistence.content_hash(sim.main_capsule)
	_kill(sim)
	sess.respawn()
	var h: Vector2i = _hero_cell(sim)
	ok(not bool(sim.dead) and _cheb(h, tile) == _min_free_ring(sim, tile) and not sim.is_blocked(h.x, h.y) and Persistence.region_key(float(sim.map.lat), float(sim.map.lon)) == Persistence.region_key(Scenarios.LAT, Scenarios.LON),
		"REQ-0010-07/09: Session.respawn after a far death puts the hero beside the capsule in the same region (hero %s, capsule %s)" % [str(h), str(tile)])
	ok(var_to_str(sess.home) == home0 and Persistence.content_hash(sim.main_capsule) == cap0 and bool(sess.has_home), "REQ-0010-09/96: Session.respawn leaves home and the capsule record untouched")
	for x in [sess, twin, later]:
		_dispose_session(x)


# =============================================================================================
# REQ-0010-02 / 09 / 83: save_game -> restore_game (Continue): same world, home restored from the capsule,
# a save made BETWEEN death and respawn keeps the death and can respawn
# =============================================================================================
func _t_save_continue_on() -> void:
	var a: Variant = _session_on(CLOCK_T)
	var tile: Vector2i = _cap_tile(a.sim)
	a.sim._place_building("wall", tile.x + 3, tile.y, -1)
	for t in 120:
		a.sim.update(Scenarios.DT)
		_topup(a.sim)
	ok(bool(a.save_game(SAVE_TMP)), "REQ-0010-02 setup: the ON session saves")
	var b: Variant = SessionScript.new()
	b.autosave = false
	ok(bool(b.restore_game(SAVE_TMP)) and b.last_error == &"", "REQ-0010-02: Continue restores the ON session (last_error=%s)" % str(b.last_error))
	ok(bool(b.sim.use_main_capsule) and bool(b.use_main_capsule), "REQ-0010-02: the restored world, and the Session that mirrors it, are ON")
	ok(bool(b.has_home) and b.home.has("tile") and Vector2i(int(b.home.tile[0]), int(b.home.tile[1])) == tile and String(b.home.get("region_key", "")) == String(a.home.region_key),
		"REQ-0010-09: Continue restores the home reference (region_key + capsule tile): %s" % str(b.home))
	ok(absf(float(b.home.lat) - Scenarios.LAT) < 1e-9 and absf(float(b.home.lon) - Scenarios.LON) < 1e-9, "REQ-0010-09: ... and the home coordinate")
	ok(Persistence.world_hash(b.sim) == Persistence.world_hash(a.sim), "REQ-0010-02/35: the continued world hashes exactly like the saved one")
	for t in 100:
		for x in [a, b]:
			x.sim.update(Scenarios.DT)
			_topup(x.sim)
	ok(Persistence.world_hash(b.sim) == Persistence.world_hash(a.sim), "REQ-0010-02: 100 ticks after Continue the two worlds are still identical (the restored one is not a different trajectory)")
	_dispose_session(b)
	# one truth: a save whose home points elsewhere does not move the home away from the capsule
	var forged: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_TMP))
	forged["home"]["tile"] = [0, 0]
	forged["home"]["region_key"] = "0.0000,0.0000"
	var f: FileAccess = FileAccess.open(SAVE_TMP + ".forged", FileAccess.WRITE)
	f.store_string(JSON.stringify(forged, "", true, true))
	f.close()
	var fo: Variant = SessionScript.new()
	fo.autosave = false
	ok(bool(fo.restore_game(SAVE_TMP + ".forged")), "REQ-0010-09 setup: the save with a forged home still loads")
	ok(Vector2i(int(fo.home.tile[0]), int(fo.home.tile[1])) == tile and String(fo.home.region_key) == String(a.home.region_key),
		"REQ-0010-09/D9: Session.home at ON is a REFERENCE to the capsule — a forged home.tile/region_key in the file cannot point away from it (home %s)" % str(fo.home))
	_dispose_session(fo)
	# a save between death and respawn
	var d: Variant = _session_on(CLOCK_T)
	_quiet(d.sim)
	var far: Vector2i = _far_cell(d.sim, tile, 10)
	d.sim.player.px = float(far.x) + 0.5
	d.sim.player.py = float(far.y) + 0.5
	_kill(d.sim)
	var died: Vector2i = _hero_cell(d.sim)
	var cap0: String = Persistence.content_hash(d.sim.main_capsule)
	var bags0: String = Persistence.content_hash(d.sim.bags)
	ok(bool(d.sim.dead) and bool(d.save_game(SAVE_TMP)), "REQ-0010-83 setup: saved in the state «dead» (the death screen is up)")
	ok(bool(SessionScript.save_meta(SAVE_TMP).get("dead", false)), "REQ-0010-83: the continue meta knows the hero is dead")
	var e: Variant = SessionScript.new()
	e.autosave = false
	ok(bool(e.restore_game(SAVE_TMP)), "REQ-0010-83: a save made between death and respawn restores")
	ok(bool(e.sim.dead), "REQ-0010-83: ... still dead — the player lands on the death screen, not on a phantom hero")
	ok(Persistence.world_hash(e.sim) == Persistence.world_hash(d.sim), "REQ-0010-83/35: the dead world hashes exactly like the saved one")
	e.respawn()
	var h: Vector2i = _hero_cell(e.sim)
	ok(not bool(e.sim.dead) and _cheb(h, tile) == _min_free_ring(e.sim, tile) and not e.sim.is_blocked(h.x, h.y), "REQ-0010-83: respawn works after the restore and puts the hero beside the capsule (%s)" % str(h))
	ok(Persistence.content_hash(e.sim.main_capsule) == cap0 and Persistence.content_hash(e.sim.bags) == bags0 and e.sim.bags.size() == 1 and Vector2i(int(e.sim.bags[0].x), int(e.sim.bags[0].y)) == died,
		"REQ-0010-96/10: the capsule is as before, the bag still lies where the hero fell (%s)" % var_to_str(e.sim.bags))
	_rm_file(SAVE_TMP)
	_rm_file(SAVE_TMP + ".forged")
	for x in [a, d, e]:
		_dispose_session(x)


# =============================================================================================
# REQ-0010-02 / 83 (hash-exact resume): a payload cut while the pawn is MID-ACTION in a small base resumes bit-exact;
# after the restore a death + respawn lands the restored world exactly where the live one lands
# =============================================================================================
func _t_restore_parity_live() -> void:
	var s: Variant = _on_real(CLOCK_T)
	var tile: Vector2i = _cap_tile(s)
	s._place_building("wall", tile.x + 2, tile.y, -1)
	s._place_building("storage", tile.x - 2, tile.y + 1, -1)
	for t in 40:
		s.update(Scenarios.DT)
		_topup(s)
	# the nearest resource node at least 6 cells from the hero: a walk long enough to still be under way 5 ticks later
	var best: int = -1
	var best_d: int = 1 << 30
	var hero: Vector2i = _hero_cell(s)
	var cells: Array = (s.map.nodes as Dictionary).keys()
	cells.sort()
	for c in cells:
		var cell: int = int(c)
		var d: int = _cheb(Vector2i(cell % int(s.n), cell / int(s.n)), hero)
		if d >= 6 and d < best_d:
			best_d = d
			best = cell
	ok(best >= 0, "REQ-0010-02 setup: a resource node 6+ cells away exists")
	if best >= 0:
		s.order_gather(best % int(s.n), best / int(s.n))
	for t in 5:
		s.update(Scenarios.DT)
		_topup(s)
	ok(s.player.get("action") != null, "REQ-0010-02 setup: the pawn is mid-action when the payload is cut")
	var r: Variant = Sim.new()
	Persistence.restore(r, _json_rt(Persistence.resume_payload(s)))
	ok(r.load_error == &"" and Persistence.world_hash(r) == Persistence.world_hash(s), "REQ-0010-02/35: a resume payload cut mid-action restores to the SAME world_hash (load_error=%s)" % str(r.load_error))
	ok(_bsig(r) == _bsig(s) and _cap_count(r) == 1 and _cap_problem(r, tile) == "", "REQ-0010-02: ... with the same buildings and the capsule on its tile")
	for t in 150:
		s.update(Scenarios.DT)
		r.update(Scenarios.DT)
		_topup(s)
		_topup(r)
	ok(Persistence.world_hash(r) == Persistence.world_hash(s), "REQ-0010-02: 150 ticks later (the walk, the gather, the stash) the restored world still equals the live one")
	_kill(s)
	_kill(r)
	s.respawn_new_pawn()
	r.respawn_new_pawn()
	ok(_hero_cell(r) == _hero_cell(s) and Persistence.world_hash(r) == Persistence.world_hash(s), "REQ-0010-07/83: a death + respawn after the restore lands the restored world exactly where the live one lands (%s)" % str(_hero_cell(r)))
	for x in [s, r]:
		_dispose(x)


# =============================================================================================
# REQ-0010-60 / 83: a corrupt / newer / orphan ON save is refused with an explicit reason, through Session.restore_game
# AND Persistence.restore, and a refusal leaves a RUNNING session exactly as it was
# =============================================================================================
func _tampered_save(src: String, case_name: String) -> String:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src))
	var region: Dictionary = d["active"]["region"]
	match case_name:
		"capsule_key_missing":
			region.erase("main_capsule")
		"capsule_empty":
			region["main_capsule"] = {}
		"capsule_null":
			region["main_capsule"] = null
		"version_99":
			region["main_capsule"]["version"] = 99
		"orphan_capsule_without_flag":
			region.erase("use_main_capsule")
		"flag_false_but_capsule":
			region["use_main_capsule"] = false
		"tile_off_map":
			region["main_capsule"]["tile"] = [999, 3]
		"tile_arity":
			region["main_capsule"]["tile"] = [3]
		"tile_text":
			region["main_capsule"]["tile"] = "8,8"
	var out: String = src + "." + case_name
	var f: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", true, true))
	f.close()
	return out


func _t_save_refusals() -> void:
	var live: Variant = _session_on(CLOCK_T)
	_quiet(live.sim)
	for t in 30:
		live.sim.update(Scenarios.DT)
		_topup(live.sim)
	ok(bool(live.save_game(SAVE_TMP)), "REQ-0010-83 setup: a valid ON save exists")
	var live_sim: Variant = live.sim
	var live_sig: String = _world_sig(live_sim)
	var live_home: String = var_to_str(live.home)
	for case_name in ["capsule_key_missing", "capsule_empty", "capsule_null", "version_99", "orphan_capsule_without_flag", "flag_false_but_capsule", "tile_off_map", "tile_arity", "tile_text"]:
		var bad: String = _tampered_save(SAVE_TMP, String(case_name))
		var label: String = "REQ-0010-60/83 [%s]" % String(case_name)
		var none: Variant = SessionScript.new()
		none.autosave = false
		var loaded: bool = none.restore_game(bad)
		ok(not loaded and none.last_error != &"" and none.sim == null and not bool(none.has_home), "%s: Session.restore_game refuses with an explicit reason and builds no world (last_error=%s)" % [label, str(none.last_error)])
		var loaded2: bool = live.restore_game(bad)
		ok(not loaded2 and live.last_error != &"" and live.sim == live_sim and _world_sig(live.sim) == live_sig and var_to_str(live.home) == live_home,
			"%s: a refused Continue leaves the RUNNING session exactly as it was (same Sim instance, same world, same home)" % label)
		# the same payload through Persistence.restore (the net-rejoin path): nothing applied over a refused world
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bad))
		var payload: Dictionary = d["active"]
		payload["runtime"]["dead"] = true
		var raw: Variant = Sim.new()
		var raw_sig: String = _world_sig(raw)
		Persistence.restore(raw, payload)
		ok(raw.load_error != &"" and _world_sig(raw) == raw_sig and not bool(raw.dead), "%s: Persistence.restore refuses too and does not apply dead=true over an empty Sim" % label)
		_dispose(raw)
		_rm_file(bad)
	ok(bool(live.restore_game(SAVE_TMP)) and live.last_error == &"", "REQ-0010-83: after the refusals a valid save still restores and the error is cleared (nothing latched)")
	_rm_file(SAVE_TMP)
	_dispose_session(live)


# =============================================================================================
# REQ-0010-98: ONE landing seam. Exactly one definition in the code; the capsule is only ever installed from it
# (and from the save-restore path)
# =============================================================================================
func _t_single_landing() -> void:
	var files: Array = []
	_gd_files("res://scripts", files)
	var re_landing: RegEx = RegEx.new()
	re_landing.compile("(?m)^\\s*(?:static\\s+)?func\\s+landing\\s*\\(")
	var re_anchor: RegEx = RegEx.new()
	re_anchor.compile("(?m)^\\s*(?:static\\s+)?func\\s+respawn_anchor\\s*\\(")
	var re_fn: RegEx = RegEx.new()
	re_fn.compile("^\\s*(?:static\\s+)?func\\s+(\\w+)")
	var re_install: RegEx = RegEx.new()
	re_install.compile("_place_building\\(\\s*(MainCapsule\\.)?KIND\\b|_place_building\\(\\s*\"main_capsule\"")
	var landing_defs: Array = []
	var anchor_defs: int = 0
	var install_sites: Dictionary = {}
	for path in files:
		var text: String = FileAccess.get_file_as_string(String(path))
		for mm in re_landing.search_all(text):
			landing_defs.append(path)
		anchor_defs += re_anchor.search_all(text).size()
		var cur_fn: String = ""
		for line in text.split("\n"):
			var code: String = String(line).get_slice("#", 0)
			var mf: RegExMatch = re_fn.search(code)
			if mf != null:
				cur_fn = mf.get_string(1)
			if re_install.search(code) != null:
				install_sites["%s::%s" % [String(path).trim_prefix("res://scripts/"), cur_fn]] = true
	ok(landing_defs.size() == 1, "REQ-0010-98: exactly ONE `func landing` in the code (found %d: %s)" % [landing_defs.size(), str(landing_defs)])
	ok(anchor_defs == 1, "REQ-0010-09: exactly ONE `func respawn_anchor` (found %d)" % anchor_defs)
	var sites: Array = install_sites.keys()
	sites.sort()
	ok(sites == ["sim/capsule.gd::from_record", "sim/capsule.gd::landing"], "REQ-0010-98: the capsule building is installed only by landing (first landing) and from_record (restoring a save) — sites: %s" % str(sites))


# =============================================================================================
# REQ-0010-34 (W1b part): switching the capsule ON does not shift the director / environment / threat streams
# =============================================================================================
func _cursors(s: Variant) -> Array:
	return [str(s.director_rng.state), str(s.env_rng.state), str(s.threat_rng.state)]


func _cursor_run(lat: float, lon: float, capsule: bool, ticks: int, with_death: bool) -> Dictionary:
	var s: Variant = _sim_with(_gen(lat, lon), true, true, capsule)
	var out: Dictionary = {"init": _cursors(s)}
	var enemies_seen: int = 0
	for t in ticks:
		s.update(Scenarios.DT)
		_topup(s)
		enemies_seen += (s.enemies as Array).size()
		if with_death and t == ticks / 2:
			_kill(s)
			s.respawn_new_pawn()
	out["end"] = _cursors(s)
	out["enemies"] = enemies_seen
	_dispose(s)
	return out


func _t_stream_cursors() -> void:
	for pr in GameData.SPAWN_PRESETS:
		for with_death in [false, true]:
			var lat: float = float(pr.lat)
			var lon: float = float(pr.lon)
			var on: Dictionary = _cursor_run(lat, lon, true, 600, bool(with_death))
			var off: Dictionary = _cursor_run(lat, lon, false, 600, bool(with_death))
			var label: String = "REQ-0010-34 [%s%s]" % [String(pr.name), " + a death" if with_death else ""]
			ok(int(off.enemies) == 0 and int(on.enemies) == 0, "%s setup: no raid/patrol in 60 s (enemies seen OFF=%d ON=%d)" % [label, int(off.enemies), int(on.enemies)])
			ok(on.end[0] != on.init[0] and on.end[1] != on.init[1], "%s setup: the director and environment streams really ran (the cursors moved in 600 ticks)" % label)
			ok(on.init == off.init, "%s: the three stream cursors right after new_game are those of the OFF world (ON %s vs OFF %s)" % [label, str(on.init), str(off.init)])
			ok(on.end == off.end, "%s: ... and after 600 ticks (director/env/threat) the flag has not shifted any of them (ON %s vs OFF %s)" % [label, str(on.end), str(off.end)])


# =============================================================================================
# REQ-0010-35 / 82 (current record fields): every field moves world_hash; round-trip returns the same hash; int64
# instants are exact through JSON (strings, not floats); dt does not matter; now_ms is not hashed
# =============================================================================================
func _t_hash_fields() -> void:
	var base: Variant = _on_real(CLOCK_T)
	var h0: String = Persistence.world_hash(base)
	ok(Persistence.world_hash(_on_real(CLOCK_T)) == h0, "REQ-0010-82 setup: twin ON worlds hash the same (%s)" % h0)
	var tile: Vector2i = _cap_tile(base)
	for field in ["level", "owner", "landed_at", "grace_start", "tile"]:
		var m: Variant = _on_real(CLOCK_T)
		match String(field):
			"level":
				m.main_capsule["level"] = 1
			"owner":
				m.main_capsule["owner"] = "someone_else"
			"landed_at":
				m.main_capsule["landed_at"] = CLOCK_T + 1
			"grace_start":
				m.main_capsule["grace_start"] = CLOCK_T + 1
			"tile":
				m.main_capsule["tile"] = [tile.x + 1, tile.y]
		ok(Persistence.world_hash(m) != h0, "REQ-0010-35/82 [%s]: mutating the capsule field changes world_hash" % String(field))
		_dispose(m)
	# the record on the wire: instants as decimal STRINGS, level an int, tile two ints
	var x: Variant = _on_real(CLOCK_T)
	x.main_capsule["level"] = 3
	x.main_capsule["landed_at"] = BIG_MS
	x.main_capsule["grace_start"] = I64_MAX
	var rec: Dictionary = Persistence.serialize_region(x).main_capsule
	ok(rec.get("landed_at") is String and rec.get("grace_start") is String and rec.get("level") is int and rec.get("tile") is Array, "REQ-0010-82: instants are strings (int64 can't ride a JSON number), level is an int, tile an array")
	var text: String = JSON.stringify(rec, "", true, true)
	ok(text.contains(str(BIG_MS)) and text.contains(str(I64_MAX)), "REQ-0010-82: 2^53+1 and int64-max appear digit-exact in the JSON text")
	var hx: String = Persistence.world_hash(x)
	var y: Variant = Sim.new()
	Persistence.restore(y, _json_rt(Persistence.resume_payload(x)))
	ok(y.load_error == &"" and int(y.main_capsule.landed_at) == BIG_MS and int(y.main_capsule.grace_start) == I64_MAX and int(y.main_capsule.level) == 3,
		"REQ-0010-82: 2^53+1 / int64-max / level 3 come back EXACT from a JSON round-trip (landed_at=%s grace_start=%s)" % [str(y.main_capsule.get("landed_at")), str(y.main_capsule.get("grace_start"))])
	ok(Persistence.world_hash(y) == hx, "REQ-0010-35: the round-tripped world has the same world_hash")
	# dt independence of the record: same seed, 100 x 0.1 s vs 200 x 0.05 s
	var a: Variant = _on_real(CLOCK_T)
	var b: Variant = _on_real(CLOCK_T)
	_quiet(a)
	_quiet(b)
	for t in 100:
		a.update(0.1)
		_topup(a)
	for t in 200:
		b.update(0.05)
		_topup(b)
	ok(Persistence.content_hash(Persistence.serialize_region(a).main_capsule) == Persistence.content_hash(Persistence.serialize_region(b).main_capsule),
		"REQ-0010-82: the capsule record's hash is the same at dt=0.1 and dt=0.05 (the same 10 s of sim)")
	# now_ms is an input, not state
	var before: String = Persistence.world_hash(a)
	a.set_clock(CLOCK_T + 5000)
	ok(Persistence.world_hash(a) == before, "REQ-0010-92: set_clock after landing does not change world_hash (now_ms is an input)")
	ok(not JSON.stringify(Persistence.resume_payload(a)).contains("now_ms"), "REQ-0010-92: now_ms appears nowhere in the save/resume payload")
	for s in [base, x, y, a, b]:
		_dispose(s)


# =============================================================================================
# REQ-0010-92 / 68: time enters the sim only through set_clock — monotone, exact int64, never rewrites the landing fact
# =============================================================================================
func _t_clock_input() -> void:
	var c: Variant = Sim.new()
	ok(int(c.now_ms) == 0, "REQ-0010-92 setup: a fresh Sim has not been told the time (now_ms=0)")
	c.set_clock(1000)
	c.set_clock(500)
	ok(int(c.now_ms) == 1000, "REQ-0010-68: set_clock with an earlier instant does not rewind now_ms (%s)" % str(c.now_ms))
	c.set_clock(BIG_MS)
	ok(int(c.now_ms) == BIG_MS, "REQ-0010-92: set_clock keeps 2^53+1 exact (no float rounding): %s" % str(c.now_ms))
	c.set_clock(5)
	ok(int(c.now_ms) == BIG_MS, "REQ-0010-68: ... and still never goes back")
	# landing instant: taken from the clock fed BEFORE new_game, monotone even if the device clock jumped back first
	var l: Variant = Sim.new()
	l.use_inventory = true
	l.use_catalog = true
	l.use_main_capsule = true
	l.set_clock(CLOCK_T)
	l.set_clock(CLOCK_T - 7000)   # the device clock jumped back before the landing
	l.new_game(_gen(Scenarios.LAT, Scenarios.LON), false)
	ok(int(l.main_capsule.landed_at) == CLOCK_T and int(l.main_capsule.grace_start) == CLOCK_T, "REQ-0010-35/68: landed_at is the (monotone) clock at landing, %s wanted %d" % [str(l.main_capsule.landed_at), CLOCK_T])
	l.set_clock(CLOCK_T + 12345)
	l.set_clock(CLOCK_T - 99999)
	ok(int(l.main_capsule.landed_at) == CLOCK_T and int(l.main_capsule.grace_start) == CLOCK_T, "REQ-0010-92: later clock pushes (forward or back) never rewrite the landing fact")
	# no clock fed at all: the explicit «not given» state, and still a deterministic world
	var n1: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	var n2: Variant = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), true, true, true)
	ok(Persistence.world_hash(n1) == Persistence.world_hash(n2), "REQ-0010-92: without any clock input the ON world is still deterministic (twin hashes agree)")
	# the same set of time inputs (rollbacks and repeats included) -> the same world
	var a: Variant = _on_real(CLOCK_T)
	var b: Variant = _on_real(CLOCK_T)
	b.set_clock(CLOCK_T - 500)
	for t in 50:
		a.update(Scenarios.DT)
		b.update(Scenarios.DT)
		_topup(a)
		_topup(b)
	a.set_clock(CLOCK_T + 1000)
	b.set_clock(CLOCK_T + 1000)
	b.set_clock(CLOCK_T + 200)
	for t in 50:
		a.update(Scenarios.DT)
		b.update(Scenarios.DT)
		_topup(a)
		_topup(b)
	ok(int(a.now_ms) == int(b.now_ms) and int(a.now_ms) == CLOCK_T + 1000, "REQ-0010-68: twin clocks with rollbacks/repeats end on the same now_ms (%s / %s)" % [str(a.now_ms), str(b.now_ms)])
	ok(Persistence.world_hash(a) == Persistence.world_hash(b), "REQ-0010-92: the same effective time inputs (rollbacks and repeats ignored) -> the same world_hash")
	for s in [c, l, n1, n2, a, b]:
		_dispose(s)


# =============================================================================================
# REQ-0010-92: alias-proof wall-clock tripwire. The W1a scan looks for `Time.get_…(` / `OS.get_…time(` CALLS; an alias
# (`const T = Time`), a system-clock provider or `Engine` ticks would slip past it. Nothing in the sim path may even NAME
# the time/OS singletons or the device-clock provider.
# =============================================================================================
func _t_no_wallclock_alias_proof() -> void:
	var re: RegEx = RegEx.new()
	re.compile("(^|[^.\\w\"])(Time|OS|DateTime)\\b|SystemClock|Engine\\.get_(ticks|physics|process)|get_unix_time|get_ticks_(msec|usec)")
	var files: Array = ["res://scripts/sim.gd", "res://scripts/persistence.gd", "res://scripts/world_gen.gd"]
	for dir_path in ["res://scripts/sim", "res://scripts/kernel"]:
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				files.append(dir_path + "/" + f)
	var offenders: Array = []
	for path in files:
		var code: PackedStringArray = PackedStringArray()
		for line in FileAccess.get_file_as_string(String(path)).split("\n"):
			var stripped: String = String(line).strip_edges()
			if not stripped.begins_with("#"):
				code.append(String(line).get_slice("#", 0))
		var m: RegExMatch = re.search("\n".join(code))
		if m != null:
			offenders.append("%s «%s»" % [String(path).trim_prefix("res://scripts/"), m.get_string()])
	ok(files.size() > 20, "REQ-0010-92: the alias-proof scan covers the sim path (%d files)" % files.size())
	ok(offenders.is_empty(), "REQ-0010-92: nothing in the sim path names Time/OS/DateTime/SystemClock/Engine ticks/get_unix_time — %s" % ("clean" if offenders.is_empty() else ", ".join(PackedStringArray(offenders))))
