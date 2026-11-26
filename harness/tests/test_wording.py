"""Wellness wording (business notes BN3, range plan B3): no "safe", "prevent",
"risk" or "injury-proof" on the coach page, in the planner's reasons or in the
shoe pick's reasons, including what a model writes."""
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.index import app
from harness import coach, wording
from harness.clients import sie
from harness.recommend import shoes
from harness.recommend import workouts as W
from tests.test_coach import PAIN, WEEK, choice, db, events, flag, page, share  # noqa: F401  (db is a fixture)
from tests.test_workouts import req


@pytest.mark.parametrize("text", [
    "Keeps you safe on race week.", "Safely builds miles.", "Helps prevent injury.", "Lowers your risk.",
    "An injury-proof plan.", "Prevention first.", "Risky jump.", "SAFER this way.",
])
def test_the_banned_words_are_caught(text):
    assert wording.claims_safety(text)


@pytest.mark.parametrize("text", [
    "In range 5 of 6 days.", "18 km is a big jump from your longest run this month.", "Shortened: big jump.",
    "Worn foam cushions less.", "Your race is 9 days out.",
])
def test_wellness_wording_passes(text):
    assert not wording.claims_safety(text)


def test_coach_pages_make_no_safety_claim(db):
    events(flag(), choice(), flag("swap-bbbbbbbbbbbb", "sore"), choice("swap-bbbbbbbbbbbb", kind="sore"),
           flag("swap-cccccccccccc", "returnSpike", injury=True), choice("swap-cccccccccccc", kind="returnSpike"),
           PAIN, WEEK)
    pages = [page(share()["token"]).text, page(share(feelings=True)["token"]).text, page("not-a-token").text,
             coach.render("Sam", False, [])]
    for html in pages:
        assert not wording.claims_safety(html), html


def test_workout_idea_titles_and_whens_make_no_safety_claim():
    # Quotes are a cited source's own words and stay as written; titles and
    # "when" lines are Evergreen's, and the app shows them.
    ideas = json.loads((Path(W.__file__).parents[1] / "data/workout_ideas/running.json").read_text())
    shown = [i.get(k, "") for i in (ideas if isinstance(ideas, list) else ideas["ideas"]) for k in ("title", "when")]
    assert shown and not [t for t in shown if wording.claims_safety(t)]


def test_a_planner_reason_with_a_safety_claim_falls_back_to_fixed_wording(monkeypatch):
    monkeypatch.setattr(sie, "chat_json", lambda *a, **k: {"reason": "Keeps you safe before race day."})
    r = TestClient(app).post("/workouts/recommend", json=req().model_dump(mode="json")).json()
    assert r["source"] == "rules"
    assert not [a for a in r["actions"] if wording.claims_safety(a["reason"])]


def test_the_prompts_carry_the_rule(monkeypatch):
    prompts = []
    monkeypatch.setattr(sie, "chat_json", lambda prompt, *a, **k: prompts.append(prompt) or {"reason": "Your usual run."})
    TestClient(app).post("/workouts/recommend", json=req().model_dump(mode="json"))
    assert prompts and all(wording.RULE in p for p in prompts)


def test_a_shoe_reason_with_a_safety_claim_is_rejected():
    elig = [{"id": "a"}, {"id": "b"}]
    with pytest.raises(ValueError):
        shoes._guard({"chosenId": "a", "whyChosen": "The safest pick for your long runs.",
                      "lost": [{"id": "b", "lostBecause": "pricier"}]}, elig)
    with pytest.raises(ValueError):
        shoes._guard({"chosenId": "a", "whyChosen": "Cushioned for your long runs.",
                      "lost": [{"id": "b", "lostBecause": "higher injury risk"}]}, elig)
