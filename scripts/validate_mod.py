#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MOD_PREFIX = "/mods/TheRedQueen/"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


required_files = [
    "mod_info.lua",
    "hook/lua/aibrains/index.lua",
    "hook/lua/AI/AIBehaviors.lua",
    "lua/AI/CustomAIs_v2/RedQueenAI.lua",
    "lua/AI/LobbyTooltips/tooltips.lua",
    "lua/AI/RedQueenBrain.lua",
    "lua/AI/RedQueen/MatchContext.lua",
    "lua/AI/RedQueen/IncomeBonus.lua",
    "lua/AI/RedQueen/CounterBuilders.lua",
    "lua/AI/RedQueen/FortificationBuilders.lua",
]

for relative in required_files:
    if not (ROOT / relative).is_file():
        fail(f"missing required file: {relative}")

metadata = (ROOT / "mod_info.lua").read_text(encoding="utf-8")
for field in ("name", "version", "description", "author", "uid", "ui_only"):
    if not re.search(rf"(?m)^{re.escape(field)}\s*=", metadata):
        fail(f"mod_info.lua is missing {field}")

uid_match = re.search(r'(?m)^uid\s*=\s*"([^"]+)"', metadata)
if not uid_match or not re.fullmatch(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
    uid_match.group(1),
):
    fail("mod UID is not a lowercase UUID-shaped identifier")

vault_version_match = re.search(r"(?m)^version\s*=\s*(\d+)", metadata)
release_label_match = re.search(
    r'(?m)^Version\s*=\s*"([^"]+)"',
    (ROOT / "lua/AI/RedQueen/Constants.lua").read_text(encoding="utf-8"),
)
registration_label_match = re.search(
    r'(?m)^\s*Version\s*=\s*"([^"]+)"',
    (ROOT / "lua/AI/CustomAIs_v2/RedQueenAI.lua").read_text(encoding="utf-8"),
)
if not vault_version_match or not release_label_match or not registration_label_match:
    fail("release version metadata is incomplete")
release_label = f"V{vault_version_match.group(1)}"
if release_label_match.group(1) != release_label:
    fail("release label must be the Vault version prefixed with V")
if registration_label_match.group(1) != release_label:
    fail("release label differs between metadata and lobby registration")
uid_revision = int(uid_match.group(1)[-6:])
if int(vault_version_match.group(1)) != uid_revision:
    fail("Vault version must match the numeric UID revision")
testing_source = (ROOT / "docs/testing.md").read_text(encoding="utf-8")
if uid_match.group(1) not in testing_source:
    fail("testing documentation does not enable the current mod UID")

registration = (ROOT / "lua/AI/CustomAIs_v2/RedQueenAI.lua").read_text(encoding="utf-8")
brain_hook = (ROOT / "hook/lua/aibrains/index.lua").read_text(encoding="utf-8")
tooltip = (ROOT / "lua/AI/LobbyTooltips/tooltips.lua").read_text(encoding="utf-8")
if 'key = "redqueen"' not in registration:
    fail("lobby registration does not expose the redqueen key")
if "keyToBrain.redqueen" not in brain_hook:
    fail("brain hook does not map the redqueen key")
if "aitype_redqueen" not in tooltip:
    fail("lobby tooltip does not match the redqueen key")

income_source = (ROOT / "lua/AI/RedQueen/IncomeBonus.lua").read_text(encoding="utf-8")
for forbidden in ("CheatEnabled", "CheatBuildRate", "IntelCheat", "VisionRadius", "OmniRadius"):
    if forbidden in income_source:
        fail(f"income-only contract violated by token: {forbidden}")
for required in ("MassProduction", "EnergyProduction", "0.10 * deficit"):
    if required not in income_source:
        fail(f"income contract is missing: {required}")

strategy_source = (ROOT / "lua/AI/RedQueen/StrategyDirector.lua").read_text(encoding="utf-8")
counter_source = (ROOT / "lua/AI/RedQueen/CounterBuilders.lua").read_text(encoding="utf-8")
production_source = (ROOT / "lua/AI/RedQueen/ProductionManager.lua").read_text(encoding="utf-8")
intel_source = (ROOT / "lua/AI/RedQueen/IntelManager.lua").read_text(encoding="utf-8")
fortification_source = (ROOT / "lua/AI/RedQueen/FortificationBuilders.lua").read_text(encoding="utf-8")
combat_source = (ROOT / "lua/AI/RedQueen/CombatManager.lua").read_text(encoding="utf-8")
context_source = (ROOT / "lua/AI/RedQueen/MatchContext.lua").read_text(encoding="utf-8")
analyzer_source = (ROOT / "scripts/analyze-log.py").read_text(encoding="utf-8")
if not re.search(r"(?m)^function ShouldTechToT2\(", counter_source):
    fail("T2 upgrade eligibility must be exported for production policy")
if "CounterBuilders.ShouldTechToT2(self.Brain, profile.Domain)" not in production_source:
    fail("T1 suppression must share its domain's T2 upgrade eligibility")
for required in ("GetBlip", "IsSeenNow", "IsSeenEver", "IsOnRadar"):
    if required not in intel_source:
        fail(f"verified intel contract is missing: {required}")
if "local highestObservedTech = 1" not in intel_source:
    fail("observed enemy tech must be recomputed from surviving intel")
if "- categories.TRANSPORTFOCUS" not in combat_source:
    fail("combat waves must leave transports available to native transport plans")
if "IsOwnedByBrain" not in production_source or "GetRebuildableForwardBaseSites" not in production_source:
    fail("forward-base lifecycle must enforce ownership and support destroyed-site rebuilding")
# FAF forwards AIExecuteBuildStructure's fourth argument into
# aiBrain:FindPlaceToBuild, whose matching parameter is a game object. Passing a
# boolean makes the engine raise "Expected a game object" and kill the calling
# scheduler task, so every call must go through the containing wrapper.
direct_build_calls = re.findall(
    r"AIBuildStructures\.AIExecuteBuildStructure",
    production_source,
)
if len(direct_build_calls) != 1:
    fail(
        "AIExecuteBuildStructure must be reached only through the "
        "ExecuteBuildStructure wrapper, which supplies a nil game-object "
        "argument and contains engine rejections"
    )
if "local function ExecuteBuildStructure" not in production_source:
    fail("the contained AIExecuteBuildStructure wrapper is missing")
if "PruneForwardBaseRecords" not in production_source:
    fail("forward-base records must be pruned so failures cannot accumulate")
# The factory cap must never veto a builder whose real job is creating an
# expansion or naval base; only builders that build nothing but factories.
if "RedQueenFactoryPure" not in production_source:
    fail("the factory cap must distinguish pure factory builders from base packages")
if "ShouldSuppressLowTierMainline" not in production_source:
    fail("Tech 1 mainline must be suppressed against an observed Tech 3 enemy")
