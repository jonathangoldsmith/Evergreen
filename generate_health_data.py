#!/usr/bin/env python3
"""
Mock Apple Health (HealthKit) data generator.

Produces data shaped like a real Apple Health export, for one of several personas:
  - output/<persona>/export.xml   -> same structure as Health app > Profile > Export All Health Data
  - output/<persona>/health.json  -> the same data in a friendlier JSON shape for app/API seeding

Personas:
  moderate       Alex  - regularly active, mixed workouts ~5x/week
  half_marathon  Jordan - training for a half marathon, structured 6-day run plan
  sedentary      Sam   - out of shape, works out 1-2x/week, desk job, short sleep

Everything is synthetic. Values are correlated the way real data is
(workout days burn more energy, bad sleep lowers HRV and raises resting HR,
weight trends slowly, etc.).

Usage:
    python3 generate_health_data.py                          # all personas, 30 days
    python3 generate_health_data.py --persona half_marathon --days 90 --seed 7
"""
import argparse
import json
import math
import os
import random
from datetime import date, datetime, timedelta, timezone
from xml.sax.saxutils import quoteattr

TZ = timezone(timedelta(hours=-8))  # Pacific
TZ_STR = "-0800"

# ---------------------------------------------------------------------------
# Workout templates
#   minutes: duration range     kcalpm: active kcal/min range
#   kmpm: km per minute range   hr: avg heart rate   steps_per_km
# ---------------------------------------------------------------------------
RUN = "HKWorkoutActivityTypeRunning"
WALK = "HKWorkoutActivityTypeWalking"
DIST_RUN = "HKQuantityTypeIdentifierDistanceWalkingRunning"
DIST_BIKE = "HKQuantityTypeIdentifierDistanceCycling"

