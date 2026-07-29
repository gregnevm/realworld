# RealWorld — tests/run_net_spike.gd : orchestrator of the spec 0006 transport spike.
#
# Spawns ONE authoritative --headless server and TWO client processes (the same Godot binary that
# runs this suite), wires them over a real localhost WebSocket, and asserts the §2 Plan wording
# end-to-end: same seed, three OS processes, lockstep command echo — identical world_hash on the
# server and on both clients, at every probe and at the end. This is an integration suite (it
# spawns processes), so it lives OUTSIDE the single-process suite loop in CI.
# Run: godot --headless --path godot -s res://tests/run_net_spike.gd
extends "res://tests/harness.gd"

const TOTAL_TICKS := 600
const LATE_JOIN_TICK := 200        # plan §5: the third client is admitted here (tick-gated, not wall-clock)
const SPAWN_SETTLE_MSEC := 500
const WAIT_TIMEOUT_MSEC := 90000


func _init() -> void:
	print("== RealWorld net transport spike (spec 0006 plan §2) ==")
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var udir := OS.get_user_data_dir()
	var port := 8900 + (OS.get_process_id() % 500)
	var outs := {
		"server": udir.path_join("net_spike_server.json"),
		"c1": udir.path_join("net_spike_client1.json"),
		"c2": udir.path_join("net_spike_client2.json"),
		"c3": udir.path_join("net_spike_client3.json"),
	}
	for k in outs:
		if FileAccess.file_exists(outs[k]):
			DirAccess.remove_absolute(outs[k])

	var pids: Array = []
	var srv := OS.create_process(exe, [
		"--headless", "--path", proj, "-s", "res://tests/net/net_server.gd", "--",
		"port=%d" % port, "clients=2", "ticks=%d" % TOTAL_TICKS,
		"late=%d" % LATE_JOIN_TICK, "out=%s" % outs.server,
	])
	ok(srv > 0, "server process spawned (pid %d, port %d)" % [srv, port])
	pids.append(srv)
	OS.delay_msec(SPAWN_SETTLE_MSEC)   # let the listener come up before the clients dial
	# All three dial at once; the server accepts two, leaves the third queued in the TCP backlog
	# and admits it at LATE_JOIN_TICK — so "who is the late joiner" is decided by the connect race
	# (as in the wild) while WHEN it joins stays deterministic.
	for label in ["c1", "c2", "c3"]:
		var pid := OS.create_process(exe, [
			"--headless", "--path", proj, "-s", "res://tests/net/net_client.gd", "--",
			"port=%d" % port, "out=%s" % outs[label],
		])
		ok(pid > 0, "client %s process spawned (pid %d)" % [label, pid])
		pids.append(pid)

	var waited := 0
	while waited < WAIT_TIMEOUT_MSEC:
		var running := 0
		for pid in pids:
			if OS.is_process_running(int(pid)):
				running += 1
		if running == 0:
			break
		OS.delay_msec(100)
		waited += 100
	if waited >= WAIT_TIMEOUT_MSEC:
		for pid in pids:
			OS.kill(int(pid))
	ok(waited < WAIT_TIMEOUT_MSEC, "all three processes finished (%.1fs)" % (waited / 1000.0))

	var server := _read(outs.server)
	var c1 := _read(outs.c1)
	var c2 := _read(outs.c2)
	var c3 := _read(outs.c3)
	var clients := [c1, c2, c3]
	ok(bool(server.get("ok", false)) and int(server.get("clients_seen", 0)) == 2,
		"server verdict ok, 2 clients served (echoed %d commands)" % int(server.get("cmd_echoes", 0)))
	# idx 0 goes to whichever client won the connect race — assert the sum, not a fixed process
	var sent := 0
	var resends := 0
	for v in clients:
		sent += int(v.get("cmds_sent", 0))
		resends += int(v.get("resends", 0))
	ok(int(server.get("cmd_echoes", 0)) == 3 and sent == 3,
		"command round-trip: 3 verbs client->server->all (gather/build/move)")
	# plan §4 over the socket: one intent was deliberately RESENT; the inbox must refuse the copy
	# as a duplicate, so the echoed schedule stays at 3 and the world hashes never split
	var refusals: Dictionary = server.get("refusals", {})
	ok(resends == 1 and int(server.get("refused", 0)) == 1 and int(refusals.get("duplicate", 0)) == 1,
		"idempotency over the wire: the resent build was refused as duplicate (refusals: %s)" % str(refusals))
	for v in clients:
		# a resumed client only sees the probes AFTER it joined, so its expected count differs
		var resumed := bool(v.get("resumed", false))
		var want_hash: int = (TOTAL_TICKS - LATE_JOIN_TICK) / 100 if resumed else TOTAL_TICKS / 100
		var want_snap: int = (TOTAL_TICKS - LATE_JOIN_TICK) / 50 if resumed else TOTAL_TICKS / 50
		var tag := "resumed client" if resumed else "client"
		ok(bool(v.get("ok", false)) and int(v.get("mismatches", 1)) == 0 and int(v.get("hash_checks", 0)) == want_hash,
			"%s %d verdict ok: %d hash probes, %d mismatches%s" % [
				tag, int(v.get("idx", -1)), int(v.get("hash_checks", 0)), int(v.get("mismatches", -1)),
				"" if bool(v.get("ok", false)) else " — err: %s" % str(v.get("err", "?")),
			])
		# §8.3 snapshot channel: every 50-tick delta reconstructed into a snapshot that matches
		# the client's locally computed one (the resumed client starts from the keyframe it was sent)
		ok(int(v.get("snap_checks", 0)) == want_snap and int(v.get("snap_mismatches", 1)) == 0,
			"%s %d snapshot stream: %d deltas reconstructed, %d mismatches" % [
				tag, int(v.get("idx", -1)), int(v.get("snap_checks", 0)), int(v.get("snap_mismatches", -1)),
			])
		# the local/remote trail per probe — printed only on failure, where it is the fastest way
		# to see WHEN two instances parted company (this is what located the pawn-action gap)
		if int(v.get("mismatches", 1)) != 0 or not bool(v.get("ok", false)):
			print("      probes (tick:local/remote): %s" % str(v.get("probes", [])))
	# plan §5: exactly one client joined mid-run, and it did so through the resume path
	var resumed_count := 0
	for v in clients:
		if bool(v.get("resumed", false)):
			resumed_count += 1
	ok(resumed_count == 1 and bool(server.get("late_joined", false)),
		"one client joined at tick %d and was resumed from authoritative state" % LATE_JOIN_TICK)
	# plan §5: the server's own record is an append-only chain that still verifies at the end
	ok(bool(server.get("chain_ok", false)) and int(server.get("chain_len", 0)) == TOTAL_TICKS / 100,
		"authoritative chain: %d commits, verified, head %s" % [
			int(server.get("chain_len", 0)), str(server.get("chain_head", "")).left(8),
		])
	var hs := str(server.get("final", "s"))
	var all_match := hs != ""
	for v in clients:
		all_match = all_match and hs == str(v.get("final", "?"))
	ok(all_match, "final world_hash identical across server and ALL THREE clients, incl. the resumed one (%s)" % str(hs).left(8))

	for k in outs:
		DirAccess.remove_absolute(outs[k])
	finish()


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"err": "verdict file missing: %s" % path}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {"err": "unparseable verdict"}
