# Experimental-led battlefield pressure

## Summary

Build a continuous, affordable experimental force that improves Red Queen’s results against stock Adaptive across land, air and water.

The current system mainly grants permission to build: shared income thresholds, strategic weights and project slots. It does not reliably connect a selected experimental to funding, construction completion, support and an effective combat operation. Native builders can also start projects outside Red Queen’s allowance.

Your chosen direction is:

- All mobile combat domains.
- Concurrency scales with available funding, without a fixed two-project ceiling.
- No fixed share of income reserved for experimentals.
- Preserve native onboard production initially.
- Scathis is a strategic game-ender; Atlantis is support, not an offensive spearhead.

“Dominating” will be evaluated through completed experimental operations, retained territory and paired benchmark results—not experimental counts alone.

## 1. Make ownership and selection accurate

Extend `Experimentals.lua` with operational classes separate from its existing broad roles:

| Class | Units |
|---|---|
| Ranged land spearhead | Fatboy, Megalith |
| Assault spearhead | Monkeylord, Galactic Colossus, Ythotha |
| Air strike | CZAR, Soul Ripper, Ahwassa |
| Naval spearhead | Tempest |
| Naval support | Atlantis |
| Strategic/economic | Scathis, Mavor, Salvation, Yolona Oss, Novax, Paragon |

Use effective installed blueprints for cost, construction rate, movement and weapon capabilities. Remove stale explanatory claims encountered in this path.

Introduce one experimental project registry, keyed by project entity identity. Track reservations, construction, completion, controller ownership and destruction. Count a project once regardless of how many engineers assist it. Exclude attached factories, satellites, eggs and death-spawned entities from independent hull counts.

Publish the actual selected blueprint and its selection/blocking reason. Replace the present diagnostic mismatch where catalog order can report one unit while an equal-priority builder constructs another.

For mobile candidates:

- Require an executable construction site, exit route and useful observed objective.
- Evaluate the candidate’s actual movement layer and relevant weapons.
- Reject operations that cannot meet the existing engagement-strength policy with available support.
- Among feasible operations, prefer the earliest predicted useful arrival; break ties by lower total investment, then blueprint ID.
- Permit repeated copies of the same suitable experimental. Role diversity must not divert funding into an unsuitable alternative.

Keep strategic and economic experimental policy outside this behavioural change, while accounting for its existing commitments.

## 2. Replace blanket gates with project affordability

Add an experimental coordinator, updated on the existing production cadence. Both Red Queen and native experimental starts must consult its admission decision for Red Queen brains only.

Replace the common mobile-experimental income thresholds and fixed concurrency ceiling with:

- Sustainable income, conservatively using the lower of instantaneous and smoothed income.
- Existing requested spending, active project commitments, operating costs and assigned build power.
- Available stored resources after known critical obligations.
- Estimated construction and support costs from effective blueprints.

No fixed income percentage is reserved. Existing essential production remains funded; otherwise uncommitted income and usable storage fund experimental work. Already committed projects receive available assistance before another hull starts.

Initial planning default: admit a new hull only when its allocated funding and available builders predict completion within five simulation minutes. This is a completion forecast, never a match-age gate. Re-evaluate assistants as funding changes; additional concurrency requires another independently affordable project.

Prevent duplicate starts through reservations shared across base managers. Adopt native-started projects into the same accounting. When conditions deteriorate, release excess assistants and defer new work before pausing an existing project. Resume recoverable projects without replacing their construction orders or losing progress.

The budget is a control policy, not an engine resource reservation: log requested versus delivered construction progress so affordability failures remain visible.

## 3. Complete the combat handoff

Retain useful native implementation, but give each experimental exactly one combat-order owner. Inspect and adapt native behaviour at the defining hook or a Red Queen-specific plan; do not repeatedly seize units between controllers.

Implement distinct operations:

- **Fatboy/Megalith:** spotted firing positions, effective weapon range, approach protection and retreat space.
- **Assault walkers:** supported approach, target selection and withdrawal when the engagement becomes untenable.
- **CZAR/Soul Ripper:** air-risk-aware approach and sustained attack only while the target remains viable.
- **Ahwassa:** attack pass, exit and reassessment; measure bomb release separately from movement orders.
- **Tempest:** reachable water firing positions and fleet support; account for surfaced versus submerged weapon availability.
- **Atlantis:** support an existing naval operation, preserving native carrier production and deployment.

Attach available AA, screening units and faction-appropriate protection according to observed threats. Report missing support through existing production demand. Avoid an indefinite assembly hold: use a safer feasible objective or defensive position while support is unavailable.

Preserve native onboard queues and their separate ownership. New reinforcement-queue optimisation and Megalith egg automation are deferred.

## 4. Prove each stage before scaling testing

Implement and validate in three separable stages: accounting/selection, construction funding, then combat operation. Keep unrelated defence changes out of experimental comparisons.

Required contracts and native fixtures cover:

- Multiple assistants counting as one project; simultaneous base requests; native/custom start collisions.
- Child entities, transfers, capture, completion and destruction.
- Three affordable simultaneous projects versus rejection of an unfunded additional project.
- Reclaim spikes, energy loss, assistant release, preserved partial construction and recovery.
- Amphibious and naval routes, unavailable targets and unsuitable firing layers.
- Every mobile controller family, including order ownership, withdrawal and preserved onboard queues.

Instrumentation must identify selection → accepted order → project → completion → controller → first effective action. Include progress, funding, support and blocking reasons. Run hook-target checks, repository validation and log analysis before accepting runtime evidence.

Start paired canaries against Adaptive on:

- Fields of Isis: UEF and Cybran.
- Syrtis Major: Aeon and Seraphim.
- Sludge: Aeon.
- Saltrock Colony: UEF.

Use seed 8675309 initially, then held-out seeds 2071971 and 424242 only after the mechanism works. Keep equal income, identical paired settings and common-horizon comparisons. Run at most two cells concurrently and preserve payloads, manifests, logs and measurements under `docs/balance/data/`.

Promote the final candidate only when the held-out set improves aggregate wins, with no faction’s win count below its control, and the logs demonstrate more useful experimental operations. Report conventional-production and territory tradeoffs. If those conditions fail, retain the control and the specific falsified hypothesis; do not continue broad threshold tuning.

## Assumptions

No income bonuses, hidden enemy information or elapsed-time progression gates are introduced. Existing strategic game-enders remain available but receive no new doctrine in this work. Gains against humans remain a later verification task; Adaptive benchmarks are the primary acceptance criterion.
