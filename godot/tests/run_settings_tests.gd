# RealWorld — tests/run_settings_tests.gd : налаштування (OD-164) — модель, збереження, панель, «жодних заглушок».
# Run: godot --headless --path godot -s res://tests/run_settings_tests.gd
extends "res://tests/harness.gd"

const SettingsScript = preload("res://scripts/settings.gd")
const SettingsUI = preload("res://scripts/ui/settings_panel.gd")
const TMP := "user://settings_test.json"


func _init() -> void:
	print("== RealWorld settings tests (OD-164) ==")
	_t_defs()
	_t_validation()
	_t_roundtrip()
	_t_corrupt()
	_t_file()
	_t_scale()
	_t_motion()
	_t_panel()
	_t_no_stubs()
	_t_isolation()
	finish()


func _t_defs() -> void:
	var seen: Dictionary = {}
	var good := true
	for d in SettingsScript.DEFS:
		var id: String = String(d.id)
		good = good and not seen.has(id) and ["toggle", "choice"].has(String(d.kind)) and String(d.label) != ""
		seen[id] = true
		if String(d.kind) == "choice":
			good = good and (d.options as Array).size() == (d.labels as Array).size() and (d.options as Array).size() >= 2
			good = good and (d.options as Array).any(func(o: Variant) -> bool: return is_equal_approx(float(o), float(d.default)))
		else:
			good = good and typeof(d.default) == TYPE_BOOL
	ok(good, "DEFS: унікальні id, валідні типи, дефолт серед options, labels == options")
	var s := SettingsScript.new()
	ok(s.values.size() == SettingsScript.DEFS.size(), "новий стор має всі ключі з дефолтами")
	ok(bool(s.get_value("hints")) and bool(s.get_value("goal_pointer")) and bool(s.get_value("haptics")), "підказки/маркер/вібрація — ON за замовчуванням")
	ok(not bool(s.get_value("reduce_motion")) and not bool(s.get_value("show_fps")), "менше руху/FPS — OFF за замовчуванням")
	ok(int(s.get_value("autosave_s")) == 30 and float(s.get_value("ui_scale")) == 0.0, "автозбереження 30 с, масштаб Авто")


func _t_validation() -> void:
	var s := SettingsScript.new()
	ok(s.set_value("show_fps", true) and bool(s.get_value("show_fps")), "toggle приймає bool")
	ok(not s.set_value("show_fps", 1) and bool(s.get_value("show_fps")), "toggle відхиляє не-bool, значення не змінилось")
	ok(not s.set_value("nope", true), "невідомий id відхилено")
	ok(s.set_value("autosave_s", 60.0) and typeof(s.get_value("autosave_s")) == TYPE_INT and int(s.get_value("autosave_s")) == 60, "choice: 60.0 з JSON → канонічний int 60")
	ok(not s.set_value("autosave_s", 45) and int(s.get_value("autosave_s")) == 60, "choice відхиляє значення поза options")
	ok(not s.set_value("ui_scale", "big"), "choice відхиляє рядок")
	ok(s.set_value("ui_scale", 1.25) and is_equal_approx(float(s.get_value("ui_scale")), 1.25), "ui_scale 1.25")


func _t_roundtrip() -> void:
	var s := SettingsScript.new()
	s.set_value("reduce_motion", true)
	s.set_value("autosave_s", 120)
	s.set_value("ui_scale", 1.5)
	var json: String = JSON.stringify(s.to_dict())
	var t := SettingsScript.new()
	ok(t.from_dict(JSON.parse_string(json)), "round-trip через JSON приймається")
	ok(t.values == s.values, "round-trip: значення ідентичні (типи канонічні)")
	s.reset()
	t.reset()


func _t_corrupt() -> void:
	var s := SettingsScript.new()
	s.set_value("show_fps", true)
	ok(not s.from_dict("рядок") and not bool(s.get_value("show_fps")), "не-словник → дефолти")
	ok(not s.from_dict({"version": 99, "values": {"show_fps": true}}) and not bool(s.get_value("show_fps")), "чужа версія → дефолти")
	ok(not s.from_dict({"version": 1, "values": 5}), "values не словник → дефолти")
	ok(s.from_dict({"version": 1, "values": {"show_fps": true, "autosave_s": 7, "ghost": 1, "hints": "так"}}), "частково валідний запис приймається")
	ok(bool(s.get_value("show_fps")) and int(s.get_value("autosave_s")) == 30 and bool(s.get_value("hints")), "валідне взято, сміття відкинуто, решта — дефолти")
	s.reset()


