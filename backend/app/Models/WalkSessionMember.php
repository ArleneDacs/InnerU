<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WalkSessionMember extends Model
{
    protected $table = 'walk_session_members';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id',
        'walk_session_id',
        'user_id',
        'username',
        'status',
        'is_tracking',
        'step_count',
        'distance_meters',
        'elapsed_seconds',
        'route_points',
        'current_location_lat',
        'current_location_lng',
    ];

    protected function casts(): array
    {
        return [
            'is_tracking' => 'boolean',
            'step_count' => 'integer',
            'distance_meters' => 'decimal:2',
            'elapsed_seconds' => 'integer',
            'route_points' => 'array',
            'current_location_lat' => 'decimal:7',
            'current_location_lng' => 'decimal:7',
        ];
    }
}
