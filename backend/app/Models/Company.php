<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Company extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'name',
        'code',
        'is_active',
        'theme_enabled',
        'theme_source',
        'tagline',
        'theme_primary_color',
        'theme_accent_color',
        'theme_background_color',
        'theme_surface_color',
        'theme_ink_color',
        'theme_muted_ink_color',
        'theme_icon_color',
        'theme_mode',
        'theme_is_dark',
        'logo_url',
        'logo_file_name',
        'logo_updated_at',
        'loading_image_url',
        'loading_image_file_name',
        'loading_image_updated_at',
        'loading_video_url',
        'loading_video_file_name',
        'loading_video_updated_at',
        'leaderboard_period_start',
        'leaderboard_period_end',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'theme_enabled' => 'boolean',
            'theme_is_dark' => 'boolean',
            'logo_updated_at' => 'datetime',
            'loading_image_updated_at' => 'datetime',
            'loading_video_updated_at' => 'datetime',
            'leaderboard_period_start' => 'date',
            'leaderboard_period_end' => 'date',
        ];
    }
}
