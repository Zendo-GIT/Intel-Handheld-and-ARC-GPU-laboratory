#!/usr/bin/env python3
"""Disable SSR only on Kena's three water material masters that enable it."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


TARGETS = (
    "M_River_UIWS",
    "M_Water_UIWS",
    "M_Water_UIWS_Opaque",
)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()

    changes = []
    for name in TARGETS:
        source = args.input_json / f"{name}.json"
        asset = load_json(source)
        data = asset["Exports"][0]["Data"]
        matches = [item for item in data if item.get("Name") == "bScreenSpaceReflections"]
        if len(matches) != 1:
            raise ValueError(
                f"{name}: expected one bScreenSpaceReflections property, "
                f"found {len(matches)}"
            )
        previous = matches[0].get("Value")
        if previous is not True:
            raise ValueError(f"{name}: expected SSR=True, found {previous!r}")
        matches[0]["Value"] = False
        write_json(args.output_json / f"{name}.json", asset)
        changes.append(
            {
                "asset": name,
                "property": "bScreenSpaceReflections",
                "previous": True,
                "new": False,
            }
        )

    manifest = {
        "purpose": "Disable screen-space reflections only on Kena water materials",
        "asset_count": len(changes),
        "changes": changes,
        "untouched": [
            "global SSR",
            "non-water materials",
            "water specular",
            "water refraction",
            "water highlights",
            "waves and foam",
        ],
    }
    write_json(args.output_json / "manifest.json", manifest)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
