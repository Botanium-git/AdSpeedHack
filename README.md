# AdSpeedHack

Current version: **v1.2.6**

This starts from the known v2 runtime behavior.

## Versioning

The release/build version is stored in the `VERSION` file.

For the next build, change only:

```text
1.0.0
```

to, for example:

```text
1.0.1
```

GitHub Actions will then produce:

```text
AdSpeedHack_ver.1.0.1.dylib
```

and the artifact itself will be named:

```text
AdSpeedHack_ver.1.0.1
```

The internal Theos library product is `AdSpeedHack.dylib`.

Suggested numbering:
- small fix/logging change: 1.0.1, 1.0.2, ...
- new feature: 1.1.0, 1.2.0, ...
- major redesign: 2.0.0


## v1.2.6

- Compile-only cleanup: removed obsolete unused logging helpers left behind by the ad-session logger migration.
- Unified user-facing product/build naming to `AdSpeedHack`; diagnostic log files remain `ASH_ver.x.x.x_log_XX.jsonl`.

## v1.2.5

- Parent ad-session logging: multiple WKWebViews from one ad share one JSONL file.
- Strong evidence (`video` / `canvas`) confirms the session immediately.
- Weak `iframe_only_candidate` evidence starts a low-confidence pending session instead of being discarded.
- Multiple weak sources can promote confidence to medium; strong evidence promotes to high.
- Adds WebView detach/removal observations and closes a session when its last participating WebView is removed.
- Keeps a stale-session fallback so a later unrelated ad can start a fresh log.


## v1.3.0
- Added read-only ad fingerprint diagnostics for future per-ad optimization profiles.
- Logs `ad_fingerprint`, `optimization_profile_key`, `ad_network_candidate`, `creative_id_candidates`, and fingerprint inputs.
- Fingerprints use normalized page/video/iframe URLs and rounded original video duration, with a deterministic FNV-1a 64-bit key.
- No reward callback spoofing. No acceleration behavior changes from v1.2.6.