PERSONAS = {
    "moderate": {
        "description": "Regularly active adult, mixed workouts about 5x/week",
        "name": "Alex",
        "profile": {"dateOfBirth": "1991-04-12", "biologicalSex": "HKBiologicalSexFemale",
                    "bloodType": "HKBloodTypeOPositive", "fitzpatrickSkinType": "HKFitzpatrickSkinTypeIII",
                    "heightCm": 168.0},
        "goals": {"moveKcal": 550, "exerciseMin": 30, "standHours": 12, "steps": 10000},
        "baseline": {"rhr": 58, "hrv": 52, "vo2": 41.8, "weight": 66.4, "bodyFat": 0.245,
                     "weightDrift": -0.02, "vo2Drift": 0.03},
        "basal_per_hr": (56, 63),
        "sleep_h": (7.1, 7.7), "bedtime_before_midnight": ((1.0, 2.2), (0.2, 1.5)), "awake_prob": 0.35,
        "resp": 14.6, "spo2": 0.965, "breathing_disturbances": 2.1,
        "step_mean": 430, "commute_mult": 1.8, "idle_hr_offset": 14,
        "schedule": "random", "rest_prob": (0.25, 0.15), "max_consecutive": 3,
        "workout_hours": [6.25, 6.5, 7.0, 12.25, 17.5, 18.0, 18.5], "weekend_hours": (8, 11),
        "fatigue_kcal": 900,
        "workouts": {
            "run":      {"type": RUN, "w": 0.30, "minutes": (25, 55), "kcalpm": (10, 13), "dist": DIST_RUN, "kmpm": (0.16, 0.19), "indoor": False, "hr": 148, "steps_per_km": 1350, "run_metrics": True},
            "strength": {"type": "HKWorkoutActivityTypeTraditionalStrengthTraining", "w": 0.22, "minutes": (35, 60), "kcalpm": (5, 7), "indoor": True, "hr": 121},
            "cycle":    {"type": "HKWorkoutActivityTypeCycling", "w": 0.15, "minutes": (40, 90), "kcalpm": (8, 11), "dist": DIST_BIKE, "kmpm": (0.38, 0.48), "indoor": False, "hr": 140},
            "yoga":     {"type": "HKWorkoutActivityTypeYoga", "w": 0.13, "minutes": (30, 60), "kcalpm": (3, 4), "indoor": True, "hr": 98},
            "walk":     {"type": WALK, "w": 0.12, "minutes": (30, 70), "kcalpm": (4, 5.5), "dist": DIST_RUN, "kmpm": (0.09, 0.105), "indoor": False, "hr": 108, "steps_per_km": 1400},
            "hiit":     {"type": "HKWorkoutActivityTypeHighIntensityIntervalTraining", "w": 0.08, "minutes": (20, 35), "kcalpm": (11, 14), "indoor": True, "hr": 152},
        },
        "run_metrics": {"power": (190, 240), "cadence": (162, 178), "gct": (235, 275), "vosc": (7.8, 9.6)},
        "hrr_1min": (22, 38),
        "mobility": {"speed": 4.9, "step_len": 71, "double_support": 0.27, "asym": 0.02, "steadiness": 0.97},
        "walk_hr_offset": 32,
        "bp": ((108, 122), (68, 79)),
        "water": (3, 7), "caffeine_prob": 0.6, "caffeine_mg": [63, 95, 125, 150], "mindful_prob": 0.45,
        "daylight": (20, 60, 110),
    },

    "half_marathon": {
        "description": "Training for a half marathon (race 2026-12-06, goal 1:45). 6 days/week, ~45-55 km/week, weekly long run building from 13 to 19 km",
        "name": "Jordan",
        "profile": {"dateOfBirth": "1997-08-03", "biologicalSex": "HKBiologicalSexMale",
                    "bloodType": "HKBloodTypeAPositive", "fitzpatrickSkinType": "HKFitzpatrickSkinTypeII",
                    "heightCm": 178.0},
        "goals": {"moveKcal": 900, "exerciseMin": 45, "standHours": 12, "steps": 15000},
        "race": {"name": "Half Marathon", "date": "2026-12-06", "distanceKm": 21.0975, "goalTime": "1:45:00"},
        "baseline": {"rhr": 48, "hrv": 78, "vo2": 51.6, "weight": 71.2, "bodyFat": 0.135,
                     "weightDrift": -0.01, "vo2Drift": 0.05},
        "basal_per_hr": (68, 75),
        "sleep_h": (7.6, 8.4), "bedtime_before_midnight": ((1.4, 2.4), (0.8, 2.0)), "awake_prob": 0.25,
        "resp": 13.2, "spo2": 0.97, "breathing_disturbances": 1.2,
        "step_mean": 520, "commute_mult": 2.0, "idle_hr_offset": 13,
        "schedule": "half_marathon",
        "workout_hours": [6.0, 6.25, 6.5, 17.75, 18.0], "weekend_hours": (7.25, 8.5),
        "fatigue_kcal": 1500,
        "workouts": {
            "easy":      {"type": RUN, "label": "Easy run", "minutes": (35, 45), "kcalpm": (11, 12.5), "dist": DIST_RUN, "kmpm": (0.167, 0.176), "indoor": False, "hr": 139, "steps_per_km": 1250, "run_metrics": True},
            "recovery":  {"type": RUN, "label": "Recovery run", "minutes": (28, 38), "kcalpm": (10, 11.5), "dist": DIST_RUN, "kmpm": (0.160, 0.168), "indoor": False, "hr": 132, "steps_per_km": 1270, "run_metrics": True},
            "intervals": {"type": RUN, "label": "Intervals 6x800m", "minutes": (48, 56), "kcalpm": (12.5, 14), "dist": DIST_RUN, "kmpm": (0.180, 0.192), "indoor": False, "hr": 158, "max_extra": (22, 30), "steps_per_km": 1200, "run_metrics": True},
            "tempo":     {"type": RUN, "label": "Tempo run", "minutes": (45, 55), "kcalpm": (13, 14.5), "dist": DIST_RUN, "kmpm": (0.190, 0.200), "indoor": False, "hr": 161, "steps_per_km": 1210, "run_metrics": True},
            "long":      {"type": RUN, "label": "Long run", "kcalpm": (11.5, 13), "dist": DIST_RUN, "kmpm": (0.164, 0.174), "indoor": False, "hr": 146, "steps_per_km": 1260, "run_metrics": True},
            "strength":  {"type": "HKWorkoutActivityTypeFunctionalStrengthTraining", "label": "Runner strength / core", "minutes": (35, 45), "kcalpm": (6, 7.5), "indoor": True, "hr": 116},
            "yoga":      {"type": "HKWorkoutActivityTypeYoga", "label": "Mobility yoga", "minutes": (20, 35), "kcalpm": (3, 4), "indoor": True, "hr": 88},
            "cycle":     {"type": "HKWorkoutActivityTypeCycling", "label": "Easy spin (cross-train)", "minutes": (40, 60), "kcalpm": (8, 10), "dist": DIST_BIKE, "kmpm": (0.40, 0.48), "indoor": False, "hr": 128},
        },
        "run_metrics": {"power": (255, 300), "cadence": (172, 184), "gct": (215, 245), "vosc": (7.2, 8.6)},
        "hrr_1min": (32, 48),
        "mobility": {"speed": 5.3, "step_len": 78, "double_support": 0.25, "asym": 0.012, "steadiness": 0.99},
        "walk_hr_offset": 30,
        "bp": ((110, 120), (66, 76)),
        "water": (6, 10), "caffeine_prob": 0.75, "caffeine_mg": [63, 95, 125], "mindful_prob": 0.25,
        "daylight": (40, 90, 160),
    },

    "sedentary": {
        "description": "Out-of-shape adult with a desk job. Works out 1-2x/week (walks, elliptical, light weights), short sleep, low daily steps",
        "name": "Sam",
        "profile": {"dateOfBirth": "1980-02-21", "biologicalSex": "HKBiologicalSexMale",
                    "bloodType": "HKBloodTypeBPositive", "fitzpatrickSkinType": "HKFitzpatrickSkinTypeIV",
                    "heightCm": 180.0},
        "goals": {"moveKcal": 400, "exerciseMin": 30, "standHours": 12, "steps": 7500},
        "baseline": {"rhr": 73, "hrv": 26, "vo2": 30.8, "weight": 98.6, "bodyFat": 0.315,
                     "weightDrift": -0.005, "vo2Drift": 0.01},
        "basal_per_hr": (78, 85),
        "sleep_h": (5.8, 6.6), "bedtime_before_midnight": ((-0.9, 0.6), (-1.6, 0.0)), "awake_prob": 0.6,
        "resp": 16.4, "spo2": 0.951, "breathing_disturbances": 7.5,
        "step_mean": 250, "commute_mult": 1.2, "stand_rule": (300, 0.15), "idle_hr_offset": 16,
        "schedule": "sedentary", "workouts_per_week": [1, 1, 2, 2, 2],
        "workout_hours": [18.0, 18.5, 19.0, 19.5], "weekend_hours": (9.5, 12),
        "fatigue_kcal": 500,
        "workouts": {
            "walk":      {"type": WALK, "w": 0.55, "minutes": (25, 45), "kcalpm": (5, 6.2), "dist": DIST_RUN, "kmpm": (0.074, 0.085), "indoor": False, "hr": 114, "steps_per_km": 1420},
            "elliptical": {"type": "HKWorkoutActivityTypeElliptical", "w": 0.25, "minutes": (20, 32), "kcalpm": (8, 10), "indoor": True, "hr": 141},
            "strength":  {"type": "HKWorkoutActivityTypeTraditionalStrengthTraining", "w": 0.20, "minutes": (25, 40), "kcalpm": (5, 6.5), "indoor": True, "hr": 119},
        },
        "run_metrics": None,
        "hrr_1min": (13, 23),
        "mobility": {"speed": 4.5, "step_len": 70, "double_support": 0.30, "asym": 0.035, "steadiness": 0.93},
        "walk_hr_offset": 38,
        "bp": ((128, 141), (82, 91)),
        "water": (1, 4), "caffeine_prob": 0.95, "caffeine_mg": [95, 150, 190, 240], "mindful_prob": 0.05,
        "daylight": (5, 25, 60),
    },
}