# Forward-base engineers come from base managers, not just ArmyPool, which FAF
# drains by claiming every new engineer for a base.
if "ForwardEngineerCandidates" not in production_source:
    fail("forward-base engineers must be sourced from base managers, not ArmyPool alone")
if "ForwardBaseSourceMinimumEngineers" not in production_source:
    fail("sourcing an engineer must respect a per-base retention floor")
# FAF's own T3 Sub Commander builder names an unregistered platoon template, so
# Red Queen registers its own rather than inheriting a silent no-op.
if 'Name = "RedQueenSupportCommander"' not in counter_source:
    fail("support commander production needs its own registered platoon template")
if 'PlatoonTemplate = "T3LandSubCommander"' in counter_source:
    fail("T3LandSubCommander is not a registered FAF platoon template")
if 'BuilderType = "Gate"' not in counter_source:
    fail("support commanders must be produced by a Quantum Gateway factory builder")
if "RedQueenSupportCommanderBuilders" not in production_source:
    fail("the support commander builder group must be registered with the managers")
# Income constants are per game tick. The pure Lua specs stub Constants with
# their own numbers, so they cannot catch a value written as the per-second
# figure -- which is how MinimumProductionMassIncome shipped as 8 (80 mass per
# second) and held the land factory target at one for a whole match. These two
# feed the factory target directly, so they are checked here against the range a
# per-tick figure can plausibly occupy.
constants_source = (ROOT / "lua/AI/RedQueen/Constants.lua").read_text(encoding="utf-8")
for name, ceiling in (
    ("MinimumProductionMassIncome", 2.0),
    ("MassIncomePerFactory", 2.0),
):
    match = re.search(rf"(?m)^\s*{name}\s*=\s*([0-9.]+)", constants_source)
    if not match:
        fail(f"missing income policy constant: {name}")
    value = float(match.group(1))
    if value > ceiling:
        fail(
            f"{name} is {value} per tick, i.e. {value * 10:.0f} mass per second. "
            "Income constants are per tick; this reads as a per-second figure "
            "and would throttle production by a factor of ten"
        )

brain_source = (ROOT / "lua/AI/RedQueenBrain.lua").read_text(encoding="utf-8")
if "RedQueenRetireBuilders" not in brain_source:
    fail("registered builders must be retired on teardown")
if "RedQueenRetired" not in production_source:
    fail("the builder priority guard must honour retirement")
# The endgame veto must be graded, with the commander emergency as the only
# absolute case; a blanket zeroing is what stalled V8's late game.
if "commander-emergency" not in strategy_source:
    fail("only a commander emergency may veto endgame investment absolutely")
if "ExperimentalsUnderConstruction" not in strategy_source:
    fail("a project under construction must never have its target withdrawn")
# Hover and amphibious are separate engine navigation grids: the amphibious
# graph is blocked past MaxWaterDepthAmphibious (25) while hover crosses the
# surface at any depth. Collapsing them routes hover units on a graph they do
# not use, and IssueObjective's path gate then silently drops the whole task
# force. On Aeon and Seraphim that is the mainline army and every engineer --
# the SCMP_037 loss built 60 land units and lost 58 of them without ever
# ordering one. The pure Lua specs stub blueprints, so pin the split here too.
if 'if hash.AMPHIBIOUS or hash.HOVER then' in combat_source:
    fail(
        "CombatManager.UnitLayer must not lump HOVER in with AMPHIBIOUS; they "
        "are different navigation graphs and hover units get stranded"
    )
if 'return "Hover"' not in combat_source:
    fail("CombatManager.UnitLayer must route hover units onto the Hover layer")
for table_name in ("DefenseDispatchLayers", "WaterDispatchLayers", "LandDispatchLayers"):
    match = re.search(rf"{table_name}\s*=\s*\{{([^}}]*)\}}", combat_source)
    if not match:
        fail(f"missing combat dispatch layer table: {table_name}")
    if '"Hover"' not in match.group(1):
        fail(f"{table_name} must dispatch the Hover task force alongside Amphibious")
if "Hover = true" not in strategy_source:
    fail("the defense objective's DefenseLayers must enable the Hover layer")
if len(re.findall(r"(?m)^\s*Hover = ", strategy_source)) < 2:
    fail(
        "the defense objective must carry a Hover entry in both DefenseLayers "
        "and LayerPositions, or the hover task force is never dispatched"
    )

# A fleet's objective must be water it can reach. An enemy start is dry land --
# it is where a commander spawns -- so CanPath("Water", ...) to it fails by
# definition, which is why every offensive on the 93%-water SCMP_037 came out as
# `layer=Air`. FAF generates "Naval Area" markers next to every spawn and
# expansion for exactly this purpose.
world_model_source = (ROOT / "lua/AI/RedQueen/WorldModel.lua").read_text(encoding="utf-8")
if '"Naval Area"' not in world_model_source:
    fail("the world model must read generated Naval Area markers for water destinations")
if "GetNavalApproach" not in world_model_source:
    fail("the world model must expose GetNavalApproach for water destinations")
if "GetNavalApproach" not in strategy_source:
    fail(
        "offensive water objectives must resolve through GetNavalApproach; "
        "GetClosestEnemyStart can never return a water-reachable position"
    )
offensive = re.search(r"OffensiveLayers = \{(.*?)\n\}", strategy_source, re.S)
if not offensive:
    fail("missing the OffensiveLayers preference table")
for terrain in ("Naval", "Mixed"):
    entry = re.search(rf"{terrain} = \{{([^}}]*)\}}", offensive.group(1))
    if not entry or '"Water"' not in entry.group(1):
        fail(
            f"OffensiveLayers.{terrain} must offer the Water layer, or the fleet "
            "is never given an objective on a map that has water"
        )

# Shore artillery. T2 artillery reaches 115 and covers the standoff band that
# point defence (26/50) and torpedo launchers (50/60) cannot, which is exactly
# where a bombarding destroyer sits. Its 50 minimum radius is a dead zone around
# the gun, not around the base, so the battery is offset away from the threat
# axis; dropping it on the threatened edge with BuildClose is what would blind
# it. The pure Lua specs stub Constants, so the offset is range-checked here.
if "Artillery =" not in strategy_source:
    fail("the defence alert must express an Artillery target")
if "ShoreArtilleryPosition" not in production_source:
    fail("shore artillery must be sited relative to the threat axis")
if "UpdateShoreArtillery" not in production_source:
    fail("shore artillery must have a build path; no fortification builder produces it")
if "self:UpdateShoreArtillery(" not in production_source:
    fail("UpdateShoreArtillery must be called from the production pass")
if "T2Artillery" in fortification_source:
    fail(
        "artillery must not join the emergency fortification group: those "
        "builders use BuildClose, which sites the gun on the threatened edge "
        "inside its own 50 minimum radius"
    )
