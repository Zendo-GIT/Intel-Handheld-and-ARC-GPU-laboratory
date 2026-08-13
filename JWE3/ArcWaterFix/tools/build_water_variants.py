#!/usr/bin/env python3
"""Construit les variantes OVL du correctif d'eau JWE3.

Le script ne modifie jamais l'archive officielle. Il charge les FGM déjà
extraits, écrit des copies patchées dans un dossier temporaire, puis demande à
Cobra Tools de créer un petit Main.ovl autonome pour chaque variante.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable


Patch = dict[str, tuple[float | int, ...]]


PROFILES: dict[str, dict[str, Patch]] = {
    "lod-static": {
        "gst_water.fgm": {
            "pWaterDetailMipBias": (0.0,),
            "pWaterDetailPlayRate": (0,),
            "pWaterStrengthTextureLODBias": (0.0,),
        },
    },
    "dither-off": {
        "waterpool.fgm": {"pWaterRoughnessFadeDitherWeight": (0.0,)},
        "waterdeep.fgm": {"pWaterRoughnessFadeDitherWeight": (0.0,)},
        "waterpoolunderside.fgm": {
            "pWaterRoughnessFadeDitherWeight": (0.0,)
        },
    },
    "opacity-safe": {
        name: {"pWaterEdgeOpacityScale": (10.0,)}
        for name in (
            "gst_water.fgm",
            "waterpool.fgm",
            "waterdeep.fgm",
            "waterpoolunderside.fgm",
            "water_volume_top.fgm",
        )
    },
    "flat-safe": {
        name: {
            "pReflectionDistortion": (0.0,),
            "pRefractionDistortion": (0.0,),
            "pWaterDetailIntensity": (0.0,),
            "pWaterDetailMipBias": (0.0,),
            "pWaterDetailParallaxAmount": (0.0,),
            "pWaterDetailPlayRate": (0,),
            "pWaterNormalIntensity": (0.0, 0.0),
            "pWaterParallaxAmount": (0.0,),
            "pWaterRoughnessFadeDitherWeight": (0.0,),
            "pWaterStrengthTextureLODBias": (0.0,),
            "pWaterTile_OscillationAmplitude": (0.0,),
            "pWaveChopScale": (0.0,),
            "pWaveHeightScale": (0.0,),
        }
        for name in (
            "gst_water.fgm",
            "waterpool.fgm",
            "waterdeep.fgm",
            "waterpoolunderside.fgm",
            "water_volume_top.fgm",
        )
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cobra-tools", required=True, type=Path)
    parser.add_argument("--water-extracted", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def patch_fgm(
    source: Path,
    destination: Path,
    requested: Patch,
    fgm_header_type: type,
    fgm_context_type: type,
) -> list[str]:
    header = fgm_header_type.from_xml_file(str(source), fgm_context_type())
    # Évite un avertissement du sérialiseur de Cobra Tools avec les FGM JWE3.
    header.context.game = header.game
    found: set[str] = set()
    report: list[str] = []

    for attribute, data in zip(
        header.attributes.data, header.value_foreach_attributes.data
    ):
        if attribute.name not in requested:
            continue
        before = tuple(data.value)
        after = requested[attribute.name]
        if len(before) != len(after):
            raise ValueError(
                f"{source.name}:{attribute.name}: taille {len(before)} != {len(after)}"
            )
        data.value[:] = after
        found.add(attribute.name)
        report.append(f"{source.name}:{attribute.name}: {before} -> {after}")

    # Certains profils couvrent plusieurs shaders : ignorer les attributs qui
    # n'existent pas dans un FGM donné est volontaire, mais au moins une
    # modification doit avoir été appliquée à chaque fichier.
    if not found:
        raise ValueError(f"Aucun attribut du profil trouvé dans {source.name}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with header.to_xml_file(header, str(destination)):
        pass
    return report


def verify_fgm(
    path: Path,
    requested: Patch,
    fgm_header_type: type,
    fgm_context_type: type,
) -> None:
    header = fgm_header_type.from_xml_file(str(path), fgm_context_type())
    values = {
        attribute.name: tuple(data.value)
        for attribute, data in zip(
            header.attributes.data, header.value_foreach_attributes.data
        )
    }
    for name, expected in requested.items():
        if name in values and values[name] != expected:
            raise ValueError(f"Vérification échouée pour {path.name}:{name}")


def build_profile(
    name: str,
    files: dict[str, Patch],
    water_dir: Path,
    output_dir: Path,
    cobra_dir: Path,
    fgm_header_type: type,
    fgm_context_type: type,
) -> Iterable[str]:
    variant_dir = output_dir / name
    variant_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix=f"clawlab-jwe3-{name}-") as temp:
        stage = Path(temp)
        for filename, requested in files.items():
            source = water_dir / filename
            if not source.is_file():
                raise FileNotFoundError(source)
            yield from patch_fgm(
                source,
                stage / filename,
                requested,
                fgm_header_type,
                fgm_context_type,
            )
            verify_fgm(
                stage / filename,
                requested,
                fgm_header_type,
                fgm_context_type,
            )

        command = [
            sys.executable,
            str(cobra_dir / "ovl_tool_cmd.py"),
            "new",
            "--game",
            "Jurassic World Evolution 3",
            "--input",
            str(stage),
            "--output",
            str(variant_dir / "Main.ovl"),
            "--compression",
            "ZLIB",
            "--force",
        ]
        subprocess.run(command, cwd=cobra_dir, check=True)


def main() -> int:
    args = parse_args()
    cobra_dir = args.cobra_tools.resolve()
    water_dir = args.water_extracted.resolve()
    output_dir = args.output.resolve()

    sys.path.insert(0, str(cobra_dir))
    from generated.formats.fgm.structs.FgmHeader import FgmHeader
    from modules.formats.FGM import FgmContext

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = Path(__file__).resolve().parent.parent / "Manifest.xml"

    for profile_name, files in PROFILES.items():
        print(f"\n[{profile_name}]")
        for line in build_profile(
            profile_name,
            files,
            water_dir,
            output_dir,
            cobra_dir,
            FgmHeader,
            FgmContext,
        ):
            print(line)
        shutil.copy2(manifest, output_dir / profile_name / "Manifest.xml")
        (output_dir / profile_name / "Variant.txt").write_text(
            profile_name + "\n", encoding="utf-8"
        )

    print(f"\nVariantes créées dans {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

