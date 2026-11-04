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
