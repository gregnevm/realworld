# RealWorld — tests/run_release_tests.gd : «чесна 1.01» (OD-166) — трипвайри: гра не обіцяє того, чого немає.
# Run: godot --headless --path godot -s res://tests/run_release_tests.gd
extends "res://tests/harness.gd"

const LifecycleScript = preload("res://scripts/ui/lifecycle.gd")
const WorldPanels = preload("res://scripts/ui/world_panels.gd")
const BuildInfo = preload("res://scripts/build_info.gd")


func _init() -> void:
	print("== RealWorld release honesty tests (OD-166) ==")
	_t_version()
	_t_no_stub_words()
	_t_social_note()
	await _t_spawn_honest()
	finish()


func _t_version() -> void:
	ok(BuildInfo.VERSION == "1.01-rc1", "версія продукту — кандидат 1.01-rc1")
	ok(BuildInfo.label().begins_with("v1.01-rc1"), "рядок збірки в ☰ починається з версії")


# Видимий гравцеві текст не містить слів-заглушок (технічні коментарі й імена функцій не рахуємо — лише рядкові літерали).
func _t_no_stub_words() -> void:
	var bad: Array = []
	var files: Array = ["res://newhud_main.gd"]
	var d := DirAccess.open("res://scripts/ui")
	for f in d.get_files():
		if f.ends_with(".gd"):
			files.append("res://scripts/ui/" + f)
	var rx := RegEx.create_from_string("\"[^\"\\n]*(заглушк|скоро буде|coming soon|TODO|в розробці|not implemented)[^\"\\n]*\"")
	for path in files:
		var src: String = FileAccess.get_file_as_string(String(path))
		for line in src.split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			if rx.search(line) != null:
				bad.append("%s: %s" % [path, t.left(80)])
	ok(bad.is_empty(), "у рядках UI немає «заглушка/скоро/TODO/в розробці» %s" % str(bad))


func _t_social_note() -> void:
	var sp = WorldPanels.SocialPanel.new()
	sp.build_once()
	var found := false
	var stack: Array = [sp]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Label and (n as Label).text.contains("згенеровані грою"):
			found = true
	ok(found, "панель «Соціальне» чесно каже: клани й друзі згенеровані грою")
	sp.free()


func _t_spawn_honest() -> void:
	var ss = LifecycleScript.SpawnScreen.new()
	get_root().add_child(ss)
	await process_frame
	var gps_visible := true
	var gps_found := false
	var stack: Array = [ss]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Button and (n as Button).text.contains("GPS"):
			gps_found = true
			gps_visible = (n as Button).visible
	ok(gps_found and not gps_visible, "кнопка «Моя GPS-локація» прихована, поки пристрій не дає фікс (нема нативного плагіна)")
	ss.free()
