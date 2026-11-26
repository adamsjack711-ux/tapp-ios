#!/usr/bin/env python3
"""Inspect locally cached iPhone symbols, without connecting to or modifying a phone.

Extracted dyld-cache external-call labels can be misleading. Only symbols inside
the inspected image are authoritative in the saved disassembly.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def inspect(path, names, output, label):
    data = path.read_bytes()
    symbols = []
    for line in run('xcrun', 'nm', '-nm', str(path)).splitlines():
        match = re.match(r'([0-9a-f]+) \(([^)]+)\) .*? (\S.*)', line)
        if match:
            # Symbol names may contain spaces; take the known nm qualifier off.
            name = line.split(') ', 1)[1]
            name = re.sub(r'^(?:non-external|external|private external) ', '', name)
            name = name.removeprefix('(was a private external) ')
            symbols.append((int(match[1], 16), match[2], name))
    text_symbols = sorted((a, n) for a, section, n in symbols if section == '__TEXT,__text')
    selected = {}
    excerpts = []
    for wanted in names:
        index = next(i for i, (_, name) in enumerate(text_symbols) if name == wanted)
        address = text_symbols[index][0]
        end = text_symbols[index + 1][0]
        selected[wanted] = {'start': hex(address), 'end': hex(end)}
        excerpts.append(run('xcrun', 'llvm-objdump', '--disassemble', '--symbolize-operands',
                            '--start-address=' + hex(address), '--stop-address=' + hex(end), str(path)))
    (output / (label + '.asm.txt')).write_text('\n'.join(excerpts))
    metadata = {'path': str(path), 'sha256': hashlib.sha256(data).hexdigest(),
                'uuid': run('xcrun', 'dwarfdump', '--uuid', str(path)).strip(), 'functions': selected}
    if label == 'phone-quartz-gates':
        # This cached arm64e image uses shared-cache relative chained pointers.
        # Resolve only mapped addresses, then validate the decoded entitlement names.
        segments = []
        cursor = 32
        for _ in range(struct.unpack_from('<I', data, 16)[0]):
            command, length = struct.unpack_from('<II', data, cursor)
            if command == 0x19:
                vm, _, offset, size = struct.unpack_from('<QQQQ', data, cursor + 24)
                segments.append((vm, size, offset))
            cursor += length

        def read(address, count):
            for vm, size, offset in segments:
                if vm <= address and address + count <= vm + size:
                    return data[offset + address - vm:offset + address - vm + count]
            raise ValueError('Unmapped address ' + hex(address))

        def pointer(address):
            value = struct.unpack('<Q', read(address, 8))[0]
            if any(vm <= value < vm + size for vm, size, _ in segments):
                return value
            return (value & 0xffffffff) + 0x180000000

        table = next(a for a, _, name in symbols if name == '__ZZN2CA6Render6Server28entitlements_for_audit_tokenERK13audit_token_tE3str')
        entries = []
        for bit in range(17):
            string_object = pointer(table + bit * 8)
            value = read(pointer(string_object + 16), 100).split(b'\0')[0].decode()
            if not value.startswith('com.apple.QuartzCore.'):
                raise ValueError('Unrecognized entitlement table layout; do not infer its bit mapping')
            entries.append({'bit': bit, 'entitlement': value})
        metadata['entitlements_table'] = {'address': hex(table), 'entries': entries,
                                          'layout_scope': '17 entries verified for cached iOS 27.2 24B5089g image'}
        metadata['context_options'] = {}
        for option in ('_kCAContextDisplayable', '_kCAContextDisplayId'):
            address = next(a for a, _, name in symbols if name == option)
            string_object = pointer(address)
            metadata['context_options'][option] = {
                'string_object_address': hex(string_object),
                'value': read(pointer(string_object + 16), 100).split(b'\0')[0].decode(),
            }
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--symbols', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    metadata = {'scope': 'Offline cached phone-image analysis; no runtime feature-state measurement', 'images': []}
    metadata['images'].append(inspect(args.symbols / 'usr/lib/libAccessibility.dylib', [
        '__AXSPointerControlEnabled', '__AXSPointerControlSetEnabled',
        '_AXRuntimeCheck_AXAction', '_AXRuntimeCheck_AXAction_PointerControl',
    ], args.output, 'phone-accessibility-gates'))
    metadata['images'].append(inspect(args.symbols / 'System/Library/Frameworks/QuartzCore.framework/QuartzCore', [
        '__ZN2CA6Render6Server24audit_token_cache_lookupERK13audit_token_t', '__XRegisterClient',
        '__ZN2CA6Render7ContextC1EPK14__CFDictionaryjji',
        '__ZN2CA12WindowServer6Server15context_createdEPNS_6Render6ObjectEPvS5_',
    ], args.output, 'phone-quartz-gates'))
    metadata['images'].append(inspect(args.symbols / 'System/Library/PrivateFrameworks/PointerUIServices.framework/PointerUIServices', [
        '-[PSPointerClientController clientInteractionState]',
        '-[PSPointerClientController pointerVisibilityState]',
        '-[PSPointerClientController isClientInteractionEnabled]',
        '___61-[PSPointerClientController clientInteractionStateDidChange:]_block_invoke_2',
        '___61-[PSPointerClientController pointerVisibilityStateDidChange:]_block_invoke.52',
    ], args.output, 'phone-pointer-client'))
    metadata['images'].append(inspect(args.symbols / 'System/Library/PrivateFrameworks/PointerUISystemServices.framework/PointerUISystemServices', [
        '-[PSPointerSystemClientController prepareScenesForPointerForDisplayConfiguration:]',
        '-[PSPointerSystemClientController invalidateScenesForPointerForDisplayConfiguration:]',
    ], args.output, 'phone-pointer-scene'))
    (args.output / 'phone-symbols.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print('Saved offline phone-symbol evidence:', args.output)


if __name__ == '__main__':
    main()
