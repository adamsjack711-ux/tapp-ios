#!/usr/bin/env python3
"""Verify saved physical-device evidence; never controls a device or sends input."""
import argparse
import json
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument("--prefix",default="ten-pass-final")
parser.add_argument("--evidence",type=Path,default=Path(__file__).parent/"Evidence")
args=parser.parse_args()
root=args.evidence
report=json.loads((root/f"{args.prefix}-report.json").read_text())
counts=json.loads((root/f"{args.prefix}-counts.json").read_text())
trace=[json.loads(line) for line in (root/f"{args.prefix}-trace.jsonl").read_text().splitlines() if line]
names=["Top left","Top right","Bottom left","Bottom right"]
expected=[f"{p}: {name}" for p in range(1,11) for name in names]
assert report["verified"] and report["stage"]=="complete" and not report["error"], report
assert report["requestedPasses"]==report["completedPasses"]==10
assert report["completed"]==expected
assert counts["corners"]==dict.fromkeys(names,10), counts["corners"]
assert counts["clicks"]==0 and counts["foreground"] is True
clicks=[e for e in counts["events"] if e["event"]=="click"]
assert len(clicks)==40
downs=[e for e in counts["events"] if e["event"]=="touch-down"]
assert len(downs)==40
assert [e["corner"] for e in downs]==[e["corner"] for e in clicks]
assert not any(e["event"] in ["touch-up-outside","touch-cancelled"] for e in counts["events"])
for index,event in enumerate(clicks):
    assert event["corner"]==names[index%4] and event["count"]==index//4+1
    assert event["foreground"] is True
assert not any(e["event"]=="inactive" and clicks[0]["time"]<=e["time"]<=clicks[-1]["time"] for e in counts["events"])
assert report["started"]<=clicks[0]["time"]<=clicks[-1]["time"]<=report["time"]
run=[e for e in trace if report["started"]<=e["time"]<=report["time"]]
starts=[e for e in run if e["stage"]=="corner-batch-started"]
assert len(starts)==1 and starts[0]["continuedBackgroundGranted"] is True
assert not any(e["stage"].startswith("failed") or e["stage"]=="corner-background-expired" for e in run)
touches=[e for e in run if e["stage"]=="touch-down-and-up-sent"]
assert len(touches)==40 and len({e["operation"] for e in touches})==40
for touch in touches:
    assert any(e["operation"]==touch["operation"] and e["stage"]=="validated-before-touch" and e["time"]<=touch["time"] for e in run)
window=[e for e in counts["events"] if e["event"]=="window-touch"]
assert len(window)==80 and [e["phase"] for e in window]==[0,3]*40
validated=[e for e in run if e["stage"]=="validated-before-touch"]
for index, target in enumerate(validated):
    for received in window[index*2:index*2+2]:
        assert abs(received["x"]-target["x"])<0.005
        assert abs(received["y"]-target["y"])<0.005
assert len([e for e in run if e["stage"]=="corner-batch-media-cleanup-verified"])==1
summary={"runID":report["runID"],"verifiedClicks":40,"verifiedPasses":10,
         "stayedForeground":True,"nativeInputVerified":True,"ownedMediaCleanupVerified":True,
         "elapsedSeconds":round(report["time"]-report["started"],2),
         "clickSpanSeconds":round(clicks[-1]["time"]-clicks[0]["time"],2)}
print(json.dumps(summary,indent=2))
