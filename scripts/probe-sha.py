#!/usr/bin/env python3
# probe-sha.py — byte-identity gate for the hybrid campaign.
# Runs the prompt suite through a llama-server at temp 0, fixed seed, cache_prompt:false,
# prints sha256 per prompt. Run it twice (e.g. PLE-cold vs PLE-warm server states); the two
# shas must match for tiering changes. Weights-identical gate only — never used to compare
# different quants.
# usage: probe-sha.py PORT [prompts.jsonl] [n_predict]
import hashlib, json, sys, urllib.request

port = sys.argv[1]
prompts_file = sys.argv[2] if len(sys.argv) > 2 else "scripts/bench-prompts.jsonl"
n_predict = int(sys.argv[3]) if len(sys.argv) > 3 else 200

prompts = []
for line in open(prompts_file):
    line = line.strip()
    if line: prompts.append(json.loads(line)["prompt"])

def completion(prompt):
    body = json.dumps({"prompt": prompt, "n_predict": n_predict,
                       "temperature": 0, "seed": 42, "cache_prompt": False})
    req = urllib.request.Request(f"http://127.0.0.1:{port}/completion",
                                 data=body.encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.loads(r.read())["content"]

ok = True
for i, p in enumerate(prompts):
    out = completion(p)
    h = hashlib.sha256(out.encode()).hexdigest()[:16]
    print(f"probe{i} {h}  {out[:60].strip()!r}")
print("SUITE_DONE")
