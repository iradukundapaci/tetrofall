#!/usr/bin/env bash
# Drives the whole store-capture pipeline against running emulators.
#
#   tools/capture/capture.sh shots gameplay/phone shatter cascade ...
#   tools/capture/capture.sh shots gameplay/tablet7@emulator-5556,gameplay/tablet10@emulator-5558 shatter ...
#   tools/capture/capture.sh reel  gameplay/video 02_blunder_i_well
#
# The target argument is one or more comma-separated `outdir[@serial]` pairs.
# A bare `outdir` shoots whatever single device `adb` is talking to, which is
# how the phone pass ran; naming serials is what lets several AVDs share one
# build. Each scene is built once, then installed, launched and photographed
# on every target in turn. That is only safe because the harness freezes the
# frame before the screencap: a device shot two seconds after the first still
# yields the identical frame, not a later one.
#
# The Android SDK is not on PATH on this machine, so every binary is
# addressed absolutely. Nothing here assumes a particular AVD: boot the ones
# you want first, and this shoots whatever you point it at.
#
# Builds are `--profile`, not `--release`: the release signing config points
# at a keystore held outside the repo (`~/keystores/tetrofall-upload.jks`)
# that isn't present, and profile is the same AOT build with the same fonts,
# colours and shaders — only the signing key and `kReleaseMode` differ, and
# nothing visual reads either.
set -euo pipefail

ANDROID_HOME=${ANDROID_HOME:-/Users/pacifique/Library/Android/sdk}
ADB="$ANDROID_HOME/platform-tools/adb"
APK=build/app/outputs/flutter-apk/app-profile.apk
PKG=com.nosleepstudios.tetrofall
ACTIVITY="$PKG/.MainActivity"

MODE=${1:?usage: capture.sh shots|reel <outdir[@serial][,...]> <name>...}
TARGET_ARG=${2:?missing output directory}
shift 2

OUTDIRS=()
SERIALS=()
IFS=',' read -r -a _specs <<< "$TARGET_ARG"
for spec in "${_specs[@]}"; do
  OUTDIRS+=("${spec%%@*}")
  if [[ "$spec" == *@* ]]; then SERIALS+=("${spec#*@}"); else SERIALS+=(""); fi