P = None  # active persona
WATCH = PHONE = None
SCALE = {"sourceName": "Withings", "sourceVersion": "6.4.1", "device": None}
HEALTH_APP = {"sourceName": "Health", "sourceVersion": "26.1", "device": None}
MINDFUL_APP = {"sourceName": "Mindfulness", "sourceVersion": "11.1", "device": None}


def configure(persona: str):
    global P, WATCH, PHONE
    P = PERSONAS[persona]
    P["key"] = persona
    n = P["name"]
    WATCH = {"sourceName": f"{n}'s Apple Watch", "sourceVersion": "11.1",
             "device": "<<HKDevice: 0x600002b4c000>, name:Apple Watch, manufacturer:Apple Inc., "
                       "model:Watch, hardware:Watch7,5, software:11.1, creation date:2026-09-20 10:12:44 +0000>"}
    PHONE = {"sourceName": f"{n}'s iPhone", "sourceVersion": "26.1",
             "device": "<<HKDevice: 0x600002b4d1a0>, name:iPhone, manufacturer:Apple Inc., "
                       "model:iPhone, hardware:iPhone17,1, software:26.1, creation date:2026-09-20 10:15:02 +0000>"}


def fmt(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:%M:%S ") + TZ_STR


def iso(dt: datetime) -> str:
    return dt.isoformat()


class Store:
    def __init__(self):
        self.records = []
        self.workouts = []
        self.activity = []

    def add(self, type_, src, start, end, value, unit=None, metadata=None):
        self.records.append({
            "type": type_, "source": src, "unit": unit, "start": start, "end": end,
            "created": end + timedelta(seconds=random.randint(5, 600)),
            "value": value, "metadata": metadata or {},
        })


# ---------------- Workout planning ----------------

def weighted_pick(rng, specs):
    items = list(specs.values())
    r, acc = rng.random() * sum(s["w"] for s in items), 0
    for s in items:
        acc += s["w"]
        if r <= acc:
            return s
    return items[-1]


def plan_workout(day: date, rng, state):
    """Return (spec, km_target_or_None) or None for a rest day."""
    W = P["workouts"]
    wd = day.weekday()
    if P["schedule"] == "random":
        rest = state["consecutive_training"] >= P["max_consecutive"] or rng.random() < P["rest_prob"][1 if wd >= 5 else 0]
        return None if rest else (weighted_pick(rng, W), None)

    if P["schedule"] == "half_marathon":
        # Mon rest/yoga, Tue intervals, Wed easy, Thu tempo, Fri strength, Sat easy/recovery/spin, Sun long
        if wd == 0:
            return (W["yoga"], None) if rng.random() < 0.4 else None
        if wd == 1:
            return (W["intervals"], None)
        if wd == 2:
            return (W["easy"], None)
        if wd == 3:
            return (W["tempo"], None)
        if wd == 4:
            return (W["strength"], None)
        if wd == 5:
            r = rng.random()
            return (W["recovery"] if r < 0.55 else W["easy"] if r < 0.8 else W["cycle"], None)
        progress = (day - state["start"]).days / max(1, state["days"] - 1)
        km = 13 + 6 * progress + rng.uniform(-0.4, 0.4)
        if rng.random() < 0.12:  # skipped/shortened long run (life happens)
            km *= 0.7
        return (W["long"], round(km, 2))

    if P["schedule"] == "sedentary":
        wk = day.isocalendar()[1]
        if wk not in state["week_plan"]:
            k = rng.choice(P["workouts_per_week"])
            state["week_plan"][wk] = set(rng.sample([1, 2, 3, 5, 6], k))  # usually not Mon/Thu
        return (weighted_pick(rng, W), None) if wd in state["week_plan"][wk] else None
    raise ValueError(P["schedule"])


def build_workout(spec, km_target, day_start, weekend, rng, wake):
    kmpm = rng.uniform(*spec["kmpm"]) if spec.get("kmpm") else None
    dur = km_target / kmpm if km_target else rng.uniform(*spec["minutes"])
    if weekend:
        hour = rng.uniform(*P["weekend_hours"])
    else:
        hour = rng.choice(P["workout_hours"])
    w_start = day_start + timedelta(hours=hour, minutes=rng.randint(0, 15))
    if w_start < wake + timedelta(minutes=15):
        w_start = wake + timedelta(minutes=rng.randint(15, 30))
    w_end = w_start + timedelta(seconds=int(dur * 60))
    kcal = dur * rng.uniform(*spec["kcalpm"])
    avg_hr = spec["hr"] + rng.randint(-5, 6)
    max_extra = spec.get("max_extra", (12, 26))
    w = {
        "type": spec["type"], "label": spec.get("label"), "start": w_start, "end": w_end,
        "durationMin": round(dur, 2), "activeKcal": round(kcal, 2),
        "basalKcal": round(dur * sum(P["basal_per_hr"]) / 2 / 60, 2),
        "avgHR": avg_hr, "minHR": avg_hr - rng.randint(25, 40), "maxHR": avg_hr + rng.randint(*max_extra),
        "indoor": spec["indoor"],
    }
    if spec.get("dist"):
        km = km_target or dur * kmpm
        w["distance"] = {"type": spec["dist"], "km": round(km, 3)}
        w["paceMinPerKm"] = round(dur / km, 2) if spec["type"] in (RUN, WALK) else None
        if spec.get("steps_per_km"):
            w["steps"] = int(km * spec["steps_per_km"] * rng.uniform(0.96, 1.04))
            w["elevationAscendedM"] = round(km * rng.uniform(4, 14), 1)
        if spec["type"] == "HKWorkoutActivityTypeCycling":
            w["elevationAscendedM"] = round(rng.uniform(80, 450), 1)
    if spec.get("run_metrics") and P["run_metrics"]:
        m = P["run_metrics"]
        fast = 1 if spec["hr"] >= 155 else 0
        w["avgPowerW"] = rng.randint(*m["power"]) + fast * 15
        w["avgCadenceSpm"] = rng.randint(*m["cadence"]) + fast * 4
        w["avgGroundContactMs"] = rng.randint(*m["gct"]) - fast * 12
        w["avgVerticalOscCm"] = round(rng.uniform(*m["vosc"]), 1)
    w["routeFile"] = (f"/workout-routes/route_{w_start.strftime('%Y-%m-%d_%-I.%M%p').lower()}.gpx"
                      if spec.get("dist") and not spec["indoor"] else None)
    return w


# ---------------- Day generation ----------------

def gen_day(store: Store, day: date, state: dict, rng: random.Random):
    midnight = datetime(day.year, day.month, day.day, tzinfo=TZ)
    weekday = day.weekday()
    weekend = weekday >= 5
    B = P["baseline"]

    # ---------- Sleep (night ending this morning) ----------
    bed_rng = P["bedtime_before_midnight"][1 if weekend else 0]
    bedtime = midnight - timedelta(hours=rng.uniform(*bed_rng))
    mean_sleep = P["sleep_h"][1 if weekend else 0]
    # The night before a long run, runners go to bed earlier
    if P["schedule"] == "half_marathon" and weekday == 6:
        bedtime -= timedelta(minutes=30)
    target_sleep_h = max(4.5, min(9.8, rng.gauss(mean_sleep, 0.65)))
    sleep_quality = (target_sleep_h - P["sleep_h"][0]) / 1.5

    store.add("HKCategoryTypeIdentifierSleepAnalysis", PHONE, bedtime - timedelta(minutes=20),
              bedtime + timedelta(hours=target_sleep_h + 0.45), "HKCategoryValueSleepAnalysisInBed")
    t = bedtime + timedelta(minutes=rng.randint(6, 22))
    asleep_total = timedelta()
    stage_totals = {"Core": 0, "Deep": 0, "REM": 0, "Awake": 0}
    deep_scale = 1.15 if P["key"] == "half_marathon" else 0.8 if P["key"] == "sedentary" else 1.0
    cycle = 0
    while asleep_total < timedelta(hours=target_sleep_h):
        cycle += 1
        deep_min = max(0, rng.gauss(28 - cycle * 6, 6) * deep_scale)
        rem_min = max(5, rng.gauss(6 + cycle * 4, 4))
        core_a, core_b = rng.uniform(15, 35), rng.uniform(10, 25)
        for stage, mins in (("Core", core_a), ("Deep", deep_min), ("Core", core_b), ("REM", rem_min)):
            if mins < 2:
                continue
            seg_end = t + timedelta(minutes=mins)
            store.add("HKCategoryTypeIdentifierSleepAnalysis", WATCH, t, seg_end, f"HKCategoryValueSleepAnalysisAsleep{stage}")
            stage_totals[stage] += mins
            asleep_total += seg_end - t
            t = seg_end
        if rng.random() < P["awake_prob"]:
            aw = rng.uniform(1, 9 if P["key"] == "sedentary" else 6)
            store.add("HKCategoryTypeIdentifierSleepAnalysis", WATCH, t, t + timedelta(minutes=aw), "HKCategoryValueSleepAnalysisAwake")
            stage_totals["Awake"] += aw
            t += timedelta(minutes=aw)
    wake = t
    state["last_sleep"] = {k: round(v) for k, v in stage_totals.items()}

    # Overnight vitals
    resp = P["resp"] - 0.4 * sleep_quality
    for i in range(rng.randint(6, 10)):
        s = bedtime + timedelta(minutes=30 + i * rng.uniform(35, 50))
        if s >= wake:
            break
        store.add("HKQuantityTypeIdentifierRespiratoryRate", WATCH, s, s + timedelta(minutes=1),
                  round(resp + rng.gauss(0, 0.6), 1), "count/min")
    for i in range(rng.randint(4, 8)):
        s = bedtime + timedelta(minutes=20 + i * rng.uniform(40, 70))
        if s >= wake:
            break
        store.add("HKQuantityTypeIdentifierOxygenSaturation", WATCH, s, s,
                  round(min(1.0, rng.gauss(P["spo2"], 0.012)), 2), "%")
    store.add("HKQuantityTypeIdentifierAppleSleepingWristTemperature", WATCH, bedtime, wake,
              round(rng.gauss(35.4, 0.25), 2), "degC")
    store.add("HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances", WATCH, bedtime, wake,
              round(max(0, rng.gauss(P["breathing_disturbances"], P["breathing_disturbances"] * 0.3)), 1), "count")

    # ---------- Recovery metrics ----------
    fatigue = state["fatigue"]
    rhr = round(B["rhr"] + 2.5 * fatigue - 2.0 * sleep_quality + rng.gauss(0, 1.2))
    hrv_base = B["hrv"] * (1 - 0.12 * fatigue + 0.12 * sleep_quality)
    store.add("HKQuantityTypeIdentifierRestingHeartRate", WATCH, midnight, midnight + timedelta(hours=23, minutes=59), rhr, "count/min")
    for _ in range(rng.randint(3, 6)):
        s = midnight + timedelta(hours=rng.uniform(0, 23.5))
        hrv = max(10, rng.gauss(hrv_base, B["hrv"] * 0.15))
        store.add("HKQuantityTypeIdentifierHeartRateVariabilitySDNN", WATCH, s, s + timedelta(seconds=60), round(hrv, 3), "ms")

    # ---------- Workout ----------
    workout = None
    plan = plan_workout(day, rng, state)
    if plan:
        spec, km_target = plan
        workout = build_workout(spec, km_target, midnight, weekend, rng, wake)
        store.workouts.append(workout)
        state["consecutive_training"] += 1
        state["fatigue"] = min(1.5, state["fatigue"] + workout["activeKcal"] / P["fatigue_kcal"])
    else:
        state["consecutive_training"] = 0
    state["fatigue"] = max(-0.5, state["fatigue"] * 0.6 - 0.1)

    # ---------- Hourly activity (steps, distance, energy, flights, stand) ----------
    total_steps = total_active = total_basal = total_flights = 0
    total_dist_km = 0.0
    stand_hours = exercise_min = 0
    wake_h = (wake - midnight).total_seconds() / 3600
    bed_next_h = 23 + rng.uniform(0, 1.5) if not weekend else 24
    base_activity = rng.uniform(0.75, 1.25)
    kcal_per_step = 0.028 * B["weight"] / 66
    stride_km = P["mobility"]["step_len"] / 100000
    for h in range(24):
        hs = midnight + timedelta(hours=h)
        he = hs + timedelta(hours=1)
        awake = wake_h <= h < bed_next_h
        basal = rng.uniform(*P["basal_per_hr"])
        store.add("HKQuantityTypeIdentifierBasalEnergyBurned", WATCH, hs, he, round(basal, 3), "kcal")
        total_basal += basal
        if not awake:
            continue
        in_workout = workout and workout["start"] < he and workout["end"] > hs
        commute = h in (8, 17) and not weekend
        lunch = h == 12
        mult = base_activity * (P["commute_mult"] if commute else 1.4 if lunch else 0.55 if 9 <= h <= 16 and not weekend else 1.0)
        steps = int(max(0, rng.gauss(P["step_mean"], P["step_mean"] * 0.5) * mult))
        active = steps * kcal_per_step + rng.uniform(2, 7)
        if in_workout:
            overlap = (min(he, workout["end"]) - max(hs, workout["start"])).total_seconds() / 60
            frac = overlap / workout["durationMin"]
            steps += int(workout.get("steps", 0) * frac)
            active += workout["activeKcal"] * frac
            exercise_min += int(overlap)
        elif steps > 900:
            exercise_min += rng.randint(0, 6)
        km = steps * stride_km
        flights = rng.choice([0, 0, 0, 1, 1, 2, 3]) if steps > 300 else 0

        if steps:
            chunks = rng.randint(1, 3)
            for c in range(chunks):
                cs = hs + timedelta(minutes=c * 60 / chunks + rng.randint(0, 5))
                ce = cs + timedelta(minutes=rng.randint(4, 15))
                store.add("HKQuantityTypeIdentifierStepCount", WATCH, cs, ce, steps // chunks, "count")
                store.add("HKQuantityTypeIdentifierDistanceWalkingRunning", WATCH, cs, ce, round(km / chunks, 5), "km")
            if rng.random() < 0.6:  # iPhone logs overlapping counts too (realistic duplication)
                store.add("HKQuantityTypeIdentifierStepCount", PHONE, hs + timedelta(minutes=10),
                          hs + timedelta(minutes=20), int(steps * rng.uniform(0.5, 0.9)), "count")
        store.add("HKQuantityTypeIdentifierActiveEnergyBurned", WATCH, hs, he, round(active, 3), "kcal")
        if flights:
            store.add("HKQuantityTypeIdentifierFlightsClimbed", PHONE, hs + timedelta(minutes=5), hs + timedelta(minutes=9), flights, "count")
        thresh, p_idle = P.get("stand_rule", (380, 0.12))
        stood = (steps > thresh or rng.random() < p_idle) and stand_hours < 15
        store.add("HKCategoryTypeIdentifierAppleStandHour", WATCH, hs, he,
                  "HKCategoryValueAppleStandHourStood" if stood else "HKCategoryValueAppleStandHourIdle")
        if stood:
            stand_hours += 1
            store.add("HKQuantityTypeIdentifierAppleStandTime", WATCH, hs + timedelta(minutes=rng.randint(0, 40)),
                      hs + timedelta(minutes=rng.randint(41, 59)), rng.randint(2, 14), "min")
        total_steps += steps
        total_active += active
        total_flights += flights
        total_dist_km += km

        n = 10 if in_workout else rng.randint(7, 11)
        for i in range(n):
            s = hs + timedelta(minutes=i * 60 / n + rng.uniform(0, 3))
            if in_workout and workout["start"] <= s <= workout["end"]:
                prog = (s - workout["start"]) / (workout["end"] - workout["start"])
                bpm = workout["avgHR"] + 12 * math.sin(prog * math.pi) - 6 + rng.gauss(0, 4)
                if workout["label"] and "Intervals" in workout["label"]:
                    bpm += 10 * math.sin(prog * math.pi * 12)  # rep / recovery oscillation
                ctx = "2"
            else:
                bpm = rhr + P["idle_hr_offset"] + rng.gauss(0, 7) + (12 if commute else 0)
                ctx = "1" if rng.random() < 0.6 else "0"
            store.add("HKQuantityTypeIdentifierHeartRate", WATCH, s, s, round(bpm), "count/min",
                      metadata={"HKMetadataKeyHeartRateMotionContext": ctx})

    # ---------- Daily mobility / environment ----------
    M = P["mobility"]
    store.add("HKQuantityTypeIdentifierWalkingHeartRateAverage", WATCH, midnight, midnight + timedelta(days=1),
              round(rhr + rng.gauss(P["walk_hr_offset"], 4)), "count/min")
    for _ in range(rng.randint(2, 5)):
        s = midnight + timedelta(hours=rng.uniform(wake_h + 0.5, 21))
        e = s + timedelta(seconds=40)
        store.add("HKQuantityTypeIdentifierWalkingSpeed", PHONE, s, e, round(rng.gauss(M["speed"], 0.25), 2), "km/hr")
        store.add("HKQuantityTypeIdentifierWalkingStepLength", PHONE, s, e, round(rng.gauss(M["step_len"], 2.5), 1), "cm")
        store.add("HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", PHONE, s, e, round(rng.gauss(M["double_support"], 0.015), 3), "%")
        store.add("HKQuantityTypeIdentifierWalkingAsymmetryPercentage", PHONE, s, e, round(max(0, rng.gauss(M["asym"], 0.012)), 3), "%")
    if weekday == 6:
        store.add("HKQuantityTypeIdentifierAppleWalkingSteadiness", PHONE, midnight, midnight + timedelta(days=1),
                  round(min(1, rng.gauss(M["steadiness"], 0.01)), 3), "%")
    dl = P["daylight"]
    store.add("HKQuantityTypeIdentifierTimeInDaylight", WATCH, midnight + timedelta(hours=7), midnight + timedelta(hours=19),
              rng.randint(dl[0], dl[2] if weekend else dl[1]), "min")
    store.add("HKQuantityTypeIdentifierEnvironmentalAudioExposure", WATCH, midnight + timedelta(hours=9), midnight + timedelta(hours=18),
              round(rng.gauss(68, 5), 1), "dBASPL")
    store.add("HKQuantityTypeIdentifierHeadphoneAudioExposure", PHONE, midnight + timedelta(hours=8), midnight + timedelta(hours=8, minutes=40),
              round(rng.gauss(72, 4), 1), "dBASPL")

    # ---------- Body measurements ----------
    state["weight"] += rng.gauss(B["weightDrift"], 0.15)
    if rng.random() < (0.75 if P["key"] != "sedentary" else 0.35):
        s = wake + timedelta(minutes=rng.randint(5, 25))
        w = round(state["weight"], 1)
        bf = round(rng.gauss(B["bodyFat"], 0.006), 3)
        store.add("HKQuantityTypeIdentifierBodyMass", SCALE, s, s, w, "kg")
        store.add("HKQuantityTypeIdentifierBodyMassIndex", SCALE, s, s, round(w / (P["profile"]["heightCm"] / 100) ** 2, 1), "count")
        store.add("HKQuantityTypeIdentifierBodyFatPercentage", SCALE, s, s, bf, "%")
        store.add("HKQuantityTypeIdentifierLeanBodyMass", SCALE, s, s, round(w * (1 - bf), 1), "kg")

    # VO2 max estimate + HR recovery after outdoor runs/walks
    if workout and workout["type"] in (RUN, WALK) and not workout["indoor"]:
        state["vo2"] += rng.gauss(B["vo2Drift"], 0.15)
        store.add("HKQuantityTypeIdentifierVO2Max", WATCH, workout["end"], workout["end"], round(state["vo2"], 2), "mL/min·kg",
                  metadata={"HKVO2MaxTestType": "2"})
    if workout:
        store.add("HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", WATCH, workout["end"], workout["end"] + timedelta(minutes=1),
                  rng.randint(*P["hrr_1min"]), "count/min")

    # ---------- Nutrition / hydration / mindfulness ----------
    for _ in range(rng.randint(*P["water"])):
        s = midnight + timedelta(hours=rng.uniform(wake_h, 21))
        store.add("HKQuantityTypeIdentifierDietaryWater", HEALTH_APP, s, s, rng.choice([250, 350, 500, 750]), "mL")
    if rng.random() < P["caffeine_prob"]:
        for _ in range(1 if P["key"] != "sedentary" else rng.randint(1, 3)):
            s = midnight + timedelta(hours=rng.uniform(wake_h, 15))
            store.add("HKQuantityTypeIdentifierDietaryCaffeine", HEALTH_APP, s, s, rng.choice(P["caffeine_mg"]), "mg")
    if rng.random() < P["mindful_prob"]:
        s = midnight + timedelta(hours=rng.choice([7.25, 12.5, 21.75]))
        store.add("HKCategoryTypeIdentifierMindfulSession", MINDFUL_APP, s, s + timedelta(minutes=rng.choice([1, 3, 5, 10])), "HKCategoryValueNotApplicable")

    if weekday == 0:  # weekly manual BP reading
        s = wake + timedelta(minutes=30)
        (s_lo, s_hi), (d_lo, d_hi) = P["bp"]
        store.add("HKQuantityTypeIdentifierBloodPressureSystolic", HEALTH_APP, s, s, rng.randint(s_lo, s_hi), "mmHg")
        store.add("HKQuantityTypeIdentifierBloodPressureDiastolic", HEALTH_APP, s, s, rng.randint(d_lo, d_hi), "mmHg")

    G = P["goals"]
    store.activity.append({
        "date": day.isoformat(),
        "activeEnergyBurned": round(total_active, 3), "activeEnergyBurnedGoal": G["moveKcal"],
        "appleExerciseTime": exercise_min, "appleExerciseTimeGoal": G["exerciseMin"],
        "appleStandHours": stand_hours, "appleStandHoursGoal": G["standHours"],
        "_steps": total_steps, "_distanceKm": round(total_dist_km, 2), "_flights": total_flights,
        "_basalKcal": round(total_basal, 1), "_restingHR": rhr, "_sleep": state["last_sleep"],
    })


# ---------------- Writers ----------------

def write_xml(store: Store, path: str, export_dt: datetime):
    def attrs(d):
        return " ".join(f"{k}={quoteattr(str(v))}" for k, v in d.items() if v is not None)

    prof = P["profile"]
    with open(path, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<!DOCTYPE HealthData [\n<!-- HealthKit Export Version: 14 -->\n'
                '<!ELEMENT HealthData (ExportDate,Me,(Record|Correlation|Workout|ActivitySummary|ClinicalRecord|Audiogram|VisionPrescription)*)>\n'
                '<!-- (DTD abbreviated in this mock) -->\n]>\n')
        f.write('<HealthData locale="en_US">\n')
        f.write(f' <ExportDate value="{fmt(export_dt)}"/>\n')
        f.write(" <Me " + attrs({
            "HKCharacteristicTypeIdentifierDateOfBirth": prof["dateOfBirth"],
            "HKCharacteristicTypeIdentifierBiologicalSex": prof["biologicalSex"],
            "HKCharacteristicTypeIdentifierBloodType": prof["bloodType"],
            "HKCharacteristicTypeIdentifierFitzpatrickSkinType": prof["fitzpatrickSkinType"],
            "HKCharacteristicTypeIdentifierCardioFitnessMedicationsUse": "None",
        }) + "/>\n")
        f.write(" <Record " + attrs({
            "type": "HKQuantityTypeIdentifierHeight", "sourceName": "Health", "sourceVersion": "26.1",
            "unit": "cm", "creationDate": "2026-09-20 10:20:00 -0800", "startDate": "2026-09-20 10:20:00 -0800",
            "endDate": "2026-09-20 10:20:00 -0800", "value": prof["heightCm"]}) + "/>\n")

        for r in sorted(store.records, key=lambda r: (r["type"], r["start"])):
            a = {
                "type": r["type"], "sourceName": r["source"]["sourceName"],
                "sourceVersion": r["source"]["sourceVersion"], "device": r["source"]["device"],
                "unit": r["unit"], "creationDate": fmt(r["created"]),
                "startDate": fmt(r["start"]), "endDate": fmt(r["end"]), "value": r["value"],
            }
            if r["metadata"]:
                f.write(" <Record " + attrs(a) + ">\n")
                for k, v in r["metadata"].items():
                    f.write(f"  <MetadataEntry key={quoteattr(k)} value={quoteattr(str(v))}/>\n")
                f.write(" </Record>\n")
            else:
                f.write(" <Record " + attrs(a) + "/>\n")

        for w in store.workouts:
            f.write(" <Workout " + attrs({
                "workoutActivityType": w["type"], "duration": w["durationMin"], "durationUnit": "min",
                "sourceName": WATCH["sourceName"], "sourceVersion": WATCH["sourceVersion"], "device": WATCH["device"],
                "creationDate": fmt(w["end"] + timedelta(seconds=8)), "startDate": fmt(w["start"]), "endDate": fmt(w["end"]),
            }) + ">\n")
            f.write(f'  <MetadataEntry key="HKIndoorWorkout" value="{1 if w["indoor"] else 0}"/>\n')
            f.write('  <MetadataEntry key="HKTimeZone" value="America/Los_Angeles"/>\n')
            if "elevationAscendedM" in w:
                f.write(f'  <MetadataEntry key="HKElevationAscended" value="{int(w["elevationAscendedM"]*100)} cm"/>\n')
            if not w["indoor"]:
                f.write(f'  <MetadataEntry key="HKWeatherTemperature" value="{random.randint(44, 62)} degF"/>\n')
                f.write(f'  <MetadataEntry key="HKWeatherHumidity" value="{random.randint(45, 88)}00 %"/>\n')
            mid = w["start"] + (w["end"] - w["start"]) / 2
            f.write(f'  <WorkoutEvent type="HKWorkoutEventTypeSegment" date="{fmt(w["start"])}" duration="{w["durationMin"]/2:.4f}" durationUnit="min"/>\n')
            f.write(f'  <WorkoutEvent type="HKWorkoutEventTypePause" date="{fmt(mid)}"/>\n')
            f.write(f'  <WorkoutEvent type="HKWorkoutEventTypeResume" date="{fmt(mid + timedelta(seconds=45))}"/>\n')
            span = f'startDate="{fmt(w["start"])}" endDate="{fmt(w["end"])}"'
            f.write(f'  <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" {span} sum="{w["activeKcal"]}" unit="kcal"/>\n')
            f.write(f'  <WorkoutStatistics type="HKQuantityTypeIdentifierBasalEnergyBurned" {span} sum="{w["basalKcal"]}" unit="kcal"/>\n')
            f.write(f'  <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" {span} average="{w["avgHR"]}" minimum="{w["minHR"]}" maximum="{w["maxHR"]}" unit="count/min"/>\n')
            if "distance" in w:
                f.write(f'  <WorkoutStatistics type="{w["distance"]["type"]}" {span} sum="{w["distance"]["km"]}" unit="km"/>\n')
            if "steps" in w:
                f.write(f'  <WorkoutStatistics type="HKQuantityTypeIdentifierStepCount" {span} sum="{w["steps"]}" unit="count"/>\n')
            if "avgPowerW" in w:
                f.write(f'  <WorkoutStatistics type="HKQuantityTypeIdentifierRunningPower" {span} average="{w["avgPowerW"]}" unit="W"/>\n')
                f.write(f'  <WorkoutStatistics type="HKQuantityTypeIdentifierRunningGroundContactTime" {span} average="{w["avgGroundContactMs"]}" unit="ms"/>\n')
                f.write(f'  <WorkoutStatistics type="HKQuantityTypeIdentifierRunningVerticalOscillation" {span} average="{w["avgVerticalOscCm"]}" unit="cm"/>\n')
            if w["routeFile"]:
                f.write("  <WorkoutRoute " + attrs({
                    "sourceName": WATCH["sourceName"], "sourceVersion": WATCH["sourceVersion"], "device": WATCH["device"],
                    "creationDate": fmt(w["end"] + timedelta(seconds=20)), "startDate": fmt(w["start"]), "endDate": fmt(w["end"])}) + ">\n")
                f.write(f'   <FileReference path="{w["routeFile"]}"/>\n')
                f.write("  </WorkoutRoute>\n")
            f.write(" </Workout>\n")

        for a in store.activity:
            f.write(" <ActivitySummary " + attrs({
                "dateComponents": a["date"],
                "activeEnergyBurned": a["activeEnergyBurned"], "activeEnergyBurnedGoal": a["activeEnergyBurnedGoal"],
                "activeEnergyBurnedUnit": "kcal", "appleMoveTime": 0, "appleMoveTimeGoal": 0,
                "appleExerciseTime": a["appleExerciseTime"], "appleExerciseTimeGoal": a["appleExerciseTimeGoal"],
                "appleStandHours": a["appleStandHours"], "appleStandHoursGoal": a["appleStandHoursGoal"],
            }) + "/>\n")
        f.write("</HealthData>\n")


def write_json(store: Store, path: str, export_dt: datetime):
    def src(s):
        return {"name": s["sourceName"], "version": s["sourceVersion"],
                "device": None if not s["device"] else ("Apple Watch" if "Watch" in s["device"] else "iPhone")}

    samples = {}
    for r in sorted(store.records, key=lambda r: r["start"]):
        short = r["type"].replace("HKQuantityTypeIdentifier", "").replace("HKCategoryTypeIdentifier", "")
        short = short[0].lower() + short[1:]
        samples.setdefault(short, []).append({
            "start": iso(r["start"]), "end": iso(r["end"]), "value": r["value"], "unit": r["unit"],
            "source": src(r["source"]), **({"metadata": r["metadata"]} if r["metadata"] else {}),
        })

    prof = P["profile"]
    sex = {"HKBiologicalSexFemale": "female", "HKBiologicalSexMale": "male"}[prof["biologicalSex"]]
    blood = prof["bloodType"].replace("HKBloodType", "").replace("Positive", "+").replace("Negative", "-")
    out = {
        "exportDate": iso(export_dt),
        "persona": {"key": P["key"], "name": P["name"], "description": P["description"]},
        "profile": {
            "dateOfBirth": prof["dateOfBirth"], "biologicalSex": sex, "bloodType": blood,
            "heightCm": prof["heightCm"], "goals": P["goals"], **({"race": P["race"]} if "race" in P else {}),
        },
        "dailySummaries": [{
            "date": a["date"],
            "rings": {
                "move": {"value": round(a["activeEnergyBurned"]), "goal": a["activeEnergyBurnedGoal"], "unit": "kcal"},
                "exercise": {"value": a["appleExerciseTime"], "goal": a["appleExerciseTimeGoal"], "unit": "min"},
                "stand": {"value": a["appleStandHours"], "goal": a["appleStandHoursGoal"], "unit": "hr"},
            },
            "steps": a["_steps"], "distanceKm": a["_distanceKm"], "flightsClimbed": a["_flights"],
            "basalEnergyKcal": a["_basalKcal"], "restingHeartRate": a["_restingHR"],
            "sleepMinutes": {"core": a["_sleep"]["Core"], "deep": a["_sleep"]["Deep"],
                             "rem": a["_sleep"]["REM"], "awake": a["_sleep"]["Awake"],
                             "totalAsleep": a["_sleep"]["Core"] + a["_sleep"]["Deep"] + a["_sleep"]["REM"]},
        } for a in store.activity],
        "workouts": [{
            "activityType": w["type"].replace("HKWorkoutActivityType", ""),
            **({"label": w["label"]} if w["label"] else {}),
            "start": iso(w["start"]), "end": iso(w["end"]), "durationMin": w["durationMin"],
            "indoor": w["indoor"], "activeEnergyKcal": w["activeKcal"], "basalEnergyKcal": w["basalKcal"],
            "heartRate": {"avg": w["avgHR"], "min": w["minHR"], "max": w["maxHR"]},
            **({"distanceKm": w["distance"]["km"]} if "distance" in w else {}),
            **({"paceMinPerKm": w["paceMinPerKm"]} if w.get("paceMinPerKm") else {}),
            **({"steps": w["steps"]} if "steps" in w else {}),
            **({"elevationAscendedM": w["elevationAscendedM"]} if "elevationAscendedM" in w else {}),
            **({"running": {"avgPowerW": w["avgPowerW"], "avgCadenceSpm": w["avgCadenceSpm"],
                            "groundContactMs": w["avgGroundContactMs"], "verticalOscillationCm": w["avgVerticalOscCm"]}}
               if "avgPowerW" in w else {}),
            "routeFile": w["routeFile"], "source": src(WATCH),
        } for w in store.workouts],
        "samples": samples,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)


def generate(persona: str, days: int, seed: int, end: date, out_root: str):
    configure(persona)
    rng = random.Random(seed)
    random.seed(seed)
    start = end - timedelta(days=days - 1)
    B = P["baseline"]
    state = {"fatigue": 0.0, "consecutive_training": 0, "weight": B["weight"], "vo2": B["vo2"],
             "last_sleep": {}, "week_plan": {}, "start": start, "days": days}
    store = Store()
    d = start
    while d <= end:
        gen_day(store, d, state, rng)
        d += timedelta(days=1)

    out = os.path.join(out_root, persona)
    os.makedirs(out, exist_ok=True)
    export_dt = datetime(end.year, end.month, end.day, 7, 30, tzinfo=TZ) + timedelta(days=1)
    write_xml(store, os.path.join(out, "export.xml"), export_dt)
    write_json(store, os.path.join(out, "health.json"), export_dt)
    types = {r["type"] for r in store.records}
    print(f"{persona:14} {P['name']:7} {days} days | {len(store.records):,} records | "
          f"{len(store.workouts)} workouts | {len(types)} record types -> {out}/")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--persona", default="all", choices=["all", *PERSONAS])
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--end", default="2026-11-17", help="last day of data (YYYY-MM-DD)")
    ap.add_argument("--out", default="output")
    args = ap.parse_args()
    end = date.fromisoformat(args.end)
    for p in (PERSONAS if args.persona == "all" else [args.persona]):
        generate(p, args.days, args.seed, end, args.out)


if __name__ == "__main__":
    main()
