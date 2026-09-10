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


## v1.7.0
- Restores baseline full-speed HTML5 behavior; removes v1.5.x end-card slowdown.
- Selective 20-second real-elapsed gate only for known problem creative families.
- Current signatures: Gossip Harbor (`oe8f937c_`) and Meje Kyodan (`o6b5ee74_`). Unknown ads get no added wait.
- Gate remainder is `max(0, 20s - real_ad_elapsed_seconds)`.
- Adds real elapsed/gate diagnostics.
- Extends WKWebView removal grace from 1.5s to 6s to reduce split sessions during transitions.
- VoidPet is not hard-coded yet because available VoidPet logs predate stable v1.3+ identity data; this avoids slowing unrelated ads.
- No reward callback/server completion spoofing.


## v1.7.0
- Removed the v1.6.0 20-second close gate.
- Known unresolved ad families only: accelerate until the final 20 seconds of the video, then switch video playback to 1x and stop seek-boosting.
- Ads that already work remain on the original full-speed path with no added wait or slow tail.
- The 6-second session-removal grace from v1.6.0 is retained to avoid split logs.
- Logs now include problem_tail_active/problem_tail_seconds/problem_tail_reason and per-video ash_tail_active.
- No reward callback or server-completion spoofing.


## v1.8.1
- Restores full-speed behavior for all ads; the v1.7.0 20-second normal-speed tail is disabled.
- Keeps known-problem-family tagging for Gossip Harbor / Meje Kyodan style assets, but does not infer reward success.
- Adds read-only asynchronous diagnostics for resource loads, fetch/XHR, window message events, visibility/page lifecycle, and video playing/ended events.
- `wk_probe` includes only newly observed async events (`async_events_new`) to compare user-confirmed reward-success and reward-failure runs.
- No reward callbacks or server completion are spoofed.
