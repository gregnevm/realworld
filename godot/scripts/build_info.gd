extends RefCounted
# Штамп збірки. У репозиторії — «dev»; CI перезаписує цей файл перед експортом web/APK
# (див. .github/workflows/godot.yml, крок «Stamp build»), тож у ☰-меню й консолі видно, яка це збірка.
# Лише дані й чиста функція: sim цього не читає (детермінізм не зачіпається).

const VERSION := "1.01"   # версія продукту (збірки CI додають № запуску); змінює власник/релізний PR
const SHA := "dev"
const RUN := "0"
const BUILT := "local"

static func label() -> String:
	if SHA == "dev":
		return "v%s · dev (локальна збірка)" % VERSION
	return "v%s · #%s · %s · %s" % [VERSION, RUN, SHA, BUILT]
