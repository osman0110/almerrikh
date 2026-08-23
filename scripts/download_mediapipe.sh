#!/usr/bin/env bash
# Download MediaPipe Tasks Vision assets for NextKick offline/production use.
# Run from project root:  bash scripts/download_mediapipe.sh
#
# Downloads ~12 MB total into web/assets/mediapipe/

set -e

VERSION="0.10.14"
BASE_CDN="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VERSION}"
MODEL_CDN="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task"
DEST="web/assets/mediapipe"

mkdir -p "${DEST}/wasm" "${DEST}/models"

download() {
    local url="$1" out="$2"
    if [ -f "$out" ]; then
        echo "  SKIP (exists): $out"
        return
    fi
    echo "  Downloading: $url"
    curl -fL --progress-bar "$url" -o "$out"
    echo "    -> $out  ($(du -sh "$out" | cut -f1))"
}

download "${BASE_CDN}/vision_bundle.mjs"                        "${DEST}/vision_bundle.mjs"
download "${BASE_CDN}/wasm/vision_wasm_internal.js"             "${DEST}/wasm/vision_wasm_internal.js"
download "${BASE_CDN}/wasm/vision_wasm_internal.wasm"           "${DEST}/wasm/vision_wasm_internal.wasm"
download "${BASE_CDN}/wasm/vision_wasm_nosimd_internal.js"      "${DEST}/wasm/vision_wasm_nosimd_internal.js"
download "${BASE_CDN}/wasm/vision_wasm_nosimd_internal.wasm"    "${DEST}/wasm/vision_wasm_nosimd_internal.wasm"
download "${MODEL_CDN}"                                          "${DEST}/models/pose_landmarker_lite.task"

echo ""
echo "Done. All MediaPipe assets in ${DEST}/"
echo "Run 'flutter build web --release' and upload build/web/ to your server."
