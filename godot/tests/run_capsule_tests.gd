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
#
# WAVE 0010-W2a (appended after the W1b block): the levels table + upgrade_capsule + the invested ledger.
# REQ-0010-11/91 (ONE table in the catalog data, rows 0..5, the code holds none of its numbers — a grep AND an injected table that
# changes behaviour; a 7th row needs no code), 12 (buffs(0) empty even when the data says otherwise), 13 (atomic debit: backpack
# FIRST, then the stock only while the hero stands in the zone, edge inclusive; refusal = the first reason, nothing debited; level 5
# is the top), 14 + 35 (ledger == the units that actually left, measured around the call; every level/ledger change moves
# world_hash; JSON round trip keeps ints; records handed out are copies), 17 (one axis: a row is {level,cost,radius,core_hp,buffs},
# one upgrade entry point), 76 (backpack-then-stock, the same cmd id in the same tick pays once, no id = no dedup), 79 (no
# hunger/cold/sleep key anywhere in the table), 82 (invested key order), 88 (a level-5 save against a lower/higher/one-row table:
# clamp, ledger as is, defence recomputed; corrupt ledgers refused), 96/97 (death leaves the ledger and stock; upgrading summons
# no body), plus a seeded property run against an INDEPENDENT oracle (measured funds + the catalog FILE + the data's metric).
# Not testable in this wave: «захист(L) впливає на resolve_raid» (REQ-0010-17, resolve_raid is W3a), drop of invested by a raid (W3a).
# WAVE 0010-W2b (appended after the W2a block): the control zone and the buffs on the hero and on the processes.
# REQ-0010-15 (the SAME act inside / ON the edge / one cell outside gives a different result on every hook — gather time, melee
# damage, bench crafting, research; the edge is inclusive; the metric is Chebyshev so the CORNER (R,R) is in and (R+1,R) is out; the
# hero's cell is floor(px),floor(py); each hook reads ITS OWN key and the CURRENT level's row, not a product of the rows below it; a
# buff multiplies capacity that exists — no bench, no research table → nothing), 16 (radius(L+1) >= radius(L) on the real table and on
# synthetic ones; every zone is a subset of the next level's zone on the 5 spawn presets; the ring itself is W4a — not testable here),
# 12 (level 0: no buff, any key, any cell, inside the R0 zone; ON level 0 is BIT-EXACT the OFF world), 79 (a need-key in the data is
# not a buff and moves no body need), 80 (no retroactivity: a level drop/rise in the middle of a craft or a research project moves
# neither the accumulated timer nor the progress — the next step simply adds at the NEW rate; the benches outside the shrunk zone keep
# working at 1.0 and nothing is lost or doubled), 88 (a level-5 save against a lower table: the buffs are the clamped row's), 01 (the
# hooks are inert under flag OFF even with a stray record + table), D9 (the node tooltip's time is the time the sim then uses), D13
# (twin worlds + a resume payload cut mid-craft stay in lock-step). Expectations come from the table the TEST builds (distinct, binary-
# exact buff values per key and per level, radii 2,3,5,6,8,9) or from the catalog FILE, never from capsule.gd.
# CLOSEOUT of the integrity blockers on W1a/W1b (guards that survived deletion — F3): `_t_on_patrol_not_spawned`,
# `_t_on_director_raid_dropped`, `_t_on_session_travel_refused` (after `_t_no_eternal_siege`) and the respawn_anchor WIRING
# checks inside `_t_respawn_seams` (REQ-0010-09: what Session.respawn hands to sim.respawn_new_pawn). Each fails when its guard is removed.
# WAVE 0010-W2b-b (appended after the W2b block; closes the two integrity gaps found by mutation): the ZONE-EDGE BAND of the node tooltip
# (REQ-0010-15 x D9: the hint == the real a.dur at every frame step the game feeds; a stated limit for coarse steps; an edge sweep where the walk meets
# the reach circle exactly on a cell border; nodes walled in on 4 / 8 sides) and the metric's SAFE FAILURE (REQ-0010-80: an unknown metric = «no zone»,
# a missing key = Chebyshev), plus a characterization pin of the OFF-world haul resume radius moved to sim/haul.gd (REQ-0010-01/D4).
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
const HudModel = preload("res://scripts/ui/hud_model.gd")

const PAD_N := 16  # the flat grass pad of the W1a tests (spawn (8,8), like the S0 `_flat` pad)

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
	_t_on_patrol_not_spawned()
	_t_on_director_raid_dropped()
	_t_on_session_travel_refused()
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
	# --- wave 0010-W2a ---
	_t_levels_table_data()
	_t_table_drives_code()
	_t_upgrade_walk()
	_t_upgrade_refusals()
	_t_upgrade_reach()
	_t_upgrade_sources()
	_t_upgrade_dedupe()
	_t_upgrade_hash_roundtrip()
	_t_invested_key_order()
	_t_save_clamp()
	_t_ledger_save_compat()
	_t_range_extension()
	_t_upgrade_side_effects()
	_t_upgrade_death_and_roster()
	_t_one_axis_api()
	_t_upgrade_property()
	# --- wave 0010-W2b ---
	_t_zone_shape()
	_t_zone_monotone()
	_t_buff_hero_hooks()
	_t_buff_one_key_each()
	_t_buff_stacks_with_gear()
	_t_buff_keys_closed()
	_t_buff_level0_and_catalog()
	_t_buff_after_real_upgrades()
	_t_buff_craft_process()
	_t_buff_craft_no_retroactivity()
	_t_buff_research_process()
	_t_buff_research_no_retroactivity()
	_t_buff_gather_melee_e2e()
	_t_buff_inspector_one_truth()
	_t_buff_off_inert()
	_t_buff_pure_and_stateless()
	_t_buff_twin_and_resume()
	_t_buff_table_clamp()
	# --- wave 0010-W2b-b (closing integrity gaps: the zone-edge band of the node tooltip, the metric's safe failure) ---
	_t_buff_inspector_band()
	_t_buff_inspector_band_walled_in()
	_t_buff_inspector_band_ringed()
	_t_buff_inspector_band_limit()
	_t_buff_inspector_band_edge()
	_t_zone_metric_safe_failure()
	_t_zone_metric_missing_and_live()
	_t_off_haul_resume_radius()
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


# ---------------------------------------------------------------------------------------------
# W1a closeout (integrity blocker, F3): three guards of the indestructible capsule had NO test that could fail — deleting
# any of them left the suite green. Each test below has an OFF control (the probe must be able to SEE the thing the guard
# suppresses) and was checked against the guard's removal on a scratch copy of the tree. Expectations come from OD-58
# («перший NPC-рейд — лише після першої прокачки»; no upgrade exists in W1, so every capsule is level 0), REQ-0010-65
# (level 0 is never raided), REQ-0010-34 (the flag does not shift the threat stream), D4/D8 (no signal without a cause),
# REQ-0010-04/75 (the capsule is one and is never wiped by a region swap) — not from the guards' bodies.
# ---------------------------------------------------------------------------------------------
# The patrol channel. A patrol robot is a machine that marches on base_center() = the capsule; at level 0 that is a machine
# raid on a capsule that cannot be hurt (critique-0010 #2: an endless siege), and OD-58 gives level 0 no NPC raid at all.
# `_quiet` parks patrol.next at 1e9, so no other test ever sees a patrol: here its roll falls due on the first tick.
func _patrol_probe(capsule: bool) -> Dictionary:
	var s: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), true, true, capsule)
	_quiet(s)
	var away: Vector2i = _far_cell(s, Vector2i(8, 8), 6)
	s.player.px = float(away.x) + 0.5
	s.player.py = float(away.y) + 0.5
	s.patrol.timer = 0.0
	s.patrol.next = 0.0
	var bots_peak: int = 0
	for t in 600:
		s.update(Scenarios.DT)
		_topup(s)
		var bots: int = 0
		for e in s.enemies:
			if String(e.get("kind", "raider")) == "bot":
				bots += 1
		bots_peak = maxi(bots_peak, bots)
	var out: Dictionary = {"bots_peak": bots_peak, "wave": int(s.patrol.wave), "next": float(s.patrol.next), "enemies": s.enemies.size()}
	_dispose(s)
	return out


func _t_on_patrol_not_spawned() -> void:
	var off: Dictionary = _patrol_probe(false)
	var rolled: bool = float(off.next) > 0.0 and float(off.next) < 1.0e9
	ok(int(off.bots_peak) >= 1 and int(off.wave) >= 1 and rolled,
		"OD-58 control (OFF): the same 600 ticks DO bring a patrol and re-arm its roll — the probe can see one (bots peak %d, wave %d, next=%s)" % [int(off.bots_peak), int(off.wave), str(off.next)])
	var on: Dictionary = _patrol_probe(true)
	ok(int(on.bots_peak) == 0 and int(on.wave) == 0 and int(on.enemies) == 0,
		"OD-58/REQ-0010-65/critique-0010 #2: at ON no patrol robot ever enters a level-0 capsule's region (bots peak %d, wave %d, enemies %d)" % [int(on.bots_peak), int(on.wave), int(on.enemies)])
	ok(is_equal_approx(float(on.next), float(off.next)),
		"REQ-0010-34: ... yet the seeded roll still happened, with the SAME value as at OFF — the threat stream does not fork on the flag (ON next=%s, OFF next=%s)" % [str(on.next), str(off.next)])


# The director channel. D8 «немає субстрату — нема ефекту: payload скидається, не імітується»: at ON a raid incident has no
# raider to bring (OD-58), so it must not arm the alarm either — a «НАБЛИЖАЄТЬСЯ РЕЙД» banner with no raid behind it is a
# false signal (D4/D8, REQ-0010-19 «найгучніший сигнал відповідає цьому рейду») that nothing would ever retire.
func _director_probe(capsule: bool) -> Dictionary:
	var s: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), true, true, capsule)
	_quiet(s)
	s.time.day = 6
	s.time.frac = 0.5
	Director.apply(s, {"incident": "raid", "count": 3, "faction": "Тестові мародери"})
	var said: bool = false
	for line in _texts(s):
		if String(line).contains("Режисер: рейдери на підході"):
			said = true
	# read right after apply: at OFF the wave itself (spawn_wave) consumes the stored payload a few seconds later
	var out: Dictionary = {"banner0": String(s.banner), "warned": bool(s.raid.get("warned", false)), "has_director": (s.raid as Dictionary).has("director"), "said": said}
	for t in 300:
		s.update(Scenarios.DT)
		_topup(s)
	out["banner"] = String(s.banner)
	_dispose(s)
	return out


func _t_on_director_raid_dropped() -> void:
	var off: Dictionary = _director_probe(false)
	ok(String(off.banner0) != "" and bool(off.warned) and bool(off.has_director) and bool(off.said),
		"D8 control (OFF): Director.apply(raid) arms the legacy cycle — banner «%s», warned=%s, payload=%s, feed line=%s" % [String(off.banner0), str(off.warned), str(off.has_director), str(off.said)])
	var on: Dictionary = _director_probe(true)
	ok(String(on.banner0) == "", "D4/D8: at ON a directed raid raises NO «НАБЛИЖАЄТЬСЯ РЕЙД» banner (banner «%s»)" % String(on.banner0))
	ok(String(on.banner) == "", "D4/D8: ... and after 30 s of sim there is still no banner — a false alarm would sit there forever (banner «%s»)" % String(on.banner))
	ok(not bool(on.warned), "D8: ... raid.warned stays false (nothing armed)")
	ok(not bool(on.has_director), "D8: ... the payload is dropped, not stored for later (no hidden queue that a future raid gate could pop)")
	ok(not bool(on.said), "D8: ... and the feed has no «Режисер: рейдери на підході» line (a fake signal)")


# The session channel. travel_to at ON is refused (REQ-0010-04 «рівно одна капсула», REQ-0010-75: a region swap wipes the
# buildings and with them the capsule). The second layer, Sim.arrive_region, refuses too — so the world itself stays intact
# even if the Session guard is gone; what only the Session guard prevents is the SIDE EFFECTS of a half-run travel: the
# region committed into the store (hash chain advanced), the false «🛬 Нова місцевість» success line, the missing error.
# A refused command must be a no-op with a reason.
func _travel_session(capsule: bool) -> Variant:
	var sess: Variant = SessionScript.new()
	sess.autosave = false
	sess.store = Persistence.store_new()
	sess.sim = _sim_with(_gen(Scenarios.LAT, Scenarios.LON), capsule, capsule, capsule)
	sess.sim.messages.clear()
	return sess


func _arrival_line(s: Variant) -> bool:
	for line in _texts(s):
		if String(line).contains("🛬") or String(line).contains("↩"):
			return true
	return false


func _t_on_session_travel_refused() -> void:
	var off: Variant = _travel_session(false)
	var lat_off: float = float(off.sim.map.lat)
	off.travel_to(Scenarios.LAT2, Scenarios.LON2, "Львів")
	ok(not is_equal_approx(float(off.sim.map.lat), lat_off) and _arrival_line(off.sim) and off.last_error == &"" and (off.store.regions as Dictionary).size() == 1,
		"REQ-0010-04 control (OFF): travel_to commits the old region, flies to the other one and logs the arrival — the probe can see a travel (last_error=%s)" % str(off.last_error))
	_dispose(off.sim)
	var on: Variant = _travel_session(true)
	var tile: Vector2i = _cap_tile(on.sim)
	var before: Dictionary = {"hash": Persistence.world_hash(on.sim), "buildings": var_to_str(on.sim.buildings), "bgrid": var_to_str(on.sim.bgrid), "capsule": var_to_str(on.sim.main_capsule),
		"store": var_to_str(on.store), "regions": var_to_str(on.sim.regions), "map": float(on.sim.map.lat)}
	on.travel_to(Scenarios.LAT2, Scenarios.LON2, "Львів")
	ok(Persistence.world_hash(on.sim) == String(before.hash), "REQ-0010-04/75: at ON travel_to leaves world_hash unchanged")
	ok(var_to_str(on.sim.buildings) == String(before.buildings) and var_to_str(on.sim.bgrid) == String(before.bgrid), "REQ-0010-75: ... buildings and bgrid untouched (the capsule is not wiped)")
	ok(var_to_str(on.sim.main_capsule) == String(before.capsule) and _cap_problem(on.sim, tile) == "", "REQ-0010-75: ... main_capsule record untouched and consistent (%s)" % _cap_problem(on.sim, tile))
	ok(var_to_str(on.sim.regions) == String(before.regions) and is_equal_approx(float(on.sim.map.lat), float(before.map)), "REQ-0010-04: ... regions and the active map did not change")
	var committed: int = (on.store.regions as Dictionary).size()
	ok(var_to_str(on.store) == String(before.store) and committed == 0, "REQ-0010-04: ... a refused travel commits nothing — the store and its hash chain are untouched (store regions %d)" % committed)
	ok(_texts(on.sim).has(MainCapsule.MSG_NO_TRAVEL), "REQ-0010-04/06: ... the feed carries the refusal reason (MainCapsule.MSG_NO_TRAVEL)")
	ok(on.last_error != &"", "REQ-0010-04/06: ... and the caller gets the reason as an error (Session.last_error=%s)" % str(on.last_error))
	ok(not _arrival_line(on.sim), "REQ-0010-04: ... and NO false «🛬 Нова місцевість» / «↩ Повернення» success line")
	_dispose(on.sim)


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
	var anchors: Array = []   # every anchor that reached respawn_new_pawn — the wiring of the respawn_anchor seam (REQ-0010-09)

	func respawn_new_pawn(anchor: Dictionary = {}) -> void:
		anchors.append(anchor.duplicate(true))
		super.respawn_new_pawn(anchor)

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
		ok((sim.anchors as Array).is_empty(), "%s setup: nothing has respawned yet (anchors seen %d)" % [label, (sim.anchors as Array).size()])
		sess.respawn()
		ok(not bool(sim.dead) and _hero_cell(sim) == pos, "%s: Session.respawn puts the hero exactly on the cell the anchor announced (D9: one truth) — hero %s, anchor %s" % [label, str(_hero_cell(sim)), str(pos)])
		ok(_cap_problem(sim, tile) == "" and int(sim.source_calls) == 1, "%s: the capsule is intact and the body came through the seam" % label)
		# the WIRING: «Місце респавну задає шов respawn_anchor» — Session.respawn must hand the sim exactly that anchor, once.
		# The position check above cannot see a dropped anchor (the sim falls back to the capsule tile and the nearest free ring
		# is the same cell), so the argument itself is recorded at the sim's door.
		var seen: Array = sim.anchors
		ok(seen.size() == 1, "%s: Session.respawn reaches sim.respawn_new_pawn exactly once (%d calls)" % [label, seen.size()])
		var got: Dictionary = seen[0] if seen.size() > 0 else {}
		ok(String(got.get("region_key", "")) != "", "%s: the anchor handed over has a non-empty region_key (%s)" % [label, str(got.get("region_key", ""))])
		ok(got.get("pos") is Vector2i and got.get("pos") != NO_CELL, "%s: ... and a real Vector2i cell, not the NO_CELL «no position» sentinel (%s)" % [label, str(got.get("pos"))])
		ok(var_to_str(got) == var_to_str(anchor), "%s: ... and it IS MainCapsule.respawn_anchor(session) (handed %s, seam %s)" % [label, str(got), str(anchor)])
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


# =============================================================================================
# WAVE 0010-W2a — helpers (the capsule_levels table, upgrade_capsule, the invested ledger)
# Expectations come from REQ-0010-11/12/13/14/17/35/76/79/82/88/91/97 and OD-58/59, NOT from capsule.gd: the data oracle is the
# catalog FILE read here independently (never through MainCapsule.table), the resource accounting is measured around the call
# (backpack + stock before/after), and the zone test uses the metric the data names. A red test here is a finding.
# =============================================================================================
const CATALOG_FILE := "res://content/catalog.json"
const PAY_IDS: Array = ["wood", "stone", "scrap", "planks", "components"]   # ids the backpack AND the stock both speak
const NEED_WORDS: Array = ["hunger", "cold", "sleep", "rest", "thirst", "need", "warm", "heat", "fatigue", "stamina"]   # S2 (REQ-0010-79)
const ROSTER_WORDS: Array = ["clone", "roster", "genome", "implant", "orbit", "pawn", "body", "dna"]   # the Orbit's business (REQ-0010-97)

var _raw_cache: Dictionary = {}


func _raw_table() -> Dictionary:
	if _raw_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_FILE))
		if parsed is Dictionary:
			_raw_cache = (parsed as Dictionary).get("capsule_levels", {})
	return _raw_cache


func _raw_rows() -> Array:
	return _raw_table().get("levels", [])


# a deep copy of the catalog table: tests may edit it, the catalog (and MainCapsule's cache) must never see it
func _table_copy() -> Dictionary:
	return _raw_table().duplicate(true)


# {res: int} price of level L in a `levels` array (JSON floats -> ints); {} outside the table
func _cost_of(rows: Array, L: int) -> Dictionary:
	var out: Dictionary = {}
	if L < 0 or L >= rows.size():
		return out
	var src: Dictionary = (rows[L] as Dictionary).get("cost", {})
	for k in src:
		out[String(k)] = int(src[k])
	return out


