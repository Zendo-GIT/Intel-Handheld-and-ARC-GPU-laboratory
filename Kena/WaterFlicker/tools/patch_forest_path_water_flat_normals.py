#!/usr/bin/env python3
"""Neutralize animated normal intensities on the confirmed Forest Path water."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


ASSET = "MI_WaterClean_Shallow"
TARGETS = {
    "Wave_Intensity": {
        "expected": 0.5,
        "guid": "{56683E20-45E3-D602-F5AC-07B30782AB90}",
    },
    "Wave_Intensity_Secondary": {
        "expected": None,
        "guid": "{E3DC7A2F-4FE7-A979-28CF-A2A7ACE4D90C}",
    },
    "Ripples_Intensity": {
        "expected": 1.0,
        "guid": "{6169C395-457B-8008-8EFF-FFADD73BA154}",
    },
}


def property_named(values: list[dict[str, Any]], name: str) -> dict[str, Any]:
    matches = [value for value in values if value.get("Name") == name]
    if len(matches) != 1:
        raise ValueError(f"Expected one {name!r} property, found {len(matches)}")
    return matches[0]


def parameter_name(entry: dict[str, Any]) -> str:
    info = property_named(entry["Value"], "ParameterInfo")
    return property_named(info["Value"], "Name")["Value"]


def parameter_guid(entry: dict[str, Any]) -> dict[str, Any]:
    container = property_named(entry["Value"], "ExpressionGUID")
    return property_named(container["Value"], "ExpressionGUID")


def set_parameter_identity(entry: dict[str, Any], name: str, guid: str) -> None:
    info = property_named(entry["Value"], "ParameterInfo")
    property_named(info["Value"], "Name")["Value"] = name
    parameter_guid(entry)["Value"] = guid


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()

    source = args.input_json / f"{ASSET}.json"
    with source.open("r", encoding="utf-8") as stream:
        asset = json.load(stream)

    entries = property_named(
        asset["Exports"][0]["Data"], "ScalarParameterValues"
    )["Value"]
    by_name = {parameter_name(entry): entry for entry in entries}
    template = copy.deepcopy(by_name["Wave_Intensity"])
    report = []

    for name, config in TARGETS.items():
        entry = by_name.get(name)
        if entry is None:
            if config["expected"] is not None:
                raise ValueError(f"Missing required existing parameter {name}")
            entry = copy.deepcopy(template)
            set_parameter_identity(entry, name, config["guid"])
            entries.append(entry)
            previous = None
            action = "added"
        else:
            guid = parameter_guid(entry)["Value"]
            if guid.upper() != config["guid"].upper():
                raise ValueError(f"Unexpected GUID for {name}: {guid}")
            value = property_named(entry["Value"], "ParameterValue")
            previous = float(value["Value"])
            if config["expected"] is not None and abs(
                previous - float(config["expected"])
            ) > 1e-6:
                raise ValueError(f"Unexpected value for {name}: {previous}")
            action = "updated"

        property_named(entry["Value"], "ParameterValue")["Value"] = 0.0
        if name not in asset["NameMap"]:
            asset["NameMap"].append(name)
        report.append(
            {
                "parameter": name,
                "previous_override": previous,
                "new_override": 0.0,
                "action": action,
            }
        )

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    with args.output_json.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(asset, stream, ensure_ascii=False, indent=2)
        stream.write("\n")

    print(
        json.dumps(
            {
                "asset": ASSET,
                "scope": "Forest Path First Tear shallow water only",
                "purpose": "Isolate animated water-normal response",
                "changes": report,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
