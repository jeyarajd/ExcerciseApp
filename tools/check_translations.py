"""Checks the String Catalogs in FloorAge/Resources: every string has a Hindi and a Spanish
translation, and each translation keeps the same format placeholders as the English (a wrong or
missing %lld or %@ can show garbage or crash). Exits with an error listing the problems.

    python3 tools/check_translations.py
"""

import collections
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGS = ["Localizable", "InfoPlist", "Exercises", "Foods"]
LANGUAGES = ["hi", "es"]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:\.\d+)?(lld|ld|d|@|lf|f|%)")


def placeholders(text):
    return collections.Counter(kind for kind in PLACEHOLDER.findall(text) if kind != "%")


def value(entry, language):
    unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
    return unit.get("value") if unit.get("state") == "translated" else None


def main():
    problems = []
    for name in CATALOGS:
        path = os.path.join(ROOT, "FloorAge", "Resources", f"{name}.xcstrings")
        if not os.path.exists(path):
            problems.append(f"{name}.xcstrings is missing")
            continue
        strings = json.load(open(path, encoding="utf-8"))["strings"]
        for key, entry in strings.items():
            if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
                continue
            english = value(entry, "en") or key
            for language in LANGUAGES:
                translated = value(entry, language)
                if translated is None:
                    problems.append(f"{name}: no {language} translation for {key!r}")
                elif placeholders(translated) != placeholders(english):
                    problems.append(f"{name}: {language} placeholders differ for {key!r}: {translated!r}")
    if problems:
        print("\n".join(problems))
        sys.exit(f"{len(problems)} translation problem(s)")
    print("Translations complete for", ", ".join(LANGUAGES))


if __name__ == "__main__":
    main()