func _same_numbers(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or absf(float(a[k]) - float(b[k])) > 1.0e-9:
			return false
	return true


# a table whose numbers appear NOWHERE in the catalog or the code: a hard-coded constant shows up as a mismatch. Cost keys are
# inserted in a NON-alphabetical order (wood, stone, planks) on purpose.
func _synth_table(n_levels: int) -> Dictionary:
	var rows: Array = []
	for L in n_levels:
		var cost: Dictionary = {}
		if L >= 1:
			cost["wood"] = 7 + 3 * L
			cost["stone"] = 2 * L
		if L >= 2:
			cost["planks"] = L + 1
		var buffs: Dictionary = {}
		if L >= 1:
			buffs["gather_mult"] = 1.0 + 0.07 * float(L)
			buffs["craft_mult"] = 1.0 + 0.03 * float(L)
		rows.append({"level": L, "cost": cost, "radius": 4 + L, "core_hp": 100.0 * float(L + 1) + 7.0, "buffs": buffs})
	return {"version": 1, "status": "proposed", "metric": "chebyshev", "levels": rows}


func _pack_set(s: Variant, res: String, n: int) -> void:
	for sl in (s.player.inv as Array):
		if String(sl.id) == res:
			sl.id = ""
			sl.n = 0
	if n > 0:
		var left: int = Inventory.add(s, res, n)
		if left != 0:
			ok(false, "setup: the backpack could not hold %d x %s (%d left over)" % [n, res, left])


func _fund(s: Variant, res: String, in_pack: int, in_stock: int) -> void:
	_pack_set(s, res, in_pack)
	s.stock[s.res_key(res)] = in_stock


func _wipe(s: Variant) -> void:
	for id in PAY_IDS:
		_fund(s, String(id), 0, 0)


func _have(s: Variant, res: String) -> int:
	return Inventory.count(s, res) + int(s.res_amount(res))


func _funds_sig(s: Variant) -> String:
	return var_to_str([s.player.inv, s.stock])


func _put_hero(s: Variant, c: Vector2i) -> void:
	s.player.px = float(c.x) + 0.5
	s.player.py = float(c.y) + 0.5
	s.player.action = null


func _half(n: int) -> int:
	return int(floor(float(n) * 0.5))


# fund `cost` exactly, split between the backpack and the stock (the backpack gets `pack_part` of each)
func _fund_cost(s: Variant, cost: Dictionary, pack_part: float) -> void:
	for res in cost:
		var c: int = int(cost[res])
		var p: int = mini(c, int(floor(float(c) * pack_part)))
		_fund(s, String(res), p, c - p)


# an ON pad at level `n` of the REAL catalog table, reached through real upgrades; funds end at zero
func _leveled(n: int) -> Variant:
	var s: Variant = _on_pad()
	_wipe(s)
	var rows: Array = _raw_rows()
	for L in range(1, n + 1):
		_fund_cost(s, _cost_of(rows, L), 0.4)
		var r: Dictionary = s.upgrade_capsule()
		if not bool(r.get("ok", false)):
			ok(false, "setup: upgrade to level %d failed: %s" % [L, str(r)])
	return s


func _ledger_sig(s: Variant) -> String:
	return var_to_str((s.main_capsule as Dictionary).get("invested", {}))


func _all_keys(v: Variant, out: Array, skip_key: String = "") -> void:
	if v is Dictionary:
		for k in (v as Dictionary):
			if String(k) == skip_key:
				continue
			out.append(String(k))
			_all_keys((v as Dictionary)[k], out, skip_key)
	elif v is Array:
		for e in (v as Array):
			_all_keys(e, out, skip_key)


func _first_word_in(keys: Array, words: Array) -> String:
	for k in keys:
		for w in words:
			if String(k).to_lower().contains(String(w)):
				return "%s ~ %s" % [String(k), String(w)]
	return ""


# =============================================================================================
# REQ-0010-11 / 12 / 16 / 17 / 79 / 97 — the ONE table in the catalog DATA; no needs buff; no clone entry; no second axis;
# the code holds none of its numbers (grep)
# =============================================================================================
func _t_levels_table_data() -> void:
	var t: Dictionary = _raw_table()
	var rows: Array = t.get("levels", [])
	ok(not t.is_empty() and rows.size() == 6, "REQ-0010-11: catalog.json carries ONE capsule_levels table with exactly 6 rows (levels 0..5, OD-56) — %d rows" % rows.size())
	var contiguous: bool = true
	for i in rows.size():
		contiguous = contiguous and int((rows[i] as Dictionary).get("level", -1)) == i
	ok(contiguous, "REQ-0010-11: the rows are levels 0,1,..,5 in order (no gap, no duplicate)")
	ok(["proposed", "approved"].has(String(t.get("status", ""))), "OD-59/60: the numbers carry an explicit status ('proposed' until the owner approves) — '%s'" % String(t.get("status", "")))
	ok(String(t.get("metric", "")) == "chebyshev", "REQ-0010-80: the zone metric is named in the data (this suite's zone oracle needs it) — '%s'" % String(t.get("metric", "")))
	# data -> code: every number the code reports is the file's number
	var s: Variant = _on_pad()
	ok(MainCapsule.max_level(s) == rows.size() - 1, "REQ-0010-11: max_level is the table size - 1 (code max %d, data rows %d)" % [MainCapsule.max_level(s), rows.size()])
	var bad: Array = []
	for L in rows.size():
		var raw: Dictionary = rows[L]
		var row: Dictionary = MainCapsule.row(s, L)
		if not _same_numbers(row.get("cost", {}), _cost_of(rows, L)):
			bad.append("cost[%d]" % L)
		if int(MainCapsule.radius(s, L)) != int(raw.radius) or int(row.get("radius", -1)) != int(raw.radius):
			bad.append("radius[%d]" % L)
		if absf(float(MainCapsule.core_hp(s, L)) - float(raw.core_hp)) > 1.0e-6 or absf(float(row.get("core_hp", -1.0)) - float(raw.core_hp)) > 1.0e-6:
			bad.append("core_hp[%d]" % L)
		if L >= 1 and not _same_numbers(MainCapsule.buffs(s, L), raw.get("buffs", {})):
			bad.append("buffs[%d]" % L)
	ok(bad.is_empty(), "REQ-0010-11: cost/radius/core_hp/buffs of every level are read from the data unchanged — %s" % ("ok" if bad.is_empty() else ", ".join(PackedStringArray(bad))))
	# REQ-0010-12: level 0 is bare
	ok(_cost_of(rows, 0).is_empty() and (rows[0] as Dictionary).get("buffs", {"x": 1}).is_empty() and MainCapsule.buffs(s, 0).is_empty(),
		"REQ-0010-12: level 0 costs nothing and buffs(0) is empty (data AND code)")
	# REQ-0010-12 is a RULE, not a property of today's numbers: a table that (wrongly) hangs a buff on level 0 still gives level 0 none
	var tricky: Dictionary = _synth_table(3)
	tricky.levels[0].buffs = {"gather_mult": 1.5, "craft_mult": 1.2}
	s.capsule_table = tricky
	ok(MainCapsule.buffs(s, 0).is_empty() and not MainCapsule.buffs(s, 1).is_empty(), "REQ-0010-12: level 0 gives NO buff even when the data lists one (level 1 still does) — buffs(0)=%s" % str(MainCapsule.buffs(s, 0)))
	s.capsule_table = {}
	# REQ-0010-16/17: the zone never shrinks, the ONE defence parameter changes with every level
	var mono: bool = true
	var strict: bool = true
	var grows: bool = true
	var prev_total: int = 0
	for L in range(1, rows.size()):
		mono = mono and int(MainCapsule.radius(s, L)) >= int(MainCapsule.radius(s, L - 1))
		strict = strict and float(MainCapsule.core_hp(s, L)) > float(MainCapsule.core_hp(s, L - 1))
		var total: int = 0
		for res in _cost_of(rows, L):
			total += int(_cost_of(rows, L)[res])
		grows = grows and total > prev_total
		prev_total = total
	ok(mono, "REQ-0010-16: radius(L+1) >= radius(L) for every level")
	ok(strict, "REQ-0010-17: an upgrade CHANGES the defence parameter — core_hp(L+1) > core_hp(L) for every level")
	ok(grows, "P1: the price of a level grows with the level (every level costs more units than the one before)")
	# prices: only resources the game knows, positive whole numbers
	var priced: bool = true
	for L in range(1, rows.size()):
		var c: Dictionary = _cost_of(rows, L)
		priced = priced and not c.is_empty()
		for res in c:
			priced = priced and GameData.RES.has(res) and int(c[res]) > 0 and Inventory.stack_max(String(res)) > 0 and s.res_key(res) != ""
	ok(priced, "REQ-0010-11/13: every level 1..5 has a price in known resources, positive whole units")
	# REQ-0010-79 / 97 / 17: no body-need multiplier, no clone/roster entry, no second axis — anywhere in the table
	var keys: Array = []
	_all_keys(t, keys, "cost")
	ok(_first_word_in(keys, NEED_WORDS) == "", "REQ-0010-79: no key of the table touches hunger/cold/sleep/thirst/needs — %s" % _first_word_in(keys, NEED_WORDS))
	ok(_first_word_in(keys, ROSTER_WORDS) == "", "REQ-0010-97: no key of the table grants/levels clones, genome, implants or Orbit things — %s" % _first_word_in(keys, ROSTER_WORDS))
	var axis: String = _first_word_in(t.keys(), ["axis", "axes", "branch", "track", "tree"])
	var row_ok: bool = true
	for r in rows:
		for k in (r as Dictionary):
			row_ok = row_ok and ["level", "cost", "radius", "core_hp", "buffs"].has(String(k))
	ok(axis == "" and row_ok, "REQ-0010-17: ONE axis — a row is exactly {level,cost,radius,core_hp,buffs} and the table has no axes/branches (%s)" % axis)
	# REQ-0010-11 «код не містить цих чисел»: no number of the table is a literal in the capsule module (comments stripped)
	var nums: Dictionary = {}
	for L in rows.size():
		var rw: Dictionary = rows[L]
		for k in (rw.get("cost", {}) as Dictionary):
			nums[str(int(rw.cost[k]))] = "cost[%d].%s" % [L, String(k)]
		nums[str(int(rw.radius))] = "radius[%d]" % L
		nums[str(int(rw.core_hp))] = "core_hp[%d]" % L
		for k in (rw.get("buffs", {}) as Dictionary):
			nums["%s" % str(float(rw.buffs[k]))] = "buffs[%d].%s" % [L, String(k)]
	var code: PackedStringArray = PackedStringArray()
	for line in FileAccess.get_file_as_string("res://scripts/sim/capsule.gd").split("\n"):
		var stripped: String = String(line).strip_edges()
		if not stripped.begins_with("#"):
			code.append(String(line).get_slice("#", 0))
	var body: String = "\n".join(code)
	var hit: String = ""
	for num in nums:
		var n_str: String = String(num)
		if n_str.length() < 2 and not n_str.contains("."):
			continue   # 0..9 are everyday literals (levels, indexes); only the table's distinctive numbers are searched
		var re: RegEx = RegEx.new()
		re.compile("(?<![\\w.])" + n_str.replace(".", "\\.") + "(?![\\w.])")
		if re.search(body) != null:
			hit = "%s (%s)" % [n_str, String(nums[num])]
			break
	ok(hit == "", "REQ-0010-11: capsule.gd holds no number of the table as a literal — %s" % ("clean" if hit == "" else hit))
	_dispose(s)


# =============================================================================================
# REQ-0010-11 / 91: the CODE follows the table — a table with other numbers and another length changes behaviour, nothing leaks
# between sims, and the table is never mutated by the code that reads it
# =============================================================================================
func _t_table_drives_code() -> void:
	var catalog_max: int = _raw_rows().size() - 1
	var s: Variant = _on_pad()
	var syn: Dictionary = _synth_table(4)
	var syn_snap: String = var_to_str(syn.duplicate(true))
	s.capsule_table = syn
	ok(MainCapsule.max_level(s) == 3, "REQ-0010-11/91: a 4-row table in s.capsule_table makes max_level 3 (%d)" % MainCapsule.max_level(s))
	var follows: bool = true
	var rows: Array = syn.levels
	for L in 4:
		var rw: Dictionary = rows[L]
		follows = follows and _same_numbers(MainCapsule.row(s, L).cost, _cost_of(rows, L)) and MainCapsule.radius(s, L) == int(rw.radius) \
			and absf(MainCapsule.core_hp(s, L) - float(rw.core_hp)) < 1.0e-6 and _same_numbers(MainCapsule.buffs(s, L), rw.buffs if L >= 1 else {})
	ok(follows, "REQ-0010-11: row/radius/core_hp/buffs of every level follow the injected table (no number is baked into the code)")
	var other: Variant = _on_pad()
	ok(MainCapsule.max_level(other) == catalog_max, "REQ-0010-11: the override of one sim does not leak into another (other max %d, catalog %d)" % [MainCapsule.max_level(other), catalog_max])
	s.capsule_table = _synth_table(9)
	ok(MainCapsule.max_level(s) == 8, "REQ-0010-91: a 9-row table -> max_level 8 (the range is the table's length, not a constant) — %d" % MainCapsule.max_level(s))
	s.capsule_table = {}
	ok(MainCapsule.max_level(s) == catalog_max, "REQ-0010-11: clearing the override returns to the catalog table (%d)" % MainCapsule.max_level(s))
	# an upgrade charges the INJECTED numbers and leaves the injected table untouched; the ledger does not alias a table dict
	s.capsule_table = syn
	_wipe(s)
	_fund_cost(s, _cost_of(rows, 1), 0.5)
	var r: Dictionary = s.upgrade_capsule()
	ok(bool(r.get("ok", false)) and s.capsule_level() == 1 and _have(s, "wood") == 0 and _have(s, "stone") == 0, "REQ-0010-13: the price charged is the injected row 1 (wood %d, stone %d) — result %s" % [int(rows[1].cost.wood), int(rows[1].cost.stone), str(r)])
	var inv: Dictionary = s.main_capsule.invested
	ok(inv.has("1") and _same_numbers(inv["1"], _cost_of(rows, 1)), "REQ-0010-14: invested[1] is the injected price — %s" % var_to_str(inv))
	ok(var_to_str(syn) == syn_snap, "REQ-0010-11: upgrade did not mutate the table it reads")
	s.main_capsule.invested["1"]["wood"] = int(s.main_capsule.invested["1"]["wood"]) + 1000
	ok(var_to_str(syn) == syn_snap and _same_numbers(MainCapsule.row(s, 1).cost, _cost_of(rows, 1)), "REQ-0010-11/14: editing the ledger afterwards does not edit the table (no aliasing of the price dict)")
	r["paid"]["wood"] = 5
	ok(int(s.main_capsule.invested["1"]["wood"]) == int(rows[1].cost.wood) + 1000 and var_to_str(syn) == syn_snap, "REQ-0010-14: the returned `paid` is a copy (editing it moves neither ledger nor table)")
	# the same on the CATALOG table: a real upgrade must not change what MainCapsule.table hands out (the cache is shared by every sim)
	var c: Variant = _on_pad()
	var cat_snap: String = var_to_str(MainCapsule.table(c))
	_wipe(c)
	_fund_cost(c, _cost_of(_raw_rows(), 1), 0.5)
	c.upgrade_capsule()
	c.main_capsule.invested["1"]["wood"] = 1
	ok(var_to_str(MainCapsule.table(c)) == cat_snap and var_to_str(MainCapsule.table(other)) == cat_snap, "REQ-0010-11: a real upgrade + a ledger edit leave the shared catalog table byte-identical")
	for x in [s, other, c]:
		_dispose(x)


# =============================================================================================
# REQ-0010-13 / 14 / 35: the whole ladder 0 -> 5 on the REAL table: exact debit, ledger == paid, hash moves every step
# =============================================================================================
func _t_upgrade_walk() -> void:
	var s: Variant = _on_pad()
	_wipe(s)
	var rows: Array = _raw_rows()
	var hashes: Dictionary = {Persistence.world_hash(s): 0}
	ok(s.capsule_level() == 0, "REQ-0010-12 setup: the capsule lands at level 0")
	for L in range(1, rows.size()):
		var cost: Dictionary = _cost_of(rows, L)
		_fund_cost(s, cost, 0.4)
		_fund(s, "components", 1, 2)   # a bystander the price does not ask for (not even at level 5): it must not move
		var before: Dictionary = {}
		for res in PAY_IDS:
			before[res] = _have(s, String(res))
		var led_before: String = _ledger_sig(s)
		var r: Dictionary = s.upgrade_capsule()
		ok(bool(r.get("ok", false)) and int(r.get("level", -1)) == L and s.capsule_level() == L, "REQ-0010-13: upgrade to level %d succeeds with exact funds — %s" % [L, str(r)])
		var exact: bool = true
		for res in PAY_IDS:
			var want: int = int(before[res]) - int(cost.get(res, 0))
			if _have(s, String(res)) != want:
				exact = false
		ok(exact, "REQ-0010-13: level %d took EXACTLY its price (backpack+stock measured around the call), nothing else" % L)
		var inv: Dictionary = s.main_capsule.invested
		ok(inv.has(str(L)) and _same_numbers(inv[str(L)], cost) and bool(_same_numbers(r.get("paid", {}), cost)), "REQ-0010-14: invested[%d] == the units that left the backpack/stock == `paid` (%s)" % [L, var_to_str(inv.get(str(L), {}))])
		ok(_ledger_sig(s) != led_before and inv.size() == L, "REQ-0010-14: the ledger gained exactly one level entry (keys: %s)" % str(inv.keys()))
		var h: String = Persistence.world_hash(s)
		ok(not hashes.has(h), "REQ-0010-35: world_hash after level %d is new (level + invested move the hash)" % L)
		hashes[h] = L
	var top: Dictionary = s.upgrade_capsule()
	ok(not bool(top.get("ok", true)) and s.capsule_level() == 5, "REQ-0010-91: level 5 is the top — one more is refused, level stays 5 (%s)" % str(top))
	_dispose(s)


# =============================================================================================
# REQ-0010-13: refusals — shortage / nothing / max / OFF: the FIRST reason and NO debit at all
# =============================================================================================
func _t_upgrade_refusals() -> void:
	var rows: Array = _raw_rows()
	var cost1: Dictionary = _cost_of(rows, 1)
	# (a) short by exactly one unit of ONE resource (the rest fully paid, split between the sources): refused, nothing moves
	for short_res in cost1:
		var s: Variant = _on_pad()
		_wipe(s)
		for res in cost1:
			var total: int = int(cost1[res]) - (1 if res == short_res else 0)
			_fund(s, String(res), _half(total), total - _half(total))
		var sig: String = _funds_sig(s)
		var led: String = _ledger_sig(s)
		var h: String = Persistence.world_hash(s)
		var r: Dictionary = s.upgrade_capsule()
		ok(not bool(r.get("ok", true)) and r.get("reason", &"") == &"cost", "REQ-0010-13: one unit of %s short -> refused with the cost reason — %s" % [String(short_res), str(r)])
		var miss: Dictionary = r.get("missing", {})
		ok(miss.size() == 1 and miss.has(short_res) and int(miss[short_res]) == 1, "REQ-0010-13: the reason names the missing resource and amount ({%s: 1}) — %s" % [String(short_res), str(miss)])
		ok(_funds_sig(s) == sig and _ledger_sig(s) == led and s.capsule_level() == 0 and Persistence.world_hash(s) == h, "REQ-0010-13: the refusal debited NOTHING (a fully paid resource keeps its units; world_hash unchanged)")
		_dispose(s)
	# (b) nothing funded: every price line is missing with its FULL amount; the first reason does not depend on dict insertion order
	var e: Variant = _on_pad()
	_wipe(e)
	var re: Dictionary = e.upgrade_capsule()
	var miss_all: Dictionary = re.get("missing", {})
	ok(_same_numbers(miss_all, cost1), "REQ-0010-13: with nothing funded the whole price is reported missing — %s vs %s" % [str(miss_all), str(cost1)])
	var asc: Array = miss_all.keys()
	var sorted_keys: Array = asc.duplicate()
	sorted_keys.sort()
	ok(asc == sorted_keys, "REQ-0010-13: the reasons come in ascending id order, so the FIRST one is a function of state (%s)" % str(asc))
	var syn: Dictionary = _synth_table(3)
	e.capsule_table = syn
	e.main_capsule.level = 1   # next row = synthetic level 2: {wood, stone, planks} inserted in that order
	var rs: Dictionary = e.upgrade_capsule()
	var keys2: Array = (rs.get("missing", {}) as Dictionary).keys()
	ok(keys2 == ["planks", "stone", "wood"], "REQ-0010-13: ... even when the table lists the price as wood, stone, planks (got %s)" % str(keys2))
	# (c) atomic over several resources: the covered line is NOT debited when another line fails
	var a: Variant = _on_pad()
	_wipe(a)
	_fund(a, "wood", int(cost1.wood), 0)             # wood fully in the backpack
	_fund(a, "stone", 0, int(cost1.stone) - 1)       # stone one short in the stock
	_fund(a, "scrap", 0, int(cost1.scrap))           # scrap fully in the stock
	var sig_a: String = _funds_sig(a)
	var ra: Dictionary = a.upgrade_capsule()
	ok(not bool(ra.get("ok", true)) and _funds_sig(a) == sig_a and a.capsule_level() == 0, "REQ-0010-13: atomic — wood and scrap were covered, stone was not: nothing was taken (%s)" % str(ra))
	# (d) the top: level 5 refuses with plenty of funds, nothing moves
	var m: Variant = _on_pad()
	m.main_capsule.level = 5
	for res in PAY_IDS:
		_fund(m, String(res), 40, 300)
	var sig_m: String = _funds_sig(m)
	var h_m: String = Persistence.world_hash(m)
	var rm: Dictionary = m.upgrade_capsule()
	ok(not bool(rm.get("ok", true)) and m.capsule_level() == 5 and _funds_sig(m) == sig_m and Persistence.world_hash(m) == h_m, "REQ-0010-13/91: at the max level upgrade is refused, level 5 stays, no debit, hash unchanged (%s)" % str(rm))
	# (e) OFF: no capsule -> a refusal with no side effect and no new key anywhere
	var off: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), true, true, false)
	var h_off: String = Persistence.world_hash(off)
	var sig_off: String = _funds_sig(off)
	var roff: Dictionary = off.upgrade_capsule()
	ok(not bool(roff.get("ok", true)) and Persistence.world_hash(off) == h_off and _funds_sig(off) == sig_off and (off.main_capsule as Dictionary).is_empty(), "REQ-0010-01: OFF — upgrade_capsule is a refusal without side effects (%s)" % str(roff))
	ok(not Persistence.serialize_region(off).has("main_capsule") and not Persistence.serialize_region(off).has("use_main_capsule"), "REQ-0010-01: OFF — the record has no capsule key after a refused upgrade")
	for x in [e, a, m, off]:
		_dispose(x)


# =============================================================================================
# REQ-0010-13 / 76: «зі складу капсули в її радіусі» — the stock counts only while the hero stands in the zone (edge inclusive);
# the backpack needs no proximity; a refusal says «far» and debits nothing
# =============================================================================================
func _t_upgrade_reach() -> void:
	var syn: Dictionary = _synth_table(3)
	var rows: Array = syn.levels
	var cost1: Dictionary = _cost_of(rows, 1)
	var radius: int = int(rows[0].radius)   # 4 — not the 2.5 stash reach, so the zone edge is a distinct line
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var dv: Vector2i = d
		# on the edge: inclusive
		var s: Variant = _on_pad()
		s.capsule_table = syn
		var cap: Vector2i = _cap_tile(s)
		_wipe(s)
		_fund_cost(s, cost1, 0.0)   # the whole price in the STOCK
		_put_hero(s, cap + dv * radius)
		var r: Dictionary = s.upgrade_capsule()
		ok(bool(r.get("ok", false)) and _have(s, "wood") == 0, "REQ-0010-13/15: hero ON the zone edge (%d cells %s) pays from the stock — %s" % [radius, str(dv), str(r)])
		_dispose(s)
		# one cell past the edge: refused, «far», nothing taken
		var f: Variant = _on_pad()
		f.capsule_table = syn
		_wipe(f)
		_fund_cost(f, cost1, 0.0)
		_put_hero(f, cap + dv * (radius + 1))
		var sig: String = _funds_sig(f)
		var h: String = Persistence.world_hash(f)
		var rf: Dictionary = f.upgrade_capsule()
		ok(not bool(rf.get("ok", true)) and rf.get("reason", &"") == &"cost" and bool(rf.get("far", false)), "REQ-0010-13: hero one cell OUTSIDE the zone (%s): refused, flagged far (the stock would have covered it) — %s" % [str(dv), str(rf)])
		ok(_funds_sig(f) == sig and Persistence.world_hash(f) == h and f.capsule_level() == 0, "REQ-0010-13: the far refusal debited nothing")
		# the backpack alone needs no proximity
		_fund_cost(f, cost1, 1.0)   # the whole price in the BACKPACK
		var rp: Dictionary = f.upgrade_capsule()
		ok(bool(rp.get("ok", false)) and f.capsule_level() == 1, "REQ-0010-13: far from the capsule the BACKPACK still pays (no proximity needed) — %s" % str(rp))
		_dispose(f)
	# far away with the price split pack + stock: the stock half cannot be reached -> refused, the backpack half stays too (atomic)
	var g: Variant = _on_pad()
	g.capsule_table = syn
	_wipe(g)
	_fund_cost(g, cost1, 0.5)
	_put_hero(g, _cap_tile(g) + Vector2i(radius + 2, 0))
	var sig_g: String = _funds_sig(g)
	var rg: Dictionary = g.upgrade_capsule()
	ok(not bool(rg.get("ok", true)) and _funds_sig(g) == sig_g and g.capsule_level() == 0, "REQ-0010-76: far away with a split price the whole command fails and neither source moves (%s)" % str(rg))
	_dispose(g)


# =============================================================================================
# REQ-0010-76: backpack FIRST, then the stock; atomic across both sources; a price larger than one stack; the ledger counts both
# =============================================================================================
func _t_upgrade_sources() -> void:
	var syn: Dictionary = _synth_table(3)   # level 1: wood 10, stone 2
	var cost1: Dictionary = _cost_of(syn.levels, 1)
	# 1. partial coverage: 4 wood in the backpack, the rest from the stock; stone only in the stock
	var s: Variant = _on_pad()
	s.capsule_table = syn
	_wipe(s)
	_fund(s, "wood", 4, 20)
	_fund(s, "stone", 0, 5)
	var r: Dictionary = s.upgrade_capsule()
	ok(bool(r.get("ok", false)) and Inventory.count(s, "wood") == 0 and s.res_amount("wood") == 14 and s.res_amount("stone") == 3 and Inventory.count(s, "stone") == 0,
		"REQ-0010-76: 4 wood from the backpack FIRST, the other 6 from the stock (20 -> 14); stone 2 from the stock (5 -> 3) — %s | pack wood %d stock wood %d stone %d" % [str(r), Inventory.count(s, "wood"), s.res_amount("wood"), s.res_amount("stone")])
	ok(_same_numbers(s.main_capsule.invested["1"], cost1), "REQ-0010-14: the ledger counts the units from BOTH sources (%s vs price %s)" % [var_to_str(s.main_capsule.invested), str(cost1)])
	_dispose(s)
	# 2. the backpack alone is enough -> the stock is not touched at all
	var b: Variant = _on_pad()
	b.capsule_table = syn
	_wipe(b)
	_fund(b, "wood", 15, 20)
	_fund(b, "stone", 3, 9)
	var rb: Dictionary = b.upgrade_capsule()
	ok(bool(rb.get("ok", false)) and Inventory.count(b, "wood") == 5 and b.res_amount("wood") == 20 and Inventory.count(b, "stone") == 1 and b.res_amount("stone") == 9,
		"REQ-0010-76: with enough in the backpack the stock stays untouched (wood pack 15->5, stock 20; stone pack 3->1, stock 9) — %s" % str(rb))
	_dispose(b)
	# 3. mixed per line: wood fully from the backpack, stone half-half
	var m: Variant = _on_pad()
	m.capsule_table = syn
	_wipe(m)
	_fund(m, "wood", 10, 7)
	_fund(m, "stone", 1, 1)
	var rm: Dictionary = m.upgrade_capsule()
	ok(bool(rm.get("ok", false)) and Inventory.count(m, "wood") == 0 and m.res_amount("wood") == 7 and Inventory.count(m, "stone") == 0 and m.res_amount("stone") == 0,
		"REQ-0010-76: each price line is split on its own (wood 10 pack / 0 stock; stone 1 pack / 1 stock) — %s" % str(rm))
	_dispose(m)
	# 4. a price bigger than one stack (wood stack = 50): spans several slots, leaves no ghost slot
	var big: Dictionary = _synth_table(2)
	big.levels[1].cost = {"wood": 130}
	var g: Variant = _on_pad()
	g.capsule_table = big
	_wipe(g)
	_fund(g, "wood", 120, 20)
	var rg: Dictionary = g.upgrade_capsule()
	var ghost: bool = false
	for sl in (g.player.inv as Array):
		if int(sl.n) < 0 or (String(sl.id) == "" and int(sl.n) != 0) or (String(sl.id) == "wood" and int(sl.n) == 0):
			ghost = true
	ok(bool(rg.get("ok", false)) and Inventory.count(g, "wood") == 0 and g.res_amount("wood") == 10 and not ghost,
		"REQ-0010-76: a 130-wood price over three 50-stacks: backpack 120 -> 0, stock 20 -> 10, no ghost slot — %s" % str(rg))
	_dispose(g)
	# 5. atomic across BOTH sources: 4 + 5 < 10 -> nothing moves, in either source
	var a: Variant = _on_pad()
	a.capsule_table = syn
	_wipe(a)
	_fund(a, "wood", 4, 5)
	_fund(a, "stone", 2, 0)
	var sig: String = _funds_sig(a)
	var ra: Dictionary = a.upgrade_capsule()
	ok(not bool(ra.get("ok", true)) and _funds_sig(a) == sig and a.capsule_level() == 0 and (a.main_capsule.invested as Dictionary).is_empty(), "REQ-0010-76: the two sources together are short (4+5 < 10): no unit left either, ledger empty (%s)" % str(ra))
	ok(int((ra.get("missing", {}) as Dictionary).get("wood", -1)) == 1, "REQ-0010-13: the missing amount counts BOTH sources (10 - 4 - 5 = 1) — %s" % str(ra.get("missing", {})))
	_dispose(a)


# =============================================================================================
# REQ-0010-76: a repeated command with the same id in the SAME tick pays once; without an id nothing is deduplicated;
# the dedup memory is not world state
# =============================================================================================
func _t_upgrade_dedupe() -> void:
	var syn: Dictionary = _synth_table(4)
	var rows: Array = syn.levels
	var total: Dictionary = {}
	for L in [1, 2]:
		for res in _cost_of(rows, L):
			total[res] = int(total.get(res, 0)) + int(_cost_of(rows, L)[res])
	var s: Variant = _on_pad()
	s.capsule_table = syn
	_wipe(s)
	_fund_cost(s, total, 0.5)   # funds for TWO levels
	var r1: Dictionary = s.upgrade_capsule(77)
	var after1: String = _funds_sig(s)
	var led1: String = _ledger_sig(s)
	var r2: Dictionary = s.upgrade_capsule(77)
	ok(bool(r1.get("ok", false)) and s.capsule_level() == 1, "REQ-0010-76 setup: the first command id=77 upgrades to 1 — %s" % str(r1))
	ok(s.capsule_level() == 1 and _funds_sig(s) == after1 and _ledger_sig(s) == led1, "REQ-0010-76: the same id in the same tick is idempotent — level still 1, funds and ledger as after the first (second said %s)" % str(r2))
	var r3: Dictionary = s.upgrade_capsule(78)
	ok(bool(r3.get("ok", false)) and s.capsule_level() == 2, "REQ-0010-76: a DIFFERENT id in the same tick is a new command — level 2 (%s)" % str(r3))
	# the dedup scope is ONE tick: after the next update() the same id is a new command (a stale memory would swallow it)
	s.capsule_table = syn
	_fund_cost(s, _cost_of(rows, 3), 0.5)
	s.update(Scenarios.DT)
	var again: Dictionary = s.upgrade_capsule(77)
	ok(bool(again.get("ok", false)) and s.capsule_level() == 3, "REQ-0010-76: the same id in a LATER tick is a new command (the idempotency window is one tick) — %s" % str(again))
	# no id (-1 is the local path): never deduplicated — two calls, two levels
	var n: Variant = _on_pad()
	n.capsule_table = syn
	_wipe(n)
	_fund_cost(n, total, 0.5)
	var a: Dictionary = n.upgrade_capsule()
	var b: Dictionary = n.upgrade_capsule()
	ok(bool(a.get("ok", false)) and bool(b.get("ok", false)) and n.capsule_level() == 2, "REQ-0010-76: two id-less commands in one tick are two commands (level 2) — %s / %s" % [str(a), str(b)])
	# the dedup memory is not state: not in the hash, not in the record, not on the wire
	var x: Variant = _on_pad()
	var y: Variant = _on_pad()
	x.capsule_table = syn
	y.capsule_table = syn
	for who in [x, y]:
		_wipe(who)
		_fund_cost(who, _cost_of(rows, 1), 0.5)
	x.upgrade_capsule(5)
	y.upgrade_capsule()
	ok(Persistence.world_hash(x) == Persistence.world_hash(y), "REQ-0010-82: the dedup memory (cmd id) is not in the hash — id 5 vs no id give the same world")
	ok(Persistence.serialize_region(x).keys() == Persistence.serialize_region(y).keys() and not JSON.stringify(Persistence.resume_payload(x)).contains("cmds"), "REQ-0010-35: ... nor in the record or the resume payload")
	for w in [s, n, x, y]:
		_dispose(w)


