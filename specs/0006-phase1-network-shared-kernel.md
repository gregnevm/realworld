# Spec 0006 — Phase 1 network model & shared sim-kernel (ADR + spec, no code this pass)

> Status: **approved · design-only · touches no code this pass** (approved 2026-07-05 — decision:
> **option A**, Godot headless authoritative server; Node = deferred fallback). This spec decides the
> *shape* of the Phase 0 → Phase 1 transition (single-player → thin authoritative server, one city,
> 8–10 players) **before** any networking code lands. It is the missing ADR the roadmap assumes.
> Companion to: **specs/0003-mechanics-kernel.md** (the 5-contract sim this must run server-side),
> **specs/0002-social-capsules-persistence.md** (the `social.new_graph()` wire-shape and the
> `seed + diff + hash-chain` persistence this must make authoritative), **AGENTS.md** (roadmap:
> «Фаза 1 — тонкий authoritative-сервер (Node) + 2–3 гравці на одній карті, спільне sim-ядро»),
> **README.md** (Roadmap). Design intent for the player-facing side lives in `GDD_BOOK/gdd.json`
> (`section:technical`, `section:scope`, `section:risks`).

---

## 0. Why this exists (one paragraph)

The kernel's entire payoff is a **bet on this transition**. `Balance.decide()` was carved out as an
AI/policy seam, `HudModel.snapshot()` was built as a pure Node-free read, the sim is scene-free and
`sim` never imports `ui` (spec 0005 R1), and the whole world is a deterministic function of `lat/lon`
(PCG32 from an FNV hash; seeded RNG only). **All of that only pays off if Phase 1 reuses the same
sim-core authoritatively.** Yet there is no written decision on *where the server-side sim lives*
(Godot headless vs a Node/TS port vs a shared transpiled core), *what the authority boundary is*, or
*how the existing seams become the wire protocol*. Left undecided, the frozen JS slice (`game/`) and
the live Godot kernel (`godot/`) diverge into two sims — the exact dual-codebase drift risk flagged in
`section:risks`. **This spec makes the decision on paper, reusing the seams the kernel already
exposes, so Phase 1 code starts de-risked.** No networking code lands this pass — same discipline as
spec 0005 Batch 0 (architecture before migration).

### Repo-precedent constraints (verified ground truth — non-negotiable)

Carried verbatim from spec 0003/0005; they bound every option below:

- **Determinism is the product, not a feature.** «Координати — seed»: world = pure function of
  `lat/lon` → PCG32(FNV). No global `randf()`; every stochastic path takes an explicit seeded
  `RandomNumberGenerator`. Network replication MUST preserve this end-to-end.
- **Fixed-tick sim.** The sim advances in discrete ticks; no wall-clock float integration in the
  authoritative loop. This is what makes lockstep/rollback possible at all.
- **JSON int→float coercion is a landmine across a wire/save boundary.** Compare with
  `is_equal_approx`, never `== 180`; carry the spec 0002 hash-chain rules to the network payload.
- **No autoloads, no `class_name`, no build step** (spec 0005 §Repo-precedent). Any server-side
  choice must not smuggle a bundler/toolchain in through the back door without an explicit ADR.
- **The mutation path is already single.** Per spec 0005 R9, sim-mutating commands flow **only**
  through the `InputController` router. That single choke-point is the natural client→server command
  channel — do not open a second one.

---

## 1. The decision — where does the authoritative sim-core run?

Three candidate models. This is the load-bearing choice; everything else follows from it.

| | **A. Godot headless as server** | **B. Port kernel to Node/TS** | **C. Shared transpiled core** |
|---|---|---|---|
| Code reuse | **One codebase** — the tested kernel *is* the server (`--headless`) | Duplicate sim in a 2nd language | Write once, target both (custom toolchain) |
| Drift risk | **None** (single source of truth) | **High** — two sims to keep bit-identical | Low, but toolchain-coupled |
| Determinism guarantee | Already proven by 152 kernel tests | Must re-prove PCG32/tick parity in JS | Must prove the transpile is faithful |
| Hosting / ops | Godot server process per shard (heavier RAM) | Node-native, cheap horizontal hosting | Node-native output |
| Latency / throughput | Adequate for 8–10 / one city | Best at scale | Best at scale |
| Toolchain debt | **Zero** (no build — matches AGENTS.md ethos) | Moderate (Node service) | **High** (transpiler = the thing AGENTS.md warns against) |
| Effort to Phase 1 | **Lowest** | High | Highest |

