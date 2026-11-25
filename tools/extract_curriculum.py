#!/usr/bin/env python3
"""Extract the Chinese JavaScript v9 curriculum from the official freeCodeCamp
i18n-curriculum repository into a compact JSON pack for the offline handheld app.

Source: https://github.com/freeCodeCamp/i18n-curriculum (branch main)
Layout structure: https://github.com/freeCodeCamp/freeCodeCamp
  curriculum/structure/superblocks/javascript-v9.json

Run on a PC with network access. The generated data/curriculum.json is what the
Godot app consumes; no Node.js / MongoDB / browser is needed on the device.

Usage:
  python tools/extract_curriculum.py --zip <path-to-i18n-curriculum.zip>
  python tools/extract_curriculum.py --fetch       # download the source zip
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ZIP = ROOT / ".build" / "i18n-curriculum.zip"
OUTPUT = ROOT / "data" / "curriculum.json"
STRUCTURE_URL = (
    "https://raw.githubusercontent.com/freeCodeCamp/freeCodeCamp/main/"
    "curriculum/structure/superblocks/javascript-v9.json"
)
I18N_ZIP_URL = "https://codeload.github.com/freeCodeCamp/i18n-curriculum/zip/refs/heads/main"
ZIP_PREFIX = "i18n-curriculum-main/curriculum/challenges/chinese/blocks/"

# Module titles are not localised in the structure file; provide Chinese names
# for the shipped modules. Unknown modules fall back to the dashed name.
MODULE_TITLES = {
    "javascript-variables-and-strings": "变量与字符串",
    "javascript-booleans-and-numbers": "布尔值与数字",
    "javascript-functions": "函数",
    "javascript-arrays": "数组",
    "javascript-objects": "对象",
    "javascript-loops": "循环",
    "review-javascript-fundamentals": "基础复习",
    "higher-order-functions-and-callbacks": "高阶函数与回调",
    "dom-manipulation-and-events": "DOM 操作与事件",
    "js-a11y": "无障碍访问",
    "debugging-javascript": "调试",
    "basic-regex": "正则表达式",
    "lab-markdown-to-html-converter": "实验：Markdown 转 HTML",
    "form-validation": "表单验证",
    "javascript-dates": "日期",
    "audio-and-video-events": "音视频事件",
    "lab-drum-machine": "实验：鼓机",
    "maps-and-sets": "Map 与 Set",
    "lab-voting-system": "实验：投票系统",
    "localstorage-and-crud-operations": "本地存储与 CRUD",
    "classes-and-the-this-keyword": "类与 this",
    "lab-bank-account-manager": "实验：银行账户管理",
    "recursion": "递归",
    "data-structures": "数据结构",
    "algorithms": "算法",
    "graphs-and-trees": "图与树",
    "dynamic-programming": "动态规划",
    "functional-programming": "函数式编程",
    "asynchronous-javascript": "异步 JavaScript",
    "lab-weather-app": "实验：天气应用",
    "review-javascript": "认证复习",
    "javascript-certification-exam": "认证考试",
}

BLOCK_KIND = {
    "lecture": "讲解",
    "workshop": "实践",
    "lab": "实验",
    "review": "复习",
    "quiz": "测验",
}


def fetch(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url} -> {dest}", flush=True)
    with urllib.request.urlopen(url, timeout=600) as response, dest.open("wb") as out:
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)


def parse_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}, text
    header = text[4:end]
    body = text[end + 5 :]
    meta: dict[str, str] = {}
    for line in header.splitlines():
        m = re.match(r"^([A-Za-z][\w-]*):\s*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return meta, body


def split_sections(body: str) -> dict[str, str]:
    """Split '# --name--' sections into a name -> text map."""
    sections: dict[str, list[str]] = {}
    current = ""
    for line in body.splitlines():
        m = re.match(r"^# --([a-z-]+)--\s*$", line)
        if m:
            current = m.group(1)
            sections.setdefault(current, [])
        elif current:
            sections[current].append(line)
    return {k: "\n".join(v).strip() for k, v in sections.items()}


def clean_inline(text: str) -> str:
    """Convert a small, safe subset of Markdown to plain text for Godot Labels."""
    # Links: keep only the visible label; drop long URLs so 640x480 labels stay readable.
    text = re.sub(r"<a\b[^>]*href=[\"'][^\"']+[\"'][^>]*>(.*?)</a>", r"\1", text, flags=re.S | re.I)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"</?(?:p|div|ul|ol|li|strong|em|b|i|code|pre|span|h[1-6])\b[^>]*>", "", text, flags=re.I)
    text = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"［图片：\1］", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"`{1,3}([^`]*)`{1,3}", r"\1", text)
    text = re.sub(r"^#{1,6}\s*", "", text, flags=re.M)
    # Markdown-escaped list bullets: "\- item" -> "• item".
    text = re.sub(r"^\s*\\[-*.+]\s*", "• ", text, flags=re.M)
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    return text.strip()


def body_to_lesson(sections: dict[str, str]) -> dict:
    """Turn a challenge file's sections into readable body + questions."""
    raw = sections.get("interactive") or sections.get("description") or ""
    instructions = sections.get("instructions") or ""
    if instructions:
        raw = raw + "\n\n## 练习要求\n\n" + instructions if raw else instructions

    # Keep code blocks as separate plain-text entries; strip interactive-editor fences.
    raw = raw.replace(":::interactive_editor", "")
    raw = re.sub(r"^:::\s*$", "", raw, flags=re.M)
    body_paragraphs: list[str] = []
    code_blocks: list[str] = []
    for chunk in re.split(r"(```[a-zA-Z]*\n.*?\n```)", raw, flags=re.S):
        if not chunk.strip():
            continue
        m = re.match(r"```[a-zA-Z]*\n(.*?)\n```", chunk, re.S)
        if m:
            code = m.group(1).strip()
            if code:
                code_blocks.append(code)
        else:
            cleaned = clean_inline(chunk)
            if cleaned:
                body_paragraphs.append(cleaned)

    questions = parse_questions(sections)
    return {
        "body": body_paragraphs,
        "code": code_blocks[:4],
        "questions": questions,
    }


