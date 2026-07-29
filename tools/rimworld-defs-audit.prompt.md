# Воркер: аудит констант RimWorld із Defs

> Запускати **з кореня інсталяції RimWorld** (там, де лежить тека `Data/`).
> Результат — `rimworld-defs-audit.md`, який вливається в `docs/rimworld-reference.md` нашого репо.
> Промпт самодостатній: воркер не має доступу до нашого репозиторію.

---

Ти працюєш у теці інсталяції гри RimWorld. Твоя задача — витягти **точні константи з XML-дефів
гри** й видати звіт, придатний для прямої вставки в довідник дизайн-канону.

## Правила — важливіші за обсяг

1. **Жодного числа без доказу.** Кожне число супроводжується: шлях до файлу, `defName`, дослівний
   XML-фрагмент. Число без фрагмента — брак, а не результат.
2. **Не вгадуй і не добирай з пам'яті.** Значна частина констант RimWorld живе в C#
   (`Assembly-CSharp.dll`), а не в XML. Якщо не знайшов у XML — пиши
   `НЕМАЄ В XML (ймовірно C#)` і йди далі. **Порожній результат — валідний і цінний.**
3. **Твої знання про RimWorld можуть бути з іншої версії.** Джерело істини — тільки файли в цій
   теці. Якщо файл суперечить твоїй пам'яті — правий файл.
4. **Тільки читання.** Не змінюй, не переміщуй, не видаляй жодного файлу гри.
5. Не намагайся декомпілювати `.dll`. Якщо константи там — просто зафіксуй це.

## Крок 0 — зафіксуй версію

- Прочитай `Version.txt` у корені (або `Data/Core/About/About.xml`). Запиши **точний білд** —
  без цього весь звіт нічого не вартий, бо числа різняться між версіями.
- Перелічи наявні DLC-теки в `Data/` (`Royalty`, `Ideology`, `Biotech`, `Anomaly`).
- **Усе шукай у `Data/Core/`.** DLC чіпай, лише якщо в Core чогось немає — і тоді явно позначай.

> Якщо `Data/` не в поточній теці — знайди її (`find . -maxdepth 3 -type d -name Defs`).
> На macOS вона всередині `RimWorldMac.app/`.

## Крок 1 — розвідка

Спершу подивись, які категорії дефів реально є в **цій** версії:

```
ls Data/Core/Defs/
```

Не припускай структуру з пам'яті — вона мінялась між версіями. Далі шукай по фактичних теках.

## Крок 2 — цільовий список

Порядок = пріоритет. Якщо часу/контексту обмаль, роби згори вниз і чесно познач, де зупинився.

### A. Пріоритет 1 — те, заради чого все затівалось

| # | Що знайти | Де шукати | Ключові поля |
|:--:|---|---|---|
| A1 | **Адаптація складності** | `Defs/DifficultyDefs/Difficulties.xml` | `adaptationEffectFactor`, `adaptationGrowthRateFactorOverZero`, `threatScale`, `allowBigThreats`, `maxThreatBigIntervalDays` — **випиши ВЕСЬ дефолтний деф цілком** |
| A2 | **Каденція подій (MTB)** | `Defs/StorytellerDefs/` | усі `StorytellerComp_*`: `mtbDays`, `minDaysPassed`, `minSpacingDays`, `randomBonus`, `categoryWeights`. Окремо для Cassandra / Phoebe / Randy |
| A3 | **Пороги інцидентів** | `Defs/IncidentDefs/` | `baseChance`, `minThreatPoints`, `minRefireDays`, `minPopulation` для рейдів і хвороб |
| A4 | **Вартість пересування по світу** | `Defs/RoadDefs/`, `Defs/BiomeDefs/` | `movementCostMultiplier` (дороги), `movementDifficulty` (біоми) — **повні таблиці, усі значення** |
| A5 | **Комфортна температура** | `Defs/StatDefs/` | `ComfyTemperatureMin`, `ComfyTemperatureMax`: `defaultBaseValue` + `postProcessCurves` |
| A6 | **Гіпотермія / тепловий удар** | `Defs/HediffDefs/` | деф `Hypothermia` і `Heatstroke`: усі `stages` з `minSeverity`, `capMods`, `painOffset`; будь-які `severityPerDay` / криві |