# =============================================================================================
# REQ-0010-14 / 35: every change of level / ledger moves the hash; a JSON round trip returns the SAME world, ints stay ints,
# the restored sim keeps upgrading identically; records handed out are copies
# =============================================================================================
func _t_upgrade_hash_roundtrip() -> void:
	var rows: Array = _raw_rows()
	var a: Variant = _leveled(2)
	var b: Variant = _leveled(2)
	var h0: String = Persistence.world_hash(a)
	ok(Persistence.world_hash(b) == h0, "REQ-0010-82 setup: two worlds built by the same upgrades hash the same (%s)" % h0)
	var seen: Dictionary = {h0: "base"}
	var collisions: Array = []
	for case_name in ["level 3 (ledger as is)", "level 1 (ledger as is)", "level 0 (ledger as is)", "ledger[1].wood +1", "ledger[1].wood -1", "ledger[2].stone +1", "ledger[3] appears", "ledger[1].components appears", "ledger[1] <-> ledger[2] swapped", "ledger[2] emptied"]:
		var m: Variant = _leveled(2)
		var inv: Dictionary = m.main_capsule.invested
		match String(case_name):
			"level 3 (ledger as is)":
				m.main_capsule.level = 3
			"level 1 (ledger as is)":
				m.main_capsule.level = 1
			"level 0 (ledger as is)":
				m.main_capsule.level = 0
			"ledger[1].wood +1":
				inv["1"]["wood"] = int(inv["1"]["wood"]) + 1
			"ledger[1].wood -1":
				inv["1"]["wood"] = int(inv["1"]["wood"]) - 1
			"ledger[2].stone +1":
				inv["2"]["stone"] = int(inv["2"]["stone"]) + 1
			"ledger[3] appears":
				inv["3"] = {"wood": 1}
			"ledger[1].components appears":
				inv["1"]["components"] = 1
			"ledger[1] <-> ledger[2] swapped":
				var tmp: Dictionary = inv["1"]
				inv["1"] = inv["2"]
				inv["2"] = tmp
			"ledger[2] emptied":
				inv["2"] = {}
		var h: String = Persistence.world_hash(m)
		if seen.has(h):
			collisions.append("%s == %s" % [String(case_name), String(seen[h])])
		seen[h] = String(case_name)
		_dispose(m)
	ok(collisions.is_empty(), "REQ-0010-35: each mutation of level or invested gives a world_hash different from the base and from every other mutation — %s" % ("ok (%d distinct)" % seen.size() if collisions.is_empty() else ", ".join(PackedStringArray(collisions))))
	# the record on the wire: a whole-number ledger under string keys, in numeric order
	var rec: Dictionary = Persistence.serialize_region(a).main_capsule
	var wire: Dictionary = rec.get("invested", {})
	var whole: bool = true
	for lk in wire:
		whole = whole and lk is String
		for res in (wire[lk] as Dictionary):
			whole = whole and typeof((wire[lk] as Dictionary)[res]) == TYPE_INT
	ok(int(rec.get("level", -1)) == 2 and wire.keys() == ["1", "2"] and whole and _same_numbers(wire["1"], _cost_of(rows, 1)) and _same_numbers(wire["2"], _cost_of(rows, 2)),
		"REQ-0010-14/82: serialize_region carries level 2 and invested {\"1\",\"2\"} = the two prices, string keys, int amounts — %s" % var_to_str(wire))
	# records handed out are COPIES: editing one cannot move the live ledger or the hash (a net snapshot would hold it across ticks)
	rec["invested"]["1"]["wood"] = 99999
	rec["level"] = 5
	ok(Persistence.world_hash(a) == h0 and int(a.main_capsule.invested["1"]["wood"]) == int(_cost_of(rows, 1).wood), "REQ-0010-35: a serialized record is a copy — editing it leaves the live ledger and the hash alone")
	# a JSON round trip: same hash, the ledger keeps its types
	var y: Variant = Sim.new()
	var accepted: bool = Persistence.restore(y, _json_rt(Persistence.resume_payload(a)))
	ok(accepted and y.load_error == &"" and Persistence.world_hash(y) == h0, "REQ-0010-35: the world restored from a JSON round trip has the same world_hash (%s vs %s)" % [Persistence.world_hash(y), h0])
	var kinds_ok: bool = true
	for lk in (y.main_capsule.invested as Dictionary):
		kinds_ok = kinds_ok and lk is String
		for res in (y.main_capsule.invested[lk] as Dictionary):
			kinds_ok = kinds_ok and typeof((y.main_capsule.invested[lk] as Dictionary)[res]) == TYPE_INT
	ok(kinds_ok and y.capsule_level() == 2 and (y.main_capsule.invested as Dictionary).keys() == ["1", "2"], "REQ-0010-14: after the round trip the ledger is back to String level keys and INT amounts (JSON gives floats) — %s" % var_to_str(y.main_capsule.invested))
	# the restored sim keeps living exactly like the original: the next upgrade lands the same ledger and the same hash
	var cost3: Dictionary = _cost_of(rows, 3)
	for who in [a, y]:
		_wipe(who)
		_fund_cost(who, cost3, 0.4)
	var ra: Dictionary = a.upgrade_capsule()
	var ry: Dictionary = y.upgrade_capsule()
	ok(bool(ra.get("ok", false)) and bool(ry.get("ok", false)) and Persistence.world_hash(a) == Persistence.world_hash(y), "REQ-0010-35: original and restored sims, same next upgrade -> the same world_hash (%s / %s)" % [str(ra), str(ry)])
	var inv_y: Dictionary = y.main_capsule.invested
	ok(inv_y.keys() == ["1", "2", "3"] and _same_numbers(inv_y["1"], _cost_of(rows, 1)) and _same_numbers(inv_y["2"], _cost_of(rows, 2)) and _same_numbers(inv_y["3"], cost3),
		"REQ-0010-14: the restored ledger got level 3 appended and kept levels 1-2 intact — %s" % var_to_str(inv_y))
	for w in [a, b, y]:
		_dispose(w)


# =============================================================================================
# REQ-0010-82: «invested (ключі в числовому порядку за зростанням)» — insertion order never leaks into the record or the hash
#
# The contract pinned here is step 1 (К1): levels 1..5 (OD-56), and the data tests cap the table at 10 rows (tests/catalog.test.js
# «capsule_levels: levels 0..5 are continuous…», run_catalog_tests `_t_capsule_levels_data`), i.e. ledger keys "1".."9" — ONE digit, where the
# lexicographic key sort of the hash input is the numeric order. Pinned: (1) EVERY insertion order of 1..5, (2) the widest ledger that
# bound allows (1..9), (3) holes and the resource order inside a level, (4) 9 levels reached by REAL upgrades and a JSON round trip.
# NOT pinned — an open question to the designer: a table of >= 11 rows. REQ-0010-91 says the range grows "by data only", REQ-0010-82 says
# "numeric order", yet a hash input that sorts string keys puts "10" before "2". Closing it moves either the OFF hash (a numeric-aware
# Persistence._canonical, D4) or the §5.1 record format (an array / padded keys), so no assertion exercises a HASH INPUT for >= 11 levels.
# =============================================================================================
func _t_invested_key_order() -> void:
	var rows: Array = _raw_rows()
	ok(rows.size() <= 10, "REQ-0010-82 domain: the shipped table has %d rows (<= 10): every ledger key is one digit, so the hash order below is the numeric one (the data tests pin the same bound)" % rows.size())
	# ---- (1) the К1 range: levels 1..5, EVERY insertion order (5! = 120), not a lucky sample ----
	var orders5: Array = _perms([1, 2, 3, 4, 5])
	ok(orders5.size() == 120, "REQ-0010-82 setup: the permutation helper yields all 120 orders of levels 1..5 (%d)" % orders5.size())
	var ref5: Variant = _on_pad()
	ref5.main_capsule.level = 5
	ref5.main_capsule.invested = _ledger_in_order(rows, [1, 2, 3, 4, 5])
	var h5: String = Persistence.world_hash(ref5)
	var text5: String = _expected_ledger_text(rows, [1, 2, 3, 4, 5])
	var probe: Variant = _on_pad()
	probe.main_capsule.level = 5
	var want5: Array = ["1", "2", "3", "4", "5"]
	var bad_hash: Array = []
	var bad_keys: Array = []
	var bad_input: Array = []
	for o in orders5:
		probe.main_capsule.invested = _ledger_in_order(rows, o)
		if Persistence.world_hash(probe) != h5:
			bad_hash.append(str(o))
		if Persistence.serialize_region(probe).main_capsule.invested.keys() != want5:
			bad_keys.append(str(o))
		if not _hash_input_has_ledger(probe, text5):
			bad_input.append(str(o))
	ok(bad_hash.is_empty(), "REQ-0010-82: the world_hash of levels 1..5 is the same in all 120 insertion orders — %d differ%s" % [bad_hash.size(), "" if bad_hash.is_empty() else " (first: %s)" % str(bad_hash[0])])
	ok(bad_keys.is_empty(), "REQ-0010-82: the record lists levels 1..5 ascending (1,2,3,4,5) in all 120 insertion orders — %d differ%s" % [bad_keys.size(), "" if bad_keys.is_empty() else " (first: %s)" % str(bad_keys[0])])
	ok(bad_input.is_empty(), "REQ-0010-82: the text the world hash digests carries the 1..5 ledger in numeric order in all 120 insertion orders — %d differ%s" % [bad_input.size(), "" if bad_input.is_empty() else " (first: %s)" % str(bad_input[0])])
	probe.main_capsule.invested = _ledger_in_order(rows, [1, 2, 3, 4])
	ok(Persistence.world_hash(probe) != h5, "REQ-0010-82 non-vacuous: a ledger without level 5 hashes differently (the order checks above compare a real ledger, not a constant)")
	# ---- (2) the widest ledger the 10-row bound allows: levels 1..9 ----
	var t10: Dictionary = _synth_table(10)
	var rows10: Array = t10.levels
	var all9: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	var orders9: Array = [all9.duplicate(), [9, 8, 7, 6, 5, 4, 3, 2, 1], [1, 3, 5, 7, 9, 2, 4, 6, 8], [2, 4, 6, 8, 1, 3, 5, 7, 9], [5, 6, 7, 8, 9, 1, 2, 3, 4], [9, 1, 8, 2, 7, 3, 6, 4, 5]]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8209
	for n in 8:
		var sh: Array = all9.duplicate()
		for j in range(sh.size() - 1, 0, -1):
			var k: int = rng.randi_range(0, j)
			var tmp: Variant = sh[j]
			sh[j] = sh[k]
			sh[k] = tmp
		orders9.append(sh)
	var x: Variant = _on_pad()
	x.capsule_table = t10
	x.main_capsule.level = 9
	x.main_capsule.invested = _ledger_in_order(rows10, all9)
	var h9: String = Persistence.world_hash(x)
	ok(Persistence.content_hash({"region": Persistence.serialize_region(x), "dyn": Persistence.serialize_runtime(x)}) == h9, "REQ-0010-82 setup: world_hash is the content hash of the {region, dyn} record whose text is checked below")
	var text9: String = _expected_ledger_text(rows10, all9)
	var want9: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
	var bad9_hash: Array = []
	var bad9_keys: Array = []
	var bad9_input: Array = []
	for o in orders9:
		x.main_capsule.invested = _ledger_in_order(rows10, o)
		if Persistence.world_hash(x) != h9:
			bad9_hash.append(str(o))
		if Persistence.serialize_region(x).main_capsule.invested.keys() != want9:
			bad9_keys.append(str(o))
		if not _hash_input_has_ledger(x, text9):
			bad9_input.append(str(o))
	ok(bad9_hash.is_empty(), "REQ-0010-82: the world_hash of levels 1..9 is the same in %d insertion orders (ascending, descending, odd/even, rotated, 8 seeded shuffles) — %d differ%s" % [orders9.size(), bad9_hash.size(), "" if bad9_hash.is_empty() else " (first: %s)" % str(bad9_hash[0])])
	ok(bad9_keys.is_empty(), "REQ-0010-82: the record lists levels 1..9 ascending in every one of them — %d differ%s" % [bad9_keys.size(), "" if bad9_keys.is_empty() else " (first: %s)" % str(bad9_keys[0])])
	ok(bad9_input.is_empty(), "REQ-0010-82: the text the world hash digests carries the 1..9 ledger in numeric order in every one of them — %d differ%s" % [bad9_input.size(), "" if bad9_input.is_empty() else " (first: %s)" % str(bad9_input[0])])
	# ---- (3) holes (a ledger need not hold every level) and the resource order inside a level ----
	var holes: Array = [[2, 5, 9], [9, 5, 2], [5, 9, 2], [9, 2, 5]]
	var h_holes: String = ""
	var holes_ok: bool = true
	for o in holes:
		x.main_capsule.invested = _ledger_in_order(rows10, o)
		if h_holes == "":
			h_holes = Persistence.world_hash(x)
		holes_ok = holes_ok and Persistence.world_hash(x) == h_holes and Persistence.serialize_region(x).main_capsule.invested.keys() == ["2", "5", "9"] \
			and _hash_input_has_ledger(x, _expected_ledger_text(rows10, [2, 5, 9]))
	ok(holes_ok and h_holes != h9, "REQ-0010-82: a ledger holding only levels 2, 5, 9 hashes and lists the same in every insertion order, numerically (2, 5, 9)")
	x.main_capsule.invested = {"1": {"wood": 3, "scrap": 5, "stone": 1}}
	var h_fwd: String = Persistence.world_hash(x)
	x.main_capsule.invested = {"1": {"stone": 1, "scrap": 5, "wood": 3}}
	ok(Persistence.world_hash(x) == h_fwd and _hash_input_has_ledger(x, "{\"1\":{\"scrap\":5,\"stone\":1,\"wood\":3}}"), "REQ-0010-82: the order resources were added inside a level does not move the hash (sorted by id in the hash input)")
	# ---- (4) 9 levels through REAL upgrades on the 10-row table (REQ-0010-91: the range is data) and a JSON round trip ----
	var real: Variant = _on_pad()
	real.capsule_table = t10
	_wipe(real)
	var climbed: bool = true
	var why: String = ""
	for L in range(1, 10):
		_fund_cost(real, _cost_of(rows10, L), 0.4)
		var r: Dictionary = real.upgrade_capsule()
		if not bool(r.get("ok", false)):
			climbed = false
			why = "level %d refused: %s" % [L, str(r)]
			break
	ok(climbed and real.capsule_level() == 9, "REQ-0010-91/13: nine real upgrades on a 10-row table reach level 9 — %s" % ("ok" if climbed else why))
	var inv9: Dictionary = real.main_capsule.invested
	var exact: bool = inv9.keys() == want9
	for L in range(1, 10):
		exact = exact and inv9.has(str(L)) and _same_numbers(inv9[str(L)], _cost_of(rows10, L))
	ok(exact and Persistence.serialize_region(real).main_capsule.invested.keys() == want9 and _hash_input_has_ledger(real, text9), "REQ-0010-14/82: the ledger of the climb is the nine prices, once each, in numeric order — in the live dictionary, the record and the hash input")
	var h_real: String = Persistence.world_hash(real)
	var back: Variant = Sim.new()
	back.capsule_table = t10
	var accepted: bool = Persistence.restore(back, _json_rt(Persistence.resume_payload(real)))
	var types_ok: bool = true
	for lk in (back.main_capsule.invested as Dictionary):
		types_ok = types_ok and lk is String
		for res in (back.main_capsule.invested[lk] as Dictionary):
			types_ok = types_ok and typeof((back.main_capsule.invested[lk] as Dictionary)[res]) == TYPE_INT
	ok(accepted and back.load_error == &"" and back.capsule_level() == 9 and Persistence.world_hash(back) == h_real, "REQ-0010-35: the level-9 world restored from a JSON round trip (keys sorted as text by the JSON writer) has the same world_hash (%s vs %s)" % [Persistence.world_hash(back), h_real])
	ok(types_ok and back.main_capsule.invested.keys() == want9 and _hash_input_has_ledger(back, text9), "REQ-0010-14/82: after the round trip the ledger is back to String level keys in numeric order and INT amounts")
	_fund_cost(real, {"wood": 60, "stone": 60, "planks": 60}, 0.4)
	var funds_before: String = _funds_sig(real)
	var past: Dictionary = real.upgrade_capsule()
	ok(not bool(past.get("ok", true)) and real.capsule_level() == 9 and _funds_sig(real) == funds_before and var_to_str(real.main_capsule.invested) == var_to_str(inv9), "REQ-0010-91: the top of a 10-row table is level 9 — a 10th upgrade is refused with nothing charged and the ledger untouched (%s)" % str(past))
	# ---- the WIRE record lists a longer ledger numerically too (that is `ledger()`, whatever the table length); what its HASH does for >= 11 rows is the open question above ----
	var wide: Variant = _on_pad()
	wide.capsule_table = _synth_table(12)
	wide.main_capsule.level = 11
	wide.main_capsule.invested = {"10": {"wood": 1}, "2": {"wood": 1}, "9": {"wood": 1}}
	var wide_keys: Array = Persistence.serialize_region(wide).main_capsule.invested.keys()
	ok(wide_keys == ["2", "9", "10"], "REQ-0010-82: the record of a 12-row table lists the ledger numerically (2, 9, 10) — %s" % str(wide_keys))
	for w in [ref5, probe, x, real, back, wide]:
		_dispose(w)


