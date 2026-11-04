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
	if _cache.has(id):
		return _cache[id]
	var path := "%s%s.png" % [DIR, id]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_cache[id] = tex
	return tex

# Resource icon by catalogue/live resource id (res_<id>).
static func res(res_id: String) -> Texture2D:
	return texture("res_" + res_id)
