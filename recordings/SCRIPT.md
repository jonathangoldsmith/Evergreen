# Evergreen: 3-minute demo script

Play `evergreen-demo-3min.mp4` (no audio, captions burned in) and talk over it. Each person has 45 seconds: say your name (about 3 s), about 40 s of content, then hand the mic on (about 2 s). The captions show exactly these lines at these times, so if you fall behind, skip ahead to the line on screen.

| Time | Speaker | Judging criterion |
|---|---|---|
| 0:00–0:45 | Anna (Design) | Idea |
| 0:45–1:30 | Jonathan (iOS app) | Autonomy |
| 1:30–2:15 | Surya (Recommendation harness) | Technical · Tool use |
| 2:15–3:00 | Tony (Data and memory) | Memory · Tool use |

Presentation is the whole three minutes.

## 0:00–0:45 · Anna · Idea

**On screen:** 0:00–0:08 title card (the buddy waves hi). 0:08–0:45 the app opens on Jordan's plan: “Three workouts, tailored to you.”

- `0:00` Hi, I'm Anna. I designed Evergreen and our little pine buddy.
- `0:03` Most of us want to work out a bit more than our normal.
- `0:08` But a plan breaks the moment it meets a real calendar.
- `0:12` A meeting runs late, it rains, your shoes wear out, and the week slips.
- `0:17` Evergreen is a personal training agent that works inside your real life.
- `0:21` It reads Apple Health: 21 runs in 30 days, an average heart rate of 132,
- `0:26` and a training load that's up 19% on your usual week.
- `0:30` Then it reads your calendar and finds the time you actually have.
- `0:35` This week: Friday evening, and Saturday and Sunday mornings.
- `0:39` Three workouts, each with a reason you can see.
- `0:43` Jonathan, show them what it does.

_Hand the mic to Jonathan._

## 0:45–1:30 · Jonathan · Autonomy

**On screen:** 0:45–1:10 a meeting lands on the 6 PM run and the card changes to “Saved your workout, Fri 6:00 PM → 6:45 PM” with no tap. 1:10–1:30 rain: “Book a day pass at 24 Hour Fitness?”, then Book it, and the run moves indoors.

- `0:45` Thanks, Anna. I'm Jonathan, and I built the iOS app.
- `0:48` Evergreen doesn't just plan. It acts for you, end to end.
- `0:52` At 4 PM, a team sync lands right on top of tonight's 6 PM run.
- `0:57` Nobody taps anything. The agent sees the conflict and moves the run to 6:45,
- `1:01` the next open slot, so the week still has all three workouts.
- `1:06` It tells you why, and Undo is one tap away.
- `1:10` Now rain is forecast for Saturday's 8:30 AM long run.
- `1:15` It finds a $15 day pass at 24 Hour Fitness, 0.4 miles from home.
- `1:19` Spending is where it always asks first. Nothing is bought without your OK.
- `1:23` One tap, and it books the pass and moves the run onto a treadmill.
- `1:27` Surya, show them how it shops.

_Hand the mic to Surya._

## 1:30–2:15 · Surya · Technical · Tool use

**On screen:** 1:30–1:41 harness architecture card. 1:41–2:15 the harness's pick (New Balance Fresh Foam X 1080 v15), Compare pairs (Senso · live citations, why each shoe lost), checkout, Place order, the buddy celebrates.

- `1:30` Thanks, Jonathan. I'm Surya. I built the recommendation harness.
- `1:33` Jordan's shoes are at 392 miles, and his race is in nine days.
- `1:38` Our harness on Vercel uses Nimble to research real shoes on expert review sites.
- `1:42` Hard rules run in code: wide toe box, no carbon plate, arrives in time to break in.
- `1:47` Then Superlinked's SIE ranks the shortlist with a Qwen reranker,
- `1:51` and a Qwen model picks one and writes why every other shoe lost.
- `1:56` Senso supplies cited passages, live, so every claim has a source.
- `2:00` Every recommendation is written to a SingleStore audit log.
- `2:05` If anything fails, guardrails fall back to a safe, deterministic pick.
- `2:09` Jordan says yes once, and two break-in runs land on his calendar.
- `2:13` Tony, take us home.

_Hand the mic to Tony._

## 2:15–3:00 · Tony · Memory · Tool use

**On screen:** 2:15–2:27 memory and Amplitude card. 2:27–2:45 the demo controls' Amplitude section. 2:45–3:00 closing card with the team and the celebrating buddy.

- `2:15` Thanks, Surya. I'm Tony. I built the data and the memory agent.
- `2:18` Evergreen remembers you, on your phone. The memory agent runs in JavaScriptCore.
- `2:23` Every tick, it rolls your history into a memory of how you actually train.
- `2:27` Workouts, memory updates and approved purchases go to Amplitude,
- `2:32` with opaque, hashed ids. No names or health readings leave the phone.
- `2:36` So we see what the agent does and what people say yes to, not who they are.
- `2:41` Evergreen plans around your real life, acts on its own, and asks before it spends.
- `2:45` Training that grows with you.
- `2:50` **Everyone:** We're Anna, Jonathan, Surya and Tony. Thank you!

_Everyone steps in for the last line; the video ends on the team card at 3:00._

## Before going on stage

- **Warm the harness** a few minutes before, so the live demo (if any) doesn't wait on a cold model:
  `curl -X POST https://trackerplusplus-harness.vercel.app/warm -H "X-Harness-Secret: $SECRET"`
- **Surya, check the SingleStore line.** In testing on 2026-11-20, `/warm` loaded 0 SingleStore candidates and responses had no `auditId`. If the audit log still isn't recording, say “is built to write every recommendation to a SingleStore audit log” instead of “every recommendation is written”.
- **Don't promise Persona verification.** The Persona SDK is linked, but there's no verification screen in the app yet.
- Practise once with a timer: 100 words in 40 seconds is a calm pace, not a rush.

Files: `evergreen-demo-3min.mp4` (1920×1080, 30 fps, 3:00, burned-in captions plus a soft caption track) and `evergreen-demo-3min.srt` (the same captions for players that want a sidecar file).
