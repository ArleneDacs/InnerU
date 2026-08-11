<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppVersion extends Model
{
    protected $table = 'app_versions';

    protected $fillable = [
        'ios_latest_version',
        'ios_store_url',
        'ios_update_required',
        'android_latest_version_code',
        'android_store_url',
        'android_update_required',
    ];

    protected function casts(): array
    {
        return [
            'android_latest_version_code' => 'integer',
            'ios_update_required' => 'boolean',
            'android_update_required' => 'boolean',
        ];
    }

    public static function current(): self
    {
        return static::query()->firstOrCreate([], [
            'ios_latest_version' => '1.0.4',
            'ios_store_url' => null,
            // Keep the pre-flag behaviour for any row created by the model:
            // an administrator must explicitly opt a release into the
            // dismissible update path.
            'ios_update_required' => true,
            'android_latest_version_code' => 34,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            'android_update_required' => true,
        ]);
    }
}
