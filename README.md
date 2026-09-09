# AdSpeedHack v1.5.0

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


## v1.5.0 end-card experiment
- Removed the global 95% / 5-second normal-speed video tail from v1.4.0.
- Restored baseline HTML5 video acceleration: 16x playback, +0.75 s / 100 ms seeking, stopping 0.35 s before the media end.
- After an observed video end (or video disappearance after a video was seen), marks the page as end-card mode.
- In end-card mode, future JavaScript timers use native timing instead of the 8x playable timer acceleration.
- Playable canvas poke is not performed after end-card mode begins.
- Adds endcard_mode, endcard_reason, and endcard_entered_epoch_ms diagnostics.
- Reward success is never inferred or spoofed.