def parse_answer_block(block: str) -> list[tuple[str, str]]:
    """Return (option_text, feedback) pairs from an --answers-- block."""
    parts = re.split(r"^---\s*$", block.strip(), flags=re.M)
    result: list[tuple[str, str]] = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        feedback_match = re.search(r"^### --feedback--\s*$", part, re.M)
        if feedback_match:
            option = part[: feedback_match.start()]
            feedback = part[feedback_match.end() :]
        else:
            option, feedback = part, ""
        option = clean_inline(option)
        feedback = clean_inline(feedback)
        if option:
            result.append((option, feedback))
    return result


def parse_questions(sections: dict[str, str]) -> list[dict]:
    questions: list[dict] = []

    # Format A: --questions-- with --text-- / --answers-- / --video-solution--.
    qblock = sections.get("questions", "")
    if qblock:
        for chunk in re.split(r"^## --text--\s*$", qblock, flags=re.M)[1:]:
            text_match = re.match(r"(.*?)(?=^## --(?:answers|video-solution)--)", chunk, re.S | re.M)
            if not text_match:
                continue
            prompt = clean_inline(text_match.group(1))
            answers_match = re.search(
                r"^## --answers--\s*(.*?)(?=^## --(?:video-solution|text)--|\Z)",
                chunk,
                re.S | re.M,
            )
            if not answers_match:
                continue
            options = parse_answer_block(answers_match.group(1))
            if len(options) < 2:
                continue
            # In freeCodeCamp's lecture format the option WITHOUT feedback is correct.
            correct = next((i for i, (_, fb) in enumerate(options) if not fb), -1)
            if correct < 0:
                continue
            questions.append(
                {
                    "text": prompt,
                    "options": [o for o, _ in options],
                    "answer": correct,
                    "feedback": options[correct][1]
                    or next((fb for _, fb in options if fb), ""),
                }
            )

    # Format B: --quizzes-- with --quiz-- / --question-- / --distractors-- / --answer--.
    quizblock = sections.get("quizzes", "")
    if quizblock:
        for chunk in re.split(r"^### --question--\s*$", quizblock, flags=re.M)[1:]:
            text_match = re.search(r"^#### --text--\s*(.*?)(?=^#### --|\Z)", chunk, re.S | re.M)
            distract_match = re.search(
                r"^#### --distractors--\s*(.*?)(?=^#### --answer--|\Z)", chunk, re.S | re.M
            )
            answer_match = re.search(r"^#### --answer--\s*(.*?)(?=^### --question--|\Z)", chunk, re.S | re.M)
            if not (text_match and distract_match and answer_match):
                continue
            prompt = clean_inline(text_match.group(1))
            distractors = [clean_inline(p) for p in re.split(r"^---\s*$", distract_match.group(1), flags=re.M)]
            distractors = [d for d in distractors if d]
            answer = clean_inline(answer_match.group(1))
            if not prompt or not answer or len(distractors) < 1:
                continue
            options = distractors[:3] + [answer]
            questions.append(
                {
                    "text": prompt,
                    "options": options,
                    "answer": len(options) - 1,
                    "feedback": "",
                }
            )

    return questions


