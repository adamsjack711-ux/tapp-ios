#!/usr/bin/env python3
"""Read installed simulator binaries; never launch a runtime or contact a phone.

Writes selected static evidence, not Apple binaries. Simulator entitlements in
__TEXT,__entitlements are distinct from codesign's often-empty signature result.
Neither proves the privileges or behavior of a physical device build.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def section(data, wanted_segment, wanted_section):
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin little-endian 64-bit Mach-O")
    cursor = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, length = struct.unpack_from("<II", data, cursor)
        if length < 8 or cursor + length > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command == 0x19:
            count = struct.unpack_from("<I", data, cursor + 64)[0]
            for index in range(count):
                entry = cursor + 72 + index * 80
                if entry + 80 > cursor + length:
                    raise ValueError("Invalid Mach-O section table")
                name, segment, _, size, offset = struct.unpack_from("<16s16sQQI", data, entry)
                if (segment.rstrip(b"\0"), name.rstrip(b"\0")) == (wanted_segment, wanted_section):
                    if offset + size > len(data):
                        raise ValueError("Section outside file")
                    return data[offset:offset + size], offset
        cursor += length
    raise ValueError("Requested Mach-O section not present")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "-j"))["runtimes"]
    args.output.mkdir(parents=True, exist_ok=True)
    found = 0
    for runtime in runtimes:
        if not runtime.get("isAvailable") or not runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        binary = Path(runtime["runtimeRoot"]) / "System/Library/CoreServices/AssistiveTouch.app/assistivetouchd"
        if not binary.is_file():
            continue
        data = binary.read_bytes()
        embedded, offset = section(data, b"__TEXT", b"__entitlements")
        entitlements = plistlib.loads(embedded.rstrip(b"\0"))
        imports = run("xcrun", "nm", "-u", str(binary)).splitlines()
        libraries = run("xcrun", "otool", "-L", str(binary)).splitlines()[1:]
        strings = run("strings", str(binary)).splitlines()
        disassembly = run("xcrun", "llvm-objdump", "--macho", "--disassemble", str(binary)).splitlines()
        indexes = set()
        for i, line in enumerate(disassembly):
            if "symbol stub for: __AXSPointerControlEnabled" in line:
                indexes.update(range(max(0, i - 10), min(len(disassembly), i + 28)))
        excerpts = []
        previous = -2
        for i in sorted(indexes):
            if i != previous + 1:
                excerpts.append("\n... disassembly excerpt ...")
            excerpts.append(disassembly[i])
            previous = i
        selected_keys = re.compile(r"(accessibility|backboard|frontboard|pointerui|hid\.|QuartzCore|platform-application|seatbelt)", re.I)
        selected_symbols = re.compile(r"(BKSMouse|BKSHID|AXUIDaemon|AXSpringBoard|HIDVirtual|AXSPointer|PointerControl|IOHIDEvent)")
        selected_strings = re.compile(r"^(HND.*(Pointer|Mouse|Window|Display|Event)|canShowASTMousePointer|resetSystemPointerToPoint:|requestGlobalMouseEventsForDisplay:.*|setCurrentAbsoluteSystemPointerPoint:.*|currentAbsoluteSystemPointerPoint|_updateAutoHideMousePointer|_pointerControlEnabledChanged|assistiveTouchMousePointerTimeout.*|moveSystemPointerIfActiveToPoint:onDisplay:)$")
        info = {
            "scope": "Static simulator evidence only; no physical-device execution or entitlement authorization proven",
            "runtime": {k: runtime.get(k) for k in ("name", "version", "buildversion", "identifier")},
            "binary_path": str(binary),
            "sha256": hashlib.sha256(data).hexdigest(),
            "macho_uuids": re.findall(r"uuid ([0-9A-F-]+)", run("xcrun", "otool", "-l", str(binary))),
            "embedded_entitlements": {"section": "__TEXT,__entitlements", "offset": offset,
                "length": len(embedded), "selected_values": {k: v for k, v in entitlements.items() if selected_keys.search(k)}},
            "private_dependencies": [s.strip() for s in libraries if "/PrivateFrameworks/" in s],
            "selected_imports": [s.strip() for s in imports if selected_symbols.search(s)],
            "selected_strings_not_method_call_proof": sorted(set(s for s in strings if selected_strings.match(s))),
        }
        name = runtime["identifier"].removeprefix("com.apple.CoreSimulator.SimRuntime.")
        (args.output / (name + ".json")).write_text(json.dumps(info, indent=2) + "\n")
        (args.output / (name + "-pointer-control.asm.txt")).write_text("\n".join(excerpts) + "\n")
        print(f"{name}: {len(data)} bytes inspected, {len(excerpts)} disassembly lines saved")
        found += 1
    if not found:
        raise SystemExit("No available iOS simulator AssistiveTouch binaries found")


if __name__ == "__main__":
    main()
