#!/usr/bin/env python3
"""Record the exact launch payload; income and starts require runtime corroboration."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root, log, map_name, difficulty = sys.argv[1:]
root = Path(root)
files = sorted([root / 'mod_info.lua'] + list((root / 'lua').rglob('*.lua')) + list((root / 'hook').rglob('*.lua')))
hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
manifest = {
    'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'status': subprocess.check_output(['git', 'status', '--short'], cwd=root, text=True),
    'payload_sha256': hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest(),
    'files': hashes, 'map': map_name, 'difficulty': difficulty,
    'factions': 'Verify actual match-contract; fixed only with FAF_FIXED_RUNTIME=1',
    # Record what was actually launched. A hardcoded seed here made every
    # manifest in a varied series claim the default, which silently destroys
    # the attribution the manifest exists to provide.
    'seed': int(os.environ.get('FAF_SEED', '2071971')),
    'red_queen_faction': os.environ.get('FAF_RQ_FACTION', '2'),
    'opponent_faction': os.environ.get('FAF_OPP_FACTION', '3'),
    'mixed': os.environ.get('FAF_MIXED', '0'),
    'fixed_runtime': os.environ.get('FAF_FIXED_RUNTIME', '0'),
    'scouting_mode': os.environ.get('FAF_SCOUTING_MODE', 'combined'),
    'starts_and_actual_income': 'Must be verified from match-contract in the log',
}
Path(log + '.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
Path(log + '.patch').write_bytes(subprocess.check_output(['git', 'diff', '--binary'], cwd=root))
