#!/usr/bin/env python3
"""Time one Markdown file to one A4 PDF: `markview pdf` against `sgv-cli export`.

Each sample is a cold process, wall clock from spawn to exit, output written to
disk. The two exporters alternate within every round so both meet the same
machine load; the table is the median of the rounds. A4 only: it is the format
PDF export uses by default.

Usage:
    python3 scripts/markview-compare/export_bench.py --fixtures /tmp/fx \
        --markview ../markview/target/release/markview \
        --sgv core/target/release/sgv-cli [--runs 5] [names...]
"""
import argparse
import pathlib
import statistics
import subprocess
import tempfile
import time

DEFAULT = ["prose-10k", "prose-100k", "uprose-100k", "math-100k", "umath-100k",
           "prose-1m", "uprose-1m"]


def timed(cmd, reject_degraded=False):
    start = time.perf_counter()
    result = subprocess.run(cmd, capture_output=True)
    elapsed = time.perf_counter() - start
    if result.returncode != 0:
        raise SystemExit(f"{cmd[0]} failed:\n{result.stderr.decode(errors='replace')[-2000:]}")
    if reject_degraded and b"could not be rendered and were degraded" in result.stderr:
        raise SystemExit(f"{cmd}: equations degraded, the sample would measure a retry pass")
    return elapsed * 1000


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--fixtures", required=True, type=pathlib.Path)
    parser.add_argument("--markview", required=True)
    parser.add_argument("--sgv", required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("names", nargs="*", default=DEFAULT)
    args = parser.parse_args()

    out = pathlib.Path(tempfile.mkdtemp(prefix="sgv-export-bench-"))
    print(f"{'fixture':<12} {'markview':>9} {'sgv-cli':>9}   (ms, median of {args.runs})")
    for name in args.names:
        src = args.fixtures / f"{name}.md"
        markview, sgv = [], []
        for _ in range(args.runs):
            markview.append(timed([args.markview, "pdf", str(src), "-o", str(out / "mv.pdf"), "--offline"]))
            sgv.append(timed([args.sgv, "export", str(src), "-o", str(out / "sgv.pdf"), "-f", "a4"], reject_degraded=True))
        print(f"{name:<12} {statistics.median(markview):9.0f} {statistics.median(sgv):9.0f}")


if __name__ == "__main__":
    main()
