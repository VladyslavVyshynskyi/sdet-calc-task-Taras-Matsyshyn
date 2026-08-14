# Calculator SDET Task — Environment Setup

## Prerequisites (install these yourself)

- **Android Studio**, with the **API 34** platform installed and an emulator (AVD) added — any device profile.
- **Maestro CLI**, installed and on your `PATH`.
- A **JDK 21**. Android Studio bundles one (JBR 21) — point `JAVA_HOME` at it. Maestro's install page suggests a newer JDK (Oracle 26 / Temurin 25); that is too new for this build, so use JDK 21.

## Environment

Set **`ANDROID_HOME`** (path to your Android SDK) and **`JAVA_HOME`** (a JDK 21) in your shell, with `adb` and `maestro` on your `PATH`.

## Set up and verify — one command

From the project root, run the setup script:

```
./run.sh
```

`run.sh` checks your toolchain is present, auto-starts your emulator if one isn't already running, builds
the app, installs it, and runs **every** flow, printing a **result for every test**. **Every run is logged
in full to `logs/run-<timestamp>.log`, and Maestro's per-test output to `logs/maestro/`** — keep them; they
are what we use to debug a failing flow. Some flows are red on purpose (that is the exercise, not a setup
problem); setup is complete when the script prints **`SETUP OK`**.

## Ground rules

- Maestro Studio and the Maestro CLI interfere with each other when run at the same time, so keep Studio closed and drive everything from the CLI. (Android Studio itself is fine.)
- **One** Android emulator. No iOS Simulator, no second emulator.
