# RealWorld — tests/off_checker.gd : what a suite calls to compare the OFF scenarios against the fixture
# (see off_fixture.gd for the platform policy and the float tolerance). `suite` is the harness (anything with
# ok(cond, name)); scenario results are cached per process so two checks of one scenario run it once.
extends RefCounted

const Fx = preload("res://tests/off_fixture.gd")
const Scenarios = preload("res://tests/off_scenarios.gd")

var suite: Object
var fixture: Dictionary = {}
var env: Dictionary = {}
var skipped: int = 0
var _cache: Dictionary = {}

func _init(owner: Object) -> void:
	suite = owner
	fixture = Fx.load_fixture()
	env = Fx.env_status(fixture)

func has_fixture() -> bool:
	return not fixture.is_empty() and fixture.has("portable") and fixture.has("numeric")

func scenario(name: String) -> Dictionary:
	if not _cache.has(name):
		_cache[name] = Scenarios.run(name)
	return _cache[name]

# compare the PORTABLE tier of one scenario on every platform
func portable(name: String, label: String) -> void:
	if not has_fixture() or not (fixture.portable as Dictionary).has(name):
		suite.ok(false, "%s: baseline fixture has no portable pins for «%s» (capture_baseline.gd was not run)" % [label, name])
		return
	var diffs: Array = []
	Fx.diff(scenario(name).portable, fixture.portable[name], "", diffs)
	_report(diffs, "%s [%s] portable pins == baseline" % [label, name])

# compare the NUMERIC tier (world_hash etc.): hard on the capture platform, FAIL in CI elsewhere, loud skip otherwise
func numeric(name: String, label: String) -> void:
	var title: String = "%s [%s] numeric pins (world_hash …) == baseline" % [label, name]
	if not has_fixture() or not (fixture.numeric as Dictionary).has(name):
		suite.ok(false, "%s: baseline fixture has no numeric pins for «%s»" % [label, name])
		return
	match String(env.mode):
		"hard":
			var diffs: Array = []
			Fx.diff(scenario(name).numeric, fixture.numeric[name], "", diffs)
			_report(diffs, title)
		"fail":
			suite.ok(false, "%s — fixture captured on a different platform than this CI runner (%s): the gate would be silently skipped; re-capture on the CI platform" % [title, String(env.note)])
		_:
			skipped += 1
			print("  [SKIP] %s — %s" % [title, String(env.note)])

func _report(diffs: Array, title: String) -> void:
	if not diffs.is_empty():
		print("    baseline mismatch — %s:\n      %s" % [title, Fx.summarize(diffs)])
	suite.ok(diffs.is_empty(), title)

# the closing banner: skipped numeric checks must be visible in the log, never a quiet pass
func skip_banner() -> void:
	if skipped > 0:
		var msg: String = "WARN: %d numeric baseline pin(s) SKIPPED — %s. world_hash pins are NOT verified in this run; run the suite on the capture platform." % [skipped, String(env.note)]
		print(msg)
		printerr(msg)
