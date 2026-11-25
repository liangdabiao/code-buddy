#!/usr/bin/env python3
"""Build the Chinese UI font subset from the local Windows DengXian face.

The glyph list is derived from the shipped curriculum JSON and every GDScript,
so no character used by the app can be silently dropped. Requires fontTools;
the IPA face is copied verbatim from the local Windows font directory.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / "assets" / "fonts"
BUILD_DIR = ROOT / ".build"
UI_FONT = Path(r"C:\Windows\Fonts\Deng.ttf")
IPA_FONT = Path(r"C:\Windows\Fonts\DejaVuSansMono_0.ttf")


def main() -> int:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    texts: list[str] = []
    data = ROOT / "data" / "curriculum.json"
    if data.exists():
        texts.append(data.read_text(encoding="utf-8"))
    for script in (ROOT / "scripts").glob("*.gd"):
        texts.append(script.read_text(encoding="utf-8"))
    texts.append("".join(chr(c) for c in range(32, 127)))
    glyphs = BUILD_DIR / "font-glyphs.txt"
    glyphs.write_text("".join(texts), encoding="utf-8")

    subprocess.run(
        [
            sys.executable, "-m", "fontTools.subset", str(UI_FONT),
            f"--text-file={glyphs}",
            f"--output-file={FONT_DIR / 'ui.ttf'}",
            "--layout-features=*", "--name-IDs=*", "--name-languages=*",
        ],
        check=True,
    )
    if IPA_FONT.exists():
        shutil.copyfile(IPA_FONT, FONT_DIR / "ipa.ttf")
    print(f"font subset ready: {(FONT_DIR / 'ui.ttf').stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
