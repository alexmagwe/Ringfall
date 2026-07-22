# TASKPLAN — Circular (Theta) Maze, Journey to the Centre

Replaces the square-grid + verticality generator with a **flat concentric-ring
maze**: spawn on the outer perimeter, run inward through gaps in each ring wall,
reach the **evac pad at the centre** to win. Rewrites `src/features/Maze/`.

Supersedes `TASKPLAN-verticality-districts.md` — that mechanic (districts,
towers, crossings, divide walls) is removed. This is flat: rings connect at
street level through gate-gaps in the arc walls.

> GDD divergence: this inverts the GDD's "spawn-centre, escape-outward" framing to
> "spawn-outer, journey-inward". The GDD needs a rewrite after this lands; not in
> scope here.

## Design decisions (settled)

- **Polar layout, deterministic from `Constants.SEED`.**
- **5 ring-bands around a central hub.** Boundary radii (studs):
  `{28, 66, 104, 142, 180, 218}` → hub r≤28, then bands b1..b5 outward; outer
  radius 218 (~440 diameter).
- **Sectors per band** (b1→b5, inner→outer): `{6, 12, 12, 24, 24}` — chosen so
  each cell arc is ~45–65 studs, and sector counts only ever double outward
  (b1→b2 and b3→b4) for clean neighbour mapping.
- **Cell** = one (band, sector) polar region.
- **Walls (street height 32):**
  - **Radial spokes** — straight box from a band's inner to outer radius at a
    sector boundary angle, oriented radially. Present unless a CW/CCW passage.
  - **Arc walls** — the boundary between band i and i+1 per sector, approximated
    by short straight chord segments (~12-stud segments) following the arc.
    Present unless an inward/outward passage.
- **Floor** = one thin cylinder part, radius 218, at y=0 (no per-cell floors).
- **Carve** = recursive backtracker over the polar cell graph. Neighbours:
  CW/CCW (same band, wrapping), inward (band-1: the parent sector), outward
  (band+1: 1 cell if same sector count, 2 cells if the outer band doubled).
- **Spawn** = a single gate-gap in the OUTER wall (b5 outer arc) at a seeded
  sector; player spawns just outside it, facing in.
- **Goal** = the central hub: a glowing **EvacPad** (touch trigger) at r=0.
  Reaching it fires the existing ESCAPED/win flow (rename "escape" → "reach evac"
  only if trivial; keep the WinScreen).
- **No orientation aid needed** — the goal is always radially inward; the
  challenge is finding the ring-wall gaps. The EvacPad glows so it's visible
  through gaps as you near the centre.

## Out of scope / Do NOT

- NO verticality (towers/bridges/divides), NO fog/warden/economy/tools, NO
  multiple rings-as-seasons, NO sewer/rooftop layers, NO tile prop variety.
- Do NOT keep the square-grid generator paths — remove district/crossing code.
- Do NOT make generation non-deterministic (one `Random.new(SEED)`).
- Keep changes within `src/features/Maze/` (+ the SpawnLocation reposition).

## Build phases

### Phase 1 — Polar grid + carve (data only)
Rewrite the carve to the polar cell graph. Represent a cell as `(band, sector)`;
`sectorsOf(band)` returns the per-band count. Implement `neighbours(cell)`
handling wrap-around and the doubling map (a b1 cell has 2 outward neighbours in
b2; a b2 cell has 1 inward neighbour in b1 = `sector // 2`). Backtracker carves a
spanning maze; store per-cell passage flags {in, out(list), cw, ccw}. Add a few
extra loops. **Accept (offline-ish):** a BFS over passages from any outer cell
reaches the hub, and reaches every cell (fully connected).

### Phase 2 — Geometry (walls + floor)
Build the cylinder floor. For each cell, build its radial spoke walls and arc
wall segments where there's NO passage. Position via polar→Cartesian:
`x = r·cos θ, z = r·sin θ`. Arc walls = chord segments; radial walls = one box
per spoke. Colour street walls concrete; cap part count (arc segmentation ~12
studs). **Accept:** in Play, a clean circular maze renders — concentric ring
walls with gaps, radial spokes, no z-fighting (reuse the dedup idea if two
segments coincide), and you can walk the corridors.

### Phase 3 — Spawn, evac, win
Punch one gap in the outer wall; place SpawnLocation just outside it. Build the
central **EvacPad** (glowing disc + touch trigger named for EscapeService).
Wire EscapeService: leaving the spawn gate starts the timer; touching EvacPad
fires Escaped → WinScreen with the time; RUN IT BACK resets to the outer gate.
**Accept:** full loop — spawn outside → run inward through the rings → touch the
centre pad → ESCAPED with correct time → restart. Zero errors.

### Phase 4 — Solvability + fun-gate
Assert (polar BFS) the hub is reachable from the spawn gate every seed. Playtest:
does running inward and hunting each ring's gap feel like a satisfying maze? Is a
first solve ~5–12 min? Record answers in `PLAYTEST-notes.md`.

## Definition of Done

- [ ] Deterministic from `SEED`; concentric-ring maze renders cleanly (no z-fight).
- [ ] Fully connected: polar BFS reaches every cell and the hub from the spawn gate.
- [ ] Spawn at an outer-wall gate; EvacPad at centre; touching it wins.
- [ ] Full loop works (spawn → inward → evac → WinScreen → restart), zero errors.
- [ ] Old square-grid/district/tower code removed; StreamingEnabled on; part budget sane.
- [ ] Only `src/features/Maze/` changed (+ SpawnLocation); `PLAYTEST-notes.md` updated.
