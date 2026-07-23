# -*- coding: utf-8 -*-
"""
Partner Center listing CSV を store-metadata.md から生成する。

Usage:
  python scripts/generate-listing-csv.py
  python scripts/generate-listing-csv.py -OutDir dist
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

WIN_DIR = Path(__file__).resolve().parent.parent
PROJECT_ROOT = WIN_DIR.parent
DEFAULT_METADATA = PROJECT_ROOT / "docs" / "store-metadata.md"
DEFAULT_TEMPLATE = WIN_DIR / "scripts" / "listing-csv-template.csv"
DEFAULT_OUT = PROJECT_ROOT / "dist" / "listingData.csv"

# store-metadata.md の見出し → CSV Field 名
SECTION_KEYS = {
    "ja": {
        "短い説明": "ShortDescription",
        "説明文": "Description",
        "What's new in this version": "ReleaseNotes",
        "Product features": "Features",
        "アプリ名": "Title",
    },
    "en": {
        "Short description": "ShortDescription",
        "Description": "Description",
        "What's new in this version": "ReleaseNotes",
        "Product features": "Features",
        "Product name": "Title",
    },
    "zh": {
        "简短说明": "ShortDescription",
        "说明": "Description",
        "此版本的新增内容": "ReleaseNotes",
        "产品功能": "Features",
        "产品名称": "Title",
    },
}

LANG_HEADERS = {
    "日本語": "ja",
    "English": "en",
    "简体中文": "zh",
}


def parse_store_metadata(text: str) -> dict[str, dict[str, str | list[str]]]:
    """Return {ja|en|zh: {ShortDescription, Description, ReleaseNotes, Title, Features: [...]}}."""
    result: dict[str, dict[str, str | list[str]]] = {
        "ja": {},
        "en": {},
        "zh": {},
    }
    # Split on ## headings
    parts = re.split(r"^##\s+", text, flags=re.MULTILINE)
    for part in parts:
        if not part.strip():
            continue
        first_line, _, body = part.partition("\n")
        title = first_line.strip()
        lang = LANG_HEADERS.get(title)
        if not lang:
            continue
        keys = SECTION_KEYS[lang]
        # Split body on blank-line-separated labels that match known keys
        # Pattern: label line alone, then content until next known label or end
        lines = body.splitlines()
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if line in keys:
                field = keys[line]
                i += 1
                # skip one blank after label if present
                while i < len(lines) and lines[i].strip() == "":
                    i += 1
                chunk: list[str] = []
                while i < len(lines):
                    nxt = lines[i].strip()
                    if nxt in keys:
                        break
                    # stop at next ##-level (shouldn't appear) or horizontal rule sections
                    if lines[i].startswith("## "):
                        break
                    chunk.append(lines[i])
                    i += 1
                # trim trailing blanks
                while chunk and chunk[-1].strip() == "":
                    chunk.pop()
                # trim leading blanks
                while chunk and chunk[0].strip() == "":
                    chunk.pop(0)
                if field == "Features":
                    feats = []
                    for raw in chunk:
                        s = raw.strip()
                        if not s:
                            continue
                        if s.startswith("- "):
                            s = s[2:].strip()
                        feats.append(s)
                    result[lang][field] = feats
                else:
                    result[lang][field] = "\n".join(chunk).strip()
                continue
            i += 1
    return result


def fill_csv(
    template_path: Path,
    out_path: Path,
    meta: dict[str, dict[str, str | list[str]]],
) -> None:
    with template_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)

    # columns: Field, ID, Type, default, ja-jp, en-us, zh-cn
    for row in rows:
        while len(row) < 7:
            row.append("")
        field = row[0]
        if field == "Title":
            for lang, col in (("ja", 4), ("en", 5), ("zh", 6)):
                title = meta.get(lang, {}).get("Title")
                if isinstance(title, str) and title:
                    row[col] = title
                else:
                    row[col] = "POUCHES"
            continue
        if field in ("Description", "ReleaseNotes", "ShortDescription"):
            for lang, col in (("ja", 4), ("en", 5), ("zh", 6)):
                val = meta.get(lang, {}).get(field, "")
                row[col] = val if isinstance(val, str) else ""
            continue
        m = re.fullmatch(r"Feature(\d+)", field)
        if m:
            idx = int(m.group(1)) - 1
            for lang, col in (("ja", 4), ("en", 5), ("zh", 6)):
                feats = meta.get(lang, {}).get("Features", [])
                if isinstance(feats, list) and 0 <= idx < len(feats):
                    row[col] = feats[idx]
                else:
                    row[col] = ""

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate Partner Center listing CSV from store-metadata.md")
    ap.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    ap.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    ap.add_argument("-o", "--output", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    if not args.metadata.is_file():
        print(f"ERROR: metadata not found: {args.metadata}", file=sys.stderr)
        return 1
    if not args.template.is_file():
        print(f"ERROR: template not found: {args.template}", file=sys.stderr)
        return 1

    text = args.metadata.read_text(encoding="utf-8")
    meta = parse_store_metadata(text)
    for lang in ("ja", "en", "zh"):
        d = meta.get(lang, {})
        desc = d.get("Description", "")
        if not isinstance(desc, str) or not desc.strip():
            print(f"ERROR: missing Description for {lang} in {args.metadata}", file=sys.stderr)
            return 1

    fill_csv(args.template, args.output, meta)
    print(f"Listing CSV: {args.output}")
    for lang in ("ja", "en", "zh"):
        d = meta[lang]
        feats = d.get("Features") or []
        print(
            f"  {lang}: desc={len(d.get('Description') or '')} "
            f"notes={len(d.get('ReleaseNotes') or '')} "
            f"short={len(d.get('ShortDescription') or '')} "
            f"features={len(feats) if isinstance(feats, list) else 0}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
