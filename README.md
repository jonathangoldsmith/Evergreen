# Tracker++
Tracker++ to improve fitness and health

## How recommendations work

![TrackerPlusPlus recommendation system](docs/figures/recommendation-system.png)

The iPhone app is the agent's hands: it keeps the person's memory, puts workouts on their calendar and asks before buying anything. A stateless backend (the harness, in `harness/` once [#13](https://github.com/jonathangoldsmith/TrackerPlusPlus/pull/13) lands) is the brain for two recommendations:

- **Shoes:** wear is measured from real run distances. Candidates come from expert reviews found on the web (Nimble) and stored in SingleStore. Code applies the hard rules (fit notes, cushioning for long runs, arrival before the race, the spending mandate). Superlinked SIE ranks the shortlist and a small open model picks one and explains why the others lost, with citations from Senso and the review page.
- **Workouts:** the next 7 days are built from the person's usual week and their memory (fixed slots, load, sleep and resting heart rate), adjusted by code for the training-load cap, readiness, worn shoes, break-in runs, a race taper and calendar conflicts. The model only writes the reasons. Optional extras from expert guidance are suggested, never booked.

Every recommendation answers within a 5 s budget, falls back to a deterministic answer if a model or service is slow, and is logged to SingleStore as an audit record.
