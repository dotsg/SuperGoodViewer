#!/usr/bin/env python3
"""Time the desktop app from process spawn to the first displayed document.

Needs a Profile build: `StartupMetrics` logs are silent in release builds.
Every sample:

* opens a fresh copy of the fixture (unique path and content), so the compiled
  PDF cache under ~/Library/Caches never serves it;
* runs with a private HOME, so it neither reads nor rewrites the user's
  preferences and every build sees the same default render options;
* reports the wall-clock time at which the app logs
  "time to first document displayed", and how many compiles it started.

The probe fires on the frame after the PDF viewer reports ready; page tiles
may still be rasterizing, so the number is a lower bound of "on screen".

Several apps can be compared; they alternate within every round. Each is
`LABEL=APP_EXECUTABLE[@CWD]`: in non-release builds the engine library is
also looked up relative to the working directory (`../core/target/release`
from `core/`), which selects which `libsogood_core.dylib` a build loads.

Usage:
    python3 scripts/markview-compare/gui_open_bench.py --fixtures /tmp/fx \
        --app "after=ui/build/macos/Build/Products/Profile/SuperGoodViewer.app/Contents/MacOS/SuperGoodViewer@core" \
        [--app before=...] [--runs 5] [names...]
"""
import argparse
import os
import pathlib
import select
import statistics
import subprocess
import tempfile
import time
import uuid

DEFAULT = ["prose-10k", "prose-100k", "math-100k", "prose-1m"]


def sample(app, cwd, fixture, scratch, home):
    copy = scratch / f"{uuid.uuid4().hex[:8]}-{fixture.name}"
    copy.write_bytes(fixture.read_bytes() + f"\n\n<!-- {copy} -->\n".encode())
    start = time.perf_counter()
    proc = subprocess.Popen([app, str(copy)], cwd=cwd, env={**os.environ, "HOME": str(home)},
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    compiles, shown = 0, None
    deadline = time.time() + 15
    try:
        while time.time() < deadline:
            ready, _, _ = select.select([proc.stdout], [], [], 0.2)
            if not ready:
                continue
            line = proc.stdout.readline()
            if not line:
                break
            if "Failed to load native engine" in line:
                raise SystemExit(f"{app}: engine library not found from cwd {cwd}")
            if "compileDocument: starting gen" in line:
                compiles += 1
            if "time to first document displayed" in line:
                shown = (time.perf_counter() - start) * 1000
                break
    finally:
        proc.kill()
        proc.wait()
    if shown is None:
        raise SystemExit(f"{app}: no first-document probe for {fixture.name} (not a Profile build?)")
    return shown, compiles


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--fixtures", required=True, type=pathlib.Path)
    parser.add_argument("--app", action="append", required=True, help="LABEL=EXECUTABLE[@CWD]")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("names", nargs="*", default=DEFAULT)
    args = parser.parse_args()

    apps = []
    for spec in args.app:
        label, _, rest = spec.partition("=")
        exe, _, cwd = rest.partition("@")
        apps.append((label, os.path.abspath(exe), os.path.abspath(cwd or ".")))

    scratch = pathlib.Path(tempfile.mkdtemp(prefix="sgv-gui-bench-"))
    home = scratch / "home"
    home.mkdir()
    warm = args.fixtures / f"{args.names[0]}.md"
    for _, exe, cwd in apps:  # page cache, font index cache under the private HOME
        sample(exe, cwd, warm, scratch, home)

    for name in args.names:
        fixture = args.fixtures / f"{name}.md"
        times = {label: [] for label, _, _ in apps}
        compiles = {label: set() for label, _, _ in apps}
        for _ in range(args.runs):
            for label, exe, cwd in apps:
                shown, count = sample(exe, cwd, fixture, scratch, home)
                times[label].append(shown)
                compiles[label].add(count)
        cells = "  ".join(f"{label} {statistics.median(times[label]):5.0f} ms (compiles {sorted(compiles[label])})"
                          for label, _, _ in apps)
        print(f"{name:<11} {cells}")


if __name__ == "__main__":
    main()
