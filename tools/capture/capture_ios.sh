#!/usr/bin/env bash
# iOS counterpart of capture.sh — shoots the same store scenes on iOS
# Simulator devices sized to App Store Connect's exact required pixel
# dimensions, so nothing gets scaled or cropped at upload.
#
#   tools/capture/capture_ios.sh
#
# The capture harness (tools/capture/main.dart) has no platform-specific
# code, so the identical entrypoint that drives the Android AVDs drives the
# simulators here. A simulator .app is architecture-generic across every
# simulated device on the same runtime, so each scene is built once and then
# installed on every target device, exactly like capture.sh shares one APK
# build across the two Android tablet AVDs.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PKG=com.nosleepstudios.tetrofall
APP=build/ios/iphonesimulator/Runner.app

# UDIDs of the four simulators created for this pass, one per App Store
# Connect screenshot slot. `xcrun simctl list devices` shows the current set.
IPHONE_65=3A5AEB6A-93ED-48EA-8E83-E97A23649D1A   # iPhone 11 Pro Max  -> 1242x2688
IPHONE_67=8AEC863C-41ED-4E41-93B5-33C3C6936A9D   # iPhone 13 Pro Max  -> 1284x2778
IPAD_129=69A807AB-4D3E-4191-A3E2-42156BFDA2C5    # iPad Pro 12.9" 6th -> 2048x2732
IPAD_13=0E8D493C-AAB3-44A7-9D5B-750991A9FA3A     # iPad Pro 13" (M5)  -> 2064x2752

OUT_IPHONE_65=gameplay/ios_iphone_65
OUT_IPHONE_67=gameplay/ios_iphone_67
OUT_IPAD_129=gameplay/ios_ipad_129
OUT_IPAD_13=gameplay/ios_ipad_13
mkdir -p "$OUT_IPHONE_65" "$OUT_IPHONE_67" "$OUT_IPAD_129" "$OUT_IPAD_13"

for d in "$IPHONE_65" "$IPHONE_67" "$IPAD_129" "$IPAD_13"; do
  xcrun simctl bootstatus "$d" -b >/dev/null 2>&1 || xcrun simctl boot "$d"
done

# README's recommended phone order (gameplay/README.md); tablet is the
# 8-scene subset that already ships for Android's 10-inch slot.
PHONE_SCENES=(shatter chain_x3 rise_pressure deep_well ghost_drop tetrofall_clear late_game game_over cascade overhang)
TABLET_SCENES=(cascade chain_x3 deep_well ghost_drop late_game rise_pressure shatter tetrofall_clear)

in_tablet_set() {
  local s=$1
  for t in "${TABLET_SCENES[@]}"; do [[ "$t" == "$s" ]] && return 0; done
  return 1
}

shoot() {
  local udid=$1 out=$2 scene=$3
  xcrun simctl install "$udid" "$APP"
  xcrun simctl launch "$udid" "$PKG" >/dev/null
  sleep 15
  xcrun simctl io "$udid" screenshot "$out/$scene.png" >/dev/null
  echo "  -> $out/$scene.png  $(sips -g pixelWidth -g pixelHeight "$out/$scene.png" | tail -2 | tr '\n' ' ')"
  xcrun simctl terminate "$udid" "$PKG" >/dev/null 2>&1 || true
}

for scene in "${PHONE_SCENES[@]}"; do
  echo "+ $scene"
  flutter build ios --simulator --debug -t tools/capture/main.dart --dart-define=SCENE="$scene" >/dev/null
  shoot "$IPHONE_65" "$OUT_IPHONE_65" "$scene"
  shoot "$IPHONE_67" "$OUT_IPHONE_67" "$scene"
  if in_tablet_set "$scene"; then
    shoot "$IPAD_129" "$OUT_IPAD_129" "$scene"
    shoot "$IPAD_13" "$OUT_IPAD_13" "$scene"
  fi
done

echo "done"
