#!/usr/bin/env python3
"""
Generate a comprehensive offline thesaurus JSON from Moby Thesaurus.

Moby Thesaurus is public domain and contains ~30K root words with
practical, commonly-used synonyms (similar to what Microsoft Word uses).

Usage:
    python3 generate_thesaurus.py

Outputs: MenubarThesaurus/Resources/thesaurus.json
"""

import json
import os
import urllib.request
import re

MOBY_URL = "https://raw.githubusercontent.com/words/moby/master/words.txt"
# Alternative: the full Moby Thesaurus from Gutenberg-style sources
MOBY_THESAURUS_URL = "https://raw.githubusercontent.com/jeffThompson/MobyThesaurus/refs/heads/master/mthesaur.txt"

OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "MenubarThesaurus", "Resources", "thesaurus.json"
)


def is_good_synonym(word: str) -> bool:
    """Filter out junk entries."""
    if not word or len(word) < 2 or len(word) > 25:
        return False
    # Skip multi-word phrases (keep hyphenated words)
    if " " in word:
        return False
    # Skip entries with weird characters
    if not all(c.isalpha() or c in "-'" for c in word):
        return False
    return True


def download_moby_thesaurus() -> dict:
    """Download and parse the Moby Thesaurus."""
    print("Downloading Moby Thesaurus...")
    try:
        req = urllib.request.Request(MOBY_THESAURUS_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except Exception as e:
        print(f"Failed to download: {e}")
        return {}

    # Try different encodings
    for encoding in ["utf-8", "latin-1", "cp1252"]:
        try:
            text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        text = raw.decode("latin-1", errors="replace")

    thesaurus = {}
    lines = text.strip().split("\n")
    print(f"Processing {len(lines)} entries...")

    for line in lines:
        line = line.strip()
        if not line:
            continue

        parts = line.split(",")
        if len(parts) < 2:
            continue

        root = parts[0].strip().lower()
        if not is_good_synonym(root):
            continue

        synonyms = []
        for s in parts[1:]:
            s = s.strip().lower()
            if is_good_synonym(s) and s != root:
                synonyms.append(s)

        if len(synonyms) >= 2:
            # Keep top 15 synonyms (they're roughly ordered by relevance in Moby)
            thesaurus[root] = synonyms[:15]

    return thesaurus


def main():
    thesaurus = download_moby_thesaurus()

    if not thesaurus:
        print("ERROR: Could not build thesaurus. Check internet connection.")
        return

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    with open(OUTPUT_PATH, "w") as f:
        json.dump(thesaurus, f, separators=(",", ":"), sort_keys=True)

    size_kb = os.path.getsize(OUTPUT_PATH) / 1024
    print(f"\nGenerated thesaurus with {len(thesaurus)} words ({size_kb:.0f} KB)")
    print(f"Saved to: {OUTPUT_PATH}")

    # Quick quality check
    test_words = ["activity", "happy", "beautiful", "run", "important", "change"]
    print("\nSample synonyms:")
    for w in test_words:
        syns = thesaurus.get(w, ["(not found)"])
        print(f"  {w}: {', '.join(syns[:8])}")


if __name__ == "__main__":
    main()
