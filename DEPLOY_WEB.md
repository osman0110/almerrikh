# NextKick — Web Deployment Guide

## Quick deploy checklist

- [ ] 1. Download MediaPipe assets (one-time, ~12 MB)
- [ ] 2. Build Flutter web release
- [ ] 3. Upload `build/web/` to server over HTTPS
- [ ] 4. Verify camera works on Chrome Android
- [ ] 5. Verify pose skeleton appears after ~3-5 s model load

---

## Step 1 — Download MediaPipe local assets

Run **once** before building. Assets are saved to `web/assets/mediapipe/`.

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/download_mediapipe.ps1
```

**macOS / Linux:**
```bash
bash scripts/download_mediapipe.sh
```

Files downloaded (~12 MB total):
```
web/assets/mediapipe/
  vision_bundle.mjs               (~136 KB)
  wasm/
    vision_wasm_internal.js        (~208 KB)
    vision_wasm_internal.wasm      (~9 MB)
    vision_wasm_nosimd_internal.js (~208 KB)
    vision_wasm_nosimd_internal.wasm (~8.9 MB)
  models/
    pose_landmarker_lite.task      (~5.6 MB)
```

> **Note:** If local assets are missing at runtime, the JS engine automatically
> falls back to CDN (internet required). This is fine for development but
> must not be relied on for production/demo.

---

## Step 2 — Build Flutter web release

```bash
flutter clean
flutter pub get
flutter build web --release
```

Output: `build/web/`

---

## Step 3 — Upload to cPanel / shared hosting

Upload the **entire contents of `build/web/`** to your `public_html/` folder
(or a subfolder like `public_html/nextkick/`).

Required structure on server:
```
public_html/
  index.html
  flutter.js
  flutter_bootstrap.js
  main.dart.js
  assets/
  canvaskit/
  .htaccess                    ← included in build/web/
  mediapipe/
    nextkick_pose_web.js
  assets/
    mediapipe/                 ← MediaPipe local assets
      vision_bundle.mjs
      wasm/
      models/
```

### Subfolder deployment

If deploying to `https://yourdomain.com/nextkick/`:

1. Flutter automatically injects `<base href="/nextkick/">` during build.
   Pass it explicitly:
   ```bash
   flutter build web --release --base-href /nextkick/
   ```

2. Update `.htaccess` `RewriteBase` to `/nextkick/` instead of `/`.

---

## Step 4 — SSL / HTTPS requirement

**Camera access requires HTTPS.** getUserMedia and WebAssembly are blocked on HTTP.

In cPanel:
1. Go to SSL/TLS → Install SSL
2. Enable AutoSSL (Let's Encrypt)
3. Once SSL is active, uncomment the HTTPS redirect block in `.htaccess`

---

## Step 5 — Verify MIME types

Your server must serve `.wasm` and `.task` files with the correct MIME type.
The `.htaccess` file handles this automatically with Apache.

Check in browser DevTools → Network:
- `vision_wasm_internal.wasm` → `application/wasm`
- `pose_landmarker_lite.task` → `application/octet-stream`

If WASM fails to load, you may need to ask your host to enable the MIME type
globally, or switch to a host that supports Apache `.htaccess` overrides.

---

## Testing camera

### Chrome Android (recommended)
1. Open `https://yourdomain.com` on Android Chrome
2. Allow camera when prompted
3. Navigate to any assessment
4. Select camera (Back Camera recommended)
5. After ~3-5 seconds the AI model loads → skeleton appears

### Safari iPhone
1. Open `https://yourdomain.com` in Safari
2. Camera permission prompt appears
3. Skeleton may take 5-10 seconds on older iPhones (CPU-only inference)
4. If camera appears but no skeleton: check console for WASM errors
5. If "HTTPS required" message appears: verify SSL certificate is active

### Desktop Chrome (development)
```bash
flutter run -d chrome
```
Uses CDN fallback automatically if local assets not downloaded yet.

---

## Known limitations

| Limitation | Affected | Workaround |
|-----------|---------|-----------|
| Inference runs on CPU (no GPU/WebGPU) | All web | Intentional for Safari compatibility |
| FPS ~15-20 on older phones | Low-end devices | Warning shown in UI |
| Photo upload in player profile | Web only | Blob URL path not supported by server upload |
| Orientation lock not enforced | Web | User must hold phone appropriately |

---

## Files that must exist on server

These are automatically included in `build/web/` after running the build.
Manual upload is only needed if the build was done WITHOUT downloading assets first.

| File | Size | Required? |
|------|------|-----------|
| `mediapipe/nextkick_pose_web.js` | ~5 KB | Yes |
| `assets/mediapipe/vision_bundle.mjs` | ~136 KB | Yes (or CDN fallback) |
| `assets/mediapipe/wasm/*.wasm` | ~18 MB total | Yes (or CDN fallback) |
| `assets/mediapipe/models/pose_landmarker_lite.task` | ~5.6 MB | Yes (or CDN fallback) |

---

## Troubleshooting

**"Camera requires HTTPS" message**
→ SSL not active or redirect not enabled. Enable AutoSSL in cPanel.

**Camera permission popup never appears**
→ Not on HTTPS, or browser blocked camera at OS level. Check browser settings.

**Skeleton never appears (model spinner stays)**
→ MediaPipe failed to load. Open DevTools → Console for error.
→ Common cause: WASM MIME type not configured. Check `.htaccess`.

**"Local assets failed, falling back to CDN"**
→ `web/assets/mediapipe/` missing. Run download script, rebuild, re-upload.

**Safari: camera opens but no skeleton**
→ iOS CPU inference can be slow. Wait 5-10 seconds.
→ Check console for `MediaPipe` or `WASM` errors.

**CORS error on WASM**
→ Some hosts block WASM loading. May need to enable COOP/COEP headers
   (see commented section in `.htaccess`) or use a different host.