### B. Пріоритет 2 — здоров'я і бій

| # | Що знайти | Де шукати | Ключові поля |
|:--:|---|---|---|
| B1 | **Больовий шок** | `Defs/StatDefs/` | `PainShockThreshold`: `defaultBaseValue` |
| B2 | **Кровотеча ран** | `Defs/HediffDefs/` (injuries) | `bleedRate` по типах поранень; `HediffCompProperties_TendDuration` |
| B3 | **Інфекція та імунітет** | `Defs/HediffDefs/` (diseases) | `HediffCompProperties_Immunizable`: `immunityPerDaySick`, `immunityPerDayNotSick`, `severityPerDay`, `immunityPerDayNotSickCurve` — і **як саме задано гонку** |
| B4 | **Покриття частин тіла** | `Defs/BodyDefs/`, `Defs/BodyPartDefs/` | `coverage` (ймовірність влучання), `hitPoints` для людини |
| B5 | **Потенція медикаментів** | `Defs/ThingDefs_Items/` (medicine) | `MedicalPotency` у `statBases` для трав'яної / промислової / гліттерворлд |
| B6 | **Точність зброї по діапазонах** | `Defs/ThingDefs_Misc/` (weapons) | `AccuracyTouch/Short/Medium/Long` — **таблиця по 6–8 репрезентативних стволах** (пістолет, автомат, снайперка, дробовик) |
| B7 | **Крива точності стрільця** | `Defs/StatDefs/` | `ShootingAccuracyPawn`: `defaultBaseValue`, `postProcessCurves`, `skillNeedFactors` — **саме крива важлива** |
| B8 | **Укриття** | `Defs/ThingDefs_Buildings/` | `fillPercent` для мішків з піском, барикади, стін — і будь-які `coverEffectiveness` |
| B9 | **Погода і точність** | `Defs/WeatherDefs/` | `accuracyMultiplier` по всіх типах погоди |
| B10 | **Ближній бій** | `Defs/StatDefs/` | `MeleeHitChance`, `MeleeDodgeChance`: бази, криві, `skillNeedFactors`; кулдауни зброї (`MeleeWeapon_Cooldown`) |

### C. Пріоритет 3 — потреби, робота, контент

| # | Що знайти | Де шукати | Ключові поля |
|:--:|---|---|---|
| C1 | **Швидкість голоду людини** | `Defs/ThingDefs_Races/` (humanlike) | `baseHungerRate`, `foodMaxNutrition` у `race` |
| C2 | **Пороги потреб** | `Defs/NeedDefs/` | усе, що є для `Food` і `Rest` — **особливо будь-які пороги зон і `fallPerDay`** |
| C3 | **Поживність їжі** | `Defs/ThingDefs_Items/` (meals) | `nutrition` для сирого / простої страви / вишуканої / поживної пасти |
| C4 | **Ефективність ліжок** | `Defs/ThingDefs_Buildings/` (beds) | `BedRestEffectiveness`, `ImmunityGainSpeedFactor`, `MedicalTendQualityOffset` |
| C5 | **Вартість досліджень** | `Defs/ResearchProjectDefs/` | `baseCost` + `techLevel` — **розподіл: мін / медіана / макс по кожному techLevel** |
| C6 | **Множник станків** | `Defs/ThingDefs_Buildings/` | `ResearchSpeedFactor`, `WorkTableWorkSpeedFactor` |
| C7 | **Робота рецептів** | `Defs/RecipeDefs/` | `workAmount` — розкид від найдешевшого до найдорожчого рецепта |
| C8 | **Рослини** | `Defs/ThingDefs_Plants/` | `growDays`, `fertilitySensitivity`, `growMinGlow`, `harvestYield`, будь-які температурні поля |
| C9 | **Модифікатори якості** | `Defs/StatDefs/`, `Defs/Misc/` | де саме задано вплив quality на стати (криві / `QualityMultiplier`) |
| C10 | **Риси й пороги зривів** | `Defs/TraitDefs/` | `mentalBreakThresholdOffset` — діапазон значень по рисах |
| C11 | **Торгівля** | `Defs/StatDefs/`, `Defs/TraderKindDefs/` | `TradePriceImprovement` (база + стеля), будь-які цінові множники |

