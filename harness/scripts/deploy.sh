#!/bin/sh
# Deploy to production, then the deploy check (range plan task T1): the deploy counts only
# if scripts/smoke.py passes, which needs SingleStore on. Run from harness/.
set -e
cd "$(dirname "$0")/.."
npx vercel deploy --prod --yes
uv run python scripts/smoke.py "${1:-https://trackerplusplus-harness.vercel.app}"
