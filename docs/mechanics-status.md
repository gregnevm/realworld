# Mechanics catalogue — status tracker

> Snapshot: **2026-07-05**. Purpose: make the *infrastructure-vs-content* gap visible — the kernel is
> deep (~377 headless tests) but not every designed mechanic is yet wired into a playable slice. This
> is the at-a-glance «what is real vs only designed» view that complements `GDD_BOOK/gdd.json`
> (`section:mechanics_overview`) and the specs.
>
> Derived from specs 0001–0005 + `godot/scripts/kernel/` at snapshot time; treat integration/test
> columns as **best-effort — the owner should correct any cell**. Batch 4 (gear) was **untracked** at
> snapshot, so its row may have advanced since.

**Legend:** ✅ done · 🟡 partial · ⬜ not started · ⚠️ untracked/uncommitted at snapshot

| Mechanic (GDD id) | Designed | Coded | Integrated in playable slice | Tested (headless) | Notes |
|---|:---:|:---:|:---:|:---:|---|
| `map_generation` | ✅ | ✅ | ✅ | ✅ | `world_gen.gd`; OSM overlay + procedural fallback; coord-seed invariants |
| `climate` | ✅ | ✅ | 🟡 | ✅ | `kernel/climate.gd` closed-form; seam to live weather API; game-side surfacing partial |
| `character_sim` | ✅ | ✅ | ✅ | ✅ | `sim.gd` single hero |
| `needs` | ✅ | ✅ | 🟡 | ✅ | `kernel/needs.gd` (food/rest); **water lives in `gear.gd`** ⚠️ |
| `health` | ✅ | ✅ | 🟡 | ✅ | `kernel/health.gd` 6-part + hediffs; **scars/prosthetics/medicine in `gear.gd`** ⚠️ |
| `inventory_gear` | ✅ | ⚠️ | ⬜ | ⚠️ | `gear.gd` exists but **untracked**; not yet wired into the sim loop |
| `gathering` | ✅ | ✅ | ✅ | ✅ | tool multipliers formalized (axe 1.6× / pick 1.9×) |
| `base_building` | ✅ | ✅ | ✅ | ✅ | building costs/HP in `data.gd` |
| `crafting_automation` | ✅ | ✅ | 🟡 | ✅ | `kernel/production.gd` bills (count/until); quality 0–6 |
| `raids_pvp` | ✅ | ✅ | ✅ | ✅ | threat-driven waves + tactic escalation via Balance |
| `balance_director` | ✅ | ✅ | 🟡 | ✅ | `kernel/balance.gd`; `decide()` AI seam; incident MTB pacing |
| `convoy_logistics` | ✅ | ✅ | ✅ | ✅ | real hubs (Kyiv/Lviv/Odesa/…); trade offers |
| `offline_persistence` | ✅ | ✅ | ✅ | ✅ | `persistence.gd` seed+diff+hash-chain; travel/permadeath |
| `social` | ✅ | ✅ | ✅ | ✅ | `social.gd` clans/stances; `new_graph()` = Phase 1 wire-shape |
| `capsules` | ✅ | ✅ | 🟡 | ✅ | `sim.gd` ≤100 km / 1-per-day; invites |
| `territory_control` | ✅ | 🟡 | ⬜ | 🟡 | clan stances feed threat; full territory meta = later |
| `economy` | ✅ | 🟡 | ⬜ | 🟡 | sinks exist (raids/convoy/upkeep); full player economy = Phase 1+ |

## Designed but deliberately NOT coded (RimWorld systems on ice)

Locked out of Phase 0 scope on purpose (`section:scope`): **mood/thoughts**, **traits**, deep
**skills as mechanics**, **beauty / room-quality buffs**, **multi-pawn management** (one hero only),
**additional human pawns** (MMO-only). Tracked here so «designed» never gets mistaken for «coming».

## How to read this

The right-hand columns tell the real story: several deep systems are **coded + tested in the kernel
but only partially surfaced in a playable slice**. The single highest-leverage move to close the gap
is **`inventory_gear` (Batch 4)** — commit it, then wire gear/water/medicine into the sim so the depth
becomes *felt*, not just *tested*. See `GDD_BOOK/gdd.json` `section:risks` (risk #5) and the CTO
integration-fixtures recommendation.
