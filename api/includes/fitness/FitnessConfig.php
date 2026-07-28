<?php

final class FitnessConfig
{
    public const TIMEZONE = 'Africa/Kigali';
    public const WEEK_START_ISO = 1; // Monday
    public const WEEK_END_ISO = 7;   // Sunday

    public const ACWR_FORMULA_VERSION = 'rolling_7_over_rolling_28_weekly_average_v1';
    public const ACWR_MIN_COMPLETE_DAYS = 28;

    public static function timezone(): DateTimeZone
    {
        return new DateTimeZone(self::TIMEZONE);
    }

    public static function today(): string
    {
        return (new DateTimeImmutable('now', self::timezone()))->format('Y-m-d');
    }

    public static function acwrThresholds(): array
    {
        return [
            'below_target_max' => 0.79,
            'in_target_max' => 1.30,
            'caution_max' => 1.50,
        ];
    }
}
