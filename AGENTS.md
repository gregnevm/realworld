# AGENTS.md — RealWorld

> Машиночитний контекст проєкту для AI-агентів (Claude Code, Cursor, Codex, Copilot, Gemini CLI, Windsurf). Тримай актуальним: застарілий AGENTS.md гірший за відсутній.
> last_reviewed: 2026-11

## Огляд
- **Що це:** RealWorld — survival-MMORPG із симуляційною глибиною RimWorld на **картах зі справжньої географії (OSM/GPS)**; один глибоко симульований персонаж, persistent-світ, логістика конвоями. **Лише телефон (OD-124, 2026-11-09): жодних веб-версій — продукт = Android APK (Godot).** Репозиторій містить дизайн-документ і граний прототип.
- **Стейдж:** prototype (Фаза 0 — одиночний вертикальний зріз).
- **Джерело істини рішень власника:** `docs/design/decisions.md` (OD-1…93) і візія капсул/Орбіти/клонів — `docs/design/capsules.md`; спеки кроку 1 — `specs/0010`–`0012`; RealGPS-шар присутності (шви кроку 2) — `specs/0013`; ревізія — `docs/design/revision-2026-11.md`. Стовпи S1–S3 approved; зріз поетапний (OD-37): крок 1 соло+капсула+Орбіта, крок 2 мультиплеєр.
- **Головні домени/модулі:**
  - `godot/` — єдиний рушій і продукт (Godot 4.7 → Android APK). Веб-зріз `game/` ВИДАЛЕНО (OD-124; історія — у git).
  - `GDD_BOOK/` — інтерактивний Game Design Document; джерело істини дизайну — `GDD_BOOK/gdd.json`.
  - `.claude/launch.json` — конфіг dev-сервера прев'ю (`realworld-game`, порт 8766).

## Стек
- **Мова(и):** GDScript (Godot 4.7); Node 22 — лише тулінг/тести.
- **Фреймворки/рантайм:** Godot 4.7, цільова платформа — Android (телефон). Web-експорт не підтримується.
- **Сховище даних:** `localStorage` (збереження гри); дизайн — `gdd.json`.
- **Зовнішні залежності/API:** OpenStreetMap **Overpass API** (генерація карти з реальних координат) з детермінованим процедурним fallback. Жодних npm-залежностей у рантаймі. Dev-only: Gemini image API (Nano Banana) для `tools/gen-art.mjs`, не в рантаймі гри; постобробка — Python Pillow + numpy.

## Архітектура
- Sim scene-free, детермінований (`godot/scripts/sim/`, `kernel/`), view-шар — `godot/scripts/ui/`; деталі — `docs/agents/godot-sim.md`, `docs/agents/godot-ui-tests-build.md`.
- World-gen: `lat/lon` → детермінований seed (PCG32) → процедурна карта; реальна геометрія OSM — збагачення.
- GDD: `GDD_BOOK/` (документація, не гра); фронтенд читає `gdd.json` через HTTP.

## Структура файлів
```
realworld/
  AGENTS.md            ← цей файл (контекст для агентів)
  godot/               порт у Godot 4.7 — форвардний рушій (деталі в розділі «Godot-порт»)
    scripts/kernel/       механічний кернел (spec 0003) + дерево контенту (catalog.gd)
    scripts/goals.gd      онбординг-ланцюг «Цілі» (чисті перевірки стану; липке виконання в session)
    content/catalog.json  335 def; валідовано catalog.gd ↔ tests/catalog.test.js (`catalog_data.js`/JS-дзеркало видалено)
    tests/                headless-сьюти Godot (run_*.gd)
  GDD_BOOK/            інтерактивний GDD; правда — gdd.json
  tests/               Node-тести (node --test): sim-ядро (вкл. drag-build/двері/ремонт/рейд-спавн/смерть), catalog, progression, process (гейт процесу)
  tools/               lint.mjs (secret-scan + Godot-3 tripwire + sim без годинника) · gen-art.mjs + art/ (арт-пайплайн Nano Banana) · process/ (PR-гейт check-pr.mjs, звіт report.mjs, Godot-3 tripwire — lib.mjs)
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

## Godot (єдиний рушій; веб-зріз видалено, OD-124)
- **Де:** `godot/` — повний порт на **Godot 4.7 (GDScript)**. Симуляція scene-free, детермінована (PCG32 із FNV-хешу координат), тестовна headless. Пиляр: «координати — це seed» (світ = чиста функція `lat/lon`). UI — **українською**.
- **Шари (sim/kernel/net/persistence/ui, живі системи):** детально — `docs/agents/godot-sim.md`. Ключове: sim scene-free й детермінований; доменні модулі `godot/scripts/sim/` — `static func module(s, ...)` без стану; кернел `godot/scripts/kernel/` — «додати механіку ніколи не редагує tick-loop»; `Persistence.world_hash` — хребет детермінізму; stock/building-шви (`res_key`, `building_def`) — ніяких прямих `stock[...]`; прапори `use_catalog`/`use_inventory` ставляться ДО `new_game`.
- **View-шар, GDScript-гочі, тести, скриншоти, APK:** `docs/agents/godot-ui-tests-build.md`. Мінімум: 12 правил view-шару (R1–R12) примусові через `run_ui_tests.gd`; кожен `var` типізований; `RandomNumberGenerator` лише seeded; тести — `test.cmd`; Godot-HUD скриншот — `Godot --path godot res://newhud.tscn -- newhud shot`.
- **UX-контракт:** `docs/ux/design-system.md` (зафіксовані токени §1 / layout §2 / оверлеї §3 / віджети §4 / граматика §5) + `docs/ux/hud.html` (рендер-макет, джерело parity). Специфікації: `specs/0003` (кернел), `specs/0004` (каталог механік+UX), `specs/0005` (view-архітектура).

