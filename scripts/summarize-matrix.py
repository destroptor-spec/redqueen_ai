#!/usr/bin/env python3
"""Tabulate a behavioural match series, grouped by payload and scouting mode.

Results from different trees are not comparable, and the mistake is easy to make
because the logs sit side by side in one directory. Every launch records the
hash of the simulation payload in `<log>.manifest.json`, so this groups by that
hash and scouting mode, keeping isolation arms in separate tables even when
they share exactly the same simulation sources.

usage: summarize-matrix.py [log ...]        (defaults to /tmp/rq-m-*.log)
"""
from __future__ import annotations

import glob
import json
import re
from collections import defaultdict
from pathlib import Path
import sys

FACTIONS = {'1': 'UEF', '2': 'Aeon', '3': 'Cybran', '4': 'Seraphim'}

# Experimental blueprints, so a run reports *which* ones it fielded rather than
# only how many. Roles mirror lua/AI/RedQueen/Experimentals.lua; see
# docs/experimental-classification.md. A count alone cannot show whether the
# classification picked an assault unit that can reach the enemy or a siege
# piece that never arrives.
EXPERIMENTALS = {
    'ual0401': 'Colossus/assault', 'uaa0310': 'CZAR/assault',
    'uas0401': 'Tempest/assault', 'xab2307': 'Salvation/siege',
    'xab1401': 'Paragon/economy',
    'url0402': 'Monkeylord/assault', 'xrl0403': 'Megalith/assault',
    'ura0401': 'SoulRipper/assault', 'url0401': 'Scathis/siege',
    'xsl0401': 'Ythotha/assault', 'xsa0402': 'Ahwassa/assault',
    'xsb2401': 'YolonaOss/siege',
    'uel0401': 'Fatboy/siege', 'ues0401': 'Atlantis/support',
    'ueb2401': 'Mavor/siege', 'xeb2402': 'Novax/intel',
}
def objectives(text: str) -> dict:
    """What the army was told to do, and how much of it Red Queen could command.

    A win rate cannot tell a defence that cost nothing from one that emptied the
    attack, and a dispatch total cannot tell an army that does not exist from
    one Red Queen is not allowed to command. Both are in the state line.
    """
    states = [line for line in text.splitlines() if 'state objective=' in line]
    pressure = re.findall(
        r'primary=(\S+?)/([0-9.]+) secondary=(\S+?)/([0-9.]+) pressure=(\w+)', text)
    held = sum(1 for row in pressure if row[4] == 'held')
    yielded = sum(1 for row in pressure if row[4] == 'yielded')
    idle = sum(1 for row in pressure if row[4] == 'idle')
    census = re.findall(r'army=(\d+)/(\d+)/(\d+)', text)
    unreachable = [int(a) - int(b) for a, b, _ in census]
    changes = len(re.findall(r'strategy objective=\w+ kind=', text))
    refused = len(re.findall(r'strategy objective-held ', text))
    kinds = re.findall(r'secondary=(\w+)/', text)
    return {
        'samples': len(states),
        'held': held,
        'yielded': yielded,
        'idle': idle,
        'changes': changes,
        'refused': refused,
        'peak_owned': max((int(c[0]) for c in census), default=0),
        'peak_available': max((int(c[2]) for c in census), default=0),
        'unreachable': (sum(unreachable) / len(unreachable)) if unreachable else 0.0,
        'defended': sum(1 for kind in kinds if kind != 'none'),
    }



RESULT = re.compile(r'\[RedQueen\]\[[A-Z]+\]\[army=(\d+)\] lifecycle game-result result=(\w+)')
# Red Queen labels its own log lines with the army it is playing, which is the
# only reliable way to find it among six armies. In a team match it is not
# necessarily the first AI, and its defeat is not the game's end -- its allies
# fight on, and the engine's stats block only arrives when the match really ends.
OWN_ARMY = re.compile(r'\[RedQueen\]\[[A-Z]+\]\[army=(\d+)\]')
CONTRACT = re.compile(r'match-contract army=(\d+) name=(\S+) faction=(\d+) side=(\w+)')
STARTED = re.compile(r'started version=(\S+) faction=(\d+)')
SCOUTING_MODE = re.compile(r'scouting mode=(\S+) production=(\S+) dispatch=(\S+)')
SCOUTING_FLAGS = {
    'combined': ('adaptive', 'on'),
    'production-only': ('adaptive', 'off'),
    'dispatch-only': ('binary', 'on'),
}
SCOUT_STATE = re.compile(
    r'\[RedQueen\]\[[A-Z]+\]\[army=(\d+)\] state .*?scout=(\d+)/(\d+)/(\d+)([^\n]*)')
