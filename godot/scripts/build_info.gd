extends RefCounted
# Штамп збірки. У репозиторії — «dev»; CI перезаписує цей файл перед експортом web/APK
# (див. .github/workflows/godot.yml, крок «Stamp build»), тож у ☰-меню й консолі видно, яка це збірка.
# Лише дані й чиста функція: sim цього не читає (детермінізм не зачіпається).

const VERSION := "1.01-rc1"   # кандидат: суфікс -rc знімається лише коли всі гейти 1.01 закриті (tests/release.test.js); збірки CI додають № запуску
const SHA := "dev"
const RUN := "0"
const BUILT := "local"

static func label() -> String:
	if SHA == "dev":
		return "v%s · dev (локальна збірка)" % VERSION
	return "v%s · #%s · %s · %s" % [VERSION, RUN, SHA, BUILT]