# Red Queen gates its own teching on energy income it never produced. Fields of
# Isis peaked at 212 a tick against a 250 Tech 3 gate and stalled there all
# match, finishing with three Tech 3 units to the opponent's forty-four. The
# ladder against that wall must survive, and must stay conditional on energy
# being the *only* thing missing, or it competes with a genuine mass shortage.
if "RedQueenEnergyBuilders" not in counter_source:
    fail("a power-construction builder group must exist; the tech gate needs a ladder")
if "RedQueenEnergyBuilders" not in production_source:
    fail("the energy builder group must be registered with the base managers")
if "T3EnergyProduction" not in counter_source or "T2EnergyProduction" not in counter_source:
    fail("power construction must cover both generator tiers")
# Size the generator to the gap. A Tech 3 generator is 57600 energy for 250 a
# tick against a Tech 2 at 12000 for 50, so reaching for Tech 3 to close a small
# shortfall over-invests fivefold -- that cost the Sentry Point victory.
if "LargeEnergyDeficit" not in counter_source:
    fail("power construction must size the generator to the energy shortfall")
if "economy.MassIncome >= massGate" not in counter_source:
    fail(
        "power must only be built when energy alone blocks teching; without the "
        "mass check it diverts engineers during a genuine mass shortage"
    )

# Tier readiness and capacity planning must stay separate. A Tech 3 upgrade is
# a Tech 3 unit the instant it starts and reports Tech 3 categories for the
# ~219 simulation seconds it takes to finish, so counting it as readiness
# suppresses every lower-tier combat builder while nothing can be built at all
# (observed on Fields of Isis). It must still count toward capacity, or planning
# orders a duplicate of the factory already building.
if "IsFactoryComplete" not in production_source:
    fail("tier readiness must distinguish completed factories from those still building")
if "domainPolicy.Ready = math.max(domainPolicy.Ready, tier)" not in production_source:
    fail("only a completed factory may raise the readiness that obsoletes lower production")
if "domainPolicy.Ready or domainPolicy.Highest" not in production_source:
    fail("IsObsoleteProfile must be able to use Ready, not only the capability ceiling")
# Selected per match profile, not applied globally and not decided inline. A map
# conditional at the point of use is a belief about what generalises, buried
# where nobody revisits it -- that is how scoping this by map size survived
# three maps and was then contradicted by the fourth.
if 'ProfileFlag("TierReadinessObsolescence")' not in production_source:
    fail("the obsolescence source must be selected by the match profile")

profile_source = (ROOT / "lua/AI/RedQueen/Profile.lua").read_text(encoding="utf-8")
if "Constants.Policy[name]" not in profile_source:
    fail("a profile must fall back to shared policy for values it does not override")
for forbidden in ("Constants.Policy[name] =", "Constants.Policy." ):
    pass
# Constants.Policy is one shared table for every army in the simulation's Lua
# state, so a profile overlay written there would leak between brains and, in a
# mixed match, into the opponent. Overrides must stay on the brain.
if re.search(r"Constants\.Policy\s*\[[^\]]+\]\s*=", profile_source) or re.search(
    r"Constants\.Policy\.\w+\s*=", profile_source
):
    fail("a profile must never assign into Constants.Policy; it is shared across armies")
brain_profile = (ROOT / "lua/AI/RedQueenBrain.lua").read_text(encoding="utf-8")
if "self.RedQueenProfile" not in brain_profile:
    fail("the profile must be exposed on the brain for builder conditions to reach")
# Capability must NOT be gated on completion: the engine consumes the old
# factory when an upgrade starts, so gating Highest makes a domain briefly
# report a lower tier and the exact-match dominance gates thrash. On Sludge that
# alone turned a victory (K/L 2.06) into a defeat (1.05).
if "if IsFactoryComplete(factory) then\n                    domainPolicy.Highest" in production_source:
    fail("Highest must not dip during an upgrade; only Ready is completion-gated")

# Artillery is a supplement, not a first response. Two brakes must survive:
# a late-game economic ladder, and the anchor's primary point defence standing
# first. Without them eight batteries appeared on a 0%-water map and turned a
# controlled Sentry Point victory (K/L 1.43) into a defeat (1.00).
if "ShoreArtilleryAllowance(state.MassIncome" not in production_source:
    fail("shore artillery must be paced by a late-game economic allowance")
for threshold in ("Tech3MinimumMassIncome", "ExperimentalMinimumMassIncome", "NukeMinimumMassIncome"):
    if threshold not in production_source:
        fail(f"the artillery allowance ladder must scale on {threshold}")
if "categories.DIRECTFIRE" not in production_source:
    fail(
        "shore artillery must check the anchor's point defence before building; "
        "point defence is cheaper and answers what artillery's 50 minimum cannot"
    )

match = re.search(r"(?m)^\s*ShoreArtilleryRearOffset\s*=\s*([0-9.]+)", constants_source)
if not match:
    fail("missing ShoreArtilleryRearOffset")
offset = float(match.group(1))
if not 10 <= offset <= 45:
    fail(
        f"ShoreArtilleryRearOffset is {offset}; outside 10-45 the battery either "
        "sits inside its own 50 minimum radius or pushes close attackers past "
        "its 115 maximum"
    )

# Static anti-navy. Torpedo launchers are water-only (BuildOnLayerCaps
# LAYER_Land = false, 1.5 minimum water depth), so they cannot be sited by
# BuildClose from a base whose coordinates are on land. The strategy director
# resolves a water cell near the threatened anchor and that position both gates
# the target and places the structure.
if "Torpedo =" not in strategy_source:
    fail("the defence alert must express a Torpedo target")
# Torpedo defences are gated on intelligence, not inference. cluster.Naval is
# only ever set from layer-bucketed observations whose confidence decays to zero
# as a contact goes stale, whereas the local `naval` has been back-filled from
# unclassified surface threat near a water anchor. Committing 450+ mass per
# launcher -- more than a Tech 2 point defence -- to a contact nobody has seen
# is exactly the waste this gate exists to prevent.
if "local observedNaval = cluster.Naval or 0" not in strategy_source:
    fail(
        "torpedo defences must key on the observed cluster.Naval, never on the "
        "back-filled naval figure, or unscouted surface threat builds launchers"
    )
match = re.search(
    r"(?m)^\s*TorpedoMinimumObservedNavalThreat\s*=\s*([0-9.]+)", constants_source
)
if not match:
    fail("missing TorpedoMinimumObservedNavalThreat")
sighting = float(match.group(1))
if not 1 <= sighting <= 30:
    fail(
        f"TorpedoMinimumObservedNavalThreat is {sighting}; a Tech 1 frigate "
        "carries 6 and a Tech 2 destroyer 14 to 23, so outside 1-30 the gate "
        "either fires on a faded blip or ignores a real fleet"
    )
