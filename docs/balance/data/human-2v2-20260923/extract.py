#!/usr/bin/env python3
"""Re-extract this study from its preserved logs; never launches a game."""
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def extract(game, text):
    samples, events, watches, stats = [], [], {}, []
    contracts, outcomes = [], []
    for line_number, line in enumerate(text.splitlines(), 1):
        if "JsonStats" in line:
            payload = line.split("JsonStats", 1)[1]
            stats = json.JSONDecoder().raw_decode(payload[payload.index('{'):])[0]['stats']
        if "GpgNetSend\tGameResult\t" in line:
            outcomes.append(line.split("GameResult\t", 1)[1])
        match = re.search(r'\[RedQueen\]\[\w+\]\[army=(\d+)\] (.*)', line)
        if not match:
            continue
        army, message = int(match[1]), match[2]
        if 'income contract' in message or 'match-contract' in message or 'started version=' in message:
            contracts.append(message)
        fields = dict(re.findall(r'(\w+)=([^ ]+)', message))
        if message.startswith('watch '):
            watches[army] = fields
        if message.startswith('state '):
            watch = watches.get(army, {})
            if 'army' in fields:
                fields['army_census'] = fields.pop('army')
            row = {'game': game, 'army': army, 'line': line_number,
                   't': int(watch['t']) if 't' in watch else None, **fields}
            row.update({'watch_' + k: v for k, v in watch.items()})
            samples.append(row)
        if message.startswith('forward base ') or message.startswith('production expansion type='):
            events.append({'game': game, 'army': army, 'line': line_number,
                           'preceding_watch_t': watches.get(army, {}).get('t'), 'message': message})
    summary = {'game': game, 'contracts': contracts, 'outcomes': outcomes, 'armies': {}}
    for army in sorted({row['army'] for row in samples}):
        rows = [row for row in samples if row['army'] == army]
        alerts = [row for row in rows if row['alert'].startswith('yes/')]
        cover = [list(map(float, row['defcover'].split('/'))) for row in alerts if 'defcover' in row]
        owned_events = [e['message'] for e in events if e['army'] == army]
        failed = [e for e in owned_events if e.startswith('forward base failed ')]
        result = {
            'samples': len(rows), 'last_watch_seconds': rows[-1]['t'],
            'modes': dict(collections.Counter(row['eco'] for row in rows)),
            'peak_mex': max(int(row['mex'].split('/')[0]) for row in rows),
            'final_mex': int(rows[-1]['mex'].split('/')[0]),
            'peak_mass_per_tick': max(float(row['mass']) for row in rows),
            'final_mass_per_tick': float(rows[-1]['mass']),
            'alert_samples': len(alerts),
            'alert_zero_coverage': sum(c[1] == 0 for c in cover),
            'alert_mean_defences': sum(c[0] for c in cover) / len(cover) if cover else None,
            'alert_mean_covering': sum(c[1] for c in cover) / len(cover) if cover else None,
            'last_mexloss_lost_defended': rows[-1].get('mexloss'),
            'forward_started': sum(e.startswith('forward base started ') for e in owned_events),
            'forward_established': sum(e.startswith('forward base established ') for e in owned_events),
            'forward_destroyed': sum(e.startswith('forward base destroyed ') for e in owned_events),
            'forward_failures': dict(collections.Counter(re.search(r'reason=(\S+)', e)[1] for e in failed)),
            'recall_failure_messages': sum(e.startswith('forward base recall failed ') for e in owned_events),
            'recall_failure_unique_bases': sorted({re.search(r'name=(\S+)', e)[1] for e in owned_events if e.startswith('forward base recall failed ')}),
            'power_storage_below_3pct_samples': sum(float(row['watch_store'].split('/')[1]) < .03 for row in rows if 'watch_store' in row),
        }
        summary['armies'][army] = result
    (HERE / f'{game}-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (HERE / f'{game}-stats.json').write_text(json.dumps(stats, indent=2) + '\n')
    for name, rows in [('samples', samples), ('events', events)]:
        columns = list(dict.fromkeys(k for row in rows for k in row))
        with (HERE / f'{game}-{name}.csv').open('w') as f:
            writer = csv.DictWriter(f, fieldnames=columns)
            writer.writeheader()
            writer.writerows(rows)
    return summary


if __name__ == '__main__':
    # Temporary extraction is solely for the existing analyzer's path argument.
    import tempfile
    with tarfile.open(HERE / 'raw-logs.tar.gz') as archive, tempfile.TemporaryDirectory() as temporary:
        for member in archive.getmembers():
            if not member.isfile() or not member.name.endswith('.log'):
                continue
            raw = archive.extractfile(member).read()
            name = Path(member.name).name
            path = Path(temporary) / name
            path.write_bytes(raw)
            result = subprocess.run(['python3', str(ROOT / 'scripts/analyze-log.py'), str(path)], capture_output=True, text=True)
            game = re.search(r'game_(\d+)', name)[1]
            (HERE / f'{game}-analysis.txt').write_text(result.stdout + result.stderr)
            if result.returncode:
                raise SystemExit(f'Analyzer rejected {name}: {result.returncode}')
            summary = extract(game, raw.decode(errors='replace'))
            print(json.dumps({'game': game, 'sha256': hashlib.sha256(raw).hexdigest(), 'armies': summary['armies']}, indent=2))
