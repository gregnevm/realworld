# AGENTS.md — RealWorld

> Машиночитний контекст проєкту для AI-агентів (Claude Code, Cursor, Codex, Copilot, Gemini CLI, Windsurf). Тримай актуальним: застарілий AGENTS.md гірший за відсутній.
> last_reviewed: 2026-06

## Огляд
- **Що це:** RealWorld — survival-MMORPG із симуляційною глибиною RimWorld на **картах зі справжньої географії (OSM/GPS)**; один глибоко симульований персонаж, persistent-світ, логістика конвоями. Репозиторій містить дизайн-документ і граний прототип.
- **Стейдж:** prototype (Фаза 0 — одиночний вертикальний зріз).
- **Головні домени/модулі:**
  - `game/` — граний прототип (HTML5 Canvas, vanilla JS).
  - `GDD_BOOK/` — інтерактивний Game Design Document; джерело істини дизайну — `GDD_BOOK/gdd.json`.
  - `.claude/launch.json` — конфіг dev-сервера прев'ю (`realworld-game`, порт 8766).

## Стек
- **Мова(и):** JavaScript (classic scripts, без транспіляції), HTML5, CSS.
- **Фреймворки/рантайм:** жодного фреймворку і **жодного кроку збірки** — браузер виконує файли як є. Node 22 та Python 3.10 доступні локально (тести/сервери/тулінг).
- **Сховище даних:** `localStorage` (збереження гри); дизайн — `gdd.json`.
- **Зовнішні залежності/API:** OpenStreetMap **Overpass API** (генерація карти з реальних координат) з детермінованим процедурним fallback. Жодних npm-залежностей у рантаймі.

## Архітектура
- Гра — єдиний глобальний неймспейс **`RW`**, розкладений по файлах у `game/js/`, які підключаються **у фіксованому порядку** в `game/index.html`: `util → worldgen → entities → render → logistics → ui → input → game`. `game.js` стартує на `DOMContentLoaded`.
- Цикл: `requestAnimationFrame` → `RW.update(G, dt)` (симуляція) + `RW.render(ctx, G)`. Уся ігрова модель — в об'єкті `G` (`RW.G`).
- World-gen: `lat/lon` → детермінований seed (`mulberry32`) → процедурна карта; за потреби зверху накладається реальна геометрія OSM (`RW.overlayOSM`).
- GDD: фронтенд читає `gdd.json` через `fetch` (потрібен HTTP-origin, не `file://`).

## Структура файлів
```
realworld/
  AGENTS.md            ← цей файл (контекст для агентів)
  game/
    index.html         ← порядок підключення скриптів = контракт
    styles.css
    js/
      util.js          RNG, A*-pathfinding, математика, неймспейс RW
      worldgen.js      lat/lon → тайлмапа; Overpass + fallback
      entities.js      дані: ресурси, будівлі, ноди, рейдери
      render.js        малювання канвасу, камера, день/ніч
      logistics.js     конвої між реальними регіонами
      ui.js            DOM-HUD, меню, спавн-екран, світова карта
      input.js         миша/клавіатура/тач
      game.js          стан, симуляція, бій, рейди, цикл, save/load
  GDD_BOOK/            інтерактивний GDD; правда — gdd.json
  .claude/launch.json  dev-сервер прев'ю
```

## Godot-порт (форвардний рушій — нові фічі сюди; JS-версія заморожена як референс)
- **Де:** `godot/` — повний порт на **Godot 4.7 (GDScript)**. Симуляція scene-free, детермінована (PCG32 із FNV-хешу координат), тестовна headless. Пиляр: «координати — це seed» (світ = чиста функція `lat/lon`). UI — **українською**.
- **Шари:**
  - `godot/scripts/` — `sim.gd` (детермінований сим), `session.gd` (оркестрація регіонів/подорожей/респавну), `social.gd`, `persistence.gd`, `world_gen.gd`, `world_view.gd` (custom-draw тайлмапи), `main.gd` (поточний HUD-моноліт — досі дефолтна сцена).
  - `godot/scripts/kernel/` — **механічний кернел (spec 0003)**: `Def`/`Thing`+`ThingComp`/`StatWorker`+`StatPart`/`SimSystem`+`SystemRegistry`/`Balance`. «Додати механіку ніколи не редагує tick-loop».
  - `godot/scripts/ui/` — **view-шар (spec 0005)**: 6 контрактів-дзеркал кернела — `Tokens`/`Theme`, `Panel`+`PanelRegistry`, `Overlay`+`OverlayRegistry`, `Widget`(бібліотека примітивів), `HudModel.snapshot()` (чистий ViewModel = аналог `Balance.assess()`), `FeedbackBus`, `InputVerbs`+`InputController`. `HudRoot` — тонкий контролер. `newhud_main.gd` — нова сцена (bare-arg `newhud`), збирається **лише з реєстрів** (`mechanics.gd`).
