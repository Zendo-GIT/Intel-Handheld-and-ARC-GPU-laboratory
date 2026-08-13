#!/usr/bin/env python3
"""Report semantic differences between two UAssetAPI JSON directories."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


def equivalent(left: Any, right: Any) -> bool:
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isclose(float(left), float(right), rel_tol=0.0, abs_tol=1e-9)
    if isinstance(left, str) and isinstance(right, (int, float)):
        return left in {"+0", "-0"} and float(right) == 0.0
    if isinstance(right, str) and isinstance(left, (int, float)):
        return right in {"+0", "-0"} and float(left) == 0.0
    if isinstance(left, str) and isinstance(right, str):
        if left in {"+0", "-0"} and right in {"+0", "-0"}:
            return True
    return left == right


def differences(left: Any, right: Any, path: str = "$") -> list[dict[str, Any]]:
    if isinstance(left, dict) and isinstance(right, dict):
        output = []
        for key in sorted(set(left) | set(right)):
            child = f"{path}.{key}"
            if key not in left:
                output.append({"path": child, "left": "<missing>", "right": right[key]})
            elif key not in right:
                output.append({"path": child, "left": left[key], "right": "<missing>"})
            else:
                output.extend(differences(left[key], right[key], child))
        return output
    if isinstance(left, list) and isinstance(right, list):
        output = []
        if len(left) != len(right):
            output.append(
                {"path": f"{path}.length", "left": len(left), "right": len(right)}
            )
        for index, (left_item, right_item) in enumerate(zip(left, right)):
            output.extend(differences(left_item, right_item, f"{path}[{index}]"))
        return output
    if equivalent(left, right):
        return []
    return [{"path": path, "left": left, "right": right}]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=200)
    args = parser.parse_args()

    report = []
    for expected_path in sorted(args.expected.glob("*.json")):
        actual_path = args.actual / expected_path.name
        if not actual_path.is_file():
            report.append(
                {"asset": expected_path.stem, "count": 1, "differences": ["missing"]}
            )
            continue
        with expected_path.open("r", encoding="utf-8") as stream:
            expected = json.load(stream)
        with actual_path.open("r", encoding="utf-8") as stream:
            actual = json.load(stream)
        found = differences(expected, actual)
        if found:
            report.append(
                {
                    "asset": expected_path.stem,
                    "count": len(found),
                    "differences": found[: args.limit],
                }
            )

    print(
        json.dumps(
            {
                "files_compared": len(list(args.expected.glob("*.json"))),
                "files_with_differences": len(report),
                "report": report,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