# Forward-base lifecycle. Establishment is the measure that matters on large
# maps -- a site that is started and then lost cost engineers and bought
# nothing. `reason=` on a failure names what killed it, and `engineer-lost`
# specifically is what garrison cover is meant to prevent, so the reasons are
# reported rather than pooled into one failure count.
#
# These counts pool every Red Queen army in the run, not just the one whose
# kill/loss is tabulated: establishment is a property of the code under test and
# each Red Queen army exercises it independently, so pooling is more sample at
# no cost in interpretation.
FORWARD = re.compile(r'\[RedQueen\]\[[A-Z]+\]\[army=(\d+)\] forward base (\w+)(.*)')
FORWARD_REASON = re.compile(r'reason=([a-z-]+)')
# Mechanism figures from the periodic state line. An outcome cannot say which of
# several bundled changes moved it; these can. Peak income and factory count are
# how an economic strangulation shows up (two cells once ran 6 factories and 89
# mass where they had run 26 and 347), and engineers held against target is how
# a suppression ceiling shows up -- held tracking target exactly is the
# signature.
# Extractor capture and churn.
#
# Two traps here, both of which produced wrong findings before this comment
# existed. First, a team match has *several* Red Queen armies logging state
# lines, so a grep over the whole log interleaves them and manufactures a
# sawtooth out of two healthy curves -- always filter to one army. Second,
# mean-held over peak-held is not a retention measure: a series growing from 0
# to its peak yields 0.5-0.7 by construction, so a healthy economy scores the
# same as a raided one.
#
# Churn is the honest figure: extractors lost as a share of extractors gained,
# summed over the per-army series. Measured at 41% across 21 armies.
MEX = re.compile(r'\[RedQueen\]\[[A-Z]+\]\[army=(\d+)\] state .*?mex=(\d+)/(\d+)')

STATE = re.compile(
    r'\[RedQueen\]\[[A-Z]+\]\[army=(\d+)\] state .*?'
    r'mass=([\d.]+) .*?factories=(\d+)/(\d+).*?'
    r'eng=(\d+)/(\d+)/\d+(?:.*?engpolicy=(\d+)/(\d+))?')


def read_stats(text: str):
    """Return the engine's final per-army stats block, or an empty list."""
    for line in reversed(text.splitlines()):
        index = line.find('{"stats"')
        if index < 0:
            continue
        try:
            return json.JSONDecoder().raw_decode(line[index:])[0]['stats']
        except (ValueError, KeyError, TypeError):
            return []
    return []


def fielded_experimentals(row) -> list[str]:
    """Which experimentals this army actually built.

    The engine's per-blueprint `built` is this army's own production; `kills` in
    the same record counts enemy units of that blueprint destroyed, so only
    `built` may be read as ours.
    """
    blueprints = row.get('blueprints')
    if not isinstance(blueprints, dict):
        return []
    named = []
    for uid, counts in sorted(blueprints.items()):
        if uid in EXPERIMENTALS and (counts.get('built') or 0) > 0:
            named.append(f"{EXPERIMENTALS[uid]}x{counts['built']}")
    return named


def forward_bases(text: str) -> dict:
    """Count forward-base starts, establishments and losses, by cause."""
    tally = {'started': 0, 'established': 0, 'failed': 0, 'destroyed': 0}
    reasons: dict[str, int] = defaultdict(int)
    for _, event, rest in FORWARD.findall(text):
        if event not in tally:
            continue
        tally[event] += 1
        if event == 'failed':
            named = FORWARD_REASON.search(rest)
            reasons[named.group(1) if named else 'unnamed'] += 1
    tally['reasons'] = dict(sorted(reasons.items(), key=lambda kv: (-kv[1], kv[0])))
    return tally