- **12 правил view-шару (spec 0005 §1, примусові через `run_ui_tests.gd`):** R1 односторонній потік (sim не імпортує ui) · R2 build-once-then-bind (без ребілду панелей) · R3 стилі лише через `Tokens`/`Theme` (жодних inline `Color(`/`StyleBoxFlat` поза `tokens.gd`/`theme.gd`) · R4 контролер не називає жодної механіки · R5 кожне число з `explain()` · R6 просторовий стан = `Overlay`, не список координат · R7 resize-safe анкери лише через `Widget.pin_*` · R8 слайси — тільки value-data · R9 sim-команди лише в роутері · R10 фідбек — один адаптер · R11 enum+іконка+число (не лише колір) · R12 keyboard-first + видимий детермінізм.
- **GDScript-гочі (обов'язково):** `:=` не виводить тип із `Variant` (доступ до поля `Dictionary`, `abs()`, нетипізований метод) → явний `: Type` або `absf/absi`; JSON round-trip перетворює `int→float`; `RefCounted` не збирає цикли → чисти крос-рефи в `_exit_tree()`; лише seeded `RandomNumberGenerator`; **інклас+preload** (жодного top-level `class_name`, жодних autoload); анкери resize-safe. Інклас з іменем `Panel` **шедовить** нативний `Panel` — базу названо `Base`.
- **Тести (headless):** `test.cmd` у корені ганяє 4 сьюти — `run_tests` (119), `run_kernel_tests` (152), `run_ui_tests` (65, spec 0005), `run_smoke` (8). Годо-екзе: `%LOCALAPPDATA%\GodotPortable\Godot_v4.7-stable_win64[_console].exe`. Приклад: `Godot_console.exe --headless --path godot -s res://tests/run_ui_tests.gd`.
- **Скриншот нового HUD:** `Godot_console.exe --path godot res://newhud.tscn -- newhud shot` (віконно, не headless) → `godot/newhud_shot.png`.
- **UX-контракт:** `docs/ux/design-system.md` (зафіксовані токени §1 / layout §2 / оверлеї §3 / віджети §4 / граматика §5) + `docs/ux/hud.html` (рендер-макет, джерело parity). Специфікації: `specs/0003` (кернел), `specs/0004` (каталог механік+UX), `specs/0005` (view-архітектура).

## Конвенції
- **Іменування:** усе публічне вішається на `RW.*`; стан гри — `G`; тайл-індекс — `i = y*N + x`.
- **Стиль:** 2 пробіли; `"use strict"` у кожному IIFE-модулі; без ES-модулів (`import/export`) — лишаємось на classic scripts заради no-build.
- **Патерни:** симуляція детермінована від seed; логіку тримай по змозі **без залежності від DOM/canvas** (щоб була тестовна в Node).
- **Чого НЕ робити:** не додавати збірку/бандлер/фреймворк без обговорення; не ламати порядок підключення скриптів; не змішувати рендер із симуляцією; жодних мережевих викликів окрім Overpass без узгодження.

## Команди
- **Запуск гри (dev):** `cd game && python -m http.server 8765` → http://localhost:8765
- **Запуск GDD:** `python "C:\Users\gregn\.claude\skills\gdd_build\scripts\serve.py" "O:\realworld\GDD_BOOK"`
- **Тести:** _поки немає_ (план: `node --test` на чистій логіці симуляції).
- **Білд/деплой:** білду немає; статичний хостинг (GitHub Pages / Railway / itch.io).

## Ключові рішення (ADR-лайт)
- **Vanilla JS, no-build** — миттєва ітерація, працює будь-де, ноль тулчейн-боргу на стадії прототипу. Альтернативу (Vite/TS) відкинули як передчасну.
- **Процедурний fallback для OSM** — гра грається офлайн і детермінована; реальна географія — це збагачення, не залежність.
- **Глобальний `RW` + classic scripts** — простота; ціна — дисципліна щодо порядку підключення (зафіксована вище).
- **Один персонаж + MMO** — це survival-RPG із ДНК RimWorld, а не колонія-сим (деталі — `GDD_BOOK/gdd.json`).

## Правила для агента
- Перед зміною — звірся з цим файлом і структурою; не вигадуй конвенції.
- Зміни тримай у скоупі задачі; не тягни неузгоджені залежності.
- **Верифікація:** прев'ю-скриншот у цьому середовищі зламаний — драйв через `preview_eval` (старт гри, `G.speed=0`, цикл `RW.update(G,dt)`, читай стан); кадр знімай через `canvas.toDataURL` (див. memory `browser-game-canvas-screenshot`).
- Секрети/ключі — ніколи в код.
- Великі рефактори/міграції (особливо перехід на клієнт-сервер для Фази 1) — спершу ADR + спека й узгодження, не одразу код.