if "NearestWaterPosition" not in strategy_source:
    fail("torpedo defences need a resolved water position; they cannot be built on land")
if "WaterPosition" not in production_source:
    fail("the torpedo build path must use the alert's resolved water position")
if "UpdateShoreTorpedo" not in production_source:
    fail("torpedo defences must have a build path; no fortification builder produces them")
if "self:UpdateShoreTorpedo(" not in production_source:
    fail("UpdateShoreTorpedo must be called from the production pass")
if "categories.ANTINAVY" not in production_source:
    fail("existing torpedo cover must be counted with the ANTINAVY category")
for naval_type in ("T1NavalDefense", "T2NavalDefense", "T3NavalDefense"):
    if naval_type in fortification_source:
        fail(
            f"{naval_type} must not join the emergency fortification group: "
            "those builders use BuildClose, which cannot site a water-only "
            "structure from a land anchor"
        )
# T3NavalDefense is Cybran-only. Offering it to another faction makes
# AIExecuteBuildStructure blacklist the type in AntiSpamList, which is module
# state shared by every army in the Lua state -- poisoning it for a Cybran ally.
if '"T3NavalDefense"' in production_source and not re.search(
    r'faction == 3\s*\n\s*and \{\s*"T3NavalDefense"', production_source
):
    fail("T3NavalDefense is Cybran-only and must sit behind a faction index 3 gate")

combat_source_extra = combat_source
if "CommitmentThreatRatio" not in combat_source_extra:
    fail("offensive commitment must be gated on observed threat at the destination")
economy_source = (ROOT / "lua/AI/RedQueen/EconomyManager.lua").read_text(encoding="utf-8")
if "ArmyDeficit" in economy_source.split("CanExpandProduction", 1)[-1][:400]:
    fail("factory expansion must not be gated on the army deficit")
if 'GetNumCategoryUnits("Engineers", category)' not in fortification_source:
    fail("emergency engineer tier checks must use the location engineer manager")
if 'BuilderName = "Red Queen Emergency T1 Point Defense"' not in fortification_source:
    fail("early defense alerts must retain a T1 point-defense fallback")
if 'PlatoonTemplate = "T1EngineerBuilder"' in fortification_source:
    fail("T1EngineerBuilder is not a registered FAF platoon template")
if 'return "Annihilation"' not in context_source:
    fail("Annihilation must remain distinct from Supremacy")
for required in ("AnchorKind", "Criticality", "DefenseLayers"):
    if required not in strategy_source:
        fail(f"critical defense anchor contract is missing: {required}")
for required in (
    "ApplyFactoryCapacityPolicy",
    "GetUnassignedEngineers",
    "UpdateFactoryAssistance",
    "HasManagedEmergencyDefense",
    "UpdateEmergencyDefense",
):
    if required not in production_source:
        fail(f"production execution contract is missing: {required}")
for required in ("ObservationCombatThreat", 'observation.Layer == "Water"'):
    if required not in intel_source:
        fail(f"movement-layer cluster contract is missing: {required}")
for required in (
    "CumulativeAirLosses",
    "GunshipAirLossBaseline",
    "Constants.Policy.AirLossWindowSeconds",
):
    if required not in strategy_source:
        fail(f"gunship loss-baseline contract is missing: {required}")
for required in ("landAnchor", "waterAnchor"):
    if required not in strategy_source:
        fail(f"defense layers must fall back to the threatened anchor: {required}")
if "SelectFactoryType = function(self, counts, targets)" not in production_source:
    fail("direct factory expansion must consume the capacity policy targets")
if "Constants.Policy.AnchorProximityTolerance" not in intel_source:
    fail("anchor assignment must resolve co-located anchors by criticality")
for required in ("Engine Lua failures:", "Red Queen Lua failures:"):
    if required not in analyzer_source:
        fail(f"log analysis must report Lua failure attribution: {required}")

# The analyzer decides whether an engine "Invalid location" warning is ours by
# matching the location name; the simulation decides the same thing with
# `string.sub(name, 1, 5) == "RQFB_"`. The two must agree, and they drifted: a
# numeric-only pattern could not see the lifecycle fixture's RQFB_LIFECYCLE_TEST,
# so in the one run built to destroy and rebuild bases our own failure was filed
# as FAF's. Nothing but this connects the producer to the consumer.
owned_location = re.search(
    r'RED_QUEEN_OWNED_LOCATION = re\.compile\(r"([^"]+)"\)', analyzer_source
)
if not owned_location:
    fail("analyze-log.py must define RED_QUEEN_OWNED_LOCATION to attribute invalid locations")
owned_location_pattern = re.compile(owned_location.group(1))
registered_locations = set()
for source_path in sorted((ROOT / "lua").rglob("*.lua")):
    for literal in re.findall(
        r'"(RQFB_[A-Za-z0-9_%]+)"', source_path.read_text(encoding="utf-8")
    ):
        # `RQFB_%d_%d` is a format, so score it as a name it would produce.
        registered_locations.add(literal.replace("%d", "7"))
if not registered_locations:
    fail("no RQFB_ location names found in lua/: the attribution contract checks nothing")
for name in sorted(registered_locations):
    if not owned_location_pattern.search(name):
        fail(
            f"analyze-log.py cannot attribute the location name {name}, which the "
            "simulation registers: an invalid-location warning for our own site "
            "would be reported as FAF's"
        )
for required in (
    "GetBestExposedEconomyTarget",
    "GetStrategicPicture",
    "GunshipCounter",
    "LandLossWindowSeconds",
    "TransportRequested",
    "FocusWeights",
    "EconomicReadiness",
    "MajorProjectSlots",
    "GetObservedArmyClusters",
    "UpdateDefenseAlert",
):
    if required not in strategy_source:
        fail(f"adaptive strategy contract is missing: {required}")
for required in (
    "T1Gunship",
    "T2AirGunship",
    "T3AirGunship",
    "T3AirFighter",
    "T1LandFactoryUpgrade",
    "T2LandFactoryUpgrade",
    "T4LandExperimental1",
    "T4SeaExperimental1",
    "T3StrategicMissile",
    "PriorityFunction",
    "StrategicFocusMinimumScore",
    "RedQueenTierDominanceBuilders",
):
    if required not in counter_source:
        fail(f"counter-production contract is missing: {required}")

for forbidden in (
    "Tech2StartSeconds",
    "Tech3StartSeconds",
    "ExperimentalStartSeconds",
    "NukeStartSeconds",
    "AirDropStartSeconds",
    "PressureStartSeconds",
    "TechTarget",
    "demand.Endgame",
):
    if forbidden in strategy_source or forbidden in counter_source:
        fail(f"elapsed-time strategy contract returned: {forbidden}")