done
NTARGETS=${#OUTDIRS[@]}

for d in "${OUTDIRS[@]}"; do mkdir -p "$d"; done

# `adb` against one target. An empty serial means "the only device attached",
# which is what the single-device invocations rely on.
adb_at() {
  local i=$1; shift
  if [ -n "${SERIALS[$i]}" ]; then
    "$ADB" -s "${SERIALS[$i]}" "$@"
  else
    "$ADB" "$@"
  fi
}

# Android's demo mode: a fixed 12:00 clock, a full battery, four bars of
# wifi and no notification icons. Without it the status bar dates every
# screenshot and leaks whatever the emulator happened to be doing.
demo_mode() {
  local i=$1
  adb_at "$i" shell settings put global sysui_demo_allowed 1 >/dev/null
  adb_at "$i" shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
  adb_at "$i" shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200 >/dev/null
  adb_at "$i" shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
  adb_at "$i" shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 >/dev/null
  adb_at "$i" shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null
}

# Android 16 ignores an app's orientation lock on screens wider than 600dp,
# so the tablet passes have to be pinned from outside the app.
lock_portrait() {
  local i=$1
  adb_at "$i" shell settings put system accelerometer_rotation 0 >/dev/null
  adb_at "$i" shell settings put system user_rotation 0 >/dev/null
}

# The app mounts `immersiveSticky`, and the first time a device sees that it
# throws up a system dialog — "Viewing full screen / swipe down to exit / Got
# it" — across the top of the screen. It is a system window, so Android also
# dims the app behind it: the capture comes out both covered and two stops
# dark. Confirming it up front is the only way to keep it off every frame.
# The phone AVD had this dismissed by hand long ago, which is why the phone
# pass never showed it and a fresh AVD did.
confirm_immersive() {
  adb_at "$1" shell settings put secure immersive_mode_confirmations confirmed >/dev/null
}

build() {
  flutter build apk --profile -t tools/capture/main.dart "$@" >/dev/null
}

# -r reinstalls in place; without it a differing dart-define set would be
# rejected as a duplicate package.
install_at() { adb_at "$1" install -r -d "$APK" >/dev/null; }

launch_at() {
  adb_at "$1" logcat -c >/dev/null 2>&1 || true
  adb_at "$1" shell am force-stop "$PKG" >/dev/null
  adb_at "$1" shell am start -n "$ACTIVITY" >/dev/null
}

# Block until the harness says the board is seeded and drawn, rather than
# sleeping a guessed number of seconds. Cold start on this machine ranged
# from two to five seconds depending on how many emulators were running, and
# every reel take that guessed short opened on an empty board — the score
# seeded and the stack not yet drawn.
wait_ready() {
  local i=$1 n=0
  until adb_at "$i" logcat -d -s flutter:I 2>/dev/null | grep -q TETROFALL_CAPTURE_READY; do
    n=$((n + 1))
    if [ "$n" -gt 120 ]; then
      echo "  ! timed out waiting for the capture-ready marker" >&2
      return 1
    fi
    sleep 0.5
  done
}

png_size() {
  python3 -c "
from PIL import Image
im = Image.open('$1'); print(f'{im.width}x{im.height}')"
}

for ((i = 0; i < NTARGETS; i++)); do
  demo_mode "$i"
  lock_portrait "$i"
  confirm_immersive "$i"
done

case "$MODE" in
  shots)
    for scene in "$@"; do
      echo "▸ $scene"
      build --dart-define=SCENE="$scene"
      for ((i = 0; i < NTARGETS; i++)); do
        install_at "$i"
        launch_at "$i"
      done

      # The harness seeds at 700ms and then holds for the scene's own settle
      # or freeze delay; 14s clears the slowest of them (the menu's attract
      # run) with room for a cold start on top.
      # The tutorial opens on a "HOW TO PLAY" modal that dims and blurs the
      # board. Tap through it to a coached step, where the board is live and
      # the gesture hint is on screen. The fractions are calibrated on the
      # 1080x1920 phone layout and read off each device's real size, so they
      # at least land in the right band on a differently sized screen.
      if [ "$scene" = tutorial ]; then
        sleep 5
        for ((i = 0; i < NTARGETS; i++)); do
          read -r w h < <(adb_at "$i" shell wm size | sed 's/.*: //; s/x/ /')
          adb_at "$i" shell input tap $((w / 2)) $((h * 574 / 1000)) >/dev/null  # Let's Go
        done
        sleep 4
        for ((i = 0; i < NTARGETS; i++)); do
          read -r w h < <(adb_at "$i" shell wm size | sed 's/.*: //; s/x/ /')
          adb_at "$i" shell input tap $((w / 2)) $((h / 2)) >/dev/null  # dismiss the first caption
        done
        sleep 7
      else
        sleep 15
      fi

      for ((i = 0; i < NTARGETS; i++)); do
        out="${OUTDIRS[$i]}/$scene.png"
        adb_at "$i" exec-out screencap -p > "$out"
        echo "  → $out  $(png_size "$out")"
      done
    done
    ;;

  reel)
    reel=$1
    secs=$(python3 - "$reel" <<'PY'
import re, sys
src = open('tools/capture/reels.dart').read()
block = src.split(f"name: '{sys.argv[1]}'", 1)[1]
print(re.search(r'seconds:\s*(\d+)', block).group(1))
PY
)
    echo "▸ $reel (${secs}s)"
    build --dart-define=REEL="$reel"
    for ((i = 0; i < NTARGETS; i++)); do
      install_at "$i"
      launch_at "$i"
      wait_ready "$i"
      adb_at "$i" shell screenrecord --bit-rate 16000000 --time-limit "$secs" /sdcard/reel.mp4
      adb_at "$i" pull /sdcard/reel.mp4 "${OUTDIRS[$i]}/$reel.mp4" >/dev/null
      adb_at "$i" shell rm /sdcard/reel.mp4
      echo "  → ${OUTDIRS[$i]}/$reel.mp4"
    done
    ;;

  *)
    echo "unknown mode '$MODE' (want: shots | reel)" >&2
    exit 2
    ;;
esac