**Recommendation: start with A (Godot headless authoritative server).** It reuses the exact sim that
377 tests already guard, keeps determinism a solved problem, and adds **zero** toolchain debt — the
cheapest path to a *correct* 8–10-player one-city slice. Treat B as a **deferred fallback**, taken
only if measured RAM/throughput on real hosting forces a Node-native sim at scale (a Phase 2 concern,
not Phase 1). **Reject C** for Phase 1 as premature toolchain debt — it contradicts the no-build ADR
and buys scale the project cannot yet use. Note in AGENTS.md that the README roadmap line
(«authoritative-сервер (Node)») is hereby **superseded**: Node is the fallback, not the default.

## 2. Authority boundary

- **Server-authoritative sim.** The server owns the tick loop, `Balance` (wealth/threat/incidents),
  raids, needs/health decay, production ticks, and the `Persistence` commit. Clients never compute
  authoritative state.
- **Client = input + prediction + render.** `HudModel.snapshot()` is *already* the pure, Node-free
  read of sim state → it becomes the **replication payload shape** (server → client). The client
  renders snapshots and may locally predict movement, but the server reconciles.
- **Commands via the existing router only.** Client intents (verbs from `InputController`, spec 0005
  R9) serialize to the server as the sole mutation channel. No client writes sim state directly.

## 3. Wire-protocol seams (reuse what the kernel already exposes)

The architecture already has the four seams the protocol needs — this spec just names their network role:

1. **State: `HudModel.snapshot(world, ctx)`** → server→client snapshot/delta payload. Already pure and
   Node-free; already headlessly tested. Add only a delta-encoder on top; do not invent a 2nd model.
2. **Commands: `InputController` verbs** → client→server command messages. Single choke-point (R9).
3. **Social: `social.new_graph(name, seed)` shape** (spec 0002) → replace the deterministic-NPC graph
   with the live backend roster; the *shape* is the wire format, so only this method swaps.
4. **Persistence: `seed + diff + prev/content_hash` chain** (spec 0002) → becomes the server's
   append-only authoritative store; the hash-chain already gives integrity for a shared world.
5. **Clock/climate: `ClimateProvider`** → the server owns the authoritative clock; clients read
   `ctx.temp_c/light/weather` from the snapshot (never compute their own).

## 4. Determinism across clients (the acceptance backbone)

- Fixed-tick; integer/seeded everywhere; **deterministic iteration order** (audit every `Dictionary`
  iteration in the tick path — GDScript `Dictionary` is insertion-ordered, but any set-like use must
  be sorted before it affects sim outcomes).
- No float nondeterminism in authoritative math; keep the spec 0002 `is_equal_approx` discipline on
  every save/wire round-trip.
- **The core test:** same `seed` fed to two independent server instances → identical world **state
  hash** after N ticks (extend the existing `_t_coord_seed_invariant` idiom to a full-world hash).

## 5. Fate of the frozen JS slice (`game/`)

Decide explicitly so it stops being a latent divergence: **`game/` stays a frozen reference render
prototype; it is NOT evolved into a second sim.** If a browser client is ever wanted in Phase 1, it
becomes a **thin render client of the Godot server** (consuming the same snapshot payload), never an
independent simulator. This kills the dual-sim drift risk at the source.

## 6. Non-goals (explicitly out of Phase 1)

Full single-shard world of the whole Earth · large-scale player economy & faction territory control
(simplified/off) · mobile/GPS client · matchmaking beyond one city · Node/TS sim port (fallback only)
· any build step / bundler.

## 7. Acceptance criteria (Specify — this pass)

