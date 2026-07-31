<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppVersion extends Model
{
    protected $table = 'app_versions';

    protected $fillable = [
        'ios_latest_version',
        'ios_store_url',
        'android_latest_version_code',
        'android_store_url',
    ];

    protected function casts(): array
    {
        return [
            'android_latest_version_code' => 'integer',
        ];
    }

    public static function current(): self
    {
        return static::query()->firstOrCreate([], [
            'ios_latest_version' => '1.0.4',
            'ios_store_url' => null,
            'android_latest_version_code' => 34,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
        ]);
    }
}
