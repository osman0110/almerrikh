# Download MediaPipe Tasks Vision assets for NextKick offline/production use.
# Run from project root:  powershell -ExecutionPolicy Bypass -File scripts/download_mediapipe.ps1
#
# Downloads ~12 MB total:
#   web/assets/mediapipe/vision_bundle.mjs      (~850 KB)
#   web/assets/mediapipe/wasm/  (4 WASM/JS files, ~9 MB total)
#   web/assets/mediapipe/models/pose_landmarker_lite.task  (~1.7 MB)

$VERSION  = "0.10.14"
$BASE_CDN = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@$VERSION"
$MODEL_CDN = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task"

$DEST_DIR = "web/assets/mediapipe"

$files = @(
    @{ url = "$BASE_CDN/vision_bundle.mjs";                              out = "$DEST_DIR/vision_bundle.mjs" },
    @{ url = "$BASE_CDN/wasm/vision_wasm_internal.js";                  out = "$DEST_DIR/wasm/vision_wasm_internal.js" },
    @{ url = "$BASE_CDN/wasm/vision_wasm_internal.wasm";                out = "$DEST_DIR/wasm/vision_wasm_internal.wasm" },
    @{ url = "$BASE_CDN/wasm/vision_wasm_nosimd_internal.js";           out = "$DEST_DIR/wasm/vision_wasm_nosimd_internal.js" },
    @{ url = "$BASE_CDN/wasm/vision_wasm_nosimd_internal.wasm";         out = "$DEST_DIR/wasm/vision_wasm_nosimd_internal.wasm" },
    @{ url = $MODEL_CDN;                                                 out = "$DEST_DIR/models/pose_landmarker_lite.task" }
)

foreach ($f in $files) {
    $dir = Split-Path $f.out
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }

    if (Test-Path $f.out) {
        Write-Host "  SKIP (exists): $($f.out)"
        continue
    }

    Write-Host "  Downloading: $($f.url)"
    try {
        Invoke-WebRequest -Uri $f.url -OutFile $f.out -UseBasicParsing
        $size = (Get-Item $f.out).Length
        Write-Host "    -> $($f.out)  ($([math]::Round($size/1KB, 0)) KB)"
    } catch {
        Write-Error "    FAILED: $_"
        exit 1
    }
}

Write-Host ""
Write-Host "Done. All MediaPipe assets are in $DEST_DIR"
Write-Host "Run 'flutter build web --release' and upload build/web/ to your server."
