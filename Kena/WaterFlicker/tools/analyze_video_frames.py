#!/usr/bin/env python3
"""Extract contact sheets and luminance-change candidates from a gameplay video."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def save_image(path: Path, image: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ok, encoded = cv2.imencode(path.suffix or ".png", image)
    if not ok:
        raise RuntimeError(f"Unable to encode {path}")
    encoded.tofile(path)


def label_frame(frame: np.ndarray, label: str) -> np.ndarray:
    result = frame.copy()
    cv2.rectangle(result, (0, 0), (result.shape[1], 34), (0, 0, 0), -1)
    cv2.putText(
        result,
        label,
        (8, 24),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.62,
        (255, 255, 255),
        1,
        cv2.LINE_AA,
    )
    return result


def make_sheet(items: list[tuple[str, np.ndarray]], columns: int = 4) -> np.ndarray:
    if not items:
        raise ValueError("No images for contact sheet")
    tile_width = 480
    tile_height = 270
    tiles = []
    for label, frame in items:
        tile = cv2.resize(frame, (tile_width, tile_height), interpolation=cv2.INTER_AREA)
        tiles.append(label_frame(tile, label))
    blank = np.zeros_like(tiles[0])
    while len(tiles) % columns:
        tiles.append(blank.copy())
    rows = [np.hstack(tiles[index : index + columns]) for index in range(0, len(tiles), columns)]
    return np.vstack(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(str(args.video))
    if not capture.isOpened():
        raise RuntimeError(f"Unable to open {args.video}")

    fps = float(capture.get(cv2.CAP_PROP_FPS))
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if fps <= 0 or frame_count <= 0:
        raise RuntimeError("Invalid video metadata")

    sample_indices = set(
        int(round(value))
        for value in np.linspace(0, frame_count - 1, min(16, frame_count))
    )
    samples: dict[int, np.ndarray] = {}
    metrics: list[dict[str, float | int]] = []
    previous_small: np.ndarray | None = None
    frames: dict[int, np.ndarray] = {}

    index = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        if index in sample_indices:
            samples[index] = frame.copy()

        small_width = 320
        small_height = max(1, int(round(height * small_width / width)))
        small = cv2.resize(frame, (small_width, small_height), interpolation=cv2.INTER_AREA)
        luma = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY).astype(np.float32)
        positive_change = 0.0
        absolute_change = 0.0
        if previous_small is not None:
            delta = luma - previous_small
            positive_change = float(np.maximum(delta, 0).mean())
            absolute_change = float(np.abs(delta).mean())
        metrics.append(
            {
                "frame": index,
                "time_seconds": index / fps,
                "mean_luma": float(luma.mean()),
                "p99_luma": float(np.percentile(luma, 99)),
                "bright_fraction": float((luma >= 245).mean()),
                "positive_change": positive_change,
                "absolute_change": absolute_change,
            }
        )
        previous_small = luma
        index += 1

    capture.release()
    decoded_count = index
    if decoded_count == 0:
        raise RuntimeError("No video frames decoded")

    minimum_spacing = max(1, int(round(fps * 0.30)))
    candidates: list[int] = []
    for metric in sorted(metrics[1:], key=lambda item: item["positive_change"], reverse=True):
        candidate = int(metric["frame"])
        if all(abs(candidate - existing) >= minimum_spacing for existing in candidates):
            candidates.append(candidate)
        if len(candidates) == 8:
            break

    wanted = sorted(set(candidates + [max(0, value - 1) for value in candidates]))
    capture = cv2.VideoCapture(str(args.video))
    wanted_set = set(wanted)
    index = 0
    while wanted_set:
        ok, frame = capture.read()
        if not ok:
            break
        if index in wanted_set:
            frames[index] = frame.copy()
            wanted_set.remove(index)
        index += 1
    capture.release()

    sample_items = [
        (f"{frame_index / fps:6.2f}s  f{frame_index}", samples[frame_index])
        for frame_index in sorted(samples)
    ]
    save_image(args.output / "timeline-contact-sheet.jpg", make_sheet(sample_items))

    candidate_items = []
    for frame_index in candidates:
        previous_index = max(0, frame_index - 1)
        if previous_index in frames:
            candidate_items.append(
                (f"before {previous_index / fps:6.2f}s", frames[previous_index])
            )
        if frame_index in frames:
            score = metrics[frame_index]["positive_change"]
            candidate_items.append(
                (f"flash? {frame_index / fps:6.2f}s +{score:.2f}", frames[frame_index])
            )
            save_image(args.output / f"candidate-{frame_index:06d}.jpg", frames[frame_index])
    save_image(args.output / "luminance-candidates.jpg", make_sheet(candidate_items))

    summary = {
        "video": str(args.video),
        "fps": fps,
        "reported_frame_count": frame_count,
        "decoded_frame_count": decoded_count,
        "duration_seconds": decoded_count / fps,
        "width": width,
        "height": height,
        "candidate_frames": candidates,
        "candidate_metrics": [metrics[value] for value in candidates],
        "mean_luma_range": [
            min(value["mean_luma"] for value in metrics),
            max(value["mean_luma"] for value in metrics),
        ],
        "max_bright_fraction": max(value["bright_fraction"] for value in metrics),
    }
    with (args.output / "summary.json").open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(summary, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
