# Evergreen: 3-minute demo script

`evergreen-demo-3min.mp4` now carries the team's recorded voices, cleaned up and laid back to back, with captions timed to the words. Play it as is, or mute it and talk live: the captions show each line when it's due.

| Time | Speaker | Judging criterion |
|---|---|---|
| 0:00–0:40 | Anna (Design) | Idea |
| 0:40–1:19 | Jonathan (iOS app) | Autonomy |
| 1:19–2:15 | Surya (Recommendation harness) | Technical · Tool use |
| 2:15–3:00 | Tony (Data and memory) | Memory · Tool use |

Presentation is the whole three minutes.

## 0:00–0:40 · Anna · Idea

**On screen:** 0:00–0:21 title card while Anna tells the story (the buddy waves hi). From 0:21, the app's plan: “Three workouts, tailored to you.”

- `0:00` Hi, I'm Anna. I designed Evergreen.
- `0:02` I want to improve my fitness in a sustainable manner,
- `0:05` but my ideal workout plan goes out the window the moment it meets the real world.
- `0:10` A meeting runs late, it rains, your shoes wear out,
- `0:13` you overtrain and tear your meniscus three times (that's a true story),
- `0:17` and before you know it, you're on the couch watching TV instead of working out.
- `0:21` Evergreen is a personal training agent that works with your real life.
- `0:25` It takes in all your data from Apple Health.
- `0:28` Then it reads your calendar and finds the time you actually have.
- `0:31` This week, we have workouts planned Friday, Saturday and Sunday.
- `0:34` Evergreen built these out so I don't overtrain.
- `0:37` Jonathan, show them what it does.

## 0:40–1:19 · Jonathan · Autonomy

**On screen:** The plan until 0:54, when the run is already moved: “Saved your workout, Fri 6:00 PM → 6:45 PM”, no tap. From 1:05 rain: “Book a day pass at 24 Hour Fitness?”; booked at 1:14.

- `0:40` Thanks, Anna. I'm Jonathan, and I built the iOS app.
- `0:43` Evergreen doesn't just plan sustainable workouts based on your training load.
- `0:46` It acts for you, end to end, to keep you on track.
- `0:50` At 4 PM, a team sync lands right on top of tonight's 6 PM run.
- `0:54` Nobody taps anything. The agent sees the conflict and moves the run to 6:45,
- `0:58` your next open slot, so the week still has all three workouts.
- `1:02` It tells you why it rescheduled, and lets you reschedule if necessary.
- `1:05` Oh no! Rain is forecast for Saturday's 8:30 AM long run.
- `1:09` Evergreen finds a $15 day pass at 24 Hour Fitness, close to home.
- `1:14` One tap, and it books the pass and moves the run onto a treadmill.
- `1:17` Surya, show them how it shops.

## 1:19–2:15 · Surya · Technical · Tool use

**On screen:** The shoe card; 1:31–1:43 the harness diagram; from 1:43 Why this pair (Senso · live citations, why each shoe lost); checkout at 2:08, then Place order and the buddy celebrates.

- `1:20` Thanks, Jonathan. I'm Surya. I built the recommendation harness behind this app.
- `1:25` Let's say Jordan's shoes are at 390 miles, 97% worn, and his race is in about nine days.
- `1:31` The harness picks from real shoes found on expert review sites.
- `1:35` Before any AI is involved, hard rules filter out shoes that don't fit, lack cushioning, or arrive too late.
- `1:43` Then we have Superlinked's SIE, which ranks the shortlist,
- `1:47` and a small open model picks one and explains why every other shoe lost.
- `1:51` We use Senso, which supplies live, cited sources, so every claim on the screen has a source.
- `1:58` It's $170, over his $20 rule, so it asks first, and every decision is logged to SingleStore.
- `2:05` Persona here verifies your age for 18+ purchases.
- `2:08` Jordan says yes once, and two break-in runs land on his calendar.
- `2:13` Tony, take us home.

## 2:15–3:00 · Tony · Memory · Tool use

**On screen:** The app's Amplitude section; from 2:34 the memory card (baseline, “too early” becoming a preference through Superlinked, the calendar preview); from 2:54 the closing card with the team.

- `2:16` Thanks, Surya. I'm Tony. I built Evergreen's memory agent and its Amplitude tracking.
- `2:22` Amplitude tells us which workout suggestions people accept, which they complete,
- `2:28` and when feedback becomes a saved preference, without sending names or raw health readings.
- `2:34` On the phone, the agent turns workout history into a personal baseline.
- `2:40` I used Superlinked to interpret sample feedback like “too early,”
- `2:45` and built a calendar preview that uses those preferences to suggest workout times that fit.
- `2:54` We are Anna, Jonathan, Surya and Tony. Thank you!

## Audio edits

- Every recording: rumble and hiss filtered, light noise reduction, gentle compression, and levels matched (−16 LUFS), so the four voices sit at the same loudness.
- Jonathan: the first try at the handoff (“…so yeah, show how it shops”) is cut; his retake, “Surya, show them how it shops”, follows “…onto a treadmill.”
- Everyone: long pauses between sentences are shortened to about a third of a second, and the voices play 5% faster (pitch unchanged) so the whole thing fits 3:00. Surya's recording had the most pauses.
- Tony: his recording includes the team's closing line, so the video ends with it over the team card.
- About half a second of silence at each mic pass.

## Before going on stage

- **Surya, check the SingleStore line.** In testing on 2026-11-20, `/warm` loaded 0 SingleStore candidates and responses had no `auditId`.
- **Surya's Persona and “$20 rule” lines** are kept as recorded. The app has no age check yet, and Why this pair shows Jordan's rule as “Always check with me before buying anything.”
- **Warm the harness** a few minutes before any live demo:
  `curl -X POST https://trackerplusplus-harness.vercel.app/warm -H "X-Harness-Secret: $SECRET"`

Files: `evergreen-demo-3min.mp4` (1920×1080, 30 fps, 3:00, voice track, burned-in captions plus a soft caption track) and `evergreen-demo-3min.srt`.
