#!/usr/bin/env python3
"""Paired comparison of two payloads over the same deterministic cells.

Cells are deterministic, so each pair is the same match under two policies.
Every figure is taken at that pair's common horizon: a behaviour change alters
match length, and comparing a 40-minute run's endpoint to a 95-minute run's
endpoint measures the clock, not the policy.
"""
import re, glob, os, statistics, sys

FIELDS = r'mex=(\d+)/(\d+) engsurvival=(\d+)/(\d+)/(\d+)/(\d+)/(\d+)/(\d+)'

def series(path):
    return re.findall(FIELDS, open(path, errors='ignore').read())

def at(v, i):
    mex, pts, u, r, l, d, w, s = (int(x) for x in v[i])
    return dict(mex=mex, pts=pts, ref=u + r + l, unsafe=u, recent=r,
                died=d, withdrawn=w, live=s)

base = {os.path.basename(p)[len('rq-m-engsurv-'):-4]: p
        for p in glob.glob('/tmp/rq-m-engsurv-*.log') if 'smoke' not in p}
cand = {os.path.basename(p)[len('rq-m-lever1-'):-4]: p
        for p in glob.glob('/tmp/rq-m-lever1-*.log')}
cells = sorted(set(base) & set(cand))
if not cells:
    sys.exit('no paired cells')

rows = []
print(f"{'cell':<22}{'horizon':>8}{'peak b/c':>11}{'final b/c':>12}"
      f"{'retain b/c':>13}{'deaths b/c':>13}{'sites b/c':>12}")
for c in cells:
    a, b = series(base[c]), series(cand[c])
    h = min(len(a), len(b)) - 1
    A, B = at(a, h), at(b, h)
    pa = max(int(x[0]) for x in a[:h + 1]); pb = max(int(x[0]) for x in b[:h + 1])
    ra, rb = A['mex'] / pa, B['mex'] / pb
    rows.append(dict(cell=c, ra=ra, rb=rb, A=A, B=B, pa=pa, pb=pb, h=h + 1,
                     la=len(a), lb=len(b)))
    print(f"{c:<22}{h+1:>8}{pa:>5}/{pb:<5}{A['mex']:>6}/{B['mex']:<5}"
          f"{ra:>7.2f}/{rb:<5.2f}{A['died']:>6}/{B['died']:<6}"
          f"{A['died']+A['withdrawn']:>5}/{B['died']+B['withdrawn']:<6}")

def mean(f): return statistics.mean(f(r) for r in rows)
print()
print(f"cells: {len(rows)}   match-length changed in "
      f"{sum(1 for r in rows if r['la'] != r['lb'])} of {len(rows)}")
print(f"mean claim retention   baseline {mean(lambda r: r['ra']):.3f}"
      f"   lever1 {mean(lambda r: r['rb']):.3f}"
      f"   delta {mean(lambda r: r['rb']-r['ra']):+.3f}")
print(f"mean peak claim        baseline {mean(lambda r: r['pa']):.1f}"
      f"   lever1 {mean(lambda r: r['pb']):.1f}")
print(f"mean final claim       baseline {mean(lambda r: r['A']['mex']):.1f}"
      f"   lever1 {mean(lambda r: r['B']['mex']):.1f}")
print(f"mean engineer deaths   baseline {mean(lambda r: r['A']['died']):.0f}"
      f"   lever1 {mean(lambda r: r['B']['died']):.0f}")
print(f"mean exclusions written baseline {mean(lambda r: r['A']['died']+r['A']['withdrawn']):.0f}"
      f"  lever1 {mean(lambda r: r['B']['died']+r['B']['withdrawn']):.0f}")
print(f"mean total refusals    baseline {mean(lambda r: r['A']['ref']):.0f}"
      f"   lever1 {mean(lambda r: r['B']['ref']):.0f}")
print(f"mean recent-loss refus baseline {mean(lambda r: r['A']['recent']):.0f}"
      f"   lever1 {mean(lambda r: r['B']['recent']):.0f}")
better = sum(1 for r in rows if r['rb'] > r['ra'] + 1e-9)
worse = sum(1 for r in rows if r['rb'] < r['ra'] - 1e-9)
print(f"\nretention: better in {better}, worse in {worse}, unchanged in "
      f"{len(rows)-better-worse}")
