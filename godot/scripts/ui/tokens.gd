# RealWorld — ui/tokens.gd : the LOCKED design-system §1 palette as ONE source of truth (spec 0005 R3).
#
# Node-free, preloaded const (NEVER an autoload — the repo has zero autoloads; see spec 0005 §0).
# This is the view layer's `Def` analogue: the single home for every color/radius the HUD uses.
# It reconciles, ONCE, the color drift between main.gd's old C_* consts and the locked tokens:
#   C_GOOD "5fd38a" -> --good #6fae54 · C_WARN "ffcf5c" -> --warn #e0b070 · C_BAD "ff6b6b" -> --crit #e06a5a
#   accent "5db0ff" -> amber #e0b070 · dim "8fa3b5" -> #54636f
# R3: Color.html(...) is allowed ONLY in this file and theme.gd. Everywhere else uses these consts.
extends RefCounted

# --- surfaces / lines / text (design-system §1) ---
const BG      := Color("0e1216")   # app background
const PANEL   := Color("151b21")   # panel
const PANEL2  := Color("1b232b")   # raised panel
const LINE    := Color("26313b")   # hairline border
const LINE2   := Color("33414d")   # stronger border
const INK     := Color("c9d4dc")   # primary text
const MUT     := Color("7c8b97")   # secondary text
const DIM     := Color("54636f")   # tertiary text (was C_DIM "8fa3b5" — DRIFT FIXED)

# --- semantic state ramp (design-system §1; colorblind-safe: always paired with icon+number, R11) ---
const GOOD    := Color("6fae54")   # green — safe/satisfied/ally/in-band  (was C_GOOD "5fd38a" — DRIFT FIXED)
const WARN    := Color("e0b070")   # amber — wants attention/act-soon/accent (was C_WARN "ffcf5c" — DRIFT FIXED)
const AMBER   := Color("e0b070")   # selection accent (== warn, per §1)
const CRIT    := Color("e06a5a")   # red — critical/hostile/blocked (was C_BAD "ff6b6b" — DRIFT FIXED)
const TEAL    := Color("86d0d6")   # info/cold/water/bots/drinkable
const COMP    := Color("b58cff")   # violet — tech/research/advanced/components
const BLOOD   := Color("b23b34")   # blood / bleed
const ACCENT  := Color("86d0d6")   # region/label accent -> teal per §1 (was C_ACCENT "5db0ff" — DRIFT FIXED)

const R       := 8                 # corner radius (design-system --r)
const NIGHT    := Color("060a18")  # night ambient tint (Light overlay / day-night darkening)
const WHITE    := Color(1, 1, 1)   # neutral modulate (afford = full)
const DIMMED   := Color(1, 1, 1, 0.45)  # unaffordable modulate (design-system palette dim)

# Return a token color at a given alpha WITHOUT callers writing a Color() literal (keeps R3's grep
# green outside this file — the only sanctioned Color() home besides theme.gd).
static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

# Resource dot colors (design-system §1). KEYS are the runtime resource ids in GameData.RES_ORDER —
# design-system §1's `--comp` dot token is shorthand for the runtime id `components` (used here + data.gd).
const RES := {
	"wood":       Color("c08a4a"),
	"stone":      Color("9aa3ab"),
	"food":       Color("e06a5a"),
	"scrap":      Color("86d0d6"),
	"planks":     Color("e0b070"),
	"components": Color("b58cff"),
}

# Terrain palette (folded out of world_view.gd's inline Color.html so overlays + tilemap share one palette, R3).
const TERRAIN := {
	"grass": Color("20321f"),
	"forest": Color("2f5133"),
	"water": Color("2b3f5c"),
	"road":  Color("4a4036"),
}

static func res(id: String) -> Color:
	return RES.get(id, INK)

static func terrain(id: String) -> Color:
	return TERRAIN.get(id, GRASS_FALLBACK)

const GRASS_FALLBACK := Color("20321f")

# The ONE enum->color site (R11). The snapshot carries the enum; the view owns the color.
static func urgency(state: StringName) -> Color:
	match state:
		&"good": return GOOD
		&"warn": return WARN
		&"crit": return CRIT
		_:       return INK

# Feed/card category -> left-border color (design-system .card .t-*).
static func category(cls: String) -> Color:
	match cls:
		"good", "t-good": return GOOD
		"warn", "t-small": return WARN
		"bad", "big", "t-big": return CRIT
		"misc", "t-misc": return TEAL
		_: return LINE2