func _t_file() -> void:
	var s := SettingsScript.new()
	s.set_value("keep_awake", true)
	s.set_value("autosave_s", 15)
	ok(s.save(TMP), "save пише файл")
	var t := SettingsScript.new()
	ok(t.load_file(TMP) and bool(t.get_value("keep_awake")) and int(t.get_value("autosave_s")) == 15, "load читає те, що записано")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	ok(not t.load_file(TMP) and not bool(t.get_value("keep_awake")), "нема файлу → дефолти")
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{ це не json")
	f.close()
	ok(not t.load_file(TMP), "зіпсований JSON → дефолти без падіння")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	s.reset()


func _t_scale() -> void:
	var s := SettingsScript.new()
	ok(is_equal_approx(s.effective_scale(1.7), 1.7), "Авто бере масштаб за DPI")
	s.set_value("ui_scale", 1.25)
	ok(is_equal_approx(s.effective_scale(1.7), 1.25), "явний вибір перебиває авто")


func _t_motion() -> void:
	var s := SettingsScript.new()
	ok(SettingsScript.motion_scale() == 1.0, "за замовчуванням анімації повні")
	s.set_value("reduce_motion", true)
	ok(SettingsScript.reduce_motion and SettingsScript.motion_scale() == 0.0, "«Менше руху» → множник 0")
	s.reset()
	ok(SettingsScript.motion_scale() == 1.0, "reset повертає рух")


func _t_panel() -> void:
	var p := SettingsUI.SettingsPanel.new()
	p.is_mobile = false
	var ids: Array = p.row_ids()
	ok(not ids.has("keep_awake") and not ids.has("haptics") and ids.has("reduce_motion") and ids.has("ui_scale"), "десктоп: mobile_only-рядків нема, решта є")
	var pm := SettingsUI.SettingsPanel.new()
	pm.is_mobile = true
	ok(pm.row_ids().size() == SettingsScript.DEFS.size(), "телефон: рядок на кожен пункт таблиці")
	var s := SettingsScript.new()
	p.bind({"values": s.values, "info": "тест"})
	var tb: Button = p._rows["show_fps"].toggle
	ok(not tb.button_pressed and tb.text == "OFF", "bind: OFF показано текстом")
	s.set_value("show_fps", true)
	p.bind({"values": s.values, "info": ""})
	ok(tb.button_pressed and tb.text == "ON ✓", "bind: ON показано текстом і станом")
	var got: Array = []
	p.changed.connect(func(id: String, v: Variant) -> void: got.append([id, v]))
	tb.button_pressed = false
	tb.pressed.emit()
	ok(got.size() == 1 and got[0][0] == "show_fps" and got[0][1] == false, "натискання toggle емітить changed(id, нове значення)")
	var seg: Array = p._rows["autosave_s"].buttons
	(seg[2].btn as Button).pressed.emit()
	ok(got.size() == 2 and got[1][0] == "autosave_s" and int(got[1][1]) == 60, "сегмент емітить значення з таблиці")
	p.bind({"values": {"autosave_s": 60}, "info": ""})
	ok((seg[2].btn as Button).button_pressed and not (seg[1].btn as Button).button_pressed, "bind позначає лише активний сегмент")
	var before: int = p.get_child_count()
	p.bind({"values": s.values, "info": ""})
	p.bind({"values": s.values, "info": ""})
	ok(p.get_child_count() == before, "R2: bind не перебудовує вузли")
	var acts: Array = []
	p.action.connect(func(id: String) -> void: acts.append(id))
	p.in_game = true
	p.bind({"values": s.values, "info": ""})
	var nb: Button = p._confirm_btn
	nb.pressed.emit()
	ok(acts.is_empty() and nb.text.begins_with("⚠"), "«Нова гра»: перше натискання лише озброює")
	nb.pressed.emit()
	ok(acts == ["new_game"], "друге натискання виконує дію")
	nb.pressed.emit()
	p.bind({"values": s.values, "info": ""})
	ok(not nb.text.begins_with("⚠"), "bind знімає озброєння")
	ok(p._actions.visible, "у грі дії сесії видно")
	p.in_game = false
	p.bind({"values": s.values, "info": ""})
	ok(not p._actions.visible, "на старті дій сесії нема")
	p.free()
	pm.free()


# Анти-заглушка: кожен пункт таблиці має споживача в коді гри. Додав пункт без дії — тест червоний.
func _t_no_stubs() -> void:
	var src := FileAccess.get_file_as_string("res://newhud_main.gd")
	var dir := DirAccess.open("res://scripts/ui")
	for f in dir.get_files():
		if f.ends_with(".gd"):
			src += FileAccess.get_file_as_string("res://scripts/ui/" + f)
	for d in SettingsScript.DEFS:
		var id: String = String(d.id)
		var used: bool = src.contains('get_value("%s")' % id)
		if id == "ui_scale":
			used = src.contains("effective_scale(")
		if id == "reduce_motion":
			used = src.contains("Settings.motion_scale()") and src.contains("Settings.reduce_motion")
		ok(used, "пункт «%s» справді застосовується в грі (не заглушка)" % id)


# Налаштування пристрою не потрапляють у сим/сейв світу/хеш.
func _t_isolation() -> void:
	var leaked: Array = []
	var files: Array = ["res://scripts/persistence.gd", "res://scripts/session.gd", "res://scripts/sim.gd"]
	var sd := DirAccess.open("res://scripts/sim")
	for f in sd.get_files():
		if f.ends_with(".gd"):
			files.append("res://scripts/sim/" + f)
	for path in files:
		if FileAccess.get_file_as_string(String(path)).contains("settings.gd"):
			leaked.append(path)
	ok(leaked.is_empty(), "sim/persistence/session не імпортують settings.gd %s" % str(leaked))
