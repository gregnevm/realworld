# AGENTS.md — RealWorld

> Машиночитний контекст проєкту для AI-агентів (Claude Code, Cursor, Codex, Copilot, Gemini CLI, Windsurf). Тримай актуальним: застарілий AGENTS.md гірший за відсутній.
> last_reviewed: 2026-11

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
- **Зовнішні залежності/API:** OpenStreetMap **Overpass API** (генерація карти з реальних координат) з детермінованим процедурним fallback. Жодних npm-залежностей у рантаймі. Dev-only: Gemini image API (Nano Banana) для `tools/gen-art.mjs`, не в рантаймі гри; постобробка — Python Pillow + numpy.

## Архітектура
- Гра — єдиний глобальний неймспейс **`RW`**, розкладений по файлах у `game/js/`, які підключаються **у фіксованому порядку** в `game/index.html`: `util → worldgen → entities → catalog_data → progression → render → logistics → ui → input → game`. `game.js` стартує на `DOMContentLoaded`.
- **Веб-зріз (прогресія, UX-граматика, сідований RNG):** `docs/agents/web-slice.md`. Заморожений референс; `G.rng` сідований, жодного `Math.random` у sim-шляхах.
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
      render.js        малювання канвасу, камера (плавне стеження + зум), день/ніч, FX-текст, стрілки загроз
      logistics.js     конвої між реальними регіонами
      ui.js            DOM-HUD, build bar, інспектор/картка вибору, мінімапа, модалки (меню/журнал/смерть), спавн із прев'ю
      input.js         граматика вводу: клік/drag-build/вибір, колесо-зум, pinch, хоткеї
      game.js          стан, симуляція, бій, рейди, цикл, save/load
  godot/               порт у Godot 4.7 — форвардний рушій (деталі в розділі «Godot-порт»)
    scripts/kernel/       механічний кернел (spec 0003) + дерево контенту (catalog.gd)
    scripts/goals.gd      онбординг-ланцюг «Цілі» (чисті перевірки стану; липке виконання в session)
    content/catalog.json  335 def; валідовано catalog.gd ↔ tests/catalog.test.js
    tests/                headless-сьюти Godot (run_*.gd)
  GDD_BOOK/            інтерактивний GDD; правда — gdd.json
  tests/               Node-тести (node --test): sim-ядро (вкл. drag-build/двері/ремонт/рейд-спавн/смерть), catalog, progression, process (гейт процесу)
  tools/               sync-catalog.mjs · lint.mjs (контракт no-build + secret-scan) · smoke.mjs (Playwright-прохід гри, CI job browser-smoke) · gen-art.mjs + art/ (арт-пайплайн Nano Banana) · process/ (PR-гейт check-pr.mjs, звіт report.mjs, Godot-3 tripwire — lib.mjs)
  art/                 style.md (арт-біблія) · palette.json · refs/ (якорі стилю) · manifest.json (виводиться з catalog.json) · out/ (gitignored кандидати)
  .claude/skills/gen-art/  скіл генерації арту (/gen-art)
  .claude/skills/gamedev/  шлюз цілісності гри (/gamedev): ворота 0–6, правило доказу, тест Ніколая, FTUE — вхід для будь-якої механіки/фічі/плейтесту
  .claude/skills/godot-game-uiux-designer/  цикл UX/UI (аудит кадрами → код → анімація → кадр після)
  .claude/agents/      ролі процесу: designer · developer · integrity (вердикти воріт, лише читання) · qa-adversary (тести від REQ) · fresh-eyes (тест Ніколая, лише кадри)
  specs/               специфікації фіч (0001…0009) + _TEMPLATE.md (REQ-ID)
  docs/                довідники: catalog.md, mechanics-status.md, rimworld-reference.md, ux/
  docs/process/        процес розробки: README (принципи P1–P10, цикл, ролі, ритми) · game-design (метод, реєстр D/M) · automation (драбина доказів, радар, LLM Week) · playtest · rework-log · ai-use-log
  docs/design/         стан дизайну — рішення ВЛАСНИКА: pillars.md · scope.md · decisions.md (OD-n)
  .github/workflows/   CI: ci.yml (Node) + godot.yml (Godot headless) + process.yml (PR-гейт + звіт процесу) + mutation.yml (gdmutant, trial, не блокує)
  .github/pull_request_template.md  контракт PR-гейта (інтент · тип · стовп · підстава · докази · що прибрано)
  .claude/launch.json  dev-сервер прев'ю
