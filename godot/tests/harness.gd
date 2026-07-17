# RealWorld — tests/harness.gd : shared scaffolding for the headless test suites.
#
# Every suite used to hand-copy the same passed/failed counters, the same ok() reporter and the
# same RESULT+quit tail. The scaffolding lives here once; a suite just does
#   extends "res://tests/harness.gd"
# runs its _t_*() functions from _init(), and calls finish() as the last line.
extends SceneTree

var passed := 0
var failed := 0

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [pass] ", name)
	else:
		failed += 1
		printerr("  [FAIL] ", name)
		print("  [FAIL] ", name)

# Print the tally and exit with a CI-friendly code (non-zero on any failure).
func finish() -> void:
	print("\n== RESULT: %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)
