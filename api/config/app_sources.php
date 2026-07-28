<?php
/**
 * Canonical registry of allowed source_app values.
 * All app writes must declare one of these identifiers.
 * 'legacy' covers existing rows that predate multi-app tracking.
 */
return [
    'nextkick_mobile' => [
        'label'  => 'NextKick Mobile',
        'active' => true,
    ],
    'nextkick_web_pose' => [
        'label'  => 'NextKick Web Pose',
        'active' => true,
    ],
    'academy_app' => [
        'label'  => 'Academy App',
        'active' => true,
    ],
    'legacy' => [
        'label'  => 'Legacy Data',
        'active' => true,
    ],
];
