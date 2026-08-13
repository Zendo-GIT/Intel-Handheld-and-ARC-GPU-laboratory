#!/usr/bin/env python3
"""Create an obvious magenta color probe for one Forest Path water material."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ASSET = "MI_WaterClean_Shallow"
TARGETS = ("FarColor", "NearColor", "ShallowColorTint")
PROBE_COLOR = {"R": 1.0, "G": 0.0, "B": 1.0, "A": 1.0}


def property_named(values: list[dict[str, Any]], name: str) -> dict[str, Any]:
    matches = [value for value in values if value.get("Name") == name]
    if len(matches) != 1:
        raise ValueError(f"Expected one {name!r} property, found {len(matches)}")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()

    source = args.input_json / f"{ASSET}.json"
    with source.open("r", encoding="utf-8") as stream:
        asset = json.load(stream)

    vector_property = property_named(
        asset["Exports"][0]["Data"], "VectorParameterValues"
    )
    changes = []
    for entry in vector_property["Value"]:
        parameter_info = property_named(entry["Value"], "ParameterInfo")
        name = property_named(parameter_info["Value"], "Name")["Value"]
        if name not in TARGETS:
            continue
        parameter_value = property_named(entry["Value"], "ParameterValue")
        color_property = property_named(parameter_value["Value"], "ParameterValue")
        previous = {
            channel: float(color_property["Value"][channel])
            for channel in ("R", "G", "B", "A")
        }
        color_property["Value"].update(PROBE_COLOR)
        changes.append({"parameter": name, "previous": previous, "new": PROBE_COLOR})

    changed_names = {item["parameter"] for item in changes}
    if changed_names != set(TARGETS):
        raise ValueError(f"Missing probe parameters: {set(TARGETS) - changed_names}")

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    with args.output_json.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(asset, stream, ensure_ascii=False, indent=2)
        stream.write("\n")

    print(
        json.dumps(
            {
                "asset": ASSET,
                "purpose": "Visible PAK load probe",
                "probe_color": "magenta",
                "changes": changes,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
