# RealWorld — settings.gd : налаштування пристрою (view-рівень, НЕ частина сейву світу й НЕ в world_hash).
#
# Один файл user://settings.json, версійований і валідований: зіпсований/чужий запис = безпечні дефолти.
# Кожен пункт таблиці DEFS має реальну дію в грі (див. `apply_*` у newhud_main.gd і `Settings.reduce_motion`);
# пунктів без дії тут НЕМА (OD-164: жодних заглушок — звуку немає, тому й повзунка гучності немає).
extends RefCounted

const PATH := "user://settings.json"
const VERSION := 1

# Статичний прапор для віджетів: читається в _process/tween без доступу до сторa (одна правда — Store.set).
static var reduce_motion := false

# kind: toggle | choice. choice.options — значення, choice.labels — підписи (рівно стільки ж).
# mobile_only: пункт показується лише на телефоні (на десктопі він нічого б не робив).
const DEFS: Array = [
	{"id": "ui_scale", "section": "Екран", "kind": "choice", "label": "Масштаб інтерфейсу", "default": 0.0,
		"options": [0.0, 0.85, 1.0, 1.25, 1.5, 2.0], "labels": ["Авто", "85%", "100%", "125%", "150%", "200%"],
		"hint": "Авто — за DPI телефону. Більше — крупніші кнопки й текст."},
	{"id": "reduce_motion", "section": "Екран", "kind": "toggle", "label": "Менше руху", "default": false,
		"hint": "Вимикає пульсації, мерехтіння кілець і анімації перемикань."},
	{"id": "show_fps", "section": "Екран", "kind": "toggle", "label": "Лічильник FPS", "default": false,
		"hint": "Кадри за секунду в куті екрана."},
	{"id": "keep_awake", "section": "Екран", "kind": "toggle", "label": "Не вимикати екран", "default": false, "mobile_only": true,
		"hint": "Екран не гасне, поки гра відкрита (витрачає батарею)."},
	{"id": "hints", "section": "Підказки", "kind": "toggle", "label": "Опис об'єктів", "default": true,
		"hint": "Підказка про те, на що навів курсор чи утримуєш палець."},
	{"id": "goal_pointer", "section": "Підказки", "kind": "toggle", "label": "Маркер цілі у світі", "default": true,
		"hint": "Показує, де діяти для поточної цілі."},
	{"id": "haptics", "section": "Керування", "kind": "toggle", "label": "Вібрація", "default": true, "mobile_only": true,
		"hint": "Короткий відгук при шкоді, смерті та рейді."},
	{"id": "autosave_s", "section": "Збереження", "kind": "choice", "label": "Автозбереження", "default": 30,
		"options": [15, 30, 60, 120], "labels": ["15 с", "30 с", "60 с", "2 хв"],
		"hint": "Гра зберігається також на початку кожного дня й при виході."},
]

var values: Dictionary = {}

func _init() -> void:
	reset()

static func def_of(id: String) -> Dictionary:
	for d in DEFS:
		if String(d.id) == id:
			return d
	return {}

func reset() -> void:
	values = {}
	for d in DEFS:
		values[String(d.id)] = d.default
	_sync_static()

func get_value(id: String) -> Variant:
	return values.get(id, def_of(id).get("default"))

# Повертає true, якщо значення прийнято (відоме id, допустиме значення). Нічого не пише на диск — це робить викликач.
func set_value(id: String, v: Variant) -> bool:
	var d: Dictionary = def_of(id)
	if d.is_empty():
		return false
	var n: Variant = _coerce(d, v)
	if n == null:
		return false
	values[id] = n
	_sync_static()
	return true

# Приводить сире значення (із JSON) до типу пункту; null = недопустиме.
static func _coerce(d: Dictionary, v: Variant) -> Variant:
	if String(d.kind) == "toggle":
		return bool(v) if typeof(v) == TYPE_BOOL else null
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return null
	for o in d.options:
		if is_equal_approx(float(o), float(v)):
			return o   # значення беремо з таблиці: тип (int/float) завжди канонічний
	return null

func _sync_static() -> void:
	reduce_motion = bool(values.get("reduce_motion", false))

# Множник тривалості анімацій: 0 за «Менше руху» — tween миттєвий.
static func motion_scale() -> float:
	return 0.0 if reduce_motion else 1.0

func to_dict() -> Dictionary:
	return {"version": VERSION, "values": values.duplicate()}

# Приймає лише відомі ключі з допустимими значеннями; решта лишається дефолтом. Повертає false, якщо запис не словник
# потрібної версії (тоді значення — усі дефолти).
func from_dict(d: Variant) -> bool:
	reset()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	var rec: Dictionary = d
	if int(rec.get("version", -1)) != VERSION or typeof(rec.get("values")) != TYPE_DICTIONARY:
		return false
	var vals: Dictionary = rec["values"]
	for k in vals:
		set_value(String(k), vals[k])
	return true

func save(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true

func load_file(path: String = PATH) -> bool:
	if not FileAccess.file_exists(path):
		reset()
		return false
	var txt: String = FileAccess.get_file_as_string(path)
	return from_dict(JSON.parse_string(txt))

# Ефективний масштаб вікна: явний вибір гравця, інакше авто (на телефоні — від DPI, на десктопі 1.0).
func effective_scale(auto_scale: float) -> float:
	var s: float = float(get_value("ui_scale"))
	return auto_scale if s <= 0.0 else s
