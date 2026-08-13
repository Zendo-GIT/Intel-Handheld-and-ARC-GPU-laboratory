#!/usr/bin/env python3
"""Swap one confirmed water instance to Unreal's cooked unlit translucent material."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ASSET = "MI_WaterClean_Shallow"
OLD_PARENT_NAME = "M_Water_UIWS"
NEW_PARENT_NAME = "M_SimpleUnlitTranslucent"
OLD_PARENT_PATH = "/Game/Mochi/MaterialLibrary/Water/UIWS/M_Water_UIWS"
NEW_PARENT_PATH = "/Engine/EngineDebugMaterials/M_SimpleUnlitTranslucent"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-json", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()

    source = args.input_json / f"{ASSET}.json"
    with source.open("r", encoding="utf-8") as stream:
        asset = json.load(stream)

    old_name_count = sum(name == OLD_PARENT_NAME for name in asset["NameMap"])
    old_path_count = sum(name == OLD_PARENT_PATH for name in asset["NameMap"])
    if old_name_count != 1 or old_path_count != 1:
        raise ValueError(
            "Unexpected parent entries in NameMap: "
            f"name={old_name_count}, path={old_path_count}"
        )

    name_imports = [
        entry
        for entry in asset["Imports"]
        if entry.get("ObjectName") == OLD_PARENT_NAME
    ]
    path_imports = [
        entry
        for entry in asset["Imports"]
        if entry.get("ObjectName") == OLD_PARENT_PATH
    ]
    if len(name_imports) != 1 or len(path_imports) != 1:
        raise ValueError(
            "Unexpected parent imports: "
            f"name={len(name_imports)}, path={len(path_imports)}"
        )

    parent_properties = [
        entry
        for entry in asset["Exports"][0]["Data"]
        if entry.get("Name") == "Parent"
    ]
    if len(parent_properties) != 1 or parent_properties[0].get("Value") != -2:
        raise ValueError("The material instance no longer uses import -2 as its parent")

    asset["NameMap"] = [
        NEW_PARENT_NAME
        if name == OLD_PARENT_NAME
        else NEW_PARENT_PATH
        if name == OLD_PARENT_PATH
        else name
        for name in asset["NameMap"]
    ]
    name_imports[0]["ObjectName"] = NEW_PARENT_NAME
    path_imports[0]["ObjectName"] = NEW_PARENT_PATH

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    with args.output_json.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(asset, stream, ensure_ascii=False, indent=2)
        stream.write("\n")

    print(
        json.dumps(
            {
                "asset": ASSET,
                "previous_parent": OLD_PARENT_PATH,
                "new_parent": NEW_PARENT_PATH,
                "scope": "Forest Path First Tear shallow water only",
                "purpose": "Separate water-surface lighting from external rendering",
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
