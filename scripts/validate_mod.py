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

print(f"Validated {len(lua_files)} Lua files and The Red Queen mod contract")
