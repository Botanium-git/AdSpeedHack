# AdSpeedHack v1.5.1

## Changes from v1.5.0

- Keeps baseline video acceleration restored in v1.5.0: 16x HTML5 playback plus the existing seek boost.
- Adds a Gossip-Harbor-style end-card transition candidate: when a video has reached the near-end region and then the same video resets to about 0 seconds without a normal `ended` event, ASH enters end-card mode with reason `video_reset_after_near_end`.
- In end-card mode, the seek boost no longer advances video elements.
- Timer acceleration is now end-card-aware even for timers that were created before end-card detection:
  - accelerated `setTimeout` callbacks wait out the remaining original real-time delay after end-card mode begins;
  - accelerated `setInterval` callbacks are gated to their original real-time cadence after end-card mode begins.
- Existing `video_ended` and `video_disappeared` end-card triggers remain in place.
- Existing end-card diagnostics (`endcard_mode`, `endcard_reason`, `endcard_entered_epoch_ms`) remain available.
- AVPlayer acceleration and ad fingerprint diagnostics are unchanged.
- No reward callback or server completion is spoofed.