for required in ("armySetup.AIBase", "manager.BaseSettings"):
    if required not in production_source:
        fail("counter builders must wait for FAF's native adaptive base setup")

for required in (
    "UpdateTierPolicy",
    "IsObsoleteProfile",
    "RedQueenEmergencyFortificationBuilders",
    "SelectForwardBaseSite",
    "RevalidateEstablishedForwardBases",
    "T3StrategicMissileDefense",
):
    if required not in production_source:
        fail(f"mid-game production contract is missing: {required}")

forward_package_match = re.search(
    r"ForwardBasePackage\s*=\s*function.*?\n\s*end,",
    production_source,
    re.DOTALL,
)
if not forward_package_match:
    fail("forward base package function is missing")
if '"T3StrategicMissile"' in forward_package_match.group(0):
    fail("forward bases must not queue strategic nuclear launchers")

lua_files = sorted(ROOT.rglob("*.lua"))
import_pattern = re.compile(r'import\("' + re.escape(MOD_PREFIX) + r'([^"\n]+)"\)')
for source_path in lua_files:
    source = source_path.read_text(encoding="utf-8")
    if "\t" in source:
        fail(f"tab indentation found in {source_path.relative_to(ROOT)}")
    if "ClassSimple" in source and re.search(r"(?m)^\s+OnCreate\s*=\s*function", source):
        fail(
            "ClassSimple constructors must use __init: "
            f"{source_path.relative_to(ROOT)}"
        )
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("--", 1)[0]
        code = re.sub(r'"(?:\\.|[^"\\])*"', "", code)
        code = re.sub(r"'(?:\\.|[^'\\])*'", "", code)
        if re.search(r"[\w\)\]]\s*%\s*[\w\(\[]", code):
            fail(
                "FAF Lua 5.0 does not support the % operator: "
                f"{source_path.relative_to(ROOT)}:{line_number}"
            )
    for imported in import_pattern.findall(source):
        target = ROOT / imported
        if not target.is_file():
            fail(
                f"broken mod import in {source_path.relative_to(ROOT)}: "
                f"{MOD_PREFIX}{imported}"
            )

# --- Module export convention ----------------------------------------------
#
# FAF's import() runs a file in a fresh environment and returns *that
# environment*, discarding whatever the file returns. So a module that exports
# with `return { ... }` is invisible to the engine: every field access on it
# raises "access to nonexistent global variable" from system/config.lua's strict
# global metatable.
#
# This is not hypothetical and it is not caught by the Lua contracts, because
# `dofile` -- which the specs use -- honours the return value that the engine
# ignores. Experimentals.lua shipped that way, passed a green suite, and failed
# on the first cycle of every match.
for source_path in sorted((ROOT / "lua").rglob("*.lua")):
    text = source_path.read_text(encoding="utf-8")
    if re.search(r"(?m)^return\s*\{", text):
        fail(
            "module exports with a top-level `return {` table, which FAF's "
            "import() discards; assign globals instead: "
            f"{source_path.relative_to(ROOT)}"
        )

# --- Experimental classification -------------------------------------------
#
# The catalog exists because FAF's own template keys cannot be trusted: three of
# them resolve to something other than what the key names. These guards keep the
# two failure modes closed -- a builder that bypasses the catalog, and a catalog
# entry that quietly readmits a rejected key.
experimental_source = (ROOT / "lua/AI/RedQueen/Experimentals.lua").read_text(encoding="utf-8")

for template, blueprint in (
    ("T4SeaExperimental1", "urb0101"),
    ("T4SeaExperimental1", "xsb0101"),
    ("T4Artillery", "uab2302"),
    ("T4Artillery", "urb2302"),
):
    if blueprint not in experimental_source:
        fail(
            "Experimentals.lua must keep recording that "
            f"{template} can resolve to {blueprint}, which is not an experimental"
        )

# A rejected blueprint must never appear as a catalog entry's expected unit.
# Scope to the catalog half: the Rejected table names these deliberately, which
# is the whole point of keeping it.
if not re.search(r"(?m)^Rejected = \{", experimental_source):
    fail("Experimentals.lua must keep a Rejected table documenting the bad keys")
catalog_source = re.split(r"(?m)^Rejected = \{", experimental_source, maxsplit=1)[0]
for rejected in ("urb0101", "xsb0101", "uab2302", "urb2302"):
    if re.search(r'Blueprint\s*=\s*"' + rejected + r'"', catalog_source):
        fail(
            f"{rejected} is not an experimental and must never be a catalog "
            "Blueprint; it belongs in Rejected"
        )

# Every experimental builder must gate through the classification, never on a
# bare template key. A builder whose BuildStructures names a T4 key must pass
# that same key to the classified condition.
for match in re.finditer(
    r'BuilderName = "(Red Queen (?:Assault|Siege) Experimental[^"]*)"(.{0,1400}?)\n    \},',
    counter_source,
    re.S,
):
    name, body = match.group(1), match.group(2)
    gate = re.search(r'\{ ShouldBuildClassifiedExperimental, \{ "([A-Za-z0-9]+)" \} \}', body)
    built = re.search(r'BuildStructures = \{ "([A-Za-z0-9]+)" \}', body)
    if not gate:
        fail(f"{name} must gate on ShouldBuildClassifiedExperimental with its template key")
    elif not built:
        fail(f"{name} must name the structure it builds")
    elif gate.group(1) != built.group(1):
        fail(
            f"{name} gates on {gate.group(1)} but builds {built.group(1)}; "
            "the gate and the build must be the same key"
        )

if "ShouldBuildLandExperimental" in counter_source or "ShouldBuildNavalExperimental" in counter_source:
    fail(
        "the role-blind experimental conditions are replaced by "
        "ShouldBuildClassifiedExperimental; a map-type gate cannot tell a "
        "Tech 1 land factory from an experimental"
    )

# The path gate must ask about the entry's own layer. Passing a literal layer
# would reintroduce the graph mismatch the classification exists to prevent.
if "Experimentals.CanAct(world, entry, world.StartPosition)" not in counter_source:
    fail("the experimental gate must test reachability via Experimentals.CanAct on the entry's layer")

# Volume is a flow, not a stock: the owned count must be *added into* the target
# rather than capping it, or production stops once the count is met. A stock
# ceiling in either direction is the defect -- the original could only ever be 1,
# and replacing it with a larger stock target regressed every measured Aeon run.
if "(forces.Experimentals or 0) + concurrent" not in strategy_source:
    fail(
        "the experimental target must add the owned count to a concurrency "
        "allowance, so owning some is not a reason to stop building"
    )
if re.search(r"demand\.DesiredExperimentals = weights\.Experimental >=", strategy_source):
    fail("the fixed experimental ceiling is replaced by a flow target")
