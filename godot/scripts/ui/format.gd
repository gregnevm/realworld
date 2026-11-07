# RealWorld — ui/format.gd : PURE Ukrainian + number formatters for the view layer (spec 0005).
#
# Node-free. The single home for view-authored user-facing strings (R10: no new Ukrainian in sim.gd).
# Mirrors the sim's own formatting (clock_str/phase_name) but returns ENUMS the view maps to labels
# at one site (R11), so the snapshot never carries a pre-baked "☀ день" string.
extends RefCounted

const CatalogDefs = preload("res://scripts/catalog_defs.gd")

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
		&"blood":  return "Кров"
		_:         return String(id)

static func need_icon(id: StringName) -> String:
	match id:
		&"hp":     return "❤"
		&"hunger": return "🍖"
		&"rest":   return "😴"
		&"water":  return "💧"
		&"blood":  return "🩸"
		_:         return "•"

# --- felt temperature (comfort °C the body experiences) as an enum + icon (R11) ---
static func comfort_enum(felt_c: float, comfort_min: float, comfort_max: float) -> StringName:
	if felt_c < comfort_min:
		return &"cold"
	if felt_c > comfort_max:
		return &"hot"
	return &"ok"

static func comfort_icon(state: StringName) -> String:
	match state:
		&"cold": return "❄"
		&"hot":  return "🥵"
		_:       return "✔"

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

# --- weather / season / temperature (enum -> icon+label at ONE site, R11) ---
static func weather_label(w: StringName) -> String:
	match w:
		&"rain": return "🌧 дощ"
		&"snow": return "🌨 сніг"
		&"fog": return "🌫 туман"
		&"cold_snap": return "🥶 мороз"
		_: return "🌤 ясно"

static func season_icon(season: String) -> String:
	match season:
		"зима": return "❄"
		"весна": return "🌱"
		"літо": return "☀"
		"осінь": return "🍂"
		_: return "◌"

# Rounded °C with a real minus sign (a hyphen reads as a dash in the tabular mono font).
static func temp(t: float) -> String:
	var r: int = int(round(t))
	return ("−%d°C" % -r) if r < 0 else ("%d°C" % r)

# Speed chip text (×N or pause) — the same words the top bar and the help sheet use.
static func speed_label(mult: float) -> String:
	return "⏸ пауза" if mult <= 0.0 else "×%d" % int(mult)

# --- inspect vocabulary (design-system §5 «inspect = hover») ---
static func node_title(kind: String) -> String:
	match kind:
		"tree": return "🌲 Дерево"
		"rock": return "🪨 Скеля"
		"bush": return "🫐 Кущ"
		"scrap": return "⚙ Руїни Старого світу"
		_: return kind

static func node_verb(kind: String) -> String:
	match kind:
		"tree": return "рубати"
		"rock": return "добувати камінь"
		"bush": return "збирати ягоди"
		"scrap": return "розбирати брухт"
		_: return "добувати"

static func terrain_title(name: String) -> String:
	return name.substr(0, 1).to_upper() + name.substr(1) if name != "" else "Земля"

# What a building DOES, derived from its def CAPABILITIES (the trap_dps/extra.heat pattern): a new
# def carrying the same capability reads right without editing this function.
static func building_blurb(kind: String, def: Dictionary, heat_radius: int = 6) -> String:
	var parts: Array = []
	var extra: Dictionary = def.get("extra", {})
	if kind.begins_with("door"):
		parts.append("прохід — кімната лишається замкненою")
	elif kind == "wall" or kind.ends_with("_wall"):
		parts.append("замикає кімнату — всередині тепліше")
	if def.has("capacity"):
		parts.append("+%d місця; тут пішак здає вантаж і їсть" % int(def.capacity))
	if bool(def.get("craft", false)):
		parts.append("сам робить дошки з дерева; крафт спорядження (I)")
	if bool(def.get("bed", false)):
		parts.append("сон відновлює сили й лікує рани")
	if float(def.get("research_rate", 0.0)) > 0.0:
		parts.append("дає очки досліджень")
	if float(extra.get("heat", 0.0)) > 0.0:
		parts.append("гріє +%d°C на %d клітин" % [int(extra.heat), heat_radius])
	if bool(extra.get("light", false)):
		parts.append("світить уночі")
	if float(def.get("trap_dps", 0.0)) > 0.0:
		parts.append("ранить ворогів на проході")
	if float(def.get("range", 0.0)) > 0.0:
		parts.append("стріляє по ворогах (радіус %.0f)" % float(def.range))
	if bool(def.get("grow", false)):
		parts.append("грядка: клік — обрати культуру")
	return " · ".join(parts)