def mechanisms(text: str) -> dict:
    """Peak economy and engineer figures for the first Red Queen army seen."""
    own = None
    peak_mass = 0.0
    peak_factories = 0
    peak_engineers = 0
    engineer_samples = 0
    at_or_below_target = 0
    suppressed = 0
    for match in STATE.finditer(text):
        army = match.group(1)
        if own is None:
            own = army
        if army != own:
            continue
        peak_mass = max(peak_mass, float(match.group(2)))
        peak_factories = max(peak_factories, int(match.group(3)))
        held, target = int(match.group(5)), int(match.group(6))
        peak_engineers = max(peak_engineers, held)
        engineer_samples += 1
        # Held never exceeding target is what a ceiling looks like from outside.
        if held <= target:
            at_or_below_target += 1
        if match.group(7):
            suppressed = max(suppressed, int(match.group(7)))
    pinned = (at_or_below_target / engineer_samples) if engineer_samples else 0.0
    return {
        'peak_mass': peak_mass,
        'factories': peak_factories,
        'engineers': peak_engineers,
        'pinned': pinned,
        'samples': engineer_samples,
        'suppressed': suppressed,
    }


def extractors(text: str) -> dict:
    """Extractor capture and retention for the first Red Queen army seen."""
    own = None
    held = []
    total = 0
    for match in MEX.finditer(text):
        if own is None:
            own = match.group(1)
        if match.group(1) != own:
            continue
        held.append(int(match.group(2)))
        total = max(total, int(match.group(3)))
    if not held:
        return {'peak': 0, 'total': 0, 'gained': 0, 'lost': 0, 'churn': 0.0}
    gained = sum(b - a for a, b in zip(held, held[1:]) if b > a)
    lost = sum(a - b for a, b in zip(held, held[1:]) if b < a)
    return {
        'peak': max(held),
        'total': total,
        'gained': gained,
        'lost': lost,
        'churn': lost / gained if gained else 0.0,
    }


def kill_loss(row) -> float:
    general = row.get('general', {})
    lost = general.get('lost', {}).get('mass', 0)
    return general.get('kills', {}).get('mass', 0) / lost if lost else 0.0


def scouting_mode(manifest: dict, text: str) -> str:
    """Corroborate requested mode with the flags the brain actually selected."""
    requested = manifest.get('scouting_mode')
    observed = set(SCOUTING_MODE.findall(text))
    if not observed:
        # Old logs do not establish which mechanisms ran. In particular the
        # sizing baseline predates adaptive production, so never call it combined.
        return f'unverified:{requested}' if requested else 'unrecorded'
    if len(observed) != 1:
        raise ValueError('Red Queen armies reported different scouting configurations')
    mode, production, dispatch = observed.pop()
    if SCOUTING_FLAGS.get(mode) != (production, dispatch):
        raise ValueError('scouting mode disagrees with the enabled mechanisms')
    if requested is not None and requested != mode:
        raise ValueError(f'manifest scouting mode {requested!r} differs from runtime {mode!r}')
    return mode


def scouting(text: str) -> dict:
    """Coverage samples and cumulative orders for the first Red Queen army."""
    own = OWN_ARMY.search(text)
    shares, fractions, held, scouts, fallback = [], [], [], [], []
    for army, targets, blind, _, rest in SCOUT_STATE.findall(text):
        if not own or army != own.group(1):
            continue
        if int(targets):
            shares.append(int(blind) / int(targets))
        totals = re.search(r'\bscoutorders=(\d+)/(\d+)', rest)
        if totals:
            scouts.append(int(totals.group(1)))
            fallback.append(int(totals.group(2)))
        count = re.search(r'\bscouts=(\d+)', rest)
        if count:
            held.append(int(count.group(1)))
        fraction = re.search(r'\bscoutfraction=([\d.]+)', rest)
        if fraction:
            fractions.append(float(fraction.group(1)))
    return {
        'samples': len(shares),
        'blind': sum(shares) / len(shares) if shares else None,
        # Never sum latest-pass Sent from old logs: the diagnostic cadence
        # misses combat passes. These are observed cumulative totals instead.
        'scout_orders': max(scouts) if scouts else None,
        'fallback_orders': max(fallback) if fallback else None,
        'held': max(held) if held else None,
        'fraction': (min(fractions), max(fractions)) if fractions else None,
    }


