# Spec 0007 — Progression pipeline (research → unlock, driven end-to-end)

> Status: **implemented** (2026-07-08). Closes the highest-leverage gap `docs/mechanics-status.md`
> named: the deep content tree (spec 0004) was *validated* but never **walked** by a mechanic — research
> gated content only in theory, nothing drove the tech pipeline, and the depth was tested, not *felt*.
> Companion to: **specs/0003** (the `ResearchState` primitive this builds on), **specs/0004 + `docs/catalog.md`**
> (the tree it walks), **specs/0005** (the view-layer rules the surfacing obeys). Design canon: RimWorld's
> research manager, made an explicit, queueable pipeline.

---

## 0. Why this exists

`kernel/production.gd` already ships the research *primitive* — `ResearchState`: one active project, points
burned in via `advance(dday)`, an unlocked-set out, and `can_make()` the gate every recipe consults. And
`content/catalog.json` ships 41 research projects in a reachability-validated DAG (tier 1 neolithic → tier 9
spacer). What was missing is the **layer between them the UI and host actually drive**: *what can I research
now*, a *queue* of upcoming projects, *what does the current tech state unlock*, a *tech-level* readout, and
the *feed of points from a research station*. Without it, `ResearchState` was an island: correct, tested, and
unreachable from play. This spec is that layer — the pipeline — plus its HUD surface and its live wiring.

## 1. The kernel — `godot/scripts/kernel/progression.gd`

A `RefCounted` façade over `ResearchState` + `catalog.gd`. Pure: set/graph closure over plain data + float
accumulation; no rng, no time, no DOM. It **edits nothing** — reuses `ResearchState` verbatim and reads the
tree through `catalog.gd`'s typed accessors (so `sim.gd`/`main.gd`/`data.gd` are untouched).

| Surface | Contract |
|---|---|
| `available()` / `is_available(id)` | projects researchable **now** — prereqs met, not unlocked/active/queued |
| `auto_next()` | the deterministic "research next" pick: lowest `(tier, cost, id)` |
| `enqueue(id)` | append to the pipeline; **refused unless prereqs are already unlocked / active / queued-earlier**, so the queue is always a valid topological order and its front is always startable |
| `start(id)` | make `id` active now (bypasses the queue; refused if one is already active) |
| `add_points(p, auto)` | burn `p` points; when a project completes the **leftover rolls into the next** queued (or, if `auto`, the next available) project — a real pipeline, not stop-start. Returns the ids unlocked by this call |
| `unlocked_buildings()` / `_recipes()` / `_items()` | the catalogue slice the current tech state opens; `tech_level()` = deepest unlocked tier |
| `research_path(id)` | the ordered, deduped, valid-topo prerequisite chain ending at `id` (the planner) |
| `steps_to_unlock(gate)` / `remaining_cost(target)` | that path minus what's unlocked, and the Σ research-points still to spend — a live "N steps / M points (≈ D days at the current rate)" readout |
| `unlocks_of(research_id)` / `catalog_counts()` | what completing a project OPENS (reverse of the gate), and per-category unlocked/total — the "researching X unlocks N" preview + tech dashboard |
| `summary()` / `to_dict()` / `from_dict()` | pure value-data ViewModel slice + save/load of the whole pipeline |

**Determinism note:** `add_points` spends leftover points across project boundaries in one call by computing
`need = cost − progress` per project, so a big daily grant deterministically finishes several cheap projects.
`auto_next`'s `(tier, cost, id)` tiebreak makes the whole auto-walk reproducible.

## 2. Verification — two validators, one `catalog.json`

Mirrors the `catalog.gd ↔ catalog.test.js` discipline so the engine and CI can never disagree:

- **`tests/progression.test.js`** (Node, every push): a JS mirror of `progression.gd` drives the same file
  and proves the pipeline **researches the entire tree from a cold start, always in prereq order**, spending
  exactly Σcost and ending at the deepest tier; **leftover points roll forward**; `enqueue` accepts only a
  valid topo order; the unlocked catalogue **grows monotonically and ends at full catalog reachability**;
  `research_path` is a valid topo order containing the full transitive closure; illegal starts are refused;
  and serialization round-trips. (12 tests.)
- **`godot/tests/run_progression_tests.gd`** (headless Godot, CI): the GDScript parity of the above, driving
  the real kernel through the same assertions.

## 3. The HUD surface (spec 0005 view layer, rules intact)

- **`hud_model.gd`** — a pure `research` slice: `Progression.summary()` + the researchable options + queue,
  all value data (R8). `{wired:false}` when no progression is attached, so degraded/test paths stay green.
- **`widgets.gd`** — `ChoiceRow`: a full-width pick row that emits a **semantic id**; the panel turns it into
  an intent, so a widget still names no sim mutator (R9). Tooltip carries the R5 explain.
- **`panels.gd`** — `ResearchPanel` (LEFT dock): tech level, active-project progress bar, a clickable list of
  researchable projects (→ `enqueue_research` intent), and the queue. Built once, bound each frame (R2).
- **`mechanics.gd`** — registers it (no controller edit — R4).
- **`run_ui_tests.gd`** — parity: slice wired + pure value data, degrades to `{wired:false}`, panel builds
  once across two binds, a row click bubbles an `enqueue_research` intent carrying the project id.

## 4. Live wiring (the pipeline actually runs)

- **`data.gd`** — a Phase-0 `research_bench` building (`research_rate: 1.0`), appended last in `BUILD_ORDER`
  so keys 1–7 keep their buildings. It is the concrete research-point source in the playable slice.
- **`session.gd`** — owns `progression` (built cold in `start()`; **account-global** — never reset by
  `travel_to`/`respawn`, like the day clock). `research_rate()` sums standing benches; `tick_research(dt)`
  feeds `rate × (dt/day_len)` points (cost is measured in game-days, so one bench funds ~1 project-day per
  in-game day) and toasts each unlock through the existing feed. `enqueue_research`/`start_research`/
  `clear_research_queue` are the intent targets.
- **`input_verbs.gd`** — binds `enqueue_research` / `start_research` / `clear_research` to those session
  methods (the router is the only place sim/session mutators are named — R9).
- **`newhud_main.gd`** — calls `tick_research(dt)` each frame and bridges every panel `intent` into the router
  (generic, names no mechanic). The demo base builds a research bench and queues two projects so the panel
  reads live in the dev screenshot.

## 5. Scope boundary (what this does NOT do yet)

The pipeline runs end-to-end — build bench → points flow → queue → unlock → readout + toast + climbing tech
level — and the planner already answers "what unlocks this". What it does **not** yet do is let the hero
**build catalog buildings / craft catalog recipes gated by unlock**: the playable slice still builds/crafts
from `data.gd`'s 6-resource table, while the catalog uses 78 resources. Bridging the two resource systems is
the next surface (a "catalog build/craft menu gated by `unlocked_buildings()`"), deliberately deferred so
this pass stays additive and the shipped slice + its suites are unchanged. Tracked in `docs/mechanics-status.md`.
