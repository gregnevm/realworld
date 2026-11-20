# RealWorld — ui/sprite_font.gd : шрифт-атлас зі згенерованого арту для емоджі-кодпоінтів.
#
# Тексти гри (банери, підказки, стрічка подій, тултіпи, написи панелей) історично несуть емоджі всередині рядків.
# Замість переписувати кожен Label на RichTextLabel, тема ставить ЦЕЙ шрифт першим у ланцюг запасних: кодпоінт
# емоджі, для якого є арт (ArtIcons.for_glyph), малюється нашим спрайтом у будь-якому Label/Button/tooltip/draw_string.
# Кодпоінт без арту провалюється далі — до системного шрифту емоджі (R11: ніколи не порожнє місце).
# View-only (R1): лише читає текстури; будується один раз на процес.
extends RefCounted

const ArtIcons = preload("res://scripts/ui/art_icons.gd")
const GameData = preload("res://scripts/data.gd")

const CELL := 48          # сторона клітинки атласу (px); шрифт масштабується до розміру тексту
const PAD := 2            # прозоре поле довкола спрайта, щоб сусіди не «текли» при фільтрації
const FIXED := 36         # «кегль» атласу менший за клітинку: у рядку спрайт на третину вищий за літери — інакше нечитабельний
const ASCENT := 37.0      # базова лінія: спрайт вищий за велику літеру й трохи звисає під рядок
const ADVANCE := 51.0

const CATALOG := "res://content/catalog.json"
const Tokens = preload("res://scripts/ui/tokens.gd")

# Кольорові мітки стану й легенди — НЕ предмети: проста плашка кольору теми (круг — ставлення, квадрат — зона на карті).
# Стоять перед каталогом, бо ті самі гліфи каталог уживає як значки ресурсів (🟡 золото, 🔴 люциферій, 🟩 нефрит).
const SWATCH := {"🟢": [true, Tokens.GOOD], "🟡": [true, Tokens.WARN], "🔴": [true, Tokens.CRIT],
	"🟩": [false, Tokens.GOOD], "🟦": [false, Tokens.TEAL], "🟥": [false, Tokens.CRIT]}
# Гліфи каталогу, які в інтерфейсі є звичайним текстовим маркером (тут ▪ — типовий пункт списку), спрайтом не стають.
# ◎ — текстове кільце (ядро капсули, легенда радара): у медальйоні «Цілі» воно стає іконкою через ArtIcons.for_glyph, а в рядку — ні.
const TEXT_ONLY := ["▪", "◎"]
# У РЯДКУ гліф означає інше, ніж на кнопці: ⚙ у текстах — брухт (ресурс), а на кнопці «Налаштування» — шестерня (ArtIcons.dress).
const INLINE_RES := {"⚙": "scrap"}

static func _swatch(round_shape: bool, col: Color) -> Image:
	var n: int = CELL - PAD * 2 - 12
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c: float = (n - 1) * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(x - c, y - c).length() if round_shape else maxf(absf(x - c), absf(y - c))
			if d <= c:
				img.set_pixel(x, y, Tokens.BG if d > c - 3.0 else col)
			else:
				img.set_pixel(x, y, Tokens.with_alpha(Tokens.BG, 0.0))
	return img

# Гліф -> текстура. Спершу таблиці ArtIcons (інтерфейс), потім гліфи ресурсів: живі (data.gd RES) і каталожні (catalog.json) —
# кожен ресурс уже має іконку `res_<id>`. Гліф, спільний для кількох ресурсів, бере арт ПЕРШОГО з них (у тексті поруч завжди назва).
static func glyph_map() -> Dictionary:
	var out: Dictionary = {}
	for sw in SWATCH:
		out[String(sw)] = ImageTexture.create_from_image(_swatch(bool(SWATCH[sw][0]), SWATCH[sw][1] as Color))
	for g0 in INLINE_RES:
		_claim(out, String(g0), ArtIcons.res(String(INLINE_RES[g0])))
	for table in [ArtIcons.GLYPH_ART, ArtIcons.GLYPH_REUSE, ArtIcons.GLYPH_PENDING]:
		for g in table:
			_claim(out, String(g), ArtIcons.for_glyph(String(g)))
	for id in GameData.RES_ORDER:
		_claim(out, String(GameData.RES[id].icon), ArtIcons.res(String(id)))
	var cat: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG)) if FileAccess.file_exists(CATALOG) else null
	if cat is Dictionary:
		for r in ((cat as Dictionary).get("resources", []) as Array):
			if r is Dictionary and (r as Dictionary).has("icon"):
				_claim(out, String(r.icon), ArtIcons.res(String(r.get("id", ""))))
	return out