if "ExperimentalFleetMaximum" in strategy_source or "ExperimentalMassIncomePerUnit" in strategy_source:
    fail("the stock-based fleet ceiling is replaced by a concurrency allowance")

# Each role needs its own in-flight allowance, or the second concurrency slot
# fills with another assault walker and the game-enders and utility
# experimentals are classified but never built.
# The role reservation must lower a crowded role's rank, never veto it: the
# in-flight count cannot tell Red Queen's projects from the engine's, so a veto
# fires on FAF's own work and locks Red Queen's builders out for the match.
if "ExperimentalRoleCrowdingPenalty" not in counter_source:
    fail("a crowded role must be ranked down rather than blocked")
if re.search(r"if not HasRoleSlot\(", counter_source):
    fail(
        "the per-role veto deadlocked against FAF's own experimental projects; "
        "it is replaced by a priority penalty"
    )
if "Experimentals.RoleForBlueprint" not in counter_source:
    fail("in-flight projects must be classified by blueprint to be counted per role")
for role in ("Economy", "Intel"):
    if f"Experimentals.Roles.{role}" not in counter_source:
        fail(f"the {role} experimental role must be reachable through the build path")
for template in ("T4EconExperimental", "T4SatelliteExperimental"):
    if template not in counter_source:
        fail(f"{template} needs a builder for its role to be more than a label")

# --- Route safety must distinguish unknown from safe -------------------------
#
# Route threat is summed from observations, so an unscouted route reports 0 --
# the same value as a route watched and found clear -- and then outscores every
# route with a known minor risk. Three of four expansions on Seton's Clutch lost
# their engineer, two dispatched at route threat 0.0.
world_source = (ROOT / "lua/AI/RedQueen/WorldModel.lua").read_text(encoding="utf-8")
intel_source = (ROOT / "lua/AI/RedQueen/IntelManager.lua").read_text(encoding="utf-8")

if "GetCoverageNear" not in intel_source:
    fail(
        "the intel manager must be able to report coverage; threat alone cannot "
        "distinguish observed-and-clear from never-observed"
    )
# Coverage is reported so a match can be diagnosed, but charging it as risk was
# measured and rejected: it cost expansion without saving an engineer, because
# the losses happen on fully covered routes. Keep the measurement, and keep the
# reason discoverable so it is not silently re-added.
if "RouteCoverage" not in world_source:
    fail("the chosen forward site must record how well its route was observed")
if "UnknownRoutePresumedThreat" in world_source:
    fail(
        "presumed route risk was measured on Seton's Clutch and rejected -- it "
        "cost peak mass 11.5 to 6.7 and saved no engineer; see "
        "docs/large-map-expansion-investigation.md before reinstating it"
    )

# Reachability must be asked on the traveller's own graph. Every engineer in the
# game crosses water, so a hardcoded "Land" describes none of them.
if re.search(r'CanPath\("Land", origin, candidate\.Position\)', world_source):
    fail(
        "forward-base siting must path on the engineer's layer; every engineer "
        "is amphibious or hover, never land-only"
    )
if "UnitTravelLayer(engineer)" not in production_source:
    fail("the forward-base layer must be derived from the engineer's motion type")
for motion in ("RULEUMT_Hover", "RULEUMT_AmphibiousFloating"):
    if motion not in production_source:
        fail(f"the motion-type map must cover {motion}")

# --- Engineers are established, and routes are re-judged in transit ---------
#
# An engineer death stalls expansion, economy and production together, and used
# to be discarded outright by RecordUnitLoss. A shortfall is answered by
# building more, not by waiting for income to recover -- the shortfall is what
# suppresses income.
if "RecentEngineerLosses" not in strategy_source:
    fail("engineer losses must be recorded; they were previously discarded outright")
if "UpdateEngineerDemand" not in strategy_source:
    fail("engineers need an establishment target, not a fixed floor")
if "(forces.Experimentals or 0) + concurrent" not in strategy_source:
    pass  # experimental flow target is guarded above
for term in (
    "Constants.Policy.EngineerLossReplacementFactor",
    "Constants.Policy.EngineersPerForwardBase",
):
    if term not in strategy_source:
        fail(f"the engineer target must include {term}")
if "RedQueenEngineerBuilders" not in counter_source:
    fail("the engineer target needs producers to act on it")
if "RedQueenEngineerBuilders" not in production_source:
    fail("the engineer builder group must be registered per base")

# FAF's engineer rule is per location, so it scales with base count rather than
# need: 21 bases produced 101 engineers against a target of 18. A global target
# only binds if the native builders are held to it as well.
if "ApplyEngineerPolicy" not in production_source:
    fail("native engineer production must be held to the army's engineer target")
if not re.search(r"self:ApplyEngineerPolicy\(", production_source):
    fail("the engineer establishment policy must actually be applied each cycle")
# But it must not cut at the target. `DesiredEngineers` is derived from factory
# count, so suppressing native production at it makes engineers the constraint
# on building factories -- measured across two Crossfire cells as 3 engineers
# where 15-20 had run, and 6 factories where 26 had been built. The ceiling has
# to be its own number, scaled by what there is to feed.
# The retreat pass has to run, not merely exist. Native builders keep sending
# engineers to extractors and expansions, and nothing else watches them once
# they are under way -- which is how they were observed reaching the enemy base.
if "UpdateEngineerRetreat" not in production_source:
    fail("the production cycle must be able to pull engineers out of danger")
production_update = re.search(
    r"    Update = function\(self\)(.*?)\n    end,", production_source, re.S)
if not production_update:
    fail("ProductionManager:Update must be a method so its body can be checked")
elif "self:UpdateEngineerRetreat()" not in production_update.group(1):
    fail("the engineer retreat pass must be applied every cycle, not merely defined")

# The commander pass has to run, and its leash has to keep the commander out of
# the middle of the map. Observed wandering alone to the centre, which no threat
# reading refuses because nothing has arrived there yet -- so the rule is
# distance, and a Lua spec cannot see the shipped number because it stubs
# Constants. A 5 km map is 256 units across, so anything at or above half that
# permits reaching the centre of the smallest map Red Queen plays.
if "UpdateCommanderTasking" not in production_source:
    fail("the production cycle must keep the commander home and working")
elif "self:UpdateCommanderTasking()" not in (production_update.group(1) if production_update else ""):
    fail("the commander pass must be applied every cycle, not merely defined")
leash = re.search(r"(?m)^\s*CommanderLeashRadius\s*=\s*(\d+)", constants_source)
if not leash:
    fail("missing CommanderLeashRadius: the commander needs a distance leash")
elif int(leash.group(1)) >= 128:
    fail(
        "CommanderLeashRadius is %s, at or beyond half of a 5 km map (256 units) "
        "-- that permits the wandering to the map centre this rule exists to stop"
        % leash.group(1)
    )

