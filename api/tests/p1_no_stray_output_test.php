<?php
// Pure regression test — no DB.
//
// Found on production 2026-09-19: players.php started with 4 spaces before
// `<?php`. With output buffering off (LiteSpeed on nextkick.me) those bytes
// are sent before headers, so http_response_code() is ignored and errors
// like 401 reach the app as HTTP 200 — which silently disables the app's
// global 401 → logout handling for that endpoint. Local php -S / WAMP hide it
// because output buffering is on there.
//
// Fails if any API PHP file has bytes (whitespace or a UTF-8 BOM) before its
// opening tag.
$root = dirname(__DIR__);
$bad = [];
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
foreach ($it as $file) {
    $path = $file->getPathname();
    if (substr($path, -4) !== '.php' || str_contains($path, '.claude-flow')) continue;
    $head = (string)file_get_contents($path, false, null, 0, 64);
    $pos = strpos($head, '<?php');
    if ($pos === false) continue; // templates/partials without a PHP tag
    if ($pos > 0) $bad[] = substr($path, strlen($root) + 1) . ' → ' . json_encode(substr($head, 0, $pos));
}
if ($bad) {
    fwrite(STDERR, "p1_no_stray_output_test: FAIL\n" . implode("\n", $bad) . "\n");
    exit(1);
}
echo "p1_no_stray_output_test: OK\n";
