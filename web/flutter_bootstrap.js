{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
      .test(navigator.userAgent);

    const appRunner = await engineInitializer.initializeEngine({
      // HTML renderer: no SharedArrayBuffer / heavy WASM needed → works on all mobile browsers.
      // CanvasKit: better quality on desktop.
      renderer: isMobile ? 'html' : 'canvaskit',
    });

    await appRunner.runApp();
  },
});
