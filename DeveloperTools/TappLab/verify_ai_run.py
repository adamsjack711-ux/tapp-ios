#!/usr/bin/env python3
"""Verify saved AI/device evidence without controlling the device."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--prefix", required=True)
parser.add_argument("--expected", required=True, choices=["Top left", "Top right", "Bottom left", "Bottom right", "Centre ready"])
parser.add_argument("--evidence", type=Path, default=Path(__file__).parent / "Evidence")
args = parser.parse_args()
root = args.evidence
report = json.loads((root / f"{args.prefix}-report.json").read_text())
counts = json.loads((root / f"{args.prefix}-counts.json").read_text())
trace = [json.loads(line) for line in (root / f"{args.prefix}-trace.jsonl").read_text().splitlines() if line]
assert report["verified"] and report["stage"] == "complete" and not report["error"], report
assert report["modelSelectedLabel"] == args.expected
names = ["Top left", "Top right", "Bottom left", "Bottom right"]
assert counts["corners"] == {name: int(name == args.expected) for name in names}, counts
assert counts["clicks"] == int(args.expected == "Centre ready")
assert counts["foreground"] is True
events = counts["events"]
assert not any(e["event"] in ["touch-up-outside", "touch-cancelled"] for e in events)
window = [e for e in events if e["event"] == "window-touch"]
assert len(window) == 2 and [e["phase"] for e in window] == [0, 3], window
assert report["started"] <= window[0]["time"] <= window[1]["time"] <= report["time"]
assert not any(e["event"] == "inactive" and window[0]["time"] <= e["time"] <= window[1]["time"] for e in events)
run = [e for e in trace if report["started"] <= e["time"] <= report["time"]]
assert not any(e["stage"].startswith("failed") or e["stage"] == "corner-background-expired" for e in run)
starts = [e for e in run if e["stage"] == "corner-batch-started"]
assert len(starts) == 1 and starts[0]["continuedBackgroundGranted"] is True
validated = [e for e in run if e["stage"] == "validated-before-touch"]
sent = [e for e in run if e["stage"] == "touch-down-and-up-sent"]
assert len(validated) == len(sent) == 1
assert validated[0]["operation"] == sent[0]["operation"]
assert validated[0]["time"] <= sent[0]["time"]
for received in window:
    assert abs(received["x"] - validated[0]["x"]) < 0.005
    assert abs(received["y"] - validated[0]["y"]) < 0.005
assert len([e for e in run if e["stage"] == "corner-batch-media-cleanup-verified"]) == 1
print(json.dumps({"runID": report["runID"], "request": report["request"],
    "modelSelectedLabel": args.expected, "verifiedClicks": 1,
    "independentCountersVerified": True, "nativeInputVerified": True,
    "ownedMediaCleanupVerified": True,
    "elapsedSeconds": round(report["time"] - report["started"], 2)}, indent=2))
