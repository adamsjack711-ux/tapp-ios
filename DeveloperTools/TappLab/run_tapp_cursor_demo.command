#!/bin/zsh
# Physical iPhone demo: bounded, no touch injection or accessibility toggles.
set -eu
cd "${0:A:h}"
export TAPP_AUDIT_TWO=1
export TAPP_AUDIT_SMOOTH=1
exec .audit-venv/bin/python run_audit_overlay_probe.py