static func _claim(out: Dictionary, glyph: String, tex: Texture2D) -> void:
	var g: String = glyph.replace("\ufe0f", "")
	if g.length() == 1 and tex != null and not out.has(g) and not (g in TEXT_ONLY):
		out[g] = tex

# Гліфи з одного кодпоінта, для яких є арт. Порядок стабільний (сортований) — атлас детермінований.
static func glyphs() -> PackedStringArray:
	var keys: Array = glyph_map().keys()
	keys.sort()
	return PackedStringArray(keys)

static func _image_of(tex: Texture2D) -> Image:
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	img = img.get_region(used)
	if img.get_width() <= CELL - PAD * 2 and img.get_height() <= CELL - PAD * 2:
		return img   # плашка-зразок уже потрібного розміру (менша за спрайт — не розтягуємо)
	var inner: int = CELL - PAD * 2
	var k: float = minf(float(inner) / float(used.size.x), float(inner) / float(used.size.y))
	img.resize(maxi(1, int(round(used.size.x * k))), maxi(1, int(round(used.size.y * k))), Image.INTERPOLATE_LANCZOS)
	return img

# null, якщо арту нема зовсім (тоді тема лишається на системних емоджі).
static func build() -> FontFile:
	var gmap: Dictionary = glyph_map()
	var list: PackedStringArray = glyphs()
	if list.is_empty():
		return null
	var cols: int = 16
	var rows: int = int(ceil(float(list.size()) / float(cols)))
	var atlas := Image.create(cols * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var f := FontFile.new()
	f.fixed_size = FIXED
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	# Для «кольорових» емоджі (кодпоінти поза базовою площиною) рушій спершу питає СИСТЕМНИЙ шрифт емоджі, якщо шрифт це дозволяє, —
	# і наш спрайт програє телефонному Noto Color Emoji. Заборона тут = наш арт має пріоритет (перевірено шейпінгом у тесті).
	f.allow_system_fallback = false
	# Рушій ставить шрифти, що «підтримують скрипт» прогону, поперед решти: без цих позначок текстовий шрифт символів
	# (DejaVu має свої ⚠ ◎ ⚙) випереджає атлас, хоч той і перший у ланцюгу.
	for script in ["Zyyy", "Zsye", "Zsym", "Zinh", "Cyrl", "Latn"]:
		f.set_script_support_override(script, true)
	var size := Vector2i(FIXED, 0)
	f.set_cache_ascent(0, FIXED, ASCENT - 8.0)   # метрики рядка — як у тексту: спрайт не розсуває рядки
	f.set_cache_descent(0, FIXED, float(CELL) - ASCENT - 4.0)
	var placed: Array = []
	for i in list.size():
		var img: Image = _image_of(gmap[list[i]] as Texture2D)
		if img == null:
			continue
		var cell := Vector2i((i % cols) * CELL, (i / cols) * CELL)
		var at := cell + Vector2i((CELL - img.get_width()) / 2, (CELL - img.get_height()) / 2)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		placed.append([list[i].unicode_at(0), cell])
	f.set_texture_image(0, size, 0, atlas)
	for p in placed:
		var code: int = int(p[0])
		var cell2: Vector2i = p[1]
		f.set_glyph_advance(0, FIXED, code, Vector2(ADVANCE, 0))
		f.set_glyph_offset(0, size, code, Vector2(0, -ASCENT))
		f.set_glyph_size(0, size, code, Vector2(CELL, CELL))
		f.set_glyph_uv_rect(0, size, code, Rect2(cell2, Vector2(CELL, CELL)))
		f.set_glyph_texture_idx(0, size, code, 0)
	return f