# every ordering of `items` (n! arrays): order-independence is proved for ALL insertion orders of the K1 range, not a sample
func _perms(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest: Array = items.duplicate()
		rest.remove_at(i)
		for p in _perms(rest):
			var tail: Array = p
			var one: Array = [items[i]]
			one.append_array(tail)
			out.append(one)
	return out


# a ledger of the price rows of `order`'s levels, inserted in exactly that order (the insertion order is the only thing that varies)
func _ledger_in_order(price_rows: Array, order: Array) -> Dictionary:
	var led: Dictionary = {}
	for L in order:
		led[str(int(L))] = _cost_of(price_rows, int(L))
	return led


# the ledger text the spec asks the hash input to carry, built here: level keys NUMERICALLY ascending (REQ-0010-82), resources by id
func _expected_ledger_text(price_rows: Array, levels: Array) -> String:
	var sorted_levels: Array = levels.duplicate()
	sorted_levels.sort()
	var parts: PackedStringArray = PackedStringArray()
	for L in sorted_levels:
		parts.append("\"%d\":%s" % [int(L), JSON.stringify(_cost_of(price_rows, int(L)), "", true)])
	return "{" + ",".join(parts) + "}"


# the exact text world_hash digests (world_hash == content_hash of this record — asserted once in the test above)
func _hash_input_has_ledger(s: Variant, ledger_text: String) -> bool:
	var text: String = Persistence._canonical({"region": Persistence.serialize_region(s), "dyn": Persistence.serialize_runtime(s)})
	return text.contains("\"invested\":" + ledger_text)


# =============================================================================================
# REQ-0010-88: a save of level 5 meets a table whose maximum is lower: the level is clamped, `invested` stays AS IS, the
# defence is recomputed from the new table; the other directions (higher max, other prices, one row, a corrupt level)
# =============================================================================================
func _t_save_clamp() -> void:
	var rows: Array = _raw_rows()
	var src: Variant = _on_pad()
	src.main_capsule.level = 5
	var led: Dictionary = {}
	for L in range(1, 6):
		led[str(L)] = _cost_of(rows, L)
	src.main_capsule.invested = led.duplicate(true)
	var payload: Dictionary = _json_rt(Persistence.resume_payload(src))
	var lowered: Dictionary = _table_copy()
	lowered["levels"] = (lowered.levels as Array).slice(0, 4)   # levels 0..3
	var y: Variant = Sim.new()
	y.capsule_table = lowered
	var accepted: bool = Persistence.restore(y, payload)
	ok(accepted and y.load_error == &"" and _cap_problem(y, _cap_tile(src)) == "", "REQ-0010-88: a level-5 save loads against a 4-row table (no refusal), the capsule building stands on its tile")
	ok(y.capsule_level() == 3, "REQ-0010-88: ... the level is clamped to the new maximum 3 (got %d)" % y.capsule_level())
	var inv: Dictionary = y.main_capsule.invested
	var as_is: bool = inv.keys() == ["1", "2", "3", "4", "5"]
	for L in range(1, 6):
		as_is = as_is and inv.has(str(L)) and _same_numbers(inv[str(L)], led[str(L)])
	ok(as_is, "REQ-0010-88: ... `invested` is kept as saved (levels 4 and 5 included) — %s" % var_to_str(inv))
	ok(absf(MainCapsule.core_hp(y, y.capsule_level()) - float(rows[3].core_hp)) < 1.0e-6 and absf(MainCapsule.core_hp(y, y.capsule_level()) - float(rows[5].core_hp)) > 1.0, "REQ-0010-88: ... the defence is the NEW level's (%s, not level 5's %s)" % [str(MainCapsule.core_hp(y, y.capsule_level())), str(rows[5].core_hp)])
	ok(MainCapsule.radius(y, y.capsule_level()) == int(rows[3].radius), "REQ-0010-88: ... and so is the zone radius")
	for res in PAY_IDS:
		_fund(y, String(res), 30, 300)
	var sig_y: String = _funds_sig(y)
	var ry: Dictionary = y.upgrade_capsule()
	ok(not bool(ry.get("ok", true)) and y.capsule_level() == 3 and _funds_sig(y) == sig_y and _ledger_sig(y) == var_to_str(inv), "REQ-0010-88/91: at the clamped maximum an upgrade is refused and the ledger stays (%s)" % str(ry))
	# the clamped world is itself stable: save it, load it into the same table -> same hash
	var y2: Variant = Sim.new()
	y2.capsule_table = lowered
	var again: bool = Persistence.restore(y2, _json_rt(Persistence.resume_payload(y)))
	ok(again and y2.capsule_level() == 3 and Persistence.world_hash(y2) == Persistence.world_hash(y), "REQ-0010-88/35: the clamped world round-trips to the same hash")
	# the clamp is a one-way effect of the SAVE: the clamped file loaded against the full table stays at 3
	var z: Variant = Sim.new()
	var back: bool = Persistence.restore(z, _json_rt(Persistence.resume_payload(y)))
	ok(back and z.capsule_level() == 3, "REQ-0010-88: a clamped save loaded against the full table stays at level 3 (%d)" % z.capsule_level())
	# a table with a HIGHER max: the level 5 save stays 5 (never raised), and the new top row is reachable
	var longer: Dictionary = _table_copy()
	(longer.levels as Array).append({"level": 6, "cost": {"wood": 9}, "radius": 15, "core_hp": 9000, "buffs": {"gather_mult": 1.3}})
	var hi: Variant = Sim.new()
	hi.capsule_table = longer
	var hi_ok: bool = Persistence.restore(hi, payload)
	ok(hi_ok and hi.capsule_level() == 5 and MainCapsule.max_level(hi) == 6, "REQ-0010-88: a level-5 save against a 7-row table stays at 5 (never raised) — level %d" % hi.capsule_level())
	# other prices (same length): the saved ledger is NOT recomputed
	var cheap: Dictionary = _synth_table(6)
	var ch: Variant = Sim.new()
	ch.capsule_table = cheap
	var ch_ok: bool = Persistence.restore(ch, payload)
	ok(ch_ok and ch.capsule_level() == 5 and _ledger_sig(ch) == var_to_str(ch.main_capsule.invested) and _same_numbers(ch.main_capsule.invested["3"], led["3"]),
		"REQ-0010-88: a table with other prices does not rewrite what was invested (ledger[3] = %s)" % var_to_str(ch.main_capsule.invested.get("3", {})))
	# a one-row table: the only level is 0
	var one: Variant = Sim.new()
	one.capsule_table = {"version": 1, "levels": [{"level": 0, "cost": {}, "radius": 3, "core_hp": 11.0, "buffs": {}}]}
	var one_ok: bool = Persistence.restore(one, payload)
	ok(one_ok and one.capsule_level() == 0 and MainCapsule.max_level(one) == 0, "REQ-0010-88/91: against a table with only level 0 the level is clamped to 0 (%d)" % one.capsule_level())
	# a corrupt save: a negative level is either refused out loud or clamped into [0, max] — never kept (REQ-0010-91 «ніколи не < 0»)
	for bad_level in [-2, 3.0, 99]:
		var bad: Dictionary = payload.duplicate(true)
		bad.region.main_capsule["level"] = bad_level
		var bs: Variant = Sim.new()
		var acc: bool = Persistence.restore(bs, _json_rt(bad))
		var lv: int = bs.capsule_level()
		var fine: bool = (not acc and bs.load_error != &"") or (acc and lv >= 0 and lv <= 5)
		ok(fine, "REQ-0010-91/75: a saved level of %s is refused or clamped into 0..5, never kept (accepted=%s level=%d err=%s)" % [str(bad_level), str(acc), lv, String(bs.load_error)])
		if acc and bad_level == 3.0:
			ok(lv == 3 and typeof(bs.main_capsule.level) == TYPE_INT, "REQ-0010-35: a level written as 3.0 (JSON) comes back as the int 3")
		_dispose(bs)
	for w in [src, y, y2, z, hi, ch, one]:
		_dispose(w)


# =============================================================================================
# REQ-0010-14 / 83 / 88: a record from before the ledger existed (the W1b shape) loads with an empty ledger and keeps working;
# a record with a corrupt ledger is refused out loud with the sim untouched, or loaded sanitised — never half-kept
# =============================================================================================
func _t_ledger_save_compat() -> void:
	var rows: Array = _raw_rows()
	var src: Variant = _leveled(1)
	var payload: Dictionary = _json_rt(Persistence.resume_payload(src))
	var old: Dictionary = payload.duplicate(true)
	(old.region.main_capsule as Dictionary).erase("invested")
	var y: Variant = Sim.new()
	var acc: bool = Persistence.restore(y, old)
	ok(acc and y.load_error == &"" and y.capsule_level() == 1 and (y.main_capsule.invested as Dictionary).is_empty(), "REQ-0010-88: a capsule record without `invested` (written before the ledger existed) loads — ledger empty, level kept (accepted=%s err=%s)" % [str(acc), String(y.load_error)])
	ok(_cap_problem(y, _cap_tile(src)) == "", "REQ-0010-75/88: ... and the load finished the job — ONE capsule building on the recorded tile, in bgrid (%s)" % _cap_problem(y, _cap_tile(src)))
	_wipe(y)
	_fund_cost(y, _cost_of(rows, 2), 0.5)
	var r: Dictionary = y.upgrade_capsule()
	ok(bool(r.get("ok", false)) and y.capsule_level() == 2 and y.main_capsule.invested.keys() == ["2"] and _same_numbers(y.main_capsule.invested["2"], _cost_of(rows, 2)),
		"REQ-0010-13/14: ... and its next upgrade writes ONLY its own ledger entry — %s" % var_to_str(y.main_capsule.invested))
	var cases: Dictionary = {
		"a negative amount": {"1": {"wood": -5}},
		"a fractional amount": {"1": {"wood": 2.5}},
		"level key 0": {"0": {"wood": 1}},
		"a level key that is not a number": {"x": {"wood": 1}},
		"an entry that is not a dictionary": {"1": 5},
		"not a dictionary at all": [1, 2],
		"an empty resource id": {"1": {"": 3}},
	}
	for name in cases:
		var bad: Dictionary = payload.duplicate(true)
		bad.region.main_capsule["invested"] = cases[name]
		var b: Variant = Sim.new()
		var loaded: bool = Persistence.restore(b, bad)
		var clean: bool = true
		if loaded:
			for lk in (b.main_capsule.invested as Dictionary):
				for res in (b.main_capsule.invested[lk] as Dictionary):
					clean = clean and typeof(b.main_capsule.invested[lk][res]) == TYPE_INT and int(b.main_capsule.invested[lk][res]) >= 0
		var refused: bool = (not loaded) and b.load_error != &"" and (b.map as Dictionary).is_empty() and (b.main_capsule as Dictionary).is_empty()
		ok(refused or (loaded and clean), "REQ-0010-83/14: a save whose ledger is %s is refused out loud with the sim untouched, or loaded sanitised — never kept as is (loaded=%s err=%s)" % [String(name), str(loaded), String(b.load_error)])
		_dispose(b)
	_dispose(src)
	_dispose(y)


# =============================================================================================
# REQ-0010-91: the range is the TABLE — a 7th row added in a test needs no code change; level 6 is refused on the 6-row table
# =============================================================================================
func _t_range_extension() -> void:
	var rows: Array = _raw_rows()
	var longer: Dictionary = _table_copy()
	var row6: Dictionary = {"level": 6, "cost": {"wood": 9, "stone": 5}, "radius": 15, "core_hp": 9999.0, "buffs": {"gather_mult": 1.3, "craft_mult": 1.3}}
	(longer.levels as Array).append(row6)
	var s: Variant = _on_pad()
	s.main_capsule.level = 5
	var led: Dictionary = {}
	for L in range(1, 6):
		led[str(L)] = _cost_of(rows, L)
	s.main_capsule.invested = led
	_wipe(s)
	_fund(s, "wood", 9, 0)
	_fund(s, "stone", 0, 5)
	var refused: Dictionary = s.upgrade_capsule()
	ok(not bool(refused.get("ok", true)) and s.capsule_level() == 5, "REQ-0010-91: on the 6-row table level 6 does not exist — refused, level 5 (%s)" % str(refused))
	s.capsule_table = longer   # the ONLY change: one more row of data
	ok(MainCapsule.max_level(s) == 6 and MainCapsule.radius(s, 6) == 15 and absf(MainCapsule.core_hp(s, 6) - 9999.0) < 1.0e-6 and absf(MainCapsule.buffs(s, 6).get("gather_mult", 0.0) - 1.3) < 1.0e-9,
		"REQ-0010-91: the new row is read as data (max 6, radius 15, core_hp 9999, buff 1.3) — no code change")
	var r: Dictionary = s.upgrade_capsule()
	ok(bool(r.get("ok", false)) and s.capsule_level() == 6, "REQ-0010-91: with the 7th row level 5 -> 6 works — %s" % str(r))
	ok(_have(s, "wood") == 0 and _have(s, "stone") == 0 and s.main_capsule.invested.has("6") and _same_numbers(s.main_capsule.invested["6"], {"wood": 9, "stone": 5}) and s.main_capsule.invested.keys() == ["1", "2", "3", "4", "5", "6"],
		"REQ-0010-14: level 6 took its 9 wood + 5 stone and wrote invested[6] — %s" % var_to_str(s.main_capsule.invested.get("6", {})))
	var top: Dictionary = s.upgrade_capsule()
	ok(not bool(top.get("ok", true)) and s.capsule_level() == 6, "REQ-0010-91: the NEW top (6) is a top — refused (%s)" % str(top))
	var y: Variant = Sim.new()
	y.capsule_table = longer
	var acc: bool = Persistence.restore(y, _json_rt(Persistence.resume_payload(s)))
	ok(acc and y.capsule_level() == 6 and Persistence.world_hash(y) == Persistence.world_hash(s), "REQ-0010-35/91: a level-6 world round-trips through JSON with its hash")
	var back: Variant = Sim.new()   # the same save against the 6-row table: clamped, the 6th ledger entry stays
	var acc2: bool = Persistence.restore(back, _json_rt(Persistence.resume_payload(s)))
	ok(acc2 and back.capsule_level() == 5 and back.main_capsule.invested.has("6"), "REQ-0010-88: the level-6 save on the 6-row table -> level 5 and invested[6] kept (%d)" % back.capsule_level())
	for w in [s, y, back]:
		_dispose(w)


# =============================================================================================
# REQ-0010-34 / 92 / 82: an upgrade is a pure state step — it draws no random numbers, touches nothing but the hero's pack, the
# stock, level and ledger; it does not read the clock; twins agree
# =============================================================================================
func _world_without_funds(s: Variant) -> String:
	return var_to_str([s.map, s.buildings, s.bgrid, s.regions, s.invites, s.bags, s.enemies, s.time, s.weather, s.player.hp, s.player.hunger, s.player.rest, s.player.px, s.player.py, s.player.skills, s.dead, s.flash_msg])


func _t_upgrade_side_effects() -> void:
	var rows: Array = _raw_rows()
	var s: Variant = _on_pad()
	_wipe(s)
	var cur0: Array = _cursors(s)
	var sig0: String = _world_without_funds(s)
	var keys0: Array = Persistence.serialize_region(s).keys()
	var failed: Dictionary = s.upgrade_capsule()   # nothing funded: a refusal must not even stir the world
	ok(not bool(failed.get("ok", true)) and _cursors(s) == cur0 and _world_without_funds(s) == sig0, "REQ-0010-34: a REFUSED upgrade draws no random numbers and changes nothing around it")
	_fund_cost(s, _cost_of(rows, 1), 0.5)
	var done: Dictionary = s.upgrade_capsule()
	ok(bool(done.get("ok", false)) and _cursors(s) == cur0, "REQ-0010-34: a successful upgrade does not shift the director/env/threat cursors")
	ok(_world_without_funds(s) == sig0, "REQ-0010-13: ... and moves nothing but the pack, the stock, the level and the ledger (map, buildings, enemies, time, hero body/position, bags unchanged)")
	ok(Persistence.serialize_region(s).keys() == keys0, "REQ-0010-35: ... and adds no key to the region record")
	# the clock is an input, not an operand: pushing it before the upgrade changes neither the ledger nor the hash
	var a: Variant = _on_real(CLOCK_T)
	var b: Variant = _on_real(CLOCK_T)
	for w in [a, b]:
		_wipe(w)
		_fund_cost(w, _cost_of(rows, 1), 0.5)
	b.set_clock(CLOCK_T + 86400000 * 3)
	a.upgrade_capsule()
	b.upgrade_capsule()
	ok(Persistence.world_hash(a) == Persistence.world_hash(b) and _ledger_sig(a) == _ledger_sig(b), "REQ-0010-92: the upgrade does not depend on the device clock (same ledger and hash with now_ms +3 days)")
	# twins: the same commands in the same order -> the same world, across updates in between
	for w in [a, b]:
		_fund_cost(w, _cost_of(rows, 2), 0.3)
		for t in 20:
			w.update(Scenarios.DT)
			_topup(w)
		w.upgrade_capsule()
	ok(a.capsule_level() == 2 and b.capsule_level() == 2, "REQ-0010-13 setup: both twins reached level 2 across ticks")
	for w in [s, a, b]:
		_dispose(w)


# =============================================================================================
# REQ-0010-96 / 97 (W2a part): death changes neither the level nor the ledger nor the capsule's stock (and the stock is still
# spendable by the new body); upgrading summons no body and trains nobody — the roster is the Orbit's business
# =============================================================================================
func _t_upgrade_death_and_roster() -> void:
	var rows: Array = _raw_rows()
	var s: Variant = _stub_on(_pad_map(PAD_N, Vector2i(8, 8)))
	_quiet(s)
	_wipe(s)
	var body0: String = var_to_str([s.player.born, s.player.skills])
	for L in range(1, 4):
		_fund_cost(s, _cost_of(rows, L), 0.5)
		s.upgrade_capsule()
	ok(s.capsule_level() == 3 and int(s.source_calls) == 0, "REQ-0010-97: three upgrades never asked for a body (respawn_source calls: %d) — the capsule levels do not hand out clones" % int(s.source_calls))
	ok(var_to_str([s.player.born, s.player.skills]) == body0, "REQ-0010-97: ... and the hero's own skills/identity are untouched by levels")
	_fund(s, "wood", 0, 61)   # something in the capsule's stock that must survive the death
	var led: String = _ledger_sig(s)
	var stock_wood: int = s.res_amount("wood")
	_kill(s)
	s.respawn_new_pawn()
	ok(int(s.source_calls) == 1, "REQ-0010-96 setup: the death took ONE body through the respawn_source seam (%d)" % int(s.source_calls))
	ok(s.capsule_level() == 3 and _ledger_sig(s) == led and s.res_amount("wood") == stock_wood, "REQ-0010-96: death + respawn left the level (3), the ledger and the capsule's stock as they were")
	# the new body is next to the capsule -> in its zone -> pays from the stock straight away
	var cost4: Dictionary = _cost_of(rows, 4)
	for res in cost4:
		_fund(s, String(res), 0, int(cost4[res]))
	var r: Dictionary = s.upgrade_capsule()
	ok(bool(r.get("ok", false)) and s.capsule_level() == 4, "REQ-0010-13/96: after the respawn the new body (empty hands, next to the capsule) upgrades from the stock — %s" % str(r))
	_dispose(s)


# =============================================================================================
# REQ-0010-17: ONE axis — the code offers exactly one way to raise the capsule, with no axis argument
# =============================================================================================
func _t_one_axis_api() -> void:
	var names: Array = []
	var cap_script: Script = MainCapsule
	var sim_script: Script = Sim
	for m in cap_script.get_script_method_list():
		var nm: String = String((m as Dictionary).name)
		if nm.contains("upgrade") or nm.contains("level_up") or nm.contains("boost") or nm.contains("buy_"):
			names.append("capsule.%s/%d" % [nm, int((m as Dictionary).args.size())])
	for m in sim_script.get_script_method_list():
		var nm2: String = String((m as Dictionary).name)
		if nm2.contains("upgrade") or nm2.contains("level_up") or nm2.contains("boost") or nm2.contains("buy_capsule"):
			names.append("sim.%s/%d" % [nm2, int((m as Dictionary).args.size())])
	names.sort()
	ok(names == ["capsule.upgrade/2", "sim.upgrade_capsule/1"], "REQ-0010-17: exactly one raise entry point (upgrade_capsule(cmd_id)) and no radius/defence/buff variant — %s" % str(names))


# =============================================================================================
# REQ-0010-13 / 14 / 76 / 91 — a seeded property run: random funding across both sources, random hero positions (zone edge
# included), random commands with and without ids, ticks in between. After EVERY call an independent oracle (measured funds,
# the data file, the data's metric) says what had to happen: accept or refuse, the exact debit, pack-first, the exact ledger.
# =============================================================================================
func _t_upgrade_property() -> void:
	for variant in ["catalog", "synthetic"]:
		var synthetic: bool = String(variant) == "synthetic"
		var table: Dictionary = _synth_table(5) if synthetic else {}
		var rows: Array = (table.levels as Array) if synthetic else _raw_rows()
		var ids: Array = []
		for L in rows.size():
			for k in _cost_of(rows, L):
				if not ids.has(k):
					ids.append(k)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 7100 + (1 if synthetic else 0)
		var max_lv: int = rows.size() - 1
		var stats: Dictionary = {"ok": 0, "cost": 0, "far": 0, "max": 0, "dup": 0}
		var problems: Array = []
		var stock_cap: int = 40 if synthetic else 300
		var ends_exact: bool = true
		var ends_stable: bool = true
		for session in 6:   # a fresh capsule every 100 steps: the low levels (refusals, «far») are visited again and again
			var s: Variant = _on_pad()
			if synthetic:
				s.capsule_table = table
			_wipe(s)
			var cap: Vector2i = _cap_tile(s)
			var done_ids: Dictionary = {}
			var bad_ids: Dictionary = {}
			for step in 100:
				var op: int = rng.randi_range(0, 9)
				var lvl: int = int(s.main_capsule.level)
				if op == 0:
					var res0: String = String(ids[rng.randi_range(0, ids.size() - 1)])
					_fund(s, res0, rng.randi_range(0, 60), rng.randi_range(0, stock_cap))
				elif op == 1 or (op == 2 and rng.randi_range(0, 1) == 0):
					var nxt: Dictionary = _cost_of(rows, lvl + 1)
					var short_one: String = String(nxt.keys()[rng.randi_range(0, nxt.size() - 1)]) if nxt.size() > 0 and rng.randi_range(0, 2) == 0 else ""
					for res in nxt:
						var need: int = maxi(0, int(nxt[res]) - (1 if String(res) == short_one else 0))
						var pk: int = rng.randi_range(0, mini(60, need))
						_fund(s, String(res), pk, need - pk)
				elif op == 3 or op == 2:
					var rad: int = int((rows[lvl] as Dictionary).radius)
					var dx: int = rng.randi_range(-(rad + 2), rad + 2)
					var dy: int = rng.randi_range(-(rad + 2), rad + 2)
					if rng.randi_range(0, 2) == 0:
						dx = clampi(dx, -rad, rad)
						dy = clampi(dy, -rad, rad)
					_put_hero(s, Vector2i(clampi(cap.x + dx, 0, PAD_N - 1), clampi(cap.y + dy, 0, PAD_N - 1)))
				elif op == 4:
					s.update(Scenarios.DT)
					_topup(s)
					done_ids.clear()
					bad_ids.clear()
				else:
					var cid: int = -1
					if rng.randi_range(0, 1) == 1:
						cid = rng.randi_range(0, 3)
						if bad_ids.has(cid):
							cid = -1
					var hero: Vector2i = _hero_cell(s)
					var in_zone: bool = maxi(absi(hero.x - cap.x), absi(hero.y - cap.y)) <= int((rows[lvl] as Dictionary).radius)
					var dup: bool = cid >= 0 and done_ids.has(cid)
					var cost: Dictionary = _cost_of(rows, lvl + 1)
					var packs: Dictionary = {}
					var stocks: Dictionary = {}
					var short: Dictionary = {}
					var far_would_fix: bool = false
					for res in ids:
						packs[res] = Inventory.count(s, String(res))
						stocks[res] = int(s.res_amount(String(res)))
					for res in cost:
						var avail: int = int(packs[res]) + (int(stocks[res]) if in_zone else 0)
						if avail < int(cost[res]):
							short[res] = int(cost[res]) - avail
							far_would_fix = far_would_fix or (not in_zone and int(stocks[res]) > 0)
					var sig0: String = _funds_sig(s)
					var led0: String = _ledger_sig(s)
					var ledger0: Dictionary = (s.main_capsule.invested as Dictionary).duplicate(true)
					var r: Dictionary = s.upgrade_capsule(cid)
					var tag: String = "[%s session %d step %d lvl %d cid %d zone %s]" % [String(variant), session, step, lvl, cid, str(in_zone)]
					if dup:
						stats.dup += 1
						if _funds_sig(s) != sig0 or _ledger_sig(s) != led0 or int(s.main_capsule.level) != lvl:
							problems.append("%s duplicate id changed state" % tag)
					elif lvl >= max_lv:
						stats["max"] += 1
						if bool(r.get("ok", true)) or int(s.main_capsule.level) != lvl or _funds_sig(s) != sig0 or _ledger_sig(s) != led0:
							problems.append("%s max level: not refused cleanly (%s)" % [tag, str(r)])
						if cid >= 0:
							bad_ids[cid] = true
					elif short.is_empty():
						stats.ok += 1
						if not bool(r.get("ok", false)) or int(s.main_capsule.level) != lvl + 1 or int(r.get("level", -1)) != lvl + 1:
							problems.append("%s affordable but refused/level wrong (%s)" % [tag, str(r)])
						for res in ids:
							var need2: int = int(cost.get(res, 0))
							var from_pack: int = mini(int(packs[res]), need2)
							var from_stock: int = need2 - from_pack
							if Inventory.count(s, String(res)) != int(packs[res]) - from_pack or int(s.res_amount(String(res))) != int(stocks[res]) - from_stock:
								problems.append("%s %s debit wrong: pack %d->%d stock %d->%d, expected pack-first -%d/-%d" % [tag, String(res), int(packs[res]), Inventory.count(s, String(res)), int(stocks[res]), int(s.res_amount(String(res))), from_pack, from_stock])
						var want_led: Dictionary = ledger0.duplicate(true)
						want_led[str(lvl + 1)] = cost.duplicate()
						if var_to_str(Persistence.serialize_region(s).main_capsule.invested) != var_to_str(MainCapsule.ledger(want_led)):
							problems.append("%s ledger is not old + price: %s" % [tag, var_to_str(s.main_capsule.invested)])
						if cid >= 0:
							done_ids[cid] = true
					else:
						stats.cost += 1
						if far_would_fix:
							stats.far += 1
						if bool(r.get("ok", true)) or r.get("reason", &"") != &"cost" or int(s.main_capsule.level) != lvl or _funds_sig(s) != sig0 or _ledger_sig(s) != led0:
							problems.append("%s unaffordable: not refused cleanly (%s)" % [tag, str(r)])
						elif not _same_numbers(r.get("missing", {}), short):
							problems.append("%s wrong missing %s, expected %s" % [tag, str(r.get("missing", {})), str(short)])
						elif bool(r.get("far", false)) != far_would_fix:
							problems.append("%s far flag %s, expected %s" % [tag, str(r.get("far", false)), str(far_would_fix)])
						if cid >= 0:
							bad_ids[cid] = true
			# end of a session: the ledger is exactly the prices of levels 1..level, once each (nothing dropped, nothing invented)
			var end_lv: int = int(s.main_capsule.level)
			var inv_end: Dictionary = s.main_capsule.invested
			ends_exact = ends_exact and inv_end.size() == end_lv
			for L in range(1, end_lv + 1):
				ends_exact = ends_exact and inv_end.has(str(L)) and _same_numbers(inv_end[str(L)], _cost_of(rows, L))
			var y: Variant = Sim.new()
			if synthetic:
				y.capsule_table = table
			var acc: bool = Persistence.restore(y, _json_rt(Persistence.resume_payload(s)))
			# NOT world_hash: after ticks the runtime floats (patrol.timer, time.frac) ride JSON with the parser's known 1-ulp error
			# (see the fixture note in AGENTS.md), which has nothing to do with the capsule. The capsule record + the funds are ints/strings.
			var ra: Dictionary = Persistence.serialize_region(s)
			var rb: Dictionary = Persistence.serialize_region(y)
			ends_stable = ends_stable and acc and y.load_error == &"" and Persistence.content_hash([ra.main_capsule, ra.stock, ra.player.inv]) == Persistence.content_hash([rb.main_capsule, rb.stock, rb.player.inv])
			_dispose(s)
			_dispose(y)
		ok(problems.is_empty(), "REQ-0010-13/14/76 [%s]: 600 random steps — every upgrade call matched the independent oracle (%d problems; first: %s)" % [String(variant), problems.size(), str(problems.slice(0, 2))])
		ok(int(stats.ok) >= 6 and int(stats.cost) >= 20 and int(stats.dup) >= 2, "REQ-0010-13/76 [%s] setup: the run really exercised the paths — %s" % [String(variant), str(stats)])
		ok(int(stats.far) >= 2, "REQ-0010-13 [%s] setup: «hero outside the zone, the stock would have covered it» refusals were reached — %s" % [String(variant), str(stats)])
		if synthetic:
			ok(int(stats["max"]) >= 1, "REQ-0010-91 [synthetic] setup: the top level was reached and attacked — %s" % str(stats))
		ok(ends_exact, "REQ-0010-14 [%s]: at the end of every session the ledger is exactly the price of each level reached, once" % String(variant))
		ok(ends_stable, "REQ-0010-35 [%s]: every session's end state survives a JSON round trip — the capsule record, the stock and the backpack come back identical" % String(variant))


# =============================================================================================
# WAVE 0010-W2b — helpers (the control zone + the buffs on the hero and on the processes)
# Expectations come from REQ-0010-12/15/16/79/80 and the wave brief, NOT from capsule.gd: the zone oracle is max(|dx|,|dy|) <= R with R
# read from the TABLE this test builds (or from the catalog FILE), the buff values are distinct per key and per level (a swapped key or a
# row mix-up cannot hide), every expected rate is a sum written out here. A red test here is a finding.
# =============================================================================================
const ZB_N := 30                                  # pad side: the capsule stands on ZB_CAP, room for R <= 13 with no clipping by the map edge
const ZB_CAP := Vector2i(12, 17)                  # x != y on purpose: a swapped (x, y) cannot hide behind a symmetric centre
const ZB_DT := 0.05
const ZB_KEYS: Array = ["gather_mult", "melee_mult", "craft_mult", "research_mult"]


# rows 0..n-1: radius 2,3,5,6,8,9,11,... ; level L>=1 buffs gather 1+.5L, melee 1+.25L, craft 1+.75L, research 1+L — binary-exact, distinct per key
# within a level and per level within a key (nothing like the catalog's proposed 3,5,7,9,11,13 / +5% steps)
func _zone_table(n_levels: int = 4) -> Dictionary:
	var rows: Array = []
	for L in n_levels:
		var buffs: Dictionary = {}
		if L >= 1:
			buffs["gather_mult"] = 1.0 + 0.5 * float(L)
			buffs["melee_mult"] = 1.0 + 0.25 * float(L)
			buffs["craft_mult"] = 1.0 + 0.75 * float(L)
			buffs["research_mult"] = 1.0 + float(L)
		var cost: Dictionary = {}
		if L >= 1:
			cost["wood"] = 5 + 4 * L
		rows.append({"level": L, "cost": cost, "radius": 2 + L + (L >> 1), "core_hp": 100.0 * float(L + 1), "buffs": buffs})
	return {"version": 1, "status": "proposed", "metric": "chebyshev", "levels": rows}


# an ON world on a flat 30x30 pad, the capsule on ZB_CAP at `level` of `table` (default: _zone_table(4)); funds are NOT touched
func _zone_sim(level: int, table: Dictionary = {}) -> Variant:
	var s: Variant = _sim_with(_pad_map(ZB_N, ZB_CAP), true, true, true)
	_quiet(s)
	s.capsule_table = _zone_table() if table.is_empty() else table
	s.main_capsule["level"] = level
	return s


func _zb_row(table: Dictionary, L: int) -> Dictionary:
	return (table.levels as Array)[L]


func _zb_radius(table: Dictionary, L: int) -> int:
	return int(_zb_row(table, L).radius)


func _zb_buff(table: Dictionary, L: int, key: String) -> float:
	return float((_zb_row(table, L).buffs as Dictionary).get(key, 1.0))


# the oracle: Chebyshev distance, edge included
func _zb_in(cap: Vector2i, c: Vector2i, radius: int) -> bool:
	return maxi(absi(c.x - cap.x), absi(c.y - cap.y)) <= radius


func _hero_px(s: Variant, px: float, py: float) -> void:
	s.player.px = px
	s.player.py = py
	s.player.action = null


func _near(a: float, b: float, rel: float = 1.0e-9) -> bool:
	return absf(a - b) <= rel * maxf(1.0, absf(b))


# hero positions around the zone edge — FRACTIONAL on purpose: the hero's cell is floor(px), floor(py), so 12+R+0.99 is still in
# and 12+R+1.0 is out; the corners are in the Chebyshev zone and out of an Euclidean/Manhattan one
func _edge_probes(cap: Vector2i, R: int) -> Array:
	var cx: float = float(cap.x)
	var cy: float = float(cap.y)
	var r: float = float(R)
	return [
		Vector2(cx + 0.5, cy + 0.5),
		Vector2(cx + r + 0.99, cy + 0.5), Vector2(cx + r + 1.0, cy + 0.5),
		Vector2(cx - r + 0.0, cy + 0.5), Vector2(cx - r - 0.01, cy + 0.5),
		Vector2(cx + 0.5, cy + r + 0.99), Vector2(cx + 0.5, cy + r + 1.0),
		Vector2(cx + 0.5, cy - r + 0.0), Vector2(cx + 0.5, cy - r - 0.01),
		Vector2(cx + r + 0.5, cy + r + 0.5), Vector2(cx + r + 1.5, cy + r + 0.5), Vector2(cx + r + 0.5, cy + r + 1.5),
		Vector2(cx - r + 0.5, cy - r + 0.5), Vector2(cx - r - 0.5, cy - r + 0.5), Vector2(cx - r + 0.5, cy - r - 0.5),
		Vector2(cx + r + 0.5, cy - r + 0.5), Vector2(cx - r + 0.5, cy + r + 0.5),
		Vector2(cx - r - 0.5, cy + r + 0.5), Vector2(cx + r + 1.5, cy - r + 0.5),
	]


# bench / hero offsets around the edge of radius R: every edge midpoint and corner (in), one step past each (out), a mixed asymmetric set
func _edge_offsets(R: int) -> Array:
	return [
		Vector2i(R, 0), Vector2i(-R, 0), Vector2i(0, R), Vector2i(0, -R),
		Vector2i(R, R), Vector2i(-R, -R), Vector2i(R, -R), Vector2i(-R, R), Vector2i(1, 2), Vector2i(-2, R - 1),
		Vector2i(R + 1, 0), Vector2i(-R - 1, 0), Vector2i(0, R + 1), Vector2i(0, -R - 1),
		Vector2i(R + 1, R), Vector2i(R, R + 1), Vector2i(R + 1, R + 1), Vector2i(-R - 1, -R), Vector2i(-R, -R - 1), Vector2i(R + 1, -R), Vector2i(-R - 1, R + 2),
	]


# the rate the sim applies to the craft timer, measured around ONE step of the real _update_crafting (the timer is put back, so the
# probe is repeatable and wrap-proof: it runs from a zeroed timer, then puts the timer back)
func _craft_rate_of(s: Variant) -> float:
	var before: float = float(s.craft_timer)
	s.craft_timer = 0.0
	s._update_crafting(ZB_DT)
	var d: float = float(s.craft_timer)
	s.craft_timer = before
	return d / ZB_DT


# research points per game-day as the SESSION reports them (the number the research panel and the ETA use)
func _research_rate_of(s: Variant) -> float:
	var sess: Variant = SessionScript.new()
	sess.autosave = false
	sess.sim = s
	return float(sess.research_rate())


func _clear_buildings_but_capsule(s: Variant) -> void:
	for b in (s.buildings as Array).duplicate():
		if String(b.kind) != MainCapsule.KIND:
			s._remove_building(b)


# =============================================================================================
# REQ-0010-15 / 16 / 80 — the zone is Chebyshev around the capsule cell, edge included, radius of the CURRENT level; the metric is the
# data's; no capsule -> no zone
# =============================================================================================
func _t_zone_shape() -> void:
	var syn: Dictionary = _zone_table(6)
	var s: Variant = _zone_sim(0, syn)
	var cap: Vector2i = _cap_tile(s)
	ok(cap == ZB_CAP, "REQ-0010-15 setup: the capsule stands on the pad's spawn %s (got %s)" % [str(ZB_CAP), str(cap)])
	for variant in ["synthetic", "catalog"]:
		var table: Dictionary = syn if String(variant) == "synthetic" else _table_copy()
		s.capsule_table = table
		var n_rows: int = (table.levels as Array).size()
		var wrong: Array = []
		var exact_count: bool = true
		for L in n_rows:
			s.main_capsule["level"] = L
			var R: int = _zb_radius(table, L)
			var hits: int = 0
			for dy in range(-(R + 3), R + 4):
				for dx in range(-(R + 3), R + 4):
					var c: Vector2i = cap + Vector2i(dx, dy)
					var got: bool = MainCapsule.in_zone(s, c)
					if got:
						hits += 1
					if got != _zb_in(cap, c, R):
						wrong.append("L%d %s" % [L, str(Vector2i(dx, dy))])
			exact_count = exact_count and hits == (2 * R + 1) * (2 * R + 1)
		ok(wrong.is_empty(), "REQ-0010-15/80 [%s]: in_zone == (max(|dx|,|dy|) <= R of the CURRENT level) for every cell in a window around the capsule, on every level — %d wrong, first %s" % [String(variant), wrong.size(), str(wrong.slice(0, 3))])
		ok(exact_count, "REQ-0010-80 [%s]: the zone holds exactly (2R+1)^2 cells on every level (a Euclidean or Manhattan zone holds fewer; an exclusive edge too)" % String(variant))
	# named edge cases at level 2 of the synthetic table (R = 5): all four edge midpoints and corners are IN, one step past each is OUT
	s.capsule_table = syn
	s.main_capsule["level"] = 2
	var ins: Array = [Vector2i(5, 0), Vector2i(-5, 0), Vector2i(0, 5), Vector2i(0, -5), Vector2i(5, 5), Vector2i(-5, -5), Vector2i(5, -5), Vector2i(-5, 5), Vector2i(0, 0)]
	var outs: Array = [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6), Vector2i(-6, -5), Vector2i(-5, -6), Vector2i(-6, 6), Vector2i(6, -6)]
	var in_bad: Array = []
	for d in ins:
		if not MainCapsule.in_zone(s, cap + (d as Vector2i)):
			in_bad.append(str(d))
	var out_bad: Array = []
	for d in outs:
		if MainCapsule.in_zone(s, cap + (d as Vector2i)):
			out_bad.append(str(d))
	ok(in_bad.is_empty(), "REQ-0010-15 (edge inclusive): the 4 edge midpoints, the 4 corners and the centre are INSIDE at R=5 — outside by mistake: %s" % str(in_bad))
	ok(out_bad.is_empty(), "REQ-0010-15: one step past the edge / the corner is OUTSIDE at R=5 — inside by mistake: %s" % str(out_bad))
	ok(not MainCapsule.in_zone(s, Vector2i(-40, -40)) and not MainCapsule.in_zone(s, Vector2i(500, 7)), "REQ-0010-15: cells far outside the map are simply outside (no error, no clamp)")
	ok(MainCapsule.buff_at(s, "gather_mult", Vector2i(-40, -40)) == 1.0, "REQ-0010-15: ... and neutral (1.0)")
	# the zone follows the level the capsule has NOW (the drop shrinks it, the rise grows it, on the very next call)
	var mover: Vector2i = cap + Vector2i(6, 0)
	s.main_capsule["level"] = 2
	var out_at_2: bool = not MainCapsule.in_zone(s, mover)
	s.main_capsule["level"] = 3
	var in_at_3: bool = MainCapsule.in_zone(s, mover)
	s.main_capsule["level"] = 1
	var out_at_1: bool = not MainCapsule.in_zone(s, mover)
	ok(out_at_2 and in_at_3 and out_at_1, "REQ-0010-80: the zone is recomputed from the current level on every call (cap+(6,0): out at R=5, in at R=6, out again at R=3)")
	# no capsule at all (flag OFF): there is no zone and no buff anywhere
	var off: Variant = _sim_with(_pad_map(PAD_N, Vector2i(8, 8)), false, false, false)
	ok(not MainCapsule.in_zone(off, Vector2i(8, 8)) and not MainCapsule.in_zone(off, Vector2i(9, 8)), "REQ-0010-01/15: with the flag OFF (no capsule record) nothing is inside any zone")
	ok(MainCapsule.buff_at(off, "gather_mult", Vector2i(8, 8)) == 1.0 and MainCapsule.buff_at(off, "craft_mult", Vector2i(9, 8)) == 1.0, "REQ-0010-01/15: ... and every buff is the neutral 1.0")
	# the metric is one string in the DATA (REQ-0010-80); the catalog names it and the oracle above used Chebyshev
	ok(String(_raw_table().get("metric", "")) == "chebyshev" and String(syn.metric) == "chebyshev", "REQ-0010-80: the zone metric is a field of the table — 'chebyshev' in the catalog")
	_dispose(s)
	_dispose(off)


