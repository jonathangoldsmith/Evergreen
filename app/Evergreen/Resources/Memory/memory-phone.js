(() => {
  // src/store/paths.mjs
  var isAbsolute = (p) => typeof p === "string" && p.startsWith("/");
  function join(...parts) {
    const joined = parts.filter((x) => x !== "").join("/").replace(/\/{2,}/g, "/");
    return joined.length > 1 && joined.endsWith("/") ? joined.slice(0, -1) : joined;
  }
  function dirname(p) {
    const i = p.lastIndexOf("/");
    return i <= 0 ? "/" : p.slice(0, i);
  }
  function basename(p) {
    return p.slice(p.lastIndexOf("/") + 1);
  }

  // src/contract/facts.mjs
  function sentencesOf(text) {
    const t2 = String(text);
    const parts = [];
    let start = 0;
    for (let i = 0; i < t2.length; i++) {
      const c = t2[i];
      if (c !== "." && c !== "!" && c !== "?") continue;
      const decimal = i > 0 && i < t2.length - 1 && t2[i - 1] >= "0" && t2[i - 1] <= "9" && t2[i + 1] >= "0" && t2[i + 1] <= "9";
      if (decimal) continue;
      parts.push(t2.slice(start, i));
      start = i + 1;
    }
    parts.push(t2.slice(start));
    return parts.map((s) => s.trim()).filter(Boolean);
  }
  function sentenceProblems(text) {
    const out = [];
    if (typeof text !== "string" || !text.trim()) return ["text must be a non-empty string"];
    if (/[\r\n]/.test(text)) out.push("text must be a single line");
    if (!text.endsWith(".")) out.push("text must end with a period");
    const parts = sentencesOf(text);
    if (parts.length > 1) out.push("text must be one sentence");
    for (const part of parts) if (!/\d/.test(part)) out.push("a sentence has no number");
    if (/[!?]/.test(text)) out.push("text must not contain ! or ?");
    if (!/\d/.test(text)) out.push("text must contain a number");
    return out;
  }

  // src/facts/constants.mjs
  var MIN_WORKOUT_MINUTES = 10;
  var THIN_DAYS_NEEDED = 14;
  var SPIKE_RATIO = 2;
  var MIN_BODY_READINGS = 3;
  var ACTIVITY_ALLOWLIST = [
    "Running",
    "Walking",
    "Cycling",
    "Hiking",
    "Swimming",
    "Rowing",
    "Elliptical",
    "StairClimbing",
    "Yoga",
    "Pilates",
    "Dance",
    "CoreTraining",
    "Flexibility",
    "MixedCardio",
    "FunctionalStrengthTraining",
    "TraditionalStrengthTraining",
    "HighIntensityIntervalTraining",
    "Boxing",
    "Tennis",
    "Soccer",
    "Basketball",
    "Golf",
    "Skiing",
    "Climbing",
    "Other"
  ];
  function activityName(activity) {
    let out = "";
    for (let i = 0; i < activity.length; i++) {
      const upper = activity[i] >= "A" && activity[i] <= "Z";
      const prevUpper = i > 0 && activity[i - 1] >= "A" && activity[i - 1] <= "Z";
      out += (i > 0 && upper && !prevUpper ? " " : "") + activity[i];
    }
    return out.toLowerCase();
  }
  var MIN_BASELINE_DAYS = 7;
  var SHORT_LABELS = { TraditionalStrengthTraining: "strength training", FunctionalStrengthTraining: "strength training" };
  var ACTIVITY_LABELS_ALL = [.../* @__PURE__ */ new Set([...ACTIVITY_ALLOWLIST.map(activityName), ...Object.values(SHORT_LABELS)])];
  function activityLabels(types) {
    const short = (t2) => SHORT_LABELS[t2] ?? activityName(t2);
    const count = {};
    for (const t2 of types) count[short(t2)] = (count[short(t2)] || 0) + 1;
    return Object.fromEntries(types.map((t2) => [t2, count[short(t2)] > 1 ? activityName(t2) : short(t2)]));
  }

  // src/facts/lint.mjs
  var BANNED_WORDS = [
    "you",
    "your",
    "yours",
    "yourself",
    "should",
    "shouldn't",
    "shall",
    "must",
    "ought",
    "try",
    "trying",
    "rest",
    "great",
    "good",
    "bad",
    "better",
    "worse",
    "excellent",
    "amazing",
    "awesome",
    "impressive",
    "lazy",
    "healthy",
    "unhealthy",
    "ready",
    "recovered",
    "recover",
    "recovery",
    "overreaching",
    "overtraining",
    "overtrained",
    "consider",
    "recommend",
    "recommended",
    "avoid",
    "careful",
    "risk",
    "risky",
    "injury",
    "lot",
    "lots",
    "plenty",
    "insufficient",
    "excessive",
    "pushing",
    "improve",
    "improving",
    "improved",
    "declining",
    "worry",
    "concern",
    "concerning",
    "fine",
    "normal",
    "abnormal",
    "will",
    "would",
    "likely",
    "probably",
    "might",
    "could",
    "expect",
    "expected",
    "predict",
    "forecast",
    "projected"
  ];
  var SECOND_PERSON_WORDS = ["you", "your", "yours", "yourself"];
  var MODAL_WORDS = ["should", "shouldn't", "shall", "must", "ought", "could", "would", "might", "will"];
  var MODAL_PHRASES = ["need to", "needs to"];
  var BANNED_PHRASES = [
    "a lot",
    "too much",
    "too many",
    "too little",
    "too few",
    "need to",
    "needs to",
    "going to",
    "on track",
    "keep it up",
    "well done",
    "good job",
    "next week",
    "tomorrow",
    "you should",
    "let's",
    "be sure",
    "make sure",
    "take a",
    "in the future"
  ];
  var IMPERATIVE_STARTS = [
    "take",
    "do",
    "don't",
    "try",
    "rest",
    "stretch",
    "aim",
    "make",
    "keep",
    "get",
    "go",
    "add",
    "drink",
    "eat",
    "sleep",
    "run",
    "walk",
    "stay",
    "avoid",
    "increase",
    "reduce",
    "decrease",
    "consider",
    "remember",
    "focus",
    "start",
    "stop",
    "plan",
    "schedule",
    "use",
    "let",
    "please",
    "be",
    "push",
    "limit",
    "skip",
    "continue",
    "maintain",
    "build",
    "set",
    "give"
  ];
  var esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  var wordRe = (w) => new RegExp(`(^|[^A-Za-z'])${esc(w)}(?![A-Za-z'])`, "i");
  var WORD_RES = BANNED_WORDS.map((w) => [w, wordRe(w)]);
  var PHRASE_RES = BANNED_PHRASES.map((p) => [p, wordRe(p)]);
  var wordCategory = (w) => SECOND_PERSON_WORDS.includes(w) ? "second person" : MODAL_WORDS.includes(w) ? "modal verb" : "banned word";
  var phraseCategory = (p) => MODAL_PHRASES.includes(p) ? "modal verb" : "banned phrase";
  var N = String.raw`\d+(?:\.\d+)?`;
  var D = String.raw`\d{4}-\d{2}-\d{2}`;
  var ACT = `(?:${ACTIVITY_LABELS_ALL.join("|")})`;
  var CMP = (unit) => String.raw`(?:equal to|(?:less than )?${N} ${unit} (?:above|below))`;
  var PCTP = String.raw`(?:equal|(?:less than )?${N}% (?:above|below))`;
  var RATIO = String.raw`(?:0|less than 0\.01|${N})`;
  var t = (src) => new RegExp(`^${src}$`);
  var WD = "(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat)";
  var FACT_TEMPLATES = {
    "history.thin": [t(String.raw`\d+ days? of data; fewer than 14\.`)],
    "coverage.28d": [t(String.raw`Data was logged on \d+ of the last 28 days, so the 28-day load average uses \d+ days?\.`)],
    "volume.today": [t(String.raw`On ${D}: \d+ counted workouts? \(10 minutes or more\) and ${N} workout minutes(?:, \d+ under 10 minutes not counted)?\.`)],
    "volume.today_so_far": [t(String.raw`So far today \(${D}\): \d+ counted workouts? \(10 minutes or more\) and ${N} workout minutes, day not finished(?:, \d+ under 10 minutes not counted)?\.`)],
    "volume.today_unlogged": [t(String.raw`${D} has no data: 0 of 1 days logged\.`), t(String.raw`${D} has no data so far: 0 of 1 days logged\.`)],
    "volume.week": [t(String.raw`Counted in the last 7 days \(${D} to ${D}; workouts of 10 minutes or more\): \d+ workouts? and ${N} workout minutes on \d+ logged days? \(\d+ unlogged days?\)(?:, \d+ under 10 minutes not counted)?\.`)],
    "volume.28d": [t(String.raw`Counted in the last 28 days \(${D} to ${D}; workouts of 10 minutes or more\): \d+ workouts? and ${N} workout minutes on \d+ logged days? \(\d+ unlogged days?\)(?:, \d+ under 10 minutes not counted)?\.`)],
    "past.week_comparisons_skipped": [t(String.raw`Comparisons of the last 7 days with earlier weeks or a target are not stated: only \d+ of 7 days are logged\.`)],
    "past.today_vs_avg": [
      t(String.raw`${N} workout minutes on ${D}, ratio ${RATIO} to the daily average of ${N} minutes over the previous 28 days \(\d+ logged days?(?:, ${PCTP})?\)\.`),
      t(String.raw`${N} workout minutes on ${D}; the daily average over the previous 28 days is ${N} minutes \(ratio 0, \d+ logged days?\)\.`),
      t(String.raw`${N} workout minutes on ${D}; the daily average over the previous 28 days is ${N} minutes, so the ratio is not defined \(\d+ logged days?\)\.`)
    ],
    "past.today_vs_highest": [t(String.raw`The workout minutes on ${D} \(${N}\) are ${N}x the highest recorded day of the previous 28 days \(${N}\)\.`)],
    "past.today_rank": [t(String.raw`The workout minutes on ${D} \(${N}\) rank \d+ of \d+ logged days? in the last 28 days, where 1 is the highest\.`)],
    "past.week_vs_avg": [
      t(String.raw`${N} workout minutes in the last 7 days, ratio ${RATIO} to the 4-week average of ${N} minutes per week \(\d+ logged days? before this week(?:, ${PCTP})?\)\.`),
      t(String.raw`${N} workout minutes in the last 7 days; the 4-week average is ${N} minutes per week \(ratio 0, \d+ logged days? before this week\)\.`),
      t(String.raw`${N} workout minutes in the last 7 days; the 4-week average is ${N} minutes per week, so the ratio is not defined \(\d+ logged days? before this week\)\.`)
    ],
    "past.week_rank": [t(String.raw`This week's workout minutes \(${N}\) rank \d+ of \d+ complete 7-day weeks? in the last 12 weeks, where 1 is the highest\.`)],
    "load.ratio": [
      t(String.raw`The minutes-based 7-day load is ${N} minutes, ratio ${RATIO} to the 28-day weekly average of ${N} minutes \(\d+ logged days?(?:, ${PCTP})?\)\.`),
      t(String.raw`The effort-weighted 7-day load is ${N} effort-minutes, ratio ${RATIO} to the 28-day weekly average of ${N} effort-minutes \(\d+ logged days?(?:, ${PCTP})?\)\.`)
    ],
    "regularity.days_since_last": [
      t(String.raw`Days since the last counted workout \(10 minutes or more\) as of ${D}: \d+ \(${D}\); \d+ counted workouts? in the last 28 days\.`),
      t(String.raw`No counted workout in the last 28 days as of ${D}: 0 workouts\.`)
    ],
    "regularity.longest_gap": [t(String.raw`Longest stretch of logged days without a counted workout \(10 minutes or more\) in the last \d+ days: \d+ days? \(\d+ unlogged days? in the window\)\.`)],
    "regularity.per_week": [t(String.raw`Counted workouts \(10 minutes or more\) in each of the last \d+ weeks \(7-day blocks, most recent first\): \d+(?:, \d+)*; logged days in those weeks: \d+(?:, \d+)*\.`)],
    "regularity.slot": [t(String.raw`Fixed slot among recognised activities: ${ACT} on ${WD} between (?:\d{2}:00 and \d{2}:00|23:00 and 00:00 the next day), in \d+ of the last 4 weeks\.`)],
    "regularity.slots_none": [t(String.raw`Fixed slots among recognised activities \(same activity, weekday and hour in 3 of the last 4 weeks\) found: 0\.`)],
    "mix.count": [
      t(String.raw`Counted workouts \(10 minutes or more\) by activity in the last 28 days: ${ACT} \d+(?:, ${ACT} \d+)*\.`),
      t(String.raw`No counted workouts \(10 minutes or more\) by activity in the last 28 days \(0 workouts\)\.`)
    ],
    "mix.median_length": [t(String.raw`Median length of counted workouts \(10 minutes or more\) by activity in the last 28 days: ${ACT} ${N} min(?:, ${ACT} ${N} min)*\.`)],
    "mix.start_bands": [t(String.raw`Counted workout starts \(10 minutes or more\) in the last 28 days: morning \d+, afternoon \d+, evening \d+ \(morning is before 12:00, evening from 17:00\)\.`)],
    "body.sleep": [t(String.raw`Average sleep over the last 7 days: ${N} h \(from \d+ nights\), ${CMP("h")} the 28-day average of ${N} h \(from \d+ nights\)\.`)],
    "body.resting_hr": [t(String.raw`Average resting heart rate over the last 7 days: ${N} bpm \(from \d+ days with a reading\), ${CMP("bpm")} the 28-day average of ${N} bpm \(from \d+ days with a reading\)\.`)],
    "goal.workouts_per_week": [t(String.raw`\d+ counted workouts? \(10 minutes or more\) in the last 7 days; the baseline is ${N} counted workouts per week over the 28 days before this week \(\d+ logged days?\)(?:, a ratio of ${N})?\.`)],
    "goal.target_progress": [t(String.raw`Progress to the target of ${N} workouts per week: \d+ counted workouts? \(10 minutes or more\) in the last 7 days, ratio ${RATIO} to the target(?: \(${N}% of the target\))?\.`)]
  };
  var templateKey = (id) => id.startsWith("regularity.slot.") ? "regularity.slot" : id;
  function lintWords(text) {
    const problems = [...sentenceProblems(text)];
    if (typeof text !== "string") return problems;
    for (const [w, re] of WORD_RES) if (re.test(text)) problems.push(wordCategory(w));
    for (const [p, re] of PHRASE_RES) if (re.test(text)) problems.push(phraseCategory(p));
    for (const sentence of sentencesOf(text)) {
      const first = sentence.split(/[\s,:;]+/)[0].toLowerCase();
      if (IMPERATIVE_STARTS.includes(first)) problems.push("imperative start");
    }
    return [...new Set(problems)];
  }
  function lintFact(text, options = {}) {
    const problems = lintWords(text);
    if (typeof text !== "string") return problems;
    const table = options.templates || FACT_TEMPLATES;
    const pools = options.id ? table[templateKey(options.id)] || [] : Object.values(table).flat();
    if (!pools.some((re) => re.test(text))) problems.push("no template match");
    return problems;
  }

  // src/store/facts.mjs
  var deepFreeze = (o) => {
    if (o && typeof o === "object" && !Object.isFrozen(o)) {
      Object.freeze(o);
      for (const v of Object.values(o)) deepFreeze(v);
    }
    return o;
  };
  var REASONS = deepFreeze({
    too_early: "too early",
    too_late: "too late",
    too_long: "too long",
    too_hard: "too hard",
    not_today: "not today"
  });
  var WHY = deepFreeze({
    schedule_change: "schedule change",
    health_change: "health change",
    goal_change: "goal change",
    other: "other"
  });
  var ACTIVITIES = deepFreeze(["run", "walk", "cycle", "swim", "strength", "yoga", "hike", "row", "elliptical", "hiit", "pilates", "dance"]);
  var ROLL_ACTIVITIES = deepFreeze(["Running", "Walking", "Cycling", "Swimming", "Strength training", "Yoga", "Hiking", "Rowing", "Elliptical", "HIIT", "Pilates", "Dance", "Other"]);
  var DAYS = deepFreeze(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]);
  var DERIVED_KINDS = deepFreeze(["profile", "rolling"]);
  var DERIVED_FACT_TYPES = deepFreeze({
    daily: { home: "rolling", keyed: "date" },
    weekly: { home: "rolling", keyed: "date" },
    coverage: { home: "rolling", keyed: null },
    thin: { home: "rolling", keyed: null },
    today: { home: "rolling", keyed: null },
    week: { home: "rolling", keyed: null },
    profile: { home: "profile", keyed: null },
    mix: { home: "profile", keyed: "activity" },
    load: { home: "profile", keyed: null },
    regularity: { home: "profile", keyed: null },
    body: { home: "profile", keyed: null }
  });
  var FILE_KINDS = deepFreeze({
    profile: { tier: "pinned", summary: "Pinned user facts", title: "Profile", path: "about-user/profile.md", facts: ["profile", "mix", "load", "regularity", "body"] },
    rolling: { tier: "pinned", summary: "Rolling workout summaries: daily 28 days, weekly 12 weeks", title: "Rolling summaries", path: "health/rolling.md", facts: ["daily", "weekly", "coverage", "thin", "today", "week"] },
    preferences: { tier: "pinned", summary: "Standing workout preferences", title: "Workout preferences", path: "preferences/workouts.md", facts: ["standing", "change"] },
    feedback: { tier: "hot", summary: "What the user said about recommendations", title: "Recommendation feedback", path: "feedback/recommendations.md", facts: ["tap", "decline", "accept", "earlier"] },
    history: { tier: "cold", summary: "Preference history", title: "Preference history", path: "history/preferences.md", facts: ["history"] }
  });
  var COMPUTED = deepFreeze({
    "volume.today": "today",
    "volume.today_so_far": "today",
    "volume.today_unlogged": "today",
    "past.today_vs_avg": "today",
    "past.today_vs_highest": "today",
    "past.today_rank": "today",
    "volume.week": "week",
    "volume.28d": "week",
    "past.week_vs_avg": "week",
    "past.week_rank": "week",
    "past.week_comparisons_skipped": "week",
    "goal.workouts_per_week": "week",
    "goal.target_progress": "week",
    "load.ratio": "load",
    "regularity.days_since_last": "regularity",
    "regularity.longest_gap": "regularity",
    "regularity.per_week": "regularity",
    "regularity.slot": "regularity",
    "regularity.slots_none": "regularity",
    "mix.median_length": "regularity",
    "mix.start_bands": "regularity",
    "body.sleep": "body",
    "body.resting_hr": "body"
  });
  var TRUST = /* @__PURE__ */ new WeakSet();
  var mint = (o) => {
    Object.freeze(o);
    TRUST.add(o);
    return o;
  };
  var isFact = (x) => x !== null && typeof x === "object" && TRUST.has(x) && x.cls === "fact";
  var isSource = (x) => x !== null && typeof x === "object" && TRUST.has(x) && x.cls === "source";
  var bad = (what) => {
    throw new TypeError(`invalid ${what}`);
  };
  var int = (n, lo, hi, what) => Number.isInteger(n) && n >= lo && n <= hi ? n : bad(what);
  var member = (v, list2, what) => typeof v === "string" && list2.includes(v) ? v : bad(what);
  var key = (v, table, what) => typeof v === "string" && Object.hasOwn(table, v) ? v : bad(what);
  var list = (a, lo, hi, what) => Array.isArray(a) && a.length >= lo && a.length <= hi ? [...a] : bad(what);
  function dateStr(s, what = "date") {
    if (typeof s !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(s)) bad(what);
    const d = /* @__PURE__ */ new Date(`${s}T00:00:00Z`);
    return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s ? bad(what) : s;
  }
  function validKey(typeId, key2) {
    const how = Object.hasOwn(DERIVED_FACT_TYPES, typeId) ? DERIVED_FACT_TYPES[typeId].keyed : null;
    if (how === "date") {
      try {
        dateStr(key2);
        return true;
      } catch {
        return false;
      }
    }
    if (how === "activity") return typeof key2 === "string" && ROLL_ACTIVITIES.includes(key2);
    return false;
  }
  function isoMs(x) {
    if (typeof x !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(x) || Number.isNaN(Date.parse(x)) || new Date(x).toISOString() !== x) bad("time");
    return x;
  }
  var dayMs = (s) => Date.parse(`${s}T00:00:00Z`);
  var addDays = (date, n) => new Date(dayMs(date) + n * 864e5).toISOString().slice(0, 10);
  var agg = (lo, hi, days, count, room = Infinity) => {
    const ex = days === void 0 || days === null ? [] : list(days, 0, 400, "excludedDays").map((d) => dateStr(d)).sort();
    if (new Set(ex).size !== ex.length || ex.some((d) => d < lo || d > hi)) bad("excludedDays (unique, inside the range)");
    const n = days === void 0 || days === null ? count === void 0 ? 0 : int(count, 0, 400, "excluded days") : ex.length;
    if (days !== void 0 && days !== null && count !== void 0 && count !== ex.length) bad("excluded days");
    const span = lo < "0001" ? Infinity : Math.round((dayMs(hi) - dayMs(lo)) / 864e5) + 1;
    if (n > Math.min(span, room)) bad("excluded days (more than the window or the measurement allows)");
    return { range: Object.freeze([lo, hi]), excludedDays: Object.freeze(ex), excludedCount: n };
  };
  var leftOut = (n) => n === 0 ? "" : ` (${n} forgotten day${n === 1 ? "" : "s"} left out)`;
  function isoTime(x) {
    if (x instanceof Date) return Number.isNaN(x.getTime()) ? bad("time") : x.toISOString();
    if (typeof x !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(x) || Number.isNaN(Date.parse(x))) bad("time");
    return x;
  }
  var REC_ID = "^rec_[0-9a-f]{8,32}$";
  var USER_ID = "^usr_[0-9a-f]{8,32}$";
  var REC = "rec_[0-9a-f]{8,32}";
  var recId = (id) => typeof id === "string" && new RegExp(REC_ID).test(id) ? id : bad("recommendation id");
  var slotText = (weekday, hour) => `${DAYS[int(weekday, 1, 7, "weekday") - 1]} ${String(int(hour, 0, 23, "hour")).padStart(2, "0")}:00`;
  var exact = (n, hi, what) => typeof n === "number" && n >= 0 && n <= hi && /^\d{1,3}(?:\.\d{1,2})?$/.test(String(n)) ? n : bad(what);
  function standingBody(reason0, count0, slots0, since0) {
    const reason = key(reason0, REASONS, "reason");
    const count = int(count0, 2, 9999, "count");
    const slots = list(slots0, 1, 5, "slots").map((s) => ({ weekday: s?.weekday, hour: s?.hour }));
    if (slots.length > Math.min(count, 5)) bad("slots");
    const prefix = count > slots.length ? `latest ${slots.length}: ` : "";
    const since = since0 === void 0 || since0 === null ? "" : ` since ${isoMs(since0)}`;
    return `Declined ${count} suggestions as ${REASONS[reason]}${since} (${prefix}${slots.map((s) => slotText(s.weekday, s.hour)).join("; ")})`;
  }
  var fact = (kind, text, fields = {}) => mint({ cls: "fact", kind, text, key: text, ...fields });
  var F = Object.freeze({
    tap: (a) => {
      const { recId: id, activity, weekday, hour, reason } = a ?? {};
      return fact("tap", `Declined 1 ${member(activity, ACTIVITIES, "activity")} suggested for ${slotText(weekday, hour)} as ${REASONS[key(reason, REASONS, "reason")]} (recommendation ${recId(id)})`, { reason, key: `tap:${id}` });
    },
    // A decline with no reason (one tap on the watch): one outcome per recommendation id, never counted towards a standing entry.
    decline: (a) => {
      const { recId: id, activity, weekday, hour } = a ?? {};
      return fact("decline", `Declined 1 ${member(activity, ACTIVITIES, "activity")} suggested for ${slotText(weekday, hour)} (recommendation ${recId(id)}, no reason given)`, { key: `tap:${id}` });
    },
    // Older feedback folded into one count per action and reason; the recommendation ids are kept in its source.
    earlier: (a) => {
      const { action, reason, count } = a ?? {};
      const n = int(count, 1, 99999999, "count");
      if (action === "accepted") return fact("earlier", `Earlier: ${n} accepts`, { key: "earlier:accept" });
      if (action !== "declined") bad("action");
      if (reason === void 0 || reason === null) return fact("earlier", `Earlier: ${n} declines with no reason given`, { key: "earlier:decline:none" });
      return fact("earlier", `Earlier: ${n} declines as ${REASONS[key(reason, REASONS, "reason")]}`, { reason, key: `earlier:decline:${reason}` });
    },
    // An accepted recommendation: one outcome per recommendation id (it shares the tap key), no reason, never counted towards a standing entry.
    accept: (a) => {
      const { recId: id, activity, weekday, hour } = a ?? {};
      return fact("accept", `Accepted 1 ${member(activity, ACTIVITIES, "activity")} suggested for ${slotText(weekday, hour)} (recommendation ${recId(id)})`, { key: `tap:${id}` });
    },
    standing: (a) => {
      const { reason, count, slots, since } = a ?? {};
      return fact("standing", standingBody(reason, count, slots, since), { reason, key: `standing:${reason}` });
    },
    // Anchored to the moment of the change: a later decline does not make this sentence false.
    change: (a) => {
      const { reason, at, count } = a ?? {};
      return fact("change", `At the change on ${isoMs(at)}: ${int(count, 1, 9999, "count")} declines as ${REASONS[key(reason, REASONS, "reason")]} moved to history; new count starts at 0`, { reason });
    },
    // States what was recorded and when it changed; it does not claim the preference stayed true until then.
    history: (a) => {
      const { reason, count, at, why } = a ?? {};
      return fact("history", `Recorded ${int(count, 1, 9999, "count")} declines as ${REASONS[key(reason, REASONS, "reason")]}; changed on ${isoMs(at)} (reason given: ${WHY[key(why, WHY, "why")]})`, { reason });
    },
    // An engine sentence for one engine fact id. It states data up to now, so a forgotten day must be named in excludedDays.
    computed: (a) => {
      const { id, text, excludedDays } = a ?? {};
      const tid = typeof id === "string" && id.startsWith("regularity.slot.") ? "regularity.slot" : id;
      const type = typeof tid === "string" && Object.hasOwn(COMPUTED, tid) ? COMPUTED[tid] : bad("fact id");
      if (typeof text !== "string" || lintFact(text, { id: tid }).length > 0) bad("engine fact text");
      const same = tid.startsWith("volume.today") ? "volume.today" : tid;
      return fact(type, text, { key: `computed:${tid === "regularity.slot" ? text : same}`, ...agg("0000-01-01", "9999-12-31", excludedDays, void 0) });
    },
    daily: (a) => {
      const { date, items } = a ?? {};
      const rows = list(items, 1, 12, "items").map((i) => ({ activity: i?.activity, minutes: i?.minutes }));
      for (const r of rows) {
        member(r.activity, ROLL_ACTIVITIES, "activity");
        int(r.minutes, 1, 1440, "minutes");
      }
      rows.sort((x, y) => x.activity < y.activity ? -1 : x.activity > y.activity ? 1 : 0);
      if (new Set(rows.map((r) => r.activity)).size !== rows.length) bad("items");
      if (rows.reduce((n, r) => n + r.minutes, 0) > 1440) bad("minutes in a day");
      return fact("daily", `[daily] ${dateStr(date)}: ${rows.map((r) => `${r.activity} ${r.minutes} min`).join(", ")}`, { key: `daily:${date}` });
    },
    weekly: (a) => {
      const { weekStart, count, minutes, excludedDays, excludedCount } = a ?? {};
      dateStr(weekStart);
      if ((/* @__PURE__ */ new Date(`${weekStart}T00:00:00Z`)).getUTCDay() !== 1) bad("week start (must be a Monday)");
      int(count, 0, 99, "count");
      int(minutes, 0, 10080, "minutes");
      if (count === 0 !== (minutes === 0) || minutes < count) bad("week totals");
      const base = `[weekly] Week of ${weekStart}: ${count} workouts, ${minutes} min`;
      const g = agg(weekStart, addDays(weekStart, 6), excludedDays, excludedCount, 7);
      if (minutes > 1440 * (7 - g.excludedCount)) bad("week totals (more minutes than the remaining days hold)");
      return fact("weekly", `${base}${leftOut(g.excludedCount)}`, { key: `weekly:${weekStart}`, ...g });
    },
    profile: (a) => {
      const { perWeek: given, workouts, asOf, validUntil, excludedDays, excludedCount } = a ?? {};
      if (workouts !== void 0 && given !== void 0 && given !== workouts / 4) bad("per week (does not match the workout count)");
      const perWeek = workouts !== void 0 ? int(workouts, 0, 399, "workouts") / 4 : given;
      exact(perWeek, 99.99, "per week");
      if (!Number.isInteger(perWeek * 4)) bad("per week (a whole number of workouts over 4 weeks gives quarters)");
      dateStr(asOf);
      dateStr(validUntil);
      if (dayMs(validUntil) - dayMs(asOf) !== 864e5) bad("valid until (must be the next day)");
      const g = agg(addDays(asOf, -27), asOf, excludedDays, excludedCount);
      return fact("profile", `4-week average: ${perWeek} workouts per week (as of ${asOf}, valid until ${validUntil})${leftOut(g.excludedCount)}`, { key: "profile", ...g });
    },
    mix: (a) => {
      const { items, asOf, excludedDays, excludedCount } = a ?? {};
      const rows = list(items, 1, 13, "items").map((i) => ({ activity: i?.activity, count: i?.count }));
      for (const r of rows) {
        member(r.activity, ROLL_ACTIVITIES, "activity");
        int(r.count, 1, 999, "count");
      }
      if (new Set(rows.map((r) => r.activity)).size !== rows.length) bad("items");
      rows.sort((x, y) => x.activity < y.activity ? -1 : x.activity > y.activity ? 1 : 0);
      const g = agg(addDays(dateStr(asOf), -27), asOf, excludedDays, excludedCount);
      return fact("mix", `Last 4 weeks by type: ${rows.map((r) => `${r.activity} ${r.count}`).join(", ")} (as of ${asOf})${leftOut(g.excludedCount)}`, { key: "mix", asOf, ...g, items: Object.freeze(rows.map((r) => Object.freeze({ ...r }))), activities: Object.freeze(rows.map((r) => r.activity)) });
    },
    coverage: (a) => {
      const { workoutDays, windowDays, endDate, excludedDays, excludedCount } = a ?? {};
      if (![7, 28, 84].includes(windowDays)) bad("window");
      const logged = int(workoutDays, 0, windowDays, "days");
      const g = agg(addDays(dateStr(endDate), -(windowDays - 1)), endDate, excludedDays, excludedCount, windowDays - logged);
      return fact("coverage", `Workouts logged on ${logged} of the ${windowDays} days ending ${endDate}${leftOut(g.excludedCount)}`, { key: `coverage:${windowDays}`, ...g });
    },
    // Days of data covers every day up to its end date, so its range starts at the beginning of time.
    thin: (a) => {
      const { days, endDate, excludedDays, excludedCount } = a ?? {};
      const g = agg("0000-01-01", dateStr(endDate), excludedDays, excludedCount);
      return fact("thin", `Days of data: ${int(days, 0, 999, "days")} (ending ${endDate})${leftOut(g.excludedCount)}`, { key: "thin", ...g });
    }
  });
  var source = (id, type, ref, at, excerpt, ids) => mint({
    cls: "source",
    text: `[${id}] type=${type}; ref=${ref}; observed_at=${isoTime(at)}${excerpt ? `; excerpt=${excerpt}` : ""}${ids ? `; ids=${ids.join(",")}` : ""}`
  });
  var sortedUnique = (ids) => {
    const out = [...ids].sort();
    return out.every((x, i) => i === 0 || out[i - 1] < x) ? out : bad("ids (unique)");
  };
  var idList = (a) => sortedUnique(list(a, 1, 1e7, "ids").map(recId));
  var idTimeList = (a) => {
    const rows = list(a, 1, 1e7, "ids").map((x) => ({ id: recId(x?.id), at: x?.at instanceof Date ? x.at.getTime() : x?.at }));
    sortedUnique(rows.map((r) => r.id));
    return rows.sort((x, y) => x.id < y.id ? -1 : 1).map((r) => `${r.id}@${isoTime(new Date(r.at))}`);
  };
  var S = Object.freeze({
    tap: (a) => {
      const { recId: id, reason, at } = a ?? {};
      return source(`S${recId(id)}`, "feedback", `recommendation:${recId(id)}`, at, key(reason, REASONS, "reason"));
    },
    accept: (a) => {
      const { recId: id, at } = a ?? {};
      return source(`S${recId(id)}`, "feedback", `recommendation:${recId(id)}`, at);
    },
    earlier: (a) => {
      const { code, ids, at } = a ?? {};
      if (code !== "accept" && code !== "none" && !Object.hasOwn(REASONS, code)) bad("code");
      return source(`E-${code}`, "feedback", "feedback/recommendations.md", at, void 0, idTimeList(ids));
    },
    standing: (a) => {
      const { reason, at } = a ?? {};
      return source(`P-${key(reason, REASONS, "reason")}`, "feedback", "feedback/recommendations.md", at);
    },
    change: (a) => {
      const { reason, at } = a ?? {};
      return source(`C-${key(reason, REASONS, "reason")}`, "chat", `preference_change:${reason}`, at);
    },
    history: (a) => {
      const { reason, changedAt, why, ids, at } = a ?? {};
      return source(`H-${key(reason, REASONS, "reason")}`, "chat", `history:${reason}:${isoMs(changedAt)}:${key(why, WHY, "why")}`, at, void 0, idList(ids));
    },
    roll: (a) => {
      const { date, at } = a ?? {};
      return source("S-roll", "health_snapshot", `daily_roll:${dateStr(date)}`, at);
    }
  });
  var WORDS = Object.values(REASONS).join("|");
  var WHYW = Object.values(WHY).join("|");
  var DAY = DAYS.join("|");
  var SLOT = `(?:${DAY}) \\d\\d:00`;
  var SLOTS = `${SLOT}(?:; ${SLOT})*`;
  var DATE = "(\\d{4}-\\d{2}-\\d{2})";
  var ACT2 = ROLL_ACTIVITIES.join("|");
  var reasonKey = (w) => Object.keys(REASONS).find((k) => REASONS[k] === w);
  var whyKey = (w) => Object.keys(WHY).find((k) => WHY[k] === w);
  var slotsOf = (str) => str.split("; ").map((s) => ({ weekday: DAYS.indexOf(s.slice(0, 3)) + 1, hour: Number(s.slice(4, 6)) }));
  var STAND = `Declined (\\d{1,4}) suggestions as (${WORDS})(?: since (\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z))? \\((?:latest \\d: )?(${SLOTS})\\)`;
  var LEFT = "(?: \\((\\d{1,3}) forgotten days? left out\\))?$";
  var PARSERS = [
    [
      new RegExp(`^Declined 1 (${ACTIVITIES.join("|")}) suggested for (${DAY}) (\\d\\d):00 as (${WORDS}) \\(recommendation (${REC})\\)$`),
      (m) => F.tap({ recId: m[5], activity: m[1], weekday: DAYS.indexOf(m[2]) + 1, hour: Number(m[3]), reason: reasonKey(m[4]) })
    ],
    [
      new RegExp(`^Declined 1 (${ACTIVITIES.join("|")}) suggested for (${DAY}) (\\d\\d):00 \\(recommendation (${REC}), no reason given\\)$`),
      (m) => F.decline({ recId: m[4], activity: m[1], weekday: DAYS.indexOf(m[2]) + 1, hour: Number(m[3]) })
    ],
    [
      new RegExp(`^Earlier: (\\d{1,8}) (accepts|declines with no reason given|declines as (${WORDS}))$`),
      (m) => F.earlier(m[2] === "accepts" ? { action: "accepted", count: Number(m[1]) } : { action: "declined", count: Number(m[1]), reason: m[3] ? reasonKey(m[3]) : void 0 })
    ],
    [
      new RegExp(`^Accepted 1 (${ACTIVITIES.join("|")}) suggested for (${DAY}) (\\d\\d):00 \\(recommendation (${REC})\\)$`),
      (m) => F.accept({ recId: m[4], activity: m[1], weekday: DAYS.indexOf(m[2]) + 1, hour: Number(m[3]) })
    ],
    [new RegExp(`^${STAND}$`), (m) => F.standing({ reason: reasonKey(m[2]), count: Number(m[1]), since: m[3], slots: slotsOf(m[4]) })],
    [
      new RegExp(`^At the change on (\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z): (\\d{1,4}) declines as (${WORDS}) moved to history; new count starts at 0$`),
      (m) => F.change({ at: m[1], count: Number(m[2]), reason: reasonKey(m[3]) })
    ],
    [
      new RegExp(`^Recorded (\\d{1,4}) declines as (${WORDS}); changed on (\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z) \\(reason given: (${WHYW})\\)$`),
      (m) => F.history({ reason: reasonKey(m[2]), count: Number(m[1]), at: m[3], why: whyKey(m[4]) })
    ],
    [
      new RegExp(`^\\[daily\\] ${DATE}: ((?:${ACT2}) \\d{1,4} min(?:, (?:${ACT2}) \\d{1,4} min)*)$`),
      (m) => F.daily({ date: m[1], items: m[2].split(", ").map((x) => {
        const r = /^(.+) (\d+) min$/.exec(x);
        return { activity: r[1], minutes: Number(r[2]) };
      }) })
    ],
    [
      new RegExp(`^\\[weekly\\] Week of ${DATE}: (\\d{1,3}) workouts, (\\d{1,5}) min${LEFT}`),
      (m) => F.weekly({ weekStart: m[1], count: Number(m[2]), minutes: Number(m[3]), excludedCount: Number(m[4] ?? 0) })
    ],
    [
      new RegExp(`^4-week average: (\\d{1,3}(?:\\.\\d{1,2})?) workouts per week \\(as of ${DATE}, valid until ${DATE}\\)${LEFT}`),
      (m) => F.profile({ perWeek: Number(m[1]), asOf: m[2], validUntil: m[3], excludedCount: Number(m[4] ?? 0) })
    ],
    [
      new RegExp(`^Last 4 weeks by type: ((?:${ACT2}) \\d{1,3}(?:, (?:${ACT2}) \\d{1,3})*) \\(as of ${DATE}\\)${LEFT}`),
      (m) => F.mix({ asOf: m[2], excludedCount: Number(m[3] ?? 0), items: m[1].split(", ").map((x) => {
        const r = /^(.+) (\d+)$/.exec(x);
        return { activity: r[1], count: Number(r[2]) };
      }) })
    ],
    [new RegExp(`^Workouts logged on (\\d{1,2}) of the (\\d{1,3}) days ending ${DATE}${LEFT}`), (m) => F.coverage({ workoutDays: Number(m[1]), windowDays: Number(m[2]), endDate: m[3], excludedCount: Number(m[4] ?? 0) })],
    [new RegExp(`^Days of data: (\\d{1,3}) \\(ending ${DATE}\\)${LEFT}`), (m) => F.thin({ days: Number(m[1]), endDate: m[2], excludedCount: Number(m[3] ?? 0) })]
  ];
  var computedFrom = (text) => {
    const id = Object.keys(COMPUTED).find((i) => lintFact(text, { id: i }).length === 0);
    return id === void 0 ? null : F.computed({ id, text });
  };
  function reconstructFact(text) {
    if (typeof text !== "string") return null;
    for (const [re, build] of PARSERS) {
      const m = re.exec(text);
      if (!m) continue;
      try {
        const f = build(m);
        return f.text === text ? f : null;
      } catch {
        return null;
      }
    }
    try {
      return computedFrom(text);
    } catch {
      return null;
    }
  }
  var ISO = "(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,3})?Z)";
  var SRC_RE = new RegExp(`^\\[(S-roll|S${REC}|[PCH]-(?:${Object.keys(REASONS).join("|")})|E-(?:accept|none|${Object.keys(REASONS).join("|")}))\\] type=([a-z_]+); ref=(\\S+); observed_at=${ISO}(?:; excerpt=(${Object.keys(REASONS).join("|")}))?(?:; ids=((?:${REC}@\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z)(?:,${REC}@\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z)*|${REC}(?:,${REC})*))?$`);
  function reconstructSource(text) {
    if (typeof text !== "string") return null;
    const m = SRC_RE.exec(text);
    if (!m) return null;
    const [, id, , ref, at, excerpt, ids] = m;
    try {
      let s;
      if (id === "S-roll") s = S.roll({ date: ref.replace("daily_roll:", ""), at });
      else if (id.startsWith("Srec_")) s = excerpt === void 0 ? S.accept({ recId: id.slice(1), at }) : S.tap({ recId: id.slice(1), reason: excerpt, at });
      else if (id[0] === "E") s = S.earlier({ code: id.slice(2), ids: ids?.split(",").map((x) => ({ id: x.split("@")[0], at: Date.parse(x.split("@")[1]) })), at });
      else if (id[0] === "P") s = S.standing({ reason: id.slice(2), at });
      else if (id[0] === "C") s = S.change({ reason: id.slice(2), at });
      else {
        const h = /^history:([a-z_]+):(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z):([a-z_]+)$/.exec(ref);
        s = S.history({ reason: id.slice(2), changedAt: h[2], why: h[3], ids: ids?.split(","), at });
      }
      return s.text === text ? s : null;
    } catch {
      return null;
    }
  }
  var classifyFact = (text) => reconstructFact(text)?.kind ?? null;
  function parseDecline(text) {
    const m = new RegExp(`^Declined 1 (${ACTIVITIES.join("|")}) suggested for (${DAY}) (\\d\\d):00 \\(recommendation (${REC}), no reason given\\)$`).exec(text);
    return m ? { activity: m[1], weekday: DAYS.indexOf(m[2]) + 1, hour: Number(m[3]), recId: m[4] } : null;
  }
  function parseAccept(text) {
    const m = new RegExp(`^Accepted 1 (${ACTIVITIES.join("|")}) suggested for (${DAY}) (\\d\\d):00 \\(recommendation (${REC})\\)$`).exec(text);
    return m ? { activity: m[1], weekday: DAYS.indexOf(m[2]) + 1, hour: Number(m[3]), recId: m[4] } : null;
  }
  function parseStanding(text) {
    const m = new RegExp(`^${STAND}$`).exec(text);
    return m ? { reason: reasonKey(m[2]), count: Number(m[1]), since: m[3] ?? null, slots: slotsOf(m[4]) } : null;
  }
  function parseTap(text) {
    const m = new RegExp(`^Declined 1 (${ACTIVITIES.join("|")}) suggested for (${DAY}) (\\d\\d):00 as (${WORDS}) \\((?:recommendation )(${REC})\\)$`).exec(text);
    return m ? { activity: m[1], weekday: DAYS.indexOf(m[2]) + 1, hour: Number(m[3]), reason: reasonKey(m[4]), recId: m[5] } : null;
  }

  // src/store/validate.mjs
  var TIERS = Object.freeze(["pinned", "hot", "cold"]);
  function parseDocument(text, kindName) {
    const err = (error) => ({ error });
    if (typeof text !== "string" || !text.endsWith("\n")) return err("document must end with a newline");
    const lines2 = text.slice(0, -1).split("\n");
    const k = Object.hasOwn(FILE_KINDS, kindName) ? FILE_KINDS[kindName] : null;
    if (!k || lines2[0] !== `<!-- idx: tier=${k.tier}; summary=${k.summary} -->` || lines2[1] !== `# ${k.title}`) {
      return err("header, summary or title does not match this file kind");
    }
    if (lines2[2] !== "## Current facts") return err("missing Current facts");
    const facts = [];
    const sources = [];
    let i = 3;
    for (; i < lines2.length && lines2[i] !== "## Sources"; i++) {
      const f = lines2[i].startsWith("- ") ? reconstructFact(lines2[i].slice(2)) : null;
      if (!f) return err("a fact line is not produced by any constructor");
      if (!k.facts.includes(f.kind)) return err(`a ${f.kind} fact does not belong in this file`);
      facts.push(f);
    }
    if (lines2[i] !== "## Sources") return err("missing Sources");
    for (i++; i < lines2.length; i++) {
      const x = lines2[i].startsWith("- ") ? reconstructSource(lines2[i].slice(2)) : null;
      if (!x) return err("a source line is not produced by any constructor");
      sources.push(x);
    }
    if (new Set(facts.map((f) => f.text)).size !== facts.length) return err("duplicate fact");
    if (new Set(sources.map((x) => x.text)).size !== sources.length) return err("duplicate source");
    const keys = facts.map((f) => f.key);
    if (new Set(keys).size !== keys.length) return err("two facts state the same thing (conflicting values for one key)");
    if (kindName === "history") {
      const bySrc = /* @__PURE__ */ new Map();
      for (const x of sources) {
        const m = /^\[H-([a-z_]+)\] type=chat; ref=history:[a-z_]+:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z):([a-z_]+); observed_at=\S+?; ids=(\S+)$/.exec(x.text);
        if (!m) return err("a source in the history file is not a history source");
        const k2 = `${m[1]}|${m[2]}|${m[3]}`;
        if (bySrc.has(k2)) return err("two sources for one history entry");
        bySrc.set(k2, m[4].split(",").length);
      }
      for (const f of facts) {
        const m = /^Recorded (\d+) declines as [a-z ]+; changed on (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z) \(reason given: ([a-z ]+)\)$/.exec(f.text);
        const why = Object.keys(WHY).find((w) => WHY[w] === m[3]);
        const k2 = `${f.reason}|${m[2]}|${why}`;
        if (!bySrc.has(k2)) return err("a history entry has no source listing its recommendation ids");
        if (bySrc.get(k2) !== Number(m[1])) return err("a history entry counts a different number of declines than its source lists");
        bySrc.delete(k2);
      }
      if (bySrc.size) return err("a history source has no entry");
    }
    if (kindName === "feedback") {
      const bySource = /* @__PURE__ */ new Map();
      const folds = /* @__PURE__ */ new Map();
      for (const x of sources) {
        const e = /^\[E-([a-z_]+)\] type=feedback; ref=\S+; observed_at=\S+?; ids=(\S+)$/.exec(x.text);
        if (e) {
          if (folds.has(e[1])) return err("two sources for one fold");
          folds.set(e[1], e[2].split(",").map((r) => r.split("@")[0]));
          continue;
        }
        const m = /^\[S(rec_[0-9a-f]+)\] type=feedback; ref=recommendation:\S+; observed_at=\S+?(?:; excerpt=(\w+))?$/.exec(x.text);
        if (!m) return err("a source in the feedback file is not a tap source");
        if (bySource.has(m[1])) return err("two sources for one tap");
        bySource.set(m[1], m[2] ?? "");
      }
      const folded = /* @__PURE__ */ new Set();
      for (const f of facts) {
        if (f.kind === "earlier") {
          const code = f.key === "earlier:accept" ? "accept" : f.key.slice("earlier:decline:".length);
          const ids = folds.get(code);
          if (!ids) return err("a fold has no source listing its recommendation ids");
          const count = Number(/^Earlier: (\d+) /.exec(f.text)[1]);
          if (ids.length !== count) return err("a fold counts a different number of outcomes than its source lists");
          for (const id2 of ids) {
            if (folded.has(id2)) return err("a recommendation id is folded twice");
            folded.add(id2);
          }
          folds.delete(code);
          continue;
        }
        const id = f.key.slice(4);
        if (!bySource.has(id)) return err("a tap has no source (no observation time)");
        if (bySource.get(id) !== (f.reason ?? "")) return err("a tap source names another reason than its tap");
        if (folded.has(id)) return err("a recommendation id is both kept and folded");
        bySource.delete(id);
      }
      if (bySource.size) return err("a source has no tap");
      if (folds.size) return err("a fold source has no fold");
      for (const f of facts) if (f.kind !== "earlier" && folded.has(f.key.slice(4))) return err("a recommendation id is both kept and folded");
    }
    return { facts, sources };
  }
  function validateDocument(text, kindName) {
    return parseDocument(text, kindName).error ?? null;
  }
  function validateForgotten(text) {
    let o;
    try {
      o = JSON.parse(text);
    } catch {
      return "not JSON";
    }
    if (!Array.isArray(o)) return "must be a JSON array";
    const known = (h) => {
      if (typeof h !== "string") return false;
      if (/^[0-9a-f]{64}$/.test(h)) return true;
      const t2 = /^type:([a-z]+)$/.exec(h);
      if (t2) return Object.hasOwn(DERIVED_FACT_TYPES, t2[1]);
      const d = /^day:(.+)$/.exec(h);
      if (d) return validKey("daily", d[1]);
      const k = /^key:([a-z]+):(.+)$/.exec(h);
      return k !== null && k[1] !== "daily" && validKey(k[1], k[2]);
    };
    if (!o.every(known)) return "entries must be sha256 hex, a fact type id, a fact type key or a forgotten day";
    if (new Set(o).size !== o.length) return "duplicate entry";
    return null;
  }
  var ISO2 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
  var ID = new RegExp(REC_ID);
  var okReason = (r) => typeof r === "string" && Object.hasOwn(REASONS, r);
  var okIds = (a) => Array.isArray(a) && a.length <= 1e7 && a.every((x) => typeof x === "string" && ID.test(x));
  function validateJournal(text) {
    let o;
    try {
      o = JSON.parse(text);
    } catch {
      return "not JSON";
    }
    if (!o || typeof o !== "object" || Array.isArray(o)) return "bad shape";
    const keys = Object.keys(o).sort().join();
    if (typeof o.at !== "string" || !ISO2.test(o.at)) return "bad time";
    if (o.op === "forget_recommendation") {
      return keys === "at,id,op" && typeof o.id === "string" && ID.test(o.id) ? null : "bad forget_recommendation";
    }
    if (o.op === "forget_fold") {
      return keys === "at,code,ids,op" && typeof o.code === "string" && (o.code === "accept" || o.code === "none" || okReason(o.code)) && okIds(o.ids) ? null : "bad forget_fold";
    }
    if (o.op === "forget_fact_type") {
      return keys === "at,op,typeId" && typeof o.typeId === "string" && Object.hasOwn(DERIVED_FACT_TYPES, o.typeId) ? null : "bad forget_fact_type";
    }
    if (o.op === "forget_fact_key") {
      return keys === "at,key,op,typeId" && typeof o.typeId === "string" && validKey(o.typeId, o.key) ? null : "bad forget_fact_key";
    }
    if (o.op === "forget_derived") {
      return keys === "at,kind,op" && DERIVED_KINDS.includes(o.kind) ? null : "bad forget_derived";
    }
    if (o.op === "forget_reason") {
      return keys === "at,op,reason" && okReason(o.reason) ? null : "bad forget_reason";
    }
    if (o.op === "forget_taps") {
      return keys === "at,ids,op,reasons" && okIds(o.ids) && Array.isArray(o.reasons) && o.reasons.every(okReason) ? null : "bad forget_taps";
    }
    if (o.op === "change_preference") {
      const ok = keys === "at,count,ids,op,reason,why" && okReason(o.reason) && Object.hasOwn(WHY, o.why) && /\.\d{3}Z$/.test(o.at) && Number.isInteger(o.count) && o.count >= 2 && okIds(o.ids) && o.ids.length === o.count;
      return ok ? null : "bad change_preference";
    }
    return "unknown operation";
  }

  // src/store/derive.mjs
  var PROMOTE_AFTER = 2;
  var SHOWN_TAPS = 5;
  var FEEDBACK_KEEP = 30;
  var DERIVED_FACT_KINDS = Object.freeze(["standing", "change", "history"]);
  var isDerivedFactKind = (k) => DERIVED_FACT_KINDS.includes(k);
  function tapsOf(doc, reason) {
    if (!doc) return [];
    const at = new Map(doc.sources.map((x) => [/^\[S(rec_[0-9a-f]+)\]/.exec(x.text)?.[1], Date.parse(/observed_at=(\S+?)(?:;|$)/.exec(x.text)[1])]));
    return doc.facts.map((f) => parseTap(f.text)).filter((t2) => t2 && t2.reason === reason).map((t2) => {
      if (!at.has(t2.recId) || Number.isNaN(at.get(t2.recId))) throw new TypeError("a tap has no valid observation time");
      return { ...t2, at: at.get(t2.recId) };
    }).sort((a, b) => a.at - b.at || (a.recId < b.recId ? -1 : a.recId > b.recId ? 1 : 0));
  }
  function expectedStanding(doc, reason, since = null) {
    const taps = tapsOf(doc, reason);
    const count = taps.length + (earlierOf(doc).get(reason)?.count ?? 0);
    return count >= PROMOTE_AFTER && taps.length > 0 ? F.standing({ reason, count, slots: taps.slice(-SHOWN_TAPS), since }) : null;
  }
  function earlierOf(doc) {
    const out = /* @__PURE__ */ new Map();
    for (const fact2 of doc?.facts.filter((f) => f.kind === "earlier") ?? []) {
      const code = fact2.key === "earlier:accept" ? "accept" : fact2.key.slice("earlier:decline:".length);
      const source2 = doc.sources.find((x) => x.text.startsWith(`[E-${code}] `));
      if (!source2) continue;
      const rows = /; ids=(\S+)$/.exec(source2.text)[1].split(",").map((x) => x.split("@"));
      out.set(code, {
        fact: fact2,
        source: source2,
        count: Number(/^Earlier: (\d+) /.exec(fact2.text)[1]),
        ids: rows.map((r) => r[0]),
        times: new Map(rows.map((r) => [r[0], Date.parse(r[1])])),
        at: Date.parse(/observed_at=(\S+?);/.exec(source2.text)[1])
      });
    }
    return out;
  }
  function changeTime(prefs, reason) {
    if (!prefs) return null;
    const times = prefs.sources.filter((x) => x.text.startsWith(`[C-${reason}]`)).map((x) => Date.parse(/observed_at=(\S+?)(?:;|$)/.exec(x.text)[1]));
    return times.length ? Math.max(...times) : null;
  }
  function changeSince(prefs, reason) {
    const t2 = changeTime(prefs, reason);
    return t2 === null ? null : new Date(t2).toISOString();
  }
  function standingProblem(prefs, feedback) {
    for (const reason of Object.keys(REASONS)) {
      const want = expectedStanding(feedback, reason, changeSince(prefs, reason));
      const have = prefs.facts.filter((f) => f.kind === "standing" && f.reason === reason);
      if (want === null ? have.length > 0 : have.length !== 1 || have[0].text !== want.text) return `the standing entry for ${reason} does not match the taps held`;
    }
    return null;
  }
  function historyProblem(history, prefs) {
    for (const h of history.facts) {
      const stamp = /changed on (\S+Z) /.exec(h.text)[1];
      const count = Number(/^Recorded (\d+) declines/.exec(h.text)[1]);
      const ok = (prefs?.facts ?? []).some((f) => f.kind === "change" && f.reason === h.reason && f.text.startsWith(`At the change on ${stamp}: ${count} declines `));
      if (!ok) return "a history entry has no matching change fact (same reason, moment and count)";
    }
    return null;
  }
  var cmp = (a, b) => a < b ? -1 : a > b ? 1 : 0;
  function canonicalOrder(kind, facts, sources) {
    const lead = kind === "rolling" ? ["daily", "weekly"] : [];
    const rank = (f) => {
      const i = lead.indexOf(f.kind);
      return i < 0 ? lead.length : i;
    };
    const fs = [...new Map(facts.map((f) => [f.text, f])).values()].sort((a, b) => rank(a) - rank(b) || cmp(a.kind, b.kind) || cmp(a.key, b.key) || cmp(a.text, b.text));
    const owner = (x) => {
      const m = /^\[(S(rec_[0-9a-f]+)|([PCHE])-([a-z_]+)|S-roll)\]/.exec(x.text);
      if (!m || m[1] === "S-roll") return Infinity;
      const i = m[2] ? fs.findIndex((f) => f.key === `tap:${m[2]}`) : m[3] === "E" ? fs.findIndex((f) => f.key === (m[4] === "accept" ? "earlier:accept" : `earlier:decline:${m[4]}`)) : fs.findIndex((f) => f.kind === { P: "standing", C: "change", H: "history" }[m[3]] && f.reason === m[4]);
      return i < 0 ? Infinity : i;
    };
    const sx = [...new Map(sources.map((x) => [x.text, x])).values()].sort((a, b) => cmp(owner(a), owner(b)) || cmp(a.text, b.text));
    return { facts: fs, sources: sx };
  }

  // src/store/memory-store.mjs
  var USER_RE = new RegExp(USER_ID);
  var SOURCES = "## Sources";
  var PathEscapeError = class extends Error {
    constructor(msg = "path escapes the user's memory folder") {
      super(msg);
      this.name = "PathEscapeError";
      this.code = "PATH_ESCAPE";
    }
  };
  var MemoryUnavailableError = class extends Error {
    constructor(msg) {
      super(`memory unavailable: ${msg}`);
      this.name = "MemoryUnavailableError";
      this.code = "MEMORY_UNAVAILABLE";
    }
  };
  var UnrecoveredWriteError = class extends Error {
    constructor(msg) {
      super(msg);
      this.name = "UnrecoveredWriteError";
      this.code = "UNRECOVERED";
    }
  };
  var DIR_SYNC_TOLERATED = Object.freeze(["ENOTSUP", "EOPNOTSUPP"]);
  var DIR_SYNC_UNSUPPORTED_PLATFORMS = Object.freeze({ win32: Object.freeze(["EINVAL", "EPERM", "EISDIR"]) });
  function toleratedDirSyncError(code, platform = "posix") {
    return DIR_SYNC_TOLERATED.includes(code) || (DIR_SYNC_UNSUPPORTED_PLATFORMS[platform] ?? []).includes(code);
  }
  var TEMP_SUFFIX = ".memtmp";
  var FORGOTTEN = "forgotten.json";
  var JOURNAL = "journal.json";
  var keyEntry = (typeId, key2) => typeId === "daily" ? `day:${key2}` : `key:${typeId}:${key2}`;
  var kindKey = (kind) => `derived-kind:${kind}`;
  var ACCESS = /* @__PURE__ */ Symbol("journal access");
  var DERIVE = /* @__PURE__ */ Symbol("derive");
  function section(text, name) {
    const lines2 = text.split("\n");
    const start = lines2.indexOf(`## ${name}`);
    if (start < 0) return "";
    let end = lines2.length;
    for (let i = start + 1; i < lines2.length; i++) if (lines2[i].startsWith("## ")) {
      end = i;
      break;
    }
    return lines2.slice(start + 1, end).join("\n");
  }
  function factLines(text) {
    return section(text, "Current facts").split("\n").filter((l) => l.startsWith("- "));
  }
  var MemoryStore = class {
    #io;
    #user;
    #id;
    #allow = 0;
    #derive = 0;
    /**
     * @param {string} root  folder that holds one sub-folder per user
     * @param {string} user  user id: usr_ followed by 8 to 32 lowercase hex characters
     * @param {object} opts  `io` (required): the host's io object (contract in node/io-node.mjs). The test hooks writeFile,
     *   fsyncFile, rename, remove and fsyncDir override single methods of it.
     */
    constructor(root, user, opts = {}) {
      if (typeof user !== "string" || !USER_RE.test(user)) throw new PathEscapeError("invalid user id");
      const hooks = Object.fromEntries(["writeFile", "fsyncFile", "rename", "remove", "fsyncDir"].filter((k) => opts[k]).map((k) => [k, opts[k]]));
      if (!opts.io || typeof opts.io.readFile !== "function") throw new TypeError("MemoryStore needs an io object (see node/io-node.mjs for the contract)");
      if (!isAbsolute(root)) throw new TypeError("the root must be an absolute path");
      this.#io = { ...opts.io, ...hooks };
      this.#makeDirs(root);
      this.root = this.#io.realpath(root);
      this.dir = join(this.root, user);
      try {
        if (this.#io.lstat(this.dir).isSymbolicLink) throw new PathEscapeError("user folder is a symlink");
      } catch (e) {
        if (e.code !== "ENOENT") throw e;
      }
      this.#makeDirs(this.dir);
      this.realDir = this.#io.realpath(this.dir);
      if (this.realDir !== join(this.root, user) || basename(this.realDir) !== user) {
        throw new PathEscapeError("user folder is not directly under the root, or its name is not exactly the id");
      }
      this.#user = user;
      const own = this.#io.lstat(this.dir);
      this.#id = `${own.dev}:${own.ino}`;
      this.lastStatus = "ok";
      this.lastError = null;
      this.sweepTemps();
    }
    /** Flush a directory. Only the documented "not supported" errors are tolerated (see toleratedDirSyncError). */
    #syncDir(d) {
      try {
        this.#io.fsyncDir(d);
      } catch (e) {
        if (!toleratedDirSyncError(e.code, this.#io.platform)) throw e;
      }
    }
    #lstat(p) {
      try {
        return this.#io.lstat(p);
      } catch (e) {
        if (e.code === "ENOENT") return null;
        throw e;
      }
    }
    /** Create a directory and every missing ancestor one level at a time, syncing the parent of each directory created. */
    #makeDirs(dir) {
      const missing = [];
      for (let d = dir; ; d = dirname(d)) {
        if (this.#lstat(d)) break;
        missing.unshift(d);
        if (dirname(d) === d) break;
      }
      for (const d of missing) {
        this.#io.mkdir(d);
        this.#syncDir(dirname(d));
      }
    }
    /** The text of a file, null when absent (ENOENT, and only that), or undefined when it exists but cannot be read. */
    #readState(p) {
      try {
        return this.#io.readFile(p);
      } catch (e) {
        return e.code === "ENOENT" ? null : void 0;
      }
    }
    /** Absolute path inside the user's folder, or throws PathEscapeError (../, absolute, symlink). */
    path(rel) {
      this.#checkDir();
      if (typeof rel !== "string" || rel === "" || rel.includes("\0") || rel.includes("\\")) throw new PathEscapeError();
      if (isAbsolute(rel)) throw new PathEscapeError();
      const parts = rel.split("/");
      if (parts.some((p) => p === ".." || p === "" || p === ".")) throw new PathEscapeError();
      let cur = this.realDir;
      for (const part of parts) {
        cur = join(cur, part);
        let st;
        st = this.#lstat(cur);
        if (st === null) continue;
        if (st.isSymbolicLink) throw new PathEscapeError("symlink in the memory folder");
      }
      return cur;
    }
    /**
     * Checked before every read, write and delete: the user folder is still a real directory (not a symlink),
     * directly under the root, with exactly the expected name. Node cannot anchor to a directory descriptor, so a swap
     * between this check and the following call is a known limit (see docs/STORE.md).
     */
    #checkDir() {
      let st;
      try {
        st = this.#io.lstat(this.dir);
      } catch {
        throw new PathEscapeError("user folder is missing");
      }
      if (st.isSymbolicLink || !st.isDirectory) throw new PathEscapeError("user folder is not a real directory");
      if (`${st.dev}:${st.ino}` !== this.#id) throw new PathEscapeError("user folder was replaced");
      if (basename(this.dir) !== this.#user || dirname(this.dir) !== this.root) throw new PathEscapeError("user folder moved");
      if (this.#io.realpath(this.dir) !== this.realDir || this.#io.realpath(dirname(this.dir)) !== this.root) {
        throw new PathEscapeError("user folder or root was replaced");
      }
    }
    #rel(kind) {
      if (typeof kind !== "string" || !Object.hasOwn(FILE_KINDS, kind)) throw new TypeError("unknown file kind");
      return FILE_KINDS[kind].path;
    }
    #readStrict(rel) {
      const p = this.path(rel);
      try {
        return this.#io.readFile(p);
      } catch (e) {
        if (e.code === "ENOENT") return null;
        if (e instanceof PathEscapeError) throw e;
        if (e.code === "ELOOP") throw new PathEscapeError("symlink in the memory folder");
        throw new MemoryUnavailableError(`${rel} cannot be read`);
      }
    }
    /** Fail closed: a damaged forgotten.json, or a journal that has not been recovered, blocks every read and write. */
    #guard() {
      this.#hashes();
      this.#checkDir();
      if (this.#allow === 0 && this.#lstat(this.path(JOURNAL)) !== null) throw new MemoryUnavailableError("an operation journal is waiting to be recovered");
    }
    /** Run fn with journal access (recovery and operations that own the journal). Internal: reached through the ACCESS symbol. */
    [ACCESS](fn) {
      this.#allow++;
      try {
        return fn();
      } finally {
        this.#allow--;
      }
    }
    /** Run fn as the store's own recompute: only then may standing, change and history facts be written (and read while out of step). */
    [DERIVE](fn) {
      this.#derive++;
      try {
        return fn();
      } finally {
        this.#derive--;
      }
    }
    /** Text of a memory file. The whole file is validated against the templates on every read; an invalid file throws. */
    view(kind) {
      return this.#load(kind)?.text ?? null;
    }
    /** The trusted fact and source objects of a file ({facts, sources}), or null when the file does not exist. */
    read(kind) {
      return this.#load(kind);
    }
    #load(kind, check = this.#derive === 0) {
      this.#guard();
      const text = this.#readStrict(this.#rel(kind));
      if (text === null) return null;
      const doc = parseDocument(text, kind);
      if (doc.error) throw new MemoryUnavailableError(`${FILE_KINDS[kind].path} is not valid (${doc.error})`);
      if (check && kind === "preferences") {
        const problem = standingProblem(doc, this.#load("feedback", false));
        if (problem) throw new MemoryUnavailableError(`${FILE_KINDS[kind].path} is not consistent (${problem})`);
      }
      if (check && kind === "history") {
        const problem = historyProblem(doc, this.#load("preferences", false));
        if (problem) throw new MemoryUnavailableError(`${FILE_KINDS[kind].path} is not consistent (${problem})`);
      }
      return { text, facts: doc.facts, sources: doc.sources };
    }
    /**
     * Validate, write to a temp file, read it back, rename over the target, read back again.
     * False means nothing changed. UnrecoveredWriteError means the target could not be restored.
     */
    /** Delete a file and make the deletion durable: remove, then fsync the containing directory. Nothing to do if it is not there. */
    #removeDurable(p, always = false) {
      if (this.#lstat(p) === null) {
        if (always && this.#lstat(dirname(p)) !== null) this.#syncDir(dirname(p));
        return;
      }
      this.#io.remove(p);
      this.#syncDir(dirname(p));
    }
    /** Create the directory (and any missing parents under the user folder), fsyncing each parent so the new entry survives a power loss. */
    #ensureDir(dir) {
      const missing = [];
      for (let d = dir; d !== this.realDir && d.startsWith(`${this.realDir}/`); d = dirname(d)) {
        if (this.#lstat(d) !== null) break;
        missing.unshift(d);
      }
      for (const d of missing) {
        this.#io.mkdir(d);
        this.#syncDir(dirname(d));
      }
    }
    #write(kind, text) {
      return this.#put(this.#rel(kind), text, (t2) => validateDocument(t2, kind));
    }
    #put(rel, text, check) {
      this.#guard();
      const p = this.path(rel);
      const bad2 = check(text);
      if (bad2) {
        this.lastError = `rejected: ${bad2}`;
        this.lastStatus = "failed";
        return false;
      }
      const before = this.#readState(p);
      if (before === void 0) {
        this.lastError = `${rel} exists but cannot be read`;
        this.lastStatus = "failed";
        throw new MemoryUnavailableError(`${rel} cannot be read`);
      }
      this.#checkDir();
      const tmp = `${p}${TEMP_SUFFIX}`;
      const put = (content) => {
        this.#removeDurable(tmp);
        this.#io.writeFile(tmp, content);
        this.#io.fsyncFile(tmp);
        if (this.#readState(tmp) !== content) throw new Error("read-back mismatch (temp file)");
        this.#checkDir();
        this.#io.rename(tmp, p);
        this.#syncDir(dirname(p));
        if (this.#readState(p) !== content) throw new Error("read-back mismatch");
      };
      try {
        this.#ensureDir(dirname(p));
        put(text);
        this.lastError = null;
        this.lastStatus = "ok";
        return true;
      } catch (e) {
        this.lastError = `write failed: ${e.message}`;
      }
      try {
        this.#removeDurable(tmp);
      } catch {
      }
      if (this.#readState(p) !== before) {
        try {
          if (before === null) this.#removeDurable(p);
          else put(before);
        } catch {
        }
        try {
          this.#removeDurable(tmp);
        } catch {
        }
        if (this.#readState(p) !== before) {
          this.lastStatus = "unrecovered";
          throw new UnrecoveredWriteError(`could not restore ${rel} after a failed write`);
        }
      }
      this.lastStatus = "failed";
      return false;
    }
    /** The one write path for memory files: objects in, canonical text out, verified. */
    #commit(kind, facts, sources) {
      if (!Object.hasOwn(FILE_KINDS, kind) || !Array.isArray(facts) || !Array.isArray(sources)) return false;
      if (!facts.every(isFact) || !sources.every(isSource)) return false;
      if (this.#derive === 0 && facts.some((f) => isDerivedFactKind(f.kind))) {
        this.lastError = "rejected: standing, change and history facts are derived by the store, callers cannot write them";
        return false;
      }
      if (DERIVED_KINDS.includes(kind) && this.kindSuppressed(kind)) {
        this.lastError = "rejected: this derived file was forgotten";
        return false;
      }
      const gone = this.#hashes();
      const ids = [
        ...facts.filter((f) => f.kind === "tap" || f.kind === "accept" || f.kind === "decline").map((f) => f.key.slice(4)),
        ...sources.map((x) => /^\[S(rec_[0-9a-f]+)\]/.exec(x.text)?.[1]).filter(Boolean)
      ];
      for (const f of facts) {
        const keyed = Object.hasOwn(DERIVED_FACT_TYPES, f.kind) ? DERIVED_FACT_TYPES[f.kind].keyed : null;
        const hit = gone.includes(`type:${f.kind}`) || f.kind === "daily" && gone.includes(`day:${f.key.slice(6)}`) || keyed === "date" && f.kind !== "daily" && gone.includes(`key:${f.kind}:${f.key.slice(f.kind.length + 1)}`) || keyed === "activity" && f.activities.some((a) => gone.includes(`key:${f.kind}:${a}`));
        if (hit) {
          this.lastError = `rejected: ${f.kind} facts (or this key) were forgotten and are suppressed`;
          return false;
        }
      }
      if (ids.some((id) => gone.includes(this.#io.sha256(id)))) {
        this.lastError = "rejected: a forgotten recommendation id";
        return false;
      }
      for (const x of sources) {
        const list2 = /; ids=(\S+)$/.exec(x.text)?.[1];
        if (list2 && list2.split(",").some((r) => gone.includes(this.#io.sha256(`forgotten:${r.split("@")[0]}`)))) {
          this.lastError = "rejected: a forgotten recommendation id in a fold or history source";
          return false;
        }
      }
      const days = gone.filter((h) => h.startsWith("day:")).map((h) => h.slice(4));
      if (days.length || facts.some((f) => f.range && f.excludedCount > 0)) {
        const have = new Set((this.#load(kind, false)?.facts ?? []).map((f) => f.text));
        for (const f of facts) {
          if (!f.range || have.has(f.text) || this.#derive > 0) continue;
          if (f.excludedCount > 0 && f.excludedDays.length === 0) {
            this.lastError = `rejected: this ${f.kind} fact claims left-out days without naming them`;
            return false;
          }
          const stray = f.excludedDays.find((d) => !days.includes(d));
          if (stray) {
            this.lastError = `rejected: this ${f.kind} fact leaves out ${stray}, which is not a forgotten day`;
            return false;
          }
        }
        for (const f of facts) {
          if (!f.range || have.has(f.text)) continue;
          const inside = days.filter((d) => d >= f.range[0] && d <= f.range[1]);
          const missing = f.excludedDays.length ? inside.filter((d) => !f.excludedDays.includes(d)) : this.#derive > 0 && inside.length <= f.excludedCount ? [] : inside;
          const hit = missing[0];
          if (hit) {
            this.lastError = `rejected: this ${f.kind} fact covers the forgotten day ${hit} without excluding it`;
            return false;
          }
        }
      }
      const k = FILE_KINDS[kind];
      const ordered = canonicalOrder(kind, facts, sources);
      return this.#write(kind, `<!-- idx: tier=${k.tier}; summary=${k.summary} -->
# ${k.title}
## Current facts
` + ordered.facts.map((x) => `- ${x.text}
`).join("") + `${SOURCES}
` + ordered.sources.map((x) => `- ${x.text}
`).join(""));
    }
    /** facts and sources must be objects made by the constructors in facts.mjs; raw text is refused. */
    create(kind, facts, sources) {
      if (!Object.hasOwn(FILE_KINDS, kind) || !Array.isArray(facts) || !Array.isArray(sources)) return false;
      if (!facts.every(isFact) || !sources.every(isSource)) return false;
      if (this.view(kind) !== null) return false;
      return this.#commit(kind, facts, sources);
    }
    /** Add a fact and its source in one verified write. A duplicate fact is ignored (true, nothing written). */
    insert(kind, fact2, src) {
      if (!isFact(fact2) || !isSource(src)) return false;
      const doc = this.read(kind);
      if (doc === null) return false;
      if (doc.facts.some((f) => f.text === fact2.text)) return true;
      return this.#commit(kind, [...doc.facts, fact2], [...doc.sources, src]);
    }
    /** Replace one existing fact by a new fact object; the source (if given) is added in the same write. */
    strReplace(kind, oldText, fact2, src) {
      if (typeof oldText !== "string" || oldText === "" || !isFact(fact2) || src !== void 0 && !isSource(src)) return false;
      const doc = this.read(kind);
      if (doc === null || !doc.facts.some((f) => f.text === oldText)) return false;
      return this.#commit(kind, doc.facts.map((f) => f.text === oldText ? fact2 : f), src ? [...doc.sources, src] : doc.sources);
    }
    /** Replace the whole file with these fact and source objects. An empty fact list deletes the file. */
    replaceFacts(kind, facts, sources = []) {
      if (!Object.hasOwn(FILE_KINDS, kind) || !Array.isArray(facts) || !Array.isArray(sources)) return false;
      if (!facts.every(isFact) || !sources.every(isSource)) return false;
      if (facts.length === 0) return this.delete(kind);
      return this.#commit(kind, facts, sources);
    }
    /** Delete a memory file (works even on a file that is no longer valid, so it can be cleared). */
    delete(kind) {
      this.#guard();
      this.#readStrict(this.#rel(kind));
      return this.#remove(this.#rel(kind));
    }
    #remove(rel) {
      const p = this.path(rel);
      this.#checkDir();
      try {
        this.#removeDurable(p, true);
      } catch {
        return false;
      }
      return this.#lstat(p) === null;
    }
    /** forgotten.json: sha256 hex of ids that were forgotten or moved to history, and of derived kinds that were forgotten. */
    #hashes() {
      const t2 = this.#readStrict(FORGOTTEN);
      if (t2 === null) return [];
      if (validateForgotten(t2) !== null) throw new MemoryUnavailableError("forgotten.json is damaged");
      return JSON.parse(t2);
    }
    #store(hashes) {
      return this.#put(FORGOTTEN, `${JSON.stringify([...new Set(hashes)].sort())}
`, validateForgotten);
    }
    isSuppressed(id) {
      return typeof id === "string" && this.#hashes().includes(this.#io.sha256(id));
    }
    /** Suppress recommendation ids. `forgotten` also marks them forgotten, so they cannot be written back into a fold or history source. */
    suppress(ids, forgotten = false) {
      if (!Array.isArray(ids) || !ids.every((x) => typeof x === "string" && new RegExp(REC_ID).test(x))) return false;
      const have = this.#hashes();
      const merged = [.../* @__PURE__ */ new Set([...have, ...ids.flatMap((x) => forgotten ? [this.#io.sha256(x), this.#io.sha256(`forgotten:${x}`)] : [this.#io.sha256(x)])])];
      return merged.length === have.length ? true : this.#store(merged);
    }
    /** A derived kind (profile, rolling) that was forgotten is not written again until it is restored. */
    kindSuppressed(kind) {
      return this.#hashes().includes(this.#io.sha256(kindKey(kind)));
    }
    suppressKind(kind) {
      if (!DERIVED_KINDS.includes(kind)) return false;
      const have = this.#hashes();
      return have.includes(this.#io.sha256(kindKey(kind))) ? true : this.#store([...have, this.#io.sha256(kindKey(kind))]);
    }
    unsuppressKind(kind) {
      if (!DERIVED_KINDS.includes(kind)) return false;
      const have = this.#hashes();
      return have.includes(this.#io.sha256(kindKey(kind))) ? this.#store(have.filter((h) => h !== this.#io.sha256(kindKey(kind)))) : true;
    }
    /** Suppression of a derived fact type, or of one key of a keyed type. Plain ids and keys in forgotten.json, never content. */
    typeSuppressed(typeId) {
      return this.#hashes().includes(`type:${typeId}`);
    }
    keySuppressed(typeId, key2) {
      return this.#hashes().includes(keyEntry(typeId, key2));
    }
    #mark(entry, on) {
      const have = this.#hashes();
      if (have.includes(entry) === on) return true;
      return this.#store(on ? [...have, entry] : have.filter((h) => h !== entry));
    }
    suppressType(typeId) {
      return Object.hasOwn(DERIVED_FACT_TYPES, typeId) && this.#mark(`type:${typeId}`, true);
    }
    unsuppressType(typeId) {
      return Object.hasOwn(DERIVED_FACT_TYPES, typeId) && this.#mark(`type:${typeId}`, false);
    }
    suppressKey(typeId, key2) {
      return validKey(typeId, key2) && this.#mark(keyEntry(typeId, key2), true);
    }
    unsuppressKey(typeId, key2) {
      return validKey(typeId, key2) && this.#mark(keyEntry(typeId, key2), false);
    }
    /** What is suppressed, for the roll and the fact engine to skip: type ids, keys and forgotten days only. */
    suppressedFacts() {
      const types = [];
      const keys = [];
      const days = [];
      for (const h of this.#hashes()) {
        const t2 = /^type:(.+)$/.exec(h);
        const k = /^key:([a-z]+):(.+)$/.exec(h);
        const d = /^day:(.+)$/.exec(h);
        if (t2) types.push(t2[1]);
        else if (k) keys.push({ type: k[1], key: k[2] });
        else if (d) days.push(d[1]);
      }
      return { types: types.sort(), keys: keys.sort((a, b) => a.type + a.key < b.type + b.key ? -1 : 1), days: days.sort() };
    }
    /** Operation journal for multi-file changes. null = none, false = present but unreadable. */
    readJournal() {
      this.#hashes();
      let t2;
      try {
        t2 = this.#readStrict(JOURNAL);
      } catch {
        return false;
      }
      if (t2 === null) return null;
      return validateJournal(t2) === null ? JSON.parse(t2) : false;
    }
    writeJournal(op) {
      return this[ACCESS](() => this.#put(JOURNAL, `${JSON.stringify(op)}
`, validateJournal));
    }
    clearJournal() {
      this.#hashes();
      return this.#remove(JOURNAL);
    }
    /** Paths (relative) of leftover temporary files under the user folder. */
    tempFiles() {
      this.#checkDir();
      const out = [];
      const walk = (dir, prefix) => {
        for (const e of this.#io.readdir(dir)) {
          if (e.name.endsWith(TEMP_SUFFIX)) out.push(`${prefix}${e.name}`);
          else if (e.isDirectory && !e.isSymbolicLink) walk(join(dir, e.name), `${prefix}${e.name}/`);
        }
      };
      walk(this.realDir, "");
      return out.sort();
    }
    /**
     * Remove every leftover temporary file. Each one must be a regular file (or a symlink, which is only unlinked,
     * never followed) inside the user's folder; a directory with a temp name makes the store unavailable.
     */
    sweepTemps() {
      let removed = 0;
      for (const rel of this.tempFiles()) {
        const p = join(this.realDir, ...rel.split("/"));
        const st = this.#io.lstat(p);
        if (st.isDirectory) throw new MemoryUnavailableError(`${rel} is a directory with a temporary file name`);
        try {
          this.#removeDurable(p);
        } catch {
          throw new MemoryUnavailableError(`${rel} could not be removed`);
        }
        removed++;
      }
      return removed;
    }
    /** Sorted paths of the memory files that exist (only the fixed per-kind paths; stray files are never listed). */
    paths() {
      this.#guard();
      return Object.values(FILE_KINDS).map((k) => k.path).filter((rel) => {
        try {
          return this.#lstat(this.path(rel))?.isFile === true;
        } catch (e) {
          if (e instanceof PathEscapeError) throw e;
          return false;
        }
      }).sort();
    }
    /** Read a file by its fixed path (as listed by paths()). */
    viewPath(rel) {
      const k = Object.keys(FILE_KINDS).find((n) => FILE_KINDS[n].path === rel);
      if (!k) throw new TypeError("not a memory file path");
      return this.view(k);
    }
  };

  // src/store/feedback.mjs
  var FEEDBACK_FILE = "feedback";
  var PREFS_FILE = "preferences";
  var HISTORY_FILE = "history";
  var WORDS2 = Object.values(REASONS).join("|");
  var KEY_OF = Object.fromEntries(Object.entries(REASONS).map(([k, w]) => [w, k]));
  var REASON_IN_LINE = new RegExp(`\\bas (${WORDS2})\\b`);
  var reasonOf = (line) => {
    const m = REASON_IN_LINE.exec(line);
    return m ? KEY_OF[m[1]] : null;
  };
  var reasonSourceHit = (reason) => (s) => s.startsWith(`- [P-${reason}]`) || s.startsWith(`- [C-${reason}]`) || s.startsWith(`- [H-${reason}]`) || s.startsWith(`- [E-${reason}]`) || s.includes("type=feedback") && s.includes(`excerpt=${reason}`);
  function createOrInsert(store, kind, fact2, src) {
    return store.view(kind) === null ? store.create(kind, [fact2], [src]) : store.insert(kind, fact2, src);
  }
  function strip(store, kind, factPred, sourcePred) {
    const doc = store.read(kind);
    if (doc === null) return true;
    const facts = doc.facts.filter((f) => !factPred(`- ${f.text}`));
    const sources = doc.sources.filter((x) => !sourcePred(`- ${x.text}`));
    if (facts.length === doc.facts.length && sources.length === doc.sources.length) return true;
    return store.replaceFacts(kind, facts, sources);
  }
  var outcomeOf = (line) => parseTap(line.slice(2)) ?? parseDecline(line.slice(2)) ?? parseAccept(line.slice(2));
  var tapsFor = (store, reason) => tapsOf(store.read(FEEDBACK_FILE), reason);
  var standingLine = (store, reason) => {
    const text = store.view(PREFS_FILE);
    if (text === null) return null;
    return factLines(text).find((l) => classifyFact(l.slice(2)) === "standing" && parseStanding(l.slice(2)).reason === reason) ?? null;
  };
  function syncStanding(store, reason, at) {
    const taps = tapsFor(store, reason);
    const want = expectedStanding(store.read(FEEDBACK_FILE), reason, changeSince(store.read(PREFS_FILE), reason));
    const cur = standingLine(store, reason);
    const sat = want ? new Date(taps.at(-1).at).toISOString() : at;
    let ok = true;
    if (want === null) {
      if (cur !== null) ok = strip(store, PREFS_FILE, (l) => l === cur, (x) => x.startsWith(`- [P-${reason}]`));
    } else {
      const src = S.standing({ reason, at: sat });
      const doc = store.read(PREFS_FILE);
      const has = doc !== null && doc.facts.some((f) => f.text === want.text) && doc.sources.some((x) => x.text === src.text);
      if (!has) {
        ok = store.replaceFacts(
          PREFS_FILE,
          [...(doc?.facts ?? []).filter((f) => !(f.kind === "standing" && f.reason === reason)), want],
          [...(doc?.sources ?? []).filter((x) => !x.text.startsWith(`[P-${reason}]`)), src]
        );
      }
    }
    if (ok && want !== null) ok = factLines(store.view(PREFS_FILE) ?? "").includes(`- ${want.text}`);
    return { ok, line: ok && want ? want.text : null };
  }
  function historyEntries(doc) {
    const out = [];
    for (const src of doc?.sources ?? []) {
      const m = /^\[H-([a-z_]+)\] type=chat; ref=history:[a-z_]+:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z):([a-z_]+); observed_at=(\S+?); ids=(\S+)$/.exec(src.text);
      if (!m) continue;
      const fact2 = doc.facts.find((f) => f.kind === "history" && f.reason === m[1] && f.text.endsWith(`changed on ${m[2]} (reason given: ${WHY[m[3]]})`));
      if (fact2) out.push({ fact: fact2, src, reason: m[1], at: m[2], why: m[3], ids: m[5].split(","), count: Number(/^Recorded (\d+) /.exec(fact2.text)[1]) });
    }
    return out;
  }
  function withFold(doc, code, entries) {
    const had = earlierOf(doc).get(code);
    const facts = doc.facts.filter((f) => f !== had?.fact);
    const sources = doc.sources.filter((x) => x !== had?.source);
    if (entries.length) {
      const sorted = [...entries].sort((a, b) => a.id < b.id ? -1 : 1);
      facts.push(F.earlier({ action: code === "accept" ? "accepted" : "declined", reason: Object.hasOwn(REASONS, code) ? code : void 0, count: sorted.length }));
      sources.push(S.earlier({ code, ids: sorted, at: new Date(Math.max(...sorted.map((e) => e.at))) }));
    }
    return { facts, sources };
  }
  var foldEntries = (fold) => fold.ids.map((id) => ({ id, at: fold.times.get(id) }));
  function writeHistory(store, j) {
    const doc = store.read(HISTORY_FILE);
    const old = historyEntries(doc).find((e) => e.reason === j.reason && e.at === j.at && e.why === j.why);
    if (old) return true;
    const ids = [...j.ids].sort();
    const fact2 = F.history({ reason: j.reason, count: ids.length, at: j.at, why: j.why });
    const src = S.history({ reason: j.reason, changedAt: j.at, why: j.why, ids, at: j.at });
    if (doc === null) return store.create(HISTORY_FILE, [fact2], [src]);
    return store.replaceFacts(HISTORY_FILE, [...doc.facts, fact2], [...doc.sources, src]);
  }
  function syncChangeFacts(store) {
    const doc = store.read(PREFS_FILE);
    if (doc === null) return true;
    const entries = historyEntries(store.read(HISTORY_FILE));
    let changed = false;
    const facts = [];
    for (const f of doc.facts) {
      if (f.kind !== "change") {
        facts.push(f);
        continue;
      }
      const stamp = /^At the change on (\S+Z): /.exec(f.text)[1];
      const total = entries.filter((e) => e.reason === f.reason && e.at === stamp).reduce((n, e) => n + e.count, 0);
      if (total === Number(/: (\d+) declines/.exec(f.text)[1])) {
        facts.push(f);
        continue;
      }
      changed = true;
      if (total > 0) facts.push(F.change({ reason: f.reason, at: stamp, count: total }));
    }
    return !changed || store.replaceFacts(PREFS_FILE, facts, doc.sources);
  }
  function removeOutcome(store, id) {
    if (!store.suppress([id], true)) return false;
    let doc = store.read(FEEDBACK_FILE);
    const line = doc?.facts.find((f) => f.kind !== "earlier" && f.key === `tap:${id}`);
    if (line && !strip(store, FEEDBACK_FILE, (l) => l === `- ${line.text}`, (x) => x.startsWith(`- [S${id}] `))) return false;
    doc = line ? store.read(FEEDBACK_FILE) : doc;
    for (const [code, fold] of doc ? earlierOf(doc) : []) {
      if (!fold.ids.includes(id)) continue;
      const next = withFold(doc, code, foldEntries(fold).filter((e2) => e2.id !== id));
      if (!store.replaceFacts(FEEDBACK_FILE, next.facts, next.sources)) return false;
      break;
    }
    const hist = store.read(HISTORY_FILE);
    const e = historyEntries(hist).find((x) => x.ids.includes(id));
    if (e) {
      const ids = e.ids.filter((x) => x !== id);
      const rest = { facts: hist.facts.filter((f) => f !== e.fact), sources: hist.sources.filter((x) => x !== e.src) };
      if (ids.length) {
        rest.facts.push(F.history({ reason: e.reason, count: ids.length, at: e.at, why: e.why }));
        rest.sources.push(S.history({ reason: e.reason, changedAt: e.at, why: e.why, ids, at: new Date(Date.parse(/observed_at=(\S+?);/.exec(e.src.text)[1])) }));
      }
      if (!store.replaceFacts(HISTORY_FILE, rest.facts, rest.sources)) return false;
    }
    return syncChangeFacts(store);
  }
  function applyJournal(store, j) {
    if (j.op === "change_preference") {
      if (!writeHistory(store, j)) return false;
      if (!store.suppress(j.ids)) return false;
      const moved = new Set(j.ids);
      if (!strip(
        store,
        FEEDBACK_FILE,
        (l) => moved.has(parseTap(l.slice(2))?.recId),
        (s) => j.ids.some((id) => s.startsWith(`- [S${id}] `))
      )) return false;
      const fdoc = store.read(FEEDBACK_FILE);
      const fold = earlierOf(fdoc).get(j.reason);
      if (fold && fold.ids.some((id) => moved.has(id))) {
        const next = withFold(fdoc, j.reason, foldEntries(fold).filter((e) => !moved.has(e.id)));
        if (!store.replaceFacts(FEEDBACK_FILE, next.facts, next.sources)) return false;
      }
      const change = F.change({ reason: j.reason, at: j.at, count: j.count });
      const csrc = S.change({ reason: j.reason, at: j.at });
      const doc = store.read(PREFS_FILE);
      const facts = [...(doc?.facts ?? []).filter((f) => !(f.kind === "standing" && f.reason === j.reason)), change];
      const sources = [...(doc?.sources ?? []).filter((x) => !x.text.startsWith(`[P-${j.reason}]`) && !x.text.startsWith(`[C-${j.reason}]`)), csrc];
      const same = doc !== null && doc.facts.length === new Set(facts.map((f) => f.text)).size && facts.every((f) => doc.facts.some((d) => d.text === f.text)) && doc.sources.length === sources.length && sources.every((x) => doc.sources.some((d) => d.text === x.text));
      return same || store.replaceFacts(PREFS_FILE, facts, sources);
    }
    if (j.op === "forget_fact_type") return applyForgetFact(store, j.typeId, null);
    if (j.op === "forget_fact_key") return applyForgetFact(store, j.typeId, j.key);
    if (j.op === "forget_derived") return store.suppressKind(j.kind) && store.delete(j.kind) && store.view(j.kind) === null;
    if (j.op === "forget_recommendation") return removeOutcome(store, j.id);
    if (j.op === "forget_fold") {
      if (!store.suppress(j.ids, true)) return false;
      const fdoc = store.read(FEEDBACK_FILE);
      if (fdoc === null || !earlierOf(fdoc).has(j.code)) return true;
      const next = withFold(fdoc, j.code, []);
      return store.replaceFacts(FEEDBACK_FILE, next.facts, next.sources);
    }
    if (j.op === "forget_taps") {
      if (!store.suppress(j.ids, true)) return false;
      const ids = new Set(j.ids);
      if (!strip(store, FEEDBACK_FILE, (l) => ids.has(outcomeOf(l)?.recId), (s) => j.ids.some((id) => s.startsWith(`- [S${id}] `)))) return false;
      return j.reasons.every((r) => syncStanding(store, r, j.at).ok);
    }
    if (j.op === "forget_reason") return purgeReason(store, j.reason);
    return false;
  }
  function finishForget(store) {
    store.sweepTemps();
    return store.tempFiles().length === 0;
  }
  function applyForgetFact(store, typeId, key2) {
    if (!(key2 === null ? store.suppressType(typeId) : store.suppressKey(typeId, key2))) return false;
    const dropKey = (f) => {
      if (key2 === null) return f.kind === typeId ? null : f;
      if (typeId === "daily") {
        if (f.kind === "daily") return f.key === `daily:${key2}` ? null : f;
        return f.range && key2 >= f.range[0] && key2 <= f.range[1] && !f.excludedDays.includes(key2) ? null : f;
      }
      if (f.kind !== typeId) return f;
      if (typeId === "mix") {
        const items = f.items.filter((i) => i.activity !== key2);
        return items.length === f.items.length ? f : items.length ? F.mix({ items, asOf: f.asOf, excludedCount: f.excludedCount }) : null;
      }
      return f.key === `${typeId}:${key2}` ? null : f;
    };
    for (const kind of DERIVED_KINDS) {
      const doc = store.read(kind);
      if (doc === null) continue;
      const facts = doc.facts.map(dropKey).filter(Boolean);
      if (facts.length === doc.facts.length && facts.every((f, i) => f === doc.facts[i])) continue;
      if (!store.replaceFacts(kind, facts, doc.sources)) return false;
    }
    return DERIVED_KINDS.every((kind) => {
      const doc = store.read(kind);
      return doc === null || doc.facts.every((f) => dropKey(f) === f);
    });
  }
  function resyncStanding(store) {
    return Object.keys(REASONS).every((r) => syncStanding(store, r, (/* @__PURE__ */ new Date(0)).toISOString()).ok);
  }
  function recover(store) {
    return store[ACCESS](() => store[DERIVE](() => {
      store.sweepTemps();
      const j = store.readJournal();
      if (j === null) return { ok: resyncStanding(store) && foldOld(store), applied: null };
      if (j === false) return { ok: false, applied: null };
      let done = false;
      try {
        done = applyJournal(store, j);
      } catch (e) {
        if (!(e instanceof TypeError)) throw e;
      }
      if (!done) return { ok: false, applied: null };
      return store.clearJournal() && resyncStanding(store) && foldOld(store) ? { ok: true, applied: j } : { ok: false, applied: null };
    }));
  }
  function runOp(store, j) {
    if (!store.writeJournal(j)) return false;
    return store[ACCESS](() => applyJournal(store, j) && store.clearJournal() && resyncStanding(store));
  }
  function foldOld(store) {
    const doc = store.read(FEEDBACK_FILE);
    if (doc === null) return true;
    const when = new Map(doc.sources.map((x) => [/^\[S(rec_[0-9a-f]+)\]/.exec(x.text)?.[1], Date.parse(/observed_at=(\S+?)(?:;|$)/.exec(x.text)[1])]));
    const entries = doc.facts.filter((f) => f.kind !== "earlier").map((f) => ({ fact: f, id: f.key.slice(4), at: when.get(f.key.slice(4)), code: f.kind === "accept" ? "accept" : f.reason ?? "none" })).sort((a, b) => a.at - b.at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    if (entries.length <= FEEDBACK_KEEP) return true;
    const kept = new Set(entries.slice(-FEEDBACK_KEEP));
    for (const r of Object.keys(REASONS)) for (const e of entries.filter((x) => x.fact.kind === "tap" && x.code === r).slice(-SHOWN_TAPS)) kept.add(e);
    const old = entries.filter((e) => !kept.has(e));
    if (old.length === 0) return true;
    let out = { facts: doc.facts.filter((f) => !old.some((e) => e.fact === f)), sources: doc.sources.filter((x) => !old.some((e) => x.text.startsWith(`[S${e.id}] `))) };
    for (const code of new Set(old.map((e) => e.code))) {
      const had = earlierOf(doc).get(code);
      const entries2 = [...had ? foldEntries(had) : [], ...old.filter((e) => e.code === code).map((e) => ({ id: e.id, at: e.at }))];
      out = withFold({ facts: out.facts, sources: out.sources }, code, entries2);
    }
    return store.replaceFacts(FEEDBACK_FILE, out.facts, out.sources);
  }
  function recordFeedbackImpl(store, { recId: recId2, activity, weekday, hour, action, reason, now } = {}) {
    const no = (why, extra = {}) => ({ written: false, promoted: null, why, ...extra });
    if (action !== "accepted" && action !== "declined") return no("action must be accepted or declined");
    const absent = reason === void 0 || reason === null;
    if (action === "accepted" && !absent) return no("an accepted recommendation takes no reason");
    if (action === "declined" && !absent && !Object.hasOwn(REASONS, reason)) return no("the reason must be one of the five, or absent");
    let fact2;
    let src;
    let at;
    try {
      at = isoTime(now);
      if (action === "accepted" || absent) {
        fact2 = (action === "accepted" ? F.accept : F.decline)({ recId: recId2, activity, weekday, hour });
        src = S.accept({ recId: recId2, at });
      } else {
        fact2 = F.tap({ recId: recId2, activity, weekday, hour, reason });
        src = S.tap({ recId: recId2, reason, at });
      }
    } catch (e) {
      return no(e.message);
    }
    if (!recover(store).ok) return no("recovery pending");
    if (store.isSuppressed(recId2)) return no("this recommendation id was forgotten or already moved to history", { suppressed: true });
    const doc = store.read(FEEDBACK_FILE);
    let seen = doc === null ? void 0 : doc.facts.find((f) => f.key === `tap:${recId2}`);
    const foldedIn = doc === null ? void 0 : [...earlierOf(doc)].find(([, e]) => e.ids.includes(recId2))?.[0];
    if (!seen && foldedIn !== void 0) seen = { reason: Object.hasOwn(REASONS, foldedIn) ? foldedIn : void 0 };
    if (!seen) {
      const folded = [...earlierOf(doc).values()].flatMap((e) => [...e.times.values()]);
      if (folded.length && Date.parse(at) <= Math.max(...folded)) return no("refused: observed at or before the newest folded outcome");
    }
    if (!seen && action === "declined" && !absent) {
      const ct = changeTime(store.read(PREFS_FILE), reason);
      if (ct !== null && Date.parse(at) <= ct) return no("refused: observed at or before the latest change of this preference");
    }
    let written = true;
    if (!seen) written = createOrInsert(store, FEEDBACK_FILE, fact2, src);
    if (!written) return no(store.lastError ?? "write failed");
    const out = { written: true, promoted: null };
    if (seen) out.duplicate = true;
    if (!foldOld(store)) out.foldFailed = true;
    const declinedReason = seen ? seen.reason : action === "declined" && !absent ? reason : void 0;
    if (declinedReason !== void 0) {
      const sync = syncStanding(store, declinedReason, at);
      out.promoted = sync.line;
      if (!sync.ok) out.promotionFailed = true;
    }
    return out;
  }
  function purgeReason(store, reason) {
    const isReason = (l) => reasonOf(l) === reason;
    const src = reasonSourceHit(reason);
    const fold = earlierOf(store.read(FEEDBACK_FILE)).get(reason);
    const moved = historyEntries(store.read(HISTORY_FILE)).filter((e) => e.reason === reason).flatMap((e) => e.ids);
    if (!store.suppress([...tapsFor(store, reason).map((t2) => t2.recId), ...fold?.ids ?? [], ...moved], true)) return false;
    if (!strip(store, HISTORY_FILE, isReason, src)) return false;
    if (!strip(store, FEEDBACK_FILE, isReason, src)) return false;
    if (!strip(store, PREFS_FILE, isReason, src)) return false;
    return [HISTORY_FILE, FEEDBACK_FILE, PREFS_FILE].every((rel) => {
      const t2 = store.view(rel);
      if (t2 === null) return true;
      const sources = t2.split("## Sources\n")[1] ?? "";
      return !factLines(t2).some(isReason) && !sources.split("\n").some((l) => l.startsWith("- ") && src(l));
    });
  }
  function forgetImpl(store, rel, prefix) {
    if (typeof prefix !== "string" || prefix.trim() === "" || /[\r\n]/.test(prefix)) return false;
    if (!Object.hasOwn(FILE_KINDS, rel)) return false;
    if (DERIVED_KINDS.includes(rel)) {
      store.lastError = `refused: ${rel} facts are recomputed from the health snapshot; use forgetFactType or forgetFactKey to stop summarising it, or forgetDerived('${rel}') to remove the whole file`;
      return false;
    }
    const rec = recover(store);
    if (!rec.ok) return false;
    const text = store.view(rel);
    const hits = text === null ? [] : factLines(text).filter((l) => l.startsWith(`- ${prefix}`));
    if (hits.length === 0) return rec.applied !== null && rec.applied.op !== "change_preference";
    const at = (/* @__PURE__ */ new Date()).toISOString();
    if (rel === FEEDBACK_FILE) {
      const outcomes = hits.map(outcomeOf).filter(Boolean);
      const reasons = [...new Set(outcomes.map((t2) => t2.reason).filter(Boolean))];
      if (outcomes.length && !runOp(store, { op: "forget_taps", ids: outcomes.map((t2) => t2.recId), reasons, at })) return false;
      for (const l of hits.filter((x) => x.startsWith("- Earlier: "))) {
        const found = [...earlierOf(store.read(FEEDBACK_FILE)).entries()].find(([, x]) => `- ${x.fact.text}` === l);
        if (found && !runOp(store, { op: "forget_fold", code: found[0], ids: [...found[1].ids].sort(), at })) return false;
      }
      const rest = hits.filter((l) => !outcomeOf(l) && !l.startsWith("- Earlier: "));
      if (rest.length && !strip(store, rel, (l) => rest.includes(l), () => false)) return false;
    } else if (rel === PREFS_FILE || rel === HISTORY_FILE) {
      const reasons = [...new Set(hits.map(reasonOf).filter(Boolean))];
      for (const r of reasons) if (!runOp(store, { op: "forget_reason", reason: r, at })) return false;
      const rest = hits.filter((l) => !reasonOf(l));
      if (rest.length && !strip(store, rel, (l) => rest.includes(l), () => false)) return false;
    } else if (!strip(store, rel, (l) => hits.includes(l), () => false)) {
      return false;
    }
    const after = store.view(rel);
    return (after === null || !factLines(after).some((l) => l.startsWith(`- ${prefix}`))) && finishForget(store);
  }
  function forgetDerivedImpl(store, kind) {
    if (!DERIVED_KINDS.includes(kind) || !recover(store).ok) return false;
    return runOp(store, { op: "forget_derived", kind, at: (/* @__PURE__ */ new Date()).toISOString() }) && finishForget(store);
  }
  function recordFeedback(store, opts = {}) {
    return store[DERIVE](() => recordFeedbackImpl(store, opts));
  }
  function forget(store, rel, prefix) {
    return store[DERIVE](() => forgetImpl(store, rel, prefix));
  }
  function forgetDerived(store, kind) {
    return store[DERIVE](() => forgetDerivedImpl(store, kind));
  }
  function forgetFactType(store, typeId) {
    if (typeof typeId !== "string" || !Object.hasOwn(DERIVED_FACT_TYPES, typeId) || !recover(store).ok) return false;
    return runOp(store, { op: "forget_fact_type", typeId, at: (/* @__PURE__ */ new Date()).toISOString() }) && finishForget(store);
  }
  function forgetFactKey(store, typeId, key2) {
    return store[DERIVE](() => {
      if (!validKey(typeId, key2) || !recover(store).ok) return false;
      return runOp(store, { op: "forget_fact_key", typeId, key: key2, at: (/* @__PURE__ */ new Date()).toISOString() }) && finishForget(store);
    });
  }
  function suppressedTypes(store) {
    if (!recover(store).ok) throw new MemoryUnavailableError("an operation journal could not be recovered");
    return store.suppressedFacts();
  }
  function forgetRecommendation(store, recId2) {
    return store[DERIVE](() => {
      if (typeof recId2 !== "string") return false;
      const rec = recover(store);
      if (!rec.ok) return false;
      const doc = store.read(FEEDBACK_FILE);
      const present = doc?.facts.some((f) => f.kind !== "earlier" && f.key === `tap:${recId2}`) || [...earlierOf(doc).values()].some((x) => x.ids.includes(recId2)) || historyEntries(store.read(HISTORY_FILE)).some((e) => e.ids.includes(recId2));
      if (!present) return rec.applied?.op === "forget_recommendation" && rec.applied.id === recId2;
      return runOp(store, { op: "forget_recommendation", id: recId2, at: (/* @__PURE__ */ new Date()).toISOString() }) && finishForget(store);
    });
  }

  // src/contract/time.mjs
  var RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?(Z|([+-])(\d{2}):(\d{2}))$/;
  function parseTimestamp(s) {
    if (typeof s !== "string") return null;
    const m = RE.exec(s);
    if (!m) return null;
    const y = Number(m[1]);
    const mo = Number(m[2]);
    const d = Number(m[3]);
    const h = Number(m[4]);
    const mi = Number(m[5]);
    const sec = m[6] === void 0 ? 0 : Number(m[6]);
    if (h > 23 || mi > 59 || sec > 59) return null;
    let offsetMin = 0;
    if (m[8] !== "Z") {
      const oh = Number(m[10]);
      const om = Number(m[11]);
      if (oh > 23 || om > 59) return null;
      offsetMin = (m[9] === "-" ? -1 : 1) * (oh * 60 + om);
    }
    const t2 = /* @__PURE__ */ new Date(0);
    t2.setUTCFullYear(y, mo - 1, d);
    if (t2.getUTCFullYear() !== y || t2.getUTCMonth() !== mo - 1 || t2.getUTCDate() !== d) return null;
    t2.setUTCHours(h, mi, sec, 0);
    const frac = m[7] === void 0 ? 0 : Number((m[7] + "00").slice(0, 3));
    const ms = t2.getTime() + frac - offsetMin * 6e4;
    const date = m[1] + "-" + m[2] + "-" + m[3];
    return { ms, date, hour: h };
  }

  // src/contract/snapshot.mjs
  var DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
  var isObj = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
  var isNum = (x) => typeof x === "number" && Number.isFinite(x);
  var decimalsOk = (x, n) => Math.abs(x * 10 ** n - Math.round(x * 10 ** n)) < 1e-4;
  function stable(v) {
    if (Array.isArray(v)) return `[${v.map(stable).join(",")}]`;
    if (isObj(v)) return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(",")}}`;
    return JSON.stringify(v);
  }
  function validDate(s) {
    if (typeof s !== "string" || !DATE_ONLY.test(s)) return false;
    const d = /* @__PURE__ */ new Date(`${s}T00:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
  }
  function validTimestamp(s) {
    return parseTimestamp(s) !== null;
  }
  function validateSnapshot(snapshot) {
    const errors = [];
    const bad2 = (path, msg) => errors.push(`${path}: ${msg}`);
    if (!isObj(snapshot)) return { ok: false, errors: ["snapshot: must be an object"] };
    if (!validTimestamp(snapshot.exportDate)) bad2("exportDate", "must be an ISO 8601 timestamp with an offset and at most 3 fractional second digits");
    if (!isObj(snapshot.persona) || typeof snapshot.persona.key !== "string" || !snapshot.persona.key) {
      bad2("persona", "must be an object with a non-empty key");
    }
    if (!Array.isArray(snapshot.dailySummaries)) bad2("dailySummaries", "must be an array");
    else {
      snapshot.dailySummaries.forEach((s, i) => {
        const p = `dailySummaries[${i}]`;
        if (!isObj(s)) return bad2(p, "must be an object");
        if (!validDate(s.date)) bad2(`${p}.date`, "must be a calendar date YYYY-MM-DD");
        if (isNum(s.restingHeartRate) && !decimalsOk(s.restingHeartRate, 6)) bad2(`${p}.restingHeartRate`, "must have at most 6 decimals");
        if (s.sleepMinutes && isNum(s.sleepMinutes.totalAsleep) && !decimalsOk(s.sleepMinutes.totalAsleep, 6)) bad2(`${p}.sleepMinutes`, "must have at most 6 decimals");
        if (s.restingHeartRate !== void 0 && !(isNum(s.restingHeartRate) && s.restingHeartRate > 0 && s.restingHeartRate <= 250)) {
          bad2(`${p}.restingHeartRate`, "must be a number between 0 and 250");
        }
        if (s.steps !== void 0 && !(isNum(s.steps) && s.steps >= 0)) bad2(`${p}.steps`, "must be a number >= 0");
        if (s.sleepMinutes !== void 0) {
          if (!isObj(s.sleepMinutes) || !(isNum(s.sleepMinutes.totalAsleep) && s.sleepMinutes.totalAsleep >= 0 && s.sleepMinutes.totalAsleep <= 1440)) {
            bad2(`${p}.sleepMinutes`, "must be an object with totalAsleep between 0 and 1440");
          }
        }
      });
    }
    if (Array.isArray(snapshot.dailySummaries)) {
      const byDate = /* @__PURE__ */ new Map();
      snapshot.dailySummaries.forEach((s, i) => {
        if (!isObj(s) || typeof s.date !== "string") return;
        const form = stable(s);
        if (byDate.has(s.date) && byDate.get(s.date) !== form) bad2(`dailySummaries[${i}]`, "conflicts with another summary for the same date");
        else byDate.set(s.date, form);
      });
    }
    if (!Array.isArray(snapshot.workouts)) bad2("workouts", "must be an array");
    else {
      snapshot.workouts.forEach((w, i) => {
        const p = `workouts[${i}]`;
        if (!isObj(w)) return bad2(p, "must be an object");
        if (typeof w.activityType !== "string" || !w.activityType) bad2(`${p}.activityType`, "must be a non-empty string");
        const okStart = validTimestamp(w.start);
        const okEnd = validTimestamp(w.end);
        if (!okStart) bad2(`${p}.start`, "must be an ISO 8601 timestamp with an offset and at most 3 fractional second digits");
        if (!okEnd) bad2(`${p}.end`, "must be an ISO 8601 timestamp with an offset and at most 3 fractional second digits");
        if (okStart && okEnd && parseTimestamp(w.end).ms < parseTimestamp(w.start).ms) bad2(`${p}.end`, "must not be before start");
        if (!(isNum(w.durationMin) && w.durationMin >= 0)) bad2(`${p}.durationMin`, "must be a number >= 0");
        if (isNum(w.effort) && !decimalsOk(w.effort, 2)) bad2(`${p}.effort`, "must have at most 2 decimals");
        if (w.effort !== void 0 && !(isNum(w.effort) && w.effort >= 1 && w.effort <= 10)) bad2(`${p}.effort`, "must be a number from 1 to 10");
        if (w.indoor !== void 0 && typeof w.indoor !== "boolean") bad2(`${p}.indoor`, "must be a boolean");
        if (w.heartRate !== void 0) {
          if (!isObj(w.heartRate) || !Object.values(w.heartRate).every(isNum)) bad2(`${p}.heartRate`, "must be an object of numbers");
        }
      });
    }
    if (Array.isArray(snapshot.workouts)) {
      const seen = /* @__PURE__ */ new Map();
      snapshot.workouts.forEach((w, i) => {
        if (!isObj(w) || parseTimestamp(w.start) === null) return;
        const key2 = `${w.activityType}|${parseTimestamp(w.start).ms}|${w.durationMin}`;
        const effort = w.effort === void 0 ? "none" : String(w.effort);
        if (seen.has(key2) && seen.get(key2) !== effort) bad2(`workouts[${i}]`, "conflicts with another workout of the same activity, instant and duration that has a different effort");
        else if (!seen.has(key2)) seen.set(key2, effort);
      });
    }
    if (snapshot.calendar !== void 0) {
      if (!isObj(snapshot.calendar) || !Array.isArray(snapshot.calendar.events)) bad2("calendar", "must be an object with an events array");
      else {
        snapshot.calendar.events.forEach((e, i) => {
          const p = `calendar.events[${i}]`;
          if (!isObj(e)) return bad2(p, "must be an object");
          if (typeof e.title !== "string" || !e.title.trim()) bad2(`${p}.title`, "must be a non-empty string");
          const okStart = validTimestamp(e.start);
          const okEnd = validTimestamp(e.end);
          if (!okStart) bad2(`${p}.start`, "must be an ISO 8601 timestamp with an offset and at most 3 fractional second digits");
          if (!okEnd) bad2(`${p}.end`, "must be an ISO 8601 timestamp with an offset and at most 3 fractional second digits");
          if (okStart && okEnd && parseTimestamp(e.end).ms <= parseTimestamp(e.start).ms) bad2(`${p}.end`, "must be after start");
        });
      }
    }
    if (snapshot.target !== void 0) {
      const t2 = isObj(snapshot.target) ? snapshot.target.workoutsPerWeek : void 0;
      if (!(isNum(t2) && t2 > 0 && Math.abs(t2 * 100 - Math.round(t2 * 100)) < 1e-9)) {
        bad2("target", "must be an object with workoutsPerWeek greater than 0 and at most 2 decimals");
      }
    }
    return { ok: errors.length === 0, errors };
  }

  // src/facts/types.mjs
  var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var FACT_TYPES = [
    { id: "history.thin", group: "history", keyed: null },
    { id: "coverage.28d", dependsOn: ["load.ratio", "volume.28d"], group: "coverage", keyed: null },
    { id: "volume.today", group: "volume", keyed: null },
    { id: "volume.today_so_far", group: "volume", keyed: null, variantOf: "volume.today" },
    { id: "volume.today_unlogged", group: "volume", keyed: null, variantOf: "volume.today" },
    { id: "volume.week", group: "volume", keyed: null },
    { id: "volume.28d", group: "volume", keyed: null },
    { id: "past.today_vs_avg", dependsOn: ["volume.today"], group: "past", keyed: null },
    { id: "past.today_vs_highest", dependsOn: ["volume.today"], group: "past", keyed: null },
    { id: "past.today_rank", dependsOn: ["volume.today"], group: "past", keyed: null },
    { id: "past.week_vs_avg", dependsOn: ["volume.week"], group: "past", keyed: null },
    { id: "past.week_rank", dependsOn: ["volume.week"], group: "past", keyed: null },
    { id: "past.week_comparisons_skipped", dependsOn: ["volume.week"], group: "past", keyed: null },
    { id: "load.ratio", dependsOn: ["volume.week", "volume.28d"], group: "load", keyed: null },
    { id: "regularity.days_since_last", dependsOn: ["volume.28d"], group: "regularity", keyed: null },
    { id: "regularity.longest_gap", group: "regularity", keyed: null },
    { id: "regularity.per_week", dependsOn: ["volume.week", "volume.28d"], group: "regularity", keyed: null },
    // Emitted ids are regularity.slot.<activityType>.<weekday>.<HH>; the key is "<activityType>.<weekday>.<HH>", for example "Running.Mon.07".
    { id: "regularity.slot", group: "regularity", keyed: { by: "activityType.weekday.hour", example: "Running.Mon.07" } },
    { id: "regularity.slots_none", group: "regularity", keyed: null, variantOf: "regularity.slot" },
    { id: "mix.count", dependsOn: ["volume.28d"], group: "mix", keyed: null },
    { id: "mix.median_length", dependsOn: ["volume.28d", "mix.count"], group: "mix", keyed: null },
    { id: "mix.start_bands", dependsOn: ["volume.28d", "mix.count"], group: "mix", keyed: null },
    { id: "body.sleep", group: "body", keyed: null },
    { id: "body.resting_hr", group: "body", keyed: null },
    { id: "goal.workouts_per_week", dependsOn: ["volume.week"], group: "goal", keyed: null },
    { id: "goal.target_progress", dependsOn: ["volume.week"], group: "goal", keyed: null }
  ];
  var FACT_TYPE_IDS = FACT_TYPES.map((t2) => t2.id);
  var FACT_TYPE_GROUPS = [...new Set(FACT_TYPES.map((t2) => t2.group))];
  var SUPPRESSED_ERROR = "suppressed lists an unknown fact type or key";
  var typeOf = (factId) => factId.startsWith("regularity.slot.") ? "regularity.slot" : factId;
  var matches = (type, id) => id === type || id.startsWith(`${type}.`);
  var DEPENDS_ON = Object.fromEntries(FACT_TYPES.filter((t2) => t2.dependsOn).map((t2) => [t2.id, t2.dependsOn]));
  var VARIANT_OF = Object.fromEntries(FACT_TYPES.filter((t2) => t2.variantOf).map((t2) => [t2.id, t2.variantOf]));
  var VALID_TYPES = new Set(FACT_TYPE_IDS.flatMap((id) => id.split(".").map((_, i, a) => a.slice(0, i + 1).join("."))));
  var SLOT_KEY = new RegExp(`^(${ACTIVITY_ALLOWLIST.filter((a) => a !== "Other").join("|")})\\.(${WEEKDAYS.join("|")})\\.([01]\\d|2[0-3])$`);
  var KEY_CHECKS = { "regularity.slot": (key2) => SLOT_KEY.test(key2) };
  function suppressionFilter(suppressed) {
    if (suppressed === void 0 || suppressed === null) return () => false;
    const fail = () => {
      throw new Error(SUPPRESSED_ERROR);
    };
    if (typeof suppressed !== "object" || Array.isArray(suppressed)) fail();
    for (const k of Object.keys(suppressed)) if (k !== "types" && k !== "keys") fail();
    const types = suppressed.types ?? [];
    const keys = suppressed.keys ?? [];
    if (!Array.isArray(types) || !Array.isArray(keys)) fail();
    for (const t2 of types) if (typeof t2 !== "string" || !VALID_TYPES.has(t2)) fail();
    for (const k of keys) {
      if (!k || typeof k !== "object" || Array.isArray(k) || typeof k.type !== "string" || typeof k.key !== "string") fail();
      for (const f of Object.keys(k)) if (f !== "type" && f !== "key") fail();
      const check = KEY_CHECKS[k.type];
      if (!check || !check(k.key)) fail();
    }
    const keyIds = new Set(keys.map((k) => `${k.type}.${k.key}`));
    const direct = (id) => keyIds.has(id) || types.some((t2) => matches(t2, id) || VARIANT_OF[id] !== void 0 && matches(t2, VARIANT_OF[id]));
    const suppressedId = (id) => direct(id) || (DEPENDS_ON[typeOf(id)] || []).some(suppressedId);
    return suppressedId;
  }

  // src/facts/compute.mjs
  var DAY_MS = 864e5;
  var WEEKDAYS2 = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var dayNum = (s) => {
    const [y, m, d] = s.slice(0, 10).split("-").map(Number);
    return Date.UTC(y, m - 1, d) / DAY_MS;
  };
  var dayIso = (n) => new Date(n * DAY_MS).toISOString().slice(0, 10);
  var MS_PER_MIN = 6e4;
  var mins = (x) => {
    const centi = Math.floor((Math.round(x * MS_PER_MIN) * 100 + MS_PER_MIN / 2) / MS_PER_MIN);
    const whole = Math.floor(centi / 100);
    const frac = centi % 100;
    return frac === 0 ? String(whole) : `${whole}.${frac < 10 ? "0" : ""}${frac % 10 === 0 ? frac / 10 : frac}`;
  };
  var pl = (n, w) => `${n} ${w}${n === 1 ? "" : "s"}`;
  var cmp2 = (a, b) => a < b ? -1 : a > b ? 1 : 0;
  var sum = (a) => a.reduce((s, v) => s + v, 0);
  function medianQ(ms) {
    const s = [...ms].sort((x, y) => x - y);
    const h = s.length >> 1;
    return s.length % 2 ? Q(s[h], MS_PER_MIN) : Q(s[h - 1] + s[h], 2 * MS_PER_MIN);
  }
  function resolveNow(now, snapshot) {
    if (typeof now === "string") {
      const p = parseTimestamp(now);
      if (!p) throw new Error("now must be an ISO 8601 timestamp with an offset and at most 3 fractional second digits");
      return { str: now, ms: p.ms };
    }
    const ms = now instanceof Date ? now.getTime() : NaN;
    if (Number.isNaN(ms)) throw new Error("now must be an ISO 8601 timestamp with an offset and at most 3 fractional second digits");
    const m = /(Z|([+-])(\d{2}):(\d{2}))$/.exec(snapshot.exportDate);
    const offMin = !m || m[1] === "Z" ? 0 : (m[2] === "-" ? -1 : 1) * (Number(m[3]) * 60 + Number(m[4]));
    return { str: new Date(ms + offMin * 6e4).toISOString().slice(0, 23) + (m ? m[1] : "Z"), ms };
  }
  var Q = (num, den = 1) => ({ num, den });
  var qCmp = (a, b) => Math.sign(a.num * b.den - b.num * a.den);
  var qDiv = (a, b) => Q(a.num * b.den, a.den * b.num);
  var qScaled = (q, d) => Math.floor((2 * Math.abs(q.num) * 10 ** d + q.den) / (2 * q.den));
  var fmtScaled = (s, d) => d === 0 ? String(s) : `${Math.floor(s / 10 ** d)}.${String(s % 10 ** d).padStart(d, "0")}`;
  var qFx = (q, d) => (q.num < 0 && qScaled(q, d) !== 0 ? "-" : "") + fmtScaled(qScaled(q, d), d);
  var qNum = (q, d) => Math.sign(q.num) * qScaled(q, d) / 10 ** d;
  var qMins = (q) => {
    const centi = qScaled(q, 2);
    const frac = centi % 100;
    return frac === 0 ? String(Math.floor(centi / 100)) : `${Math.floor(centi / 100)}.${frac < 10 ? "0" : ""}${frac % 10 === 0 ? frac / 10 : frac}`;
  };
  function compare(valueQ, baseQ) {
    const c = qCmp(valueQ, baseQ);
    return { dir: c === 0 ? "equal" : c > 0 ? "above" : "below", ratio: baseQ.num > 0 ? qDiv(valueQ, baseQ) : null, zero: valueQ.num === 0 };
  }
  var diffPhrase = (q, d, unit) => {
    const s = qScaled(q, d);
    return s === 0 ? `less than ${fmtScaled(1, d)}${unit}` : `${fmtScaled(s, d)}${unit}`;
  };
  var ratioText = (r) => r.num === 0 ? "0" : qScaled(r, 2) === 0 ? "less than 0.01" : qFx(r, 2);
  var pctAllowed = (c) => c.ratio !== null && !c.zero && c.ratio.num * 10 >= c.ratio.den && c.ratio.num <= 10 * c.ratio.den;
  var pctQ = (c) => Q(Math.abs(c.ratio.num - c.ratio.den) * 100, c.ratio.den);
  var pctTag = (c) => c.dir === "equal" ? "equal" : `${diffPhrase(pctQ(c), 1, "%")} ${c.dir}`;
  var cmpKind = (c) => c.ratio === null ? "undefined" : c.zero ? "zero" : "ratio";
  var qx = (q) => ({ num: q.num, den: q.den });
  var cmpNumbers = (c, exactExtra = {}) => ({
    ratio: c.ratio === null ? null : qNum(c.ratio, 2),
    percent: pctAllowed(c) ? qNum(pctQ(c), 1) : null,
    direction: c.dir,
    exact: { ...c.ratio === null ? {} : { ratio: qx(c.ratio) }, ...exactExtra }
  });
  function stable2(v) {
    if (Array.isArray(v)) return `[${v.map(stable2).join(",")}]`;
    if (v && typeof v === "object") return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable2(v[k])}`).join(",")}}`;
    return JSON.stringify(v);
  }
  var FORGOTTEN_ERROR = "forgottenDays lists a malformed date";
  function computeFacts(snapshot, now, options = {}) {
    const facts = computeFactsUnlinted(snapshot, now, options);
    for (const f of facts) {
      const problems = lintFact(f.text, { id: f.id });
      if (problems.length > 0) throw new Error(`fact failed lint: ${f.id}: ${problems.join(", ")}`);
    }
    return facts;
  }
  function computeFactsUnlinted(snapshot, now, options = {}) {
    const validation = validateSnapshot(snapshot);
    if (!validation.ok) throw new Error(`snapshot failed validation: ${validation.errors.join("; ")}`);
    const isSuppressed = suppressionFilter(options && options.suppressed);
    const { str: nowStr, ms: nowMs } = resolveNow(now, snapshot);
    const forgottenList = options && options.forgottenDays !== void 0 ? options.forgottenDays : [];
    if (!Array.isArray(forgottenList)) throw new Error(FORGOTTEN_ERROR);
    const forgot = new Set(
      forgottenList.map((d) => {
        if (typeof d !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(d)) throw new Error(FORGOTTEN_ERROR);
        const n = dayNum(d);
        if (dayIso(n) !== d) throw new Error(FORGOTTEN_ERROR);
        return n;
      })
    );
    const requested = options && options.dayMode !== void 0 ? options.dayMode : "auto";
    if (requested !== "auto" && requested !== "completed" && requested !== "in_progress") throw new Error("dayMode must be auto, completed or in_progress");
    const nowDate = dayNum(nowStr);
    const atMidnight = /^\d{4}-\d{2}-\d{2}T00:00(?::00(?:\.0+)?)?(?:Z|[+-]\d{2}:\d{2})$/.test(nowStr);
    const mode = requested === "auto" ? atMidnight ? "completed" : "in_progress" : requested;
    if (mode === "completed" && !atMidnight) throw new Error("dayMode completed needs now to be a local midnight");
    const liveDay = mode === "in_progress" ? nowDate : null;
    const today = nowDate - 1;
    const ended = (w) => {
      const s = parseTimestamp(w.start);
      const e = parseTimestamp(w.end);
      return s !== null && e !== null && s.ms <= nowMs && e.ms <= nowMs && dayNum(w.start) <= (liveDay ?? today);
    };
    const durMs = (w) => Number.isFinite(w.durationMin) && w.durationMin >= 0 ? Math.round(w.durationMin * MS_PER_MIN) : 0;
    const ordered = (snapshot.workouts || []).filter(ended).map((w) => ({ raw: w.activityType, type: ACTIVITY_ALLOWLIST.includes(w.activityType) ? w.activityType : "Other", ms: parseTimestamp(w.start).ms, day: dayNum(w.start), hour: Number(w.start.slice(11, 13)), dur: durMs(w), rawMs: w.durationMin * MS_PER_MIN, min: durMs(w) / MS_PER_MIN, effort: Number.isFinite(w.effort) && w.effort >= 1 && w.effort <= 10 ? Math.round(w.effort * 100) : null, start: w.start, end: w.end })).sort((a, b) => a.ms - b.ms || cmp2(a.raw, b.raw) || b.dur - a.dur || b.rawMs - a.rawMs || cmp2(a.start, b.start) || cmp2(a.end, b.end) || (a.effort ?? -1) - (b.effort ?? -1));
    const forgottenIdentities = /* @__PURE__ */ new Set();
    for (const w of snapshot.workouts || []) {
      const p = parseTimestamp(w.start);
      if (p !== null && forgot.has(dayNum(w.start))) forgottenIdentities.add(`${w.activityType}|${p.ms}`);
    }
    const seen = /* @__PURE__ */ new Set();
    const uniqueAll = ordered.filter((w) => {
      const key2 = `${w.raw}|${w.ms}`;
      if (forgottenIdentities.has(key2)) return false;
      if (seen.has(key2)) return false;
      seen.add(key2);
      return true;
    });
    const unique = uniqueAll.filter((w) => w.day <= today);
    const liveRecords = uniqueAll.filter((w) => w.day === liveDay);
    const loggedWorkoutDays = unique.map((w) => w.day);
    const isCounted = (w) => w.rawMs >= MIN_WORKOUT_MINUTES * MS_PER_MIN;
    const workouts = unique.filter(isCounted);
    const shortByDay = /* @__PURE__ */ new Map();
    for (const w of unique) if (!isCounted(w)) shortByDay.set(w.day, (shortByDay.get(w.day) || 0) + 1);
    const byDay = /* @__PURE__ */ new Map();
    for (const w of workouts) {
      if (!byDay.has(w.day)) byDay.set(w.day, []);
      byDay.get(w.day).push(w);
    }
    const exportMs = parseTimestamp(snapshot.exportDate)?.ms ?? NaN;
    const lookBack = exportMs > nowMs;
    const summaries = /* @__PURE__ */ new Map();
    for (const s of [...snapshot.dailySummaries || []].sort((x, y) => cmp2(stable2(x), stable2(y)))) {
      const d = dayNum(s.date);
      if (d <= today && !forgot.has(d) && !(lookBack && d >= today) && !summaries.has(d)) summaries.set(d, s);
    }
    const liveSummary = liveDay !== null && !lookBack && !forgot.has(liveDay) && (snapshot.dailySummaries || []).some((s) => dayNum(s.date) === liveDay);
    const logged = /* @__PURE__ */ new Set([...summaries.keys(), ...loggedWorkoutDays]);
    const nLogged = logged.size;
    const facts = [];
    const add = (id, group, window, text, numbers) => {
      if (!isSuppressed(id)) facts.push({ id, group, text, numbers, window });
    };
    if (nLogged < THIN_DAYS_NEEDED) {
      const spanDays = nLogged === 0 ? 0 : Math.max(...logged) - Math.min(...logged) + 1;
      add("history.thin", "history", `${spanDays}d`, `${pl(nLogged, "day")} of data; fewer than ${THIN_DAYS_NEEDED}.`, {
        daysOfData: nLogged,
        daysNeeded: THIN_DAYS_NEEDED,
        spanDays
      });
      return facts;
    }
    const first = Math.min(...logged);
    const spanBack = today - first;
    const dayMs2 = (d) => sum((byDay.get(d) || []).map((w) => w.dur));
    const dayMin = (d) => dayMs2(d) / MS_PER_MIN;
    const days = (a, b) => {
      const out = [];
      for (let k = b; k >= a; k--) out.push(today - k);
      return out;
    };
    const minutesIn = (a, b) => sum(days(a, b).map(dayMs2)) / MS_PER_MIN;
    const countIn = (a, b) => sum(days(a, b).map((d) => (byDay.get(d) || []).length));
    const shortIn = (a, b) => sum(days(a, b).map((d) => shortByDay.get(d) || 0));
    const shortNote = (n) => n > 0 ? `, ${n} under ${MIN_WORKOUT_MINUTES} minutes not counted` : "";
    const loggedIn = (a, b) => days(a, b).filter((d) => logged.has(d)).length;
    const loggedToday = logged.has(today);
    const l28 = loggedIn(0, 27);
    const l7 = loggedIn(0, 6);
    const D2 = dayIso(today);
    const todayMin = dayMin(today);
    const todayCount = countIn(0, 0);
    if (mode === "completed") {
      if (loggedToday) {
        add("volume.today", "volume", "day", `On ${D2}: ${pl(todayCount, "counted workout")} (${MIN_WORKOUT_MINUTES} minutes or more) and ${mins(todayMin)} workout minutes${shortNote(shortIn(0, 0))}.`, {
          date: D2,
          workouts: todayCount,
          minutes: todayMin,
          shortWorkouts: shortIn(0, 0)
        });
      } else {
        add("volume.today_unlogged", "volume", "day", `${D2} has no data: 0 of 1 days logged.`, { date: D2, loggedDays: 0, windowDays: 1 });
      }
    } else {
      const live = dayIso(liveDay);
      const liveCounted = liveRecords.filter(isCounted);
      const liveShort = liveRecords.length - liveCounted.length;
      const liveMin = sum(liveCounted.map((w) => w.dur)) / MS_PER_MIN;
      if (liveSummary || liveRecords.length > 0) {
        add("volume.today_so_far", "volume", "day", `So far today (${live}): ${pl(liveCounted.length, "counted workout")} (${MIN_WORKOUT_MINUTES} minutes or more) and ${mins(liveMin)} workout minutes, day not finished${shortNote(liveShort)}.`, {
          date: live,
          workouts: liveCounted.length,
          minutes: liveMin,
          shortWorkouts: liveShort,
          dayFinished: false
        });
      } else {
        add("volume.today_unlogged", "volume", "day", `${live} has no data so far: 0 of 1 days logged.`, { date: live, loggedDays: 0, windowDays: 1 });
      }
    }
    const m7 = minutesIn(0, 6);
    const c7 = countIn(0, 6);
    add("volume.week", "volume", "7d", `Counted in the last 7 days (${dayIso(today - 6)} to ${dayIso(today)}; workouts of ${MIN_WORKOUT_MINUTES} minutes or more): ${pl(c7, "workout")} and ${mins(m7)} workout minutes on ${pl(l7, "logged day")} (${pl(7 - l7, "unlogged day")})${shortNote(shortIn(0, 6))}.`, {
      from: dayIso(today - 6),
      to: dayIso(today),
      workouts: c7,
      minutes: m7,
      loggedDays: l7,
      unloggedDays: 7 - l7,
      shortWorkouts: shortIn(0, 6)
    });
    const m28 = minutesIn(0, 27);
    const c28 = countIn(0, 27);
    add("volume.28d", "volume", "28d", `Counted in the last 28 days (${dayIso(today - 27)} to ${dayIso(today)}; workouts of ${MIN_WORKOUT_MINUTES} minutes or more): ${pl(c28, "workout")} and ${mins(m28)} workout minutes on ${pl(l28, "logged day")} (${pl(28 - l28, "unlogged day")})${shortNote(shortIn(0, 27))}.`, {
      from: dayIso(today - 27),
      to: dayIso(today),
      workouts: c28,
      minutes: m28,
      loggedDays: l28,
      unloggedDays: 28 - l28,
      shortWorkouts: shortIn(0, 27)
    });
    const lPrev = loggedIn(1, 28);
    if (mode === "completed" && loggedToday && lPrev >= MIN_BASELINE_DAYS) {
      const sumPrev = sum(days(1, 28).map(dayMs2));
      const avgQ = Q(sumPrev, lPrev * MS_PER_MIN);
      const c = compare(Q(dayMs2(today)), Q(sumPrev, lPrev));
      const lead = `${mins(todayMin)} workout minutes on ${D2}`;
      const counts = pl(lPrev, "logged day");
      const kind = cmpKind(c);
      const text = kind === "undefined" ? `${lead}; the daily average over the previous 28 days is ${qFx(avgQ, 2)} minutes, so the ratio is not defined (${counts}).` : kind === "zero" ? `${lead}; the daily average over the previous 28 days is ${qFx(avgQ, 2)} minutes (ratio 0, ${counts}).` : `${lead}, ratio ${ratioText(c.ratio)} to the daily average of ${qFx(avgQ, 2)} minutes over the previous 28 days (${counts}${pctAllowed(c) ? `, ${pctTag(c)}` : ""}).`;
      add("past.today_vs_avg", "past", "day vs 28d", text, {
        minutes: todayMin,
        averageMinutesPerDay: qNum(avgQ, 2),
        ...cmpNumbers(c, { averageMinutesPerDay: qx(avgQ) }),
        loggedDays: lPrev
      });
      const prevMax = Math.max(...days(1, 28).map(dayMs2));
      if (prevMax > 0 && dayMs2(today) >= SPIKE_RATIO * prevMax) {
        const ratio = Q(dayMs2(today), prevMax);
        add("past.today_vs_highest", "past", "day vs 28d", `The workout minutes on ${D2} (${mins(todayMin)}) are ${qFx(ratio, 2)}x the highest recorded day of the previous 28 days (${mins(prevMax / MS_PER_MIN)}).`, {
          minutes: todayMin,
          highestPreviousDayMinutes: prevMax / MS_PER_MIN,
          ratio: qNum(ratio, 2),
          exact: { ratio: qx(ratio) },
          threshold: SPIKE_RATIO
        });
      }
    }
    if (mode === "completed" && loggedToday && dayMin(today) > 0) {
      const pool = days(0, 27).filter((d) => logged.has(d));
      const rank = 1 + pool.filter((d) => dayMin(d) > dayMin(today)).length;
      add("past.today_rank", "past", "28d", `The workout minutes on ${D2} (${mins(todayMin)}) rank ${rank} of ${pl(pool.length, "logged day")} in the last 28 days, where 1 is the highest.`, {
        minutes: todayMin,
        rank,
        of: pool.length
      });
    }
    const weekComplete = l7 === 7;
    const lBase = loggedIn(7, 34);
    const baseOk = lBase >= MIN_BASELINE_DAYS;
    const comparisonIds = ["past.week_vs_avg", "past.week_rank", "load.ratio", "goal.workouts_per_week", ...snapshot.target ? ["goal.target_progress"] : []];
    if (!weekComplete && comparisonIds.some((id) => !isSuppressed(id))) {
      add("past.week_comparisons_skipped", "past", "7d", `Comparisons of the last 7 days with earlier weeks or a target are not stated: only ${l7} of 7 days are logged.`, {
        loggedDays: l7,
        windowDays: 7
      });
    }
    if (weekComplete && baseOk) {
      const sumBase = sum(days(7, 34).map(dayMs2));
      const weekMs = sum(days(0, 6).map(dayMs2));
      const baseWeekQ = Q(sumBase * 7, lBase * MS_PER_MIN);
      const c = compare(Q(weekMs), Q(sumBase * 7, lBase));
      const lead = `${mins(m7)} workout minutes in the last 7 days`;
      const counts = `${pl(lBase, "logged day")} before this week`;
      const kind = cmpKind(c);
      const text = kind === "undefined" ? `${lead}; the 4-week average is ${qFx(baseWeekQ, 2)} minutes per week, so the ratio is not defined (${counts}).` : kind === "zero" ? `${lead}; the 4-week average is ${qFx(baseWeekQ, 2)} minutes per week (ratio 0, ${counts}).` : `${lead}, ratio ${ratioText(c.ratio)} to the 4-week average of ${qFx(baseWeekQ, 2)} minutes per week (${counts}${pctAllowed(c) ? `, ${pctTag(c)}` : ""}).`;
      add("past.week_vs_avg", "past", "7d vs 28d", text, {
        minutes: m7,
        averageMinutesPerWeek: qNum(baseWeekQ, 2),
        ...cmpNumbers(c, { averageMinutesPerWeek: qx(baseWeekQ) }),
        loggedDays: lBase
      });
    }
    const weeks = [];
    for (let j = 0; j < 12 && 7 * j + 6 <= spanBack; j++) {
      if (loggedIn(7 * j, 7 * j + 6) === 7) weeks.push({ j, m: minutesIn(7 * j, 7 * j + 6) });
    }
    if (weeks.length >= 2 && weeks[0].j === 0) {
      const rank = 1 + weeks.filter((w) => w.m > weeks[0].m).length;
      add("past.week_rank", "past", "84d", `This week's workout minutes (${mins(m7)}) rank ${rank} of ${pl(weeks.length, "complete 7-day week")} in the last 12 weeks, where 1 is the highest.`, {
        minutes: m7,
        rank,
        of: weeks.length
      });
    }
    if (weekComplete && l28 >= MIN_BASELINE_DAYS) {
      const w282 = workouts.filter((w) => today - w.day <= 27);
      const useEffort = w282.length > 0 && w282.every((w) => w.effort !== null);
      const unitDen = useEffort ? MS_PER_MIN * 100 : MS_PER_MIN;
      const load = (w) => useEffort ? w.effort * w.dur : w.dur;
      const L7 = sum(w282.filter((w) => today - w.day <= 6).map(load));
      const L28 = sum(w282.map(load));
      if (L28 > 0) {
        const c = compare(Q(L7), Q(L28 * 7, l28));
        const unit = useEffort ? "effort-minutes" : "minutes";
        add("load.ratio", "load", "7d vs 28d", `The ${useEffort ? "effort-weighted" : "minutes-based"} 7-day load is ${qMins(Q(L7, unitDen))} ${unit}, ratio ${ratioText(c.ratio)} to the 28-day weekly average of ${qFx(Q(L28 * 7, l28 * unitDen), 2)} ${unit} (${pl(l28, "logged day")}${pctAllowed(c) ? `, ${pctTag(c)}` : ""}).`, {
          basis: useEffort ? "effort" : "minutes",
          load7: L7 / unitDen,
          averagePerWeek28: qNum(Q(L28 * 7, l28 * unitDen), 2),
          ...cmpNumbers(c, { averagePerWeek28: qx(Q(L28 * 7, l28 * unitDen)) }),
          loggedDays: l28
        });
        if (!isSuppressed("coverage.28d")) facts.unshift({
          id: "coverage.28d",
          group: "coverage",
          text: `Data was logged on ${l28} of the last 28 days, so the 28-day load average uses ${pl(l28, "day")}.`,
          numbers: { loggedDays: l28, windowDays: 28 },
          window: "28d"
        });
      }
    }
    const inWindow = workouts.filter((w) => today - w.day <= 27);
    const lastDay = inWindow.length ? Math.max(...inWindow.map((w) => w.day)) : null;
    if (lastDay !== null) {
      const ago = today - lastDay;
      add("regularity.days_since_last", "regularity", "28d", `Days since the last counted workout (${MIN_WORKOUT_MINUTES} minutes or more) as of ${dayIso(today)}: ${ago} (${dayIso(lastDay)}); ${pl(c28, "counted workout")} in the last 28 days.`, {
        asOf: dayIso(today),
        daysSinceLast: ago,
        lastWorkoutDate: dayIso(lastDay),
        workouts28: c28
      });
    } else {
      add("regularity.days_since_last", "regularity", "28d", `No counted workout in the last 28 days as of ${dayIso(today)}: 0 workouts.`, {
        asOf: dayIso(today),
        daysSinceLast: null,
        lastWorkoutDate: null,
        workouts28: 0
      });
    }
    const gapLen = Math.min(27, spanBack) + 1;
    let run = 0;
    let gap = 0;
    let unlogged = 0;
    for (const d of days(0, gapLen - 1)) {
      if (!logged.has(d)) {
        unlogged++;
        run = 0;
      } else if (byDay.has(d)) run = 0;
      else gap = Math.max(gap, ++run);
    }
    add("regularity.longest_gap", "regularity", `${gapLen}d`, `Longest stretch of logged days without a counted workout (${MIN_WORKOUT_MINUTES} minutes or more) in the last ${gapLen} days: ${pl(gap, "day")} (${pl(unlogged, "unlogged day")} in the window).`, {
      gapDays: gap,
      windowDays: gapLen,
      unloggedDays: unlogged
    });
    const perWeek = [];
    const perWeekLogged = [];
    for (let j = 0; j < 4 && 7 * j + 6 <= spanBack; j++) {
      perWeek.push(countIn(7 * j, 7 * j + 6));
      perWeekLogged.push(loggedIn(7 * j, 7 * j + 6));
    }
    add(
      "regularity.per_week",
      "regularity",
      `${perWeek.length * 7}d`,
      // the days the blocks cover
      `Counted workouts (${MIN_WORKOUT_MINUTES} minutes or more) in each of the last ${perWeek.length} weeks (7-day blocks, most recent first): ${perWeek.join(", ")}; logged days in those weeks: ${perWeekLogged.join(", ")}.`,
      {
        perWeek,
        loggedDays: perWeekLogged
      }
    );
    const slots = /* @__PURE__ */ new Map();
    for (const w of workouts) {
      const k = today - w.day;
      if (k > 27) continue;
      const key2 = JSON.stringify([w.raw, new Date(w.day * DAY_MS).getUTCDay(), w.hour]);
      if (!slots.has(key2)) slots.set(key2, /* @__PURE__ */ new Set());
      slots.get(key2).add(Math.floor(k / 7));
    }
    const fixed = [...slots.entries()].filter(([, set]) => set.size >= 3).map(([key2, set]) => {
      const [raw, wd, hour] = JSON.parse(key2);
      return { type: raw, wd, hour, weeks: set.size };
    }).filter((s) => ACTIVITY_ALLOWLIST.includes(s.type) && s.type !== "Other").sort((a, b) => a.wd - b.wd || a.hour - b.hour || cmp2(a.type, b.type));
    if (fixed.length === 0) {
      add("regularity.slots_none", "regularity", "28d", "Fixed slots among recognised activities (same activity, weekday and hour in 3 of the last 4 weeks) found: 0.", { slots: 0 });
    }
    for (const s of fixed) {
      const hh = String(s.hour).padStart(2, "0");
      add(`regularity.slot.${s.type}.${WEEKDAYS2[s.wd]}.${hh}`, "regularity", "28d", `Fixed slot among recognised activities: ${activityLabels([s.type])[s.type]} on ${WEEKDAYS2[s.wd]} between ${hh}:00 and ${s.hour === 23 ? "00:00 the next day" : `${String(s.hour + 1).padStart(2, "0")}:00`}, in ${s.weeks} of the last 4 weeks.`, {
        activityType: s.type,
        weekday: WEEKDAYS2[s.wd],
        hour: s.hour,
        hourEnd: (s.hour + 1) % 24,
        endsNextDay: s.hour === 23,
        weeks: s.weeks
      });
    }
    const w28 = workouts.filter((w) => today - w.day <= 27);
    if (w28.length === 0) {
      add("mix.count", "mix", "28d", `No counted workouts (${MIN_WORKOUT_MINUTES} minutes or more) by activity in the last 28 days (0 workouts).`, { byActivity: {}, total: 0 });
    } else {
      const byType = /* @__PURE__ */ new Map();
      for (const w of w28) {
        if (!byType.has(w.type)) byType.set(w.type, []);
        byType.get(w.type).push(w);
      }
      const order = [...byType.entries()].sort((a, b) => b[1].length - a[1].length || (a[0] < b[0] ? -1 : 1));
      const label = activityLabels(order.map(([t2]) => t2));
      add("mix.count", "mix", "28d", `Counted workouts (${MIN_WORKOUT_MINUTES} minutes or more) by activity in the last 28 days: ${order.map(([t2, a]) => `${label[t2]} ${a.length}`).join(", ")}.`, {
        byActivity: Object.fromEntries(order.map(([t2, a]) => [t2, a.length])),
        total: w28.length
      });
      add("mix.median_length", "mix", "28d", `Median length of counted workouts (${MIN_WORKOUT_MINUTES} minutes or more) by activity in the last 28 days: ${order.map(([t2, a]) => `${label[t2]} ${qMins(medianQ(a.map((w) => w.dur)))} min`).join(", ")}.`, {
        medianMinutesByActivity: Object.fromEntries(order.map(([t2, a]) => [t2, qNum(medianQ(a.map((w) => w.dur)), 2)])),
        // 2 decimals, like the sentence
        exact: { medianMinutesByActivity: Object.fromEntries(order.map(([t2, a]) => [t2, qx(medianQ(a.map((w) => w.dur)))])) }
        // fractions of a minute
      });
      const band = (h) => h < 12 ? "morning" : h < 17 ? "afternoon" : "evening";
      const bands = { morning: 0, afternoon: 0, evening: 0 };
      for (const w of w28) bands[band(w.hour)]++;
      add("mix.start_bands", "mix", "28d", `Counted workout starts (${MIN_WORKOUT_MINUTES} minutes or more) in the last 28 days: morning ${bands.morning}, afternoon ${bands.afternoon}, evening ${bands.evening} (morning is before 12:00, evening from 17:00).`, bands);
    }
    const series = (pick, a, b) => days(a, b).map((d) => summaries.has(d) ? pick(summaries.get(d)) : void 0).filter((v) => Number.isFinite(v)).map((v) => Math.round(v * 1e6));
    const body = (id, label, unit, pick, d, U) => {
      const s7 = series(pick, 0, 6);
      const s28 = series(pick, 0, 27);
      if (s7.length < MIN_BODY_READINGS || s28.length < MIN_BODY_READINGS) return;
      const n7 = s7.length;
      const n28 = s28.length;
      const sum7 = sum(s7);
      const sum28 = sum(s28);
      const a7 = Q(sum7, n7 * U);
      const a28 = Q(sum28, n28 * U);
      const D3 = sum7 * n28 - sum28 * n7;
      const diff = Q(D3, n7 * n28 * U);
      const dir = D3 === 0 ? "equal" : D3 > 0 ? "above" : "below";
      const noun = id === "body.sleep" ? "nights" : "days with a reading";
      const text = `${label} over the last 7 days: ${qFx(a7, d)} ${unit} (from ${n7} ${noun}), ${dir === "equal" ? "equal to" : `${diffPhrase(diff, d, ` ${unit}`)} ${dir}`} the 28-day average of ${qFx(a28, d)} ${unit} (from ${n28} ${noun}).`;
      add(id, "body", "7d vs 28d", text, {
        average7: qNum(a7, d),
        average28: qNum(a28, d),
        difference: qNum(diff, d),
        direction: dir,
        exact: { average7: qx(a7), average28: qx(a28), difference: qx(diff) },
        logged7: n7,
        logged28: n28
      });
    };
    body("body.sleep", "Average sleep", "h", (s) => s.sleepMinutes ? s.sleepMinutes.totalAsleep : void 0, 2, 60 * 1e6);
    body("body.resting_hr", "Average resting heart rate", "bpm", (s) => s.restingHeartRate, 2, 1e6);
    if (weekComplete && baseOk) {
      const cnt = countIn(7, 34);
      const baseQ = Q(cnt * 7, lBase);
      const ratio = cnt > 0 ? Q(c7 * lBase, cnt * 7) : null;
      add("goal.workouts_per_week", "goal", "7d vs 28d", `${pl(c7, "counted workout")} (${MIN_WORKOUT_MINUTES} minutes or more) in the last 7 days; the baseline is ${qFx(baseQ, 2)} counted workouts per week over the 28 days before this week (${pl(lBase, "logged day")})${ratio === null ? "" : `, a ratio of ${qFx(ratio, 2)}`}.`, {
        workouts7: c7,
        baselineWorkoutsPerWeek: qNum(baseQ, 2),
        ratio: ratio === null ? null : qNum(ratio, 2),
        exact: { baselineWorkoutsPerWeek: qx(baseQ), ...ratio === null ? {} : { ratio: qx(ratio) } },
        loggedDays: lBase
      });
    }
    const targetCenti = snapshot.target && Number.isFinite(snapshot.target.workoutsPerWeek) ? Math.round(snapshot.target.workoutsPerWeek * 100) : 0;
    if (weekComplete && targetCenti > 0) {
      const ratio = Q(c7 * 100, targetCenti);
      const pctOk = c7 !== 0 && ratio.num * 10 >= ratio.den && ratio.num <= 10 * ratio.den;
      const pct = Q(c7 * 1e4, targetCenti);
      add("goal.target_progress", "goal", "7d", `Progress to the target of ${targetCenti / 100} workouts per week: ${pl(c7, "counted workout")} (${MIN_WORKOUT_MINUTES} minutes or more) in the last 7 days, ratio ${ratioText(ratio)} to the target${pctOk ? ` (${qFx(pct, 1)}% of the target)` : ""}.`, {
        target: targetCenti / 100,
        workouts7: c7,
        ratio: qNum(ratio, 2),
        exact: { ratio: qx(ratio) },
        percentOfTarget: pctOk ? qNum(pct, 1) : null
      });
    }
    return facts;
  }

  // src/memory/roll.mjs
  var DAY_MS2 = 864e5;
  var DAILY_KEPT = 28;
  var WEEKLY_KEPT = 12;
  var MIDNIGHT = /^\d{4}-\d{2}-\d{2}T00:00(?::00(?:\.0+)?)?(?:Z|[+-]\d{2}:\d{2})$/;
  var dayNum2 = (date) => Date.parse(`${date}T00:00:00Z`) / DAY_MS2;
  var dayIso2 = (n) => new Date(n * DAY_MS2).toISOString().slice(0, 10);
  var addDays2 = (date, n) => dayIso2(dayNum2(date) + n);
  var LABELS = { TraditionalStrengthTraining: "Strength training", FunctionalStrengthTraining: "Strength training", HighIntensityIntervalTraining: "HIIT" };
  var SAME = ["Running", "Walking", "Cycling", "Swimming", "Yoga", "Hiking", "Rowing", "Elliptical", "Pilates", "Dance"];
  var labelOf = (raw) => LABELS[raw] ?? (SAME.includes(raw) ? raw : "Other");
  function countedByDay(snapshot, nowMs, lastDay, forgotten) {
    const gone = new Set(forgotten);
    const days = /* @__PURE__ */ new Map();
    const seen = /* @__PURE__ */ new Set();
    for (const w of snapshot.workouts ?? []) {
      const start = parseTimestamp(w.start);
      const end = parseTimestamp(w.end);
      if (!start || !end || end.ms > nowMs || start.date > lastDay || gone.has(start.date)) continue;
      const id = `${w.activityType}|${start.ms}`;
      if (seen.has(id)) continue;
      seen.add(id);
      if (!(w.durationMin >= MIN_WORKOUT_MINUTES)) continue;
      const day = days.get(start.date) ?? /* @__PURE__ */ new Map();
      const label = labelOf(w.activityType);
      day.set(label, { minutes: (day.get(label)?.minutes ?? 0) + w.durationMin, count: (day.get(label)?.count ?? 0) + 1 });
      days.set(start.date, day);
    }
    return days;
  }
  function loggedDays(snapshot, lastDay, forgotten) {
    const out = /* @__PURE__ */ new Set();
    for (const s of snapshot.dailySummaries ?? []) if (s.date <= lastDay) out.add(s.date);
    for (const w of snapshot.workouts ?? []) {
      const p = parseTimestamp(w.start);
      if (p && p.date <= lastDay) out.add(p.date);
    }
    for (const d of forgotten) out.delete(d);
    return out;
  }
  function engineSuppression(sup) {
    const types = /* @__PURE__ */ new Set();
    for (const t2 of sup.types) {
      for (const id of Object.keys(COMPUTED)) if (COMPUTED[id] === t2) types.add(id);
      if (t2 === "mix") types.add("mix");
    }
    return { types: [...types].sort(), keys: [] };
  }
  var NOT_STORED = ["volume.28d", "mix.median_length", "mix.start_bands", "regularity.per_week", "regularity.longest_gap", "regularity.slots_none", "past.today_rank"];
  var storeType = (id) => id.startsWith("regularity.slot.") ? "regularity" : COMPUTED[id];
  var stored = (f, types) => !NOT_STORED.includes(f.id) && types.includes(storeType(f.id));
  var bySlot = (a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
  function dailyLines(days, lastDay, skip) {
    const out = [];
    for (let n = dayNum2(lastDay) - (DAILY_KEPT - 1); n <= dayNum2(lastDay); n++) {
      const date = dayIso2(n);
      const day = days.get(date);
      if (!day || skip.day(date)) continue;
      const items = [...day].map(([activity, v]) => ({ activity, minutes: Math.max(1, Math.round(v.minutes)) }));
      out.push(F.daily({ date, items }));
    }
    return out;
  }
  function weeklyLines(days, logged, lastDay, skip, within, forgotten) {
    const out = [];
    let monday = addDays2(lastDay, -(((/* @__PURE__ */ new Date(`${lastDay}T00:00:00Z`)).getUTCDay() + 6) % 7));
    if (addDays2(monday, 6) > lastDay) monday = addDays2(monday, -7);
    for (let i = 0; i < WEEKLY_KEPT; i++, monday = addDays2(monday, -7)) {
      const dates = Array.from({ length: 7 }, (_, k) => addDays2(monday, k));
      if (!dates.every((d) => logged.has(d) || forgotten.includes(d)) || skip.week(monday)) continue;
      const cells = dates.flatMap((d) => [...(days.get(d) ?? /* @__PURE__ */ new Map()).values()]);
      out.push(F.weekly({ weekStart: monday, count: cells.reduce((n, c) => n + c.count, 0), minutes: Math.round(cells.reduce((n, c) => n + c.minutes, 0)), excludedDays: within(monday, addDays2(monday, 6)) }));
    }
    return out;
  }
  function mixLine(days, lastDay, skip) {
    const lo = addDays2(lastDay, -27);
    const counts = /* @__PURE__ */ new Map();
    for (let n = dayNum2(lo); n <= dayNum2(lastDay); n++) {
      for (const [activity, v] of days.get(dayIso2(n)) ?? []) counts.set(activity, (counts.get(activity) ?? 0) + v.count);
    }
    const items = [...counts].filter(([activity]) => !skip.mix(activity)).map(([activity, count]) => ({ activity, count }));
    return { items, workouts: [...counts.values()].reduce((a, b) => a + b, 0), lo };
  }
  function rollDay({ store, snapshot, now, mode = "auto" } = {}) {
    const wrote = [];
    try {
      const midnight = MIDNIGHT.test(now);
      const dayMode = mode === "auto" ? midnight ? "completed" : "in_progress" : mode;
      const sup = suppressedTypes(store);
      const forgotten = sup.days;
      const facts = computeFacts(snapshot, now, { suppressed: engineSuppression(sup), forgottenDays: forgotten, dayMode });
      const nowIso = new Date(parseTimestamp(now).ms).toISOString();
      const lastDay = dayMode === "completed" ? addDays2(now.slice(0, 10), -1) : now.slice(0, 10);
      const within = (lo, hi) => forgotten.filter((d) => d >= lo && d <= hi);
      const computed = (f) => F.computed({ id: f.id, text: f.text, excludedDays: forgotten });
      const skip = {
        kind: (k) => sup.types.includes(k),
        day: (d) => forgotten.includes(d),
        week: (d) => sup.keys.some((k) => k.type === "weekly" && k.key === d),
        mix: (a) => sup.keys.some((k) => k.type === "mix" && k.key === a)
      };
      const put = (kind, list2, sources2) => {
        if (store.kindSuppressed(kind)) return true;
        if (!store.replaceFacts(kind, list2, sources2)) throw new Error(store.lastError ?? `could not write ${kind}`);
        wrote.push(kind);
        return true;
      };
      if (dayMode === "in_progress") {
        const today = facts.filter((f) => stored(f, ["today"])).map(computed);
        if (today.length === 0) return { ok: true, mode: dayMode, day: lastDay, wrote };
        const doc = store.read("rolling");
        put("rolling", [...(doc?.facts ?? []).filter((f) => f.kind !== "today"), ...today], doc?.sources ?? [S.roll({ date: lastDay, at: nowIso })]);
        return { ok: true, mode: dayMode, day: lastDay, wrote };
      }
      const sources = [S.roll({ date: lastDay, at: nowIso })];
      if (facts.length > 0 && facts[0].id === "history.thin") {
        const days2 = facts[0].numbers.daysOfData;
        put("rolling", skip.kind("thin") ? [] : [F.thin({ days: days2, endDate: lastDay, excludedDays: within("0000-01-01", lastDay) })], sources);
        put("profile", [], sources);
        return { ok: true, mode: dayMode, day: lastDay, thin: days2 < THIN_DAYS_NEEDED, wrote };
      }
      const days = countedByDay(snapshot, parseTimestamp(now).ms, lastDay, forgotten);
      const logged = loggedDays(snapshot, lastDay, forgotten);
      const volume28 = facts.find((f) => f.id === "volume.28d");
      const mix = mixLine(days, lastDay, skip);
      const fresh = [
        ...skip.kind("daily") ? [] : dailyLines(days, lastDay, skip),
        ...skip.kind("weekly") ? [] : weeklyLines(days, logged, lastDay, skip, within, forgotten)
      ];
      const have = new Set(fresh.map((f) => f.key));
      const kept = (store.read("rolling")?.facts ?? []).filter((f) => (f.kind === "daily" || f.kind === "weekly") && !have.has(f.key) && !(f.kind === "daily" ? skip.day(f.key.slice(6)) : skip.week(f.key.slice(7))));
      const history = [...fresh, ...kept];
      const latest = (kind, n) => history.filter((f) => f.kind === kind).sort(bySlot).slice(-n);
      const rolling = [
        ...latest("daily", DAILY_KEPT),
        ...latest("weekly", WEEKLY_KEPT),
        ...facts.filter((f) => stored(f, ["today", "week"])).map(computed),
        // Days with at least one counted workout (a day with only a daily summary is not one).
        ...volume28 && !skip.kind("coverage") ? [F.coverage({ workoutDays: [...days.keys()].filter((d) => d >= addDays2(lastDay, -27) && d <= lastDay).length, windowDays: 28, endDate: lastDay, excludedDays: within(addDays2(lastDay, -27), lastDay) })] : []
      ];
      put("rolling", rolling, sources);
      const profile = [
        ...facts.filter((f) => stored(f, ["load", "regularity", "body"])).map(computed),
        ...skip.kind("profile") ? [] : [F.profile({ workouts: mix.workouts, asOf: lastDay, validUntil: addDays2(lastDay, 1), excludedDays: within(mix.lo, lastDay) })],
        ...skip.kind("mix") || mix.items.length === 0 ? [] : [F.mix({ items: mix.items, asOf: lastDay, excludedDays: within(mix.lo, lastDay) })]
      ];
      put("profile", profile, sources);
      return { ok: true, mode: dayMode, day: lastDay, thin: false, wrote };
    } catch (e) {
      return { ok: false, error: String(e && e.message ? e.message : e), wrote };
    }
  }

  // src/memory/planner-text.mjs
  var DAILY_SHOWN = 7;
  var WEEKLY_SHOWN = 12;
  var TARGET_WORDS = 450;
  var MAX_WORDS = 600;
  var words = (text) => text.split(/\s+/).filter(Boolean).length;
  var lines = (facts) => facts.map((f) => `- ${f.text}`);
  function plannerText(store) {
    try {
      if (!recover(store).ok) return { ok: false, error: "memory is not available: a half-finished change is pending" };
      const files = {};
      for (const name of Object.keys(FILE_KINDS)) {
        const doc = store.read(name);
        if (doc !== null) files[name] = canonicalOrder(name, doc.facts, []).facts;
      }
      const render = (nDaily2, nWeekly2) => {
        const out = ["Memory facts (counts and dates only)"];
        for (const name of ["profile", "preferences"]) {
          if (files[name]) out.push(`## ${FILE_KINDS[name].path} (${files[name].length} facts)`, ...lines(files[name]));
        }
        const roll = files.rolling;
        if (roll) {
          const daily = roll.filter((f) => f.kind === "daily");
          const weekly = roll.filter((f) => f.kind === "weekly");
          const rest = roll.filter((f) => f.kind !== "daily" && f.kind !== "weekly");
          const left = { daily: daily.length - Math.min(nDaily2, daily.length), weekly: weekly.length - Math.min(nWeekly2, weekly.length) };
          out.push(
            `## ${FILE_KINDS.rolling.path} (${roll.length} facts)`,
            ...lines(weekly.slice(left.weekly)),
            ...lines(daily.slice(left.daily)),
            ...lines(rest),
            `- ${FILE_KINDS.rolling.path}: ${left.daily} earlier daily lines and ${left.weekly} earlier weekly lines not shown`
          );
          render.left = left;
        }
        const others = ["feedback", "history"].filter((n) => files[n]);
        if (others.length) out.push(`## Other memory files (${others.length} files)`, ...others.map((n) => `- ${FILE_KINDS[n].path}: ${files[n].length} facts`));
        return out.join("\n");
      };
      let nDaily = DAILY_SHOWN;
      let nWeekly = WEEKLY_SHOWN;
      let text = render(nDaily, nWeekly);
      while (words(text) > MAX_WORDS && (nDaily > 0 || nWeekly > 0)) {
        if (nDaily > 0) nDaily--;
        else nWeekly--;
        text = render(nDaily, nWeekly);
      }
      if (words(text) > MAX_WORDS) return { ok: false, error: "memory text is too long even without rolling lines" };
      return { ok: true, text, words: words(text), targetMet: words(text) <= TARGET_WORDS, leftOut: render.left ?? { daily: 0, weekly: 0 } };
    } catch (e) {
      return { ok: false, error: String(e && e.name ? e.name : "Error") };
    }
  }

  // src/amplitude/sha256.mjs
  var K = new Uint32Array([
    1116352408,
    1899447441,
    3049323471,
    3921009573,
    961987163,
    1508970993,
    2453635748,
    2870763221,
    3624381080,
    310598401,
    607225278,
    1426881987,
    1925078388,
    2162078206,
    2614888103,
    3248222580,
    3835390401,
    4022224774,
    264347078,
    604807628,
    770255983,
    1249150122,
    1555081692,
    1996064986,
    2554220882,
    2821834349,
    2952996808,
    3210313671,
    3336571891,
    3584528711,
    113926993,
    338241895,
    666307205,
    773529912,
    1294757372,
    1396182291,
    1695183700,
    1986661051,
    2177026350,
    2456956037,
    2730485921,
    2820302411,
    3259730800,
    3345764771,
    3516065817,
    3600352804,
    4094571909,
    275423344,
    430227734,
    506948616,
    659060556,
    883997877,
    958139571,
    1322822218,
    1537002063,
    1747873779,
    1955562222,
    2024104815,
    2227730452,
    2361852424,
    2428436474,
    2756734187,
    3204031479,
    3329325298
  ]);
  function utf8(str) {
    const out = [];
    for (let i = 0; i < str.length; i += 1) {
      let c = str.charCodeAt(i);
      if (c >= 55296 && c < 56320 && i + 1 < str.length) {
        c = 65536 + (c - 55296 << 10) + (str.charCodeAt(i + 1) - 56320);
        i += 1;
      }
      if (c < 128) out.push(c);
      else if (c < 2048) out.push(192 | c >> 6, 128 | c & 63);
      else if (c < 65536) out.push(224 | c >> 12, 128 | c >> 6 & 63, 128 | c & 63);
      else out.push(240 | c >> 18, 128 | c >> 12 & 63, 128 | c >> 6 & 63, 128 | c & 63);
    }
    return out;
  }
  var rotr = (x, n) => x >>> n | x << 32 - n;
  function sha256Hex(str) {
    const bytes = utf8(str);
    const bitLen = bytes.length * 8;
    bytes.push(128);
    while (bytes.length % 64 !== 56) bytes.push(0);
    const hi = Math.floor(bitLen / 4294967296);
    const lo = bitLen >>> 0;
    for (const word of [hi, lo]) bytes.push(word >>> 24 & 255, word >>> 16 & 255, word >>> 8 & 255, word & 255);
    const h = new Uint32Array([1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225]);
    const w = new Uint32Array(64);
    for (let off = 0; off < bytes.length; off += 64) {
      for (let i = 0; i < 16; i += 1) {
        const j = off + i * 4;
        w[i] = bytes[j] << 24 | bytes[j + 1] << 16 | bytes[j + 2] << 8 | bytes[j + 3];
      }
      for (let i = 16; i < 64; i += 1) {
        const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ w[i - 15] >>> 3;
        const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ w[i - 2] >>> 10;
        w[i] = w[i - 16] + s0 + w[i - 7] + s1 >>> 0;
      }
      let [a, b, c, d, e, f, g, hh] = h;
      for (let i = 0; i < 64; i += 1) {
        const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        const ch = e & f ^ ~e & g;
        const t1 = hh + S1 + ch + K[i] + w[i] >>> 0;
        const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        const maj = a & b ^ a & c ^ b & c;
        const t2 = S0 + maj >>> 0;
        hh = g;
        g = f;
        f = e;
        e = d + t1 >>> 0;
        d = c;
        c = b;
        b = a;
        a = t1 + t2 >>> 0;
      }
      h[0] += a;
      h[1] += b;
      h[2] += c;
      h[3] += d;
      h[4] += e;
      h[5] += f;
      h[6] += g;
      h[7] += hh;
    }
    return Array.from(h, (x) => x.toString(16).padStart(8, "0")).join("");
  }

  // src/amplitude/events.mjs
  var MIN_WORKOUT_MIN = 10;
  var EVENTS = Object.freeze({
    workout_completed: ["activity", "minutes", "weekday", "hour", "source", "rec_id", "supersedes", "occurrence_id", "local_date", "local_week", "utc_offset_minutes"],
    workout_retracted: ["occurrence_id", "utc_offset_minutes"],
    workout_missed: ["activity", "planned_weekday", "planned_hour"],
    recommendation_shown: ["rec_id", "activity", "minutes", "weekday", "hour", "framing"],
    recommendation_accepted: ["rec_id", "activity", "weekday", "hour"],
    recommendation_declined: ["rec_id", "activity", "weekday", "hour", "reason"],
    comeback_accepted: ["rec_id", "minutes"],
    recommendation_outcome: ["rec_id", "outcome"],
    memory_rolled: ["daily_lines", "weekly_lines", "preferences", "prompt_words"],
    preference_learned: ["reason", "times_said"]
  });
  var REASONS2 = Object.freeze(["too_early", "too_late", "too_long", "too_hard", "not_today"]);
  var ACTIVITIES2 = Object.freeze([
    "Running",
    "Walking",
    "Cycling",
    "Hiking",
    "Swimming",
    "Rowing",
    "Elliptical",
    "StairClimbing",
    "Yoga",
    "Pilates",
    "Dance",
    "CoreTraining",
    "Flexibility",
    "MixedCardio",
    "FunctionalStrengthTraining",
    "TraditionalStrengthTraining",
    "HighIntensityIntervalTraining",
    "Boxing",
    "Tennis",
    "Soccer",
    "Basketball",
    "Golf",
    "Skiing",
    "Climbing",
    "Other"
  ]);
  var compact = (t2) => String(t2).toLowerCase().replace(/[^a-z0-9]/g, "");
  var ALIASES = new Map([
    ...ACTIVITIES2.map((n) => [compact(n), n]),
    ["hiit", "HighIntensityIntervalTraining"],
    ["strengthtraining", "TraditionalStrengthTraining"]
  ]);
  var FRAMINGS = Object.freeze(["none", "neutral", "baseline", "streak", "comeback", "rank"]);
  var WEEKDAYS3 = Object.freeze(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]);
  var OUTCOMES = Object.freeze(["completed", "not_completed"]);
  var SOURCES2 = Object.freeze(["mock", "phone", "watch", "manual"]);
  var OPAQUE = /^(usr|rec|occ)_[0-9a-f]{8,32}$/;
  var ID_PREFIXES = Object.freeze(["usr", "rec", "occ"]);
  function hostHmac(host, label, data) {
    const secret = host?.secret;
    if (typeof host?.hmac !== "function") throw new Error("host hmac is required");
    if (typeof secret !== "string" || secret.length < 16) throw new Error("TRACKER_ID_SECRET is not set or too short");
    const out = host.hmac(secret, `${label}\0${data}`);
    if (typeof out !== "string" || !/^[0-9a-f]{64}$/.test(out)) throw new Error("host hmac failed");
    return out;
  }
  function opaqueId(prefix, seed, host) {
    if (!ID_PREFIXES.includes(prefix)) throw new Error("unknown id prefix");
    if (typeof seed !== "string" || seed.length === 0) throw new Error("id seed must be a non-empty string");
    return `${prefix}_${hostHmac(host, prefix, seed).slice(0, 16)}`;
  }
  var INSIDE = (list2) => (v) => typeof v === "string" && list2.includes(v);
  var NUM = (lo, hi) => (v) => typeof v === "number" && Number.isFinite(v) && v >= lo && v <= hi;
  var INT = (lo, hi) => (v) => Number.isInteger(v) && v >= lo && v <= hi;
  var idOf = (prefix) => (v) => typeof v === "string" && OPAQUE.test(v) && v.startsWith(`${prefix}_`);
  function parseDate(v) {
    const m = typeof v === "string" && /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
    if (!m) return null;
    const ms = Date.UTC(+m[1], +m[2] - 1, +m[3]);
    return new Date(ms).toISOString().slice(0, 10) === v ? ms : null;
  }
  var WEEKDAY_OF = (ms) => WEEKDAYS3[(new Date(ms).getUTCDay() + 6) % 7];
  var mondayOf = (ms) => new Date(ms - (new Date(ms).getUTCDay() + 6) % 7 * 864e5).toISOString().slice(0, 10);
  function checkRetractionTime(props, timeMs) {
    if (timeMs % 6e4 !== 0 || ((timeMs + props.utc_offset_minutes * 6e4) % 36e5 + 36e5) % 36e5 !== 0) {
      throw new Error("workout time fields disagree");
    }
  }
  function checkWorkoutTime(props, timeMs) {
    const dayMs2 = parseDate(props.local_date);
    if (dayMs2 === null || props.weekday !== WEEKDAY_OF(dayMs2) || props.local_week !== mondayOf(dayMs2) || timeMs !== dayMs2 + props.hour * 36e5 - props.utc_offset_minutes * 6e4) {
      throw new Error("workout time fields disagree");
    }
  }
  var twoDecimals = (v) => Math.round(v * 100) / 100 === v;
  var REQUIRED = Object.freeze({
    workout_completed: ["activity", "minutes", "weekday", "hour", "occurrence_id", "local_date", "local_week", "utc_offset_minutes"],
    workout_retracted: ["occurrence_id", "utc_offset_minutes"],
    workout_missed: ["activity", "planned_weekday", "planned_hour"],
    recommendation_shown: ["rec_id", "activity", "weekday", "hour", "framing"],
    recommendation_accepted: ["rec_id", "activity"],
    recommendation_declined: ["rec_id", "activity", "reason"],
    comeback_accepted: ["rec_id", "minutes"],
    recommendation_outcome: ["rec_id", "outcome"],
    memory_rolled: ["daily_lines", "weekly_lines", "preferences", "prompt_words"],
    preference_learned: ["reason", "times_said"]
  });
  var RULES = {
    activity: INSIDE(ACTIVITIES2),
    planned_weekday: INSIDE(WEEKDAYS3),
    weekday: INSIDE(WEEKDAYS3),
    planned_hour: INT(0, 23),
    hour: INT(0, 23),
    minutes: (v) => NUM(0, 1440)(v) && twoDecimals(v),
    framing: INSIDE(FRAMINGS),
    reason: INSIDE(REASONS2),
    source: INSIDE(SOURCES2),
    rec_id: idOf("rec"),
    supersedes: idOf("occ"),
    occurrence_id: idOf("occ"),
    local_date: (v) => parseDate(v) !== null,
    local_week: (v) => parseDate(v) !== null,
    utc_offset_minutes: INT(-840, 840),
    outcome: INSIDE(OUTCOMES),
    daily_lines: INT(0, 1e4),
    weekly_lines: INT(0, 1e4),
    preferences: INT(0, 1e4),
    prompt_words: INT(0, 1e5),
    times_said: INT(1, 1e4)
  };
  function cleanProps(name, props) {
    if (props !== void 0 && props !== null && (typeof props !== "object" || Array.isArray(props))) {
      throw new Error("event properties must be an object");
    }
    const allowed = new Set(EVENTS[name]);
    const kept = {};
    for (const k of Object.keys(props || {}).sort()) {
      if (!allowed.has(k) || props[k] === void 0) continue;
      if (!RULES[k](props[k])) throw new Error(`invalid value for property ${k}`);
      kept[k] = props[k];
    }
    for (const k of REQUIRED[name]) {
      if (!Object.hasOwn(kept, k)) throw new Error(`missing required property ${k}`);
    }
    return kept;
  }
  function checkUser(userId) {
    if (!idOf("usr")(userId)) throw new Error("user id must be opaque: usr_ and 8 to 32 lowercase hex");
  }
  function checkOccurrence(id) {
    if (!idOf("occ")(id)) throw new Error("occurrence id must be opaque: occ_ and 8 to 32 lowercase hex");
  }
  function insertIdOf(userId, name, occurrenceId) {
    return sha256Hex(JSON.stringify([userId, name, occurrenceId])).slice(0, 32);
  }
  function sanitizeEvent(e) {
    if (!e || typeof e !== "object" || Array.isArray(e)) throw new Error("event must be an object");
    if (typeof e.event_type !== "string" || !Object.hasOwn(EVENTS, e.event_type)) throw new Error("unknown event type");
    checkUser(e.user_id);
    if (!Number.isSafeInteger(e.time) || e.time <= 0) throw new Error("invalid event time");
    if (typeof e.insert_id !== "string" || !/^[0-9a-f]{32}$/.test(e.insert_id)) throw new Error("invalid insert_id");
    const props = cleanProps(e.event_type, e.event_properties);
    if (props.occurrence_id !== void 0 && e.insert_id !== insertIdOf(e.user_id, e.event_type, props.occurrence_id)) {
      throw new Error("insert_id does not match the occurrence");
    }
    if (props.supersedes !== void 0 && props.supersedes === props.occurrence_id) throw new Error("an event cannot supersede itself");
    if (e.event_type === "workout_completed") checkWorkoutTime(props, e.time);
    if (e.event_type === "workout_retracted") checkRetractionTime(props, e.time);
    return { user_id: e.user_id, event_type: e.event_type, time: e.time, event_properties: props, insert_id: e.insert_id };
  }
  function buildEvent(name, userId, date, props, occurrenceId) {
    if (typeof name !== "string" || !Object.hasOwn(EVENTS, name)) throw new Error("unknown event type");
    checkUser(userId);
    checkOccurrence(occurrenceId);
    if (props && typeof props === "object" && props.supersedes === occurrenceId) throw new Error("an event cannot supersede itself");
    const at = date instanceof Date ? date : new Date(date);
    if (Number.isNaN(at.getTime())) throw new Error("invalid event time");
    let given = props;
    if ((name === "workout_completed" || name === "workout_retracted") && given && typeof given === "object" && !Array.isArray(given)) {
      if (given.occurrence_id !== void 0 && given.occurrence_id !== occurrenceId) throw new Error("occurrence_id does not match the occurrence");
      given = { ...given, occurrence_id: occurrenceId };
    }
    const kept = cleanProps(name, given);
    if (name === "workout_completed") checkWorkoutTime(kept, at.getTime());
    if (name === "workout_retracted") checkRetractionTime(kept, at.getTime());
    const insertId = insertIdOf(userId, name, occurrenceId);
    return {
      user_id: userId,
      event_type: name,
      time: at.getTime(),
      event_properties: kept,
      insert_id: insertId
    };
  }
  var DAYS2 = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  function canonicalActivity(type) {
    return typeof type === "string" ? ALIASES.get(compact(type)) ?? "Other" : "Other";
  }
  function instant(iso) {
    const m = typeof iso === "string" && /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)(Z|[+-]\d{2}(?::?\d{2})?)$/i.exec(iso);
    if (!m) throw new Error("invalid workout time");
    let zone = m[3].toUpperCase();
    if (zone !== "Z") zone = zone.length === 3 ? `${zone}:00` : zone.length === 5 ? `${zone.slice(0, 3)}:${zone.slice(3)}` : zone;
    const ms = Date.parse(`${m[1]}T${m[2]}${zone}`);
    if (Number.isNaN(ms)) throw new Error("invalid workout time");
    const offsetMin = zone === "Z" ? 0 : (zone[0] === "-" ? -1 : 1) * (Number(zone.slice(1, 3)) * 60 + Number(zone.slice(4, 6)));
    return { ms, offsetMin };
  }
  function floorToLocalHour({ ms, offsetMin }) {
    const off = offsetMin * 6e4;
    const local = ms + off;
    return local - (local % 36e5 + 36e5) % 36e5 - off;
  }
  function wallClock(iso) {
    const m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2})/.exec(iso);
    const day = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).getUTCDay();
    return { weekday: DAYS2[day], hour: +m[4] };
  }
  var contentHash = (host, startMs, endMs, p) => hostHmac(
    host,
    "content",
    JSON.stringify([startMs, endMs, p.activity, p.minutes, p.weekday, p.hour, p.source, p.utc_offset_minutes])
  ).slice(0, 16);
  function newSent(userId) {
    checkUser(userId);
    return { user: userId, workouts: {}, forgotten: [], tombstones: [] };
  }
  var SENT_FIELDS = ["user", "workouts", "forgotten", "tombstones"];
  var MAX_FORGOTTEN = 2e4;
  var ENTRY_FIELDS = ["hash", "occurrence_id", "version", "day", "prior", "time", "offset", "live"];
  function checkSent(sent, userId) {
    if (!sent || typeof sent !== "object" || Array.isArray(sent) || !sent.workouts || typeof sent.workouts !== "object" || Array.isArray(sent.workouts)) {
      throw new Error("sent must be a map made by newSent");
    }
    if (Object.keys(sent).some((k) => !SENT_FIELDS.includes(k))) throw new Error("sent has an unknown field");
    if (sent.user !== userId) throw new Error("sent belongs to another user");
    const workouts = {};
    for (const k of Object.keys(sent.workouts)) {
      const v = sent.workouts[k];
      if (!idOf("occ")(k) || !v || typeof v !== "object" || Array.isArray(v) || !/^[0-9a-f]{16}$/.test(v.hash) || !idOf("occ")(v.occurrence_id) || !Number.isInteger(v.version) || v.version < 1 || !/^\d{4}-\d{2}-\d{2}$/.test(v.day) || !Number.isSafeInteger(v.time) || !Number.isInteger(v.offset) || v.offset < -840 || v.offset > 840 || typeof v.live !== "boolean") {
        throw new Error("sent has an invalid entry");
      }
      if (Object.keys(v).some((f) => !ENTRY_FIELDS.includes(f))) throw new Error("sent has an unknown field");
      const prior = v.prior === void 0 ? [] : v.prior;
      if (!Array.isArray(prior) || prior.length > 1e3 || prior.some((d) => parseDate(d) === null)) throw new Error("sent has an invalid entry");
      workouts[k] = { hash: v.hash, occurrence_id: v.occurrence_id, version: v.version, day: v.day, prior: [...new Set(prior)].sort(), time: v.time, offset: v.offset, live: v.live };
    }
    const rawForgotten = sent.forgotten === void 0 ? [] : sent.forgotten;
    if (!Array.isArray(rawForgotten) || rawForgotten.length > MAX_FORGOTTEN || rawForgotten.some((d) => parseDate(d) === null)) {
      throw new Error("sent has an invalid forgotten list");
    }
    const rawTombs = sent.tombstones === void 0 ? [] : sent.tombstones;
    if (!Array.isArray(rawTombs) || rawTombs.length > MAX_FORGOTTEN) throw new Error("sent has an invalid tombstone list");
    const seenKeys = /* @__PURE__ */ new Set();
    const tombstones = rawTombs.map((t2) => {
      if (!t2 || typeof t2 !== "object" || Array.isArray(t2) || Object.keys(t2).some((f) => !["key", "version", "restored"].includes(f)) || !idOf("occ")(t2.key) || !Number.isInteger(t2.version) || t2.version < 1 || typeof t2.restored !== "boolean" || seenKeys.has(t2.key)) {
        throw new Error("sent has an invalid tombstone");
      }
      seenKeys.add(t2.key);
      return { key: t2.key, version: t2.version, restored: t2.restored };
    }).sort((a, b) => a.key < b.key ? -1 : 1);
    return { user: sent.user, workouts, forgotten: [...new Set(rawForgotten)].sort(), tombstones };
  }
  function coverage(snapshot) {
    const c = snapshot.coverage;
    if (c === void 0 || c === null) return null;
    if (typeof c !== "object" || Array.isArray(c) || parseDate(c.from) === null || parseDate(c.to) === null || c.from > c.to) {
      throw new Error("invalid coverage");
    }
    return { from: c.from, to: c.to };
  }
  function roundMinutes(m) {
    const sign = m < 0 ? -1 : 1;
    const x = Math.abs(m);
    const str = String(x);
    if (str.includes("e")) return sign * (Math.round(x * 100) / 100);
    return sign * Number(`${Math.round(Number(`${str}e2`))}e-2`);
  }
  var SOURCE_ID = /^wk_[0-9a-f]{8,32}$/;
  function eventsFromSnapshot(snapshot, userId, { host, sent, source: source2 } = {}) {
    if (source2 !== void 0 && !SOURCES2.includes(source2)) throw new Error("invalid source option");
    if (!snapshot || typeof snapshot !== "object" || !Array.isArray(snapshot.workouts)) throw new Error("snapshot must have a workouts array");
    const prev = checkSent(sent === void 0 ? newSent(userId) : sent, userId);
    const cover = coverage(snapshot);
    const forgotten = new Set(prev.forgotten);
    const tombs = new Map(prev.tombstones.map((t2) => [t2.key, t2]));
    const newTombs = /* @__PURE__ */ new Map();
    const forgottenKeys = /* @__PURE__ */ new Set();
    const byKey = /* @__PURE__ */ new Map();
    for (const w of snapshot.workouts) {
      if (!w || typeof w !== "object") throw new Error("invalid workout");
      if (typeof w.durationMin !== "number" || !Number.isFinite(w.durationMin) || w.durationMin < 0 || w.durationMin > 1440) throw new Error("invalid workout duration");
      const start = instant(w.start);
      if (w.id !== void 0 && (typeof w.id !== "string" || !SOURCE_ID.test(w.id))) throw new Error("invalid workout id");
      const basis = w.id !== void 0 ? `id|${w.id}` : `start|${start.ms}`;
      const key2 = opaqueId("occ", `${userId}|${basis}`, host);
      const src = w.source !== void 0 ? w.source : source2;
      if (src === void 0) throw new Error("workout source is required");
      if (!SOURCES2.includes(src)) throw new Error("invalid workout source");
      const endMs = w.end === void 0 || w.end === null ? "" : instant(w.end).ms;
      const { weekday, hour } = wallClock(w.start);
      const localDate = w.start.slice(0, 10);
      if (forgotten.has(localDate)) {
        forgottenKeys.add(key2);
        continue;
      }
      if (tombs.has(key2) && !tombs.get(key2).restored) continue;
      const props = {
        activity: canonicalActivity(w.activityType),
        minutes: roundMinutes(w.durationMin),
        weekday,
        hour,
        source: src,
        local_date: localDate,
        local_week: mondayOf(parseDate(localDate)),
        utc_offset_minutes: start.offsetMin
      };
      const content = JSON.stringify([start.ms, endMs, props.activity, props.minutes, props.utc_offset_minutes, props.weekday, props.hour, props.source, w.durationMin]);
      const rec = { key: key2, basis, start, endMs, props, content, localDate, raw: w.durationMin };
      const have = byKey.get(key2);
      if (have && w.id === void 0 && content !== have.content) throw new Error("workouts at the same start need ids");
      if (!have || content < have.content) byKey.set(key2, rec);
    }
    for (const key2 of forgottenKeys) byKey.delete(key2);
    const workoutsNext = { ...prev.workouts };
    const events = [];
    for (const key2 of [...forgottenKeys].sort()) {
      const old = prev.workouts[key2];
      if (old) {
        if (old.live) events.push(buildEvent("workout_retracted", userId, new Date(old.time), { utc_offset_minutes: old.offset }, old.occurrence_id));
        delete workoutsNext[key2];
      }
      if (!tombs.has(key2)) newTombs.set(key2, { key: key2, version: old ? old.version : 1, restored: false });
    }
    const tombstones = [...prev.tombstones, ...newTombs.values()].sort((a, b) => a.key < b.key ? -1 : 1);
    const next = { user: userId, workouts: workoutsNext, forgotten: prev.forgotten, tombstones };
    const eligible = /* @__PURE__ */ new Set();
    for (const rec of [...byKey.values()].sort((a, b) => a.key < b.key ? -1 : 1)) {
      if (rec.raw < MIN_WORKOUT_MIN) continue;
      eligible.add(rec.key);
      const hash = contentHash(host, rec.start.ms, rec.endMs, rec.props);
      const old = prev.workouts[rec.key];
      if (old && old.live && old.hash === hash) continue;
      const floor = tombs.has(rec.key) ? tombs.get(rec.key).version : 0;
      const version = Math.max(old ? old.version : 0, floor) + 1;
      const occ = opaqueId("occ", `${userId}|${rec.basis}|${version}`, host);
      const extra = old && old.live ? { supersedes: old.occurrence_id } : {};
      const time = floorToLocalHour(rec.start);
      events.push(buildEvent("workout_completed", userId, new Date(time), { ...rec.props, ...extra }, occ));
      const prior = old ? [.../* @__PURE__ */ new Set([...old.prior, old.day])].filter((d) => d !== rec.localDate).sort() : [];
      next.workouts[rec.key] = { hash, occurrence_id: occ, version, day: rec.localDate, prior, time, offset: rec.start.offsetMin, live: true };
    }
    for (const key2 of Object.keys(prev.workouts).sort()) {
      const old = prev.workouts[key2];
      if (!old.live || eligible.has(key2) || forgottenKeys.has(key2)) continue;
      const present = byKey.has(key2);
      const covered = cover && old.day >= cover.from && old.day <= cover.to;
      if (!present && !covered) continue;
      events.push(buildEvent("workout_retracted", userId, new Date(old.time), { utc_offset_minutes: old.offset }, old.occurrence_id));
      next.workouts[key2] = { ...old, live: false };
    }
    return { events, next };
  }

  // src/amplitude/outbox.mjs
  var OUTBOX_FIELDS = ["user", "state", "events", "status"];
  var FAIL = (error, more = {}) => ({ ok: false, error, ...more });
  function newOutbox(userId) {
    return { user: userId, state: newSent(userId), events: [] };
  }
  function checkOutbox(o) {
    if (!o || typeof o !== "object" || Array.isArray(o) || !Array.isArray(o.events)) throw new Error("outbox is invalid");
    if (Object.keys(o).some((k) => !OUTBOX_FIELDS.includes(k))) throw new Error("outbox has an unknown field");
    if (o.status !== void 0 && o.status !== "unrecovered" && o.status !== "unsynced") throw new Error("outbox is invalid");
    checkUser(o.user);
    const events = o.events.map(sanitizeEvent);
    if (events.some((e) => e.user_id !== o.user)) throw new Error("outbox event belongs to another user");
    const out = { user: o.user, state: checkSent(o.state, o.user), events };
    if (o.status !== void 0) out.status = o.status;
    return out;
  }
  function checkUsable(o) {
    if (o.status === "unrecovered") throw new Error("outbox state is unrecovered; load it with loadOutbox first");
    if (o.status === "unsynced") throw new Error("outbox is not synced to disk; run syncOutbox first");
    return o;
  }
  function plainOutbox(outbox) {
    const o = checkUsable(checkOutbox(outbox));
    return { user: o.user, state: o.state, events: o.events };
  }
  function ackOutbox(outbox, acked) {
    const o = plainOutbox(outbox);
    const ids = Array.isArray(acked) ? acked : (acked?.acked ?? []).flatMap((b) => b.insert_ids);
    const done = new Set(ids);
    return { user: o.user, state: o.state, events: o.events.filter((e) => !done.has(e.insert_id)) };
  }
  function callStore(fn, ...args) {
    try {
      const r = fn(...args);
      if (!r || typeof r !== "object") return FAIL("outbox could not be saved", { unrecovered: true });
      return r;
    } catch {
      return FAIL("outbox could not be saved", { unrecovered: true });
    }
  }
  function afterFailedSave(saved, original) {
    try {
      if (saved.unsynced && saved.outbox) {
        const { status: _s, ...plain } = checkOutbox(saved.outbox);
        return { ...plain, status: "unsynced" };
      }
      if (saved.outbox) {
        const { status: _s, ...plain } = checkOutbox(saved.outbox);
        return plain;
      }
    } catch {
      return { ...original, status: "unrecovered" };
    }
    if (saved.unrecovered) return { ...original, status: "unrecovered" };
    return original;
  }
  var STORE_ERRORS = [
    "outbox could not be saved",
    "outbox could not be read",
    "outbox could not be synced",
    "outbox is invalid",
    "outbox directory sync failed",
    "outbox state unrecovered",
    "outbox on disk differs from the intended content",
    "outbox read-back did not match"
  ];
  var fixedError = (r) => typeof r?.error === "string" && STORE_ERRORS.includes(r.error) ? r.error : "store failed";
  function persist(store, plain) {
    const saved = callStore((o) => store.save(o), plain);
    if (!saved.ok) return saved;
    try {
      const r = store.load();
      if (!r || r.ok !== true || !r.outbox) return FAIL("outbox read-back did not match", { unrecovered: true });
      const back = checkOutbox(r.outbox);
      if (back.status !== void 0 || JSON.stringify(back) !== JSON.stringify(plain)) return FAIL("outbox read-back did not match", { unrecovered: true });
    } catch {
      return FAIL("outbox read-back did not match", { unrecovered: true });
    }
    return { ok: true };
  }
  function commitStaged(store, outbox, { snapshot, events = [], host, source: source2 } = {}) {
    const o = plainOutbox(outbox);
    let state = o.state;
    let built = [];
    if (snapshot) ({ events: built, next: state } = eventsFromSnapshot(snapshot, o.user, { host, sent: o.state, source: source2 }));
    const have = new Set(o.events.map((e) => e.insert_id));
    const added = [...built, ...events].map(sanitizeEvent).filter((e) => !have.has(e.insert_id) && have.add(e.insert_id));
    const staged = { user: o.user, state, events: [...o.events, ...added] };
    const saved = persist(store, staged);
    if (saved.ok) return { ok: true, outbox: staged, added: added.length };
    return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
  }
  function acknowledge(store, outbox, acked) {
    const after = ackOutbox(outbox, acked);
    const saved = persist(store, after);
    if (saved.ok) return { ok: true, outbox: after };
    return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
  }
  function loadOutbox(store, userId) {
    let r;
    try {
      r = store.load();
    } catch {
      return FAIL("outbox could not be read");
    }
    if (!r || typeof r !== "object" || r.ok !== true) return FAIL(r && typeof r === "object" ? fixedError(r) : "outbox could not be read");
    if (r.outbox === null) return { ok: true, outbox: null };
    try {
      const o = checkOutbox(r.outbox);
      if (o.status !== void 0 || o.user !== userId) throw new Error("outbox is invalid");
      return { ok: true, outbox: o };
    } catch {
      return FAIL("outbox is invalid");
    }
  }
  function forgetDay(store, outbox, localDate) {
    if (parseDate(localDate) === null) throw new Error("invalid local date");
    const o = plainOutbox(outbox);
    const dropIds = /* @__PURE__ */ new Set();
    const retract = /* @__PURE__ */ new Map();
    const isCompleted = (e) => e.event_type === "workout_completed";
    const dropEvent = (e, time, offset) => {
      dropIds.add(e.insert_id);
      retract.set(e.event_properties.occurrence_id, { time, offset });
      if (e.event_properties.supersedes) retract.set(e.event_properties.supersedes, { time, offset });
    };
    for (const e of o.events) if (isCompleted(e) && e.event_properties.local_date === localDate) dropEvent(e, e.time, e.event_properties.utc_offset_minutes);
    const tombs = new Map(o.state.tombstones.map((t2) => [t2.key, t2]));
    const workouts = {};
    for (const [key2, entry] of Object.entries(o.state.workouts)) {
      if (entry.day !== localDate && !entry.prior.includes(localDate)) {
        workouts[key2] = entry;
        continue;
      }
      tombs.set(key2, { key: key2, version: entry.version, restored: false });
      for (const e of o.events) if (isCompleted(e) && e.event_properties.occurrence_id === entry.occurrence_id) dropEvent(e, entry.time, entry.offset);
      if (entry.live) retract.set(entry.occurrence_id, { time: entry.time, offset: entry.offset });
    }
    const pendingRetractions = new Set(o.events.filter((e) => e.event_type === "workout_retracted").map((e) => e.event_properties.occurrence_id));
    const events = o.events.filter((e) => !dropIds.has(e.insert_id));
    for (const [occ, { time, offset }] of [...retract.entries()].sort(([a], [b]) => a < b ? -1 : 1)) {
      if (pendingRetractions.has(occ)) continue;
      events.push(buildEvent("workout_retracted", o.user, new Date(time), { utc_offset_minutes: offset }, occ));
    }
    const next = { user: o.user, state: { user: o.user, workouts, forgotten: [.../* @__PURE__ */ new Set([...o.state.forgotten, localDate])].sort(), tombstones: [...tombs.values()].sort((a, b) => a.key < b.key ? -1 : 1) }, events };
    const saved = persist(store, next);
    if (saved.ok) return { ok: true, outbox: next };
    return { ok: false, error: fixedError(saved), outbox: afterFailedSave(saved, checkOutbox(outbox)) };
  }

  // src/amplitude/io-store.mjs
  var FAIL2 = (error, more = {}) => ({ ok: false, error, ...more });
  var TOLERATED = ["ENOTSUP", "EOPNOTSUPP"];
  function createIoStore({ io, dir, userId }) {
    checkUser(userId);
    const path = `${dir}/outbox.json`;
    const tmp = `${dir}/.outbox.json.tmp`;
    const read = (p) => {
      try {
        return io.readFile(p);
      } catch (e) {
        return e?.code === "ENOENT" ? null : void 0;
      }
    };
    const syncDir = () => {
      try {
        io.fsyncDir(dir);
        return true;
      } catch (e) {
        return TOLERATED.includes(e?.code);
      }
    };
    function reconcile(text, intended, dirSynced) {
      const raw = read(path);
      if (raw === void 0 || raw === null) return FAIL2("outbox state unrecovered", { unrecovered: true });
      if (raw === text) return dirSynced ? { ok: true } : FAIL2("outbox directory sync failed", { unsynced: true, outbox: intended });
      try {
        const onDisk = plainOutbox(JSON.parse(raw));
        if (onDisk.user !== userId) throw new Error("invalid");
        return FAIL2("outbox on disk differs from the intended content", { outbox: onDisk });
      } catch {
        return FAIL2("outbox state unrecovered", { unrecovered: true });
      }
    }
    function save(given) {
      let outbox;
      try {
        outbox = plainOutbox(given);
      } catch {
        return FAIL2("outbox could not be saved");
      }
      if (outbox.user !== userId) return FAIL2("outbox could not be saved");
      const text = JSON.stringify(outbox);
      try {
        io.remove(tmp);
        io.writeFile(tmp, text);
        io.fsyncFile(tmp);
        if (io.readFile(tmp) !== text) throw new Error("mismatch");
      } catch {
        try {
          io.remove(tmp);
        } catch {
        }
        return FAIL2("outbox could not be saved");
      }
      try {
        io.rename(tmp, path);
      } catch {
        try {
          io.remove(tmp);
        } catch {
        }
        return reconcile(text, outbox, false);
      }
      return reconcile(text, outbox, syncDir());
    }
    function load() {
      try {
        io.remove(tmp);
      } catch {
        return FAIL2("outbox could not be read");
      }
      const text = read(path);
      if (text === null) return { ok: true, outbox: null };
      if (text === void 0) return FAIL2("outbox could not be read");
      try {
        const outbox = plainOutbox(JSON.parse(text));
        if (outbox.user !== userId) throw new Error("invalid");
        return syncDir() ? { ok: true, outbox } : FAIL2("outbox directory sync failed");
      } catch {
        return FAIL2("outbox is invalid");
      }
    }
    function sync(given) {
      let outbox;
      try {
        outbox = plainOutbox(given);
      } catch {
        return FAIL2("outbox could not be synced");
      }
      return reconcile(JSON.stringify(outbox), outbox, syncDir());
    }
    return { save, load, sync };
  }

  // src/phone/entry.mjs
  var open = (a) => {
    const io = globalThis.memoryIO;
    if (!io) throw new Error("memoryIO is not set");
    return new MemoryStore(a.root, a.user, { io });
  };
  var call = (argsJson, fn) => {
    try {
      const args = JSON.parse(argsJson);
      return JSON.stringify(fn(open(args), args));
    } catch (e) {
      return JSON.stringify({ ok: false, error: String(e && e.name ? e.name : "Error") });
    }
  };
  var FORGET = {
    recommendation: (s, a) => forgetRecommendation(s, a.recId),
    day: (s, a) => forgetFactKey(s, "daily", a.date),
    type: (s, a) => forgetFactType(s, a.type),
    key: (s, a) => forgetFactKey(s, a.type, a.key),
    derived: (s, a) => forgetDerived(s, a.kind),
    preference: (s, a) => forget(s, "preferences", a.prefix)
  };
  var outboxOf = (store, a) => {
    const io = globalThis.memoryIO;
    if (!io || typeof io.hmac !== "function" || !io.idSecret) return null;
    const outStore = createIoStore({ io, dir: store.dir, userId: a.user });
    const loaded = loadOutbox(outStore, a.user);
    if (!loaded.ok) throw new Error(loaded.error);
    return { outStore, outbox: loaded.outbox ?? newOutbox(a.user), host: { hmac: io.hmac, secret: io.idSecret } };
  };
  var EVENT_ACTIVITY = { run: "Running", walk: "Walking", cycle: "Cycling", swim: "Swimming", strength: "TraditionalStrengthTraining", yoga: "Yoga", hike: "Hiking", row: "Rowing", elliptical: "Elliptical", hiit: "HighIntensityIntervalTraining", pilates: "Pilates", dance: "Dance" };
  var WEEKDAYS4 = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  var stage = (out, args) => {
    const r = commitStaged(out.outStore, out.outbox, { ...args, host: out.host, source: "phone" });
    return r.ok ? { staged: r.added } : { stageError: r.error };
  };
  globalThis.memoryRoll = (argsJson) => call(argsJson, (store, a) => {
    const rolled = rollDay({ store, snapshot: a.snapshot, now: a.now, mode: a.mode });
    const out = rolled.ok ? outboxOf(store, a) : null;
    if (!out) return rolled;
    const events = [];
    if (rolled.mode === "completed") {
      const rolling = store.read("rolling")?.facts ?? [];
      const planner = plannerText(store);
      events.push(buildEvent("memory_rolled", a.user, a.now, {
        daily_lines: rolling.filter((f) => f.kind === "daily").length,
        weekly_lines: rolling.filter((f) => f.kind === "weekly").length,
        preferences: store.read("preferences")?.facts.length ?? 0,
        prompt_words: planner.ok ? planner.words : 0
      }, opaqueId("occ", `${a.user}|rolled|${rolled.day}`, out.host)));
    }
    return { ...rolled, ...stage(out, { snapshot: a.snapshot, events }) };
  });
  globalThis.memoryTap = (argsJson) => call(argsJson, (store, a) => {
    const tap = recordFeedback(store, a);
    const out = tap.written ? outboxOf(store, a) : null;
    if (!out) return tap;
    const props = { rec_id: a.recId, activity: EVENT_ACTIVITY[a.activity] ?? "Other", weekday: WEEKDAYS4[a.weekday - 1], hour: a.hour };
    const occ = (label) => opaqueId("occ", `${a.user}|${label}|${a.recId}`, out.host);
    const events = [];
    if (a.action === "accepted") events.push(buildEvent("recommendation_accepted", a.user, a.now, props, occ("accepted")));
    else if (a.reason) events.push(buildEvent("recommendation_declined", a.user, a.now, { ...props, reason: a.reason }, occ("declined")));
    if (tap.promoted) events.push(buildEvent("preference_learned", a.user, a.now, { reason: a.reason, times_said: 2 }, opaqueId("occ", `${a.user}|learned|${a.reason}`, out.host)));
    return { ...tap, ...stage(out, { events }) };
  });
  globalThis.memoryForget = (argsJson) => call(argsJson, (store, a) => {
    if (!Object.hasOwn(FORGET, a.what)) return { ok: false, error: "unknown what" };
    const ok = FORGET[a.what](store, a) === true;
    const out = ok && a.what === "day" ? outboxOf(store, a) : null;
    if (!out) return { ok };
    const r = forgetDay(out.outStore, out.outbox, a.date);
    return r.ok ? { ok } : { ok: false, error: r.error };
  });
  globalThis.memoryFlush = (argsJson) => call(argsJson, (store, a) => {
    const out = outboxOf(store, a);
    return out ? { ok: true, events: out.outbox.events } : { ok: false, error: "no id secret or hmac set" };
  });
  globalThis.memoryAck = (argsJson) => call(argsJson, (store, a) => {
    const out = outboxOf(store, a);
    if (!out) return { ok: false, error: "no id secret or hmac set" };
    const r = acknowledge(out.outStore, out.outbox, a.acked);
    return r.ok ? { ok: true, left: r.outbox.events.length } : { ok: false, error: r.error };
  });
  globalThis.memoryPlannerText = (argsJson) => call(argsJson, (store) => plannerText(store));
})();