def combined_kill_loss(rows) -> float:
    """Kill/loss for a whole side, pooling mass rather than averaging ratios.

    Averaging per-army ratios would let one army that barely fought dominate the
    figure for a side that did the actual fighting.
    """
    killed = sum(row.get('general', {}).get('kills', {}).get('mass', 0) for row in rows)
    lost = sum(row.get('general', {}).get('lost', {}).get('mass', 0) for row in rows)
    return killed / lost if lost else 0.0


paths = sys.argv[1:] or sorted(glob.glob('/tmp/rq-m-*.log'))
groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
invalid = False

for name in paths:
    log = Path(name)
    if not log.is_file():
        continue
    text = log.read_text(errors='replace')
    manifest_path = log.with_name(log.name + '.manifest.json')
    payload, game_map, seed = '(no manifest)', '?', '?'
    manifest = {}
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text())
        payload = manifest.get('payload_sha256', '?')
        game_map = manifest.get('map', '?')
        seed = manifest.get('seed', '?')
    try:
        mode = scouting_mode(manifest, text)
    except ValueError as error:
        print(f'ERROR: {log}: {error}', file=sys.stderr)
        invalid = True
        continue
    started = STARTED.search(text)
    stats = read_stats(text)

    # Locate Red Queen among the armies. The stats block lists every army in
    # army order including the launching player, and `army=N` from the log is a
    # 1-based army index into that same order.
    own = OWN_ARMY.search(text)
    own_index = int(own.group(1)) - 1 if own else None
    outcome = next((match for match in RESULT.finditer(text)
                    if int(match.group(1)) - 1 == own_index), None)
    sides = {int(m.group(1)) - 1: m.group(4) for m in CONTRACT.finditer(text)}

    mine = None
    if stats and own_index is not None and 0 <= own_index < len(stats):
        mine = stats[own_index]
    elif stats:
        ai = [row for row in stats if row.get('type') == 'AI']
        mine = ai[0] if ai else None

    # Opposition is every army the contract calls an enemy; in a 1v1 that is the
    # single opponent, and in a team match it is the whole opposing side, which
    # is the only comparison that means anything there.
    enemies = [stats[i] for i, side in sides.items()
               if side == 'enemy' and 0 <= i < len(stats)]
    if not enemies and stats:
        ai = [row for row in stats if row.get('type') == 'AI' and row is not mine]
        enemies = ai[:1]

    contestants = sum(1 for side in sides.values() if side in ('ally', 'enemy'))
    groups[payload, mode].append({
        'run': log.name.replace('rq-m-', '').replace('.log', ''),
        'map': game_map,
        'seed': seed,
        'faction': FACTIONS.get(started.group(2), '?') if started else '(no start)',
        'result': outcome.group(2) if outcome else '(unfinished)',
        'kl': kill_loss(mine) if mine else None,
        'opponent': combined_kill_loss(enemies) if enemies else None,
        'experimentals': mine['units']['experimental']['built'] if mine else None,
        'sacus': mine['units']['sacu']['built'] if mine else None,
        'fielded': fielded_experimentals(mine) if mine else [],
        'contestants': contestants,
        'forward': forward_bases(text),
        'mechanism': mechanisms(text),
        'extractors': extractors(text),
        'scouting': scouting(text),
        'objectives': objectives(text),
    })

if not groups:
    if invalid:
        raise SystemExit(1)
    print('No match logs found.', file=sys.stderr)
    raise SystemExit(2)

