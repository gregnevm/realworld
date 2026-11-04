---
name: gen-art
description: Генерує ігрові асети RealWorld (спрайти будівель/нод, актори, іконки ресурсів/предметів/досліджень, тайли terrain, UI-піктограми) через Nano Banana (Gemini image API) в єдиному концептуальному стилі, з автоматичним маніфестом із catalog.json. Тригери — /gen-art, «згенеруй спрайт/іконку/тайл/арт», «намалюй асет», «онови арт для <id>», «ось ключ Gemini/nanobanana», нові def у catalog.json без арту.
---

# gen-art — концептуальний арт-пайплайн

Скоуп пайплайна: `art/style.md` (стиль-гайд, додається до КОЖНОГО промпту) → `art/refs/*.png` (затверджені якорі стилю, ≤3 йдуть image-input у кожен запит) → `art/manifest.json` (що малювати; виводиться з `godot/content/catalog.json`) → `tools/gen-art.mjs` (API) → `tools/art/post.py` (chroma-key → alpha, trim, resize, снеп до `art/palette.json`) → кандидати в `art/out/` (gitignored) → `approve` → `godot/assets/gen/<kind>/<id>.png` (комітиться).

## 0. Ключ (одноденний, від користувача)
- Користувач дає ключ у чаті → одразу: `printf %s '<KEY>' | node tools/gen-art.mjs key`. Це запише `.env.local` (0600, gitignored), перевірить `git check-ignore` і валідність ключа на API.
- НІКОЛИ не друкуй ключ (маскується `AIza…xxxx`), не клади його в код/коміт/PR/meta. Перед комітом `npm run lint` (secret-scan валить CI на `AIza…`).
- Exit 2 або «ключ недійсний або прострочений» → попроси новий ключ. НЕ ретрай.
- Ключ живе лише в контейнері сесії. Новій сесії потрібен новий `key`.

## 1. Цикл
1. `node tools/gen-art.mjs sync`: підтягує нові def з каталогу. Людські правки `subject/status/notes` зберігаються.
2. **Якорі першими.** Якщо `art/refs/` порожній: `gen --only ref_world,ref_ground --n 3` → переглянь (Read PNG) → `approve ref_world@vN` (і ground). Без якорів стиль між батчами пливе.
3. Батч: `node tools/gen-art.mjs gen --kind icon --prefix res_ --limit 8 --n 2` (дефолтний ліміт 12 — захист від спалення квоти).
   Перед дорогим батчем можна `--dry`: друкує промпти без API.
4. Переглянь кандидати (`art/out/<kind>/<id>/vN.png`, Read). Відбраковуй, якщо:
   - фон не зник (магента лишилась) або обрізано об'єкт;
   - ракурс не top-down 3/4 (тайли — строго згори);
   - є текст/літери; палітра чи контур не як у refs;
   - предмет не той (перевір `label` у маніфесті).
5. Погане → додай рядок `notes` у маніфест (напр. `"notes": "ручка коротша, без металу"`) → `gen --only <id>`. `style.md` НЕ правиш заради одного асета.
6. Добре → `node tools/gen-art.mjs approve <id>@vN`. Approved не перегенеровується без `--only <id> --force`.
7. `node tools/gen-art.mjs status` → підсумок. Коміть `godot/assets/gen/**` + `art/manifest.json` (+ `art/refs/**` для якорів).

## 2. Kinds (рамка задана в `tools/art/lib.mjs` KINDS; не дублюй у subject)
| kind | що | розмір | фон |
|---|---|---|---|
| ref | лист-якір стилю | raw (~1024) | темний slate |
| sprite | будівлі (`bld_*`), ресурсні ноди (`node_*`) | 128 | магента→alpha |
| actor | герой, рейдер, патрульний робот | 128 | магента→alpha |
| icon | ресурси `res_*`, предмети `item_*`, дослідження `rsch_*` | 128 | магента→alpha |
| tile | terrain `tile_*` (9 типів world_gen) | 64 | безшовний |
| ui | HUD-піктограми (додавай рядки вручну, `id: ui_*`) | 64 | магента→alpha |

Епоха (`eraOf(tier)`) додається автоматично з research-tier, тож неолітична сокира й plasteel-турель лишаються в одному світі.

## 3. Правила
- Оригінальний IP: жодних «in the style of <гра/студія/художник>», брендів, чужих персонажів.
- Модель: дефолт `gemini-2.5-flash-image` (дешевий). Для серій, де важлива консистентність, `--model gemini-3-pro-image-preview`.
- Підключення асетів у рендер Godot (`world_view.gd`/HUD) — окрема задача зі своїми тестами (R3/R11 view-шару). Цей скіл лише виробляє асети.
