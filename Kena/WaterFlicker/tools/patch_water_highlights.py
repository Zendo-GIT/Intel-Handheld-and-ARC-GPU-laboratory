#!/usr/bin/env python3
"""Create JSON variants that disable only Kena's water highlight parameters.

Input files are UAssetAPI JSON exports of the material instances from:
  Kena/Content/Mochi/MaterialLibrary/Water/UIWS

The script deliberately leaves SSR, specular, refraction, waves, foam and every
non-highlight parameter unchanged.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


FAMILIES = {
    "M_River_UIWS": {
        "parameter": "HighlightIntensity",
        "guid": "{7C68C014-4D2C-EADF-725A-70AE7AD375F9}",
        "template": "MI_River_UIWS",
    },
    "M_Water_UIWS": {
        "parameter": "Highlight_Intensity",
        "guid": "{2511E933-48BC-9F04-101E-BB9A77673212}",
        "template": "MI_WaterClean_Cave",
    },
    "M_Water_UIWS_Opaque": {
        "parameter": "Highlight_Intensity",
        "guid": "{B8C6CD27-4EA6-893F-59FF-6D8CD2B0C099}",
        "template": "MI_Water_Ocean_Opaque",
    },
    "M_WaterDZ_Opaque": {
        "parameter": "Highlight_Intensity",
        "guid": "{61F5706F-44C6-2878-28E9-C68B5E0822E0}",
        "template": "MI_Water_Ocean_Opaque",
    },
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def property_named(values: list[dict[str, Any]], name: str) -> dict[str, Any]:
    matches = [value for value in values if value.get("Name") == name]
    if len(matches) != 1:
        raise ValueError(f"Expected one {name!r} property, found {len(matches)}")
    return matches[0]


def parent_name(asset: dict[str, Any]) -> str:
    export = asset["Exports"][0]
    parent_index = property_named(export["Data"], "Parent")["Value"]
    if not isinstance(parent_index, int) or parent_index >= 0:
        raise ValueError(f"Unsupported material parent index: {parent_index!r}")
    return asset["Imports"][-parent_index - 1]["ObjectName"]


def scalar_entries(asset: dict[str, Any]) -> list[dict[str, Any]]:
    export = asset["Exports"][0]
    return property_named(export["Data"], "ScalarParameterValues")["Value"]


def parameter_name(entry: dict[str, Any]) -> str:
    info = property_named(entry["Value"], "ParameterInfo")
    return property_named(info["Value"], "Name")["Value"]


def parameter_value(entry: dict[str, Any]) -> dict[str, Any]:
    return property_named(entry["Value"], "ParameterValue")


def parameter_guid(entry: dict[str, Any]) -> dict[str, Any]:
    guid = property_named(entry["Value"], "ExpressionGUID")
    return property_named(guid["Value"], "ExpressionGUID")


def set_parameter_identity(entry: dict[str, Any], name: str, guid: str) -> None:
    info = property_named(entry["Value"], "ParameterInfo")
    property_named(info["Value"], "Name")["Value"] = name
    parameter_guid(entry)["Value"] = guid


def resolve_family(
    asset_name: str,
    parents: dict[str, str],
    trail: tuple[str, ...] = (),
) -> str:
    if asset_name in trail:
        raise ValueError(f"Material parent cycle: {' -> '.join((*trail, asset_name))}")
    parent = parents[asset_name]
    if parent in FAMILIES:
        return parent
    if parent not in parents:
        raise ValueError(f"Unsupported parent {parent!r} for {asset_name!r}")
    return resolve_family(parent, parents, (*trail, asset_name))


def find_template(
    assets: dict[str, dict[str, Any]], family: str
) -> dict[str, Any]:
    config = FAMILIES[family]
    template_asset = assets[config["template"]]
    matches = [
        entry
        for entry in scalar_entries(template_asset)
        if parameter_name(entry) == config["parameter"]
    ]
    if len(matches) != 1:
        raise ValueError(
            f"Template {config['template']} does not contain exactly one "
            f"{config['parameter']} entry"
        )
    return matches[0]


def patch_assets(input_dir: Path, output_dir: Path) -> dict[str, Any]:
    paths = sorted(input_dir.glob("MI_*.json"))
    if not paths:
        raise ValueError(f"No MI_*.json files found in {input_dir}")

    assets = {path.stem: load_json(path) for path in paths}
    parents = {name: parent_name(asset) for name, asset in assets.items()}
    templates = {family: find_template(assets, family) for family in FAMILIES}

    report: list[dict[str, Any]] = []
    for name, source in assets.items():
        family = resolve_family(name, parents)
        config = FAMILIES[family]
        result = copy.deepcopy(source)
        entries = scalar_entries(result)
        matches = [
            entry
            for entry in entries
            if parameter_name(entry) == config["parameter"]
        ]
        if len(matches) > 1:
            raise ValueError(
                f"{name} contains duplicate {config['parameter']} entries"
            )

        if matches:
            entry = matches[0]
            previous = parameter_value(entry)["Value"]
            existing_guid = parameter_guid(entry)["Value"].upper()
            if existing_guid != config["guid"].upper():
                raise ValueError(
                    f"Unexpected GUID for {name}/{config['parameter']}: "
                    f"{existing_guid}"
                )
            action = "updated"
        else:
            entry = copy.deepcopy(templates[family])
            set_parameter_identity(entry, config["parameter"], config["guid"])
            entries.append(entry)
            previous = None
            action = "added"

        parameter_value(entry)["Value"] = 0.0
        if config["parameter"] not in result["NameMap"]:
            result["NameMap"].append(config["parameter"])

        write_json(output_dir / f"{name}.json", result)
        report.append(
            {
                "asset": name,
                "family": family,
                "parameter": config["parameter"],
                "guid": config["guid"],
                "previous_override": previous,
                "new_override": 0.0,
                "action": action,
            }
        )

    manifest = {
        "purpose": "Disable only custom water highlights that flash on Intel Arc",
        "asset_count": len(report),
        "updated_count": sum(item["action"] == "updated" for item in report),
        "added_count": sum(item["action"] == "added" for item in report),
        "families": FAMILIES,
        "assets": report,
    }
    write_json(output_dir / "manifest.json", manifest)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()
    manifest = patch_assets(args.input_json, args.output_json)
    print(
        f"Patched {manifest['asset_count']} water material instances: "
        f"{manifest['updated_count']} updated, {manifest['added_count']} added."
    )


if __name__ == "__main__":
    main()
