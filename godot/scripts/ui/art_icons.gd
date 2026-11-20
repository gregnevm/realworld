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

# Гліфи, для яких арт УЖЕ є в інших наборах (спрайт споруди / іконка предмета чи ресурсу): «bld:», «item:», «res:».
# Пін-тест `_t_art_icons` вимагає PNG для кожного рядка цієї таблиці.
const GLYPH_REUSE := {"📦": "bld:storage", "🎯": "ui:ui_goal", "⚡": "bld:battery", "🧪": "bld:chemistry_bench", "🏗": "bld:stone_wall",
	"⚒": "bld:workbench", "💡": "bld:lamp", "🦺": "item:flak_vest", "⛏": "item:pick", "🔥": "bld:campfire", "🪵": "res:wood", "🪨": "res:stone",
	"🛏": "bld:bed", "🛠": "bld:workbench"}
# Гліфи, для яких іконку ще не згенеровано (рядки `ui_*` у art/manifest.json зі статусом todo): поки PNG нема — лишається емоджі (R11),
# щойно `/gen-art` покладе файл — він підхопиться без зміни панелей. `_t_art_icons` перевіряє, що кожен id є в маніфесті.
const GLYPH_PENDING := {"☰": "ui_menu", "⚙": "ui_settings", "♻": "ui_dismantle", "🔨": "ui_build", "🚀": "ui_capsule", "🚚": "ui_convoy",
	"🗺": "ui_map", "🧭": "ui_compass", "🛡": "ui_social", "📜": "ui_eras", "❔": "ui_help", "⚖": "ui_balance", "💾": "ui_save", "🗑": "ui_trash",
	"↩": "ui_back", "↺": "ui_reset", "⚠": "ui_warning", "☀": "ui_sun", "🌙": "ui_moon", "⛅": "ui_cloud", "🌧": "ui_rain", "❄": "ui_snow",
	"🌫": "ui_fog", "✖": "ui_close", "⏱": "ui_timer", "🔒": "ui_lock", "☠": "ui_death", "📍": "ui_pin"}

static func for_glyph(glyph: String) -> Texture2D:
	if GLYPH_ART.has(glyph):
		return ui(String(GLYPH_ART[glyph]))
	if GLYPH_REUSE.has(glyph):
		var src: PackedStringArray = String(GLYPH_REUSE[glyph]).split(":")
		match src[0]:
			"bld":
				return building(src[1])
			"item":
				return texture("item_" + src[1])
			"res":
				return res(src[1])
		return ui(src[1])
	return ui(String(GLYPH_PENDING[glyph])) if GLYPH_PENDING.has(glyph) else null

# «🎒 Інвентар» -> ["🎒", "Інвентар"]: перший «словесний» шматок до пробілу, якщо він відомий гліф (з будь-якої з трьох таблиць).
# Текст без відомого гліфа повертається як ["", text].
static func split_glyph(text: String) -> PackedStringArray:
	var at: int = text.find(" ")
	var head: String = (text if at < 0 else text.substr(0, at)).replace("\ufe0f", "")
	if GLYPH_ART.has(head) or GLYPH_REUSE.has(head) or GLYPH_PENDING.has(head):
		return PackedStringArray([head, "" if at < 0 else text.substr(at + 1)])
	return PackedStringArray(["", text])

# Кнопка з текстом «<емоджі> Назва»: якщо для емоджі є арт — він стає іконкою кнопки, а емоджі зникає з тексту.
# Нема арту — кнопка лишається як була (R11). Викликати ПІСЛЯ встановлення тексту; повторний виклик безпечний.
static func dress(b: Button, icon_px: int = 22) -> bool:
	var parts: PackedStringArray = split_glyph(b.text)
	if parts[0] == "":
		return false
	var tex: Texture2D = for_glyph(parts[0])
	if tex == null:
		return false
	b.icon = tex
	b.text = parts[1]
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", icon_px)
	return true

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

# Full-screen key art (assets/gen/key): spawn / death backdrops. null → the caller keeps a flat colour.
static func key(id: String) -> Texture2D:
	return _load("key:" + id, "res://assets/gen/key/%s.png" % id)
