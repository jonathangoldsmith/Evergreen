---
# gstack: design-md-format=spec
name: Evergreen
description: Training that grows with you: an encouraging coach on light, green-tinted neutrals; one pine accent and one typeface belong to the agent, everything else stays still.
colors:
  surface: "#F7F8F6"
  card: "#FFFFFF"
  text: "#15201B"
  text-muted: "#55615B"
  accent: "#1F6F5C"
  on-accent: "#FFFFFF"
  rule: "#E3E7E4"
  success: "#2F7A4F"
  warning: "#8A5A00"
  error: "#B3261E"
  dark-surface: "#0F1513"
  dark-card: "#18201D"
  dark-text: "#EEF2EF"
  dark-text-muted: "#A6B1AC"
  dark-accent: "#5FC2A6"
  dark-on-accent: "#0F1513"
  dark-rule: "#26302C"
typography:
  display:
    fontFamily: General Sans
    fontWeight: 600
    fontSize: 24pt (agent card headline), 30–40pt (onboarding titles)
    letterSpacing: -0.01em
  body:
    fontFamily: SF Pro
    fontSize: 17pt (Dynamic Type .body)
    lineHeight: 22pt
  label:
    fontFamily: SF Pro
    fontSize: 13pt (Dynamic Type .footnote)
  mono:
    fontFamily: SF Pro
    fontFeature: tnum
rounded:
  sm: 8px
  md: 12px
  lg: 20px
  phone: 40px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 48px
components:
  agent-card:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.lg}"
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.md}"
  button-ghost:
    borderColor: "{colors.rule}"
    textColor: "{colors.text}"
    rounded: "{rounded.md}"
  badge:
    borderColor: "{colors.accent}"
    textColor: "{colors.accent}"
    rounded: "{rounded.sm}"
---

# Evergreen

## Overview

**Creative North Star:** Training that grows with you. Evergreen is an encouraging coach that shows its reasoning: every workout says why it was picked, from Apple Health data (runs, heart rate, training load) and the open time on the calendar ("Easy pace. Your training load is up 18%, so this one stays light."). Shopping is an occasional, helpful extra that protects training, and it always asks first. Its work is recognizable at a glance because it alone gets the accent and the display face.
**Product context:** native iOS personal fitness agent (Personal Agents Hackathon, 2026-11-20) for people who want to work out a bit more than their normal; peers are Google Health Coach, Apple Workout Buddy, Fitbod, WHOOP and Oura.
**Mode per surface:** Operate for every screen (onboarding, Today).
**Reference sites:** Oura's 2025 "Today" redesign (one daily focus), WHOOP's one-screen home, Gentler Streak (Apple Design Award 2024, humane fitness).
**Key characteristics:**
- the agent's latest action is the only card on screen
- pine accent + General Sans appear only on what the agent did
- progress is a sentence, never a ring or chart
- encouraging at the miss: a muted "Next time", never red, guilt or a minus number
- every workout carries its reason, citing the health data or calendar time behind it
- one character: the pine buddy, a round, friendly pine with dot eyes, rosy cheeks and coral running shoes. It is the mark, the Welcome art (running) and the week's progress (a tier fills per finished workout; it cheers when the week is done). No other illustration. Its leaf green, blush and shoe coral are decoration only, never text or UI color

## Colors

**Strategy:** Restrained. One accent means "the agent did this"; neutrals carry a slight green tint derived from it.
**Light or dark:** light by default, because Sam checks the app indoors at a desk and the demo runs on a bright projector; dark mode keeps the same hierarchy with a lighter accent (7.7:1 on dark card), not an inversion.
Warning is used only for the offline label; error only for real failures. Every text pair is 4.5:1 or better.

## Typography

General Sans (Fontshare, ITF Free Font License, 12 static styles + variable) is the agent's voice: first-person headlines ("Saved your workout", "Book a day pass at 24 Hour Fitness?", "Time for new running shoes?") and the Welcome line "Training that grows with you." and the two onboarding titles only. SF Pro with Dynamic Type handles everything else: a justified exception to "no system font as body", because this is a native Operate surface and SF Pro gives Dynamic Type, accessibility and tabular numbers for free. Bundle General Sans Semibold (UIAppFonts) and scale it with UIFontMetrics so it follows Dynamic Type.

## Layout

iPhone portrait only. Single column, 16pt side margins, 24pt between sections. Onboarding: Welcome → Permissions (three Allow rows on one page). Today: date → agent card → "On your calendar" rows → "This week: 1 of 3 done".

## Elevation & Depth

Only the agent card is elevated: 0 2px 8px at 6% ink in light mode; a 1px rule instead of a shadow in dark mode. Rows sit flat on the surface, separated by 1px rules.

## Shapes

20pt continuous radius on the agent card, 12pt on buttons, 8pt on badges. Rows have no radius.

## Components

- **Agent card:** verb (General Sans, accent) · struck-through before → after · one-line reason · one muted line (what it keeps, or the terms) · Undo + Pick another time, or the ask's primary + Not now. VoiceOver reads it as one sentence.
- **Plan row:** day (with a "Moved" badge when the agent moved it) · activity and length · time on the right. No radius, 1px rules between.
- **Buttons:** primary = solid accent, ghost = 1px rule; at least 44pt tall; focus ring is 2px accent.
- **Badge:** "Moved", accent outline.
- **Demo controls:** floating debug button, toggled from the app's page in iOS Settings. On by default in Debug builds (simulator or phone from Xcode), off in Release. One button per beat: the plan, a meeting moves a workout, rain buys a day pass, shoes near 400 miles.

## Do's and Don'ts

- Do reserve the accent and General Sans for agent actions only.
- Do write progress as a sentence ("2 of 3 this week").
- Do keep the last good screen up with a quiet label instead of a spinner.
- Don't use rings, charts, progress circles or confetti.
- Don't show minus points or red at a missed workout.
- Don't stack cards or nest a card inside a card.
- Don't put neon accents or glowing edges on dark surfaces.

## Motion

- **Approach:** minimal-functional
- **Easing:** enter(ease-out) exit(ease-out) move(ease-in-out)
- **Duration:** micro 80ms, short 200ms, medium 300ms, long 600ms
- **The one authored moment:** none for now; onboarding's Permissions page slides in (300ms ease-in-out)

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-19 | Initial design system created | Created by /design-consultation from the office-hours design doc, the plan design review (D4–D17) and fitness-app research |
| 2026-11-20 | Demo trimmed to the canvas beats | Comebacks, points, the Feed and Done sheets, the week view and the Live Activity removed; Today shows the week's rows; the gym day pass kept as a fourth beat |
| 2026-11-20 | Renamed to Rally; cheerleader voice | Asked for a strong, motivating brand. Copy turns first-person and upbeat; visuals, accent rules and the no-guilt rules stay |
| 2026-11-20 | Renamed to Evergreen; tailored-training proposition | Value moves to picking the right, sustainable workout from health data and calendar time, with occasional ask-first shopping. Coach voice that cites its data; pine tree as the one image, including the week's progress |
| 2026-11-20 | Pine buddy mascot | Asked for a cuter brand: an original kawaii pine with running shoes replaces the flat pine |
