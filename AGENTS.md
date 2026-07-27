# AGENTS.md — RealWorld

> Машиночитний контекст проєкту для AI-агентів (Claude Code, Cursor, Codex, Copilot, Gemini CLI, Windsurf). Тримай актуальним: застарілий AGENTS.md гірший за відсутній.
> last_reviewed: 2026-07

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
- Гра — єдиний глобальний неймспейс **`RW`**, розкладений по файлах у `game/js/`, які підключаються **у фіксованому порядку** в `game/index.html`: `util → worldgen → entities → catalog_data → progression → render → logistics → ui → input → game`. `game.js` стартує на `DOMContentLoaded`.
- **Прогресія у веб-зрізі:** `G.research = RW.Progression(RW.CATALOG)` — той самий tech-DAG, що і в Godot (`catalog.json`); дослідні столи генерують прогрес у `RW.update`; будівлі з `research:`-гейтом заблоковані до розблокування (клік по локу планує весь шлях). Після зміни `catalog.json` — `node tools/sync-catalog.mjs` (CI-тест ловить розсинхрон).
- **Сідований геймплей-RNG (веб):** `G.rng = RW.mulberry32(hashSeed(lat,lon) ^ 0x5EED)` — рейди/лут/засідки/OSM-ноди детерміновані від координат; жодного `Math.random` у sim-шляхах; стан RNG персистується в сейві (`rngState`, `getState/setState`).
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
      entities.js      дані: ресурси, будівлі (з research-гейтами), ноди, рейдери
      catalog_data.js  ЗГЕНЕРОВАНИЙ зріз godot/content/catalog.json (node tools/sync-catalog.mjs)
      progression.js   RW.Progression — JS-дзеркало kernel/progression.gd (дерево досліджень)
      render.js        малювання канвасу, камера, день/ніч
      logistics.js     конвої між реальними регіонами
      ui.js            DOM-HUD, меню, спавн-екран, світова карта
      input.js         миша/клавіатура/тач
      game.js          стан, симуляція, бій, рейди, цикл, save/load
  godot/               порт у Godot 4.7 — форвардний рушій (деталі в розділі «Godot-порт»)
    scripts/kernel/       механічний кернел (spec 0003) + дерево контенту (catalog.gd)
    content/catalog.json  335 def; валідовано catalog.gd ↔ tests/catalog.test.js
    tests/                headless-сьюти Godot (run_*.gd)
  GDD_BOOK/            інтерактивний GDD; правда — gdd.json
  tests/               Node-тести (node --test): sim-ядро, catalog, progression
  specs/               специфікації фіч (0001…0008)
  docs/                довідники: catalog.md, mechanics-status.md, ux/
  .github/workflows/   CI: ci.yml (Node) + godot.yml (Godot headless)
  .claude/launch.json  dev-сервер прев'ю
