#!/usr/bin/env python3
"""Check bash syntax of release-smoke.sh"""
import subprocess
import sys

result = subprocess.run(
    ["bash", "-n", "scripts/release-smoke.sh"],
    capture_output=True,
    text=True
)
if result.returncode == 0:
    print("bash -n: SYNTAX OK")
else:
    print("bash -n: SYNTAX ERROR")
    print(result.stderr)
    sys.exit(1)
