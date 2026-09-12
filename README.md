# AdSpeedHack v1.10.0

v1.10.0 changes only the targeted problem-ad timing and session/log continuity logic.

## Runtime behavior

- Normal ads keep the existing full-speed behavior.
- Known problem families currently recognized:
  - Gossip Harbor (`oe8f937c_`)
  - VoidPet (`o9147b6a_`)
  - Meje Kyodan (`o6b5ee74_`)
- These families are accelerated immediately.
- Their HTML5 video is prevented from reaching the terminal end while the first 25 seconds of real wall-clock time have not elapsed.
- Once 25 seconds have elapsed, playback is released and may finish normally.
- This does not spoof reward callbacks, SDK completion events, network responses, or reward state.
- Diagnostic fields report the family, elapsed real time, and whether the 25-second minimum has elapsed.

The 25-second value is intentionally conservative and remains a test value; the actual lower boundary has not yet been established.

## Log continuity

Before a new JSONL is committed, ASH checks the immediately preceding session.

A previous log is reused only when:
- the gap is at most 6 seconds,
- the new fingerprint was already observed in that session, and
- creative IDs do not conflict when both sides provide them.

Each active session keeps the set of every fingerprint observed because a fingerprint can evolve while one ad is loading.

A successful merge writes `ad_session_reconnected_by_fingerprint` to the existing JSONL and keeps the existing `ad_session_id`.

This is deliberately narrower than merging every matching fingerprint: the same creative shown again later must remain a separate ad/log.

## Unchanged

- HTML5 playback rate / seek boost
- playable timer acceleration
- same-origin iframe acceleration
- AVPlayer acceleration
- weak iframe candidate policy
- reward success is never inferred from SDK/network/video events