### D. Явно перевір, чи це взагалі в XML

Це те, що я підозрюю як C#-константи. **Не вигадуй їх.** Прогони пошук, і якщо порожньо —
так і напиши. Негативний результат тут так само корисний, як позитивний.

- Періоди `TickRare` / `TickLong` (перевір заразом: які дефи мають `tickerType` і які саме значення)
- Дистанції брекетів точності (touch / short / medium / long у клітинах)
- XP на рівень навички (крива 0→20), денна стеля навчання (~4000), швидкість «іржі» після 10 рівня
- Множники пристрасті (0.35 / 1.0 / 1.5)
- Пороги capacity: непритомність 30% Consciousness, downed 15% Moving
- Пороги зривів настрою: 35% / 20% / 5%
- Крива «багатство → очки загрози», мінімум 35 і стеля 10 000
- Розподіл якості крафту за рівнем навички
- Температурні межі росту рослин (6 °C / 42 °C)
- Множник ×1.5 / ×2 за дослідження вище свого tech level

Метод: `grep -rn "<ім'я поля>" Data/Core/Defs/ | head -20` для кожного. Порожньо → C#.

## Крок 3 — формат виходу

Створи **`rimworld-defs-audit.md`** у поточній теці. Структура:

```markdown
# Аудит констант RimWorld із Defs

**Версія гри:** <точний білд з Version.txt>
**DLC у Data/:** <перелік>
**Дата аудиту:** <сьогодні>
**Покрито:** A1–A6 ✓ · B1–B10 ✓ · C1–C11 частково (зупинився на C7) · D ✓

## A1. Адаптація складності

**Файл:** `Data/Core/Defs/DifficultyDefs/Difficulties.xml`
**Def:** `Rough`

| Поле | Значення |
|---|---|
| adaptationEffectFactor | 0.5 |
| threatScale | 1.0 |

<докази — дослівний XML-фрагмент>
```xml
<adaptationEffectFactor>0.5</adaptationEffectFactor>
```

**Коментар:** <лише якщо структура дефа неочевидна — напр. поле є в кількох дефах з різними значеннями>

...

## Не знайдено в XML

| Ціль | Що шукав | Висновок |
|---|---|---|
| D1 TickRare період | `grep -rn "tickerType"` — знайдено лише перелічення Normal/Rare/Long без періодів | періоди в C# |

## Знахідки поза списком

<до 10 пунктів: числа, які трапились по дорозі й виглядають цінними для гри
про виживання на РЕАЛЬНІЙ географії — вартість руху, погода, сезонність, температура.
Кожна — з тим самим доказом. Без цього розділу теж нормально.>
```

## Крок 4 — самоперевірка перед видачею

Пройдись по власному звіту і викинь усе, що не проходить ці три питання:

1. **У кожного числа є дослівний XML-фрагмент і шлях до файлу?** Якщо ні — прибери число або
   перенеси в «не знайдено».
2. **Чи не переписав я значення з пам'яті замість файлу?** Особливо там, де твоє число підозріло
   «кругле» й збігається з тим, що ти й так знав. Перечитай файл.
3. **Чи вказана версія гри вгорі?** Без неї звіт нема куди вливати.

Наприкінці одним абзацом: **що не встиг** і **що виявилось складнішим, ніж список припускав**.
Це не виправдання — це наступний робочий елемент.
