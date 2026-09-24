#!/usr/bin/env python3
"""Checks the App Store listing in fastlane/metadata before an upload.

For every locale folder it checks that the required files exist and that each
field fits App Store Connect's limits. Lengths are counted in characters
(Unicode code points after NFC normalisation), not bytes, so Hindi text is
measured the way it is typed. It also checks the keyword field: no spaces
after commas, no empty or duplicate keywords, no simple plurals of another
keyword, and no words already in the name or subtitle (Apple indexes those
already, so repeating them wastes space).

Usage: python3 tools/check_appstore_metadata.py [path/to/fastlane/metadata]
Exits 1 and lists the problems if anything fails.
"""

import re
import sys
import unicodedata
from pathlib import Path

LOCALES = ["en-US", "hi", "es-MX", "es-ES"]

# File name -> maximum length in characters.
LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "keywords.txt": 100,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "release_notes.txt": 4000,
    "privacy_url.txt": None,
    "support_url.txt": None,
}

SHARED_FILES = {
    "copyright.txt": None,
    "primary_category.txt": {"HEALTH_AND_FITNESS"},
    "secondary_category.txt": {"LIFESTYLE"},
}

# Words the listing must not use. "AI" is matched as a whole word, case-sensitive.
BANNED = [re.compile(r"\bAI\b")]


def read(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    return unicodedata.normalize("NFC", text).strip()


def length(text: str) -> int:
    return len(text)


def words(text: str) -> set:
    """Lower-case words of a name or subtitle, split on anything that isn't a letter,
    digit or combining mark (so Devanagari words stay whole)."""
    return {w for w in re.split(r"[^\wऀ-ॿ]+", text.lower()) if w}


def check_keywords(locale: str, keywords: str, name: str, subtitle: str) -> list:
    problems = []
    if re.search(r",\s", keywords):
        problems.append(f"{locale}/keywords.txt: remove spaces after commas")
    if keywords != keywords.strip() or "\n" in keywords:
        problems.append(f"{locale}/keywords.txt: must be a single line")
    items = keywords.split(",")
    seen = set()
    for raw in items:
        item = raw.strip().lower()
        if not item:
            problems.append(f"{locale}/keywords.txt: empty keyword (double or trailing comma)")
            continue
        if item in seen:
            problems.append(f"{locale}/keywords.txt: duplicate keyword '{item}'")
        seen.add(item)
    for item in seen:
        for suffix in ("s", "es"):
            if item + suffix in seen:
                problems.append(f"{locale}/keywords.txt: '{item}' and '{item + suffix}' are the same word")
    taken = words(name) | words(subtitle)
    for item in seen:
        for word in words(item):
            if word in taken:
                problems.append(f"{locale}/keywords.txt: '{word}' is already in the name or subtitle")
    return problems


def check_locale(folder: Path, locale: str) -> list:
    problems = []
    if not folder.is_dir():
        return [f"{locale}: folder {folder} is missing"]
    texts = {}
    for filename, limit in LIMITS.items():
        path = folder / filename
        if not path.is_file():
            problems.append(f"{locale}/{filename}: missing")
            continue
        text = read(path)
        texts[filename] = text
        if not text:
            problems.append(f"{locale}/{filename}: empty")
        if limit is not None and length(text) > limit:
            problems.append(f"{locale}/{filename}: {length(text)} characters, limit is {limit}")
        if filename.endswith("_url.txt") and not re.fullmatch(r"https://\S+", text):
            problems.append(f"{locale}/{filename}: must be a single https:// URL")
        for pattern in BANNED:
            if pattern.search(text):
                problems.append(f"{locale}/{filename}: uses the banned word '{pattern.pattern}'")
    if {"keywords.txt", "name.txt", "subtitle.txt"} <= texts.keys():
        problems += check_keywords(locale, texts["keywords.txt"], texts["name.txt"], texts["subtitle.txt"])
    if "name.txt" in texts and "Floor Age" not in texts["name.txt"]:
        problems.append(f"{locale}/name.txt: keep the brand name 'Floor Age'")
    return problems


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    metadata = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "fastlane" / "metadata"
    problems = []
    for filename, allowed in SHARED_FILES.items():
        path = metadata / filename
        if not path.is_file():
            problems.append(f"{filename}: missing")
        elif allowed is not None and read(path) not in allowed:
            problems.append(f"{filename}: '{read(path)}' should be one of {sorted(allowed)}")
        elif not read(path):
            problems.append(f"{filename}: empty")
    for locale in LOCALES:
        problems += check_locale(metadata / locale, locale)

    if problems:
        print("App Store metadata problems:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"App Store metadata OK: {len(LOCALES)} locales ({', '.join(LOCALES)}) within limits.")
    for locale in LOCALES:
        folder = metadata / locale
        sizes = ", ".join(
            f"{f.replace('.txt', '')} {length(read(folder / f))}/{LIMITS[f]}"
            for f in ("name.txt", "subtitle.txt", "keywords.txt", "promotional_text.txt", "description.txt")
        )
        print(f"  {locale}: {sizes}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
