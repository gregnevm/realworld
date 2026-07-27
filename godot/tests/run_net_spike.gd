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
	}
	for k in outs:
		if FileAccess.file_exists(outs[k]):
			DirAccess.remove_absolute(outs[k])

	var pids: Array = []
	var srv := OS.create_process(exe, [
		"--headless", "--path", proj, "-s", "res://tests/net/net_server.gd", "--",
		"port=%d" % port, "clients=2", "ticks=%d" % TOTAL_TICKS, "out=%s" % outs.server,
	])
	ok(srv > 0, "server process spawned (pid %d, port %d)" % [srv, port])
	pids.append(srv)
	OS.delay_msec(SPAWN_SETTLE_MSEC)   # let the listener come up before the clients dial
	for label in ["c1", "c2"]:
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
	ok(bool(server.get("ok", false)) and int(server.get("clients_seen", 0)) == 2,
		"server verdict ok, 2 clients served (echoed %d commands)" % int(server.get("cmd_echoes", 0)))
	# idx 0 goes to whichever client won the connect race — assert the sum, not a fixed process
	var sent := int(c1.get("cmds_sent", 0)) + int(c2.get("cmds_sent", 0))
	ok(int(server.get("cmd_echoes", 0)) == 3 and sent == 3,
		"command round-trip: 3 verbs client->server->all (gather/build/move)")
	for v in [c1, c2]:
		ok(bool(v.get("ok", false)) and int(v.get("mismatches", 1)) == 0 and int(v.get("hash_checks", 0)) == TOTAL_TICKS / 100,
			"client %d verdict ok: %d hash probes, 0 mismatches%s" % [
				int(v.get("idx", -1)), int(v.get("hash_checks", 0)),
				"" if bool(v.get("ok", false)) else " — err: %s" % str(v.get("err", "?")),
			])
	var hs := str(server.get("final", "s"))
	ok(hs != "" and hs == str(c1.get("final", "1")) and hs == str(c2.get("final", "2")),
		"final world_hash identical across server and both clients (%s)" % str(hs).left(8))

	for k in outs:
		DirAccess.remove_absolute(outs[k])
	finish()


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"err": "verdict file missing: %s" % path}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {"err": "unparseable verdict"}
