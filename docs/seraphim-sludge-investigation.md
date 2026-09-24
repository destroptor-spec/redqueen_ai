# Seraphim on Sludge — 2026-09-07

## Conclusion first: it no longer reproduces

Sludge (`SCMP_037`), seed 2071971, Seraphim against stock Adaptive — the exact
configuration that lost:

| Payload | Result | Red Queen K/L | Opponent |
| --- | --- | --- | --- |
| `0cbb34c70ae5` (when first measured) | **defeat** | 0.64 | 0.65 |
| `ff9ab9572dd3` (current tree) | **victory** | **3.39** | 0.26 |

An Aeon control on the same map and seed also improved, 1.85 to 2.63, so this is
not Seraphim-specific recovery — but Seraphim now *out-performs* the Aeon
control on the map where it was the only faction to lose.

The mechanism is visible in production, normalised per 10 000 ticks because the
matches differ in length:

| | naval | tech1 | tech2 | land | air |
| --- | --- | --- | --- | --- | --- |
| Seraphim, when it lost | 9.3 | 142 | 27.9 | 53 | 13.9 |
| Seraphim, current tree | **26.9** | 164 | 25.8 | 59 | 10.1 |
| Aeon control, current tree | 9.8 | 154 | 42.1 | 64 | 18.6 |

Seraphim's warship production nearly tripled. On a map that is 93% water that is
the whole story: the naval work — first-tier naval production and water
objectives becoming expressible at all — is what turned this match around, and
Seraphim ends up building warships at nearly three times the Aeon control's rate.

## But a real faction defect was found, and it is still there

Red Queen references four FAF platoon templates that lack squads for some
factions. Verified against `lua/AI/PlatoonTemplates/`:

| Builder | Template | Silently inert for |
| --- | --- | --- |
| `Red Queen T2 Land Dominance` | `T2AttackTank` | **Seraphim** |
| `Red Queen T3 Air Dominance` | `T3AirGunship` | **Seraphim** |
| `Red Queen T3 Gunship Counter` | `T3AirGunship` | **Seraphim** |
| `Red Queen T1 Gunship Counter` | `T1Gunship` | **UEF, Aeon, Seraphim** |

### Why it is silent

`FactoryBuilderManager:GetFactoryTemplate` (`lua/sim/FactoryBuilderManager.lua:355`)
does not fail when the playing faction has no squad. It returns
`{ templateData.Name, '' }` — a template with **no units in it** — which is
truthy, so the builder is selected, builds nothing, and logs nothing. There is
no warning on this path; the `SPEW` calls nearby cover a missing template and a
missing `FactionSquads` table, not a missing faction *within* it.

So the builder appears healthy in every diagnostic Red Queen emits.

### Two different causes, needing two different fixes

**`T2AttackTank` is an arbitrary FAF omission.** It holds the alternate Tech 2
land units — `del0204` Gatling Bot, `xal0203` Assault Tank, `drl0204` Rocket Bot
— and Seraphim has an equivalent (`xsl0203` Hover Tank) that simply is not
listed. `T2LandDFTank` covers all four factions in the same role with the
standard Tech 2 tanks including Seraphim's `xsl0202`, so switching to it closes
the gap with no judgement call.

This is measurable and persistent: Seraphim's Tech 2 production is 25.8 per 10k
against the Aeon control's 42.1, and that ratio barely moved between the two
payloads (27.9 against 41.4 before). The Tech 2 land ladder has never worked for
Seraphim.

**`T3AirGunship` and `T1Gunship` reflect the game.** Seraphim has no Tech 3
gunship and only Cybran has a Tech 1 gunship, so these are not omissions to
correct but capabilities that faction does not have. The "Gunship Counter"
ladder is Red Queen *countering with* ground-attack air — its condition counts
`categories.AIR * categories.GROUNDATTACK` — so the same-role substitutes with
full coverage are `T3AirBomber` and `T1AirBomber`.

The safe shape is a faction-gated sibling builder rather than changing the
existing one: UEF, Aeon and Cybran keep the exact behaviour already measured,
and only the uncovered factions gain a path. That is the pattern the experimental
builders already use.

## What this does not explain

Seraphim's Tech 3 production was **zero** in the losing match, so the two
`T3AirGunship` gaps could not have contributed to it. And Seraphim trailed the
other factions in *every* category, including Tech 1 at 142 per 10k against 198
and 235 — a general economic lag that no template gap accounts for. The
template defect is real and worth fixing on its own merits; it was not the cause
of this loss.

## Caveat

One run per payload. The comparison is between payloads on a fixed seed, and the
simulation is deterministic, so it is not run-to-run noise — but payload
divergence alone has been measured to swing mass kill/loss by ±0.7 on this
harness, and 0.64 to 3.39 is a larger swing than that with a mechanism behind it
(naval production tripling). Confirming at seeds 8675309 and 31337, where
Seraphim previously scored 1.47 and 0.72, would settle it.
