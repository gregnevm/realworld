# RealWorld — ui/format.gd : PURE Ukrainian + number formatters for the view layer (spec 0005).
#
# Node-free. The single home for view-authored user-facing strings (R10: no new Ukrainian in sim.gd).
# Mirrors the sim's own formatting (clock_str/phase_name) but returns ENUMS the view maps to labels
# at one site (R11), so the snapshot never carries a pre-baked "☀ день" string.
extends RefCounted

# --- clock ---
static func hhmm(frac: float) -> String:
	var mins: int = int(frac * 24.0 * 60.0)
	return "%02d:%02d" % [mins / 60, mins % 60]

# Day phase as an enum (R11). Boundaries mirror sim.phase_name() exactly so the two never disagree.
static func phase_enum(frac: float) -> StringName:
	if frac < 0.22 or frac > 0.80:
		return &"night"
	if frac < 0.30:
		return &"dawn"
	if frac > 0.72:
		return &"dusk"
	return &"day"

static func phase_label(phase: StringName) -> String:
	match phase:
		&"night": return "🌙 ніч"
		&"dawn":  return "🌅 світанок"
		&"dusk":  return "🌇 сутінки"
		_:        return "☀ день"

static func phase_icon(phase: StringName) -> String:
	match phase:
		&"night": return "🌙"
		&"dawn":  return "🌅"
		&"dusk":  return "🌇"
		_:        return "☀"

# --- needs / urgency (thresholds mirror main.gd _bbar: >50 good, >25 warn, else crit) ---
static func urgency_enum(pct: float) -> StringName:
	if pct > 50.0:
		return &"good"
	if pct > 25.0:
		return &"warn"
	return &"crit"

static func need_label(id: StringName) -> String:
	match id:
		&"hp":     return "HP"
		&"hunger": return "Голод"
		&"rest":   return "Відп."
		&"water":  return "Вода"
		_:         return String(id)

static func need_icon(id: StringName) -> String:
	match id:
		&"hp":     return "❤"
		&"hunger": return "🍖"
		&"rest":   return "😴"
		&"water":  return "💧"
		_:         return "•"

# --- region / seed (faithful %.4f precision — the shareable world address; spec pillar) ---
static func region_line(place_name: String, lat: float, lon: float) -> String:
	return "%s (%.4f, %.4f)" % [place_name, lat, lon]

static func seed_hex(seed_val: int) -> String:
	return "%08x" % seed_val

static func coords(lat: float, lon: float) -> String:
	return "%.4f,%.4f" % [lat, lon]

# --- stats: placeholder explain (R5). Same {value, explain} shape as the future StatWorker.explain(ctx),
# so swapping the source in spec 0003 §8 needs no widget change. ---
static func melee_explain_placeholder(dmg: float) -> String:
	return "база+спорядження = %.0f урон (розклад з'явиться зі StatWorker)" % dmg

static func gather_explain_placeholder(t: float) -> String:
	return "час видобутку %.2f с (× навик × інструмент — зі StatWorker)" % t

# --- feed category (delegates the color to Tokens.category; here only the label if needed) ---
static func short_hash(h: String) -> String:
	return h.substr(0, 8) if h.length() >= 8 else "—"
