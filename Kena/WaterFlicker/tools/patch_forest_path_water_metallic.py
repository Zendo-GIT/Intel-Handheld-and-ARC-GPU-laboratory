#!/usr/bin/env python3
"""Disable the metallic response on the confirmed Forest Path water instance."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ASSET = "MI_WaterClean_Shallow"
PARAMETER = "Metallic"
EXPECTED_GUID = "{A47A146C-40A6-1098-2D09-5E95D8CE6DA2}"
EXPECTED_VALUE = 0.699999988079071
TARGET_VALUE = 0.0


def property_named(values: list[dict[str, Any]], name: str) -> dict[str, Any]:
    matches = [value for value in values if value.get("Name") == name]
    if len(matches) != 1:
        raise ValueError(f"Expected one {name!r} property, found {len(matches)}")
    return matches[0]


def parameter_name(entry: dict[str, Any]) -> str:
    info = property_named(entry["Value"], "ParameterInfo")
    return property_named(info["Value"], "Name")["Value"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()

    source = args.input_json / f"{ASSET}.json"
    with source.open("r", encoding="utf-8") as stream:
        asset = json.load(stream)

    scalar_property = property_named(
        asset["Exports"][0]["Data"], "ScalarParameterValues"
    )
    matches = [
        entry
        for entry in scalar_property["Value"]
        if parameter_name(entry) == PARAMETER
    ]
    if len(matches) != 1:
        raise ValueError(f"Expected one {PARAMETER} entry, found {len(matches)}")

    entry = matches[0]
    value_property = property_named(entry["Value"], "ParameterValue")
    guid_container = property_named(entry["Value"], "ExpressionGUID")
    guid_property = property_named(guid_container["Value"], "ExpressionGUID")
    if guid_property["Value"].upper() != EXPECTED_GUID.upper():
        raise ValueError(f"Unexpected {PARAMETER} GUID: {guid_property['Value']}")
    if abs(float(value_property["Value"]) - EXPECTED_VALUE) > 1e-6:
        raise ValueError(f"Unexpected {PARAMETER} value: {value_property['Value']}")

    value_property["Value"] = TARGET_VALUE
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    with args.output_json.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(asset, stream, ensure_ascii=False, indent=2)
        stream.write("\n")

    print(
        json.dumps(
            {
                "asset": ASSET,
                "parameter": PARAMETER,
                "previous": EXPECTED_VALUE,
                "new": TARGET_VALUE,
                "scope": "Forest Path First Tear shallow water only",
                "purpose": "Isolate the low-roughness metallic reflection path",
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
