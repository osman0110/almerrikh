<?php
/**
 * Assessment type normalization.
 * Raw type strings from any app are mapped to canonical normalized_type values.
 * The original raw type is always preserved in the `type` column.
 */

const NK_NORMALIZED_TYPES = [
    'squat',
    'jump_landing',
    'single_leg_balance',
    'countermovement_jump',
    'drop_jump',
    'single_leg_drop_jump',
    'mobility',
    'wellness',
    'other',
];

const NK_ASSESSMENT_TYPE_MAP = [
    // squat
    'squat'                    => 'squat',
    'squattest'                => 'squat',
    'squat test'               => 'squat',
    'squatassessment'          => 'squat',
    'squat assessment'         => 'squat',
    // jump_landing
    'jumplanding'              => 'jump_landing',
    'jump_landing'             => 'jump_landing',
    'jump landing'             => 'jump_landing',
    'jumplandingassessment'    => 'jump_landing',
    'jump landing assessment'  => 'jump_landing',
    // single_leg_balance
    'singlelegbalance'         => 'single_leg_balance',
    'single_leg_balance'       => 'single_leg_balance',
    'single leg balance'       => 'single_leg_balance',
    'singlelegbalanceassessment' => 'single_leg_balance',
    'single leg balance assessment' => 'single_leg_balance',
    // countermovement_jump
    'cmj'                      => 'countermovement_jump',
    'countermovementjump'      => 'countermovement_jump',
    'countermovement_jump'     => 'countermovement_jump',
    'countermovement jump'     => 'countermovement_jump',
    // drop_jump
    'dj'                       => 'drop_jump',
    'dropjump'                 => 'drop_jump',
    'drop_jump'                => 'drop_jump',
    'drop jump'                => 'drop_jump',
    // single_leg_drop_jump
    'sldj'                     => 'single_leg_drop_jump',
    'singlelegdropjump'        => 'single_leg_drop_jump',
    'single_leg_drop_jump'     => 'single_leg_drop_jump',
    'single leg drop jump'     => 'single_leg_drop_jump',
    // mobility
    'mobility'                 => 'mobility',
    'mobility assessment'      => 'mobility',
    // wellness
    'wellness'                 => 'wellness',
    // other
    'other'                    => 'other',
];

/**
 * Maps any raw assessment type string to its canonical normalized_type.
 * Strips spaces/underscores for fuzzy matching.
 *
 * @param  string $rawType  Value as sent by the client app
 * @return string           Canonical normalized_type (lowercase snake_case)
 */
function nk_normalize_assessment_type(string $rawType): string
{
    $key = strtolower(trim($rawType));

    if (isset(NK_ASSESSMENT_TYPE_MAP[$key])) {
        return NK_ASSESSMENT_TYPE_MAP[$key];
    }

    // Fallback: strip all non-alpha chars and retry
    $stripped = preg_replace('/[^a-z]/', '', $key);
    foreach (NK_ASSESSMENT_TYPE_MAP as $mapKey => $value) {
        if (preg_replace('/[^a-z]/', '', $mapKey) === $stripped) {
            return $value;
        }
    }

    return 'other';
}

/**
 * Returns a human-readable label for a normalized_type.
 */
function nk_assessment_type_label(string $normalizedType): string
{
    $labels = [
        'squat'                => 'Squat Assessment',
        'jump_landing'         => 'Jump Landing',
        'single_leg_balance'   => 'Single Leg Balance',
        'countermovement_jump' => 'Countermovement Jump (CMJ)',
        'drop_jump'            => 'Drop Jump',
        'single_leg_drop_jump' => 'Single Leg Drop Jump',
        'mobility'             => 'Mobility',
        'wellness'             => 'Wellness',
        'other'                => 'Other',
    ];
    return $labels[$normalizedType] ?? ucwords(str_replace('_', ' ', $normalizedType));
}