```

## Godot-порт (форвардний рушій — нові фічі сюди; JS-версія — граний браузерний зріз, який несе пайплайн прогресії поверх спільного catalog.json)
- **Де:** `godot/` — повний порт на **Godot 4.7 (GDScript)**. Симуляція scene-free, детермінована (PCG32 із FNV-хешу координат), тестовна headless. Пиляр: «координати — це seed» (світ = чиста функція `lat/lon`). UI — **українською**.
- **Шари (sim/kernel/net/persistence/ui, живі системи):** детально — `docs/agents/godot-sim.md`. Ключове: sim scene-free й детермінований; доменні модулі `godot/scripts/sim/` — `static func module(s, ...)` без стану; кернел `godot/scripts/kernel/` — «додати механіку ніколи не редагує tick-loop»; `Persistence.world_hash` — хребет детермінізму; stock/building-шви (`res_key`, `building_def`) — ніяких прямих `stock[...]`; прапори `use_catalog`/`use_inventory` ставляться ДО `new_game`.
- **View-шар, GDScript-гочі, тести, скриншоти, APK, web-експорт:** `docs/agents/godot-ui-tests-build.md`. Мінімум: 12 правил view-шару (R1–R12) примусові через `run_ui_tests.gd`; кожен `var` типізований; `RandomNumberGenerator` лише seeded; тести — `test.cmd`; Godot-HUD скриншот — `Godot --path godot res://newhud.tscn -- newhud shot`.
- **UX-контракт:** `docs/ux/design-system.md` (зафіксовані токени §1 / layout §2 / оверлеї §3 / віджети §4 / граматика §5) + `docs/ux/hud.html` (рендер-макет, джерело parity). Специфікації: `specs/0003` (кернел), `specs/0004` (каталог механік+UX), `specs/0005` (view-архітектура).

## Арт-пайплайн (gen-art, Nano Banana)
- **Лор:** ШІ-постапокаліпсис (OD-6, 2026-11-05) — машини повстали, патрульні роботи, брухт замість мародерства; біоми багаторівневі (макробіом → кластер), є фауна й флора (OD-6).
- **Деталі:** `docs/agents/art-pipeline.md`. Мінімум: `node tools/gen-art.mjs sync` синхронізує маніфест із каталогом; ключ лише в `.env.local`/`$GEMINI_API_KEY`; не міняти модель посеред серії; арт — лише для механік, що пройшли G0–G1 (P4).

## Конвенції
- **Іменування:** усе публічне вішається на `RW.*`; стан гри — `G`; тайл-індекс — `i = y*N + x`.
- **Стиль:** 2 пробіли; `"use strict"` у кожному IIFE-модулі; без ES-модулів (`import/export`) — лишаємось на classic scripts заради no-build.
- **Патерни:** симуляція детермінована від seed; логіку тримай по змозі **без залежності від DOM/canvas** (щоб була тестовна в Node).
- **Чого НЕ робити:** не додавати збірку/бандлер/фреймворк без обговорення; не ламати порядок підключення скриптів; не змішувати рендер із симуляцією; жодних мережевих викликів окрім Overpass без узгодження (виняток — dev-тулінг `tools/gen-art.mjs` → Gemini, узгоджено 2026-11).

## Команди
- **Запуск гри (dev):** `cd game && python -m http.server 8765` → http://localhost:8765
- **Запуск GDD:** `python "C:\Users\gregn\.claude\skills\gdd_build\scripts\serve.py" "O:\realworld\GDD_BOOK"`
- **Тести:** `npm test` (Node `node --test` — детерміноване sim-ядро + валідація `catalog.json`/пайплайну прогресії + чиста половина арт-пайплайну `tests/art.test.js`); `npm run lint` (tools/lint.mjs: порядок скриптів = контракт, strict-IIFE, без ES-модулів, без `Math.random` у sim-файлах, без Godot-3 API у `.gd`); `npm run smoke` (tools/smoke.mjs: Playwright + Chromium — спавн → drag-build → вибір/демонтаж → модалки → дослідження → рейд → смерть → reload/continue; падає на будь-якому console.error; у CI — job `browser-smoke` з артефактом скриншотів); headless-сьюти Godot — `test.cmd` у корені (перелік — у розділі «Godot-порт» вище). Обидва набори ганяються в CI (`.github/workflows/ci.yml` + `godot.yml`).
- **Білд/деплой:** білду немає; статичний хостинг (GitHub Pages / Railway / itch.io).

