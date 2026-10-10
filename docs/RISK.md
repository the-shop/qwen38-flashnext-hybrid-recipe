# Risk and compliance

## Gating — options considered

**Outcome:** published ungated, with the `not-for-all-audiences` tag.

None of these is access control for a 101 GB file. A gated repo is one re-upload away from an
ungated mirror. What they differ on is friction, signalling, and whether we take on a
personal-data list.

| option | who gets files | what we learn | obligations | reversible |
|---|---|---|---|---|
| **ungated** (parent's choice) | anyone, anonymously | nothing | none | yes, but pulled copies stay pulled |
| **not-for-all-audiences** | identical — adds interstitial, drops out of default search | nothing | none | fully, instantly, no residue |
| **gated-auto** | anyone with an account, one click | username, email, timestamp, custom fields | **data-controller duties**: lawful basis, privacy notice, retention policy, access/erasure requests, breach duty, discovery surface | gate flips off; records persist until actively deleted |
| **gated-manual** | only those we approve | same, plus justification | all of the above, plus an indefinite review queue, plus an implicit claim we vetted people | same |

Gating buys a paper trail, not control. Manual gating additionally buys a maintenance burden
and an implied endorsement — "we approved them" reads worse after an incident than "it was open".

**One factor that differs from the parent's situation:** most abliterated releases go out under
pseudonyms; this one is published under a company name, so it stays durably associated with it.

## Licence — Qwen Community 1.0

Ship the **upstream HF LICENSE (3235 bytes)**. Our local 3220-byte copy is text-identical; line endings differ (CRLF upstream).

**Fine, no separate licence:** redistribution with LICENSE verbatim · internal commercial use that
gives no third party access to the model, its outputs or its capabilities · fine-tunes and
derivatives · research and evaluation · a collaborator running it on their own hardware for their
own work.

**Clause 1 applies to everyone downstream:** a commercial product or service with more than 100M
monthly active users or more than US$20M monthly revenue must prominently display the model name.

**Needs a separate Qwen licence, obtained before the use starts:** commercial hosted
inference or fine-tuning API · shipping it as the engine of a commercial AI work assistant.

**Genuinely ambiguous — Qwen has published nothing, so these go to Qwen, not to assumption:**
inference as a feature of a larger paid product · a free tier funded elsewhere in the business ·
a consultancy running it for a named client · clause 2's reach over distant derivatives.

### What a collaborator must be told, in writing, before building

1. Licence is **Qwen Community 1.0, not Apache-2.0.** The apache claim on
   `orcarouter/Qwen3.8-Flash-Next-Uncensored` is a different lineage. This is the most likely
   expensive mistake.
2. Clause 2 is **theirs** to clear with Qwen. the-shop cannot sublicence it.
3. the-shop takes no position on their specific use and is not giving legal advice.
4. The model is decensored. The 0/100 refusals figure is trohrbaugh's; we ran no safety evaluation.
5. Do not plan capacity off any throughput number we have published.

## What publication makes permanent

Every download completed before any takedown · mirrors on ModelScope, CDNs, torrents ·
downstream requants and fine-tunes that cite us in their lineage · the card text in HF exports
and archival crawls.

Deleting the repo stops new downloads **from us** and nothing else. It is also a visible event
that tends to draw more attention than quiet maintenance. **The only moment of real control is
before the first upload completes.**

## Mitigations, in order of effect

1. An honest, specific card — the largest lever, for both HF moderation and for how a critical
   write-up reads.
2. The `not-for-all-audiences` tag — removes casual discovery at near-zero cost.
3. An explicit intended-use / out-of-scope section.
4. A working abuse-report contact.
5. Lineage framing in the first line — "requantization of trohrbaugh's abliteration", not buried.

Note the nuance that trohrbaugh did the decensoring **will not survive contact with a social
media post**. Plan on that.

## Disclosure minimum

1. Decensored, with 0/100 refusals and KL 0.1160 attributed to **trohrbaugh**, plus an explicit
   "the-shop ran no safety evaluation".
2. MTP draft head is byte-identical to the **base**-model head, not modified by Heretic.
3. Unvalidated surface: no 64K–128K needles, no agentic/SWE rounds, no uncensored suite, plus the
   llama.cpp #28805 decode-EOS observation.
4. The throughput delta is **retracted**; no like-for-like QSA comparison against the UD-Q4_K_XL baseline exists.
5. Exactness is vs a q8_0 reference from a lossy F16 re-encode — two removes from BF16. Name the
   KV type on both sides. Never quote 94.62% against the 89.5% anchor.
6. Qwen Community 1.0 verbatim, clause 2 named, full lineage including closed PR #27739.
7. Tie every provenance statement to its evidence (parent by sha256, mirror by the download
   script and log), and mark anything unevidenced as unresolved — that is what makes the rest credible.
