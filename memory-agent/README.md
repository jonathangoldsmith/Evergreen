# Tracker memory

A memory layer for a fitness agent: each day it turns a health snapshot and a person's taps on recommendations into short facts (numbers with their windows, never advice) and keeps them as plain Markdown files. It runs on the phone in iOS JavaScriptCore; Node is only for tests and demos.

## Run

Needs Node.js 20 or newer. Run everything from the `memory-agent/` folder.

```sh
node scripts/demo.mjs          # one sample person; or sedentary, half_marathon
node scripts/trial.mjs         # four-week trial, dry run: docs/TRIAL.md
npm install                    # once: the phone bundle tests need esbuild
npm test
node scripts/build-phone.mjs   # writes dist/phone.js
node scripts/mock-calendar.mjs # rewrites the mock calendar in fixtures/personas/
```

The phone host contract is in `docs/PHONE.md`.

## Docs

- `docs/MEMORY-LOGIC.md`: how it works
- `docs/PRODUCT-DIRECTION.md`: scope, sizes, rules
- `docs/CONTRACT.md`, `docs/STORE.md`, `docs/AMPLITUDE.md`: the three parts
- `docs/TRIAL.md`: the four-week trial
- `docs/PREFERENCE.md`: provisional
- `docs/RESEARCH.md`: what other health apps do

## Replay the full demo

From `memory-agent/`, run `node scripts/demo.mjs sedentary`. The calendar section reruns Sam's synthetic feedback and existing mock busy times through the local Memory Agent. It builds a draft before feedback, after two declines, and after forgetting one. No calendar is written. The original Amplitude section remains a dry run.

For live classification, run `node --env-file=../harness/.env scripts/demo.mjs sedentary --live-superlinked` with a local backend checkout containing the git-ignored key. Only the two fixed fictional replies go to Superlinked; calendar intervals, workout history and memory files stay local. The default path uses fixed labels and does not call Superlinked.

Amplitude stages two synthetic declines and, only if the same replay learned a preference, one preference event. Section (g) is this replay; section (e) is the old four-week reference. Both are dry runs by default. To deliver just the replay events, add `--send-amplitude` with the existing trial project’s `AMPLITUDE_API_KEY` and `AMPLITUDE_SECRET_KEY` in your local secret file or environment. The CLI checks the project can read a prior trial user before sending. No key, raw feedback, health data, or calendar times appear in analytics output.
