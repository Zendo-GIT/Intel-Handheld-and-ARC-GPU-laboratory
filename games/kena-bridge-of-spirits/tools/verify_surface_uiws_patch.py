#!/usr/bin/env python3
"""Verify the 31-asset Kena UIWS foam patch and its binary round-trip."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

from patch_surface_uiws_foam import EXPECTED, PARAMETER, property_named, parameter_name


def load(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def foam_value_property(asset: dict[str, Any]) -> dict[str, Any]:
    scalars = property_named(
        asset["Exports"][0]["Data"], "ScalarParameterValues"
    )["Value"]
    matches = [entry for entry in scalars if parameter_name(entry) == PARAMETER]
    if len(matches) != 1:
        raise ValueError(f"Expected one {PARAMETER!r}, found {len(matches)}")
    return property_named(matches[0]["Value"], "ParameterValue")


def normalize(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: normalize(child) for key, child in value.items()}
    if isinstance(value, list):
        return [normalize(child) for child in value]
    if isinstance(value, str) and value in {"+0", "-0"}:
        return 0.0
    if isinstance(value, float) and math.isclose(value, 0.0, abs_tol=0.0):
        return 0.0
    return value


def without_reader_version_metadata(asset: dict[str, Any]) -> dict[str, Any]:
    cleaned = copy.deepcopy(asset)
    # UAssetGUI's tojson command reports these from the explicitly selected
    # reader version. They are not material properties and do not represent
    # semantic changes in the reconstructed asset.
    cleaned.pop("ObjectVersion", None)
    cleaned.pop("CustomVersionContainer", None)
    return normalize(cleaned)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--original-json", required=True, type=Path)
    parser.add_argument("--patched-json", required=True, type=Path)
    parser.add_argument("--roundtrip-json", required=True, type=Path)
    parser.add_argument("--binary-assets", required=True, type=Path)
    args = parser.parse_args()

    expected_names = set(EXPECTED)
    patched_names = {path.stem for path in args.patched_json.glob("*.json")}
    roundtrip_names = {path.stem for path in args.roundtrip_json.glob("*.json")}
    uasset_names = {path.stem for path in args.binary_assets.glob("*.uasset")}
    uexp_names = {path.stem for path in args.binary_assets.glob("*.uexp")}

    failures: list[str] = []
    for label, actual_names in (
        ("patched JSON", patched_names),
        ("round-trip JSON", roundtrip_names),
        ("uasset", uasset_names),
        ("uexp", uexp_names),
    ):
        if actual_names != expected_names:
            missing = sorted(expected_names - actual_names)
            extra = sorted(actual_names - expected_names)
            failures.append(f"{label}: missing={missing}, extra={extra}")

    verified = []
    for asset_name in sorted(expected_names):
        try:
            original = load(args.original_json / f"{asset_name}.json")
            patched = load(args.patched_json / f"{asset_name}.json")
            roundtrip = load(args.roundtrip_json / f"{asset_name}.json")

            expected_patch = copy.deepcopy(original)
            foam_value_property(expected_patch)["Value"] = 0.0
            if normalize(expected_patch) != normalize(patched):
                raise ValueError("patched JSON changes data beyond Foam_Opacity")
            if without_reader_version_metadata(patched) != without_reader_version_metadata(
                roundtrip
            ):
                raise ValueError("binary round-trip changed semantic asset data")
            if float(foam_value_property(roundtrip)["Value"]) != 0.0:
                raise ValueError("round-trip Foam_Opacity is not zero")

            verified.append(asset_name)
        except Exception as error:  # Report every asset failure together.
            failures.append(f"{asset_name}: {error}")

    report = {
        "expected_assets": len(expected_names),
        "verified_assets": len(verified),
        "binary_files": len(uasset_names) + len(uexp_names),
        "semantic_change_per_asset": "Foam_Opacity -> 0 only",
        "waterfall_assets_included": False,
        "failures": failures,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