# Engineer replacement must stay below combat production, and a Lua spec cannot
# see the shipped number because it stubs Constants. Measured behaviour: the
# shared replacement priority reached 930 after four engineer deaths and 1000
# after eight, which stopped unit production in every factory at every tier.
ceiling = re.search(
    r"(?m)^\s*EngineerReplacementPriorityCeiling\s*=\s*(\d+)", constants_source)
combat_priorities = [
    int(m) for m in re.findall(
        r'BuilderName = "Red Queen T[23] (?:Land|Air) (?:Dominance|Factory Tech)"[^}]*?'
        r"Priority = (\d+)", counter_source, re.S)
]
if not ceiling:
    fail("missing EngineerReplacementPriorityCeiling: engineer demand needs a bound")
elif combat_priorities and int(ceiling.group(1)) >= min(combat_priorities):
    fail(
        "EngineerReplacementPriorityCeiling is %s, at or above a combat builder "
        "(%s). Replacing engineer losses would outrank the army that prevents "
        "them, which is the observed failure" % (
            ceiling.group(1), min(combat_priorities))
    )

# Engineer survival. Native `EngineerMoveWithSafePath` returns true when the
# threat-constrained path fails, so the caller issues the build order and the
# engineer walks into whatever is there -- observed in a match and reproduced
# against the shipped native source. The hook must refuse, and must be scoped to
# Red Queen brains: the function is global to every AI in the simulation, so an
# unguarded replacement would change the opponents Red Queen is measured
# against.
platoon_hook = (ROOT / "hook/lua/AI/aiutilities.lua").read_text(encoding="utf-8")
if "EngineerMoveWithSafePath" not in platoon_hook:
    fail("the engineer travel hook is missing; native accepts an unsafe route")
# The hook must live in the file that *defines* the symbol it captures. A first
# attempt hooked platoon.lua, where the function is only used (as
# `AIUtils.EngineerMoveWithSafePath`), so capturing the bare global read a name
# absent from that environment -- `system/config.lua`'s strict metatable raised,
# the import of platoon.lua failed, and the simulation crashed before the first
# frame. Nothing in the gate caught it because the contracts stub the hook's
# environment.
for hook_relative, captured in (
    ("hook/lua/AI/aiutilities.lua", "EngineerMoveWithSafePath"),
    ("hook/lua/sim/FactoryBuilderManager.lua", "FactoryBuilderManager.BuilderParamCheck"),
    ("hook/lua/platoon.lua", "Platoon.ForkThread"),
):
    source = (ROOT / hook_relative).read_text(encoding="utf-8")
    symbol = captured.split(".")[0]
    if symbol not in source:
        fail(
            "%s captures %s, which that file's environment does not define; hook "
            "the file that defines the symbol or the strict global metatable will "
            "abort its import" % (hook_relative, captured)
        )
else:
    if "NativeEngineerMoveWithSafePath" not in platoon_hook:
        fail("the engineer travel hook must call through to the native implementation")
    # Scoped to this hook's own body: the thread hook above also mentions the
    # marker, so a file-wide substring check passes even when this replacement
    # applies to every AI in the match.
    travel_hook = re.search(
        r"EngineerMoveWithSafePath = function\(aiBrain, unit, destination\)(.*?)\nend",
        platoon_hook, re.S)
    if not travel_hook:
        fail("the engineer travel hook must be a function of (aiBrain, unit, destination)")
    elif "RedQueenLobbyPersonality" not in travel_hook.group(1):
        fail(
            "the engineer travel hook must be scoped to Red Queen brains; it is a "
            "global function shared with every other AI in the match"
        )
    if "return false" not in platoon_hook:
        fail("the engineer travel hook must refuse an unsafe assignment")

survival = (ROOT / "lua/AI/RedQueen/EngineerSurvival.lua").read_text(encoding="utf-8")
if "return {" in survival:
    fail("EngineerSurvival must export globals; import() discards a returned table")
# Refusing on an absent route would break transport-served expansion, which
# native handles perfectly well. The module must judge danger, not pathability.
if "if threat == nil then" not in survival or "return true, \"unassessed\"" not in survival:
    fail("an unassessable route must be left to native transport handling, not refused")

# The director reads sibling modules through `self.Modules` -- built factory
# counts for the engineer target, the scouting summary for scout production.
# Nothing assigned that table for the life of the project, so both readers took
# their absent-module fallback silently: zero built factories all match, and
# scout production pinned to its floor. Specs missed it because they inject
# `director.Modules` directly, which is exactly why this check reads the brain.
brain_source = (ROOT / "lua/AI/RedQueenBrain.lua").read_text(encoding="utf-8")
if not re.search(r"modules\.Strategy\.Modules\s*=\s*modules", brain_source):
    fail(
        "the brain must give the strategy director the module table; without it "
        "self.Modules is nil and the engineer target and scout production "
        "silently use their fallbacks"
    )

# Scouting has to actually run. Red Queen's intel comes only from sampling its
# own mobile units, so without a dispatch pass nothing ever observes a position
# the army has not already walked into -- and the commitment gate then judges a
# wave against a threat of 0 at the destination it is attacking.
if "MaintainScouts" not in combat_source:
    fail("the combat cycle must have a scouting pass")
combat_update = re.search(r"    Update = function\(self\)(.*?)\n    end,", combat_source, re.S)
if not combat_update:
    fail("CombatManager:Update must be a method so its body can be checked")
elif "self:MaintainScouts()" not in combat_update.group(1):
    fail("the scouting pass must be applied every combat cycle, not merely defined")
for term in ("ScoutingConfig.Create(ScenarioInfo.Options)", "self.RedQueenScouting = scouting",
             "scouting mode=%s production=%s dispatch=%s"):
    if term not in brain_source:
        fail(f"scouting isolation must be applied and logged at brain startup: {term}")

# Cover sizing is a calibration too, and the same blindness applies: a spec
# stubs Constants and cannot see the shipped fraction. Measured across 21 cells,
# committing six or more units to forward-base cover cost 0.30 mass kill/loss
# and 19.7 peak income against the same cells' baseline, while committing fewer
# than six cost 0.11 and gained 4.1. The product of fraction and undefended
# multiple is the cap on all cover at once; above roughly a third of the army it
# is a raid rather than a garrison.
fraction = re.search(r"(?m)^\s*GarrisonForceFraction\s*=\s*([0-9.]+)", constants_source)
multiple = re.search(r"(?m)^\s*GarrisonUndefendedMultiple\s*=\s*([0-9.]+)", constants_source)
if not fraction or not multiple:
    fail("cover sizing needs both GarrisonForceFraction and GarrisonUndefendedMultiple")
