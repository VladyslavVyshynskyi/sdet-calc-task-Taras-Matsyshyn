#!/usr/bin/env bash
#
# run.sh — build the calculator, install it, and run every Maestro flow, printing
# a result for every test. This is a RUNNER (like the shared QE automation
# harness's run scripts) — it does NOT install your toolchain; set that up
# yourself per README.md first. It only checks the toolchain is present, then
# auto-starts the first installed AVD if no emulator is already running (it
# launches an existing AVD — it does not create one; if you have NO AVD it stops
# with a clear error).
#
# Every run is logged in full to logs/run-<timestamp>.log, and Maestro's per-test
# output (per-flow logs, screenshots, report) is collected under logs/maestro/.
#
# Usage:  ./run.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
mkdir -p logs
TS="$(date +%Y-%m-%d_%H-%M-%S)"
LOG="logs/run-$TS.log"
REPORT="logs/results-$TS.xml"

# Mirror all output (stdout + stderr) to the console AND the log file.
exec > >(tee -a "$LOG") 2>&1

echo "=== sdet-calc-task run.sh @ $TS ==="
echo "log: $LOG"

fail() {
  echo
  echo "FAILED: $*"
  echo "Full log: $LOG  —  if you are stuck for more than 60 min, contact your interviewer."
  exit 1
}

# 1. Toolchain checks (must already be installed — this script does not install it) ----
echo
echo "--- checks ---"
command -v adb     >/dev/null 2>&1 || fail "adb not found — install Android Studio (SDK Platform-Tools) and put platform-tools on your PATH."
command -v maestro >/dev/null 2>&1 || fail "maestro not found — install the Maestro CLI, then open a new terminal."
{ [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; } || command -v java >/dev/null 2>&1 || fail "no JDK — point JAVA_HOME at Android Studio's bundled JBR (see README.md)."
# Assert the JDK major AGP 8.5 needs (17-21; Android Studio's JBR is 21).
jbin="java"; { [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; } && jbin="$JAVA_HOME/bin/java"
jmajor="$("$jbin" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -1)"
if [ -n "$jmajor" ]; then
  [ "$jmajor" -ge 17 ] 2>/dev/null || fail "JDK $jmajor is too old — AGP 8.5 needs JDK 17-21 (Android Studio's JBR is 21). Point JAVA_HOME at the JBR."
  [ "$jmajor" -gt 21 ] 2>/dev/null && echo "WARNING: JDK $jmajor is newer than the certified JDK 21 — the build may warn/fail; point JAVA_HOME at Android Studio's JBR 21 if so."
fi
[ -x ./gradlew ] || fail "./gradlew is missing or not executable — run: chmod +x gradlew"

# Make sure an emulator is running. If none is connected, auto-start the FIRST
# installed AVD (this only launches an already-installed AVD — it does NOT install
# the toolchain). If there is NO AVD at all, stop with a clear error.
if [ -z "$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')" ]; then
  emu=""
  if command -v emulator >/dev/null 2>&1; then
    emu="emulator"
  else
    for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk"; do
      [ -n "$d" ] && [ -x "$d/emulator/emulator" ] && { emu="$d/emulator/emulator"; break; }
    done
  fi
  [ -n "$emu" ] || fail "emulator binary not found — install Android Studio's Emulator (SDK component) and set ANDROID_HOME (see README.md)."
  avd="$("$emu" -list-avds 2>/dev/null | head -1)"
  [ -n "$avd" ] || fail "NO AVD FOUND — create one in Android Studio (Device Manager), e.g. a Pixel with API 34, then re-run ./run.sh."
  echo "no emulator connected — starting AVD '$avd' (cold boot can take a few minutes)..."
  "$emu" -avd "$avd" >"logs/emulator-$TS.log" 2>&1 &
fi

# Wait for an emulator to finish booting (cold boot is ~2-5 min) so the check below is not a race.
boot_tries=0
until [ -n "$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')" ] \
   && [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  boot_tries=$((boot_tries + 1))
  [ "$boot_tries" -eq 1 ] && echo "waiting for the emulator to finish booting (up to ~5 min)..."
  [ "$boot_tries" -ge 150 ] && break
  sleep 2
done

devices="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
[ "$(printf '%s\n' "$devices" | grep -c .)" -eq 1 ] || fail "expected exactly ONE running emulator in state 'device' — none finished booting in time, or more than one device is connected. Start a single AVD, wait for the home screen, then re-run ./run.sh."

echo "adb:     $(command -v adb)"
echo "maestro: $(maestro --version 2>/dev/null | tail -1)"
echo "jdk:     ${jmajor:-unknown}"
echo "device:  $devices"

# 2. Build --------------------------------------------------------------------------
echo
echo "--- build ---"
./gradlew assembleDebug || fail "Gradle build failed — if it says 'SDK location not found', set ANDROID_HOME to your Android SDK. Otherwise check JAVA_HOME (a JDK 17-21) and that SDK API 34 is installed."
apk="app/build/outputs/apk/debug/app-debug.apk"
[ -f "$apk" ] || fail "APK not found at $apk after a successful build."

# 3. Install ------------------------------------------------------------------------
echo
echo "--- install ---"
adb install -r "$apk" || fail "adb install failed."

# 4. Run every flow (a result for every test). A non-zero Maestro exit is EXPECTED
#    here — some flows are meant to be red; the per-test summary below is the point.
echo
echo "--- run: all flows ---"
maestro test flows/ --format junit --output "$REPORT" || true
[ -f "$REPORT" ] || fail "Maestro produced no report at $REPORT — did the run start? Check $LOG."

# 5. Per-test result summary (parsed from the JUnit report) -------------------------
echo
echo "=== TEST RESULTS ==="
smoke_ok=0; total=0; passed=0
while IFS= read -r line; do
  name="$(printf '%s' "$line"   | sed -E 's/.*<testcase[^>]* name="([^"]+)".*/\1/')"
  status="$(printf '%s' "$line" | sed -E 's/.*status="([^"]+)".*/\1/')"
  case "$status" in SUCCESS) res="PASS" ;; *) res="FAIL" ;; esac
  printf '  %-14s %s\n' "$name" "$res"
  total=$((total + 1)); [ "$res" = "PASS" ] && passed=$((passed + 1))
  [ "$name" = "smoke" ] && [ "$res" = "PASS" ] && smoke_ok=1
done < <(grep '<testcase ' "$REPORT")
echo "  ---"
echo "  $passed/$total passed   (report: $REPORT)"

# 6. Environment verdict (build + install + the smoke flow), independent of
#    the triage flows' pass/fail.
echo
if [ "$smoke_ok" -eq 1 ]; then
  echo "=== SETUP OK — build, install, and the Maestro harness all work (smoke green). ==="
  echo "Per-test results are above; full log $LOG; Maestro per-test output in logs/maestro/."
  exit 0
fi
fail "the smoke flow did not pass (smoke=$smoke_ok) — the app may not be launching or installing. See $LOG."
