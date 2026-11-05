# RealWorld — clock.gd : the ONE wall-clock source of the game (spec 0012 REQ-11, D1).
#
# The sim never reads a clock (REQ-10: no Time.* / OS.get_*time* / Engine.get_ticks_* in the sim corpus —
# tools/lint.mjs + run_tests `_t_no_wallclock_in_sim`). Absolute time enters the game in exactly one
# way: Session asks a Clock for `now_ms()` and hands the number to the sim as an ARGUMENT
# (Sim.set_clock(now_ms)). This file is the only product script outside the view layer that may call
# Time.get_unix_time_from_system (and the only one excluded from the lint corpus for that reason).
#
# `now_ms` = UTC milliseconds since the Unix epoch, int64 (~1.8e12 today). It is a whole number so it
# survives JSON: a save carries it as a decimal STRING (to_wire/from_wire — the same discipline as the
# RNG cursors in persistence.gd), never as a float.
#
# Providers (swap one for another without touching the sim — REQ-11):
#   SystemClock — the device clock (OD-53); the only provider that reads the OS.
#   FixedClock  — a constant (tests): `now` never moves.
#   FakeClock   — a settable clock (dev / tests): advance() / set_ms(), including backwards.
# Monotonic is NOT a provider but the guard every economy consumer reads `now` through (REQ-68): a clock
# that jumps back never lowers `last_seen`, so rewinding the device clock cannot shorten a cooldown.
#
# No static state, no class_name, no autoload (AGENTS.md): consumers `const Clock = preload(...)`
# and hold their own provider instance, so ON->OFF->ON in one process shares nothing (REQ-63).
extends RefCounted

const MS_PER_DAY := 86400000

# The largest/smallest int64 as exact floats: 2^63 is representable, 2^63-1 is not.
const _INT64_FLOAT_LIMIT := 9223372036854775808.0
const _INT64_MAX_DIGITS := "9223372036854775807"
const _INT64_MIN_DIGITS := "9223372036854775808"


# Interface. Never instantiated directly; the base answers 0 so a stray base is inert, not random.
class ClockBase extends RefCounted:
	func now_ms() -> int:
		return 0


# The device clock. The ONLY place in the product that asks the OS for the time of day.
class SystemClock extends ClockBase:
	func now_ms() -> int:
		return int(floor(Time.get_unix_time_from_system() * 1000.0))


# A frozen instant: tests that must not depend on when they run.
class FixedClock extends ClockBase:
	var ms: int = 0

	func _init(p_ms: int = 0) -> void:
		ms = p_ms

	func now_ms() -> int:
		return ms


# A settable instant: dev time-travel and the REQ-68 rewind scenarios. advance() takes a negative step too.
class FakeClock extends ClockBase:
	var ms: int = 0

	func _init(p_ms: int = 0) -> void:
		ms = p_ms

	func advance(d_ms: int) -> void:
		ms += d_ms

	func set_ms(v: int) -> void:
		ms = v

	func now_ms() -> int:
		return ms


# REQ-68: never goes backwards. observe(now) returns max(now, last_seen) and remembers it, so a consumer
# that credits/cools down by `observe(clock.now_ms())` is immune to the device clock being wound back.
# `last_seen` is public: Session restores it from the save (`last_seen_now`) and writes it back.
class Monotonic extends RefCounted:
	var last_seen: int = 0

	func observe(now: int) -> int:
		if now > last_seen:
			last_seen = now
		return last_seen


# int64 -> JSON-safe decimal string. A float would lose bits above 2^53; a string never does.
static func to_wire(ms: int) -> String:
	return str(ms)


# Wire value -> int64. Accepts what a save can hold: the decimal string to_wire() wrote, a real int (an
# in-process payload that never touched JSON), or a float (JSON.parse_string turns EVERY number into one;
# fractions floor). Anything else — NaN, inf, overflow, text, null, bool, containers — yields `fallback`.
static func from_wire(v: Variant, fallback: int = 0) -> int:
	if v is int:
		return v
	if v is float:
		return _from_float(v, fallback)
	if v is String or v is StringName:
		var s := String(v)
		if s.is_valid_int():
			return _from_int_string(s, fallback)
		if s.is_valid_float():
			return _from_float(s.to_float(), fallback)
	return fallback


# String.to_int() wraps/clamps (and logs an error) beyond int64, so range-check the digits first.
static func _from_int_string(s: String, fallback: int) -> int:
	var neg := s.begins_with("-")
	var digits := s.trim_prefix("-").trim_prefix("+")
	while digits.length() > 1 and digits.begins_with("0"):
		digits = digits.substr(1)
	if digits.length() > _INT64_MAX_DIGITS.length():
		return fallback
	if digits.length() == _INT64_MAX_DIGITS.length():
		var limit := _INT64_MIN_DIGITS if neg else _INT64_MAX_DIGITS
		if digits > limit:   # equal-length digit strings compare numerically
			return fallback
	return s.to_int()


static func _from_float(f: float, fallback: int) -> int:
	if is_nan(f) or is_inf(f) or f >= _INT64_FLOAT_LIMIT or f < -_INT64_FLOAT_LIMIT:
		return fallback
	return int(floor(f))