for payload, mode in sorted(groups):
    rows = sorted(groups[payload, mode], key=lambda r: (r['map'], r['seed'], r['run']))
    print(f'payload {payload[:12]} scouting={mode}  ({len(rows)} runs)')
    print('  %-20s %-9s %-8s %-9s %-11s %6s %6s %4s %5s %4s %7s' % (
        'run', 'map', 'seed', 'faction', 'result', 'K/L', 'opp', 'exp', 'sacu', 'v', 'fb'))
    for row in rows:
        forward = row['forward']
        print('  %-20s %-9s %-8s %-9s %-11s %6s %6s %4s %5s %4s %7s' % (
            row['run'][:20], row['map'], row['seed'], row['faction'], row['result'],
            '%.2f' % row['kl'] if row['kl'] is not None else '-',
            '%.2f' % row['opponent'] if row['opponent'] is not None else '-',
            row['experimentals'] if row['experimentals'] is not None else '-',
            row['sacus'] if row['sacus'] is not None else '-',
            row['contestants'] or '-',
            '%d/%d' % (forward['established'], forward['started'])
            if forward['started'] else '-'))
        if row['fielded']:
            print('      fielded: ' + ', '.join(row['fielded']))
        scouts = row['scouting']
        if scouts['samples']:
            details = ['mean blind %.0f%% (%d samples)' % (100 * scouts['blind'], scouts['samples'])]
            if scouts['scout_orders'] is not None:
                details.append('orders through last sample: scout=%d fallback=%d' % (
                    scouts['scout_orders'], scouts['fallback_orders']))
            else:
                details.append('cumulative orders unrecorded')
            if scouts['held'] is not None:
                details.append('peak held %d' % scouts['held'])
            if scouts['fraction'] is not None:
                details.append('requested fraction %.3f-%.3f' % scouts['fraction'])
            print('      scouting: ' + ', '.join(details))
        mechanism = row['mechanism']
        if mechanism['samples']:
            print('      economy: peak mass %.1f, %d factories, %d engineers'
                  '  (held <= target in %.0f%% of samples%s)' % (
                      mechanism['peak_mass'], mechanism['factories'],
                      mechanism['engineers'], 100.0 * mechanism['pinned'],
                      ', %d builders suppressed' % mechanism['suppressed']
                      if mechanism['suppressed'] else ''))
        obj = row['objectives']
        if obj['samples']:
            print('      objectives: %d changes, %d refused; pressure %dh/%dy/%di;'
                  ' secondary filled in %d of %d samples' % (
                      obj['changes'], obj['refused'], obj['held'], obj['yielded'],
                      obj['idle'], obj['defended'], obj['samples']))
            print('      army: peak owned %d, peak commandable %d,'
                  ' mean beyond reach %.1f' % (
                      obj['peak_owned'], obj['peak_available'], obj['unreachable']))
        mex = row['extractors']
        if mex['peak']:
            print('      extractors: peak %d of %d on the map (%.0f%%),'
                  ' %d built / %d lost, churn %.2f' % (
                      mex['peak'], mex['total'],
                      100.0 * mex['peak'] / mex['total'] if mex['total'] else 0,
                      mex['gained'], mex['lost'], mex['churn']))
        if forward['reasons'] or forward['destroyed']:
            lost = ', '.join('%s=%d' % item for item in forward['reasons'].items())
            if forward['destroyed']:
                lost += (', ' if lost else '') + 'destroyed=%d' % forward['destroyed']
            print('      forward lost: ' + lost)
    finished = [r for r in rows if r['result'] in ('victory', 'defeat')]
    wins = sum(1 for r in finished if r['result'] == 'victory')
    print(f'  record: {wins}W/{len(finished) - wins}L of {len(finished)} finished')

    # Establishment rate across the group. A per-run figure is too small a
    # sample to read; the group rate is the one that moves under a change.
    started = sum(r['forward']['started'] for r in rows)
    established = sum(r['forward']['established'] for r in rows)
    causes: dict[str, int] = defaultdict(int)
    for row in rows:
        for reason, count in row['forward']['reasons'].items():
            causes[reason] += count
        if row['forward']['destroyed']:
            causes['destroyed'] += row['forward']['destroyed']
    kept = [r['extractors'] for r in rows if r['extractors']['peak']]
    if kept:
        gained = sum(k['gained'] for k in kept)
        print('  extractors: %d built / %d lost (churn %.2f), peak capture'
              ' %.0f%% of map points' % (
                  gained, sum(k['lost'] for k in kept),
                  sum(k['lost'] for k in kept) / max(1, gained),
                  100.0 * sum(k['peak'] for k in kept)
                  / max(1, sum(k['total'] for k in kept))))
    if started:
        print('  forward bases: %d/%d established (%.0f%%)%s' % (
            established, started, 100.0 * established / started,
            '  lost: ' + ', '.join('%s=%d' % item for item in
                                   sorted(causes.items(), key=lambda kv: (-kv[1], kv[0])))
            if causes else ''))
    print()

if len(groups) > 1:
    print('Runs span %d payload/scouting configurations; compare matched cells across groups.'
          % len(groups), file=sys.stderr)
if invalid:
    raise SystemExit(1)
