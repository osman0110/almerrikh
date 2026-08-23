/**
 * NextKick Pose Web — MediaPipe PoseLandmarker integration
 *
 * ARCHITECTURE
 *   - This module handles ML inference ONLY.
 *   - The camera (video element) is managed by Flutter/Dart.
 *   - Dart calls preload() first (setup screen), then initialize({videoElementId}) → start() → stop().
 *   - Landmark data is returned as a Float32Array via getLatestLandmarks().
 *     Format: 33 × 4 floats = [x,y,z,vis, x,y,z,vis, ...]
 *
 * LOCAL ASSETS
 *   Expects files at paths relative to this script:
 *     ../assets/mediapipe/vision_bundle.mjs
 *     ../assets/mediapipe/wasm/
 *     ../assets/mediapipe/models/pose_landmarker_lite.task
 *
 * PRELOAD API (setup screen)
 *   preload()              — load model WITHOUT starting camera/RAF loop
 *   getProgress()          — 0–100 loading progress
 *   isReady()              — true when model is ready to run
 *   checkBrowserSupport()  — sync check for HTTPS / WebAssembly / camera API
 *   testCameraAccess()     — request getUserMedia briefly to test camera
 *   getCameraPermissionState() — query permission without asking
 *   verifyAssets()         — HEAD-check key local files
 */

'use strict';