```

## Godot-порт (форвардний рушій — нові фічі сюди; JS-версія — граний браузерний зріз, який несе пайплайн прогресії поверх спільного catalog.json)
- **Де:** `godot/` — повний порт на **Godot 4.7 (GDScript)**. Симуляція scene-free, детермінована (PCG32 із FNV-хешу координат), тестовна headless. Пиляр: «координати — це seed» (світ = чиста функція `lat/lon`). UI — **українською**.
- **Шари:**
  - `godot/scripts/` — `sim.gd` (детермінований сим: **фасад + стан + core loop**; публічний API незмінний — делегати), `session.gd` (оркестрація регіонів/подорожей/респавну), `social.gd`, `persistence.gd`, `world_gen.gd`, `world_view.gd` (custom-draw тайлмапи; роботи малюються окремо від рейдерів), `main.gd` (СТАРИЙ HUD-моноліт — заморожений референс, більше НЕ дефолтна сцена; виключений із gdlint).
  - `godot/scripts/sim/` — **доменні модулі живого сима** (декомпозиція моноліту): `threats.gd` (рейди кланів + **патрульні роботи** — лор постапокаліпсису, амбієнтний канал із seeded `threat_rng`, роботи = джерело брухту/компонентів; вороги/турелі/смерть/респавн), `environment.gd` (seed погодних/threat-стрімів, reroll погоди, indoor-BFS; дрібні гетери temp_at/light_at лишились публічним API sim.gd), `world_meta.gd` (капсули/інвайти spec 0002 + конвої). Патерн: **static func module(s, ...)** — модуль без стану, без preload sim.gd (без циклу); sim.gd тримає однорядкові делегати, тож session/тести/main.gd бачать той самий API.
  - `godot/scripts/kernel/` — **механічний кернел (spec 0003)**: `Def`/`Thing`+`ThingComp`/`StatWorker`+`StatPart`/`SimSystem`+`SystemRegistry`/`Balance`. «Додати механіку ніколи не редагує tick-loop».
  - `godot/content/catalog.json` + `godot/scripts/kernel/catalog.gd` — **дерево контенту** (повне: 335 def — ресурси/дослідження/будівлі/рецепти/предмети, від неоліту до космічного корабля) через seam `Defs.load_pack`. Чисті дані, RimWorld-канон + Factorio-ланцюги. Валідатор перевіряє ациклічність tech-DAG + **досяжність від сирих ресурсів** (нічого не «застрягло»). НЕ чіпає `data.gd`. Довідник — `docs/catalog.md`. Тести: `tests/catalog.test.js` (Node) + `godot/tests/run_catalog_tests.gd` (Godot).
  - **Research-ворота живого контенту (spec 0007 phase 2):** `data.gd` BUILDINGS/ITEMS несуть опційне `research: "<catalog-id>"`; `sim.research_unlocked` (мапа) живиться з `progression.research.unlocked` у `session.tick_research()`; `sim.try_build`/`craft_item` відмовляють до відкриття (🔒 + назва з `RESEARCH_LABEL`). Неолітичне ядро — без воріт. UI: `locked` у слайсах build/gear → 🔒 + disabled у BuildBar/GearPanel. Валідація воріт: `_t_research_gates` (run_tests) — кожен `research:`-id існує в catalog.json і `RESEARCH_LABEL` дзеркалить label (одруківка в id = назавжди замкнений контент). Заморожений `main.gd` не має research-UI — його `_start_game` відкриває всі ворота одразу.
  - **Відкритий склад (spec 0008 phase 2):** `sim.use_catalog` (дефолт OFF — шліфований зріз байт-у-байт; ставиться ДО `new_game`, не фліпається посеред сейва). ON = ключі `stock` — catalogue-ids через `data_bridge`. Шов ОДИН: `sim.res_key/res_amount/cost_keys/afford` — усі доступи до stock (sim, `sim/`-модулі, hud_model-слайси через `_amount`/`_afford` з fallback для test-fakes) ідуть крізь нього; жодного прямого `stock[...]` поза швом — **примусово tripwire'ом `_t_stock_seam`** (run_tests; поза корпусом: sim.gd-шов, hud_model-фолбек, kernel/ зі своїм world.stock, заморожений main.gd). Прапор **персистується** (`serialize_region` пише `use_catalog`, `load_region` відновлює — сейв не читається чужим словником). Тести — `_t_open_stock` (обидва стани прапора) + `_t_use_catalog_persist`. Phases 3–4 (каталожні build/craft панелі на живому симі, розширення ресурсної множини) чекають рішень §5 spec 0008.
  - `godot/scripts/kernel/progression.gd` — **пайплайн прогресії (spec 0007):** черга досліджень над `catalog.gd` + `ResearchState`; `available()`/`auto_next()`/`enqueue()`/`add_points()` (leftover перетікає в наступний проєкт), `unlocked_buildings/recipes/items()`, `tech_level()`, планувальник `research_path()`/`steps_to_unlock()`, `summary()`/`to_dict()`. Живий: `session.tick_research()` живить його від `research_bench` (data.gd); UI — `ResearchPanel` (LEFT dock); дієслова `enqueue_research`/`start_research`. Тести: `tests/progression.test.js` (Node, 12) + `godot/tests/run_progression_tests.gd` (Godot).
  - `godot/scripts/ui/` — **view-шар (spec 0005)**: 6 контрактів-дзеркал кернела — `Tokens`/`Theme`, `Panel`+`PanelRegistry`, `Overlay`+`OverlayRegistry`, `Widget`(бібліотека примітивів), `HudModel.snapshot()` (чистий ViewModel = аналог `Balance.assess()`), `FeedbackBus`, `InputVerbs`+`InputController`. `HudRoot` — тонкий контролер. **`newhud.tscn` — ДЕФОЛТНА сцена (playable)**: `world_input.gd` (event-половина граматики: кліки/WASD/зум/швидкість/generic hotkey-роутинг; чиста `decide_click`), `lifecycle.gd` (спавн-екран з координатами/GPS + екран смерті→респавн; ГОЧА: Control під CanvasLayer НЕ успадковує розмір в'юпорта — пінити TOP_LEFT + явний розмір, як hud_root), `world_panels.gd` (Логістика M / Капсула V / Соціальне O / Довідка H), `panels.gd` (+`BuildBarPanel` BAR-док 1–0, `GearPanel` I), `mechanics.gd` — реєстрація. `mount()` поважає `default_open`; хоткеї панелей НЕ мають перетинати §3-локовані ключі оверлеїв (R/T/L/P/G/Z/F/K) — Tech переїхав T→U, ResearchBrowser R→N; правило примусове tripwire-тестом у `run_ui_tests.gd` (+ унікальність хоткеїв панелі↔оверлеї). **Виняток M:** §3-слот «Логістична мапа (модалка)» тимчасово обслуговує `LogisticsPanel` (тому M нема в locked-списку tripwire'а); коли модалка-оверлей на M з'явиться, тест унікальності хоткеїв сам примусить панель з'їхати з ключа. **Одна правда на дію:** три catalog-браузери (B/C/N) пишуть у `catalog_sim` (форвард-модель, НЕ жива гра) — тому titled «Каталог · …», tag «демо», notice-рядок «пісочниця, не жива гра» і `default_open=false`; живі панелі (BuildBar/Research/Gear) — єдині default-open дії. Панелі емітять інтенти-verbs (`select_build`/`take_invite` — аліаси, бо ім'я sim-мутатора в панелі заборонене R9-tripwire'ом).
    - **Пайплайн контенту в HUD:** `ui/catalog_view.gd` — ViewModel каталогу (`Catalog.build_db()` → value-data зрізи: research-прогрес, buildable/craftable, next) → `ui/catalog_panels.gd` `TechPanel` (build-once+bind) → реєстр `mechanics.gd`. `HudModel.snapshot()` несе зріз `catalog`. Не чіпає `hud_root.gd` (R4). Тести — `run_ui_tests.gd` (R8/R2 + tripwires розширені на нові файли).
- **12 правил view-шару (spec 0005 §1, примусові через `run_ui_tests.gd`):** R1 односторонній потік (sim не імпортує ui) · R2 build-once-then-bind (без ребілду панелей) · R3 стилі лише через `Tokens`/`Theme` (жодних inline `Color(`/`StyleBoxFlat` поза `tokens.gd`/`theme.gd`) · R4 контролер не називає жодної механіки · R5 кожне число з `explain()` · R6 просторовий стан = `Overlay`, не список координат · R7 resize-safe анкери лише через `Widget.pin_*` · R8 слайси — тільки value-data · R9 sim-команди лише в роутері · R10 фідбек — один адаптер · R11 enum+іконка+число (не лише колір) · R12 keyboard-first + видимий детермінізм.
- **GDScript-гочі (обов'язково):** `:=` не виводить тип із `Variant` (доступ до поля `Dictionary`, `abs()`, нетипізований метод) → явний `: Type` або `absf/absi`; JSON round-trip перетворює `int→float`; `RefCounted` не збирає цикли → чисти крос-рефи в `_exit_tree()`, а Thing↔Comp рвуться через `Thing.detach()` / `CatalogSim.dispose()`/`dispose_shared()` (сим прунить destroyed-Things у `tick()`); лише seeded `RandomNumberGenerator`; **інклас+preload** (жодного top-level `class_name`, жодних autoload); анкери resize-safe. Інклас з іменем `Panel` **шедовить** нативний `Panel` — базу названо `Base`. **Статична типізація примусова:** кожен `var` у продуктових скриптах типізований (nullable/гетерогенні — явний `: Variant`); tripwire в `run_tests.gd` валить CI за нетипізоване оголошення; `untyped_declaration=1` у `project.godot` підсвічує в редакторі (headless аналайзер-ворнінги НЕ друкує — не покладайся).
- **Тести (headless):** `test.cmd` у корені ганяє сьюти — `run_tests` (198, вкл. tripwires «жодного глобального randf/randi», «жодного нетипізованого var» і «жодного stock[...] поза швом», детермінізм рейдів + патрулів, контент-пак, research-ворота + валідація gate-id проти каталогу, персистенс use_catalog), `run_kernel_tests` (242), `run_catalog_tests` (70, вкл. lifecycle-sweep), `run_progression_tests` (42), `run_ui_tests` (135, spec 0005 + граматика world_input + §3-hotkey-контракт), `run_smoke` (8). Усі сьюти виходять **без ObjectDB-ліків** (нові Things у тестах — detach/dispose в кінці тесту). CI (`godot.yml`) грепає leak-warning у кожному сьюті + окремий job **gdlint** (gdtoolkit 4.x; конфіг `gdlintrc` у корені кодифікує конвенції — RimWorld-канонні `Sub_Class` імена, max-line 200, без class-definitions-order; заморожений `scripts/main.gd` і `godot/tests/` поза скоупом). Локальний гейт — `.pre-commit-config.yaml` (`pip install pre-commit && pre-commit install`); gdformat свідомо не увімкнений (масовий реформат — окремий крок). Плюс `npm test` (Node) ганяє детерміноване sim-ядро + валідацію `catalog.json`. Годо-екзе: Windows — `%LOCALAPPDATA%\GodotPortable\Godot_v4.7-stable_win64[_console].exe`; Linux/CI — офіційний `Godot_v4.7-stable_linux.x86_64` (реліз-zip із GitHub, як у `godot.yml`). Приклад: `Godot_console.exe --headless --path godot -s res://tests/run_ui_tests.gd`.
- **Скриншот нового HUD:** `Godot_console.exe --path godot res://newhud.tscn -- newhud shot` (віконно, не headless) → `godot/newhud_shot.png`.
- **Web-експорт (клік-і-грай):** `Godot_console.exe --headless --path godot --export-release "Web" build/web/index.html` → `godot/build/web/` (gitignored); на свіжому checkout спершу `--import`. Пресет `godot/export_presets.cfg`: **threads OFF** (без COOP/COEP — працює на будь-якому статичному хостингу; рендер веб-дефолтний gl_compatibility). **CI білдить сам:** job `godot-web-build` у `godot.yml` — артефакт `web-build` (готовий клік-і-грай зі README.txt) з кожного пушу; темплейти кешуються між ранами. Шаблони локально: Windows — `%APPDATA%\Godot\export_templates\4.7.stable\web_*.zip` (тягнуться частково з 1.28ГБ tpz HTTP-Range-скриптом — не качай весь); Linux — `~/.local/share/godot/export_templates/4.7.stable/` (range-запити до GitHub-CDN ненадійні — качай tpz цілком транзитно і бери лише `templates/web_*`, як робить CI-job). Локальне прев'ю: dev-сервер `godot-web` (порт 8792, `.claude/launch.json`); ГОЧА: прихована вкладка прев'ю заморожує rAF → одно-тредовий web-білд Godot не рендерить і canvas лишається 0×0 — верифікуй у ВИДИМІЙ вкладці (claude-in-chrome). **Емодзі-іконки у веб-білді ПРАЦЮЮТЬ:** монохромний NotoEmoji (OFL, `godot/assets/fonts/`) підвішений фолбеком через `theme.gd` — `Theme.default_font` = FontVariation(base=вбудований, fallbacks=[NotoEmoji]) + `ThemeDB.fallback_font` для custom-draw; сам лише `ThemeDB.fallback_font` НЕ працює (дефолтна тема Godot несе власний шрифт і перехоплює lookup — десктоп маскує це системними шрифтами). Завантаження шрифту двошляхове: `ResourceLoader` (експорт пакує ttf як imported-ресурс заремапом — сирого шляху в PCK нема) АБО `FileAccess`+`load_dynamic_font` (свіжий checkout / headless-тести без import-кешу).
- **UX-контракт:** `docs/ux/design-system.md` (зафіксовані токени §1 / layout §2 / оверлеї §3 / віджети §4 / граматика §5) + `docs/ux/hud.html` (рендер-макет, джерело parity). Специфікації: `specs/0003` (кернел), `specs/0004` (каталог механік+UX), `specs/0005` (view-архітектура).

## Конвенції
- **Іменування:** усе публічне вішається на `RW.*`; стан гри — `G`; тайл-індекс — `i = y*N + x`.
- **Стиль:** 2 пробіли; `"use strict"` у кожному IIFE-модулі; без ES-модулів (`import/export`) — лишаємось на classic scripts заради no-build.
- **Патерни:** симуляція детермінована від seed; логіку тримай по змозі **без залежності від DOM/canvas** (щоб була тестовна в Node).
- **Чого НЕ робити:** не додавати збірку/бандлер/фреймворк без обговорення; не ламати порядок підключення скриптів; не змішувати рендер із симуляцією; жодних мережевих викликів окрім Overpass без узгодження.

## Команди
- **Запуск гри (dev):** `cd game && python -m http.server 8765` → http://localhost:8765
- **Запуск GDD:** `python "C:\Users\gregn\.claude\skills\gdd_build\scripts\serve.py" "O:\realworld\GDD_BOOK"`
- **Тести:** `npm test` (Node `node --test` — детерміноване sim-ядро + валідація `catalog.json`/пайплайну прогресії); headless-сьюти Godot — `test.cmd` у корені (перелік — у розділі «Godot-порт» вище). Обидва набори ганяються в CI (`.github/workflows/ci.yml` + `godot.yml`).
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