- [x] Kernel-sharing model chosen (A/B/C) with the §1 matrix rationale recorded. *(Chosen: **A**.)*
- [x] Authority boundary documented (server owns X; client predicts/renders Y) — §2.
- [x] Wire protocol expressed as the 5 existing seams (§3), with **no new** parallel state model.
- [x] Fate of `game/` decided (§5) — stays a frozen reference render prototype, never a 2nd sim.
- [x] Determinism test strategy defined: same seed → identical world-state hash on 2 instances (§4).
- [x] AGENTS.md roadmap line reconciled (Node = fallback, not default) — **done 2026-07-27**:
      AGENTS.md «Ключові рішення» entry + README Roadmap line now name Godot headless as the
      Phase-1 server with Node as measured-fallback. `GDD_BOOK` already reconciled.

## 8. Plan (next pass, once this is approved)

1. Inventory the kernel for anything scene-coupled or wall-clock-coupled that blocks `--headless`
   server use (expected: little — the sim is already scene-free).
2. Spike: one `--headless` Godot server + two Godot clients on one `seed`; assert identical
   state-hash after N ticks (proves A end-to-end before committing to it).
3. Design the snapshot delta-encoder over `HudModel.snapshot()` (payload size + tick cadence).
4. Design the command envelope over `InputController` verbs (ordering, idempotency, validation).
5. Make `Persistence` authoritative + append-only on the server; define reconnect/rejoin.
6. Only if the spike's RAM/throughput fails a real hosting target: open a Node-port ADR (option B).

## 9. Tasks (Specify complete; implementation deferred)

- [x] Frame the decision + option matrix (this doc).
- [x] Owner: approve/adjust the A-first recommendation. **→ approved 2026-07-05 (option A).**
- [x] Spike the 2-client / 1-server determinism test (Plan §2) — **complete 2026-07-27**: the
      determinism backbone (§9.1) AND the transport half (§9.2) are both green. Option A is
      proven end-to-end.
- [x] Snapshot delta-encoder over `HudModel.snapshot()` (Plan §3) — **landed 2026-07-27, see
      §9.3**: `scripts/net/snapshot.gd` codec + `run_snapshot_tests.gd` + a live delta channel
      in the transport spike. **← next action: formalize the command envelope (Plan §4 —
      idempotency/validation over the proven ack-gated grammar), then authoritative
      persistence + rejoin (Plan §5).**
- [x] Fold the chosen boundary + protocol back into AGENTS.md and `GDD_BOOK` (✅ `section:risks`/`section:scope`; AGENTS.md + README 2026-07-27).

### 9.1 Spike results (2026-07-27, determinism half)

- **Plan §1 inventory: clean.** Grep-audit of the whole authoritative path (`sim.gd`, `sim/`,
  `session.gd`, `kernel/`, `world_gen.gd`, `social.gd`, `persistence.gd`) found **zero**
  wall-clock/scene coupling — no `Time.`/`OS.`/`Engine.`/`get_tree`/`await`. Nothing blocks
  `--headless` server use.
- **§4 core test: green.** `Persistence.world_hash(sim)` extends the spec 0002 canonical-JSON +
  FNV content-hash to the full authoritative state (save fields **plus** enemies/shots, raid &
  patrol cycles, weather state, `env_rng`/`threat_rng` cursors; view channels and derived caches
  deliberately excluded). `tests/run_determinism_tests.gd` drives two independent instances —
  600 ambient ticks and 500 ticks with a scripted gather/build/move command stream — hash-equal
  at every probe; different seed ⇒ different hash; region payload survives
  serialize→`load_region`→serialize bit-stable.
- **Two OS processes, not two objects:** the suite prints `WORLD_HASH_FINAL=`; CI runs it twice
  and `diff`s the lines (godot.yml «Cross-process determinism hash»), so per-process
  nondeterminism has nowhere to hide. The suite is leak-gated like every other and runs in
  `test.cmd`.

### 9.2 Spike results (2026-07-27, transport half — Plan §2 complete)

- **Literally the §2 Plan sentence:** `tests/run_net_spike.gd` spawns **one authoritative
  `--headless` server + two client processes** (`tests/net/net_server.gd` / `net_client.gd`,
  same Godot binary) over a real localhost **WebSocket**; 600 lockstep ticks finish in ~2 s;
  `world_hash` matches on the server and both clients at every 100-tick probe and at the end.
