<?php
/**
 * api/mobile/auth.php
 *
 * Production-facing auth endpoint called by the Flutter app.
 * Flutter kApiBase = https://nextkick.me/api/mobile
 *
 * This file is a thin delegate: all logic lives in api/auth.php.
 * Using __DIR__ ensures the include resolves correctly regardless of
 * the HTTP server's working directory.
 */
require_once __DIR__ . '/../auth.php';