## Ключові рішення (ADR-лайт)
- **Vanilla JS, no-build** — миттєва ітерація, працює будь-де, ноль тулчейн-боргу на стадії прототипу. Альтернативу (Vite/TS) відкинули як передчасну.
- **Процедурний fallback для OSM** — гра грається офлайн і детермінована; реальна географія — це збагачення, не залежність.
- **Глобальний `RW` + classic scripts** — простота; ціна — дисципліна щодо порядку підключення (зафіксована вище).
- **Один персонаж + MMO** — це survival-RPG із ДНК RimWorld, а не колонія-сим (деталі — `GDD_BOOK/gdd.json`).
- **Фаза 1: authoritative-сервер = Godot headless (spec 0006, option A, затверджено 2026-07-05)** — той самий тестований кернел і є сервером; Node-порт — лише fallback за виміряної нестачі RAM/пропускної здатності (дублювання сима = ризик дрейфу). Межа авторитету, wire-шви (`HudModel.snapshot`/verbs/`social.new_graph`/hash-chain/`ClimateProvider`) і доля `game/` (заморожений рендер-прототип, не другий сим) — у спеці. Детермінізм-хребет: `Persistence.world_hash` + `run_determinism_tests`.

## Процес розробки (docs/process/README.md) — автопілот
Власник робить лише 3 речі: **каже, чого хоче · тисне кнопки на твої питання · мерджить PR**. Усе інше — твоя робота: ніколи не проси власника редагувати файли процесу, кликати ролі чи запускати звіти. Тригери нижче спрацьовують **без нагадування**:

| Подія | Що робиш сам |
|---|---|
| Старт сесії, а також після компактації контексту | `npm run process -- --brief` — стан, відкриті OD, попередження; врахуй їх у плані |
| Будь-який ігровий запит (механіка, фіча, баг, UI, баланс) | `/gamedev`: стовп → спека (`designer`) → код + докази → тести від REQ (`qa-adversary`) → кадри (`fresh-eyes`) → вердикт (`integrity`) → PR; власнику — PR + ≤ 4 питання кнопками |
| Робота впирається в рішення власника (стовп, scope, ввід, баланс, ШІ-арт, великий рефактор) або власник каже «вирішимо» | `/decide`: питання кнопками з рекомендацією → записуєш вибір у `docs/design/` → PR. Без відповіді OD лишається `open` |
| Створено PR | шаблон `.github/pull_request_template.md` (CI `process.yml` блокує без доказів/стовпа/підстави); стежиш за CI і правиш сам |
| Власник виправив твій результат (чат, рев'ю, плейтест) | рядок у `docs/process/rework-log.md` у найближчому PR |
| Власник каже «плейтест» | білд (APK/web з CI) + картка 5 задач + бланк; після — його нотатки → журнал `docs/process/playtests/`, тріаж, rework-log |
| «мердж» | перевір CI зелений на поточному head → squash-merge |
| Дата «Наступна LLM Week» у `docs/process/automation.md` минула | нагадай власнику одним рядком і запропонуй список повторів |

Межі: стовпи/scope/модель вводу/баланс/ШІ-арт вирішує лише власник (P1, `docs/design/decisions.md`); без доказу нема «готово» (P2); фіча без стовпа S1–S3 — «заморожено» (P7); нова спека — з `specs/_TEMPLATE.md` (стабільні REQ-ID).

## Правила для агента
- Перед зміною — звірся з цим файлом і структурою; не вигадуй конвенції.
- Зміни тримай у скоупі задачі; не тягни неузгоджені залежності.
- **Верифікація:** веб-зріз — `npm run smoke` (або власний Playwright-скрипт за його зразком: старт гри, `G.speed=0`, цикл `RW.update(G,dt)`, читай стан, `page.screenshot`); у середовищах без Playwright — `preview_eval` + `canvas.toDataURL` (див. memory `browser-game-canvas-screenshot`). Godot-HUD — `xvfb-run -a Godot --path godot res://newhud.tscn -- newhud shot` → `godot/newhud_shot.png`.
- Секрети/ключі — ніколи в код.
- Великі рефактори/міграції (особливо перехід на клієнт-сервер для Фази 1) — спершу ADR + спека й узгодження, не одразу код.
