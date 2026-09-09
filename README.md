# AdSpeedHack v1.4.0

## Changes

- Keeps the v1.3.0 ad fingerprint / identity logging foundation.
- HTML5 rewarded-video acceleration now uses a protected normal-speed tail.
- Fast phase: 16x playback + existing seek boost.
- Tail rule: acceleration stops at the earlier of 95% progress or 5 seconds remaining.
- Tail phase: 1.0x playback, no seek boost.
- Added tail-state diagnostics to logs (`ash_tail_active`, `ash_tail_entered_wall_seconds`).
- AVPlayer acceleration remains unchanged at 600x for this experiment.
- Playable timer acceleration remains unchanged at 8x.

This version intentionally changes only the HTML5 video tail behavior so reward compatibility can be tested without mixing multiple behavioral changes.