# Missing materials for a cost against a stock map ({} when affordable). Value-in, value-out.
static func shortfall(cost: Dictionary, have: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in cost:
		var need: int = int(cost[k]) - int(have.get(k, 0))
		if need > 0:
			out[k] = need
	return out

# One condition row (HeroHealth.condition_rows value data) -> icon + label + percent (R11: never a
# bare colour; the old line read «переохолодження: тяж.0.44»).
static func condition_text(row: Dictionary) -> String:
	var pct: int = int(round(float(row.get("sev", 0.0)) * 100.0))
	var label := String(row.get("label", ""))
	var part := String(row.get("part", ""))
	match String(row.get("kind", "")):
		"hypothermia": return "❄ переохолодження %d%%" % pct
		"heatstroke": return "🥵 перегрів %d%%" % pct
		"malnutrition": return "🍖 виснаження %d%%" % pct
		"exhaustion": return "💤 недосип %d%%" % pct
		"disease": return "🦠 %s %d%% · імунітет %d%%" % [label, pct, int(round(float(row.get("extra", 0.0)) * 100.0))]
		"injury":
			var inf: float = float(row.get("extra", 0.0))
			return "🩹 %s: %s %d%%%s" % [label, part, pct, (" · інфекція %d%%" % int(round(inf * 100.0))) if inf >= 0.1 else ""]
		"scar": return "〰 шрам: %s" % part
		"implant": return "🦾 %s: %s" % [label, part]
	return "%s %d%%" % [label, pct]

# Mouse/keyboard wording -> touch wording (phones): ONE ordered table so the tooltip, the goals and
# the help never teach a key the player doesn't have. Longest phrases first.
const TOUCH_WORDS := [
	["затисни й веди — ряд", "веди пальцем — ряд"], ["Затисни ЛКМ — стіна ляже рядом", "Веди пальцем — стіна ляже рядом"],
	["ПКМ/Esc — скасувати", "✖ — скасувати"], ["ПКМ — розібрати", "🗑 — розібрати"],
	["ЛКМ —", "тап —"], ["ЛКМ", "тап"], ["Натисни ", "Вибери внизу "], ["натисни ", "вибери внизу "],
	["і клікни", "і торкнись"], ["Клікни", "Торкнись"], ["клікни", "торкнись"], ["клік —", "тап —"],
	["клавіша 0", "слот 0 внизу"], ["(I)", "(☰ → Спорядження)"], ["(J)", "(☰)"],
	["Space — пауза, +/− — швидкість", "⏸ ×1 ×2 ×3 угорі"], ["Стрілка часу: ", ""],
]

static func touchify(text: String) -> String:
	var out := text
	for pair in TOUCH_WORDS:
		out = out.replace(String(pair[0]), String(pair[1]))
	return out

# --- Основна капсула (spec 0010): нестача/ціна СЛОВАМИ — «🪵 деревина ×8» (іконка + назва + число: колір не єдиний носій, R11) ---
static func res_words(res: String, n: int) -> String:
	return "%s %s ×%d" % [CatalogDefs.res_icon(res).strip_edges(), CatalogDefs.res_label(res).to_lower(), n]

static func cost_words(cost: Dictionary) -> String:
	var parts: Array = []
	var keys: Array = cost.keys()
	keys.sort()
	for k in keys:
		parts.append(res_words(String(k), int(cost[k])))
	return " · ".join(parts)

# ПЕРША причина відмови прокачки (REQ-0010-38): перший ключ нестачі за алфавітом; `far` — склад покрив би, та герой поза зоною.
static func capsule_shortfall(missing: Dictionary, far: bool) -> String:
	if missing.is_empty():
		return ""
	var keys: Array = missing.keys()
	keys.sort()
	var first: String = String(keys[0])
	var text: String = "Бракує: " + res_words(first, int(missing[first]))
	if far:
		text += " · підійди до капсули: склад діє в її зоні"
	return text

# Імунітет у годинах/хвилинах: «5 год 30 хв» / «40 хв» (мс UTC-годинника, округлення вгору до хвилини).
static func left_ms(ms: int) -> String:
	var mins: int = int(ceil(float(maxi(0, ms)) / 60000.0))
	if mins >= 60:
		return "%d год %d хв" % [mins / 60, mins % 60]
	return "%d хв" % mins