# =============================================================================================
# REQ-0010-16 — radius(L+1) >= radius(L); every zone is contained in the next one (same capsule, any cell of the map, 5 presets)
# =============================================================================================
func _t_zone_monotone() -> void:
	var tables: Dictionary = {"catalog": _table_copy(), "synthetic 3": _zone_table(3), "synthetic 7": _zone_table(7), "synthetic 10": _zone_table(10)}
	for name in tables:
		var table: Dictionary = tables[name]
		var s: Variant = _zone_sim(0, table)
		var n_rows: int = (table.levels as Array).size()
		var mono: bool = true
		var same_as_data: bool = true
		for L in n_rows:
			same_as_data = same_as_data and MainCapsule.radius(s, L) == _zb_radius(table, L)
			if L + 1 < n_rows:
				mono = mono and MainCapsule.radius(s, L + 1) >= MainCapsule.radius(s, L)
		ok(mono, "REQ-0010-16 [%s]: radius(L+1) >= radius(L) for every consecutive pair of the %d rows" % [String(name), n_rows])
		ok(same_as_data, "REQ-0010-11/16 [%s]: radius(L) is the table row's radius (no clamp, no offset)" % String(name))
		_dispose(s)
	# the same, as geometry on real maps: zone(L) is a subset of zone(L+1), and it never shrinks in size
	var contained: bool = true
	var grew: bool = true
	var detail: String = ""
	for pr in GameData.SPAWN_PRESETS:
		var s2: Variant = _sim_with(_gen(float(pr.lat), float(pr.lon)), true, true, true)
		var cap: Vector2i = _cap_tile(s2)
		var n: int = int(s2.n)
		var prev: Dictionary = {}
		var prev_n: int = -1
		var rows: int = (_raw_rows() as Array).size()
		for L in rows:
			s2.main_capsule["level"] = L
			var cur: Dictionary = {}
			for y in n:
				for x in n:
					if MainCapsule.in_zone(s2, Vector2i(x, y)):
						cur[y * n + x] = true
			if L > 0:
				for k in prev:
					if not cur.has(k):
						contained = false
						detail = "%s L%d lost cell %d" % [String(pr.name), L, int(k)]
				grew = grew and cur.size() >= prev_n
			prev = cur
			prev_n = cur.size()
			if L == 0:
				var holds_cap: bool = prev.has(cap.y * n + cap.x)
				ok(holds_cap, "REQ-0010-15/16 [%s]: level 0 has a zone and the capsule cell is in it" % String(pr.name))
		_dispose(s2)
	ok(contained, "REQ-0010-16: on every spawn preset the zone of level L lies inside the zone of level L+1 — %s" % detail)
	ok(grew, "REQ-0010-16: ... and the number of cells inside never drops with the level")


# =============================================================================================
# REQ-0010-15 / 80 — the HERO's buffs (gather time, melee damage): same act inside / on the edge / outside -> different result; the
# hero's cell is floor(px), floor(py); each hook reads the current level's row
# =============================================================================================
func _t_buff_hero_hooks() -> void:
	var syn: Dictionary = _zone_table(4)
	var node: Dictionary = {"kind": "tree"}
	var bad_g: Array = []
	var bad_m: Array = []
	var seen_in: int = 0
	var seen_out: int = 0
	var seen_edge_in: int = 0
	for L in 4:
		var s: Variant = _zone_sim(L, syn)
		var cap: Vector2i = _cap_tile(s)
		var R: int = _zb_radius(syn, L)
		_hero_px(s, float(cap.x) + 14.5, float(cap.y) + 0.5)   # 14 cells out: outside every zone of this table — the reference
		var base_g: float = s.gather_time(node)
		var base_m: float = s.melee_damage()
		_hero_px(s, float(cap.x) - 14.5, float(cap.y) + 0.5)   # the other side must give the same reference
		if not (_near(s.gather_time(node), base_g) and _near(s.melee_damage(), base_m)):
			bad_g.append("L%d: two far spots disagree" % L)
		for pr in _edge_probes(cap, R):
			var p: Vector2 = pr
			_hero_px(s, p.x, p.y)
			var c: Vector2i = Vector2i(floori(p.x), floori(p.y))
			var inside: bool = L >= 1 and _zb_in(cap, c, R)
			if inside:
				seen_in += 1
				if maxi(absi(c.x - cap.x), absi(c.y - cap.y)) == R:
					seen_edge_in += 1
			else:
				seen_out += 1
			var want_g: float = base_g / _zb_buff(syn, L, "gather_mult") if inside else base_g
			var want_m: float = base_m * _zb_buff(syn, L, "melee_mult") if inside else base_m
			if not _near(s.gather_time(node), want_g):
				bad_g.append("L%d hero (%.2f,%.2f) cell %s inside=%s: gather %.6f want %.6f" % [L, p.x, p.y, str(c - cap), str(inside), s.gather_time(node), want_g])
			if not _near(s.melee_damage(), want_m):
				bad_m.append("L%d hero (%.2f,%.2f) cell %s inside=%s: melee %.6f want %.6f" % [L, p.x, p.y, str(c - cap), str(inside), s.melee_damage(), want_m])
		_dispose(s)
	ok(bad_g.is_empty(), "REQ-0010-15/80: gather_time = base / gather_mult(current level) in the zone (edge inclusive, Chebyshev corners, fractional cells) and = base outside — %d wrong, first %s" % [bad_g.size(), str(bad_g.slice(0, 2))])
	ok(bad_m.is_empty(), "REQ-0010-15/80: melee_damage = base * melee_mult(current level) in the zone and = base outside — %d wrong, first %s" % [bad_m.size(), str(bad_m.slice(0, 2))])
	ok(seen_in >= 24 and seen_edge_in >= 20 and seen_out >= 30, "REQ-0010-15 setup: the probes really covered the inside (%d), the inclusive edge (%d) and the outside (%d)" % [seen_in, seen_edge_in, seen_out])
	# the SAME hero, the SAME act, only the cell differs: strictly better inside than outside at every level >= 1
	var s2: Variant = _zone_sim(3, syn)
	var cap2: Vector2i = _cap_tile(s2)
	_hero_px(s2, float(cap2.x) + 6.5, float(cap2.y) + 0.5)   # on the edge (R=6)
	var g_edge: float = s2.gather_time(node)
	var m_edge: float = s2.melee_damage()
	_hero_px(s2, float(cap2.x) + 7.5, float(cap2.y) + 0.5)   # one cell past
	ok(g_edge < s2.gather_time(node) and m_edge > s2.melee_damage(), "REQ-0010-15: on the edge the hero gathers faster and hits harder than one cell further out (%.4f < %.4f; %.2f > %.2f)" % [g_edge, s2.gather_time(node), m_edge, s2.melee_damage()])
	# a level change moves the result on the VERY NEXT call (nothing cached): the hero stays on cap+(4,0)
	_hero_px(s2, float(cap2.x) + 4.5, float(cap2.y) + 0.5)
	var plain: float = 1.3 / (1.0 + float(s2.player.skills.gather) * 0.04)   # data.gd NODEINFO tree.time and the skill formula
	var seen: Array = []
	for L in [3, 0, 2, 1, 3]:
		s2.main_capsule["level"] = L
		var inside_now: bool = L >= 1 and _zb_in(cap2, cap2 + Vector2i(4, 0), _zb_radius(syn, L))
		var want: float = plain / _zb_buff(syn, L, "gather_mult") if inside_now else plain
		seen.append(_near(s2.gather_time(node), want))
	ok(not seen.has(false), "REQ-0010-80: raising and dropping the level between two calls changes gather_time at once (levels 3,0,2,1,3 at cap+(4,0): inside at levels 3 and 2 (R=6,5), outside at levels 0 and 1 (R=2,3)) — %s" % str(seen))
	_dispose(s2)


# =============================================================================================
# REQ-0010-15 — each hook reads ITS OWN key, and an ABSENT key is neutral (1.0), not 0 and not an error
# =============================================================================================
func _t_buff_one_key_each() -> void:
	var node: Dictionary = {"kind": "tree"}
	var base_research: float = float(GameData.BUILDINGS.research_bench.research_rate)
	var report: Array = []
	for key in ZB_KEYS:
		var bf: Dictionary = {}
		bf[String(key)] = 2.0
		var rows: Array = [
			{"level": 0, "cost": {}, "radius": 2, "core_hp": 100.0, "buffs": {}},
			{"level": 1, "cost": {"wood": 5}, "radius": 4, "core_hp": 200.0, "buffs": bf},
		]
		var tab: Dictionary = {"version": 1, "status": "proposed", "metric": "chebyshev", "levels": rows}
		var s: Variant = _zone_sim(1, tab)
		var cap: Vector2i = _cap_tile(s)
		_wipe(s)
		s._place_building("workbench", cap.x + 2, cap.y, -1)
		s._place_building("research_bench", cap.x, cap.y - 2, -1)
		_hero_px(s, float(cap.x) + 14.5, float(cap.y) + 0.5)
		var g0: float = s.gather_time(node)
		var m0: float = s.melee_damage()
		_hero_px(s, float(cap.x) + 1.5, float(cap.y) + 0.5)
		var want_g: float = g0 / 2.0 if String(key) == "gather_mult" else g0
		var want_m: float = m0 * 2.0 if String(key) == "melee_mult" else m0
		var want_c: float = 2.0 if String(key) == "craft_mult" else 1.0
		var want_r: float = base_research * (2.0 if String(key) == "research_mult" else 1.0)
		report.append([String(key), _near(s.gather_time(node), want_g), _near(s.melee_damage(), want_m), _near(_craft_rate_of(s), want_c), _near(_research_rate_of(s), want_r)])
		_dispose(s)
	var wrong: Array = []
	for r in report:
		var row: Array = r
		if not (bool(row[1]) and bool(row[2]) and bool(row[3]) and bool(row[4])):
			wrong.append(row)
	ok(wrong.is_empty(), "REQ-0010-15: with ONLY one key in the row (value 2.0) exactly the matching hook reacts (gather/melee/craft/research) and the other three stay neutral — [key, gather, melee, craft, research] ok-flags of the wrong ones: %s" % str(wrong))


# =============================================================================================
# REQ-0010-15 — the buff is a MULTIPLIER on top of everything else the hero has (skill, tool, weapon): inside the zone the same hero, with
# the same gear and skills, works/hits exactly b times as well as outside — whatever the gear is
# =============================================================================================
func _t_buff_stacks_with_gear() -> void:
	var syn: Dictionary = _zone_table(4)   # level 3: R = 6, gather 2.5, melee 1.75
	var node: Dictionary = {"kind": "tree"}
	var bad: Array = []
	var loadouts: Array = [
		["bare hands", "", "", 0.0, 0.0],
		["axe + club, skills 10/7", "axe", "club", 10.0, 7.0],
		["axe + bow, skills 20/20", "axe", "bow", 20.0, 20.0],
		["pick only, skill 3", "pick", "", 3.0, 0.0],
	]
	for lo in loadouts:
		var row: Array = lo
		var s: Variant = _zone_sim(3, syn)
		var cap: Vector2i = _cap_tile(s)
		s.player.equipped = {"tool": String(row[1]), "weapon": String(row[2])}
		s.player.skills.gather = float(row[3])
		s.player.skills.combat = float(row[4])
		_hero_px(s, float(cap.x) + 14.5, float(cap.y) + 0.5)
		var g_out: float = s.gather_time(node)
		var m_out: float = s.melee_damage()
		_hero_px(s, float(cap.x) + 2.5, float(cap.y) + 0.5)
		var g_in: float = s.gather_time(node)
		var m_in: float = s.melee_damage()
		if not _near(g_in * 2.5, g_out):
			bad.append("%s: gather in %.6f out %.6f (ratio %.6f, want 2.5)" % [String(row[0]), g_in, g_out, g_out / g_in])
		if not _near(m_in, m_out * 1.75):
			bad.append("%s: melee in %.6f out %.6f (ratio %.6f, want 1.75)" % [String(row[0]), m_in, m_out, m_in / m_out])
		_dispose(s)
	ok(bad.is_empty(), "REQ-0010-15: for every loadout (skills, tool, weapon) the in-zone/out-of-zone ratio is exactly the row's multiplier (gather 2.5 on the time, melee 1.75 on the damage) — %s" % str(bad))


# =============================================================================================
# REQ-0010-79 / wave step 3 — the vocabulary is closed: a need-key in the data is NOT a buff and moves no body need
# =============================================================================================
func _t_buff_keys_closed() -> void:
	ok(_first_word_in(MainCapsule.BUFF_KEYS, NEED_WORDS) == "", "REQ-0010-79: no key of the buff vocabulary names a body need — %s" % _first_word_in(MainCapsule.BUFF_KEYS, NEED_WORDS))
	var bf: Dictionary = {"gather_mult": 2.0, "hunger_mult": 0.5, "cold_mult": 0.5, "sleep_mult": 0.5, "rest_mult": 0.5, "bogus_mult": 3.0}
	var rows: Array = [
		{"level": 0, "cost": {}, "radius": 3, "core_hp": 100.0, "buffs": {}},
		{"level": 1, "cost": {"wood": 5}, "radius": 4, "core_hp": 200.0, "buffs": bf},
	]
	var tab: Dictionary = {"version": 1, "status": "proposed", "metric": "chebyshev", "levels": rows}
	var s: Variant = _zone_sim(1, tab)
	var cap: Vector2i = _cap_tile(s)
	var got: Dictionary = MainCapsule.buffs(s, 1)
	ok(_first_word_in(got.keys(), NEED_WORDS) == "" and not got.has("bogus_mult"), "REQ-0010-79: buffs(level) hands out only vocabulary keys — a need-key / an unknown key in the data never becomes a buff (%s)" % str(got.keys()))
	var cell: Vector2i = cap + Vector2i(1, 0)
	var flat: bool = true
	for k in ["hunger_mult", "cold_mult", "sleep_mult", "rest_mult", "bogus_mult", "", "gather"]:
		flat = flat and MainCapsule.buff_at(s, String(k), cell) == 1.0
	ok(flat, "REQ-0010-79: buff_at of a need-key / unknown key inside the zone is the neutral 1.0")
	ok(MainCapsule.buff_at(s, "gather_mult", cell) == 2.0, "REQ-0010-15 control: the legitimate key of the same row is 2.0 there")
	# the bodies: the same hero stands inside the zone for 300 ticks at level 1 (need keys in the data) and at level 0 (none): the same needs
	var a: Variant = _zone_sim(1, tab)
	var b: Variant = _zone_sim(0, tab)
	for w in [a, b]:
		_hero_px(w, float(cap.x) + 1.5, float(cap.y) + 0.5)
		w.player.hunger = 60.0
		w.player.rest = 60.0
	for t in 300:
		a.update(Scenarios.DT)
		b.update(Scenarios.DT)
	ok(_near(float(a.player.hunger), float(b.player.hunger)) and _near(float(a.player.rest), float(b.player.rest)) and _near(float(a.player.hp), float(b.player.hp)), "REQ-0010-79: 300 ticks inside the zone — hunger/rest/hp at level 1 (need-keys in its row) equal level 0's (%.4f/%.4f vs %.4f/%.4f)" % [float(a.player.hunger), float(a.player.rest), float(b.player.hunger), float(b.player.rest)])
	for w in [s, a, b]:
		_dispose(w)


# =============================================================================================
# REQ-0010-12 — level 0 gives no buff anywhere (inside its R0 zone too) and is BIT-EXACT the OFF world; with the REAL catalog every
# key's value shows up in its hook at every level >= 1 (the table is not vacuous)
# =============================================================================================
func _t_buff_level0_and_catalog() -> void:
	var node: Dictionary = {"kind": "tree"}
	var table: Dictionary = _table_copy()
	var rows: Array = table.levels
	var s: Variant = _zone_sim(0, table)
	var cap: Vector2i = _cap_tile(s)
	ok(MainCapsule.buffs(s, 0).is_empty(), "REQ-0010-12: buffs(0) is empty")
	var flat: bool = true
	var R0: int = _zb_radius(table, 0)
	for k in ZB_KEYS:
		for dy in range(-(R0 + 2), R0 + 3):
			for dx in range(-(R0 + 2), R0 + 3):
				flat = flat and MainCapsule.buff_at(s, String(k), cap + Vector2i(dx, dy)) == 1.0
	ok(flat, "REQ-0010-12: at level 0 every key is exactly 1.0 on every cell, the R0 zone included")
	# bit-exact vs a flag-OFF twin on the same pad: the same hero cell, the same benches
	var off: Variant = _sim_with(_pad_map(ZB_N, ZB_CAP), false, false, false)
	_quiet(off)
	for w in [s, off]:
		_hero_px(w, float(cap.x) + 1.5, float(cap.y) + 0.5)
		w._place_building("workbench", cap.x + 2, cap.y, -1)
		w._place_building("research_bench", cap.x, cap.y - 2, -1)
	ok(s.gather_time(node) == off.gather_time(node) and s.melee_damage() == off.melee_damage(), "REQ-0010-12/01: at level 0 inside the zone gather_time and melee_damage equal the OFF world's BIT FOR BIT (%s vs %s)" % [str(s.gather_time(node)), str(off.gather_time(node))])
	for t in 5:
		s._update_crafting(ZB_DT)
		off._update_crafting(ZB_DT)
	ok(float(s.craft_timer) == float(off.craft_timer) and float(s.craft_timer) > 0.0, "REQ-0010-12/01: ... and 5 crafting steps leave craft_timer identical to the OFF world's (%s vs %s)" % [str(s.craft_timer), str(off.craft_timer)])
	ok(_research_rate_of(s) == _research_rate_of(off) and _research_rate_of(s) > 0.0, "REQ-0010-12/01: ... and the research rate (%s vs %s)" % [str(_research_rate_of(s)), str(_research_rate_of(off))])
	# a table that WRONGLY lists buffs on row 0: level 0 still gives none, at the hooks too (REQ-0010-12 is not a data convention)
	var bf0: Dictionary = {"gather_mult": 1.5, "melee_mult": 1.25, "craft_mult": 1.75, "research_mult": 2.0}
	var tab0: Dictionary = _zone_table(3)
	((tab0.levels as Array)[0] as Dictionary)["buffs"] = bf0
	var w0: Variant = _zone_sim(0, tab0)
	var cap_w: Vector2i = _cap_tile(w0)
	w0._place_building("workbench", cap_w.x + 2, cap_w.y, -1)
	w0._place_building("research_bench", cap_w.x, cap_w.y - 2, -1)
	_hero_px(w0, float(cap_w.x) + 14.5, float(cap_w.y) + 0.5)
	var plain_g: float = w0.gather_time(node)
	var plain_m: float = w0.melee_damage()
	_hero_px(w0, float(cap_w.x) + 1.5, float(cap_w.y) + 0.5)
	ok(w0.gather_time(node) == plain_g and w0.melee_damage() == plain_m and _craft_rate_of(w0) == 1.0 and _research_rate_of(w0) == float(GameData.BUILDINGS.research_bench.research_rate), "REQ-0010-12: row 0 listing buffs in the data still gives NO buff at level 0 — gather/melee/craft/research are plain inside the zone")
	_dispose(w0)
	# the real table, every level >= 1: the hook shows the data's number for every key the row names (data-driven, no number pinned here)
	var problems: Array = []
	var any_effect: bool = false
	var base_research: float = float(GameData.BUILDINGS.research_bench.research_rate)
	for L in range(1, rows.size()):
		s.main_capsule["level"] = L
		var buffs: Dictionary = (rows[L] as Dictionary).get("buffs", {})
		_hero_px(s, float(cap.x) + 14.5, float(cap.y) + 0.5)
		var g0: float = s.gather_time(node)
		var m0: float = s.melee_damage()
		_hero_px(s, float(cap.x) + 1.5, float(cap.y) + 0.5)
		var vg: float = float(buffs.get("gather_mult", 1.0))
		var vm: float = float(buffs.get("melee_mult", 1.0))
		var vc: float = float(buffs.get("craft_mult", 1.0))
		var vr: float = float(buffs.get("research_mult", 1.0))
		any_effect = any_effect or vg != 1.0 or vm != 1.0 or vc != 1.0 or vr != 1.0
		if not _near(s.gather_time(node), g0 / vg):
			problems.append("L%d gather" % L)
		if not _near(s.melee_damage(), m0 * vm):
			problems.append("L%d melee" % L)
		if not _near(_craft_rate_of(s), vc):
			problems.append("L%d craft (%s vs %s)" % [L, str(_craft_rate_of(s)), str(vc)])
		if not _near(_research_rate_of(s), base_research * vr):
			problems.append("L%d research" % L)
	ok(problems.is_empty(), "REQ-0010-15 [catalog]: for every level 1..5 each hook applies exactly the row's value for its key inside the zone — %s" % str(problems))
	ok(any_effect, "REQ-0010-15 [catalog]: the REAL table gives at least one non-neutral buff (a table of all 1.0 would satisfy every other test and mean nothing)")
	_dispose(s)
	_dispose(off)


