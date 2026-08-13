#!/usr/bin/env python3
"""Disable the flash-triggering foam layer on all Kena UIWS surfaces."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


PARAMETER = "Foam_Opacity"
SWITCH = "Foam?"
TARGET_VALUE = 0.0

WATER_PARENT = "M_Water_UIWS"
WATER_GUID = "{CB569CB5-4FF6-722B-35EE-E89BB3D5DF72}"
RIVER_PARENT = "M_River_UIWS"
RIVER_GUID = "{7C07BE19-4045-A520-999D-148633CAA9D0}"

# Every build-10345375 UIWS surface instance whose Foam? static switch is
# enabled. Waterfall/cascade materials use a separate M_Waterfall_* family and
# are intentionally absent. Instances where Foam? is already disabled and
# opaque instances without Foam_Opacity are also absent because there is no
# active foam contribution to neutralize.
EXPECTED: dict[str, tuple[float, str, str]] = {
    "MI_Pond_UIWS": (0.2, WATER_PARENT, WATER_GUID),
    "MI_River_Forge": (0.1, RIVER_PARENT, RIVER_GUID),
    "MI_River_ForgeFoam": (0.7, "MI_River_Forge", RIVER_GUID),
    "MI_River_Hideout": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_Hideout_Meditation": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_HideoutFast": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_HideoutFast2": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_Logs": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_UIWS": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_UIWS_shallow": (0.5, RIVER_PARENT, RIVER_GUID),
    "MI_River_UIWS_shallow_Foam": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_UIWS_shallow_Foam2": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_VH_Ent": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_River_VillageDocks": (0.1, RIVER_PARENT, RIVER_GUID),
    "MI_River_W2": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_RiverBG_W2": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_RusuGorge_UIWS": (0.6, WATER_PARENT, WATER_GUID),
    "MI_RusuGorge_UIWS_LightFoam": (0.35, WATER_PARENT, WATER_GUID),
    "MI_RusuGorge_UIWS_Single": (0.6, WATER_PARENT, WATER_GUID),
    "MI_W2_BarnWater": (0.5, WATER_PARENT, WATER_GUID),
    "MI_W2ThresholdWater": (0.6, WATER_PARENT, WATER_GUID),
    "MI_Water_HuntsmanArena": (0.2, WATER_PARENT, WATER_GUID),
    "MI_Water_Ocean": (0.8, WATER_PARENT, WATER_GUID),
    "MI_WaterBG_W2": (0.8, RIVER_PARENT, RIVER_GUID),
    "MI_WaterClean_Cave": (0.8, WATER_PARENT, WATER_GUID),
    "MI_WaterClean_Shallow": (0.2, WATER_PARENT, WATER_GUID),
    "MI_WaterClean_UIWS_Rain": (1.0, WATER_PARENT, WATER_GUID),
    "MI_WaterClean_UIWS1": (0.5, WATER_PARENT, WATER_GUID),
    "MI_WaterClean_VH_Cave": (0.5, WATER_PARENT, WATER_GUID),
    "MI_WaterDirty_Shallow": (0.2, WATER_PARENT, WATER_GUID),
    "MI_WaterDZ_UIWS": (1.0, WATER_PARENT, WATER_GUID),
}


def property_named(values: list[dict[str, Any]], name: str) -> dict[str, Any]:
    matches = [value for value in values if value.get("Name") == name]
    if len(matches) != 1:
        raise ValueError(f"Expected one {name!r} property, found {len(matches)}")
    return matches[0]


def parameter_name(entry: dict[str, Any]) -> str:
    info = property_named(entry["Value"], "ParameterInfo")
    return property_named(info["Value"], "Name")["Value"]


def resolve_import(asset: dict[str, Any], package_index: int) -> dict[str, Any]:
    if package_index >= 0:
        raise ValueError(f"Expected an import index, found {package_index}")
    return asset["Imports"][-package_index - 1]


def verify_parent(
    asset: dict[str, Any], export_data: list[dict[str, Any]], expected: str
) -> None:
    parent_index = int(property_named(export_data, "Parent")["Value"])
    actual = resolve_import(asset, parent_index)["ObjectName"]
    if actual != expected:
        raise ValueError(f"Expected parent {expected}, found {actual}")


def verify_foam_switch(export_data: list[dict[str, Any]], asset_name: str) -> None:
    static_parameters = property_named(export_data, "StaticParameters")
    switches = property_named(
        static_parameters["Value"], "StaticSwitchParameters"
    )["Value"]
    matches = [entry for entry in switches if parameter_name(entry) == SWITCH]
    if len(matches) != 1:
        raise ValueError(
            f"{asset_name}: expected one {SWITCH!r} switch, found {len(matches)}"
        )
    value = property_named(matches[0]["Value"], "Value")["Value"]
    override = property_named(matches[0]["Value"], "bOverride")["Value"]
    if value is not True or override is not True:
        raise ValueError(
            f"{asset_name}: expected enabled, overridden {SWITCH!r} switch"
        )


def patch_asset(
    source: Path,
    destination: Path,
    expected_value: float,
    expected_parent: str,
    expected_guid: str,
) -> dict[str, Any]:
    with source.open("r", encoding="utf-8") as stream:
        asset = json.load(stream)

    if len(asset.get("Exports", [])) != 1:
        raise ValueError(f"{source.stem}: expected exactly one export")
    export_data = asset["Exports"][0]["Data"]
    verify_parent(asset, export_data, expected_parent)
    verify_foam_switch(export_data, source.stem)

    scalars = property_named(export_data, "ScalarParameterValues")["Value"]
    matches = [entry for entry in scalars if parameter_name(entry) == PARAMETER]
    if len(matches) != 1:
        raise ValueError(
            f"{source.stem}: expected one {PARAMETER!r}, found {len(matches)}"
        )

    entry = matches[0]
    value_property = property_named(entry["Value"], "ParameterValue")
    guid_container = property_named(entry["Value"], "ExpressionGUID")
    guid_property = property_named(guid_container["Value"], "ExpressionGUID")
    actual_value = float(value_property["Value"])
    actual_guid = guid_property["Value"]
    if abs(actual_value - expected_value) > 1e-6:
        raise ValueError(
            f"{source.stem}: expected {PARAMETER}={expected_value}, "
            f"found {actual_value}"
        )
    if actual_guid.upper() != expected_guid.upper():
        raise ValueError(
            f"{source.stem}: expected GUID {expected_guid}, found {actual_guid}"
        )

    value_property["Value"] = TARGET_VALUE
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(asset, stream, ensure_ascii=False, indent=2)
        stream.write("\n")

    return {
        "asset": source.stem,
        "direct_parent": expected_parent,
        "family": WATER_PARENT if expected_guid == WATER_GUID else RIVER_PARENT,
        "previous": actual_value,
        "new": TARGET_VALUE,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()

    available = {path.stem for path in args.input_json.glob("*.json")}
    missing = sorted(set(EXPECTED) - available)
    if missing:
        raise ValueError(f"Missing expected assets: {', '.join(missing)}")

    results = []
    for asset_name, specification in sorted(EXPECTED.items()):
        results.append(
            patch_asset(
                args.input_json / f"{asset_name}.json",
                args.output_json / f"{asset_name}.json",
                *specification,
            )
        )

    water_count = sum(item["family"] == WATER_PARENT for item in results)
    river_count = sum(item["family"] == RIVER_PARENT for item in results)
    print(
        json.dumps(
            {
                "patched_assets": len(results),
                "water_surface_instances": water_count,
                "river_surface_instances": river_count,
                "parameter": PARAMETER,
                "new_value": TARGET_VALUE,
                "scope": "Every UIWS surface instance with Foam? enabled",
                "excluded": [
                    "M_Waterfall_* waterfall and cascade materials",
                    "opaque water without Foam_Opacity",
                    "instances where Foam? is already disabled",
                ],
                "assets": results,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
