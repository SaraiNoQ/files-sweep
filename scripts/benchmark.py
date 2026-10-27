"""Generate a bounded fixture and compare scan bookkeeping to macOS du.

Only writes to a new .bench-fixture/<count> directory in this project.
Never deletes an existing directory or scans personal files.
"""
import argparse
import json
import os
import platform
import statistics
import subprocess
import time
from pathlib import Path

project = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--files", type=int, default=100_000)
parser.add_argument("--runs", type=int, default=3)
args = parser.parse_args()
if not 100 <= args.files <= 1_000_000 or not 1 <= args.runs <= 10:
    parser.error("files must be 100..1000000; runs must be 1..10")
root = project / ".bench-fixture" / str(args.files)
marker = root / ".fixture-complete"
if root.exists() and not marker.exists():
    raise SystemExit("Fixture exists but is incomplete; choose another size or inspect it manually.")
if not root.exists():
    root.mkdir(parents=True)
    for i in range(args.files):
        directory = root / f"project-{i // 1000:04d}"
        if i % 1000 == 0:
            directory.mkdir()
        with (directory / f"artifact-{i:07d}.bin").open("xb") as stream:
            if i % 16 == 0:
                stream.write(b"x" * 128)
    # A sparse file exercises logical versus physical size.
    with (root / "sparse.bin").open("xb") as stream:
        stream.truncate(2 * 1024**3)
    os.link(root / "project-0000/artifact-0000000.bin", root / "hardlink.bin")
    os.symlink("project-0000", root / "directory-link")
    marker.write_text(str(args.files))

binary = project / ".build/release/filesweep-bench"
scans, du_times = [], []
for _ in range(args.runs):
    scans.append(json.loads(subprocess.check_output([str(binary), str(root)], text=True)))
    start = time.perf_counter()
    du_bytes = int(subprocess.check_output(["/usr/bin/du", "-sk", str(root)], text=True).split()[0]) * 1024
    du_times.append(time.perf_counter() - start)
    assert scans[-1]["complete"], scans[-1]
    assert scans[-1]["allocatedBytes"] == du_bytes, (scans[-1], du_bytes)
    assert scans[-1]["entries"] == args.files + (args.files + 999) // 1000 + 5 + scans[-1]["finderMetadataEntries"]

report = {
    "os": platform.platform(), "fixtureFiles": args.files,
    "cacheState": "uncontrolled/warm after fixture creation; NOT a cold-cache benchmark",
    "runs": scans, "duSeconds": du_times,
    "medianScanSeconds": statistics.median(s["seconds"] for s in scans),
    "medianDuSeconds": statistics.median(du_times),
    "medianAnalysisSeconds": statistics.median(s["analysisSeconds"] for s in scans),
    "notes": "du retains no searchable tree. RSS includes metadata analysis. Finder .DS_Store files are counted and reported. APFS clone sharing is not deduplicated. No file content read by scanner."
}
output = project / "docs" / f"benchmark-{args.files}.json"
output.parent.mkdir(exist_ok=True)
output.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