# =============================================================================================
# REQ-0010-15 / 80 — through REAL upgrades (funds spent, ledger written): the buff and the radius of the level just reached apply at once
# =============================================================================================
func _t_buff_after_real_upgrades() -> void:
	var rows: Array = _raw_rows()
	var base: float = 1.3   # data.gd NODEINFO tree.time; the hero's gather skill is 0 at the start and the formula is 1 + skill*0.04
	var bad: Array = []
	var s: Variant = _on_pad()
	var cap: Vector2i = _cap_tile(s)
	var base_dur: float = base / (1.0 + float(s.player.skills.gather) * 0.04)
	var node: Dictionary = {"kind": "tree"}
	_wipe(s)
	for L in range(1, 3):
		_fund_cost(s, _cost_of(rows, L), 0.4)
		var r: Dictionary = s.upgrade_capsule()
		if not bool(r.get("ok", false)):
			bad.append("upgrade to %d refused: %s" % [L, str(r)])
			continue
		var R: int = int((rows[L] as Dictionary).radius)
		var v: float = float(((rows[L] as Dictionary).buffs as Dictionary).get("gather_mult", 1.0))
		_hero_px(s, float(cap.x) + float(R) + 0.5, float(cap.y) + 0.5)   # on the edge of the level just reached (x = 8 + R <= 15 on this pad)
		if not _near(s.gather_time(node), base_dur / v):
			bad.append("L%d edge: gather %.6f want %.6f" % [L, s.gather_time(node), base_dur / v])
		_hero_px(s, float(cap.x) + 0.5, float(cap.y) + 1.5)
		if not _near(s.gather_time(node), base_dur / v):
			bad.append("L%d beside the capsule: gather %.6f want %.6f" % [L, s.gather_time(node), base_dur / v])
	ok(bad.is_empty(), "REQ-0010-15/80: after each REAL upgrade (level 1, then 2) gather_time inside the zone — edge included — is base / the row's gather_mult, at once — %s" % str(bad))
	# one cell beyond the level-1 edge it is plain again (level 1 reached by a fresh real upgrade)
	var s1: Variant = _leveled(1)
	var R1: int = int((rows[1] as Dictionary).radius)
	_hero_px(s1, float(cap.x) + float(R1) + 1.5, float(cap.y) + 0.5)
	ok(_near(s1.gather_time(node), base_dur), "REQ-0010-15: one cell past the level-1 edge the same hero gathers at the plain time (%.4f vs %.4f)" % [s1.gather_time(node), base_dur])
	for w in [s, s1]:
		_dispose(w)


# =============================================================================================
# REQ-0010-15 / 80 — bench crafting: each workbench counts its OWN cell (edge inclusive, Chebyshev), a bench outside works at 1.0, a
# buff multiplies capacity that exists (no bench -> nothing), level 0 == the plain count
# =============================================================================================
func _t_buff_craft_process() -> void:
	var syn: Dictionary = _zone_table(4)
	var wrong: Array = []
	var covered_in: int = 0
	var covered_out: int = 0
	for L in [1, 2, 3]:
		var s: Variant = _zone_sim(L, syn)
		var cap: Vector2i = _cap_tile(s)
		_wipe(s)
		var R: int = _zb_radius(syn, L)
		var b: float = _zb_buff(syn, L, "craft_mult")
		for off in _edge_offsets(R):
			var o: Vector2i = off
			var bench: Variant = s._place_building("workbench", cap.x + o.x, cap.y + o.y, -1)
			var inside: bool = _zb_in(cap, cap + o, R)
			if inside:
				covered_in += 1
			else:
				covered_out += 1
			var got: float = _craft_rate_of(s)
			var want: float = b if inside else 1.0
			if not _near(got, want):
				wrong.append("L%d bench at %s: rate %.6f want %.6f" % [L, str(o), got, want])
			s._remove_building(bench)
		_dispose(s)
	ok(wrong.is_empty(), "REQ-0010-15/80: one bench at every edge point/corner/step-past of levels 1..3 — rate = craft_mult(level) inside (edge inclusive), exactly 1.0 outside — %d wrong, first %s" % [wrong.size(), str(wrong.slice(0, 3))])
	ok(covered_in >= 30 and covered_out >= 30, "REQ-0010-15 setup: the bench probes covered both sides (%d in, %d out)" % [covered_in, covered_out])
	# several benches: the rate is the SUM of each bench's own multiplier
	var s2: Variant = _zone_sim(3, syn)   # R = 6, craft 3.25
	var cap2: Vector2i = _cap_tile(s2)
	_wipe(s2)
	ok(_craft_rate_of(s2) == 0.0 and float(s2.craft_timer) == 0.0, "REQ-0010-15 (D8): with NO bench the craft rate is 0 at level 3 — a buff multiplies capacity, it does not create it")
	var foreign: Array = ["storage", "wall", "bed", "research_bench", "campfire", "turret"]
	for i in foreign.size():
		s2._place_building(String(foreign[i]), cap2.x + 1 + i, cap2.y + 3, -1)
	ok(_craft_rate_of(s2) == 0.0, "REQ-0010-15 (D8): six other buildings inside the zone (storage, wall, bed, research table, campfire, turret) and the capsule itself make NO crafting capacity — the rate stays 0 (%s)" % str(_craft_rate_of(s2)))
	var timer_probe: float = float(s2.craft_timer)
	s2._update_crafting(ZB_DT)
	ok(float(s2.craft_timer) == timer_probe, "REQ-0010-15 (D8): ... and a crafting step with no bench leaves the timer untouched")
	s2._place_building("workbench", cap2.x + 6, cap2.y, -1)   # edge: in
	ok(_near(_craft_rate_of(s2), 3.25), "REQ-0010-15: one bench on the edge -> 3.25 (%s)" % str(_craft_rate_of(s2)))
	s2._place_building("workbench", cap2.x + 7, cap2.y, -1)   # one past: out
	ok(_near(_craft_rate_of(s2), 3.25 + 1.0), "REQ-0010-15/80: + one bench just outside -> 3.25 + 1.0 (the outside bench still works, without the buff) — %s" % str(_craft_rate_of(s2)))
	s2._place_building("workbench", cap2.x - 6, cap2.y - 6, -1)   # corner: in
	s2._place_building("workbench", cap2.x, cap2.y + 6, -1)       # edge: in
	ok(_near(_craft_rate_of(s2), 3.25 * 3.0 + 1.0), "REQ-0010-15: + a corner bench and an edge bench -> 3 * 3.25 + 1.0 (%s)" % str(_craft_rate_of(s2)))
	# the real step really uses that rate: one update() of the whole sim adds dt * rate to the timer (no wrap: stock is empty, timer small)
	var before: float = float(s2.craft_timer)
	var want_step: float = Scenarios.DT * (3.25 * 3.0 + 1.0)
	s2.update(Scenarios.DT)
	ok(_near(float(s2.craft_timer) - before, want_step), "REQ-0010-15: a full sim.update(dt) advances the craft timer by dt * Σ per-bench multipliers (%s vs %s)" % [str(float(s2.craft_timer) - before), str(want_step)])
	# level 0: the plain count, bit-exact (1.0 per bench) even for benches inside the R0 zone
	var s0: Variant = _zone_sim(0, syn)
	var cap0: Vector2i = _cap_tile(s0)
	_wipe(s0)
	s0._place_building("workbench", cap0.x + 2, cap0.y, -1)
	s0._place_building("workbench", cap0.x - 1, cap0.y + 1, -1)
	s0._place_building("workbench", cap0.x + 9, cap0.y, -1)
	var t0: float = 0.0
	for i in 6:
		s0._update_crafting(ZB_DT)
		t0 += ZB_DT * 3.0
	ok(float(s0.craft_timer) == t0, "REQ-0010-12: at level 0 three benches (two inside R0) advance the timer by exactly dt * 3 per step — %s vs %s" % [str(s0.craft_timer), str(t0)])
	for w in [s2, s0]:
		_dispose(w)


# =============================================================================================
# REQ-0010-80 — NO RETROACTIVITY: a level drop (or rise) in the middle of a craft moves nothing that was accumulated; the next step adds
# at the new rate; the bench outside the shrunk zone keeps working and nothing is lost or doubled
# =============================================================================================
func _t_buff_craft_no_retroactivity() -> void:
	var syn: Dictionary = _zone_table(4)
	var s: Variant = _zone_sim(3, syn)
	var cap: Vector2i = _cap_tile(s)
	_wipe(s)
	var bench_cell: Vector2i = cap + Vector2i(5, 0)   # in at R=6 and R=5 (edge), out at R=3 and R=2
	var bench: Variant = s._place_building("workbench", bench_cell.x, bench_cell.y, -1)
	var bench_hp: float = float(bench.hp)
	var plan: Array = [[3, 4], [1, 4], [2, 4], [0, 4], [3, 4]]   # (level, steps): 4*0.05*(3.25 + 1 + 2.5 + 1 + 3.25) = 2.2 < 3.5, no wrap
	var expect_timer: float = 0.0
	var no_jump: bool = true
	var per_step: bool = true
	var log_rows: Array = []
	for seg in plan:
		var L: int = int(seg[0])
		var before: float = float(s.craft_timer)
		s.main_capsule["level"] = L
		no_jump = no_jump and float(s.craft_timer) == before
		var rate: float = _zb_buff(syn, L, "craft_mult") if _zb_in(cap, bench_cell, _zb_radius(syn, L)) else 1.0
		for i in int(seg[1]):
			var b4: float = float(s.craft_timer)
			s._update_crafting(ZB_DT)
			var d: float = float(s.craft_timer) - b4
			per_step = per_step and _near(d, ZB_DT * rate)
			expect_timer += ZB_DT * rate
		log_rows.append("L%d rate %.2f" % [L, rate])
	ok(no_jump, "REQ-0010-80: changing the level (3->1->2->0->3) leaves craft_timer EXACTLY as it was at that instant — nothing is rolled back or forward")
	ok(per_step, "REQ-0010-80: every step after a change adds dt * (the NEW level's multiplier at the bench's own cell) — %s" % str(log_rows))
	ok(_near(float(s.craft_timer), expect_timer), "REQ-0010-80: the final timer is the sum of the per-step increments, each at the rate of ITS step (%s vs %s)" % [str(s.craft_timer), str(expect_timer)])
	ok(s.buildings.has(bench) and float(bench.hp) == bench_hp and s.has_workbench(), "REQ-0010-80: the bench that fell outside the shrunk zone is intact (still built, same hp) — it merely works without the buff")
	_dispose(s)
	# the whole thing through sim.update: planks come out at the rates in force, no wood lost or created
	var e: Variant = _zone_sim(3, syn)
	var cap_e: Vector2i = _cap_tile(e)
	_wipe(e)
	e.stock[e.res_key("wood")] = 60
	var cells: Array = [cap_e + Vector2i(3, 0), cap_e + Vector2i(5, 0)]
	for c in cells:
		var cv: Vector2i = c
		e._place_building("workbench", cv.x, cv.y, -1)
	var wood0: int = int(e.res_amount("wood"))
	var planks0: int = int(e.res_amount("planks"))
	var timer: float = 0.0
	var planks: int = 0
	for seg in [[3, 60], [0, 60], [3, 30]]:
		var L2: int = int(seg[0])
		e.main_capsule["level"] = L2
		var rate2: float = 0.0
		for c in cells:
			rate2 += _zb_buff(syn, L2, "craft_mult") if _zb_in(cap_e, c, _zb_radius(syn, L2)) else 1.0
		for i in int(seg[1]):
			e.update(Scenarios.DT)
			_topup(e)
			timer += Scenarios.DT * rate2
			while timer >= 3.5:
				timer -= 3.5
				planks += 1
	ok(planks >= 15, "REQ-0010-80 setup: the run made planks (%d)" % planks)
	ok(int(e.res_amount("planks")) - planks0 == planks and wood0 - int(e.res_amount("wood")) == 2 * planks, "REQ-0010-80: planks made == the oracle's %d, and each cost exactly 2 wood (planks +%d, wood -%d) — nothing lost, nothing doubled across the level drop" % [planks, int(e.res_amount("planks")) - planks0, wood0 - int(e.res_amount("wood"))])
	ok(_near(float(e.craft_timer), timer), "REQ-0010-80: the real craft_timer after 150 ticks with the level 3 -> 0 -> 3 equals the per-step oracle (%s vs %s)" % [str(e.craft_timer), str(timer)])
	_dispose(e)


# =============================================================================================
# REQ-0010-15 — research tables (Session.research_rate): the same per-cell rule; no table -> 0; level 0 == the plain sum
# =============================================================================================
func _t_buff_research_process() -> void:
	var syn: Dictionary = _zone_table(4)
	var base: float = float(GameData.BUILDINGS.research_bench.research_rate)
	var wrong: Array = []
	for L in [1, 2, 3]:
		var s: Variant = _zone_sim(L, syn)
		var cap: Vector2i = _cap_tile(s)
		var R: int = _zb_radius(syn, L)
		var b: float = _zb_buff(syn, L, "research_mult")
		for off in _edge_offsets(R):
			var o: Vector2i = off
			var tbl: Variant = s._place_building("research_bench", cap.x + o.x, cap.y + o.y, -1)
			var got: float = _research_rate_of(s)
			var want: float = base * (b if _zb_in(cap, cap + o, R) else 1.0)
			if not _near(got, want):
				wrong.append("L%d table at %s: rate %.6f want %.6f" % [L, str(o), got, want])
			s._remove_building(tbl)
		_dispose(s)
	ok(wrong.is_empty(), "REQ-0010-15/80: one research table at every edge point/corner/step-past of levels 1..3 — rate = base * research_mult inside (edge inclusive), base outside — %d wrong, first %s" % [wrong.size(), str(wrong.slice(0, 3))])
	var s2: Variant = _zone_sim(3, syn)   # R = 6, research 4.0
	var cap2: Vector2i = _cap_tile(s2)
	_wipe(s2)
	s2._place_building("workbench", cap2.x + 1, cap2.y + 1, -1)
	s2._place_building("storage", cap2.x - 2, cap2.y, -1)
	ok(_research_rate_of(s2) == 0.0, "REQ-0010-15 (D8): at level 3 with a workbench and a storage but NO research table the research rate is exactly 0 (%s)" % str(_research_rate_of(s2)))
	s2._place_building("research_bench", cap2.x + 6, cap2.y, -1)   # edge: in
	s2._place_building("research_bench", cap2.x + 7, cap2.y, -1)   # out
	s2._place_building("research_bench", cap2.x, cap2.y - 6, -1)   # edge: in
	ok(_near(_research_rate_of(s2), base * 4.0 * 2.0 + base), "REQ-0010-15: two tables inside + one just outside -> 2 * base * 4.0 + base (%s)" % str(_research_rate_of(s2)))
	var s0: Variant = _zone_sim(0, syn)
	var cap0: Vector2i = _cap_tile(s0)
	s0._place_building("research_bench", cap0.x + 2, cap0.y, -1)
	s0._place_building("research_bench", cap0.x + 9, cap0.y, -1)
	ok(_research_rate_of(s0) == base * 2.0, "REQ-0010-12: at level 0 two tables (one inside R0) give exactly the plain sum 2 * base (%s)" % str(_research_rate_of(s0)))
	for w in [s2, s0]:
		_dispose(w)


# =============================================================================================
# REQ-0010-80 — research progress is not retroactive either: a project in progress, the level moves, progress is untouched and grows at the
# new rate (the real Session.tick_research, the real progression)
# =============================================================================================
func _t_buff_research_no_retroactivity() -> void:
	var syn: Dictionary = _zone_table(4)
	var sess: Variant = _session_on()
	var s: Variant = sess.sim
	s.capsule_table = syn
	var cap: Vector2i = _cap_tile(s)
	var bench_cell: Vector2i = cap + Vector2i(5, 0)   # in at R=6 / R=5 (edge), out at R=3 / R=2
	s._place_building("research_bench", bench_cell.x, bench_cell.y, -1)
	var best: Variant = null
	for r in sess.progression.available():
		if best == null or float(r.cost()) > float(best.cost()):
			best = r
	ok(best != null, "REQ-0010-80 setup: a research project is available")
	if best == null:
		_dispose_session(sess)
		return
	ok(sess.start_research(String(best.id)), "REQ-0010-80 setup: the project starts")
	var plan: Array = [[3, 3], [1, 3], [2, 3], [0, 3], [3, 3]]   # Σ rate·steps = 3·(4 + 1 + 3 + 1 + 4) = 39
	var day_len: float = maxf(1.0, float(s.time.day_len))
	var dday: float = 0.25 * float(best.cost()) / 39.0   # the whole run burns 25% of the project: it can never complete
	var dt: float = dday * day_len
	var base: float = float(GameData.BUILDINGS.research_bench.research_rate)
	var expect: float = float(sess.progression.active_progress())
	var no_jump: bool = true
	var per_step: bool = true
	for seg in plan:
		var L: int = int(seg[0])
		var before: float = float(sess.progression.active_progress())
		s.main_capsule["level"] = L
		no_jump = no_jump and float(sess.progression.active_progress()) == before
		var rate: float = base * (_zb_buff(syn, L, "research_mult") if _zb_in(cap, bench_cell, _zb_radius(syn, L)) else 1.0)
		for i in int(seg[1]):
			var b4: float = float(sess.progression.active_progress())
			sess.tick_research(dt)
			per_step = per_step and _near(float(sess.progression.active_progress()) - b4, rate * dday, 1.0e-7)
			expect += rate * dday
	ok(no_jump, "REQ-0010-80: moving the level mid-project leaves the accumulated research progress exactly where it was")
	ok(per_step, "REQ-0010-80: every tick_research step adds rate(current level, the table's own cell) * dday")
	ok(_near(float(sess.progression.active_progress()), expect, 1.0e-7) and float(sess.progression.active_progress()) < float(best.cost()), "REQ-0010-80: the final progress is the sum of the per-step increments (%s vs %s), the project did not complete" % [str(sess.progression.active_progress()), str(expect)])
	# D9: the number the research panel reads is the number the pump uses
	s.main_capsule["level"] = 3
	var vm: Dictionary = HudModel._research_slice(sess)
	ok(_near(float(vm.get("rate", -1.0)), float(sess.research_rate())) and _near(float(sess.research_rate()), base * 4.0), "D9/REQ-0010-15: the research panel's rate is the session's rate the pump uses (%s vs %s)" % [str(vm.get("rate", -1.0)), str(sess.research_rate())])
	_dispose_session(sess)


# =============================================================================================
# REQ-0010-15 — end to end through the real processes: a gather job and a melee hit inside the zone are quicker/harder than the same act
# outside; the baseline is the OFF-world number
# =============================================================================================
func _gather_ticks(s: Variant, hero: Vector2i, tree: Vector2i) -> int:
	var cell: int = tree.y * int(s.n) + tree.x
	s.map.nodes[cell] = {"kind": "tree", "amount": 40}
	_put_hero(s, hero)
	s.order_gather(tree.x, tree.y)
	var ticks: int = 0
	while int(s.map.nodes[cell].amount) == 40 and ticks < 120:
		s.update(Scenarios.DT)
		ticks += 1
	return ticks


func _first_hit(s: Variant, hero: Vector2i) -> float:
	_put_hero(s, hero)
	var e: Dictionary = GameData.make_raider(float(hero.x) + 1.0, float(hero.y) + 0.5, 1)
	e.hp = 1000.0
	e.maxhp = 1000.0
	s.enemies.append(e)
	s.order_attack(e)
	s.update(Scenarios.DT)
	return 1000.0 - float(e.hp)


func _t_buff_gather_melee_e2e() -> void:
	var syn: Dictionary = _zone_table(4)   # level 2: R = 5, gather 2.0, melee 1.5
	var in_cell: Vector2i = ZB_CAP + Vector2i(3, 0)
	var out_cell: Vector2i = ZB_CAP + Vector2i(9, 0)
	var s_in: Variant = _zone_sim(2, syn)
	var s_out: Variant = _zone_sim(2, syn)
	var s_ref: Variant = _sim_with(_pad_map(ZB_N, ZB_CAP), false, false, false)   # the OFF world: the baseline number
	_quiet(s_ref)
	for w in [s_in, s_out]:
		_wipe(w)
	var base_dur: float = 1.3 / (1.0 + float(s_ref.player.skills.gather) * 0.04)   # data.gd NODEINFO tree time, skill formula of the OFF world
	var t_in: int = _gather_ticks(s_in, in_cell, in_cell + Vector2i(1, 0))
	var t_out: int = _gather_ticks(s_out, out_cell, out_cell + Vector2i(1, 0))
	var want_out: int = int(ceil(base_dur / Scenarios.DT - 1.0e-6))
	var want_in: int = int(ceil(base_dur / 2.0 / Scenarios.DT - 1.0e-6))
	ok(absi(t_out - want_out) <= 1, "REQ-0010-15 (e2e): a gather job OUTSIDE the zone takes the plain time: %d ticks (plain %.2f s -> %d)" % [t_out, base_dur, want_out])
	ok(absi(t_in - want_in) <= 1, "REQ-0010-15 (e2e): the same job INSIDE the zone takes 1/2.0 of it: %d ticks (want %d)" % [t_in, want_in])
	ok(t_in < t_out, "REQ-0010-15 (e2e): inside is strictly quicker than outside (%d < %d ticks)" % [t_in, t_out])
	# melee: the first real hit of the real _do_attack
	var m_out: float = s_out.melee_damage()
	var hit_in: float = _first_hit(s_in, in_cell)
	var hit_out: float = _first_hit(s_out, out_cell)
	var plain: float = float(s_ref.melee_damage())
	ok(_near(hit_out, plain), "REQ-0010-15 (e2e): a melee hit OUTSIDE the zone deals the plain damage (%.3f vs %.3f)" % [hit_out, plain])
	ok(_near(hit_in, plain * 1.5), "REQ-0010-15 (e2e): the same hit INSIDE the zone deals melee_mult(2) = 1.5x (%.3f vs %.3f)" % [hit_in, plain * 1.5])
	ok(m_out > 0.0, "REQ-0010-15 setup: the reference damage is positive")
	for w in [s_in, s_out, s_ref]:
		_dispose(w)


# =============================================================================================
# D9 — the node tooltip's «≈X с за одиницю» is the time the sim then actually works with. The buff depends on where the hero STANDS at
# work, and the tooltip is read while he stands elsewhere: both mismatches (hero in / tree out, hero out / tree in) must not show a lie
# =============================================================================================
func _t_buff_inspector_one_truth() -> void:
	var syn: Dictionary = _zone_table(4)   # level 2: R = 5, gather 2.0
	var cases: Array = [
		["hero inside the zone, the tree outside it", Vector2i(1, 0), Vector2i(11, 0)],
		["hero outside the zone, the tree inside it", Vector2i(11, 0), Vector2i(3, 0)],
	]
	for cs in cases:
		var label: String = String(cs[0])
		var s: Variant = _zone_sim(2, syn)
		var cap: Vector2i = _cap_tile(s)
		var hero: Vector2i = cap + (cs[1] as Vector2i)
		var tree: Vector2i = cap + (cs[2] as Vector2i)
		s.map.nodes[tree.y * int(s.n) + tree.x] = {"kind": "tree", "amount": 40}
		_put_hero(s, hero)
		var vm: Dictionary = HudModel._inspect_slice(s, {"hover": tree})
		var shown: String = ""
		for l in (vm.get("lines", []) as Array):
			if String(l).begins_with("≈"):
				shown = String(l)
		ok(shown != "", "D9 setup [%s]: the node tooltip carries a time line (%s)" % [label, str(vm.get("lines", []))])
		s.order_gather(tree.x, tree.y)
		var dur: float = -1.0
		var stood_in: bool = false
		for t in 200:
			s.update(Scenarios.DT)
			var a: Variant = s.player.get("action")
			if a is Dictionary and float((a as Dictionary).get("dur", 0.0)) > 0.0:
				dur = float((a as Dictionary).dur)
				stood_in = MainCapsule.in_zone(s, _hero_cell(s))
				break
		ok(dur > 0.0, "D9 setup [%s]: the hero reached the tree and started working (dur %.3f, he stands %s the zone)" % [label, dur, "in" if stood_in else "out of"])
		ok(shown == "≈%.1f с за одиницю" % dur, "D9 [%s]: the tooltip says «%s» but the sim works with %.3f s per unit — the player is shown a number the sim does not use" % [label, shown, dur])
		_dispose(s)


