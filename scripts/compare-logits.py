#!/usr/bin/env python3
# compare-logits.py — KL / top-k agreement between two logits-dump outputs.
# usage: compare-logits.py REF.bin CAND.bin [--label hybrid]
# Emits per-prompt mean KL(ref||cand), top-1/top-5 agreement, and p99 worst position.
# NOTE: bins written by logits-dump.cpp before its top-k heap fix hold token ids 0-255
# plus the argmax, not the true top-256; for those bins only top-1 agreement is valid
# (KL, top-5 and p99 are not).
import struct, sys, math, collections

def load(path):
    """returns {(prompt,pos): (tail_lse, [(idx, logit)])}"""
    f = open(path, 'rb'); out = {}
    while True:
        hdr = f.read(16)
        if not hdr: break
        if len(hdr) < 16: raise IOError('truncated header')
        pi, k, = struct.unpack('<II', hdr[:8])
        lse, kk = struct.unpack('<fI', hdr[8:])
        items = [struct.unpack('<if', f.read(8)) for _ in range(kk)]
        out[(pi, k)] = (lse, items)
    f.close(); return out

def softmax_map(entry):
    lse, items = entry
    mx = max((l for _, l in items), default=0.0)
    m = {i: math.exp(l - mx) for i, l in items}
    tail = math.exp(lse - mx) - sum(m.values())
    m['__tail__'] = max(tail, 0.0)
    return m, mx

ref = load(sys.argv[1]); cand = load(sys.argv[2])
label = sys.argv[sys.argv.index('--label') + 1] if '--label' in sys.argv else 'cand'

per_prompt = collections.defaultdict(list)
worst = []
for key in sorted(ref.keys()):
    if key not in cand:
        print(f'  missing position {key} in candidate'); continue
    pr, mxr = softmax_map(ref[key]); pc, mxc = softmax_map(cand[key])
    # align scales: renormalize with common offset mx = max(mxr, mxc)
    mx = max(mxr, mxc)
    pr = {k: v * math.exp(mxr - mx) for k, v in pr.items()}
    pc = {k: v * math.exp(mxc - mx) for k, v in pc.items()}
    Zr = sum(pr.values()); Zc = sum(pc.values())
    pr = {k: v / Zr for k, v in pr.items()}; pc = {k: v / Zc for k, v in pc.items()}
    kl = 0.0
    for k, p in pr.items():
        q = pc.get(k, 0.0)
        if p > 0 and q > 0: kl += p * math.log(p / q)
        elif p > 0: kl += p * 12.0  # missing mass penalty (log p/eps)
    pi, pos = key
    per_prompt[pi].append(kl)
    # top-1 agreement: argmax over stored top sets
    t1r = max(ref[key][1], key=lambda x: x[1])[0] if ref[key][1] else -1
    t1c = max(cand[key][1], key=lambda x: x[1])[0] if cand[key][1] else -2
    worst.append((kl, pi, pos, t1r == t1c))

mean_kl = [sum(v) / len(v) for v in per_prompt.values()]
agree = sum(1 for _, _, _, ok in worst if ok) / len(worst)
top5 = []
for key in ref.keys():
    if key not in cand: continue
    r5 = {i for i, _ in sorted(ref[key][1], key=lambda x: -x[1])[:5]}
    c5 = {i for i, _ in sorted(cand[key][1], key=lambda x: -x[1])[:5]}
    top5.append(len(r5 & c5) / 5.0)
worst.sort()
p99 = worst[int(len(worst) * 0.99)] if worst else (0, 0, 0, False)

print(f'=== {label} vs reference ===')
print(f'positions compared: {len(worst)}')
print(f'mean KL(ref||{label}): {sum(mean_kl)/len(mean_kl):.4f}   per-prompt: {["%.4f" % m for m in mean_kl]}')
print(f'top-1 agreement:      {agree*100:.2f}%')
print(f'top-5 agreement:      {sum(top5)/len(top5)*100:.2f}%')
print(f'p99 worst KL:         {p99[0]:.4f} (prompt {p99[1]}, pos {p99[2]}, top1_match={p99[3]})')
