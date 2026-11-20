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
```

The phone host contract is in `docs/PHONE.md`.

## Docs

- `docs/MEMORY-LOGIC.md`: how it works
- `docs/PRODUCT-DIRECTION.md`: scope, sizes, rules
- `docs/CONTRACT.md`, `docs/STORE.md`, `docs/AMPLITUDE.md`: the three parts
- `docs/TRIAL.md`: the four-week trial
- `docs/PREFERENCE.md`: provisional
- `docs/RESEARCH.md`: what other health apps do