# =============================================================================================
# REQ-0010-01 — flag OFF: the hooks are inert even if a stray record and a table are lying around (the hook sits under the flag)
# =============================================================================================
func _t_buff_off_inert() -> void:
	var node: Dictionary = {"kind": "tree"}
	var syn: Dictionary = _zone_table(4)
	var clean: Variant = _sim_with(_pad_map(ZB_N, ZB_CAP), false, false, false)
	var stray: Variant = _sim_with(_pad_map(ZB_N, ZB_CAP), false, false, false)
	for w in [clean, stray]:
		_quiet(w)
	stray.capsule_table = syn
	stray.main_capsule = {"kind": "main", "tile": [ZB_CAP.x, ZB_CAP.y], "level": 3, "invested": {}, "owner": "local"}
	ok(stray.use_main_capsule == false and clean.use_main_capsule == false, "REQ-0010-01 setup: both worlds are flag OFF")
	for w in [clean, stray]:
		_hero_px(w, float(ZB_CAP.x) + 1.5, float(ZB_CAP.y) + 0.5)
		w._place_building("workbench", ZB_CAP.x + 2, ZB_CAP.y, -1)
		w._place_building("research_bench", ZB_CAP.x, ZB_CAP.y - 2, -1)
	ok(stray.gather_time(node) == clean.gather_time(node) and stray.melee_damage() == clean.melee_damage(), "REQ-0010-01: OFF + a stray level-3 record inside its 'zone': gather_time and melee_damage are the clean OFF world's, bit for bit")
	var plain_timer: float = 0.0
	for t in 6:
		clean._update_crafting(ZB_DT)
		stray._update_crafting(ZB_DT)
		plain_timer += ZB_DT * 1.0   # one bench
	ok(float(stray.craft_timer) == float(clean.craft_timer) and float(clean.craft_timer) == plain_timer, "REQ-0010-01: ... craft_timer is the plain dt * count (%s vs %s vs %s)" % [str(stray.craft_timer), str(clean.craft_timer), str(plain_timer)])
	ok(_research_rate_of(stray) == _research_rate_of(clean) and _research_rate_of(clean) == float(GameData.BUILDINGS.research_bench.research_rate), "REQ-0010-01: ... and Session.research_rate is the plain sum (%s)" % str(_research_rate_of(stray)))
	for w in [clean, stray]:
		_dispose(w)


# =============================================================================================
# the buffs are PURE reads (no RNG, no state, no hash movement) and persist nothing of their own: radius/buffs/rates are recomputed
# =============================================================================================
func _t_buff_pure_and_stateless() -> void:
	var node: Dictionary = {"kind": "tree"}
	var s: Variant = _leveled(3)
	var cap: Vector2i = _cap_tile(s)
	s._place_building("workbench", cap.x + 2, cap.y, -1)
	s._place_building("research_bench", cap.x, cap.y - 2, -1)
	_hero_px(s, float(cap.x) + 1.5, float(cap.y) + 0.5)
	var h0: String = Persistence.world_hash(s)
	var cur0: Array = _cursors(s)
	var cap0: String = var_to_str(s.main_capsule)
	var sig0: String = _world_sig(s)
	var timer0: float = float(s.craft_timer)
	var acc: float = 0.0
	for i in 200:
		for k in ZB_KEYS:
			acc += MainCapsule.buff_at(s, String(k), cap + Vector2i(i % 9 - 4, i % 7 - 3))
		acc += float(MainCapsule.in_zone(s, cap + Vector2i(i % 21 - 10, 0)))
		acc += s.gather_time(node) + s.melee_damage() + _research_rate_of(s)
	ok(acc > 0.0 and Persistence.world_hash(s) == h0 and _cursors(s) == cur0 and var_to_str(s.main_capsule) == cap0 and _world_sig(s) == sig0 and float(s.craft_timer) == timer0, "REQ-0010-15/34: 200 rounds of buff_at/in_zone/gather_time/melee_damage/research_rate change nothing — hash, record, world and the three RNG cursors are as before")
	var rec: Dictionary = Persistence.serialize_region(s)
	var keys: Array = []
	_all_keys(rec.get("main_capsule", {}), keys)
	var derived: String = _first_word_in(keys, ["buff", "zone", "radius", "mult", "core_hp"])
	ok(derived == "", "REQ-0010-80/88: the saved capsule record stores no derived value (buffs/zone/radius/defence are recomputed from level + table) — %s in %s" % [derived, str(keys)])
	var rkeys: Array = []
	_all_keys(Persistence.serialize_runtime(s), rkeys)
	var rderived: String = _first_word_in(rkeys, ["buff", "zone", "radius", "mult"])
	ok(rderived == "", "REQ-0010-80: ... nor does the runtime half cache a buff, a zone or a multiplier — %s" % rderived)
	_dispose(s)


# =============================================================================================
# D13 / REQ-0010-80 — twins with buffs in effect stay in lock-step; a resume payload cut MID-CRAFT restores the same buffs from level + table
# and the restored world then runs exactly like the live one (the real catalog table, JSON round trip)
# =============================================================================================
func _craft_world() -> Variant:
	var s: Variant = _zone_sim(2, _table_copy())
	var cap: Vector2i = _cap_tile(s)
	_wipe(s)
	s.stock[s.res_key("wood")] = 80
	s._place_building("workbench", cap.x + 2, cap.y, -1)        # inside (R(2) = 7 in the catalog)
	s._place_building("workbench", cap.x + 9, cap.y, -1)        # outside
	s._place_building("research_bench", cap.x, cap.y - 3, -1)   # inside
	return s


func _t_buff_twin_and_resume() -> void:
	var a: Variant = _craft_world()
	var b: Variant = _craft_world()
	for t in 300:
		a.update(Scenarios.DT)
		b.update(Scenarios.DT)
		_topup(a)
		_topup(b)
	ok(Persistence.world_hash(a) == Persistence.world_hash(b) and float(a.craft_timer) == float(b.craft_timer) and a.res_amount("planks") == b.res_amount("planks"), "D13/REQ-0010-80: two twin ON worlds with a buffed bench and an unbuffed one agree on world_hash, craft_timer and planks after 300 ticks")
	ok(int(a.res_amount("planks")) >= 5, "REQ-0010-80 setup: the twins crafted (%d planks)" % int(a.res_amount("planks")))
	# the buff is really in effect in this world (so the comparison below is not between two neutral worlds)
	var rows: Array = _raw_rows()
	var want_rate: float = float((rows[2] as Dictionary).buffs.craft_mult) + 1.0
	ok(_near(_craft_rate_of(a), want_rate), "REQ-0010-15 setup: the inside bench is buffed by level 2's craft_mult and the outside one is not (%s vs %s)" % [str(_craft_rate_of(a)), str(want_rate)])
	# resume mid-craft
	var live: Variant = _craft_world()
	for t in 150:
		live.update(Scenarios.DT)
		_topup(live)
	ok(float(live.craft_timer) > 0.0 and float(live.craft_timer) < 3.5, "REQ-0010-80 setup: the payload is cut with a craft in progress (timer %s)" % str(live.craft_timer))
	var payload: Dictionary = _json_rt(Persistence.resume_payload(live))
	var rest: Variant = Sim.new()
	var accepted: bool = Persistence.restore(rest, payload)
	_mute(rest)   # the director's weights are not part of any payload: the live world is muted by _quiet, so the restored one must be too
	ok(accepted and rest.load_error == &"" and rest.capsule_level() == 2 and _cap_tile(rest) == _cap_tile(live), "REQ-0010-80: the resume payload loads (level 2, same tile)")
	ok(_near(_craft_rate_of(rest), _craft_rate_of(live)) and _research_rate_of(rest) == _research_rate_of(live), "REQ-0010-80: the restored world recomputes the same rates from level + table (craft %s vs %s, research %s vs %s)" % [str(_craft_rate_of(rest)), str(_craft_rate_of(live)), str(_research_rate_of(rest)), str(_research_rate_of(live))])
	var cap: Vector2i = _cap_tile(live)
	var probe_ok: bool = true
	for L in [0, 2]:
		live.main_capsule["level"] = L
		rest.main_capsule["level"] = L
		for dx in range(-9, 10):
			probe_ok = probe_ok and MainCapsule.in_zone(live, cap + Vector2i(dx, 0)) == MainCapsule.in_zone(rest, cap + Vector2i(dx, 0)) and MainCapsule.buff_at(live, "craft_mult", cap + Vector2i(dx, 0)) == MainCapsule.buff_at(rest, "craft_mult", cap + Vector2i(dx, 0))
	live.main_capsule["level"] = 2
	rest.main_capsule["level"] = 2
	ok(probe_ok, "REQ-0010-80: after the JSON round trip the zone and the buff agree cell for cell with the live world (the tile survived as an integer)")
	for t in 150:
		live.update(Scenarios.DT)
		rest.update(Scenarios.DT)
		_topup(live)
		_topup(rest)
	ok(Persistence.world_hash(live) == Persistence.world_hash(rest) and float(live.craft_timer) == float(rest.craft_timer) and live.res_amount("planks") == rest.res_amount("planks"), "D13/REQ-0010-80: 150 ticks after the restore the live world and the restored one still agree on world_hash, craft_timer and planks")
	for w in [a, b, live, rest]:
		_dispose(w)


# =============================================================================================
# REQ-0010-88 x 80 — a level-5 save against a lower table: the zone and the buffs are the CLAMPED row's (and never an out-of-range read)
# =============================================================================================
func _t_buff_table_clamp() -> void:
	var node: Dictionary = {"kind": "tree"}
	var big: Dictionary = _zone_table(6)
	var src: Variant = _zone_sim(5, big)
	var payload: Dictionary = _json_rt(Persistence.resume_payload(src))
	var low: Dictionary = _zone_table(3)   # rows 0..2: R = 2,3,5; level 2: gather 2.0, melee 1.5, craft 2.5, research 3.0
	var y: Variant = Sim.new()
	y.capsule_table = low
	var accepted: bool = Persistence.restore(y, payload)
	ok(accepted and y.capsule_level() == 2, "REQ-0010-88 setup: the level-5 save loads against the 3-row table, level clamped to 2 (%d)" % y.capsule_level())
	var cap: Vector2i = _cap_tile(y)
	_hero_px(y, float(cap.x) + 14.5, float(cap.y) + 0.5)
	var g0: float = y.gather_time(node)
	var m0: float = y.melee_damage()
	var bad: Array = []
	for pr in _edge_probes(cap, 5):
		var p: Vector2 = pr
		_hero_px(y, p.x, p.y)
		var inside: bool = _zb_in(cap, Vector2i(floori(p.x), floori(p.y)), 5)
		if not _near(y.gather_time(node), g0 / 2.0 if inside else g0) or not _near(y.melee_damage(), m0 * 1.5 if inside else m0):
			bad.append("(%.2f,%.2f) inside=%s" % [p.x, p.y, str(inside)])
	ok(bad.is_empty(), "REQ-0010-88/15: after the clamp the zone is level 2's (R=5, NOT level 5's R=9) and the buffs are its row's (gather 2.0, melee 1.5) — wrong probes: %s" % str(bad.slice(0, 3)))
	y._place_building("workbench", cap.x + 5, cap.y, -1)
	y._place_building("workbench", cap.x + 6, cap.y, -1)
	ok(_near(_craft_rate_of(y), 2.5 + 1.0), "REQ-0010-88/15: the craft rate after the clamp is level 2's row too (edge bench 2.5, bench past it 1.0) — %s" % str(_craft_rate_of(y)))
	for w in [src, y]:
		_dispose(w)


# =============================================================================================
# WAVE 0010-W2b-b — closing the integrity gaps (F3) on the W2b block: (1) the ZONE-EDGE BAND of the node tooltip, (2) the metric's safe failure
#
# (1) REQ-0010-15 x D9. The tooltip «≈X с за одиницю» is read while the hero stands elsewhere; the buff the sim then applies belongs to the cell
# where he STANDS at work, and that cell is decided by his walk. Deep inside / far outside the zone every cell of the node's 3x3 agrees, so a
# naive hint is right; the lie lives in the BAND — a node 0..1 cell from the edge, d = R-1..R+2 from the capsule. The oracle is the sim itself:
# the hint (HudModel._inspect_slice, what the player SEES) against `action.dur` of the real order_gather + update walk (what the sim COUNTS),
# for nodes on the axes, diagonals and off-axis, heroes next to the node (inside the reach: he works where he stands), a few cells away (off
# the cell's centre), with and without a wall that bends the path, at the frame steps the game really feeds (60 fps = 0.0167 .. 30 fps x3 =
# 0.1). Plus the REQ-0010-15 oracle on the cell where the hero really worked (Chebyshev, edge inclusive) and an EDGE sweep: starts placed so
# the straight walk meets the reach circle EXACTLY on a cell border (the entry point must land on the NEAR side of it).
# (2) REQ-0010-80. The metric is the DATA's; an unknown one means «no zone» (documented: capsule.gd zone_distance, godot-sim.md): no buff,
# no stock reach — never «the whole map is the zone». A missing key is Chebyshev (the one value the spec names).
# Expectations come from the table this test builds + the Chebyshev oracle `_zb_in`; none from capsule.gd. A red test here is a finding.
# =============================================================================================
const BAND_DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
const BAND_AXES: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# the largest simulated step at which the tooltip is promised EXACT: the game feeds sim.update(frame_dt * speed); 60 fps x1 = 0.0167, 30 fps x3 = 0.1
# (speeds x1..x3, REQ-0012-83). Above it («≈») the prediction may be off by one walking step inside the band — see `_t_buff_inspector_band_limit`.
const BAND_EXACT_DT_MAX := 0.1


# wall layouts: 0 none; 1 a vertical wall on the column just past the zone's east edge (gap at its south end); 2 a horizontal wall on the row
# just past the north edge (gap at its west end): the hero is made to walk AROUND it, so the path (not the straight line) decides the entry cell
func _band_world(level: int, table: Dictionary, wall: int) -> Variant:
	var s: Variant = _zone_sim(level, table)
	var cap: Vector2i = _cap_tile(s)
	var R: int = _zb_radius(table, level)
	if wall == 1:
		for y in range(cap.y - R - 3, cap.y + R + 1):
			s._place_building("wall", cap.x + R + 1, y, -1)
	elif wall == 2:
		for x in range(cap.x - R, cap.x + R + 4):
			s._place_building("wall", x, cap.y - R - 1, -1)
	return s


# node offsets from the capsule: d = R-1 (all inside), R (the edge), R+1 (just out), R+2 (all out) — on the 4 axes, the 4 diagonals and 4 off-axis lines;
# `band_only` keeps the two rings whose 3x3 straddles the edge (d = R, R+1)
func _band_nodes(R: int, band_only: bool = false) -> Array:
	var out: Array = []
	for d in ([R, R + 1] if band_only else [R - 1, R, R + 1, R + 2]):
		for dir in BAND_DIRS:
			out.append((dir as Vector2i) * d)
		out.append(Vector2i(d, 1))
		out.append(Vector2i(-1, -d))
		out.append(Vector2i(-d, -1))
		out.append(Vector2i(1, d))
	return out


# start points: the 8 cells around the node (centres; the 4 orthogonal ones are INSIDE the reach, so he works where he stands) + a few cells away
# on the given directions, deliberately OFF the centre of his cell (the hero is not always at a cell's centre)
func _band_heroes(node: Vector2i, far_dirs: Array) -> Array:
	var out: Array = []
	for d in BAND_DIRS:
		var dv: Vector2i = d
		out.append(Vector2(float(node.x + dv.x) + 0.5, float(node.y + dv.y) + 0.5))
	for d in far_dirs:
		var fv: Vector2i = d
		var k: int = 3 if fv.x == 0 or fv.y == 0 else 2
		out.append(Vector2(float(node.x + fv.x * k) + 0.5 + 0.31, float(node.y + fv.y * k) + 0.5 - 0.17))
	return out


# the body must start every run the same: the sims are reused and a long walk tires the hero (an `exhaustion` hediff slows the work, which would
# move `dur` between the hint and the first working tick)
func _band_reset(s: Variant) -> void:
	_quiet(s)
	_topup(s)
	if s.health != null:
		s.health.hediffs.clear()
		s.health.blood = 1.0
	s.player.action = null


# one real gather order: the hint the player sees at hover time, then the walk, up to the FIRST working tick -> what the sim counts
func _band_run(s: Variant, node: Vector2i, p: Vector2, dt: float) -> Dictionary:
	_band_reset(s)
	s.map.nodes.clear()
	s.map.nodes[node.y * int(s.n) + node.x] = {"kind": "tree", "amount": 40}
	_hero_px(s, p.x, p.y)
	var vm: Dictionary = HudModel._inspect_slice(s, {"hover": node})
	var shown: String = ""
	for l in (vm.get("lines", []) as Array):
		if String(l).begins_with("≈"):
			shown = String(l)
	s.order_gather(node.x, node.y)
	var dur: float = -1.0
	var cell: Vector2i = Vector2i(-1, -1)
	var ticks: int = 0
	while ticks < 1500:
		s.update(dt)
		ticks += 1
		var a: Variant = s.player.get("action")
		if a is Dictionary and float((a as Dictionary).get("dur", 0.0)) > 0.0:
			dur = float((a as Dictionary).dur)
			cell = _hero_cell(s)
			break
	return {"shown": shown, "dur": dur, "cell": cell, "ticks": ticks}


# does the node's 3x3 hold passable cells of BOTH verdicts (the band: where the hero's stand decides the buff)
func _band_mixed(s: Variant, cap: Vector2i, R: int, node: Vector2i) -> bool:
	var ins: int = 0
	var outs: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Vector2i = node + Vector2i(dx, dy)
			if s.is_blocked(c.x, c.y):
				continue
			if _zb_in(cap, c, R):
				ins += 1
			else:
				outs += 1
	return ins > 0 and outs > 0


func _band_new_stats() -> Dictionary:
	return {"runs": 0, "bad": [], "bad_unmixed_list": [], "bad_unmixed": 0, "bad_mixed": 0, "work_wrong": [], "stuck": [], "diverge": 0, "near_diverge": 0, "buffed": 0, "unbuffed": 0, "mixed_runs": 0}


# one (node, start) case into `st`: the tooltip == the work time, and the work time is the REQ-0010-15 time of the cell the hero really stood on
func _band_case(st: Dictionary, s: Variant, cap: Vector2i, R: int, mult: float, plain: float, node: Vector2i, p: Vector2, dt: float, tag: String) -> void:
	var r: Dictionary = _band_run(s, node, p, dt)
	st.runs = int(st.runs) + 1
	if float(r.dur) < 0.0:
		(st.stuck as Array).append("%s node %s start (%.2f,%.2f)" % [tag, str(node - cap), p.x - float(cap.x), p.y - float(cap.y)])
		return
	var stand: Vector2i = r.cell
	var stand_in: bool = _zb_in(cap, stand, R)
	var node_in: bool = _zb_in(cap, node, R)
	var mixed: bool = _band_mixed(s, cap, R, node)
	var centre: Vector2 = Vector2(float(node.x) + 0.5, float(node.y) + 0.5)
	if stand_in != node_in:
		st.diverge = int(st.diverge) + 1
		if p.distance_to(centre) < float(s.GATHER_REACH):
			st.near_diverge = int(st.near_diverge) + 1   # he started inside the reach: he works where he stands, NOT where the tree is
	if stand_in:
		st.buffed = int(st.buffed) + 1
	else:
		st.unbuffed = int(st.unbuffed) + 1
	if mixed:
		st.mixed_runs = int(st.mixed_runs) + 1
	if not _near(float(r.dur), plain / mult if stand_in else plain):
		(st.work_wrong as Array).append("%s node %s stand %s: dur %.4f" % [tag, str(node - cap), str(stand - cap), float(r.dur)])
	if String(r.shown) != "≈%.1f с за одиницю" % float(r.dur):
		(st.bad as Array).append("%s node %s start (%.2f,%.2f) stand %s: tooltip «%s», sim works %.4f s" % [tag, str(node - cap), p.x - float(cap.x), p.y - float(cap.y), str(stand - cap), String(r.shown), float(r.dur)])
		if mixed:
			st.bad_mixed = int(st.bad_mixed) + 1
		else:
			st.bad_unmixed = int(st.bad_unmixed) + 1
			(st.bad_unmixed_list as Array).append((st.bad as Array)[(st.bad as Array).size() - 1])


func _band_sweep(level: int, table: Dictionary, dt: float, walls: Array, far_dirs: Array) -> Dictionary:
	var R: int = _zb_radius(table, level)
	var mult: float = _zb_buff(table, level, "gather_mult")
	var st: Dictionary = _band_new_stats()
	for wall in walls:
		var s: Variant = _band_world(level, table, int(wall))
		var cap: Vector2i = _cap_tile(s)
		var plain: float = float(GameData.NODEINFO.tree.time) / (1.0 + float(s.player.skills.gather) * 0.04)   # data time / the OFF world's skill formula
		for off in _band_nodes(R):
			var node: Vector2i = cap + (off as Vector2i)
			if node.x < 1 or node.y < 1 or node.x > ZB_N - 2 or node.y > ZB_N - 2 or s.is_blocked(node.x, node.y):
				continue
			for hs in _band_heroes(node, far_dirs):
				var p: Vector2 = hs
				var hc: Vector2i = Vector2i(floori(p.x), floori(p.y))
				if hc.x < 1 or hc.y < 1 or hc.x > ZB_N - 2 or hc.y > ZB_N - 2 or s.is_blocked(hc.x, hc.y):
					continue
				_band_case(st, s, cap, R, mult, plain, node, p, dt, "L%d w%d dt%s" % [level, int(wall), str(dt)])
		_dispose(s)
	return st


# the node walled in on its 4 orthogonal sides — or on all 8 (`ring`) — (the path is 4-connected, so it is UNREACHABLE and the sim's hero walks
# straight at it, through the walls): the walls are per node, taken down after it
func _band_sweep_enclosed(level: int, table: Dictionary, dts: Array, far_dirs: Array, ring: bool) -> Dictionary:
	var R: int = _zb_radius(table, level)
	var mult: float = _zb_buff(table, level, "gather_mult")
	var st: Dictionary = _band_new_stats()
	var s: Variant = _band_world(level, table, 0)
	var cap: Vector2i = _cap_tile(s)
	var plain: float = float(GameData.NODEINFO.tree.time) / (1.0 + float(s.player.skills.gather) * 0.04)
	for off in _band_nodes(R, true):
		var node: Vector2i = cap + (off as Vector2i)
		if node.x < 2 or node.y < 2 or node.x > ZB_N - 3 or node.y > ZB_N - 3 or s.is_blocked(node.x, node.y):
			continue
		var built: Array = []
		for d in (BAND_DIRS if ring else BAND_AXES):
			var w: Vector2i = node + (d as Vector2i)
			if not s.is_blocked(w.x, w.y):
				built.append(s._place_building("wall", w.x, w.y, -1))
		for dt in dts:
			for hs in _band_heroes(node, far_dirs):
				var p: Vector2 = hs
				var hc: Vector2i = Vector2i(floori(p.x), floori(p.y))
				if hc.x < 1 or hc.y < 1 or hc.x > ZB_N - 2 or hc.y > ZB_N - 2 or s.is_blocked(hc.x, hc.y):
					continue
				_band_case(st, s, cap, R, mult, plain, node, p, float(dt), "L%d walled-in dt%s" % [level, str(dt)])
		for b in built:
			s._remove_building(b)
	_dispose(s)
	return st


func _band_brief(st: Dictionary) -> String:
	return "%d runs, %d tooltip lies, %d stuck, first %s" % [int(st.runs), (st.bad as Array).size(), (st.stuck as Array).size(), str((st.bad as Array).slice(0, 2))]


