"""Guardrail events from the phone (plan item 9, eng review D1).

One route takes every uploaded event: flags, choices, morning answers, weekly pain
answers with their OSTRC codes, the injury answer, backtest answers, week counts,
consent and completed workouts. Each type is a strict model: an unknown field is
refused, so a pain location or a calendar title can never be stored by mistake.
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Annotated, Literal, Optional, Union

from pydantic import BaseModel, ConfigDict, Field


class _Event(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_.:-]+$")
    at: datetime


class FlagEvent(_Event):
    type: Literal["flag"]
    kind: Literal["spike", "returnSpike", "sore", "tired"]
    unit: Literal["km", "minutes"]
    planned: float = Field(ge=0, le=1000)
    suggested: float = Field(ge=0, le=1000)
    longest30: Optional[float] = Field(default=None, ge=0, le=1000)
    injuryAdjusted: bool = False
    runDay: date


class ChoiceEvent(_Event):
    type: Literal["choice"]
    choice: Literal["accept", "keep", "undo"]
    kind: Literal["spike", "returnSpike", "sore", "tired"]
    run: str = Field(pattern=r"^swap-[0-9a-f]{12}$")   # the run's hashed key, never its title
    runDay: date


class CheckInEvent(_Event):
    type: Literal["check_in"]
    answer: Literal["fresh", "tired", "sore"]
    runDay: date


class PainEvent(_Event):
    type: Literal["pain"]
    answer: Literal["no", "aLittle", "yes", "noAnswer"]
    ostrc: Optional[list[Annotated[int, Field(ge=0, le=4)]]] = Field(default=None, min_length=4, max_length=4)
    weekStart: date


class InjuryEvent(_Event):
    type: Literal["injury"]
    injured: bool
    monthsAgo: Optional[int] = Field(default=None, ge=0, le=12)


class BacktestAnswerEvent(_Event):
    type: Literal["backtest_answer"]
    answer: Literal["yes", "no", "dontKnow"]
    flagged: bool
    jumpPercent: int = Field(ge=-100, le=1000, multiple_of=5)
    monthsAgo: int = Field(ge=0, le=13)


class RangeWeekEvent(_Event):
    type: Literal["range_week"]
    weekStart: date
    daysCounted: int = Field(ge=0, le=7)
    daysInRange: int = Field(ge=0, le=7)
    swaps: int = Field(ge=0, le=50)
    comebacks: int = Field(ge=0, le=50)


class ConsentEvent(_Event):
    type: Literal["consent"]
    uploads: Literal[True]          # a "no" never leaves the phone
    research: bool
    version: int = Field(ge=1)


class WorkoutCompletedEvent(_Event):
    type: Literal["workout_completed"]
    activityType: str = Field(max_length=40)
    minutes: int = Field(ge=0, le=1440)


Event = Annotated[Union[FlagEvent, ChoiceEvent, CheckInEvent, PainEvent, InjuryEvent, BacktestAnswerEvent,
                        RangeWeekEvent, ConsentEvent, WorkoutCompletedEvent], Field(discriminator="type")]

# The one type that updates in place (eng re-run outside voice #2): a week's counts
# change until Tuesday night, so the newest upload wins.
UPSERT_TYPES = {"range_week"}


class EventsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    events: list[Event] = Field(min_length=1, max_length=500)
