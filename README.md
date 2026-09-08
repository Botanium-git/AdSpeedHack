# AddSpeedHack

Current version: **v1.0.0**

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
AddSpeedHack-v1.0.1.dylib
```

and the artifact itself will be named:

```text
AddSpeedHack-v1.0.1
```

The internal Theos library product is `AddSpeedHack.dylib`.

Suggested numbering:
- small fix/logging change: 1.0.1, 1.0.2, ...
- new feature: 1.1.0, 1.2.0, ...
- major redesign: 2.0.0