# =============================================================================================
# REQ-0010-15 x D9 — the band sweep: hint == the sim's time at every frame step the game feeds
# =============================================================================================
func _t_buff_inspector_band() -> void:
	var syn: Dictionary = _zone_table(4)   # level 2: R = 5, gather x2.0 (level 1: R 3 x1.5, level 3: R 6 x2.5)
	var plans: Array = [
		[2, 0.1, [0, 1, 2], BAND_DIRS],
		[2, 0.05, [0, 1, 2], BAND_AXES],
		[2, 0.0167, [0], BAND_AXES],
		[1, 0.1, [0, 2], BAND_AXES],
		[3, 0.1, [0, 1], BAND_AXES],
	]
	var sum: Dictionary = _band_new_stats()
	for pl in plans:
		var st: Dictionary = _band_sweep(int(pl[0]), syn, float(pl[1]), pl[2] as Array, pl[3] as Array)
		var tag: String = "level %d, dt %s, walls %s" % [int(pl[0]), str(pl[1]), str(pl[2])]
		ok((st.bad as Array).is_empty(), "REQ-0010-15 x D9 [%s]: the node tooltip equals the time the sim then works with, over the zone-edge band — %s" % [tag, _band_brief(st)])
		ok((st.work_wrong as Array).is_empty() and (st.stuck as Array).is_empty(), "REQ-0010-15 [%s]: the work time is gather_mult(level) iff the cell the hero really stood on is inside the Chebyshev zone (edge inclusive), the plain time otherwise; every walk reached the tree — wrong %s, stuck %s" % [tag, str((st.work_wrong as Array).slice(0, 2)), str((st.stuck as Array).slice(0, 2))])
		for k in ["runs", "diverge", "near_diverge", "buffed", "unbuffed", "mixed_runs"]:
			sum[k] = int(sum[k]) + int(st[k])
	# the sweep is not vacuous: it contains the cases a naive «buff of the TREE's cell» hint gets wrong, the hero-already-in-reach ones, both outcomes
	ok(int(sum.diverge) >= 100, "REQ-0010-15 x D9 setup: %d of %d runs have the hero WORKING in a cell whose verdict differs from the tree's own cell (a hint that reads the tree's cell is wrong on every one)" % [int(sum.diverge), int(sum.runs)])
	ok(int(sum.near_diverge) >= 20, "REQ-0010-15 x D9 setup: %d runs start with the hero INSIDE the reach (he works where he stands) on a cell of the other verdict than the tree's" % int(sum.near_diverge))
	ok(int(sum.buffed) >= 100 and int(sum.unbuffed) >= 100, "REQ-0010-15 x D9 setup: both outcomes are reached (%d worked inside the zone, %d outside)" % [int(sum.buffed), int(sum.unbuffed)])
	ok(int(sum.mixed_runs) >= 100, "REQ-0010-15 x D9 setup: %d runs are on a node whose 3x3 holds both verdicts (the band proper)" % int(sum.mixed_runs))


# =============================================================================================
# REQ-0010-15 x D9 — a node the path cannot reach (the path is 4-connected: walls on its 4 orthogonal sides are enough): the sim's hero walks
# straight at it from where he stands, and the tooltip must follow
# =============================================================================================
func _t_buff_inspector_band_walled_in() -> void:
	var syn: Dictionary = _zone_table(4)
	var runs: int = 0
	var stuck: int = 0
	var bad: Array = []
	var work_wrong: Array = []
	var diverge: int = 0
	var st: Dictionary = _band_sweep_enclosed(2, syn, [0.1, 0.05], BAND_AXES, false)
	runs += int(st.runs)
	stuck += (st.stuck as Array).size()
	bad.append_array(st.bad as Array)
	work_wrong.append_array(st.work_wrong as Array)
	diverge += int(st.diverge)
	ok(runs >= 200 and diverge >= 10, "REQ-0010-15 x D9 setup: %d walks at nodes walled in on 4 sides (%d of them work on a cell of the other verdict than the tree's), %d stuck" % [runs, diverge, stuck])
	ok(bad.is_empty(), "REQ-0010-15 x D9: for a node the path cannot reach the tooltip still equals the time the sim works with (%d lies, first %s)" % [bad.size(), str(bad.slice(0, 3))])
	ok(work_wrong.is_empty(), "REQ-0010-15: ... and that time is gather_mult(level) iff the cell the hero stopped on is inside the zone — wrong %s" % str(work_wrong.slice(0, 3)))


# =============================================================================================
# REQ-0010-15 x D9 — the same with the node walled in on ALL 8 sides. Nothing passable is left in its 3x3 but the tree's own cell, yet the hero (the
# sim does not refuse an unreachable gather order: `order_gather` has no path check) still walks straight at it THROUGH the wall and stops, inside the
# reach, on a wall cell — whose verdict can be the other one. The tooltip must still equal the time the sim works with (D9 has no «unless walled in»)
# =============================================================================================
func _t_buff_inspector_band_ringed() -> void:
	var syn: Dictionary = _zone_table(4)
	var runs: int = 0
	var stuck: int = 0
	var bad: Array = []
	var diverge: int = 0
	var st: Dictionary = _band_sweep_enclosed(2, syn, [0.1, 0.05, 0.0167], BAND_AXES, true)
	runs += int(st.runs)
	stuck += (st.stuck as Array).size()
	bad.append_array(st.bad as Array)
	diverge += int(st.diverge)
	ok(runs >= 200 and diverge >= 10, "REQ-0010-15 x D9 setup: %d walks at nodes walled in on all 8 sides (%d of them work on a cell of the other verdict than the tree's), %d stuck" % [runs, diverge, stuck])
	ok(bad.is_empty(), "REQ-0010-15 x D9: for a node walled in on all 8 sides the tooltip still equals the time the sim works with — %d lies, first %s" % [bad.size(), str(bad.slice(0, 3))])


# =============================================================================================
# the stated limit of the «≈»: exact at every frame step the game feeds (<= BAND_EXACT_DT_MAX); at coarser steps (a frame hitch) the tooltip may
# name the wrong verdict ONLY in the band — outside it (all of the node's 3x3 agree) it stays exact at ANY step. The in-band count is printed, not
# hidden: a bigger step lets the hero overshoot into the next cell before the sim looks at his position (spec question: is that acceptable?)
# =============================================================================================
func _t_buff_inspector_band_limit() -> void:
	var syn: Dictionary = _zone_table(4)
	ok(1.0 / 60.0 * 3.0 <= BAND_EXACT_DT_MAX and 1.0 / 30.0 * 3.0 <= BAND_EXACT_DT_MAX + 1.0e-9, "REQ-0010-15 x D9: a 60 fps frame at x3 (%.4f) and a 30 fps frame at x3 (%.4f) are inside the promised-exact step range (<= %s)" % [1.0 / 60.0 * 3.0, 1.0 / 30.0 * 3.0, str(BAND_EXACT_DT_MAX)])
	for dt in [0.15, 0.2, 0.3]:
		var st: Dictionary = _band_sweep(2, syn, float(dt), [0, 1], BAND_AXES)
		ok(int(st.bad_unmixed) == 0, "REQ-0010-15 x D9 [dt %s]: outside the band (the node's 3x3 agrees on the zone) the tooltip is exact even on a coarse step — %d lies outside the band, first %s" % [str(dt), int(st.bad_unmixed), str((st.bad_unmixed_list as Array).slice(0, 2))])
		ok((st.stuck as Array).is_empty(), "REQ-0010-15 [dt %s]: every walk still reaches the tree (%d stuck)" % [str(dt), (st.stuck as Array).size()])
		print("  note: KNOWN LIMIT [dt %s]: %d of %d runs show a tooltip of the other verdict (all in the band) — REQ-0010-15 / D9 give no tolerance for a coarse step" % [str(dt), int(st.bad_mixed), int(st.runs)])


# =============================================================================================
# REQ-0010-15 x D9 — the EDGE sweep. The hero need not stand at a cell's centre; his walk (4-connected path, a straight segment from where he
# stands to the centre of the first path cell Q) can meet the reach circle (radius GATHER_REACH around the tree's centre) EXACTLY on the border
# between his cell C and Q. The cell he then works in is the one just PAST the border (he stops inside the circle, not on it), so a tooltip
# that lands on the border's far side names the other verdict whenever the zone edge IS that border. Starts are built by pure geometry from the
# sim's own path: E = (circle ∩ the C|Q border), P = E + 0.03..0.06 * (the unit vector from Q's centre through E), inside C.
# =============================================================================================
func _band_edge_starts(s: Variant, cap: Vector2i, R: int) -> Array:
	var out: Array = []
	var reach: float = float(s.GATHER_REACH)
	for off in _band_nodes(R):
		var node: Vector2i = cap + (off as Vector2i)
		if node.x < 2 or node.y < 2 or node.x > ZB_N - 3 or node.y > ZB_N - 3 or s.is_blocked(node.x, node.y):
			continue
		var c: Vector2 = Vector2(float(node.x) + 0.5, float(node.y) + 0.5)
		for dv in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:   # the diagonal neighbours: from an orthogonal one he is already in reach
			var cell: Vector2i = node + (dv as Vector2i)
			if s.is_blocked(cell.x, cell.y):
				continue
			var path: Array = s.compute_path(cell.x, cell.y, node.x, node.y)
			if path.is_empty():
				continue
			var q: Vector2i = path[0]
			if absi(q.x - cell.x) + absi(q.y - cell.y) != 1 or _zb_in(cap, cell, R) == _zb_in(cap, q, R):
				continue   # the C|Q border is not on the zone edge: nothing to mispredict
			var qc: Vector2 = Vector2(float(q.x) + 0.5, float(q.y) + 0.5)
			var cands: Array = []
			if q.x == cell.x:   # vertical neighbours: the border is the horizontal line y = max(C.y, Q.y)
				var by: float = float(maxi(cell.y, q.y))
				if absf(by - c.y) < reach:
					var h: float = sqrt(reach * reach - (by - c.y) * (by - c.y))
					cands = [Vector2(c.x - h, by), Vector2(c.x + h, by)]
			else:               # horizontal neighbours: the border is the vertical line x = max(C.x, Q.x)
				var bx: float = float(maxi(cell.x, q.x))
				if absf(bx - c.x) < reach:
					var h2: float = sqrt(reach * reach - (bx - c.x) * (bx - c.x))
					cands = [Vector2(bx, c.y - h2), Vector2(bx, c.y + h2)]
			for e in cands:
				var ev: Vector2 = e
				if (q.x == cell.x and floori(ev.x) != cell.x) or (q.y == cell.y and floori(ev.y) != cell.y):
					continue   # this intersection is not on the shared border segment
				var u: Vector2 = (ev - qc).normalized()
				for back in [0.03, 0.06]:
					var p: Vector2 = ev + u * float(back)
					if Vector2i(floori(p.x), floori(p.y)) != cell:
						continue
					out.append({"node": node, "p": p, "before": cell, "after": q})
	return out


func _t_buff_inspector_band_edge() -> void:
	var syn: Dictionary = _zone_table(4)
	var after_in: int = 0
	var after_out: int = 0
	var total: int = 0
	var bad: Array = []
	var work_wrong: Array = []
	var stuck: int = 0
	for L in [1, 2, 3]:
		var R: int = _zb_radius(syn, L)
		var mult: float = _zb_buff(syn, L, "gather_mult")
		var s: Variant = _band_world(L, syn, 0)
		var cap: Vector2i = _cap_tile(s)
		var plain: float = float(GameData.NODEINFO.tree.time) / (1.0 + float(s.player.skills.gather) * 0.04)
		var starts: Array = _band_edge_starts(s, cap, R)
		for dt in [0.0167, 0.05, 0.1]:
			for cf in starts:
				var cfg: Dictionary = cf
				var node: Vector2i = cfg.node
				var p: Vector2 = cfg.p
				if node.x < 1 or node.y < 1 or node.x > ZB_N - 2 or node.y > ZB_N - 2:
					continue
				var r: Dictionary = _band_run(s, node, p, float(dt))
				total += 1
				if float(r.dur) < 0.0:
					stuck += 1
					continue
				if _zb_in(cap, cfg.after, R):
					after_in += 1
				else:
					after_out += 1
				var stand_in: bool = _zb_in(cap, r.cell, R)
				if not _near(float(r.dur), plain / mult if stand_in else plain):
					work_wrong.append("L%d dt%s node %s: dur %.4f stand %s" % [L, str(dt), str(node - cap), float(r.dur), str((r.cell as Vector2i) - cap)])
				if String(r.shown) != "≈%.1f с за одиницю" % float(r.dur):
					bad.append("L%d dt%s node %s start (%.4f,%.4f) crosses the border into %s: tooltip «%s», sim works %.4f s (stands %s)" % [L, str(dt), str(node - cap), p.x - float(cap.x), p.y - float(cap.y), str((cfg.after as Vector2i) - cap), String(r.shown), float(r.dur), str((r.cell as Vector2i) - cap)])
		_dispose(s)
	ok(total >= 60 and after_in >= 20 and after_out >= 20, "REQ-0010-15 x D9 setup: %d edge-border walks built (%d end just inside the zone, %d just outside, tooltip checked at 3 frame steps on 3 levels), %d stuck" % [total, after_in, after_out, stuck])
	ok(bad.is_empty(), "REQ-0010-15 x D9: a straight walk that meets the reach circle exactly on a zone-edge cell border — the tooltip names the cell the hero then works in (%d lies, first %s)" % [bad.size(), str(bad.slice(0, 2))])
	ok(work_wrong.is_empty(), "REQ-0010-15: ... and the work time there is the buffed one iff that cell is inside the zone — wrong %s" % str(work_wrong.slice(0, 2)))


# =============================================================================================
# REQ-0010-80 — the metric is one string in the DATA. An unknown one (a typo, another geometry that is not implemented) means «no zone»: no buff
# anywhere, no stock reach — NOT «the whole map is the zone». A missing key is Chebyshev. The data is read on every call (flip it -> the zone follows)
# =============================================================================================
func _t_zone_metric_safe_failure() -> void:
	var node: Dictionary = {"kind": "tree"}
	var ref: Variant = _sim_with(_pad_map(ZB_N, ZB_CAP), false, false, false)   # the OFF world: the plain numbers
	_quiet(ref)
	var plain_gather: float = float(ref.gather_time(node))
	var plain_melee: float = float(ref.melee_damage())
	var base_research: float = float(GameData.BUILDINGS.research_bench.research_rate)
	var attacked: int = 0
	var zone_bad: Array = []
	var buff_bad: Array = []
	var craft_bad: Array = []
	var research_bad: Array = []
	var hero_bad: Array = []
	var hint_bad: Array = []
	var reach_bad: Array = []
	var pack_bad: Array = []
	for bad_metric in ["manhattan", "euclidean", "", "Chebyshev", "chebychev", " chebyshev", "chebyshev ", "l_inf"]:
		var table: Dictionary = _zone_table(4)
		table["metric"] = bad_metric
		for L in [0, 1, 2, 3]:
			var s: Variant = _zone_sim(L, table)
			var cap: Vector2i = _cap_tile(s)
			var R: int = _zb_radius(table, L)
			var label: String = "«%s» L%d" % [String(bad_metric), L]
			attacked += 1
			# 1. no cell is in the zone — not the capsule's own, not one next to it, not the edge — and no key is buffed anywhere
			for dy in range(-(R + 3), R + 4):
				for dx in range(-(R + 3), R + 4):
					var c: Vector2i = cap + Vector2i(dx, dy)
					if MainCapsule.in_zone(s, c):
						zone_bad.append("%s in_zone %s" % [label, str(Vector2i(dx, dy))])
					for key in ZB_KEYS:
						if MainCapsule.buff_at(s, String(key), c) != 1.0:
							buff_bad.append("%s %s@%s" % [label, String(key), str(Vector2i(dx, dy))])
			# 2. the processes and the hero hooks run at the plain rate, nothing breaks
			s._place_building("workbench", cap.x + 1, cap.y + 1, -1)
			s._place_building("workbench", cap.x + R, cap.y, -1)
			s._place_building("workbench", cap.x + R + 4, cap.y, -1)
			s._place_building("research_bench", cap.x, cap.y - 2, -1)
			s._place_building("research_bench", cap.x - R, cap.y, -1)
			_hero_px(s, float(cap.x) + 1.5, float(cap.y) + 0.5)
			if not _near(_craft_rate_of(s), 3.0):
				craft_bad.append("%s craft rate %s (3 benches)" % [label, str(_craft_rate_of(s))])
			if _research_rate_of(s) != 2.0 * base_research:
				research_bad.append("%s research rate %s (want %s)" % [label, str(_research_rate_of(s)), str(2.0 * base_research)])
			if float(s.gather_time(node)) != plain_gather or float(s.melee_damage()) != plain_melee:
				hero_bad.append("%s gather %s melee %s (plain %s / %s)" % [label, str(s.gather_time(node)), str(s.melee_damage()), str(plain_gather), str(plain_melee)])
			var tree: Vector2i = cap + Vector2i(R + 1, 0)
			s.map.nodes[tree.y * int(s.n) + tree.x] = {"kind": "tree", "amount": 9}
			var hint: float = float(MainCapsule.gather_preview(s, tree.y * int(s.n) + tree.x))
			if hint != plain_gather:
				hint_bad.append("%s hint %s (plain %s)" % [label, str(hint), str(plain_gather)])
			# 3. no zone -> no stock reach: the stock cannot pay even beside the capsule; the backpack still can; nothing is debited on the refusal
			if L == 0:
				var price: Dictionary = _cost_of(table.levels as Array, 1)
				_wipe(s)
				_fund_cost(s, price, 0.0)
				_put_hero(s, cap + Vector2i(1, 0))
				var sig: String = _funds_sig(s)
				var r: Dictionary = s.upgrade_capsule()
				if bool(r.get("ok", true)) or r.get("reason", &"") != &"cost" or not bool(r.get("far", false)) or _funds_sig(s) != sig:
					reach_bad.append("%s stock beside the capsule: %s" % [label, str(r)])
				_fund_cost(s, price, 1.0)
				var rp: Dictionary = s.upgrade_capsule()
				if not bool(rp.get("ok", false)) or s.capsule_level() != 1:
					pack_bad.append("%s backpack: %s" % [label, str(rp)])
			_dispose(s)
	ok(attacked == 32, "REQ-0010-80 setup: 8 unknown metrics (manhattan, euclidean, empty, 2 case/typo variants, 2 whitespace variants, l_inf) x 4 levels were attacked (%d)" % attacked)
	ok(zone_bad.is_empty(), "REQ-0010-80: an unknown metric means «no zone» — in_zone is false for every cell of the window around the capsule, its own cell and the edge included (%d cells inside by mistake, first %s)" % [zone_bad.size(), str(zone_bad.slice(0, 3))])
	ok(buff_bad.is_empty(), "REQ-0010-80: ... and buff_at is exactly the neutral 1.0 for every key and cell (%d buffed by mistake, first %s)" % [buff_bad.size(), str(buff_bad.slice(0, 3))])
	ok(craft_bad.is_empty(), "REQ-0010-80: ... the craft rate is the number of workbenches (3), no multiplier — %s" % str(craft_bad.slice(0, 3)))
	ok(research_bad.is_empty(), "REQ-0010-80: ... the research rate is the plain sum of the tables — %s" % str(research_bad.slice(0, 3)))
	ok(hero_bad.is_empty() and hint_bad.is_empty(), "REQ-0010-80/D9: ... the hero beside the capsule gathers and hits at the OFF world's plain numbers and the node hint says the plain time — %s %s" % [str(hero_bad.slice(0, 2)), str(hint_bad.slice(0, 2))])
	ok(reach_bad.is_empty(), "REQ-0010-80: with no zone the capsule's stock is out of reach even beside it (refused as «far», nothing debited) — %s" % str(reach_bad.slice(0, 2)))
	ok(pack_bad.is_empty(), "REQ-0010-80: ... while the backpack still pays for the upgrade — %s" % str(pack_bad.slice(0, 2)))
	_dispose(ref)


func _t_zone_metric_missing_and_live() -> void:
	var table: Dictionary = _zone_table(4)
	table.erase("metric")
	ok(not table.has("metric"), "REQ-0010-80 setup: the table under test has no `metric` key")
	var s: Variant = _zone_sim(0, table)
	var cap: Vector2i = _cap_tile(s)
	ok(MainCapsule.zone_metric(s) == "chebyshev", "REQ-0010-80: a table without a `metric` key is Chebyshev — the one geometry the spec names (got «%s»)" % MainCapsule.zone_metric(s))
	var wrong: Array = []
	var hits: int = 0
	for L in [0, 1, 2, 3]:
		s.main_capsule["level"] = L
		var R: int = _zb_radius(table, L)
		for dy in range(-(R + 3), R + 4):
			for dx in range(-(R + 3), R + 4):
				var c: Vector2i = cap + Vector2i(dx, dy)
				var want: bool = _zb_in(cap, c, R)
				if want:
					hits += 1
				if MainCapsule.in_zone(s, c) != want:
					wrong.append("L%d %s" % [L, str(Vector2i(dx, dy))])
				if L >= 1:
					var bw: float = _zb_buff(table, L, "gather_mult") if want else 1.0
					if MainCapsule.buff_at(s, "gather_mult", c) != bw:
						wrong.append("L%d buff %s" % [L, str(Vector2i(dx, dy))])
	ok(wrong.is_empty() and hits > 0, "REQ-0010-80: with no `metric` key the zone is exactly the Chebyshev square of the current level and the buff follows it — %d cells inside, %d wrong, first %s" % [hits, wrong.size(), str(wrong.slice(0, 3))])
	# the data is read on EVERY call: flip the metric in the live world and the zone follows (no cached zone, no cached verdict)
	var live: Dictionary = _zone_table(4)
	s.capsule_table = live
	s.main_capsule["level"] = 2
	var edge: Vector2i = cap + Vector2i(5, 5)   # the corner: in for Chebyshev, out for Manhattan/Euclid
	var states: Array = []
	for m in ["chebyshev", "manhattan", "chebyshev", "", "chebyshev"]:
		var t2: Dictionary = _zone_table(4)
		t2["metric"] = m
		s.capsule_table = t2
		states.append(MainCapsule.in_zone(s, edge) and MainCapsule.buff_at(s, "craft_mult", edge) == 2.5)
	ok(states == [true, false, true, false, true], "REQ-0010-80: the metric is read from the data on every call — chebyshev / manhattan / chebyshev / empty / chebyshev gives %s" % str(states))
	_dispose(s)


# =============================================================================================
# CHARACTERIZATION PIN (REQ-0010-01 / D4: flag OFF == the code before the spec; NOT a spec-0010 requirement). W2b moved the auto-haul block out of
# sim.gd into sim/haul.gd «without a change of behaviour»; the S0 `gather_haul` scenario does not straddle the resume radius, so a changed
# HAUL_RESUME_RADIUS (7 -> 6) passed every suite. The expectations are the BASELINE's (HEAD:godot/scripts/sim.gd `HAUL_RESUME_RADIUS := 7`,
# «Euclidean tiles»; nearest same-kind node wins, a tie goes to the lower cell index): an exhausted node hands the hero to a same-kind neighbour
# within 7 tiles (dx^2 + dy^2 <= 49), never to a farther one, never to another kind. OFF world, the real _do_gather -> continue_gather path.
# =============================================================================================
func _haul_resume_target(extra: Array) -> Vector2i:
	var s: Variant = _sim_with(_pad_map(ZB_N, ZB_CAP), false, false, false)
	_quiet(s)
	var n: int = int(s.n)
	var a: Vector2i = Vector2i(10, 10)
	s.map.nodes.clear()
	s.map.nodes[a.y * n + a.x] = {"kind": "tree", "amount": 1}
	for e in extra:
		var o: Dictionary = e
		var at: Vector2i = a + (o.at as Vector2i)
		s.map.nodes[at.y * n + at.x] = {"kind": String(o.get("kind", "tree")), "amount": 40}
	_put_hero(s, a + Vector2i(-1, 0))   # next to the tree: inside the reach, he works at once
	s.order_gather(a.x, a.y)
	for t in 400:
		s.update(0.05)
		if not s.map.nodes.has(a.y * n + a.x):
			break
	var act: Variant = s.player.get("action")
	var got: Vector2i = Vector2i(-1, -1)
	if act is Dictionary and String((act as Dictionary).get("type", "")) == "gather":
		got = Vector2i(int((act as Dictionary).nx), int((act as Dictionary).ny))
	var gone: bool = not s.map.nodes.has(a.y * n + a.x)
	_dispose(s)
	return got if gone else Vector2i(-2, -2)


func _t_off_haul_resume_radius() -> void:
	var a: Vector2i = Vector2i(10, 10)
	var cases: Array = [
		["(7,0): d^2 = 49, the edge of the radius, resumes", [{"at": Vector2i(7, 0)}], a + Vector2i(7, 0)],
		["(-7,0) resumes", [{"at": Vector2i(-7, 0)}], a + Vector2i(-7, 0)],
		["(0,-7) resumes", [{"at": Vector2i(0, -7)}], a + Vector2i(0, -7)],
		["(6,3): d^2 = 45, inside the circle though outside the 6-square, resumes", [{"at": Vector2i(6, 3)}], a + Vector2i(6, 3)],
		["(8,0): d^2 = 64, out of range, no resume", [{"at": Vector2i(8, 0)}], Vector2i(-1, -1)],
		["(7,1): d^2 = 50, just out of the circle, no resume", [{"at": Vector2i(7, 1)}], Vector2i(-1, -1)],
		["(5,5): d^2 = 50 (7.07 tiles), no resume", [{"at": Vector2i(5, 5)}], Vector2i(-1, -1)],
		["(-5,-5): d^2 = 50, no resume", [{"at": Vector2i(-5, -5)}], Vector2i(-1, -1)],
		["nearest wins: trees at 7 and 3 tiles -> the 3", [{"at": Vector2i(7, 0)}, {"at": Vector2i(3, 0)}], a + Vector2i(3, 0)],
		["a tie goes to the lower cell index: (4,0) and (0,4) -> (4,0)", [{"at": Vector2i(4, 0)}, {"at": Vector2i(0, 4)}], a + Vector2i(4, 0)],
		["a tie goes to the lower cell index: (-4,0) and (4,0) -> (-4,0)", [{"at": Vector2i(4, 0)}, {"at": Vector2i(-4, 0)}], a + Vector2i(-4, 0)],
		["another kind is ignored: a rock at 2 tiles, a tree at 6 -> the tree", [{"at": Vector2i(2, 0), "kind": "rock"}, {"at": Vector2i(6, 0)}], a + Vector2i(6, 0)],
		["only another kind in range: no resume", [{"at": Vector2i(2, 0), "kind": "rock"}], Vector2i(-1, -1)],
	]
	var wrong: Array = []
	for cs in cases:
		var got: Vector2i = _haul_resume_target(cs[1] as Array)
		if got != (cs[2] as Vector2i):
			wrong.append("%s: got %s, want %s" % [String(cs[0]), str(got), str(cs[2])])
	ok(wrong.is_empty(), "REQ-0010-01/D4 (characterization): an exhausted tree hands the OFF-world hero to the nearest same-kind node within 7 tiles (Euclidean, edge included), a tie to the lower cell index, nothing farther, nothing of another kind — %d of %d cases wrong, first %s" % [wrong.size(), cases.size(), str(wrong.slice(0, 2))])
