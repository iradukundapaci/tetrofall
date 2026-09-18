#!/usr/bin/env bash
# App Store "app preview" video candidates for iOS — the video counterpart of
# capture_ios.sh. Apple caps an app preview at 15-30s, so this records the
# opening of three already-vetted honest reels (gameplay/README.md's "cuts
# 6-8 are honest play, so any of them can go on the store page" list) rather
# than authoring new gameplay just for a shorter cut.
#
#   tools/capture/capture_ios_previews.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PKG=com.nosleepstudios.tetrofall
APP=build/ios/iphonesimulator/Runner.app
LEN=28   # seconds recorded per preview; Apple's window is 15-30s.

IPHONE_67=8AEC863C-41ED-4E41-93B5-33C3C6936A9D   # 1284x2778
IPAD_129=69A807AB-4D3E-4191-A3E2-42156BFDA2C5    # 2048x2732

OUT_IPHONE=gameplay/ios_iphone_67_previews
OUT_IPAD=gameplay/ios_ipad_129_previews
mkdir -p "$OUT_IPHONE" "$OUT_IPAD"

for d in "$IPHONE_67" "$IPAD_129"; do
  xcrun simctl bootstatus "$d" -b >/dev/null 2>&1 || xcrun simctl boot "$d"
done

# name -> preview number, in the order they should read on the listing.
REELS=(01_skilled_run 06_endurance_2min 07_cascade_2min)

record() {
  local udid=$1 out=$2 n=$3
  xcrun simctl install "$udid" "$APP"
  xcrun simctl launch "$udid" "$PKG" >/dev/null
  sleep 5   # cold start + the harness's own ~1s opening hold before it reads as "on screen"

  local raw
  raw=$(mktemp -t tetrofall_preview).mov
  xcrun simctl io "$udid" recordVideo --codec h264 "$raw" &
  local rec_pid=$!
  sleep "$LEN"
  kill -INT "$rec_pid"
  wait "$rec_pid" 2>/dev/null || true

  xcrun simctl terminate "$udid" "$PKG" >/dev/null 2>&1 || true

  ffmpeg -y -loglevel error -i "$raw" -c copy "$out/preview$n.mp4"
  rm -f "$raw"
  echo "  -> $out/preview$n.mp4  $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration -of csv=p=0 "$out/preview$n.mp4")"
}

n=1
for reel in "${REELS[@]}"; do
  echo "+ $reel -> preview$n"
  flutter build ios --simulator --debug -t tools/capture/main.dart --dart-define=REEL="$reel" >/dev/null
  record "$IPHONE_67" "$OUT_IPHONE" "$n"
  record "$IPAD_129" "$OUT_IPAD" "$n"
  n=$((n + 1))
done

echo "done"