- **Transport decision: WebSocket, not ENet.** The web export (threads OFF) has no UDP, so a
  §5-style thin browser client stays possible; TCP ordering makes the lockstep command envelope
  trivial; 10 ticks/s survival pacing does not need UDP latency. Recorded as the Phase-1 default.
- **Command grammar over the wire works (Plan §4 seed):** clients send allowlisted verbs
  (`order_gather`/`try_build`/`order_move`); the server QUEUES them, schedules into the next
  advance batch and echoes the schedule to everyone — all three instances apply identically.
  The lockstep is **ack-gated** (flow control): the server opens the next batch only after every
  client acked the previous one, and a client sends its commands *before* its ack, so TCP
  ordering guarantees each command lands in the very next batch. Consequence: the command
  schedule — and therefore the final world_hash — is deterministic **across runs**, not just
  across instances (verified: 5 consecutive runs, identical final hash). Without the gate a
  headless server outruns clients by orders of magnitude and late commands fall off the end —
  the first CI run caught exactly that.
- **Remaining for Phase 1 proper:** snapshot delta-encoder over `HudModel.snapshot()` (Plan §3 —
  ✅ done, §9.3), formalized command envelope + idempotency (Plan §4), authoritative persistence
  + rejoin (Plan §5). The transport and determinism risks are retired.

### 9.3 Delta-encoder results (2026-07-27, Plan §3)

- **Codec:** `scripts/net/snapshot.gd` — `encode(prev, next)` → minimal patch (`["r", v]`
  replace / `["p", {key: node}, [del]]` recursive dictionary patch; arrays replace wholesale —
  measured small), `apply(base, delta)` reconstructs; `null` = nothing changed. Keyframe =
  `encode(null, snap)`. Malformed deltas keep the base (the server is authoritative; the next
  keyframe heals).
- **Payload measured** (`run_snapshot_tests.gd`, live session, 600 ticks): full snapshot
  ≈ 12.9 KB; delta avg ≈ 105 B (peak = keyframe); at 1-in-5 cadence ≈ 190 B. A 10 tick/s delta
  stream ≈ **1.0 KB/s vs 126 KB/s** full-snapshot — the encoder pays for itself two orders of
  magnitude over; no index-diff for arrays needed at this scale.
- **Three wire landmines found by the fidelity harness, all now codec discipline:**
  1. Godot's default `JSON.stringify` **rounds floats** (a 1.358e-14 daylight factor mutated in
     transit) → every net message goes through `Snapshot.to_wire()` (full_precision).
  2. Even full precision does **not** guarantee a bit round-trip of an arbitrary double
     (observed `…6282704` → wire → `…6282703`) → the sender diffs **wire-normalized** snapshots
     (`wire_normalize`), i.e. deltas are computed over what actually shipped — after one
     round-trip the wire domain is idempotent, so drift can never accumulate.
  3. GDScript Variant `==` promotes bool to int (`true == 1`) while the canonical hash keeps
     them distinct → the codec's `_eq` is canonical (bool-strict, numeric int/float, recursive).
- **Live over the socket:** the transport spike now streams a `snap` delta every 50 ticks;
  each client reconstructs and hash-compares against its locally computed snapshot — 12/12
  deltas, 0 mismatches on both clients, run-to-run deterministic. `content_hash` doubles as the
  canonical equalizer for JSON's type coercions (int→float, StringName→String, int-keys→string).

## 10. Risks & rollback

- **Risk:** a Node/TS port (B) duplicates sim logic → two implementations drift.
  → **Mitigation:** default to A (one codebase); take B only under a measured hosting/throughput
  failure, and if taken, gate it behind a shared cross-implementation determinism-hash test.
- **Risk:** network nondeterminism (float order, `Dictionary`/set iteration, message reordering) →
  clients desync.
  → **Mitigation:** fixed-tick + integer/seeded + sorted iteration in the sim path + the two-instance
  state-hash test as a permanent tripwire.
- **Risk:** the snapshot payload is too large at 10 players/one city.
  → **Mitigation:** delta-encode over `HudModel.snapshot()`; measure in the spike before scaling.
- **Rollback:** this pass adds **no code** — rolling back is deleting this file. The spike (Plan §2)
  is an isolated throwaway branch; nothing in Phase 0 depends on it until the boundary is approved.
