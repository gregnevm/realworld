# RealWorld — tests/capture_baseline.gd : DEV-ONLY (not in CI, not in test.cmd) fixture capture.
#
# Prints (or writes) godot/tests/fixtures/off_baseline.json from the CURRENT code. Run it ONLY on
# the unmodified baseline commit — that is the whole point of the fixture ("flag OFF == the code
# before specs 0010/0012"); the first-wave PR records baseline_commit in the header. Re-capturing on
# top of product changes would make the pin a tautology — the suites refuse nothing here, so the
# discipline is yours: `git stash` / checkout the baseline first.
#
# Usage (from the repo root, Linux Godot 4.7-stable — the CI platform):
#   godot --headless --path godot -s res://tests/capture_baseline.gd -- commit=$(git rev-parse HEAD) write
#   godot --headless --path godot -s res://tests/capture_baseline.gd -- commit=$(git rev-parse HEAD)   # print only
# `write` stores res://tests/fixtures/off_baseline.json; `out=<abs path>` writes elsewhere (used to
# diff two independent capture processes: the capture itself must be deterministic).
extends SceneTree

const Scenarios = preload("res://tests/off_scenarios.gd")
const FIXTURE_PATH := "res://tests/fixtures/off_baseline.json"


func _init() -> void:
	var commit: String = ""
	var out_path: String = ""
	var write: bool = false
	for a in OS.get_cmdline_user_args():
		var arg: String = String(a)
		if arg.begins_with("commit="):
			commit = arg.substr(7)
		elif arg.begins_with("out="):
			out_path = arg.substr(4)
		elif arg == "write":
			write = true
	if commit == "":
		commit = _git_head()
	var fixture: Dictionary = build_fixture(commit)
	var text: String = JSON.stringify(fixture, "\t", true, true)
	if out_path != "":
		_store(out_path, text)
	elif write:
		_store(FIXTURE_PATH, text)
	else:
		print(text)
	print("capture: baseline_commit=%s platform=%s godot=%s scenarios=%d bytes=%d" % [commit, OS.get_name(),
		Engine.get_version_info().string, Scenarios.SCENARIOS.size(), text.length()])
	print("capture: WORLD_HASH_FINAL (twin ambient) = %s" % String(fixture.world_hash_final))
	quit(0)


static func build_fixture(commit: String) -> Dictionary:
	var scenarios: Dictionary = Scenarios.run_all()
	var portable: Dictionary = {}
	var numeric: Dictionary = {}
	for name in scenarios:
		portable[name] = scenarios[name].portable
		numeric[name] = scenarios[name].numeric
	var legacy_saves: Dictionary = {}
	for kind in Scenarios.SAVE_KINDS:
		var saved: Dictionary = Scenarios.save_session_text(String(kind))
		var text: String = String(saved.text)
		var gz: PackedByteArray = text.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
		# the exact save string a BASELINE build wrote — later builds must still load it as an OFF world
		legacy_saves[kind] = {
			"gz_b64": Marshalls.raw_to_base64(gz), "raw_length": text.length(), "sha256": text.sha256_text(),
			"restore": Scenarios.restore_legacy(text),
		}
	return {
		"schema": 1,
		"baseline_commit": commit,
		"platform": OS.get_name(),
		"godot_version": Engine.get_version_info().string,
		"captured_by": "godot/tests/capture_baseline.gd",
		"world_hash_final": numeric["twin_ambient_300"]["world_hash"],
		"save_version": Scenarios.SessionScript.SAVE_VERSION,
		"portable": portable,
		"numeric": numeric,
		"legacy_saves": legacy_saves,
	}


static func _store(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("capture: cannot write ", path)
		return
	f.store_string(text + "\n")
	f.close()
	print("capture: wrote ", path)


static func _git_head() -> String:
	var out: Array = []
	var code: int = OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], out)
	if code != 0 or out.is_empty():
		return "unknown"
	return String(out[0]).strip_edges()