(function () {
  // ── Path resolution ───────────────────────────────────────────────────────
  const SCRIPT_DIR   = new URL('.', import.meta.url).href;
  const LOCAL_BASE   = SCRIPT_DIR + '../assets/mediapipe/';
  const LOCAL_VISION = LOCAL_BASE + 'vision_bundle.mjs';
  const LOCAL_WASM   = LOCAL_BASE + 'wasm';
  const LOCAL_MODEL  = LOCAL_BASE + 'models/pose_landmarker_lite.task';

  const _IS_DEV_HOST = (
    window.location.hostname === 'localhost' ||
    window.location.hostname === '127.0.0.1'
  );
  const CDN_BASE   = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/';
  const CDN_VISION = CDN_BASE + 'vision_bundle.mjs';
  const CDN_WASM   = CDN_BASE + 'wasm';
  const CDN_MODEL  = 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task';

  // ── State machine ─────────────────────────────────────────────────────────
  const STATE = Object.freeze({
    IDLE:     'idle',
    LOADING:  'loading',
    READY:    'ready',
    RUNNING:  'running',
    STOPPED:  'stopped',
    ERROR:    'error',
  });

  const LANDMARK_COUNT = 33;
  const FLOATS_PER_LM  = 4;

  // ── Helper ────────────────────────────────────────────────────────────────
  function _isSecureEnv() {
    return window.isSecureContext === true ||
      window.location.hostname === 'localhost' ||
      window.location.hostname === '127.0.0.1';
  }

  const API = {
    _state:           STATE.IDLE,
    _errorMessage:    null,
    _landmarker:      null,
    _videoId:         'nk-pose-video',
    _rafId:           null,
    _videoWatcherId:  null,
    _lastVideoTime:   -1,
    _landmarkBuf:     new Float32Array(LANDMARK_COUNT * FLOATS_PER_LM),
    _hasLandmarks:    false,
    _inferenceActive: false,
    _progress:        0,
    _loadPromise:     null,
    _firstRafLog:     false, // log video state on first _rafLoop execution

    // FPS tracking
    _fpsBuffer:  new Float64Array(30),
    _fpsBufIdx:  0,
    _fps:        0,

    // ── Public setup API ─────────────────────────────────────────────────────

    preload: async function (config) {
      if (config && config.videoElementId) API._videoId = config.videoElementId;

      if (API._state === STATE.READY || API._state === STATE.RUNNING) {
        return { success: true, status: 'ready', cached: true };
      }
      if (API._state === STATE.ERROR) {
        API._state = STATE.IDLE;
        API._errorMessage = null;
        API._loadPromise = null;
      }
      if (API._loadPromise) return API._loadPromise;

      API._loadPromise = (async () => {
        API._state   = STATE.LOADING;
        API._progress = 5;
        try {
          if (!_isSecureEnv()) {
            throw new Error('HTTPS_REQUIRED');
          }
          API._progress = 15;

          const { PoseLandmarker, vision, modelPath } = await API._loadMediaPipe();
          API._progress = 65;

          API._landmarker = await PoseLandmarker.createFromOptions(vision, {
            baseOptions: {
              modelAssetPath: modelPath,
              delegate: 'CPU',
            },
            runningMode:               'VIDEO',
            numPoses:                  1,
            minPoseDetectionConfidence: 0.40,
            minPosePresenceConfidence:  0.40,
            minTrackingConfidence:      0.40,
            outputSegmentationMasks:   false,
          });

          API._progress = 100;
          API._state    = STATE.READY;
          API._loadPromise = null;
          return { success: true, status: 'ready', cached: false };
        } catch (err) {
          const msg = err.message || String(err);
          API._setError('Model load failed: ' + msg);
          API._loadPromise = null;
          return { success: false, status: 'error', error: msg };
        }
      })();

      return API._loadPromise;
    },

    getProgress: function () { return API._progress; },

    isReady: function () {
      return API._state === STATE.READY || API._state === STATE.RUNNING;
    },

    checkBrowserSupport: function () {
      const secure = _isSecureEnv();
      const hasMedia = !!(
        navigator.mediaDevices &&
        typeof navigator.mediaDevices.getUserMedia === 'function'
      );
      const hasWasm = typeof WebAssembly === 'object' &&
                      typeof WebAssembly.instantiate === 'function';
      return {
        isSecureContext: secure,
        hasMediaDevices: hasMedia,
        hasWebAssembly:  hasWasm,
        supported:       secure && hasMedia && hasWasm,
      };
    },

    verifyAssets: async function () {
      const toCheck = [LOCAL_VISION, LOCAL_MODEL];
      const missing = [];
      for (const url of toCheck) {
        let found = false;
        try {
          const r = await fetch(url, { method: 'HEAD', cache: 'default' });
          found = r.ok;
        } catch (_) {
          try {
            const r2 = await fetch(url, { cache: 'default' });
            found = r2.ok;
            if (r2.body) await r2.body.cancel().catch(() => {});
          } catch (_2) { /* not found */ }
        }
        if (!found) missing.push(url.split('/').pop());
      }
      return { ok: missing.length === 0, missing };
    },

    testCameraAccess: async function () {
      try {
        let permState = 'prompt';
        try {
          const ps = await navigator.permissions.query({ name: 'camera' });
          permState = ps.state;
        } catch (_) {}

        if (permState === 'denied') {
          return { ok: false, state: 'denied', error: 'NotAllowedError' };
        }

        const stream = await navigator.mediaDevices.getUserMedia({
          video: true,
          audio: false,
        });
        stream.getTracks().forEach(t => t.stop());
        return { ok: true, state: 'granted' };
      } catch (err) {
        return { ok: false, state: 'denied', error: err.name || String(err) };
      }
    },

    getCameraPermissionState: async function () {
      try {
        const ps = await navigator.permissions.query({ name: 'camera' });
        return ps.state;
      } catch (_) {
        return 'unknown';
      }
    },

    // ── Exercise API ─────────────────────────────────────────────────────────

    initialize: async function (config) {
      if (config && config.videoElementId) API._videoId = config.videoElementId;

      if (API._state === STATE.READY || API._state === STATE.RUNNING) {
        return;
      }
      if (API._state === STATE.LOADING && API._loadPromise) {
        await API._loadPromise;
        return;
      }

      await API.preload(config);
    },

    start: function () {
      if (API._state === STATE.RUNNING) return;
      if (API._state === STATE.ERROR)   return;
      API._state         = STATE.RUNNING;
      API._lastVideoTime = -1;
      API._hasLandmarks  = false;
      API._firstRafLog   = false;
      API._rafLoop();
      API._startVideoWatcher(); // ← Start live video health watcher
    },

    stop: function () {
      if (API._rafId !== null) {
        cancelAnimationFrame(API._rafId);
        API._rafId = null;
      }
      API._stopVideoWatcher();
      API._hasLandmarks = false;
      if (API._state === STATE.RUNNING) API._state = STATE.STOPPED;
    },

    dispose: function (options) {
      const keepModel = options && options.keepModel === true;
      API.stop(); // also stops watcher
      if (!keepModel) {
        if (API._landmarker) {
          try { API._landmarker.close(); } catch (_) {}
          API._landmarker = null;
        }
        API._state    = STATE.IDLE;
        API._progress = 0;
        API._loadPromise = null;
      } else {
        if (API._state === STATE.STOPPED) API._state = STATE.READY;
      }
      API._errorMessage = null;
    },

    // ── Status accessors ─────────────────────────────────────────────────────

    getStatus:          function () { return API._state; },
    getLastError:       function () { return API._errorMessage; },
    getFps:             function () { return Math.round(API._fps * 10) / 10; },
    getLatestLandmarks: function () {
      return API._hasLandmarks ? API._landmarkBuf : null;
    },

    /**
     * getVideoStatus() — returns diagnostic object for the video element.
     * Callable from Dart via JS interop.
     */
    getVideoStatus: function () {
      const video = document.getElementById(API._videoId);
      if (!video) return { found: false };
      const tracks  = video.srcObject ? video.srcObject.getVideoTracks() : [];
      const track   = tracks[0] || null;
      return {
        found:        true,
        currentTime:  video.currentTime,
        paused:       video.paused,
        ended:        video.ended,
        readyState:   video.readyState,
        videoWidth:   video.videoWidth,
        videoHeight:  video.videoHeight,
        hasSrcObject: !!video.srcObject,
        trackState:   track ? track.readyState  : 'none',
        trackEnabled: track ? track.enabled     : false,
        trackMuted:   track ? track.muted       : true,
      };
    },

    // ── Internal — video watcher ──────────────────────────────────────────────

    _startVideoWatcher: function () {
      API._stopVideoWatcher();
      let lastTime = -1;

      API._videoWatcherId = setInterval(function () {
        if (API._state !== STATE.RUNNING) return;

        const video = document.getElementById(API._videoId);
        if (!video) {
          console.warn('[NextKickCamera] watcher: video element #' + API._videoId + ' NOT FOUND in DOM');
          return;
        }

        const t      = video.currentTime;
        const tracks = video.srcObject ? video.srcObject.getVideoTracks() : [];
        const track  = tracks[0] || null;
        const tState = track ? track.readyState : 'no-track';

        if (lastTime >= 0 && t === lastTime) {
          // currentTime not advancing — video is frozen
          console.warn(
            '[NextKickCamera] currentTime FROZEN ' +
            'time=' + t +
            ' paused=' + video.paused +
            ' ended=' + video.ended +
            ' readyState=' + video.readyState +
            ' trackState=' + tState +
            ' trackEnabled=' + (track ? track.enabled : 'N/A') +
            ' trackMuted=' + (track ? track.muted : 'N/A')
          );

          // Recovery: try play() if paused and stream is still live
          if (video.paused && !video.ended && tState === 'live') {
            console.log('[NextKickCamera] Recovery: calling video.play()');
            video.play().then(function () {
              console.log('[NextKickCamera] Recovery play() resolved');
            }).catch(function (e) {
              console.error('[NextKickCamera] Recovery play() failed:', e);
            });
          } else if (tState !== 'live') {
            console.error('[NextKickCamera] Track is not live — stream may have ended. trackState=' + tState);
          }
        } else {
          console.log('[NextKickCamera] currentTime tick ' + lastTime + ' → ' + t + ' trackState=' + tState);
        }
        lastTime = t;
      }, 1000);
    },

    _stopVideoWatcher: function () {
      if (API._videoWatcherId !== null) {
        clearInterval(API._videoWatcherId);
        API._videoWatcherId = null;
      }
    },

    // ── Internal — inference ──────────────────────────────────────────────────

    _setError: function (msg) {
      console.error('[NextKickPose]', msg);
      API._state        = STATE.ERROR;
      API._errorMessage = msg;
    },

    _loadMediaPipe: async function () {
      try {
        const mod    = await import(LOCAL_VISION);
        const vision = await mod.FilesetResolver.forVisionTasks(LOCAL_WASM);
        console.log('[NextKickPose] Local MediaPipe assets loaded.');
        return { PoseLandmarker: mod.PoseLandmarker, vision, modelPath: LOCAL_MODEL };
      } catch (localErr) {
        if (!_IS_DEV_HOST) {
          throw new Error(
            'MediaPipe local assets not found. ' +
            'Run scripts/download_mediapipe.sh and rebuild. ' +
            '(' + localErr.message + ')'
          );
        }
        console.warn('[NextKickPose] Local assets missing — CDN fallback (dev only).');
      }
      const mod    = await import(CDN_VISION);
      const vision = await mod.FilesetResolver.forVisionTasks(CDN_WASM);
      console.log('[NextKickPose] CDN MediaPipe loaded (dev host).');
      return { PoseLandmarker: mod.PoseLandmarker, vision, modelPath: CDN_MODEL };
    },

    _rafLoop: function () {
      if (API._state !== STATE.RUNNING) return;
      API._rafId = requestAnimationFrame(API._rafLoop);
      if (!API._landmarker) return;
      if (API._inferenceActive) return;

      const video = document.getElementById(API._videoId);

      // First RAF execution: log full video state for diagnosis
      if (!API._firstRafLog) {
        API._firstRafLog = true;
        if (!video) {
          console.error('[NextKickCamera] _rafLoop: video element #' + API._videoId + ' NOT FOUND');
        } else {
          const tracks = video.srcObject ? video.srcObject.getVideoTracks() : [];
          const track  = tracks[0] || null;
          console.log('[NextKickCamera] _rafLoop first tick:',
            'element found, currentTime=' + video.currentTime,
            'paused=' + video.paused,
            'readyState=' + video.readyState,
            'srcObject=' + !!video.srcObject,
            'tracks=' + tracks.length,
            'trackState=' + (track ? track.readyState : 'none'),
            'videoSize=' + video.videoWidth + 'x' + video.videoHeight
          );
        }
      }

      if (!video || video.readyState < 2 || video.paused || video.ended) return;
      if (video.currentTime === API._lastVideoTime) return;
      API._lastVideoTime  = video.currentTime;
      API._inferenceActive = true;
      const t0 = performance.now();
      try {
        const result = API._landmarker.detectForVideo(video, t0);
        API._processResult(result);
        API._updateFps(t0);
      } catch (err) {
        if (!API._lastInferenceError) {
          console.warn('[NextKickPose] Inference error:', err);
          API._lastInferenceError = true;
        }
        API._hasLandmarks = false;
      } finally {
        API._inferenceActive = false;
      }
    },

    _processResult: function (result) {
      if (result && result.landmarks && result.landmarks.length > 0) {
        const lms = result.landmarks[0];
        if (lms.length === LANDMARK_COUNT) {
          const buf = API._landmarkBuf;
          for (let i = 0; i < LANDMARK_COUNT; i++) {
            const base    = i * FLOATS_PER_LM;
            buf[base]     = lms[i].x;
            buf[base + 1] = lms[i].y;
            buf[base + 2] = lms[i].z || 0;
            buf[base + 3] = lms[i].visibility != null ? lms[i].visibility : 1.0;
          }
          API._hasLandmarks      = true;
          API._lastInferenceError = false;
          return;
        }
      }
      API._hasLandmarks = false;
    },

    _updateFps: function (ts) {
      API._fpsBuffer[API._fpsBufIdx] = ts;
      API._fpsBufIdx = (API._fpsBufIdx + 1) % API._fpsBuffer.length;
      const oldest = API._fpsBuffer[API._fpsBufIdx];
      if (oldest > 0) {
        const elapsed = (ts - oldest) / 1000;
        if (elapsed > 0) API._fps = API._fpsBuffer.length / elapsed;
      }
    },
  };

  window.NextKickPoseWeb = API;
})();
