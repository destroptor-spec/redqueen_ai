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
semantic_version_match = re.search(
    r'(?m)^Version\s*=\s*"([^"]+)"',
    (ROOT / "lua/AI/RedQueen/Constants.lua").read_text(encoding="utf-8"),
)
registration_version_match = re.search(
    r'(?m)^\s*Version\s*=\s*"([^"]+)"',
    (ROOT / "lua/AI/CustomAIs_v2/RedQueenAI.lua").read_text(encoding="utf-8"),
)
if not vault_version_match or not semantic_version_match or not registration_version_match:
    fail("release version metadata is incomplete")
if semantic_version_match.group(1) != registration_version_match.group(1):
    fail("semantic version differs between constants and lobby registration")
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
for required in ("GetBlip", "IsSeenNow", "IsSeenEver", "IsOnRadar"):
    if required not in intel_source:
        fail(f"verified intel contract is missing: {required}")
if "local highestObservedTech = 1" not in intel_source:
    fail("observed enemy tech must be recomputed from surviving intel")
if "- categories.TRANSPORTFOCUS" not in combat_source:
    fail("combat waves must leave transports available to native transport plans")
if "IsOwnedByBrain" not in production_source or "GetRebuildableForwardBaseSites" not in production_source:
    fail("forward-base lifecycle must enforce ownership and support destroyed-site rebuilding")
if 'GetNumCategoryUnits("Engineers", category)' not in fortification_source:
    fail("emergency engineer tier checks must use the location engineer manager")
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
