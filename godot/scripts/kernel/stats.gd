# RealWorld — kernel/stats.gd : the stat pipeline (StatDef / StatWorker / StatPart).
#
# RimWorld analogue: StatDef / StatWorker / StatPart. A stat's final value is a base number folded
# through an ordered list of StatParts, each contributing a multiplier or offset from some source:
# gear quality, a health capacity, a research bonus, ambient temperature. Adding a new modifier
# source = writing one StatPart and appending it — callers just ask StatWorker.value(ctx). This
# replaces ad-hoc formulas (gather_mult, dmg_bonus) with one extensible, explainable pipeline.
extends RefCounted

# One contribution to a stat. Pure: transform the running value; explain() drives tooltips.
class StatPart extends RefCounted:
	func transform(val: float, _ctx: Dictionary) -> float:
		return val

	func explain(_ctx: Dictionary) -> String:
		return ""

# Item quality scales the stat (reads ctx.quality_mult, produced by Things.CompQuality.mult()).
class StatPart_Quality extends StatPart:
	func transform(val: float, ctx: Dictionary) -> float:
		return val * float(ctx.get("quality_mult", 1.0))

	func explain(ctx: Dictionary) -> String:
		return "×якість %.2f" % float(ctx.get("quality_mult", 1.0))

# A health capacity (Moving, Manipulation...) scales the stat: a hurt leg slows MoveSpeed, a hurt
# arm slows WorkSpeed. Reads ctx.capacities (produced by the HealthTracker).
class StatPart_Capacity extends StatPart:
	var cap_key: StringName

	func _init(p_cap: StringName) -> void:
		cap_key = p_cap

	func transform(val: float, ctx: Dictionary) -> float:
		var caps: Dictionary = ctx.get("capacities", {})
		return val * clampf(float(caps.get(cap_key, 1.0)), 0.0, 1.0)

	func explain(ctx: Dictionary) -> String:
		var caps: Dictionary = ctx.get("capacities", {})
		return "×%s %.2f" % [cap_key, float(caps.get(cap_key, 1.0))]

# A flat multiplier from a named ctx factor (research unlocks, temperature comfort, weather...).
class StatPart_Factor extends StatPart:
	var ctx_key: StringName
	var dflt: float

	func _init(p_key: StringName, p_default: float = 1.0) -> void:
		ctx_key = p_key
		dflt = p_default

	func transform(val: float, ctx: Dictionary) -> float:
		return val * float(ctx.get(ctx_key, dflt))

	func explain(ctx: Dictionary) -> String:
		return "×%s %.2f" % [ctx_key, float(ctx.get(ctx_key, dflt))]

# Computes one stat from a base + its parts. Cheap to build per-query; deterministic.
class StatWorker extends RefCounted:
	var stat_id: StringName
	var base: float
	var parts: Array = []

	func _init(p_id: StringName, p_base: float, p_parts: Array = []) -> void:
		stat_id = p_id
		base = p_base
		parts = p_parts

	func value(ctx: Dictionary) -> float:
		var v: float = base
		for p in parts:
			v = p.transform(v, ctx)
		return v

	# Human-readable breakdown for a tooltip: "base 12.0 · ×якість 1.50 · ×moving 0.80".
	func explain(ctx: Dictionary) -> String:
		var out := ["base %.1f" % base]
		for p in parts:
			var e: String = p.explain(ctx)
			if e != "":
				out.append(e)
		return " · ".join(out)
