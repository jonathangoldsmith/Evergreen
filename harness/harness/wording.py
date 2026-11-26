"""Wellness wording (business notes BN3, range plan B3).

Evergreen says what it changed and why ("in range", "a big jump from your
longest run", "shortened"), never that it makes running safe. Fixed strings are
checked by tests; text a model writes in Evergreen's voice is checked here and
falls back to the fixed wording when it slips.
"""
import re

BANNED = re.compile(r"\b(safe(?:ly|r|st|ty)?|unsafe|prevent\w*|risk\w*|injury[- ]?proof)\b", re.IGNORECASE)

# Added to every prompt whose answer the app shows in Evergreen's voice.
RULE = ("Say what the plan does and why, using the numbers given. Never say safe, prevent, risk or injury-proof, "
        "and never claim it lowers injury.")


def claims_safety(text: str) -> bool:
    """True when the text uses a word BN3 rules out."""
    return bool(BANNED.search(text))
