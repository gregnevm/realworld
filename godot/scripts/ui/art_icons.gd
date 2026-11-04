# RealWorld — ui/art_icons.gd : generated icon textures for the HUD (art pipeline → assets/gen/icon).
#
# One cached lookup, view-only (R1). Imported resource first (export/editor); raw PNG fallback when
# there is no import cache (fresh checkout, headless tests). A miss returns null and callers keep
# their emoji glyph (R11), so a missing PNG never leaves a blank slot. Misses are cached too.
extends RefCounted

const DIR := "res://assets/gen/icon/"
static var _cache: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if id == "":
		return null
	return _load(id, "%s%s.png" % [DIR, id])

# Resource icon by catalogue/live resource id (res_<id>).
static func res(res_id: String) -> Texture2D:
	return texture("res_" + res_id)

# HUD-icon art (assets/gen/ui). Emoji glyphs the panels already use map to bespoke art, so a panel
# keeps passing its emoji (R11 fallback) and gets the generated icon for free when one exists.
const UI_DIR := "res://assets/gen/ui/"
const GLYPH_ART := {"❤": "ui_hp", "🍖": "ui_food", "😴": "ui_rest", "🩸": "ui_blood", "🌡": "ui_temp",
	"🎒": "ui_carry", "⚔": "ui_threat", "💰": "ui_wealth", "🔬": "ui_research", "◎": "ui_goal"}

static func ui(id: String) -> Texture2D:
	return _load("ui:" + id, "%s%s.png" % [UI_DIR, id])

static func for_glyph(glyph: String) -> Texture2D:
	return ui(String(GLYPH_ART[glyph])) if GLYPH_ART.has(glyph) else null

static func _load(key: String, path: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

# Building sprite (sprite/ then tile/ dir, bld_<kind>) cropped to its opaque content, so a small HUD slot
# shows the object itself instead of a thumbnail swimming in the generator's transparent margin.
static var _crops: Dictionary = {}

static func building(kind: String) -> Texture2D:
	if _crops.has(kind):
		return _crops[kind]
	var tex: Texture2D = _load("spr:" + kind, "res://assets/gen/sprite/bld_%s.png" % kind)
	if tex == null:
		tex = _load("til:" + kind, "res://assets/gen/tile/bld_%s.png" % kind)
	var out: Texture2D = tex
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty() and img.detect_alpha() != Image.ALPHA_NONE:
			var u := img.get_used_rect()
			if u.size.x > 0 and u.size.y > 0:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(u)
				out = at
	_crops[kind] = out
	return out