elif float(fraction.group(1)) * float(multiple.group(1)) > 0.35:
    fail(
        "cover may draw up to %.0f%% of the army at once (GarrisonForceFraction %s "
        "times GarrisonUndefendedMultiple %s). Six or more units on forward bases "
        "cost 0.30 kill/loss and 19.7 income across 21 cells"
        % (100 * float(fraction.group(1)) * float(multiple.group(1)),
           fraction.group(1), multiple.group(1))
    )

# Where the cut sits is a calibration, and Lua specs stub Constants -- so no
# contract can see the shipped number. Measured native engineer counts across
# ten baseline cells: 24, 35, 44, 51, 53, 55, 56, 63, 66, and one runaway at
# 101. A floor at or below the pack cuts armies that were not in trouble: set
# to the target's own maximum of 18 it pinned Sentry Point at 18 against a
# natural 53, taking income from 32.2 to 7.3, and turned a Seton's victory into
# a defeat. Raise this only against a new measurement of what armies hold.
suppression_floor = re.search(
    r"(?m)^\s*EngineerSuppressionMinimum\s*=\s*([0-9.]+)", constants_source)
if not suppression_floor:
    fail("missing EngineerSuppressionMinimum: the engineer cut needs a floor")
elif float(suppression_floor.group(1)) < 40:
    fail(
        f"EngineerSuppressionMinimum is {suppression_floor.group(1)}, at or below the "
        "engineer counts armies were measured holding (24-66). A floor there cuts "
        "ordinary production, not a runaway: it cost 4x income on Sentry Point"
    )

policy_match = re.search(
    r"    ApplyEngineerPolicy = function\(.*?\n    end,\n", production_source, re.S)
if not policy_match:
    fail("ApplyEngineerPolicy must be a manager method so its body can be checked")
else:
    policy_body = policy_match.group(0)
    if "EngineerSuppressionPerFactory" not in policy_body:
        fail("engineer suppression must scale with capacity, not cut at the target")
    if re.search(r"held >= target\b", policy_body):
        fail("engineer suppression must not cut at the engineer target itself")
if "RedQueenEngineerDisabled" not in production_source:
    fail("engineer suppression must go through the guarded priority, never a definition")

# --- Forward-base packages are an ordered build plan --------------------------
#
# Every tier used to lead with T1LandFactory and T1Radar, so an engineer at a
# contested site raised a 240-mass factory and a radar before its first gun.
# Only 21% of started bases established across the 21-cell matrix.
if "ForwardBaseTier" not in production_source:
    fail("forward-base packages must be tiered, with each tier declaring its own minimum")
if re.search(r"for _, buildingType in pairs\(package\) do", production_source):
    fail(
        "the forward-base package is an ordered build plan: iterate it with "
        "ipairs, since pairs gives no ordering contract and the simulation must "
        "be deterministic"
    )
if "for _, buildingType in ipairs(package) do" not in production_source:
    fail("the forward-base package must be queued in its declared order")
# Each tier must lead with a defence rather than infrastructure.
for tier_block in re.findall(r"Package = \{([^}]*)\}", production_source):
    first = re.search(r'"([A-Za-z0-9]+)"', tier_block)
    if first and ("Factory" in first.group(1) or "Radar" in first.group(1)):
        fail(
            "a forward-base tier must lead with a defence, not "
            f"{first.group(1)} -- nothing else shoots while the engineer is exposed"
        )

# A route authorised once cannot carry a 175-second walk against a 180-second
# intel lifetime, so it is re-judged in transit and the engineer released.
if "ForwardBaseRecallReason" not in production_source:
    fail("an in-flight forward base must have its route re-judged")
if "IssueClearCommands" not in production_source:
    fail("a recall must clear the engineer's queued structures to release it")
if "Constants.Policy.ForwardBaseRecallThreatRatio" not in production_source:
    fail(
        "a recall needs a margin over the dispatch limit, or a committed "
        "engineer thrashes on ordinary noise"
    )

# --- Teams follow the map, not the slot numbering ---------------------------
#
# Saltrock Colony numbers its six starts interleaved, so pairing them by sorted
# slot index puts every army's nearest neighbour on the opposing team: allies
# about 285 apart on a 512 map against enemies about 100 apart. That silently
# misdescribes every team result measured on such a map.
hook_source = (ROOT / "hook/lua/aibrains/index.lua").read_text(encoding="utf-8")
if "RedQueenProximityTeams" not in hook_source:
    fail("team layouts must group contestants by start proximity, not slot order")
if re.search(r"setup\.Team = 2 \+ math\.floor\(\(index - 1\) / teamSize\)", hook_source):
    fail(
        "sequential slot pairing is replaced by proximity grouping; on an "
        "interleaved map it makes each army's nearest neighbour an enemy"
    )
if "RedQueenStartPosition" not in hook_source:
    fail("proximity grouping needs the scenario's own start markers")

# A layout hands every slot to an AI, so the launching player only consumes a
# start. Verified that the engine runs a session with no human at all, which is
# what lets a 2v2v2 fit a six-army map.
smoke_source = (ROOT / "scripts/run-smoke.sh").read_text(encoding="utf-8")
if 'FAF_NO_HUMAN:=1' not in smoke_source:
    fail("team layouts must default to no human player, or a start is wasted")
overlay_source = (ROOT / "scripts/prepare-runtime.py").read_text(encoding="utf-8")
if "os.environ.get('FAF_NO_HUMAN') == '1'" not in overlay_source:
    fail("the launch overlay must act on FAF_NO_HUMAN, not merely mention it")
if "playerOptions.Human = false" not in overlay_source:
    fail("the no-human overlay must actually hand the player's start to an AI")


# The game's Lua flattens a multi-return call into the generic-for's control
# variables, so `for _, x in ipairs(f())` where f returns two values raises
# "loop over expected but got number" at runtime. LuaJIT accepts it happily, so
# the contract gate cannot see it -- it cost 177 failed production passes in a
# run that had already been reported as a result. Bind such a call to a local
# first.
MULTI_RETURN_LINE = re.compile(r"^\s*return\s+[^,\n(){}]+,\s*\S", re.M)
for lua_path in lua_files:
    lua_source = lua_path.read_text(encoding="utf-8")
    multi_return = set()
    for method in re.finditer(r"(\w+)\s*=\s*function\(self[^)]*\)(.*?)\n    end,",
                              lua_source, re.S):
        if MULTI_RETURN_LINE.search(method.group(2)):
            multi_return.add(method.group(1))
    for use in re.finditer(r"in i?pairs\(self:(\w+)\(\)", lua_source):
        if use.group(1) in multi_return:
            fail(
                f"{lua_path.name}: self:{use.group(1)}() returns several values and is "
                "iterated directly; bind it to a local first or the game's Lua "
                "raises 'loop over expected but got number'"
            )

print(f"Validated {len(lua_files)} Lua files and The Red Queen mod contract")
