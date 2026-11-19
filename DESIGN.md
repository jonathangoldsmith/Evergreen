---
# gstack: design-md-format=spec
name: TrackerPlusPlus
description: A quiet assistant on light, green-tinted neutrals; one pine accent and one typeface belong to the agent, everything else stays still.
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
    fontSize: 22pt (agent card), 17pt (feed rows), 72pt (Done points)
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

# TrackerPlusPlus

## Overview

**Creative North Star:** A quiet assistant. The agent's work is recognizable at a glance because it alone gets the accent and the display face; "It already handled it" is the one thing to remember.
**Product context:** native iOS personal fitness agent (Personal Agents Hackathon, 2026-11-20) for people who want to work out a bit more than their normal; peers are Google Health Coach, Apple Workout Buddy, Fitbod, WHOOP and Oura.
**Mode per surface:** Operate for every screen (Today, This week, Feed sheet, Done sheet, onboarding).
**Reference sites:** Oura's 2025 "Today" redesign (one daily focus), WHOOP's one-screen home, Gentler Streak (Apple Design Award 2024, humane fitness).
**Key characteristics:**
- the agent's latest action is the only card on screen
- pine accent + General Sans appear only on what the agent did
- progress is a sentence, never a ring or chart
- calm at the miss: "No problem", never a minus number

## Colors

**Strategy:** Restrained. One accent means "the agent did this"; neutrals carry a slight green tint derived from it.
**Light or dark:** light by default, because Sam checks the app indoors at a desk and the demo runs on a bright projector; dark mode keeps the same hierarchy with a lighter accent (7.7:1 on dark card), not an inversion.
Warning is used only for the offline label; error only for real failures. Every text pair is 4.5:1 or better.

## Typography

General Sans (Fontshare, ITF Free Font License, 12 static styles + variable) is the agent's voice: verb-first headlines ("Booked comeback", "Moved") and the Done points number only. SF Pro with Dynamic Type handles everything else: a justified exception to "no system font as body", because this is a native Operate surface and SF Pro gives Dynamic Type, accessibility and tabular numbers for free. Bundle General Sans Semibold (UIAppFonts) and scale it with UIFontMetrics so it follows Dynamic Type.

## Layout

iPhone portrait only. Single column, 16pt side margins, 24pt between sections. Today: agent card → today's rows → "This week: 1 of 3" link. Feed and Done are sheets.

## Elevation & Depth

Only the agent card is elevated: 0 2px 8px at 6% ink in light mode; a 1px rule instead of a shadow in dark mode. Rows sit flat on the surface, separated by 1px rules.

## Shapes

20pt continuous radius on the agent card, 12pt on buttons, 8pt on badges. Rows have no radius.

## Components

- **Agent card:** verb (General Sans, accent) · struck-through before → after · one-line reason · what the comeback keeps · Undo + Pick another time. VoiceOver reads it as one sentence.
- **Feed row:** the same five parts, newest first, Undo on each.
- **Buttons:** primary = solid accent, ghost = 1px rule; at least 44pt tall; focus ring is 2px accent.
- **Badge:** "2× comeback", accent outline.
- **Demo controls:** floating debug button, enabled from the app's page in iOS Settings, off by default.

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
- **The one authored moment:** the Done points count-up (600ms ease-out); none under Reduce Motion

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-11-19 | Initial design system created | Created by /design-consultation from the office-hours design doc, the plan design review (D4–D17) and fitness-app research |
