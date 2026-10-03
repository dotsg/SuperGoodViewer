#!/usr/bin/env python3
"""Generate the fixtures used by docs/MARKVIEW_COMPARISON.md.

Two families, all deterministic:

* ``prose-*`` / ``math-*`` -- markview's own comparison fixtures, produced by
  its ``scripts/comparison_fixtures.py`` (a markview checkout is required).
  They repeat six paragraph bodies (and one block of seven formulas) until the
  target size, which a content-keyed layout cache resolves almost for free.
* ``uprose-*`` / ``umath-*`` -- the same vocabulary and the same formula
  shapes, but every paragraph is a different random draw of words and every
  formula carries different numerals, so no two blocks are identical.

Usage:
    python3 scripts/markview-compare/fixtures.py --markview ../markview --out /tmp/fx
"""
import argparse
import pathlib
import random
import re
import sys

UNIQUE = {"uprose-100k": (100 * 1024, False), "uprose-1m": (1024 * 1024, False),
          "umath-100k": (100 * 1024, True)}
FILLER = "Short words keep the final line readable. "


def unique_text(fixtures, target, maths, seed):
    rng = random.Random(seed)
    words = " ".join(fixtures.PARAGRAPHS).split()
    text = "# A comparison document\n\n"
    while True:
        block = " ".join(rng.choice(words) for _ in range(rng.randint(45, 80)))
        block = block.capitalize().rstrip(".,") + ".\n\n"
        if maths:
            # Numerals only: rewriting letters would break commands such as \xi.
            block += re.sub(r"(?<![a-zA-Z\\])\d+", lambda _: str(rng.randint(2, 999)),
                            "".join(fixtures.MATH))
        if len((text + block).encode()) > target:
            break
        text += block
    remaining = target - len(text.encode())
    return text + (FILLER * (remaining // len(FILLER) + 1))[:remaining]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--markview", required=True, type=pathlib.Path,
                        help="path to a markview checkout")
    parser.add_argument("--out", required=True, type=pathlib.Path)
    args = parser.parse_args()

    sys.path.insert(0, str(args.markview / "scripts"))
    import comparison_fixtures as fixtures  # noqa: E402  (markview, MIT)

    args.out.mkdir(parents=True, exist_ok=True)
    for path in fixtures.write(args.out, ("10k", "100k", "1m", "math-10k", "math-100k")):
        print(path)
    for seed, (name, (size, maths)) in enumerate(UNIQUE.items(), start=1):
        path = args.out / f"{name}.md"
        text = unique_text(fixtures, size, maths, seed)
        assert len(text.encode()) == size
        path.write_text(text)
        print(path)


if __name__ == "__main__":
    main()
