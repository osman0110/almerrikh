#!/usr/bin/env bash
# Build 18 hotfix gates for ITMS-90683 (CoreLocation pulled in by DKCamera via file_picker).
# Run on the Mac from the repo root. Do NOT upload Build 18 unless all three gates pass.
#
#   bash docs/apple_review/build18_location_gates.sh pods            # gate 1, after pod install
#   bash docs/apple_review/build18_location_gates.sh ipa <path.ipa>  # gates 2 + 3
set -u
PATTERN='CLLocationManager|requestWhenInUseAuthorization|startUpdatingLocation|DKCamera|DKImagePickerController|DKPhotoGallery'

case "${1:-}" in
  pods)
    echo "== Gate 1: ios/Podfile.lock must not list any DK pod"
    if grep -Ei "DKCamera|DKImagePickerController|DKPhotoGallery" ios/Podfile.lock; then
      echo "FAIL: DK pods still present. Do not build."; exit 1
    fi
    echo "PASS"
    ;;
  ipa)
    IPA="${2:?path to .ipa}"
    WORK=/tmp/almerrikh_ipa; rm -rf "$WORK"; mkdir -p "$WORK"
    unzip -q "$IPA" -d "$WORK" || { echo "unzip failed"; exit 1; }
    APP="$WORK/Payload/Runner.app"
    echo "== Info.plist usage keys in the IPA"
    plutil -p "$APP/Info.plist" | grep -E "UsageDescription|CFBundleVersion"
    echo "== Gate 2: strings scan of Runner + every embedded file"
    HITS=$(find "$APP" -type f -print0 | xargs -0 strings 2>/dev/null | grep -Ei "$PATTERN" | sort -u)
    if [ -n "$HITS" ]; then echo "$HITS"; echo "FAIL: location/DK symbols still present."; exit 1; fi
    echo "PASS"
    echo "== Gate 3: no Mach-O binary links CoreLocation"
    FAIL=0
    while IFS= read -r f; do
      if file "$f" | grep -q "Mach-O" && otool -L "$f" 2>/dev/null | grep -q CoreLocation; then
        echo "FOUND CoreLocation: $f"; FAIL=1
      fi
    done < <(find "$APP" -type f)
    [ "$FAIL" -eq 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
    echo "All gates passed. Device test: camera from assessment screen, xlsx import, file export/save."
    ;;
  *) echo "usage: $0 pods | ipa <file.ipa>"; exit 2 ;;
esac