def build_pack(structure: dict, zf: zipfile.ZipFile) -> dict:
    chapters: list[dict] = []
    stats = Counter()
    for chapter in structure.get("chapters", []):
        ch_out: list[dict] = []
        for module in chapter.get("modules", []):
            blocks_out: list[dict] = []
            for block_name in module.get("blocks", []):
                prefix = ZIP_PREFIX + block_name + "/"
                files = sorted(n for n in zf.namelist() if n.startswith(prefix) and n.endswith(".md"))
                if not files:
                    stats["block_missing"] += 1
                    continue
                lessons: list[dict] = []
                for path in files:
                    text = zf.read(path).decode("utf-8", "replace")
                    meta, body = parse_frontmatter(text)
                    sections = split_sections(body)
                    lesson = body_to_lesson(sections)
                    if not lesson["body"] and not lesson["code"] and not lesson["questions"]:
                        continue
                    lesson["id"] = meta.get("id", "")
                    lesson["title"] = clean_inline(meta.get("title", "")) or block_name
                    lessons.append(lesson)
                    stats["lessons"] += 1
                    stats["questions"] += len(lesson["questions"])
                if not lessons:
                    continue
                dashed = module.get("dashedName", "")
                if block_name.startswith(("quiz-", "review-")):
                    kind = "quiz" if block_name.startswith("quiz-") else "review"
                elif block_name.startswith("lab-"):
                    kind = "lab"
                elif block_name.startswith("workshop-"):
                    kind = "workshop"
                elif block_name.startswith("lecture-"):
                    kind = "lecture"
                else:
                    kind = "other"
                blocks_out.append(
                    {
                        "id": block_name,
                        "title": clean_inline(BLOCK_KIND.get(kind, lessons[0]["title"][:24]))
                        + " · "
                        + lessons[0]["title"][:30],
                        "kind": kind,
                        "lessons": lessons,
                    }
                )
                stats["blocks"] += 1
            if blocks_out:
                module_id = module.get("dashedName", "")
                ch_out.append(
                    {
                        "id": module_id,
                        "title": MODULE_TITLES.get(module_id, module_id),
                        "blocks": blocks_out,
                    }
                )
                stats["modules"] += 1
        if ch_out:
            chapters.append({"id": chapter.get("dashedName", ""), "title": "JavaScript", "modules": ch_out})
    return {
        "meta": {
            "title": "JavaScript 编程认证 · 中文离线版",
            "source": "freeCodeCamp i18n-curriculum (chinese, javascript-v9)",
            "license": "课程版权归 freeCodeCamp.org；代码 MIT",
            "moduleCount": stats["modules"],
            "blockCount": stats["blocks"],
            "lessonCount": stats["lessons"],
            "questionCount": stats["questions"],
        },
        "chapters": chapters,
    }, stats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", type=Path, default=SOURCE_ZIP)
    parser.add_argument("--fetch", action="store_true", help="Download the source zip first")
    parser.add_argument("--structure", type=Path, help="Local javascript-v9.json (for offline runs)")
    args = parser.parse_args()

    if args.fetch or not args.zip.exists():
        fetch(I18N_ZIP_URL, args.zip)
    if args.structure:
        structure = json.loads(args.structure.read_text(encoding="utf-8"))
    else:
        print("Fetching superblock structure...", flush=True)
        with urllib.request.urlopen(STRUCTURE_URL, timeout=60) as r:
            structure = json.loads(r.read().decode("utf-8"))

    with zipfile.ZipFile(args.zip) as zf:
        pack, stats = build_pack(structure, zf)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(pack, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("stats:", dict(stats), flush=True)
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size / 1024 / 1024:.2f} MB)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
