#!/usr/bin/env python3
"""Build ONE offline curriculum pack containing multiple programming tracks.

Tracks shipped: JavaScript (javascript-v9) + Python (python-for-everybody and
scientific-computing-with-python), all from freeCodeCamp Chinese i18n curriculum.

Output data/curriculum.json has this shape:
  {
    "meta": {...},
    "tracks": [
      {"id": "javascript", "title": "...", "chapters": [...]},
      {"id": "python", "title": "...", "chapters": [...]}
    ]
  }

The Godot app keeps the existing chapter/module/block/lesson reader; only the
repository layer is aware of tracks.
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_curriculum import (  # noqa: E402
    BLOCK_KIND,
    build_pack,
    clean_inline,
)

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ZIP = ROOT.parent / ".build" / "fcc" / "i18n-curriculum.zip"
OUTPUT = ROOT / "data" / "curriculum.json"
STRUCTURE_DIR = ROOT.parent / ".build" / "fcc"

ZIP_PREFIX = "i18n-curriculum-main/curriculum/challenges/chinese/blocks/"

# Each superblock becomes one track; its `blocks` become the modules.
TRACKS = [
    {
        "id": "javascript",
        "title": "JavaScript 编程",
        "badge": "JS",
        "structure": "javascript-v9.json",
        "source": "freeCodeCamp i18n-curriculum (chinese, javascript-v9)",
    },
    {
        "id": "python",
        "title": "Python 编程",
        "badge": "PY",
        "structure": "python_superblocks.json",
        "source": "freeCodeCamp i18n-curriculum (chinese, python-for-everybody + scientific-computing-with-python)",
    },
]

# Human-friendly module names for Python blocks (both superblocks are flat).
PY_MODULE_TITLES = {
    "python-for-everybody": "Python 人人学",
    "learn-string-manipulation-by-building-a-cipher": "字符串处理 · 密码器",
    "learn-how-to-work-with-numbers-and-strings-by-implementing-the-luhn-algorithm": "数字与字符串 · Luhn 算法",
    "learn-lambda-functions-by-building-an-expense-tracker": "Lambda 函数 · 记账应用",
    "learn-list-comprehension-by-building-a-case-converter-program": "列表推导 · 大小写转换",
    "learn-the-bisection-method-by-finding-the-square-root-of-a-number": "二分法 · 求平方根",
    "build-an-arithmetic-formatter-project": "项目 · 算术格式化器",
    "learn-regular-expressions-by-building-a-password-generator": "正则表达式 · 密码生成器",
    "learn-algorithm-design-by-building-a-shortest-path-algorithm": "算法设计 · 最短路径",
    "learn-recursion-by-solving-the-tower-of-hanoi-puzzle": "递归 · 汉诺塔",
    "learn-data-structures-by-building-the-merge-sort-algorithm": "数据结构 · 归并排序",
    "build-a-time-calculator-project": "项目 · 时间计算器",
    "learn-classes-and-objects-by-building-a-sudoku-solver": "类与对象 · 数独求解器",
    "learn-tree-traversal-by-building-a-binary-search-tree": "树遍历 · 二叉搜索树",
    "build-a-budget-app-project": "项目 · 预算应用",
    "learn-special-methods-by-building-a-vector-space": "特殊方法 · 向量空间",
    "learn-interfaces-by-building-an-equation-solver": "接口 · 方程求解器",
    "build-a-polygon-area-calculator-project": "项目 · 多边形面积计算器",
    "learn-encapsulation-by-building-a-projectile-trajectory-calculator": "封装 · 弹道计算器",
    "build-a-probability-calculator-project": "项目 · 概率计算器",
}


def load_structure(name: str) -> dict:
    return json.loads((STRUCTURE_DIR / name).read_text(encoding="utf-8"))


def build_javascript_track(zf: zipfile.ZipFile) -> tuple[dict, Counter]:
    structure = load_structure("javascript-v9.json")
    pack, stats = build_pack(structure, zf)
    # build_pack already emits chapters with meta; return them as-is.
    return pack, stats


def build_python_track(zf: zipfile.ZipFile) -> tuple[dict, Counter]:
    """Python superblocks use a flat `blocks` list, not chapters/modules.

    We group the flat blocks into two chapters (P4E, Scientific Computing),
    each block becomes a module, and each module's lessons are split into
    readable blocks of at most 4 lessons so the reader page stays short.
    """
    from extract_curriculum import body_to_lesson, parse_frontmatter, split_sections

    stats = Counter()
    groups = [
        ("python-for-everybody", "Python 人人学", load_structure("python-for-everybody.json").get("blocks", [])),
        (
            "scientific-computing-with-python",
            "用 Python 做科学计算",
            load_structure("scientific-computing-with-python.json").get("blocks", []),
        ),
    ]

    chapters = []
    for chapter_id, chapter_title, block_names in groups:
        modules = []
        for block_name in block_names:
            prefix = ZIP_PREFIX + block_name + "/"
            files = sorted(n for n in zf.namelist() if n.startswith(prefix) and n.endswith(".md"))
            if not files:
                stats["block_missing"] += 1
                continue
            lessons = []
            for path in files:
                text = zf.read(path).decode("utf-8", "replace")
                meta, body = parse_frontmatter(text)
                lesson = body_to_lesson(split_sections(body))
                if not lesson["body"] and not lesson["code"] and not lesson["questions"]:
                    continue
                lesson["id"] = meta.get("id", "")
                lesson["title"] = clean_inline(meta.get("title", "")) or block_name
                lessons.append(lesson)
                stats["lessons"] += 1
                stats["questions"] += len(lesson["questions"])
            if not lessons:
                continue

            # Split long projects into short reading blocks.
            chunks = [lessons[i : i + 4] for i in range(0, len(lessons), 4)]
            blocks = []
            for index, chunk in enumerate(chunks):
                kind = "quiz" if "quiz" in block_name else ("lab" if "lab" in block_name else "lecture")
                first_title = chunk[0]["title"]
                block_title = first_title if len(chunks) == 1 else "%s · %d" % (first_title, index + 1)
                if len(block_title) > 34:
                    block_title = block_title[:32] + "…"
                blocks.append(
                    {
                        "id": "%s--%d" % (block_name, index),
                        "title": clean_inline(BLOCK_KIND.get(kind, "讲解")) + " · " + block_title,
                        "kind": kind,
                        "lessons": chunk,
                    }
                )
                stats["blocks"] += 1
            modules.append(
                {
                    "id": block_name,
                    "title": PY_MODULE_TITLES.get(block_name, clean_inline(block_name)),
                    "blocks": blocks,
                }
            )
            stats["modules"] += 1
        if modules:
            chapters.append({"id": chapter_id, "title": chapter_title, "modules": modules})

    return {"chapters": chapters}, stats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", type=Path, default=SOURCE_ZIP)
    args = parser.parse_args()

    total = Counter()
    tracks = []
    with zipfile.ZipFile(args.zip) as zf:
        js_pack, js_stats = build_javascript_track(zf)
        tracks.append(
            {
                "id": "javascript",
                "title": "JavaScript 编程",
                "badge": "JS",
                "chapters": js_pack.get("chapters", []),
                "stats": dict(js_stats),
            }
        )
        total.update(js_stats)

        py_pack, py_stats = build_python_track(zf)
        tracks.append(
            {
                "id": "python",
                "title": "Python 编程",
                "badge": "PY",
                "chapters": py_pack.get("chapters", []),
                "stats": dict(py_stats),
            }
        )
        total.update(py_stats)

    pack = {
        "meta": {
            "title": "编程学习宝 · 中文离线版",
            "source": "freeCodeCamp i18n-curriculum (chinese)",
            "license": "课程版权归 freeCodeCamp.org；代码 MIT",
            "trackCount": len(tracks),
            "moduleCount": total["modules"],
            "blockCount": total["blocks"],
            "lessonCount": total["lessons"],
            "questionCount": total["questions"],
        },
        "tracks": tracks,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(pack, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("stats:", dict(total), flush=True)
    for track in tracks:
        print("  %s: %s" % (track["title"], track["stats"]), flush=True)
    print("wrote %s (%.2f MB)" % (OUTPUT, OUTPUT.stat().st_size / 1024 / 1024), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
