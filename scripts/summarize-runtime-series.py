#!/usr/bin/env python3
"""Summarize only recorded observations from an isolated match series."""
import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
args = parser.parse_args()
spec = importlib.util.spec_from_file_location('trace', Path(__file__).with_name('analyze-production-trace.py'))
trace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace)
for path in sorted(args.directory.glob('*.result.json')):
    result = json.loads(path.read_text())
    log = path.with_name(path.name.replace('.result.json', '.log'))
    text = log.read_text(errors='replace')
    events = trace.parse_events(text)
    own = [e for e in events if e['army'] == '2']
    stats = []
    for line in text.splitlines():
        index = line.find('{"stats"')
        if index >= 0:
            try: stats = json.JSONDecoder().raw_decode(line[index:])[0]['stats']
            except (ValueError, KeyError): pass
    results = re.findall(r'\[army=(\d+)\] lifecycle game-result result=(\w+) tick=(\d+)', text)
    result['results'] = results
    result['mass_kl'] = [round(row['general']['kills']['mass'] / max(1, row['general']['lost']['mass']), 3) for row in stats[1:]]
    result['max_factories'] = max([int(e['live']) for e in own if e['event'] == 'capacity'], default=None)
    result['alerts'] = text.count('defense alert started')
    decisions = Counter()
    for e in own:
        if e['event'] == 'aggregate' and e['subsystem'] == 'commitment': decisions[e['state']] += int(e['count'])
    result['commitment'] = dict(decisions)
    projects = Counter(e['outcome'] for e in own if e['event'] == 'construction-outcome' and e['subsystem'] == 'projects')
    result['projects'] = dict(projects)
    result['traced_project_starts'] = sum(e['event'] == 'construction-start' and e['subsystem'] == 'projects' for e in own)
    result['overflow'] = sum(e['event'] == 'overflow' or e.get('coverage') == 'incomplete' for e in own)
    result['lua_errors'] = text.count('Error running lua script')
    result['invalid_locations'] = text.count('Invalid location')
    result['log_bytes'] = log.stat().st_size
    manifest = json.loads(Path(str(log) + '.manifest.json').read_text())
    result['payload'] = manifest['payload_sha256']
    print(json.dumps(result, sort_keys=True))