## Арт-пайплайн (gen-art, Nano Banana)
- **Лор:** ШІ-постапокаліпсис (OD-6, 2026-11-05) — машини повстали, патрульні роботи, брухт замість мародерства; біоми багаторівневі (макробіом → кластер), є фауна й флора (OD-6).
- **Деталі:** `docs/agents/art-pipeline.md`. Мінімум: `node tools/gen-art.mjs sync` синхронізує маніфест із каталогом; ключ лише в `.env.local`/`$GEMINI_API_KEY`; не міняти модель посеред серії; арт — лише для механік, що пройшли G0–G1 (P4).

## Конвенції
- **Іменування:** GDScript-конвенції — `docs/agents/godot-sim.md`; статична типізація, лише seeded RNG.
- **Стиль:** 2 пробіли; `"use strict"` у кожному IIFE-модулі; без ES-модулів (`import/export`) — лишаємось на classic scripts заради no-build.
- **Патерни:** симуляція детермінована від seed; логіку тримай по змозі **без залежності від DOM/canvas** (щоб була тестовна в Node).
- **Чого НЕ робити:** не додавати збірку/бандлер/фреймворк без обговорення; не ламати порядок підключення скриптів; не змішувати рендер із симуляцією; жодних мережевих викликів окрім Overpass без узгодження (виняток — dev-тулінг `tools/gen-art.mjs` → Gemini, узгоджено 2026-11).

## Команди
- **Запуск гри (dev):** `godot --path godot` (десктоп-редактор лише для розробки) або APK з CI на телефоні.
- **Запуск GDD:** `python "C:\Users\gregn\.claude\skills\gdd_build\scripts\serve.py" "O:\realworld\GDD_BOOK"`
- **Тести:** `npm test` (Node `node --test` — детерміноване sim-ядро + валідація `catalog.json`/пайплайну прогресії + чиста половина арт-пайплайну `tests/art.test.js`); `npm run lint` (tools/lint.mjs: secret-scan, без Godot-3 API у `.gd`, без годинника/системного RNG у sim-корпусі `.gd` — spec 0012 REQ-10); `npm run smoke` (tools/smoke.mjs: Playwright + Chromium — спавн → drag-build → вибір/демонтаж → модалки → дослідження → рейд → смерть → reload/continue; падає на будь-якому console.error; у CI — job `browser-smoke` з артефактом скриншотів); headless-сьюти Godot — `test.cmd` у корені (перелік — у розділі «Godot-порт» вище). Обидва набори ганяються в CI (`.github/workflows/ci.yml` + `godot.yml`).
- **Білд/деплой:** Android APK через CI (`godot.yml` → `publish.yml`); веб-хостингу немає.
- **Версії збірок (Godot APK):** штамп `godot/scripts/build_info.gd` ставить CI; видно в ☰-меню. main публікується у prerelease `main-latest` (`.github/workflows/publish.yml`). Капсула в збірках УВІМК за замовчуванням (OD-114, опт-аут `nocapsule`). Деталі — `docs/agents/godot-ui-tests-build.md`.

## Ключові рішення (ADR-лайт)
- **Vanilla JS, no-build** — миттєва ітерація, працює будь-де, ноль тулчейн-боргу на стадії прототипу. Альтернативу (Vite/TS) відкинули як передчасну.
- **Процедурний fallback для OSM** — гра грається офлайн і детермінована; реальна географія — це збагачення, не залежність.
- **Лише телефон (OD-124, 2026-11-09)** — веб-версії (JS-зріз `game/`, Godot Web-експорт, Pages) видалено; єдиний продукт — Android APK з Godot.
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
| Власник каже «плейтест» | білд (APK з CI) + картка 5 задач + бланк; після — його нотатки → журнал `docs/process/playtests/`, тріаж, rework-log |
| «мердж» | перевір CI зелений на поточному head → squash-merge |
| Дата «Наступна LLM Week» у `docs/process/automation.md` минула | нагадай власнику одним рядком і запропонуй список повторів |

Межі: стовпи/scope/модель вводу/баланс/ШІ-арт вирішує лише власник (P1, `docs/design/decisions.md`); без доказу нема «готово» (P2); фіча без стовпа S1–S3 — «заморожено» (P7); нова спека — з `specs/_TEMPLATE.md` (стабільні REQ-ID).

## Правила для агента
- Перед зміною — звірся з цим файлом і структурою; не вигадуй конвенції.
- Зміни тримай у скоупі задачі; не тягни неузгоджені залежності.
- **Верифікація:** Godot-HUD — `xvfb-run -a Godot --path godot res://newhud.tscn -- newhud shot` → `godot/newhud_shot.png`.
- Секрети/ключі — ніколи в код.
- Великі рефактори/міграції (особливо перехід на клієнт-сервер для Фази 1) — спершу ADR + спека й узгодження, не одразу код.
