# RealWorld — tests/run_perf.gd : headless frame-budget probe (informational, NOT a CI gate).
#
# Gives the "performance" axis numbers instead of guesses: worldgen cost and sim.update tick
# cost at the production map size (session.MAP_N = 56) plus scaled-up maps, so regressions and
# headroom are visible before a bigger map ships. Perf thresholds flake on shared runners, so
# this suite asserts only that the probe ran — read the printed table. The pawn idles (no
# orders), which measures the ambient cost every frame pays: needs, climate, threat streams,
# raids arriving on their natural cadence. Run:
#   godot --headless --path godot -s res://tests/run_perf.gd
extends "res://tests/harness.gd"

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

const DT := 0.1                    # same tick step the suites and the game loop use
const WARMUP_TICKS := 120
const MEASURE_TICKS := 1200        # ~2 game-minutes; enough for a raid cycle to land
const TIME_CAP_USEC := 8_000_000   # per map size: stop early so huge maps keep the probe quick

const BUDGET_60FPS_USEC := 16667


func _init() -> void:
	print("== RealWorld Godot perf probe (informational) ==")
	print("  dt=%.1f  warmup=%d  measure<=%d ticks (cap %.1fs/size)" % [
		DT, WARMUP_TICKS, MEASURE_TICKS, TIME_CAP_USEC / 1_000_000.0
	])
	for n: int in [56, 112, 224]:
		_probe(n)
	ok(true, "probe completed — see the table above (60fps budget = %d us/tick)" % BUDGET_60FPS_USEC)
	finish()


# keep the pawn alive through raids/needs so the probe measures ticks, not a death screen
func _topup(sim: Variant) -> void:
	sim.player.hp = 100.0
	sim.player.hunger = 100.0
	sim.player.rest = 100.0


func _probe(n: int) -> void:
	var t0 := Time.get_ticks_usec()
	var map := WorldGen.generate_map(50.4501, 30.5234, n)
	var gen_usec := Time.get_ticks_usec() - t0

	var sim: Variant = Sim.new()
	sim.new_game(map)
	for i in WARMUP_TICKS:
		sim.update(DT)
		_topup(sim)

	var samples := PackedInt64Array()
	var started := Time.get_ticks_usec()
	while samples.size() < MEASURE_TICKS and Time.get_ticks_usec() - started < TIME_CAP_USEC:
		var s := Time.get_ticks_usec()
		sim.update(DT)
		samples.append(Time.get_ticks_usec() - s)
		_topup(sim)

	samples.sort()
	var total := 0
	for v in samples:
		total += v
	var count := samples.size()
	var avg := float(total) / maxi(count, 1)
	var p50 := samples[count / 2]
	var p95 := samples[mini(int(count * 0.95), count - 1)]
	var worst := samples[count - 1]
	var pct := 100.0 * avg / BUDGET_60FPS_USEC
	print("  n=%3d (%5d tiles)  gen=%7.2f ms | tick x%d: avg=%6.1f us  p50=%d  p95=%d  max=%d  (%.1f%% of 60fps budget)" % [
		n, n * n, gen_usec / 1000.0, count, avg, p50, p95, worst, pct
	])
