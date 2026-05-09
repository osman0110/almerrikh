<?php
// Optional manual setup check:
// http://localhost/smart-sport-scribe-main/api/setup.php
header('Content-Type: text/html; charset=utf-8');

require_once 'db.php';

echo '<h2>Database setup complete</h2>';
echo '<p>Database <b>smart_sport</b> is ready.</p>';
echo '<p>Tables: users (email + phone), user_tokens, user_profiles.</p>';
